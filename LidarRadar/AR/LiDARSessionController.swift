import ARKit
import Foundation
import os

/// 裝置有沒有光達深度。只問系統，不開相機，所以在同意之前也能安全呼叫。
enum LiDARCapability {
    static var sceneDepth: Bool {
        ARWorldTrackingConfiguration.isSupported
            && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    static var mesh: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    /// 這個 App 要的是深度圖，不是網格。有網格但沒有 sceneDepth 時無法算距離。
    static var canMeasure: Bool {
        sceneDepth
    }
}

/// 持有 ARSession，在背景佇列把每一幀的深度交給 Metal。
///
/// 主執行緒只收到算完的公尺數。不要在這裡保留 ARFrame，否則相機串流會卡住。
///
/// 別的 App 在前景時，ARKit 不能繼續。Apple 在 WWDC22 寫明 ARKit 不支援多工相機。
/// iPhone 上 `AVCaptureSession.isMultitaskingCameraAccessSupported` 只有兩種情況會是 true：
/// 把 voip 放進 UIBackgroundModes（這是通話 App 才合法），或持有 Apple 另外核准的
/// `com.apple.developer.avfoundation.multitasking-camera-access`（個人開發者帳號簽不了）。
/// 這裡不宣告 voip、也不把那個 entitlement 寫進簽名檔。預設仍用 ARKit。
/// `LIDAR_MULTITASKING_CAPTURE` 預設不編譯；打開且系統回報支援時，才改走檔案底部的 AVFoundation 光達。
/// 系統中斷時把 Live Activity 標成暫停，回到前景再 run。
final class LiDARSessionController: NSObject, ARSessionDelegate {
    var onSample: ((Double?) -> Void)?
    var onInterrupted: ((Bool) -> Void)?
    var onTrackingHint: ((String?) -> Void)?
    var onFailure: ((String, Bool) -> Void)?
    var onCameraDenied: (() -> Void)?

    private let session = ARSession()
    private let sessionQueue = DispatchQueue(label: "com.kwok.lidarradar.arsession", qos: .userInitiated)
    private let metalQueue = DispatchQueue(label: "com.kwok.lidarradar.metal", qos: .userInitiated)
    private let lowPower = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.kwok.lidarradar", category: "session")

    private var reducer: MetalDepthReducer?
#if LIDAR_MULTITASKING_CAPTURE
    private var depthCapture: LiDARDepthCapture?
#endif
    private var setupError: String?
    private let wantsRunning = OSAllocatedUnfairLock(initialState: false)
    /// 只有系統中斷或失敗之後才重新 run，避免每次回到前景都把追蹤重開一次。
    private var needsRestart = false
    private var metalBusy = false
    private var lastTimestamp: TimeInterval = 0
    private var restartCount = 0
    private var loggedFirstSample = false

    override init() {
        super.init()
        session.delegate = self
        session.delegateQueue = sessionQueue
        do {
            reducer = try MetalDepthReducer()
        } catch {
            setupError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func setLowPower(_ enabled: Bool) {
        lowPower.withLock { $0 = enabled }
    }

    func start() {
        wantsRunning.withLock { $0 = true }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.restartCount = 0
            self.needsRestart = false
            self.run()
        }
    }

    /// 從背景回到前景時呼叫。若系統沒有中斷過，就不要重跑，免得畫面閃一下又要重新對準。
    func resume() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
#if LIDAR_MULTITASKING_CAPTURE
            if self.depthCapture != nil {
                guard self.wantsRunning.withLock({ $0 }) else { return }
                self.depthCapture?.start()
                return
            }
#endif
            guard self.wantsRunning.withLock({ $0 }), self.needsRestart else { return }
            self.needsRestart = false
            self.run()
        }
    }

    func stop() {
        wantsRunning.withLock { $0 = false }
#if LIDAR_MULTITASKING_CAPTURE
        depthCapture?.stop()
#endif
        // 在 session 佇列上 pause，才不會和 run() 交錯又把相機打開。
        // 強引用 session，即使這個控制器已經被放掉，相機也會先停。
        let activeSession = self.session
        sessionQueue.async {
            activeSession.pause()
        }
    }

    private func run() {
        guard wantsRunning.withLock({ $0 }) else { return }
        if let setupError {
            publishFailure(setupError, canRetry: false)
            return
        }
        guard LiDARCapability.canMeasure else {
            publishFailure(L10n.failureNoLidar, canRetry: false)
            return
        }

#if LIDAR_MULTITASKING_CAPTURE
        // 只有編譯旗標打開、而且系統真的允許多工相機時才走 AVFoundation。
        // 旗標預設關閉。ARKit 在多工時不會出深度，所以不能拿它充數。
        if MultitaskingCamera.isSupported {
            startMultitaskingCapture()
            return
        }
#endif

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        configuration.planeDetection = []
        configuration.environmentTexturing = .none
        configuration.isLightEstimationEnabled = false
        configuration.isAutoFocusEnabled = true
        // 只開原始 sceneDepth。平滑深度比較慢，障礙警示要的是近的那一幀。
        configuration.frameSemantics.insert(.sceneDepth)

        guard wantsRunning.withLock({ $0 }) else { return }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        logger.info("ARSession 已啟動 sceneDepth")
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 優先用當幀深度。若這幀還沒準備好，平滑深度只在有開對應 semantic 時才會有值；
        // 我們沒開，所以這裡實質上只用 sceneDepth。
        guard let depthData = frame.sceneDepth ?? frame.smoothedSceneDepth else { return }
        consume(depthMap: depthData.depthMap, confidenceMap: depthData.confidenceMap, timestamp: frame.timestamp)
    }

