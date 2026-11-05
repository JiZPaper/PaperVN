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

    @Test func 同一个ID在一组是主条目_在另一组是附属条目时两边都生效() {
        // Fate/stay night TV reproduction：TMDB 上单独成作品（Bangumi 3955 ↔ TMDB tv/329731），
        // AniList 上没有自己的条目，并在 TV 版（AniList 356）里
        let calibration = 作品匹配校准.shared
        let previous = calibration.测试用校准表([
            作品对应组(类型: .anime, ids: [.bangumi: "3955", .tmdb: "tv/329731"]),
            作品对应组(类型: .anime, ids: [.aniList: "356"], 附属: [.bangumi: ["3955"], .tmdb: ["tv/329731"]]),
        ])
        defer { calibration.测试用校准表(previous.groups, splits: previous.splits) }
        let known: [资料库平台: String] = [.bangumi: "3955"]
        #expect(calibration.平台ID(.tmdb, 类型: .anime, 已知: known, 手动: []) == "tv/329731")
        #expect(calibration.并入(.aniList, 类型: .anime, 已知: known, 手动: []))
        #expect(!calibration.并入(.tmdb, 类型: .anime, 已知: known, 手动: []))
        #expect(calibration.查找(.bangumi, 平台ID: "3955", 类型: .anime, 手动: [])?.附属 == false)
    }

    private func TMDB记录(_ id: String, _ status: 资料库状态) -> 平台资料库记录 {
        平台资料库记录(
            平台: .tmdb, 平台ID: id, 类型: .anime, malID: nil, 标题: id, 日文标题: nil, 封面地址: nil,
            快照: 同步快照(状态: status, 评分: nil, 进度: nil), 总数: nil, 平均评分: nil, 发行日期: nil,
            开始日期: nil, 完成日期: nil, 修改时间: nil
        )
    }

    @Test func 后台校准覆盖用户的手动匹配并撤回写错的记录() throws {
        let calibration = 作品匹配校准.shared
        let previous = calibration.测试用校准表([
            // 课外授课篇在 TMDB 上并在动画 tv/62110 里
            作品对应组(类型: .anime, ids: [.tmdb: "tv/62110"], 附属: [.myAnimeList: ["32863"], .bangumi: ["170762"]]),
            // Re:Zero 第二季在 TMDB 上并在整部剧 tv/65942 里
            作品对应组(类型: .anime, ids: [.tmdb: "tv/65942"], 附属: [.myAnimeList: ["39587"]]),
            // Fate/Zero Remix：和用户选的一样
            作品对应组(类型: .anime, ids: [.bangumi: "36379", .tmdb: "movie/1621319"]),
        ])
        defer { calibration.测试用校准表(previous.groups, splits: previous.splits) }
        var store = 同步状态存储()
        store.手动匹配 = [
            作品对应组(类型: .anime, ids: [.myAnimeList: "32863", .bangumi: "170762", .tmdb: "movie/359628"]),  // 选成了真人电影
            作品对应组(类型: .anime, ids: [.myAnimeList: "39587", .tmdb: "tv/65942"]),  // 选成了整部剧
            作品对应组(类型: .anime, ids: [.bangumi: "36379", .tmdb: "movie/1621319"]),
            作品对应组(类型: .anime, ids: [.bangumi: "1", .tmdb: "movie/1"]),  // 没有校准，保留
        ]
        // 和平台上读到的记录一样：当初写进去以后没改过
        let watched = 同步快照(状态: .completed, 评分: nil, 进度: nil)
        store.基线[.tmdb] = 平台基线(账户ID: "1", 账户名称: "user", 快照: [
            "mal-anime:32863": watched,
            "mal-anime:39587": watched,
        ])
        var libraries: [资料库平台: 平台资料库] = [
            .tmdb: 平台资料库(平台: .tmdb, 账户ID: "1", 账户名称: "user", 记录: [
                TMDB记录("movie/359628", .completed), TMDB记录("tv/65942", .completed),
            ]),
        ]
        // Re:Zero 第一季（预装映射里 TMDB tv/65942 属于它）也在资料库里
        let firstSeason = try #require(作品映射.查找(.tmdb, 平台ID: "tv/65942", 类型: .anime)?.键)
        var local: [String: 本地资料库条目] = [
            "mal-anime:32863": 本地资料库条目(id: "mal-anime:32863", 类型: .anime, 平台ID: [.tmdb: "movie/359628"], 标题: "", 加入时间: nil),
            firstSeason: 本地资料库条目(id: firstSeason, 类型: .anime, 平台ID: [:], 标题: "", 加入时间: nil),
        ]
        let withdrawals = PaperVNSync中心.跟随校准(store: &store, libraries: &libraries, local: &local)
        // 校准过的三组手动匹配都去掉，没校准的保留
        #expect(store.手动匹配.map(\.ids) == [["bangumi": "1", "tmdb": "movie/1"]])
        // 真人电影不属于任何作品、也没被用户改过：从 TMDB 删除，也不再出现在这次读到的记录里
        #expect(withdrawals == [撤回写入(平台: .tmdb, 平台ID: "movie/359628", 类型: .anime)])
        #expect(libraries[.tmdb]?.记录.values.contains { $0.平台ID == "movie/359628" } == false)
        #expect(local["mal-anime:32863"]?.平台ID[.tmdb] == nil)
        // 整部剧的条目属于第一季（预装映射），不删；第二季的基线去掉，第一季补上基线，不会弹出确认
        #expect(libraries[.tmdb]?.记录.values.contains { $0.平台ID == "tv/65942" } == true)
        #expect(store.基线[.tmdb]?.快照 == [firstSeason: watched])
    }

    @Test func 跟随校准之后同步不会弹出确认() throws {
        let calibration = 作品匹配校准.shared
        let previous = calibration.测试用校准表([
            作品对应组(类型: .anime, ids: [.tmdb: "tv/65942"], 附属: [.myAnimeList: ["39587"]]),
        ])
        defer { calibration.测试用校准表(previous.groups, splits: previous.splits) }
        let firstSeason = try #require(作品映射.查找(.tmdb, 平台ID: "tv/65942", 类型: .anime)?.键)
        let secondSeason = "mal-anime:39587"
        // 用户把第二季手动匹配到了整部剧的 TMDB 条目，TMDB 上记着第二季的“看过”；资料库里第一季是“计划观看”
        var store = 同步状态存储()
        store.手动匹配 = [作品对应组(类型: .anime, ids: [.myAnimeList: "39587", .tmdb: "tv/65942"])]
        let written = 同步快照(状态: .completed, 评分: nil, 进度: nil)
        store.基线[.tmdb] = 平台基线(账户ID: "1", 账户名称: "user", 快照: [secondSeason: written])
        var record = TMDB记录("tv/65942", .completed)
        var libraries: [资料库平台: 平台资料库] = [
            .tmdb: 平台资料库(平台: .tmdb, 账户ID: "1", 账户名称: "user", 记录: [record]),
        ]
        var first = 本地资料库条目(id: firstSeason, 类型: .anime, 平台ID: [:], 标题: "", 加入时间: nil)
        first.状态 = .planning
        var second = 本地资料库条目(id: secondSeason, 类型: .anime, 平台ID: [.tmdb: "tv/65942"], 标题: "", 加入时间: nil)
        second.状态 = .completed
        var local = [firstSeason: first, secondSeason: second]
        _ = PaperVNSync中心.跟随校准(store: &store, libraries: &libraries, local: &local)
        // 同步时这条记录按预装映射归到第一季
        record.指定键 = firstSeason
        libraries[.tmdb] = 平台资料库(平台: .tmdb, 账户ID: "1", 账户名称: "user", 记录: [record])

        var session = 同步会话(本地: local, 平台: libraries, 基线: store.基线, 待推送: [:])
        同步合并.检查减少(&session)
        同步合并.检查导入方式(&session)
        同步合并.合并(&session)
        #expect(session.减少提示.isEmpty)
        #expect(!session.需要选择导入方式)
        #expect(session.冲突.isEmpty)
        同步合并.生成推送(&session)
        #expect(!session.需要确认推送)
        // TMDB 上这一条改成资料库里第一季的状态
        #expect(session.推送.contains { $0.平台 == .tmdb && $0.键 == firstSeason && $0.目标?.状态 == .planning })
        #expect(session.本地[secondSeason]?.平台ID[.tmdb] == nil)
    }

    @Test func 所属作品不在资料库里时撤回() {
        let calibration = 作品匹配校准.shared
        let previous = calibration.测试用校准表([
            作品对应组(类型: .anime, ids: [.tmdb: "tv/65942"], 附属: [.myAnimeList: ["39587"]]),
        ])
        defer { calibration.测试用校准表(previous.groups, splits: previous.splits) }
        var store = 同步状态存储()
        store.手动匹配 = [作品对应组(类型: .anime, ids: [.myAnimeList: "39587", .tmdb: "tv/65942"])]
        store.基线[.tmdb] = 平台基线(账户ID: "1", 账户名称: "user", 快照: ["mal-anime:39587": 同步快照(状态: .completed, 评分: nil, 进度: nil)])
        var libraries: [资料库平台: 平台资料库] = [
            .tmdb: 平台资料库(平台: .tmdb, 账户ID: "1", 账户名称: "user", 记录: [TMDB记录("tv/65942", .completed)]),
        ]
        var local: [String: 本地资料库条目] = [:]
        let withdrawals = PaperVNSync中心.跟随校准(store: &store, libraries: &libraries, local: &local)
        #expect(withdrawals == [撤回写入(平台: .tmdb, 平台ID: "tv/65942", 类型: .anime)])
        #expect(libraries[.tmdb]?.记录.isEmpty == true)
    }

    @Test func 用户在平台上改过的记录不撤回() {
        let calibration = 作品匹配校准.shared
        let previous = calibration.测试用校准表([
            作品对应组(类型: .anime, ids: [.tmdb: "tv/62110"], 附属: [.myAnimeList: ["32863"]]),
        ])
        defer { calibration.测试用校准表(previous.groups, splits: previous.splits) }
        var store = 同步状态存储()
        store.手动匹配 = [作品对应组(类型: .anime, ids: [.myAnimeList: "32863", .tmdb: "movie/359628"])]
        store.基线[.tmdb] = 平台基线(账户ID: "1", 账户名称: "user", 快照: ["mal-anime:32863": 同步快照(状态: .planning, 评分: nil, 进度: nil)])
        var libraries: [资料库平台: 平台资料库] = [
            .tmdb: 平台资料库(平台: .tmdb, 账户ID: "1", 账户名称: "user", 记录: [TMDB记录("movie/359628", .completed)]),
        ]
        var local: [String: 本地资料库条目] = [:]
        let withdrawals = PaperVNSync中心.跟随校准(store: &store, libraries: &libraries, local: &local)
        #expect(withdrawals.isEmpty)
        #expect(store.手动匹配.isEmpty)
        #expect(libraries[.tmdb]?.记录.values.contains { $0.平台ID == "movie/359628" } == true)
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
