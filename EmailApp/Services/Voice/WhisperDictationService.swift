//
//  WhisperDictationService.swift
//  EmailApp
//
//  Voice dictation using Whisper via server endpoint
//

import Foundation
import AVFoundation
import Combine
import os.log

// MARK: - Logger

private let dictationLogger = Logger(subsystem: "com.orion.emailapp", category: "Dictation")

// MARK: - Dictation Service Protocol

/// Protocol for voice dictation services
public protocol DictationServiceProtocol: AnyObject {
    /// Start recording audio for transcription
    func startRecording() async throws

    /// Stop recording and get transcript
    func stopRecording() async throws -> String

    /// Cancel recording without transcription
    func cancelRecording()

    /// Whether recording is currently in progress
    var isRecording: Bool { get }

    /// Current audio level (0.0 - 1.0) for visualization
    var audioLevel: Float { get }

    /// Publisher for recording state changes
    var isRecordingPublisher: AnyPublisher<Bool, Never> { get }

    /// Publisher for audio level updates
    var audioLevelPublisher: AnyPublisher<Float, Never> { get }
}

// MARK: - Whisper Dictation Service

/// Voice dictation service using Whisper via server proxy
@MainActor
public final class WhisperDictationService: ObservableObject, DictationServiceProtocol, @unchecked Sendable {
    // MARK: - Published Properties

    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var recordingDuration: TimeInterval = 0

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?

    private let apiClient: BrainAPIClient
    private let consentManager: ConsentManagerProtocol
    private let audioSessionManager: AudioSessionManager

    private var levelMeter: AudioLevelMeter?
    private var durationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let isRecordingSubject = CurrentValueSubject<Bool, Never>(false)
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0.0)

    // Audio configuration
    private let sampleRate: Double = 16000.0  // Whisper prefers 16kHz
    private let channels: AVAudioChannelCount = 1  // Mono

    // MARK: - Publishers

    public nonisolated var isRecordingPublisher: AnyPublisher<Bool, Never> {
        isRecordingSubject.eraseToAnyPublisher()
    }

    public nonisolated var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    public init(
        apiClient: BrainAPIClient,
        consentManager: ConsentManagerProtocol = ConsentManager.shared,
        audioSessionManager: AudioSessionManager = .shared
    ) {
        self.apiClient = apiClient
        self.consentManager = consentManager
        self.audioSessionManager = audioSessionManager

        setupBindings()
    }

    /// Convenience initializer
    public convenience init(
        authProvider: AuthSessionProviding,
        configuration: BrainAPIConfiguration = .default
    ) {
        let client = BrainAPIClient(configuration: configuration, authProvider: authProvider)
        self.init(apiClient: client)
    }

    deinit {
        cleanupRecording()
    }

    // MARK: - Setup

    private func setupBindings() {
        $isRecording
            .sink { [weak self] value in
                self?.isRecordingSubject.send(value)
            }
            .store(in: &cancellables)

        $audioLevel
            .sink { [weak self] value in
                self?.audioLevelSubject.send(value)
            }
            .store(in: &cancellables)
    }

    // MARK: - DictationServiceProtocol

    /// Start recording audio
    public nonisolated func startRecording() async throws {
        // Check consent
        let hasConsent = await consentManager.hasConsent(for: .audioCapture)
        guard hasConsent else {
            throw VoiceError.noConsent(.audioCapture)
        }

        // Check microphone permission
        let hasPermission = await audioSessionManager.requestMicrophonePermission()
        guard hasPermission else {
            throw VoiceError.microphonePermissionDenied
        }

        // Perform recording setup on main actor
        try await MainActor.run {
            try self.performStartRecording()
        }
    }

    private func performStartRecording() throws {
        guard !isRecording else {
            dictationLogger.warning("Already recording")
            return
        }

        // Configure audio session
        do {
            try audioSessionManager.configureForRecording()
            try audioSessionManager.setPreferredSampleRate(sampleRate)
        } catch {
            throw VoiceError.audioSessionError(underlying: error)
        }

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "dictation_\(UUID().uuidString).wav"
        tempFileURL = tempDir.appendingPathComponent(fileName)

        guard let fileURL = tempFileURL else {
            throw VoiceError.recordingFailed(reason: "Could not create temp file")
        }

        // Setup audio engine
        audioEngine = AVAudioEngine()

        guard let audioEngine = audioEngine else {
            throw VoiceError.recordingFailed(reason: "Could not create audio engine")
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create output format matching Whisper requirements
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw VoiceError.recordingFailed(reason: "Could not create audio format")
        }

        // Create audio file
        do {
            audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: outputFormat.settings
            )
        } catch {
            throw VoiceError.recordingFailed(reason: "Could not create audio file: \(error.localizedDescription)")
        }

        // Create format converter if needed
        var converter: AVAudioConverter?
        if inputFormat.sampleRate != sampleRate || inputFormat.channelCount != channels {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // Convert format if needed
            let bufferToWrite: AVAudioPCMBuffer
            if let converter = converter {
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / inputFormat.sampleRate)
                ) else {
                    return
                }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                guard status != .error, error == nil else {
                    return
                }

                bufferToWrite = convertedBuffer
            } else {
                bufferToWrite = buffer
            }

            // Write to file
            do {
                try self.audioFile?.write(from: bufferToWrite)
            } catch {
                dictationLogger.error("Failed to write audio: \(error.localizedDescription)")
            }

            // Calculate audio level
            self.updateAudioLevel(from: buffer)
        }

        // Start audio engine
        do {
            try audioEngine.start()
        } catch {
            cleanupRecording()
            throw VoiceError.recordingFailed(reason: "Could not start audio engine: \(error.localizedDescription)")
        }

        isRecording = true
        recordingDuration = 0

        // Start duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recordingDuration += 0.1
            }
        }

        dictationLogger.info("Recording started")
    }

    /// Stop recording and get transcript
    public nonisolated func stopRecording() async throws -> String {
        return try await MainActor.run {
            try self.performStopRecording()
        }
    }

    private func performStopRecording() throws -> String {
        guard isRecording else {
            throw VoiceError.recordingFailed(reason: "Not currently recording")
        }

        // Stop engine and cleanup
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        durationTimer?.invalidate()
        durationTimer = nil

        audioFile = nil  // Close file

        guard let fileURL = tempFileURL else {
            cleanupRecording()
            throw VoiceError.recordingFailed(reason: "No audio file available")
        }

        isRecording = false
        audioLevel = 0

        dictationLogger.info("Recording stopped, duration: \(self.recordingDuration)")

        // Return file URL for transcription
        // Note: The actual transcription happens asynchronously
        return fileURL.path
    }

    /// Transcribe the recorded audio
    public func transcribeRecording() async throws -> String {
        guard let fileURL = tempFileURL else {
            throw VoiceError.invalidAudioData
        }

        // Read audio file
        let audioData: Data
        do {
            audioData = try Data(contentsOf: fileURL)
        } catch {
            cleanupRecording()
            throw VoiceError.invalidAudioData
        }

        dictationLogger.info("Uploading \(audioData.count) bytes for transcription")

        // Upload to server for transcription
        do {
            let result = try await apiClient.uploadAudio(data: audioData, mimeType: "audio/wav")

            // Cleanup temp file
            cleanupRecording()

            dictationLogger.info("Transcription completed: \(result.text.prefix(50))...")
            return result.text

        } catch let error as BrainAPIError {
            cleanupRecording()
            throw mapBrainError(error)
        } catch {
            cleanupRecording()
            throw VoiceError.transcriptionFailed(reason: error.localizedDescription)
        }
    }

    /// Cancel recording without transcription
    public nonisolated func cancelRecording() {
        Task { @MainActor in
            self.performCancelRecording()
        }
    }

    private func performCancelRecording() {
        guard isRecording else { return }

        cleanupRecording()
        isRecording = false
        audioLevel = 0
        recordingDuration = 0

        dictationLogger.info("Recording cancelled")
    }

    // MARK: - Private Methods

    private func cleanupRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        audioFile = nil

        durationTimer?.invalidate()
        durationTimer = nil

        levelMeter?.stopMonitoring()
        levelMeter = nil

        // Delete temp file
        if let fileURL = tempFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        tempFileURL = nil

        // Deactivate audio session
        try? audioSessionManager.deactivate()
    }

    private func updateAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelDataValue[i]
            sum += sample * sample
        }

        let rms = sqrtf(sum / Float(frameLength))
        let avgPower = 20 * log10f(rms)

        let normalizedLevel = AudioLevelMeter.normalizedLevel(from: avgPower)

        Task { @MainActor in
            self.audioLevel = normalizedLevel
        }
    }

    private func mapBrainError(_ error: BrainAPIError) -> VoiceError {
        switch error {
        case .unauthorized:
            return .transcriptionFailed(reason: "Authentication required")
        case .serviceUnavailable:
            return .serviceUnavailable
        case .networkError(let underlying):
            return .transcriptionFailed(reason: "Network error: \(underlying.localizedDescription)")
        default:
            return .transcriptionFailed(reason: error.localizedDescription ?? "Unknown error")
        }
    }
}

