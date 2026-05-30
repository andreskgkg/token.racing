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
                        TextField("http://127.0.0.1:8787", text: $backendURL)
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
                    SecureField("Cursor Admin API key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    TextField("Cursor account email, optional", text: $accountEmail)
                        .textFieldStyle(.roundedBorder)
                    Button("Connect Cursor API") {
                        state.saveAPIConnection(app: app, apiKey: apiKey, accountEmail: accountEmail)
                        apiKey = ""
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        case .claudeCode, .codex:
            Text("Auto-detects local sessions. No upload, no picker, no API key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
