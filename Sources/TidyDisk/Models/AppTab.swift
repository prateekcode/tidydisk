import Foundation

/// Every screen the shell can show. The top bar lists `barGroups`; the rest
/// are reached from buttons (Settings, Log) or from inside another tab.
enum AppTab: String, Hashable, CaseIterable {
    case overview, disk, clean, largeFiles, apps, projects, ai, monitor
    case duplicates, settings, log

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .disk: return "Disk"
        case .clean: return "Clean"
        case .largeFiles: return "Large Files"
        case .apps: return "Apps"
        case .projects: return "Projects"
        case .ai: return "AI"
        case .monitor: return "Monitor"
        case .duplicates: return "Duplicates"
        case .settings: return "Settings"
        case .log: return "Log"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .disk: return "chart.pie"
        case .clean: return "sparkles"
        case .largeFiles: return "doc.text"
        case .apps: return "macwindow"
        case .projects: return "hammer"
        case .ai: return "brain"
        case .monitor: return "waveform.path.ecg"
        case .duplicates: return "doc.on.doc"
        case .settings: return "gearshape"
        case .log: return "text.alignleft"
        }
    }

    /// Top-bar tabs, split where the bar draws a divider.
    static let barGroups: [[AppTab]] = [
        [.overview, .disk, .clean, .largeFiles, .apps, .projects], [.ai], [.monitor],
    ]

    /// The top-bar tab that stays lit while this screen is open.
    var barTab: AppTab { self == .duplicates ? .clean : self }
}
