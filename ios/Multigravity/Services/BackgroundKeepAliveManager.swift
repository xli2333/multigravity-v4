import AVFoundation
import Foundation
import UIKit

/// Maintains a non-intrusive background execution session using pure digital silence (`0.0` volume, zero-amplitude PCM)
/// with `AVAudioSession` `.playback` + `[.mixWithOthers]`.
///
/// Guarantees:
/// 1. Never interrupts, pauses, or ducks other apps (Douyin, Bilibili, Apple Music, NetEase Music, WeChat, games).
/// 2. Never registers `MPNowPlayingInfoCenter` or `MPRemoteCommandCenter` — completely invisible in Control Center,
///    Lock Screen media player, Dynamic Island media indicator, AirPods controls, and CarPlay.
/// 3. Automatically yields to phone calls / FaceTime / Siri / in-app voice recording or calls, and seamlessly resumes
///    silent keep-alive + WebSocket health check as soon as the interruption or recording ends.
@MainActor
public final class BackgroundKeepAliveManager: NSObject, AVAudioPlayerDelegate {
    public static let shared = BackgroundKeepAliveManager()

    public private(set) var isRunningKeepAlive: Bool = false

    /// Invoked after an audio interruption ends or upon background transition so WebSockets can immediately verify liveness.
    public var onWakeCheck: (() -> Void)?
    /// Invoked periodically (~20s) while keep-alive is active to guard against silent NAT / cellular handoff drops.
    public var onHeartbeatTick: (() -> Void)?

    private var audioPlayer: AVAudioPlayer?
    private var watchdogTimer: Timer?
    private var resumeRetryTask: Task<Void, Never>?
    private var isSystemInterrupted: Bool = false
    private var isDictatingActive: Bool = false
    private var isNarrationActive: Bool = false
    private var observersInstalled: Bool = false

    private static let silentWAVData: Data = buildSilentWAV(durationSeconds: 8, sampleRate: 8000)

    private override init() {
        super.init()
        installObserversIfNeeded()
    }

    public var shouldKeepAlive: Bool {
        let settings = AppSettings.shared
        return settings.isPaired
            && !settings.isDemoMode
            && settings.enableBackgroundKeepAlive
            && (settings.enablePushNotifications || settings.enableLiveActivities)
    }

    /// True when an interactive in-app audio feature (mic recording, dictation, live voice call, or TTS narration)
    /// owns `AVAudioSession` and must not have its category overwritten.
    public var isExclusiveInAppAudioActive: Bool {
        AudioRecorderManager.shared.isRecording
            || VoiceCallManager.shared.isInCall
            || isDictatingActive
            || isNarrationActive
    }

    public func setDictatingActive(_ active: Bool) {
        isDictatingActive = active
        if !active {
            restoreAfterExclusiveAudio()
        }
    }

    public func setNarrationActive(_ active: Bool) {
        isNarrationActive = active
        if !active {
            restoreAfterExclusiveAudio()
        }
    }

