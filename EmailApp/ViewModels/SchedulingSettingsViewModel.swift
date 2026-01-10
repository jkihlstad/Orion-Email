import Foundation
import SwiftUI
import Combine

// MARK: - Scheduling Settings View Model

/// ViewModel for the scheduling settings view
/// Handles loading and saving global calendar policy settings
@MainActor
class SchedulingSettingsViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var policy: CalendarPolicy?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: CalendarError?

    // Work Hours
    @Published var workHours: [DayWorkHours] = DayWorkHours.defaultWeekdays

    // Focus Blocks
    @Published var focusBlocks: [FocusBlock] = []

    // Meeting Limits
    @Published var maxMeetingsPerDay: Int = 8
    @Published var bufferMinutes: Int = 15
    @Published var maxConsecutiveHours: Double = 3.0

    // Automation
    @Published var autoApplyFlexible: Bool = false
    @Published var autoSendApprovals: Bool = false
    @Published var applyOnApproval: Bool = true

    // MARK: - Private Properties

    private let api: CalendarAPIProtocol
    private var cancellables = Set<AnyCancellable>()
    private var originalPolicy: CalendarPolicy?

    // MARK: - Computed Properties

    /// Whether the settings have been changed from the original
    var hasChanges: Bool {
        guard let original = originalPolicy else { return false }

        return workHours != original.workHours ||
               focusBlocks != original.focusBlocks ||
               maxMeetingsPerDay != original.meetingLimits.maxMeetingsPerDay ||
               bufferMinutes != original.meetingLimits.bufferMinutesBetweenMeetings ||
               maxConsecutiveHours != original.meetingLimits.maxConsecutiveHours ||
               autoApplyFlexible != original.autoApplyFlexible ||
               autoSendApprovals != original.autoSendApprovals ||
               applyOnApproval != original.applyOnApproval
    }

    // MARK: - Initialization

    init(api: CalendarAPIProtocol = CalendarAPIFactory.create()) {
        self.api = api
    }

    // MARK: - Public Methods

    /// Loads the current calendar policy
    func loadPolicy() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let loadedPolicy = try await api.getPolicy()
            applyPolicy(loadedPolicy ?? .default)
            isLoading = false
        } catch let apiError as CalendarError {
            error = apiError
            isLoading = false

            #if DEBUG
            applyPolicy(.default)
            #endif
        } catch {
            self.error = .networkError(error.localizedDescription)
            isLoading = false

            #if DEBUG
            applyPolicy(.default)
            #endif
        }
    }

    /// Saves the current settings as the calendar policy
    func savePolicy() async {
        guard !isSaving else { return }

        isSaving = true
        error = nil

        let newPolicy = buildPolicy()

        do {
            try await api.updatePolicy(newPolicy)

            policy = newPolicy
            originalPolicy = newPolicy

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

    /// Resets settings to the original loaded values
    func resetToOriginal() {
        guard let original = originalPolicy else { return }
        applyPolicy(original)
    }

    /// Adds a new focus block
    func addFocusBlock(_ block: FocusBlock) {
        withAnimation(Theme.Animation.easeFast) {
            focusBlocks.append(block)
        }
    }

    /// Updates an existing focus block
    func updateFocusBlock(_ block: FocusBlock) {
        withAnimation(Theme.Animation.easeFast) {
            if let index = focusBlocks.firstIndex(where: { $0.id == block.id }) {
                focusBlocks[index] = block
            }
        }
    }

    /// Removes a focus block by ID
    func removeFocusBlock(id: String) {
        withAnimation(Theme.Animation.easeFast) {
            focusBlocks.removeAll { $0.id == id }
        }
    }

    /// Updates work hours for a specific day
    func updateWorkHours(dayOfWeek: Int, isEnabled: Bool? = nil, startTime: String? = nil, endTime: String? = nil) {
        guard let index = workHours.firstIndex(where: { $0.dayOfWeek == dayOfWeek }) else { return }

        var updated = workHours[index]
        if let isEnabled = isEnabled { updated.isEnabled = isEnabled }
        if let startTime = startTime { updated.startTime = startTime }
        if let endTime = endTime { updated.endTime = endTime }

        workHours[index] = updated
    }

    // MARK: - Private Methods

    private func applyPolicy(_ policy: CalendarPolicy) {
        self.policy = policy
        self.originalPolicy = policy

        // Work Hours
        workHours = policy.workHours

        // Focus Blocks
        focusBlocks = policy.focusBlocks

        // Meeting Limits
        maxMeetingsPerDay = policy.meetingLimits.maxMeetingsPerDay
        bufferMinutes = policy.meetingLimits.bufferMinutesBetweenMeetings
        maxConsecutiveHours = policy.meetingLimits.maxConsecutiveHours

        // Automation
        autoApplyFlexible = policy.autoApplyFlexible
        autoSendApprovals = policy.autoSendApprovals
        applyOnApproval = policy.applyOnApproval
    }

    private func buildPolicy() -> CalendarPolicy {
        let meetingLimits = MeetingLimits(
            maxMeetingsPerDay: maxMeetingsPerDay,
            bufferMinutesBetweenMeetings: bufferMinutes,
            maxConsecutiveHours: maxConsecutiveHours,
            preferredMeetingDurations: originalPolicy?.meetingLimits.preferredMeetingDurations ?? [30, 60]
        )

        return CalendarPolicy(
            workHours: workHours,
            focusBlocks: focusBlocks,
            meetingLimits: meetingLimits,
            autoApplyFlexible: autoApplyFlexible,
            autoSendApprovals: autoSendApprovals,
            applyOnApproval: applyOnApproval
        )
    }
}

// MARK: - Scheduling Settings View Model Factory

/// Factory for creating SchedulingSettingsViewModel instances
enum SchedulingSettingsViewModelFactory {
    static func create(api: CalendarAPIProtocol = CalendarAPIFactory.create()) -> SchedulingSettingsViewModel {
        return SchedulingSettingsViewModel(api: api)
    }

    #if DEBUG
    static func createMock(policy: CalendarPolicy = .default) -> SchedulingSettingsViewModel {
        let viewModel = SchedulingSettingsViewModel(api: MockCalendarAPI())
        viewModel.policy = policy
        return viewModel
    }
    #endif
}
