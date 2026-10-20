import Foundation
import Testing
@testable import PaperVN

@Suite
@MainActor
struct 作品匹配校准Tests {
    @Test func 手动匹配按已知ID找到目标平台的作品() {
        let manual = [作品对应组(类型: .anime, ids: [.bangumi: "12345", .myAnimeList: "999"])]
        let calibration = 作品匹配校准.shared
        #expect(calibration.平台ID(.myAnimeList, 类型: .anime, 已知: [.bangumi: "12345"], 手动: manual) == "999")
        #expect(calibration.查找(.bangumi, 平台ID: "12345", 类型: .anime, 手动: manual)?.键 == "mal-anime:999")
        // 动画和漫画分开，ID 相同也不能互相使用
        #expect(calibration.平台ID(.myAnimeList, 类型: .manga, 已知: [.bangumi: "12345"], 手动: manual) == nil)
        #expect(calibration.平台ID(.myAnimeList, 类型: .anime, 已知: [.bangumi: "1"], 手动: manual) == nil)
    }

    @Test func 手动匹配为附属条目时并入所选作品_不单独同步() {
        // Bangumi 77777 是 MAL 999 的特别篇
        let manual = [作品对应组(类型: .anime, ids: [.myAnimeList: "999"], 附属: [.bangumi: ["77777"]])]
        let calibration = 作品匹配校准.shared
        #expect(calibration.查找(.bangumi, 平台ID: "77777", 类型: .anime, 手动: manual) == 作品映射.结果(键: "mal-anime:999", 附属: true))
        #expect(calibration.查找(.myAnimeList, 平台ID: "999", 类型: .anime, 手动: manual) == 作品映射.结果(键: "mal-anime:999", 附属: false))
        // 附属条目不会被当成同一部作品去推送
        #expect(calibration.平台ID(.myAnimeList, 类型: .anime, 已知: [.bangumi: "77777"], 手动: manual) == nil)
    }

    @Test func 轻小说和漫画同属一组() {
        let manual = [作品对应组(类型: .lightNovel, ids: [.bangumi: "7", .myAnimeList: "8"])]
        #expect(作品匹配校准.shared.平台ID(.myAnimeList, 类型: .manga, 已知: [.bangumi: "7"], 手动: manual) == "8")
    }

    @Test func 输入编号或链接() {
        #expect(匹配候选编号("12345", 链接: "/subject/") == 12345)
        #expect(匹配候选编号("https://bgm.tv/subject/328609?from=1", 链接: "/subject/") == 328609)
        #expect(匹配候选编号("https://myanimelist.net/anime/5114/Fullmetal", 链接: "myanimelist.net/anime/") == 5114)
        #expect(匹配候选编号("鋼の錬金術師", 链接: "/subject/") == nil)
        #expect(匹配候选编号("0", 链接: "/subject/") == nil)
    }

    @Test func 提交内容不含目标平台和账户信息() throws {
        let work = 未匹配作品(
            键: "bangumi-anime:12345", 类型: .anime, 标题: "ある作品", 全部标题: ["Some Work", "ある作品"], 年份: 2020,
            已知ID: [.bangumi: "12345", .myAnimeList: "1"]
        )
        let item = 作品匹配校准.提交项(work, 平台: .myAnimeList)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any]
        #expect(json?["platform"] as? String == "myAnimeList")
        #expect(json?["kind"] as? String == "unmatched")
        #expect(json?["ids"] as? [String: String] == ["bangumi": "12345"])
        #expect(json?["titles"] as? [String] == ["ある作品", "Some Work"])
        let manual = 作品匹配校准.提交项(work, 平台: .myAnimeList, 手动匹配: 匹配候选(id: "42", 标题: "Aru Sakuhin"))
        let manualJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(manual)) as? [String: Any]
        #expect(manualJSON?["kind"] as? String == "manual")
        #expect(manualJSON?["suggestedID"] as? String == "42")
    }
}
