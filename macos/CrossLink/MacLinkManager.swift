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
    @Published private(set) var receivedText = ""
    @Published var autoClipboard = UserDefaults.standard.bool(forKey: "autoClipboard") {
        didSet { UserDefaults.standard.set(autoClipboard, forKey: "autoClipboard") }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let port: UInt16 = 48321
    private var secret = Pairing.storedSecret()
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

    var pairURL: String { Pairing.connectionURL(host: hostIP, port: port, secret: secret) }
    private var waitingStatus: String { hostIP.isEmpty ? "Нет локального IP" : "Ожидание Android · \(hostIP):\(port)" }

    init() {
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
        notifier.requestPermission()
        restart()
    }

    func resetPairing() {
        disconnectClient()
        Pairing.forgetSecret()
        secret = Pairing.storedSecret()
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
        else if peer === active { active = nil }
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
        _ = sendEncrypted(type: "bye", text: "", to: active)
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
                if peer.buffer.count > self.maxFrame + 4 { self.drop(peer); return }
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
            receivedText = String(text.prefix(20000))
            notifier.textArrived(receivedText)
        case "clipboard":
            let clipped = String(text.prefix(20000))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clipped, forType: .string)
            clipboardChangeCount = NSPasteboard.general.changeCount  // Prevent feedback loops
            receivedText = clipped
            notifier.clipboardArrived(characters: clipped.count)
        case "ping": return sendEncrypted(type: "pong", text: "", to: peer)
        case "pong": break
        default: return false
        }
        return true
    }

    private func sendPlain(_ object: [String: Any], to peer: Peer) {
        guard let raw = try? JSONSerialization.data(withJSONObject: object) else { return }
        writeFrame(raw, to: peer)
    }

    @discardableResult
    private func sendEncrypted(type: String, text: String, to target: Peer? = nil) -> Bool {
        guard let peer = target ?? active, let sendKey = peer.sendKey, text.utf8.count <= 20000 else { return false }
        peer.sendSequence += 1
        let obj: [String: Any] = ["type": type, "seq": peer.sendSequence, "text": text]
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let sealed = try? AES.GCM.seal(data, using: sendKey),
              let frame = sealed.combined else { return false }
        writeFrame(frame, to: peer)
        return true
    }

    private func writeFrame(_ data: Data, to peer: Peer) {
        var length = UInt32(data.count).bigEndian
        var framed = withUnsafeBytes(of: &length) { Data($0) }
        framed.append(data)
        peer.connection.send(content: framed, completion: .contentProcessed { [weak self, weak peer] error in
            MainActor.assumeIsolated {
                if error != nil, let self, let peer { self.drop(peer) }
            }
        })
    }

    func sendText(_ text: String) { _ = sendEncrypted(type: "text", text: text) }

    func sendCurrentClipboard() {
        guard let str = NSPasteboard.general.string(forType: .string) else { return }
        _ = sendEncrypted(type: "clipboard", text: str)
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
        _ = sendEncrypted(type: "clipboard", text: text)
    }

    private func randomBytes(_ length: Int) -> Data {
        var bytes = Data(count: length)
        let result = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!) }
        precondition(result == errSecSuccess)
        return bytes
    }
}
