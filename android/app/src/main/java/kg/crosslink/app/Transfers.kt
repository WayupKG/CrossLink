package kg.crosslink.app

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.provider.MediaStore
import android.provider.OpenableColumns
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/** File transfer limits shared by both directions (see PROTOCOL.md, "Files"). */
object Transfers {
    /** Raw bytes per file_chunk: base64 makes it 256 KiB, well inside a 512 KiB frame. */
    const val CHUNK = 192 * 1024
    const val MAX_SIZE = 4L * 1024 * 1024 * 1024
    const val MAX_INCOMING = 4

    /** The name as the receiver will save it: no folders, control characters or hidden-file dot. */
    fun safeName(raw: String): String {
        val base = raw.substringAfterLast('/').substringAfterLast('\\')
            .filter { it >= ' ' && it != ':' }.trim().trimStart('.')
        if (base.isEmpty()) return "file"
        if (base.length <= 120) return base
        val dot = base.lastIndexOf('.')
        val ext = if (dot > 0 && base.length - dot <= 16) base.substring(dot) else ""
        return base.take(120 - ext.length) + ext
    }

    fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
}

/** A file picked on the phone. The stream is opened while the picker's read grant is still alive. */
class OutgoingFile(val name: String, val size: Long, val mime: String, val input: InputStream) {
    companion object {
        fun open(context: Context, uris: List<Uri>): List<OutgoingFile> = uris.mapNotNull { uri ->
            try {
                val resolver = context.contentResolver
                var name: String? = null
                var size = -1L
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use {
                    if (it.moveToFirst()) {
                        name = it.getString(0)
                        if (!it.isNull(1)) size = it.getLong(1)
                    }
                }
                val input = resolver.openInputStream(uri) ?: return@mapNotNull null
                OutgoingFile(Transfers.safeName(name ?: uri.lastPathSegment ?: "file"), size,
                    resolver.getType(uri) ?: "application/octet-stream", input)
            } catch (_: Exception) { null }
        }
    }
}

/**
 * A file arriving from the Mac, written straight into the shared collection as a pending item:
 * photos to Pictures/CrossLink, videos to Movies/CrossLink, the rest to Download/CrossLink.
 * Other apps see it only after [publish]; [abort] removes the partial file.
 */
class IncomingFile(context: Context, val name: String, val size: Long, val mime: String) {
    private val resolver = context.contentResolver
    val uri: Uri
    private val out: OutputStream
    private val digest = MessageDigest.getInstance("SHA-256")
    var received = 0L
        private set

    init {
        val target = when {
            mime.startsWith("image/") -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI to "Pictures/CrossLink"
            mime.startsWith("video/") -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI to "Movies/CrossLink"
            else -> null
        }
        uri = target?.let { insert(it.first, it.second) }
            // A media collection refuses types it does not know; Downloads takes anything
            ?: insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, "Download/CrossLink")
            ?: throw IOException("Cannot create file")
        out = try {
            resolver.openOutputStream(uri) ?: throw IOException("Cannot open file")
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    private fun insert(collection: Uri, folder: String): Uri? = try {
        resolver.insert(collection, ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        })
    } catch (_: IllegalArgumentException) { null }

    fun write(data: ByteArray) {
        if (received + data.size > (if (size >= 0) size else Transfers.MAX_SIZE)) throw IOException("File is larger than announced")
        out.write(data)
        digest.update(data)
        received += data.size
    }

    /** True when the content matches what the sender hashed; the file then becomes visible. */
    fun publish(sha256: String): Boolean {
        out.close()
        if ((size >= 0 && received != size) || !Transfers.hex(digest.digest()).equals(sha256, ignoreCase = true)) {
            resolver.delete(uri, null, null)
            return false
        }
        resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        return true
    }

    fun abort() {
        try { out.close() } catch (_: Exception) { }
        try { resolver.delete(uri, null, null) } catch (_: Exception) { }
    }
}
