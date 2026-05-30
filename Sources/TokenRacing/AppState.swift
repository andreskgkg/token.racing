import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var data: AppData
    @Published var selectedTimeframe: Timeframe = .today
    @Published var adapterStatuses: [CodingApp: AdapterAvailability] = [:]
    @Published var leaderboardRows: [LeaderboardRow] = []
    @Published var syncStatus: String = "Local only"
    @Published var isRefreshing = false
    @Published var apiKeyConnections: [CodingApp: Bool] = [:]

    private let store: LocalStore
    private let syncClient: SyncClient
    var onMenuBarContentChange: (([MenuBarEntry]) -> Void)?

    init(store: LocalStore = LocalStore(), syncClient: SyncClient = SyncClient()) {
        self.store = store
        self.syncClient = syncClient
        data = store.load()
        refreshAPIKeyConnections()
        rebuildLeaderboard()
    }

    var profile: UserProfile? { data.profile }
    var demoMode: Bool { data.demoMode }
    var backendURL: String { data.backendURL }
    var enabledApps: Set<CodingApp> { data.sourceSettings.enabledApps }
    var customPaths: [CodingApp: String] { data.sourceSettings.customPaths }
    var apiAccountEmails: [CodingApp: String] { data.sourceSettings.apiAccountEmails ?? [:] }

    var currentBreakdown: [CodingApp: Int] {
        breakdown(for: selectedTimeframe)
    }

    var currentTotal: Int {
        currentBreakdown.values.reduce(0, +)
    }

    var currentRank: Int? {
        leaderboardRows.first(where: { $0.isCurrentUser })?.rank
    }

    var acceptedFriends: [Friend] {
        data.friends.filter { $0.status == .accepted }
    }

    var pendingFriends: [Friend] {
        data.friends.filter { $0.status == .pending }
    }

    func createProfile(handle: String) {
        let normalized = normalizeHandle(handle)
        guard !normalized.isEmpty else { return }
        data.profile = UserProfile(handle: normalized)
        saveAndRefreshMenuTitle()
        Task { await registerAndRefresh() }
    }

    func setDemoMode(_ enabled: Bool) {
        data.demoMode = enabled
        saveAndRefreshMenuTitle()
        Task { await refreshUsage() }
    }

    func setBackendURL(_ backendURL: String) {
        data.backendURL = backendURL.trimmingCharacters(in: .whitespacesAndNewlines)
        saveAndRefreshMenuTitle()
    }

    func saveAPIConnection(app: CodingApp, apiKey: String, accountEmail: String? = nil) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }

        do {
            try ConnectionSecrets.saveAPIKey(trimmedKey, for: app)
            setAPIAccountEmail(accountEmail, for: app)
            refreshAPIKeyConnections()
            Task { await detectAdapters(); await refreshUsage() }
        } catch {
            syncStatus = error.localizedDescription
        }
    }

    func removeAPIConnection(app: CodingApp) {
        ConnectionSecrets.deleteAPIKey(for: app)
        setAPIAccountEmail(nil, for: app)
        refreshAPIKeyConnections()
        Task { await detectAdapters(); await refreshUsage() }
    }

    func setAPIAccountEmail(_ email: String?, for app: CodingApp) {
        var emails = data.sourceSettings.apiAccountEmails ?? [:]
        let normalized = email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if normalized.isEmpty {
            emails.removeValue(forKey: app)
        } else {
            emails[app] = normalized
        }
        data.sourceSettings.apiAccountEmails = emails
        saveAndRefreshMenuTitle()
    }

    func refreshAPIKeyConnections() {
        apiKeyConnections = Dictionary(uniqueKeysWithValues: CodingApp.allCases.map {
            ($0, ConnectionSecrets.hasAPIKey(for: $0))
        })
    }

    func setProfileAvatarDataURL(_ avatarDataURL: String?) {
        guard data.profile != nil else { return }
        data.profile?.avatarDataURL = avatarDataURL
        saveAndRefreshMenuTitle()
        rebuildLeaderboard()
        Task { await registerAndRefresh() }
    }

    func setAppEnabled(_ app: CodingApp, enabled: Bool) {
        if enabled {
            data.sourceSettings.enabledApps.insert(app)
        } else {
            data.sourceSettings.enabledApps.remove(app)
        }
        saveAndRefreshMenuTitle()
        Task { await refreshUsage() }
    }

    func setCustomPath(_ path: String?, for app: CodingApp) {
        if let path, !path.isEmpty {
            data.sourceSettings.customPaths[app] = path
        } else {
            data.sourceSettings.customPaths.removeValue(forKey: app)
        }
        saveAndRefreshMenuTitle()
        Task { await detectAdapters(); await refreshUsage() }
    }

    func refreshAll() async {
        await detectAdapters()
        await refreshUsage()
        await registerAndRefresh()
    }

    func detectAdapters() async {
        let adapters = makeAdapters()
        var statuses: [CodingApp: AdapterAvailability] = [:]
        for adapter in adapters {
            statuses[adapter.app] = await adapter.detectAvailability()
        }
        adapterStatuses = statuses
    }

    func refreshUsage() async {
        guard data.profile != nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let startDate = Timeframe.month.startDate()
        var events: [TokenUsageEvent] = []

        if data.demoMode, let profile = data.profile {
            events = Timeframe.allCases.flatMap { timeframe in
                DemoDataProvider.events(for: profile, since: timeframe.startDate(), timeframe: timeframe)
            }
        } else {
            for adapter in makeAdapters() where data.sourceSettings.enabledApps.contains(adapter.app) {
                do {
                    events.append(contentsOf: try await adapter.fetchUsageSince(date: startDate))
                } catch {
                    syncStatus = "\(adapter.app.shortName): \(error.localizedDescription)"
                }
            }
        }

        data.usageEvents = deduplicate(events)
        data.lastRefreshAt = Date()
        saveAndRefreshMenuTitle()
        rebuildLeaderboard()
        await syncAggregates()
    }

    func sendFriendRequest(handleOrInviteCode: String) async {
        guard let profile else { return }
        do {
            let synced = try await syncClient.sendFriendRequest(
                profile: profile,
                handleOrInviteCode: handleOrInviteCode.trimmingCharacters(in: .whitespacesAndNewlines),
                backendURL: data.backendURL
            )
            applySyncedFriends(synced)
            syncStatus = "Friend request sent"
        } catch {
            syncStatus = error.localizedDescription
        }
    }

    func respondToRequest(friend: Friend, status: FriendRequestStatus) async {
        guard let profile else { return }
        do {
            let synced = try await syncClient.respondToRequest(
                profile: profile,
                friendId: friend.id,
                status: status,
                backendURL: data.backendURL
            )
            applySyncedFriends(synced)
            syncStatus = status == .accepted ? "Friend accepted" : "Friend declined"
            await registerAndRefresh()
        } catch {
            syncStatus = error.localizedDescription
        }
    }

    func registerAndRefresh() async {
        guard let profile else { return }
        do {
            let syncedProfile = try await syncClient.upsertUser(profile: profile, backendURL: data.backendURL)
            data.profile = mergeLocalProfile(profile, with: syncedProfile)
            let friends = try await syncClient.fetchFriends(profile: syncedProfile, backendURL: data.backendURL)
            applySyncedFriends(friends)
            await syncAggregates()
            let leaderboard = try await syncClient.fetchLeaderboard(
                profile: syncedProfile,
                timeframe: selectedTimeframe,
                backendURL: data.backendURL
            )
            if !data.demoMode {
                leaderboardRows = leaderboard
                saveAndRefreshMenuTitle()
            }
            syncStatus = "Synced"
        } catch {
            syncStatus = "Backend offline: \(error.localizedDescription)"
            rebuildLeaderboard()
        }
    }

    private func mergeLocalProfile(_ localProfile: UserProfile, with syncedProfile: UserProfile) -> UserProfile {
        var merged = syncedProfile
        if merged.avatarDataURL == nil {
            merged.avatarDataURL = localProfile.avatarDataURL
        }
        return merged
    }

    func setTimeframe(_ timeframe: Timeframe) {
        selectedTimeframe = timeframe
        rebuildLeaderboard()
        Task { await registerAndRefresh() }
    }

    func resetLocalProfile() {
        data = .empty
        saveAndRefreshMenuTitle()
        rebuildLeaderboard()
    }

    private func syncAggregates() async {
        guard let profile else { return }
        do {
            try await syncClient.uploadAggregates(
                profile: profile,
                aggregates: aggregatesForSync(),
                backendURL: data.backendURL
            )
        } catch {
            syncStatus = "Aggregate sync failed: \(error.localizedDescription)"
        }
    }

    private func rebuildLeaderboard() {
        guard let profile else {
            leaderboardRows = []
            onMenuBarContentChange?([])
            return
        }

        let breakdown = self.breakdown(for: selectedTimeframe)
        if data.demoMode {
            leaderboardRows = DemoDataProvider.leaderboard(
                profile: profile,
                timeframe: selectedTimeframe,
                currentBreakdown: breakdown
            )
        } else {
            var localRows = [
                LeaderboardRow(
                    id: profile.id,
                    handle: profile.handle,
                    avatarDataURL: profile.avatarDataURL,
                    totalTokens: breakdown.values.reduce(0, +),
                    breakdown: breakdown,
                    isCurrentUser: true
                )
            ]
            for friend in acceptedFriends {
                localRows.append(
                    LeaderboardRow(
                        id: friend.id,
                        handle: friend.handle,
                        avatarDataURL: friend.avatarDataURL,
                        totalTokens: 0,
                        breakdown: [:],
                        isCurrentUser: false
                    )
                )
            }
            localRows.sort { $0.totalTokens > $1.totalTokens }
            for index in localRows.indices {
                localRows[index].rank = index + 1
            }
            leaderboardRows = localRows
        }

        saveAndRefreshMenuTitle()
    }

    private func breakdown(for timeframe: Timeframe) -> [CodingApp: Int] {
        let startDate = timeframe.startDate()
        let events = data.usageEvents.filter { $0.timestamp >= startDate }
        return Dictionary(grouping: events, by: \.app)
            .mapValues { $0.reduce(0) { $0 + $1.tokens } }
    }

    private func aggregatesForSync() -> [TokenAggregate] {
        Timeframe.allCases.flatMap { timeframe in
            let periodStart = timeframe.startDate()
            let breakdown = self.breakdown(for: timeframe)
            return CodingApp.allCases.map { app in
                TokenAggregate(
                    app: app,
                    timeframe: timeframe,
                    periodStart: periodStart,
                    tokens: breakdown[app, default: 0]
                )
            }
        }
    }

    private func makeAdapters() -> [UsageAdapter] {
        [
            CursorUsageAdapter(settings: data.sourceSettings),
            ClaudeCodeUsageAdapter(settings: data.sourceSettings),
            CodexUsageAdapter(settings: data.sourceSettings)
        ]
    }

    private func applySyncedFriends(_ syncedFriends: [SyncedFriend]) {
        data.friends = syncedFriends.map {
            Friend(
                id: $0.id,
                handle: $0.handle,
                inviteCode: $0.inviteCode,
                avatarDataURL: $0.avatarDataURL,
                status: $0.status,
                direction: $0.direction,
                createdAt: Date()
            )
        }
        saveAndRefreshMenuTitle()
        rebuildLeaderboard()
    }

    private func deduplicate(_ events: [TokenUsageEvent]) -> [TokenUsageEvent] {
        var seen = Set<String>()
        return events.filter { event in
            let key = "\(event.app.rawValue)-\(event.timestamp.timeIntervalSince1970)-\(event.tokens)-\(event.sourceDescription)"
            return seen.insert(key).inserted
        }
    }

    private func normalizeHandle(_ handle: String) -> String {
        handle
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    private func saveAndRefreshMenuTitle() {
        store.save(data)
        onMenuBarContentChange?(menuBarEntries())
    }

    private func menuBarEntries() -> [MenuBarEntry] {
        let friendRows = leaderboardRows
            .filter { !$0.isCurrentUser }
            .prefix(4)

        let rows = friendRows.isEmpty ? Array(leaderboardRows.prefix(1)) : Array(friendRows)
        if !rows.isEmpty {
            return rows.map {
                MenuBarEntry(handle: $0.handle, avatarDataURL: $0.avatarDataURL, tokens: $0.totalTokens)
            }
        }

        guard let profile else {
            return []
        }

        let todayTokens = breakdown(for: .today).values.reduce(0, +)
        return [
            MenuBarEntry(handle: profile.handle, avatarDataURL: profile.avatarDataURL, tokens: todayTokens)
        ]
    }
}
