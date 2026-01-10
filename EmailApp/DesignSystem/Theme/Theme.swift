import SwiftUI

// MARK: - Theme

/// Design system theme constants for the Email App
/// Provides consistent colors, typography, spacing, and animations throughout the app
struct Theme {
    // MARK: - Singleton
    static let shared = Theme()

    private init() {}

    // MARK: - Colors

    struct Colors {
        // Primary Brand Colors
        static let primary = Color("Primary", bundle: nil)
        static let primaryVariant = Color("PrimaryVariant", bundle: nil)

        // Semantic Colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        // Dynamic Colors (adapt to light/dark mode)
        static let background = Color(uiColor: .systemBackground)
        static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
        static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)
        static let groupedBackground = Color(uiColor: .systemGroupedBackground)

        static let text = Color(uiColor: .label)
        static let secondaryText = Color(uiColor: .secondaryLabel)
        static let tertiaryText = Color(uiColor: .tertiaryLabel)
        static let quaternaryText = Color(uiColor: .quaternaryLabel)

        static let separator = Color(uiColor: .separator)
        static let opaqueSeparator = Color(uiColor: .opaqueSeparator)

        // Glass Effect Colors
        static let glassBackground = Color.white.opacity(0.1)
        static let glassBorder = Color.white.opacity(0.2)
        static let glassShadow = Color.black.opacity(0.1)

        // Label Colors (Gmail-inspired)
        static let labelRed = Color(hex: "#EA4335") ?? .red
        static let labelOrange = Color(hex: "#FA7B17") ?? .orange
        static let labelYellow = Color(hex: "#FBBC04") ?? .yellow
        static let labelGreen = Color(hex: "#34A853") ?? .green
        static let labelBlue = Color(hex: "#4285F4") ?? .blue
        static let labelPurple = Color(hex: "#A142F4") ?? .purple
        static let labelPink = Color(hex: "#FF6D01") ?? .pink
        static let labelGray = Color(hex: "#5F6368") ?? .gray

        static let allLabelColors: [Color] = [
            labelRed, labelOrange, labelYellow, labelGreen,
            labelBlue, labelPurple, labelPink, labelGray
        ]

        // Avatar Background Colors
        static let avatarColors: [Color] = [
            Color(hex: "#1A73E8") ?? .blue,
            Color(hex: "#EA4335") ?? .red,
            Color(hex: "#34A853") ?? .green,
            Color(hex: "#FBBC04") ?? .yellow,
            Color(hex: "#FF6D01") ?? .orange,
            Color(hex: "#46BDC6") ?? .teal,
            Color(hex: "#7BAAF7") ?? .blue,
            Color(hex: "#F28B82") ?? .pink
        ]

