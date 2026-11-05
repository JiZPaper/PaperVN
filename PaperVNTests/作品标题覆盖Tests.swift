import Foundation
import Testing
@testable import PaperVN

@Suite
@MainActor
struct 作品标题覆盖Tests {
    private let 原有 = 作品多语言标题.生成(
        原名: "ゆるキャン△ スペシャル", 原名语言: "ja", 罗马字: "Yuru Camp△ Special", 英文: "Laid-Back Camp Specials", 中文: "摇曳露营△ 特别篇"
    )

    @Test func 原名只改文字不改语言() {
        let result = 作品标题覆盖.替换(原有, 覆盖: ["original": "ゆるキャン△ OVA"])
        let main = result.first(where: \.main)
        #expect(main?.title == "ゆるキャン△ OVA")
        #expect(main?.lang == "ja")
        #expect(main?.latin == "Yuru Camp△ Special")
        #expect(result.count == 原有.count)
    }

    @Test func 同语言的标题被替换() {
        let result = 作品标题覆盖.替换(原有, 覆盖: ["zh-Hans": "摇曳露营△ OVA", "latin": "Yuru Camp△ OVA"])
        #expect(result.filter { $0.lang == "zh-Hans" }.map(\.title) == ["摇曳露营△ OVA"])
        #expect(result.first { $0.lang == "zh-Hans" }?.official == true)
        #expect(result.first(where: \.main)?.latin == "Yuru Camp△ OVA")
        #expect(result.first { $0.lang == "en" }?.title == "Laid-Back Camp Specials")
    }

    @Test func 原名语言的标题改原名() {
        let result = 作品标题覆盖.替换(原有, 覆盖: ["ja": "ゆるキャン△ OVA"])
        #expect(result.filter { $0.lang == "ja" }.count == 1)
        #expect(result.first(where: \.main)?.title == "ゆるキャン△ OVA")
    }

    @Test func 没有的语言补上() {
        let result = 作品标题覆盖.替换(原有, 覆盖: ["zh-Hant": "搖曳露營△ OVA"])
        #expect(result.last == 用户多语言标题(lang: "zh-Hant", title: "搖曳露營△ OVA", latin: nil, official: true, main: false))
    }

    @Test func 没有原名时补一个() {
        let result = 作品标题覆盖.替换([], 覆盖: ["original": "ゆるキャン△ OVA"])
        #expect(result == [用户多语言标题(lang: "und", title: "ゆるキャン△ OVA", latin: nil, official: true, main: true)])
    }
}
