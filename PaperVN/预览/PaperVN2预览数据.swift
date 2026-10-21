#if DEBUG
import SwiftUI

// PaperVN 2 新界面在 Xcode 预览中使用的示例数据。只在 DEBUG 构建中编译，App 运行时不会用到。
// 封面是 MyAnimeList 上作品的真实封面地址，预览需要联网才能显示；其余数据都是虚构的。

/// 一部示例作品：同时生成资料库条目、平台记录和冲突。
struct 预览作品 {
    let 类型: 作品类型
    let malID: Int
    let aniListID: Int?
    /// MAL 的罗马字标题，也是资料库的默认标题。
    let 罗马字: String
    let 原名: String
    let 英文: String?
    let 中文: String?
    let 封面: String
    let 总数: Int?
    /// 10–100。
    let 平均评分: Double?
    let 发行日期: String?

    var 键: String { 本地资料库条目.MyAnimeListID(类型 == .anime ? .anime : .manga, malID) }

    var 多语言标题: [用户多语言标题] {
        作品多语言标题.生成(原名: 原名, 原名语言: "ja", 罗马字: 罗马字, 英文: 英文, 中文: 中文)
    }

    var 标题结果: 标题工具.标题结果 {
        标题工具.标题结果(text: 原名, isJapanese: true, languageCode: "ja")
    }

    func 条目(
        _ status: 资料库状态?,
        评分 score: Int? = nil,
        进度 progress: Int? = nil,
        开始日期 started: String? = nil,
        完成日期 finished: String? = nil,
        修改于 daysAgo: Double = 1
    ) -> 本地资料库条目 {
        var platformIDs: [资料库平台: String] = [.myAnimeList: String(malID)]
        if let aniListID { platformIDs[.aniList] = String(aniListID) }
        var entry = 本地资料库条目(
            id: 键,
            类型: 类型,
            平台ID: platformIDs,
            标题: 罗马字,
            加入时间: Date(timeIntervalSinceNow: -86_400 * (daysAgo + 30))
        )
        entry.状态 = status
        entry.评分 = score
        entry.进度 = progress
        entry.总数 = 总数
        entry.平均评分 = 平均评分
        entry.发行日期 = 发行日期
        entry.开始日期 = started
        entry.完成日期 = finished
        entry.封面地址 = 封面
        entry.日文标题 = 原名
        entry.多语言标题 = 多语言标题
        entry.修改时间 = Date(timeIntervalSinceNow: -86_400 * daysAgo)
        return entry
    }

    func 记录(
        _ platform: 资料库平台,
        _ status: 资料库状态,
        评分 score: Int? = nil,
        进度 progress: Int? = nil,
        修改于 daysAgo: Double? = nil
    ) -> 平台资料库记录 {
        平台资料库记录(
            平台: platform,
            平台ID: platform == .myAnimeList ? String(malID) : String(aniListID ?? malID),
            类型: 类型,
            malID: malID,
            标题: 罗马字,
            日文标题: 原名,
            封面地址: 封面,
            快照: 同步快照(状态: status, 评分: score, 进度: progress),
            总数: 总数,
            平均评分: 平均评分,
            发行日期: 发行日期,
            开始日期: nil,
            完成日期: nil,
            修改时间: daysAgo.map { Date(timeIntervalSinceNow: -86_400 * $0) },
            多语言标题: 多语言标题
        )
    }

    var 详情目标: 作品详情目标 {
        作品详情目标(kind: 类型 == .anime ? .anime : .manga, malID: malID, 标题: 罗马字, 封面: 封面)
    }
}

enum 预览数据 {
    // MARK: 作品

