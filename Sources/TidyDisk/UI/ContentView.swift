import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            Theme.background(for: state.phase)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: state.phase)

            HStack(spacing: 0) {
                SidebarView()
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 660)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showProSheet) { ProSheet() }
        .task { state.revalidateLicense() }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch state.sidebar {
        case .smartScan:
            flowContent
        case .projects:
            ProjectsView()
                .transition(.opacity)
        case .largeFiles:
            LargeFilesView()
                .transition(.opacity)
        case .duplicates:
            DuplicatesView()
                .transition(.opacity)
        case .category(let category):
            CategoryView(category: category)
                .transition(.opacity)
        case .log:
            LogView()
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var flowContent: some View {
        switch state.phase {
        case .welcome:
            WelcomeView().transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .scanning:
            ScanningView().transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .review:
            ReviewView().transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .cleaning:
            CleaningView().transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .done:
            DoneView().transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // clear the traffic lights
            Spacer().frame(height: 48)

            SidebarRow(item: .smartScan, label: "Smart Scan", icon: "sparkles.rectangle.stack.fill")

            Text("SPACE LENS")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 4)

            SidebarRow(item: .projects, label: "Projects", icon: "folder.fill.badge.gearshape")
            SidebarRow(item: .largeFiles, label: "Large Files", icon: "doc.badge.clock.fill")
            SidebarRow(item: .duplicates, label: "Duplicates", icon: "doc.on.doc.fill")

            Text("CATEGORIES")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 4)

            ForEach(state.categories) { category in
                SidebarRow(item: .category(category), label: category.rawValue, icon: category.icon)
            }

            Spacer()

            if ProConfig.paywallEnabled {
                ProSidebarBadge()
            }
            SidebarRow(item: .log, label: "Log", icon: "text.alignleft")
                .padding(.bottom, 14)
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .background(Color.black.opacity(0.22))
    }
}

/// "Unlock Pro" (free) or "Pro ✓" (licensed) — opens the Pro sheet either way.
struct ProSidebarBadge: View {
    @EnvironmentObject var state: AppState
    @State private var hovering = false

    var body: some View {
        Button {
            state.showProSheet = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: state.isPro ? "checkmark.seal.fill" : "crown.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state.isPro ? Theme.tierColor(.safe) : .yellow)
                    .frame(width: 22)
                Text(state.isPro ? "TidyDisk Pro" : "Unlock Pro")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.10) : Color.white.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in hovering = inside }
    }
}

struct SidebarRow: View {
    @EnvironmentObject var state: AppState
    let item: SidebarItem
    let label: String
    let icon: String

    @State private var hovering = false

    private var isSelected: Bool { state.sidebar == item }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) { state.sidebar = item }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                    .frame(width: 22)
                Text(label)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12)
                          : hovering ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in hovering = inside }
    }
}
