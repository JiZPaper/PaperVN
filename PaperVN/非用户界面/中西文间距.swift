import Foundation

/// 去掉中文、日文与西文（字母、数字）之间的空格。
/// 系统的相对时间等格式会在数字和中日文之间插空格（例如日语的“10 秒前”），App 的文案约定是不加空格。
/// 韩文按词分写，空格是正常的，不处理。
nonisolated enum 中西文间距 {
    private static let 东亚文字 = #"\p{Han}\p{Hiragana}\p{Katakana}ー々〆"#
    private static let 西文 = #"A-Za-z0-9"#
    private static let 空白 = #"[\s  ]+"#

    private static let 规则 = try! NSRegularExpression(
        pattern: "(?<=[\(东亚文字)])\(空白)(?=[\(西文)])|(?<=[\(西文)])\(空白)(?=[\(东亚文字)])"
    )

    static func 去除空格(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return 规则.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

extension Date {
    /// 相对时间（如“10秒前”），已去掉中日文与数字之间的空格。
    func 相对时间文本(
        presentation: Date.RelativeFormatStyle.Presentation = .named,
        unitsStyle: Date.RelativeFormatStyle.UnitsStyle = .wide
    ) -> String {
        中西文间距.去除空格(
            formatted(.relative(presentation: presentation, unitsStyle: unitsStyle))
        )
    }
}
