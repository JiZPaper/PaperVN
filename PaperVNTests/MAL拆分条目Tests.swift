import Foundation
import Testing
@testable import PaperVN

/// MAL 55357（劇場総集編ぼっち・ざ・ろっく！，2 集）拆成 Re:（mal-anime:55357）和 Re:Re:（aniList-anime:171099）。
@Suite
@MainActor
struct MAL拆分条目Tests {
    private let re = "mal-anime:55357"
    private let reRe = "aniList-anime:171099"

    private func MAL记录(_ status: 资料库状态, score: Int? = nil, progress: Int? = nil) -> 平台资料库记录 {
        平台资料库记录(
            平台: .myAnimeList,
            平台ID: "55357",
            类型: .anime,
            malID: 55357,
            标题: "Bocchi the Rock! Movie",
            日文标题: "劇場総集編ぼっち・ざ・ろっく！",
            封面地址: "https://example.com/cover.jpg",
            快照: 同步快照(状态: status, 评分: score, 进度: progress),
            总数: 2,
            平均评分: 85,
            发行日期: "2024-06-07",
            开始日期: "2024-06-08",
            完成日期: "2024-08-10",
            修改时间: nil
        )
    }

    private func 拆开(_ record: 平台资料库记录, 基线: [String: 同步快照] = [:]) -> [String: 平台资料库记录] {
        Dictionary(uniqueKeysWithValues: MAL拆分条目.拆开(record, 基线: 基线).map { ($0.键, $0) })
    }

    private var parts: [作品映射.拆分部分] { 作品映射.MAL拆分(55357, 类型: .anime) ?? [] }

    @Test func 映射里有拆分() {
        #expect(parts.map(\.键) == [re, reRe])
        #expect(作品映射.平台ID(reRe, 平台: .myAnimeList, 类型: .anime) == "55357#2")
        #expect(作品映射.查找(.myAnimeList, 平台ID: "55357#2", 类型: .anime)?.键 == reRe)
        #expect(作品映射.平台ID(reRe, 平台: .annict, 类型: .anime) == 作品映射.Annict节点ID("11308"))
        #expect(作品映射.平台ID(reRe, 平台: .bangumi, 类型: .anime) == "459642")
    }

    @Test func 看完两集() {
        let records = 拆开(MAL记录(.completed, score: 80, progress: 2))
        #expect(records[re]?.快照 == 同步快照(状态: .completed, 评分: 80, 进度: 1))
        #expect(records[reRe]?.快照 == 同步快照(状态: .completed, 评分: 80, 进度: 1))
        #expect(records[re]?.平台ID == "55357#1" && records[reRe]?.平台ID == "55357#2")
        #expect(records[re]?.malID == 55357 && records[reRe]?.malID == nil)
        // 标题是各部自己的（AniList 的原名、罗马字、英文），不是 MAL 合在一起的条目的
        #expect(records[re]?.日文标题 == "ぼっち・ざ・ろっく！Re:" && records[re]?.标题 == "Bocchi the Rock! Re:")
        #expect(records[reRe]?.日文标题 == "ぼっち・ざ・ろっく！ Re:Re:")
        #expect(records[reRe]?.多语言标题.first { $0.main }?.lang == "ja")
        #expect(records[re]?.多语言标题.contains { $0.title == "劇場総集編ぼっち・ざ・ろっく！" || $0.title == "Bocchi the Rock! Movie" } == false)
        #expect(records[re]?.开始日期 == "2024-06-08" && records[re]?.完成日期 == nil)
        #expect(records[reRe]?.开始日期 == nil && records[reRe]?.完成日期 == "2024-08-10")
    }

    @Test func 在看第一集看完() {
        let records = 拆开(MAL记录(.inProgress, progress: 1))
        #expect(records[re]?.快照.状态 == .completed)
        #expect(records[reRe]?.快照 == 同步快照(状态: .inProgress, 评分: nil, 进度: nil))
    }

    @Test func 弃坑时没看完的也是弃坑() {
        let records = 拆开(MAL记录(.dropped, progress: 1))
        #expect(records[re]?.快照.状态 == .completed)
        #expect(records[reRe]?.快照.状态 == .dropped)
        let planned = 拆开(MAL记录(.planning))
        #expect(planned[re]?.快照.状态 == .planning && planned[reRe]?.快照.状态 == .planning)
    }

    @Test func 合并状态与进度() {
        let done = 同步快照(状态: .completed, 评分: 80, 进度: 1)
        #expect(MAL拆分条目.合并([done, done], parts) == 同步快照(状态: .completed, 评分: 80, 进度: 2))
        // 只看完一部算在看
        #expect(MAL拆分条目.合并([done, nil], parts) == 同步快照(状态: .inProgress, 评分: 80, 进度: 1))
        #expect(MAL拆分条目.合并([done, 同步快照(状态: .planning, 评分: nil, 进度: nil)], parts)?.状态 == .inProgress)
        #expect(MAL拆分条目.合并([done, 同步快照(状态: .dropped, 评分: nil, 进度: nil)], parts)?.状态 == .dropped)
        #expect(MAL拆分条目.合并([nil, nil], parts) == nil)
    }

