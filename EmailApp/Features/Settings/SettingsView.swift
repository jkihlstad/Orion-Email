import SwiftUI

// MARK: - Settings View

/// Settings screen with account management, preferences, and privacy controls
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var consentManager: ConsentManager

    @State private var showConsentFlow = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var notificationsEnabled = true
    @State private var aiFeatureEnabled = true
    @State private var voiceFeatureEnabled = true
    @State private var selectedTheme: ThemeOption = .system
    @State private var swipeLeftAction: SwipeAction = .archive
    @State private var swipeRightAction: SwipeAction = .delete
    @Environment(\.dismiss) private var dismiss

    enum ThemeOption: String, CaseIterable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
    }

    enum SwipeAction: String, CaseIterable {
        case archive = "Archive"
        case delete = "Delete"
        case markRead = "Mark Read"
        case star = "Star"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()

                Form {
                    // Account Section
                    accountSection

                    // Notifications Section
                    notificationsSection

                    // AI & Voice Features Section
                    aiVoiceSection

                    // Appearance Section
                    appearanceSection

                    // Gestures Section
                    gesturesSection

                    // Privacy Section
                    privacySection

                    // About Section
                    aboutSection

                    // Sign Out Section
                    signOutSection
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showConsentFlow) {
                ConsentFlowView()
            }
            .alert("Sign Out", isPresented: $showSignOutConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    signOut()
                }
            } message: {
                Text("Are you sure you want to sign out? You will need to sign in again to access your emails.")
            }
            .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Account", role: .destructive) {
                    deleteAccount()
                }
            } message: {
                Text("This will permanently delete your account and all associated data. This action cannot be undone.")
            }
        }
    }

    // MARK: - Account Section

    private var accountSection: some View {
        Section {
            // Primary account
            if case .authenticated(let account) = authManager.authState {
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        AccountAvatar(account: account, size: 48)

                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(account.displayName)
                                .font(Theme.Typography.bodyBold)
                            Text(account.email)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }

            // Add account
            Button(action: addAccount) {
                Label("Add another account", systemImage: "plus.circle")
            }
        } header: {
            Text("Account")
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $notificationsEnabled) {
                Label("Push Notifications", systemImage: "bell.fill")
            }
            .onChange(of: notificationsEnabled) { _, _ in
                Haptics.selection()
            }

            if notificationsEnabled {
                NavigationLink {
                    NotificationPreferencesView()
                } label: {
                    Label("Notification Preferences", systemImage: "slider.horizontal.3")
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Get notified about new emails and important updates.")
        }
    }

    // MARK: - AI & Voice Section

    private var aiVoiceSection: some View {
        Section {
            Toggle(isOn: $aiFeatureEnabled) {
                Label {
                    VStack(alignment: .leading) {
                        Text("AI Features")
                        Text("Summaries, suggested replies")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "sparkles")
                }
            }
            .onChange(of: aiFeatureEnabled) { _, newValue in
                Haptics.selection()
                consentManager.setConsent(.aiAnalysis, granted: newValue)
            }

            Toggle(isOn: $voiceFeatureEnabled) {
                Label {
                    VStack(alignment: .leading) {
                        Text("Voice Features")
                        Text("Dictation, voice commands")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "mic.fill")
                }
            }
            .onChange(of: voiceFeatureEnabled) { _, newValue in
                Haptics.selection()
                consentManager.setConsent(.audioCapture, granted: newValue)
            }
        } header: {
            Text("AI & Voice")
        } footer: {
            Text("These features use on-device processing when possible. See Privacy for more details.")
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section {
            Picker("Theme", selection: $selectedTheme) {
                ForEach(ThemeOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .onChange(of: selectedTheme) { _, newValue in
                Haptics.selection()
                updateTheme(newValue)
            }

            NavigationLink {
                SignatureSettingsView()
            } label: {
                Label("Email Signature", systemImage: "signature")
            }
        } header: {
            Text("Appearance")
        }
    }

    // MARK: - Gestures Section

    private var gesturesSection: some View {
        Section {
            Picker("Swipe Left", selection: $swipeLeftAction) {
                ForEach(SwipeAction.allCases, id: \.self) { action in
                    Text(action.rawValue).tag(action)
                }
            }

            Picker("Swipe Right", selection: $swipeRightAction) {
                ForEach(SwipeAction.allCases, id: \.self) { action in
                    Text(action.rawValue).tag(action)
                }
            }
        } header: {
            Text("Gestures")
        } footer: {
            Text("Customize swipe actions for email rows.")
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            Button(action: { showConsentFlow = true }) {
                Label {
                    HStack {
                        Text("Manage Consents")
                        Spacer()
                        Text("\(activeConsentsCount) active")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "hand.raised.fill")
                }
            }
            .foregroundStyle(.primary)

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Privacy Policy", systemImage: "doc.text.fill")
            }

            NavigationLink {
                TermsOfServiceView()
            } label: {
                Label("Terms of Service", systemImage: "doc.plaintext.fill")
            }

            NavigationLink {
                DataExportView()
            } label: {
                Label("Export My Data", systemImage: "square.and.arrow.up.fill")
            }
        } header: {
            Text("Privacy & Data")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0 (1)")
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                LicensesView()
            } label: {
                Text("Open Source Licenses")
            }

            Button(action: openSupport) {
                Label("Help & Support", systemImage: "questionmark.circle.fill")
            }
            .foregroundStyle(.primary)

            Button(action: rateApp) {
                Label("Rate Orion Mail", systemImage: "star.fill")
            }
            .foregroundStyle(.primary)
        } header: {
            Text("About")
        }
    }

    // MARK: - Sign Out Section

    private var signOutSection: some View {
        Section {
            Button(action: { showSignOutConfirmation = true }) {
                HStack {
                    Spacer()
                    Text("Sign Out")
                        .foregroundStyle(.red)
                    Spacer()
                }
            }

            Button(action: { showDeleteAccountConfirmation = true }) {
                HStack {
                    Spacer()
                    Text("Delete Account")
                        .foregroundStyle(.red)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var activeConsentsCount: Int {
        consentManager.consents.filter { $0.value }.count
    }

    // MARK: - Actions

    private func addAccount() {
        Haptics.light()
        // Would open add account flow
    }

    private func updateTheme(_ theme: ThemeOption) {
        switch theme {
        case .system:
            appState.setColorScheme(nil)
        case .light:
            appState.setColorScheme(.light)
        case .dark:
            appState.setColorScheme(.dark)
        }
    }

    private func signOut() {
        Haptics.warning()
        authManager.signOut()
        dismiss()
    }

    private func deleteAccount() {
        Haptics.error()
        // Would delete account
        authManager.signOut()
        dismiss()
    }

    private func openSupport() {
        Haptics.light()
        // Would open support URL
    }

    private func rateApp() {
        Haptics.light()
        // Would open App Store rating
    }
}

// MARK: - Account Detail View

struct AccountDetailView: View {
    let account: EmailAccount

    @State private var autoSync = true
    @State private var syncFrequency = "15 minutes"
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            // Account info
            Section {
                HStack {
                    Text("Email")
                    Spacer()
                    Text(account.email)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Provider")
                    Spacer()
                    Text(account.provider.displayName)
                        .foregroundStyle(.secondary)
                }

                if let lastSync = account.lastSyncedAt {
                    HStack {
                        Text("Last Synced")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Sync settings
            Section("Sync") {
                Toggle("Auto Sync", isOn: $autoSync)

                if autoSync {
                    Picker("Sync Frequency", selection: $syncFrequency) {
                        Text("5 minutes").tag("5 minutes")
                        Text("15 minutes").tag("15 minutes")
                        Text("30 minutes").tag("30 minutes")
                        Text("1 hour").tag("1 hour")
                    }
                }

                Button(action: syncNow) {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            // Danger zone
            Section {
                Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                    Label("Remove Account", systemImage: "trash")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(account.displayName)
        .alert("Remove Account?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                removeAccount()
            }
        } message: {
            Text("This will remove the account from this device. Your emails will remain on the server.")
        }
    }

    private func syncNow() {
        Haptics.light()
        // Would trigger sync
    }

    private func removeAccount() {
        Haptics.warning()
        // Would remove account
        dismiss()
    }
}

// MARK: - Notification Preferences View

struct NotificationPreferencesView: View {
    @State private var newEmailNotifications = true
    @State private var importantEmailNotifications = true
    @State private var soundEnabled = true
    @State private var badgeEnabled = true

    var body: some View {
        Form {
            Section("Email Notifications") {
                Toggle("All New Emails", isOn: $newEmailNotifications)
                Toggle("Important Only", isOn: $importantEmailNotifications)
            }

            Section("Notification Style") {
                Toggle("Sound", isOn: $soundEnabled)
                Toggle("Badge Count", isOn: $badgeEnabled)
            }
        }
        .navigationTitle("Notification Preferences")
    }
}

// MARK: - Signature Settings View

struct SignatureSettingsView: View {
    @State private var signatureEnabled = true
    @State private var signatureText = "Sent from Orion Mail"

    var body: some View {
        Form {
            Section {
                Toggle("Use Signature", isOn: $signatureEnabled)
            }

            if signatureEnabled {
                Section("Signature") {
                    TextEditor(text: $signatureText)
                        .frame(minHeight: 100)
                }
            }
        }
        .navigationTitle("Email Signature")
    }
}

// MARK: - Privacy Policy View

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Privacy Policy")
                    .font(Theme.Typography.title)

                Text("Last updated: January 2025")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)

                Text("""
                Your privacy is important to us. This Privacy Policy explains how Orion Mail collects, uses, and protects your personal information.

                1. Data Collection
                We collect only the information necessary to provide you with email services. This includes your email address, contacts, and email content.

                2. Data Usage
                Your data is used solely to provide email functionality, AI-powered features (with your consent), and to improve the app experience.

                3. Data Storage
                Your emails are stored securely using industry-standard encryption. AI processing is performed on-device when possible.

                4. Third-Party Services
                We use secure APIs to connect to email providers like Gmail and Outlook. We do not sell your data to third parties.

                5. Your Rights
                You can export your data, revoke consents, or delete your account at any time from the Settings menu.
                """)
                .font(Theme.Typography.body)
            }
            .padding()
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Terms of Service View

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Terms of Service")
                    .font(Theme.Typography.title)

                Text("Last updated: January 2025")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)

                Text("""
                By using Orion Mail, you agree to these Terms of Service.

                1. Acceptable Use
                You agree to use Orion Mail for lawful purposes only and not to send spam or malicious content.

                2. Account Responsibility
                You are responsible for maintaining the security of your account credentials.

                3. Service Availability
                We strive to provide reliable service but cannot guarantee 100% uptime.

                4. Intellectual Property
                Orion Mail and its design are protected by copyright and trademark laws.

                5. Limitation of Liability
                We are not liable for any indirect damages arising from the use of our service.

                6. Changes to Terms
                We may update these terms from time to time. Continued use constitutes acceptance.
                """)
                .font(Theme.Typography.body)
            }
            .padding()
        }
        .navigationTitle("Terms of Service")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data Export View

struct DataExportView: View {
    @State private var isExporting = false
    @State private var exportComplete = false

    var body: some View {
        Form {
            Section {
                Text("Export all your emails, contacts, and settings to a downloadable file.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(action: exportData) {
                    HStack {
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, Theme.Spacing.xs)
                        }
                        Text(isExporting ? "Exporting..." : "Export My Data")
                    }
                }
                .disabled(isExporting)
            }

            if exportComplete {
                Section {
                    Label("Export complete! Check your downloads.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("Export Data")
    }

    private func exportData() {
        isExporting = true

        // Simulate export
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isExporting = false
            exportComplete = true
            Haptics.success()
        }
    }
}

// MARK: - Licenses View

struct LicensesView: View {
    var body: some View {
        List {
            LicenseRow(name: "Swift", license: "Apache 2.0")
            LicenseRow(name: "SwiftUI", license: "Apple Inc.")
        }
        .navigationTitle("Open Source Licenses")
    }
}

struct LicenseRow: View {
    let name: String
    let license: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(name)
                .font(Theme.Typography.bodyBold)
            Text(license)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Settings") {
    SettingsView()
        .environmentObject(AppState())
        .environmentObject(AuthManager())
        .environmentObject(ConsentManager())
}
