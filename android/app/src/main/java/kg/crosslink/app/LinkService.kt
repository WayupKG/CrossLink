package kg.crosslink.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.IBinder

/**
 * Foreground service that keeps the process (and LinkController's socket) alive while the
 * user is in other apps, so the "send to Mac" menu entries work. It holds no state itself.
 */
class LinkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(ONGOING_ID, ongoing(this, null), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        // The socket does not survive a killed process, so there is nothing to restart.
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL = "link"
        private const val FILES_CHANNEL = "files"
        private const val ONGOING_ID = 1
        /** --brand of the design tokens (ui/Theme.kt); some shades draw the icon on it. */
        private const val BRAND = 0xFF3552F5.toInt()

        /** Must be called while the app is in the foreground (Android forbids it from the background). */
        fun start(context: Context) {
            try { context.startForegroundService(Intent(context, LinkService::class.java)) }
            catch (_: Exception) { /* Keep the connection; it just may not outlive the screen */ }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }

        /** Shows an upload in the connection notification; null brings the usual text back. */
        fun progress(context: Context, text: String?) {
            val manager = context.getSystemService(NotificationManager::class.java)
            // Only while the service shows its notification; otherwise this would post a stray one
            if (manager.activeNotifications.none { it.id == ONGOING_ID }) return
            manager.notify(ONGOING_ID, ongoing(context, text))
        }

        /** A file from the Mac is saved: tapping the notification opens it. */
        fun fileReceived(context: Context, name: String, uri: Uri, mime: String) {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(FILES_CHANNEL, "Файлы с Mac", NotificationManager.IMPORTANCE_DEFAULT))
            val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            val notification = Notification.Builder(context, FILES_CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_crosslink)
                .setColor(BRAND)
                .setContentTitle("Файл с Mac")
                .setContentText(name)
                .setContentIntent(PendingIntent.getActivity(context, uri.hashCode(), view,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
                .setAutoCancel(true)
                .build()
            manager.notify(uri.toString(), 2, notification)
        }

        private fun ongoing(context: Context, text: String?): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Соединение с Mac", NotificationManager.IMPORTANCE_LOW))
            val open = PendingIntent.getActivity(context, 0,
                Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
            // A tap sends the clipboard: one touch from any app, without expanding the notification.
            // Android lets only the app on screen read the clipboard, so it opens an invisible one.
            val sendClipboard = PendingIntent.getActivity(context, 1,
                SendToMacActivity.clipboardIntent(context), PendingIntent.FLAG_IMMUTABLE)
            return Notification.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_crosslink)
                .setColor(BRAND)
                .setContentTitle("CrossLink · связь с Mac")
                .setContentText(text ?: "Нажмите, чтобы отправить буфер на Mac")
                .setContentIntent(sendClipboard)
                .addAction(Notification.Action.Builder(
                    Icon.createWithResource(context, R.drawable.ic_stat_crosslink), "Открыть CrossLink", open).build())
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .build()
        }
    }
}
