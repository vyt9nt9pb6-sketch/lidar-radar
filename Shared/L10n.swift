import Foundation

/// 介面字串。英文是開發語言，也是找不到翻譯時的退路。
/// 繁體中文在 Shared/Localizable.xcstrings。主 App 與 Widget 都會把這份目錄打進自己的 bundle，
/// 所以動態島會跟著手機語言，而不是寫死中文。
enum L10n {
    static var appName: String { String(localized: "app.name") }
    static var checking: String { String(localized: "checking.body") }

    static var consentSubtitle: String { String(localized: "consent.subtitle") }
    static var consentPrinciples: String { String(localized: "consent.principles") }
    static var consentDisclaimer: String { String(localized: "consent.disclaimer") }
    static var consentToggle: String { String(localized: "consent.toggle") }
    static var consentAgree: String { String(localized: "consent.agree") }
    static var consentLater: String { String(localized: "consent.later") }

    static var principleLocalTitle: String { String(localized: "principle.local.title") }
    static var principleLocalDetail: String { String(localized: "principle.local.detail") }
    static var principleUploadTitle: String { String(localized: "principle.upload.title") }
    static var principleUploadDetail: String { String(localized: "principle.upload.detail") }
    static var principleStoreTitle: String { String(localized: "principle.store.title") }
    static var principleStoreDetail: String { String(localized: "principle.store.detail") }

    static var permissionTitle: String { String(localized: "permission.title") }
    static var permissionBody: String { String(localized: "permission.body") }
    static var permissionOpenSettings: String { String(localized: "permission.openSettings") }
    static var permissionOpenPrivacy: String { String(localized: "permission.openPrivacy") }

    static var unsupportedTitle: String { String(localized: "unsupported.title") }
    static var unsupportedBody: String { String(localized: "unsupported.body") }
    static var unsupportedSceneDepth: String { String(localized: "unsupported.sceneDepth") }
    static var unsupportedMesh: String { String(localized: "unsupported.mesh") }
    static var unsupportedYes: String { String(localized: "unsupported.yes") }
    static var unsupportedNo: String { String(localized: "unsupported.no") }
    static var unsupportedIsland: String { String(localized: "unsupported.island") }

    static var settingsTitle: String { String(localized: "settings.title") }
    static var settingsMonitoring: String { String(localized: "settings.monitoring") }
    static var settingsLowPower: String { String(localized: "settings.lowPower") }
    static var settingsSound: String { String(localized: "settings.sound") }
    static var settingsIgnoreSilent: String { String(localized: "settings.ignoreSilent") }
    static var settingsHaptics: String { String(localized: "settings.haptics") }
    static var settingsPreview: String { String(localized: "settings.preview") }
    static var settingsMonitoringFooter: String { String(localized: "settings.monitoringFooter") }
    static var settingsIsland: String { String(localized: "settings.island") }
    static var settingsRestart: String { String(localized: "settings.restart") }
    static var settingsIslandFooter: String { String(localized: "settings.islandFooter") }
    static var settingsPrivacy: String { String(localized: "settings.privacy") }
    static var settingsSystemSettings: String { String(localized: "settings.systemSettings") }
    static var settingsRevoke: String { String(localized: "settings.revoke") }
    static var settingsPrivacyFooter: String { String(localized: "settings.privacyFooter") }
    static var settingsDone: String { String(localized: "settings.done") }
    static var settingsRevokeTitle: String { String(localized: "settings.revokeTitle") }
    static var settingsRevokeConfirm: String { String(localized: "settings.revokeConfirm") }
    static var settingsCancel: String { String(localized: "settings.cancel") }
    static var settingsRevokeMessage: String { String(localized: "settings.revokeMessage") }
    static var settingsPip: String { String(localized: "settings.pip") }
    static var settingsPipFooterUnsupported: String { String(localized: "settings.pipFooterUnsupported") }
    static var settingsPipFooterSupported: String { String(localized: "settings.pipFooterSupported") }

    static func settingsVersion(_ version: String, _ build: String) -> String {
        String(format: String(localized: "settings.versionFormat"), locale: .current, version, build)
    }