    /// 必須在持有這張深度圖的那條呼叫裡同步複製。ARFrame 和 AVFoundation 的緩衝區都不能留到之後。
    private func consume(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer?, timestamp: TimeInterval) {
        let lowPowerOn = lowPower.withLock { $0 }
        let minInterval = lowPowerOn ? (1.0 / 15.0) : 0
        if minInterval > 0, lastTimestamp > 0, timestamp >= lastTimestamp, timestamp - lastTimestamp < minInterval {
            return
        }
        guard !metalBusy else { return }
        guard let reducer, reducer.ingest(depthMap: depthMap, confidenceMap: confidenceMap) else { return }

        lastTimestamp = timestamp
        metalBusy = true
        metalQueue.async { [weak self] in
            let meters = reducer.reduce()
            DispatchQueue.main.async {
                guard let self else { return }
                if let meters, !self.loggedFirstSample {
                    self.loggedFirstSample = true
                    self.logger.info("第一筆前方最近距離 \(meters, privacy: .public) 公尺")
                }
                self.onSample?(meters)
            }
            self?.sessionQueue.async {
                self?.metalBusy = false
                self?.restartCount = 0
            }
        }
    }

#if LIDAR_MULTITASKING_CAPTURE
    private func startMultitaskingCapture() {
        session.pause()
        let capture = depthCapture ?? LiDARDepthCapture(depthQueue: sessionQueue)
        depthCapture = capture
        // 深度回呼就在 sessionQueue 上，複製必須同步做完，不能再 async，否則緩衝區會被收回。
        capture.onDepth = { [weak self] depthMap in
            self?.consume(depthMap: depthMap, confidenceMap: nil, timestamp: CACurrentMediaTime())
        }
        capture.onInterrupted = { [weak self] interrupted in
            DispatchQueue.main.async {
                self?.onInterrupted?(interrupted)
            }
            guard !interrupted else { return }
            self?.sessionQueue.async {
                guard self?.wantsRunning.withLock({ $0 }) == true else { return }
                self?.depthCapture?.start()
            }
        }
        capture.onFailure = { [weak self] message in
            self?.publishFailure(message, canRetry: true)
        }
        capture.start()
        logger.info("改走 AVFoundation 光達。ARKit 多工時不會出深度。")
    }
#endif

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let hint = Self.hint(for: camera.trackingState)
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingHint?(hint)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        logger.error("ARSession 失敗：\(error.localizedDescription, privacy: .public)")
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            wantsRunning.withLock { $0 = false }
            DispatchQueue.main.async { [weak self] in
                self?.onCameraDenied?()
            }
            return
        }

        let message = Self.message(for: error)
        restartCount += 1
        needsRestart = true
        if restartCount <= 3, wantsRunning.withLock({ $0 }) {
            publishFailure("\(message) \(L10n.failureRetrying)", canRetry: true)
            sessionQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.run()
            }
        } else {
            publishFailure("\(message) \(L10n.failureGiveUp)", canRetry: true)
        }
    }

    /// 系統中斷（背景、鎖定、來電）時不要再呼叫 pause()，否則收不到恢復通知。
    func sessionWasInterrupted(_ session: ARSession) {
        logger.info("ARSession 被系統中斷")
        needsRestart = true
        DispatchQueue.main.async { [weak self] in
            self?.onInterrupted?(true)
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        logger.info("ARSession 中斷結束")
        DispatchQueue.main.async { [weak self] in
            self?.onInterrupted?(false)
        }
        // 不要在 delegate 回呼裡同步 run()，ARSession 可能會再進來這條佇列而卡住。
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.wantsRunning.withLock({ $0 }), self.needsRestart else { return }
            self.needsRestart = false
            self.run()
        }
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        // 我們只需要相機與深度，不需要把舊的世界座標接回去。
        false
    }

    private func publishFailure(_ message: String, canRetry: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.onFailure?(message, canRetry)
        }
    }

    private static func hint(for state: ARCamera.TrackingState) -> String? {
        switch state {
        case .normal, .notAvailable:
            return nil
        case .limited(let reason):
            switch reason {
            case .initializing:
                return L10n.hintInitializing
            case .excessiveMotion:
                return L10n.hintMotion
            case .insufficientFeatures:
                return L10n.hintFeatures
            case .relocalizing:
                return L10n.hintRelocalizing
            @unknown default:
                return L10n.hintLimited
            }
        @unknown default:
            return L10n.hintLimited
        }
    }

    private static func message(for error: Error) -> String {
        guard let arError = error as? ARError else {
            return L10n.failureGeneric
        }
        switch arError.code {
        case .cameraUnauthorized:
            return L10n.failureCamera
        case .unsupportedConfiguration:
            return L10n.failureUnsupported
        case .sensorUnavailable:
            return L10n.failureSensorUnavailable
        case .sensorFailed:
            return L10n.failureSensorFailed
        case .worldTrackingFailed:
            return L10n.failureWorldTracking
        default:
            return L10n.failureGeneric
        }
    }
}
