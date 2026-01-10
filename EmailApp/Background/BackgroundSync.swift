//
//  BackgroundSync.swift
//  EmailApp
//
//  Background task scheduling for email sync operations
//

import Foundation
import BackgroundTasks
import os.log

// MARK: - Logger

private let syncLogger = Logger(subsystem: "com.orion.emailapp", category: "BackgroundSync")

// MARK: - Background Task Identifiers

/// Identifiers for background tasks
public enum BackgroundTaskIdentifier: String {
    case refreshInbox = "com.orion.emailapp.refresh-inbox"
    case flushPendingActions = "com.orion.emailapp.flush-pending"
    case syncMemories = "com.orion.emailapp.sync-memories"
    case cleanupCache = "com.orion.emailapp.cleanup-cache"

    public var identifier: String { rawValue }
}

// MARK: - Background Sync Manager

/// Manager for background sync operations
@MainActor
public final class BackgroundSyncManager: ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties

    @Published public private(set) var lastRefreshDate: Date?
    @Published public private(set) var pendingActionsCount: Int = 0
    @Published public private(set) var isSyncing: Bool = false

    // MARK: - Private Properties

    private let emailCache: EmailCacheProtocol
    private let authProvider: AuthSessionProviding
    private let brainAPIClient: BrainAPIClient?

    private var refreshTask: Task<Void, Never>?

    // Configuration
    private let minimumRefreshInterval: TimeInterval = 15 * 60 // 15 minutes
    private let maxPendingActionRetries = 3

    // MARK: - Singleton

    public static var shared: BackgroundSyncManager?

    // MARK: - Initialization

    public init(
        emailCache: EmailCacheProtocol,
        authProvider: AuthSessionProviding,
        brainAPIClient: BrainAPIClient? = nil
    ) {
        self.emailCache = emailCache
        self.authProvider = authProvider
        self.brainAPIClient = brainAPIClient

        loadLastRefreshDate()
    }

    // MARK: - Registration

    /// Register all background tasks
    /// Call this in AppDelegate.application(_:didFinishLaunchingWithOptions:)
    public nonisolated static func registerBackgroundTasks() {
        // Register refresh inbox task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.refreshInbox.identifier,
            using: nil
        ) { task in
            Task { @MainActor in
                await BackgroundSyncManager.shared?.handleRefreshInbox(task: task as! BGAppRefreshTask)
            }
        }

        // Register flush pending actions task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.flushPendingActions.identifier,
            using: nil
        ) { task in
            Task { @MainActor in
                await BackgroundSyncManager.shared?.handleFlushPendingActions(task: task as! BGProcessingTask)
            }
        }

        // Register cleanup task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskIdentifier.cleanupCache.identifier,
            using: nil
        ) { task in
            Task { @MainActor in
                await BackgroundSyncManager.shared?.handleCleanupCache(task: task as! BGProcessingTask)
            }
        }

        syncLogger.info("Background tasks registered")
    }

    /// Schedule background tasks
    /// Call this when app enters background
    public func scheduleBackgroundTasks() {
        scheduleRefreshInboxTask()
        scheduleFlushPendingActionsTask()
        scheduleCleanupCacheTask()
    }

    // MARK: - Scheduling

    /// Schedule inbox refresh task
    public func scheduleRefreshInboxTask() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifier.refreshInbox.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumRefreshInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            syncLogger.debug("Scheduled inbox refresh task")
        } catch {
            syncLogger.error("Failed to schedule inbox refresh: \(error.localizedDescription)")
        }
    }

    /// Schedule pending actions flush task
    public func scheduleFlushPendingActionsTask() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifier.flushPendingActions.identifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60) // 1 minute

        do {
            try BGTaskScheduler.shared.submit(request)
            syncLogger.debug("Scheduled flush pending actions task")
        } catch {
            syncLogger.error("Failed to schedule flush pending actions: \(error.localizedDescription)")
        }
    }

    /// Schedule cache cleanup task
    private func scheduleCleanupCacheTask() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifier.cleanupCache.identifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        // Run once a day
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24 * 60 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
            syncLogger.debug("Scheduled cleanup cache task")
        } catch {
            syncLogger.error("Failed to schedule cleanup cache: \(error.localizedDescription)")
        }
    }

    // MARK: - Task Handlers

    /// Handle inbox refresh background task
    private func handleRefreshInbox(task: BGAppRefreshTask) async {
        syncLogger.info("Starting background inbox refresh")

        // Schedule next refresh
        scheduleRefreshInboxTask()

        // Set up expiration handler
        task.expirationHandler = { [weak self] in
            self?.refreshTask?.cancel()
            syncLogger.warning("Inbox refresh task expired")
        }

        // Perform refresh
        refreshTask = Task {
            do {
                try await performInboxRefresh()
                task.setTaskCompleted(success: true)
                syncLogger.info("Background inbox refresh completed successfully")
            } catch {
                task.setTaskCompleted(success: false)
                syncLogger.error("Background inbox refresh failed: \(error.localizedDescription)")
            }
        }

        await refreshTask?.value
    }

    /// Handle flush pending actions background task
    private func handleFlushPendingActions(task: BGProcessingTask) async {
        syncLogger.info("Starting background flush pending actions")

        // Set up expiration handler
        var operationTask: Task<Void, Never>?

        task.expirationHandler = {
            operationTask?.cancel()
            syncLogger.warning("Flush pending actions task expired")
        }

        operationTask = Task {
            do {
                try await performFlushPendingActions()
                task.setTaskCompleted(success: true)
                syncLogger.info("Background flush pending actions completed successfully")
            } catch {
                task.setTaskCompleted(success: false)
                syncLogger.error("Background flush pending actions failed: \(error.localizedDescription)")
            }
        }

        await operationTask?.value

        // Schedule next flush if there are still pending actions
        let pendingCount = await emailCache.getPendingActions().count
        if pendingCount > 0 {
            scheduleFlushPendingActionsTask()
        }
    }

    /// Handle cache cleanup background task
    private func handleCleanupCache(task: BGProcessingTask) async {
        syncLogger.info("Starting background cache cleanup")

        task.expirationHandler = {
            syncLogger.warning("Cache cleanup task expired")
        }

        // Prune old cache entries
        if let cacheStore = emailCache as? EmailCacheStore {
            await cacheStore.pruneCache(olderThan: 30)
        }

        task.setTaskCompleted(success: true)
        scheduleCleanupCacheTask()

        syncLogger.info("Background cache cleanup completed")
    }

    // MARK: - Sync Operations

    /// Perform inbox refresh
    private func performInboxRefresh() async throws {
        guard await authProvider.isAuthenticated else {
            throw SyncError.notAuthenticated
        }

        await MainActor.run {
            self.isSyncing = true
        }

        defer {
            Task { @MainActor in
                self.isSyncing = false
            }
        }

        // In a real implementation, you would:
        // 1. Call the Gmail API to fetch new threads
        // 2. Cache them using emailCache.cacheThreads()
        // 3. Update lastRefreshDate

        // For now, we'll just update the refresh date
        let refreshDate = Date()

        await MainActor.run {
            self.lastRefreshDate = refreshDate
        }

        saveLastRefreshDate(refreshDate)

        syncLogger.info("Inbox refresh completed")
    }

    /// Flush pending offline actions
    private func performFlushPendingActions() async throws {
        guard await authProvider.isAuthenticated else {
            throw SyncError.notAuthenticated
        }

        let pendingActions = await emailCache.getPendingActions()

        await MainActor.run {
            self.pendingActionsCount = pendingActions.count
        }

        guard !pendingActions.isEmpty else {
            syncLogger.debug("No pending actions to flush")
            return
        }

        syncLogger.info("Flushing \(pendingActions.count) pending actions")

        for action in pendingActions {
            // Check if we should skip due to too many retries
            if action.retryCount >= maxPendingActionRetries {
                syncLogger.warning("Skipping action \(action.id) - max retries exceeded")
                continue
            }

            do {
                try await performAction(action)
                await emailCache.clearPendingAction(id: action.id)

                await MainActor.run {
                    self.pendingActionsCount -= 1
                }

                syncLogger.debug("Successfully flushed action: \(action.actionType.rawValue)")
            } catch {
                // Update retry count
                if let cacheStore = emailCache as? EmailCacheStore {
                    await cacheStore.updatePendingActionRetry(id: action.id, error: error.localizedDescription)
                }

                syncLogger.error("Failed to flush action \(action.id): \(error.localizedDescription)")
            }
        }
    }

    /// Perform a single offline action
    private func performAction(_ action: ThreadAction) async throws {
        // In a real implementation, you would call the appropriate API
        // based on the action type

        guard let client = brainAPIClient else {
            throw SyncError.notConfigured
        }

        // Simulate API call
        // In reality, you would have specific endpoints for each action type
        switch action.actionType {
        case .markRead, .markUnread:
            syncLogger.debug("Syncing read status for thread: \(action.threadId ?? "unknown")")
            // await client.updateReadStatus(...)

        case .archive:
            syncLogger.debug("Syncing archive for thread: \(action.threadId ?? "unknown")")
            // await client.archiveThread(...)

        case .trash:
            syncLogger.debug("Syncing trash for thread: \(action.threadId ?? "unknown")")
            // await client.trashThread(...)

        case .star, .unstar:
            syncLogger.debug("Syncing star status for thread: \(action.threadId ?? "unknown")")
            // await client.updateStarStatus(...)

        case .moveToLabel, .removeLabel:
            syncLogger.debug("Syncing label change for thread: \(action.threadId ?? "unknown")")
            // await client.updateLabels(...)

        case .sendDraft:
            syncLogger.debug("Sending draft: \(action.messageId ?? "unknown")")
            // await client.sendDraft(...)

        case .deleteDraft:
            syncLogger.debug("Deleting draft: \(action.messageId ?? "unknown")")
            // await client.deleteDraft(...)
        }
    }

    // MARK: - Manual Sync

    /// Trigger a manual inbox refresh
    public func refreshInbox() async throws {
        try await performInboxRefresh()
    }

    /// Trigger a manual flush of pending actions
    public func flushPendingActions() async throws {
        try await performFlushPendingActions()
    }

    // MARK: - Persistence

    private func loadLastRefreshDate() {
        if let date = UserDefaults.standard.object(forKey: "lastRefreshDate") as? Date {
            lastRefreshDate = date
        }
    }

    private func saveLastRefreshDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "lastRefreshDate")
    }

    // MARK: - Status

    /// Check if a refresh is needed based on time elapsed
    public var needsRefresh: Bool {
        guard let lastRefresh = lastRefreshDate else { return true }
        return Date().timeIntervalSince(lastRefresh) > minimumRefreshInterval
    }

    /// Get time until next scheduled refresh
    public var timeUntilNextRefresh: TimeInterval? {
        guard let lastRefresh = lastRefreshDate else { return nil }
        let nextRefresh = lastRefresh.addingTimeInterval(minimumRefreshInterval)
        let remaining = nextRefresh.timeIntervalSince(Date())
        return remaining > 0 ? remaining : 0
    }
}

