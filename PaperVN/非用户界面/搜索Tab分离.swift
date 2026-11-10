import ObjectiveC
import SwiftUI
import UIKit

// iOS 27 起，SwiftUI 的搜索 Tab 只有两种现成组合：
// 分离但轻点后立即弹出键盘（.searchTabSelection），或者与其他 Tab 合并。
// 这里恢复 iOS 26 的行为：搜索 Tab 分离在 Tab 栏右侧，轻点后展开为搜索框，
// 再轻点搜索框才弹出键盘。
//
// 做法：UIKit 公开的 `prominentTabIdentifier` 设为 `UISearchTab.identifier`，
// 同时不开启自动激活。SwiftUI 每次更新都会把它重置为 nil（且不触发 KVO），
// 所以给这个控制器实例换一个动态子类，在 setter 里把 nil 换回搜索 Tab。
// 如果以后系统更新后行为变了，先用最小示例核对 SwiftUI 是否仍然这样重置。

extension View {
    /// 只在 iPhone、iOS 27 及以上生效；其他情况原样返回
    @ViewBuilder
    func 平台搜索Tab分离(_ 启用: Bool) -> some View {
        if #available(iOS 27.0, *),
           UIDevice.current.userInterfaceIdiom != .pad {
            self.modifier(搜索Tab分离修饰(启用: 启用))
        } else {
            self
        }
    }
}

@available(iOS 27.0, *)
private struct 搜索Tab分离修饰: ViewModifier {
    let 启用: Bool

    func body(content: Content) -> some View {
        content
            .task(id: 启用) {
                // 根视图刚出现或刚切换设置时，底层控制器和搜索 Tab 可能还没建好
                for 间隔 in [0, 50, 150, 300, 600, 1000] {
                    if 间隔 > 0 {
                        try? await Task.sleep(for: .milliseconds(间隔))
                    }
                    if Task.isCancelled { return }
                    if 搜索Tab分离.应用(启用: 启用) { return }
                }
            }
    }
}

@available(iOS 27.0, *)
@MainActor
enum 搜索Tab分离 {
    private static var 启用键: UInt8 = 0
    private static let 子类前缀 = "PaperVN搜索Tab分离_"

    /// 返回是否已经应用到位
    static func 应用(启用: Bool) -> Bool {
        guard let 控制器 = 根标签栏控制器() else { return false }
        let 有搜索Tab = 控制器.tabs.contains { $0 is UISearchTab }
        if 启用, !有搜索Tab { return false }

        guard 换成拦截子类(控制器) else { return false }
        objc_setAssociatedObject(
            控制器,
            &启用键,
            启用,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        // 传 nil：启用时由子类换成搜索 Tab，停用时就是系统默认
        控制器.setProminentTabIdentifier(nil, animated: false)
        return true
    }

    private static func 已启用(_ 控制器: AnyObject) -> Bool {
        objc_getAssociatedObject(控制器, &启用键) as? Bool ?? false
    }

    private static func 根标签栏控制器() -> UITabBarController? {
        for 场景 in UIApplication.shared.connectedScenes {
            guard let 窗口场景 = 场景 as? UIWindowScene else { continue }
            for 窗口 in 窗口场景.windows {
                if let 找到 = 查找(窗口.rootViewController) { return 找到 }
            }
        }
        return nil
    }

    private static func 查找(_ 控制器: UIViewController?) -> UITabBarController? {
        guard let 控制器 else { return nil }
        if let 标签栏 = 控制器 as? UITabBarController { return 标签栏 }
        for 子控制器 in 控制器.children {
            if let 找到 = 查找(子控制器) { return 找到 }
        }
        return nil
    }

    private static func 换成拦截子类(_ 控制器: UITabBarController) -> Bool {
        guard let 原类 = object_getClass(控制器) else { return false }
        let 原类名 = NSStringFromClass(原类)
        if 原类名.hasPrefix(子类前缀) { return true }

        let 子类名 = 子类前缀 + 原类名
        if let 已有: AnyClass = NSClassFromString(子类名) {
            object_setClass(控制器, 已有)
            return true
        }

        let 带动画 = #selector(
            UITabBarController.setProminentTabIdentifier(_:animated:)
        )
        let 不带动画 = #selector(
            setter: UITabBarController.prominentTabIdentifier
        )
        guard let 带动画方法 = class_getInstanceMethod(原类, 带动画),
              let 不带动画方法 = class_getInstanceMethod(原类, 不带动画),
              let 子类 = objc_allocateClassPair(原类, 子类名, 0)
        else { return false }

        typealias 带动画函数 = @convention(c) (
            AnyObject, Selector, NSString?, Bool
        ) -> Void
        typealias 不带动画函数 = @convention(c) (
            AnyObject, Selector, NSString?
        ) -> Void
        let 原带动画 = unsafeBitCast(
            method_getImplementation(带动画方法),
            to: 带动画函数.self
        )
        let 原不带动画 = unsafeBitCast(
            method_getImplementation(不带动画方法),
            to: 不带动画函数.self
        )

        let 新带动画: @convention(block) (AnyObject, NSString?, Bool) -> Void = {
            控制器, 标识符, 动画 in
            原带动画(控制器, 带动画, 替换后的标识符(控制器, 标识符), 动画)
        }
        let 新不带动画: @convention(block) (AnyObject, NSString?) -> Void = {
            控制器, 标识符 in
            原不带动画(控制器, 不带动画, 替换后的标识符(控制器, 标识符))
        }
        class_addMethod(
            子类,
            带动画,
            imp_implementationWithBlock(新带动画),
            method_getTypeEncoding(带动画方法)
        )
        class_addMethod(
            子类,
            不带动画,
            imp_implementationWithBlock(新不带动画),
            method_getTypeEncoding(不带动画方法)
        )
        objc_registerClassPair(子类)
        object_setClass(控制器, 子类)
        return true
    }

    private nonisolated static func 替换后的标识符(
        _ 控制器: AnyObject,
        _ 标识符: NSString?
    ) -> NSString? {
        if let 标识符 { return 标识符 }
        nonisolated(unsafe) let 目标 = 控制器
        let 换成搜索Tab = MainActor.assumeIsolated { 已启用(目标) }
        guard 换成搜索Tab else { return nil }
        let 搜索标识符 = MainActor.assumeIsolated { UISearchTab.identifier }
        return 搜索标识符 as NSString
    }
}
