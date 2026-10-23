package kg.crosslink.app

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/**
 * Finds the paired Mac on the LAN by its Bonjour service, for when its IP has changed since the QR
 * scan. The Mac publishes a TXT "id" derived from the pairing secret, so other Macs are skipped.
 * Blocking: call it off the main thread.
 */
class MacFinder(context: Context) {
    private val nsd = context.getSystemService(NsdManager::class.java)

    fun find(id: String, timeoutMs: Long = 4000): InetSocketAddress? {
        val found = LinkedBlockingQueue<NsdServiceInfo>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(info: NsdServiceInfo) { found.offer(info) }
            override fun onServiceLost(info: NsdServiceInfo) = Unit
            override fun onDiscoveryStarted(type: String) = Unit
            override fun onDiscoveryStopped(type: String) = Unit
            override fun onStartDiscoveryFailed(type: String, code: Int) = Unit
            override fun onStopDiscoveryFailed(type: String, code: Int) = Unit
        }
        val deadline = System.currentTimeMillis() + timeoutMs
        nsd.discoverServices(TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        try {
            while (true) {
                val left = deadline - System.currentTimeMillis()
                if (left <= 0) return null
                val info = found.poll(left, TimeUnit.MILLISECONDS) ?: return null
                // Resolves run one at a time: NsdManager rejects a second concurrent resolve
                val resolved = resolve(info, deadline) ?: continue
                val txtId = resolved.attributes["id"]?.toString(Charsets.UTF_8)
                val host = ipv4Of(resolved)
                if (txtId == id && host != null) return InetSocketAddress(host, resolved.port)
            }
        } finally {
            try { nsd.stopServiceDiscovery(listener) } catch (_: Exception) { }
        }
    }

    @Suppress("DEPRECATION") // the callback API replacing resolveService exists only on Android 14+
    private fun resolve(info: NsdServiceInfo, deadline: Long): NsdServiceInfo? {
        val result = AtomicReference<NsdServiceInfo?>()
        val done = CountDownLatch(1)
        nsd.resolveService(info, object : NsdManager.ResolveListener {
            override fun onServiceResolved(resolved: NsdServiceInfo) { result.set(resolved); done.countDown() }
            override fun onResolveFailed(info: NsdServiceInfo, code: Int) { done.countDown() }
        })
        done.await((deadline - System.currentTimeMillis()).coerceAtLeast(0), TimeUnit.MILLISECONDS)
        return result.get()
    }

    @Suppress("DEPRECATION")
    private fun ipv4Of(info: NsdServiceInfo): InetAddress? {
        val addresses = if (Build.VERSION.SDK_INT >= 34) info.hostAddresses else listOfNotNull(info.host)
        return addresses.firstOrNull { it is Inet4Address }
    }

    companion object {
        const val TYPE = "_crosslink._tcp"
    }
}
