import ActivityKit
import Foundation
import os

/// 更新動態島與鎖定畫面。裝置沒有動態島、或使用者關掉即時動態時，不會當掉。
///
/// 即時動態的 ActivityContent API 從 iOS 16.2 開始。部署目標仍是 16.1；
/// 停在 16.1 的手機會走 needsNewerOS，聲音、震動與畫面數字照常。
@MainActor
final class LiveActivityManager {
    enum Availability: Equatable {
        case idle
        case needsNewerOS
        case turnedOff
        case running
        case failed
    }

    private let logger = Logger(subsystem: "com.kwok.lidarradar", category: "activity")
    private var attributes = RadarAttributes(startedAt: Date())
    private var activity: Activity<RadarAttributes>?
    private var queued: RadarAttributes.ContentState?
    private var drain: Task<Void, Never>?
    private var ended = false
    private var didLogFailure = false

    private var lastLevel: DangerLevel?
    private var lastDistance = -999.0
    private var lastPaused: Bool?
    private var lastLowPower: Bool?
    private var lastSentAt = Date.distantPast

    private(set) var availability: Availability = .idle
    var onAvailability: ((Availability) -> Void)?

    func beginSession() {
        ended = false
        attributes = RadarAttributes(startedAt: Date())
        activity = nil
        lastLevel = nil
        lastDistance = -999
        lastPaused = nil
        lastLowPower = nil
        lastSentAt = .distantPast
        didLogFailure = false
        availability = .idle
    }

    /// 等級改變會立刻送出。距離要差 0.25 公尺且距上次至少 2 秒。
    /// 另外每 15 秒送一次心跳，讓 staleDate 不會把還活著的監測標成過期。
    func publish(_ state: RadarAttributes.ContentState, force: Bool = false) {
        guard !ended else { return }
        guard force || shouldSend(state) else { return }
        remember(state)
        queued = state
        guard drain == nil else { return }
        drain = Task { @MainActor in
            await self.drainQueue()
        }
    }

    func endAll() async {
        ended = true
        queued = nil
        guard #available(iOS 16.2, *) else {
            setAvailability(.needsNewerOS)
            return
        }
        await endAllModern()
        activity = nil
        setAvailability(.idle)
    }

    private func shouldSend(_ state: RadarAttributes.ContentState) -> Bool {
        if lastLevel == nil { return true }
        if state.isPaused != lastPaused { return true }
        if state.level != lastLevel { return true }
        if state.isLowPower != lastLowPower { return true }
        let elapsed = Date().timeIntervalSince(lastSentAt)
        if abs(state.distanceMeters - lastDistance) >= 0.25 && elapsed >= 2 { return true }
        if elapsed >= 15 { return true }
        return false
    }

    private func remember(_ state: RadarAttributes.ContentState) {
        lastLevel = state.level
        lastDistance = state.distanceMeters
        lastPaused = state.isPaused
        lastLowPower = state.isLowPower
        lastSentAt = Date()
    }

    private func drainQueue() async {
        while !ended, let next = queued {
            queued = nil
            if ended { break }
            let availability = await deliver(next)
            guard !ended else { break }
            setAvailability(availability)
        }
        drain = nil
    }

    private func deliver(_ state: RadarAttributes.ContentState) async -> Availability {
        guard #available(iOS 16.2, *) else { return .needsNewerOS }
        return await deliverModern(state)
    }

    @available(iOS 16.2, *)
    private func deliverModern(_ state: RadarAttributes.ContentState) async -> Availability {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return .turnedOff
        }
        if activity == nil {
            activity = Activity<RadarAttributes>.activities.first
            for extra in Activity<RadarAttributes>.activities.dropFirst() {
                await endModern(extra, state: state)
            }
        }
        do {
            if let activity {
                guard !ended else { return .idle }
                await activity.update(makeContent(state))
                if ended {
                    await endModern(activity, state: state)
                    self.activity = nil
                    return .idle
                }
                self.activity = activity
            } else {
                guard !ended else { return .idle }
                let created = try Activity<RadarAttributes>.request(
                    attributes: attributes,
                    content: makeContent(state),
                    pushType: nil
                )
                if ended {
                    await endModern(created, state: state)
                    self.activity = nil
                    return .idle
                }
                activity = created
            }
            didLogFailure = false
            return .running
        } catch {
            if !didLogFailure {
                didLogFailure = true
                logger.error("即時動態更新失敗：\(error.localizedDescription, privacy: .public)")
            }
            activity = nil
            if !ActivityAuthorizationInfo().areActivitiesEnabled {
                return .turnedOff
            }
            return .failed
        }
    }

    @available(iOS 16.2, *)
    private func endAllModern() async {
        let state = RadarAttributes.ContentState.make(
            distanceMeters: nil,
            level: .unknown,
            isPaused: true,
            isLowPower: false
        )
        if let activity {
            await endModern(activity, state: state)
        }
        for existing in Activity<RadarAttributes>.activities {
            await endModern(existing, state: state)
        }
    }

    @available(iOS 16.2, *)
    private func endModern(_ activity: Activity<RadarAttributes>, state: RadarAttributes.ContentState) async {
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: 0)
        await activity.end(content, dismissalPolicy: .immediate)
    }

    @available(iOS 16.2, *)
    private func makeContent(_ state: RadarAttributes.ContentState) -> ActivityContent<RadarAttributes.ContentState> {
        let stale: Date? = state.isPaused ? nil : Date().addingTimeInterval(25)
        let score: Double
        if state.isPaused {
            score = 0
        } else {
            switch state.level {
            case .danger: score = 100
            case .warning: score = 60
            case .safe: score = 20
            case .unknown: score = 5
            }
        }
        return ActivityContent(state: state, staleDate: stale, relevanceScore: score)
    }

    private func setAvailability(_ availability: Availability) {
        self.availability = availability
        onAvailability?(availability)
    }
}
