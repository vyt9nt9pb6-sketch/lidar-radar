import Foundation

/// 連續幾幀的中位數，拿掉單幀雜訊。
///
/// 第一幀直接採用，避免 App 一打開就慢半拍。
/// 之後危險必須至少兩幀同意，免得一塊反光就讓手機狂震。
struct DistanceStabilizer {
    private(set) var samples: [Double?] = []
    private let window = 3

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    mutating func push(_ sample: Double?) -> (distance: Double?, level: DangerLevel) {
        samples.append(sample)
        if samples.count > window {
            samples.removeFirst(samples.count - window)
        }

        if samples.count < 2 {
            return (sample, DangerLevel.classify(sample))
        }

        let finite = samples.compactMap { $0 }.filter(\.isFinite)
        let distance = finite.isEmpty ? nil : finite.sorted()[finite.count / 2]
        let levels = samples.map { DangerLevel.classify($0) }
        let dangerCount = levels.filter { $0 == .danger }.count
        let warningOrCloser = levels.filter { $0 == .warning || $0 == .danger }.count

        if dangerCount >= 2 {
            return (distance, .danger)
        }
        if warningOrCloser >= 2, DangerLevel.classify(distance) != .safe {
            let level: DangerLevel = dangerCount >= 2 ? .danger : .warning
            return (distance, level)
        }
        if finite.isEmpty {
            return (nil, .unknown)
        }
        // 只有一幀貼得很近時，先降成注意，下一幀再確認。
        let classified = DangerLevel.classify(distance)
        if classified == .danger {
            return (distance, .warning)
        }
        return (distance, classified)
    }
}
