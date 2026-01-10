//
//  CoreDataStack.swift
//  EmailApp
//
//  CoreData setup for offline caching
//

import Foundation
import CoreData
import os.log

// MARK: - Logger

private let coreDataLogger = Logger(subsystem: "com.orion.emailapp", category: "CoreData")

// MARK: - Core Data Stack

/// Core Data stack manager for the email app
public final class CoreDataStack: @unchecked Sendable {
    // MARK: - Singleton

    public static let shared = CoreDataStack()

    // MARK: - Properties

    /// The model name (without .xcdatamodeld extension)
    private let modelName = "EmailApp"

    /// The persistent container
    public private(set) lazy var persistentContainer: NSPersistentContainer = {
        setupContainer()
    }()

    /// Main context for UI operations (main thread only)
    public var mainContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    /// Background context for background operations
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Setup

    private func setupContainer() -> NSPersistentContainer {
        // Create managed object model programmatically
        let model = createManagedObjectModel()

        let container = NSPersistentContainer(name: modelName, managedObjectModel: model)

        // Configure persistent store description
        let storeURL = getStoreURL()
        let description = NSPersistentStoreDescription(url: storeURL)

        // Enable lightweight migration
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        // Enable persistent history tracking for sync
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [description]

        // Load persistent stores
        container.loadPersistentStores { storeDescription, error in
            if let error = error as NSError? {
                coreDataLogger.error("Failed to load persistent store: \(error.localizedDescription)")

                // In production, you might want to handle this more gracefully
                // For now, we'll try to recover by deleting the store
                self.handlePersistentStoreError(error, storeURL: storeURL)
            } else {
                coreDataLogger.info("Persistent store loaded: \(storeDescription.url?.lastPathComponent ?? "unknown")")
            }
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "MainContext"

        return container
    }

    private func getStoreURL() -> URL {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeDirectory = appSupportURL.appendingPathComponent("EmailApp", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)

        return storeDirectory.appendingPathComponent("\(modelName).sqlite")
    }

    private func handlePersistentStoreError(_ error: NSError, storeURL: URL) {
        coreDataLogger.warning("Attempting to recover from persistent store error")

        // Delete the corrupted store
        let fileManager = FileManager.default
        let storePath = storeURL.path

        // Delete all related files
        let relatedFiles = [
            storePath,
            storePath + "-shm",
            storePath + "-wal"
        ]

        for file in relatedFiles {
            try? fileManager.removeItem(atPath: file)
        }

        coreDataLogger.info("Deleted corrupted store files, will recreate on next launch")
    }

    // MARK: - Managed Object Model

    /// Create the managed object model programmatically
    private func createManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // Create entities
        let threadEntity = createEmailThreadEntity()
        let messageEntity = createEmailMessageEntity()
        let pendingActionEntity = createPendingActionEntity()
        let attachmentEntity = createAttachmentEntity()

        // Set up relationships
        setupRelationships(
            threadEntity: threadEntity,
            messageEntity: messageEntity,
            attachmentEntity: attachmentEntity
        )

        model.entities = [threadEntity, messageEntity, pendingActionEntity, attachmentEntity]

        return model
    }

    private func createEmailThreadEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CachedEmailThread"
        entity.managedObjectClassName = "CachedEmailThread"

        entity.properties = [
            createAttribute(name: "id", type: .stringAttributeType, optional: false),
            createAttribute(name: "historyId", type: .stringAttributeType, optional: true),
            createAttribute(name: "snippet", type: .stringAttributeType, optional: true),
            createAttribute(name: "subject", type: .stringAttributeType, optional: true),
            createAttribute(name: "senderName", type: .stringAttributeType, optional: true),
            createAttribute(name: "senderEmail", type: .stringAttributeType, optional: true),
            createAttribute(name: "date", type: .dateAttributeType, optional: true),
            createAttribute(name: "isUnread", type: .booleanAttributeType, optional: false, defaultValue: false),
            createAttribute(name: "isStarred", type: .booleanAttributeType, optional: false, defaultValue: false),
            createAttribute(name: "labelIds", type: .transformableAttributeType, optional: true),
            createAttribute(name: "messageCount", type: .integer32AttributeType, optional: false, defaultValue: 0),
            createAttribute(name: "cachedAt", type: .dateAttributeType, optional: false),
            createAttribute(name: "syncToken", type: .stringAttributeType, optional: true)
        ]

