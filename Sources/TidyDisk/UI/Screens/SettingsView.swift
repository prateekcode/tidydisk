import SwiftUI
import AppKit

/// Everything the user can switch: how the app behaves, what it may read,
/// what it is connected to, what it remembers, and what version this is.
struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Page(icon: AppTab.settings.icon, title: "Settings",
             subtitle: "TidyDisk \(Project.version) · free and open source") {
            KitButton("Report a problem", icon: "exclamationmark.bubble") { Self.open(Project.issues) }
        } content: {
            ScrollView {
                HStack(alignment: .top, spacing: Theme.gap) {
                    VStack(spacing: Theme.gap) {
                        GeneralPanel()
                        ScanningPanel()
                        PrivacyPanel()
                    }
                    VStack(spacing: Theme.gap) {
                        GitHubPanel()
                        DestinationsPanel()
                        SavedDataPanel()
                        AboutPanel()
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .onAppear { state.checkGitHubConnection() }
    }

    static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - General

private struct GeneralPanel: View {
    @EnvironmentObject var state: AppState
    @AppStorage(Preferences.menuBarShowsFreeSpace) private var showsFreeSpace = true
    @State private var opensAtLogin = LoginItem.isEnabled

    var body: some View {
        LabeledPanel(label: "General", icon: "switch.2") {
            SettingRow(icon: "power", title: "Open at login",
                       detail: "Starts in the menu bar when you log in.") {
                KitToggle(isOn: Binding(get: { opensAtLogin },
                                        set: { opensAtLogin = LoginItem.set($0) }))
            }
            Rule()
            SettingRow(icon: "menubar.rectangle", title: "Free space in the menu bar",
                       detail: "Shows the number beside the icon. It updates by itself.") {
                KitToggle(isOn: $showsFreeSpace)
            }
            Rule()
            SettingRow(icon: "calendar.badge.clock", title: "Weekly scan",
                       detail: "Mondays at 10:00, with a notification of what can be cleaned. Nothing is removed.") {
                KitToggle(isOn: Binding(get: { state.weeklyScanEnabled },
                                        set: { state.setWeeklyScan($0) }))
            }
        }
        .onAppear { opensAtLogin = LoginItem.isEnabled }
    }
}

// MARK: - Scanning

private struct ScanningPanel: View {
    @EnvironmentObject var disk: DiskStore
    @State private var hasFullAccess = Engine.hasFullDiskAccess()

    private var stepIndex: Int {
        DiskStore.thresholdSteps.firstIndex(of: disk.largeThreshold) ?? 0
    }

    var body: some View {
        LabeledPanel(label: "Scanning", icon: "magnifyingglass") {
            SettingRow(icon: "lock.shield", color: hasFullAccess ? Theme.green : Theme.amber,
                       title: "Full Disk Access",
                       detail: hasFullAccess
                           ? "TidyDisk can measure the Trash, Mail, Photos and sandboxed app data."
                           : "Without it the Trash, Mail, Photos and sandboxed app data are left out.") {
                if hasFullAccess {
                    Badge("Granted", color: Theme.green, icon: "checkmark")
                } else {
                    KitButton("Open System Settings") { Engine.openFullDiskAccessSettings() }
                }
            }
            Rule()
            SettingRow(icon: "doc.text", color: Theme.amber, title: "Large file size",
                       detail: "Files of at least this size appear in Large Files.") {
                HStack(spacing: 8) {
                    StepButton(icon: "minus", enabled: stepIndex > 0) {
                        disk.largeThreshold = DiskStore.thresholdSteps[stepIndex - 1]
                    }
                    Text(Format.bytes(disk.largeThreshold))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .monospacedDigit()
                        .frame(minWidth: 64)
                    StepButton(icon: "plus", enabled: stepIndex < DiskStore.thresholdSteps.count - 1) {
                        disk.largeThreshold = DiskStore.thresholdSteps[stepIndex + 1]
                    }
                }
            }
        }
        .onAppear { hasFullAccess = Engine.hasFullDiskAccess() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullAccess = Engine.hasFullDiskAccess()
        }
    }

    private struct StepButton: View {
        let icon: String
        let enabled: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
        }
    }
}

// MARK: - Privacy

private struct PrivacyPanel: View {
    @State private var sharesUsage = UsageStats.isEnabled

    var body: some View {
        LabeledPanel(label: "Privacy", icon: "hand.raised") {
            SettingRow(icon: "chart.bar", title: "Share anonymous usage statistics",
                       detail: "Off unless you switch it on. Helps decide what to build next.") {
                KitToggle(isOn: Binding(get: { sharesUsage }, set: {
                    UsageStats.isEnabled = $0
                    sharesUsage = UsageStats.isEnabled
                }))
            }
            Rule()
            VStack(alignment: .leading, spacing: 8) {
                Fact(icon: "checkmark", color: Theme.green,
                     text: "Sent when on: which tab you open, that a scan or clean-up finished (sizes rounded), app and macOS version, Mac model, language, and a random id made on this Mac.")
                Fact(icon: "xmark", color: Theme.red,
                     text: "Never sent: file names, paths, folder or project names, account names, anything you type.")
                Fact(icon: "trash", color: Theme.textSecondary,
                     text: "Switching it off erases the id and asks our server to delete what this Mac sent.")
                LinkButton(title: "Read the code that sends it", icon: "arrow.up.forward", accent: true) {
                    SettingsView.open(Project.usageStatsSource)
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private struct Fact: View {
        let icon: String
        let color: Color
        let text: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(text)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - GitHub

private struct GitHubPanel: View {
    @EnvironmentObject var state: AppState
    @State private var tokenField = ""

    var body: some View {
        LabeledPanel(label: "GitHub", icon: "arrow.up.forward.square") {
            if state.githubChecking {
                ProgressView().controlSize(.small)
            } else if let login = state.githubLogin {
                Badge(state.githubUsesToken ? login : "\(login) · gh CLI", color: Theme.green, icon: "checkmark")
            } else {
                Badge("Not connected", color: Theme.amber)
            }
        } content: {
            SettingRow(icon: "shippingbox", title: "Push projects to private repos",
                       detail: "Projects → Push to GitHub backs a project up to this account before you delete it.") {
                if state.githubUsesToken {
                    KitButton("Disconnect", kind: .danger) { state.disconnectGitHub() }
                }
            }
            if !state.githubUsesToken {
                Rule()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        SecureField("Personal access token (repo scope)", text: $tokenField)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
                            .onSubmit { state.connectGitHub(token: tokenField) }
                        KitButton("Connect", kind: .primary) { state.connectGitHub(token: tokenField) }
                            .disabled(tokenField.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack(spacing: 14) {
                        LinkButton(title: "Create a token on github.com", icon: "arrow.up.forward", accent: true) {
                            SettingsView.open("https://github.com/settings/tokens/new?scopes=repo&description=TidyDisk")
                        }
                        Text("Kept in your Keychain.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let error = state.githubError {
                        Text(error).font(.system(size: 12.5)).foregroundStyle(Theme.red)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }
}

// MARK: - Backup destinations

private struct DestinationsPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        LabeledPanel(label: "Backup destinations", icon: "externaldrive.badge.icloud") {
            KitButton("Add folder", icon: "plus") { addFolder() }
        } content: {
            if state.cloudDestinations.isEmpty {
                SettingRow(icon: "icloud.slash", color: Theme.textSecondary, title: "No destinations yet",
                           detail: "Sign in to iCloud, install a cloud drive, or add a folder.") { EmptyView() }
            } else {
                ForEach(state.cloudDestinations) { destination in
                    DestinationRow(destination: destination)
                    Rule()
                }
            }
            HStack {
                Text("Projects → Archive zips a project into one of these. macOS asks once before the first write.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                LinkButton(title: "Files and Folders settings", icon: "arrow.up.forward", accent: true) {
                    SettingsView.open("x-apple.systempreferences:com.apple.preference.security?Privacy_Files")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
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

    private var status: (icon: String, color: Color, text: String) {
        switch state.probeResults[destination.path] {
        case .ok: return ("checkmark.circle", Theme.green, "Writable · \(Engine.abbreviate(destination.path))")
        case .failed(let reason): return ("xmark.circle", Theme.red, "No access: \(reason)")
        case nil: return ("folder", Theme.accent, Engine.abbreviate(destination.path))
        }
    }

    var body: some View {
        SettingRow(icon: status.icon, color: status.color, title: destination.name, detail: status.text) {
            HStack(spacing: 12) {
                LinkButton(title: "Test access") { state.probeDestination(destination) }
                if isCustom {
                    Button { state.removeCustomDestination(path: destination.path) } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove this destination")
                }
            }
        }
    }
}

// MARK: - Saved data

private struct SavedDataPanel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        LabeledPanel(label: "Saved by TidyDisk", icon: "internaldrive") {
            SettingRow(icon: "sparkles", color: Theme.green, title: "Cleaned all time",
                       detail: "\(Format.bytes(state.cleanedAllTime)) in "
                           + (state.cleanUps == 1 ? "1 clean-up" : "\(state.cleanUps) clean-ups") + ".") {
                KitButton("Reset") { state.resetCleanedCounter() }
                    .disabled(state.cleanedAllTime == 0 && state.cleanUps == 0)
            }
            Rule()
            SettingRow(icon: "clock.arrow.circlepath", title: "Last scan and disk measurement",
                       detail: state.lastScan.map { "Kept between launches. Last scan \(Format.ago($0))." }
                           ?? "Nothing saved yet.") {
                KitButton("Forget") { state.forgetSavedScan() }
                    .disabled(state.isBusy || (state.lastScan == nil && state.disk.index == nil))
            }
        }
    }
}

// MARK: - About

private struct AboutPanel: View {
    @State private var check = UpdateCheck.idle
    @State private var copied = false

    private var updateDetail: String {
        switch check {
        case .idle: return "Asks GitHub for the newest release. Only when you press the button."
        case .checking: return "Checking…"
        case .current: return "You have the newest version."
        case .available(let version): return "Version \(version) is out."
        case .failed: return "Could not reach GitHub. Try again later."
        }
    }

    var body: some View {
        LabeledPanel(label: "About", icon: "info.circle") {
            Badge("MIT licence", color: Theme.accent)
        } content: {
            SettingRow(icon: "arrow.down.circle", title: "TidyDisk \(Project.version) (\(Project.build))",
                       detail: updateDetail) {
                if case .available = check {
                    HStack(spacing: 8) {
                        KitButton(copied ? "Copied" : "Copy brew command", icon: "doc.on.doc") {
                            SettingsView.copy(Project.brewUpgrade)
                            copied = true
                        }
                        KitButton("Download", kind: .primary) { SettingsView.open(Project.releases) }
                    }
                } else {
                    KitButton("Check for updates") {
                        check = .checking
                        Task { check = await UpdateCheck.run() }
                    }
                    .disabled(check == .checking)
                }
            }
            Rule()
            SettingRow(icon: "chevron.left.forwardslash.chevron.right", title: "Open source",
                       detail: "Every line of what TidyDisk reads and removes is public. Stars and fixes are welcome.") {
                KitButton("GitHub", icon: "star") { SettingsView.open(Project.repository) }
            }
            Rule()
            HStack(spacing: 18) {
                LinkButton(title: "Website", icon: "arrow.up.forward", accent: true) {
                    SettingsView.open(Project.website)
                }
                LinkButton(title: "Licence", icon: "arrow.up.forward", accent: true) {
                    SettingsView.open(Project.license)
                }
                LinkButton(title: "Request a cleaner", icon: "arrow.up.forward", accent: true) {
                    SettingsView.open(Project.issues)
                }
                Spacer()
                Text("© RiekApps").font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }
}
