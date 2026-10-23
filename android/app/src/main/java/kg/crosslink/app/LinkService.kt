package kg.crosslink.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder

/**
 * Foreground service that keeps the process (and LinkController's socket) alive while the
 * user is in other apps, so the "send to Mac" menu entries work. It holds no state itself.
 */
class LinkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Соединение с Mac", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_crosslink)
            .setContentTitle("CrossLink")
            .setContentText("Поддерживает связь с Mac")
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        // The socket does not survive a killed process, so there is nothing to restart.
        return START_NOT_STICKY
    }

    companion object {
        private const val CHANNEL = "link"

        /** Must be called while the app is in the foreground (Android forbids it from the background). */
        fun start(context: Context) {
            try { context.startForegroundService(Intent(context, LinkService::class.java)) }
            catch (_: Exception) { /* Keep the connection; it just may not outlive the screen */ }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, LinkService::class.java))
        }
    }
}
