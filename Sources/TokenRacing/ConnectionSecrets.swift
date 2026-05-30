import Foundation

enum ConnectionSecrets {
    static let service = "TokenRacing.APIKeys"

    static func account(for app: CodingApp) -> String {
        switch app {
        case .cursor:
            return "cursor-admin-api-key"
        case .claudeCode:
            return "claude-code-api-key"
        case .codex:
            return "codex-openai-api-key"
        }
    }

    static func hasAPIKey(for app: CodingApp) -> Bool {
        ((try? KeychainStore.read(service: service, account: account(for: app))) ?? nil)?.isEmpty == false
    }

    static func apiKey(for app: CodingApp) -> String? {
        guard let key = try? KeychainStore.read(service: service, account: account(for: app)),
              !key.isEmpty else {
            return nil
        }
        return key
    }

    static func saveAPIKey(_ key: String, for app: CodingApp) throws {
        try KeychainStore.save(service: service, account: account(for: app), secret: key)
    }

    static func deleteAPIKey(for app: CodingApp) {
        KeychainStore.delete(service: service, account: account(for: app))
    }
}
