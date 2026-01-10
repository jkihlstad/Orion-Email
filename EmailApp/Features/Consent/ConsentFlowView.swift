import SwiftUI

// MARK: - Consent Flow View

/// Consent management view with toggles for each consent type
struct ConsentFlowView: View {
    @EnvironmentObject var consentManager: ConsentManager
    @State private var localConsents: [ConsentType: Bool] = [:]
    @State private var hasChanges = false
    @State private var showSaveConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.Spacing.lg) {
                        // Header
                        headerSection

                        // Consent cards
                        consentCardsSection

                        // Info section
                        infoSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Privacy & Consents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if hasChanges {
                            showSaveConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveConsents()
                    }
                    .font(Theme.Typography.bodyBold)
                    .disabled(!hasChanges)
                }
            }
            .alert("Unsaved Changes", isPresented: $showSaveConfirmation) {
                Button("Discard", role: .destructive) {
                    dismiss()
                }
                Button("Save") {
                    saveConsents()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You have unsaved changes. Would you like to save them?")
            }
            .onAppear {
                loadConsents()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.primary)

            Text("Your Privacy Matters")
                .font(Theme.Typography.title2)

            Text("Control how your data is used within Orion Mail. You can change these settings at any time.")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, Theme.Spacing.md)
    }

    // MARK: - Consent Cards Section

    private var consentCardsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            ForEach(ConsentType.allCases, id: \.self) { consentType in
                ConsentCard(
                    type: consentType,
                    isGranted: Binding(
                        get: { localConsents[consentType] ?? false },
                        set: { newValue in
                            localConsents[consentType] = newValue
                            checkForChanges()
                        }
                    )
                )
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            Divider()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.Colors.primary)
                    Text("About Your Data")
                        .font(Theme.Typography.headline)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    InfoBullet(
                        icon: "lock.shield.fill",
                        text: "Your data is encrypted and stored securely"
                    )
                    InfoBullet(
                        icon: "cpu",
                        text: "AI processing happens on-device when possible"
                    )
                    InfoBullet(
                        icon: "trash.fill",
                        text: "You can delete all your data at any time"
                    )
                    InfoBullet(
                        icon: "arrow.down.doc.fill",
                        text: "Export your data from Settings"
                    )
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )

            // Reset all consents
            Button(action: resetAllConsents) {
                Text("Reset All Consents")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.red)
            }
            .padding(.top, Theme.Spacing.md)
        }
    }

    // MARK: - Actions

    private func loadConsents() {
        for type in ConsentType.allCases {
            localConsents[type] = consentManager.isConsentGranted(type)
        }
    }

    private func checkForChanges() {
        hasChanges = ConsentType.allCases.contains { type in
            localConsents[type] != consentManager.isConsentGranted(type)
        }
    }

    private func saveConsents() {
        Haptics.success()

        for (type, granted) in localConsents {
            consentManager.setConsent(type, granted: granted)
        }

        consentManager.completeInitialConsent()
        hasChanges = false
        dismiss()
    }

    private func resetAllConsents() {
        Haptics.warning()

        for type in ConsentType.allCases {
            localConsents[type] = type.isRequired
        }
        checkForChanges()
    }
}

// MARK: - Consent Card

struct ConsentCard: View {
    let type: ConsentType
    @Binding var isGranted: Bool

    @State private var showDetails = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: Theme.Spacing.md) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconBackgroundColor)
                        .frame(width: 44, height: 44)

                    Image(systemName: type.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isGranted ? .white : .secondary)
                }

                // Content
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    HStack {
                        Text(type.displayName)
                            .font(Theme.Typography.bodyBold)

                        if type.isRequired {
                            Text("Required")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(.white)
                                .padding(.horizontal, Theme.Spacing.xs)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Theme.Colors.primary)
                                )
                        }
                    }

                    Text(type.description)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(showDetails ? nil : 2)
                }

                Spacer()

                // Toggle
                Toggle("", isOn: $isGranted)
                    .labelsHidden()
                    .disabled(type.isRequired)
                    .onChange(of: isGranted) { _, _ in
                        Haptics.selection()
                    }
            }

            // Expand/collapse button
            Button(action: { showDetails.toggle() }) {
                HStack {
                    Spacer()
                    Text(showDetails ? "Show less" : "Learn more")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.primary)
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.sm)

            // Details
            if showDetails {
                ConsentDetails(type: type)
                    .padding(.top, Theme.Spacing.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.card)
                .stroke(isGranted ? Theme.Colors.primary.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .animation(Theme.Animation.defaultSpring, value: showDetails)
    }

    private var iconBackgroundColor: Color {
        if isGranted {
            return Theme.Colors.primary
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.05)
    }
}

// MARK: - Consent Details

struct ConsentDetails: View {
    let type: ConsentType

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Divider()

            Text("What this means:")
                .font(Theme.Typography.captionBold)

