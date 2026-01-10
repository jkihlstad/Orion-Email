import Foundation
import EventKit

enum CalendarAccessLevel {
    case full
    case writeOnly
    case denied
    case notDetermined
}

final class AppleCalendarConnector: ObservableObject {
    private let store = EKEventStore()

    @Published var accessLevel: CalendarAccessLevel = .notDetermined
    @Published var isConnected: Bool = false

    init() {
        updateAccessStatus()
    }

    func updateAccessStatus() {
        if #available(iOS 17.0, *) {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess:
                accessLevel = .full
                isConnected = true
            case .writeOnly:
                accessLevel = .writeOnly
                isConnected = true
            case .denied, .restricted:
                accessLevel = .denied
                isConnected = false
            case .notDetermined:
                accessLevel = .notDetermined
                isConnected = false
            @unknown default:
                accessLevel = .notDetermined
                isConnected = false
            }
        } else {
            switch EKEventStore.authorizationStatus(for: .event) {
            case .authorized:
                accessLevel = .full
                isConnected = true
            case .denied, .restricted:
                accessLevel = .denied
                isConnected = false
            case .notDetermined:
                accessLevel = .notDetermined
                isConnected = false
            @unknown default:
                accessLevel = .notDetermined
                isConnected = false
            }
        }
    }

    @MainActor
    func requestFullAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let granted = try await store.requestFullAccessToEvents()
            updateAccessStatus()
            return granted
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                store.requestAccess(to: .event) { granted, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }
                    Task { @MainActor in
                        self.updateAccessStatus()
                    }
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    @MainActor
    func requestWriteOnlyAccess() async throws -> Bool {
        if #available(iOS 17.0, *) {
            let granted = try await store.requestWriteOnlyAccessToEvents()
            updateAccessStatus()
            return granted
        } else {
            // Fall back to full access on older iOS
            return try await requestFullAccess()
        }
    }

    func fetchEvents(from startDate: Date, to endDate: Date) -> [EKEvent] {
        guard accessLevel == .full else { return [] }

        let calendars = store.calendars(for: .event)
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        return store.events(matching: predicate)
    }

    func convertToCanonicalEvents(_ events: [EKEvent]) -> [[String: Any]] {
        return events.compactMap { event -> [String: Any]? in
            guard let eventId = event.eventIdentifier else { return nil }

            return [
                "eventType": "calendar.event.upserted",
                "payload": [
                    "payloadVersion": "1",
                    "provider": "apple_eventkit",
                    "accountId": "local",
                    "providerEventId": eventId,
                    "providerCalendarId": event.calendar?.calendarIdentifier ?? "default",
                    "event": [
                        "title": event.title ?? "",
                        "location": event.location ?? "",
                        "startAtMs": Int(event.startDate.timeIntervalSince1970 * 1000),
                        "endAtMs": Int(event.endDate.timeIntervalSince1970 * 1000),
                        "timezone": event.timeZone?.identifier ?? TimeZone.current.identifier,
                        "allDay": event.isAllDay,
                        "attendees": event.attendees?.compactMap { attendee -> [String: String]? in
                            guard let email = attendee.url?.absoluteString.replacingOccurrences(of: "mailto:", with: "") else { return nil }
                            return ["email": email, "name": attendee.name ?? ""]
                        } ?? [],
                        "organizer": event.organizer.map { org -> [String: String] in
                            let email = org.url?.absoluteString.replacingOccurrences(of: "mailto:", with: "") ?? ""
                            return ["email": email, "name": org.name ?? ""]
                        } as Any,
                        "rrule": event.recurrenceRules?.first?.description,
                    ] as [String: Any],
                    "sync": ["source": "device"]
                ] as [String: Any],
                "idempotencyKey": "apple:\(eventId):\(Int(event.startDate.timeIntervalSince1970))"
            ]
        }
    }
}