        return entity
    }

    private func createEmailMessageEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CachedEmailMessage"
        entity.managedObjectClassName = "CachedEmailMessage"

        entity.properties = [
            createAttribute(name: "id", type: .stringAttributeType, optional: false),
            createAttribute(name: "threadId", type: .stringAttributeType, optional: false),
            createAttribute(name: "subject", type: .stringAttributeType, optional: true),
            createAttribute(name: "fromName", type: .stringAttributeType, optional: true),
            createAttribute(name: "fromEmail", type: .stringAttributeType, optional: true),
            createAttribute(name: "toRecipients", type: .transformableAttributeType, optional: true),
            createAttribute(name: "ccRecipients", type: .transformableAttributeType, optional: true),
            createAttribute(name: "bccRecipients", type: .transformableAttributeType, optional: true),
            createAttribute(name: "date", type: .dateAttributeType, optional: true),
            createAttribute(name: "snippet", type: .stringAttributeType, optional: true),
            createAttribute(name: "bodyPlain", type: .stringAttributeType, optional: true),
            createAttribute(name: "bodyHtml", type: .stringAttributeType, optional: true),
            createAttribute(name: "labelIds", type: .transformableAttributeType, optional: true),
            createAttribute(name: "isUnread", type: .booleanAttributeType, optional: false, defaultValue: false),
            createAttribute(name: "cachedAt", type: .dateAttributeType, optional: false)
        ]

        return entity
    }

    private func createPendingActionEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CachedPendingAction"
        entity.managedObjectClassName = "CachedPendingAction"

        entity.properties = [
            createAttribute(name: "id", type: .stringAttributeType, optional: false),
            createAttribute(name: "actionType", type: .stringAttributeType, optional: false),
            createAttribute(name: "threadId", type: .stringAttributeType, optional: true),
            createAttribute(name: "messageId", type: .stringAttributeType, optional: true),
            createAttribute(name: "payload", type: .binaryDataAttributeType, optional: true),
            createAttribute(name: "createdAt", type: .dateAttributeType, optional: false),
            createAttribute(name: "retryCount", type: .integer16AttributeType, optional: false, defaultValue: 0),
            createAttribute(name: "lastError", type: .stringAttributeType, optional: true)
        ]

        return entity
    }

    private func createAttachmentEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = "CachedAttachment"
        entity.managedObjectClassName = "CachedAttachment"

        entity.properties = [
            createAttribute(name: "id", type: .stringAttributeType, optional: false),
            createAttribute(name: "messageId", type: .stringAttributeType, optional: false),
            createAttribute(name: "filename", type: .stringAttributeType, optional: true),
            createAttribute(name: "mimeType", type: .stringAttributeType, optional: true),
            createAttribute(name: "size", type: .integer64AttributeType, optional: false, defaultValue: 0),
            createAttribute(name: "localPath", type: .stringAttributeType, optional: true),
            createAttribute(name: "downloadedAt", type: .dateAttributeType, optional: true)
        ]

        return entity
    }

    private func setupRelationships(
        threadEntity: NSEntityDescription,
        messageEntity: NSEntityDescription,
        attachmentEntity: NSEntityDescription
    ) {
        // Thread -> Messages (one-to-many)
        let threadToMessages = NSRelationshipDescription()
        threadToMessages.name = "messages"
        threadToMessages.destinationEntity = messageEntity
        threadToMessages.deleteRule = .cascadeDeleteRule
        threadToMessages.isOptional = true

        let messagesToThread = NSRelationshipDescription()
        messagesToThread.name = "thread"
        messagesToThread.destinationEntity = threadEntity
        messagesToThread.maxCount = 1
        messagesToThread.deleteRule = .nullifyDeleteRule
        messagesToThread.isOptional = true

        threadToMessages.inverseRelationship = messagesToThread
        messagesToThread.inverseRelationship = threadToMessages

        threadEntity.properties.append(threadToMessages)
        messageEntity.properties.append(messagesToThread)

        // Message -> Attachments (one-to-many)
        let messageToAttachments = NSRelationshipDescription()
        messageToAttachments.name = "attachments"
        messageToAttachments.destinationEntity = attachmentEntity
        messageToAttachments.deleteRule = .cascadeDeleteRule
        messageToAttachments.isOptional = true

        let attachmentToMessage = NSRelationshipDescription()
        attachmentToMessage.name = "message"
        attachmentToMessage.destinationEntity = messageEntity
        attachmentToMessage.maxCount = 1
        attachmentToMessage.deleteRule = .nullifyDeleteRule
        attachmentToMessage.isOptional = true

        messageToAttachments.inverseRelationship = attachmentToMessage
        attachmentToMessage.inverseRelationship = messageToAttachments

        messageEntity.properties.append(messageToAttachments)
        attachmentEntity.properties.append(attachmentToMessage)
    }

    private func createAttribute(
        name: String,
        type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional

        if let defaultValue = defaultValue {
            attribute.defaultValue = defaultValue
        }

        if type == .transformableAttributeType {
            attribute.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
            attribute.attributeValueClassName = "NSArray"
        }

        return attribute
    }

    // MARK: - Save Operations

    /// Save the main context
    public func saveMainContext() {
        saveContext(mainContext)
    }

    /// Save a context
    public func saveContext(_ context: NSManagedObjectContext) {
        guard context.hasChanges else { return }

        do {
            try context.save()
            coreDataLogger.debug("Context saved successfully")
        } catch {
            coreDataLogger.error("Failed to save context: \(error.localizedDescription)")
        }
    }

    /// Perform a background task
    public func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        persistentContainer.performBackgroundTask { context in
            context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
            block(context)

            if context.hasChanges {
                do {
                    try context.save()
                } catch {
                    coreDataLogger.error("Failed to save background context: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Cleanup

    /// Delete all data from the store
    public func deleteAllData() {
        let entities = persistentContainer.managedObjectModel.entities

        performBackgroundTask { context in
            for entity in entities {
                guard let entityName = entity.name else { continue }

                let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
                let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                batchDeleteRequest.resultType = .resultTypeObjectIDs

                do {
                    let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
                    if let objectIDs = result?.result as? [NSManagedObjectID] {
                        let changes = [NSDeletedObjectsKey: objectIDs]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.mainContext])
                    }
                } catch {
                    coreDataLogger.error("Failed to delete \(entityName): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Get the size of the persistent store
    public func storeSize() -> Int64 {
        let storeURL = getStoreURL()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: storeURL.path) else {
            return 0
        }
        return attributes[.size] as? Int64 ?? 0
    }
}

// MARK: - Migration Support

extension CoreDataStack {
    /// Check if migration is needed
    public func requiresMigration() -> Bool {
        let storeURL = getStoreURL()
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            return false
        }

        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType,
                at: storeURL
            )
            return !persistentContainer.managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        } catch {
            coreDataLogger.error("Failed to check migration status: \(error.localizedDescription)")
            return false
        }
    }

    /// Perform migration if needed
    public func migrateIfNeeded() async {
        guard requiresMigration() else {
            coreDataLogger.info("No migration needed")
            return
        }

        coreDataLogger.info("Starting store migration...")

        // The lightweight migration is handled automatically by the persistent container
        // For complex migrations, you would implement custom migration here

        coreDataLogger.info("Migration completed")
    }
}
