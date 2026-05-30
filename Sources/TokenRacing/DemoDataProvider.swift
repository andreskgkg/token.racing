import Foundation

enum DemoDataProvider {
    static func events(for profile: UserProfile, since startDate: Date, timeframe: Timeframe) -> [TokenUsageEvent] {
        let seed = abs(profile.handle.hashValue % 8_000)
        let baseDate = timeframe.startDate()

        return [
            TokenUsageEvent(app: .cursor, timestamp: baseDate.addingTimeInterval(900), tokens: 18_400 + seed, sourceDescription: "Demo Mode"),
            TokenUsageEvent(app: .claudeCode, timestamp: baseDate.addingTimeInterval(1_800), tokens: 42_900 + seed * 3, sourceDescription: "Demo Mode"),
            TokenUsageEvent(app: .codex, timestamp: baseDate.addingTimeInterval(2_700), tokens: 9_700 + seed / 2, sourceDescription: "Demo Mode")
        ].filter { $0.timestamp >= startDate }
    }

    static func leaderboard(profile: UserProfile, timeframe: Timeframe, currentBreakdown: [CodingApp: Int]) -> [LeaderboardRow] {
        let multiplier: Int
        switch timeframe {
        case .today: multiplier = 1
        case .week: multiplier = 5
        case .month: multiplier = 18
        }

        var rows = [
            LeaderboardRow(
                id: profile.id,
                handle: profile.handle,
                avatarDataURL: profile.avatarDataURL,
                totalTokens: currentBreakdown.values.reduce(0, +),
                breakdown: currentBreakdown,
                isCurrentUser: true
            ),
            demoRow(handle: "maya", cursor: 18_300, claude: 83_100, codex: 7_700, multiplier: multiplier),
            demoRow(handle: "sam", cursor: 51_200, claude: 22_400, codex: 14_500, multiplier: multiplier),
            demoRow(handle: "nora", cursor: 9_900, claude: 40_200, codex: 31_800, multiplier: multiplier)
        ]

        rows.sort { $0.totalTokens > $1.totalTokens }
        for index in rows.indices {
            rows[index].rank = index + 1
        }
        return rows
    }

    private static func demoRow(handle: String, cursor: Int, claude: Int, codex: Int, multiplier: Int) -> LeaderboardRow {
        let breakdown: [CodingApp: Int] = [
            .cursor: cursor * multiplier,
            .claudeCode: claude * multiplier,
            .codex: codex * multiplier
        ]

        return LeaderboardRow(
            id: stableID(for: handle),
            handle: handle,
            avatarDataURL: nil,
            totalTokens: breakdown.values.reduce(0, +),
            breakdown: breakdown,
            isCurrentUser: false
        )
    }

    private static func stableID(for handle: String) -> UUID {
        switch handle {
        case "maya":
            return UUID(uuidString: "00000000-0000-4000-8000-000000000001") ?? UUID()
        case "sam":
            return UUID(uuidString: "00000000-0000-4000-8000-000000000002") ?? UUID()
        case "nora":
            return UUID(uuidString: "00000000-0000-4000-8000-000000000003") ?? UUID()
        default:
            return UUID()
        }
    }
}
