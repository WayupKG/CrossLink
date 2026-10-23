package kg.crosslink.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning

class MainActivity : ComponentActivity() {
    private lateinit var link: LinkController

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        link = LinkController.get(this)
        link.restorePairing()
        // Without it the connection notification of LinkService is hidden (the service still runs)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                MainScreen(link = link, scan = ::scanQR)
            }
        }
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
    val connected = link.connected
    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Spacer(Modifier.height(12.dp))
        Text("CrossLink", style = MaterialTheme.typography.headlineLarge)
        Text("macOS ↔ Android · Локальная сеть", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(if (connected) "● Подключено" else "○ Не подключено",
            color = if (connected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
        Text(link.status, style = MaterialTheme.typography.bodyMedium)

        if (!connected) {
            if (link.reconnecting) {
                OutlinedButton(onClick = link::disconnect) { Text("Остановить переподключение") }
            }
            HorizontalDivider()
            Text("1. Сопряжение", style = MaterialTheme.typography.titleLarge)
            Text("Откройте приложение на Mac, затем сканируйте QR-код. Оба устройства должны быть в одной Wi-Fi-сети.")
            Button(onClick = scan, modifier = Modifier.fillMaxWidth()) { Text("Сканировать QR-код") }
            OutlinedTextField(
                value = link.pairCode,
                onValueChange = { link.pairCode = it },
                label = { Text("Или вставьте код crosslink://") },
                minLines = 2,
                maxLines = 3,
                modifier = Modifier.fillMaxWidth()
            )
            Button(onClick = { link.connect(link.pairCode) }, modifier = Modifier.fillMaxWidth()) {
                Text("Подключиться")
            }
        } else {
            OutlinedButton(onClick = link::disconnect) { Text("Отключиться") }
        }

        TextButton(onClick = link::forgetPairing) { Text("Забыть сопряжение") }
        HorizontalDivider()
        Text("2. Отправка на Mac", style = MaterialTheme.typography.titleLarge)
        OutlinedTextField(
            value = link.draft,
            onValueChange = { link.draft = it },
            label = { Text("Текст или ссылка") },
            minLines = 2,
            modifier = Modifier.fillMaxWidth()
        )
        Button(onClick = { link.sendMessage(link.draft); link.draft = "" },
            enabled = connected && link.draft.isNotBlank(), modifier = Modifier.fillMaxWidth()) {
            Text("Отправить текст")
        }
        OutlinedButton(onClick = link::sendClipboard, enabled = connected, modifier = Modifier.fillMaxWidth()) {
            Text("Отправить буфер обмена")
        }
        Text("Android не даёт читать буфер в фоне. Выделите текст в любом приложении и выберите «CrossLink» в меню (или «Поделиться» → CrossLink) — он сразу попадёт в буфер Mac.",
            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)

        if (link.receivedText.isNotEmpty()) {
            HorizontalDivider()
            Text("Последнее с Mac", style = MaterialTheme.typography.titleMedium)
            Text(link.receivedText, maxLines = 8, overflow = TextOverflow.Ellipsis)
            Text("При отправке буфера с Mac текст автоматически попадает в буфер Android.",
                style = MaterialTheme.typography.bodySmall)
        }
        Spacer(Modifier.height(24.dp))
        Text("MVP 0.1 • Связь держится в фоне и восстанавливается сама (уведомление «Поддерживает связь с Mac»).",
            style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
