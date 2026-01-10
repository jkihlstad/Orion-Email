import SwiftUI

// MARK: - Glass Toolbar

/// A translucent toolbar with blur effect for navigation and actions
struct GlassToolbar<LeadingContent: View, CenterContent: View, TrailingContent: View>: View {
    let leadingContent: LeadingContent
    let centerContent: CenterContent
    let trailingContent: TrailingContent
    var height: CGFloat
    var showsDivider: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        height: CGFloat = Theme.Spacing.toolbarHeight,
        showsDivider: Bool = true,
        @ViewBuilder leading: () -> LeadingContent,
        @ViewBuilder center: () -> CenterContent,
        @ViewBuilder trailing: () -> TrailingContent
    ) {
        self.height = height
        self.showsDivider = showsDivider
        self.leadingContent = leading()
        self.centerContent = center()
        self.trailingContent = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                // Leading
                HStack(spacing: Theme.Spacing.xs) {
                    leadingContent
                }
                .frame(minWidth: 60, alignment: .leading)

                Spacer()

                // Center
                centerContent

                Spacer()

                // Trailing
                HStack(spacing: Theme.Spacing.xs) {
                    trailingContent
                }
                .frame(minWidth: 60, alignment: .trailing)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: height)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
            )

            if showsDivider {
                Divider()
                    .opacity(0.5)
            }
        }
    }
}

// MARK: - Convenience Initializers

extension GlassToolbar where CenterContent == EmptyView {
    /// Creates a toolbar with only leading and trailing content
    init(
        height: CGFloat = Theme.Spacing.toolbarHeight,
        showsDivider: Bool = true,
        @ViewBuilder leading: () -> LeadingContent,
        @ViewBuilder trailing: () -> TrailingContent
    ) {
        self.init(
            height: height,
            showsDivider: showsDivider,
            leading: leading,
            center: { EmptyView() },
            trailing: trailing
        )
    }
}

extension GlassToolbar where LeadingContent == EmptyView, TrailingContent == EmptyView {
    /// Creates a toolbar with only center content
    init(
        height: CGFloat = Theme.Spacing.toolbarHeight,
        showsDivider: Bool = true,
        @ViewBuilder center: () -> CenterContent
    ) {
        self.init(
            height: height,
            showsDivider: showsDivider,
            leading: { EmptyView() },
            center: center,
            trailing: { EmptyView() }
        )
    }
}

// MARK: - Glass Toolbar Button

/// A button styled for use in glass toolbars
struct GlassToolbarButton: View {
    let iconName: String
    var label: String?
    var badge: Int?
    var isDestructive: Bool
    var isDisabled: Bool
    let action: () -> Void

    @State private var isPressed = false

    init(
        iconName: String,
        label: String? = nil,
        badge: Int? = nil,
        isDestructive: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.iconName = iconName
        self.label = label
        self.badge = badge
        self.isDestructive = isDestructive
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: performAction) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .medium))

                    if let label = label {
                        Text(label)
                            .font(Theme.Typography.callout)
                    }
                }
                .foregroundStyle(foregroundColor)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())

                // Badge
                if let badge = badge, badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(Theme.Typography.unreadBadge)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.red)
                        )
                        .offset(x: 8, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? Theme.Opacity.disabled : 1.0)
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(Theme.Animation.buttonPress, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var foregroundColor: Color {
        if isDisabled {
            return .secondary
        }
        if isDestructive {
            return Theme.Colors.error
        }
        return .primary
    }

    private func performAction() {
        guard !isDisabled else { return }
        Haptics.light()
        action()
    }
}

// MARK: - Glass Bottom Toolbar

/// A floating bottom toolbar with glass effect
struct GlassBottomToolbar<Content: View>: View {
    let content: Content
    var padding: CGFloat
    var safeAreaPadding: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        padding: CGFloat = Theme.Spacing.md,
        safeAreaPadding: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.safeAreaPadding = safeAreaPadding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.5)

            content
                .padding(.horizontal, padding)
                .padding(.top, padding)
                .padding(.bottom, safeAreaPadding ? 0 : padding)
                .frame(maxWidth: .infinity)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .bottom)
                )
        }
    }
}

// MARK: - Floating Action Bar