    static let 芙莉莲 = 预览作品(
        类型: .anime, malID: 52991, aniListID: 154587,
        罗马字: "Sousou no Frieren", 原名: "葬送のフリーレン",
        英文: "Frieren: Beyond Journey's End", 中文: "葬送的芙莉莲",
        封面: "https://cdn.myanimelist.net/images/anime/1015/138006.jpg",
        总数: 28, 平均评分: 92.8, 发行日期: "2023-09-29"
    )
    static let 芙莉莲第二季 = 预览作品(
        类型: .anime, malID: 59978, aniListID: 182255,
        罗马字: "Sousou no Frieren 2nd Season", 原名: "葬送のフリーレン 第2期",
        英文: "Frieren: Beyond Journey's End Season 2", 中文: "葬送的芙莉莲 第二季",
        封面: "https://cdn.myanimelist.net/images/anime/1921/154528.jpg",
        总数: nil, 平均评分: nil, 发行日期: "2026-01-16"
    )
    static let 我推的孩子 = 预览作品(
        类型: .anime, malID: 52034, aniListID: 150672,
        罗马字: "\"Oshi no Ko\"", 原名: "【推しの子】",
        英文: "[Oshi No Ko]", 中文: "【我推的孩子】",
        封面: "https://cdn.myanimelist.net/images/anime/1812/134736.jpg",
        总数: 11, 平均评分: 85.9, 发行日期: "2023-04-12"
    )
    static let 间谍过家家 = 预览作品(
        类型: .anime, malID: 50265, aniListID: 140960,
        罗马字: "Spy x Family", 原名: "SPY×FAMILY",
        英文: "Spy x Family", 中文: "间谍过家家",
        封面: "https://cdn.myanimelist.net/images/anime/1441/122795.jpg",
        总数: 12, 平均评分: 85.1, 发行日期: "2022-04-09"
    )
    static let 间谍过家家第二季 = 预览作品(
        类型: .anime, malID: 53887, aniListID: 158927,
        罗马字: "Spy x Family Season 2", 原名: "SPY×FAMILY Season 2",
        英文: "Spy x Family Season 2", 中文: "间谍过家家 第二季",
        封面: "https://cdn.myanimelist.net/images/anime/1506/138982.jpg",
        总数: 12, 平均评分: 81.4, 发行日期: "2023-10-07"
    )
    static let 孤独摇滚 = 预览作品(
        类型: .anime, malID: 47917, aniListID: 130003,
        罗马字: "Bocchi the Rock!", 原名: "ぼっち・ざ・ろっく！",
        英文: "Bocchi the Rock!", 中文: "孤独摇滚！",
        封面: "https://cdn.myanimelist.net/images/anime/1448/127956.jpg",
        总数: 12, 平均评分: 88.0, 发行日期: "2022-10-09"
    )
    static let 药屋少女 = 预览作品(
        类型: .anime, malID: 54492, aniListID: 161645,
        罗马字: "Kusuriya no Hitorigoto", 原名: "薬屋のひとりごと",
        英文: "The Apothecary Diaries", 中文: "药屋少女的呢喃",
        封面: "https://cdn.myanimelist.net/images/anime/1708/138033.jpg",
        总数: 24, 平均评分: 88.6, 发行日期: "2023-10-22"
    )
    static let 进击的巨人完结篇 = 预览作品(
        类型: .anime, malID: 51535, aniListID: 146984,
        罗马字: "Shingeki no Kyojin: The Final Season - Kanketsu-hen", 原名: "進撃の巨人 The Final Season 完結編",
        英文: "Attack on Titan: The Final Season - The Final Chapters", 中文: "进击的巨人 最终季 完结篇",
        封面: "https://cdn.myanimelist.net/images/anime/1279/131078.jpg",
        总数: 2, 平均评分: 90.1, 发行日期: "2023-03-04"
    )
    static let 芙莉莲漫画 = 预览作品(
        类型: .manga, malID: 126287, aniListID: 118586,
        罗马字: "Sousou no Frieren", 原名: "葬送のフリーレン",
        英文: "Frieren: Beyond Journey's End", 中文: "葬送的芙莉莲",
        封面: "https://cdn.myanimelist.net/images/manga/3/232121.jpg",
        总数: nil, 平均评分: 90.3, 发行日期: "2020-04-28"
    )
    static let 间谍过家家漫画 = 预览作品(
        类型: .manga, malID: 119161, aniListID: 108556,
        罗马字: "Spy x Family", 原名: "SPY×FAMILY",
        英文: "Spy x Family", 中文: "间谍过家家",
        封面: "https://cdn.myanimelist.net/images/manga/3/219741.jpg",
        总数: nil, 平均评分: 86.5, 发行日期: "2019-03-25"
    )
    static let 剑风传奇 = 预览作品(
        类型: .manga, malID: 2, aniListID: 30002,
        罗马字: "Berserk", 原名: "ベルセルク",
        英文: "Berserk", 中文: "剑风传奇",
        封面: "https://cdn.myanimelist.net/images/manga/1/157897.jpg",
        总数: nil, 平均评分: 94.7, 发行日期: "1989-08-25"
    )
    static let 黑色五叶草 = 预览作品(
        类型: .manga, malID: 86337, aniListID: 86123,
        罗马字: "Black Clover", 原名: "ブラッククローバー",
        英文: "Black Clover", 中文: "黑色五叶草",
        封面: "https://cdn.myanimelist.net/images/manga/2/166254.jpg",
        总数: nil, 平均评分: 79.2, 发行日期: "2015-02-16"
    )
    static let 狼与香辛料 = 预览作品(
        类型: .lightNovel, malID: 9115, aniListID: 39115,
        罗马字: "Ookami to Koushinryou", 原名: "狼と香辛料",
        英文: "Spice and Wolf", 中文: "狼与香辛料",
        封面: "https://cdn.myanimelist.net/images/manga/2/153860.jpg",
        总数: 24, 平均评分: 85.0, 发行日期: "2006-02-10"
    )
    static let 刀剑神域 = 预览作品(
        类型: .lightNovel, malID: 21479, aniListID: 41479,
        罗马字: "Sword Art Online", 原名: "ソードアート・オンライン",
        英文: "Sword Art Online", 中文: "刀剑神域",
        封面: "https://cdn.myanimelist.net/images/manga/2/280994.jpg",
        总数: 28, 平均评分: 73.1, 发行日期: "2009-04-10"
    )

