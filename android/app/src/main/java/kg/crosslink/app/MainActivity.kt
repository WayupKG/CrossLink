package kg.crosslink.app

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import kg.crosslink.app.ui.AppIcon
import kg.crosslink.app.ui.BrandSurface
import kg.crosslink.app.ui.CrossLinkTheme
import kg.crosslink.app.ui.Field
import kg.crosslink.app.ui.IconAction
import kg.crosslink.app.ui.IconBox
import kg.crosslink.app.ui.Lucide
import kg.crosslink.app.ui.Motion
import kg.crosslink.app.ui.Panel
import kg.crosslink.app.ui.Pill
import kg.crosslink.app.ui.PillStyle
import kg.crosslink.app.ui.ProgressLine
import kg.crosslink.app.ui.StatusDot
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class MainActivity : ComponentActivity() {
    private lateinit var link: LinkController

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        link = LinkController.get(this)
        link.restorePairing()
        // Without it the connection notification of LinkService is hidden (the service still runs)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        setContent {
            CrossLinkTheme { MainScreen(link = link, scan = ::scanQR) }
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // The clipboard is readable only now: what was copied in another app goes to the Mac
        link.focused = hasFocus
        if (hasFocus) link.offerClipboard()
    }

    private fun scanQR() {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        GmsBarcodeScanning.getClient(this, options).startScan()
            .addOnSuccessListener { barcode ->
                barcode.rawValue?.let {
                    link.pairCode = it
                    link.connect(it)
                }
            }
            .addOnFailureListener { link.pairCode = "" }
    }
}

@Composable
private fun MainScreen(link: LinkController, scan: () -> Unit) {
    val t = CrossLinkTheme.tokens
    val context = LocalContext.current
    val send = { uris: List<Uri> -> if (uris.isNotEmpty()) link.sendFiles(OutgoingFile.open(context, uris)) }
    val pickMedia = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { send(it) }
    val pickFiles = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { send(it) }

    Column(
        Modifier
            .fillMaxSize()
            .background(t.background)
            .verticalScroll(rememberScrollState())
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Hero(link, scan)
        Reveal(!link.connected && !link.reconnecting && !link.hasPairing) { ManualCode(link) }
        Reveal(link.connected) {
            Composer(
                link,
                onPhotos = { pickMedia.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo)) },
                onFiles = { pickFiles.launch(arrayOf("*/*")) },
            )
        }
        Reveal(link.connected || link.history.isNotEmpty()) { History(link) }
        Hint()
        Footer(link)
    }
}

/** Panels open with --duration-slow and close faster with --duration-medium: closing gets out of the way. */
@Composable
private fun Reveal(visible: Boolean, content: @Composable () -> Unit) {
    AnimatedVisibility(
        visible,
        enter = fadeIn(tween(Motion.slow, easing = Motion.smoothOut)) +
            expandVertically(tween(Motion.slow, easing = Motion.smoothOut)),
        exit = fadeOut(tween(Motion.quick)) + shrinkVertically(tween(Motion.medium, easing = Motion.smoothOut)),
    ) { content() }
}

@Composable
private fun Hero(link: LinkController, scan: () -> Unit) {
    val glow by animateFloatAsState(if (link.connected) 1f else 0f, tween(Motion.verySlow, easing = Motion.smoothOut), label = "glow")
    BrandSurface(glow) {
        Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                AppIcon(52.dp)
                Column {
                    Text("CrossLink", style = MaterialTheme.typography.headlineMedium)
                    Text("Mac ↔ Android · локальная сеть", style = MaterialTheme.typography.bodySmall,
                        color = Color.White.copy(alpha = 0.6f))
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatusDot(live = link.connected, busy = link.reconnecting,
                    color = if (link.connected) Color(0xFF8C9DFF) else Color.White.copy(alpha = 0.45f))
                AnimatedContent(link.status, label = "status",
                    transitionSpec = { fadeIn(tween(Motion.quick)) togetherWith fadeOut(tween(Motion.quick)) }) {
                    Text(it, style = MaterialTheme.typography.bodyMedium, color = Color.White.copy(alpha = 0.85f))
                }
            }
            when {
                link.connected -> Pill("Отключиться", link::disconnect, Modifier.fillMaxWidth(),
                    style = PillStyle.Glass, icon = Lucide.Power)
                link.reconnecting -> Pill("Остановить переподключение", link::disconnect, Modifier.fillMaxWidth(),
                    style = PillStyle.Glass, icon = Lucide.X)
                link.hasPairing -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Pill("Подключиться", { link.connect(link.pairCode) }, Modifier.weight(1f),
                        style = PillStyle.Inverse, icon = Lucide.RotateCw)
                    Pill("QR", scan, style = PillStyle.Glass, icon = Lucide.ScanQrCode)
                }
                else -> Pill("Сканировать QR-код", scan, Modifier.fillMaxWidth(),
                    style = PillStyle.Inverse, icon = Lucide.ScanQrCode)
            }
        }
    }
}

