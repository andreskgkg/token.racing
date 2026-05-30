import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if state.profile == nil {
                OnboardingView()
            } else {
                DashboardView()
            }
        }
        .frame(width: 400, height: 600)
        .background(AppBackground())
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var handle = ""
    @State private var demoMode = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                AppMark()
                Text("Token Racing")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("A tiny private leaderboard for AI coding token usage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            CleanCard {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledFieldTitle(number: "1", title: "Pick a handle")
                    TextField("andres", text: $handle)
                        .textFieldStyle(.roundedBorder)

                    LabeledFieldTitle(number: "2", title: "Connect apps")
                    ForEach(CodingApp.allCases) { app in
                        Toggle(app.rawValue, isOn: Binding(
                            get: { state.enabledApps.contains(app) },
                            set: { state.setAppEnabled(app, enabled: $0) }
                        ))
                    }

                    LabeledFieldTitle(number: "3", title: "Privacy")
                    Text("Raw logs and API keys stay on this Mac. Friends only see aggregate token counts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle("Demo Mode", isOn: $demoMode)
                        .help("Shows clearly marked sample leaderboard rows until local usage is connected.")
                }
            }

            Spacer()

            Button {
                state.createProfile(handle: handle)
                state.setDemoMode(demoMode)
            } label: {
                Text("Start Tracking")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(22)
        .task {
            demoMode = state.demoMode
            await state.detectAdapters()
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @State private var friendInput = ""
    @State private var copiedInvite = false
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Timeframe", selection: Binding(
                get: { state.selectedTimeframe },
                set: { state.setTimeframe($0) }
            )) {
                ForEach(Timeframe.allCases) { timeframe in
                    Text(timeframe.rawValue).tag(timeframe)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    CurrentUserCard()
                    LeaderboardCard()
                    FriendsCard(friendInput: $friendInput)
                    PrivacyCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }

            footer
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(state)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let profile = state.profile {
                AvatarView(handle: profile.handle, avatarDataURL: profile.avatarDataURL, size: 38)
            } else {
                AppMark()
            }

            VStack(alignment: .leading, spacing: 3) {
                if let profile = state.profile {
                    Text("@\(profile.handle)")
                        .font(.headline)

                    Button {
                        copyInviteCode(profile.inviteCode)
                    } label: {
                        Text(copiedInvite ? "invite copied" : "click to invite friends")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func copyInviteCode(_ inviteCode: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(inviteCode, forType: .string)
        copiedInvite = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            copiedInvite = false
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.syncStatus == "Synced" ? Color.green : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)

            Text(state.syncStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            Button {
                Task { await state.refreshAll() }
            } label: {
                if state.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct CurrentUserCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        CleanCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(state.selectedTimeframe.rawValue)'s Tokens")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(state.currentTotal.exactTokenString)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 5) {
                        Text("Rank")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(state.currentRank.map { "#\($0)" } ?? "-")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }
}

struct BreakdownCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        CleanCard(title: "Breakdown") {
            VStack(spacing: 12) {
                ForEach(CodingApp.allCases) { app in
                    AppBreakdownRow(
                        app: app,
                        tokens: state.currentBreakdown[app, default: 0],
                        total: max(state.currentTotal, 1)
                    )
                }
            }
        }
    }
}

struct AppBreakdownRow: View {
    let app: CodingApp
    let tokens: Int
    let total: Int

    private var progress: Double {
        min(1, Double(tokens) / Double(total))
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(app.rawValue)
                    .font(.callout)
                Spacer()
                Text(tokens.exactTokenString)
                    .font(.callout.weight(.semibold).monospacedDigit())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: max(4, geometry.size.width * progress))
                }
            }
            .frame(height: 6)
        }
    }
}

struct LeaderboardCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        CleanCard(title: "Leaderboard") {
            if state.leaderboardRows.isEmpty {
                Text("No leaderboard rows yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.leaderboardRows) { row in
                        LeaderboardRowView(row: row)
                    }
                }
            }
        }
    }
}

struct LeaderboardRowView: View {
    let row: LeaderboardRow

    var body: some View {
        HStack(spacing: 11) {
            AvatarView(handle: row.handle, avatarDataURL: row.avatarDataURL, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("#\(row.rank)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(row.isCurrentUser ? Color.accentColor : Color.secondary)
                    Text(displayName)
                        .font(.callout.weight(row.isCurrentUser ? .bold : .semibold))
                }
                Text(appSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(row.totalTokens.tokenAbbreviation)
                .font(.callout.weight(.bold).monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(row.isCurrentUser ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var appSummary: String {
        CodingApp.allCases
            .map { "\($0.shortName) \(row.breakdown[$0, default: 0].tokenAbbreviation)" }
            .joined(separator: " / ")
    }

    private var displayName: String {
        row.handle.contains(" ") ? row.handle : "@\(row.handle)"
    }
}

struct FriendsCard: View {
    @EnvironmentObject private var state: AppState
    @Binding var friendInput: String

    var body: some View {
        CleanCard(title: "Friends") {
            if let profile = state.profile {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Invite")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(profile.inviteCode)
                            .font(.callout.monospaced().bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.secondary.opacity(0.10), in: Capsule())
                    }

                    HStack(spacing: 8) {
                        TextField("Handle or share code", text: $friendInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            Task {
                                await state.sendFriendRequest(handleOrInviteCode: friendInput)
                                friendInput = ""
                            }
                        }
                        .disabled(friendInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !state.pendingFriends.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(state.pendingFriends) { friend in
                                FriendRequestRow(friend: friend)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct FriendRequestRow: View {
    @EnvironmentObject private var state: AppState
    let friend: Friend

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(friend.handle)")
                    .font(.callout.weight(.semibold))
                Text(friend.direction == .inbound ? "Incoming request" : "Pending")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if friend.direction == .inbound {
                Button("Accept") {
                    Task { await state.respondToRequest(friend: friend, status: .accepted) }
                }
                Button("Decline") {
                    Task { await state.respondToRequest(friend: friend, status: .declined) }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PrivacyCard: View {
    var body: some View {
        CleanCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield")
                    .foregroundStyle(Color.accentColor)
                Text("Only aggregate token counts sync. Prompts, code, file names, API keys, and raw logs stay local.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CleanCard<Content: View>: View {
    private let title: String?
    private let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

struct LabeledFieldTitle: View {
    let number: String
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
            Text(title)
                .font(.headline)
        }
    }
}

struct AppMark: View {
    var body: some View {
        Text("🏁")
            .font(.system(size: 18))
            .frame(width: 38, height: 38)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
    }
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.10),
                    Color.clear,
                    Color.secondary.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}