    // MARK: 资料库

    /// 动画、漫画与轻小说的资料库，涵盖每种状态。
    static let 资料库条目: [本地资料库条目] = [
        芙莉莲.条目(.completed, 评分: 100, 进度: 28, 开始日期: "2023-09-29", 完成日期: "2024-03-22", 修改于: 12),
        芙莉莲第二季.条目(.planning, 修改于: 0.2),
        我推的孩子.条目(.inProgress, 评分: 80, 进度: 7, 开始日期: "2023-04-12", 修改于: 0.5),
        间谍过家家.条目(.completed, 评分: 80, 进度: 12, 修改于: 40),
        间谍过家家第二季.条目(.onHold, 进度: 4, 修改于: 20),
        孤独摇滚.条目(.completed, 评分: 90, 进度: 12, 修改于: 60),
        药屋少女.条目(.inProgress, 评分: 90, 进度: 15, 修改于: 2),
        进击的巨人完结篇.条目(.dropped, 进度: 1, 修改于: 90),
        芙莉莲漫画.条目(.inProgress, 评分: 90, 进度: 128, 修改于: 3),
        间谍过家家漫画.条目(.planning, 修改于: 5),
        剑风传奇.条目(.onHold, 评分: 100, 进度: 364, 修改于: 120),
        黑色五叶草.条目(.dropped, 进度: 210, 修改于: 200),
        狼与香辛料.条目(.completed, 评分: 90, 进度: 24, 修改于: 300),
        刀剑神域.条目(.inProgress, 评分: 70, 进度: 12, 修改于: 7),
    ]

    /// 十分钟前加入资料库的“计划观看”。
    static var 刚加入的条目: 本地资料库条目 {
        var entry = 芙莉莲第二季.条目(.planning)
        entry.加入时间 = Date(timeIntervalSinceNow: -600)
        return entry
    }

    // MARK: 账户

    static let 用户名 = "paperreader"

    static func vndb(已登录: Bool) -> 用户登录 {
        let auth = 用户登录(previewing: true)
        auth.isLoggedIn = 已登录
        auth.username = 已登录 ? 用户名 : ""
        auth.userID = 已登录 ? "u271828" : ""
        return auth
    }

    static func myAnimeList(已登录: Bool) -> MyAnimeList账户 {
        已登录
            ? .预览已登录(MyAnimeList用户资料(id: 18_675_309, name: 用户名, picture: nil, joinedAt: "2019-04-01T00:00:00+00:00"))
            : MyAnimeList账户(previewing: true)
    }

