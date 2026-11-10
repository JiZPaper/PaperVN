import Testing
@testable import PaperVN

@MainActor
struct Spotlight索引Tests {
    @Test func 视觉小说打开VNDB编号() {
        let entry = 本地资料库条目(id: "vn:v17", 类型: .visualNovel, 平台ID: [.vndb: "v17"], 标题: "Ever17", 加入时间: nil)
        #expect(entry.Spotlight路由(标题: "Ever17") == .visualNovel("v17"))
    }

    @Test func 轻小说打开作品详情并保留类型() throws {
        let entry = 本地资料库条目(id: "mal-manga:21", 类型: .lightNovel, 平台ID: [.myAnimeList: "21"], 标题: "Book", 加入时间: nil)
        guard case .work(let target) = entry.Spotlight路由(标题: "显示名") else {
            Issue.record("应打开作品详情")
            return
        }
        #expect(target.malID == 21)
        #expect(target.标题 == "显示名")
        #expect(target.类型 == .lightNovel)
    }

    @Test func 其他语言名称的条目打开同一部作品() {
        #expect(Spotlight索引.条目ID(标识符: "mal-anime:52991\u{1F}Frieren") == "mal-anime:52991")
        #expect(Spotlight索引.条目ID(标识符: "vn:v17") == "vn:v17")
    }

    @Test func 只写入含假名的词() {
        #expect(Spotlight索引.假名词语("葬送のフリーレン").contains("フリーレン"))
        #expect(!Spotlight索引.假名词语("葬送のフリーレン").contains("葬送"))
        #expect(!Spotlight索引.假名词语("葬送のフリーレン").contains("の"))
        #expect(Spotlight索引.假名词语("【推しの子】").contains("推し"))
        #expect(Spotlight索引.假名词语("葬送的芙莉莲").isEmpty)
        #expect(Spotlight索引.假名词语("Sousou no Frieren").isEmpty)
    }

    @Test func 没有平台编号的作品没有路由() {
        let vn = 本地资料库条目(id: "vn:", 类型: .visualNovel, 平台ID: [:], 标题: "A", 加入时间: nil)
        let anime = 本地资料库条目(id: "other", 类型: .anime, 平台ID: [:], 标题: "B", 加入时间: nil)
        #expect(vn.Spotlight路由(标题: "A") == nil)
        #expect(anime.Spotlight路由(标题: "B") == nil)
    }
}
