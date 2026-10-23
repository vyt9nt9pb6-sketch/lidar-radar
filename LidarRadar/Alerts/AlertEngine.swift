import AudioToolbox
import AVFoundation
import CoreHaptics
import Foundation
import os
import UIKit

/// 依危險等級同時發出震動與聲音。兩者都是「叫了就返回」，所以是並行的。
///
/// 安全與讀取中不發聲。等級沒變時，用該等級的間隔重複，直到離開該等級。
@MainActor
final class AlertEngine {
    private let logger = Logger(subsystem: "com.kwok.lidarradar", category: "alert")
    private var engine: CHHapticEngine?
    private var hapticsReady = false
    private let warningImpact = UIImpactFeedbackGenerator(style: .medium)
    private let dangerImpact = UIImpactFeedbackGenerator(style: .heavy)
    private var warningPlayer: AVAudioPlayer?
    private var dangerPlayer: AVAudioPlayer?
    private var timer: Timer?
    private var currentLevel: DangerLevel = .unknown
    private var audioReady = false

    var soundEnabled = true
    var hapticsEnabled = true
    var ignoresSilentSwitch = true
    /// 子母畫面需要 playback 工作階段，否則系統不會讓小窗啟動。
    private var playbackRequired = false

    func prepare() {
        prepareHaptics()
        preparePlayers()
        configureAudioSession()
    }

    /// 從背景回來時補上被關掉的聲音與觸覺。已經在跑就不要重開，避免通知中心劃下來又把引擎重啟。
    func resumeIfNeeded() {
        if !hapticsReady {
            prepareHaptics()
        }
        if warningPlayer == nil || dangerPlayer == nil {
            preparePlayers()
        }
        if !audioReady {
            configureAudioSession()
        }
    }

    func apply(soundEnabled: Bool, hapticsEnabled: Bool, ignoresSilentSwitch: Bool, playbackRequired: Bool = false) {
        let silentChanged = self.ignoresSilentSwitch != ignoresSilentSwitch || self.playbackRequired != playbackRequired
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.ignoresSilentSwitch = ignoresSilentSwitch
        self.playbackRequired = playbackRequired
        if silentChanged {
            audioReady = false
            configureAudioSession()
        }
        if !soundEnabled && !hapticsEnabled {
            stop()
        }
    }

    func setLevel(_ level: DangerLevel) {
        guard level != currentLevel else { return }
        currentLevel = level
        timer?.invalidate()
        timer = nil
        guard level.triggersAlert else { return }
        if level == .warning {
            warningImpact.prepare()
        } else {
            dangerImpact.prepare()
        }
        playBurst(for: level)
        let interval = level.repeatInterval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playBurst(for: level)
            }
        }
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        currentLevel = .unknown
        timer?.invalidate()
        timer = nil
        engine?.stop(completionHandler: nil)
    }

    func deactivateAudio() {
        stop()
        guard audioReady else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        audioReady = false
    }

    /// 設定頁用來確認手機有沒有震、有沒有出聲。
    func playPreview() {
        prepare()
        playBurst(for: .danger)
    }

    private func playBurst(for level: DangerLevel) {
        if hapticsEnabled {
            playHaptic(level)
        }
        if soundEnabled {
            playSound(level)
        }
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            hapticsReady = false
            return
        }
        do {
            let engine = try CHHapticEngine()
            engine.stoppedHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.hapticsReady = false
                }
            }
            engine.resetHandler = { [weak self] in
                Task { @MainActor in
                    try? self?.engine?.start()
                    self?.hapticsReady = true
                }
            }
            try engine.start()
            self.engine = engine
            hapticsReady = true
        } catch {
            hapticsReady = false
            logger.error("觸覺引擎無法啟動：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func playHaptic(_ level: DangerLevel) {
        guard level.triggersAlert else { return }
        if hapticsReady, let engine {
            do {
                let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: level.hapticIntensity)
                let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: level.hapticSharpness)
                var events = [
                    CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)
                ]
                if level == .danger {
                    events.append(
                        CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0.09)
                    )
                }
                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                return
            } catch {
                hapticsReady = false
                logger.error("觸覺播放失敗，改用系統震動：\(error.localizedDescription, privacy: .public)")
            }
        }

        if level == .danger {
            dangerImpact.impactOccurred(intensity: 1)
        } else {
            warningImpact.impactOccurred(intensity: CGFloat(level.hapticIntensity))
        }
    }

    private func preparePlayers() {
        warningPlayer = try? AVAudioPlayer(data: Self.wav(frequency: DangerLevel.warning.toneFrequency, duration: 0.12))
        dangerPlayer = try? AVAudioPlayer(data: Self.wav(frequency: DangerLevel.danger.toneFrequency, duration: 0.16))
        warningPlayer?.volume = 0.55
        dangerPlayer?.volume = 1
        warningPlayer?.prepareToPlay()
        dangerPlayer?.prepareToPlay()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if ignoresSilentSwitch || playbackRequired {
                // playback 會在靜音開關關掉時仍然出聲，這是安全警示需要的。
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            } else {
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            }
            try session.setActive(true)
            audioReady = true
        } catch {
            audioReady = false
            logger.error("音訊工作階段失敗：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func playSound(_ level: DangerLevel) {
        if !audioReady {
            configureAudioSession()
        }
        let player = level == .danger ? dangerPlayer : warningPlayer
        player?.currentTime = 0
        if player?.play() == true {
            return
        }
        // 自製提示音失敗時，退回系統音，至少還有聲音。
        AudioServicesPlaySystemSound(level == .danger ? 1005 : 1057)
    }

    /// 16-bit PCM WAV，讓 App 不必另外夾音檔。
    private static func wav(frequency: Double, duration: Double) -> Data {
        let sampleRate = 22_050
        let frameCount = Int(Double(sampleRate) * duration)
        var pcm = Data()
        pcm.reserveCapacity(frameCount * 2)
        for index in 0..<frameCount {
            let time = Double(index) / Double(sampleRate)
            let attack = 0.008
            let release = 0.03
            let envelope: Double
            if time < attack {
                envelope = time / attack
            } else if time > duration - release {
                envelope = max(0, (duration - time) / release)
            } else {
                envelope = 1
            }
            let sample = sin(2 * Double.pi * frequency * time) * envelope
            let clamped = Int16(max(-32767, min(32767, Int(sample * 32767))))
            var little = clamped.littleEndian
            pcm.append(Data(bytes: &little, count: MemoryLayout<Int16>.size))
        }

        let dataSize = pcm.count
        var header = Data()
        header.reserveCapacity(44 + dataSize)
        header.append(contentsOf: "RIFF".utf8)
        appendU32(UInt32(36 + dataSize), to: &header)
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        appendU32(16, to: &header)
        appendU16(1, to: &header)
        appendU16(1, to: &header)
        appendU32(UInt32(sampleRate), to: &header)
        appendU32(UInt32(sampleRate * 2), to: &header)
        appendU16(2, to: &header)
        appendU16(16, to: &header)
        header.append(contentsOf: "data".utf8)
        appendU32(UInt32(dataSize), to: &header)
        header.append(pcm)
        return header
    }

    private static func appendU32(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 4))
    }

    private static func appendU16(_ value: UInt16, to data: inout Data) {
        var little = value.littleEndian
        data.append(Data(bytes: &little, count: 2))
    }
}
