import SwiftUI
import CoreImage.CIFilterBuiltins
import AppKit

struct ContentView: View {
    @ObservedObject var link: MacLinkManager
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            hero
            if link.connected {
                composer.transition(.opacity.combined(with: .move(edge: .top)))
            }
            if link.connected || !link.history.isEmpty {
                historyPanel.transition(.opacity)
            }
            footer
        }
        .padding(12)
        .frame(width: 360)
        .background(Tokens.background)
        .font(Typo.body)
        .foregroundStyle(Tokens.foreground)
        .animation(Motion.slow, value: link.connected)
        .animation(Motion.slow, value: link.history.count)
    }

    // MARK: Hero

    private var hero: some View {
        BrandSurface(glow: link.connected ? 1 : 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CrossLink").font(Typo.display(20)).tracking(-0.4)
                        Text("Mac ↔ Android · локальная сеть").font(Typo.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    moreMenu
                }
                HStack(spacing: 6) {
                    StatusDot(live: link.connected, color: link.connected ? Color(hex: 0x8C9DFF) : .white.opacity(0.45))
                    Text(link.status)
                        .font(Typo.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                        .animation(Motion.quick, value: link.status)
                }
                if link.connected {
                    Button { link.disconnectPhone() } label: { Label("Отключить телефон", systemImage: "power") }
                        .buttonStyle(Pill(kind: .glass, height: 34, fullWidth: true))
                } else {
                    pairing
                }
            }
        }
    }

    private var pairing: some View {
        VStack(spacing: 12) {
            if let image = makeQR(link.pairURL) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 168, height: 168)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Radius.pop, style: .continuous).fill(.white))
                    .accessibilityLabel("QR-код для сопряжения с Android")
            }
            Text("Откройте CrossLink на Android и нажмите «Сканировать QR-код»")
                .font(Typo.inter(12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            HStack(spacing: 8) {
                Button { copyToPasteboard(link.pairURL) } label: { Label("Скопировать код", systemImage: "doc.on.doc") }
                    .buttonStyle(Pill(kind: .glass, height: 30))
                Text("\(link.hostIP):\(String(link.port))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var moreMenu: some View {
        Menu {
            Toggle("Запускать при входе в систему", isOn: Binding(
                get: { link.launchAtLogin },
                set: { link.setLaunchAtLogin($0) }))
            Button("Обновить IP и подключение") { link.restart() }
            Button("Скопировать код подключения") { copyToPasteboard(link.pairURL) }
            Divider()
            Button("Сбросить сопряжение", role: .destructive) { link.resetPairing() }
            Divider()
            Button("Выйти из CrossLink") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.10)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Composer

    private var composer: some View {
        Panel {
            Text("Отправить на телефон").font(Typo.title).tracking(-0.14)
            HStack(spacing: 8) {
                TextField("Текст или ссылка", text: $draft)
                    .focused($draftFocused)
                    .modifier(FieldLook(focused: draftFocused))
                    .onSubmit(sendDraft)
                Button(action: sendDraft) { Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(Pill(kind: .primary, height: 34))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Отправить (⏎)")
            }
            HStack(spacing: 8) {
                Button { link.sendCurrentClipboard() } label: { Label("Буфер", systemImage: "doc.on.clipboard") }
                    .buttonStyle(Pill(kind: .secondary))
                Button(action: pickFiles) { Label("Файлы…", systemImage: "paperclip") }
                    .buttonStyle(Pill(kind: .secondary))
                Spacer()
            }
            Toggle(isOn: $link.autoClipboard) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Автоотправка буфера").font(Typo.inter(12.5, .medium))
                    Text("Всё скопированное на Mac сразу уходит на телефон. Не включайте, если копируете пароли.")
                        .font(Typo.caption).foregroundStyle(Tokens.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Tokens.brand)
        }
    }

    // MARK: History

    private var historyPanel: some View {
        Panel {
            HStack {
                Text("История").font(Typo.title).tracking(-0.14)
                Spacer()
                if link.history.contains(where: { $0.state != .active }) {
                    Button("Очистить") { link.clearHistory() }.buttonStyle(Pill(kind: .ghost, height: 24))
                }
            }
            if link.history.isEmpty {
                Text("Здесь появится всё, что вы отправите на телефон или получите с него.")
                    .font(Typo.caption).foregroundStyle(Tokens.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // A short list takes its own height; a long one scrolls inside the popover
                ViewThatFits(in: .vertical) {
                    rows
                    ScrollView { rows }.scrollIndicators(.never)
                }
                .frame(maxHeight: 280)
                .padding(.horizontal, -8)
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(link.history) { entry in
                HistoryRow(entry: entry)
                    .transition(.opacity.combined(with: .offset(y: -8)))
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("v0.2 · AES-256-GCM · только локальная сеть")
                .font(Typo.inter(10.5)).foregroundStyle(Tokens.mutedForeground)
            Spacer()
            Button("Выйти") { NSApplication.shared.terminate(nil) }
                .buttonStyle(Pill(kind: .ghost, height: 24))
        }
        .padding(.horizontal, 6)
    }

    // MARK: Actions

    private func sendDraft() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        link.sendText(draft)
        draft = ""
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Отправить"
        panel.message = "Файлы уйдут на телефон: фото и видео в Галерею, остальное в «Загрузки»"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { link.sendFiles(panel.urls) }
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

/// One history line; observes its entry, so a moving file redraws only this row.
private struct HistoryRow: View {
    @ObservedObject var entry: HistoryEntry
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconBox(symbol: symbol,
                    // What came from the phone is tinted with the brand, what went there stays neutral
                    tint: entry.incoming ? Tokens.brandStrong : Tokens.foreground,
                    fill: entry.incoming ? Tokens.brand.opacity(0.12) : Tokens.muted)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(Typo.body)
                    .lineLimit(entry.kind == .file ? 1 : 3)
                    .truncationMode(entry.kind == .file ? .middle : .tail)
                    .textSelection(.enabled)
                HStack(spacing: 4) {
                    Image(systemName: entry.incoming ? "arrow.down.left" : "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                    Text(meta)
                }
                .font(Typo.caption)
                .foregroundStyle(entry.state == .failed ? Tokens.destructiveText : Tokens.mutedForeground)
                if entry.kind == .file && entry.state == .active {
                    ProgressLine(value: entry.progress).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(hovering ? Tokens.accent : .clear))
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 0) {
            if entry.state == .failed {
                Image(systemName: "exclamationmark.circle").foregroundStyle(Tokens.destructiveText).frame(width: 26, height: 26)
            } else if entry.kind == .file {
                if let url = entry.fileURL {
                    action("arrow.up.forward.app", "Открыть") { NSWorkspace.shared.open(url) }
                    action("folder", "Показать в Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                } else if entry.state == .done {
                    Image(systemName: "checkmark").foregroundStyle(Tokens.mutedForeground).frame(width: 26, height: 26)
                }
            } else {
                if entry.isLink, let url = URL(string: entry.title.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    action("safari", "Открыть ссылку") { NSWorkspace.shared.open(url) }
                }
                action("doc.on.doc", "Скопировать") { copyToPasteboard(entry.title) }
            }
        }
        .font(.system(size: 12, weight: .medium))
    }

    private func action(_ symbol: String, _ help: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .foregroundStyle(hovering ? Tokens.foreground : Tokens.mutedForeground)
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var symbol: String {
        switch entry.kind {
        case .file: entry.isImage ? "photo" : "doc"
        case .clipboard: "doc.on.clipboard"
        case .text: entry.isLink ? "link" : "text.alignleft"
        }
    }

    private var meta: String {
        var parts = [entry.incoming ? "С телефона" : "На телефон"]
        switch entry.kind {
        case .text: parts.append("текст")
        case .clipboard: parts.append("буфер")
        case .file: if entry.size >= 0 { parts.append(Transfers.formatSize(entry.size)) }
        }
        parts.append(entry.date.formatted(date: .omitted, time: .shortened))
        switch entry.state {
        case .active: parts.append("\(Int(entry.progress * 100))%")
        case .failed: parts.append("не удалось")
        case .done: if entry.kind == .file { parts.append(entry.incoming ? "в Загрузках" : "доставлено") }
        }
        return parts.joined(separator: " · ")
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
