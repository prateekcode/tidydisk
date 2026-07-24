import SwiftUI

enum Theme {
    // Purple "CleanMyMac" palette
    static let deepPurple = Color(red: 0.10, green: 0.03, blue: 0.22)
    static let purple = Color(red: 0.32, green: 0.12, blue: 0.55)
    static let magenta = Color(red: 0.78, green: 0.25, blue: 0.95)
    static let accent = Color(red: 0.65, green: 0.35, blue: 1.0)

    // Success palette
    static let deepGreen = Color(red: 0.04, green: 0.15, blue: 0.08)
    static let green = Color(red: 0.15, green: 0.45, blue: 0.22)

    static let cardFill = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.12)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)

    static func tierColor(_ tier: RiskTier) -> Color {
        switch tier {
        case .safe: return Color(red: 0.35, green: 0.85, blue: 0.55)
        case .aggressive: return Color(red: 1.0, green: 0.65, blue: 0.25)
        case .nuclear: return Color(red: 1.0, green: 0.35, blue: 0.40)
        }
    }

    static func background(for phase: AppPhase) -> LinearGradient {
        let colors: [Color] = phase == .done
            ? [deepGreen, green.opacity(0.85), deepGreen]
            : [deepPurple, purple, deepPurple.opacity(0.9)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Theme.cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Theme.cardStroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
