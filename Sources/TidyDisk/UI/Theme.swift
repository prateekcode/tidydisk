import SwiftUI

/// Flat dark design tokens. Every screen reads colours, type and spacing from here.
enum Theme {
    // Surfaces
    static let bg = Color(hex: 0x0E0E10)
    static let bar = Color(hex: 0x17171A)
    static let panel = Color(hex: 0x1B1B1E)
    static let raised = Color(hex: 0x26262B)
    static let line = Color.white.opacity(0.07)
    static let track = Color.white.opacity(0.09)

    // Signal colours
    static let accent = Color(hex: 0x6366F1)
    static let gold = Color(hex: 0xEDB23E)
    static let green = Color(hex: 0x4DB883)
    static let amber = Color(hex: 0xE9A23B)
    static let red = Color(hex: 0xE5534B)
    static let blue = Color(hex: 0x4F86F0)
    static let violet = Color(hex: 0xA78BFA)
    static let gray = Color(hex: 0x8A8A93)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

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
