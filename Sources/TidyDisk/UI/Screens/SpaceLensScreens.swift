import SwiftUI
import AppKit

// MARK: - Projects explorer

struct ProjectsView: View {
    @EnvironmentObject var state: AppState

    private var maxBytes: Int64 { max(state.projects.map(\.totalBytes).max() ?? 1, 1) }
    private var totalArtifacts: Int64 { state.projects.reduce(0) { $0 + $1.artifactBytes } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Projects")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(state.projects.isEmpty
                     ? "Find the dev projects eating your disk, wherever they live"
                     : "\(Format.bytes(totalArtifacts)) of build junk across \(state.projects.count) projects")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 16)

            if state.projects.isEmpty && !state.projectsScanning {
                Spacer()
                PillButton(title: "Scan Projects", prominent: true) { state.scanProjects() }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.projects) { project in
                            ProjectRow(project: project, maxBytes: maxBytes)
                        }
                    }
                    .padding(24)
                }
                HStack {
                    if state.projectsScanning {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Scanning…").foregroundStyle(Theme.textSecondary)
                    } else {
                        PillButton(title: "Rescan") { state.scanProjects() }
                    }
                }
                .padding(.bottom, 24)
            }
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

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.magenta, Theme.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(project.totalBytes) / CGFloat(maxBytes)))
                }
            }
            .frame(height: 7)

            HStack {
                if project.artifactBytes > 0 {
                    Text("\(Format.bytes(project.artifactBytes)) junk")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.tierColor(.aggressive))
                    Text(breakdown)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                } else {
                    Text("No build junk")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()

                if let activity = state.projectActivity[project.path] {
                    ProgressView().controlSize(.small).tint(.white)
                    Text(activity)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else if isCleaning {
                    ProgressView().controlSize(.small).tint(.white)
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
        .padding(14)
        .glassCard(cornerRadius: 14)
        .frame(maxWidth: 640)
    }
}

// MARK: - Large files

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Large Files")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Files over 200 MB in your home folder (Library excluded)")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 40)
            .padding(.bottom, 16)

            if state.largeFilesScanning {
                Spacer()
                ProgressView().controlSize(.large).tint(.white)
                Text("Hunting big files…")
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 12)
                Spacer()
            } else if !state.largeFilesScanned {
                Spacer()
                PillButton(title: "Find Large Files", prominent: true) { state.scanLargeFiles() }
                Spacer()
            } else if state.largeFiles.isEmpty {
                Spacer()
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.tierColor(.safe))
                Text("Nothing over 200 MB — tidy!")
                    .font(.title3)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 10)
                Spacer()
                PillButton(title: "Rescan") { state.scanLargeFiles() }
                    .padding(.bottom, 24)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(state.largeFiles) { file in
                            LargeFileRow(file: file)
                        }
                    }
                    .padding(24)
                }
                HStack(spacing: 14) {
                    PillButton(title: "Rescan") { state.scanLargeFiles() }
                    Spacer()
                    if !state.selectedFiles.isEmpty {
                        Text(Format.bytes(state.selectedFilesBytes))
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        PillButton(title: "Move \(state.selectedFiles.count) to Trash", prominent: true) {
                            state.trashSelectedFiles()
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 24)
            }
        }
    }
}

struct LargeFileRow: View {
    @EnvironmentObject var state: AppState
    let file: LargeFile

    private var isOn: Bool { state.selectedFiles.contains(file.path) }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                if isOn { state.selectedFiles.remove(file.path) } else { state.selectedFiles.insert(file.path) }
            }
        } label: {
            HStack(spacing: 12) {
                CheckCircle(isOn: isOn)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(Engine.abbreviate((file.path as NSString).deletingLastPathComponent))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(file.modified, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(Format.bytes(file.bytes))
                    .font(.callout.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 74, alignment: .trailing)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .glassCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 640)
    }
}
