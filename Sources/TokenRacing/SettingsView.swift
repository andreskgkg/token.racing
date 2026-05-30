import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var backendURL = ""
    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ProfilePictureSection()

                    Toggle("Demo Mode", isOn: Binding(
                        get: { state.demoMode },
                        set: { state.setDemoMode($0) }
                    ))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backend")
                            .font(.headline)
                        TextField(AppData.defaultBackendURL, text: $backendURL)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                state.setBackendURL(backendURL)
                                Task { await state.registerAndRefresh() }
                            }
                        Text("The backend receives handles, friend requests, and aggregate token counts only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Usage Sources")
                            .font(.headline)
                        ForEach(CodingApp.allCases) { app in
                            UsageSourceRow(app: app)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected Sources")
                            .font(.headline)
                        ForEach(CodingApp.allCases) { app in
                            let status = state.adapterStatuses[app]
                            VStack(alignment: .leading, spacing: 4) {
                                Text(app.rawValue)
                                    .fontWeight(.semibold)
                                Text(status?.message ?? "Not checked yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(status?.detectedPaths ?? [], id: \.self) { path in
                                    Text(path)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Button("Reset Local Profile", role: .destructive) {
                        showResetConfirmation = true
                    }
                }
                .padding()
            }
        }
        .frame(width: 480, height: 620)
        .onAppear {
            backendURL = state.backendURL
        }
        .task {
            await state.detectAdapters()
        }
        .confirmationDialog("Reset local profile?", isPresented: $showResetConfirmation) {
            Button("Reset", role: .destructive) {
                state.resetLocalProfile()
                dismiss()
            }
        } message: {
            Text("This removes local profile, friend, and aggregate state from this Mac. It does not delete backend data.")
        }
    }
}

struct ProfilePictureSection: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile Picture")
                .font(.headline)

            HStack(spacing: 12) {
                if let profile = state.profile {
                    AvatarView(handle: profile.handle, avatarDataURL: profile.avatarDataURL, size: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("@\(profile.handle)")
                            .fontWeight(.semibold)
                        Text("Friends see this thumbnail next to your token count.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Choose") {
                    chooseAvatar()
                }

                if state.profile?.avatarDataURL != nil {
                    Button("Remove") {
                        state.setProfileAvatarDataURL(nil)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func chooseAvatar() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a profile picture. Token Racing stores and syncs only a small thumbnail."

        guard panel.runModal() == .OK,
              let url = panel.url,
              let dataURL = AvatarImageData.dataURL(from: url) else {
            return
        }

        state.setProfileAvatarDataURL(dataURL)
    }
}

struct UsageSourceRow: View {
    @EnvironmentObject private var state: AppState
    let app: CodingApp
    @State private var apiKey = ""
    @State private var accountEmail = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(app.rawValue, isOn: Binding(
                    get: { state.enabledApps.contains(app) },
                    set: { state.setAppEnabled(app, enabled: $0) }
                ))
                Spacer()
                connectionBadge
            }

            connectionControls

            Text(explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            accountEmail = state.apiAccountEmails[app] ?? ""
        }
    }

    @ViewBuilder
    private var connectionControls: some View {
        switch app {
        case .cursor:
            if state.apiKeyConnections[app] == true {
                HStack {
                    Text(state.apiAccountEmails[app].map { "Filtering to \($0)" } ?? "Connected to Cursor Admin API")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Disconnect") {
                        state.removeAPIConnection(app: app)
                        apiKey = ""
                        accountEmail = ""
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        SecureField("Cursor Admin API key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Paste Key") {
                            apiKey = pastedText()
                        }
                    }
                    TextField("Cursor account email, optional", text: $accountEmail)
                        .textFieldStyle(.roundedBorder)
                    Button("Connect Cursor API") {
                        state.saveAPIConnection(app: app, apiKey: apiKey, accountEmail: accountEmail)
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    CursorAPIKeyHelpView()
                }
            }
        case .claudeCode, .codex:
            Text("Auto-detects local sessions. No upload, no picker, no API key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func pastedText() -> String {
        NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var connectionBadge: some View {
        let status = state.adapterStatuses[app]
        let connected = status?.isAvailable == true

        return Text(connected ? "Connected" : "Not found")
            .font(.caption2.weight(.bold))
            .foregroundStyle(connected ? Color.green : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((connected ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
    }

    private var explanation: String {
        switch app {
        case .cursor:
            return CursorUsageAdapter(settings: state.data.sourceSettings).explainDataSource()
        case .claudeCode:
            return ClaudeCodeUsageAdapter(settings: state.data.sourceSettings).explainDataSource()
        case .codex:
            return CodexUsageAdapter(settings: state.data.sourceSettings).explainDataSource()
        }
    }
}

struct CursorAPIKeyHelpView: View {
    private let dashboardURL = URL(string: "https://cursor.com/dashboard")!
    private let docsURL = URL(string: "https://cursor.com/docs/api")!

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("How to find your Cursor API key")
                    .font(.caption.weight(.bold))
                Spacer()
                Link("Open dashboard", destination: dashboardURL)
                    .font(.caption)
            }

            VStack(spacing: 8) {
                CursorAPIHelpStep(
                    number: "1",
                    title: "Open Cursor Dashboard",
                    detail: "Go to cursor.com/dashboard and sign in with the team account that uses Cursor."
                )
                CursorAPIHelpStep(
                    number: "2",
                    title: "Go to Settings -> Advanced",
                    detail: "In the team dashboard, open Settings, then scroll to Advanced."
                )
                CursorAPIHelpStep(
                    number: "3",
                    title: "Create an Admin API key",
                    detail: "Find Admin API Keys, click Create New API Key, name it Token Racing, and copy it immediately."
                )
                CursorAPIHelpStep(
                    number: "4",
                    title: "Paste it here",
                    detail: "Keys usually start with crsr_. Optional: add your Cursor account email to filter team usage to you."
                )
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Only Cursor team admins can create Admin API keys. Personal Cursor accounts may not have this screen.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Link("Docs", destination: docsURL)
                    .font(.caption2)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct CursorAPIHelpStep: View {
    let number: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text(number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
