import SwiftUI

// MARK: - Glass Chip

/// A small tag/label chip with glass effect for email labels
struct GlassChip: View {
    let text: String
    var iconName: String?
    var color: Color?
    var style: ChipStyle
    var size: ChipSize
    var isRemovable: Bool
    var onRemove: (() -> Void)?
    var onTap: (() -> Void)?

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    enum ChipStyle {
        case filled
        case outlined
        case glass
        case tinted
    }

    enum ChipSize {
        case small
        case medium
        case large

        var fontSize: Font {
            switch self {
            case .small: return Theme.Typography.caption2
            case .medium: return Theme.Typography.labelChip
            case .large: return Theme.Typography.callout
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 12
            case .large: return 14
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small: return Theme.Spacing.xxs
            case .medium: return Theme.Spacing.xs - 2
            case .large: return Theme.Spacing.xs
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return Theme.Spacing.xs
            case .medium: return Theme.Spacing.sm
            case .large: return Theme.Spacing.md
            }
        }
    }

    init(
        _ text: String,
        iconName: String? = nil,
        color: Color? = nil,
        style: ChipStyle = .glass,
        size: ChipSize = .medium,
        isRemovable: Bool = false,
        onRemove: (() -> Void)? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.text = text
        self.iconName = iconName
        self.color = color
        self.style = style
        self.size = size
        self.isRemovable = isRemovable
        self.onRemove = onRemove
        self.onTap = onTap
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            // Icon
            if let iconName = iconName {
                Image(systemName: iconName)
                    .font(.system(size: size.iconSize, weight: .medium))
            }

            // Text
            Text(text)
                .font(size.fontSize)
                .lineLimit(1)

            // Remove button
            if isRemovable {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: size.iconSize - 2, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.vertical, size.verticalPadding)
        .padding(.leading, size.horizontalPadding)
        .padding(.trailing, isRemovable ? size.horizontalPadding - 4 : size.horizontalPadding)
        .background(background)
        .clipShape(Capsule())
        .overlay(borderOverlay)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(Theme.Animation.buttonPress, value: isPressed)
        .contentShape(Capsule())
        .if(onTap != nil) { view in
            view.onTapGesture {
                Haptics.light()
                onTap?()
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
        }
    }

    // MARK: - Style Computed Properties

    private var foregroundColor: Color {
        switch style {
        case .filled:
            return .white
        case .outlined:
            return color ?? .primary
        case .glass:
            return .primary
        case .tinted:
            return color ?? Theme.Colors.primary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .filled:
            Capsule()
                .fill(color ?? Theme.Colors.primary)
        case .outlined:
            Color.clear
        case .glass:
            Capsule()
                .fill(.ultraThinMaterial)
        case .tinted:
            Capsule()
                .fill((color ?? Theme.Colors.primary).opacity(0.15))
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch style {
        case .filled:
            EmptyView()
        case .outlined:
            Capsule()
                .stroke(color ?? borderStrokeColor, lineWidth: 1)
        case .glass:
            Capsule()
                .stroke(glassBorderColor, lineWidth: 0.5)
        case .tinted:
            Capsule()
                .stroke((color ?? Theme.Colors.primary).opacity(0.3), lineWidth: 0.5)
        }
    }

    private var borderStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)
    }

    private var glassBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(Theme.Opacity.glassBorder)
            : Color.black.opacity(0.1)
    }

    private func remove() {
        Haptics.light()
        onRemove?()
    }
}

// MARK: - Email Label Chip

/// A chip specifically designed for email labels
struct EmailLabelChip: View {
    let label: EmailLabel
    var size: GlassChip.ChipSize
    var onTap: (() -> Void)?

    init(label: EmailLabel, size: GlassChip.ChipSize = .medium, onTap: (() -> Void)? = nil) {
        self.label = label
        self.size = size
        self.onTap = onTap
    }

    var body: some View {
        GlassChip(
            label.name,
            iconName: label.type == .custom ? nil : label.iconName,
            color: label.displayColor,
            style: .tinted,
            size: size,
            onTap: onTap
        )
    }
}

// MARK: - Recipient Chip

/// A chip for displaying email recipients
struct RecipientChip: View {
    let participant: EmailParticipant
    var isRemovable: Bool
    var onRemove: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    init(
        participant: EmailParticipant,
        isRemovable: Bool = true,
        onRemove: (() -> Void)? = nil
    ) {
        self.participant = participant
        self.isRemovable = isRemovable
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Theme.Colors.avatarColor(for: participant.id))
                    .frame(width: 20, height: 20)

                Text(participant.initials)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Name
            Text(participant.displayName)
                .font(Theme.Typography.labelChip)
                .lineLimit(1)

