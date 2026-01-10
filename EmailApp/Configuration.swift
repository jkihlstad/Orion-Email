import Foundation

/// App-wide configuration loaded from environment or Info.plist
enum Configuration {

    // MARK: - Keys

    private enum Keys {
        static let convexURL = "CONVEX_URL"
        static let clerkPublishableKey = "CLERK_PUBLISHABLE_KEY"
        static let clerkFrontendAPI = "CLERK_FRONTEND_API"
        static let brainAPIURL = "BRAIN_API_URL"
        static let openAIAPIKey = "OPENAI_API_KEY"
        static let bundleID = "CFBundleIdentifier"
    }

    // MARK: - Convex

    static var convexURL: URL {
        guard let urlString = value(for: Keys.convexURL),
              let url = URL(string: urlString) else {
            fatalError("CONVEX_URL not configured")
        }
        return url
    }

    // MARK: - Clerk Authentication

    static var clerkPublishableKey: String {
        guard let key = value(for: Keys.clerkPublishableKey) else {
            fatalError("CLERK_PUBLISHABLE_KEY not configured")
        }
        return key
    }

    static var clerkFrontendAPI: String {
        value(for: Keys.clerkFrontendAPI) ?? "clerk.example.com"
    }

    // MARK: - Brain API

    static var brainAPIURL: URL? {
        guard let urlString = value(for: Keys.brainAPIURL),
              let url = URL(string: urlString) else {
            return nil
        }
        return url
    }

    // MARK: - OpenAI

    static var openAIAPIKey: String? {
        value(for: Keys.openAIAPIKey)
    }

    // MARK: - App Info

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.orion.emailapp"
    }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Feature Flags

    static var isAISummariesEnabled: Bool {
        boolValue(for: "FEATURE_AI_SUMMARIES") ?? true
    }

    static var isSuggestedRepliesEnabled: Bool {
        boolValue(for: "FEATURE_SUGGESTED_REPLIES") ?? true
    }

    static var isVoiceDictationEnabled: Bool {
        boolValue(for: "FEATURE_VOICE_DICTATION") ?? true
    }

    static var isTTSReadAloudEnabled: Bool {
        boolValue(for: "FEATURE_TTS_READ_ALOUD") ?? true
    }

    static var isSmartSearchEnabled: Bool {
        boolValue(for: "FEATURE_SMART_SEARCH") ?? true
    }

    // MARK: - Debug

    static var isDebugLoggingEnabled: Bool {
        #if DEBUG
        return boolValue(for: "DEBUG_LOGGING") ?? true
        #else
        return boolValue(for: "DEBUG_LOGGING") ?? false
        #endif
    }

    static var useMockData: Bool {
        #if DEBUG
        return boolValue(for: "USE_MOCK_DATA") ?? false
        #else
        return false
        #endif
    }

    // MARK: - Networking

    static var apiTimeout: TimeInterval {
        TimeInterval(intValue(for: "API_TIMEOUT") ?? 30)
    }

    static var maxRetries: Int {
        intValue(for: "MAX_RETRIES") ?? 3
    }

    // MARK: - Storage Keys

    enum StorageKeys {
        static let appGroup = "group.com.orion.emailapp"
        static let keychainService = "com.orion.emailapp.keychain"
        static let authTokenKey = "clerk_session_token"
        static let refreshTokenKey = "clerk_refresh_token"
        static let userConsentsKey = "user_consents"
        static let selectedAccountKey = "selected_account_id"
        static let recentSearchesKey = "recent_searches"
        static let lastSyncTimestampKey = "last_sync_timestamp"
    }

    // MARK: - Background Tasks

    enum BackgroundTasks {
        static let refreshIdentifier = "com.orion.emailapp.refresh"
        static let syncIdentifier = "com.orion.emailapp.sync"
        static let cleanupIdentifier = "com.orion.emailapp.cleanup"
    }

    // MARK: - API Endpoints

    enum Endpoints {
        static let listThreads = "/email/sync/listThreads"
        static let getThread = "/email/sync/getThread"
        static let applyAction = "/email/actions/apply"
        static let createDraft = "/email/send/createDraft"
        static let updateDraft = "/email/send/updateDraft"
        static let sendDraft = "/email/send/sendDraft"
        static let getLabels = "/email/labels"
        static let createLabel = "/email/labels/create"
        static let deleteLabel = "/email/labels"
        static let ingestBatch = "/email/ingest/insertBatch"

        // Brain/AI endpoints
        static let summarizeThread = "/ai/email/summarize"
        static let suggestReplies = "/ai/email/replies"
        static let extractTasks = "/ai/email/tasks"
        static let askAboutEmail = "/ai/email/ask"
        static let getRelatedMemories = "/ai/email/memories"

        // Voice endpoints
        static let transcribeAudio = "/ai/voice/transcribe"
        static let synthesizeSpeech = "/ai/voice/tts"
    }

    // MARK: - Defaults

    enum Defaults {
        static let pageSize = 50
        static let maxPageSize = 100
        static let cacheExpirationSeconds: TimeInterval = 300 // 5 minutes
        static let syncIntervalSeconds: TimeInterval = 300 // 5 minutes
        static let maxRecentSearches = 10
        static let maxPendingActions = 100
    }

    // MARK: - Private Helpers

    private static func value(for key: String) -> String? {
        // First check ProcessInfo environment
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }

        // Then check Info.plist
        if let value = Bundle.main.infoDictionary?[key] as? String, !value.isEmpty {
            return value
        }

        return nil
    }

    private static func boolValue(for key: String) -> Bool? {
        guard let value = value(for: key) else { return nil }
        return value.lowercased() == "true" || value == "1"
    }

    private static func intValue(for key: String) -> Int? {
        guard let value = value(for: key) else { return nil }
        return Int(value)
    }
}

// MARK: - Environment

enum AppEnvironment {
    case development
    case staging
    case production

    static var current: AppEnvironment {
        #if DEBUG
        return .development
        #else
        if Configuration.convexURL.absoluteString.contains("staging") {
            return .staging
        }
        return .production
        #endif
    }

    var name: String {
        switch self {
        case .development: return "Development"
        case .staging: return "Staging"
        case .production: return "Production"
        }
    }
}
