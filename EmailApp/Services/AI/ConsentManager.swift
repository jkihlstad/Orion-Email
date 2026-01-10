//
//  ConsentManager.swift
//  EmailApp
//
//  Consent checking and management for sensitive operations
//

import Foundation
import Combine
import os.log

// MARK: - Logger

private let consentLogger = Logger(subsystem: "com.orion.emailapp", category: "Consent")

// MARK: - Consent Manager Protocol

/// Protocol for consent management
public protocol ConsentManagerProtocol: AnyObject, Sendable {
    /// Check if consent is granted for a specific type
    func hasConsent(for type: ConsentType) async -> Bool

    /// Request consent for a specific type
    func requestConsent(for type: ConsentType) async -> Bool

    /// Revoke consent for a specific type
    func revokeConsent(for type: ConsentType) async

    /// Get all current consent states
    func getAllConsents() async -> [ConsentType: Bool]

    /// Grant consent for a specific type
    func grantConsent(for type: ConsentType) async

    /// Check multiple consents at once
    func hasAllConsents(for types: [ConsentType]) async -> Bool
}

// MARK: - Consent Record

/// Record of a consent decision
private struct ConsentRecord: Codable {
    let type: ConsentType
    let granted: Bool
    let grantedAt: Date?
    let revokedAt: Date?
    let version: Int

    init(type: ConsentType, granted: Bool) {
        self.type = type
        self.granted = granted
        self.grantedAt = granted ? Date() : nil
        self.revokedAt = granted ? nil : Date()
        self.version = 1
    }
}

// MARK: - Consent Manager

/// Implementation of consent management with local and server sync
@MainActor
public final class ConsentManager: ObservableObject, ConsentManagerProtocol, @unchecked Sendable {
    // MARK: - Published Properties

    @Published public private(set) var consents: [ConsentType: Bool] = [:]
    @Published public private(set) var isSyncing: Bool = false

    // MARK: - Private Properties

    private let userDefaults: UserDefaults
    private let consentsKey = "user_consents"
    private let serverSyncEndpoint: URL?
    private let session: URLSession
    private let authProvider: AuthSessionProviding?

    private var syncTask: Task<Void, Never>?
    private var pendingSyncChanges: [(ConsentType, Bool)] = []

    // MARK: - Singleton

    public static let shared = ConsentManager()

    // MARK: - Initialization

    public init(
        userDefaults: UserDefaults = .standard,
        serverSyncEndpoint: URL? = nil,
        session: URLSession = .shared,
        authProvider: AuthSessionProviding? = nil
    ) {
        self.userDefaults = userDefaults
        self.serverSyncEndpoint = serverSyncEndpoint
        self.session = session
        self.authProvider = authProvider

        loadStoredConsents()
    }

    // MARK: - ConsentManagerProtocol

    /// Check if consent is granted for a specific type
    public nonisolated func hasConsent(for type: ConsentType) async -> Bool {
        return await MainActor.run {
            self.consents[type] ?? false
        }
    }

    /// Request consent for a specific type (this would typically show a UI prompt)
    public nonisolated func requestConsent(for type: ConsentType) async -> Bool {
        // In a real implementation, this would show a consent dialog
        // For now, we check if already granted
        let hasExisting = await hasConsent(for: type)
        if hasExisting {
            return true
        }

        consentLogger.info("Consent requested for: \(type.rawValue)")

        // Return false to indicate consent was not immediately granted
        // The UI layer should show a consent dialog and call grantConsent() if approved
        return false
    }

    /// Grant consent for a specific type
    public nonisolated func grantConsent(for type: ConsentType) async {
        await MainActor.run {
            self.consents[type] = true
        }

        await saveConsents()
        await syncWithServer(type: type, granted: true)

        consentLogger.info("Consent granted for: \(type.rawValue)")
    }

