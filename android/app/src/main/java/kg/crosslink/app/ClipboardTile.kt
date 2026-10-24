package kg.crosslink.app

import android.app.PendingIntent
import android.app.StatusBarManager
import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Quick Settings tile "Буфер → Mac": copy something on the phone, pull down the shade, tap.
 * Like the notification button, it opens the invisible SendToMacActivity, the only way an app may
 * read the clipboard on Android 10+.
 */
class ClipboardTile : TileService() {
    companion object {
        private const val PREFS = "tile"
        private const val ADDED = "added"

        /** Whether the tile is in the shade, so the app stops offering to add it. */
        fun isAdded(context: Context) = context.getSharedPreferences(PREFS, MODE_PRIVATE).getBoolean(ADDED, false)

        private fun setAdded(context: Context, added: Boolean) =
            context.getSharedPreferences(PREFS, MODE_PRIVATE).edit().putBoolean(ADDED, added).apply()

        /**
         * Android 13+ asks in a system dialog. [done] gets true once the tile is there, false when the
         * user declined, null when the system cannot ask (some firmwares), then it is added by hand.
         */
        @RequiresApi(33)
        fun requestAdd(context: Context, done: (Boolean?) -> Unit) {
            context.getSystemService(StatusBarManager::class.java).requestAddTileService(
                ComponentName(context, ClipboardTile::class.java), "Буфер → Mac",
                Icon.createWithResource(context, R.drawable.ic_tile_clipboard), context.mainExecutor,
            ) { result ->
                when (result) {
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED,
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED -> {
                        setAdded(context, true)
                        done(true)
                    }
                    StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_NOT_ADDED -> done(false)
                    else -> done(null)
                }
            }
        }
    }

    override fun onTileAdded() = setAdded(this, true)

    override fun onTileRemoved() = setAdded(this, false)

    override fun onStartListening() {
        val tile = qsTile ?: return
        // A tap with no connection still opens the activity, which says why nothing was sent
        tile.state = Tile.STATE_INACTIVE
        tile.subtitle = if (LinkController.get(this).connected) "Подключено" else "Нет связи"
        tile.updateTile()
    }

    override fun onClick() {
        val intent = SendToMacActivity.clipboardIntent(this)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }
}