    static var radarMonitoring: String { String(localized: "radar.monitoring") }
    static var radarPaused: String { String(localized: "radar.paused") }
    static var radarSettings: String { String(localized: "radar.settings") }
    static var radarMeters: String { String(localized: "radar.meters") }
    static var radarPausedTitle: String { String(localized: "radar.pausedTitle") }
    static var radarPausedMessage: String { String(localized: "radar.pausedMessage") }
    static var radarFailureTitle: String { String(localized: "radar.failureTitle") }
    static var radarRetry: String { String(localized: "radar.retry") }
    static var radarStarting: String { String(localized: "radar.starting") }
    static var radarAim: String { String(localized: "radar.aim") }
    static var radarThresholds: String { String(localized: "radar.thresholds") }

    static func radarFPS(_ fps: Int) -> String {
        String(format: String(localized: "radar.fpsFormat"), locale: .current, fps)
    }

    static var principlesLine: String { String(localized: "radar.principlesLine") }

    static var activityIdle: String { String(localized: "activity.idle") }
    static var activityNeedsOS: String { String(localized: "activity.needsOS") }
    static var activityOff: String { String(localized: "activity.off") }
    static var activityRunning: String { String(localized: "activity.running") }
    static var activityFailed: String { String(localized: "activity.failed") }

    static var a11yPaused: String { String(localized: "a11y.paused") }
    static var a11yReading: String { String(localized: "a11y.reading") }

    static func a11yDistance(_ distance: String, _ level: String) -> String {
        String(format: String(localized: "a11y.distanceFormat"), locale: .current, distance, level)
    }

    static var powerSystem: String { String(localized: "power.system") }
    static var powerThermal: String { String(localized: "power.thermal") }
    static var powerManual: String { String(localized: "power.manual") }

    static var hintInitializing: String { String(localized: "hint.initializing") }
    static var hintMotion: String { String(localized: "hint.motion") }
    static var hintFeatures: String { String(localized: "hint.features") }
    static var hintRelocalizing: String { String(localized: "hint.relocalizing") }
    static var hintLimited: String { String(localized: "hint.limited") }

    static var failureNoMetal: String { String(localized: "failure.noMetal") }
    static var failureNoQueue: String { String(localized: "failure.noQueue") }
    static var failureNoLibrary: String { String(localized: "failure.noLibrary") }
    static var failureNoKernel: String { String(localized: "failure.noKernel") }
    static var failureThreads: String { String(localized: "failure.threads") }
    static var failureNoLidar: String { String(localized: "failure.noLidar") }
    static var failureGeneric: String { String(localized: "failure.generic") }
    static var failureCamera: String { String(localized: "failure.camera") }
    static var failureUnsupported: String { String(localized: "failure.unsupported") }
    static var failureSensorUnavailable: String { String(localized: "failure.sensorUnavailable") }
    static var failureSensorFailed: String { String(localized: "failure.sensorFailed") }
    static var failureWorldTracking: String { String(localized: "failure.worldTracking") }
    static var failureRetrying: String { String(localized: "failure.retrying") }
    static var failureGiveUp: String { String(localized: "failure.giveUp") }

    static var levelSafe: String { String(localized: "level.safe") }
    static var levelWarning: String { String(localized: "level.warning") }
    static var levelDanger: String { String(localized: "level.danger") }
    static var levelReading: String { String(localized: "level.reading") }

    static var statusPaused: String { String(localized: "status.paused") }
    static var statusDanger: String { String(localized: "status.danger") }
    static var statusWarning: String { String(localized: "status.warning") }
    static var statusSafe: String { String(localized: "status.safe") }
    static var statusReading: String { String(localized: "status.reading") }
    static var statusLowPowerSuffix: String { String(localized: "status.lowPowerSuffix") }

    static var widgetMeters: String { String(localized: "widget.meters") }
    static var widgetElapsed: String { String(localized: "widget.elapsed") }

    static var pipPausedTitle: String { String(localized: "pip.pausedTitle") }
    static var pipPausedHint: String { String(localized: "pip.pausedHint") }
    static var pipInlineCaption: String { String(localized: "pip.inlineCaption") }
    static var pipPossible: String { String(localized: "pip.possible") }
    static var pipNotPossible: String { String(localized: "pip.notPossible") }
    static var pipActive: String { String(localized: "pip.active") }
}