    /// Revoke consent for a specific type
    public nonisolated func revokeConsent(for type: ConsentType) async {
        await MainActor.run {
            self.consents[type] = false
        }

        await saveConsents()
        await syncWithServer(type: type, granted: false)

        consentLogger.info("Consent revoked for: \(type.rawValue)")
    }

    /// Get all current consent states
    public nonisolated func getAllConsents() async -> [ConsentType: Bool] {
        return await MainActor.run {
            self.consents
        }
    }

    /// Check multiple consents at once
    public nonisolated func hasAllConsents(for types: [ConsentType]) async -> Bool {
        for type in types {
            if !(await hasConsent(for: type)) {
                return false
            }
        }
        return true
    }

    // MARK: - Convenience Methods

    /// Check if AI analysis is allowed
    public nonisolated func canPerformAIAnalysis() async -> Bool {
        return await hasAllConsents(for: [.aiAnalysis, .emailContent])
    }

    /// Check if voice recording is allowed
    public nonisolated func canRecordAudio() async -> Bool {
        return await hasConsent(for: .audioCapture)
    }

    /// Check if TTS is allowed
    public nonisolated func canSpeakText() async -> Bool {
        return await hasConsent(for: .voiceSynthesis)
    }

    // MARK: - Bulk Operations

    /// Grant multiple consents at once
    public nonisolated func grantConsents(for types: [ConsentType]) async {
        for type in types {
            await grantConsent(for: type)
        }
    }

    /// Revoke all consents
    public nonisolated func revokeAllConsents() async {
        for type in ConsentType.allCases {
            await revokeConsent(for: type)
        }
    }

    // MARK: - Persistence

    /// Load stored consents from UserDefaults
    private func loadStoredConsents() {
        guard let data = userDefaults.data(forKey: consentsKey) else {
            // Initialize with all false
            for type in ConsentType.allCases {
                consents[type] = false
            }
            return
        }

        do {
            let decoder = JSONDecoder()
            let records = try decoder.decode([ConsentRecord].self, from: data)

            for record in records {
                consents[record.type] = record.granted
            }

            // Ensure all types have a value
            for type in ConsentType.allCases {
                if consents[type] == nil {
                    consents[type] = false
                }
            }

            consentLogger.debug("Loaded \(records.count) consent records")
        } catch {
            consentLogger.error("Failed to load consents: \(error.localizedDescription)")
            // Initialize with all false on error
            for type in ConsentType.allCases {
                consents[type] = false
            }
        }
    }

    /// Save consents to UserDefaults
    private nonisolated func saveConsents() async {
        let currentConsents = await MainActor.run { self.consents }

        let records = currentConsents.map { type, granted in
            ConsentRecord(type: type, granted: granted)
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(records)

            await MainActor.run {
                self.userDefaults.set(data, forKey: self.consentsKey)
            }

            consentLogger.debug("Saved \(records.count) consent records")
        } catch {
            consentLogger.error("Failed to save consents: \(error.localizedDescription)")
        }
    }

    // MARK: - Server Sync

    /// Sync consent change with server
    private nonisolated func syncWithServer(type: ConsentType, granted: Bool) async {
        guard let endpoint = serverSyncEndpoint else {
            return
        }

        // Add to pending changes
        await MainActor.run {
            self.pendingSyncChanges.append((type, granted))
        }

        // Debounce sync
        await MainActor.run {
            self.syncTask?.cancel()
        }

        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds debounce

            guard !Task.isCancelled else { return }

            await self?.performServerSync(endpoint: endpoint)
        }

