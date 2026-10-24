package kg.crosslink.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * A reboot or an app update ends the process and so the link; this brings it back without opening
 * the app, unless the user had switched it off. Android lets an app start its foreground service
 * from these two broadcasts.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> LinkController.get(context).resume()
        }
    }
}