@Composable
private fun ManualCode(link: LinkController) {
    val t = CrossLinkTheme.tokens
    Panel {
        Text("Код вручную", style = MaterialTheme.typography.titleMedium, color = t.foreground)
        Text("Камера недоступна? На Mac нажмите «Скопировать код подключения» и вставьте его сюда.",
            style = MaterialTheme.typography.bodySmall, color = t.mutedForeground)
        Field(link.pairCode, { link.pairCode = it }, "crosslink://pair?…", minLines = 2, maxLines = 3)
        Pill("Подключиться", { link.connect(link.pairCode) }, Modifier.fillMaxWidth(),
            style = PillStyle.Secondary, enabled = link.pairCode.isNotBlank())
    }
}

@Composable
private fun Composer(link: LinkController, onPhotos: () -> Unit, onFiles: () -> Unit) {
    val t = CrossLinkTheme.tokens
    Panel {
        Text("Отправить на Mac", style = MaterialTheme.typography.titleMedium, color = t.foreground)
        Field(link.draft, { link.draft = it }, "Текст или ссылка", minLines = 3)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Pill("Буфер", link::sendClipboard, Modifier.weight(1f), style = PillStyle.Secondary,
                icon = Lucide.Clipboard, height = 40.dp)
            Pill("Фото", onPhotos, Modifier.weight(1f), style = PillStyle.Secondary, icon = Lucide.Image, height = 40.dp)
            Pill("Файл", onFiles, Modifier.weight(1f), style = PillStyle.Secondary, icon = Lucide.File, height = 40.dp)
        }
        Pill("Отправить", { if (link.sendMessage(link.draft)) link.draft = "" }, Modifier.fillMaxWidth(),
            icon = Lucide.Send, enabled = link.draft.isNotBlank())
    }
}

@Composable
private fun History(link: LinkController) {
    val t = CrossLinkTheme.tokens
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("История", style = MaterialTheme.typography.titleMedium, color = t.foreground, modifier = Modifier.weight(1f))
            if (link.history.any { it.state != HistoryItem.State.ACTIVE }) {
                Pill("Очистить", link::clearHistory, style = PillStyle.Ghost, height = 32.dp)
            }
        }
        if (link.history.isEmpty()) {
            Text("Здесь появится всё, что вы отправите на Mac или получите с него.",
                style = MaterialTheme.typography.bodySmall, color = t.mutedForeground)
        }
        link.history.forEach { item -> key(item.key) { HistoryRow(item) } }
    }
}

