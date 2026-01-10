import SwiftUI

// MARK: - Email App Entry Point (not used when CalendarAppApp is the main entry)

// @main - Disabled since CalendarAppApp is now the main entry point
struct EmailAppApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @StateObject private var consentManager = ConsentManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(authManager)
                .environmentObject(consentManager)
                .preferredColorScheme(appState.colorScheme)
        }
    }
}

// MARK: - Content View

/// Main content view that handles navigation based on auth state
struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var consentManager: ConsentManager

    @State private var showMailbox = false
    @State private var showCompose = false
    @State private var showSettings = false
    @State private var selectedThread: EmailThread?
    @State private var searchText = ""

    var body: some View {
        Group {
            switch authManager.authState {
            case .unknown:
                LoadingView()
            case .unauthenticated:
                WelcomeView()
            case .authenticating:
                LoadingView(message: "Signing in...")
            case .authenticated(let account):
                MainAppView(
                    account: account,
                    showMailbox: $showMailbox,
                    showCompose: $showCompose,
                    showSettings: $showSettings,
                    selectedThread: $selectedThread
                )
            case .error(let message):
                ErrorView(message: message) {
                    authManager.retry()
                }
            }
        }
        .animation(Theme.Animation.defaultSpring, value: authManager.authState)
        .onAppear {
            authManager.checkAuthState()
        }
    }
}

// MARK: - Main App View

struct MainAppView: View {
    let account: EmailAccount
    @Binding var showMailbox: Bool
    @Binding var showCompose: Bool
    @Binding var showSettings: Bool
    @Binding var selectedThread: EmailThread?

    @StateObject private var threadListVM = ThreadListViewModel()
    @State private var selectedLabel: EmailLabel = .inbox
    @State private var showSearch = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                // Background gradient
                backgroundGradient
                    .ignoresSafeArea()

                // Main content
                ThreadListView(
                    viewModel: threadListVM,
                    selectedLabel: selectedLabel,
                    onThreadSelected: { thread in
                        selectedThread = thread
                        navigationPath.append(thread)
                    },
                    onComposeTapped: {
                        showCompose = true
                    },
                    onMenuTapped: {
                        showMailbox = true
                    },
                    onSearchTapped: {
                        showSearch = true
                    }
                )
            }
            .navigationDestination(for: EmailThread.self) { thread in
                ThreadDetailView(thread: thread)
            }
        }
        .sheet(isPresented: $showMailbox) {
            MailboxView(
                selectedLabel: $selectedLabel,
                account: account
            ) {
                showMailbox = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(
                replyToThread: nil,
                onDismiss: {
                    showCompose = false
                }
            )
        }
        .sheet(isPresented: $showSearch) {
            SearchView(
                onThreadSelected: { thread in
                    showSearch = false
                    selectedThread = thread
                    navigationPath.append(thread)
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: selectedLabel) { _, _ in
            threadListVM.loadThreads(labelId: selectedLabel.id)
        }
        .onAppear {
            threadListVM.loadThreads(labelId: selectedLabel.id)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                Color(uiColor: .systemBackground).opacity(0.95)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Theme.Colors.primary)

                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Animated background
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.3),
                    Color.purple.opacity(0.3),
                    Color.pink.opacity(0.2)
                ],
                startPoint: isAnimating ? .topLeading : .bottomTrailing,
                endPoint: isAnimating ? .bottomTrailing : .topLeading
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 5).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: Theme.Spacing.xxl) {
                Spacer()

                // Logo/Icon
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.primary)
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)

                    Text("Orion Mail")
                        .font(Theme.Typography.largeTitle)

                    Text("Your intelligent email companion")
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, Theme.Spacing.xxl)

                Spacer()

                // Features
                VStack(spacing: Theme.Spacing.md) {
                    FeatureRow(
                        icon: "sparkles",
                        title: "AI-Powered",
                        description: "Smart summaries and suggested replies"
                    )

                    FeatureRow(
                        icon: "lock.shield.fill",
                        title: "Privacy First",
                        description: "Your data stays on your device"
                    )

                    FeatureRow(
                        icon: "bolt.fill",
                        title: "Lightning Fast",
                        description: "Instant search across all emails"
                    )
                }
                .padding(.horizontal, Theme.Spacing.xl)

                Spacer()

                // Sign in buttons
                VStack(spacing: Theme.Spacing.md) {
                    SignInButton(
                        provider: .gmail,
                        action: { authManager.signIn(with: .gmail) }
                    )

                    SignInButton(
                        provider: .outlook,
                        action: { authManager.signIn(with: .outlook) }
                    )

                    Button("Sign in with other email") {
                        authManager.signIn(with: .other)
                    }
                    .font(Theme.Typography.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.Colors.primary)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.bodyBold)
                Text(description)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .glassMorphism()
    }
}

