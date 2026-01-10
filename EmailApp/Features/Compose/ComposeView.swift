import SwiftUI
import PhotosUI

// MARK: - Compose View

/// Email composer with recipients, subject, body, attachments, and voice dictation
struct ComposeView: View {
    var replyToThread: EmailThread?
    var composeMode: ThreadDetailView.ComposeMode = .reply
    let onDismiss: () -> Void

    @StateObject private var viewModel = ComposeViewModel()
    @State private var showDiscardAlert = false
    @State private var showCcBcc = false
    @State private var showAttachmentPicker = false
    @State private var showRecipientPicker = false
    @State private var recipientFieldType: RecipientFieldType = .to
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @FocusState private var focusedField: FocusField?
    @Environment(\.colorScheme) private var colorScheme

    enum FocusField {
        case to, cc, bcc, subject, body
    }

    enum RecipientFieldType {
        case to, cc, bcc
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            // Recipients
                            recipientsSection

                            Divider()

                            // Subject
                            subjectField

                            Divider()

                            // Body
                            bodyEditor
                        }
                    }

                    // Toolbar
                    composeToolbar
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        handleCancel()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: sendEmail) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .disabled(!viewModel.canSend)
                }
            }
            .alert("Discard Draft?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) {
                    onDismiss()
                }
                Button("Save Draft") {
                    saveDraft()
                    onDismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Do you want to save this message as a draft or discard it?")
            }
            .photosPicker(
                isPresented: $showAttachmentPicker,
                selection: $selectedPhotoItems,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos, .pdf])
            )
            .onChange(of: selectedPhotoItems) { _, items in
                handlePhotoPicker(items)
            }
            .onAppear {
                setupForReply()
            }
        }
    }

    // MARK: - Navigation Title

    private var navigationTitle: String {
        if replyToThread != nil {
            switch composeMode {
            case .reply: return "Reply"
            case .replyAll: return "Reply All"
            case .forward: return "Forward"
            }
        }
        return "New Message"
    }

    // MARK: - Recipients Section

    private var recipientsSection: some View {
        VStack(spacing: 0) {
            // To field
            RecipientField(
                label: "To",
                recipients: $viewModel.recipients,
                text: $viewModel.toFieldText,
                isFocused: focusedField == .to,
                onTap: { focusedField = .to },
                onAddRecipient: {
                    recipientFieldType = .to
                    showRecipientPicker = true
                }
            )

            // Cc/Bcc toggle
            if !showCcBcc {
                Button(action: { showCcBcc = true }) {
                    HStack {
                        Text("Cc/Bcc")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.primary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .buttonStyle(.plain)
            }

            // Cc field
            if showCcBcc {
                Divider()
                    .padding(.leading, Theme.Spacing.md)

                RecipientField(
                    label: "Cc",
                    recipients: $viewModel.ccRecipients,
                    text: $viewModel.ccFieldText,
                    isFocused: focusedField == .cc,
                    onTap: { focusedField = .cc },
                    onAddRecipient: {
                        recipientFieldType = .cc
                        showRecipientPicker = true
                    }
                )

                Divider()
                    .padding(.leading, Theme.Spacing.md)

                // Bcc field
                RecipientField(
                    label: "Bcc",
                    recipients: $viewModel.bccRecipients,
                    text: $viewModel.bccFieldText,
                    isFocused: focusedField == .bcc,
                    onTap: { focusedField = .bcc },
                    onAddRecipient: {
                        recipientFieldType = .bcc
                        showRecipientPicker = true
                    }
                )
            }
        }
    }

    // MARK: - Subject Field

    private var subjectField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Subject")
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            TextField("", text: $viewModel.subject)
                .font(Theme.Typography.body)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .subject)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Body Editor

    private var bodyEditor: some View {
        VStack(spacing: 0) {
            // Text editor
            TextEditor(text: $viewModel.body)
                .font(Theme.Typography.body)
                .scrollContentBackground(.hidden)
                .focused($focusedField, equals: .body)
                .frame(minHeight: 200)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)

            // Attachments row
            if !viewModel.attachments.isEmpty {
                Divider()
                attachmentsRow
            }
        }
    }

    // MARK: - Attachments Row

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(viewModel.attachments) { attachment in
                    AttachmentPreview(
                        attachment: attachment,
                        onRemove: {
                            removeAttachment(attachment)
                        }
                    )
                }
            }
            .padding()
        }
    }

    // MARK: - Compose Toolbar

    private var composeToolbar: some View {
        GlassBottomToolbar {
            HStack(spacing: Theme.Spacing.lg) {
                // Attachment button
                Button(action: { showAttachmentPicker = true }) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                // Camera button
                Button(action: openCamera) {
                    Image(systemName: "camera")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                // Voice dictation button
                VoiceDictationButton(
                    isRecording: $viewModel.isRecording,
                    onToggle: toggleDictation
                )

                Spacer()

                // Character count
                if viewModel.body.count > 0 {
                    Text("\(viewModel.body.count)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                // AI assist button
                Menu {
                    Button(action: { viewModel.generateAIReply(tone: .professional) }) {
                        Label("Professional", systemImage: "briefcase")
                    }
                    Button(action: { viewModel.generateAIReply(tone: .casual) }) {
                        Label("Casual", systemImage: "hand.wave")
                    }
                    Button(action: { viewModel.generateAIReply(tone: .brief) }) {
                        Label("Brief", systemImage: "text.alignleft")
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xxs) {
                        Image(systemName: "sparkles")
                        Text("AI Assist")
                    }
                    .font(Theme.Typography.calloutBold)
                    .foregroundStyle(Theme.Colors.primary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        Capsule()
                            .fill(Theme.Colors.primary.opacity(0.1))
                    )
                }
            }
        }
    }

    // MARK: - Actions

    private func setupForReply() {
        guard let thread = replyToThread else { return }

        switch composeMode {
        case .reply:
            if let sender = thread.latestMessage?.sender {
                viewModel.recipients = [sender]
            }
            viewModel.subject = thread.subject.hasPrefix("Re: ") ? thread.subject : "Re: \(thread.subject)"
        case .replyAll:
            if let message = thread.latestMessage {
                viewModel.recipients = [message.sender] + message.recipients.filter { $0.email != "user@gmail.com" }
                viewModel.ccRecipients = message.ccRecipients
            }
            viewModel.subject = thread.subject.hasPrefix("Re: ") ? thread.subject : "Re: \(thread.subject)"
            showCcBcc = !viewModel.ccRecipients.isEmpty
        case .forward:
            viewModel.subject = thread.subject.hasPrefix("Fwd: ") ? thread.subject : "Fwd: \(thread.subject)"
            if let message = thread.latestMessage {
                viewModel.body = "\n\n---------- Forwarded message ----------\nFrom: \(message.sender.displayName)\nDate: \(formatDate(message.sentAt))\nSubject: \(message.subject)\n\n\(message.bodyPlainText)"
            }
        }

        focusedField = composeMode == .forward ? .to : .body
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func handleCancel() {
        if viewModel.hasContent {
            showDiscardAlert = true
        } else {
            onDismiss()
        }
    }

    private func sendEmail() {
        Haptics.success()
        viewModel.send()
        onDismiss()
    }

    private func saveDraft() {
        viewModel.saveDraft()
    }

    private func toggleDictation() {
        Haptics.medium()
        viewModel.toggleDictation()
    }

    private func openCamera() {
        Haptics.light()
        // Would open camera
    }

    private func handlePhotoPicker(_ items: [PhotosPickerItem]) {
        Task {
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // Create attachment from data
                    let attachment = EmailAttachment(
                        id: UUID().uuidString,
                        filename: "image.jpg",
                        mimeType: "image/jpeg",
                        size: Int64(data.count),
                        downloadURL: nil,
                        thumbnailURL: nil
                    )
                    await MainActor.run {
                        viewModel.attachments.append(attachment)
                    }
                }
            }
        }
    }

    private func removeAttachment(_ attachment: EmailAttachment) {
        Haptics.light()
        viewModel.attachments.removeAll { $0.id == attachment.id }
    }
}

// MARK: - Recipient Field

struct RecipientField: View {
    let label: String
    @Binding var recipients: [EmailParticipant]
    @Binding var text: String
    let isFocused: Bool
    var onTap: (() -> Void)?
    var onAddRecipient: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
                .padding(.top, Theme.Spacing.sm)

            // Recipients chips + input
            FlowingChipLayout(spacing: Theme.Spacing.xs, lineSpacing: Theme.Spacing.xs) {
                ForEach(recipients) { recipient in
                    RecipientChip(
                        participant: recipient,
                        isRemovable: true,
                        onRemove: {
                            removeRecipient(recipient)
                        }
                    )
                }

                // Input field
                TextField("", text: $text)
                    .font(Theme.Typography.body)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 100)
                    .onSubmit {
                        addRecipientFromText()
                    }
            }
            .padding(.vertical, Theme.Spacing.xs)

            // Add button
            Button(action: { onAddRecipient?() }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.primary)
            }
            .buttonStyle(.plain)
            .padding(.top, Theme.Spacing.sm)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xxs)
        .background(isFocused ? Theme.Colors.primary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private func removeRecipient(_ recipient: EmailParticipant) {
        Haptics.light()
        recipients.removeAll { $0.id == recipient.id }
    }

    private func addRecipientFromText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.contains("@") else { return }

        let recipient = EmailParticipant(
            id: UUID().uuidString,
            email: trimmed,
            name: nil,
            avatarURL: nil
        )
        recipients.append(recipient)
        text = ""
    }
}

