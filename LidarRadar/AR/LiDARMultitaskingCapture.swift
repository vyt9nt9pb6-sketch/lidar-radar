import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import os

/// 預設不編譯。免費 Apple ID 簽不了多工相機 entitlement，編譯進來也無法在背景拿到深度。
///
/// 若 Apple 已核准 `com.apple.developer.avfoundation.multitasking-camera-access`：
/// 1. 把它加進 LidarRadar.entitlements（值為 true）。
/// 2. 在 LidarRadar target 的 Swift Active Compilation Conditions 加上 LIDAR_MULTITASKING_CAPTURE。
/// 3. 不要同時加 voip。那個背景模式是給網路電話的。
///
/// 這條路徑用 `builtInLiDARDepthCamera`，不是 ARKit。ARKit 在多工時仍然不會出深度。
/// `isMultitaskingCameraAccessSupported` 為 false 時，呼叫端應繼續用 ARKit，不要啟動這裡。
#if LIDAR_MULTITASKING_CAPTURE

final class LiDARDepthCapture: NSObject, AVCaptureDepthDataOutputDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onDepth: ((CVPixelBuffer) -> Void)?
    var onInterrupted: ((Bool) -> Void)?
    var onFailure: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let videoSink = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private let depthQueue: DispatchQueue
    private let logger = Logger(subsystem: "com.kwok.lidarradar", category: "avdepth")
    private var observers: [NSObjectProtocol] = []

    init(depthQueue: DispatchQueue) {
        self.depthQueue = depthQueue
        super.init()
    }

    func start() {
        if observers.isEmpty {
            observeInterruptions()
        }
        guard !session.isRunning else { return }
        do {
            try configure()
        } catch {
            onFailure?(error.localizedDescription)
            return
        }
        session.startRunning()
        if session.isRunning {
            let enabled = session.isMultitaskingCameraAccessEnabled
            logger.info("AVFoundation 光達已啟動，多工相機 \(enabled, privacy: .public)")
        } else {
            onFailure?(L10n.failureGeneric)
        }
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority

        for input in session.inputs {
            session.removeInput(input)
        }
        for output in session.outputs {
            session.removeOutput(output)
        }

        guard let device = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) else {
            throw Failure(L10n.failureNoLidar)
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw Failure(L10n.failureUnsupported)
        }
        session.addInput(input)

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if let format = Self.preferredFormat(device) {
            device.activeFormat = format
            if let depth = format.supportedDepthDataFormats.first(where: {
                CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat32
            }) ?? format.supportedDepthDataFormats.first {
                device.activeDepthDataFormat = depth
            }
        }
        let frame = CMTime(value: 1, timescale: 30)
        device.activeVideoMinFrameDuration = frame
        device.activeVideoMaxFrameDuration = frame

        videoSink.alwaysDiscardsLateVideoFrames = true
        videoSink.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.kwok.lidarradar.avvideo"))
        guard session.canAddOutput(videoSink) else {
            throw Failure(L10n.failureUnsupported)
        }
        session.addOutput(videoSink)

        depthOutput.isFilteringEnabled = false
        depthOutput.alwaysDiscardsLateDepthData = true
        depthOutput.setDelegate(self, callbackQueue: depthQueue)
        guard session.canAddOutput(depthOutput) else {
            throw Failure(L10n.failureUnsupported)
        }
        session.addOutput(depthOutput)

        if #available(iOS 16.0, *), session.isMultitaskingCameraAccessSupported {
            session.isMultitaskingCameraAccessEnabled = true
        }
    }

    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        let depth: AVDepthData
        if depthData.depthDataType == kCVPixelFormatType_DepthFloat32 {
            depth = depthData
        } else {
            depth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        }
        onDepth?(depth.depthDataMap)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 彩色幀丟掉。光達裝置需要同時掛影像輸出，深度才會穩定送出。
    }

    private func observeInterruptions() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .AVCaptureSessionWasInterrupted,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.onInterrupted?(true)
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionInterruptionEnded,
            object: session,
            queue: .main
        ) { [weak self] _ in
            // 要不要重開由 LiDARSessionController 看 wantsRunning 決定，避免使用者已停止卻又把相機打開。
            self?.onInterrupted?(false)
        })
        observers.append(center.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: session,
            queue: .main
        ) { [weak self] note in
            let message = (note.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription
            self?.onFailure?(message ?? L10n.failureGeneric)
        })
    }

    private static func preferredFormat(_ device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats.filter { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return size.width > 0 && size.width <= 1280 && !format.supportedDepthDataFormats.isEmpty
        }.min { lhs, rhs in
            let left = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let right = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            return left.width * left.height < right.width * right.height
        }
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

#endif
