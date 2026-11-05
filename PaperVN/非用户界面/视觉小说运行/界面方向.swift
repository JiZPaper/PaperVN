import UIKit

/// iPhone 平时只用竖屏；运行横版视觉小说时由运行页面切到横屏，离开时切回来。
/// 工程里给 iPhone 声明了竖屏和横屏，实际允许哪些由这里决定（App 代理的 supportedInterfaceOrientationsFor）。
/// iPad 不受影响，始终跟随设备方向。
@MainActor
enum 界面方向 {
    private(set) static var 允许: UIInterfaceOrientationMask = .portrait

    static func 切换(_ mask: UIInterfaceOrientationMask) {
        guard UIDevice.current.userInterfaceIdiom == .phone, mask != 允许 else { return }
        允许 = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        // 根视图控制器和全屏弹出的运行页面都要重新读取支持的方向
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

final class PaperVNAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated {
            UIDevice.current.userInterfaceIdiom == .phone ? 界面方向.允许 : .all
        }
    }
}
