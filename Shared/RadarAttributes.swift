import ActivityKit
import Foundation

/// 動態島與鎖定畫面即時動態的資料。
///
/// 主 App 與 Widget 必須編譯同一份定義。ActivityKit 用這個型別的名字對上兩邊，
/// 欄位用 Codable 傳遞，所以新增欄位時兩邊會一起改到。
struct RadarAttributes: ActivityAttributes {
    /// 會隨距離改變的內容。編碼後必須小於 4KB。
    struct ContentState: Codable, Hashable {
        /// 公尺。小於 0 代表目前沒有讀數。
        var distanceMeters: Double
        var level: DangerLevel
        /// 相機被 iOS 暫停（鎖定、背景、來電）時為 true。
        var isPaused: Bool
        var isLowPower: Bool
        var updatedAt: Date
        /// 動態島展開區與鎖定畫面底部的短句。由主 App 寫入，Widget 只負責顯示。
        var statusText: String

        var hasDistance: Bool {
            distanceMeters.isFinite && distanceMeters >= 0
        }

        var distanceLabel: String {
            guard hasDistance else { return "—" }
            return String(format: "%.1f", locale: .current, distanceMeters)
        }

        /// 緊湊動態島空間很小。暫停時改顯示文字，不沿用舊距離。
        var compactDistance: String {
            if isPaused { return L10n.radarPaused }
            guard hasDistance else { return "—" }
            return String(format: "%.1fm", locale: .current, distanceMeters)
        }

        /// 暫停時不要沿用上一筆的紅黃綠，避免人以為還在量。
        var displayLevel: DangerLevel {
            isPaused ? .unknown : level
        }
    }

    /// 這次監測開始的時間。Widget 用它畫一個會自己走的計時。
    var startedAt: Date
}

extension RadarAttributes.ContentState {
    static func make(
        distanceMeters: Double?,
        level: DangerLevel,
        isPaused: Bool,
        isLowPower: Bool,
        now: Date = Date()
    ) -> RadarAttributes.ContentState {
        let storedDistance = distanceMeters ?? -1
        return RadarAttributes.ContentState(
            distanceMeters: storedDistance,
            level: level,
            isPaused: isPaused,
            isLowPower: isLowPower,
            updatedAt: now,
            statusText: statusText(level: level, isPaused: isPaused, isLowPower: isLowPower)
        )
    }

    static func statusText(level: DangerLevel, isPaused: Bool, isLowPower: Bool) -> String {
        if isPaused {
            return L10n.statusPaused
        }
        let base: String
        switch level {
        case .danger:
            base = L10n.statusDanger
        case .warning:
            base = L10n.statusWarning
        case .safe:
            base = L10n.statusSafe
        case .unknown:
            base = L10n.statusReading
        }
        return isLowPower ? base + L10n.statusLowPowerSuffix : base
    }
}
