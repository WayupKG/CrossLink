package kg.crosslink.app

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/**
 * Invisible target of the text selection menu and the share sheet: puts the text into the Mac
 * clipboard over the open connection and closes at once. Android does not let a background app
 * read the clipboard, so this is how text copied on the phone reaches the Mac.
 */
class SendToMacActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = when (intent?.action) {
            Intent.ACTION_PROCESS_TEXT -> intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT)
            Intent.ACTION_SEND -> intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
            else -> null
        }?.toString().orEmpty()
        val link = LinkController.get(this)
        val message = when {
            text.isBlank() -> "Нет текста для отправки"
            link.sendMessage(text, asClipboard = true) -> "Отправлено в буфер Mac"
            else -> link.status
        }
        Toast.makeText(applicationContext, message, Toast.LENGTH_SHORT).show()
        finish()
    }
}
