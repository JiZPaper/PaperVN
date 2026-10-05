import Foundation
import Testing
@testable import PaperVN

@Suite
struct 评论标记文本Tests {
    @Test
    func 普通文本不产生额外块() {
        let 结果 = 评论标记解析.解析("这部作品很好看")
        #expect(结果.块列表.count == 1)
        #expect(结果.块列表[0].类型 == .正文)
        #expect(结果.纯文本 == "这部作品很好看")
        #expect(结果.含剧透 == false)
    }

    @Test
    func 标题标签渲染成标题块而不是裸标签() {
        let 结果 = 评论标记解析.解析("[h1]总评[/h1]正文内容")
        #expect(结果.块列表.count == 2)
        #expect(结果.块列表[0].类型 == .标题(级别: 1))
        #expect(结果.块列表[0].纯文本 == "总评")
        #expect(结果.块列表[1].类型 == .正文)
        #expect(结果.块列表[1].纯文本 == "正文内容")
        #expect(!结果.纯文本.contains("[h1]"))
    }

    @Test
    func 行内样式标签转成样式开关() {
        let 结果 = 评论标记解析.解析("[b]很棒[/b]，[i]真的[/i]，[strike]算了[/strike]")
        let 片段 = 结果.块列表.flatMap(\.片段)
        #expect(片段.first { $0.文本 == "很棒" }?.样式.粗体 == true)
        #expect(片段.first { $0.文本 == "真的" }?.样式.斜体 == true)
        #expect(片段.first { $0.文本 == "算了" }?.样式.删除线 == true)
        #expect(!结果.纯文本.contains("["))
    }

    @Test
    func 剧透标签被标记且不丢失文字() {
        for 标记 in ["spoiler", "mask"] {
            let 结果 = 评论标记解析.解析("结局是[\(标记)]主角死了[/\(标记)]")
            #expect(结果.含剧透)
            #expect(结果.纯文本 == "结局是主角死了")
            let 剧透片段 = 结果.块列表.flatMap(\.片段).filter(\.样式.剧透)
            #expect(剧透片段.map(\.文本) == ["主角死了"])
        }
    }

    @Test
    func 未知标签按原文保留() {
        let 结果 = 评论标记解析.解析("笑死了[笑][随便写的]")
        #expect(结果.纯文本 == "笑死了[笑][随便写的]")
    }

    @Test
    func 带地址与不带地址的链接都能识别() {
        let 带参数 = 评论标记解析.解析("[url=https://vndb.org]看这里[/url]")
        let 参数片段 = 带参数.块列表.flatMap(\.片段)
        #expect(参数片段.first?.文本 == "看这里")
        #expect(参数片段.first?.样式.链接?.absoluteString == "https://vndb.org")

        let 裸地址 = 评论标记解析.解析("[url]https://vndb.org/v11[/url]")
        let 地址片段 = 裸地址.块列表.flatMap(\.片段)
        #expect(地址片段.first?.样式.链接?.absoluteString == "https://vndb.org/v11")
    }

    @Test
    func 列表标签拆成列表项块() {
        let 结果 = 评论标记解析.解析("[list][*]剧情好[*]音乐好[/list]")
        #expect(结果.块列表.count == 2)
        #expect(结果.块列表[0].类型 == .列表项(标号: nil))
        #expect(结果.块列表[0].纯文本 == "剧情好")
        #expect(结果.块列表[1].纯文本 == "音乐好")
    }

    @Test
    func 有序列表带序号() {
        let 结果 = 评论标记解析.解析("[olist][*]第一[*]第二[/olist]")
        #expect(结果.块列表[0].类型 == .列表项(标号: "1."))
        #expect(结果.块列表[1].类型 == .列表项(标号: "2."))
    }

    @Test
    func 图片标签不把地址当正文输出() {
        let 结果 = 评论标记解析.解析("[img]https://example.com/a.png[/img]")
        #expect(结果.isEmpty)
    }

    @Test
    func 原样标签内部不再解析() {
        let 结果 = 评论标记解析.解析("[noparse][b]x[/b][/noparse]")
        #expect(结果.纯文本 == "[b]x[/b]")

        let 代码 = 评论标记解析.解析("[code][b]y[/b][/code]")
        #expect(代码.块列表.count == 1)
        #expect(代码.块列表[0].类型 == .代码)
        #expect(代码.块列表[0].纯文本 == "[b]y[/b]")
    }

    @Test
    func 引用与分隔线各自成块() {
        let 结果 = 评论标记解析.解析("[quote]原话[/quote][hr]我的看法")
        #expect(结果.块列表.count == 3)
        #expect(结果.块列表[0].类型 == .引用)
        #expect(结果.块列表[1].类型 == .分隔线)
        #expect(结果.块列表[2].纯文本 == "我的看法")
    }

    @Test
    func 只影响外观的标签被移除() {
        let 结果 = 评论标记解析.解析("[color=red][size=3]很好[/size][/color]")
        #expect(结果.纯文本 == "很好")
    }

    @Test
    func 未闭合的方括号不会吃掉文字() {
        let 结果 = 评论标记解析.解析("评分[b未闭合\n下一行")
        #expect(结果.纯文本.contains("[b未闭合"))
        #expect(结果.纯文本.contains("下一行"))
    }
}
