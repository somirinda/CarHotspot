import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// 尽早创建 CBCentralManager（带 restoreIdentifier），
    /// 这样 App 在后台被蓝牙事件唤醒时才能收到 willRestoreState 回调。
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        HotspotMonitor.shared.autoStartIfNeeded()
        return true
    }
}

@main
struct CarHotspotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