@Composable
private fun HistoryRow(item: HistoryItem) {
    val t = CrossLinkTheme.tokens
    val context = LocalContext.current
    val shift = with(LocalDensity.current) { Motion.distanceBase.roundToPx() }
    // New rows rise into place; content arriving is shown with --duration-slow, as in replai
    val appear = remember { MutableTransitionState(false).apply { targetState = true } }
    AnimatedVisibility(appear, enter = fadeIn(tween(Motion.slow, easing = Motion.smoothOut)) +
        slideInVertically(tween(Motion.slow, easing = Motion.smoothOut)) { shift }) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            IconBox(
                icon = when {
                    item.kind == HistoryItem.Kind.FILE && item.isImage -> Lucide.Image
                    item.kind == HistoryItem.Kind.FILE -> Lucide.File
                    item.kind == HistoryItem.Kind.CLIPBOARD -> Lucide.Clipboard
                    item.isLink -> Lucide.Link
                    else -> Lucide.Keyboard
                },
                // What came from the Mac is tinted with the brand, what went there stays neutral
                tint = if (item.incoming) t.brandStrong else t.foreground,
                fill = if (item.incoming) t.brand.copy(alpha = 0.12f) else t.muted,
            )
            Column(Modifier.weight(1f).padding(top = 1.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(item.title, style = MaterialTheme.typography.bodyMedium, color = t.foreground,
                    maxLines = if (item.kind == HistoryItem.Kind.FILE) 1 else 3, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(if (item.incoming) Lucide.ArrowDownLeft else Lucide.ArrowUpRight, null,
                        Modifier.size(12.dp), tint = t.mutedForeground)
                    Text(meta(item), style = MaterialTheme.typography.labelSmall,
                        color = if (item.state == HistoryItem.State.FAILED) t.destructiveText else t.mutedForeground)
                }
                if (item.kind == HistoryItem.Kind.FILE && item.state == HistoryItem.State.ACTIVE) {
                    ProgressLine(item.progress, Modifier.padding(top = 6.dp))
                }
            }
            Row {
                when {
                    item.state == HistoryItem.State.FAILED -> Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                        Icon(Lucide.CircleAlert, "Не удалось", Modifier.size(18.dp), tint = t.destructiveText)
                    }
                    item.kind == HistoryItem.Kind.FILE -> item.uri?.let { uri ->
                        IconAction(Lucide.ExternalLink, "Открыть") { open(context, Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, item.mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)) }
                    }
                    else -> {
                        if (item.isLink) IconAction(Lucide.ExternalLink, "Открыть ссылку") {
                            open(context, Intent(Intent.ACTION_VIEW, Uri.parse(item.title.trim())))
                        }
                        IconAction(Lucide.Copy, "Скопировать") { copy(context, item.title) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Hint() {
    val t = CrossLinkTheme.tokens
    val context = LocalContext.current
    var offerTile by remember { mutableStateOf(Build.VERSION.SDK_INT >= 33 && !ClipboardTile.isAdded(context)) }
    Column(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Android не даёт приложениям читать буфер в фоне. Скопированное на телефоне уходит на Mac, " +
            "когда вы открываете CrossLink, нажимаете на его уведомление или на плитку «Буфер → Mac» " +
            "в шторке. Фото и файлы — через «Поделиться» → CrossLink.",
            style = MaterialTheme.typography.bodySmall, color = t.mutedForeground)
        if (offerTile && Build.VERSION.SDK_INT >= 33) {
            Pill("Добавить плитку в шторку", {
                ClipboardTile.requestAdd(context) { added ->
                    if (added == true) offerTile = false
                    if (added == null) Toast.makeText(context,
                        "Добавьте плитку «Буфер → Mac» вручную: шторка → изменить", Toast.LENGTH_LONG).show()
                }
            }, style = PillStyle.Outline, icon = Lucide.Clipboard, height = 40.dp)
        }
    }
}

@Composable
private fun Footer(link: LinkController) {
    val t = CrossLinkTheme.tokens
    Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (link.hasPairing) {
            Pill("Забыть сопряжение", link::forgetPairing, style = PillStyle.Ghost, icon = Lucide.Trash,
                height = 40.dp, contentColor = t.destructiveText)
        }
        Spacer(Modifier.weight(1f))
        Text("v0.2 · AES-256-GCM", style = MaterialTheme.typography.labelSmall, color = t.mutedForeground,
            modifier = Modifier.padding(end = 8.dp))
    }
}

private fun meta(item: HistoryItem): String {
    val parts = mutableListOf(if (item.incoming) "С Mac" else "На Mac")
    when (item.kind) {
        HistoryItem.Kind.TEXT -> parts += "текст"
        HistoryItem.Kind.CLIPBOARD -> parts += "буфер"
        HistoryItem.Kind.FILE -> if (item.size >= 0) parts += formatSize(item.size)
    }
    parts += TIME.format(Instant.ofEpochMilli(item.time).atZone(ZoneId.systemDefault()))
    when (item.state) {
        HistoryItem.State.ACTIVE -> parts += "${(item.progress * 100).toInt()}%"
        HistoryItem.State.FAILED -> parts += "не удалось"
        // A finished file shows no progress line, and a received one has the "open" button
        HistoryItem.State.DONE -> Unit
    }
    return parts.joinToString(" · ")
}

private val TIME = DateTimeFormatter.ofPattern("HH:mm")
private val RU = Locale.forLanguageTag("ru")

private fun formatSize(bytes: Long): String {
    if (bytes < 1024) return "$bytes Б"
    val units = listOf("КБ", "МБ", "ГБ")
    var value = bytes / 1024.0
    var unit = 0
    while (value >= 1024 && unit < units.lastIndex) { value /= 1024; unit++ }
    return (if (value >= 100) "%.0f %s" else "%.1f %s").format(RU, value, units[unit])
}

private fun copy(context: Context, text: String) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
        .setPrimaryClip(ClipData.newPlainText(LinkController.CLIP_LABEL, text))
    // Android 13+ confirms copying itself
    if (Build.VERSION.SDK_INT < 33) Toast.makeText(context, "Скопировано", Toast.LENGTH_SHORT).show()
}

private fun open(context: Context, intent: Intent) {
    try { context.startActivity(intent) }
    catch (_: ActivityNotFoundException) { Toast.makeText(context, "Нет приложения, чтобы открыть", Toast.LENGTH_SHORT).show() }
}
