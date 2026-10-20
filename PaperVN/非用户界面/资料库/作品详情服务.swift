import Foundation

/// 动画、漫画与轻小说详情页用到的整合数据。
/// 视觉小说继续用 VNDB；这里整合 MyAnimeList（简介、类型、制作、相关作品）、
/// AniList（角色与声优、制作人员、标签、外部链接）与 Bangumi（中文标题、评分、吐槽）。
/// 标签和简介不使用 Bangumi。
struct 作品详细信息: Sendable {
    struct 角色: Identifiable, Sendable {
        let id: Int
        let 名字: String
        let 原名: String?
        let 图片: String?
        let 是主角: Bool
        /// 声优的罗马字名与原名，按“制作人员语言”设置显示。
        let 声优: String?
        let 声优原名: String?
    }

    struct 相关作品: Identifiable, Sendable {
        let kind: MyAnimeList列表项.种类
        let malID: Int
        let 标题: String
        let 封面: String?
        let 关系: String
        /// AniList 提供的各语言标题，按标题语言设置显示；没有时用 MAL 的标题。
        var 多语言标题: [用户多语言标题]? = nil
        var id: String { "\(kind.rawValue):\(malID)" }
    }

    struct 标签: Identifiable, Sendable {
        let 名称: String
        let 是剧透: Bool
        var id: String { 名称 }
    }

    struct 人员: Identifiable, Sendable {
        /// 罗马字名与原名，按“制作人员语言”设置显示。
        let 名字: String
        var 原名: String? = nil
        let 职责: String
        var id: String { "\(名字)|\(职责)" }
    }

    struct 链接: Identifiable, Sendable {
        let 站点: String
        let 地址: String
        var id: String { 地址 }
    }

    let kind: MyAnimeList列表项.种类
    let malID: Int
    var 类型: 作品类型
    var 标题: String
    var 日文标题: String?
    var 英文标题: String?
    var 封面: String?
    var 横幅: String?
    /// MAL 的英文简介；TMDB 有界面语言的简介时换成 TMDB 的。
    var 简介: String?
    var 媒体类型: String?
    var 状态: String?
    var 开始日期: String?
    var 结束日期: String?
    var 季度: String?
    var 集数: Int?
    var 单集分钟: Int?
    var 卷数: Int?
    var 话数: Int?
    var 原作: String?
    var 年龄分级: String?
    var MAL评分: Double?
    var MAL评分人数: Int?
    var AniList评分: Int?
    var AniList人气: Int?
    /// 映射目录上线前，按日文原名和日期在 Bangumi 搜索匹配。
    var bangumiID: Int?
    var 中文标题: String?
    /// 日文标题字段的语言：来自 MAL 的 ja 字段时是日语；AniList 提供出品国家时以它为准。
    var 原名语言: String?
    var Bangumi评分: Double?
    var Bangumi评分人数: Int?
    var Bangumi排名: Int?
    var 类型标签: [String] = []
    var 标签: [标签] = []
    var 制作: [String] = []
    var 连载: [String] = []
    var 角色: [角色] = []
    var 制作人员: [人员] = []
    var 相关: [相关作品] = []
    var 外部链接: [链接] = []
    /// TMDB 上的条目（“tv/123”“tv/123/season/2”“movie/123”），来自预装的作品映射。
    var TMDB路径: String?
    var TMDB评分: Double?
    var TMDB评分人数: Int?

    /// 没有 MAL ID 的作品（只在 AniList、Bangumi 上）malID 为 0。
    var malURL: URL? { malID > 0 ? URL(string: "https://myanimelist.net/\(kind.rawValue)/\(malID)") : nil }
    var bangumiURL: URL? { bangumiID.flatMap { URL(string: "https://bgm.tv/subject/\($0)") } }

    /// 各来源评分换算到 10 分制后，按评分人数的对数加权平均；AniList 没有人数，按人气折算。
    var 综合评分: Double? {
        var weighted = 0.0, weights = 0.0
        func add(_ score: Double?, count: Int?) {
            guard let score, score > 0 else { return }
            let weight = log10(Double(max(count ?? 100, 10)))
            weighted += score * weight
            weights += weight
        }
        add(MAL评分, count: MAL评分人数)
        add(Bangumi评分, count: Bangumi评分人数)
        add(AniList评分.map { Double($0) / 10 }, count: AniList人气)
        add(TMDB评分, count: TMDB评分人数)
        return weights > 0 ? weighted / weights : nil
    }

