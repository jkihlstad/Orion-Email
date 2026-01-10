//
//  AudioSessionManager.swift
//  EmailApp
//
//  Shared audio session management for recording and playback
//

import Foundation
import AVFoundation
import Combine
import os.log

// MARK: - Logger

private let audioLogger = Logger(subsystem: "com.orion.emailapp", category: "AudioSession")

// MARK: - Audio Session Mode

/// Modes for audio session configuration
public enum AudioSessionMode: Equatable {
    case idle
    case recording
    case playback
    case playbackWithDucking
}

// MARK: - Audio Route

/// Audio output routes
public enum AudioRoute: Equatable {
    case speaker
    case receiver
    case headphones
    case bluetooth
    case carPlay
    case unknown

    init(from portType: AVAudioSession.Port) {
        switch portType {
        case .builtInSpeaker:
            self = .speaker
        case .builtInReceiver:
            self = .receiver
        case .headphones, .headsetMic:
            self = .headphones
        case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
            self = .bluetooth
        case .carAudio:
            self = .carPlay
        default:
            self = .unknown
        }
    }
}

// MARK: - Audio Session Error

/// Errors related to audio session management
public enum AudioSessionError: Error, LocalizedError {
    case configurationFailed(underlying: Error)
    case activationFailed(underlying: Error)
    case deactivationFailed(underlying: Error)
    case routeChangeFailed
    case interruptionHandlingFailed

    public var errorDescription: String? {
        switch self {
        case .configurationFailed(let error):
            return "Failed to configure audio session: \(error.localizedDescription)"
        case .activationFailed(let error):
            return "Failed to activate audio session: \(error.localizedDescription)"
        case .deactivationFailed(let error):
            return "Failed to deactivate audio session: \(error.localizedDescription)"
        case .routeChangeFailed:
            return "Failed to handle route change"
        case .interruptionHandlingFailed:
            return "Failed to handle audio interruption"
        }
    }
}

// MARK: - Audio Session Delegate

/// Delegate for audio session events
public protocol AudioSessionManagerDelegate: AnyObject {
    /// Called when an interruption begins (e.g., phone call)
    func audioSessionInterruptionBegan()

    /// Called when an interruption ends
    func audioSessionInterruptionEnded(shouldResume: Bool)

    /// Called when the audio route changes
    func audioSessionRouteChanged(newRoute: AudioRoute, reason: AVAudioSession.RouteChangeReason)

    /// Called when media services are reset
    func audioSessionMediaServicesWereReset()
}

// Default implementations
public extension AudioSessionManagerDelegate {
    func audioSessionInterruptionBegan() {}
    func audioSessionInterruptionEnded(shouldResume: Bool) {}
    func audioSessionRouteChanged(newRoute: AudioRoute, reason: AVAudioSession.RouteChangeReason) {}
    func audioSessionMediaServicesWereReset() {}
}

// MARK: - Audio Session Manager

/// Singleton manager for audio session configuration
public final class AudioSessionManager: @unchecked Sendable {
    // MARK: - Singleton

    public static let shared = AudioSessionManager()

    // MARK: - Properties

    private let audioSession = AVAudioSession.sharedInstance()
    private var currentMode: AudioSessionMode = .idle
    private var notificationObservers: [NSObjectProtocol] = []

    private weak var delegate: AudioSessionManagerDelegate?

    // Publishers
    private let routeChangeSubject = PassthroughSubject<(AudioRoute, AVAudioSession.RouteChangeReason), Never>()
    private let interruptionSubject = PassthroughSubject<(Bool, Bool), Never>() // (began, shouldResume)

    public var routeChangePublisher: AnyPublisher<(AudioRoute, AVAudioSession.RouteChangeReason), Never> {
        routeChangeSubject.eraseToAnyPublisher()
    }

    public var interruptionPublisher: AnyPublisher<(Bool, Bool), Never> {
        interruptionSubject.eraseToAnyPublisher()
    }

    // MARK: - Initialization

    private init() {
        setupNotifications()
    }

    deinit {
        removeNotifications()
    }

    // MARK: - Configuration

    /// Set the delegate for audio session events
    public func setDelegate(_ delegate: AudioSessionManagerDelegate?) {
        self.delegate = delegate
    }

    /// Configure audio session for recording
    public func configureForRecording() throws {
        guard currentMode != .recording else { return }

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try audioSession.setActive(true)
            currentMode = .recording

            audioLogger.info("Audio session configured for recording")
        } catch {
            audioLogger.error("Failed to configure for recording: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(underlying: error)
        }
    }

    /// Configure audio session for playback
    public func configureForPlayback(withDucking: Bool = true) throws {
        let targetMode: AudioSessionMode = withDucking ? .playbackWithDucking : .playback

        guard currentMode != targetMode else { return }

        do {
            var options: AVAudioSession.CategoryOptions = [.allowBluetooth]
            if withDucking {
                options.insert(.duckOthers)
            } else {
                options.insert(.mixWithOthers)
            }

            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: options
            )
            try audioSession.setActive(true)
            currentMode = targetMode

            audioLogger.info("Audio session configured for playback (ducking: \(withDucking))")
        } catch {
            audioLogger.error("Failed to configure for playback: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(underlying: error)
        }
    }

