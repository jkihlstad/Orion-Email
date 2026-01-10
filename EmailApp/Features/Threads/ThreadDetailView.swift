import SwiftUI

// MARK: - Thread Detail View

/// Thread detail view with message cards, quick actions, attachments, and AI summary
struct ThreadDetailView: View {
    let thread: EmailThread

    @StateObject private var viewModel = ThreadDetailViewModel()
    @State private var showCompose = false
    @State private var composeMode: ComposeMode = .reply
    @State private var showAIChat = false
    @State private var expandedMessageIds: Set<String> = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    enum ComposeMode {
        case reply
        case replyAll
        case forward
    }

    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            // Content
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    // Subject header
                    subjectHeader

                    // AI Summary (if available)
                    if viewModel.aiSummary != nil {
                        aiSummaryCard
                    }

                    // Messages
                    messagesStack

                    // Quick reply suggestions
                    if let summary = viewModel.aiSummary, !summary.suggestedReplies.isEmpty {
                        suggestedReplies
                    }

                    // Bottom padding
                    Color.clear.frame(height: 100)
                }
                .padding(.horizontal)
            }

            // Bottom action bar
            VStack {
                Spacer()
                quickActionBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarActions
            }
        }
        .sheet(isPresented: $showCompose) {
            ComposeView(
                replyToThread: thread,
                composeMode: composeMode,
                onDismiss: { showCompose = false }
            )
        }
        .sheet(isPresented: $showAIChat) {
            AIChatView(thread: thread)
        }
        .task {
            viewModel.loadThread(thread)
            await viewModel.loadAISummary()
        }
    }

    // MARK: - Subject Header

    private var subjectHeader: some View {
        GlassCard(padding: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Subject
                Text(thread.subject.isEmpty ? "(No subject)" : thread.subject)
                    .font(Theme.Typography.title3)
                    .foregroundStyle(.primary)

                // Labels
                if !thread.labels.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(thread.labels) { label in
                                EmailLabelChip(label: label, size: .small)
                            }
                        }
                    }
                }

                // Metadata
                HStack(spacing: Theme.Spacing.md) {
                    Label("\(thread.messagesCount) messages", systemImage: "envelope")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)

                    if thread.hasAttachments {
                        Label("Has attachments", systemImage: "paperclip")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Star button
                    Button(action: toggleStar) {
                        Image(systemName: thread.isStarred ? "star.fill" : "star")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(thread.isStarred ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - AI Summary Card

    private var aiSummaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                // Header
                HStack {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Colors.primary)

                    Text("AI Summary")
                        .font(Theme.Typography.headline)

                    Spacer()

                    if let sentiment = viewModel.aiSummary?.sentiment {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Image(systemName: sentiment.iconName)
                            Text(sentiment.rawValue.capitalized)
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(sentiment.color)
                    }
                }

                // Summary text
                if let summary = viewModel.aiSummary {
                    Text(summary.summary)
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)

                    // Key points
                    if !summary.keyPoints.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Key Points")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(.primary)

                            ForEach(summary.keyPoints, id: \.self) { point in
                                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                    Circle()
                                        .fill(Theme.Colors.primary)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    Text(point)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }

                    // Action items
                    if !summary.actionItems.isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Action Items")
                                .font(Theme.Typography.captionBold)
                                .foregroundStyle(.primary)

                            ForEach(summary.actionItems, id: \.self) { item in
                                HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.Colors.primary)
                                    Text(item)
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
                }

                // Ask AI button
                Button(action: { showAIChat = true }) {
                    HStack {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                        Text("Ask AI about this email")
                    }
                    .font(Theme.Typography.calloutBold)
                    .foregroundStyle(Theme.Colors.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.button)
                            .fill(Theme.Colors.primary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    // MARK: - Messages Stack

    private var messagesStack: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ForEach(viewModel.messages) { message in
                MessageCard(
                    message: message,
                    isExpanded: expandedMessageIds.contains(message.id),
                    onToggleExpand: {
                        toggleMessageExpansion(message)
                    },
                    onReply: {
                        composeMode = .reply
                        showCompose = true
                    }
                )
            }
        }
    }

    // MARK: - Suggested Replies

    private var suggestedReplies: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Suggested Replies")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.sm)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    if let replies = viewModel.aiSummary?.suggestedReplies {
                        ForEach(replies) { reply in
                            SuggestedReplyChip(reply: reply) {
                                // Use this reply
                                composeMode = .reply
                                showCompose = true
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Quick Action Bar

    private var quickActionBar: some View {
        GlassBottomToolbar {
            HStack(spacing: Theme.Spacing.lg) {
                QuickActionButton(icon: "arrowshape.turn.up.left.fill", label: "Reply") {
                    composeMode = .reply
                    showCompose = true
                }

                QuickActionButton(icon: "arrowshape.turn.up.left.2.fill", label: "Reply All") {
                    composeMode = .replyAll
                    showCompose = true
                }

                QuickActionButton(icon: "arrowshape.turn.up.right.fill", label: "Forward") {
                    composeMode = .forward
                    showCompose = true
                }

                QuickActionButton(icon: "archivebox.fill", label: "Archive") {
                    archiveThread()
                }

                QuickActionButton(icon: "trash.fill", label: "Delete", isDestructive: true) {
                    deleteThread()
                }
            }
        }
    }

    // MARK: - Toolbar Actions

    private var toolbarActions: some View {
        Menu {
            Button(action: toggleStar) {
                Label(
                    thread.isStarred ? "Unstar" : "Star",
                    systemImage: thread.isStarred ? "star.slash" : "star"
                )
            }

            Button(action: toggleRead) {
                Label(
                    thread.isRead ? "Mark as Unread" : "Mark as Read",
                    systemImage: thread.isRead ? "envelope.badge" : "envelope.open"
                )
            }

            Divider()

            Button(action: { /* Move to label */ }) {
                Label("Move to...", systemImage: "folder")
            }

            Button(action: { /* Add label */ }) {
                Label("Label as...", systemImage: "tag")
            }

            Divider()

            Button(action: markAsSpam) {
                Label("Report Spam", systemImage: "exclamationmark.shield")
            }

            Button(role: .destructive, action: deleteThread) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
        }
    }

    // MARK: - Actions

    private func toggleMessageExpansion(_ message: EmailMessage) {
        Haptics.selection()
        withAnimation(Theme.Animation.defaultSpring) {
            if expandedMessageIds.contains(message.id) {
                expandedMessageIds.remove(message.id)
            } else {
                expandedMessageIds.insert(message.id)
            }
        }
    }

    private func toggleStar() {
        Haptics.light()
        viewModel.applyAction(thread.isStarred ? .unstar : .star)
    }

    private func toggleRead() {
        Haptics.light()
        viewModel.applyAction(thread.isRead ? .markUnread : .markRead)
    }

    private func archiveThread() {
        Haptics.success()
        viewModel.applyAction(.archive)
        dismiss()
    }

    private func deleteThread() {
        Haptics.warning()
        viewModel.applyAction(.trash)
        dismiss()
    }

    private func markAsSpam() {
        Haptics.warning()
        viewModel.applyAction(.spam)
        dismiss()
    }
}

// MARK: - Message Card

struct MessageCard: View {
    let message: EmailMessage
    let isExpanded: Bool
    var onToggleExpand: (() -> Void)?
    var onReply: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Header (always visible)
                Button(action: { onToggleExpand?() }) {
                    messageHeader
                }
                .buttonStyle(.plain)

                // Body (when expanded)
                if isExpanded {
                    Divider()
                        .padding(.horizontal)

                    messageBody

                    // Attachments
                    if !message.attachments.isEmpty {
                        Divider()
                            .padding(.horizontal)
                        attachmentsRow
                    }
                }
            }
        }
    }

    private var messageHeader: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            // Avatar
            SenderAvatar(sender: message.sender, size: 36)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                // Sender name and timestamp
                HStack {
                    Text(message.sender.displayName)
                        .font(Theme.Typography.bodyBold)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(formatDate(message.sentAt))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                // Recipients
                Text(recipientsText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Snippet (when collapsed)
                if !isExpanded {
                    Text(message.snippet)
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, Theme.Spacing.xxs)
                }
            }
        }
        .padding()
    }

    private var messageBody: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            // Full body text
            Text(message.bodyPlainText)
                .font(Theme.Typography.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            // Quick actions
            HStack(spacing: Theme.Spacing.md) {
                Button(action: { onReply?() }) {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "arrowshape.turn.up.left")
                        Text("Reply")
                    }
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.primary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: { /* Copy */ }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button(action: { /* Share */ }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(message.attachments) { attachment in
                    AttachmentChip(attachment: attachment)
                }
            }
            .padding()
        }
    }

    private var recipientsText: String {
        var text = "to "
        let names = message.recipients.map { $0.displayName }
        if names.count <= 2 {
            text += names.joined(separator: ", ")
        } else {
            text += "\(names[0]), \(names[1]), and \(names.count - 2) others"
        }
        return text
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Sender Avatar

struct SenderAvatar: View {
    let sender: EmailParticipant
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if let avatarURL = sender.avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholderView
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholderView: some View {
        ZStack {
            Circle()
                .fill(Theme.Colors.avatarColor(for: sender.id))
            Text(sender.initials)
                .font(.system(size: size * 0.35, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Attachment Chip

struct AttachmentChip: View {
    let attachment: EmailAttachment

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: attachment.iconName)
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.primary)

            VStack(alignment: .leading, spacing: 0) {
                Text(attachment.filename)
                    .font(Theme.Typography.caption)
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(Theme.Typography.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Suggested Reply Chip

struct SuggestedReplyChip: View {
    let reply: SuggestedReply
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    Image(systemName: reply.tone.iconName)
                        .font(.system(size: 10))
                    Text(reply.label)
                        .font(Theme.Typography.captionBold)
                }
                .foregroundStyle(Theme.Colors.primary)

                Text(reply.content)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding()
            .frame(width: 200, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.CornerRadius.md)
                            .stroke(Theme.Colors.primary.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            VStack(spacing: Theme.Spacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(Theme.Typography.caption2)
            }
            .foregroundStyle(isDestructive ? Theme.Colors.error : .primary)
            .frame(minWidth: 50)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - AI Chat View

struct AIChatView: View {
    let thread: EmailThread
    @Environment(\.dismiss) private var dismiss
    @State private var inputText = ""

    var body: some View {
        NavigationStack {
            VStack {
                // Chat messages would go here
                ScrollView {
                    Text("Ask me anything about this email thread...")
                        .font(Theme.Typography.body)
                        .foregroundStyle(.secondary)
                        .padding()
                }

                Spacer()

                // Input field
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("Ask about this email...", text: $inputText)
                        .textFieldStyle(.plain)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: Theme.CornerRadius.searchBar)
                                .fill(.ultraThinMaterial)
                        )

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(inputText.isEmpty ? .secondary : Theme.Colors.primary)
                    }
                    .disabled(inputText.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Ask AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sendMessage() {
        // Would send message to AI
        inputText = ""
    }
}

// MARK: - Preview

#Preview("Thread Detail") {
    NavigationStack {
        ThreadDetailView(thread: .mock)
    }
}
