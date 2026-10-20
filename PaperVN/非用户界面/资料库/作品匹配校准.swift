import Foundation

/// 同一部作品在各平台上的 ID。来自管理员审核过的校准表，或用户自己手动匹配的作品。
nonisolated struct 作品对应组: Codable, Hashable, Sendable {
    /// “anime”或“manga”：MAL、AniList 把漫画和轻小说都算作 manga。
    let type: String
    /// 平台 → 作品在该平台上的 ID（主条目）。
    let ids: [String: String]
    /// 平台 → 附属条目的 ID：这部作品的特别篇、单行本、其他版本等，导入时并入这部作品，不单独同步。
    var attached: [String: [String]]?

    init(类型: 作品类型, ids: [资料库平台: String], 附属: [资料库平台: [String]] = [:]) {
        type = 作品对应组.分组(类型)
        self.ids = Dictionary(uniqueKeysWithValues: ids.map { ($0.key.rawValue, $0.value) })
        attached = 附属.isEmpty ? nil : Dictionary(uniqueKeysWithValues: 附属.map { ($0.key.rawValue, $0.value) })
    }

    /// 这组对应的作品在资料库里的编号：主条目在预装映射里有作品时用映射的编号，否则按 MAL、Annict、AniList、Bangumi 的顺序编号。
    func 键(类型 type: 作品类型) -> String? {
        for (name, id) in ids {
            if let platform = 资料库平台(rawValue: name),
               let mapped = 作品映射.查找(platform, 平台ID: id, 类型: type), !mapped.附属 {
                return mapped.键
            }
        }
        let kind = 作品对应组.分组(type)
        for platform in [资料库平台.myAnimeList, .annict, .aniList, .bangumi] {
            guard let id = ids[platform.rawValue] else { continue }
            return platform == .myAnimeList ? "mal-\(kind):\(id)" : "\(platform.rawValue)-\(kind):\(id)"
        }
        return nil
    }

    static func 分组(_ type: 作品类型) -> String { type == .anime ? "anime" : "manga" }
}

/// 同步时在某个平台上找不到、没有同步过去的作品，可以在同步任务里查看并手动匹配。
nonisolated struct 未匹配作品: Codable, Hashable, Identifiable, Sendable {
    let 键: String
    let 类型: 作品类型
    let 标题: String
    let 全部标题: [String]
    let 年份: Int?
    /// 作品在其他平台上的 ID，帮助后台确认是哪一部作品。
    let 已知ID: [资料库平台: String]

    var id: String { 键 }
}

/// 手动匹配时在平台上搜到的作品。
struct 匹配候选: Identifiable, Hashable {
    let id: String
    let 标题: String
    /// 来源标明的语言，没有标明时为 nil，显示时用系统字体。
    var 标题语言: String?
    var 其他标题: String?
    var 其他标题语言: String?
    /// Bangumi 的中文名由用户编辑，只有允许非官方标题时才显示。
    var 其他标题为官方 = true
    var 年份: Int?
    var 封面: URL?
    var 种类: String?
}

/// PaperVN Sync 的作品匹配校准：同步前读取审核过的校准表；找不到的作品和手动匹配的作品匿名提交到 PaperVN 后台。
/// 提交的内容只有作品的标题、年份和各平台的作品 ID，不含账户信息。
@MainActor
final class 作品匹配校准 {
    static let shared = 作品匹配校准()

    private static let 校准表地址 = URL(string: "https://papervn.jizpaper.com/api/library-matches/calibrations")!
    private static let 提交地址 = URL(string: "https://papervn.jizpaper.com/api/library-matches/reports")!

    private struct 缓存: Codable {
        var etag: String?
        var groups: [作品对应组]
    }

    private var 缓存内容: 缓存
    /// 平台 + 分组 + ID → 所在的对应组，查找时不用每次遍历。
    private var 索引: [String: (group: 作品对应组, 附属: Bool)] = [:]

    private init() {
        缓存内容 = (try? Data(contentsOf: Self.缓存地址)).flatMap { try? JSONDecoder().decode(缓存.self, from: $0) }
            ?? 缓存(etag: nil, groups: [])
        重建索引()
    }

    /// 同步前读取最新的校准表；读取失败时继续使用上次的。
    func 更新() async {
        var request = URLRequest(url: Self.校准表地址, timeoutInterval: 10)
        if let etag = 缓存内容.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        struct 响应: Decodable { let groups: [作品对应组] }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let value = try? JSONDecoder().decode(响应.self, from: data) else { return }
        缓存内容 = 缓存(etag: http.value(forHTTPHeaderField: "ETag"), groups: value.groups)
        重建索引()
        if let data = try? JSONEncoder().encode(缓存内容) {
            try? FileManager.default.createDirectory(at: Self.缓存地址.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.缓存地址, options: .atomic)
        }
    }