        static func avatarColor(for id: String) -> Color {
            let hash = abs(id.hashValue)
            return avatarColors[hash % avatarColors.count]
        }
    }

    // MARK: - Typography

    struct Typography {
        // Title Styles
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)

        // Headline Styles
        static let headline = Font.headline
        static let subheadline = Font.subheadline

        // Body Styles
        static let body = Font.body
        static let bodyBold = Font.body.weight(.semibold)
        static let callout = Font.callout
        static let calloutBold = Font.callout.weight(.semibold)

        // Caption Styles
        static let caption = Font.caption
        static let caption2 = Font.caption2
        static let captionBold = Font.caption.weight(.semibold)

        // Custom Sizes
        static let senderName = Font.system(size: 15, weight: .semibold)
        static let emailSubject = Font.system(size: 14, weight: .medium)
        static let emailSnippet = Font.system(size: 13, weight: .regular)
        static let emailTimestamp = Font.system(size: 12, weight: .regular)
        static let labelChip = Font.system(size: 11, weight: .medium)
        static let unreadBadge = Font.system(size: 11, weight: .bold)

        // Monospace (for code/technical content)
        static let monospace = Font.system(.body, design: .monospaced)
        static let monospaceSm = Font.system(.caption, design: .monospaced)
    }

    // MARK: - Spacing

    struct Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64

        // Component-specific spacing
        static let listRowPadding: CGFloat = 16
        static let listRowVerticalPadding: CGFloat = 12
        static let cardPadding: CGFloat = 16
        static let toolbarHeight: CGFloat = 56
        static let searchBarHeight: CGFloat = 44
        static let chipHeight: CGFloat = 28
        static let avatarSizeSmall: CGFloat = 32
        static let avatarSizeMedium: CGFloat = 40
        static let avatarSizeLarge: CGFloat = 56
    }

    // MARK: - Corner Radius

    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let full: CGFloat = 1000

        // Component-specific
        static let card: CGFloat = 16
        static let chip: CGFloat = 14
        static let button: CGFloat = 12
        static let searchBar: CGFloat = 12
        static let avatar: CGFloat = 1000
        static let sheet: CGFloat = 20
    }

    // MARK: - Shadows

    struct Shadows {
        static let none = ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
        static let xs = ShadowStyle(color: Colors.glassShadow.opacity(0.05), radius: 2, x: 0, y: 1)
        static let sm = ShadowStyle(color: Colors.glassShadow.opacity(0.1), radius: 4, x: 0, y: 2)
        static let md = ShadowStyle(color: Colors.glassShadow.opacity(0.15), radius: 8, x: 0, y: 4)
        static let lg = ShadowStyle(color: Colors.glassShadow.opacity(0.2), radius: 16, x: 0, y: 8)
        static let xl = ShadowStyle(color: Colors.glassShadow.opacity(0.25), radius: 24, x: 0, y: 12)

        // Glass-specific shadows
        static let glass = ShadowStyle(color: Colors.glassShadow.opacity(0.1), radius: 12, x: 0, y: 4)
        static let glassElevated = ShadowStyle(color: Colors.glassShadow.opacity(0.2), radius: 20, x: 0, y: 8)
    }

    struct ShadowStyle {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // MARK: - Animation

    struct Animation {
        // Durations
        static let instant: Double = 0.1
        static let fast: Double = 0.2
        static let normal: Double = 0.3
        static let slow: Double = 0.5
        static let verySlow: Double = 0.8

        // Spring Animations
        static let defaultSpring = SwiftUI.Animation.spring(response: 0.35, dampingFraction: 0.7)
        static let gentleSpring = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
        static let bouncySpring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.6)
        static let snappySpring = SwiftUI.Animation.spring(response: 0.25, dampingFraction: 0.8)

        // Ease Animations
        static let easeDefault = SwiftUI.Animation.easeInOut(duration: normal)
        static let easeFast = SwiftUI.Animation.easeInOut(duration: fast)
        static let easeSlow = SwiftUI.Animation.easeInOut(duration: slow)

        // Interactive
        static let buttonPress = SwiftUI.Animation.easeOut(duration: instant)
        static let pageTransition = SwiftUI.Animation.easeInOut(duration: normal)
        static let cardExpand = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.75)
        static let pullToRefresh = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.7)
    }

    // MARK: - Blur

    struct Blur {
        static let none: CGFloat = 0
        static let subtle: CGFloat = 3
        static let light: CGFloat = 8
        static let medium: CGFloat = 15
        static let heavy: CGFloat = 25
        static let intense: CGFloat = 40
    }

    // MARK: - Opacity

    struct Opacity {
        static let disabled: Double = 0.4
        static let placeholder: Double = 0.5
        static let secondary: Double = 0.7
        static let primary: Double = 1.0

        // Glass opacities
        static let glassBg: Double = 0.1
        static let glassBgHover: Double = 0.15
        static let glassBorder: Double = 0.2
        static let glassBorderActive: Double = 0.3
    }
}

// MARK: - View Extensions

extension View {
    /// Applies a shadow style from the theme
    func shadow(_ style: Theme.ShadowStyle) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }

    /// Applies glass morphism effect
    func glassMorphism(
        cornerRadius: CGFloat = Theme.CornerRadius.card,
        opacity: Double = Theme.Opacity.glassBg
    ) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(Theme.Opacity.glassBorder), lineWidth: 1)
            )
            .shadow(Theme.Shadows.glass)
    }

    /// Standardized press animation
    func pressAnimation(isPressed: Bool) -> some View {
        self
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(Theme.Animation.buttonPress, value: isPressed)
    }
}

// MARK: - Haptics

struct Haptics {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    static func heavy() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Colors Section
            Group {
                Text("Colors")
                    .font(Theme.Typography.title2)

                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(Theme.Colors.allLabelColors.indices, id: \.self) { index in
                        Circle()
                            .fill(Theme.Colors.allLabelColors[index])
                            .frame(width: 32, height: 32)
                    }
                }
            }

            Divider()

            // Typography Section
            Group {
                Text("Typography")
                    .font(Theme.Typography.title2)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Large Title").font(Theme.Typography.largeTitle)
                    Text("Title").font(Theme.Typography.title)
                    Text("Headline").font(Theme.Typography.headline)
                    Text("Body").font(Theme.Typography.body)
                    Text("Caption").font(Theme.Typography.caption)
                }
            }

            Divider()

            // Glass Effect Demo
            Group {
                Text("Glass Effects")
                    .font(Theme.Typography.title2)

                Text("Sample Glass Card")
                    .padding()
                    .frame(maxWidth: .infinity)
                    .glassMorphism()
            }
        }
        .padding()
    }
    .background(
        LinearGradient(
            colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}