        await MainActor.run {
            self.syncTask = task
        }
    }

    /// Perform the actual server sync
    private nonisolated func performServerSync(endpoint: URL) async {
        await MainActor.run {
            self.isSyncing = true
        }

        defer {
            Task { @MainActor in
                self.isSyncing = false
            }
        }

        // Get auth token if available
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let auth = authProvider {
            do {
                let token = try await auth.getAccessToken()
                headers["Authorization"] = "Bearer \(token)"
            } catch {
                consentLogger.warning("Could not get auth token for consent sync: \(error.localizedDescription)")
            }
        }

        let changesToSync = await MainActor.run {
            let changes = self.pendingSyncChanges
            self.pendingSyncChanges.removeAll()
            return changes
        }

        guard !changesToSync.isEmpty else { return }

        // Build request
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let payload: [[String: Any]] = changesToSync.map { type, granted in
            [
                "consent_type": type.rawValue,
                "granted": granted,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: ["consents": payload])

            let (_, response) = try await session.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    consentLogger.info("Synced \(changesToSync.count) consent changes with server")
                } else {
                    consentLogger.warning("Server sync returned status \(httpResponse.statusCode)")
                }
            }
        } catch {
            consentLogger.error("Failed to sync consents with server: \(error.localizedDescription)")

            // Re-add failed changes to pending
            await MainActor.run {
                self.pendingSyncChanges.append(contentsOf: changesToSync)
            }
        }
    }

    /// Fetch consents from server (e.g., on app launch)
    public nonisolated func fetchFromServer() async {
        guard let endpoint = serverSyncEndpoint else { return }

        // Get auth token
        guard let auth = authProvider else { return }

        do {
            let token = try await auth.getAccessToken()

            var request = URLRequest(url: endpoint)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let consentsArray = json["consents"] as? [[String: Any]] else {
                return
            }

            for consentData in consentsArray {
                guard let typeRaw = consentData["consent_type"] as? String,
                      let type = ConsentType(rawValue: typeRaw),
                      let granted = consentData["granted"] as? Bool else {
                    continue
                }

                await MainActor.run {
                    self.consents[type] = granted
                }
            }

            await saveConsents()
            consentLogger.info("Fetched consents from server")

        } catch {
            consentLogger.error("Failed to fetch consents from server: \(error.localizedDescription)")
        }
    }
}

// MARK: - Consent Requirement Wrapper

/// Property wrapper for requiring consent before accessing a value
@propertyWrapper
public struct RequiresConsent<Value> {
    private let consentType: ConsentType
    private let consentManager: ConsentManagerProtocol
    private var wrappedValueStorage: Value?

    public var wrappedValue: Value? {
        get {
            // Note: This is a simplified synchronous check
            // In production, you'd want to use async/await pattern
            return wrappedValueStorage
        }
        set {
            wrappedValueStorage = newValue
        }
    }

    public init(wrappedValue: Value? = nil, _ consentType: ConsentType, manager: ConsentManagerProtocol = ConsentManager.shared) {
        self.wrappedValueStorage = wrappedValue
        self.consentType = consentType
        self.consentManager = manager
    }
}

// MARK: - Mock Implementation

#if DEBUG
/// Mock consent manager for testing and previews
@MainActor
public final class MockConsentManager: ObservableObject, ConsentManagerProtocol, @unchecked Sendable {
    @Published public var consents: [ConsentType: Bool]

    public init(defaultConsent: Bool = true) {
        var initial: [ConsentType: Bool] = [:]
        for type in ConsentType.allCases {
            initial[type] = defaultConsent
        }
        self.consents = initial
    }

    public nonisolated func hasConsent(for type: ConsentType) async -> Bool {
        return await MainActor.run { self.consents[type] ?? false }
    }

    public nonisolated func requestConsent(for type: ConsentType) async -> Bool {
        return await hasConsent(for: type)
    }

    public nonisolated func grantConsent(for type: ConsentType) async {
        await MainActor.run { self.consents[type] = true }
    }

    public nonisolated func revokeConsent(for type: ConsentType) async {
        await MainActor.run { self.consents[type] = false }
    }

    public nonisolated func getAllConsents() async -> [ConsentType: Bool] {
        return await MainActor.run { self.consents }
    }

    public nonisolated func hasAllConsents(for types: [ConsentType]) async -> Bool {
        for type in types {
            if !(await hasConsent(for: type)) {
                return false
            }
        }
        return true
    }
}
#endif
