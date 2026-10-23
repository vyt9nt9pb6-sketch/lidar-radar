import Foundation

/// 只記住「已同意」和幾個開關。深度、距離、位置都不進這裡。
@MainActor
final class SettingsStore: ObservableObject {
    @Published var consentAccepted: Bool {
        didSet { store(Key.consent, consentAccepted) }
    }
    @Published var lowPower: Bool {
        didSet { store(Key.lowPower, lowPower) }
    }
    @Published var soundEnabled: Bool {
        didSet { store(Key.sound, soundEnabled) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { store(Key.haptics, hapticsEnabled) }
    }
    @Published var ignoreSilentSwitch: Bool {
        didSet { store(Key.ignoreSilent, ignoreSilentSwitch) }
    }
    /// 實驗功能，預設關閉。打開後切到別的 App 會試著浮出子母畫面。
    @Published var pictureInPictureEnabled: Bool {
        didSet { store(Key.pictureInPicture, pictureInPictureEnabled) }
    }

    private let defaults: UserDefaults
    private var persist = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        consentAccepted = defaults.object(forKey: Key.consent) as? Bool ?? false
        lowPower = defaults.object(forKey: Key.lowPower) as? Bool ?? false
        soundEnabled = defaults.object(forKey: Key.sound) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        ignoreSilentSwitch = defaults.object(forKey: Key.ignoreSilent) as? Bool ?? true
        pictureInPictureEnabled = defaults.object(forKey: Key.pictureInPicture) as? Bool ?? false
    }

    func acceptConsent() {
        consentAccepted = true
    }

    /// 刪掉這個 App 的 UserDefaults，記憶體回到出廠開關，同意狀態清空。
    func resetAll() {
        persist = false
        consentAccepted = false
        lowPower = false
        soundEnabled = true
        hapticsEnabled = true
        ignoreSilentSwitch = true
        pictureInPictureEnabled = false
        if let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        }
        persist = true
    }

    private func store(_ key: String, _ value: Bool) {
        guard persist else { return }
        defaults.set(value, forKey: key)
    }

    private enum Key {
        static let consent = "consent.accepted.v1"
        static let lowPower = "settings.lowPower"
        static let sound = "settings.soundEnabled"
        static let haptics = "settings.hapticsEnabled"
        static let ignoreSilent = "settings.ignoreSilentSwitch"
        static let pictureInPicture = "settings.pictureInPicture"
    }
}
