import Testing
@testable import PaperVN

@MainActor
struct 综合搜索合并Tests {
    private func 作品(_ mal: Int, _ type: 作品类型 = .anime) -> 作品搜索结果 {
        作品搜索结果(
            id: 作品搜索结果.编号(类型: type, malID: mal),
            类型: type,
            malID: mal,
            标题: "作品\(mal)",
            多语言标题: []
        )
    }

    private func 命中(_ 编号: String, _ 类型: 智能搜索条目类型) -> 智能搜索命中 {
        智能搜索命中(类型: 类型, 编号: 编号, 概率: 0.5, 名称匹配: true, 系列: nil, 所属作品: nil)
    }

    @Test
    func Hiro智能找到的作品在前_平台搜到的接在后面且不重复() {
        var 输入 = 综合搜索合并.输入()
        输入.智能搜索命中 = [命中("n9115", .轻小说), 命中("a10495", .动画)]
        for item in [作品(9115, .lightNovel), 作品(10495), 作品(20)] { 输入.动画漫画[item.id] = item }
        输入.在线作品顺序 = ["a20", "a10495", "a999"]
        let ids = 综合搜索合并.合并(输入).map(\.id)
        // a999 没有详情，不显示
        #expect(ids == ["n9115", "a10495", "a20"])
    }

    @Test
    func 不按相关程度时动画漫画接在最后() {
        var 输入 = 综合搜索合并.输入()
        输入.按相关程度 = false
        输入.智能搜索命中 = [命中("a10495", .动画)]
        for item in [作品(10495), 作品(20)] { 输入.动画漫画[item.id] = item }
        输入.在线作品顺序 = ["a20"]
        #expect(综合搜索合并.合并(输入).map(\.id) == ["a20"])
    }

    @Test
    func 同系列的动画叠在排在最前面的那部下面() {
        var 输入 = 综合搜索合并.输入()
        // ゆるゆり♪♪（12403）排在第一，ゆるゆり（10495）是同一系列，Summer Pockets（50694）不是
        输入.智能搜索命中 = [命中("a12403", .动画), 命中("a50694", .动画), 命中("a10495", .动画)]
        for item in [作品(12403), 作品(50694), 作品(10495)] { 输入.动画漫画[item.id] = item }
        let 条目 = 综合搜索合并.合并(输入)
        #expect(条目.map(\.id) == ["a12403", "a50694"])
        if case let .动画漫画(组) = 条目.first {
            #expect(组.同系列.map(\.id) == ["a10495"])
        } else {
            Issue.record("第一个条目不是动画")
        }
    }

    @Test
    func 编号前缀区分动画漫画轻小说() {
        #expect(作品搜索结果.编号(类型: .anime, malID: 1) == "a1")
        #expect(作品搜索结果.编号(类型: .manga, malID: 1) == "m1")
        #expect(作品搜索结果.编号(类型: .lightNovel, malID: 1) == "n1")
    }
}

struct Hiro智能动画漫画Tests {
    @Test
    func 内置模型能找到动画漫画与轻小说() async throws {
        let 引擎 = 智能搜索引擎.shared
        for (查询, 目标) in [("孤独摇滚", "a47917"), ("摇曳百合", "a10495"), ("电锯人", "m116778"), ("败犬女主太多了", "n138481"), ("石头门", "v2002"), ("sp", "a50694"), ("sp", "v20424"), ("asobi no kankei", "n193341"), ("asobi no kankei", "m196717"), ("nine", "v19829"), ("萝卜子", "v27448"), ("少女波子汽水", "a32587"), ("euphoria", "a10851"), ("今天开始当女子小学生", "m2147585092")] {
            let 结果 = try await 引擎.搜索(查询)
            #expect(结果.命中.prefix(5).contains { $0.编号 == 目标 }, "\(查询)")
        }
        let 动画 = try await 引擎.搜索("孤独摇滚")
        #expect(动画.命中.first?.类型 == .动画)
    }
}
