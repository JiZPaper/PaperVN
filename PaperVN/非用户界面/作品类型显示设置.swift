import Foundation

/// 设置里“搜索”→“显示类型”的勾选：只影响搜索结果，关闭的类型搜索不到。Today 和资料库不受影响。至少保留一种类型。
nonisolated enum 作品类型显示设置 {
    static func 键(_ type: 作品类型) -> String {
        "contentTypes.\(type.rawValue).enabled"
    }

    static func 已启用(_ type: 作品类型, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: 键(type)) as? Bool ?? true
    }

    static func 已启用类型(defaults: UserDefaults = .standard) -> Set<作品类型> {
        Set(作品类型.allCases.filter { 已启用($0, defaults: defaults) })
    }

    /// 视觉小说的角色、会社、制作人员、发行版本都来自 VNDB，随视觉小说一起开关。
    static var 视觉小说已启用: Bool { 已启用(.visualNovel) }
}
