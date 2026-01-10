import SwiftUI

// MARK: - Thread Row View

/// Individual thread row component for the list
/// Shows sender avatar, name, subject, snippet, timestamp, and indicators
struct ThreadRowView: View {
    let thread: EmailThread
    var onStar: (() -> Void)?
    var onTap: (() -> Void)?

    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                // Avatar
                senderAvatar

                // Content
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    // Top row: Sender and Timestamp
                    HStack(alignment: .center) {
                        senderName
                        Spacer()
                        timestamp
                    }

                    // Subject
                    subject

                    // Snippet and indicators
                    HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                        snippet
                        Spacer()
                        indicators
                    }

                    // Labels
                    if !thread.labels.isEmpty && thread.labels.first?.type != .inbox {
                        labelsRow
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.listRowVerticalPadding)
            .padding(.horizontal, Theme.Spacing.listRowPadding)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.99 : 1.0)
        .animation(Theme.Animation.buttonPress, value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    // MARK: - Subviews

    private var senderAvatar: some View {
        ZStack {
            if let sender = thread.primarySender {
                if let avatarURL = sender.avatarURL {
                    AsyncImage(url: avatarURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarPlaceholder(for: sender)
                    }
                } else {
                    avatarPlaceholder(for: sender)
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: Theme.Spacing.avatarSizeMedium, height: Theme.Spacing.avatarSizeMedium)
        .clipShape(Circle())
        .overlay(
            // Unread indicator
            Circle()
                .fill(Theme.Colors.primary)
                .frame(width: 10, height: 10)
                .opacity(thread.isRead ? 0 : 1)
                .offset(x: -2, y: -2),
            alignment: .topLeading
        )
    }

    private func avatarPlaceholder(for sender: EmailParticipant) -> some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.avatarColor(for: sender.id))

            Text(sender.initials)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private var senderName: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            Text(thread.primarySender?.displayName ?? "Unknown")
                .font(thread.isRead ? Theme.Typography.body : Theme.Typography.bodyBold)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if thread.messagesCount > 1 {
                Text("(\(thread.messagesCount))")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timestamp: some View {
        Text(thread.formattedDate)
            .font(Theme.Typography.emailTimestamp)
            .foregroundStyle(thread.isRead ? .secondary : Theme.Colors.primary)
    }

    private var subject: some View {
        Text(thread.subject.isEmpty ? "(No subject)" : thread.subject)
            .font(thread.isRead ? Theme.Typography.emailSubject : Theme.Typography.calloutBold)
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private var snippet: some View {
        Text(thread.snippet)
            .font(Theme.Typography.emailSnippet)
            .foregroundStyle(.secondary)
            .lineLimit(2)
    }

    private var indicators: some View {
        HStack(spacing: Theme.Spacing.xs) {
            // Attachment indicator
            if thread.hasAttachments {
                Image(systemName: "paperclip")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Star button
            Button(action: {
                Haptics.light()
                onStar?()
            }) {
                Image(systemName: thread.isStarred ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(thread.isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var labelsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(thread.labels.filter { $0.type != .inbox }) { label in
                    GlassChip(
                        label.name,
                        color: label.displayColor,
                        style: .tinted,
                        size: .small
                    )
                }
            }
        }
        .padding(.top, Theme.Spacing.xxs)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
            .fill(thread.isRead ? Color.clear : Theme.Colors.primary.opacity(0.03))
    }
}

// MARK: - Skeleton Thread Row

/// Skeleton loading state for thread rows
struct SkeletonThreadRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Avatar skeleton
            Circle()
                .fill(shimmerGradient)
                .frame(width: Theme.Spacing.avatarSizeMedium, height: Theme.Spacing.avatarSizeMedium)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                // Sender row
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(width: 120, height: 14)

                    Spacer()

                    RoundedRectangle(cornerRadius: 4)
                        .fill(shimmerGradient)
                        .frame(width: 50, height: 12)
                }

                // Subject
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(height: 14)

                // Snippet
                RoundedRectangle(cornerRadius: 4)
                    .fill(shimmerGradient)
                    .frame(width: 200, height: 12)
            }
        }
        .padding(.vertical, Theme.Spacing.listRowVerticalPadding)
        .padding(.horizontal, Theme.Spacing.listRowPadding)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
                isAnimating = true
            }
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.gray.opacity(isAnimating ? 0.1 : 0.2),
                Color.gray.opacity(isAnimating ? 0.2 : 0.1)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Swipeable Thread Row

/// Thread row with swipe actions
struct SwipeableThreadRow: View {
    let thread: EmailThread
    var onArchive: (() -> Void)?
    var onDelete: (() -> Void)?
    var onToggleRead: (() -> Void)?
    var onStar: (() -> Void)?
    var onTap: (() -> Void)?

    @State private var offset: CGFloat = 0
    @State private var showLeftActions = false
    @State private var showRightActions = false
    @GestureState private var isDragging = false

    private let actionThreshold: CGFloat = 80
    private let fullSwipeThreshold: CGFloat = 150

    var body: some View {
        ZStack {
            // Background actions
            HStack(spacing: 0) {
                // Left actions (archive)
                leftActions
                Spacer()
                // Right actions (delete)
                rightActions
            }

            // Main row
            ThreadRowView(
                thread: thread,
                onStar: onStar,
                onTap: onTap
            )
            .offset(x: offset)
            .gesture(swipeGesture)
        }
        .clipped()
    }

    private var leftActions: some View {
        HStack(spacing: 0) {
            SwipeActionButton(
                icon: "archivebox.fill",
                title: "Archive",
                color: .green,
                action: {
                    Haptics.success()
                    resetOffset()
                    onArchive?()
                }
            )
            .opacity(offset > 0 ? 1 : 0)
            .frame(width: max(0, offset))
        }
    }

    private var rightActions: some View {
        HStack(spacing: 0) {
            SwipeActionButton(
                icon: thread.isRead ? "envelope.badge.fill" : "envelope.open.fill",
                title: thread.isRead ? "Unread" : "Read",
                color: .blue,
                action: {
                    Haptics.light()
                    resetOffset()
                    onToggleRead?()
                }
            )

            SwipeActionButton(
                icon: "trash.fill",
                title: "Delete",
                color: .red,
                action: {
                    Haptics.warning()
                    resetOffset()
                    onDelete?()
                }
            )
        }
        .opacity(offset < 0 ? 1 : 0)
        .frame(width: max(0, -offset))
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                let translation = value.translation.width

                // Apply resistance at edges
                if translation > 0 {
                    offset = min(fullSwipeThreshold, translation * 0.8)
                } else {
                    offset = max(-fullSwipeThreshold * 1.5, translation * 0.8)
                }
            }
            .onEnded { value in
                let translation = value.translation.width
                let velocity = value.predictedEndTranslation.width

                withAnimation(Theme.Animation.defaultSpring) {
                    // Full swipe left (archive)
                    if translation > fullSwipeThreshold || velocity > 500 {
                        offset = UIScreen.main.bounds.width
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            Haptics.success()
                            onArchive?()
                        }
                    }
                    // Partial swipe left
                    else if translation > actionThreshold {
                        offset = actionThreshold
                        showLeftActions = true
                    }
                    // Full swipe right (delete)
                    else if translation < -fullSwipeThreshold || velocity < -500 {
                        offset = -UIScreen.main.bounds.width
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            Haptics.warning()
                            onDelete?()
                        }
                    }
                    // Partial swipe right
                    else if translation < -actionThreshold {
                        offset = -actionThreshold * 2
                        showRightActions = true
                    }
                    // Reset
                    else {
                        resetOffset()
                    }
                }
            }
    }

    private func resetOffset() {
        withAnimation(Theme.Animation.defaultSpring) {
            offset = 0
            showLeftActions = false
            showRightActions = false
        }
    }
}

