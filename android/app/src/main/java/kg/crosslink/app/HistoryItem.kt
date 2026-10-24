package kg.crosslink.app

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.concurrent.atomic.AtomicLong

/**
 * One line of the history: a text, a clipboard or a file that went to or came from the Mac.
 * Kept in memory only: clipboard content may be a password and should not land on disk.
 * Fields that change during a transfer are Compose state, so only that row redraws.
 */
class HistoryItem(
    val incoming: Boolean,
    val kind: Kind,
    /** The text itself or the file name. */
    val title: String,
    val size: Long = -1,
    val mime: String = "",
) {
    enum class Kind { TEXT, CLIPBOARD, FILE }
    enum class State { ACTIVE, DONE, FAILED }

    val key = counter.incrementAndGet()
    val time = System.currentTimeMillis()
    var state by mutableStateOf(if (kind == Kind.FILE) State.ACTIVE else State.DONE)
    /** 0..1 while a file is moving. */
    var progress by mutableFloatStateOf(0f)
    /** Where a received file was saved, to open it. */
    var uri by mutableStateOf<Uri?>(null)

    val isLink: Boolean get() = kind != Kind.FILE && LINK.matches(title.trim())
    val isImage: Boolean get() = mime.startsWith("image/")

    private companion object {
        val counter = AtomicLong()
        val LINK = Regex("""https?://\S+""")
    }
}