// MARK: - Voice Dictation Button

struct VoiceDictationButton: View {
    @Binding var isRecording: Bool
    let onToggle: () -> Void

    @State private var pulseAnimation = false

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                if isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 44, height: 44)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.5)
                        .animation(
                            .easeInOut(duration: 1.0).repeatForever(autoreverses: false),
                            value: pulseAnimation
                        )
                }

                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isRecording ? .red : .primary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.2) : Color.clear)
                    )
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, newValue in
            pulseAnimation = newValue
        }
    }
}

// MARK: - Attachment Preview

struct AttachmentPreview: View {
    let attachment: EmailAttachment
    var onRemove: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            ZStack(alignment: .topTrailing) {
                // Thumbnail or icon
                if attachment.isImage, let url = attachment.thumbnailURL {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        iconPlaceholder
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.sm))
                } else {
                    iconPlaceholder
                }

                // Remove button
                if onRemove != nil {
                    Button(action: { onRemove?() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: 8, y: -8)
                }
            }

            // Filename
            Text(attachment.filename)
                .font(Theme.Typography.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 80)

            // Size
            Text(attachment.formattedSize)
                .font(Theme.Typography.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var iconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.sm)
                .fill(Theme.Colors.primary.opacity(0.1))
                .frame(width: 80, height: 80)

            Image(systemName: attachment.iconName)
                .font(.system(size: 28))
                .foregroundStyle(Theme.Colors.primary)
        }
    }
}

// MARK: - Preview

#Preview("New Compose") {
    ComposeView(
        replyToThread: nil,
        onDismiss: {}
    )
}

#Preview("Reply") {
    ComposeView(
        replyToThread: .mock,
        composeMode: .reply,
        onDismiss: {}
    )
}
