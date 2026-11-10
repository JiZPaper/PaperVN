import Foundation

/// 资料库里的动画是不是音乐（MV）、广告等不能导入的条目（见 `同步合并.去掉不可导入的条目`）。
/// 同步时只能从 MAL、AniList 的记录读到分类，资料库条目本身不存分类：只登录了 Bangumi、Annict，
/// 或者同步没有在进行时，以前导入的音乐条目认不出来。
///
/// 所以每部动画都向公开接口读一次分类，不需要登录任何平台：有 MAL 或 AniList ID 的先批量问 AniList（format 是否为 MUSIC），
/// AniList 上没有的问 MAL（media_type；广告、宣传片多半只在 MAL 上有）。读到的结果存在磁盘上，同一部作品只读一次。
/// 两边都没有编号的作品（只在 Bangumi、Annict 上的）不判断。
nonisolated enum 不可导入条目判定 {
    /// 先用磁盘上的结果，还没读过的动画再联网读取。返回不能导入的作品编号（只含读到分类的）。
    static func 读取(_ entries: [本地资料库条目]) async -> Set<String> {
        var cache = 读取缓存()
        let missing = entries.filter { $0.类型 == .anime && cache[$0.id] == nil }.map(查询目标)
            .filter { $0.malID != nil || $0.aniListID != nil }
        if !missing.isEmpty {
            let found = await 联网读取(missing)
            if !found.isEmpty {
                // 读取期间别处也可能写过缓存：重新读一次再合并，不覆盖掉
                cache = 读取缓存().merging(found) { _, new in new }
                保存缓存(cache)
            }
        }
        return Set(entries.filter { $0.类型 == .anime && cache[$0.id] == false }.map(\.id))
    }

    /// 以前读到的不能导入的作品编号。只读磁盘，不联网（同步时用）。
    static var 已知: Set<String> {
        Set(读取缓存().filter { !$0.value }.keys)
    }

    // MARK: 联网

    private struct 目标 {
        let 键: String
        let malID: Int?
        let aniListID: Int?
    }

    private static func 查询目标(_ entry: 本地资料库条目) -> 目标 {
        func 编号(_ platform: 资料库平台, 前缀: String) -> Int? {
            if let value = entry.平台ID[platform] ?? 作品映射.平台ID(entry.id, 平台: platform, 类型: entry.类型),
               let id = Int(value) { return id }
            guard entry.id.hasPrefix(前缀), let value = entry.id.split(separator: ":").last else { return nil }
            return Int(value)
        }
        // 共用一个 MAL 条目的拆分作品（“55357#2”）不按 MAL 判断：Int 转不出来，自然落到 AniList
        return 目标(键: entry.id, malID: 编号(.myAnimeList, 前缀: "mal-"), aniListID: 编号(.aniList, 前缀: "aniList-"))
    }

    /// 作品编号 → 能否导入。读取失败的不记下来，下次再读。
    private static func 联网读取(_ targets: [目标]) async -> [String: Bool] {
        var found: [String: Bool] = [:]

        // AniList：一次最多 50 部，按 MAL ID 和 AniList ID 各查一组
        var pending = targets
        while !pending.isEmpty, !Task.isCancelled {
            let byMAL = Array(pending.filter { $0.malID != nil }.prefix(50))
            let byAniList = Array(pending.filter { $0.malID == nil && $0.aniListID != nil }.prefix(50))
            guard !byMAL.isEmpty || !byAniList.isEmpty else { break }
            guard let media = await AniList分类(mal: byMAL.compactMap(\.malID), aniList: byAniList.compactMap(\.aniListID)) else { break }
            for target in byMAL + byAniList {
                let format = target.malID.flatMap { media.mal[$0] } ?? target.aniListID.flatMap { media.aniList[$0] }
                if let value = 作品搜索结果.可导入(格式: format) { found[target.键] = value }
            }
            let asked = Set((byMAL + byAniList).map(\.键))
            pending.removeAll { asked.contains($0.键) }
            if !pending.isEmpty { try? await Task.sleep(for: .milliseconds(800)) }
        }

        // AniList 上没有的：问 MAL（未登录用 Client ID）
        let rest = targets.filter { found[$0.键] == nil && $0.malID != nil }
        await withTaskGroup(of: (String, Bool?).self) { group in
            var iterator = rest.makeIterator()
            func next() {
                guard let target = iterator.next(), let id = target.malID else { return }
                group.addTask { (target.键, await MAL可导入(id)) }
            }
            for _ in 0..<4 { next() }
            for await (key, value) in group {
                if let value { found[key] = value }
                next()
            }
        }
        return found
    }

    /// AniList 的 format（TV、MOVIE、MUSIC 等）。请求失败时返回 nil。
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
              a: Page(perPage: 50) { media(idMal_in: $a, type: ANIME) { id idMal format } }
              b: Page(perPage: 50) { media(id_in: $b, type: ANIME) { id idMal format } }
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

    /// MAL 的 media_type。MAL 上已经没有这个条目时当作可以导入（不再重复读取）；请求失败时返回 nil。
    private static func MAL可导入(_ id: Int) async -> Bool? {
        guard MyAnimeListOAuth配置.isConfigured else { return nil }
        var components = URLComponents(string: "https://api.myanimelist.net/v2/anime/\(id)")!
        components.queryItems = [URLQueryItem(name: "fields", value: "media_type")]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue(MyAnimeListOAuth配置.clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        struct 作品: Decodable {
            let mediaType: String?
            enum CodingKeys: String, CodingKey { case mediaType = "media_type" }
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return true }
        guard status == 200, let decoded = try? JSONDecoder().decode(作品.self, from: data) else { return nil }
        return 作品搜索结果.可导入(格式: decoded.mediaType) ?? true
    }

    // MARK: 缓存

    private static func 读取缓存() -> [String: Bool] {
        guard let data = try? Data(contentsOf: 缓存地址),
              let value = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return value
    }

    private static func 保存缓存(_ cache: [String: Bool]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: 缓存地址.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: 缓存地址, options: .atomic)
    }

    private static var 缓存地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "PaperVN Sync", directoryHint: .isDirectory)
            .appending(path: "动画分类.json")
    }
}
