import Foundation
import Testing
@testable import PaperVN

/// 期望值来自生成模型时的规范化规则；两侧规则不一致时模型会在 App 里失效。
struct 智能搜索名称规范化Tests {
    private let 变音映射: [Unicode.Scalar: [Unicode.Scalar]] = [
        "é": ["e"], "ō": ["o"], "ß": ["s", "s"], "ς": ["σ"],
    ]

    private func 规范化(_ 文本: String) -> String {
        String(String.UnicodeScalarView(
            智能搜索名称索引.规范化(文本, 变音映射: 变音映射)
        ))
    }

    @Test
    func 罗马字长音写法折叠成同一形式() {
        #expect(规范化("Ｔｏｈｓａｋａ　Ｒｉｎ") == "tosakarin")
        #expect(规范化("Toosaka Rin") == "tosakarin")
        #expect(规范化("Café Ōkami") == "cafeokami")
        #expect(规范化("Steins;Gate") == "steinsgate")
    }

    @Test
    func 片假名转平假名并去掉长音符() {
        #expect(规范化("トウサカ") == "とうさか")
        #expect(规范化("サマーポケッツ") == "さまぽけっつ")
    }

    @Test
    func 特殊字母按映射折叠() {
        #expect(规范化("Straße") == "strasse")
        #expect(规范化("ΟΔΟΣ") == "οδοσ")
    }

    @Test
    func 单个汉字也值得搜索() {
        #expect(智能搜索视图模型.值得搜索("猫"))
        #expect(!智能搜索视图模型.值得搜索("a"))
        #expect(智能搜索视图模型.值得搜索("ab"))
        #expect(!智能搜索视图模型.值得搜索("  "))
    }
}

/// 用 App 预装的模型搜索：输错、同音字、假名读音也要找到作品。
struct 智能搜索引擎Tests {
    private func 前五(_ 文本: String) async throws -> [String] {
        try await 智能搜索引擎.shared.搜索(文本).命中.prefix(5).map(\.编号)
    }

    @Test
    func 中文同音字() async throws {
        #expect(try await 前五("命运石之们").contains("v2002"))
    }

    @Test
    func 假名读音对上罗马字标题() async throws {
        #expect(try await 前五("ひぐらしのなくころに").contains("v67"))
    }

    @Test
    func 拉丁字母换位() async throws {
        #expect(try await 前五("steins gaet").contains("v2002"))
    }
}
