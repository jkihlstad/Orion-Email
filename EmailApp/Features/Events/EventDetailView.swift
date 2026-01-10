import SwiftUI

// MARK: - Event Detail View

/// Displays detailed information about a calendar event with AI control options
struct EventDetailView: View {
    // MARK: - Properties

    @StateObject private var viewModel: EventDetailViewModel
    @State private var showingAIControlSheet = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let eventId: String

    // MARK: - Initialization

    init(eventId: String, api: CalendarAPIProtocol = CalendarAPIFactory.create()) {
        self.eventId = eventId
        _viewModel = StateObject(wrappedValue: EventDetailViewModel(api: api))
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                if viewModel.isLoading {
                    loadingView
                } else if let event = viewModel.event {
                    eventContent(event)
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    emptyStateView
                }
            }
            .padding()
        }
        .background(backgroundGradient)
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAIControlSheet) {
            if let event = viewModel.event {
                EventAIControlSheet(
                    event: event,
                    onSave: { policy in
                        Task {
                            await viewModel.updatePolicy(policy)
                        }
                    }
                )
            }
        }
        .task {
            await viewModel.loadEvent(id: eventId)
        }
    }

    // MARK: - Event Content

    @ViewBuilder
    private func eventContent(_ event: CalendarEvent) -> some View {
        // Title and Lock State Badge
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(event.title)
                            .font(Theme.Typography.title2)
                            .foregroundStyle(Color.primary)

                        Text(event.formattedDate)
                            .font(Theme.Typography.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    lockStateBadge(event.policy.lockState)
                }

                Divider()

                // Time
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.blue)
                    Text(event.formattedTimeRange)
                        .font(Theme.Typography.body)
                    Text("(\(event.formattedDuration))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                // Location
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.red)
                        Text(location)
                            .font(Theme.Typography.body)
                    }
                }

                // Organizer
                if let organizer = event.organizer {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "person.fill")
                            .foregroundStyle(.green)
                        Text("Organized by \(organizer.displayName)")
                            .font(Theme.Typography.body)
                    }
                }
            }
        }

        // Attendees Section
        if !event.attendees.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text("Attendees")
                            .font(Theme.Typography.headline)
                        Spacer()
                        Text("\(event.attendees.count)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xxs)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    ForEach(event.attendees) { attendee in
                        attendeeRow(attendee)
                    }
                }
            }
        }

        // AI Policy Section
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text("AI Scheduling")
                        .font(Theme.Typography.headline)
                    Spacer()
                    Button {
                        Haptics.light()
                        showingAIControlSheet = true
                    } label: {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Configure")
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.blue)
                    }
                }

                Divider()

                policyRow(
                    icon: event.policy.lockState.iconName,
                    iconColor: event.policy.lockState.color,
                    title: "Lock State",
                    value: event.policy.lockState.displayName
                )

                policyRow(
                    icon: "person.badge.key.fill",
                    iconColor: .purple,
                    title: "Move Permissions",
                    value: event.policy.movePermissions.displayName
                )

                policyRow(
                    icon: "eye.fill",
                    iconColor: .blue,
                    title: "Content Sharing",
                    value: event.policy.contentSharing.displayName
                )

                if event.policy.requiresUserConfirmationBeforeSendingRequests {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                        Text("Requires confirmation before sending requests")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let approver = event.policy.approver {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "person.badge.shield.checkmark.fill")
                            .foregroundStyle(.orange)
                        Text("Approver: \(approver.displayName)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let maxShift = event.policy.maxShiftMinutes {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.teal)
                        Text("Max shift: \(maxShift) minutes")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        // Configure AI Button
        Button {
            Haptics.medium()
            showingAIControlSheet = true
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Configure AI Settings")
                    .font(Theme.Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.button))
        }
    }

    // MARK: - Helper Views

    private func lockStateBadge(_ state: LockState) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: state.iconName)
            Text(state.displayName)
                .font(Theme.Typography.captionBold)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(state.color.opacity(0.15))
        .foregroundStyle(state.color)
        .clipShape(Capsule())
    }

    private func attendeeRow(_ attendee: Attendee) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(Theme.Colors.avatarColor(for: attendee.email))
                .frame(width: Theme.Spacing.avatarSizeSmall, height: Theme.Spacing.avatarSizeSmall)
                .overlay(
                    Text(attendee.initials)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.displayName)
                    .font(Theme.Typography.body)
                Text(attendee.email)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private func policyRow(icon: String, iconColor: Color, title: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(Theme.Typography.bodyBold)
        }
    }

    private var loadingView: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading event...")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xxl)
        }
    }

    private func errorView(_ error: CalendarError) -> some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)

                Text("Unable to Load Event")
                    .font(Theme.Typography.headline)

                Text(error.errorDescription ?? "An error occurred")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    Task {
                        await viewModel.loadEvent(id: eventId)
                    }
                } label: {
                    Text("Try Again")
                        .font(Theme.Typography.bodyBold)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
    }

    private var emptyStateView: some View {
        GlassCard {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text("Event Not Found")
                    .font(Theme.Typography.headline)

                Text("This event may have been deleted or moved.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.blue.opacity(0.15), Color.purple.opacity(0.1)]
                : [Color.blue.opacity(0.08), Color.purple.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EventDetailView(eventId: "event-1", api: MockCalendarAPI())
    }
}
