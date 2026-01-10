//
//  EmailCacheStore.swift
//  EmailApp
//
//  Local cache for emails using CoreData
//

import Foundation
import CoreData
import os.log

// MARK: - Logger

private let cacheLogger = Logger(subsystem: "com.orion.emailapp", category: "EmailCache")

// MARK: - Email Cache Protocol

/// Protocol for email caching operations
public protocol EmailCacheProtocol: AnyObject, Sendable {
    /// Cache multiple threads
    func cacheThreads(_ threads: [EmailThread]) async

    /// Get cached threads, optionally filtered by label
    func getCachedThreads(label: String?) async -> [EmailThread]

    /// Cache a thread with its messages
    func cacheThread(_ thread: EmailThread, messages: [EmailMessage]) async

    /// Get a cached thread with its messages
    func getCachedThread(id: String) async -> (EmailThread, [EmailMessage])?

    /// Cache a pending action for offline sync
    func cachePendingAction(_ action: ThreadAction) async

    /// Get all pending actions
    func getPendingActions() async -> [ThreadAction]

    /// Clear a pending action after successful sync
    func clearPendingAction(id: String) async

    /// Clear all cached data
    func clearCache() async

    /// Get cache statistics
    func getCacheStats() async -> CacheStats
}

// MARK: - Email Thread Model

/// Email thread model for caching
public struct EmailThread: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let historyId: String?
    public let snippet: String?
    public let subject: String?
    public let senderName: String?
    public let senderEmail: String?
    public let date: Date?
    public let isUnread: Bool
    public let isStarred: Bool
    public let labelIds: [String]
    public let messageCount: Int

    public init(
        id: String,
        historyId: String? = nil,
        snippet: String? = nil,
        subject: String? = nil,
        senderName: String? = nil,
        senderEmail: String? = nil,
        date: Date? = nil,
        isUnread: Bool = false,
        isStarred: Bool = false,
        labelIds: [String] = [],
        messageCount: Int = 1
    ) {
        self.id = id
        self.historyId = historyId
        self.snippet = snippet
        self.subject = subject
        self.senderName = senderName
        self.senderEmail = senderEmail
        self.date = date
        self.isUnread = isUnread
        self.isStarred = isStarred
        self.labelIds = labelIds
        self.messageCount = messageCount
    }
}

// MARK: - Email Message Model

/// Email message model for caching
public struct EmailMessage: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let threadId: String
    public let subject: String?
    public let fromName: String?
    public let fromEmail: String?
    public let toRecipients: [EmailRecipient]
    public let ccRecipients: [EmailRecipient]
    public let bccRecipients: [EmailRecipient]
    public let date: Date?
    public let snippet: String?
    public let bodyPlain: String?
    public let bodyHtml: String?
    public let labelIds: [String]
    public let isUnread: Bool

    public init(
        id: String,
        threadId: String,
        subject: String? = nil,
        fromName: String? = nil,
        fromEmail: String? = nil,
        toRecipients: [EmailRecipient] = [],
        ccRecipients: [EmailRecipient] = [],
        bccRecipients: [EmailRecipient] = [],
        date: Date? = nil,
        snippet: String? = nil,
        bodyPlain: String? = nil,
        bodyHtml: String? = nil,
        labelIds: [String] = [],
        isUnread: Bool = false
    ) {
        self.id = id
        self.threadId = threadId
        self.subject = subject
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
        self.bccRecipients = bccRecipients
        self.date = date
        self.snippet = snippet
        self.bodyPlain = bodyPlain
        self.bodyHtml = bodyHtml
        self.labelIds = labelIds
        self.isUnread = isUnread
    }
}

/// Email recipient
public struct EmailRecipient: Codable, Equatable, Sendable {
    public let name: String?
    public let email: String

    public init(name: String? = nil, email: String) {
        self.name = name
        self.email = email
    }
}

// MARK: - Thread Action Model

