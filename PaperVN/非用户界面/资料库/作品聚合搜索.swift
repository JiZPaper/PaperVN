import Foundation

/// 搜索页里的一部动画、漫画或轻小说。作品的划分和资料库一致（动画以 Annict 为准、漫画与轻小说以 MAL 为准），
/// 不同平台搜到的同一部作品合成一条。数据源是综合的：没有 MAL ID 的作品用 AniList 或 Bangumi 的 ID。
struct 作品搜索结果: Identifiable, Hashable, Sendable {
    /// 和 Hiro智能的条目编号一致：“a”“m”“n”加编号，例如“a10495”。编号是 MAL ID；
    /// 没有 MAL ID 时最高位标出来源：0x8000_0000 | AniList ID，0x4000_0000 | Bangumi ID。
    let id: String
    let 类型: 作品类型
    /// 没有 MAL ID 时为 0。
    let malID: Int
    var aniListID: Int? = nil
    var bangumiID: Int? = nil
    var 标题: String
    var 多语言标题: [用户多语言标题]
    var 封面: String?
    var 年份: Int?
    /// 平台标明的格式（TV、MOVIE、MANGA 等），只用来显示。
    var 格式: String?
    var 成人内容 = false

    var 详情目标: 作品详情目标 {
        作品详情目标(kind: 类型 == .anime ? .anime : .manga, malID: malID, 标题: 标题, 封面: 封面, aniListID: aniListID, bangumiID: bangumiID)
    }

    /// 资料库与作品映射里的编号，例如“mal-anime:10495”“aniList-manga:101444”。
    nonisolated var 作品键: String {
        let 分组 = 类型 == .anime ? "anime" : "manga"
        if malID > 0 { return "mal-\(分组):\(malID)" }
        if let aniListID { return "aniList-\(分组):\(aniListID)" }
        return "bangumi-\(分组):\(bangumiID ?? 0)"
    }

    nonisolated static let AniList标记: UInt32 = 0x8000_0000
    nonisolated static let Bangumi标记: UInt32 = 0x4000_0000

    nonisolated static func 编号(类型 type: 作品类型, malID: Int, aniListID: Int? = nil, bangumiID: Int? = nil) -> String {
        let 数字: UInt32
        if malID > 0 { 数字 = UInt32(malID) }
        else if let aniListID { 数字 = AniList标记 | UInt32(aniListID) }
        else { 数字 = Bangumi标记 | UInt32(bangumiID ?? 0) }
        switch type {
        case .anime: return "a\(数字)"
        case .lightNovel: return "n\(数字)"
        case .manga, .visualNovel: return "m\(数字)"
        }
    }

    /// 解开编号：（类型、MAL ID、AniList ID、Bangumi ID）。
    nonisolated static func 解析(_ id: String) -> (类型: 作品类型, malID: Int, aniListID: Int?, bangumiID: Int?)? {
        guard let 前缀 = id.first, let 数字 = UInt32(id.dropFirst()) else { return nil }
        let type: 作品类型
        switch 前缀 {
        case "a": type = .anime
        case "m": type = .manga
        case "n": type = .lightNovel
        default: return nil
        }
        if 数字 & AniList标记 != 0 { return (type, 0, Int(数字 & ~AniList标记), nil) }
        if 数字 & Bangumi标记 != 0 { return (type, 0, nil, Int(数字 & ~Bangumi标记)) }
        if 数字 & 0x2000_0000 != 0 { return nil }  // 只在 Annict 上的作品：没有可以打开的详情
        return (type, Int(数字), nil, nil)
    }
}

/// 动画、漫画与轻小说的搜索：
/// - Hiro智能在设备上找到的作品，用 MAL ID 向 AniList 批量读取标题和封面；
/// - 同时在各平台（AniList、Bangumi，以及已登录的 MyAnimeList、Annict、TMDB）上按关键词搜索，
///   用预装的作品映射把各平台的条目归到同一部作品，多个平台都搜到的排在前面。
@MainActor
final class 作品聚合搜索 {
    static let shared = 作品聚合搜索()

    private var 详情缓存: [String: 作品搜索结果] = [:]
    nonisolated private static let 等待秒数: Double = 4

