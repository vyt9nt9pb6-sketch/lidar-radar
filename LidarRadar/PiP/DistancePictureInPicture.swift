import AVFoundation
import AVKit
import CoreMedia
import SwiftUI
import UIKit

/// 實驗用子母畫面。內容是一張距離卡片，不是相機預覽。
///
/// `canStartPictureInPictureAutomaticallyFromInline` 在圖層已經在畫面上、而且系統認為播得起來時設成 true。
/// 切到別的 App 時，系統會把這張卡片帶成浮動小窗。進到背景後若系統沒自動啟動，再呼叫一次 start。
///
/// 小窗顯示什麼由外面傳入的 PiPCard 決定。沒有新的光達幀時必須傳 `.paused`，這裡不會自己沿用上一張距離。
@MainActor
final class DistancePictureInPicture: NSObject, ObservableObject {
    let displayLayer = AVSampleBufferDisplayLayer()
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false

    private let renderer = DistanceCardRenderer()
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var timebase: CMTimebase?
    private var card: PiPCard = .paused
    private var enabled = false
    private var playing = true

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1).cgColor
        var clock: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: kCFAllocatorDefault,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &clock
        )
        if let clock {
            timebase = clock
            displayLayer.controlTimebase = clock
            CMTimebaseSetTime(clock, time: .zero)
            CMTimebaseSetRate(clock, rate: 1)
        }
    }

    var statusText: String {
        guard enabled else { return "" }
        if isActive {
            return L10n.pipActive
        }
        return isPossible ? L10n.pipPossible : L10n.pipNotPossible
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else {
            if on { enqueue() }
            return
        }
        enabled = on
        if on {
            startInline()
        } else {
            timer?.invalidate()
            timer = nil
            controller?.canStartPictureInPictureAutomaticallyFromInline = false
            if controller?.isPictureInPictureActive == true {
                controller?.stopPictureInPicture()
            }
            isPossible = false
            isActive = false
        }
    }

    /// 立刻換成這一張。暫停卡不會留著舊距離，因為整張圖重畫。
    func show(_ card: PiPCard) {
        self.card = card
        guard enabled else { return }
        enqueue()
    }

    /// 背景時若自動啟動沒發生，再試一次。已經在小窗裡就什麼都不做。
    func startIfNeeded() {
        guard enabled, let controller else { return }
        guard controller.isPictureInPicturePossible, !controller.isPictureInPictureActive else { return }
        controller.startPictureInPicture()
    }

    private func startInline() {
        enqueue()
        if controller == nil {
            let source = AVPictureInPictureController.ContentSource(
                sampleBufferDisplayLayer: displayLayer,
                playbackDelegate: self
            )
            let controller = AVPictureInPictureController(contentSource: source)
            controller.delegate = self
            controller.requiresLinearPlayback = true
            self.controller = controller
            possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
                let possible = controller.isPictureInPicturePossible
                Task { @MainActor in
                    guard let self else { return }
                    self.isPossible = possible
                    controller.canStartPictureInPictureAutomaticallyFromInline = self.enabled && possible
                }
            }
        }
        controller?.canStartPictureInPictureAutomaticallyFromInline = enabled
        if timer == nil {
            let timer = Timer(timeInterval: 1.0 / 8.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.enqueue()
                }
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func enqueue() {
        guard enabled, playing else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        let time = CMClockGetTime(CMClockGetHostTimeClock())
        guard let sample = renderer.makeSample(for: card, presentationTime: time) else { return }
        displayLayer.enqueue(sample)
    }
}

extension DistancePictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isActive = false
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            self.isActive = false
            self.isPossible = pictureInPictureController.isPictureInPicturePossible
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

extension DistancePictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        // 使用者按暫停時仍繼續送卡片。否則小窗會凍在最後一張距離，看起來像還在量。
        Task { @MainActor in
            self.playing = true
            if let timebase = self.timebase {
                CMTimebaseSetRate(timebase, rate: 1)
            }
            self.enqueue()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: CMTime(value: 24 * 60 * 60, timescale: 1))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        // 不要讓子母畫面把我們的提示音工作階段關掉。真正有沒有新距離，由外面決定要不要響。
        false
    }
}

struct PictureInPictureInlineView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> PiPContainerView {
        let view = PiPContainerView()
        view.install(layer)
        return view
    }

    func updateUIView(_ uiView: PiPContainerView, context: Context) {
        uiView.install(layer)
    }
}

final class PiPContainerView: UIView {
    func install(_ sampleLayer: AVSampleBufferDisplayLayer) {
        if sampleLayer.superlayer !== layer {
            sampleLayer.removeFromSuperlayer()
            layer.addSublayer(sampleLayer)
        }
        sampleLayer.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.forEach { $0.frame = bounds }
    }
}
