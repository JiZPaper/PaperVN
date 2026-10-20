import Foundation

/// 预装在 App 内的作品 ID 映射（`PaperVNWorkMap.json`，由 `Tools/构建作品映射.py` 生成）。
///
/// 同步时不再按标题现场匹配：各平台的条目先查这份映射，得到它属于哪一部作品。
/// - 动画以 Annict 的作品划分为准：一部 Annict 作品是一部作品；没有 Annict 作品的按 MAL 划分。
/// - 漫画与轻小说以 MAL 为准（Annict 没有漫画与轻小说）。
/// - 一部作品在同一个平台上可以有多个条目：主条目之外的是“附属条目”（例如 Bangumi 单独成条目的特别篇、
///   Annict 并入正篇的 MAL 特别篇、Bangumi 书籍的单行本）。附属条目在导入时并入作品，不单独成为一部作品，
///   也不会被写入。
/// 映射里没有的条目仍按 MAL ID 对应；对不上的作品可以在同步任务里手动匹配，或由后台校准。
nonisolated enum 作品映射 {
    struct 结果: Equatable {
        /// 作品在资料库里的编号，例如“mal-anime:5114”。
        let 键: String
        let 附属: Bool
    }

    private struct 文件: Decodable {
        struct 分组: Decodable {
            /// [编号, MAL, AniList, Annict, Bangumi, TMDB（可省略）]，没有的为 null；编号能由 MAL 或 AniList ID 推出时也为 null。
            let works: [[JSONValue]]
            /// 平台 → [平台上的 ID, works 的下标, ID, 下标, …]
            let attached: [String: [Int]]
            /// Annict 把这些作品（MAL 的特别篇）并在正篇的话里：不写入 Annict，也不算在 Annict 上找不到
            let annictFolded: [Int]?
            /// 和别的作品共用一个 TMDB 条目（整个系列一个条目）：不写入 TMDB，也不算在 TMDB 上找不到
            let tmdbNoWrite: [Int]?
            /// [作品下标, 系列下标, …]：AniList 续作、前作关系连起来的动画（各季），系列下标是其中下标最小的作品
            let series: [Int]?
        }
        let anime: 分组
        let manga: 分组
        /// 类别（anime、manga）→ 语言 → MAL ID：原名不是日文的作品（来自 AniList 的出品国家）
        let originalLanguage: [String: [String: [Int]]]?
        /// VNDB ID → 推送到 Bangumi 时使用的主条目（只列出有多个 Bangumi 条目的作品；0 表示没有自己的条目，不推送）
        let visualNovels: [String: Int]?
        /// 被几部 VNDB 作品共用的 Bangumi 条目 → 唯一写入它的 VNDB 作品
        let visualNovelSharedBangumi: [String: String]?
        /// 对应文件里没有、从 Wikidata 补充的 VNDB → Bangumi 条目
        let visualNovelExtraBangumi: [String: Int]?
    }

    /// 只需要字符串、整数和 null 三种值。
    private enum JSONValue: Decodable {
        case string(String), int(Int), null
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(Int.self) { self = .int(value) }
            else { self = .string(try container.decode(String.self)) }
        }
        var text: String? {
            switch self {
            case let .string(value): value
            case let .int(value): String(value)
            case .null: nil
            }
        }
    }

    private struct 表 {
        /// “平台|ID” → 结果
        var 条目: [String: 结果] = [:]
        /// 编号 → TMDB 上的季（例如“tv/8853/season/2”）：第二季以后在 TMDB 上没有单独的条目
        var TMDB季: [String: String] = [:]
        /// 编号 → TMDB 上的完整路径（“tv/123”“tv/123/season/2”“movie/123”），读取详情时使用
        var TMDB路径: [String: String] = [:]
        /// Annict 上没有单独作品的编号
        var Annict并入正篇: Set<String> = []
        /// 编号 → 平台 → 主条目 ID（Annict 为 GraphQL 节点 ID）
        var 主条目: [String: [资料库平台: String]] = [:]
        /// MAL ID → 原名的语言（只有不是日文的作品）
        var 原名语言: [Int: String] = [:]
        /// 编号 → 所属系列（系列里第一部作品的编号）
        var 系列: [String: String] = [:]
    }

    private static let 平台顺序: [资料库平台] = [.myAnimeList, .aniList, .annict, .bangumi, .tmdb]

    private struct 视觉小说表 {
        var 主条目: [String: Int] = [:]
        var 共用条目归属: [Int: String] = [:]
        var 补充条目: [String: Int] = [:]
    }

    private static let 数据: (anime: 表, manga: 表, visualNovels: 视觉小说表) = {
        guard let url = Bundle.main.url(forResource: "PaperVNWorkMap", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(文件.self, from: data) else { return (表(), 表(), 视觉小说表()) }
        var visualNovels = 视觉小说表()
        visualNovels.主条目 = file.visualNovels ?? [:]
        for (bangumi, vndb) in file.visualNovelSharedBangumi ?? [:] {
            if let id = Int(bangumi) { visualNovels.共用条目归属[id] = vndb }
        }
        visualNovels.补充条目 = file.visualNovelExtraBangumi ?? [:]
        var anime = 读取(file.anime, 种类: "anime")
        var manga = 读取(file.manga, 种类: "manga")
        for (kind, languages) in file.originalLanguage ?? [:] {
            var table: [Int: String] = [:]
            for (language, ids) in languages { for id in ids { table[id] = language } }
            if kind == "anime" { anime.原名语言 = table } else if kind == "manga" { manga.原名语言 = table }
        }
        return (anime, manga, visualNovels)
    }()

    /// 映射文件有几 MB，在后台先读出来，免得第一次查找时卡住主线程。
    static func 预载() async {
        await Task.detached(priority: .utility) { _ = 数据.anime.条目.count }.value
    }

    /// 视觉小说在 Bangumi 上有多个条目（不同发行版本）时，推送用的主条目；0 表示没有自己的条目。
    static func 视觉小说Bangumi主条目(_ vndbID: String) -> Int? {
        数据.visualNovels.主条目[vndbID.lowercased()]
    }

    /// 这个 Bangumi 条目被几部 VNDB 作品共用时，只有归属的那部作品能写入。
    static func 视觉小说可以写入(_ bangumiID: Int, vndbID: String) -> Bool {
        guard let owner = 数据.visualNovels.共用条目归属[bangumiID] else { return true }
        return owner == vndbID.lowercased()
    }

    /// 对应文件里没有、从 Wikidata 补充的 Bangumi 条目。
    static func 视觉小说补充Bangumi条目(_ vndbID: String) -> Int? {
        数据.visualNovels.补充条目[vndbID.lowercased()]
    }

    private static func 读取(_ group: 文件.分组, 种类 kind: String) -> 表 {
        var table = 表()
        table.条目.reserveCapacity(group.works.count * 3 + group.attached.count)
        var keys: [String] = []
        keys.reserveCapacity(group.works.count)
        let tmdbNoWrite = Set(group.tmdbNoWrite ?? [])
        for (rowIndex, row) in group.works.enumerated() {
            // 编号为 null 时由 MAL ID（或 AniList ID）推出
            let mal = row.count > 1 ? row[1].text : nil
            let ani = row.count > 2 ? row[2].text : nil
            guard let key = row.first?.text ?? mal.map({ "mal-\(kind):\($0)" }) ?? ani.map({ "aniList-\(kind):\($0)" }) else {
                keys.append("")
                continue
            }
            keys.append(key)
            var ids: [资料库平台: String] = [:]
            for (offset, platform) in 平台顺序.enumerated() {
                guard row.count > offset + 1, let raw = row[offset + 1].text else { continue }
                if platform == .tmdb {
                    table.TMDB路径[key] = raw
                    // “tv/123/season/1”和“tv/123”是 TMDB 上的同一个条目；第二季以后不写入 TMDB
                    let parts = raw.split(separator: "/")
                    if tmdbNoWrite.contains(rowIndex) || (parts.count == 4 && parts[2] == "season" && parts[3] != "1") {
                        table.TMDB季[key] = raw
                        continue
                    }
                    let id = parts.prefix(2).joined(separator: "/")
                    ids[.tmdb] = id
                    if table.条目["tmdb|\(id)"] == nil { table.条目["tmdb|\(id)"] = 结果(键: key, 附属: false) }
                    continue
                }
                let id = platform == .annict ? Annict节点ID(raw) : raw
                ids[platform] = id
                table.条目["\(platform.rawValue)|\(id)"] = 结果(键: key, 附属: false)
            }
            table.主条目[key] = ids
        }
        for index in group.annictFolded ?? [] where keys.indices.contains(index) && !keys[index].isEmpty {
            table.Annict并入正篇.insert(keys[index])
        }
        if let series = group.series {
            for offset in stride(from: 0, to: series.count - 1, by: 2) {
                let (index, root) = (series[offset], series[offset + 1])
                guard keys.indices.contains(index), keys.indices.contains(root),
                      !keys[index].isEmpty, !keys[root].isEmpty else { continue }
                table.系列[keys[index]] = keys[root]
            }
        }
        for (name, values) in group.attached {
            guard let platform = 资料库平台(rawValue: name) else { continue }
            for offset in stride(from: 0, to: values.count - 1, by: 2) {
                let index = values[offset + 1]
                guard keys.indices.contains(index), !keys[index].isEmpty else { continue }
                let id = platform == .annict ? Annict节点ID(String(values[offset])) : String(values[offset])
                // 同一个条目既是某部作品的主条目又被列为附属时，以主条目为准
                if table.条目["\(platform.rawValue)|\(id)"] == nil {
                    table.条目["\(platform.rawValue)|\(id)"] = 结果(键: keys[index], 附属: true)
                }
            }
        }
        return table
    }

    private static func 分组表(for type: 作品类型) -> 表 { type == .anime ? 数据.anime : 数据.manga }

    /// 平台上的条目属于哪部作品。
    static func 查找(_ platform: 资料库平台, 平台ID id: String, 类型 type: 作品类型) -> 结果? {
        分组表(for: type).条目["\(platform.rawValue)|\(id)"]
    }

    /// 平台条目所属作品的 MAL ID（作品以 MAL 编号时）。
    static func malID(_ platform: 资料库平台, 平台ID id: String, 类型 type: 作品类型) -> Int? {
        guard let key = 查找(platform, 平台ID: id, 类型: type)?.键, key.hasPrefix("mal-"),
              let colon = key.firstIndex(of: ":") else { return nil }
        return Int(key[key.index(after: colon)...])
    }

    /// 作品在平台上的主条目 ID，新增到该平台时使用。
    static func 平台ID(_ key: String, 平台 platform: 资料库平台, 类型 type: 作品类型) -> String? {
        分组表(for: type).主条目[key]?[platform]
    }

    /// 作品在 TMDB 上没有单独的条目（某部剧的第二季以后，或和别的作品共用一个条目）：返回 TMDB 上的路径。
    static func TMDB季(_ key: String) -> String? {
        分组表(for: .anime).TMDB季[key]
    }

    /// Annict 把这部作品（MAL 的特别篇）并在正篇的话里，Annict 上没有单独的作品。
    static func Annict并入正篇(_ key: String) -> Bool {
        分组表(for: .anime).Annict并入正篇.contains(key)
    }

    /// 原名的语言：MAL 的 ja 字段放的是原名，中国、韩国作品其实是中文、韩文。映射里没有列出的返回 nil（按来源标明的语言）。
    static func 原名语言(_ type: 作品类型, malID: Int) -> String? {
        分组表(for: type).原名语言[malID]
    }

    /// 动画所属的系列（各季、续篇）：同一系列的作品返回相同的编号，不属于任何系列时为 nil。搜索页用它把各季叠在一起。
    static func 系列(_ key: String, 类型 type: 作品类型) -> String? {
        分组表(for: type).系列[key]
    }

    /// 作品在 TMDB 上的完整路径，读取详情时使用。
    static func TMDB路径(_ key: String) -> String? {
        分组表(for: .anime).TMDB路径[key]
    }

    /// Annict 的 GraphQL 节点 ID 是“Work-编号”的 Base64。
    static func Annict节点ID(_ annictID: String) -> String {
        Data("Work-\(annictID)".utf8).base64EncodedString()
    }
}