            // Remove button
            if isRemovable {
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Theme.Spacing.xxs)
        .padding(.leading, Theme.Spacing.xxs)
        .padding(.trailing, isRemovable ? Theme.Spacing.xs : Theme.Spacing.sm)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 0.5)
                )
        )
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(Theme.Opacity.glassBorder)
            : Color.black.opacity(0.1)
    }

    private func remove() {
        Haptics.light()
        onRemove?()
    }
}

// MARK: - Action Chip

/// A chip for quick actions
struct ActionChip: View {
    let text: String
    var iconName: String?
    var color: Color
    let action: () -> Void

    @State private var isPressed = false

    init(
        _ text: String,
        iconName: String? = nil,
        color: Color = Theme.Colors.primary,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.iconName = iconName
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: performAction) {
            HStack(spacing: Theme.Spacing.xxs) {
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(text)
                    .font(Theme.Typography.labelChip)
            }
            .foregroundStyle(.white)
            .padding(.vertical, Theme.Spacing.xs - 2)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(color)
            )
            .shadow(Theme.Shadows.xs)
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(Theme.Animation.buttonPress, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private func performAction() {
        Haptics.light()
        action()
    }
}

// MARK: - Chip Group

/// A horizontal scrolling group of chips
struct ChipGroup<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let data: Data
    let content: (Data.Element) -> Content
    var spacing: CGFloat

    init(
        _ data: Data,
        spacing: CGFloat = Theme.Spacing.xs,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: spacing) {
                ForEach(data) { item in
                    content(item)
                }
            }
            .padding(.horizontal, Theme.Spacing.xxs)
        }
    }
}

// MARK: - Flowing Chip Layout

/// A layout that wraps chips to new lines
struct FlowingChipLayout: Layout {
    var spacing: CGFloat = Theme.Spacing.xs
    var lineSpacing: CGFloat = Theme.Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing,
            lineSpacing: lineSpacing
        )
        return result.bounds
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing,
            lineSpacing: lineSpacing
        )

        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            )
            subview.place(at: point, proposal: .unspecified)
        }
    }

    struct FlowResult {
        var bounds: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat, lineSpacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + lineSpacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
                bounds.width = max(bounds.width, x - spacing)
            }

            bounds.height = y + lineHeight
        }
    }
}

// MARK: - Preview

#Preview("Glass Chips") {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Styles
                Group {
                    Text("Chip Styles")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        GlassChip("Glass", style: .glass)
                        GlassChip("Filled", color: .blue, style: .filled)
                        GlassChip("Outlined", color: .green, style: .outlined)
                        GlassChip("Tinted", color: .orange, style: .tinted)
                    }
                }

                // Sizes
                Group {
                    Text("Chip Sizes")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        GlassChip("Small", size: .small)
                        GlassChip("Medium", size: .medium)
                        GlassChip("Large", size: .large)
                    }
                }

                // With Icons
                Group {
                    Text("With Icons")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        GlassChip("Inbox", iconName: "tray.fill", color: .blue, style: .tinted)
                        GlassChip("Starred", iconName: "star.fill", color: .yellow, style: .tinted)
                        GlassChip("Important", iconName: "bookmark.fill", color: .red, style: .tinted)
                    }
                }

                // Removable
                Group {
                    Text("Removable Chips")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        GlassChip("Work", isRemovable: true, onRemove: {})
                        GlassChip("Personal", color: .green, style: .tinted, isRemovable: true, onRemove: {})
                    }
                }

                // Recipient Chips
                Group {
                    Text("Recipient Chips")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        RecipientChip(participant: .mockSender)
                        RecipientChip(participant: .mockRecipient, isRemovable: false)
                    }
                }

                // Action Chips
                Group {
                    Text("Action Chips")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        ActionChip("Reply", iconName: "arrowshape.turn.up.left.fill", action: {})
                        ActionChip("Forward", iconName: "arrowshape.turn.up.right.fill", color: .green, action: {})
                    }
                }

                // Email Labels
                Group {
                    Text("Email Labels")
                        .font(Theme.Typography.headline)

                    HStack(spacing: Theme.Spacing.sm) {
                        EmailLabelChip(label: .inbox)
                        EmailLabelChip(label: .starred)
                        EmailLabelChip(label: .drafts)
                    }
                }

                // Flowing Layout
                Group {
                    Text("Flowing Layout")
                        .font(Theme.Typography.headline)

                    FlowingChipLayout {
                        GlassChip("Work", color: .blue, style: .tinted)
                        GlassChip("Personal", color: .green, style: .tinted)
                        GlassChip("Travel", color: .orange, style: .tinted)
                        GlassChip("Finance", color: .purple, style: .tinted)
                        GlassChip("Shopping", color: .pink, style: .tinted)
                        GlassChip("Social", color: .cyan, style: .tinted)
                    }
                    .frame(maxWidth: 300)
                }
            }
            .padding()
        }
    }
}
