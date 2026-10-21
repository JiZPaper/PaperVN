import Foundation
import Testing
@testable import PaperVN

@Suite
@MainActor
struct PaperVNSync合并Tests {
    // MARK: 构造数据

    private func 记录(
        _ platform: 资料库平台,
        mal: Int,
        _ status: 资料库状态,
        score: Int? = nil,
        progress: Int? = nil,
        type: 作品类型 = .anime
    ) -> 平台资料库记录 {
        平台资料库记录(
            平台: platform,
            平台ID: platform == .myAnimeList ? String(mal) : "\(platform.rawValue)-\(mal)",
            类型: type,
            malID: mal,
            标题: "作品\(mal)",
            日文标题: nil,
            封面地址: nil,
            快照: 同步快照(状态: status, 评分: score, 进度: progress),
            总数: nil,
            平均评分: nil,
            发行日期: nil,
            开始日期: nil,
            完成日期: nil,
            修改时间: nil
        )
    }

    private func 资料库(_ platform: 资料库平台, account: String = "1", _ records: [平台资料库记录]) -> 平台资料库 {
        平台资料库(平台: platform, 账户ID: account, 账户名称: "user", 记录: records)
    }

    private func 基线(_ library: 平台资料库) -> 平台基线 {
        平台基线(账户ID: library.账户ID, 账户名称: library.账户名称, 快照: library.记录.mapValues(\.快照))
    }

    private func 本地(from records: [平台资料库记录]) -> [String: 本地资料库条目] {
        Dictionary(uniqueKeysWithValues: records.map { record in
            var entry = 本地资料库条目(
                id: record.键,
                类型: record.类型,
                平台ID: [record.平台: record.平台ID],
                标题: record.标题,
                加入时间: nil
            )
            entry.状态 = record.快照.状态
            entry.评分 = record.快照.评分
            entry.进度 = record.快照.进度
            return (record.键, entry)
        })
    }

    private func 键(_ mal: Int) -> String { "mal-anime:\(mal)" }

    // MARK: 新账户