struct SignInButton: View {
    let provider: EmailAccount.EmailProvider
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.medium()
            action()
        }) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: provider.iconName)
                    .font(.system(size: 20))
                Text("Sign in with \(provider.displayName)")
                    .font(Theme.Typography.bodyBold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.button)
                    .fill(providerColor)
            )
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var providerColor: Color {
        switch provider {
        case .gmail: return Color(hex: "#EA4335") ?? .red
        case .outlook: return Color(hex: "#0078D4") ?? .blue
        case .icloud: return Color(hex: "#007AFF") ?? .blue
        case .other: return Theme.Colors.primary
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.error)

                Text("Something went wrong")
                    .font(Theme.Typography.title2)

                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Spacing.xl)

                Button(action: {
                    Haptics.medium()
                    retryAction()
                }) {
                    Text("Try Again")
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.primary)
                        )
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, Theme.Spacing.md)
            }
        }
    }
}

// MARK: - App State

/// Global app state management
@MainActor
class AppState: ObservableObject {
    @Published var colorScheme: ColorScheme?
    @Published var isOnboardingComplete: Bool
    @Published var selectedAccountId: String?

    init() {
        self.colorScheme = nil // Follows system
        self.isOnboardingComplete = UserDefaults.standard.bool(forKey: "isOnboardingComplete")
        self.selectedAccountId = UserDefaults.standard.string(forKey: "selectedAccountId")
    }

    func setColorScheme(_ scheme: ColorScheme?) {
        colorScheme = scheme
    }

    func completeOnboarding() {
        isOnboardingComplete = true
        UserDefaults.standard.set(true, forKey: "isOnboardingComplete")
    }

    func selectAccount(_ accountId: String) {
        selectedAccountId = accountId
        UserDefaults.standard.set(accountId, forKey: "selectedAccountId")
    }
}

// MARK: - Auth Manager

/// Manages authentication state
@MainActor
class AuthManager: ObservableObject {
    @Published var authState: AuthState = .unknown
    @Published var accounts: [EmailAccount] = []

    private let emailAPI: EmailAPIProtocol

    init(emailAPI: EmailAPIProtocol = ConvexEmailAPI()) {
        self.emailAPI = emailAPI
    }

    func checkAuthState() {
        // Simulate checking stored credentials
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)

            // For demo purposes, auto-authenticate with mock account
            #if DEBUG
            authState = .authenticated(.mock)
            accounts = [.mock]
            #else
            authState = .unauthenticated
            #endif
        }
    }

    func signIn(with provider: EmailAccount.EmailProvider) {
        authState = .authenticating

        Task {
            do {
                // Simulate OAuth flow
                try await Task.sleep(nanoseconds: 1_500_000_000)

                let account = EmailAccount(
                    id: UUID().uuidString,
                    email: "user@\(provider.rawValue).com",
                    displayName: "User",
                    avatarURL: nil,
                    provider: provider,
                    isActive: true,
                    lastSyncedAt: Date()
                )

                accounts.append(account)
                authState = .authenticated(account)
            } catch {
                authState = .error("Failed to sign in. Please try again.")
            }
        }
    }

    func signOut() {
        accounts.removeAll()
        authState = .unauthenticated
    }

    func retry() {
        checkAuthState()
    }
}

// MARK: - Consent Manager

/// Manages user consent for data processing
@MainActor
class ConsentManager: ObservableObject {
    @Published var consents: [ConsentType: Bool] = [:]
    @Published var hasCompletedInitialConsent: Bool = false

    init() {
        loadConsents()
    }

    func loadConsents() {
        for type in ConsentType.allCases {
            consents[type] = UserDefaults.standard.bool(forKey: "consent.\(type.rawValue)")
        }
        hasCompletedInitialConsent = UserDefaults.standard.bool(forKey: "consent.completed")
    }

    func setConsent(_ type: ConsentType, granted: Bool) {
        consents[type] = granted
        UserDefaults.standard.set(granted, forKey: "consent.\(type.rawValue)")
    }

    func isConsentGranted(_ type: ConsentType) -> Bool {
        consents[type] ?? false
    }

    func completeInitialConsent() {
        hasCompletedInitialConsent = true
        UserDefaults.standard.set(true, forKey: "consent.completed")
    }

    func resetAllConsents() {
        for type in ConsentType.allCases {
            consents[type] = false
            UserDefaults.standard.removeObject(forKey: "consent.\(type.rawValue)")
        }
        hasCompletedInitialConsent = false
        UserDefaults.standard.removeObject(forKey: "consent.completed")
    }
}

// MARK: - Preview

#Preview("Main App") {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(AuthManager())
        .environmentObject(ConsentManager())
}

#Preview("Welcome View") {
    WelcomeView()
        .environmentObject(AuthManager())
}

#Preview("Loading View") {
    LoadingView(message: "Signing in...")
}

#Preview("Error View") {
    ErrorView(message: "Unable to connect to the server. Please check your internet connection and try again.") {}
}
