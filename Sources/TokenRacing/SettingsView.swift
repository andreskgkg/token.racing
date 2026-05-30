import AppKit
import SwiftUI

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

struct UsageSourceRow: View {
    @EnvironmentObject private var state: AppState
    let app: CodingApp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(app.rawValue, isOn: Binding(
                get: { state.enabledApps.contains(app) },
                set: { state.setAppEnabled(app, enabled: $0) }
            ))

            HStack {
                Text(state.customPaths[app] ?? "No custom file selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Choose File/Folder") {
                    choosePath()
                }
                if state.customPaths[app] != nil {
                    Button("Clear") {
                        state.setCustomPath(nil, for: app)
                    }
                }
            }

            Text(explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
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

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a local usage/log file or folder for \(app.rawValue). Raw contents never leave this Mac."
        if panel.runModal() == .OK {
            state.setCustomPath(panel.url?.path, for: app)
        }
    }
}
