import Testing
@testable import PaperVN

@Suite
struct 简介预览文本处理Tests {
    @Test
    func 移除任意语言的末尾署名行() {
        let cases = [
            ("正文\n\n[摘自官网]", "正文"),
            ("Body\n\n(Translated from the official website)", "Body"),
            ("本文\n\n［出典：公式サイト］", "本文"),
            ("본문\n\n【출처: 공식 웹사이트】", "본문"),
            ("正文\n\n（翻译自官网）", "正文")
        ]

        for (input, expected) in cases {
            #expect(简介预览文本处理.外部显示文本(input) == expected)
        }
    }

    @Test
    func 保留没有署名的普通末行() {
        let text = "第一段\n\n普通的最后一行"
        #expect(简介预览文本处理.外部显示文本(text) == text)
    }

    @Test
    func 在空白截断行上显示省略号() {
        let text = "第一行\n\n后续正文"
        #expect(
            简介预览文本处理.在截断空行显示省略号(
                text,
                lineIndex: 1
            ) == "第一行\n…"
        )
    }
}