    /// Called when an in-app recorder, dictation, or voice call finishes.
    /// If background keep-alive is enabled, transitions smoothly back to `.playback` + `[.mixWithOthers]`
    /// instead of deactivating the session and allowing iOS to suspend the app.
    public func restoreAfterExclusiveAudio() {
        guard !isExclusiveInAppAudioActive else { return }
        if shouldKeepAlive {
            activateSilentLoop(forceReconfigureSession: true)
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public func refreshKeepAliveState() {
        installObserversIfNeeded()
        if shouldKeepAlive {
            startWatchdogIfNeeded()
            if !isExclusiveInAppAudioActive && !isSystemInterrupted {
                activateSilentLoop(forceReconfigureSession: false)
            }
        } else {
            stopKeepAlive()
        }
    }

    public func stopKeepAlive() {
        resumeRetryTask?.cancel()
        resumeRetryTask = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        isRunningKeepAlive = false
        if !isExclusiveInAppAudioActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func activateSilentLoop(forceReconfigureSession: Bool) {
        guard shouldKeepAlive, !isExclusiveInAppAudioActive, !isSystemInterrupted else { return }

        if !forceReconfigureSession, let player = audioPlayer, player.isPlaying {
            isRunningKeepAlive = true
            return
        }

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "MultigravityKeepAliveArm") {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        defer {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }

        let session = AVAudioSession.sharedInstance()
        do {
            if forceReconfigureSession
                || session.category != .playback
                || session.mode != .default
                || !session.categoryOptions.contains(.mixWithOthers)
                || session.categoryOptions.contains(.duckOthers) {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)

            let player: AVAudioPlayer
            if let existing = audioPlayer {
                player = existing
            } else {
                let created = try AVAudioPlayer(data: Self.silentWAVData, fileTypeHint: AVFileType.wav.rawValue)
                created.delegate = self
                created.numberOfLoops = -1
                created.volume = 0.0
                created.prepareToPlay()
                self.audioPlayer = created
                player = created
            }

            player.volume = 0.0
            player.numberOfLoops = -1
            if !player.isPlaying {
                _ = player.play()
            }
            isRunningKeepAlive = player.isPlaying
        } catch {
            isRunningKeepAlive = false
            print("[KeepAlive] Failed to activate silent audio session: \(error.localizedDescription)")
        }
    }

    private func startWatchdogIfNeeded() {
        guard watchdogTimer == nil else { return }
        let timer = Timer(timeInterval: 20.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.shouldKeepAlive else {
                    self.stopKeepAlive()
                    return
                }
                if !self.isExclusiveInAppAudioActive && !self.isSystemInterrupted {
                    if self.audioPlayer?.isPlaying != true {
                        self.activateSilentLoop(forceReconfigureSession: true)
                    } else {
                        self.isRunningKeepAlive = true
                    }
                }
                self.onHeartbeatTick?()
            }
        }
        timer.tolerance = 3.0
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func schedulePostInterruptionRecovery() {
        resumeRetryTask?.cancel()
        resumeRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.activateSilentLoop(forceReconfigureSession: true)
            self.onWakeCheck?()
            for delayNs: UInt64 in [800_000_000, 2_500_000_000] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard !Task.isCancelled, self.shouldKeepAlive else { return }
                if !self.isExclusiveInAppAudioActive && !self.isSystemInterrupted && self.audioPlayer?.isPlaying != true {
                    self.activateSilentLoop(forceReconfigureSession: true)
                }
                self.onWakeCheck?()
            }
        }
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true
        let nc = NotificationCenter.default

        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notif in
            let typeRaw = notif.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let typeRaw, let type = AVAudioSession.InterruptionType(rawValue: typeRaw) else { return }
                switch type {
                case .began:
                    self.isSystemInterrupted = true
                    self.isRunningKeepAlive = false
                case .ended:
                    self.isSystemInterrupted = false
                    if self.shouldKeepAlive {
                        self.schedulePostInterruptionRecovery()
                    }
                @unknown default:
                    self.isSystemInterrupted = false
                    if self.shouldKeepAlive {
                        self.schedulePostInterruptionRecovery()
                    }
                }
            }
        }

        nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSystemInterrupted = false
                self.audioPlayer = nil
                self.isRunningKeepAlive = false
                if self.shouldKeepAlive {
                    self.schedulePostInterruptionRecovery()
                }
            }
        }

        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let reasonRaw = notif.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                guard let self, self.shouldKeepAlive else { return }
                // Unplugging headphones or disconnecting AirPods pauses `.playback` players by default;
                // resume silent playback immediately so background keep-alive is never lost.
                if let reasonRaw, let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRaw),
                   reason == .oldDeviceUnavailable || reason == .categoryChange || reason == .override {
                    if !self.isExclusiveInAppAudioActive && !self.isSystemInterrupted {
                        self.activateSilentLoop(forceReconfigureSession: reason == .categoryChange)
                    }
                }
            }
        }

        nc.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.shouldKeepAlive else { return }
                self.startWatchdogIfNeeded()
                if !self.isExclusiveInAppAudioActive && !self.isSystemInterrupted {
                    self.activateSilentLoop(forceReconfigureSession: false)
                }
                self.onWakeCheck?()
            }
        }

        nc.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isSystemInterrupted = false
                self.refreshKeepAliveState()
                self.onWakeCheck?()
            }
        }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            BackgroundKeepAliveManager.shared.audioPlayer = nil
            BackgroundKeepAliveManager.shared.refreshKeepAliveState()
        }
    }

    /// Synthesizes a valid PCM16LE mono WAV containing pure digital zeros.
    nonisolated private static func buildSilentWAV(durationSeconds: Int, sampleRate: UInt32) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(numChannels) * bytesPerSample
        let blockAlign = numChannels * (bitsPerSample / 8)
        let numSamples = sampleRate * UInt32(max(1, durationSeconds))
        let dataSize = numSamples * UInt32(numChannels) * bytesPerSample
        let riffChunkSize = 36 + dataSize

        var wav = Data(capacity: Int(44 + dataSize))
        wav.append(contentsOf: "RIFF".utf8)
        appendLE(&wav, riffChunkSize)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        appendLE(&wav, UInt32(16))      // PCM fmt chunk size
        appendLE(&wav, UInt16(1))       // AudioFormat = 1 (PCM)
        appendLE(&wav, numChannels)
        appendLE(&wav, sampleRate)
        appendLE(&wav, byteRate)
        appendLE(&wav, blockAlign)
        appendLE(&wav, bitsPerSample)
        wav.append(contentsOf: "data".utf8)
        appendLE(&wav, dataSize)
        wav.append(Data(count: Int(dataSize)))
        return wav
    }

    nonisolated private static func appendLE<T: FixedWidthInteger>(_ data: inout Data, _ value: T) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}