/// Pending action for offline sync
public struct ThreadAction: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let actionType: ActionType
    public let threadId: String?
    public let messageId: String?
    public let payload: Data?
    public let createdAt: Date
    public var retryCount: Int
    public var lastError: String?

    public init(
        id: String = UUID().uuidString,
        actionType: ActionType,
        threadId: String? = nil,
        messageId: String? = nil,
        payload: Data? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.actionType = actionType
        self.threadId = threadId
        self.messageId = messageId
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastError = lastError
    }

    public enum ActionType: String, Codable, Sendable {
        case markRead
        case markUnread
        case archive
        case trash
        case star
        case unstar
        case moveToLabel
        case removeLabel
        case sendDraft
        case deleteDraft
    }
}

// MARK: - Cache Stats

/// Cache statistics
public struct CacheStats: Sendable {
    public let threadCount: Int
    public let messageCount: Int
    public let pendingActionCount: Int
    public let cacheSize: Int64
    public let lastUpdated: Date?

    public init(
        threadCount: Int = 0,
        messageCount: Int = 0,
        pendingActionCount: Int = 0,
        cacheSize: Int64 = 0,
        lastUpdated: Date? = nil
    ) {
        self.threadCount = threadCount
        self.messageCount = messageCount
        self.pendingActionCount = pendingActionCount
        self.cacheSize = cacheSize
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Email Cache Store

/// CoreData-based implementation of email caching
public actor EmailCacheStore: EmailCacheProtocol {
    // MARK: - Properties

    private let coreDataStack: CoreDataStack

    // MARK: - Initialization

    public init(coreDataStack: CoreDataStack = .shared) {
        self.coreDataStack = coreDataStack
    }

    // MARK: - Thread Operations

    /// Cache multiple threads
    public func cacheThreads(_ threads: [EmailThread]) async {
        let context = coreDataStack.newBackgroundContext()

        await context.perform {
            for thread in threads {
                self.upsertThread(thread, in: context)
            }

            do {
                try context.save()
                cacheLogger.debug("Cached \(threads.count) threads")
            } catch {
                cacheLogger.error("Failed to cache threads: \(error.localizedDescription)")
            }
        }
    }

    /// Get cached threads
    public func getCachedThreads(label: String?) async -> [EmailThread] {
        let context = coreDataStack.newBackgroundContext()

        return await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailThread")
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

            if let label = label {
                request.predicate = NSPredicate(format: "ANY labelIds == %@", label)
            }

            do {
                let results = try context.fetch(request)
                return results.compactMap { self.threadFromManagedObject($0) }
            } catch {
                cacheLogger.error("Failed to fetch cached threads: \(error.localizedDescription)")
                return []
            }
        }
    }

    /// Cache a thread with its messages
    public func cacheThread(_ thread: EmailThread, messages: [EmailMessage]) async {
        let context = coreDataStack.newBackgroundContext()

        await context.perform {
            // Upsert thread
            let threadObject = self.upsertThread(thread, in: context)

            // Upsert messages
            for message in messages {
                self.upsertMessage(message, threadObject: threadObject, in: context)
            }

            do {
                try context.save()
                cacheLogger.debug("Cached thread \(thread.id) with \(messages.count) messages")
            } catch {
                cacheLogger.error("Failed to cache thread: \(error.localizedDescription)")
            }
        }
    }

    /// Get a cached thread with its messages
    public func getCachedThread(id: String) async -> (EmailThread, [EmailMessage])? {
        let context = coreDataStack.newBackgroundContext()

        return await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailThread")
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            do {
                guard let threadObject = try context.fetch(request).first,
                      let thread = self.threadFromManagedObject(threadObject) else {
                    return nil
                }

                // Fetch messages
                let messageRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailMessage")
                messageRequest.predicate = NSPredicate(format: "threadId == %@", id)
                messageRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

                let messageObjects = try context.fetch(messageRequest)
                let messages = messageObjects.compactMap { self.messageFromManagedObject($0) }

                return (thread, messages)
            } catch {
                cacheLogger.error("Failed to fetch cached thread: \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Pending Actions

    /// Cache a pending action
    public func cachePendingAction(_ action: ThreadAction) async {
        let context = coreDataStack.newBackgroundContext()

        await context.perform {
            let entity = NSEntityDescription.entity(forEntityName: "CachedPendingAction", in: context)!
            let object = NSManagedObject(entity: entity, insertInto: context)

            object.setValue(action.id, forKey: "id")
            object.setValue(action.actionType.rawValue, forKey: "actionType")
            object.setValue(action.threadId, forKey: "threadId")
            object.setValue(action.messageId, forKey: "messageId")
            object.setValue(action.payload, forKey: "payload")
            object.setValue(action.createdAt, forKey: "createdAt")
            object.setValue(action.retryCount, forKey: "retryCount")
            object.setValue(action.lastError, forKey: "lastError")

            do {
                try context.save()
                cacheLogger.debug("Cached pending action: \(action.actionType.rawValue)")
            } catch {
                cacheLogger.error("Failed to cache pending action: \(error.localizedDescription)")
            }
        }
    }

    /// Get all pending actions
    public func getPendingActions() async -> [ThreadAction] {
        let context = coreDataStack.newBackgroundContext()

        return await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedPendingAction")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

            do {
                let results = try context.fetch(request)
                return results.compactMap { self.actionFromManagedObject($0) }
            } catch {
                cacheLogger.error("Failed to fetch pending actions: \(error.localizedDescription)")
                return []
            }
        }
    }

    /// Clear a pending action
    public func clearPendingAction(id: String) async {
        let context = coreDataStack.newBackgroundContext()

        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedPendingAction")
            request.predicate = NSPredicate(format: "id == %@", id)

            do {
                let results = try context.fetch(request)
                for object in results {
                    context.delete(object)
                }
                try context.save()
                cacheLogger.debug("Cleared pending action: \(id)")
            } catch {
                cacheLogger.error("Failed to clear pending action: \(error.localizedDescription)")
            }
        }
    }

    /// Update retry count for a pending action
    public func updatePendingActionRetry(id: String, error: String?) async {
        let context = coreDataStack.newBackgroundContext()

        await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CachedPendingAction")
            request.predicate = NSPredicate(format: "id == %@", id)
            request.fetchLimit = 1

            do {
                if let object = try context.fetch(request).first {
                    let currentRetry = object.value(forKey: "retryCount") as? Int16 ?? 0
                    object.setValue(currentRetry + 1, forKey: "retryCount")
                    object.setValue(error, forKey: "lastError")
                    try context.save()
                }
            } catch {
                cacheLogger.error("Failed to update pending action: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Cache Management

    /// Clear all cached data
    public func clearCache() async {
        coreDataStack.deleteAllData()
        cacheLogger.info("Cache cleared")
    }

    /// Get cache statistics
    public func getCacheStats() async -> CacheStats {
        let context = coreDataStack.newBackgroundContext()

        return await context.perform {
            var threadCount = 0
            var messageCount = 0
            var pendingCount = 0
            var lastUpdated: Date?

            do {
                // Count threads
                let threadRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailThread")
                threadCount = try context.count(for: threadRequest)

                // Count messages
                let messageRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailMessage")
                messageCount = try context.count(for: messageRequest)

                // Count pending actions
                let pendingRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedPendingAction")
                pendingCount = try context.count(for: pendingRequest)

                // Get last cached date
                let dateRequest = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailThread")
                dateRequest.sortDescriptors = [NSSortDescriptor(key: "cachedAt", ascending: false)]
                dateRequest.fetchLimit = 1
                if let result = try context.fetch(dateRequest).first {
                    lastUpdated = result.value(forKey: "cachedAt") as? Date
                }

            } catch {
                cacheLogger.error("Failed to get cache stats: \(error.localizedDescription)")
            }

            return CacheStats(
                threadCount: threadCount,
                messageCount: messageCount,
                pendingActionCount: pendingCount,
                cacheSize: self.coreDataStack.storeSize(),
                lastUpdated: lastUpdated
            )
        }
    }

    /// Prune old cache entries
    public func pruneCache(olderThan days: Int = 30) async {
        let context = coreDataStack.newBackgroundContext()
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        await context.perform {
            // Delete old threads
            let threadRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedEmailThread")
            threadRequest.predicate = NSPredicate(format: "cachedAt < %@", cutoffDate as NSDate)

            let threadDelete = NSBatchDeleteRequest(fetchRequest: threadRequest)
            threadDelete.resultType = .resultTypeCount

            // Delete old messages
            let messageRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedEmailMessage")
            messageRequest.predicate = NSPredicate(format: "cachedAt < %@", cutoffDate as NSDate)

            let messageDelete = NSBatchDeleteRequest(fetchRequest: messageRequest)
            messageDelete.resultType = .resultTypeCount

            do {
                let threadResult = try context.execute(threadDelete) as? NSBatchDeleteResult
                let messageResult = try context.execute(messageDelete) as? NSBatchDeleteResult

                let threadsDeleted = threadResult?.result as? Int ?? 0
                let messagesDeleted = messageResult?.result as? Int ?? 0

                cacheLogger.info("Pruned cache: \(threadsDeleted) threads, \(messagesDeleted) messages")
            } catch {
                cacheLogger.error("Failed to prune cache: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Helpers

    @discardableResult
    private func upsertThread(_ thread: EmailThread, in context: NSManagedObjectContext) -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailThread")
        request.predicate = NSPredicate(format: "id == %@", thread.id)
        request.fetchLimit = 1

        let object: NSManagedObject
        if let existing = try? context.fetch(request).first {
            object = existing
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "CachedEmailThread", in: context)!
            object = NSManagedObject(entity: entity, insertInto: context)
        }

        object.setValue(thread.id, forKey: "id")
        object.setValue(thread.historyId, forKey: "historyId")
        object.setValue(thread.snippet, forKey: "snippet")
        object.setValue(thread.subject, forKey: "subject")
        object.setValue(thread.senderName, forKey: "senderName")
        object.setValue(thread.senderEmail, forKey: "senderEmail")
        object.setValue(thread.date, forKey: "date")
        object.setValue(thread.isUnread, forKey: "isUnread")
        object.setValue(thread.isStarred, forKey: "isStarred")
        object.setValue(thread.labelIds as NSArray, forKey: "labelIds")
        object.setValue(thread.messageCount, forKey: "messageCount")
        object.setValue(Date(), forKey: "cachedAt")

        return object
    }

    private func upsertMessage(_ message: EmailMessage, threadObject: NSManagedObject?, in context: NSManagedObjectContext) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CachedEmailMessage")
        request.predicate = NSPredicate(format: "id == %@", message.id)
        request.fetchLimit = 1

        let object: NSManagedObject
        if let existing = try? context.fetch(request).first {
            object = existing
        } else {
            let entity = NSEntityDescription.entity(forEntityName: "CachedEmailMessage", in: context)!
            object = NSManagedObject(entity: entity, insertInto: context)
        }

        object.setValue(message.id, forKey: "id")
        object.setValue(message.threadId, forKey: "threadId")
        object.setValue(message.subject, forKey: "subject")
        object.setValue(message.fromName, forKey: "fromName")
        object.setValue(message.fromEmail, forKey: "fromEmail")
        object.setValue(message.date, forKey: "date")
        object.setValue(message.snippet, forKey: "snippet")
        object.setValue(message.bodyPlain, forKey: "bodyPlain")
        object.setValue(message.bodyHtml, forKey: "bodyHtml")
        object.setValue(message.labelIds as NSArray, forKey: "labelIds")
        object.setValue(message.isUnread, forKey: "isUnread")
        object.setValue(Date(), forKey: "cachedAt")

        // Encode recipients
        if let toData = try? JSONEncoder().encode(message.toRecipients) {
            object.setValue(toData, forKey: "toRecipients")
        }
        if let ccData = try? JSONEncoder().encode(message.ccRecipients) {
            object.setValue(ccData, forKey: "ccRecipients")
        }
        if let bccData = try? JSONEncoder().encode(message.bccRecipients) {
            object.setValue(bccData, forKey: "bccRecipients")
        }

        if let threadObject = threadObject {
            object.setValue(threadObject, forKey: "thread")
        }
    }

    private func threadFromManagedObject(_ object: NSManagedObject) -> EmailThread? {
        guard let id = object.value(forKey: "id") as? String else { return nil }

        return EmailThread(
            id: id,
            historyId: object.value(forKey: "historyId") as? String,
            snippet: object.value(forKey: "snippet") as? String,
            subject: object.value(forKey: "subject") as? String,
            senderName: object.value(forKey: "senderName") as? String,
            senderEmail: object.value(forKey: "senderEmail") as? String,
            date: object.value(forKey: "date") as? Date,
            isUnread: object.value(forKey: "isUnread") as? Bool ?? false,
            isStarred: object.value(forKey: "isStarred") as? Bool ?? false,
            labelIds: object.value(forKey: "labelIds") as? [String] ?? [],
            messageCount: object.value(forKey: "messageCount") as? Int ?? 1
        )
    }

    private func messageFromManagedObject(_ object: NSManagedObject) -> EmailMessage? {
        guard let id = object.value(forKey: "id") as? String,
              let threadId = object.value(forKey: "threadId") as? String else { return nil }

        var toRecipients: [EmailRecipient] = []
        var ccRecipients: [EmailRecipient] = []
        var bccRecipients: [EmailRecipient] = []

        if let toData = object.value(forKey: "toRecipients") as? Data {
            toRecipients = (try? JSONDecoder().decode([EmailRecipient].self, from: toData)) ?? []
        }
        if let ccData = object.value(forKey: "ccRecipients") as? Data {
            ccRecipients = (try? JSONDecoder().decode([EmailRecipient].self, from: ccData)) ?? []
        }
        if let bccData = object.value(forKey: "bccRecipients") as? Data {
            bccRecipients = (try? JSONDecoder().decode([EmailRecipient].self, from: bccData)) ?? []
        }

        return EmailMessage(
            id: id,
            threadId: threadId,
            subject: object.value(forKey: "subject") as? String,
            fromName: object.value(forKey: "fromName") as? String,
            fromEmail: object.value(forKey: "fromEmail") as? String,
            toRecipients: toRecipients,
            ccRecipients: ccRecipients,
            bccRecipients: bccRecipients,
            date: object.value(forKey: "date") as? Date,
            snippet: object.value(forKey: "snippet") as? String,
            bodyPlain: object.value(forKey: "bodyPlain") as? String,
            bodyHtml: object.value(forKey: "bodyHtml") as? String,
            labelIds: object.value(forKey: "labelIds") as? [String] ?? [],
            isUnread: object.value(forKey: "isUnread") as? Bool ?? false
        )
    }

    private func actionFromManagedObject(_ object: NSManagedObject) -> ThreadAction? {
        guard let id = object.value(forKey: "id") as? String,
              let actionTypeRaw = object.value(forKey: "actionType") as? String,
              let actionType = ThreadAction.ActionType(rawValue: actionTypeRaw),
              let createdAt = object.value(forKey: "createdAt") as? Date else {
            return nil
        }

        return ThreadAction(
            id: id,
            actionType: actionType,
            threadId: object.value(forKey: "threadId") as? String,
            messageId: object.value(forKey: "messageId") as? String,
            payload: object.value(forKey: "payload") as? Data,
            createdAt: createdAt,
            retryCount: Int(object.value(forKey: "retryCount") as? Int16 ?? 0),
            lastError: object.value(forKey: "lastError") as? String
        )
    }
}
