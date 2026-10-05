import Foundation
import Testing
@testable import PaperVN

struct Today推荐内容Tests {
    @Test
    func 填写语言跟随App界面并区分中文脚本() {
        let samples: [(String, Today推荐语言)] = [
            ("zh_CN", .简体中文),
            ("zh-Hans", .简体中文),
            ("zh_TW", .繁体中文),
            ("zh-Hant-HK", .繁体中文),
            ("ja_JP", .日语),
            ("ko_KR", .韩语),
            ("en_US", .英语)
        ]
        for (identifier, expected) in samples {
            #expect(Today推荐语言.当前语言(Locale(identifier: identifier)) == expected)
        }
    }

    @Test
    func 单一英语推荐可供其他界面语言显示() throws {
        let content = try JSONDecoder().decode(Today推荐多语言内容.self, from: Data(#"""
        {
          "description": { "default": "Summer", "en": "Summer" },
          "introduction": { "default": "A summer story.", "en": "A summer story." }
        }
        """#.utf8))
        #expect(content.标题(locale: Locale(identifier: "zh-Hans"), fallback: "旧标题") == "Summer")
        #expect(content.正文(locale: Locale(identifier: "ja"), fallback: "旧描述") == "A summer story.")
        #expect(content.description["zh-Hans"] == nil)
    }

    @Test
    func 多语言标题与描述独立保存并按界面显示() throws {
        let content = Today推荐多语言内容(
            description: ["default": "夏日物语", "zh-Hant": "夏日物語", "ja": "夏の物語"],
            introduction: ["default": "值得阅读。", "zh-Hant": "值得閱讀。", "ja": "読んでほしい物語。"]
        )
        let roundTrip = try JSONDecoder().decode(
            Today推荐多语言内容.self,
            from: JSONEncoder().encode(content)
        )
        #expect(roundTrip.标题(locale: Locale(identifier: "ja_JP"), fallback: "") == "夏の物語")
        #expect(roundTrip.正文(locale: Locale(identifier: "zh_TW"), fallback: "") == "值得閱讀。")
        #expect(roundTrip.标题(locale: Locale(identifier: "ko_KR"), fallback: "") == "夏日物语")
    }
}
