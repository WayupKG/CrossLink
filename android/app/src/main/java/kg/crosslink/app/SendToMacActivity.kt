package kg.crosslink.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.core.content.IntentCompat

/**
 * Invisible target of the text selection menu and the share sheet: puts the text into the Mac
 * clipboard, or starts sending shared photos and files, over the open connection and closes at once.
 * Android does not let a background app read the clipboard, so this is how text copied on the phone
 * reaches the Mac; the notification button and the Quick Settings tile open it with
 * [ACTION_SEND_CLIPBOARD] to read the clipboard while it is on top.
 */
class SendToMacActivity : Activity() {
    companion object {
        const val ACTION_SEND_CLIPBOARD = "kg.crosslink.app.SEND_CLIPBOARD"
        /** Gives up when the window never gets focus, so the invisible window does not block the screen. */
        private const val FOCUS_WAIT_MS = 2_000L

        fun clipboardIntent(context: Context): Intent = Intent(context, SendToMacActivity::class.java)
            .setAction(ACTION_SEND_CLIPBOARD)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    private val readsClipboard get() = intent?.action == ACTION_SEND_CLIPBOARD

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (readsClipboard) {
            // Android 10+ gives the clipboard only to the focused window, see onWindowFocusChanged
            window.decorView.postDelayed({ if (!isFinishing) done("Не удалось прочитать буфер") }, FOCUS_WAIT_MS)
            return
        }
        val link = LinkController.get(this)
        val streams = sharedStreams()
        done(if (streams.isNotEmpty()) {
            // Open the streams now: the read grant of the sharing app ends with this activity
            val files = OutgoingFile.open(this, streams)
            when {
                files.isEmpty() -> "Не удалось открыть файл"
                link.sendFiles(files) -> if (files.size == 1) "Отправляю на Mac: ${files[0].name}"
                    else "Отправляю на Mac: ${files.size} файлов"
                else -> link.status
            }
        } else {
            val text = when (intent?.action) {
                Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
                Intent.ACTION_SEND -> intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
                else -> null
            }?.toString().orEmpty()
            when {
                text.isBlank() -> "Нет текста для отправки"
                link.sendMessage(text, asClipboard = true) -> "Отправлено в буфер Mac"
                else -> link.status
            }
        })
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || !readsClipboard || isFinishing) return
        val link = LinkController.get(this)
        done(if (link.sendClipboard()) "Буфер отправлен на Mac" else link.status)
    }

    private fun done(message: String) {
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
        finish()
    }

    private fun sharedStreams(): List<Uri> = when (intent?.action) {
        Intent.ACTION_SEND -> listOfNotNull(IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java))
        Intent.ACTION_SEND_MULTIPLE ->
            IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        else -> emptyList()
    }
}