    /// Hiro智能找到的作品的标题和封面：有 MAL ID 或 AniList ID 的向 AniList 批量读取，只在 Bangumi 上的读 Bangumi。
    /// AniList 上没有的 MAL 作品（例如一些总集篇）再向 Bangumi 读（按作品映射里的 Bangumi 条目）。
    func 详情(_ 编号: [String]) async -> [String: 作品搜索结果] {
        var 结果: [String: 作品搜索结果] = [:]
        var 动画MAL: [Int] = [], 书籍MAL: [Int] = [], 动画AniList: [Int] = [], 书籍AniList: [Int] = []
        var Bangumi: [(String, 作品类型, Int)] = []
        for id in 编号 {
            if let cached = 详情缓存[id] {
                结果[id] = cached
                continue
            }
            guard let parsed = 作品搜索结果.解析(id) else { continue }
            let 动画 = parsed.类型 == .anime
            if parsed.malID > 0 { 动画 ? 动画MAL.append(parsed.malID) : 书籍MAL.append(parsed.malID) }
            else if let ani = parsed.aniListID { 动画 ? 动画AniList.append(ani) : 书籍AniList.append(ani) }
            else if let bgm = parsed.bangumiID { Bangumi.append((id, parsed.类型, bgm)) }
        }
        if !(动画MAL + 书籍MAL + 动画AniList + 书籍AniList).isEmpty {
            struct 响应: Decodable {
                struct 页: Decodable { let media: [AniList作品] }
                struct 数据: Decodable { let a: 页?; let b: 页?; let c: 页?; let d: 页? }
                let data: 数据
            }
            if let data = try? await 平台账户工具.graphQL(
                endpoint: AniListOAuth配置.endpoint,
                platform: "AniList",
                accessToken: nil,
                query: """
                query ($a: [Int], $b: [Int], $c: [Int], $d: [Int]) {
                  a: Page(perPage: 50) { media(idMal_in: $a, type: ANIME) { \(AniList作品.字段) } }
                  b: Page(perPage: 50) { media(idMal_in: $b, type: MANGA) { \(AniList作品.字段) } }
                  c: Page(perPage: 50) { media(id_in: $c, type: ANIME) { \(AniList作品.字段) } }
                  d: Page(perPage: 50) { media(id_in: $d, type: MANGA) { \(AniList作品.字段) } }
                }
                """,
                variables: ["a": Array(动画MAL.prefix(50)), "b": Array(书籍MAL.prefix(50)),
                            "c": Array(动画AniList.prefix(50)), "d": Array(书籍AniList.prefix(50))]
            ), let decoded = try? JSONDecoder().decode(响应.self, from: data) {
                let pages = [decoded.data.a, decoded.data.b, decoded.data.c, decoded.data.d]
                for media in pages.flatMap({ $0?.media ?? [] }) {
                    // 按 AniList ID 查到的作品用请求时的编号（AniList 后来补上了 MAL ID 也一样）
                    for item in media.结果(请求的编号: 编号) {
                        详情缓存[item.id] = item
                        结果[item.id] = item
                    }
                }
            }
        }
        // AniList 上没有的：用作品映射里的 Bangumi 条目
        for id in 编号 where 结果[id] == nil {
            guard let parsed = 作品搜索结果.解析(id), parsed.bangumiID == nil else { continue }
            let 分组 = parsed.类型 == .anime ? "anime" : "manga"
            let key = parsed.malID > 0 ? "mal-\(分组):\(parsed.malID)" : "aniList-\(分组):\(parsed.aniListID ?? 0)"
            if let bgm = 作品映射.平台ID(key, 平台: .bangumi, 类型: parsed.类型).flatMap(Int.init) {
                Bangumi.append((id, parsed.类型, bgm))
            }
        }
        // Bangumi 不向未登录的请求返回成人条目，登录了 Bangumi 时带上令牌
        let token = Bangumi.isEmpty ? nil : try? await PaperVNSync中心.shared.bangumi?.validAccessToken()
        await withTaskGroup(of: (String, 作品搜索结果)?.self) { group in
            for (id, type, bgm) in Bangumi.prefix(20) {
                group.addTask { await Self.Bangumi条目(id: id, 类型: type, bangumiID: bgm, token: token) }
            }
            for await item in group {
                guard let (id, value) = item else { continue }
                详情缓存[id] = value
                结果[id] = value
            }
        }
        return 结果
    }