    /// 各语言的标题，按标题语言设置显示。MAL 的标题是罗马字，日文标题是原名，中文标题来自 Bangumi。
    var 多语言标题: [用户多语言标题] {
        作品多语言标题.生成(原名: 日文标题, 原名语言: 原名语言, 罗马字: 标题, 英文: 英文标题, 中文: 中文标题)
    }
}

enum 作品详情错误: LocalizedError {
    case unavailable

    var errorDescription: String? {
        String(localized: "暂时无法获取作品信息，请稍后再试。")
    }
}

/// 获取并缓存作品详情。MAL 与 AniList 并行请求，任意一边成功就能显示。
actor 作品详情服务 {
    static let shared = 作品详情服务()

    private var cache: [String: (savedAt: Date, value: 作品详细信息)] = [:]
    private let lifetime: TimeInterval = 60 * 60

    func 详情(
        kind: MyAnimeList列表项.种类,
        malID: Int,
        accessToken: String?,
        forceRefresh: Bool = false
    ) async throws -> 作品详细信息 {
        let key = "\(kind.rawValue):\(malID)"
        if !forceRefresh, let cached = cache[key], Date().timeIntervalSince(cached.savedAt) < lifetime {
            return cached.value
        }
        async let mal = try? Self.fetchMAL(kind: kind, id: malID, accessToken: accessToken)
        async let anilist = try? Self.fetchAniList(kind: kind, malID: malID)
        let (malValue, aniValue) = await (mal, anilist)
        guard malValue != nil || aniValue != nil else { throw 作品详情错误.unavailable }
        var detail = malValue ?? 作品详细信息(kind: kind, malID: malID, 类型: kind == .anime ? .anime : .manga, 标题: "")
        if let aniValue { Self.merge(aniValue, into: &detail) }
        if let bangumi = try? await Self.matchBangumi(detail) {
            detail.bangumiID = bangumi.id
            detail.中文标题 = bangumi.nameCN.flatMap { $0.isEmpty ? nil : $0 }
            detail.Bangumi评分 = bangumi.rating?.score.flatMap { $0 > 0 ? $0 : nil }
            detail.Bangumi评分人数 = bangumi.rating?.total
            detail.Bangumi排名 = bangumi.rating?.rank.flatMap { $0 > 0 ? $0 : nil }
            // 相关作品：用 Bangumi 的关联条目补上原名和中文名（MAL 只有罗马字标题，AniList 也不一定有）
            if let related = try? await Self.fetchBangumiRelated(bangumi.id) {
                Self.mergeBangumiRelated(related, into: &detail)
            }
        }
        if kind == .anime, TMDB配置.isConfigured, let path = 作品映射.TMDB路径("mal-anime:\(malID)") {
            await Self.mergeTMDB(path, into: &detail)
        }
        cache[key] = (.now, detail)
        return detail
    }

    /// 没有 MAL ID 的作品：AniList 上有就以 AniList 为主，Bangumi 补上中文名和评分；只在 Bangumi 上的用 Bangumi 的条目。
    func 详情(
        kind: MyAnimeList列表项.种类,
        aniListID: Int?,
        bangumiID: Int?,
        bangumiToken: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> 作品详细信息 {
        let key = "\(kind.rawValue):anilist\(aniListID ?? 0):bangumi\(bangumiID ?? 0)"
        if !forceRefresh, let cached = cache[key], Date().timeIntervalSince(cached.savedAt) < lifetime {
            return cached.value
        }
        let 分组 = kind == .anime ? "anime" : "manga"
        let 类型: 作品类型 = kind == .anime ? .anime : .manga
        var detail = 作品详细信息(kind: kind, malID: 0, 类型: 类型, 标题: "")
        var found = false
        if let aniListID, let value = try? await Self.fetchAniList(kind: kind, id: aniListID) {
            Self.merge(value, into: &detail)
            found = true
        }
        let bangumi = bangumiID
            ?? aniListID.flatMap { 作品映射.平台ID("aniList-\(分组):\($0)", 平台: .bangumi, 类型: 类型).flatMap(Int.init) }
        if let bangumi, let subject = try? await Self.fetchBangumiSubject(bangumi, token: bangumiToken) {
            detail.bangumiID = subject.id
            detail.中文标题 = subject.nameCN.flatMap { $0.isEmpty ? nil : $0 }
            detail.Bangumi评分 = subject.rating?.score.flatMap { $0 > 0 ? $0 : nil }
            detail.Bangumi评分人数 = subject.rating?.total
            detail.Bangumi排名 = subject.rating?.rank.flatMap { $0 > 0 ? $0 : nil }
            if !found {
                // Bangumi 的 name 是原名，没有标明语言
                detail.标题 = subject.name
                detail.日文标题 = subject.name
                detail.简介 = subject.summary.flatMap { $0.isEmpty ? nil : $0 }
                detail.封面 = subject.images?.large ?? subject.images?.common
                detail.开始日期 = subject.date
                detail.集数 = kind == .anime ? subject.eps.flatMap { $0 > 0 ? $0 : nil } : nil
                detail.卷数 = kind == .manga ? subject.volumes.flatMap { $0 > 0 ? $0 : nil } : nil
                detail.媒体类型 = subject.platform
                detail.类型标签 = (subject.tags ?? []).prefix(6).map(\.name)
                if kind == .manga, subject.platform == "小说" { detail.类型 = .lightNovel }
            }
            if let url = URL(string: "https://bgm.tv/subject/\(subject.id)"), !detail.外部链接.contains(where: { $0.站点 == "Bangumi" }) {
                detail.外部链接.append(.init(站点: "Bangumi", 地址: url.absoluteString))
            }
            found = true
        }
        guard found else { throw 作品详情错误.unavailable }
        cache[key] = (.now, detail)
        return detail
    }

    private struct Bangumi完整条目: Decodable {
        struct 评分: Decodable { let score: Double?; let total: Int?; let rank: Int? }
        struct 图片: Decodable { let large: String?; let common: String? }
        struct 标签: Decodable { let name: String }
        let id: Int
        let name: String
        let nameCN: String?
        let summary: String?
        let date: String?
        let platform: String?
        let images: 图片?
        let eps: Int?
        let volumes: Int?
        let rating: 评分?
        let tags: [标签]?
        enum CodingKeys: String, CodingKey {
            case id, name, summary, date, platform, images, eps, volumes, rating, tags
            case nameCN = "name_cn"
        }
    }

    /// Bangumi 不向未登录的请求返回成人条目，登录了 Bangumi 时带上令牌。
    private static func fetchBangumiSubject(_ id: Int, token: String?) async throws -> Bangumi完整条目 {
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/subjects/\(id)")!, timeoutInterval: 15)
        request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw 作品详情错误.unavailable }
        return try JSONDecoder().decode(Bangumi完整条目.self, from: data)
    }

    // MARK: TMDB

    /// TMDB 有各语言的简介：界面语言不是英语、TMDB 上有这种语言的简介时，用它代替 MAL 的英文简介。
    /// 评分只取电影和第一季（TMDB 的剧集评分是整部剧的，不能算作第二季以后的评分）。
    private static func mergeTMDB(_ path: String, into detail: inout 作品详细信息) async {
        struct 条目: Decodable { let overview: String?; let vote_average: Double?; let vote_count: Int? }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return }
        let base = "\(parts[0])/\(parts[1])"
        let language = [URLQueryItem(name: "language", value: TMDB配置.语言)]
        let laterSeason = parts.count == 4 && parts[3] != "1"
        var overview: String?
        if parts.count == 4, let data = try? await TMDB配置.请求("3/\(path)", query: language),
           let season = try? JSONDecoder().decode(条目.self, from: data) {
            overview = season.overview
        }
        if let data = try? await TMDB配置.请求("3/\(base)", query: language),
           let show = try? JSONDecoder().decode(条目.self, from: data) {
            if !laterSeason, overview?.isEmpty != false { overview = show.overview }
            if !laterSeason, let score = show.vote_average, score > 0, (show.vote_count ?? 0) > 0 {
                detail.TMDB评分 = score
                detail.TMDB评分人数 = show.vote_count
            }
        }
        detail.TMDB路径 = path
        if !TMDB配置.语言.hasPrefix("en"), let overview = overview?.trimmingCharacters(in: .whitespacesAndNewlines), !overview.isEmpty {
            detail.简介 = overview
        }
        if let url = URL(string: "https://www.themoviedb.org/\(base)"), !detail.外部链接.contains(where: { $0.站点 == "TMDB" }) {
            detail.外部链接.append(.init(站点: "TMDB", 地址: url.absoluteString))
        }
    }

    // MARK: MyAnimeList

    private struct MAL作品: Decodable {
        struct 图片: Decodable { let medium: String?; let large: String? }
        struct 别名: Decodable { let en: String?; let ja: String?; let synonyms: [String]? }
        struct 名称: Decodable { let name: String }
        struct 季度: Decodable { let year: Int; let season: String }
        struct 作者: Decodable {
            struct 节点: Decodable { let firstName: String?; let lastName: String?
                enum CodingKeys: String, CodingKey { case firstName = "first_name"; case lastName = "last_name" } }
            let node: 节点
            let role: String?
        }
        struct 连载: Decodable { struct 节点: Decodable { let name: String }; let node: 节点 }
        struct 相关: Decodable {
            struct 节点: Decodable { let id: Int; let title: String; let mainPicture: 图片?
                enum CodingKeys: String, CodingKey { case id, title; case mainPicture = "main_picture" } }
            let node: 节点
            let relationType: String?
            let relationTypeFormatted: String?
            enum CodingKeys: String, CodingKey {
                case node
                case relationType = "relation_type"
                case relationTypeFormatted = "relation_type_formatted"
            }
        }

        let id: Int
        let title: String
        let mainPicture: 图片?
        let alternativeTitles: 别名?
        let startDate: String?
        let endDate: String?
        let synopsis: String?
        let mean: Double?
        let numScoringUsers: Int?
        let mediaType: String?
        let status: String?
        let genres: [名称]?
        let numEpisodes: Int?
        let averageEpisodeDuration: Int?
        let startSeason: 季度?
        let source: String?
        let rating: String?
        let studios: [名称]?
        let numVolumes: Int?
        let numChapters: Int?
        let authors: [作者]?
        let serialization: [连载]?
        let relatedAnime: [相关]?
        let relatedManga: [相关]?

        enum CodingKeys: String, CodingKey {
            case id, title, synopsis, mean, status, genres, source, rating, studios, authors, serialization
            case mainPicture = "main_picture"
            case alternativeTitles = "alternative_titles"
            case startDate = "start_date"
            case endDate = "end_date"
            case numScoringUsers = "num_scoring_users"
            case mediaType = "media_type"
            case numEpisodes = "num_episodes"
            case averageEpisodeDuration = "average_episode_duration"
            case startSeason = "start_season"
            case numVolumes = "num_volumes"
            case numChapters = "num_chapters"
            case relatedAnime = "related_anime"
            case relatedManga = "related_manga"
        }
    }

    private static func fetchMAL(kind: MyAnimeList列表项.种类, id: Int, accessToken: String?) async throws -> 作品详细信息 {
        let common = "id,title,main_picture,alternative_titles,start_date,end_date,synopsis,mean,num_scoring_users,media_type,status,genres,related_anime,related_manga"
        let fields = kind == .anime
            ? common + ",num_episodes,average_episode_duration,start_season,source,rating,studios"
            : common + ",num_volumes,num_chapters,authors{first_name,last_name},serialization{name}"
        var components = URLComponents(string: "https://api.myanimelist.net/v2/\(kind.rawValue)/\(id)")!
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else if MyAnimeListOAuth配置.isConfigured {
            // 未登录时用 Client ID 读取公开数据
            request.setValue(MyAnimeListOAuth配置.clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        } else {
            throw 作品详情错误.unavailable
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw 作品详情错误.unavailable }
        let raw = try JSONDecoder().decode(MAL作品.self, from: data)

        var detail = 作品详细信息(
            kind: kind,
            malID: raw.id,
            类型: kind == .anime ? .anime : (["light_novel", "novel"].contains(raw.mediaType ?? "") ? .lightNovel : .manga),
            标题: raw.title
        )
        detail.日文标题 = raw.alternativeTitles?.ja.flatMap { $0.isEmpty ? nil : $0 }
        detail.原名语言 = detail.日文标题 == nil ? nil : (作品映射.原名语言(detail.类型, malID: raw.id) ?? "ja")
        detail.英文标题 = raw.alternativeTitles?.en.flatMap { $0.isEmpty ? nil : $0 }
        detail.封面 = raw.mainPicture?.large ?? raw.mainPicture?.medium
        detail.简介 = raw.synopsis.flatMap { $0.isEmpty ? nil : $0 }
        detail.媒体类型 = raw.mediaType
        detail.状态 = raw.status
        detail.开始日期 = raw.startDate
        detail.结束日期 = raw.endDate
        detail.季度 = raw.startSeason.map { "\($0.year) \($0.season)" }
        detail.集数 = raw.numEpisodes.flatMap { $0 > 0 ? $0 : nil }
        detail.单集分钟 = raw.averageEpisodeDuration.flatMap { $0 > 0 ? $0 / 60 : nil }
        detail.卷数 = raw.numVolumes.flatMap { $0 > 0 ? $0 : nil }
        detail.话数 = raw.numChapters.flatMap { $0 > 0 ? $0 : nil }
        detail.原作 = raw.source
        detail.年龄分级 = raw.rating
        detail.MAL评分 = raw.mean
        detail.MAL评分人数 = raw.numScoringUsers
        detail.类型标签 = raw.genres?.map(\.name) ?? []
        detail.制作 = raw.studios?.map(\.name)
            ?? raw.authors?.map { author in
                let name = [author.node.firstName, author.node.lastName]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }
                    .joined(separator: " ")
                return author.role.map { "\(name)（\($0)）" } ?? name
            } ?? []
        detail.连载 = raw.serialization?.map(\.node.name) ?? []
        // 动画按 Annict 划分作品：并在这部作品里的 MAL 特别篇（映射里的附属条目）不算相关作品
        let ownKey = "mal-\(kind == .anime ? "anime" : "manga"):\(raw.id)"
        let relatedAnime = (raw.relatedAnime ?? []).filter {
            作品映射.查找(.myAnimeList, 平台ID: String($0.node.id), 类型: .anime) != 作品映射.结果(键: ownKey, 附属: true)
        }
        detail.相关 = relatedAnime.map { 作品详细信息.相关作品(kind: .anime, malID: $0.node.id, 标题: $0.node.title, 封面: $0.node.mainPicture?.medium, 关系: 关系名称($0.relationType, 原文: $0.relationTypeFormatted, 当前种类: kind)) }
            + (raw.relatedManga ?? []).map { 作品详细信息.相关作品(kind: .manga, malID: $0.node.id, 标题: $0.node.title, 封面: $0.node.mainPicture?.medium, 关系: 关系名称($0.relationType, 原文: $0.relationTypeFormatted, 当前种类: kind)) }
        return detail
    }

    // MARK: Bangumi

    private struct Bangumi条目: Decodable {
        struct 评分: Decodable { let score: Double?; let total: Int?; let rank: Int? }
        let id: Int
        let name: String
        let nameCN: String?
        let date: String?
        let rating: 评分?
        enum CodingKeys: String, CodingKey { case id, name, date, rating; case nameCN = "name_cn" }
    }

    private struct Bangumi搜索结果: Decodable { let data: [Bangumi条目] }

    /// MAL 的关联类型换成本地化的名称，能对应的沿用视觉小说的关联名称；不认识的类型用 MAL 的原文。
    private static func 关系名称(_ type: String?, 原文: String?, 当前种类: MyAnimeList列表项.种类) -> String {
        switch type {
        // 与视觉小说（VNDB）相同的关联名称
        case "sequel": String(localized: "续作")
        case "prequel": String(localized: "前作")
        case "alternative_setting": String(localized: "平行设定")
        case "alternative_version": String(localized: "其他版本")
        case "side_story": String(localized: "外传")
        case "parent_story": String(localized: "系列")
        case "character": String(localized: "相同角色")
        // 视觉小说没有对应的关联
        case "summary": String(localized: "总集篇")
        case "full_story": String(localized: "完整版")
        case "spin_off": String(localized: "作品")
        // MAL 的“改编”不分方向：在动画页面里通常指原作漫画或小说（沿用视觉小说的“原作”），在漫画、轻小说页面里指改编出的作品
        case "adaptation": 当前种类 == .anime ? String(localized: "原作") : String(localized: "改编")
        case "other": String(localized: "其他")
        default: 原文 ?? ""
        }
    }

    private struct Bangumi关联条目: Decodable {
        let id: Int
        let type: Int
        let name: String
        let nameCN: String?
        enum CodingKeys: String, CodingKey { case id, type, name; case nameCN = "name_cn" }
    }

    private static func fetchBangumiRelated(_ id: Int) async throws -> [Bangumi关联条目] {
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/subjects/\(id)/subjects")!, timeoutInterval: 15)
        request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return try JSONDecoder().decode([Bangumi关联条目].self, from: data)
    }

    /// 把 Bangumi 的关联条目对应到 MAL 的相关作品：先查预装的作品映射，其余按统一写法后的标题对应，唯一才采用。
    /// 对上后补上 Bangumi 的原名和中文名。
    private static func mergeBangumiRelated(_ related: [Bangumi关联条目], into detail: inout 作品详细信息) {
        for index in detail.相关.indices {
            let item = detail.相关[index]
            let bangumiType = item.kind == .anime ? 2 : 1
            let candidates = related.filter { $0.type == bangumiType }
            var match: Bangumi关联条目?
            if let id = Self.映射的Bangumi条目(kind: item.kind, malID: item.malID) {
                match = candidates.first { $0.id == id }
            }
            if match == nil {
                let keys = Set(([item.标题] + (item.多语言标题 ?? []).map(\.title)).map(同步合并.标题匹配键))
                let found = candidates.filter { candidate in
                    [candidate.name, candidate.nameCN].compactMap { $0 }.contains { keys.contains(同步合并.标题匹配键($0)) }
                }
                if found.count == 1 { match = found[0] }
            }
            guard let match else { continue }
            let chinese = match.nameCN.flatMap { $0.isEmpty ? nil : $0 }
            detail.相关[index].多语言标题 = 作品多语言标题.合并([
                item.多语言标题 ?? 作品多语言标题.生成(原名: nil, 罗马字: item.标题),
                作品多语言标题.生成(原名: match.name, 罗马字: nil, 中文: chinese),
            ])
        }
    }

    private struct Bangumi条目详情: Decodable {
        struct 评分: Decodable { let score: Double?; let total: Int?; let rank: Int? }
        let id: Int
        let name: String
        let nameCN: String?
        let date: String?
        let rating: 评分?
        enum CodingKeys: String, CodingKey { case id, name, date, rating; case nameCN = "name_cn" }
    }

    /// 预装的作品映射中，MAL 作品对应的 Bangumi 主条目。
    private static func 映射的Bangumi条目(kind: MyAnimeList列表项.种类, malID: Int) -> Int? {
        let anime = kind == .anime
        return 作品映射.平台ID("mal-\(anime ? "anime" : "manga"):\(malID)", 平台: .bangumi, 类型: anime ? .anime : .manga).flatMap(Int.init)
    }

    /// 先查预装的作品映射，查不到再按标题搜索（只用于显示详情，不影响同步）。
    private static func matchBangumi(_ detail: 作品详细信息) async throws -> Bangumi条目? {
        if let id = Self.映射的Bangumi条目(kind: detail.kind, malID: detail.malID) {
            var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/subjects/\(id)")!, timeoutInterval: 15)
            request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let subject = try? JSONDecoder().decode(Bangumi条目.self, from: data) {
                return subject
            }
        }
        return try await searchBangumi(detail)
    }

    /// 映射目录上线前的临时匹配：用日文原名搜索，名称完全一致优先，其次是开始日期相同（年月）的条目。
    private static func searchBangumi(_ detail: 作品详细信息) async throws -> Bangumi条目? {
        let keyword = detail.日文标题 ?? detail.标题
        guard !keyword.isEmpty else { return nil }
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/search/subjects?limit=10")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
        // Bangumi 条目类型：1 书籍（漫画、轻小说），2 动画
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyword": keyword,
            "filter": ["type": [detail.kind == .anime ? 2 : 1]],
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let candidates = try JSONDecoder().decode(Bangumi搜索结果.self, from: data).data

        func normalized(_ value: String) -> String {
            value.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
        }
        let names = [detail.日文标题, detail.标题, detail.英文标题].compactMap { $0 }.map(normalized)
        if let exact = candidates.first(where: { names.contains(normalized($0.name)) }) {
            return exact
        }
        let month = detail.开始日期.map { String($0.prefix(7)) }
        if let month, month.count == 7,
           let sameMonth = candidates.first(where: { $0.date?.hasPrefix(month) == true }) {
            return sameMonth
        }
        return nil
    }

    // MARK: AniList

    private struct AniList响应: Decodable {
        struct 数据: Decodable { let Media: 作品? }
        struct 作品: Decodable {
            struct 图片: Decodable { let extraLarge: String?; let large: String? }
            struct 标签: Decodable { let name: String; let rank: Int?; let isMediaSpoiler: Bool?; let isGeneralSpoiler: Bool? }
            struct 名字: Decodable { let full: String?; let native: String? }
            struct 角色连接: Decodable {
                struct 边: Decodable {
                    struct 节点: Decodable { let id: Int; let name: 名字?; let image: 小图? }
                    struct 声优: Decodable { let name: 名字? }
                    let role: String?
                    let node: 节点?
                    let voiceActors: [声优]?
                }
                let edges: [边]?
            }
            struct 人员连接: Decodable {
                struct 边: Decodable {
                    struct 节点: Decodable { let name: 名字? }
                    let role: String?
                    let node: 节点?
                }
                let edges: [边]?
            }
            struct 小图: Decodable { let medium: String?; let large: String? }
            struct 链接: Decodable { let site: String; let url: String? }
            struct 标题: Decodable { let romaji: String?; let english: String?; let native: String? }
            struct 日期: Decodable { let year: Int?; let month: Int?; let day: Int?
                var text: String? {
                    guard let year else { return nil }
                    guard let month else { return String(format: "%04d", year) }
                    guard let day else { return String(format: "%04d-%02d", year, month) }
                    return String(format: "%04d-%02d-%02d", year, month, day)
                }
            }

            let title: 标题?
            let countryOfOrigin: String?
            let format: String?
            let status: String?
            let startDate: 日期?
            let endDate: 日期?
            let season: String?
            let seasonYear: Int?
            let episodes: Int?
            let duration: Int?
            let chapters: Int?
            let volumes: Int?
            let genres: [String]?
            let source: String?
            let description: String?
            let averageScore: Int?
            let popularity: Int?
            let bannerImage: String?
            let coverImage: 图片?
            let tags: [标签]?
            let characters: 角色连接?
            let staff: 人员连接?
            let externalLinks: [链接]?
            struct 关联连接: Decodable {
                struct 边: Decodable {
                    struct 节点: Decodable { let idMal: Int?; let countryOfOrigin: String?; let title: 标题? }
                    let node: 节点?
                }
                let edges: [边]?
            }
            let relations: 关联连接?
        }
        let data: 数据?
    }

    private struct AniList结果 {
        var 标题: String?
        var 英文标题: String?
        var 日文标题: String?
        var 媒体类型: String?
        var 状态: String?
        var 开始日期: String?
        var 结束日期: String?
        var 季度: String?
        var 集数: Int?
        var 单集分钟: Int?
        var 卷数: Int?
        var 话数: Int?
        var 类型标签: [String]
        var 原作: String?
        var 简介: String?
        var 评分: Int?
        var 人气: Int?
        var 横幅: String?
        var 封面: String?
        var 标签: [作品详细信息.标签]
        var 角色: [作品详细信息.角色]
        var 人员: [作品详细信息.人员]
        var 链接: [作品详细信息.链接]
        /// 相关作品的 MAL ID → 各语言标题。
        var 相关标题: [Int: [用户多语言标题]] = [:]
        /// 原名的语言，由 AniList 的出品国家决定。
        var 原名语言: String? = nil
    }

    /// 按 MAL ID 或 AniList 自己的 ID 读取。
    private static func fetchAniList(kind: MyAnimeList列表项.种类, malID: Int? = nil, id: Int? = nil) async throws -> AniList结果 {
        let query = """
        query ($idMal: Int, $id: Int, $type: MediaType) {
          Media(idMal: $idMal, id: $id, type: $type) {
            title { romaji english native }
            countryOfOrigin
            format
            status
            startDate { year month day }
            endDate { year month day }
            season
            seasonYear
            episodes
            duration
            chapters
            volumes
            genres
            source
            description(asHtml: false)
            averageScore
            popularity
            bannerImage
            coverImage { extraLarge large }
            tags { name rank isMediaSpoiler isGeneralSpoiler }
            characters(sort: [ROLE, RELEVANCE], perPage: 16) {
              edges { role node { id name { full native } image { medium large } } voiceActors(language: JAPANESE) { name { full native } } }
            }
            staff(sort: [RELEVANCE], perPage: 16) { edges { role node { name { full native } } } }
            relations { edges { node { idMal type countryOfOrigin title { romaji english native } } } }
            externalLinks { site url }
          }
        }
        """
        var variables: [String: Any] = ["type": kind == .anime ? "ANIME" : "MANGA"]
        if let malID { variables["idMal"] = malID } else { variables["id"] = id ?? 0 }
        let body: [String: Any] = [
            "query": query,
            "variables": variables,
        ]
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let media = try JSONDecoder().decode(AniList响应.self, from: data).data?.Media else {
            throw 作品详情错误.unavailable
        }
        var result = AniList结果(
            标题: media.title?.romaji,
            英文标题: media.title?.english,
            日文标题: media.title?.native,
            媒体类型: media.format?.lowercased(),
            状态: media.status.map(状态映射),
            开始日期: media.startDate?.text,
            结束日期: media.endDate?.text,
            季度: media.seasonYear.map { year in media.season.map { "\(year) \($0.lowercased())" } ?? "\(year)" },
            集数: media.episodes,
            单集分钟: media.duration,
            卷数: media.volumes,
            话数: media.chapters,
            类型标签: media.genres ?? [],
            原作: media.source?.lowercased(),
            简介: media.description.map(纯文本),
            评分: media.averageScore,
            人气: media.popularity,
            横幅: media.bannerImage,
            封面: media.coverImage?.extraLarge ?? media.coverImage?.large,
            标签: (media.tags ?? [])
                .filter { ($0.rank ?? 0) >= 50 }
                .map { 作品详细信息.标签(名称: $0.name, 是剧透: ($0.isMediaSpoiler ?? false) || ($0.isGeneralSpoiler ?? false)) },
            角色: (media.characters?.edges ?? []).compactMap { edge in
                guard let node = edge.node else { return nil }
                let name = node.name?.full ?? node.name?.native ?? ""
                guard !name.isEmpty else { return nil }
                let actor = edge.voiceActors?.first?.name
                return 作品详细信息.角色(
                    id: node.id,
                    名字: name,
                    原名: node.name?.native,
                    图片: node.image?.large ?? node.image?.medium,
                    是主角: edge.role == "MAIN",
                    声优: actor?.full ?? actor?.native,
                    声优原名: actor?.native
                )
            },
            人员: (media.staff?.edges ?? []).compactMap { edge in
                guard let name = edge.node?.name?.full ?? edge.node?.name?.native else { return nil }
                return 作品详细信息.人员(名字: name, 原名: edge.node?.name?.native, 职责: edge.role ?? "")
            },
            链接: (media.externalLinks ?? []).compactMap { link in
                link.url.map { 作品详细信息.链接(站点: link.site, 地址: $0) }
            },
            相关标题: Dictionary(
                (media.relations?.edges ?? []).compactMap { edge -> (Int, [用户多语言标题])? in
                    guard let node = edge.node, let malID = node.idMal else { return nil }
                    return (malID, 作品多语言标题.生成(
                        原名: node.title?.native,
                        原名语言: 作品多语言标题.语言(国家: node.countryOfOrigin),
                        罗马字: node.title?.romaji,
                        英文: node.title?.english
                    ))
                },
                uniquingKeysWith: { first, _ in first }
            )
        )
        result.原名语言 = 作品多语言标题.语言(国家: media.countryOfOrigin)
        return result
    }

    /// AniList 的状态换成 MAL 的写法，详情页只认一套。
    private static func 状态映射(_ value: String) -> String {
        switch value {
        case "FINISHED": "finished"
        case "RELEASING": "currently_airing"
        case "NOT_YET_RELEASED": "not_yet_aired"
        case "CANCELLED": "discontinued"
        case "HIATUS": "on_hiatus"
        default: value.lowercased()
        }
    }

    private static func merge(_ value: AniList结果, into detail: inout 作品详细信息) {
        // 基础字段以 MAL 为准，MAL 拿不到（比如还没有 Client ID）时用 AniList 补上
        if detail.标题.isEmpty { detail.标题 = value.标题 ?? value.日文标题 ?? "" }
        if detail.日文标题 == nil {
            detail.日文标题 = value.日文标题
            detail.原名语言 = value.原名语言
        }
        // AniList 标明了出品国家时以它为准（MAL 把中国、韩国作品的原名也放在 ja 字段）
        if let language = value.原名语言, detail.日文标题 != nil { detail.原名语言 = language }
        if detail.英文标题 == nil { detail.英文标题 = value.英文标题 }
        if detail.媒体类型 == nil { detail.媒体类型 = value.媒体类型 }
        if detail.状态 == nil {
            detail.状态 = detail.kind == .manga && value.状态 == "currently_airing" ? "currently_publishing" : value.状态
        }
        if detail.开始日期 == nil { detail.开始日期 = value.开始日期 }
        if detail.结束日期 == nil { detail.结束日期 = value.结束日期 }
        if detail.季度 == nil { detail.季度 = value.季度 }
        if detail.集数 == nil { detail.集数 = value.集数 }
        if detail.单集分钟 == nil { detail.单集分钟 = value.单集分钟 }
        if detail.卷数 == nil { detail.卷数 = value.卷数 }
        if detail.话数 == nil { detail.话数 = value.话数 }
        if detail.类型标签.isEmpty { detail.类型标签 = value.类型标签 }
        if detail.原作 == nil { detail.原作 = value.原作 }
        if detail.kind == .manga, ["novel", "light_novel"].contains(value.媒体类型 ?? "") {
            detail.类型 = .lightNovel
        }
        // 简介以 MAL 为准，MAL 没有时才用 AniList
        if detail.简介 == nil { detail.简介 = value.简介 }
        if detail.封面 == nil { detail.封面 = value.封面 }
        detail.横幅 = value.横幅
        detail.AniList评分 = value.评分
        detail.AniList人气 = value.人气
        detail.标签 = value.标签
        detail.角色 = value.角色
        detail.制作人员 = value.人员
        detail.外部链接 = value.链接
        for index in detail.相关.indices {
            detail.相关[index].多语言标题 = value.相关标题[detail.相关[index].malID]
        }
    }

    /// AniList 的简介即使要求纯文本也可能带 <br> 和 <i>。
    private static func 纯文本(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\n\n\n", with: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
