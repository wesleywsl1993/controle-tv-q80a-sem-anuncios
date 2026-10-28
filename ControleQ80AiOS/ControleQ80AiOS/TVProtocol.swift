import Foundation

struct TVApp: Identifiable, Hashable {
    let id: String
    let name: String
}

enum TVProtocol {
    static func isPrivateIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let bytes = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 3,
                  part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                  let number = Int(part), (0...255).contains(number) else { return nil }
            return number
        }
        guard bytes.count == 4 else { return false }
        return bytes[0] == 10 ||
            (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
            (bytes[0] == 192 && bytes[1] == 168)
    }

    static func isValidAppID(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...80).contains(bytes.count) && bytes.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) ||
            (97...122).contains($0) || [45, 46, 95].contains($0)
        }
    }

    static func webSocketURL(ip: String, token: String?) -> URL? {
        guard isPrivateIPv4(ip) else { return nil }
        var parts = URLComponents()
        parts.scheme = "wss"
        parts.host = ip
        parts.port = 8002
        parts.path = "/api/v2/channels/samsung.remote.control"
        var items = [URLQueryItem(name: "name", value: Data("Controle Q80A iOS".utf8).base64EncodedString())]
        if let token, !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        parts.queryItems = items
        return parts.url
    }

    static func appURL(ip: String, id: String) -> URL? {
        guard isPrivateIPv4(ip), isValidAppID(id) else { return nil }
        var parts = URLComponents()
        parts.scheme = "http"
        parts.host = ip
        parts.port = 8001
        parts.path = "/api/v2/applications/\(id)"
        return parts.url
    }

    private static func encode(_ value: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func key(_ value: String) -> String? {
        encode(["method": "ms.remote.control",
                "params": ["Cmd": "Click", "DataOfCmd": value,
                           "Option": "false", "TypeOfRemote": "SendRemoteKey"]])
    }

    static func text(_ value: String) -> String? {
        encode(["method": "ms.remote.control",
                "params": ["Cmd": Data(value.utf8).base64EncodedString(),
                           "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"]])
    }

    static func appListRequest() -> String? {
        encode(["method": "ms.channel.emit",
                "params": ["event": "ed.installedApp.get", "to": "host"]])
    }
}