    /// 读取 Bangumi 条目的标题、封面和年份，作为搜索结果。编号保持请求时的写法。
    nonisolated private static func Bangumi条目(id: String, 类型 type: 作品类型, bangumiID: Int, token: String?) async -> (String, 作品搜索结果)? {
        struct 条目: Decodable {
            struct 图片: Decodable { let large: String?; let common: String? }
            let name: String
            let name_cn: String?
            let date: String?
            let platform: String?
            let nsfw: Bool?
            let images: 图片?
        }
        guard let parsed = 作品搜索结果.解析(id) else { return nil }
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/subjects/\(bangumiID)")!, timeoutInterval: 10)
        request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let subject = try? JSONDecoder().decode(条目.self, from: data) else { return nil }
        let chinese = subject.name_cn.flatMap { $0.isEmpty || $0 == subject.name ? nil : $0 }
        return (id, 作品搜索结果(
            id: id,
            类型: type,
            malID: parsed.malID,
            aniListID: parsed.aniListID,
            bangumiID: bangumiID,
            标题: subject.name,
            // Bangumi 的 name 没有标明语言；中文名由用户编辑，按非官方标题处理
            多语言标题: 作品多语言标题.生成(原名: subject.name, 罗马字: nil, 中文: chinese),
            封面: subject.images?.large ?? subject.images?.common,
            年份: subject.date.flatMap { Int($0.prefix(4)) },
            格式: subject.platform,
            成人内容: subject.nsfw ?? false
        ))
    }

    /// 在各平台上按关键词搜索，按相关程度排好。没登录的平台、请求失败的平台跳过。
    func 在线搜索(_ 关键词: String) async -> [作品搜索结果] {
        let text = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let sync = PaperVNSync中心.shared
        // 各平台的搜索请求：平台、搜索时用的类型（轻小说在各平台上都和漫画一起搜）
        let 请求: [(资料库平台, 作品类型)] = [
            (.aniList, .anime), (.aniList, .manga),
            (.bangumi, .anime), (.bangumi, .manga),
            (.myAnimeList, .anime), (.myAnimeList, .manga),
            (.annict, .anime), (.tmdb, .anime),
        ]
        // 搜索页等所有结果回来才显示，慢的平台最多等 4 秒，超时的不算
        let 各平台结果 = await withTaskGroup(of: (Int, [匹配候选])?.self) { group in
            for index in 请求.indices {
                let platform = 请求[index].0
                let type = 请求[index].1
                group.addTask {
                    let candidates = await Self.搜索(sync, platform, type, text)
                    return (index, candidates)
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(Self.等待秒数))
                return nil
            }
            var all: [Int: [匹配候选]] = [:]
            for await result in group {
                guard let result else { break }
                all[result.0] = result.1
                if all.count == 请求.count { break }
            }
            group.cancelAll()
            return all
        }

        var 得分: [String: Double] = [:]
        var 合并: [String: 作品搜索结果] = [:]
        var 标题来源: [String: [[用户多语言标题]]] = [:]
        for index in 请求.indices {
            let (platform, type) = 请求[index]
            for (rank, candidate) in (各平台结果[index] ?? []).enumerated() {
                guard let item = Self.结果(candidate, 平台: platform, 搜索类型: type) else { continue }
                // 多个平台都搜到、排得靠前的作品更可能是要找的
                得分[item.id, default: 0] += 1 / Double(rank + 2)
                标题来源[item.id, default: []].append(item.多语言标题)
                if var existing = 合并[item.id] {
                    existing.封面 = existing.封面 ?? item.封面
                    existing.年份 = existing.年份 ?? item.年份
                    existing.格式 = existing.格式 ?? item.格式
                    合并[item.id] = existing
                } else {
                    合并[item.id] = item
                }
            }
        }
        for (id, lists) in 标题来源 {
            合并[id]?.多语言标题 = 作品多语言标题.合并(lists)
        }
        return 合并.values.sorted {
            let a = 得分[$0.id] ?? 0, b = 得分[$1.id] ?? 0
            return a != b ? a > b : $0.id < $1.id
        }
    }

    private static func 搜索(_ sync: PaperVNSync中心, _ platform: 资料库平台, _ type: 作品类型, _ text: String) async -> [匹配候选] {
        do {
            return try await sync.搜索候选(platform, 类型: type, 关键词: text)
        } catch {
            return []
        }
    }

