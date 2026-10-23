package kg.crosslink.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.security.GeneralSecurityException
import java.security.SecureRandom
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * LAN-only encrypted client. No third-party server, accounts or analytics.
 * One instance per process, shared by the main screen and the "send to Mac" menu entries;
 * LinkService keeps the process alive while the link is wanted. A lost link is retried with
 * growing pauses until the user disconnects or the Mac says "bye".
 */
class LinkController private constructor(private val context: Context) {
    companion object {
        @Volatile private var instance: LinkController? = null

        fun get(context: Context): LinkController = instance ?: synchronized(this) {
            instance ?: LinkController(context.applicationContext).also { instance = it }
        }

        private const val FIRST_RETRY_MS = 1_000L
        private const val MAX_RETRY_MS = 30_000L
        private const val PING_SECONDS = 20L
        /** The Mac answers every ping, so this much silence means the link is dead. */
        private const val READ_TIMEOUT_MS = 45_000
    }

    var status by mutableStateOf("Нет подключения")
        private set
    var connected by mutableStateOf(false)
        private set
    /** The link was lost and is being retried in the background; the user can stop it. */
    var reconnecting by mutableStateOf(false)
        private set
    var receivedText by mutableStateOf("")
        private set
    var draft by mutableStateOf("")
    var pairCode by mutableStateOf("")
    private val ui = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val sender = Executors.newSingleThreadExecutor()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val epoch = AtomicInteger(0)
    private val writeLock = Any()
    @Volatile private var socket: Socket? = null
    @Volatile private var session: Session? = null
    /** Pairing code to stay connected to; null once the user or the Mac ended the link. */
    @Volatile private var wanted: String? = null
    @Volatile private var retryDelayMs = FIRST_RETRY_MS
    @Volatile private var pinger: ScheduledFuture<*>? = null
    private val maxFrame = 512 * 1024
    private val random = SecureRandom()
    private var restored = false

    private class Session(
        val out: DataOutputStream,
        val inboundKey: SecretKeySpec,
        val outboundKey: SecretKeySpec,
        var outgoingSeq: Int = 0,
        var incomingSeq: Int = 0
    )

    private class PairCode(val host: String, val port: Int, val secret: ByteArray)

    /** The Mac answered with another key: it was re-paired, so retrying cannot help. */
    private class AuthFailed : IOException("Pairing key rejected")

    private fun isPrivateIPv4(host: String): Boolean {
        val segments = host.split(".")
        if (segments.size != 4) return false
        val octets = segments.map { it.toIntOrNull() ?: return false }
        if (octets.any { it !in 0..255 }) return false
        return octets[0] == 10 || (octets[0] == 172 && octets[1] in 16..31) ||
            (octets[0] == 192 && octets[1] == 168) ||
            (octets[0] == 169 && octets[1] == 254)
    }

