import SwiftUI

/// Dark neutral surfaces with TidyDisk's purple as the one accent.
/// Every screen reads colours, type and spacing from here.
enum Theme {
    // Brand purples (unchanged since 1.0): the accent, never a background wash
    static let accent = Color(red: 0.65, green: 0.35, blue: 1.0)
    static let magenta = Color(red: 0.78, green: 0.25, blue: 0.95)

    // Surfaces: near-black with a trace of purple so the accent sits naturally
    static let bg = Color(hex: 0x0D0C11)
    static let backdrop = bg
    static let bar = Color(hex: 0x15141A)
    static let panel = Color(hex: 0x1A1920)
    static let raised = Color(hex: 0x211F28)
    static let selected = Color(hex: 0x34313F)
    static let line = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.10)

    // Signal colours
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.28)
    static let green = Color(red: 0.35, green: 0.85, blue: 0.55)
    static let amber = Color(red: 1.0, green: 0.65, blue: 0.25)
    static let red = Color(red: 1.0, green: 0.35, blue: 0.40)
    static let blue = Color(red: 0.38, green: 0.62, blue: 1.0)
    static let violet = Color(red: 0.80, green: 0.62, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.48, blue: 0.72)
    static let teal = Color(red: 0.30, green: 0.82, blue: 0.86)
    static let gray = Color.white.opacity(0.55)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    static let textTertiary = Color.white.opacity(0.42)

    // Metrics
    static let radius: CGFloat = 12
    static let gap: CGFloat = 16
    static let pagePadding: CGFloat = 24
    static let barHeight: CGFloat = 52

    static func tierColor(_ tier: RiskTier) -> Color {
        switch tier {
        case .safe: return green
        case .aggressive: return amber
        case .nuclear: return red
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    /// Wide heavy face for titles and big numbers.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy).width(.expanded)
    }

    /// Uppercase section labels ("CLEAN", "RUNNING NOW").
    static let label = Font.system(size: 11.5, weight: .semibold)
}

/// Flat surface with a hairline border: the only card style in the app.
struct PanelStyle: ViewModifier {
    var radius: CGFloat = Theme.radius
    var fill: Color = Theme.panel

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func panel(radius: CGFloat = Theme.radius, fill: Color = Theme.panel) -> some View {
        modifier(PanelStyle(radius: radius, fill: fill))
    }
}
