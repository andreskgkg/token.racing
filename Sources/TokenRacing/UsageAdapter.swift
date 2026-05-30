import Foundation

protocol UsageAdapter {
    var app: CodingApp { get }
    func detectAvailability() async -> AdapterAvailability
    func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent]
    func explainDataSource() -> String
}

enum UsageAdapterError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return message
        }
    }
}

final class CursorUsageAdapter: UsageAdapter {
    let app: CodingApp = .cursor
    private let settings: UsageSourceSettings
    private let session: URLSession

    init(settings: UsageSourceSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func detectAvailability() async -> AdapterAvailability {
        let paths = candidatePaths()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        let hasAPIKey = ConnectionSecrets.hasAPIKey(for: app)
        let message: String
        if hasAPIKey {
            message = "Connected with Cursor Admin API. API key is stored only in macOS Keychain."
        } else {
            message = "Connect a Cursor Enterprise/Admin API key to fetch exact token usage locally. Personal Cursor accounts do not currently expose a token API."
        }

        return AdapterAvailability(
            app: app,
            isAvailable: hasAPIKey,
            isExact: hasAPIKey,
            message: message,
            detectedPaths: existing
        )
    }

    func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent] {
        guard let apiKey = ConnectionSecrets.apiKey(for: app) else {
            return []
        }

        return try await fetchCursorUsageSince(date: date, apiKey: apiKey)
    }

    func explainDataSource() -> String {
        "Cursor connects through the Cursor Admin API when the user provides an Enterprise/Admin API key. The key stays in macOS Keychain; Token Racing syncs only aggregate token counts."
    }

    private func candidatePaths() -> [String] {
        [
            "~/Library/Application Support/Cursor/User/globalStorage",
            "~/Library/Application Support/Cursor/logs",
            "~/.cursor"
        ].map { ($0 as NSString).expandingTildeInPath }
    }

    private func fetchCursorUsageSince(date: Date, apiKey: String) async throws -> [TokenUsageEvent] {
        let pageSize = 25
        let finalEndDate = Date()
        var events: [TokenUsageEvent] = []
        var windowStartDate = date

        while windowStartDate <= finalEndDate {
            let windowEndDate = min(
                windowStartDate.addingTimeInterval(29 * 24 * 60 * 60),
                finalEndDate
            )
            events.append(contentsOf: try await fetchCursorUsageWindow(
                startDate: windowStartDate,
                endDate: windowEndDate,
                apiKey: apiKey,
                pageSize: pageSize
            ))

            guard windowEndDate < finalEndDate else { break }
            windowStartDate = windowEndDate.addingTimeInterval(0.001)
        }

        return events
    }

    private func fetchCursorUsageWindow(
        startDate: Date,
        endDate: Date,
        apiKey: String,
        pageSize: Int
    ) async throws -> [TokenUsageEvent] {
        var page = 1
        var hasNextPage = true
        var events: [TokenUsageEvent] = []

        while hasNextPage, page <= 100 {
            let result = try await fetchCursorUsagePage(
                startDate: startDate,
                endDate: endDate,
                apiKey: apiKey,
                page: page,
                pageSize: pageSize
            )
            events.append(contentsOf: result.events)
            hasNextPage = result.hasNextPage
            page += 1
        }

        return events
    }