    /// Configure audio session for speech recognition
    public func configureForSpeechRecognition() throws {
        guard currentMode != .recording else { return }

        do {
            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers]
            )
            try audioSession.setActive(true)
            currentMode = .recording

            audioLogger.info("Audio session configured for speech recognition")
        } catch {
            audioLogger.error("Failed to configure for speech recognition: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(underlying: error)
        }
    }

    /// Deactivate audio session
    public func deactivate() throws {
        guard currentMode != .idle else { return }

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            currentMode = .idle

            audioLogger.info("Audio session deactivated")
        } catch {
            audioLogger.error("Failed to deactivate: \(error.localizedDescription)")
            throw AudioSessionError.deactivationFailed(underlying: error)
        }
    }

    // MARK: - Audio Settings

    /// Set preferred sample rate for recording
    public func setPreferredSampleRate(_ sampleRate: Double) throws {
        do {
            try audioSession.setPreferredSampleRate(sampleRate)
            audioLogger.debug("Set preferred sample rate: \(sampleRate)")
        } catch {
            audioLogger.error("Failed to set sample rate: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(underlying: error)
        }
    }

    /// Set preferred buffer duration
    public func setPreferredBufferDuration(_ duration: TimeInterval) throws {
        do {
            try audioSession.setPreferredIOBufferDuration(duration)
            audioLogger.debug("Set preferred buffer duration: \(duration)")
        } catch {
            audioLogger.error("Failed to set buffer duration: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(underlying: error)
        }
    }

    /// Get current input sample rate
    public var currentSampleRate: Double {
        audioSession.sampleRate
    }

    /// Get available inputs
    public var availableInputs: [AVAudioSessionPortDescription]? {
        audioSession.availableInputs
    }

    /// Get current route
    public var currentRoute: AudioRoute {
        guard let output = audioSession.currentRoute.outputs.first else {
            return .unknown
        }
        return AudioRoute(from: output.portType)
    }

    /// Check if headphones are connected
    public var isHeadphonesConnected: Bool {
        let outputs = audioSession.currentRoute.outputs
        return outputs.contains { output in
            output.portType == .headphones ||
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothHFP
        }
    }

    // MARK: - Permissions

    /// Request microphone permission
    public func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Check microphone permission status
    public var microphonePermissionStatus: AVAudioSession.RecordPermission {
        audioSession.recordPermission
    }

    /// Check if microphone permission is granted
    public var hasMicrophonePermission: Bool {
        audioSession.recordPermission == .granted
    }

    // MARK: - Notifications

    private func setupNotifications() {
        // Interruption notification
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        notificationObservers.append(interruptionObserver)

        // Route change notification
        let routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        notificationObservers.append(routeChangeObserver)

        // Media services reset notification
        let mediaResetObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
        notificationObservers.append(mediaResetObserver)
    }

    private func removeNotifications() {
        notificationObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            audioLogger.info("Audio interruption began")
            delegate?.audioSessionInterruptionBegan()
            interruptionSubject.send((true, false))

        case .ended:
            var shouldResume = false
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            }

            audioLogger.info("Audio interruption ended (shouldResume: \(shouldResume))")
            delegate?.audioSessionInterruptionEnded(shouldResume: shouldResume)
            interruptionSubject.send((false, shouldResume))

        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        let newRoute = currentRoute

        audioLogger.info("Audio route changed to \(String(describing: newRoute)) (reason: \(reasonValue))")
        delegate?.audioSessionRouteChanged(newRoute: newRoute, reason: reason)
        routeChangeSubject.send((newRoute, reason))
    }

    private func handleMediaServicesReset() {
        audioLogger.warning("Media services were reset")

        // Reset current mode
        currentMode = .idle

        delegate?.audioSessionMediaServicesWereReset()
    }
}

// MARK: - Audio Level Meter

/// Helper class for monitoring audio levels
public final class AudioLevelMeter: @unchecked Sendable {
    private var timer: Timer?
    private var levelProvider: (() -> Float)?

    private let levelSubject = PassthroughSubject<Float, Never>()

    public var levelPublisher: AnyPublisher<Float, Never> {
        levelSubject.eraseToAnyPublisher()
    }

    public init() {}

    /// Start monitoring levels
    public func startMonitoring(updateInterval: TimeInterval = 0.05, levelProvider: @escaping () -> Float) {
        self.levelProvider = levelProvider

        DispatchQueue.main.async { [weak self] in
            self?.timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
                guard let self = self, let provider = self.levelProvider else { return }
                let level = provider()
                self.levelSubject.send(level)
            }
        }
    }

    /// Stop monitoring levels
    public func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        levelProvider = nil
    }

    /// Convert decibel value to normalized level (0.0 - 1.0)
    public static func normalizedLevel(from decibels: Float, minDb: Float = -60, maxDb: Float = 0) -> Float {
        guard decibels.isFinite else { return 0 }

        let clampedDb = max(minDb, min(maxDb, decibels))
        let normalized = (clampedDb - minDb) / (maxDb - minDb)
        return normalized
    }
}
