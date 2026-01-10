import Foundation

// MARK: - Cleaned Event (Brain Input)
/// The canonical event representation consumed by the Brain.
/// Raw event envelopes from the ingestion store are transformed into this shape
/// before being processed by the Brain's reasoning engine.
struct CleanedEvent: Codable, Identifiable, Equatable {

    /// Unique identifier for this event instance
    let eventId: String

    /// The Clerk user ID this event belongs to
    let userId: String

    /// The event type (see SuiteEventTypes for constants)
    let eventType: String

    /// Unix timestamp (seconds) when the event occurred
    let occurredAt: TimeInterval

    /// IANA timezone identifier (e.g., "America/Los_Angeles")
    let timezone: String

    /// Event-specific payload data
    let payload: EventPayload

    /// Cross-entity references for linking related data
    let refs: EventRefs

    // MARK: - Identifiable
    var id: String { eventId }
}

// MARK: - Event Payload
/// Type-erased container for event-specific payload data.
/// The Brain expects a consistent wrapper, but contents vary by event type.
struct EventPayload: Codable, Equatable {

    /// The underlying payload data as a dictionary
    private var data: [String: AnyCodableValue]

    init(_ data: [String: AnyCodableValue] = [:]) {
        self.data = data
    }

    subscript(key: String) -> AnyCodableValue? {
        get { data[key] }
        set { data[key] = newValue }
    }

    /// Access a string value from the payload
    func string(for key: String) -> String? {
        data[key]?.stringValue
    }

    /// Access an integer value from the payload
    func int(for key: String) -> Int? {
        data[key]?.intValue
    }

    /// Access a boolean value from the payload
    func bool(for key: String) -> Bool? {
        data[key]?.boolValue
    }

    /// Access a double value from the payload
    func double(for key: String) -> Double? {
        data[key]?.doubleValue
    }

    /// Check if payload is empty
    var isEmpty: Bool { data.isEmpty }

    /// All keys in the payload
    var keys: [String] { Array(data.keys) }
}

// MARK: - Event References
/// Cross-entity references for linking related data across the suite.
/// These stable IDs allow the Brain to correlate events across domains.
struct EventRefs: Codable, Equatable {

    /// Task ID (stable across edits) - e.g., "t_123"
    var taskId: String?

    /// Gmail thread ID - e.g., "gmail_abc"
    var threadId: String?

    /// Apple EventKit event ID - e.g., "ABCDE"
    var ekEventId: String?

    /// Google Calendar event ID
    var gcalEventId: String?

    /// Message ID within a thread
    var messageId: String?

    /// Parent task ID for subtasks
    var parentTaskId: String?

    /// Proposal ID for scheduler proposals
    var proposalId: String?

    init(
        taskId: String? = nil,
        threadId: String? = nil,
        ekEventId: String? = nil,
        gcalEventId: String? = nil,
        messageId: String? = nil,
        parentTaskId: String? = nil,
        proposalId: String? = nil
    ) {
        self.taskId = taskId
        self.threadId = threadId
        self.ekEventId = ekEventId
        self.gcalEventId = gcalEventId
        self.messageId = messageId
        self.parentTaskId = parentTaskId
        self.proposalId = proposalId
    }

    /// Check if this refs object has any references set
    var isEmpty: Bool {
        taskId == nil &&
        threadId == nil &&
        ekEventId == nil &&
        gcalEventId == nil &&
        messageId == nil &&
        parentTaskId == nil &&
        proposalId == nil
    }

    /// Returns all non-nil reference pairs
    var allRefs: [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []
        if let taskId { result.append(("taskId", taskId)) }
        if let threadId { result.append(("threadId", threadId)) }
        if let ekEventId { result.append(("ekEventId", ekEventId)) }
        if let gcalEventId { result.append(("gcalEventId", gcalEventId)) }
        if let messageId { result.append(("messageId", messageId)) }
        if let parentTaskId { result.append(("parentTaskId", parentTaskId)) }
        if let proposalId { result.append(("proposalId", proposalId)) }
        return result
    }
}

// MARK: - AnyCodableValue
/// A type-erased codable value for flexible payload handling.
enum AnyCodableValue: Codable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodableValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodableValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unable to decode AnyCodableValue"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - CleanedEvent Builder
extension CleanedEvent {

    /// Creates a new event with a generated UUID
    static func create(
        userId: String,
        eventType: String,
        timezone: String = TimeZone.current.identifier,
        payload: EventPayload = EventPayload(),
        refs: EventRefs = EventRefs()
    ) -> CleanedEvent {
        CleanedEvent(
            eventId: UUID().uuidString,
            userId: userId,
            eventType: eventType,
            occurredAt: Date().timeIntervalSince1970,
            timezone: timezone,
            payload: payload,
            refs: refs
        )
    }
}

// MARK: - Validation
extension CleanedEvent {

    /// Validates that the event has required fields set
    var isValid: Bool {
        !eventId.isEmpty &&
        !userId.isEmpty &&
        !eventType.isEmpty &&
        occurredAt > 0 &&
        !timezone.isEmpty
    }

    /// Returns validation errors, if any
    var validationErrors: [String] {
        var errors: [String] = []
        if eventId.isEmpty { errors.append("eventId is required") }
        if userId.isEmpty { errors.append("userId is required") }
        if eventType.isEmpty { errors.append("eventType is required") }
        if occurredAt <= 0 { errors.append("occurredAt must be positive") }
        if timezone.isEmpty { errors.append("timezone is required") }
        return errors
    }
}
