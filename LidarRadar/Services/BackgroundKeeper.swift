import CoreLocation
import Foundation
import os
import UIKit

/// 背景只做兩件事：把即時動態改成「已暫停」，以及在使用者允許時掛一個很粗的定位。
///
/// 定位座標看過就丟，不寫檔、不上傳。它不能讓光達在鎖定畫面繼續跑，
/// iOS 不允許背景使用相機。不要把 allowsBackgroundLocationUpdates 在沒有「永遠」授權時打開，否則會直接崩潰。
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.kwok.lidarradar", category: "background")
    private var task: UIBackgroundTaskIdentifier = .invalid
    private var didStart = false

    func requestAndStart() {
        if !didStart {
            didStart = true
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyReduced
            manager.distanceFilter = 500
            manager.activityType = .other
            manager.pausesLocationUpdatesAutomatically = true
            manager.allowsBackgroundLocationUpdates = false
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            enableBackgroundUpdatesIfAllowed()
            manager.startUpdatingLocation()
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        didStart = false
        endKeepAlive()
    }

    func beginKeepAlive() {
        guard task == .invalid else { return }
        task = UIApplication.shared.beginBackgroundTask(withName: "com.kwok.lidarradar.keepalive") { [weak self] in
            DispatchQueue.main.async {
                self?.endKeepAlive()
            }
        }
    }

    func endKeepAlive() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            enableBackgroundUpdatesIfAllowed()
            manager.startUpdatingLocation()
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 故意不保存 locations。這個回呼存在，只是因為開始定位後系統會送座標進來。
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("定位失敗（不影響前景光達）：\(error.localizedDescription, privacy: .public)")
    }

    private func enableBackgroundUpdatesIfAllowed() {
        // 只有「永遠」授權才打開。使用期間授權就維持 false，避免執行期例外。
        guard manager.authorizationStatus == .authorizedAlways else { return }
        manager.allowsBackgroundLocationUpdates = true
    }
}
