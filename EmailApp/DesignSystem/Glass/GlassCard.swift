import SwiftUI

// MARK: - Glass Card

/// A translucent card component with Apple-ish liquid glass design
/// Features ultra-thin material background, subtle border, and smooth shadows
struct GlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat
    var padding: CGFloat
    var material: Material
    var borderColor: Color
    var borderWidth: CGFloat
    var shadowStyle: Theme.ShadowStyle
    var isInteractive: Bool

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        cornerRadius: CGFloat = Theme.CornerRadius.card,
        padding: CGFloat = Theme.Spacing.md,
        material: Material = .ultraThinMaterial,
        borderColor: Color? = nil,
        borderWidth: CGFloat = 1,
        shadowStyle: Theme.ShadowStyle = Theme.Shadows.glass,
        isInteractive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.material = material
        self.borderColor = borderColor ?? Color.white.opacity(Theme.Opacity.glassBorder)
        self.borderWidth = borderWidth
        self.shadowStyle = shadowStyle
        self.isInteractive = isInteractive
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(adaptiveBorderColor, lineWidth: borderWidth)
                    )
            )
            .shadow(shadowStyle)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(Theme.Animation.buttonPress, value: isPressed)
            .if(isInteractive) { view in
                view.onTapGesture { }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in isPressed = true }
                            .onEnded { _ in isPressed = false }
                    )
            }
    }

    private var adaptiveBorderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(Theme.Opacity.glassBorder)
        } else {
            return Color.black.opacity(0.08)
        }
    }
}

// MARK: - Glass Card Variants

extension GlassCard {
    /// Creates an elevated glass card with stronger shadow
    static func elevated(
        cornerRadius: CGFloat = Theme.CornerRadius.card,
        padding: CGFloat = Theme.Spacing.md,
        @ViewBuilder content: () -> Content
    ) -> GlassCard {
        GlassCard(
            cornerRadius: cornerRadius,
            padding: padding,
            material: .regularMaterial,
            shadowStyle: Theme.Shadows.glassElevated,
            content: content
        )
    }

    /// Creates a subtle glass card with minimal styling
    static func subtle(
        cornerRadius: CGFloat = Theme.CornerRadius.card,
        padding: CGFloat = Theme.Spacing.md,
        @ViewBuilder content: () -> Content
    ) -> GlassCard {
        GlassCard(
            cornerRadius: cornerRadius,
            padding: padding,
            material: .ultraThinMaterial,
            shadowStyle: Theme.Shadows.xs,
            content: content
        )
    }
}

// MARK: - Glass Card Button

/// An interactive glass card that acts as a button
struct GlassCardButton<Content: View>: View {
    let content: Content
    let action: () -> Void
    var cornerRadius: CGFloat
    var padding: CGFloat

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    init(
        cornerRadius: CGFloat = Theme.CornerRadius.card,
        padding: CGFloat = Theme.Spacing.md,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.action = action
        self.content = content()
    }

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            content
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(borderColor, lineWidth: 1)
                        )
                )
                .shadow(Theme.Shadows.glass)
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var borderColor: Color {
        if colorScheme == .dark {
            return Color.white.opacity(Theme.Opacity.glassBorder)
        } else {
            return Color.black.opacity(0.08)
        }
    }
}

// MARK: - Glass Button Style

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(Theme.Animation.buttonPress, value: configuration.isPressed)
    }
}

// MARK: - Floating Glass Card

/// A glass card designed for floating overlays
struct FloatingGlassCard<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat
    var padding: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(
        cornerRadius: CGFloat = Theme.CornerRadius.xl,
        padding: CGFloat = Theme.Spacing.lg,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Outer glow
                    RoundedRectangle(cornerRadius: cornerRadius + 4)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blur(radius: 8)
                        .offset(y: 4)

                    // Main card
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.4),
                                            Color.white.opacity(0.1)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            )
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
    }
}

// MARK: - Glass Container

/// A full-width glass container for sections
struct GlassContainer<Content: View>: View {
    let content: Content
    var cornerRadius: CGFloat
    var verticalPadding: CGFloat
    var horizontalPadding: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(
        cornerRadius: CGFloat = Theme.CornerRadius.md,
        verticalPadding: CGFloat = Theme.Spacing.sm,
        horizontalPadding: CGFloat = Theme.Spacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.verticalPadding = verticalPadding
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.vertical, verticalPadding)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(borderColor, lineWidth: 0.5)
                    )
            )
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
}

// MARK: - View Extension for Conditional Modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(
        _ condition: Bool,
        transform: (Self) -> Transform
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview("Glass Cards") {
    ZStack {
        // Gradient background to showcase glass effect
        LinearGradient(
            colors: [
                Color.blue.opacity(0.4),
                Color.purple.opacity(0.4),
                Color.pink.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                // Standard Glass Card
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Standard Glass Card")
                            .font(Theme.Typography.headline)
                        Text("This is a translucent card with ultra-thin material background.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Elevated Glass Card
                GlassCard.elevated {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Elevated Glass Card")
                            .font(Theme.Typography.headline)
                        Text("This card has a stronger shadow for more emphasis.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(.secondary)
                    }
                }

                // Interactive Glass Card Button
                GlassCardButton(action: {
                    print("Tapped!")
                }) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text("Tap me!")
                            .font(Theme.Typography.bodyBold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }

                // Floating Glass Card
                FloatingGlassCard {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                        Text("Floating Overlay")
                            .font(Theme.Typography.title3)
                        Text("Perfect for modals and popovers")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Glass Container
                GlassContainer {
                    HStack {
                        Text("Container Style")
                            .font(Theme.Typography.callout)
                        Spacer()
                        Text("12 items")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }
}

#Preview("Dark Mode") {
    ZStack {
        Color.black.ignoresSafeArea()

        LinearGradient(
            colors: [
                Color.blue.opacity(0.3),
                Color.purple.opacity(0.3)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()

        VStack(spacing: Theme.Spacing.lg) {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Dark Mode Glass")
                        .font(Theme.Typography.headline)
                    Text("Glass effects adapt beautifully to dark mode.")
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }

            FloatingGlassCard {
                Text("Floating in the dark")
                    .font(Theme.Typography.bodyBold)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