    @Test func 评分不同时不改MAL的评分() {
        let combined = MAL拆分条目.合并([
            同步快照(状态: .completed, 评分: 80, 进度: 1),
            同步快照(状态: .completed, 评分: 90, 进度: 1),
        ], parts)
        #expect(combined == 同步快照(状态: .completed, 评分: nil, 进度: 2))
        #expect(MAL拆分条目.相符(combined!, 同步快照(状态: .completed, 评分: 70, 进度: 2)))
    }

    @Test func MAL没改过时沿用基线() {
        // 上次写回时两部分数不同，MAL 上仍是原来的 70 分：拆开后各部保持 80、90，不会被 MAL 的 70 覆盖
        let base = [
            re: 同步快照(状态: .completed, 评分: 80, 进度: 1),
            reRe: 同步快照(状态: .completed, 评分: 90, 进度: 1),
        ]
        let records = 拆开(MAL记录(.completed, score: 70, progress: 2), 基线: base)
        #expect(records[re]?.快照.评分 == 80 && records[reRe]?.快照.评分 == 90)
        // MAL 上改过（改成弃坑）：按集数重新分配
        let changed = 拆开(MAL记录(.dropped, score: 70, progress: 1), 基线: base)
        #expect(changed[re]?.快照 == 同步快照(状态: .completed, 评分: 70, 进度: 1))
        #expect(changed[reRe]?.快照.状态 == .dropped)
    }

    @Test func 拆开再合并不变() {
        let cases: [同步快照] = [
            同步快照(状态: .completed, 评分: 80, 进度: 2),
            同步快照(状态: .inProgress, 评分: nil, 进度: 1),
            同步快照(状态: .inProgress, 评分: 60, 进度: nil),
            同步快照(状态: .planning, 评分: nil, 进度: nil),
            同步快照(状态: .onHold, 评分: nil, 进度: 1),
            同步快照(状态: .dropped, 评分: 30, 进度: nil),
        ]
        for value in cases {
            let split = MAL拆分条目.按集数分配(value, parts)
            let combined = MAL拆分条目.合并(split, parts)
            #expect(combined.map { MAL拆分条目.相符($0, value) } == true, "\(value)")
        }
    }

    @Test func 详情页不按合在一起的MAL条目打开() {
        let reEntry = 本地资料库条目(id: re, 类型: .anime, 平台ID: [.myAnimeList: "55357#1"], 标题: "Bocchi the Rock! Re:", 加入时间: .now)
        let target = reEntry.详情目标(标题: "")
        #expect(target?.malID == 0 && target?.aniListID == 165253 && target?.bangumiID == 436738)
        #expect(target?.作品键 == re)
        // 还没同步过（资料库里记着整条 MAL ID）也一样
        let old = 本地资料库条目(id: re, 类型: .anime, 平台ID: [.myAnimeList: "55357"], 标题: "", 加入时间: .now)
        #expect(old.详情目标(标题: "")?.aniListID == 165253)
        let reReEntry = 本地资料库条目(id: reRe, 类型: .anime, 平台ID: [.myAnimeList: "55357#2"], 标题: "", 加入时间: .now)
        #expect(reReEntry.详情目标(标题: "")?.aniListID == 171099 && reReEntry.详情目标(标题: "")?.bangumiID == 459642)
        #expect(reReEntry.详情目标(标题: "")?.作品键 == reRe)
    }

    @Test func SummerPockets剧场编辑版拆成四部() {
        let parts = 作品映射.MAL拆分(61926, 类型: .anime) ?? []
        #expect(parts.map(\.键) == ["mal-anime:61926", "aniList-anime:206609", 作品映射.查找(.aniList, 平台ID: "206610", 类型: .anime)?.键, "aniList-anime:206611"])
        #expect(parts.map(\.标题) == ["Summer Pockets 久島鴎編", "Summer Pockets 紬ヴェンダース編", "Summer Pockets 空門蒼編", "Summer Pockets 鳴瀬しろは編"])
        // Annict 16331 是空門蒼編，不再算到久島鴎編上
        #expect(作品映射.查找(.annict, 平台ID: 作品映射.Annict节点ID("16331"), 类型: .anime)?.键 == parts[2].键)
        #expect(作品映射.平台ID(parts[0].键, 平台: .tmdb, 类型: .anime) == "movie/1531742")
        // MAL 上看到第 2 集：前两部看完，后两部还在计划
        var record = MAL记录(.planning, progress: 2)
        record = 平台资料库记录(
            平台: .myAnimeList, 平台ID: "61926", 类型: .anime, malID: 61926, 标题: "Summer Pockets Movie", 日文标题: nil, 封面地址: nil,
            快照: record.快照, 总数: 4, 平均评分: nil, 发行日期: nil, 开始日期: nil, 完成日期: nil, 修改时间: nil
        )
        let split = MAL拆分条目.拆开(record, 基线: [:])
        #expect(split.map(\.快照.状态) == [.completed, .completed, .planning, .planning])
    }

    @Test func 不需要拆分的记录原样返回() {
        var record = MAL记录(.completed)
        record = 平台资料库记录(
            平台: .myAnimeList, 平台ID: "5114", 类型: .anime, malID: 5114, 标题: "FMA", 日文标题: nil, 封面地址: nil,
            快照: record.快照, 总数: 64, 平均评分: nil, 发行日期: nil, 开始日期: nil, 完成日期: nil, 修改时间: nil
        )
        #expect(MAL拆分条目.拆开(record, 基线: [:]) == [record])
    }
}