    /// 作品在目标平台上的 ID：先看用户自己手动匹配的，再看校准表。
    func 平台ID(_ platform: 资料库平台, 类型 type: 作品类型, 已知 known: [资料库平台: String], 手动 manual: [作品对应组]) -> String? {
        let kind = 作品对应组.分组(type)
        for group in manual where group.type == kind {
            if known.contains(where: { group.ids[$0.key.rawValue] == $0.value }), let id = group.ids[platform.rawValue] { return id }
        }
        for (knownPlatform, id) in known {
            // 附属条目不单独同步，只按主条目找
            if let entry = 索引[Self.索引键(knownPlatform.rawValue, kind, id)], !entry.附属,
               let value = entry.group.ids[platform.rawValue] { return value }
        }
        return nil
    }

    /// 平台条目属于哪部作品、是否为附属条目：先看用户自己手动匹配的，再看校准表。
    func 查找(_ platform: 资料库平台, 平台ID id: String, 类型 type: 作品类型, 手动 manual: [作品对应组]) -> 作品映射.结果? {
        let kind = 作品对应组.分组(type)
        func result(_ group: 作品对应组, 附属: Bool) -> 作品映射.结果? {
            group.键(类型: type).map { 作品映射.结果(键: $0, 附属: 附属) }
        }
        for group in manual.reversed() where group.type == kind {
            if group.ids[platform.rawValue] == id { return result(group, 附属: false) }
            if group.attached?[platform.rawValue]?.contains(id) == true { return result(group, 附属: true) }
        }
        if let entry = 索引[Self.索引键(platform.rawValue, kind, id)] { return result(entry.group, 附属: entry.附属) }
        return nil
    }

    struct 提交项: Encodable {
        let type: String
        let platform: String
        let kind: String
        let ids: [String: String]
        let titles: [String]
        let year: Int?
        var suggestedID: String?
        var suggestedTitle: String?
        /// 手动匹配时的关系：“main”同一部作品，“attached”附属条目。
        var role: String?

        init(_ work: 未匹配作品, 平台 platform: 资料库平台, 手动匹配 match: 匹配候选? = nil, 附属: Bool = false) {
            role = match == nil ? nil : (附属 ? "attached" : "main")
            type = work.类型.rawValue
            self.platform = platform.rawValue
            kind = match == nil ? "unmatched" : "manual"
            ids = Dictionary(uniqueKeysWithValues: work.已知ID.filter { $0.key != platform }.map { ($0.key.rawValue, $0.value) })
            var titles: [String] = []
            for title in [work.标题] + work.全部标题 where !title.isEmpty && !titles.contains(title) { titles.append(title) }
            self.titles = Array(titles.prefix(8))
            year = work.年份
            suggestedID = match?.id
            suggestedTitle = match?.标题
        }
    }

    /// 匿名提交，返回是否成功；失败的下次同步时再提交。
    func 提交(_ items: [提交项]) async -> Bool {
        guard !items.isEmpty else { return true }
        struct 内容: Encodable { let items: [提交项]; let client: String? }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        var success = true
        for start in stride(from: 0, to: items.count, by: 100) {
            var request = URLRequest(url: Self.提交地址, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(内容(items: Array(items[start..<min(start + 100, items.count)]), client: version))
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 201 else {
                success = false
                continue
            }
        }
        return success
    }

    private func 重建索引() {
        索引 = [:]
        for group in 缓存内容.groups {
            for (platform, values) in group.attached ?? [:] {
                for id in values { 索引[Self.索引键(platform, group.type, id)] = (group, true) }
            }
            for (platform, id) in group.ids { 索引[Self.索引键(platform, group.type, id)] = (group, false) }
        }
    }

    private static func 索引键(_ platform: String, _ kind: String, _ id: String) -> String { "\(platform)|\(kind)|\(id)" }

    private static var 缓存地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "PaperVN Sync", directoryHint: .isDirectory)
            .appending(path: "作品匹配校准.json")
    }
}

/// 手动匹配时输入的作品编号：纯数字，或作品页面链接中的编号。
nonisolated func 匹配候选编号(_ query: String, 链接 path: String) -> Int? {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if let id = Int(text), id > 0 { return id }
    guard let range = text.range(of: path) else { return nil }
    let digits = text[range.upperBound...].prefix { $0.isNumber }
    return Int(digits)
}
