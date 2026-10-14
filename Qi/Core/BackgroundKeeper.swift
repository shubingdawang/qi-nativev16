import Foundation
import CoreLocation
import UIKit

/// 定位辅助：她切出去的时候，让正在回的话、正在跑的工具接着跑完。
///
/// iOS 切到后台大约 30 秒就会把网络掐掉，他想得久一点、她切出去久一点，那句话就断了。
/// 开着这个的话：他一开始回话（或者用工具）就用**最低精度**的定位顶着，
/// App 在后台也不会被挂起；最后一件事做完马上停。
///
/// - 精度是「三公里」那一档，耗电很小；位置不存、不发，回调里什么都不做
/// - 只在有事在跑的时候开，平常、等定时消息的时候都不开
/// - 开着的时候状态栏会有定位标记，这是系统规定的，也让她知道它在顶着
/// - 不保证一定不断：系统内存紧张、她手动划掉 App，照样会停
@MainActor
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {

    static let shared = BackgroundKeeper()

    private let manager = CLLocationManager()
    /// 现在有几件事在跑（回话、工具）
    private var holds = 0
    private var running = false
    /// iOS 17 起：拿着它，「使用期间」的定位权限在后台也能接着收
    private var session: AnyObject?

    static let key = "locationAssist"
    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.key) }

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
    }

    /// 打开开关时问一次权限
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    var permissionText: String {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "已允许定位"
        case .denied, .restricted: return "定位被关掉了：去「设置 → 栖 → 位置」改成「使用 App 期间」"
        default: return "还没问过定位权限"
        }
    }

    /// 开始一件事（回话、跑工具）。⚠️ 要在 App 还在前台的时候叫：
    /// 「使用期间」的权限只认在前台开起来的定位
    func begin() {
        holds += 1
        refresh()
    }

    func end() {
        holds = max(0, holds - 1)
        refresh()
    }

    private func refresh() {
        let want = enabled && holds > 0
        let status = manager.authorizationStatus
        let allowed = status == .authorizedWhenInUse || status == .authorizedAlways
        if want, allowed, !running {
            running = true
            manager.allowsBackgroundLocationUpdates = true
            if #available(iOS 17.0, *) { session = CLBackgroundActivitySession() }
            manager.startUpdatingLocation()
        } else if (!want || !allowed), running {
            running = false
            manager.stopUpdatingLocation()
            manager.allowsBackgroundLocationUpdates = false
            if #available(iOS 17.0, *) { (session as? CLBackgroundActivitySession)?.invalidate() }
            session = nil
        }
    }

    // 位置本身不要：收到就扔
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in BackgroundKeeper.shared.refresh() }
    }
}
