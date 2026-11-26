import SwiftUI
import AppKit

// MARK: - Projects explorer

struct ProjectsView: View {
    @EnvironmentObject var state: AppState

    private var maxBytes: Int64 { max(state.projects.map(\.totalBytes).max() ?? 1, 1) }
    private var totalArtifacts: Int64 { state.projects.reduce(0) { $0 + $1.artifactBytes } }

    private var subtitle: String {
        state.projects.isEmpty
            ? "Find the dev projects eating your disk, wherever they live"
            : "\(Format.bytes(totalArtifacts)) of build output across \(state.projects.count) projects"
    }

    var body: some View {
        Page(icon: AppTab.projects.icon, title: "Projects", subtitle: subtitle) {
            if state.projectsScanning { BusyLabel(text: "Scanning…") }
            KitButton(state.projects.isEmpty ? "Scan projects" : "Scan again", icon: "arrow.clockwise",
                      kind: state.projects.isEmpty ? .primary : .secondary) { state.scanProjects() }
                .disabled(state.projectsScanning)
        } content: {
            if state.projects.isEmpty {
                EmptyState(icon: AppTab.projects.icon,
                           title: state.projectsScanning ? "Looking for projects…" : "No projects scanned yet",
                           message: "TidyDisk finds every folder with a .git, package.json, pubspec.yaml or Xcode project and sizes its build output.")
                    .panel()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.projects) { project in
                            ProjectRow(project: project, maxBytes: maxBytes)
                            Rule()
                        }
                    }
                }
                .panel()
            }
        }
        .alert("Couldn't complete", isPresented: Binding(
            get: { state.actionAlert != nil },
            set: { if !$0 { state.actionAlert = nil } }
        )) {
            Button("Open Settings") { state.tab = .settings }
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.actionAlert ?? "")
        }
        .alert(item: $state.archivePrompt) { prompt in
            Alert(
                title: Text("Archived to \(prompt.destinationName)"),
                message: Text("\(prompt.project.name) was zipped to \(Engine.abbreviate(prompt.zipPath)).\n\nMove the local project (\(Format.bytes(prompt.project.totalBytes))) to Trash to free up space? Make sure the zip has finished syncing before emptying the Trash."),
                primaryButton: .destructive(Text("Move to Trash")) {
                    state.trashProject(prompt.project)
                },
                secondaryButton: .cancel(Text("Keep Local"))
            )
        }
    }
}

struct ProjectRow: View {
    @EnvironmentObject var state: AppState
    let project: ProjectInfo
    let maxBytes: Int64

    private var isCleaning: Bool { state.projectCleaning.contains(project.path) }

    private var breakdown: String {
        project.artifacts.prefix(3)
            .map { "\(($0.path as NSString).lastPathComponent) \(Format.bytes($0.bytes))" }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(project.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(Engine.abbreviate((project.path as NSString).deletingLastPathComponent))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(Format.bytes(project.totalBytes))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            Meter(value: Double(project.totalBytes) / Double(maxBytes))

            HStack {
                if project.artifactBytes > 0 {
                    Text("\(Format.bytes(project.artifactBytes)) build output")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.tierColor(.aggressive))
                    Text(breakdown)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("No build output")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                if let activity = state.projectActivity[project.path] {
                    ProgressView().controlSize(.small)
                    Text(activity)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else if isCleaning {
                    ProgressView().controlSize(.small)
                } else {
                    if project.artifactBytes > 0 {
                        Button("Clean") { state.cleanProject(project) }
                            .buttonStyle(.plain)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    Menu {
                        Button {
                            state.pushProjectToGitHub(project)
                        } label: {
                            Label("Push to GitHub (private)", systemImage: "arrow.up.circle")
                        }
                        ForEach(state.cloudDestinations) { destination in
                            Button {
                                state.archiveProject(project, to: destination)
                            } label: {
                                Label("Archive to \(destination.name)", systemImage: "icloud.and.arrow.up")
                            }
                        }
                        Divider()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path)])
                        } label: {
                            Label("Reveal in Finder", systemImage: "magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
    }
}
