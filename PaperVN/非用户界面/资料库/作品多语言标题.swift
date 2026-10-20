import Foundation

/// 把各平台的标题整理成和 VNDB 相同的多语言标题列表，动画、漫画、轻小说也按“偏好语言＞备用语言＞默认标题”显示。
nonisolated enum 作品多语言标题 {
    /// - Parameters:
    ///   - 原名: 原语言标题（日文、韩文或中文）。
    ///   - 原名语言: 来源标明的语言（MAL 的 ja 字段、AniList 的出品国家等）。来源没有标明时为 nil，
    ///     记为“und”（未知），不按文字猜测，显示时用系统字体。
    ///   - 罗马字: 原名的罗马字写法。
    ///   - 英文: 英文标题，各平台给出的英文标题视为官方标题。
    ///   - 中文: 简体中文标题。
    ///   - 中文为官方: Bangumi 的中文名由用户编辑，不能确定是否为官方译名，视为非官方。
    static func 生成(
        原名: String?,
        原名语言: String? = nil,
        罗马字: String?,
        英文: String? = nil,
        中文: String? = nil,
        中文为官方: Bool = false
    ) -> [用户多语言标题] {
        var titles: [用户多语言标题] = []
        let native = 有效(原名)
        let latin = 有效(罗马字)
        if let native {
            titles.append(用户多语言标题(
                lang: 原名语言 ?? "und",
                title: native,
                latin: latin,
                official: true,
                main: true
            ))
        } else if let latin {
            // 只有罗马字时也作为原语言标题，但不当作日文
            titles.append(用户多语言标题(lang: "ja-Latn", title: latin, latin: latin, official: true, main: true))
        }
        if let english = 有效(英文) {
            titles.append(用户多语言标题(lang: "en", title: english, latin: nil, official: true, main: false))
        }
        if let chinese = 有效(中文) {
            titles.append(用户多语言标题(lang: "zh-Hans", title: chinese, latin: nil, official: 中文为官方, main: false))
        }
        return titles
    }

    /// 合并多个来源的标题：前面的来源优先，原语言标题只保留一个，同语言同文字的去重。
    static func 合并(_ lists: [[用户多语言标题]]) -> [用户多语言标题] {
        var result: [用户多语言标题] = []
        var hasMain = false
        for title in lists.joined() {
            if result.contains(where: { $0.lang == title.lang && $0.title == title.title }) { continue }
            if title.main {
                guard !hasMain else {
                    // 其他来源的原名降为普通标题，仍可按语言选到
                    result.append(用户多语言标题(lang: title.lang, title: title.title, latin: title.latin, official: title.official, main: false))
                    continue
                }
                hasMain = true
            }
            result.append(title)
        }
        return result
    }

    /// AniList 的出品国家换成语言代码。
    static func 语言(国家 country: String?) -> String? {
        switch country {
        case "JP": "ja"
        case "KR": "ko"
        case "CN": "zh-Hans"
        case "TW", "HK": "zh-Hant"
        default: nil
        }
    }

    private static func 有效(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

extension 本地资料库条目 {
    /// 按标题语言设置选出的标题；没有多语言标题时用默认标题。
    func 显示标题(偏好: 标题语言, 回退: 标题语言, 允许非官方: Bool) -> 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: 多语言标题,
            defaultTitle: 标题,
            偏好: 偏好,
            回退: 回退,
            允许非官方: 允许非官方
        )
    }

    /// 所有语言的标题，用于搜索。
    var 全部标题: [String] {
        [标题] + (多语言标题 ?? []).flatMap { [$0.title, $0.latin].compactMap { $0 } }
    }
}
