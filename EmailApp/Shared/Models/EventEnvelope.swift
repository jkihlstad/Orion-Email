import Foundation

// MARK: - Event Envelope (Raw Ingestion Format)
/// Raw event envelope as stored in the ingestion store.
/// This is the unprocessed format before transformation to CleanedEvent.
struct EventEnvelope: Codable, Identifiable, Equatable {

    /// Unique envelope identifier
    let id: String

    /// Source application that emitted the event
    let source: EventSource

    /// The user ID from the source system
    let userId: String

    /// Raw event type string
    let eventType: String

    /// When the event was ingested (may differ from occurredAt)
    let ingestedAt: TimeInterval

    /// When the event actually occurred
    let occurredAt: TimeInterval

    /// Original timezone from source
    let timezone: String?

    /// Raw payload as received from source
    let rawPayload: Data

    /// Processing status for the envelope
    var status: EnvelopeStatus

    /// Number of processing attempts
    var attemptCount: Int

    /// Last error message if processing failed
    var lastError: String?
}

// MARK: - Event Source
/// Identifies the source application that emitted an event.
enum EventSource: String, Codable, CaseIterable {
    case emailApp = "email"
    case calendarApp = "calendar"
    case tasksApp = "tasks"
    case brainService = "brain"
    case schedulerService = "scheduler"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .emailApp: return "Email"
        case .calendarApp: return "Calendar"
        case .tasksApp: return "Tasks"
        case .brainService: return "Brain"
        case .schedulerService: return "Scheduler"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Envelope Status
/// Processing status for event envelopes.
enum EnvelopeStatus: String, Codable, CaseIterable {
    /// Envelope received but not yet processed
    case pending

    /// Currently being processed
    case processing

    /// Successfully transformed to CleanedEvent
    case processed

    /// Processing failed (check lastError)
    case failed

    /// Marked as tombstone/deleted
    case tombstone

    /// Skipped (e.g., duplicate, invalid)
    case skipped

    var isTerminal: Bool {
        switch self {
        case .processed, .failed, .tombstone, .skipped: return true
        case .pending, .processing: return false
        }
    }
}

// MARK: - Envelope to CleanedEvent Transformation
extension EventEnvelope {

    /// Transform this envelope into a CleanedEvent for Brain consumption.
    /// Returns nil if transformation fails.
    func toCleanedEvent() -> CleanedEvent? {
        guard let payload = parsePayload(),
              let refs = extractRefs(from: payload) else {
            return nil
        }

        return CleanedEvent(
            eventId: id,
            userId: userId,
            eventType: eventType,
            occurredAt: occurredAt,
            timezone: timezone ?? TimeZone.current.identifier,
            payload: cleanPayload(payload),
            refs: refs
        )
    }

    // MARK: - Private Helpers

    private func parsePayload() -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: rawPayload) as? [String: Any]
    }

    private func extractRefs(from payload: [String: Any]) -> EventRefs? {
        // Extract refs from either top-level or nested "refs" object
        let refsDict = payload["refs"] as? [String: String] ?? [:]

        // Also check top-level for common ref patterns
        let taskId = refsDict["taskId"] ?? payload["taskId"] as? String
        let threadId = refsDict["threadId"] ?? payload["threadId"] as? String
        let ekEventId = refsDict["ekEventId"] ?? payload["ekEventId"] as? String
        let gcalEventId = refsDict["gcalEventId"] ?? payload["gcalEventId"] as? String
        let messageId = refsDict["messageId"] ?? payload["messageId"] as? String
        let parentTaskId = refsDict["parentTaskId"] ?? payload["parentTaskId"] as? String
        let proposalId = refsDict["proposalId"] ?? payload["proposalId"] as? String

        return EventRefs(
            taskId: taskId,
            threadId: threadId,
            ekEventId: ekEventId,
            gcalEventId: gcalEventId,
            messageId: messageId,
            parentTaskId: parentTaskId,
            proposalId: proposalId
        )
    }

    private func cleanPayload(_ raw: [String: Any]) -> EventPayload {
        // Remove refs from payload (they're extracted separately)
        var cleaned = raw
        cleaned.removeValue(forKey: "refs")
        cleaned.removeValue(forKey: "taskId")
        cleaned.removeValue(forKey: "threadId")
        cleaned.removeValue(forKey: "ekEventId")
        cleaned.removeValue(forKey: "gcalEventId")
        cleaned.removeValue(forKey: "messageId")
        cleaned.removeValue(forKey: "parentTaskId")
        cleaned.removeValue(forKey: "proposalId")

        var payload = EventPayload()
        for (key, value) in cleaned {
            payload[key] = toAnyCodableValue(value)
        }
        return payload
    }

    private func toAnyCodableValue(_ value: Any) -> AnyCodableValue {
        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { toAnyCodableValue($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { toAnyCodableValue($0) })
        default:
            return .null
        }
    }
}

// MARK: - Envelope Builder
extension EventEnvelope {

    /// Creates a new envelope with generated ID and current timestamp
    static func create(
        source: EventSource,
        userId: String,
        eventType: String,
        occurredAt: TimeInterval? = nil,
        timezone: String? = nil,
        payload: [String: Any]
    ) throws -> EventEnvelope {
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        let now = Date().timeIntervalSince1970

        return EventEnvelope(
            id: UUID().uuidString,
            source: source,
            userId: userId,
            eventType: eventType,
            ingestedAt: now,
            occurredAt: occurredAt ?? now,
            timezone: timezone ?? TimeZone.current.identifier,
            rawPayload: payloadData,
            status: .pending,
            attemptCount: 0,
            lastError: nil
        )
    }
}

// MARK: - Tombstone Support
extension EventEnvelope {

    /// Check if this envelope represents a deletion
    var isTombstone: Bool {
        status == .tombstone || SuiteEventTypes.isTombstone(eventType)
    }

    /// Mark this envelope as a tombstone
    mutating func markAsTombstone() {
        status = .tombstone
    }
}
