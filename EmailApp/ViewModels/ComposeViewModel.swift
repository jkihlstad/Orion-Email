import Foundation
import SwiftUI
import Combine
import Speech

// MARK: - Compose View Model

/// ViewModel for the email composer
/// Handles recipients, subject, body, attachments, and voice dictation
@MainActor
class ComposeViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var recipients: [EmailParticipant] = []
    @Published var ccRecipients: [EmailParticipant] = []
    @Published var bccRecipients: [EmailParticipant] = []

    @Published var toFieldText = ""
    @Published var ccFieldText = ""
    @Published var bccFieldText = ""

    @Published var subject = ""
    @Published var body = ""

    @Published var attachments: [EmailAttachment] = []

    @Published var isSending = false
    @Published var isSavingDraft = false
    @Published var isRecording = false
    @Published var sendError: EmailError?

    // MARK: - Computed Properties

    var canSend: Bool {
        !recipients.isEmpty && (!subject.isEmpty || !body.isEmpty)
    }

    var hasContent: Bool {
        !recipients.isEmpty ||
        !ccRecipients.isEmpty ||
        !bccRecipients.isEmpty ||
        !subject.isEmpty ||
        !body.isEmpty ||
        !attachments.isEmpty
    }

    var totalRecipientsCount: Int {
        recipients.count + ccRecipients.count + bccRecipients.count
    }

    var attachmentsTotalSize: Int64 {
        attachments.reduce(0) { $0 + $1.size }
    }

    var formattedAttachmentsSize: String {
        ByteCountFormatter.string(fromByteCount: attachmentsTotalSize, countStyle: .file)
    }

    // MARK: - Private Properties

    private let emailAPI: EmailAPIProtocol
    private let aiAssistant: AIEmailAssistantProtocol
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var cancellables = Set<AnyCancellable>()
    private var currentDraftId: String?

    // MARK: - Initialization

    init(
        emailAPI: EmailAPIProtocol = ConvexEmailAPI(),
        aiAssistant: AIEmailAssistantProtocol = AIEmailAssistant()
    ) {
        self.emailAPI = emailAPI
        self.aiAssistant = aiAssistant

        setupSpeechRecognition()
        setupAutoSave()
    }

    // MARK: - Public Methods

    /// Sends the email
    func send() {
        guard canSend else { return }

        isSending = true
        sendError = nil

        Task {
            do {
                // Create draft first
                let draft = try await createDraftForSending()

                // Send the draft
                try await emailAPI.sendDraft(draftId: draft.id)

                isSending = false
                Haptics.success()
            } catch let error as EmailError {
                sendError = error
                isSending = false
                Haptics.error()
            } catch {
                sendError = .networkError(error.localizedDescription)
                isSending = false
                Haptics.error()
            }
        }
    }

    /// Saves the current compose state as a draft
    func saveDraft() {
        guard hasContent else { return }

        isSavingDraft = true

        Task {
            do {
                let draft = EmailDraft(
                    id: currentDraftId ?? UUID().uuidString,
                    accountId: "current-account",
                    replyToMessageId: nil,
                    replyToThreadId: nil,
                    recipients: recipients,
                    ccRecipients: ccRecipients,
                    bccRecipients: bccRecipients,
                    subject: subject,
                    body: body,
                    attachments: attachments,
                    createdAt: Date(),
                    updatedAt: Date(),
                    isDraft: true
                )

                let savedDraft = try await emailAPI.createDraft(draft: draft)
                currentDraftId = savedDraft.id
                isSavingDraft = false
            } catch {
                isSavingDraft = false
            }
        }
    }

    /// Toggles voice dictation
    func toggleDictation() {
        if isRecording {
            stopDictation()
        } else {
            startDictation()
        }
    }

    /// Generates an AI reply based on the given tone
    func generateAIReply(tone: SuggestedReply.ReplyTone) {
        Task {
            // Create a mock thread for context (in real app, would use actual thread)
            let mockThread = EmailThread.mock

            if let reply = try? await aiAssistant.generateReply(for: mockThread, tone: tone) {
                body = reply
                Haptics.success()
            }
        }
    }

    /// Adds a recipient from email string
    func addRecipient(_ email: String, to field: RecipientField) {
        let recipient = EmailParticipant(
            id: UUID().uuidString,
            email: email,
            name: nil,
            avatarURL: nil
        )

        switch field {
        case .to:
            recipients.append(recipient)
            toFieldText = ""
        case .cc:
            ccRecipients.append(recipient)
            ccFieldText = ""
        case .bcc:
            bccRecipients.append(recipient)
            bccFieldText = ""
        }
    }

    /// Removes a recipient
    func removeRecipient(_ recipient: EmailParticipant, from field: RecipientField) {
        switch field {
        case .to:
            recipients.removeAll { $0.id == recipient.id }
        case .cc:
            ccRecipients.removeAll { $0.id == recipient.id }
        case .bcc:
            bccRecipients.removeAll { $0.id == recipient.id }
        }
    }

    /// Adds an attachment
    func addAttachment(_ attachment: EmailAttachment) {
        attachments.append(attachment)
    }

    /// Removes an attachment
    func removeAttachment(_ attachment: EmailAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    /// Clears all compose state
    func clear() {
        recipients.removeAll()
        ccRecipients.removeAll()
        bccRecipients.removeAll()
        toFieldText = ""
        ccFieldText = ""
        bccFieldText = ""
        subject = ""
        body = ""
        attachments.removeAll()
        currentDraftId = nil
    }

    // MARK: - Private Methods

    private func setupSpeechRecognition() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        audioEngine = AVAudioEngine()
    }

    private func setupAutoSave() {
        // Auto-save draft every 30 seconds when there's content
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.hasContent else { return }
                self.saveDraft()
            }
            .store(in: &cancellables)
    }

    private func startDictation() {
        guard let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable,
              let audioEngine = audioEngine else {
            return
        }

        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }

            Task { @MainActor in
                self?.performDictation()
            }
        }
    }

    private func performDictation() {
        guard let audioEngine = audioEngine else { return }

        // Stop any existing recognition task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        // Get audio input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                Task { @MainActor in
                    // Append transcribed text to body
                    let transcription = result.bestTranscription.formattedString
                    if !transcription.isEmpty {
                        self.body += (self.body.isEmpty ? "" : " ") + transcription
                    }
                }
            }

            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self.stopDictation()
                }
            }
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isRecording = true
            Haptics.medium()
        } catch {
            stopDictation()
        }
    }

    private func stopDictation() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRecording = false
        Haptics.light()
    }

    private func createDraftForSending() async throws -> EmailDraft {
        let draft = EmailDraft(
            id: currentDraftId ?? UUID().uuidString,
            accountId: "current-account",
            replyToMessageId: nil,
            replyToThreadId: nil,
            recipients: recipients,
            ccRecipients: ccRecipients,
            bccRecipients: bccRecipients,
            subject: subject,
            body: body,
            attachments: attachments,
            createdAt: Date(),
            updatedAt: Date(),
            isDraft: false
        )

        return try await emailAPI.createDraft(draft: draft)
    }

    // MARK: - Types

    enum RecipientField {
        case to
        case cc
        case bcc
    }
}

// MARK: - Recipient Autocomplete

extension ComposeViewModel {
    /// Searches for contacts matching a query
    func searchContacts(query: String) async -> [EmailParticipant] {
        guard query.count >= 2 else { return [] }

        // In production, this would search an actual contacts database
        // For now, return mock results

        let mockContacts = [
            EmailParticipant(id: "c1", email: "alice@example.com", name: "Alice Johnson", avatarURL: nil),
            EmailParticipant(id: "c2", email: "bob@example.com", name: "Bob Smith", avatarURL: nil),
            EmailParticipant(id: "c3", email: "carol@example.com", name: "Carol Williams", avatarURL: nil),
            EmailParticipant(id: "c4", email: "david@example.com", name: "David Brown", avatarURL: nil)
        ]

        let lowercaseQuery = query.lowercased()
        return mockContacts.filter {
            $0.email.lowercased().contains(lowercaseQuery) ||
            ($0.name?.lowercased().contains(lowercaseQuery) ?? false)
        }
    }
}