// MARK: - Swipe Action Button

struct SwipeActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(Theme.Typography.caption2)
            }
            .foregroundStyle(.white)
            .frame(width: 80)
            .frame(maxHeight: .infinity)
            .background(color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Thread Row") {
    VStack(spacing: 0) {
        ThreadRowView(
            thread: .mock,
            onStar: {},
            onTap: {}
        )

        Divider()

        ThreadRowView(
            thread: EmailThread(
                id: "thread-2",
                accountId: "account-1",
                subject: "Meeting Tomorrow - Please confirm your attendance",
                snippet: "Don't forget about our meeting tomorrow at 10am. We'll be discussing the Q4 roadmap and budget allocation for next year.",
                participants: [.mockSender, .mockRecipient],
                messages: [],
                labels: [.inbox, .starred],
                isRead: true,
                isStarred: true,
                isArchived: false,
                isTrashed: false,
                isSpam: false,
                hasAttachments: true,
                lastMessageAt: Date().addingTimeInterval(-7200),
                messagesCount: 3
            ),
            onStar: {},
            onTap: {}
        )
    }
    .background(Color(uiColor: .systemBackground))
}

#Preview("Skeleton Loading") {
    VStack(spacing: 0) {
        SkeletonThreadRow()
        Divider()
        SkeletonThreadRow()
        Divider()
        SkeletonThreadRow()
    }
    .background(Color(uiColor: .systemBackground))
}

#Preview("Swipeable Row") {
    SwipeableThreadRow(
        thread: .mock,
        onArchive: { print("Archive") },
        onDelete: { print("Delete") },
        onToggleRead: { print("Toggle read") },
        onStar: { print("Star") },
        onTap: { print("Tap") }
    )
    .background(Color(uiColor: .systemBackground))
}