    private func fetchCursorUsagePage(
        startDate: Date,
        endDate: Date,
        apiKey: String,
        page: Int,
        pageSize: Int
    ) async throws -> CursorUsagePage {
        guard let url = URL(string: "https://api.cursor.com/teams/filtered-usage-events") else {
            return CursorUsagePage(events: [], hasNextPage: false)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let auth = Data("\(apiKey):".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")

        let email = settings.apiAccountEmails?[app]
        var body: [String: Any] = [
            "startDate": Int(startDate.timeIntervalSince1970 * 1000),
            "endDate": Int(endDate.timeIntervalSince1970 * 1000),
            "page": page,
            "pageSize": pageSize
        ]
        if let email, !email.isEmpty {
            body["email"] = email
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            throw UsageAdapterError.unavailable(cursorAPIErrorMessage(statusCode: statusCode, data: data))
        }

        let value = try JSONSerialization.jsonObject(with: data)
        guard let root = value as? [String: Any],
              let usageEvents = root["usageEvents"] as? [[String: Any]] else {
            return CursorUsagePage(events: [], hasNextPage: false)
        }

        let events: [TokenUsageEvent] = usageEvents.compactMap { event in
            guard let tokenUsage = event["tokenUsage"] as? [String: Any] else {
                return nil
            }

            let explicitTotal = intValue(tokenUsage["totalTokens"])
            let componentTotal = [
                "inputTokens",
                "outputTokens",
                "cacheWriteTokens",
                "cacheReadTokens"
            ].reduce(0) { partial, key in partial + intValue(tokenUsage[key]) }
            let tokens = explicitTotal > 0 ? explicitTotal : componentTotal
            guard tokens > 0 else { return nil }

            let timestamp = dateValue(event["timestamp"]) ?? Date()
            guard timestamp >= startDate else { return nil }

            return TokenUsageEvent(
                app: app,
                timestamp: timestamp,
                tokens: tokens,
                sourceDescription: explainDataSource()
            )
        }

        let pagination = root["pagination"] as? [String: Any]
        let hasNextPage = boolValue(pagination?["hasNextPage"])
            ?? (intValue(pagination?["currentPage"]) < intValue(pagination?["numPages"]))
        return CursorUsagePage(events: events, hasNextPage: hasNextPage)
    }

    private func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            switch string.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private func cursorAPIErrorMessage(statusCode: Int?, data: Data) -> String {
        let fallback = "Cursor API failed. Check that your key is a Cursor Admin API key for a team account, then try again."
        let statusPrefix = statusCode.map { "HTTP \($0)" } ?? "No HTTP status"

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let body = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let body, !body.isEmpty {
                return "Cursor API failed (\(statusPrefix)): \(body)"
            }
            return "\(fallback) (\(statusPrefix))."
        }

        let code = (root["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawMessage = (root["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let genericInternalError = code == "internal" && (rawMessage == nil || rawMessage == "Error")

        if statusCode == 401 || statusCode == 403 {
            return "Cursor API rejected the key (\(statusPrefix)). Use a Cursor team Admin API key, not a personal account key."
        }

        if genericInternalError {
            return "Cursor API returned a temporary internal error (\(statusPrefix)). Try Refresh again; if it keeps happening, verify the Admin API key has team access and remove the optional email filter."
        }

        let details = [code, rawMessage]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ": ")

        if details.isEmpty {
            return "\(fallback) (\(statusPrefix))."
        }

        return "Cursor API failed (\(statusPrefix)): \(details)"
    }

    private func dateValue(_ value: Any?) -> Date? {
        if let string = value as? String, let milliseconds = TimeInterval(string) {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        if let number = value as? TimeInterval {
            return Date(timeIntervalSince1970: number / 1000)
        }
        return nil
    }

    private struct CursorUsagePage {
        var events: [TokenUsageEvent]
        var hasNextPage: Bool
    }
}

final class ClaudeCodeUsageAdapter: UsageAdapter {
    let app: CodingApp = .claudeCode
    private let settings: UsageSourceSettings

    init(settings: UsageSourceSettings) {
        self.settings = settings
    }

    func detectAvailability() async -> AdapterAvailability {
        let paths = candidatePaths()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        let hasDefaultProjectPath = existing.contains(where: { $0.hasSuffix("/.claude/projects") })
        let message: String
        if existing.isEmpty {
            message = "Claude Code local project logs were not detected."
        } else {
            message = "Auto-connected to Claude Code local logs. No upload or file selection needed."
        }

        return AdapterAvailability(
            app: app,
            isAvailable: !existing.isEmpty,
            isExact: hasDefaultProjectPath,
            message: message,
            detectedPaths: existing
        )
    }

    func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent] {
        let path = defaultProjectPath()
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }
        return try UsageLogParser(app: app, sourceDescription: explainDataSource()).events(since: date, atPath: path)
    }

    func explainDataSource() -> String {
        "Claude Code auto-scans ~/.claude/projects on this Mac for explicit token fields. Prompts, file names, code, and raw logs are not stored or synced."
    }

    private func defaultProjectPath() -> String {
        ("~/.claude/projects" as NSString).expandingTildeInPath
    }

    private func candidatePaths() -> [String] {
        [
            "~/.claude/projects",
            "~/.claude"
        ].map { ($0 as NSString).expandingTildeInPath }
    }
}

final class CodexUsageAdapter: UsageAdapter {
    let app: CodingApp = .codex
    private let settings: UsageSourceSettings

    init(settings: UsageSourceSettings) {
        self.settings = settings
    }

    func detectAvailability() async -> AdapterAvailability {
        let paths = candidatePaths()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        let message: String
        if existing.isEmpty {
            message = "Codex local sessions were not detected."
        } else {
            message = "Auto-connected to Codex local sessions. No upload or file selection needed."
        }

        return AdapterAvailability(
            app: app,
            isAvailable: !existing.isEmpty,
            isExact: existing.contains(where: { $0.hasSuffix("/.codex/sessions") }),
            message: message,
            detectedPaths: existing
        )
    }

    func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent] {
        guard let path = defaultSessionsPath() else {
            return []
        }
        return try UsageLogParser(app: app, sourceDescription: explainDataSource()).events(since: date, atPath: path)
    }

    func explainDataSource() -> String {
        "Codex auto-scans local ~/.codex/sessions logs for explicit token usage events. No raw logs leave this Mac."
    }

    private func defaultSessionsPath() -> String? {
        let sessions = ("~/.codex/sessions" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: sessions) {
            return sessions
        }
        let codex = ("~/.codex" as NSString).expandingTildeInPath
        return FileManager.default.fileExists(atPath: codex) ? codex : nil
    }

    private func candidatePaths() -> [String] {
        [
            "~/.codex/sessions",
            "~/.codex",
            "~/.config/openai",
            "~/Library/Application Support/OpenAI"
        ].map { ($0 as NSString).expandingTildeInPath }
    }
}
