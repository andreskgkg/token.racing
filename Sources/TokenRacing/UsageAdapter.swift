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

    init(settings: UsageSourceSettings) {
        self.settings = settings
    }

    func detectAvailability() async -> AdapterAvailability {
        let paths = candidatePaths()
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        let hasCustomPath = settings.customPaths[app].map { FileManager.default.fileExists(atPath: $0) } ?? false
        let message: String
        if hasCustomPath {
            message = "Using user-selected local Cursor usage/log file."
        } else {
            message = "Cursor local support folders were detected, but the exact token ledger is not standardized. Select a local usage/log file to enable extraction."
        }

        return AdapterAvailability(
            app: app,
            isAvailable: hasCustomPath || !existing.isEmpty,
            isExact: hasCustomPath,
            message: message,
            detectedPaths: existing
        )
    }

    func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent] {
        guard let path = settings.customPaths[app] else {
            return []
        }
        return try UsageLogParser(app: app, sourceDescription: explainDataSource()).events(since: date, atPath: path)
    }

    func explainDataSource() -> String {
        "Cursor adapter reads only local files. Because Cursor's exact token accounting file is not public/stable, MVP extraction requires a user-selected local JSON, JSONL, or log file containing token counts."
    }

    private func candidatePaths() -> [String] {
        [
            "~/Library/Application Support/Cursor/User/globalStorage",
            "~/Library/Application Support/Cursor/logs",
            "~/.cursor"
        ].map { ($0 as NSString).expandingTildeInPath }
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
        let hasCustomPath = settings.customPaths[app].map { FileManager.default.fileExists(atPath: $0) } ?? false
        let hasDefaultProjectPath = existing.contains(where: { $0.hasSuffix("/.claude/projects") })
        let message: String
        if hasCustomPath {
            message = "Using user-selected local Claude Code usage/log file."
        } else if existing.isEmpty {
            message = "Claude Code local project logs were not detected."
        } else {
            message = "Claude Code project logs were detected and will be scanned locally for explicit token usage fields."
        }

        return AdapterAvailability(
            app: app,
            isAvailable: hasCustomPath || !existing.isEmpty,
            isExact: hasCustomPath || hasDefaultProjectPath,
            message: message,
            detectedPaths: existing
        )
    }

    func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent] {
        let path = settings.customPaths[app] ?? defaultProjectPath()
        guard FileManager.default.fileExists(atPath: path) else {
            return []
        }
        return try UsageLogParser(app: app, sourceDescription: explainDataSource()).events(since: date, atPath: path)
    }

    func explainDataSource() -> String {
        "Claude Code adapter scans local ~/.claude project JSONL/JSON files for explicit token fields such as input_tokens, output_tokens, cache tokens, prompt_tokens, completion_tokens, or total_tokens. Prompts, file names, code, and raw logs are not stored or synced."
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
        let hasCustomPath = settings.customPaths[app].map { FileManager.default.fileExists(atPath: $0) } ?? false
        let message: String
        if hasCustomPath {
            message = "Using user-selected local Codex/OpenAI Codex usage/log file."
        } else {
            message = "Codex local folders were detected if installed, but exact token accounting varies by version. Select a local usage/log file to enable extraction."
        }

        return AdapterAvailability(
            app: app,
            isAvailable: hasCustomPath || !existing.isEmpty,
            isExact: hasCustomPath,
            message: message,
            detectedPaths: existing
        )
    }

    func fetchUsageSince(date: Date) async throws -> [TokenUsageEvent] {
        guard let path = settings.customPaths[app] else {
            return []
        }
        return try UsageLogParser(app: app, sourceDescription: explainDataSource()).events(since: date, atPath: path)
    }

    func explainDataSource() -> String {
        "Codex adapter reads only local files. MVP extraction requires a user-selected local JSON, JSONL, or log file containing token counts until Codex's local usage schema is confirmed."
    }

    private func candidatePaths() -> [String] {
        [
            "~/.codex",
            "~/.config/openai",
            "~/Library/Application Support/OpenAI"
        ].map { ($0 as NSString).expandingTildeInPath }
    }
}
