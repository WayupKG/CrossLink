import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit

struct ContentView: View {
    @ObservedObject var link: MacLinkManager
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CrossLink").font(.headline)
                    Text("macOS ↔ Android").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(link.connected ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
            }

            Text(link.status).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !link.connected {
                VStack(spacing: 7) {
                    if let image = makeQR(link.pairURL) {
                        Image(nsImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 170, height: 170)
                            .accessibilityLabel("QR-код для сопряжения с Android")
                    }
                    Text("Откройте CrossLink на Android и отсканируйте QR")
                        .font(.caption).multilineTextAlignment(.center)
                    Text("Mac: \(link.hostIP):\(link.port)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Button("Скопировать код подключения") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.pairURL, forType: .string)
                    }
                    Button("Обновить IP и подключение") { link.restart() }
                        .font(.caption)
                    Button("Сбросить сопряжение") { link.resetPairing() }
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack {
                    Label("Android подключён", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("Отключить") { link.disconnectPhone() }
                }
                Toggle("Автоотправка буфера Mac", isOn: $link.autoClipboard)
                    .toggleStyle(.checkbox)
                Text("Автоотправка выключена по умолчанию ради приватности.")
                    .font(.caption2).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("Текст или ссылка", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(sendDraft)
                    Button("Отправить") { sendDraft() }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Button("Отправить буфер") { link.sendCurrentClipboard() }
                    Spacer()
                }
                if !link.receivedText.isEmpty {
                    Divider()
                    Text("Последнее сообщение с Android:").font(.caption).foregroundStyle(.secondary)
                    Text(link.receivedText).lineLimit(4).textSelection(.enabled)
                    Button("Скопировать") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link.receivedText, forType: .string)
                    }
                }
            }
            Divider()
            Toggle("Запускать при входе в систему", isOn: Binding(
                get: { link.launchAtLogin },
                set: { link.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox)
            HStack {
                Text("MVP • Только локальная сеть").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Выход") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(18)
        .frame(width: 340)
    }

    private func sendDraft() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        link.sendText(draft)
        draft = ""
    }

    private func makeQR(_ value: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(value.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let image = output.transformed(by: CGAffineTransform(scaleX: 7, y: 7))
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
