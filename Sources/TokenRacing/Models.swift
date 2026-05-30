import Foundation

enum CodingApp: String, Codable, CaseIterable, Identifiable {
    case cursor = "Cursor"
    case claudeCode = "Claude Code"
    case codex = "Codex"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .cursor: return "Cursor"
        case .claudeCode: return "Claude"
        case .codex: return "Codex"
        }
    }
}

enum Timeframe: String, Codable, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .today:
            return calendar.startOfDay(for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
        }
    }
}

struct UserProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var handle: String
    var inviteCode: String
    var avatarDataURL: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        handle: String,
        inviteCode: String = InviteCode.generate(),
        avatarDataURL: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.handle = handle
        self.inviteCode = inviteCode
        self.avatarDataURL = avatarDataURL
        self.createdAt = createdAt
    }
}

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case declined
}

struct Friend: Codable, Identifiable, Equatable {
    var id: UUID
    var handle: String
    var inviteCode: String?
    var avatarDataURL: String? = nil
    var status: FriendRequestStatus
    var direction: FriendRequestDirection
    var createdAt: Date
}

enum FriendRequestDirection: String, Codable {
    case inbound
    case outbound
}

struct TokenUsageEvent: Codable, Identifiable, Equatable {
    var id: UUID
    var app: CodingApp
    var timestamp: Date
    var tokens: Int
    var sourceDescription: String

    init(id: UUID = UUID(), app: CodingApp, timestamp: Date, tokens: Int, sourceDescription: String) {
        self.id = id
        self.app = app
        self.timestamp = timestamp
        self.tokens = tokens
        self.sourceDescription = sourceDescription
    }
}

struct TokenAggregate: Codable, Identifiable, Equatable {
    var id: String { "\(app.rawValue)-\(timeframe.rawValue)-\(periodStart.timeIntervalSince1970)" }
    var app: CodingApp
    var timeframe: Timeframe
    var periodStart: Date
    var tokens: Int
}

struct LeaderboardRow: Codable, Identifiable, Equatable {
    var id: UUID
    var handle: String
    var avatarDataURL: String? = nil
    var totalTokens: Int
    var breakdown: [CodingApp: Int]
    var isCurrentUser: Bool

    var rankDisplay: String { "#\(rank)" }
    var rank: Int = 0
}

struct MenuBarEntry: Equatable {
    var handle: String
    var avatarDataURL: String?
    var tokens: Int
}

struct AdapterAvailability: Codable, Equatable {
    var app: CodingApp
    var isAvailable: Bool
    var isExact: Bool
    var message: String
    var detectedPaths: [String]
}

struct UsageSourceSettings: Codable, Equatable {
    var enabledApps: Set<CodingApp>
    var customPaths: [CodingApp: String]
    var apiAccountEmails: [CodingApp: String]?

    static let empty = UsageSourceSettings(
        enabledApps: Set(CodingApp.allCases),
        customPaths: [:],
        apiAccountEmails: [:]
    )
}

struct AppData: Codable {
    static let defaultBackendURL = "https://token.racing/api"

    var profile: UserProfile?
    var friends: [Friend]
    var usageEvents: [TokenUsageEvent]
    var sourceSettings: UsageSourceSettings
    var demoMode: Bool
    var backendURL: String
    var lastRefreshAt: Date?

    static let empty = AppData(
        profile: nil,
        friends: [],
        usageEvents: [],
        sourceSettings: .empty,
        demoMode: true,
        backendURL: defaultBackendURL,
        lastRefreshAt: nil
    )
}

enum InviteCode {
    static func generate() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in alphabet.randomElement() ?? "R" })
    }
}

extension Int {
    var tokenAbbreviation: String {
        if self >= 1_000_000 {
            return String(format: "%.1fM", Double(self) / 1_000_000)
        }
        if self >= 1_000 {
            return String(format: "%.1fK", Double(self) / 1_000)
        }
        return "\(self)"
    }

    var exactTokenString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}
