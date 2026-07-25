import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Settings")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Connections used by Space Lens project actions")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 14) {
                    GitHubCard()
                    DestinationsCard()
                }
                .padding(24)
            }
        }
        .onAppear { state.checkGitHubConnection() }
    }
}

// MARK: - GitHub

private struct GitHubCard: View {
    @EnvironmentObject var state: AppState
    @State private var tokenField = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.up.forward.square.fill")
                    .foregroundStyle(Theme.accent)
                Text("GitHub")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if state.githubChecking {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let login = state.githubLogin {
                    Label("\(login)\(state.githubUsesToken ? "" : " (gh CLI)")",
                          systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.tierColor(.safe))
                } else {
                    Text("Not connected")
                        .font(.callout)
                        .foregroundStyle(Theme.tierColor(.aggressive))
                }
            }

            Text("\"Push to GitHub\" backs projects up to private repos on this account.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if state.githubUsesToken {
                Button("Disconnect") { state.disconnectGitHub() }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.tierColor(.nuclear))
            } else {
                HStack(spacing: 8) {
                    SecureField("Paste a personal access token (repo scope)", text: $tokenField)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 340)
                        .onSubmit { state.connectGitHub(token: tokenField) }
                    PillButton(title: "Connect") { state.connectGitHub(token: tokenField) }
                }
                Button("Create a token on github.com ↗") {
                    NSWorkspace.shared.open(URL(string:
                        "https://github.com/settings/tokens/new?scopes=repo&description=TidyDisk")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Theme.accent)

                if let error = state.githubError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.tierColor(.nuclear))
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 14)
        .frame(maxWidth: 640)
    }
}

// MARK: - Backup destinations

private struct DestinationsCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(Theme.accent)
                Text("Backup Destinations")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                PillButton(title: "Add Folder…") { addFolder() }
            }

            Text("\"Archive to…\" zips a project into these folders. macOS asks for permission on first write — use Test access to trigger the prompt, and grant it.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if state.cloudDestinations.isEmpty {
                Text("No destinations found — sign into iCloud, install a cloud drive, or add a folder.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(state.cloudDestinations) { destination in
                    DestinationRow(destination: destination)
                }
            }

            Button("Open Privacy Settings (Files & Folders) ↗") {
                NSWorkspace.shared.open(URL(string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Files")!)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Theme.accent)
        }
        .padding(16)
        .glassCard(cornerRadius: 14)
        .frame(maxWidth: 640)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use as Backup Destination"
        if panel.runModal() == .OK, let url = panel.url {
            state.addCustomDestination(path: url.path)
        }
    }
}

private struct DestinationRow: View {
    @EnvironmentObject var state: AppState
    let destination: CloudDestination

    private var isCustom: Bool { Engine.customDestinationPaths.contains(destination.path) }

    var body: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 1) {
                Text(destination.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Test access") { state.probeDestination(destination) }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
            if isCustom {
                Button {
                    state.removeCustomDestination(path: destination.path)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Remove this destination")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 9, height: 9)
    }

    private var dotColor: Color {
        switch state.probeResults[destination.path] {
        case .ok: return Theme.tierColor(.safe)
        case .failed: return Theme.tierColor(.nuclear)
        case nil: return Color.white.opacity(0.3)
        }
    }

    private var statusText: String {
        switch state.probeResults[destination.path] {
        case .ok: return "Writable ✓ · \(Engine.abbreviate(destination.path))"
        case .failed(let reason): return "No access — \(reason)"
        case nil: return Engine.abbreviate(destination.path)
        }
    }
}
