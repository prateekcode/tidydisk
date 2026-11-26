import SwiftUI

// The shared kit. Screens compose these; they do not draw their own cards,
// buttons, badges or bars.

// MARK: - Page chrome

/// Icon tile + title + one-line subtitle on the left, actions on the right.
struct PageHeader<Trailing: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(icon, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.display(21))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A full tab: header on top, content below, standard page padding.
struct Page<Trailing: View, Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(icon: icon, title: title, subtitle: subtitle, trailing: trailing)
            content()
        }
        .padding(Theme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Rounded square with a tinted symbol: page headers, list rows, tiles.
struct IconTile: View {
    let symbol: String
    var color: Color = Theme.accent
    var size: CGFloat = 32

    init(_ symbol: String, color: Color = Theme.accent, size: CGFloat = 32) {
        self.symbol = symbol
        self.color = color
        self.size = size
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color.opacity(0.16))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .medium))
                    .foregroundStyle(color)
            )
    }
}

/// Uppercase label that opens a panel ("CLEAN", "RUNNING NOW").
struct SectionLabel: View {
    let text: String
    var icon: String?

    init(_ text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
            }
            Text(text.uppercased()).font(.label).tracking(0.9)
        }
        .foregroundStyle(Theme.textSecondary)
    }
}

/// Hairline between rows.
struct Rule: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

// MARK: - Status

/// Small tinted pill: "POOR", "RUNNING", "MCP", "NEARLY FULL".
struct Badge: View {
    let text: String
    let color: Color
    var icon: String?

    init(_ text: String, color: Color, icon: String? = nil) {
        self.text = text
        self.color = color
        self.icon = icon
    }

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.6)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(color.opacity(0.16)))
        .fixedSize()
    }
}

// MARK: - Bars

/// Thin progress bar. `value` is 0…1.
struct Meter: View {
    let value: Double
    var color: Color = Theme.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

/// One bar split into coloured shares (disk usage by kind).
struct StackedBar: View {
    struct Segment: Identifiable {
        let id: String
        let color: Color
        let value: Double
    }

    let segments: [Segment]
    var height: CGFloat = 16

    private var total: Double { max(segments.reduce(0) { $0 + max($1.value, 0) }, 1) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(segments.filter { $0.value > 0 }) { segment in
                    Rectangle().fill(segment.color)
                        .frame(width: max(2, (geo.size.width - CGFloat(segments.count) * 2)
                                             * segment.value / total))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: height)
        .background(Theme.track)
        .clipShape(Capsule())
    }
}

/// Colour dot + label + value under a stacked bar.
struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(label).foregroundStyle(Theme.textSecondary)
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
        }
        .font(.system(size: 13))
        .fixedSize()
    }
}

/// Lays children out left to right and wraps to the next line (legends).
struct Flow: Layout {
    var spacing: CGFloat = 20
    var lineSpacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = place(subviews, in: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, point) in zip(subviews, place(subviews, in: bounds.width).points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                          proposal: .unspecified)
        }
    }

    private func place(_ subviews: Subviews, in width: CGFloat)
        -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (points, widest, y + rowHeight)
    }
}

/// Filled line chart for live samples. `values` oldest → newest.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.accent
    /// Fixed top of the scale; nil scales to the largest sample.
    var ceiling: Double?

    var body: some View {
        GeometryReader { geo in
            let top = max(ceiling ?? (values.max() ?? 1), 0.0001)
            let step = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0
            let points = values.enumerated().map { index, value in
                CGPoint(x: CGFloat(index) * step,
                        y: geo.size.height * (1 - CGFloat(min(max(value / top, 0), 1))))
            }
            if points.count > 1 {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.18))
                Path { path in
                    path.move(to: points[0])
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

// MARK: - Controls

struct KitButton: View {
    enum Kind { case primary, secondary, gold, danger }

    let title: String
    var icon: String?
    var kind: Kind = .secondary
    /// Stretch to the container width (panel call-to-action).
    var fill = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    init(_ title: String, icon: String? = nil, kind: Kind = .secondary, fill: Bool = false,
         action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.fill = fill
        self.action = action
    }

    private var background: Color {
        switch kind {
        case .primary: return Theme.accent
        case .secondary: return Theme.panel
        case .gold: return Theme.gold
        case .danger: return Theme.red
        }
    }

    private var foreground: Color { kind == .gold ? .black : Theme.textPrimary }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(height: 34)
            .background(background.opacity(hovering ? 0.86 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(kind == .secondary ? Theme.line : .clear, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Square tick box with an optional mixed state for group headers.
struct CheckBox: View {
    enum Mark { case off, on, mixed }

    let mark: Mark

    init(_ mark: Mark) { self.mark = mark }
    init(isOn: Bool) { self.mark = isOn ? .on : .off }

    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(mark == .off ? Color.clear : Theme.accent)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(mark == .off ? Color.white.opacity(0.28) : .clear, lineWidth: 1.5)
            )
            .overlay(
                Image(systemName: mark == .mixed ? "minus" : "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(.white)
                    .opacity(mark == .off ? 0 : 1)
            )
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
    }
}

/// Segmented switch ("By CPU / By memory", "Overview / Map / Folders").
struct Segmented<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String
        var icon: String?
        var count: Int?
        var id: Value { value }

        init(_ value: Value, _ label: String, icon: String? = nil, count: Int? = nil) {
            self.value = value
            self.label = label
            self.icon = icon
            self.count = count
        }
    }

    @Binding var selection: Value
    let options: [Option]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isOn = option.value == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option.value }
                } label: {
                    HStack(spacing: 6) {
                        if let icon = option.icon {
                            Image(systemName: icon).font(.system(size: 12, weight: .medium))
                        }
                        Text(option.label).font(.system(size: 13, weight: .semibold))
                        if let count = option.count {
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.white.opacity(0.12)))
                        }
                    }
                    .foregroundStyle(isOn ? Theme.textPrimary : Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isOn ? Theme.selected : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .panel(radius: 9, fill: Theme.raised)
    }
}

// MARK: - Rows and tiles

/// Label, big number and a caption: the small summary cards.
struct StatTile: View {
    let label: String
    var icon: String?
    var color: Color = Theme.gray
    let value: String
    let detail: String
    /// 0...1 draws a meter beside the value.
    var meter: Double?
    var detailLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let icon { IconTile(icon, color: color, size: 28) }
                SectionLabel(label).lineLimit(1).minimumScaleFactor(0.8)
            }
            HStack(spacing: 12) {
                Text(value)
                    .font(.display(22))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let meter { Meter(value: meter, color: color) }
            }
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(detailLines)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .panel()
    }
}

/// Tappable list row: icon, title + subtitle, trailing value, chevron.
struct NavRow: View {
    let icon: String
    var color: Color = Theme.accent
    let title: String
    let subtitle: String
    let value: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle).font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(value).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .background(hovering ? Color.white.opacity(0.03) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Centred message for a tab with nothing to show yet.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            IconTile(icon, color: Theme.gray, size: 52)
            Text(title).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(message).font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            if let actionTitle, let action {
                KitButton(actionTitle, kind: .primary, action: action).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Spinner + label while a scan runs.
struct BusyLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }
}
