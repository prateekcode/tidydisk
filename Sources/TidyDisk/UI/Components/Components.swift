import SwiftUI

// MARK: - Big round action button (Scan / Run)

struct GlowButton: View {
    let title: String
    let action: () -> Void

    @State private var pulsing = false
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 110, height: 110)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [Theme.magenta, Theme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: Theme.magenta.opacity(pulsing ? 0.9 : 0.45), radius: pulsing ? 34 : 18)
                // scoped animation — a global withAnimation(.repeatForever) leaks into
                // other scene updates (visibly jitters the MenuBarExtra label)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulsing)
                .scaleEffect(hovering ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(duration: 0.3)) { hovering = inside }
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - Pill button (secondary actions)

struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(prominent ? Color.black : Theme.textPrimary)
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(prominent ? Color.white : Color.white.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Task icon tile

struct TaskIcon: View {
    let task: CleanupTask
    var size: CGFloat = 34

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Theme.tierColor(task.tier).opacity(0.85), Theme.tierColor(task.tier).opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: task.icon)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Tier badge

struct TierBadge: View {
    let tier: RiskTier

    var body: some View {
        Text(tier.label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.tierColor(tier))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.tierColor(tier).opacity(0.16)))
    }
}

// MARK: - Checkbox

struct CheckCircle: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? Color.clear : Color.white.opacity(0.4), lineWidth: 1.5)
                .background(Circle().fill(isOn ? Theme.accent : Color.clear))
            if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
    }
}

// MARK: - Hero disc (welcome / done screens)

struct HeroDisc: View {
    let symbol: String
    let colors: [Color]

    @State private var floating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: colors, center: .topLeading, startRadius: 20, endRadius: 260)
                )
                .frame(width: 230, height: 230)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                .shadow(color: colors.first?.opacity(0.6) ?? .clear, radius: 50, y: 18)
            Image(systemName: symbol)
                .font(.system(size: 88, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
        }
        .offset(y: floating ? -9 : 9)
        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true), value: floating)
        .onAppear { floating = true }
    }
}