// MARK: - Recording State

/// State of a recording session
public struct RecordingState: Equatable {
    public let isRecording: Bool
    public let duration: TimeInterval
    public let audioLevel: Float

    public init(isRecording: Bool = false, duration: TimeInterval = 0, audioLevel: Float = 0) {
        self.isRecording = isRecording
        self.duration = duration
        self.audioLevel = audioLevel
    }

    public var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Mock Implementation

#if DEBUG
/// Mock dictation service for testing and previews
@MainActor
public final class MockDictationService: ObservableObject, DictationServiceProtocol, @unchecked Sendable {
    @Published public var isRecording: Bool = false
    @Published public var audioLevel: Float = 0.0

    private let isRecordingSubject = CurrentValueSubject<Bool, Never>(false)
    private let audioLevelSubject = CurrentValueSubject<Float, Never>(0.0)

    public var mockTranscript = "This is a mock transcription of your voice recording."
    public var shouldFail = false
    public var simulateDelay: TimeInterval = 1.0

    public nonisolated var isRecordingPublisher: AnyPublisher<Bool, Never> {
        isRecordingSubject.eraseToAnyPublisher()
    }

    public nonisolated var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    public init() {}

    public nonisolated func startRecording() async throws {
        if await MainActor.run(body: { self.shouldFail }) {
            throw VoiceError.microphonePermissionDenied
        }

        await MainActor.run {
            self.isRecording = true
            self.isRecordingSubject.send(true)
        }

        // Simulate audio level changes
        Task { @MainActor in
            while self.isRecording {
                self.audioLevel = Float.random(in: 0.1...0.8)
                self.audioLevelSubject.send(self.audioLevel)
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    public nonisolated func stopRecording() async throws -> String {
        let delay = await MainActor.run { self.simulateDelay }
        let transcript = await MainActor.run { self.mockTranscript }

        await MainActor.run {
            self.isRecording = false
            self.audioLevel = 0
            self.isRecordingSubject.send(false)
            self.audioLevelSubject.send(0)
        }

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        return transcript
    }

    public nonisolated func cancelRecording() {
        Task { @MainActor in
            self.isRecording = false
            self.audioLevel = 0
            self.isRecordingSubject.send(false)
            self.audioLevelSubject.send(0)
        }
    }
}
#endif
