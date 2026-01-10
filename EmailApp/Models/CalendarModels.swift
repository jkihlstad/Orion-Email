import Foundation

enum LockState: String, Codable, CaseIterable {
    case locked, flexible, negotiable, sensitive
}

struct EventApprover: Codable, Equatable {
    var name: String?
    var email: String?
    var phone: String?
}

struct EventPolicy: Codable, Equatable {
    var lockState: LockState
    var requiresUserConfirmationBeforeSendingRequests: Bool
    var contentSharing: String // "none"|"minimal"|"full"
    var approver: EventApprover?
    var maxShiftMinutes: Int?
    var maxShiftDays: Int?
}

struct CalendarEventDTO: Codable, Identifiable, Equatable {
    var id: String
    var title: String?
    var startAt: TimeInterval
    var endAt: TimeInterval
    var timezone: String
    var policy: EventPolicy?
}

struct ProposalOptionDTO: Codable, Equatable {
    var startAt: TimeInterval
    var endAt: TimeInterval
    var score: Double
    var explain: String
}

struct RescheduleProposalDTO: Codable, Identifiable, Equatable {
    var id: String
    var eventId: String
    var status: String
    var rationale: String
    var options: [ProposalOptionDTO]
    var chosenOptionIndex: Int?
    var requiresApprover: Bool
}