    /// 平台的搜索结果归到作品。动画以 Annict 划分：并入正篇的特别篇归到正篇。
    private static func 结果(_ candidate: 匹配候选, 平台 platform: 资料库平台, 搜索类型 searchType: 作品类型) -> 作品搜索结果? {
        let 种类 = (candidate.种类 ?? "").uppercased()
        let type: 作品类型 = searchType == .anime ? .anime : (种类.contains("NOVEL") || 种类.contains("小说") ? .lightNovel : .manga)
        // Annict 的搜索结果编号就是 GraphQL 节点 ID，和映射里的一样
        let key = 作品映射.查找(platform, 平台ID: candidate.id, 类型: type)?.键
            ?? (platform == .myAnimeList ? "mal-\(type == .anime ? "anime" : "manga"):\(candidate.id)" : nil)
        // 映射里没有的条目：平台自己的 ID（AniList、Bangumi）也能打开详情
        let resolved = key ?? {
            let 分组 = type == .anime ? "anime" : "manga"
            switch platform {
            case .aniList: return "aniList-\(分组):\(candidate.id)"
            case .bangumi: return "bangumi-\(分组):\(candidate.id)"
            default: return nil
            }
        }()
        guard let resolved, let colon = resolved.firstIndex(of: ":"),
              let number = Int(resolved[resolved.index(after: colon)...]) else { return nil }
        let prefix = resolved[..<colon]
        let malID = prefix.hasPrefix("mal-") ? number : 0
        var aniListID = prefix.hasPrefix("aniList-") ? number : nil
        let bangumiID = prefix.hasPrefix("bangumi-") ? number : nil
        if malID == 0, aniListID == nil, bangumiID == nil { return nil }
        if platform == .aniList, malID == 0 { aniListID = Int(candidate.id) }
        var mainLanguage = candidate.标题语言 ?? "und"
        if mainLanguage == "ja", malID > 0, let language = 作品映射.原名语言(type, malID: malID) { mainLanguage = language }
        var titles = [用户多语言标题(lang: mainLanguage, title: candidate.标题, latin: nil, official: true, main: true)]
        if let other = candidate.其他标题 {
            titles.append(用户多语言标题(lang: candidate.其他标题语言 ?? "und", title: other, latin: nil, official: candidate.其他标题为官方, main: false))
        }
        return 作品搜索结果(
            id: 作品搜索结果.编号(类型: type, malID: malID, aniListID: aniListID, bangumiID: bangumiID),
            类型: type,
            malID: malID,
            aniListID: aniListID,
            bangumiID: bangumiID,
            标题: candidate.标题,
            多语言标题: titles,
            封面: candidate.封面?.absoluteString,
            年份: candidate.年份,
            格式: candidate.种类
        )
    }
}

/// AniList 按 MAL ID 批量读取时的一部作品。
private struct AniList作品: Decodable {
    static let 字段 = "id idMal type format isAdult countryOfOrigin startDate { year } title { native romaji english } coverImage { large medium }"

    struct 标题: Decodable { let native: String?; let romaji: String?; let english: String? }
    struct 日期: Decodable { let year: Int? }
    struct 封面: Decodable { let large: String?; let medium: String? }
    let id: Int
    let idMal: Int?
    let type: String?
    let format: String?
    let isAdult: Bool?
    let countryOfOrigin: String?
    let startDate: 日期?
    let title: 标题
    let coverImage: 封面?

    /// 按请求时用的编号返回（同一部作品可能以 MAL ID 或 AniList ID 请求）。
    func 结果(请求的编号 ids: [String]) -> [作品搜索结果] {
        let kind: 作品类型 = type == "ANIME" ? .anime : (format == "NOVEL" ? .lightNovel : .manga)
        // 漫画和轻小说在 AniList 上是同一种类型，编号前缀按请求时的
        let 候选 = [kind, .manga, .lightNovel].flatMap { type in
            [idMal.map { 作品搜索结果.编号(类型: type, malID: $0) },
             作品搜索结果.编号(类型: type, malID: 0, aniListID: id)].compactMap { $0 }
        }
        return 候选.filter(ids.contains).compactMap { requested in
            guard let parsed = 作品搜索结果.解析(requested) else { return nil }
            return 结果(编号: requested, 类型: parsed.类型 == .anime ? .anime : kind)
        }
    }

    private func 结果(编号 requested: String, 类型 kind: 作品类型) -> 作品搜索结果 {
        let parsed = 作品搜索结果.解析(requested)
        let malID = parsed?.malID ?? 0
        return 作品搜索结果(
            id: requested,
            类型: kind,
            malID: malID > 0 ? malID : (idMal ?? 0),
            aniListID: id,
            标题: title.romaji ?? title.native ?? title.english ?? String(id),
            多语言标题: 作品多语言标题.生成(
                原名: title.native,
                原名语言: 作品多语言标题.语言(国家: countryOfOrigin),
                罗马字: title.romaji,
                英文: title.english
            ),
            封面: coverImage?.large ?? coverImage?.medium,
            年份: startDate?.year,
            格式: format?.replacingOccurrences(of: "_", with: " "),
            成人内容: isAdult ?? false
        )
    }
}