    private fun parse(raw: String): PairCode? {
        val uri = try { Uri.parse(raw.trim()) } catch (_: Exception) { null } ?: return null
        if (uri.scheme != "crosslink" || uri.host != "pair") return null
        val host = uri.getQueryParameter("host")
        val port = uri.getQueryParameter("port")?.toIntOrNull()
        val secret = try {
            Base64.decode(uri.getQueryParameter("key") ?: "", Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        } catch (_: Exception) { null }
        if (host.isNullOrBlank() || !isPrivateIPv4(host) || port == null || port !in 1..65535 || secret?.size != 32) return null
        return PairCode(host, port, secret)
    }

    /** Reconnects with the saved pairing once per process, so a recreated screen keeps the live connection. */
    fun restorePairing() {
        if (restored) return
        restored = true
        val saved = SavedPairing(context).load() ?: return
        pairCode = saved
        connect(saved, save = false)
    }

    fun connect(raw: String, save: Boolean = true) {
        val code = parse(raw) ?: run { status = "Неверный код сопряжения"; return }
        wanted = raw.trim()
        retryDelayMs = FIRST_RETRY_MS
        reconnecting = false
        LinkService.start(context)
        open(code, save)
    }

    /** Starts a new connection attempt, abandoning the previous one. */
    private fun open(code: PairCode, save: Boolean) {
        val id = epoch.incrementAndGet()
        stopPinging()
        socket?.closeQuietly()
        socket = null
        session = null
        update(id) { connected = false; status = "Подключение к Mac…" }
        executor.execute { run(id, code, save) }
    }

    private fun retry(id: Int) {
        if (epoch.get() != id) return
        val code = wanted?.let(::parse) ?: return
        open(code, save = false)
    }

    private fun run(id: Int, code: PairCode, save: Boolean) {
        var current: Socket? = null
        var discovered = false
        try {
            val reached = reach(id, code)
            current = reached.first
            discovered = reached.second
            if (epoch.get() != id) return
            socket = current
            current.soTimeout = 15000
            val input = DataInputStream(current.getInputStream())
            val output = DataOutputStream(current.getOutputStream())
            val clientNonce = ByteArray(32).also(random::nextBytes)
            writeRaw(output, JSONObject()
                .put("type", "hello").put("version", 1)
                .put("nonce", Base64.encodeToString(clientNonce, Base64.NO_WRAP))
                .toString().toByteArray(Charsets.UTF_8))
            val hello = JSONObject(String(readRaw(input), Charsets.UTF_8))
            if (hello.optString("type") != "hello_ack" || hello.optInt("version") != 1)
                throw IOException("Bad handshake")
            val serverNonce = Base64.decode(hello.getString("nonce"), Base64.DEFAULT)
            if (serverNonce.size != 32) throw IOException("Invalid server nonce")
            val salt = clientNonce + serverNonce
            val inbound = hkdf(code.secret, salt, "crosslink/v1/mac-to-android")
            val outbound = hkdf(code.secret, salt, "crosslink/v1/android-to-mac")
            val currentSession = Session(output, inbound, outbound)
            session = currentSession
            val ready = try { decode(readRaw(input), currentSession) }
                catch (_: GeneralSecurityException) { throw AuthFailed() }
            if (ready.optString("type") != "ready") throw IOException("Authentication failed")
            sendEncrypted(currentSession, "ready_ack", "")
            current.soTimeout = READ_TIMEOUT_MS
            if (discovered) rememberAddress(current.inetAddress.hostAddress ?: code.host, current.port)
            if (save) { try { SavedPairing(context).save(raw()) } catch (_: Exception) { /* Keep working without persistence */ } }
            retryDelayMs = FIRST_RETRY_MS
            startPinging(currentSession, current)
            update(id) { connected = true; reconnecting = false; status = "Подключено к Mac · зашифровано" }
            while (epoch.get() == id) {
                val message = decode(readRaw(input), currentSession)
                val text = message.optString("text", "").take(20000)
                when (message.optString("type")) {
                    "text" -> update(id) { receivedText = text }
                    "clipboard" -> update(id) {
                        receivedText = text
                        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                            .setPrimaryClip(ClipData.newPlainText("CrossLink", text))
                    }
                    "ping" -> sendEncrypted(currentSession, "pong", "")
                    "pong" -> Unit
                    "bye" -> {
                        wanted = null
                        update(id) { status = "Mac завершил соединение" }
                        return
                    }
                    else -> throw IOException("Unsupported event")
                }
            }
        } catch (e: Exception) {
            // Log.w, not Log.i: vivo firmware drops Log.i of third-party apps. No payload or key here.
            Log.w("CrossLink", "Connection lost: $e")
            if (epoch.get() != id) return
            // A Bonjour answer can be spoofed, so a wrong key there is just another failed attempt
            if (e is AuthFailed && !discovered) {
                wanted = null
                update(id) { status = "Mac не принял ключ: сопряжение сброшено на Mac. Отсканируйте QR заново." }
            } else if (wanted != null) {
                val delay = retryDelayMs
                retryDelayMs = (delay * 2).coerceAtMost(MAX_RETRY_MS)
                update(id) { reconnecting = true; status = "Нет связи с Mac. Повтор через ${delay / 1000} с…" }
                scheduler.schedule({ retry(id) }, delay, TimeUnit.MILLISECONDS)
            }
        } finally {
            current?.closeQuietly()
            if (epoch.get() == id) {
                stopPinging()
                session = null
                socket = null
                if (wanted == null) {
                    LinkService.stop(context)
                    update(id) { reconnecting = false }
                }
                update(id) { connected = false }
            }
        }
    }

    /**
     * Connects to the address from the QR code or, if the Mac is not there, looks it up via Bonjour
     * (DHCP gave it another IP). The second value tells whether the address came from Bonjour.
     */
    private fun reach(id: Int, code: PairCode): Pair<Socket, Boolean> {
        try {
            return socketTo(code.host, code.port, 3000) to false
        } catch (direct: IOException) {
            update(id) { status = "Ищу Mac в сети…" }
            val found = MacFinder(context).find(discoveryId(code.secret)) ?: throw direct
            val host = found.address.hostAddress ?: throw direct
            if (!isPrivateIPv4(host) || (host == code.host && found.port == code.port)) throw direct
            return socketTo(host, found.port, 5000) to true
        }
    }

    private fun socketTo(host: String, port: Int, timeoutMs: Int): Socket {
        val s = Socket()
        try {
            s.tcpNoDelay = true
            s.connect(InetSocketAddress(host, port), timeoutMs)
            return s
        } catch (e: IOException) {
            s.closeQuietly()
            throw e
        }
    }

    /** The Mac moved to another IP: keep the new address so the next start connects directly. */
    private fun rememberAddress(host: String, port: Int) {
        val old = wanted?.let(Uri::parse) ?: return
        val updated = old.buildUpon().clearQuery()
            .appendQueryParameter("host", host)
            .appendQueryParameter("port", port.toString())
            .appendQueryParameter("key", old.getQueryParameter("key"))
            .build().toString()
        wanted = updated
        ui.post { pairCode = updated }
        try {
            val saved = SavedPairing(context)
            if (saved.load() != null) saved.save(updated)
        } catch (_: Exception) { /* The QR address still works as a start point */ }
    }

    private fun raw(): String = wanted.orEmpty()

    /** Same tag as Pairing.discoveryID on the Mac (see PROTOCOL.md). */
    private fun discoveryId(secret: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return mac.doFinal("crosslink/v1/discovery".toByteArray(Charsets.UTF_8))
            .take(8).joinToString("") { "%02x".format(it) }
    }

    private fun startPinging(current: Session, socket: Socket) {
        pinger = scheduler.scheduleWithFixedDelay({
            try { sendEncrypted(current, "ping", "") } catch (_: Exception) { socket.closeQuietly() }
        }, PING_SECONDS, PING_SECONDS, TimeUnit.SECONDS)
    }

    private fun stopPinging() {
        pinger?.cancel(false)
        pinger = null
    }

    fun disconnect() {
        wanted = null
        epoch.incrementAndGet()
        stopPinging()
        socket?.closeQuietly()
        socket = null
        session = null
        connected = false
        reconnecting = false
        status = "Отключено"
        LinkService.stop(context)
    }

    fun forgetPairing() {
        disconnect()
        SavedPairing(context).clear()
        pairCode = ""
        status = "Сопряжение удалено с Android"
    }

    /** Queues the text for the Mac; false (with the reason in [status]) when it cannot be sent. */
    fun sendMessage(text: String, asClipboard: Boolean = false): Boolean {
        if (text.isBlank()) return false
        if (text.toByteArray(Charsets.UTF_8).size > 20000) {
            status = "Слишком большой текст (максимум 20 КБ)"
            return false
        }
        val current = session ?: run { status = "Сначала подключитесь к Mac"; return false }
        sender.execute {
            try { sendEncrypted(current, if (asClipboard) "clipboard" else "text", text) }
            catch (_: Exception) { ui.post { status = "Ошибка отправки" } }
        }
        return true
    }

    fun sendClipboard() {
        val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
        if (text.isEmpty()) status = "Буфер обмена пуст или недоступен"
        else sendMessage(text, asClipboard = true)
    }

    private fun update(id: Int, block: () -> Unit) {
        ui.post { if (epoch.get() == id) block() }
    }

    private fun readRaw(input: DataInputStream): ByteArray {
        val length = input.readInt()
        if (length <= 0 || length > maxFrame) throw IOException("Invalid frame size")
        return ByteArray(length).also { input.readFully(it) }
    }

    private fun writeRaw(out: DataOutputStream, data: ByteArray) {
        if (data.isEmpty() || data.size > maxFrame) throw IOException("Invalid frame size")
        out.writeInt(data.size)
        out.write(data)
        out.flush()
    }

    private fun decode(blob: ByteArray, current: Session): JSONObject {
        if (blob.size < 28) throw IOException("Invalid sealed message")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, current.inboundKey, GCMParameterSpec(128, blob.copyOfRange(0, 12)))
        val plain = cipher.doFinal(blob, 12, blob.size - 12)
        val parsed = JSONObject(String(plain, Charsets.UTF_8))
        if (parsed.getInt("seq") != current.incomingSeq + 1) throw IOException("Invalid sequence")
        current.incomingSeq += 1
        return parsed
    }

    private fun sendEncrypted(current: Session, type: String, text: String) {
        synchronized(writeLock) {
            if (session !== current) return
            val next = current.outgoingSeq + 1
            val plain = JSONObject().put("type", type).put("seq", next).put("text", text)
                .toString().toByteArray(Charsets.UTF_8)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, current.outboundKey)
            val frame = cipher.iv + cipher.doFinal(plain)
            writeRaw(current.out, frame)
            current.outgoingSeq = next
        }
    }

    private fun hkdf(key: ByteArray, salt: ByteArray, label: String): SecretKeySpec {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(salt, "HmacSHA256"))
        val prk = mac.doFinal(key)
        mac.init(SecretKeySpec(prk, "HmacSHA256"))
        val okm = mac.doFinal(label.toByteArray(Charsets.UTF_8) + byteArrayOf(1))
        return SecretKeySpec(okm.copyOf(32), "AES")
    }

    private fun Socket.closeQuietly() = try { close() } catch (_: Exception) { }
}
