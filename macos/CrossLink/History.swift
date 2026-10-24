import Foundation
import CryptoKit
import UniformTypeIdentifiers

/// One line of the history: a text, a clipboard or a file that went to or came from the phone.
/// Kept in memory only: clipboard content may be a password and should not land on disk.
/// A transfer updates its own entry, so only that row redraws.
@MainActor
final class HistoryEntry: ObservableObject, Identifiable {
    enum Kind { case text, clipboard, file }
    enum State { case active, done, failed }

    let id = UUID()
    let incoming: Bool
    let kind: Kind
    /// The text itself or the file name.
    let title: String
    let size: Int64
    let date = Date()
    @Published var state: State
    /// 0...1 while a file is moving.
    @Published var progress = 0.0
    /// Where a received file was saved.
    @Published var fileURL: URL?

    init(incoming: Bool, kind: Kind, title: String, size: Int64 = -1) {
        self.incoming = incoming
        self.kind = kind
        self.title = title
        self.size = size
        state = kind == .file ? .active : .done
    }

    var isLink: Bool {
        guard kind != .file, let url = URL(string: title.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }

    var isImage: Bool { UTType(filenameExtension: (title as NSString).pathExtension)?.conforms(to: .image) ?? false }
}

/// File transfer limits shared by both directions (see PROTOCOL.md, "Files").
enum Transfers {
    /// Raw bytes per file_chunk: base64 makes it 256 KiB, well inside a 512 KiB frame.
    static let chunk = 192 * 1024
    static let maxSize: Int64 = 4 * 1024 * 1024 * 1024
    static let maxIncoming = 4

    /// The name as it will be saved: no folders, control characters or hidden-file dot.
    static func safeName(_ raw: String) -> String {
        let last = raw.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
        var base = String(last.unicodeScalars.filter { $0.value >= 0x20 && $0 != ":" })
            .trimmingCharacters(in: .whitespaces)
        while base.hasPrefix(".") { base.removeFirst() }
        if base.isEmpty { return "file" }
        guard base.count > 120 else { return base }
        let ext = (base as NSString).pathExtension
        let suffix = !ext.isEmpty && ext.count < 16 ? "." + ext : ""
        return String(base.prefix(120 - suffix.count)) + suffix
    }

    static func mime(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }

    /// ~/Downloads/name, or "name 2.ext", "name 3.ext"… like Safari when the name is taken.
    static func downloadURL(for name: String) -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)")
            number += 1
        }
        return candidate
    }

    static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    static func newID() -> String {
        (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    static func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
