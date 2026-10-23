import AVFoundation

/// 只問系統「這支手機現在允不允許多工相機」，不開相機、不加 entitlement。
///
/// iPhone 上，沒有 voip 背景模式、也沒有 Apple 核准的
/// `com.apple.developer.avfoundation.multitasking-camera-access` 時，這裡是 false。
/// 這個 App 兩個都不加，所以真機上預期是 false。子母畫面仍可浮出來，但光達幀不會繼續到。
enum MultitaskingCamera {
    static var isSupported: Bool {
        guard #available(iOS 16.0, *) else { return false }
        return AVCaptureSession().isMultitaskingCameraAccessSupported
    }
}
