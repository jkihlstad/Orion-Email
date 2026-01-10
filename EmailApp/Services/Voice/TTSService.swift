//
//  TTSService.swift
//  EmailApp
//
//  Text-to-Speech service using OpenAI TTS via server endpoint
//

import Foundation
import AVFoundation
import Combine
import os.log

// MARK: - Logger

private let ttsLogger = Logger(subsystem: "com.orion.emailapp", category: "TTS")

// MARK: - TTS Service Protocol

/// Protocol for text-to-speech services
public protocol TTSServiceProtocol: AnyObject {
    /// Speak the given text
    func speak(text: String) async throws

    /// Speak text with specific voice
    func speak(text: String, voice: VoiceType) async throws

    /// Stop current speech
    func stop()

    /// Pause current speech
    func pause()

    /// Resume paused speech
    func resume()

    /// Whether speech is currently playing
    var isSpeaking: Bool { get }

    /// Whether speech is paused
    var isPaused: Bool { get }

    /// Current playback progress (0.0 - 1.0)
    var currentProgress: Float { get }

    /// Publisher for speaking state changes
    var isSpeakingPublisher: AnyPublisher<Bool, Never> { get }

    /// Publisher for progress updates
    var progressPublisher: AnyPublisher<Float, Never> { get }
}

// MARK: - TTS Playback State

/// State of TTS playback
public enum TTSPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case finished
    case error(String)

    public var isActive: Bool {
        switch self {
        case .loading, .playing, .paused:
            return true
        default:
            return false
        }
    }
}

// MARK: - TTS Service

/// Text-to-Speech service using OpenAI TTS via server
@MainActor
public final class TTSService: NSObject, ObservableObject, TTSServiceProtocol, @unchecked Sendable {
    // MARK: - Published Properties

    @Published public private(set) var isSpeaking: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var currentProgress: Float = 0.0
    @Published public private(set) var playbackState: TTSPlaybackState = .idle

    // MARK: - Public Properties

    @Published public var selectedVoice: VoiceType = .alloy
    @Published public var playbackSpeed: Float = 1.0

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var progressTimer: Timer?

    private let apiClient: BrainAPIClient
    private let consentManager: ConsentManagerProtocol
    private let audioSessionManager: AudioSessionManager

    private var cancellables = Set<AnyCancellable>()

    private let isSpeakingSubject = CurrentValueSubject<Bool, Never>(false)
    private let progressSubject = CurrentValueSubject<Float, Never>(0.0)

    // Audio cache
    private var audioCache: [String: Data] = [:]
    private let maxCacheSize = 10

    // MARK: - Publishers

    public nonisolated var isSpeakingPublisher: AnyPublisher<Bool, Never> {
        isSpeakingSubject.eraseToAnyPublisher()
    }

    public nonisolated var progressPublisher: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
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

