import SwiftUI

/// 前方距離的警示等級。
///
/// 這個檔案會同時編譯進主 App 與 Widget Extension，
/// 門檻、顏色、文案、震動強度與提示音都只有這一份，避免兩邊判斷不一致。
///
/// 門檻（公尺，越近越危險）：
/// - 危險：小於 0.8
/// - 注意：0.8（含）到小於 1.5
/// - 安全：1.5（含）以上
/// - 讀取中：沒有可用距離
enum DangerLevel: String, Codable, Hashable, CaseIterable {
    case safe
    case warning
    case danger
    case unknown

    /// 小於這個距離視為危險。
    static let dangerMeters: Double = 0.8
    /// 小於這個距離（但還沒到危險）視為注意。
    static let warningMeters: Double = 1.5

    static func classify(_ meters: Double?) -> DangerLevel {
        guard let meters, meters.isFinite, meters > 0 else { return .unknown }
        if meters < dangerMeters { return .danger }
        if meters < warningMeters { return .warning }
        return .safe
    }

    var emoji: String {
        switch self {
        case .safe: return "🟢"
        case .warning: return "🟡"
        case .danger: return "🔴"
        case .unknown: return "⚪️"
        }
    }

    var label: String {
        switch self {
        case .safe: return L10n.levelSafe
        case .warning: return L10n.levelWarning
        case .danger: return L10n.levelDanger
        case .unknown: return L10n.levelReading
        }
    }

    /// 動態島、鎖定畫面與 App 內大字共用的顏色。
    var color: Color {
        switch self {
        case .safe:
            return Color(red: 0.24, green: 0.86, blue: 0.59)
        case .warning:
            return Color(red: 0.98, green: 0.76, blue: 0.28)
        case .danger:
            return Color(red: 1.0, green: 0.34, blue: 0.36)
        case .unknown:
            return Color(red: 0.62, green: 0.67, blue: 0.74)
        }
    }

    /// Core Haptics 強度，0 表示這個等級不震動。
    var hapticIntensity: Float {
        switch self {
        case .safe, .unknown: return 0
        case .warning: return 0.55
        case .danger: return 1
        }
    }

    var hapticSharpness: Float {
        switch self {
        case .warning: return 0.4
        case .danger: return 1
        case .safe, .unknown: return 0
        }
    }

    /// 等級維持不變時，重複聲音與震動的間隔。
    var repeatInterval: TimeInterval {
        switch self {
        case .warning: return 1.2
        case .danger: return 0.45
        case .safe, .unknown: return .infinity
        }
    }

    var toneFrequency: Double {
        switch self {
        case .warning: return 740
        case .danger: return 1046
        case .safe, .unknown: return 0
        }
    }

    /// 安全與讀取中只顯示顏色，不發出聲音或震動，避免一路響個不停。
    var triggersAlert: Bool {
        self == .warning || self == .danger
    }
}
