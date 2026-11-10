import Testing
@testable import PaperVN

/// 需要网络：漫画还是轻小说向公开接口读取，不需要登录任何平台。
@MainActor
struct 书籍类型判定网络Tests {
    private func 条目(_ id: String, _ type: 作品类型, _ ids: [资料库平台: String] = [:]) -> 本地资料库条目 {
        本地资料库条目(id: id, 类型: type, 平台ID: ids, 标题: id, 加入时间: nil)
    }

    @Test
    func 分错的漫画和轻小说都能改正() async {
        let entries = [
            // 欢迎来到实力至上主义的教室 2年级篇（轻小说），曾被记成漫画
            条目("mal-manga:123992", .manga),
            // 剑风传奇（漫画）
            条目("mal-manga:2", .lightNovel),
            // 只有 AniList ID
            条目("aniList-manga:115166", .manga, [.aniList: "115166"]),
            // 只在 Bangumi 上：第一次的亲密接触（小说）；エマノン・シリーズ（漫画，带“小说改”标签）
            条目("bangumi-manga:1", .manga, [.bangumi: "1"]),
            条目("bangumi-manga:105850", .lightNovel, [.bangumi: "105850"]),
        ]
        let types = await 书籍类型判定.读取(entries)
        #expect(types["mal-manga:123992"] == .lightNovel)
        #expect(types["mal-manga:2"] == .manga)
        #expect(types["aniList-manga:115166"] == .lightNovel)
        #expect(types["bangumi-manga:1"] == .lightNovel)
        #expect(types["bangumi-manga:105850"] == .manga)

        // 读到的结果存在磁盘上，资料库读盘时不联网也能改正
        var cached = entries
        书籍类型判定.改正(&cached)
        #expect(cached.map(\.类型) == [.lightNovel, .manga, .lightNovel, .lightNovel, .manga])
    }

    @Test
    func 动画不受影响() async {
        let types = await 书籍类型判定.读取([条目("mal-anime:5114", .anime)])
        #expect(types.isEmpty)
    }
}
