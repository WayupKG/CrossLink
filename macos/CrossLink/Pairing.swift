import Foundation
import Security
import Darwin
import CryptoKit

struct Pairing {
    static let bonjourType = "_crosslink._tcp"

    /// Public Bonjour tag of this pairing: the phone recognises its Mac by it without the secret leaking.
    static func discoveryID(secret: Data) -> String {
        let tag = HMAC<SHA256>.authenticationCode(for: Data("crosslink/v1/discovery".utf8), using: SymmetricKey(data: secret))
        return Data(tag).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// The saved pairing key, or a new one when there is none. Nil when the Keychain refused access
    /// (the owner pressed "Deny" for a rebuilt app): the saved key must survive that, not be replaced.
    static func storedSecret() -> Data? {
        let service = "kg.crosslink.pairing.v1"
        let account = "local-device"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let found = SecItemCopyMatching(query as CFDictionary, &result)
        if found == errSecSuccess, let existing = result as? Data, existing.count == 32 {
            return existing
        }
        guard found == errSecSuccess || found == errSecItemNotFound else { return nil }
        let secret = randomSecret()
        let saveQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: secret
        ]
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        precondition(SecItemAdd(saveQuery as CFDictionary, nil) == errSecSuccess, "Cannot store pairing key")
        return secret
    }

    static func randomSecret() -> Data {
        var secret = Data(count: 32)
        let rc = secret.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
        }
        precondition(rc == errSecSuccess, "Secure random generator failed")
        return secret
    }

    static func forgetSecret() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "kg.crosslink.pairing.v1",
            kSecAttrAccount as String: "local-device"
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func localIPv4() -> String? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let start = addresses else { return nil }
        defer { freeifaddrs(addresses) }
        var current: UnsafeMutablePointer<ifaddrs>? = start
        var candidates: [(String, String)] = []
        while let item = current {
            let entry = item.pointee
            if let addr = entry.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) {
                let name = String(cString: entry.ifa_name)
                var ipv4 = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: buffer)
                    if !ip.hasPrefix("127.") && !ip.hasPrefix("169.254.") {
                        candidates.append((name, ip))
                    }
                }
            }
            current = entry.ifa_next
        }
        return candidates.first(where: { $0.0 == "en0" })?.1 ?? candidates.first?.1
    }

    static func connectionURL(host: String, port: UInt16, secret: Data) -> String {
        var parts = URLComponents()
        parts.scheme = "crosslink"
        parts.host = "pair"
        parts.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
            URLQueryItem(name: "key", value: secret.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""))
        ]
        return parts.url!.absoluteString
    }
}
