import Foundation
import SwiftUI
import Combine

// MARK: - Event Detail View Model

/// ViewModel for the event detail view
/// Handles loading event data and updating event policies
@MainActor
class EventDetailViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var event: CalendarEvent?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: CalendarError?

    // MARK: - Private Properties

    private let api: CalendarAPIProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(api: CalendarAPIProtocol = CalendarAPIFactory.create()) {
        self.api = api
    }

    // MARK: - Public Methods

    /// Loads event details by ID
    func loadEvent(id: String) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            event = try await api.getEvent(id: id)
            isLoading = false

            // If no event returned, use mock in debug
            #if DEBUG
            if event == nil {
                useMockData(id: id)
            }
            #endif
        } catch let apiError as CalendarError {
            error = apiError
            isLoading = false

            #if DEBUG
            useMockData(id: id)
            #endif
        } catch {
            self.error = .networkError(error.localizedDescription)
            isLoading = false

            #if DEBUG
            useMockData(id: id)
            #endif
        }
    }

    /// Updates the event's AI scheduling policy
    func updatePolicy(_ policy: EventPolicy) async {
        guard let eventId = event?.id else { return }
        guard !isSaving else { return }

        isSaving = true
        error = nil

        do {
            try await api.updateEventPolicy(eventId: eventId, policy: policy)

            // Update local state on success
            withAnimation(Theme.Animation.easeFast) {
                event?.policy = policy
            }

            isSaving = false
            Haptics.success()
        } catch let apiError as CalendarError {
            error = apiError
            isSaving = false
            Haptics.error()
        } catch {
            self.error = .networkError(error.localizedDescription)
            isSaving = false
            Haptics.error()
        }
    }

    /// Reloads the current event
    func refresh() async {
        guard let id = event?.id else { return }
        await loadEvent(id: id)
    }

    // MARK: - Private Methods

    private func useMockData(id: String) {
        // Try to find a matching mock event
        if let mockEvent = CalendarEvent.mockEvents.first(where: { $0.id == id }) {
            event = mockEvent
        } else {
            // Use the first mock event as fallback
            event = CalendarEvent.mock
        }
    }
}

// MARK: - Event Detail View Model Factory

/// Factory for creating EventDetailViewModel instances
enum EventDetailViewModelFactory {
    static func create(api: CalendarAPIProtocol = CalendarAPIFactory.create()) -> EventDetailViewModel {
        return EventDetailViewModel(api: api)
    }

    #if DEBUG
    static func createMock(event: CalendarEvent? = .mock) -> EventDetailViewModel {
        let viewModel = EventDetailViewModel(api: MockCalendarAPI())
        viewModel.event = event
        return viewModel
    }
    #endif
}
