import Foundation

/// 设置里“作品类型”的开关：关闭的类型不在 Today 中显示（为你推荐、Today 故事与推荐、随机语录），
/// 搜索也不会搜到。资料库不受影响。至少保留一种类型。
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
