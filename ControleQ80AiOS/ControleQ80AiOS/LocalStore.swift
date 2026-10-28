import Foundation
import Security

struct TVSettings: Codable {
    var ip: String
    var spotifyID: String
    var youtubeID: String
    var netflixID: String

    static let initial = TVSettings(
        ip: "",
        spotifyID: "201606009684",
        youtubeID: "111299001912",
        netflixID: "3201907018807"
    )
}

enum LocalStore {
    private static func directory() throws -> URL {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ControleQ80A", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }

    static func load() -> TVSettings {
        guard let folder = try? directory(),
              let data = try? Data(contentsOf: folder.appendingPathComponent("settings.json")),
              let settings = try? JSONDecoder().decode(TVSettings.self, from: data) else {
            return .initial
        }
        return settings
    }

    static func save(_ settings: TVSettings) throws {
        let url = try directory().appendingPathComponent("settings.json")
        try JSONEncoder().encode(settings).write(to: url, options: .atomic)
        var file = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }
}

enum PairingStore {
    private static let tokenService = "br.com.wesley.controleq80a.ios.token"
    private static let certificateService = "br.com.wesley.controleq80a.ios.certificate"

    private static func query(service: String, ip: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: ip]
    }

    private static func load(service: String, ip: String) -> String? {
        var request = query(service: service, ip: ip)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func save(_ value: String, service: String, ip: String) -> Bool {
        let request = query(service: service, ip: ip)
        SecItemDelete(request as CFDictionary)
        var item = request
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private static func remove(service: String, ip: String) {
        SecItemDelete(query(service: service, ip: ip) as CFDictionary)
    }

    static func token(for ip: String) -> String? { load(service: tokenService, ip: ip) }
    static func certificatePin(for ip: String) -> String? { load(service: certificateService, ip: ip) }
    @discardableResult static func saveToken(_ token: String, for ip: String) -> Bool {
        save(token, service: tokenService, ip: ip)
    }
    @discardableResult static func saveCertificatePin(_ pin: String, for ip: String) -> Bool {
        save(pin, service: certificateService, ip: ip)
    }
    static func clear(for ip: String) {
        remove(service: tokenService, ip: ip)
        remove(service: certificateService, ip: ip)
    }
}