// MARK: - Sync Errors

/// Errors that can occur during sync operations
public enum SyncError: Error, LocalizedError {
    case notAuthenticated
    case notConfigured
    case networkUnavailable
    case serverError(message: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User is not authenticated"
        case .notConfigured:
            return "Sync service is not configured"
        case .networkUnavailable:
            return "Network is not available"
        case .serverError(let message):
            return "Server error: \(message)"
        case .cancelled:
            return "Sync was cancelled"
        }
    }
}

// MARK: - Sync Status

/// Status of sync operations
public struct SyncStatus: Equatable {
    public let lastSyncDate: Date?
    public let pendingActionsCount: Int
    public let isSyncing: Bool
    public let lastError: String?

    public init(
        lastSyncDate: Date? = nil,
        pendingActionsCount: Int = 0,
        isSyncing: Bool = false,
        lastError: String? = nil
    ) {
        self.lastSyncDate = lastSyncDate
        self.pendingActionsCount = pendingActionsCount
        self.isSyncing = isSyncing
        self.lastError = lastError
    }

    public var formattedLastSync: String {
        guard let date = lastSyncDate else { return "Never" }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - App Lifecycle Integration

extension BackgroundSyncManager {
    /// Call when app becomes active
    public func applicationDidBecomeActive() {
        Task {
            // Refresh if needed
            if needsRefresh {
                do {
                    try await refreshInbox()
                } catch {
                    syncLogger.error("Failed to refresh on active: \(error.localizedDescription)")
                }
            }

            // Check for pending actions
            let pendingCount = await emailCache.getPendingActions().count
            await MainActor.run {
                self.pendingActionsCount = pendingCount
            }

            if pendingCount > 0 {
                do {
                    try await flushPendingActions()
                } catch {
                    syncLogger.error("Failed to flush pending on active: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Call when app enters background
    public func applicationDidEnterBackground() {
        scheduleBackgroundTasks()
    }

    /// Call when app will terminate
    public func applicationWillTerminate() {
        // Save any pending state
        if let lastRefresh = lastRefreshDate {
            saveLastRefreshDate(lastRefresh)
        }
    }
}
