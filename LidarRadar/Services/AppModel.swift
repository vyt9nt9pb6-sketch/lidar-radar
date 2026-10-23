import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

/// 把同意、光達、警示、動態島和背景接在一起。畫面只跟這個物件說話。
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case needsConsent
        case checking
        case unsupported
        case needsCamera
        case monitoring
    }

    @Published var phase: Phase
    @Published var distanceMeters: Double?
    @Published var level: DangerLevel = .unknown
    @Published var isInterrupted = false
    @Published var isLowPower = false
    @Published var lowPowerReason = ""
    @Published var measuredFPS = 0
    @Published var trackingHint: String?
    @Published var failureMessage: String?
    @Published var liveAvailability: LiveActivityManager.Availability = .idle
    @Published var supportsSceneDepth = false
    @Published var supportsMesh = false
    @Published var showSettings = false

    let settings: SettingsStore
    let pictureInPicture = DistancePictureInPicture()
    /// 啟動時問一次。不開相機。真機上沒有特殊資格時是 false。
    let multitaskingCameraSupported = MultitaskingCamera.isSupported

    private let alerts = AlertEngine()
    private let live = LiveActivityManager()
    private let background = BackgroundKeeper()
    private var session: LiDARSessionController?
    private var stabilizer = DistanceStabilizer()
    private var cancellables = Set<AnyCancellable>()
    private var hardwareStarted = false
    private var askingCamera = false
    private var locationSchedule: Task<Void, Never>?
    private let launchHardware: Bool
    private var fpsWindowStart = Date()
    private var fpsCount = 0
    private var sceneIsActive = true
    /// 離開前景之後，只有比這個時間更晚的光達幀才算「還在量」。
    private var acceptDistanceAfter: Date?
    private var lastDepthAt: Date?
    private var backgroundWatch: Task<Void, Never>?

    init(launchHardware: Bool = true, settings: SettingsStore = SettingsStore()) {
        self.launchHardware = launchHardware
        self.settings = settings
        phase = settings.consentAccepted ? .checking : .needsConsent
        live.onAvailability = { [weak self] availability in
            Task { @MainActor in
                self?.liveAvailability = availability
            }
        }
        guard launchHardware else { return }
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyRuntimeSettings()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyRuntimeSettings() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyRuntimeSettings() }
            .store(in: &cancellables)
    }

    func onAppear() {
        guard launchHardware else { return }
        evaluateRoute()
    }

    func acceptConsent() {
        settings.acceptConsent()
        evaluateRoute()
    }

    func evaluateRoute() {
        guard launchHardware else { return }
        guard settings.consentAccepted else {
            phase = .needsConsent
            return
        }
        supportsSceneDepth = LiDARCapability.sceneDepth
        supportsMesh = LiDARCapability.mesh
        guard LiDARCapability.canMeasure else {
            phase = .unsupported
            if hardwareStarted {
                stopMonitoring(endLiveActivity: true)
            }
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            phase = .monitoring
            startMonitoringIfNeeded()
        case .notDetermined:
            guard !askingCamera else { return }
            askingCamera = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor in
                    self?.askingCamera = false
                    self?.evaluateRoute()
                }
            }
        case .denied, .restricted:
            phase = .needsCamera
            if hardwareStarted {
                stopMonitoring(endLiveActivity: true)
            }
        @unknown default:
            phase = .needsCamera
            if hardwareStarted {
                stopMonitoring(endLiveActivity: true)
            }
        }
    }

    func handle(scenePhase: ScenePhase) {
        guard launchHardware else { return }
        switch scenePhase {
        case .active:
            sceneIsActive = true
            acceptDistanceAfter = nil
            backgroundWatch?.cancel()
            background.endKeepAlive()
            if phase == .checking || phase == .needsCamera || phase == .unsupported || !settings.consentAccepted {
                evaluateRoute()
            } else if phase == .monitoring {
                isInterrupted = false
                UIApplication.shared.isIdleTimerDisabled = true
                alerts.resumeIfNeeded()
                session?.resume()
                alerts.setLevel(level)
                pictureInPicture.show(currentCard())
                publishLiveActivity(force: true)
            }
        case .inactive:
            // 控制中心也會進到這裡。先把子母畫面的圖改成暫停，避免把舊距離帶出去。
            // 不在這裡 startPictureInPicture，否則拉下通知中心也會浮出小窗。
            guard phase == .monitoring, settings.pictureInPictureEnabled else { return }
            acceptDistanceAfter = Date()
            pictureInPicture.show(.paused)
        case .background:
            guard phase == .monitoring else { return }
            sceneIsActive = false
            UIApplication.shared.isIdleTimerDisabled = false
            if settings.pictureInPictureEnabled {
                acceptDistanceAfter = acceptDistanceAfter ?? Date()
                if !captureIsLive {
                    alerts.stop()
                }
                pictureInPicture.show(currentCard())
                pictureInPicture.startIfNeeded()
                publishLiveActivity(force: true)
                background.beginKeepAlive()
                watchForStaleDepth()
            } else {
                isInterrupted = true
                alerts.deactivateAudio()
                background.beginKeepAlive()
                publishLiveActivity(force: true)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.background.endKeepAlive()
                }
            }
        @unknown default:
            break
        }
    }

    func retrySession() {
        failureMessage = nil
        stabilizer.reset()
        session?.start()
    }

    func restartLiveActivity() {
        Task { @MainActor in
            await live.endAll()
            live.beginSession()
            publishLiveActivity(force: true)
        }
    }

    func playPreviewAlert() {
        alerts.prepare()
        alerts.playPreview()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func revokeConsent() {
        showSettings = false
        stopMonitoring(endLiveActivity: false)
        Task { @MainActor in
            await live.endAll()
        }
        settings.resetAll()
        distanceMeters = nil
        level = .unknown
        isInterrupted = false
        failureMessage = nil
        trackingHint = nil
        measuredFPS = 0
        liveAvailability = .idle
        phase = .needsConsent
    }

    var liveActivityCaption: String {
        switch liveAvailability {
        case .idle:
            return L10n.activityIdle
        case .needsNewerOS:
            return L10n.activityNeedsOS
        case .turnedOff:
            return L10n.activityOff
        case .running:
            return L10n.activityRunning
        case .failed:
            return L10n.activityFailed
        }
    }

    var distanceLabel: String {
        guard let distanceMeters, distanceMeters.isFinite else { return "—" }
        return String(format: "%.1f", locale: .current, distanceMeters)
    }

    var accessibilityDistance: String {
        if isInterrupted {
            return L10n.a11yPaused
        }
        if distanceMeters != nil {
            return L10n.a11yDistance(distanceLabel, level.label)
        }
        return L10n.a11yReading
    }

    private func startMonitoringIfNeeded() {
        if !hardwareStarted {
            hardwareStarted = true
            let session = LiDARSessionController()
            session.onSample = { [weak self] sample in
                Task { @MainActor in
                    self?.ingest(sample)
                }
            }
            session.onInterrupted = { [weak self] interrupted in
                Task { @MainActor in
                    guard let self, self.phase == .monitoring else { return }
                    if interrupted {
                        self.isInterrupted = true
                        self.alerts.stop()
                        self.pictureInPicture.show(.paused)
                        self.publishLiveActivity(force: true)
                    }
                    // 恢復通知先不要把舊距離當成新的。等下一幀真的到了，ingest 才會解除暫停。
                }
            }
            session.onTrackingHint = { [weak self] hint in
                Task { @MainActor in
                    self?.trackingHint = hint
                }
            }
            session.onFailure = { [weak self] message, _ in
                Task { @MainActor in
                    self?.failureMessage = message
                }
            }
            session.onCameraDenied = { [weak self] in
                Task { @MainActor in
                    self?.phase = .needsCamera
                    self?.stopMonitoring(endLiveActivity: true)
                }
            }
            self.session = session
            alerts.prepare()
            live.beginSession()
            scheduleLocationRequest()
        }
        failureMessage = nil
        isInterrupted = false
        UIApplication.shared.isIdleTimerDisabled = true
        applyRuntimeSettings()
        session?.start()
        publishLiveActivity(force: true)
    }

    private func stopMonitoring(endLiveActivity: Bool) {
        hardwareStarted = false
        locationSchedule?.cancel()
        backgroundWatch?.cancel()
        session?.stop()
        session = nil
        pictureInPicture.setEnabled(false)
        alerts.deactivateAudio()
        background.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        stabilizer.reset()
        if endLiveActivity {
            Task { @MainActor in
                await live.endAll()
            }
        }
    }

    private func scheduleLocationRequest() {
        locationSchedule?.cancel()
        locationSchedule = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, phase == .monitoring else { return }
            background.requestAndStart()
        }
    }

    private func ingest(_ sample: Double?) {
        guard phase == .monitoring else { return }
        lastDepthAt = Date()
        // 在背景時，離開前景之前的距離不算。沒有新幀就保持暫停，不更新數字。
        if !sceneIsActive {
            guard settings.pictureInPictureEnabled, let after = acceptDistanceAfter, let last = lastDepthAt, last >= after else {
                return
            }
            if isInterrupted {
                isInterrupted = false
            }
        } else if isInterrupted {
            return
        }
        let stabilized = stabilizer.push(sample)
        if distanceMeters != stabilized.distance {
            distanceMeters = stabilized.distance
        }
        if level != stabilized.level {
            level = stabilized.level
        }
        if failureMessage != nil {
            failureMessage = nil
        }
        alerts.setLevel(level)
        noteFPS()
        pictureInPicture.show(currentCard())
        publishLiveActivity(force: false)
    }

    private func noteFPS() {
        fpsCount += 1
        let elapsed = Date().timeIntervalSince(fpsWindowStart)
        guard elapsed >= 1 else { return }
        measuredFPS = Int((Double(fpsCount) / elapsed).rounded())
        fpsCount = 0
        fpsWindowStart = Date()
    }

    private func applyRuntimeSettings() {
        let systemLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ProcessInfo.processInfo.thermalState
        let hot = thermal == .serious || thermal == .critical
        let enabled = settings.lowPower || systemLowPower || hot
        isLowPower = enabled
        if systemLowPower {
            lowPowerReason = L10n.powerSystem
        } else if hot {
            lowPowerReason = L10n.powerThermal
        } else if settings.lowPower {
            lowPowerReason = L10n.powerManual
        } else {
            lowPowerReason = ""
        }
        session?.setLowPower(enabled)
        guard phase == .monitoring else {
            pictureInPicture.setEnabled(false)
            return
        }
        let pipOn = settings.pictureInPictureEnabled
        alerts.apply(
            soundEnabled: settings.soundEnabled,
            hapticsEnabled: settings.hapticsEnabled,
            ignoresSilentSwitch: settings.ignoreSilentSwitch,
            playbackRequired: pipOn
        )
        pictureInPicture.setEnabled(pipOn)
        if pipOn {
            pictureInPicture.show(currentCard())
        }
    }

    /// 前景一律看 isInterrupted。背景必須有「離開之後才到」的新幀，而且不能太舊。
    private var captureIsLive: Bool {
        if sceneIsActive { return !isInterrupted }
        guard settings.pictureInPictureEnabled,
              let last = lastDepthAt,
              let after = acceptDistanceAfter,
              last >= after,
              Date().timeIntervalSince(last) < 0.8 else {
            return false
        }
        return !isInterrupted
    }

    private func currentCard() -> PiPCard {
        guard captureIsLive else { return .paused }
        return .live(distance: distanceLabel, emoji: level.emoji, level: level)
    }

    private func watchForStaleDepth() {
        backgroundWatch?.cancel()
        backgroundWatch = Task { @MainActor in
            var released = false
            while !Task.isCancelled, !self.sceneIsActive {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled, !self.sceneIsActive, self.phase == .monitoring else { return }
                let live = self.captureIsLive
                if self.isInterrupted == live {
                    self.isInterrupted = !live
                    if self.isInterrupted {
                        self.alerts.stop()
                    } else {
                        self.alerts.setLevel(self.level)
                    }
                    self.pictureInPicture.show(self.currentCard())
                    self.publishLiveActivity(force: true)
                } else if !live {
                    self.pictureInPicture.show(.paused)
                }
                if !released {
                    self.background.endKeepAlive()
                    released = true
                }
            }
        }
    }

    private func publishLiveActivity(force: Bool) {
        guard phase == .monitoring else { return }
        let paused = sceneIsActive ? isInterrupted : !captureIsLive
        let state = RadarAttributes.ContentState.make(
            distanceMeters: distanceMeters,
            level: level,
            isPaused: paused,
            isLowPower: isLowPower
        )
        live.publish(state, force: force)
    }

    static func preview(distance: Double?, level: DangerLevel, paused: Bool = false) -> AppModel {
        let model = AppModel(launchHardware: false, settings: SettingsStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
        model.phase = .monitoring
        model.distanceMeters = distance
        model.level = level
        model.isInterrupted = paused
        model.liveAvailability = .running
        model.measuredFPS = 30
        return model
    }
}
