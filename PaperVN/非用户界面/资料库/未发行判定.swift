import Foundation
import os

/// 没有发行或播出日期的动画、漫画、轻小说是不是还没发行。
/// 光看日期分不出来：没有日期可能是还没定档，也可能只是平台没提供（Annict 只有年份，Bangumi 的条目常常不填）。
///
/// 所以这些作品向公开接口读一次状态，不需要登录任何平台：有 MAL 或 AniList ID 的先批量问 AniList（status 是否为 NOT_YET_RELEASED），
/// AniList 上没有的问 MAL（not_yet_aired、not_yet_published）。结果存在磁盘上；状态会变，所以隔一段时间重新读：
/// 还没发行的每天一次（定档、开播后及时移出），已经发行的不会再变回去，隔得久一些。
nonisolated enum 未发行判定 {
    struct 结果: Codable, Equatable {
        /// 平台上查不到这部作品时为 nil。
        var 未发行: Bool?
        var 检查时间: Date
    }

    /// 磁盘上记着的结果：true 是平台标明还没发行。没读过、平台上查不到时为 nil。
    static func 已知(_ id: String) -> Bool? {
        缓存 { $0[id]?.未发行 }
    }

    /// 只有计划中、没有日期的作品需要判断。
    static func 需要判断(_ entry: 本地资料库条目) -> Bool {
        entry.类型 != .visualNovel && entry.状态 == .planning && (entry.发行日期 ?? "").isEmpty
    }

    /// 还没读过或该重新读的作品联网读取。返回结果有没有变化（列表需要重新分组）。
    @discardableResult
    static func 读取(_ entries: [本地资料库条目], now: Date = .now) async -> Bool {
        let missing = entries.filter { entry in
            guard 需要判断(entry) else { return false }
            guard let known = 缓存({ $0[entry.id] }) else { return true }
            return now.timeIntervalSince(known.检查时间) > 有效期(known.未发行)
        }
        guard !missing.isEmpty else { return false }
        let found = await 联网读取(missing)
        guard !found.isEmpty else { return false }
        return 缓存 { cache in
            var changed = false
            for (key, value) in found {
                if cache[key]?.未发行 != value { changed = true }
                cache[key] = 结果(未发行: value, 检查时间: now)
            }
            保存(cache)
            return changed
        }
    }

    private static func 有效期(_ unreleased: Bool?) -> TimeInterval {
        switch unreleased {
        case true?: 86_400
        case false?: 30 * 86_400
        case nil: 7 * 86_400
        }
    }

    // MARK: 联网

    private struct 目标 {
        let 键: String
        let 动画: Bool
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
        return 目标(
            键: entry.id,
            动画: entry.类型 == .anime,
            malID: 编号(.myAnimeList, 前缀: "mal-"),
            aniListID: 编号(.aniList, 前缀: "aniList-")
        )
    }

    /// 作品编号 → 是否未发行；平台上查不到的记为 nil（外层的 Optional 有值），请求失败的不在结果里，下次再读。
    private static func 联网读取(_ entries: [本地资料库条目]) async -> [String: Bool?] {
        var found: [String: Bool?] = [:]
        var failed: Set<String> = []

        // AniList：动画、漫画的 MAL ID 各自编号，分开查；一次每组最多 50 部
        var pending = entries.map(查询目标).filter { $0.malID != nil || $0.aniListID != nil }
        var rest: [目标] = []
        while !pending.isEmpty, !Task.isCancelled {
            func 取(_ anime: Bool, byMAL: Bool) -> [目标] {
                Array(pending.filter { $0.动画 == anime && ($0.malID != nil) == byMAL }.prefix(50))
            }
            let groups = (am: 取(true, byMAL: true), aa: 取(true, byMAL: false), mm: 取(false, byMAL: true), ma: 取(false, byMAL: false))
            let asked = groups.am + groups.aa + groups.mm + groups.ma
            let keys = Set(asked.map(\.键))
            pending.removeAll { keys.contains($0.键) }
            guard let status = await AniList状态(
                动画MAL: groups.am.compactMap(\.malID), 动画AniList: groups.aa.compactMap(\.aniListID),
                书籍MAL: groups.mm.compactMap(\.malID), 书籍AniList: groups.ma.compactMap(\.aniListID)
            ) else {
                failed.formUnion(keys)
                failed.formUnion(pending.map(\.键))
                break
            }
            for target in asked {
                let table = target.动画 ? status.动画 : status.书籍
                if let value = target.malID.flatMap({ table.mal[$0] }) ?? target.aniListID.flatMap({ table.aniList[$0] }) {
                    found[target.键] = .some(value == "NOT_YET_RELEASED")
                } else {
                    rest.append(target)
                }
            }
            if !pending.isEmpty { try? await Task.sleep(for: .milliseconds(800)) }
        }

        // AniList 上没有的：MAL（用 Client ID，不需要登录）
        await withTaskGroup(of: (String, Bool??).self) { group in
            var iterator = rest.makeIterator()
            func next() {
                guard let target = iterator.next() else { return }
                group.addTask {
                    guard let id = target.malID else { return (target.键, .some(nil)) }
                    return (target.键, await MAL状态(id, 动画: target.动画))
                }
            }
            for _ in 0..<4 { next() }
            for await (key, value) in group {
                if let value { found[key] = value }
                next()
            }
        }
        for key in failed { found[key] = nil }
        return found
    }

    private typealias 状态表 = (mal: [Int: String], aniList: [Int: String])

    /// AniList 的 status（FINISHED、RELEASING、NOT_YET_RELEASED 等）。请求失败时返回 nil。
    private static func AniList状态(
        动画MAL: [Int], 动画AniList: [Int], 书籍MAL: [Int], 书籍AniList: [Int]
    ) async -> (动画: 状态表, 书籍: 状态表)? {
        struct 响应: Decodable {
            struct 作品: Decodable { let id: Int; let idMal: Int?; let status: String? }
            struct 页: Decodable { let media: [作品] }
            struct 数据: Decodable { let am: 页?; let aa: 页?; let mm: 页?; let ma: 页? }
            let data: 数据
        }
        guard let data = try? await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query ($am: [Int], $aa: [Int], $mm: [Int], $ma: [Int]) {
              am: Page(perPage: 50) { media(idMal_in: $am, type: ANIME) { id idMal status } }
              aa: Page(perPage: 50) { media(id_in: $aa, type: ANIME) { id idMal status } }
              mm: Page(perPage: 50) { media(idMal_in: $mm, type: MANGA) { id idMal status } }
              ma: Page(perPage: 50) { media(id_in: $ma, type: MANGA) { id idMal status } }
            }
            """,
            variables: ["am": 动画MAL, "aa": 动画AniList, "mm": 书籍MAL, "ma": 书籍AniList]
        ), let decoded = try? JSONDecoder().decode(响应.self, from: data) else { return nil }
        func 表(_ byMAL: 响应.页?, _ byAniList: 响应.页?) -> 状态表 {
            var mal: [Int: String] = [:], aniList: [Int: String] = [:]
            for media in byMAL?.media ?? [] {
                if let id = media.idMal, let status = media.status { mal[id] = status }
            }
            for media in byAniList?.media ?? [] {
                if let status = media.status { aniList[media.id] = status }
            }
            return (mal, aniList)
        }
        return (表(decoded.data.am, decoded.data.aa), 表(decoded.data.mm, decoded.data.ma))
    }

    /// 外层 nil 是请求失败，内层 nil 是 MAL 上没有这部作品或没有标明状态。
    private static func MAL状态(_ id: Int, 动画: Bool) async -> Bool?? {
        guard MyAnimeListOAuth配置.isConfigured else { return nil }
        var components = URLComponents(string: "https://api.myanimelist.net/v2/\(动画 ? "anime" : "manga")/\(id)")!
        components.queryItems = [URLQueryItem(name: "fields", value: "status")]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.setValue(MyAnimeListOAuth配置.clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        struct 作品: Decodable { let status: String? }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let code = (response as? HTTPURLResponse)?.statusCode else { return nil }
        if code == 404 { return .some(nil) }
        guard code == 200, let decoded = try? JSONDecoder().decode(作品.self, from: data) else { return nil }
        return .some(decoded.status.map { $0 == "not_yet_aired" || $0 == "not_yet_published" })
    }

    // MARK: 缓存

    /// 列表分组时每部作品都要查，读进内存后不再读盘。
    private static let 内存缓存 = OSAllocatedUnfairLock<[String: 结果]?>(initialState: nil)

    private static func 缓存<T: Sendable>(_ body: @Sendable (inout [String: 结果]) -> T) -> T {
        内存缓存.withLock { state in
            var cache = state ?? 读盘()
            defer { state = cache }
            return body(&cache)
        }
    }

    private static func 读盘() -> [String: 结果] {
        guard let data = try? Data(contentsOf: 缓存地址),
              let value = try? JSONDecoder().decode([String: 结果].self, from: data) else { return [:] }
        return value
    }

    private static func 保存(_ cache: [String: 结果]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: 缓存地址.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: 缓存地址, options: .atomic)
    }

    private static var 缓存地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "PaperVN Sync", directoryHint: .isDirectory)
            .appending(path: "未发行状态.json")
    }
}
