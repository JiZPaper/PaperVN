import Testing
@testable import PaperVN

/// 需要网络：没有 MAL ID 的作品也能搜到、能打开详情。
@MainActor
struct 作品聚合搜索网络Tests {
    @Test
    func 只在AniList上的漫画能搜到也能读取详情() async throws {
        let 结果 = await 作品聚合搜索.shared.在线搜索("女子小学生はじめました")
        let 漫画 = 结果.first { $0.aniListID == 101444 }
        #expect(漫画 != nil, "\(结果.map { ($0.id, $0.标题) })")
        let detail = try await 作品详情服务.shared.详情(kind: .manga, aniListID: 101444, bangumiID: nil)
        #expect(!detail.标题.isEmpty)
        #expect(detail.bangumiID == 61272)
    }

    @Test
    func Hiro智能命中的AniList编号能取到标题() async {
        let id = 作品搜索结果.编号(类型: .manga, malID: 0, aniListID: 101444)
        let 详情 = await 作品聚合搜索.shared.详情([id])
        #expect(详情[id]?.aniListID == 101444)
    }

    @Test
    func 只在Bangumi上的作品能读取详情() async throws {
        // 国产动画等只在 Bangumi 上的条目
        let detail = try await 作品详情服务.shared.详情(kind: .manga, aniListID: nil, bangumiID: 1)
        #expect(!detail.标题.isEmpty)
    }
}