    @Test
    func 新账户内容不同时要求选择导入方式() {
        let mal = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed, score: 80, progress: 12)])
        let ani = 资料库(.aniList, [记录(.aniList, mal: 1, .inProgress, score: 80, progress: 5)])
        var session = 同步会话(
            本地: 本地(from: Array(mal.记录.values)),
            平台: [.myAnimeList: mal, .aniList: ani],
            基线: [.myAnimeList: 基线(mal)],
            待推送: [:]
        )
        同步合并.检查导入方式(&session)
        #expect(session.需要选择导入方式)
        #expect(session.来源概况.map(\.来源).contains(.平台(.aniList)))
    }

    @Test
    func 新账户内容一致时不打扰用户() {
        let mal = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed, score: 80, progress: 12)])
        // AniList 精度更高，但按 MAL 的精度比较是一样的
        let ani = 资料库(.aniList, [记录(.aniList, mal: 1, .completed, score: 78, progress: 12)])
        var session = 同步会话(
            本地: 本地(from: Array(mal.记录.values)),
            平台: [.myAnimeList: mal, .aniList: ani],
            基线: [.myAnimeList: 基线(mal)],
            待推送: [:]
        )
        同步合并.检查导入方式(&session)
        #expect(!session.需要选择导入方式)
    }

    @Test
    func 合并时记录不同的作品生成冲突_只在一边的作品自动加入() {
        let mal = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed, progress: 12)])
        let ani = 资料库(.aniList, [
            记录(.aniList, mal: 1, .inProgress, progress: 5),
            记录(.aniList, mal: 2, .planning),
        ])
        var session = 同步会话(
            本地: 本地(from: Array(mal.记录.values)),
            平台: [.myAnimeList: mal, .aniList: ani],
            基线: [.myAnimeList: 基线(mal)],
            待推送: [:]
        )
        session.导入方式 = .合并
        同步合并.合并(&session)
        #expect(session.冲突.map(\.键) == [键(1)])
        #expect(session.结果[键(2)] == .保留(同步快照(状态: .planning, 评分: nil, 进度: nil)))

        // 选 AniList 的记录后，MAL 要改，作品 2 也要加到 MAL
        session.冲突[0].选择 = .平台(.aniList)
        同步合并.应用冲突选择(&session)
        同步合并.生成推送(&session)
        let malOperations = session.推送.filter { $0.平台 == .myAnimeList }
        #expect(Set(malOperations.map(\.种类)) == [.修改, .新增])
        #expect(session.需要确认推送)
    }

    @Test
    func 以一个账户为准时删除其他平台多出的作品() {
        let mal = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed)])
        let ani = 资料库(.aniList, [
            记录(.aniList, mal: 1, .completed),
            记录(.aniList, mal: 2, .dropped),
        ])
        var session = 同步会话(本地: [:], 平台: [.myAnimeList: mal, .aniList: ani], 基线: [:], 待推送: [:])
        session.导入方式 = .为准(.平台(.myAnimeList))
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(session.结果[键(2)] == .删除)
        #expect(session.推送.contains { $0.平台 == .aniList && $0.种类 == .删除 && $0.键 == 键(2) })
        #expect(同步合并.新资料库(session)[键(2)] == nil)
    }

    @Test
    func 分别保留时其他账户多出的作品隐藏且不删除() {
        let mal = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed)])
        let ani = 资料库(.aniList, [
            记录(.aniList, mal: 1, .completed),
            记录(.aniList, mal: 2, .dropped),
        ])
        var session = 同步会话(本地: [:], 平台: [.myAnimeList: mal, .aniList: ani], 基线: [:], 待推送: [:])
        session.导入方式 = .分别保留(.平台(.myAnimeList))
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(session.新隐藏[键(2)] == [.aniList])
        #expect(session.推送.isEmpty)
        #expect(同步合并.新资料库(session)[键(2)] == nil)
        #expect(同步合并.新资料库(session)[键(1)] != nil)
    }

    // MARK: 已同步过的账户

    @Test
    func 平台上的修改需要确认_采用后推送到其他平台() {
        let malBefore = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .inProgress, progress: 3)])
        let aniBefore = 资料库(.aniList, [记录(.aniList, mal: 1, .inProgress, progress: 3)])
        let malNow = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .inProgress, progress: 4)])
        var session = 同步会话(
            本地: 本地(from: Array(malBefore.记录.values)),
            平台: [.myAnimeList: malNow, .aniList: aniBefore],
            基线: [.myAnimeList: 基线(malBefore), .aniList: 基线(aniBefore)],
            待推送: [:]
        )
        同步合并.合并(&session)
        #expect(session.冲突.first?.种类 == .外部更改)
        #expect(Set(session.冲突.first?.版本.map(\.来源) ?? []) == [.本地, .平台(.myAnimeList)])
        session.冲突[0].选择 = .平台(.myAnimeList)
        同步合并.应用冲突选择(&session)
        同步合并.生成推送(&session)
        #expect(session.推送.map(\.平台) == [.aniList])
        #expect(session.推送.first?.目标?.进度 == 4)
        #expect(!session.需要确认推送)
    }

    @Test
    func 两个平台改得不一样时生成冲突() {
        let before = [记录(.myAnimeList, mal: 1, .inProgress, progress: 3)]
        let malBefore = 资料库(.myAnimeList, before)
        let aniBefore = 资料库(.aniList, [记录(.aniList, mal: 1, .inProgress, progress: 3)])
        var session = 同步会话(
            本地: 本地(from: before),
            平台: [
                .myAnimeList: 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .inProgress, progress: 4)]),
                .aniList: 资料库(.aniList, [记录(.aniList, mal: 1, .dropped, progress: 3)]),
            ],
            基线: [.myAnimeList: 基线(malBefore), .aniList: 基线(aniBefore)],
            待推送: [:]
        )
        同步合并.合并(&session)
        #expect(session.冲突.count == 1)
        #expect(session.冲突.first?.种类 == .记录不同)
    }

    @Test
    func 平台上单独删除也要确认() {
        let malBefore = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed)])
        var session = 同步会话(
            本地: 本地(from: Array(malBefore.记录.values)),
            平台: [.myAnimeList: 资料库(.myAnimeList, [])],
            基线: [.myAnimeList: 基线(malBefore)],
            待推送: [:]
        )
        同步合并.合并(&session)
        #expect(session.冲突.first?.种类 == .外部更改)
        #expect(session.冲突.first?.版本.contains { $0.来源 == .平台(.myAnimeList) && $0.快照 == nil } == true)
    }

    @Test
    func 平台上新增的作品需要确认_不采用时从平台删除() {
        let malBefore = 资料库(.myAnimeList, [])
        let malNow = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 5, .planning)])
        var session = 同步会话(
            本地: [:],
            平台: [.myAnimeList: malNow],
            基线: [.myAnimeList: 基线(malBefore)],
            待推送: [:]
        )
        同步合并.合并(&session)
        #expect(session.冲突.first?.版本.contains { $0.来源 == .本地 && $0.快照 == nil } == true)
        session.冲突[0].选择 = .本地
        同步合并.应用冲突选择(&session)
        同步合并.生成推送(&session)
        #expect(session.推送.first?.种类 == .删除)
    }

    @Test
    func 资料库大量减少时先提示() {
        let records = (1...30).map { 记录(.myAnimeList, mal: $0, .completed) }
        let before = 资料库(.myAnimeList, records)
        var session = 同步会话(
            本地: 本地(from: records),
            平台: [.myAnimeList: 资料库(.myAnimeList, [])],
            基线: [.myAnimeList: 基线(before)],
            待推送: [:]
        )
        同步合并.检查减少(&session)
        #expect(session.减少提示.first?.上次数量 == 30)

        // 选择“保留并重新上传”后不再逐项询问，全部重新上传
        session.减少处理[.myAnimeList] = .保留并重新上传
        同步合并.忽略保留平台的删除(&session)
        同步合并.合并(&session)
        #expect(session.冲突.isEmpty)
        同步合并.生成推送(&session)
        #expect(session.推送.filter { $0.种类 == .新增 }.count == 30)
    }

    @Test
    func 换了账户按新账户处理() {
        let records = [记录(.myAnimeList, mal: 1, .completed)]
        let oldAccount = 资料库(.myAnimeList, account: "1", records)
        let newAccount = 资料库(.myAnimeList, account: "2", [记录(.myAnimeList, mal: 2, .planning)])
        var session = 同步会话(
            本地: 本地(from: records),
            平台: [.myAnimeList: newAccount],
            基线: [.myAnimeList: 基线(oldAccount)],
            待推送: [:]
        )
        同步合并.检查减少(&session)
        #expect(session.减少提示.isEmpty)
        同步合并.检查导入方式(&session)
        #expect(session.需要选择导入方式)
        #expect(session.来源概况.first { $0.来源 == .平台(.myAnimeList) }?.账户已更换 == true)
    }

    @Test
    func 本地修改待推送时覆盖没有变化的平台() {
        let records = [记录(.myAnimeList, mal: 1, .inProgress, progress: 3)]
        let mal = 资料库(.myAnimeList, records)
        var local = 本地(from: records)
        local[键(1)]?.进度 = 6
        var session = 同步会话(
            本地: local,
            平台: [.myAnimeList: mal],
            基线: [.myAnimeList: 基线(mal)],
            待推送: [键(1): [.myAnimeList]]
        )
        同步合并.合并(&session)
        #expect(session.冲突.isEmpty)
        同步合并.生成推送(&session)
        #expect(session.推送.first?.目标?.进度 == 6)
    }

    @Test
    func Annict只比较观看状态() {
        let records = [记录(.myAnimeList, mal: 1, .inProgress, score: 70, progress: 3)]
        let mal = 资料库(.myAnimeList, records)
        let annict = 资料库(.annict, [记录(.annict, mal: 1, .inProgress)])
        var session = 同步会话(
            本地: 本地(from: records),
            平台: [.myAnimeList: mal, .annict: annict],
            基线: [.myAnimeList: 基线(mal)],
            待推送: [:]
        )
        同步合并.检查导入方式(&session)
        #expect(!session.需要选择导入方式)
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(session.推送.isEmpty)
        // 采用 Annict 的状态时，评分和进度沿用资料库的值
        #expect(同步合并.新资料库(session)[键(1)]?.进度 == 3)
    }

    // MARK: Bangumi

    @Test
    func Bangumi只导入_不写入也不删除() {
        let mal = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed)])
        let bangumi = 资料库(.bangumi, [
            记录(.bangumi, mal: 1, .completed),
            记录(.bangumi, mal: 2, .dropped),
        ])
        var session = 同步会话(本地: [:], 平台: [.myAnimeList: mal, .bangumi: bangumi], 基线: [:], 待推送: [:])
        session.导入方式 = .为准(.平台(.myAnimeList))
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(!session.推送.contains { $0.平台 == .bangumi })
        #expect(session.无法删除[.bangumi] == nil)
    }

    @Test
    func Bangumi上的作品导入资料库_资料库的修改不写回Bangumi() {
        let bangumiRecords = [记录(.bangumi, mal: 1, .inProgress, progress: 3), 记录(.bangumi, mal: 2, .planning)]
        let bangumi = 资料库(.bangumi, bangumiRecords)
        // 只在 Bangumi 上的作品导入资料库，也加到 MAL
        var session = 同步会话(本地: [:], 平台: [.bangumi: bangumi, .myAnimeList: 资料库(.myAnimeList, [])], 基线: [:], 待推送: [:])
        session.导入方式 = .合并
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(Set(同步合并.新资料库(session).keys) == [键(1), 键(2)])
        #expect(session.推送.allSatisfy { $0.平台 == .myAnimeList && $0.种类 == .新增 })

        // 之后在 PaperVN 中修改：不写回 Bangumi，Bangumi 也不会被当成有了新的更改
        var local = 本地(from: bangumiRecords)
        local[键(1)]?.进度 = 8
        var next = 同步会话(本地: local, 平台: [.bangumi: bangumi], 基线: [.bangumi: 基线(bangumi)], 待推送: [键(1): [.bangumi]])
        同步合并.合并(&next)
        #expect(next.冲突.isEmpty)
        同步合并.生成推送(&next)
        #expect(next.推送.isEmpty)
        #expect(同步合并.新资料库(next)[键(1)]?.进度 == 8)
    }

    @Test
    func 同一部作品的多个条目只保留主条目() {
        var main = 记录(.bangumi, mal: 1, .planning)
        main.指定键 = 键(1)
        var special = 记录(.bangumi, mal: 2, .completed)
        special.指定键 = 键(1)
        special.附属 = true
        let library = 资料库(.bangumi, [special, main])
        #expect(library.记录.count == 1)
        #expect(library.记录[键(1)]?.平台ID == main.平台ID)
        #expect(library.附属记录.map(\.平台ID) == [special.平台ID])
    }

    @Test
    func 只有附属条目时取进展最多的_也不会写入() {
        var first = 记录(.myAnimeList, mal: 10, .planning)
        first.指定键 = 键(1)
        first.附属 = true
        var second = 记录(.myAnimeList, mal: 11, .completed)
        second.指定键 = 键(1)
        second.附属 = true
        let mal = 资料库(.myAnimeList, [first, second])
        #expect(mal.记录[键(1)]?.平台ID == second.平台ID)

        var local = 本地(from: [记录(.myAnimeList, mal: 1, .inProgress)])
        local[键(1)]?.进度 = 3
        var session = 同步会话(本地: local, 平台: [.myAnimeList: mal], 基线: [.myAnimeList: 基线(mal)], 待推送: [键(1): [.myAnimeList]])
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(session.推送.isEmpty)
    }

    @Test
    func 集数划分不同的平台进度不算冲突也不写入() {
        // Re:Zero 第三季：MAL 一季 16 集，Bangumi 分成两个条目，这个条目只有 8 集
        var mal = 记录(.myAnimeList, mal: 1, .inProgress, progress: 13)
        mal.总数 = 16
        var bangumiBase = 记录(.bangumi, mal: 1, .inProgress, progress: 3)
        bangumiBase.总数 = 8
        var bangumiNow = bangumiBase
        bangumiNow.快照 = 同步快照(状态: .inProgress, 评分: nil, 进度: 5)
        let malLibrary = 资料库(.myAnimeList, [mal])
        var local = 本地(from: [mal])
        local[键(1)]?.总数 = 16
        var session = 同步会话(
            本地: local,
            平台: [.myAnimeList: malLibrary, .bangumi: 资料库(.bangumi, [bangumiNow])],
            基线: [.myAnimeList: 基线(malLibrary), .bangumi: 基线(资料库(.bangumi, [bangumiBase]))],
            待推送: [:]
        )
        同步合并.合并(&session)
        #expect(session.冲突.isEmpty)
        同步合并.生成推送(&session)
        #expect(同步合并.新资料库(session)[键(1)]?.进度 == 13)
        #expect(!session.推送.contains { $0.平台 == .myAnimeList && $0.目标?.进度 == 5 })
    }

    @Test
    func 仅导出的平台不导入_仅导入的平台不写入() {
        let records = [记录(.myAnimeList, mal: 1, .inProgress, progress: 3)]
        let mal = 资料库(.myAnimeList, records)
        // AniList 上多一部作品，设为仅导出：不导入资料库，也不删除
        let ani = 资料库(.aniList, [记录(.aniList, mal: 1, .inProgress, progress: 3), 记录(.aniList, mal: 2, .completed)])
        var local = 本地(from: records)
        local[键(1)]?.进度 = 4
        var session = 同步会话(
            本地: local,
            平台: [.myAnimeList: mal, .aniList: ani],
            基线: [.myAnimeList: 基线(mal), .aniList: 基线(ani)],
            待推送: [键(1): [.myAnimeList, .aniList]]
        )
        session.仅导出 = [.aniList]
        session.仅导入 = [.myAnimeList]
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(同步合并.新资料库(session)[键(2)] == nil)
        #expect(!session.推送.contains { $0.平台 == .myAnimeList })
        #expect(session.推送.contains { $0.平台 == .aniList && $0.键 == 键(1) && $0.目标?.进度 == 4 })
        #expect(!session.推送.contains { $0.键 == 键(2) })
    }

    @Test
    func 资料库已有的对应_弱编号保留_对错的改到正确作品且不算删除() {
        // 资料库：作品 1 的 Bangumi 条目是 bangumi-1；作品 2 的 Bangumi 条目是 bangumi-2
        var local: [String: 本地资料库条目] = [:]
        for mal in [1, 2] {
            local[键(mal)] = 本地资料库条目(id: 键(mal), 类型: .anime, 平台ID: [.myAnimeList: String(mal), .bangumi: "bangumi-\(mal)"], 标题: "作品\(mal)", 加入时间: nil)
        }
        // 映射：bangumi-1 只有 AniList 编号（弱），bangumi-2 其实是另一部作品 3（有 MAL ID）
        var weak = 记录(.bangumi, mal: 1, .completed)
        weak.malID = nil
        weak.指定键 = "aniList-anime:99"
        var moved = 记录(.bangumi, mal: 2, .completed)
        moved.malID = 3
        moved.指定键 = 键(3)
        var libraries: [资料库平台: 平台资料库] = [.bangumi: 资料库(.bangumi, [weak, moved])]
        var store = 同步状态存储()
        store.基线[.bangumi] = 平台基线(账户ID: "1", 账户名称: "user", 快照: [键(1): weak.快照, 键(2): moved.快照])
        PaperVNSync中心.核对已有对应(&libraries, local: &local, store: &store)
        #expect(libraries[.bangumi]?.记录[键(1)] != nil)
        #expect(libraries[.bangumi]?.记录[键(3)] != nil)
        #expect(store.基线[.bangumi]?.快照[键(2)] == nil)
        #expect(local[键(2)]?.平台ID[.bangumi] == nil)
        #expect(local[键(1)]?.平台ID[.bangumi] == "bangumi-1")
    }

    @Test
    func 对错的平台条目带来的记录_改回MAL上的记录() {
        // 以前把 Bangumi 上“2期”（看完 13 集）对到了总集篇（MAL 上看完 1 集），资料库记的是 Bangumi 的 13 集
        var local: [String: 本地资料库条目] = [:]
        local[键(2)] = 本地资料库条目(id: 键(2), 类型: .anime, 平台ID: [.myAnimeList: "2", .bangumi: "bangumi-2"], 标题: "总集篇", 加入时间: nil)
        local[键(2)]?.状态 = .completed
        local[键(2)]?.进度 = 13
        var moved = 记录(.bangumi, mal: 2, .completed, progress: 13)
        moved.malID = 3
        moved.指定键 = 键(3)
        var libraries: [资料库平台: 平台资料库] = [
            .bangumi: 资料库(.bangumi, [moved]),
            .myAnimeList: 资料库(.myAnimeList, [记录(.myAnimeList, mal: 2, .completed, progress: 1)]),
        ]
        var store = 同步状态存储()
        store.基线[.bangumi] = 平台基线(账户ID: "1", 账户名称: "user", 快照: [键(2): 同步快照(状态: .completed, 评分: nil, 进度: 13)])
        PaperVNSync中心.核对已有对应(&libraries, local: &local, store: &store)
        #expect(local[键(2)]?.进度 == 1)
        #expect(local[键(2)]?.平台ID[.bangumi] == nil)
    }

    @Test
    func TMDB只比较是否计划观看与评分() {
        let tmdb = 资料库平台.tmdb.同步能力
        // TMDB 上评过分的作品记为“看过”，资料库里是“在看”：不算不一致
        #expect(同步快照.一致(同步快照(状态: .completed, 评分: 80, 进度: nil), tmdb, 同步快照(状态: .inProgress, 评分: 80, 进度: 5), .本地))
        #expect(!同步快照.一致(同步快照(状态: .planning, 评分: nil, 进度: nil), tmdb, 同步快照(状态: .inProgress, 评分: nil, 进度: 5), .本地))
        #expect(tmdb.可记录(同步快照(状态: .planning, 评分: nil, 进度: nil)))
        #expect(!tmdb.可记录(同步快照(状态: .inProgress, 评分: nil, 进度: 3)))
    }

    @Test
    func TMDB记录不了的作品从想看列表移除_不新增() {
        let records = [记录(.myAnimeList, mal: 1, .inProgress, progress: 3), 记录(.myAnimeList, mal: 2, .inProgress, progress: 1)]
        let mal = 资料库(.myAnimeList, records)
        // TMDB 上 1 在想看列表里，2 没有
        var watchlist = 记录(.tmdb, mal: 1, .planning)
        watchlist.指定键 = 键(1)
        let tmdb = 资料库(.tmdb, [watchlist])
        var session = 同步会话(本地: 本地(from: records), 平台: [.myAnimeList: mal, .tmdb: tmdb], 基线: [.myAnimeList: 基线(mal), .tmdb: 基线(tmdb)], 待推送: [键(1): [.tmdb]])
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        let operations = session.推送.filter { $0.平台 == .tmdb }
        #expect(operations.map(\.种类) == [.删除])
        #expect(operations.first?.键 == 键(1))
    }

    @Test
    func 预装映射按Annict的作品划分() {
        // 鋼の錬金術師 FULLMETAL ALCHEMIST：Annict 1745 ↔ MAL 5114
        let annict = 作品映射.查找(.annict, 平台ID: 作品映射.Annict节点ID("1745"), 类型: .anime)
        #expect(annict == 作品映射.结果(键: "mal-anime:5114", 附属: false))
        #expect(作品映射.平台ID("mal-anime:5114", 平台: .annict, 类型: .anime) == 作品映射.Annict节点ID("1745"))
        #expect(作品映射.Annict节点ID("1745") == "V29yay0xNzQ1")
    }

    // MARK: 多语言标题

    @Test
    func 多语言标题按偏好语言选择() {
        let anilist = 作品多语言标题.生成(原名: "葬送のフリーレン", 原名语言: "ja", 罗马字: "Sousou no Frieren", 英文: "Frieren: Beyond Journey's End")
        let bangumi = 作品多语言标题.生成(原名: "葬送のフリーレン", 罗马字: nil, 中文: "葬送的芙莉莲")
        let titles = 作品多语言标题.合并([anilist, bangumi])
        #expect(titles.filter(\.main).count == 1)
        func pick(_ lang: 标题语言, unofficial: Bool = false) -> String {
            标题工具.获取主标题(titles: titles, defaultTitle: "default", 偏好: lang, 回退: .original, 允许非官方: unofficial).text
        }
        #expect(pick(.original) == "葬送のフリーレン")
        #expect(pick(.english) == "Frieren: Beyond Journey's End")
        #expect(pick(.romanized) == "Sousou no Frieren")
        // Bangumi 的中文名视为非官方，需要打开“允许非官方标题”
        #expect(pick(.chinese) == "葬送のフリーレン")
        #expect(pick(.chinese, unofficial: true) == "葬送的芙莉莲")
    }

    // MARK: 更改时间

    @Test
    func 平台上已经一致的作品不重新写入() {
        let mal = 资料库(.myAnimeList, [记录(.myAnimeList, mal: 1, .completed, score: 80, progress: 12)])
        let ani = 资料库(.aniList, [记录(.aniList, mal: 1, .completed, score: 80, progress: 12), 记录(.aniList, mal: 2, .planning)])
        var session = 同步会话(本地: [:], 平台: [.myAnimeList: mal, .aniList: ani], 基线: [:], 待推送: [:])
        session.导入方式 = .合并
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        // 只有 MAL 缺少的作品 2 需要写入；作品 1 两边一致，不碰
        #expect(session.推送.map(\.键) == [键(2)])
        #expect(session.推送.first?.平台 == .myAnimeList)
    }

    @Test
    func 第一次导入按所选平台的更改时间() {
        var malRecord = 记录(.myAnimeList, mal: 1, .completed)
        malRecord.修改时间 = Date(timeIntervalSince1970: 100)
        var aniRecord = 记录(.aniList, mal: 1, .completed)
        aniRecord.修改时间 = Date(timeIntervalSince1970: 900)
        var session = 同步会话(
            本地: [:],
            平台: [.myAnimeList: 资料库(.myAnimeList, [malRecord]), .aniList: 资料库(.aniList, [aniRecord])],
            基线: [:],
            待推送: [:]
        )
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(session.需要选择修改时间来源)
        #expect(session.需要确认推送)
        session.修改时间来源 = .myAnimeList
        #expect(同步合并.新资料库(session)[键(1)]?.修改时间 == Date(timeIntervalSince1970: 100))
        session.修改时间来源 = .aniList
        #expect(同步合并.新资料库(session)[键(1)]?.修改时间 == Date(timeIntervalSince1970: 900))
    }

    // MARK: 本地丢失

    @Test
    func 本地丢失的作品从平台恢复() {
        let records = [记录(.myAnimeList, mal: 1, .completed, score: 80, progress: 12)]
        let mal = 资料库(.myAnimeList, records)
        var session = 同步会话(本地: [:], 平台: [.myAnimeList: mal], 基线: [.myAnimeList: 基线(mal)], 待推送: [:])
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(session.冲突.isEmpty)
        #expect(session.推送.isEmpty)
        #expect(同步合并.新资料库(session)[键(1)]?.进度 == 12)
    }

    @Test
    func 在PaperVN中删除的作品不会被恢复() {
        let bangumi = 资料库(.bangumi, [记录(.bangumi, mal: 1, .completed)])
        var session = 同步会话(本地: [:], 平台: [.bangumi: bangumi], 基线: [.bangumi: 基线(bangumi)], 待推送: [:])
        session.本地已删除 = [键(1)]
        同步合并.合并(&session)
        #expect(同步合并.新资料库(session)[键(1)] == nil)
    }

    // MARK: 空值与已看完

    @Test
    func 来源没有记录的进度和评分不会把平台上的值清空() {
        var malRecord = 记录(.myAnimeList, mal: 1, .completed, score: 80, progress: 12)
        malRecord.总数 = 12
        let mal = 资料库(.myAnimeList, [malRecord])
        // Bangumi 标了“看过”，没有评分也没有集数
        let bangumi = 资料库(.bangumi, [记录(.bangumi, mal: 1, .completed)])
        var session = 同步会话(
            本地: 本地(from: [malRecord]),
            平台: [.myAnimeList: mal, .bangumi: bangumi],
            基线: [.myAnimeList: 基线(mal)],
            待推送: [:]
        )
        同步合并.检查导入方式(&session)
        #expect(!session.需要选择导入方式)
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(!session.推送.contains { $0.平台 == .myAnimeList })
        let entry = 同步合并.新资料库(session)[键(1)]
        #expect(entry?.进度 == 12)
        #expect(entry?.评分 == 80)
    }

    @Test
    func MAL上已看完却是0集的作品补满进度() {
        var broken = 记录(.myAnimeList, mal: 1, .completed, score: 80, progress: nil)
        broken.总数 = 24
        let mal = 资料库(.myAnimeList, [broken])
        var local = 本地(from: [broken])
        local[键(1)]?.总数 = 24
        var session = 同步会话(本地: local, 平台: [.myAnimeList: mal], 基线: [.myAnimeList: 基线(mal)], 待推送: [:])
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(session.推送.first?.目标?.进度 == 24)
        #expect(session.推送.first?.目标?.评分 == 80)
    }

    @Test
    func 基线按平台实际保存的值记录() {
        let saved = 同步合并.平台保存的值(
            同步快照(状态: .inProgress, 评分: 75, 进度: nil),
            现有: 同步快照(状态: .planning, 评分: nil, 进度: 3),
            platform: .myAnimeList,
            type: .anime
        )
        #expect(saved.评分 == 80)
        #expect(saved.进度 == 3)
    }

    // MARK: 标题匹配（用户资料库里没对上的真实例子）

    @Test
    func 预装映射对上季度写法与前缀不同的作品() {
        // 以前同步时按标题现场匹配遇到过的作品，现在由预装的作品映射对应
        #expect(作品映射.查找(.bangumi, 平台ID: "537409", 类型: .anime)?.键 == "mal-anime:61006")  // ぼっち・ざ・ろっく！ 第2期
        #expect(作品映射.查找(.bangumi, 平台ID: "442616", 类型: .anime)?.键 == "mal-anime:60160")  // 虹ヶ咲 完結編 最終章
        // Bangumi 上的是漫画，不能对应到同名的动画
        #expect(作品映射.查找(.bangumi, 平台ID: "218102", 类型: .anime) == nil)
        #expect(作品映射.查找(.bangumi, 平台ID: "218102", 类型: .manga)?.键 != "mal-anime:51678")
    }

    @Test
    func 预装映射的不写入规则() {
        // 攻殻機動隊 SAC Solid State Society 与 3D 版共用一个 TMDB 条目：只有一部写入
        #expect(作品映射.TMDB季("mal-anime:1566") != nil)
        // いちご100% 的特别篇：Annict 把它并在正篇的话里，动画按 Annict 划分，所以是正篇的附属条目
        #expect(作品映射.查找(.myAnimeList, 平台ID: "641", 类型: .anime) == 作品映射.结果(键: "mal-anime:248", 附属: true))
        // GLO・RI・A：VNDB 分成两部、Bangumi 只有一个条目，只有 v152 写入
        #expect(作品映射.视觉小说可以写入(166106, vndbID: "v152"))
        #expect(!作品映射.视觉小说可以写入(166106, vndbID: "v11106"))
    }

    @Test
    func 分割放送的写法是同一个键() {
        #expect(同步合并.标题匹配键("進撃の巨人 The Final Season Part.2") == 同步合并.标题匹配键("進撃の巨人 The Final Season Part 2"))
        #expect(同步合并.标题匹配键("千歳くんはラムネ瓶のなか 第2クール") == 同步合并.标题匹配键("千歳くんはラムネ瓶のなか 2クール"))
        #expect(同步合并.标题匹配键("ラブライブ！虹ヶ咲学園スクールアイドル同好会 2期") == 同步合并.标题匹配键("ラブライブ！虹ヶ咲学園スクールアイドル同好会 2"))
        #expect(同步合并.标题匹配键("進撃の巨人 The Final Season Part 2") != 同步合并.标题匹配键("進撃の巨人 The Final Season"))
    }

    @Test
    func 第二季和Season2是同一个键() {
        #expect(同步合并.标题匹配键("進撃の巨人 第二季") == 同步合并.标题匹配键("進撃の巨人 Season 2"))
        #expect(同步合并.标题匹配键("進撃の巨人 2nd Season") == 同步合并.标题匹配键("進撃の巨人 2期"))
        #expect(同步合并.标题匹配键("進撃の巨人") != 同步合并.标题匹配键("進撃の巨人 2期"))
    }

    // MARK: 覆盖后 Bangumi 删不掉的作品

    @Test
    func 只在Bangumi上的作品不会被恢复回资料库() {
        // 用 MAL 覆盖之后：资料库里没有，Bangumi 上还留着（删不掉），基线里也有
        let bangumi = 资料库(.bangumi, [记录(.bangumi, mal: 99, .completed)])
        let mal = 资料库(.myAnimeList, [])
        var session = 同步会话(
            本地: [:],
            平台: [.bangumi: bangumi, .myAnimeList: mal],
            基线: [.bangumi: 基线(bangumi), .myAnimeList: 基线(mal)],
            待推送: [:]
        )
        同步合并.合并(&session)
        同步合并.生成推送(&session)
        #expect(同步合并.新资料库(session)[键(99)] == nil)
        #expect(!session.推送.contains { $0.平台 == .myAnimeList })
    }

    // MARK: AniList 自动填写的日期

    @Test
    func AniList新建时自动填上的日期写入后改回资料库里的() {
        // 新建：平台上原来没有日期，AniList 填了当天，资料库里没有 → 清除
        #expect(同步合并.自动填写后的修正(
            原有: 同步日期(), 保存后: 同步日期(完成: "2026-10-19"), 期望: 同步日期()
        ) == 同步日期())
        // 资料库里有真实的日期 → 改成资料库里的
        #expect(同步合并.自动填写后的修正(
            原有: 同步日期(), 保存后: 同步日期(完成: "2026-10-19"), 期望: 同步日期(完成: "2024-05-01")
        ) == 同步日期(完成: "2024-05-01"))
        // 平台上原来就有的日期不动；和资料库一致时也不用改
        #expect(同步合并.自动填写后的修正(
            原有: 同步日期(完成: "2023-01-02"), 保存后: 同步日期(完成: "2023-01-02"), 期望: 同步日期()
        ) == nil)
        #expect(同步合并.自动填写后的修正(
            原有: 同步日期(), 保存后: 同步日期(完成: "2024-05-01"), 期望: 同步日期(完成: "2024-05-01")
        ) == nil)
    }

    private func AniList记录(完成日期: String?, 创建: String) -> 平台资料库记录 {
        var record = 记录(.aniList, mal: 32281, .completed, progress: 1)
        record.完成日期 = 完成日期
        record.创建时间 = ISO8601DateFormatter().date(from: 创建)
        return record
    }

    private func 本地条目(加入: String) -> 本地资料库条目 {
        var entry = 本地资料库条目(id: 键(32281), 类型: .anime, 平台ID: [:], 标题: "君の名は。", 加入时间: ISO8601DateFormatter().date(from: 加入))
        entry.状态 = .completed
        entry.完成日期 = "2026-10-19"
        return entry
    }

    @Test
    func 认出PaperVN推送后AniList自动填写的完成日期() {
        let record = AniList记录(完成日期: "2026-10-19", 创建: "2026-10-19T10:08:27Z")
        let mal = 记录(.myAnimeList, mal: 32281, .completed, progress: 1)
        let fix = 同步合并.AniList自动填写的日期(
            record, 本地: 本地条目(加入: "2026-10-17T02:00:00Z"),
            基线: 同步快照(状态: .completed, 评分: nil, 进度: 1), 其他记录: [mal]
        )
        #expect(fix == 同步日期())
        // MAL 上有真实的完成日期时改成它
        var malWithDate = mal
        malWithDate.完成日期 = "2017-01-03"
        #expect(同步合并.AniList自动填写的日期(
            record, 本地: 本地条目(加入: "2026-10-17T02:00:00Z"),
            基线: 同步快照(状态: .completed, 评分: nil, 进度: 1), 其他记录: [malWithDate]
        ) == 同步日期(完成: "2017-01-03"))
    }

    @Test
    func 在AniList上自己标记的完成日期不动() {
        let record = AniList记录(完成日期: "2026-10-19", 创建: "2026-10-19T10:08:27Z")
        // 作品是从 AniList 导入的（资料库里没有更早的记录）
        #expect(同步合并.AniList自动填写的日期(
            record, 本地: 本地条目(加入: "2026-10-19T12:00:00Z"),
            基线: 同步快照(状态: .completed, 评分: nil, 进度: 1), 其他记录: []
        ) == nil)
        // 上次同步时还是“在看”，之后在 AniList 上改成了看过
        #expect(同步合并.AniList自动填写的日期(
            record, 本地: 本地条目(加入: "2026-10-17T02:00:00Z"),
            基线: 同步快照(状态: .inProgress, 评分: nil, 进度: 1), 其他记录: []
        ) == nil)
        // 日期不是创建那天
        #expect(同步合并.AniList自动填写的日期(
            AniList记录(完成日期: "2026-10-25", 创建: "2026-10-19T10:08:27Z"), 本地: 本地条目(加入: "2026-10-17T02:00:00Z"),
            基线: 同步快照(状态: .completed, 评分: nil, 进度: 1), 其他记录: []
        ) == nil)
        // MAL 上也记着同一天
        var mal = 记录(.myAnimeList, mal: 32281, .completed, progress: 1)
        mal.完成日期 = "2026-10-19"
        #expect(同步合并.AniList自动填写的日期(
            record, 本地: 本地条目(加入: "2026-10-17T02:00:00Z"),
            基线: 同步快照(状态: .completed, 评分: nil, 进度: 1), 其他记录: [mal]
        ) == nil)
    }
}