/// A floating action bar for quick actions
struct FloatingActionBar: View {
    let actions: [FloatingAction]
    var showsLabels: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(actions: [FloatingAction], showsLabels: Bool = false) {
        self.actions = actions
        self.showsLabels = showsLabels
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(actions) { action in
                Button(action: action.perform) {
                    VStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: action.iconName)
                            .font(.system(size: 20, weight: .medium))

                        if showsLabels {
                            Text(action.label)
                                .font(Theme.Typography.caption2)
                        }
                    }
                    .foregroundStyle(action.isDestructive ? Theme.Colors.error : .primary)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .shadow(Theme.Shadows.glassElevated)
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(Theme.Opacity.glassBorder)
            : Color.black.opacity(0.1)
    }
}

struct FloatingAction: Identifiable {
    let id: String
    let label: String
    let iconName: String
    var isDestructive: Bool = false
    let action: () -> Void

    func perform() {
        Haptics.light()
        action()
    }
}

// MARK: - Segmented Glass Toolbar

/// A toolbar with segmented control style
struct SegmentedGlassToolbar<T: Hashable>: View {
    let options: [SegmentOption<T>]
    @Binding var selection: T

    @Namespace private var animation
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button(action: { select(option.value) }) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        if let iconName = option.iconName {
                            Image(systemName: iconName)
                                .font(.system(size: 14, weight: .medium))
                        }
                        Text(option.label)
                            .font(Theme.Typography.calloutBold)
                    }
                    .foregroundStyle(selection == option.value ? .primary : .secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selection == option.value {
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .matchedGeometryEffect(id: "selection", in: animation)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xxs)
        .background(
            Capsule()
                .fill(backgroundFill)
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                )
        )
        .animation(Theme.Animation.defaultSpring, value: selection)
    }

    private var backgroundFill: some ShapeStyle {
        AnyShapeStyle(colorScheme == .dark
            ? Color.white.opacity(0.05)
            : Color.black.opacity(0.03))
    }

    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.08)
    }

    private func select(_ value: T) {
        Haptics.selection()
        selection = value
    }
}

struct SegmentOption<T: Hashable>: Identifiable {
    let id: String
    let label: String
    let iconName: String?
    let value: T

    init(id: String = UUID().uuidString, label: String, iconName: String? = nil, value: T) {
        self.id = id
        self.label = label
        self.iconName = iconName
        self.value = value
    }
}

// MARK: - Preview

#Preview("Glass Toolbars") {
    ZStack {
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: 0) {
            // Top toolbar
            GlassToolbar(
                leading: {
                    GlassToolbarButton(iconName: "line.3.horizontal", action: {})
                },
                center: {
                    Text("Inbox")
                        .font(Theme.Typography.headline)
                },
                trailing: {
                    GlassToolbarButton(iconName: "magnifyingglass", action: {})
                    GlassToolbarButton(iconName: "ellipsis", action: {})
                }
            )

            Spacer()

            // Floating action bar
            FloatingActionBar(actions: [
                FloatingAction(id: "1", label: "Archive", iconName: "archivebox") {},
                FloatingAction(id: "2", label: "Delete", iconName: "trash", isDestructive: true) {},
                FloatingAction(id: "3", label: "Move", iconName: "folder") {},
                FloatingAction(id: "4", label: "More", iconName: "ellipsis") {}
            ])
            .padding(.bottom, Theme.Spacing.lg)

            // Bottom toolbar
            GlassBottomToolbar {
                HStack(spacing: Theme.Spacing.xl) {
                    GlassToolbarButton(iconName: "tray", badge: 5, action: {})
                    GlassToolbarButton(iconName: "star", action: {})
                    GlassToolbarButton(iconName: "paperplane", action: {})
                    GlassToolbarButton(iconName: "gear", action: {})
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview("Segmented Toolbar") {
    struct PreviewWrapper: View {
        @State private var selection = "inbox"

        var body: some View {
            ZStack {
                LinearGradient(
                    colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack {
                    SegmentedGlassToolbar(
                        options: [
                            SegmentOption(label: "Primary", iconName: "tray.fill", value: "inbox"),
                            SegmentOption(label: "Social", iconName: "person.2.fill", value: "social"),
                            SegmentOption(label: "Promo", iconName: "tag.fill", value: "promo")
                        ],
                        selection: $selection
                    )
                    .padding()

                    Spacer()
                }
            }
        }
    }

    return PreviewWrapper()
}
