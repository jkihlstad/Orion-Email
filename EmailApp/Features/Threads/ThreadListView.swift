import SwiftUI

// MARK: - Thread List View

/// Main inbox view with pull to refresh, thread rows, swipe actions, and empty states
struct ThreadListView: View {
    @ObservedObject var viewModel: ThreadListViewModel
    let selectedLabel: EmailLabel
    var onThreadSelected: ((EmailThread) -> Void)?
    var onComposeTapped: (() -> Void)?
    var onMenuTapped: (() -> Void)?
    var onSearchTapped: (() -> Void)?

    @State private var showingSelectionMode = false
    @State private var selectedThreadIds: Set<String> = []
    @State private var showDeleteConfirmation = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Toolbar
                toolbar

                // Content
                if viewModel.isLoading && viewModel.threads.isEmpty {
                    loadingState
                } else if viewModel.threads.isEmpty {
                    emptyState
                } else {
                    threadList
                }
            }

            // Floating compose button
            if !showingSelectionMode {
                composeButton
            }

            // Selection toolbar
            if showingSelectionMode && !selectedThreadIds.isEmpty {
                selectionToolbar
            }
        }
        .alert("Delete emails?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteSelectedThreads()
            }
        } message: {
            Text("This will move \(selectedThreadIds.count) email(s) to trash.")
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        GlassToolbar(
            leading: {
                GlassToolbarButton(iconName: "line.3.horizontal") {
                    onMenuTapped?()
                }
            },
            center: {
                VStack(spacing: Theme.Spacing.xxs) {
                    Text(selectedLabel.name)
                        .font(Theme.Typography.headline)

                    if viewModel.isRefreshing {
                        HStack(spacing: Theme.Spacing.xxs) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Updating...")
                                .font(Theme.Typography.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if selectedLabel.unreadCount > 0 {
                        Text("\(selectedLabel.unreadCount) unread")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            },
            trailing: {
                GlassToolbarButton(iconName: "magnifyingglass") {
                    onSearchTapped?()
                }

                if showingSelectionMode {
                    Button("Done") {
                        exitSelectionMode()
                    }
                    .font(Theme.Typography.bodyBold)
                } else {
                    GlassToolbarButton(iconName: "ellipsis") {
                        showingSelectionMode = true
                    }
                }
            }
        )
    }

    // MARK: - Thread List

    private var threadList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.threads) { thread in
                    VStack(spacing: 0) {
                        if showingSelectionMode {
                            selectableThreadRow(thread)
                        } else {
                            SwipeableThreadRow(
                                thread: thread,
                                onArchive: {
                                    archiveThread(thread)
                                },
                                onDelete: {
                                    deleteThread(thread)
                                },
                                onToggleRead: {
                                    toggleRead(thread)
                                },
                                onStar: {
                                    toggleStar(thread)
                                },
                                onTap: {
                                    Haptics.light()
                                    onThreadSelected?(thread)
                                }
                            )
                        }

                        Divider()
                            .padding(.leading, Theme.Spacing.listRowPadding + Theme.Spacing.avatarSizeMedium + Theme.Spacing.sm)
                    }
                }

                // Bottom padding for FAB
                Color.clear
                    .frame(height: 100)
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private func selectableThreadRow(_ thread: EmailThread) -> some View {
        Button(action: { toggleSelection(thread) }) {
            HStack(spacing: Theme.Spacing.sm) {
                // Selection checkbox
                ZStack {
                    Circle()
                        .stroke(
                            selectedThreadIds.contains(thread.id) ? Theme.Colors.primary : Color.gray.opacity(0.3),
                            lineWidth: 2
                        )
                        .frame(width: 24, height: 24)

                    if selectedThreadIds.contains(thread.id) {
                        Circle()
                            .fill(Theme.Colors.primary)
                            .frame(width: 24, height: 24)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.leading, Theme.Spacing.md)

                // Thread row content
                ThreadRowView(
                    thread: thread,
                    onStar: nil,
                    onTap: nil
                )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    VStack(spacing: 0) {
                        SkeletonThreadRow()
                        Divider()
                            .padding(.leading, Theme.Spacing.listRowPadding + Theme.Spacing.avatarSizeMedium + Theme.Spacing.sm)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()

            Image(systemName: emptyStateIcon)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(emptyStateTitle)
                .font(Theme.Typography.title2)

            Text(emptyStateMessage)
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)

            if selectedLabel.type == .inbox {
                Button(action: { onComposeTapped?() }) {
                    Text("Compose an email")
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.md)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.primary)
                        )
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.top, Theme.Spacing.md)
            }

            Spacer()
        }
    }

    private var emptyStateIcon: String {
        switch selectedLabel.type {
        case .inbox: return "tray"
        case .sent: return "paperplane"
        case .drafts: return "doc.text"
        case .spam: return "shield.checkered"
        case .trash: return "trash"
        case .starred: return "star"
        default: return "tray"
        }
    }

    private var emptyStateTitle: String {
        switch selectedLabel.type {
        case .inbox: return "Your inbox is empty"
        case .sent: return "No sent messages"
        case .drafts: return "No drafts"
        case .spam: return "No spam"
        case .trash: return "Trash is empty"
        case .starred: return "No starred messages"
        default: return "No emails"
        }
    }

    private var emptyStateMessage: String {
        switch selectedLabel.type {
        case .inbox: return "Messages you receive will appear here"
        case .sent: return "Messages you send will appear here"
        case .drafts: return "Unfinished messages will be saved here"
        case .spam: return "Messages marked as spam will appear here"
        case .trash: return "Deleted messages will appear here"
        case .starred: return "Star important messages to find them here"
        default: return "Messages with this label will appear here"
        }
    }

    // MARK: - Compose Button

    private var composeButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button(action: {
                    Haptics.medium()
                    onComposeTapped?()
                }) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Compose")
                            .font(Theme.Typography.bodyBold)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.primary)
                    )
                    .shadow(Theme.Shadows.glassElevated)
                }
                .buttonStyle(GlassButtonStyle())
                .padding(.trailing, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.lg)
            }
        }
    }

    // MARK: - Selection Toolbar

    private var selectionToolbar: some View {
        VStack {
            Spacer()
            FloatingActionBar(actions: [
                FloatingAction(id: "read", label: "Read", iconName: "envelope.open") {
                    markSelectedAsRead()
                },
                FloatingAction(id: "archive", label: "Archive", iconName: "archivebox") {
                    archiveSelectedThreads()
                },
                FloatingAction(id: "delete", label: "Delete", iconName: "trash", isDestructive: true) {
                    showDeleteConfirmation = true
                },
                FloatingAction(id: "more", label: "More", iconName: "ellipsis") {
                    // Show more options
                }
            ])
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    // MARK: - Actions

    private func toggleSelection(_ thread: EmailThread) {
        Haptics.selection()
        withAnimation(Theme.Animation.easeFast) {
            if selectedThreadIds.contains(thread.id) {
                selectedThreadIds.remove(thread.id)
            } else {
                selectedThreadIds.insert(thread.id)
            }
        }
    }

    private func exitSelectionMode() {
        Haptics.light()
        withAnimation(Theme.Animation.defaultSpring) {
            showingSelectionMode = false
            selectedThreadIds.removeAll()
        }
    }

    private func archiveThread(_ thread: EmailThread) {
        viewModel.applyAction(threadId: thread.id, action: .archive)
    }

    private func deleteThread(_ thread: EmailThread) {
        viewModel.applyAction(threadId: thread.id, action: .trash)
    }

    private func toggleRead(_ thread: EmailThread) {
        let action: MessageAction = thread.isRead ? .markUnread : .markRead
        viewModel.applyAction(threadId: thread.id, action: action)
    }

    private func toggleStar(_ thread: EmailThread) {
        let action: MessageAction = thread.isStarred ? .unstar : .star
        viewModel.applyAction(threadId: thread.id, action: action)
    }

    private func markSelectedAsRead() {
        for threadId in selectedThreadIds {
            viewModel.applyAction(threadId: threadId, action: .markRead)
        }
        exitSelectionMode()
    }

    private func archiveSelectedThreads() {
        for threadId in selectedThreadIds {
            viewModel.applyAction(threadId: threadId, action: .archive)
        }
        exitSelectionMode()
    }

    private func deleteSelectedThreads() {
        for threadId in selectedThreadIds {
            viewModel.applyAction(threadId: threadId, action: .trash)
        }
        exitSelectionMode()
    }
}

// MARK: - Preview

#Preview("Thread List") {
    struct PreviewWrapper: View {
        @StateObject private var viewModel = ThreadListViewModel()

        var body: some View {
            ThreadListView(
                viewModel: viewModel,
                selectedLabel: .inbox,
                onThreadSelected: { _ in },
                onComposeTapped: {},
                onMenuTapped: {},
                onSearchTapped: {}
            )
            .onAppear {
                viewModel.loadThreads(labelId: "INBOX")
            }
        }
    }

    return PreviewWrapper()
}

#Preview("Empty State") {
    struct PreviewWrapper: View {
        @StateObject private var viewModel = ThreadListViewModel()

        var body: some View {
            ThreadListView(
                viewModel: viewModel,
                selectedLabel: .starred,
                onThreadSelected: { _ in },
                onComposeTapped: {},
                onMenuTapped: {},
                onSearchTapped: {}
            )
        }
    }

    return PreviewWrapper()
}

#Preview("Loading State") {
    struct PreviewWrapper: View {
        @StateObject private var viewModel: ThreadListViewModel = {
            let vm = ThreadListViewModel()
            vm.isLoading = true
            return vm
        }()

        var body: some View {
            ThreadListView(
                viewModel: viewModel,
                selectedLabel: .inbox,
                onThreadSelected: { _ in },
                onComposeTapped: {},
                onMenuTapped: {},
                onSearchTapped: {}
            )
        }
    }

    return PreviewWrapper()
}