            ForEach(detailPoints, id: \.self) { point in
                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.success)
                        .padding(.top, 2)

                    Text(point)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if type.isRequired {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Colors.warning)

                    Text("This consent is required for the app to function properly.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private var detailPoints: [String] {
        switch type {
        case .emailContent:
            return [
                "Access to read and organize your emails",
                "Search functionality across your messages",
                "Spam and security filtering",
                "Email threading and conversation grouping"
            ]
        case .audioCapture:
            return [
                "Voice dictation for composing emails",
                "Voice commands for hands-free operation",
                "Audio is processed on-device when possible",
                "Recordings are not stored permanently"
            ]
        case .aiAnalysis:
            return [
                "Generate email summaries automatically",
                "Suggest relevant replies",
                "Identify action items and deadlines",
                "Smart categorization of emails"
            ]
        case .syncContacts:
            return [
                "Auto-complete when composing emails",
                "Show contact photos in conversations",
                "Better spam detection",
                "Contacts remain on your device"
            ]
        case .usageAnalytics:
            return [
                "Help us improve app performance",
                "Identify and fix bugs faster",
                "Understand feature usage patterns",
                "No personal email content is collected"
            ]
        }
    }
}

// MARK: - Info Bullet

struct InfoBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 20)

            Text(text)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Initial Consent Flow

/// Full-screen initial consent flow for first-time users
struct InitialConsentFlowView: View {
    @EnvironmentObject var consentManager: ConsentManager
    @State private var currentPage = 0
    @State private var localConsents: [ConsentType: Bool] = [:]
    @Environment(\.dismiss) private var dismiss

    private let consentTypes = ConsentType.allCases

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.2),
                    Color.purple.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                // Progress indicator
                ProgressView(value: Double(currentPage + 1), total: Double(consentTypes.count + 1))
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.primary)
                    .padding(.horizontal)

                // Content
                TabView(selection: $currentPage) {
                    // Intro page
                    introPage
                        .tag(0)

                    // Consent pages
                    ForEach(Array(consentTypes.enumerated()), id: \.element) { index, type in
                        consentPage(for: type)
                            .tag(index + 1)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(Theme.Animation.defaultSpring, value: currentPage)

                // Navigation buttons
                navigationButtons
                    .padding(.horizontal)
                    .padding(.bottom)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            // Set required consents by default
            for type in ConsentType.allCases {
                localConsents[type] = type.isRequired
            }
        }
    }

    // MARK: - Intro Page

    private var introPage: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.primary)

            Text("Privacy First")
                .font(Theme.Typography.largeTitle)

            Text("Before you start, let's set up your privacy preferences. You're in control of your data.")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()
        }
    }

    // MARK: - Consent Page

    private func consentPage(for type: ConsentType) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Theme.Colors.primary.opacity(0.2))
                    .frame(width: 100, height: 100)

                Image(systemName: type.iconName)
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primary)
            }

            // Title
            VStack(spacing: Theme.Spacing.sm) {
                Text(type.displayName)
                    .font(Theme.Typography.title)

                if type.isRequired {
                    Text("Required")
                        .font(Theme.Typography.captionBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.primary)
                        )
                }
            }

            // Description
            Text(type.description)
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            Spacer()

            // Toggle
            if !type.isRequired {
                GlassCard {
                    Toggle(isOn: Binding(
                        get: { localConsents[type] ?? false },
                        set: { localConsents[type] = $0 }
                    )) {
                        Text("Enable \(type.displayName)")
                            .font(Theme.Typography.bodyBold)
                    }
                }
                .padding(.horizontal)
            } else {
                Text("This permission is required to use the app.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: Theme.Spacing.md) {
            if currentPage > 0 {
                Button(action: goBack) {
                    Text("Back")
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.button)
                                .fill(.ultraThinMaterial)
                        )
                }
                .buttonStyle(.plain)
            }

            Button(action: goNext) {
                Text(currentPage == consentTypes.count ? "Get Started" : "Continue")
                    .font(Theme.Typography.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.button)
                            .fill(Theme.Colors.primary)
                    )
            }
            .buttonStyle(GlassButtonStyle())
        }
    }

    // MARK: - Actions

    private func goBack() {
        Haptics.light()
        withAnimation(Theme.Animation.defaultSpring) {
            currentPage -= 1
        }
    }

    private func goNext() {
        Haptics.medium()

        if currentPage == consentTypes.count {
            // Save and complete
            for (type, granted) in localConsents {
                consentManager.setConsent(type, granted: granted)
            }
            consentManager.completeInitialConsent()
            dismiss()
        } else {
            withAnimation(Theme.Animation.defaultSpring) {
                currentPage += 1
            }
        }
    }
}

// MARK: - Preview

#Preview("Consent Flow") {
    ConsentFlowView()
        .environmentObject(ConsentManager())
}

#Preview("Initial Consent Flow") {
    InitialConsentFlowView()
        .environmentObject(ConsentManager())
}
