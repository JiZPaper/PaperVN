import Foundation

/// 漫画还是轻小说。资料库的编号（“mal-manga:123”）分不出这两种，平台记录也不一定可靠：
/// Bangumi 的收藏列表里没有分类，只能按标签猜；在详情页载入完之前加入的作品也只知道是“书”。
///
/// 所以每部书都向公开接口读一次分类，不需要登录任何平台：有 MAL 或 AniList ID 的先批量问 AniList（format 是否为 NOVEL），
/// AniList 上没有的问 MAL（media_type），都没有的问 Bangumi 条目的 platform（“小说”“漫画”）。
/// 读到的结果存在磁盘上，同一部作品只读一次；资料库从磁盘读出、加入作品、同步写入时都按它改正，结果以它为准。
nonisolated enum 书籍类型判定 {
    /// 读取失败的作品不记下来，下次再读；平台上明确不是漫画也不是小说的（画集、写真集等）不改动。
    static func 改正(_ entries: inout [本地资料库条目]) {
        let cache = 读取缓存()
        for index in entries.indices {
            guard let type = 已知类型(entries[index], cache: cache) else { continue }
            entries[index].类型 = type
        }
    }

    /// 先用磁盘上的结果改正，还没读过的作品再联网读取。返回作品编号 → 类型（只含读到的）。
    static func 读取(_ entries: [本地资料库条目], bangumiToken: String? = nil) async -> [String: 作品类型] {
        var cache = 读取缓存()
        let books = entries.filter { 是书($0) }
        let missing = books.filter { cache[$0.id] == nil }
        if !missing.isEmpty {
            let found = await 联网读取(missing, bangumiToken: bangumiToken)
            if !found.isEmpty {
                // 读取期间别处也可能写过缓存：重新读一次再合并，不覆盖掉
                cache = 读取缓存().merging(found) { _, new in new }
                保存缓存(cache)
            }
        }
        var result: [String: 作品类型] = [:]
        for entry in books {
            if let type = 已知类型(entry, cache: cache) { result[entry.id] = type }
        }
        return result
    }

    private static func 是书(_ entry: 本地资料库条目) -> Bool {
        entry.类型 == .manga || entry.类型 == .lightNovel
    }

    private static func 已知类型(_ entry: 本地资料库条目, cache: [String: String]) -> 作品类型? {
        guard 是书(entry), let value = cache[entry.id], let type = 作品类型(rawValue: value),
              type == .manga || type == .lightNovel else { return nil }
        return type
    }

    // MARK: 联网

    private struct 目标 {
        let 键: String
        let malID: Int?
        let aniListID: Int?
        let bangumiID: Int?
    }

    private static func 查询目标(_ entry: 本地资料库条目) -> 目标 {
        func 编号(_ platform: 资料库平台, 前缀: String) -> Int? {
            if let value = entry.平台ID[platform] ?? 作品映射.平台ID(entry.id, 平台: platform, 类型: entry.类型),
               let id = Int(value) { return id }
            guard entry.id.hasPrefix(前缀), let value = entry.id.split(separator: ":").last else { return nil }
            return Int(value)
        }
        // 共用一个 MAL 条目的拆分作品（“55357#2”）不按 MAL 判断：Int 转不出来，自然落到 AniList、Bangumi
        return 目标(
            键: entry.id,
            malID: 编号(.myAnimeList, 前缀: "mal-"),
            aniListID: 编号(.aniList, 前缀: "aniList-"),
            bangumiID: 编号(.bangumi, 前缀: "bangumi-")
        )
    }

    /// 作品编号 → 类型的 rawValue；平台明确说了不是漫画也不是小说的记为空字符串，不再重复读取。
    private static func 联网读取(_ entries: [本地资料库条目], bangumiToken: String?) async -> [String: String] {
        let targets = entries.map(查询目标)
        var found: [String: String] = [:]

        // AniList：一次最多 50 部，按 MAL ID 和 AniList ID 各查一组
        var pending = targets
        while !pending.isEmpty, !Task.isCancelled {
            let byMAL = Array(pending.filter { $0.malID != nil }.prefix(50))
            let byAniList = Array(pending.filter { $0.malID == nil && $0.aniListID != nil }.prefix(50))
            guard !byMAL.isEmpty || !byAniList.isEmpty else { break }
            guard let media = await AniList分类(mal: byMAL.compactMap(\.malID), aniList: byAniList.compactMap(\.aniListID)) else { break }
            for target in byMAL + byAniList {
                let format = target.malID.flatMap { media.mal[$0] } ?? target.aniListID.flatMap { media.aniList[$0] }
                if let format { found[target.键] = (format == "NOVEL" ? 作品类型.lightNovel : .manga).rawValue }
            }
            let asked = Set((byMAL + byAniList).map(\.键))
            pending.removeAll { asked.contains($0.键) }
            if !pending.isEmpty { try? await Task.sleep(for: .milliseconds(800)) }
        }

        // AniList 上没有的：MAL（未登录用 Client ID），再不行用 Bangumi
        let rest = targets.filter { found[$0.键] == nil }
        await withTaskGroup(of: (String, String?).self) { group in
            var iterator = rest.makeIterator()
            func next() {
                guard let target = iterator.next() else { return }
                group.addTask {
                    if let id = target.malID, let type = await MAL分类(id) { return (target.键, type.rawValue) }
                    if let id = target.bangumiID, let platform = await Bangumi平台(id, token: bangumiToken) {
                        return (target.键, 分类(Bangumi: platform)?.rawValue ?? "")
                    }
                    return (target.键, nil)
                }
            }
            for _ in 0..<4 { next() }
            for await (key, type) in group {
                if let type { found[key] = type }
                next()
            }
        }
        return found
    }

    /// AniList 的 format（MANGA、NOVEL、ONE_SHOT）。请求失败时返回 nil。
    private static func AniList分类(mal: [Int], aniList: [Int]) async -> (mal: [Int: String], aniList: [Int: String])? {
        struct 响应: Decodable {
            struct 作品: Decodable { let id: Int; let idMal: Int?; let format: String? }
            struct 页: Decodable { let media: [作品] }
            struct 数据: Decodable { let a: 页?; let b: 页? }
            let data: 数据
        }
        guard let data = try? await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query ($a: [Int], $b: [Int]) {
              a: Page(perPage: 50) { media(idMal_in: $a, type: MANGA) { id idMal format } }
              b: Page(perPage: 50) { media(id_in: $b, type: MANGA) { id idMal format } }
            }
            """,
            variables: ["a": mal, "b": aniList]
        ), let decoded = try? JSONDecoder().decode(响应.self, from: data) else { return nil }
        var byMAL: [Int: String] = [:], byAniList: [Int: String] = [:]
        for media in decoded.data.a?.media ?? [] {
            if let id = media.idMal, let format = media.format { byMAL[id] = format }
        }
        for media in decoded.data.b?.media ?? [] {
            if let format = media.format { byAniList[media.id] = format }
        }
        return (byMAL, byAniList)
    }

    private static func MAL分类(_ id: Int) async -> 作品类型? {
        guard MyAnimeListOAuth配置.isConfigured else { return nil }
        var components = URLComponents(string: "https://api.myanimelist.net/v2/manga/\(id)")!
        components.queryItems = [URLQueryItem(name: "fields", value: "media_type")]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue(MyAnimeListOAuth配置.clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        struct 作品: Decodable {
            let mediaType: String?
            enum CodingKeys: String, CodingKey { case mediaType = "media_type" }
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let value = try? JSONDecoder().decode(作品.self, from: data).mediaType else { return nil }
        return 分类(MAL: value)
    }

    /// Bangumi 条目的 platform（“小说”“漫画”“画集”等）。读取失败时返回 nil。
    private static func Bangumi平台(_ id: Int, token: String?) async -> String? {
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/subjects/\(id)")!, timeoutInterval: 15)
        request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
        // Bangumi 不向未登录的请求返回成人条目
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        struct 条目: Decodable { let platform: String? }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(条目.self, from: data) else { return nil }
        return decoded.platform ?? ""
    }

    static func 分类(MAL mediaType: String) -> 作品类型 {
        ["light_novel", "novel"].contains(mediaType) ? .lightNovel : .manga
    }

    /// “小说”是轻小说，“漫画”是漫画；画集、绘本等其他书籍不判断。
    static func 分类(Bangumi platform: String) -> 作品类型? {
        switch platform {
        case "小说": .lightNovel
        case "漫画": .manga
        default: nil
        }
    }

    // MARK: 缓存

    private static func 读取缓存() -> [String: String] {
        guard let data = try? Data(contentsOf: 缓存地址),
              let value = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return value
    }

    private static func 保存缓存(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: 缓存地址.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: 缓存地址, options: .atomic)
    }

    private static var 缓存地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "PaperVN Sync", directoryHint: .isDirectory)
            .appending(path: "书籍类型.json")
    }
}
