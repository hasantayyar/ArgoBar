import Foundation

enum TokenReaderError: LocalizedError {
    case configNotFound
    case tokenNotFound
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .configNotFound:
            return "ArgoCD config not found at ~/.config/argocd/config"
        case .tokenNotFound:
            return "No auth token for this server. Run argocd login first."
        case .tokenExpired:
            return "Auth token expired. Run argocd login again."
        }
    }
}

struct TokenReader {
    private let configPath: URL
    private let skewSeconds: TimeInterval

    init(
        configPath: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/argocd/config"),
        skewSeconds: TimeInterval = 120
    ) {
        self.configPath = configPath
        self.skewSeconds = skewSeconds
    }

    func readToken(forServer serverHost: String) throws -> String {
        let token = try loadToken(forServer: serverHost)
        guard isTokenValid(token) else {
            throw TokenReaderError.tokenExpired
        }
        return token
    }

    func hasValidToken(forServer serverHost: String) -> Bool {
        guard let token = try? loadToken(forServer: serverHost) else { return false }
        return isTokenValid(token)
    }

    private func loadToken(forServer serverHost: String) throws -> String {
        guard FileManager.default.fileExists(atPath: configPath.path()) else {
            throw TokenReaderError.configNotFound
        }

        let content = try String(contentsOf: configPath, encoding: .utf8)
        if let token = ArgoCDConfigParser.token(forServer: serverHost, in: content) {
            return token
        }
        throw TokenReaderError.tokenNotFound
    }

    func isTokenValid(_ token: String) -> Bool {
        guard let exp = jwtExpirationDate(token) else { return false }
        return exp.timeIntervalSinceNow > skewSeconds
    }

    private func jwtExpirationDate(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        switch payload.count % 4 {
        case 2: payload += "=="
        case 3: payload += "="
        default: break
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let exp = json["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: exp)
        }
        if let exp = json["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }
}

enum ArgoCDConfigParser {
    /// Parses auth-token for a given server from ArgoCD CLI config YAML.
    static func token(forServer serverHost: String, in yaml: String) -> String? {
        var inUsersSection = false
        var currentBlock: [String: String] = [:]

        func flushBlock() -> String? {
            defer { currentBlock = [:] }
            guard currentBlock["name"] == serverHost,
                  let token = currentBlock["auth-token"],
                  !token.isEmpty else {
                return nil
            }
            return token
        }

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed == "users:" {
                inUsersSection = true
                currentBlock = [:]
                continue
            }

            guard inUsersSection else { continue }

            if trimmed.hasPrefix("- ") {
                if let token = flushBlock() { return token }
                currentBlock = [:]
                if let pair = parseKeyValue(from: String(trimmed.dropFirst(2))) {
                    currentBlock[pair.key] = pair.value
                }
                continue
            }

            if let pair = parseKeyValue(from: trimmed) {
                currentBlock[pair.key] = pair.value
            } else {
                if let token = flushBlock() { return token }
                break
            }
        }

        return flushBlock()
    }

    private static func parseKeyValue(from line: String) -> (key: String, value: String)? {
        guard let colonIndex = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        var value = String(line[line.index(after: colonIndex)...])
            .trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        guard !key.isEmpty, !value.isEmpty else { return nil }
        return (key, value)
    }
}