    static func aniList(已登录: Bool) -> AniList账户 {
        已登录 ? .预览已登录(AniList用户资料(id: 5_467_218, name: 用户名, avatar: nil)) : AniList账户(previewing: true)
    }

    static func annict(已登录: Bool) -> Annict账户 {
        已登录
            ? .预览已登录(Annict用户资料(annictId: 98_765, username: 用户名, name: "纸片读者", avatarUrl: nil))
            : Annict账户(previewing: true)
    }

    static func tmdb(已登录: Bool) -> TMDB账户 {
        已登录 ? .预览已登录(TMDB用户资料(id: 22_334_455, username: 用户名, name: nil, avatar: nil)) : TMDB账户(previewing: true)
    }

    static func bangumi(已登录: Bool) -> Bangumi账户 {
        已登录
            ? .预览已登录(Bangumi用户资料(
                id: 778_899,
                username: 用户名,
                nickname: "纸片读者",
                userGroup: 10,
                avatar: .init(large: "", medium: "", small: ""),
                sign: ""
            ))
            : Bangumi账户(previewing: true)
    }

    /// 只在预览里使用的设置：每个预览一份，互不影响，也不改动 App 自己的设置。
    static func 设置(_ name: String, _ values: [String: Any] = [:]) -> UserDefaults {
        let suite = "PaperVN.预览.\(name)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        for (key, value) in values {
            defaults.set(value, forKey: key)
        }
        return defaults
    }

    // MARK: PaperVN Sync

    private static func 资料库(_ platform: 资料库平台, _ records: [平台资料库记录], 账户名称: String = 用户名) -> 平台资料库 {
        平台资料库(平台: platform, 账户ID: "\(platform.rawValue)-1", 账户名称: 账户名称, 记录: records)
    }

    private static func 基线(_ library: 平台资料库) -> 平台基线 {
        平台基线(账户ID: library.账户ID, 账户名称: library.账户名称, 快照: library.记录.mapValues(\.快照))
    }

    private static var 本地字典: [String: 本地资料库条目] {
        Dictionary(资料库条目.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 和资料库一致的 MyAnimeList 资料库。
    private static var 一致的MAL资料库: 平台资料库 {
        资料库(.myAnimeList, 资料库条目.map { entry in
            平台资料库记录(
                平台: .myAnimeList,
                平台ID: String(entry.malID ?? 0),
                类型: entry.类型,
                malID: entry.malID,
                标题: entry.标题,
                日文标题: entry.日文标题,
                封面地址: entry.封面地址,
                快照: 同步合并.快照(entry),
                总数: entry.总数,
                平均评分: entry.平均评分,
                发行日期: entry.发行日期,
                开始日期: nil,
                完成日期: nil,
                修改时间: entry.修改时间,
                多语言标题: entry.多语言标题 ?? []
            )
        })
    }

    /// MyAnimeList 与 AniList 上的作品比上次同步时少了很多。
    static var 资料库减少会话: 同步会话 {
        let mal = 资料库(.myAnimeList, [芙莉莲.记录(.myAnimeList, .completed, 评分: 100, 进度: 28)])
        let ani = 资料库(.aniList, [])
        var session = 同步会话(本地: 本地字典, 平台: [.myAnimeList: mal, .aniList: ani], 基线: [:], 待推送: [:])
        session.减少提示 = [
            资料库减少提示(平台: .myAnimeList, 账户名称: 用户名, 上次数量: 312, 现在数量: 1),
            资料库减少提示(平台: .aniList, 账户名称: 用户名, 上次数量: 298, 现在数量: 0),
        ]
        session.减少处理 = [.aniList: .保留并重新上传]
        return session
    }

    /// 第一次登录 AniList，它和资料库、MyAnimeList 的内容不同；Annict 没有登录，Bangumi 同步方式为“无”。
    static func 导入方式会话(读取失败: Bool = false) -> 同步会话 {
        var session = 同步会话(本地: 本地字典, 平台: [.myAnimeList: 一致的MAL资料库], 基线: [:], 待推送: [:])
        session.需要选择导入方式 = true
        session.来源概况 = [
            来源概况(来源: .本地, 账户名称: nil, 数量: [.anime: 8, .manga: 4, .lightNovel: 2], 账户已更换: false),
            来源概况(来源: .平台(.myAnimeList), 账户名称: 用户名, 数量: [.anime: 126, .manga: 48, .lightNovel: 9], 账户已更换: false),
            来源概况(来源: .平台(.aniList), 账户名称: "paper_reader_jp", 数量: [.anime: 131, .manga: 51], 账户已更换: true),
        ]
        session.未参与 = [.annict: .未登录, .tmdb: .未登录, .bangumi: .同步方式为无]
        if 读取失败 {
            session.读取失败 = [.tmdb: String(localized: "无法读取账户信息，请重新登录。")]
            session.未参与[.tmdb] = nil
        }
        return session
    }

    /// 其他平台上的更改和记录不同的作品。`全部已选择` 为 true 时每部作品都选好了版本。
    static func 检查更改会话(全部已选择: Bool = false) -> 同步会话 {
        var session = 同步会话(本地: 本地字典, 平台: [.myAnimeList: 一致的MAL资料库], 基线: [:], 待推送: [:])
        func 冲突(_ work: 预览作品, _ kind: 条目冲突.种类, _ versions: [同步版本], 选择: 同步来源?) -> 条目冲突 {
            条目冲突(
                种类: kind,
                键: work.键,
                标题: work.罗马字,
                多语言标题: work.多语言标题,
                类型: work.类型,
                封面地址: work.封面,
                版本: versions,
                选择: 全部已选择 ? (选择 ?? versions.first?.来源) : 选择
            )
        }
        session.冲突 = [
            冲突(我推的孩子, .外部更改, [
                同步版本(来源: .本地, 快照: 同步快照(状态: .inProgress, 评分: 80, 进度: 7)),
                同步版本(来源: .平台(.myAnimeList), 快照: 同步快照(状态: .inProgress, 评分: 80, 进度: 9)),
            ], 选择: .平台(.myAnimeList)),
            冲突(孤独摇滚, .外部更改, [
                同步版本(来源: .本地, 快照: 同步快照(状态: .completed, 评分: 90, 进度: 12)),
                同步版本(来源: .平台(.aniList), 快照: nil),
            ], 选择: nil),
            冲突(药屋少女, .记录不同, [
                同步版本(来源: .本地, 快照: 同步快照(状态: .inProgress, 评分: 90, 进度: 15)),
                同步版本(来源: .平台(.myAnimeList), 快照: 同步快照(状态: .completed, 评分: 90, 进度: 24)),
                同步版本(来源: .平台(.annict), 快照: 同步快照(状态: .onHold, 评分: nil, 进度: nil)),
            ], 选择: nil),
            冲突(芙莉莲漫画, .记录不同, [
                同步版本(来源: .平台(.myAnimeList), 快照: 同步快照(状态: .inProgress, 评分: 90, 进度: 128)),
                同步版本(来源: .平台(.aniList), 快照: 同步快照(状态: .inProgress, 评分: 85, 进度: 131)),
            ], 选择: nil),
            冲突(芙莉莲第二季, .记录不同, [
                同步版本(来源: .本地, 快照: nil),
                同步版本(来源: .平台(.tmdb), 快照: 同步快照(状态: .planning, 评分: nil, 进度: nil)),
            ], 选择: nil),
        ]
        session.冲突已生成 = true
        return session
    }

    /// 确认同步。`首次同步` 为 true 时各平台都没有基线，需要选择“最近更改”的依据。
    static func 确认会话(首次同步: Bool = false) -> 同步会话 {
        let mal = 一致的MAL资料库
        let ani = 资料库(.aniList, [
            芙莉莲.记录(.aniList, .completed, 评分: 100, 进度: 28, 修改于: 12),
            芙莉莲第二季.记录(.aniList, .planning, 修改于: 0.2),
            我推的孩子.记录(.aniList, .inProgress, 评分: 80, 进度: 9, 修改于: 0.4),
            孤独摇滚.记录(.aniList, .completed, 评分: 90, 进度: 12, 修改于: 60),
        ])
        let bgm = 资料库(.bangumi, [
            芙莉莲.记录(.bangumi, .completed, 评分: 100, 进度: 28),
            药屋少女.记录(.bangumi, .inProgress, 评分: 90, 进度: 15),
        ], 账户名称: "纸片读者")
        let annict = 资料库(.annict, [
            我推的孩子.记录(.annict, .inProgress),
            药屋少女.记录(.annict, .inProgress),
        ])
        let libraries: [资料库平台: 平台资料库] = [.myAnimeList: mal, .aniList: ani, .bangumi: bgm, .annict: annict]
        var session = 同步会话(
            本地: 本地字典,
            平台: libraries,
            基线: 首次同步 ? [:] : libraries.mapValues(基线),
            待推送: [:]
        )
        session.仅导入 = [.bangumi]
        session.结果 = [
            我推的孩子.键: .保留(同步快照(状态: .inProgress, 评分: 80, 进度: 9)),
            药屋少女.键: .保留(同步快照(状态: .completed, 评分: 90, 进度: 24)),
            黑色五叶草.键: .删除,
        ]
        func 操作(_ platform: 资料库平台, _ work: 预览作品, _ kind: 推送操作.种类, 已知ID: Bool = true, 目标: 同步快照?) -> 推送操作 {
            推送操作(
                平台: platform, 键: work.键, 种类: kind, 类型: work.类型,
                标题: work.原名, 日文标题: work.原名, malID: work.malID,
                平台ID: 已知ID ? String(work.malID) : nil,
                目标: 目标
            )
        }
        session.推送 = [
            操作(.myAnimeList, 我推的孩子, .修改, 目标: 同步快照(状态: .inProgress, 评分: 80, 进度: 9)),
            操作(.myAnimeList, 药屋少女, .修改, 目标: 同步快照(状态: .completed, 评分: 90, 进度: 24)),
            操作(.myAnimeList, 黑色五叶草, .删除, 目标: nil),
            操作(.aniList, 药屋少女, .修改, 目标: 同步快照(状态: .completed, 评分: 90, 进度: 24)),
            操作(.aniList, 狼与香辛料, .新增, 已知ID: false, 目标: 同步快照(状态: .completed, 评分: 90, 进度: 24)),
            操作(.aniList, 剑风传奇, .新增, 已知ID: false, 目标: 同步快照(状态: .onHold, 评分: 100, 进度: 364)),
            操作(.annict, 药屋少女, .修改, 目标: 同步快照(状态: .completed, 评分: nil, 进度: nil)),
        ]
        session.未匹配 = [.annict: [芙莉莲第二季.键]]
        session.需要确认推送 = true
        return session
    }

    /// 同步任务页面“缺失的作品”。
    static let 未匹配: [资料库平台: [未匹配作品]] = [
        .aniList: [
            未匹配作品(键: 剑风传奇.键, 类型: .manga, 标题: 剑风传奇.原名, 全部标题: [剑风传奇.原名, 剑风传奇.罗马字], 年份: 1989, 已知ID: [.myAnimeList: "2"]),
            未匹配作品(键: 狼与香辛料.键, 类型: .lightNovel, 标题: 狼与香辛料.原名, 全部标题: [狼与香辛料.原名, 狼与香辛料.英文 ?? ""], 年份: 2006, 已知ID: [.myAnimeList: "9115"]),
            // 资料库里已经没有这部作品，只显示标题
            未匹配作品(键: "mal-anime:9999901", 类型: .anime, 标题: "劇場版 ぼっち・ざ・ろっく！ Re:", 全部标题: [], 年份: 2024, 已知ID: [.myAnimeList: "9999901"]),
        ],
        .annict: [
            未匹配作品(键: 芙莉莲第二季.键, 类型: .anime, 标题: 芙莉莲第二季.原名, 全部标题: [芙莉莲第二季.原名], 年份: 2026, 已知ID: [.myAnimeList: "59978"]),
        ],
    ]

    /// 手动匹配时在 AniList 上搜到的作品。
    static let 匹配候选列表: [匹配候选] = [
        匹配候选(id: "30002", 标题: "ベルセルク", 标题语言: "ja", 其他标题: "Berserk", 其他标题语言: "en", 年份: 1989, 封面: URL(string: 剑风传奇.封面), 种类: "漫画"),
        匹配候选(id: "103236", 标题: "ベルセルク 黄金時代篇 MEMORIAL EDITION", 标题语言: "ja", 其他标题: "剑风传奇 黄金时代篇", 其他标题语言: "zh-Hans", 其他标题为官方: false, 年份: 2022, 种类: "漫画"),
        匹配候选(id: "112456", 标题: "ドゥルアンキ", 标题语言: "ja", 其他标题: "Duranki", 其他标题语言: "en", 年份: 2023, 种类: "漫画"),
    ]

    // MARK: 作品详情

    static let 评论: [视觉小说评论] = [
        视觉小说评论(
            id: "preview-1", source: .bangumi, username: "旅途中的魔法使",
            avatarURL: nil,
            text: "节奏很慢，但每一集都在回味“十年”这个时间单位。看完第一季再回头看第一集，辛美尔的那句话完全是另一种分量。",
            rating: 10, isRecommended: nil, dateText: "2025-10-12", timestamp: nil, language: nil
        ),
        视觉小说评论(
            id: "preview-2", source: .bangumi, username: "北部高原",
            avatarURL: nil,
            text: "一级魔法使考试篇的战斗作画相当用心，配乐也很加分。",
            rating: 9, isRecommended: nil, dateText: "2025-08-03", timestamp: nil, language: nil
        ),
        视觉小说评论(
            id: "preview-3", source: .bangumi, username: "Stark",
            avatarURL: nil,
            text: "喜欢这种安静的冒险故事。",
            rating: 8, isRecommended: nil, dateText: "2024-12-30", timestamp: nil, language: nil
        ),
    ]

    static var 芙莉莲详情: 作品详细信息 {
        var detail = 作品详细信息(
            kind: .anime,
            malID: 芙莉莲.malID,
            类型: .anime,
            标题: 芙莉莲.罗马字,
            日文标题: 芙莉莲.原名,
            英文标题: 芙莉莲.英文,
            封面: 芙莉莲.封面,
            简介: "打倒魔王、结束旅程的勇者一行人各自回到了日常。长寿的精灵魔法使芙莉莲在五十年后与同伴重逢，却在送别勇者时意识到自己从未真正了解过他们。为了“了解人类”，她带着新的同伴，再次踏上了当年的旅途。",
            媒体类型: "tv",
            状态: "finished_airing",
            开始日期: "2023-09-29",
            结束日期: "2024-03-22",
            季度: "2023年秋季",
            集数: 28,
            单集分钟: 24,
            原作: "manga",
            年龄分级: "pg_13",
            MAL评分: 9.28,
            MAL评分人数: 682_314,
            AniList评分: 90,
            AniList人气: 412_087,
            bangumiID: 400_602,
            中文标题: 芙莉莲.中文,
            原名语言: "ja",
            Bangumi评分: 9.0,
            Bangumi评分人数: 48_210,
            Bangumi排名: 12
        )
        detail.类型标签 = ["冒险", "剧情", "奇幻"]
        detail.标签 = [
            .init(名称: "精灵", 是剧透: false),
            .init(名称: "魔法", 是剧透: false),
            .init(名称: "公路片", 是剧透: false),
            .init(名称: "时间跳跃", 是剧透: false),
            .init(名称: "原作漫画改编", 是剧透: false),
            .init(名称: "主要角色死亡", 是剧透: true),
        ]
        detail.制作 = ["Madhouse"]
        detail.角色 = [
            .init(id: 184_947, 名字: "Frieren", 原名: "フリーレン", 图片: nil, 是主角: true, 声优: "Tanezaki, Atsumi", 声优原名: "種﨑敦美"),
            .init(id: 184_949, 名字: "Fern", 原名: "フェルン", 图片: nil, 是主角: true, 声优: "Ichinose, Kana", 声优原名: "市ノ瀬加那"),
            .init(id: 184_948, 名字: "Stark", 原名: "シュタルク", 图片: nil, 是主角: true, 声优: "Kobayashi, Chiaki", 声优原名: "小林千晃"),
            .init(id: 184_950, 名字: "Himmel", 原名: "ヒンメル", 图片: nil, 是主角: false, 声优: "Okamoto, Nobuhiko", 声优原名: "岡本信彦"),
        ]
        detail.制作人员 = [
            .init(名字: "Saitou, Keiichirou", 原名: "斎藤圭一郎", 职责: "导演"),
            .init(名字: "Suzuki, Tomohiro", 原名: "鈴木智尋", 职责: "系列构成"),
            .init(名字: "Evan Call", 职责: "音乐"),
        ]
        detail.相关 = [
            .init(kind: .anime, malID: 芙莉莲第二季.malID, 标题: 芙莉莲第二季.罗马字, 封面: 芙莉莲第二季.封面, 关系: "续集", 多语言标题: 芙莉莲第二季.多语言标题),
            .init(kind: .manga, malID: 芙莉莲漫画.malID, 标题: 芙莉莲漫画.罗马字, 封面: 芙莉莲漫画.封面, 关系: "原作", 多语言标题: 芙莉莲漫画.多语言标题),
        ]
        detail.外部链接 = [.init(站点: "官方网站", 地址: "https://frieren-anime.jp/")]
        return detail
    }
}

// MARK: - 预览环境

extension View {
    /// 注入 App 根视图上的所有环境对象。`已登录` 为 true 时各平台账户都已登录。
    func 预览环境(已登录: Bool = true) -> some View {
        environmentObject(预览数据.vndb(已登录: 已登录))
            .environmentObject(PaperVNPremiumStore(previewing: true))
            .environmentObject(鲲Galgame账户(previewing: true))
            .environmentObject(预览数据.bangumi(已登录: 已登录))
            .environmentObject(预览数据.myAnimeList(已登录: 已登录))
            .environmentObject(预览数据.aniList(已登录: 已登录))
            .environmentObject(预览数据.annict(已登录: 已登录))
            .environmentObject(预览数据.tmdb(已登录: 已登录))
            .environmentObject(家长控制中心.shared)
            .environmentObject(PaperVNURLRouter())
    }
}

/// 一个预览里切换同一界面的多个状态，避免每个状态各占一个画布标签。
/// 顶部的切换栏只在预览里出现：轻点 ‹ › 或中间的菜单切换状态，切换时重新准备数据并重新创建界面。
struct 预览状态切换: View {
    struct 状态 {
        let 名称: Text
        let 准备: () -> Void
        let 内容: () -> AnyView

        init<V: View>(_ 名称: String, 准备: @escaping () -> Void = {}, @ViewBuilder 内容: @escaping () -> V) {
            self.init(名称: Text(verbatim: 名称), 准备: 准备, 内容: 内容)
        }

        /// 名称使用App里已本地化的文字，例如新功能介绍各页的标题。
        init<V: View>(名称: Text, 准备: @escaping () -> Void = {}, @ViewBuilder 内容: @escaping () -> V) {
            self.名称 = 名称
            self.准备 = 准备
            self.内容 = { AnyView(内容()) }
        }
    }

    private let 状态列表: [状态]
    @State private var 选择 = 0
    @State private var 已准备: Int?

    init(_ 状态列表: [状态]) {
        self.状态列表 = 状态列表
    }

    var body: some View {
        VStack(spacing: 0) {
            切换栏
            Group {
                if 已准备 == 选择 {
                    状态列表[选择].内容()
                } else {
                    Color.clear
                }
            }
            .id(选择)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // 在视图更新之外设定共享状态，再显示内容
        .task(id: 选择) {
            状态列表[选择].准备()
            已准备 = 选择
        }
    }

    private var 切换栏: some View {
        HStack(spacing: 12) {
            Button {
                选择 -= 1
            } label: {
                Image(systemName: "chevron.backward")
            }
            .disabled(选择 == 0)

            Menu {
                Picker("状态", selection: $选择) {
                    ForEach(状态列表.indices, id: \.self) { index in
                        状态列表[index].名称.tag(index)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    状态列表[选择].名称
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }

            Text(verbatim: "\(选择 + 1)/\(状态列表.count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Button {
                选择 += 1
            } label: {
                Image(systemName: "chevron.forward")
            }
            .disabled(选择 == 状态列表.count - 1)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// 预览开始前先执行准备（设定共享状态），再显示内容。
struct 预览准备<Content: View>: View {
    private let content: Content

    init(_ prepare: () -> Void, @ViewBuilder content: () -> Content) {
        prepare()
        self.content = content()
    }

    var body: some View { content }
}
#endif
