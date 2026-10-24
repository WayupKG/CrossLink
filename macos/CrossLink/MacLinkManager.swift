import Foundation
import Network
import CryptoKit
import AppKit
import ServiceManagement

@MainActor
final class MacLinkManager: ObservableObject {
    @Published private(set) var status = "Запуск сервера…"
    @Published private(set) var connected = false
    @Published private(set) var hostIP = ""
    /// Newest first, see HistoryEntry.
    @Published private(set) var history: [HistoryEntry] = []
    @Published var autoClipboard = UserDefaults.standard.bool(forKey: "autoClipboard") {
        didSet { UserDefaults.standard.set(autoClipboard, forKey: "autoClipboard") }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Banners and sound for what arrives; false once the user (or an old build) refused them.
    @Published private(set) var notificationsAllowed = true

    let port: UInt16 = 48321
    /// A throwaway key when the Keychain refused the saved one (see keychainDenied).
    private var secret: Data
    private var keychainDenied = false
    private var listener: NWListener?
    /// The authenticated phone. Only a connection that completes the handshake replaces it,
    /// so a stray LAN connection to the port cannot drop the phone.
    private var active: Peer?
    /// A connection still proving it knows the pairing secret; at most one at a time.
    private var pending: Peer?
    private var clipboardChangeCount = NSPasteboard.general.changeCount
    private var clipboardTimer: Timer?
    private var watchdog: Timer?
    private let pathMonitor = NWPathMonitor()
    private let notifier = Notifier()
    private let maxFrame = 512 * 1024
    private let historySize = 50
    /// Android pings every 20 s, so this much silence means the phone is gone (sleep, other network).
    private let activeTimeout: TimeInterval = 60
    private let handshakeTimeout: TimeInterval = 10
    private enum Stage { case awaitingHello, awaitingAuth, connected }

    /// One TCP connection with its own handshake and crypto state.
    @MainActor
    private final class Peer {
        let connection: NWConnection
        var buffer = Data()
        var stage: Stage = .awaitingHello
        var sendKey: SymmetricKey?
        var receiveKey: SymmetricKey?
        var sendSequence = 0
        var receiveSequence = 0
        var lastActivity = Date()
        init(_ connection: NWConnection) { self.connection = connection }
    }

    /// A file going to the phone. The next chunk is read only after the previous one is handed to
    /// the network, so a big file does not pile up in memory and pongs slip in between.
    @MainActor
    private final class Upload {
        let id = Transfers.newID()
        let entry: HistoryEntry
        let handle: FileHandle
        let name: String
        let size: Int64
        let mime: String
        weak var peer: Peer?
        var hasher = SHA256()
        var sent: Int64 = 0
        var shownPercent = -1
        var finished = false
        init(entry: HistoryEntry, handle: FileHandle, name: String, size: Int64, mime: String, peer: Peer) {
            self.entry = entry; self.handle = handle; self.name = name; self.size = size; self.mime = mime; self.peer = peer
        }
    }

    /// A file coming from the phone: written to a temporary file, moved to Downloads once its hash matches.
    @MainActor
    private final class Download {
        let entry: HistoryEntry
        let name: String
        let size: Int64
        let temp: URL
        let handle: FileHandle
        var hasher = SHA256()
        var received: Int64 = 0
        var shownPercent = -1
        init(entry: HistoryEntry, name: String, size: Int64, temp: URL, handle: FileHandle) {
            self.entry = entry; self.name = name; self.size = size; self.temp = temp; self.handle = handle
        }
    }

    private var uploads: [Upload] = []
    private var uploading: Upload?
    /// Uploads sent in full and waiting for the phone's file_done.
    private var unconfirmed: [String: Upload] = [:]
    private var downloads: [String: Download] = [:]

    var pairURL: String { Pairing.connectionURL(host: hostIP, port: port, secret: secret) }
    private var waitingStatus: String {
        if keychainDenied { return "Нет доступа к Связке ключей: перезапустите CrossLink и нажмите «Разрешить всегда»" }
        return hostIP.isEmpty ? "Нет локального IP" : "Ожидание Android · \(hostIP):\(port)"
    }

    init() {
        if let saved = Pairing.storedSecret() {
            secret = saved
        } else {
            secret = Pairing.randomSecret()
            keychainDenied = true
        }
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchClipboard() }
        }
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.dropSilentPeers() }
        }
        // A new Wi-Fi network or DHCP lease changes the address in the QR code
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAddress() }
        }
        pathMonitor.start(queue: .main)
        notifier.requestPermission { [weak self] allowed in Task { @MainActor in self?.notificationsAllowed = allowed } }
        restart()
    }

    /// Called when the menu opens: the user may have changed it in System Settings meanwhile.
    func refreshNotificationPermission() {
        notifier.checkPermission { [weak self] allowed in Task { @MainActor in self?.notificationsAllowed = allowed } }
    }

    func resetPairing() {
        disconnectClient()
        Pairing.forgetSecret()
        secret = Pairing.storedSecret() ?? Pairing.randomSecret()
        restart()
    }

    func restart() {
        disconnectClient()
        listener?.cancel()
        listener = nil
        hostIP = Pairing.localIPv4() ?? ""
        guard !hostIP.isEmpty else {
            status = "Локальный IP не найден. Подключитесь к Wi-Fi и обновите подключение."
            return
        }
        do {
            guard let tcpPort = NWEndpoint.Port(rawValue: port) else { return }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let server = try NWListener(using: parameters, on: tcpPort)
            listener = server
            // Bonjour lets the phone find this Mac after its IP changes; only the paired phone knows the id
            server.service = NWListener.Service(type: Pairing.bonjourType,
                txtRecord: NWTXTRecord(["id": Pairing.discoveryID(secret: secret)]))
            // Handlers run on the main queue (see start(queue:)), so MainActor isolation holds.
            server.newConnectionHandler = { [weak self] incoming in
                MainActor.assumeIsolated { self?.accept(incoming) }
            }
            server.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    switch state {
                    case .ready:
                        if !self.connected { self.status = self.waitingStatus }
                    case .failed(let error): self.status = "Ошибка сервера: \(error.localizedDescription)"
                    default: break
                    }
                }
            }
            server.start(queue: .main)
        } catch {
            status = "Не удалось открыть порт \(port): \(error.localizedDescription)"
        }
    }

    private func refreshAddress() {
        let ip = Pairing.localIPv4() ?? ""
        guard ip != hostIP else { return }
        if listener == nil || ip.isEmpty {
            restart()
        } else {
            hostIP = ip
            if active == nil { status = waitingStatus }
        }
    }

    private func accept(_ incoming: NWConnection) {
        if let pending { drop(pending) }
        let peer = Peer(incoming)
        pending = peer
        if active == nil { status = "Устанавливаем защищённое соединение…" }
        incoming.stateUpdateHandler = { [weak self, weak peer] state in
            MainActor.assumeIsolated {
                guard let self, let peer else { return }
                switch state {
                case .ready: self.readNext(from: peer)
                case .failed, .cancelled: self.drop(peer)
                default: break
                }
            }
        }
        incoming.start(queue: .main)
    }

    /// Closes a connection we track; anything else (already dropped) is ignored.
    private func drop(_ peer: Peer) {
        if peer === pending { pending = nil }
        else if peer === active {
            active = nil
            failTransfers()
        }
        else { return }
        peer.connection.cancel()
        if active == nil {
            connected = false
            status = waitingStatus
        }
    }

    private func promote(_ peer: Peer) {
        // The same phone reconnecting (or a re-paired one) replaces the old session
        if let old = active { drop(old) }
        pending = nil
        active = peer
        connected = true
        status = "Android подключён · зашифровано"
    }

    func disconnectClient() {
        if let pending { drop(pending) }
        if let active { drop(active) }
    }

    /// "Disconnect" in the menu: the phone reconnects on its own after a dropped link, so tell it to stop first.
    func disconnectPhone() {
        guard let active else { return }
        sendEncrypted(type: "bye", text: "", to: active)
        drop(active)
    }

    private func dropSilentPeers() {
        let now = Date()
        if let pending, now.timeIntervalSince(pending.lastActivity) > handshakeTimeout { drop(pending) }
        if let active, now.timeIntervalSince(active.lastActivity) > activeTimeout { drop(active) }
    }

    private func readNext(from peer: Peer) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self, weak peer] data, _, done, error in
            MainActor.assumeIsolated {
                guard let self, let peer, peer === self.active || peer === self.pending else { return }
                if let data { peer.buffer.append(data) }
                if peer.buffer.count > self.maxFrame + 4 + 65536 { self.drop(peer); return }
                while peer.buffer.count >= 4 {
                    let length = peer.buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                    if length == 0 || length > self.maxFrame { self.drop(peer); return }
                    guard peer.buffer.count >= Int(length) + 4 else { break }
                    let frame = peer.buffer.subdata(in: 4..<(Int(length) + 4))
                    peer.buffer.removeSubrange(0..<(Int(length) + 4))
                    peer.lastActivity = Date()
                    guard self.handle(frame, from: peer) else { self.drop(peer); return }
                }
                if done || error != nil { self.drop(peer) }
                else { self.readNext(from: peer) }
            }
        }
    }

    private func handle(_ frame: Data, from peer: Peer) -> Bool {
        if peer.stage == .awaitingHello {
            guard let obj = try? JSONSerialization.jsonObject(with: frame) as? [String: Any],
                  obj["type"] as? String == "hello",
                  obj["version"] as? Int == 1,
                  let nonce64 = obj["nonce"] as? String,
                  let clientNonce = Data(base64Encoded: nonce64), clientNonce.count == 32 else { return false }
            let serverNonce = randomBytes(32)
            let salt = clientNonce + serverNonce
            peer.sendKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret),
                salt: salt, info: Data("crosslink/v1/mac-to-android".utf8), outputByteCount: 32)
            peer.receiveKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret),
                salt: salt, info: Data("crosslink/v1/android-to-mac".utf8), outputByteCount: 32)
            sendPlain(["type": "hello_ack", "version": 1, "nonce": serverNonce.base64EncodedString()], to: peer)
            peer.stage = .awaitingAuth
            return sendEncrypted(type: "ready", text: "Mac готов", to: peer)
        }
        guard let receiveKey = peer.receiveKey,
              let box = try? AES.GCM.SealedBox(combined: frame),
              let plain = try? AES.GCM.open(box, using: receiveKey),
              let obj = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let seq = obj["seq"] as? Int, seq == peer.receiveSequence + 1,
              let type = obj["type"] as? String else { return false }
        peer.receiveSequence = seq
        let text = obj["text"] as? String ?? ""
        if peer.stage == .awaitingAuth {
            guard type == "ready_ack" else { return false }
            peer.stage = .connected
            promote(peer)
            return true
        }
        switch type {
        case "text":
            let clipped = String(text.prefix(20000))
            remember(HistoryEntry(incoming: true, kind: .text, title: clipped))
            notifier.textArrived(clipped)
        case "clipboard":
            let clipped = String(text.prefix(20000))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipped, forType: .string)
            clipboardChangeCount = NSPasteboard.general.changeCount  // Prevent feedback loops
            remember(HistoryEntry(incoming: true, kind: .clipboard, title: clipped))
            notifier.clipboardArrived(characters: clipped.count)
        case "file_start": startDownload(obj, from: peer)
        case "file_chunk": receiveChunk(obj, from: peer)
        case "file_end": finishDownload(obj, from: peer)
        case "file_cancel":
            if let id = obj["id"] as? String, let download = downloads.removeValue(forKey: id) { discard(download) }
        case "file_done":
            if let id = obj["id"] as? String, let upload = unconfirmed.removeValue(forKey: id) {
                let ok = obj["ok"] as? Bool ?? false
                upload.entry.state = ok ? .done : .failed
                if ok { upload.entry.progress = 1 }
                // A refusal can come mid-file (phone storage full): stop sending the rest
                if !ok, !upload.finished { endUpload(upload) }
            }
        case "ping": return sendEncrypted(type: "pong", text: "", to: peer)
        case "pong": break
        default: return false
        }
        return true
    }

    // MARK: Sending

    private func sendPlain(_ object: [String: Any], to peer: Peer) {
        guard let raw = try? JSONSerialization.data(withJSONObject: object) else { return }
        writeFrame(raw, to: peer)
    }

    @discardableResult
    private func sendEncrypted(type: String, text: String, to target: Peer? = nil) -> Bool {
        guard text.utf8.count <= 20000 else { return false }
        return sendEncrypted(["type": type, "text": text], to: target)
    }

    /// [then] runs once the frame is handed to the network (not when the phone got it).
    @discardableResult
    private func sendEncrypted(_ message: [String: Any], to target: Peer? = nil, then: (() -> Void)? = nil) -> Bool {
        guard let peer = target ?? active, let sendKey = peer.sendKey else { return false }
        var object = message
        object["seq"] = peer.sendSequence + 1
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let sealed = try? AES.GCM.seal(data, using: sendKey),
              let frame = sealed.combined else { return false }
        peer.sendSequence += 1
        writeFrame(frame, to: peer, then: then)
        return true
    }

    private func writeFrame(_ data: Data, to peer: Peer, then: (() -> Void)? = nil) {
        var length = UInt32(data.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(data)
        peer.connection.send(content: framed, completion: .contentProcessed { [weak self, weak peer] error in
            MainActor.assumeIsolated {
                if error != nil {
                    if let self, let peer { self.drop(peer) }
                } else {
                    then?()
                }
            }
        })
    }

    func sendText(_ text: String) {
        let entry = HistoryEntry(incoming: false, kind: .text, title: text)
        remember(entry)
        if !sendEncrypted(type: "text", text: text) { entry.state = .failed }
    }

    func sendCurrentClipboard() {
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        sendClipboard(str)
    }

    private func sendClipboard(_ text: String) {
        let entry = HistoryEntry(incoming: false, kind: .clipboard, title: text)
        remember(entry)
        if !sendEncrypted(type: "clipboard", text: text) { entry.state = .failed }
    }

    // MARK: Files to the phone

    /// Queues files for the phone (they go one after another). Folders are skipped.
    func sendFiles(_ urls: [URL]) {
        guard let peer = active else {
            status = "Сначала подключите телефон"
            notifier.notConnected()
            return
        }
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let name = Transfers.safeName(url.lastPathComponent)
            let size = Int64(values?.fileSize ?? -1)
            let entry = HistoryEntry(incoming: false, kind: .file, title: name, size: size)
            remember(entry)
            guard let handle = try? FileHandle(forReadingFrom: url) else {
                entry.state = .failed
                continue
            }
            uploads.append(Upload(entry: entry, handle: handle, name: name, size: size, mime: Transfers.mime(for: url), peer: peer))
        }
        if uploading == nil { nextUpload() }
    }

    private func nextUpload() {
        guard !uploads.isEmpty else { uploading = nil; return }
        let upload = uploads.removeFirst()
        uploading = upload
        guard let peer = upload.peer, peer === active,
              sendEncrypted(["type": "file_start", "id": upload.id, "name": upload.name,
                             "size": upload.size, "mime": upload.mime], to: peer) else {
            upload.entry.state = .failed
            endUpload(upload)
            return
        }
        unconfirmed[upload.id] = upload
        sendChunk(upload)
    }

    private func sendChunk(_ upload: Upload) {
        guard !upload.finished else { return }
        guard let peer = upload.peer, peer === active else {
            upload.entry.state = .failed
            endUpload(upload)
            return
        }
        let data: Data
        do {
            data = try upload.handle.read(upToCount: Transfers.chunk) ?? Data()
        } catch {
            // The file went away (deleted, unmounted disk): let the phone drop its partial copy
            sendEncrypted(["type": "file_cancel", "id": upload.id], to: peer)
            unconfirmed[upload.id] = nil
            upload.entry.state = .failed
            endUpload(upload)
            return
        }
        if !data.isEmpty {
            upload.hasher.update(data: data)
            upload.sent += Int64(data.count)
            showProgress(upload.entry, done: upload.sent, of: upload.size, shown: &upload.shownPercent)
        }
        if data.count == Transfers.chunk {
            sendEncrypted(["type": "file_chunk", "id": upload.id, "data": data.base64EncodedString()], to: peer) { [weak self] in
                self?.sendChunk(upload)
            }
            return
        }
        if !data.isEmpty {
            sendEncrypted(["type": "file_chunk", "id": upload.id, "data": data.base64EncodedString()], to: peer)
        }
        sendEncrypted(["type": "file_end", "id": upload.id, "sha256": Transfers.hex(upload.hasher.finalize())], to: peer)
        // Done only when the phone confirms with file_done
        endUpload(upload)
    }

    private func endUpload(_ upload: Upload) {
        guard !upload.finished else { return }
        upload.finished = true
        try? upload.handle.close()
        if uploading === upload { nextUpload() }
    }

    // MARK: Files from the phone

    private func startDownload(_ obj: [String: Any], from peer: Peer) {
        guard let id = obj["id"] as? String, !id.isEmpty, downloads[id] == nil else { return }
        let name = Transfers.safeName(obj["name"] as? String ?? "")
        let size = (obj["size"] as? NSNumber)?.int64Value ?? -1
        let entry = HistoryEntry(incoming: true, kind: .file, title: name, size: size)
        remember(entry)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("CrossLink-\(id).part")
        guard downloads.count < Transfers.maxIncoming, size <= Transfers.maxSize,
              FileManager.default.createFile(atPath: temp.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: temp) else {
            entry.state = .failed
            sendEncrypted(["type": "file_done", "id": id, "ok": false], to: peer)
            return
        }
        downloads[id] = Download(entry: entry, name: name, size: size, temp: temp, handle: handle)
    }

    private func receiveChunk(_ obj: [String: Any], from peer: Peer) {
        guard let id = obj["id"] as? String, let download = downloads[id] else { return }
        let limit = download.size >= 0 ? download.size : Transfers.maxSize
        guard let base64 = obj["data"] as? String, let data = Data(base64Encoded: base64),
              download.received + Int64(data.count) <= limit,
              (try? download.handle.write(contentsOf: data)) != nil else {
            downloads[id] = nil
            discard(download)
            sendEncrypted(["type": "file_done", "id": id, "ok": false], to: peer)
            return
        }
        download.hasher.update(data: data)
        download.received += Int64(data.count)
        showProgress(download.entry, done: download.received, of: download.size, shown: &download.shownPercent)
    }

    private func finishDownload(_ obj: [String: Any], from peer: Peer) {
        guard let id = obj["id"] as? String, let download = downloads.removeValue(forKey: id) else { return }
        try? download.handle.close()
        let intact = (download.size < 0 || download.received == download.size)
            && Transfers.hex(download.hasher.finalize()) == (obj["sha256"] as? String)?.lowercased()
        var saved: URL?
        if intact {
            let target = Transfers.downloadURL(for: download.name)
            if (try? FileManager.default.moveItem(at: download.temp, to: target)) != nil {
                // Like a browser download: Gatekeeper checks an app or script from the phone before it runs
                var values = URLResourceValues()
                values.quarantineProperties = [kLSQuarantineAgentNameKey as String: "CrossLink",
                                               kLSQuarantineTypeKey as String: kLSQuarantineTypeOtherDownload]
                var marked = target
                try? marked.setResourceValues(values)
                saved = target
            }
        }
        sendEncrypted(["type": "file_done", "id": id, "ok": saved != nil], to: peer)
        guard let saved else { discard(download); return }
        download.entry.state = .done
        download.entry.progress = 1
        download.entry.fileURL = saved
        notifier.fileArrived(name: saved.lastPathComponent, url: saved)
    }

    private func discard(_ download: Download) {
        try? download.handle.close()
        try? FileManager.default.removeItem(at: download.temp)
        download.entry.state = .failed
    }

    /// The phone is gone: half-received files are useless and uploads cannot be confirmed.
    private func failTransfers() {
        downloads.values.forEach(discard)
        downloads.removeAll()
        for upload in unconfirmed.values where upload.entry.state == .active { upload.entry.state = .failed }
        unconfirmed.removeAll()
        for upload in uploads + [uploading].compactMap({ $0 }) {
            upload.entry.state = .failed
            upload.finished = true
            try? upload.handle.close()
        }
        uploads.removeAll()
        uploading = nil
    }

    /// Unknown size (-1) shows as an empty bar until the end; the row redraws once per percent.
    private func showProgress(_ entry: HistoryEntry, done: Int64, of size: Int64, shown: inout Int) {
        let percent = size > 0 ? Int(min(100, done * 100 / size)) : 0
        guard percent != shown else { return }
        shown = percent
        entry.progress = Double(percent) / 100
    }

    // MARK: History and settings

    private func remember(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        if history.count > historySize { history.removeLast(history.count - historySize) }
    }

    func clearHistory() {
        history.removeAll { $0.state != .active }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = "Автозапуск: \(error.localizedDescription)"
        }
        if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func watchClipboard() {
        let count = NSPasteboard.general.changeCount
        guard count != clipboardChangeCount else { return }
        clipboardChangeCount = count
        guard autoClipboard, connected,
              let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else { return }
        sendClipboard(text)
    }

    private func randomBytes(_ length: Int) -> Data {
        var bytes = Data(count: length)
        let result = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!) }
        precondition(result == errSecSuccess)
        return bytes
    }
}