        super.init()
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
        stop()
    }

    // MARK: - Setup

    private func setupBindings() {
        $isSpeaking
            .sink { [weak self] value in
                self?.isSpeakingSubject.send(value)
            }
            .store(in: &cancellables)

        $currentProgress
            .sink { [weak self] value in
                self?.progressSubject.send(value)
            }
            .store(in: &cancellables)
    }

    // MARK: - TTSServiceProtocol

    /// Speak the given text using selected voice
    public nonisolated func speak(text: String) async throws {
        let voice = await MainActor.run { self.selectedVoice }
        try await speak(text: text, voice: voice)
    }

    /// Speak text with specific voice
    public nonisolated func speak(text: String, voice: VoiceType) async throws {
        // Check consent
        let hasConsent = await consentManager.hasConsent(for: .voiceSynthesis)
        guard hasConsent else {
            throw VoiceError.noConsent(.voiceSynthesis)
        }

        // Validate text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VoiceError.playbackFailed(reason: "No text to speak")
        }

        try await MainActor.run {
            try self.performSpeak(text: text, voice: voice)
        }
    }

    private func performSpeak(text: String, voice: VoiceType) throws {
        // Stop any current playback
        stop()

        // Update state
        playbackState = .loading
        isSpeaking = false
        isPaused = false
        currentProgress = 0

        // Check cache
        let cacheKey = "\(voice.rawValue)_\(text.hashValue)"
        if let cachedAudio = audioCache[cacheKey] {
            ttsLogger.debug("Using cached audio")
            try playAudioData(cachedAudio)
            return
        }

        // Fetch audio from server asynchronously
        Task { [weak self] in
            guard let self = self else { return }

            do {
                let speed = await MainActor.run { self.playbackSpeed }
                let audioData = try await self.apiClient.getTTSAudio(text: text, voice: voice, speed: speed)

                await MainActor.run {
                    // Cache the audio
                    self.cacheAudio(audioData, forKey: cacheKey)

                    do {
                        try self.playAudioData(audioData)
                    } catch {
                        self.playbackState = .error(error.localizedDescription)
                        ttsLogger.error("Playback failed: \(error.localizedDescription)")
                    }
                }

            } catch let error as BrainAPIError {
                await MainActor.run {
                    self.playbackState = .error(error.localizedDescription ?? "TTS failed")
                }
                ttsLogger.error("TTS API error: \(error.localizedDescription ?? "unknown")")

            } catch {
                await MainActor.run {
                    self.playbackState = .error(error.localizedDescription)
                }
                ttsLogger.error("TTS error: \(error.localizedDescription)")
            }
        }
    }

    private func playAudioData(_ data: Data) throws {
        // Configure audio session for playback with ducking
        do {
            try audioSessionManager.configureForPlayback(withDucking: true)
        } catch {
            throw VoiceError.audioSessionError(underlying: error)
        }

        // Create player
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackSpeed
            audioPlayer?.prepareToPlay()
        } catch {
            throw VoiceError.playbackFailed(reason: "Could not create audio player: \(error.localizedDescription)")
        }

        // Start playback
        guard audioPlayer?.play() == true else {
            throw VoiceError.playbackFailed(reason: "Could not start playback")
        }

        isSpeaking = true
        playbackState = .playing
        startProgressTimer()

        ttsLogger.info("Started TTS playback")
    }

    /// Stop current speech
    public nonisolated func stop() {
        Task { @MainActor in
            self.performStop()
        }
    }

    private func performStop() {
        audioPlayer?.stop()
        audioPlayer = nil

        stopProgressTimer()

        isSpeaking = false
        isPaused = false
        currentProgress = 0
        playbackState = .idle

        // Deactivate audio session
        try? audioSessionManager.deactivate()

        ttsLogger.debug("Stopped TTS playback")
    }

    /// Pause current speech
    public nonisolated func pause() {
        Task { @MainActor in
            self.performPause()
        }
    }

    private func performPause() {
        guard isSpeaking, !isPaused else { return }

        audioPlayer?.pause()
        isPaused = true
        playbackState = .paused
        stopProgressTimer()

        ttsLogger.debug("Paused TTS playback")
    }

    /// Resume paused speech
    public nonisolated func resume() {
        Task { @MainActor in
            self.performResume()
        }
    }

    private func performResume() {
        guard isPaused else { return }

        audioPlayer?.play()
        isPaused = false
        playbackState = .playing
        startProgressTimer()

        ttsLogger.debug("Resumed TTS playback")
    }

    // MARK: - Progress Tracking

    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player = audioPlayer, player.duration > 0 else { return }
        currentProgress = Float(player.currentTime / player.duration)
    }

    // MARK: - Caching

    private func cacheAudio(_ data: Data, forKey key: String) {
        // Remove oldest if at capacity
        if audioCache.count >= maxCacheSize {
            if let firstKey = audioCache.keys.first {
                audioCache.removeValue(forKey: firstKey)
            }
        }
        audioCache[key] = data
    }

    /// Clear the audio cache
    public func clearCache() {
        audioCache.removeAll()
        ttsLogger.debug("Cleared audio cache")
    }

    // MARK: - Voice Selection

    /// Get available voices
    public var availableVoices: [VoiceType] {
        VoiceType.allCases
    }

    /// Set playback speed (0.25 to 4.0)
    public func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = max(0.25, min(4.0, speed))
        audioPlayer?.rate = playbackSpeed
    }
}

// MARK: - AVAudioPlayerDelegate

extension TTSService: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopProgressTimer()
            self.isSpeaking = false
            self.isPaused = false
            self.currentProgress = flag ? 1.0 : 0.0
            self.playbackState = .finished

            // Deactivate audio session
            try? self.audioSessionManager.deactivate()

            ttsLogger.info("TTS playback finished (success: \(flag))")
        }
    }

    public nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.stopProgressTimer()
            self.isSpeaking = false
            self.isPaused = false
            self.playbackState = .error(error?.localizedDescription ?? "Decode error")

            try? self.audioSessionManager.deactivate()

            ttsLogger.error("TTS decode error: \(error?.localizedDescription ?? "unknown")")
        }
    }
}

// MARK: - Text Chunking Helper

/// Helper for chunking long text for TTS
public struct TTSTextChunker {
    /// Maximum characters per chunk (OpenAI TTS limit is 4096)
    public static let maxChunkSize = 4000

    /// Split text into chunks suitable for TTS
    public static func chunk(_ text: String) -> [String] {
        guard text.count > maxChunkSize else {
            return [text]
        }

        var chunks: [String] = []
        var currentChunk = ""

        // Split by sentences
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))

        for sentence in sentences {
            let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSentence.isEmpty else { continue }

            let sentenceWithPunctuation = trimmedSentence + ". "

            if currentChunk.count + sentenceWithPunctuation.count > maxChunkSize {
                if !currentChunk.isEmpty {
                    chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
                }
                currentChunk = sentenceWithPunctuation
            } else {
                currentChunk += sentenceWithPunctuation
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk.trimmingCharacters(in: .whitespaces))
        }

        return chunks
    }
}

// MARK: - Mock Implementation

#if DEBUG
/// Mock TTS service for testing and previews
@MainActor
public final class MockTTSService: ObservableObject, TTSServiceProtocol, @unchecked Sendable {
    @Published public var isSpeaking: Bool = false
    @Published public var isPaused: Bool = false
    @Published public var currentProgress: Float = 0.0

    private let isSpeakingSubject = CurrentValueSubject<Bool, Never>(false)
    private let progressSubject = CurrentValueSubject<Float, Never>(0.0)

    public var shouldFail = false
    public var simulateDuration: TimeInterval = 3.0

    private var progressTask: Task<Void, Never>?

    public nonisolated var isSpeakingPublisher: AnyPublisher<Bool, Never> {
        isSpeakingSubject.eraseToAnyPublisher()
    }

    public nonisolated var progressPublisher: AnyPublisher<Float, Never> {
        progressSubject.eraseToAnyPublisher()
    }

    public init() {}

    public nonisolated func speak(text: String) async throws {
        try await speak(text: text, voice: .alloy)
    }

    public nonisolated func speak(text: String, voice: VoiceType) async throws {
        let shouldFail = await MainActor.run { self.shouldFail }
        if shouldFail {
            throw VoiceError.serviceUnavailable
        }

        await MainActor.run {
            self.isSpeaking = true
            self.isPaused = false
            self.currentProgress = 0
            self.isSpeakingSubject.send(true)
        }

        let duration = await MainActor.run { self.simulateDuration }

        // Simulate progress
        progressTask = Task { @MainActor in
            let steps = 30
            for i in 0...steps {
                guard !Task.isCancelled, self.isSpeaking, !self.isPaused else { break }
                self.currentProgress = Float(i) / Float(steps)
                self.progressSubject.send(self.currentProgress)
                try? await Task.sleep(nanoseconds: UInt64((duration / Double(steps)) * 1_000_000_000))
            }

            if !Task.isCancelled {
                self.isSpeaking = false
                self.isSpeakingSubject.send(false)
            }
        }
    }

    public nonisolated func stop() {
        Task { @MainActor in
            self.progressTask?.cancel()
            self.isSpeaking = false
            self.isPaused = false
            self.currentProgress = 0
            self.isSpeakingSubject.send(false)
            self.progressSubject.send(0)
        }
    }

    public nonisolated func pause() {
        Task { @MainActor in
            self.isPaused = true
        }
    }

    public nonisolated func resume() {
        Task { @MainActor in
            self.isPaused = false
        }
    }
}
#endif
