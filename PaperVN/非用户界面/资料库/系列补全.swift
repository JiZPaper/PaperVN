import Foundation

/// 加入资料库后，看同一系列（前作、续作、外传、特别篇等）里还有哪些作品不在资料库里，提醒一起加入。
/// 动画、漫画与轻小说沿 MAL 的关系，视觉小说沿 VNDB 的关系一层层找下去，所以加入的是第一部时也能找到后面的作品。
/// 只找同一类型的作品（和详情页“相关”的规则一致），改编、相同角色、平行设定等不算同一系列。
/// 在提醒里选“忽略”后，这个系列不再提醒。
enum 系列补全 {
    struct 作品: Identifiable {
        /// 加入资料库时写入的记录；视觉小说只用来显示标题。
        var 条目: 本地资料库条目
        var 封面色情程度: Double?
        var 封面暴力程度: Double?
        /// 开始放送、发行的日期（“2006-04-02”），用来排序。
        var 日期: String?

        var id: String { 条目.id }
        var vndbID: String? { 条目.平台ID[.vndb] }
    }

    struct 结果: Identifiable {
        /// 刚加入资料库的作品。
        let 作品键: String
        let 作品: [作品]

        var id: String { 作品键 }
    }

    /// 一次最多读取的作品数，系列很长（例如几十部外传）时只提醒前面找到的。
    private static let 读取上限 = 40
    private static let 忽略设置键 = "seriesCompletionIgnoredWorks"

    // MARK: 忽略

    /// 选了“忽略”的系列：刚加入的作品和当时没加入的作品都记下，系列里任何一部再加入时都不再提醒。
    static func 忽略(_ result: 结果) {
        var keys = Set(UserDefaults.standard.stringArray(forKey: 忽略设置键) ?? [])
        keys.insert(result.作品键)
        keys.formUnion(result.作品.map(\.id))
        UserDefaults.standard.set(keys.sorted(), forKey: 忽略设置键)
    }

    private static func 已忽略(_ keys: [String]) -> Bool {
        let ignored = Set(UserDefaults.standard.stringArray(forKey: 忽略设置键) ?? [])
        return keys.contains { ignored.contains($0) }
    }

    /// 已经在资料库里的作品去掉，按日期排好；系列里没有其他作品或者已经忽略时为 nil。
    private static func 整理(_ works: [作品], 作品键: String) -> 结果? {
        let library = 本地资料库.shared.条目
        let keys = Set(library.map(\.id))
        let malIDs = Set(library.compactMap { entry in entry.malID.map { "\(entry.类型 == .anime ? "anime" : "manga"):\($0)" } })
        guard !已忽略([作品键] + works.map(\.id)) else { return nil }
        var missing = works.filter { work in
            guard !keys.contains(work.id) else { return false }
            guard let malID = work.条目.malID else { return true }
            return !malIDs.contains("\(work.条目.类型 == .anime ? "anime" : "manga"):\(malID)")
        }
        guard !missing.isEmpty else { return nil }
        var entries = missing.map(\.条目)
        Bangumi中文名补全.预装(&entries)
        for index in missing.indices { missing[index].条目 = entries[index] }
        // 没有日期的排在最后
        missing.sort { ($0.日期 ?? "9999") < ($1.日期 ?? "9999") }
        return 结果(作品键: 作品键, 作品: missing)
    }

    // MARK: 动画、漫画与轻小说

    /// MAL 上算作同一系列的关系。
    private static let MAL系列关系类型: Set<String> = ["sequel", "prequel", "side_story", "parent_story", "summary", "full_story"]

    static func 检查(
        kind: MyAnimeList列表项.种类,
        malID: Int,
        作品键: String,
        类型: 作品类型,
        accessToken: String?
    ) async -> 结果? {
        guard malID > 0, !已忽略([作品键]) else { return nil }
        let 分组 = kind == .anime ? "anime" : "manga"
        var visited: Set<Int> = [malID]
        var frontier = [malID]
        var requested = 0
        var works: [String: 作品] = [:]

        while !frontier.isEmpty, requested < 读取上限 {
            let batch = Array(frontier.prefix(读取上限 - requested))
            frontier = []
            requested += batch.count
            var relations: [MAL系列关系] = []
            // 同时读取 4 部，避免 MAL 限流
            for chunk in stride(from: 0, to: batch.count, by: 4).map({ Array(batch[$0..<min($0 + 4, batch.count)]) }) {
                await withTaskGroup(of: [MAL系列关系].self) { group in
                    for id in chunk {
                        group.addTask { await Self.读取MAL关系(kind: kind.rawValue, id: id, accessToken: accessToken) }
                    }
                    for await value in group { relations += value }
                }
            }
            guard !Task.isCancelled else { return nil }

            for relation in relations {
                let node = relation.node
                guard MAL系列关系类型.contains(relation.relationType ?? ""), !visited.contains(node.id) else { continue }
                visited.insert(node.id)
                // 音乐（MV）、广告、宣传片不是作品
                guard 作品搜索结果.可导入(格式: node.mediaType) != false else { continue }
                let nodeType: 作品类型 = kind == .anime
                    ? .anime
                    : (["light_novel", "novel"].contains(node.mediaType ?? "") ? .lightNovel : .manga)
                guard nodeType == 类型 else { continue }
                frontier.append(node.id)

                // 并入别的作品的条目（Annict 并入正篇的特别篇）和 MAL 上几部合成一个的条目不单独加入，只沿着它继续找
                let mapped = 作品映射.查找(.myAnimeList, 平台ID: String(node.id), 类型: nodeType)
                guard mapped?.附属 != true, 作品映射.MAL拆分(node.id, 类型: nodeType) == nil else { continue }
                let key = mapped?.键 ?? "mal-\(分组):\(node.id)"
                guard key != 作品键, works[key] == nil else { continue }

                let native = node.alternativeTitles?.ja.flatMap { $0.isEmpty ? nil : $0 }
                var entry = 本地资料库条目(
                    id: key,
                    类型: nodeType,
                    平台ID: [.myAnimeList: String(node.id)],
                    标题: node.title,
                    加入时间: nil
                )
                entry.状态 = .planning
                entry.封面地址 = node.mainPicture?.large ?? node.mainPicture?.medium
                entry.日文标题 = native
                entry.多语言标题 = 作品多语言标题.生成(
                    原名: native,
                    原名语言: native == nil ? nil : (作品映射.原名语言(nodeType, malID: node.id) ?? "ja"),
                    罗马字: node.title,
                    英文: node.alternativeTitles?.en.flatMap { $0.isEmpty ? nil : $0 }
                )
                entry.发行日期 = node.startDate
                works[key] = 作品(
                    条目: entry,
                    封面色情程度: node.nsfw == "black" ? 2 : (node.nsfw == "gray" ? 1 : nil),
                    日期: node.startDate
                )
            }
        }
        return 整理(Array(works.values), 作品键: 作品键)
    }

    nonisolated private struct MAL系列条目: Decodable, Sendable {
        let relatedAnime: [MAL系列关系]?
        let relatedManga: [MAL系列关系]?
        enum CodingKeys: String, CodingKey {
            case relatedAnime = "related_anime"
            case relatedManga = "related_manga"
        }
    }

    nonisolated private struct MAL系列关系: Decodable, Sendable {
        struct 节点: Decodable, Sendable {
            struct 图片: Decodable, Sendable { let medium: String?; let large: String? }
            struct 别名: Decodable, Sendable { let en: String?; let ja: String? }
            let id: Int
            let title: String
            let mainPicture: 图片?
            let alternativeTitles: 别名?
            let mediaType: String?
            let startDate: String?
            let nsfw: String?
            enum CodingKeys: String, CodingKey {
                case id, title, nsfw
                case mainPicture = "main_picture"
                case alternativeTitles = "alternative_titles"
                case mediaType = "media_type"
                case startDate = "start_date"
            }
        }
        let node: 节点
        let relationType: String?
        enum CodingKeys: String, CodingKey {
            case node
            case relationType = "relation_type"
        }
    }

    /// 读取一部作品在 MAL 上的同类型关系，读不到时为空。
    nonisolated private static func 读取MAL关系(kind: String, id: Int, accessToken: String?) async -> [MAL系列关系] {
        let nodeFields = "{media_type,alternative_titles,start_date,nsfw}"
        let field = kind == "anime" ? "related_anime" : "related_manga"
        var components = URLComponents(string: "https://api.myanimelist.net/v2/\(kind)/\(id)")!
        components.queryItems = [URLQueryItem(name: "fields", value: "id,\(field)\(nodeFields)")]
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else if MyAnimeListOAuth配置.isConfigured {
            request.setValue(MyAnimeListOAuth配置.clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        } else {
            return []
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let value = try? JSONDecoder().decode(MAL系列条目.self, from: data) else { return [] }
        return (kind == "anime" ? value.relatedAnime : value.relatedManga) ?? []
    }

    // MARK: 视觉小说

    /// VNDB 上算作同一系列的关系：续作、前作、外传、主线作品、同一系列。
    private static let VNDB系列关系类型: Set<String> = ["seq", "preq", "side", "par", "ser"]

    static func 检查(vnID: String) async -> 结果? {
        let 作品键 = 本地资料库条目.视觉小说ID(vnID)
        guard !已忽略([作品键]) else { return nil }
        var visited: Set<String> = [vnID]
        var frontier = [vnID]
        var requested = 0
        var works: [String: 作品] = [:]

        while !frontier.isEmpty, requested < 读取上限 {
            let batch = Array(frontier.prefix(读取上限 - requested))
            frontier = []
            requested += batch.count
            guard let nodes = try? await VNDB服务.shared.按编号获取系列关系(batch) else { break }
            guard !Task.isCancelled else { return nil }

            for node in nodes {
                if node.id != vnID {
                    var entry = 本地资料库条目(
                        id: 本地资料库条目.视觉小说ID(node.id),
                        类型: .visualNovel,
                        平台ID: [.vndb: node.id],
                        标题: node.title,
                        加入时间: nil
                    )
                    entry.多语言标题 = node.titles
                    entry.封面地址 = node.image?.url ?? node.image?.thumbnail
                    entry.发行日期 = node.released
                    works[entry.id] = 作品(
                        条目: entry,
                        封面色情程度: node.image?.sexual,
                        封面暴力程度: node.image?.violence,
                        日期: node.released
                    )
                }
                for relation in node.relations ?? []
                where VNDB系列关系类型.contains(relation.relation)
                    && relation.relation_official != false
                    && !visited.contains(relation.id) {
                    visited.insert(relation.id)
                    frontier.append(relation.id)
                }
            }
        }
        return 整理(Array(works.values), 作品键: 作品键)
    }

    /// 把选中的视觉小说加入资料库（计划游玩），和详情页加入时一样同步到 Bangumi。
    static func 添加视觉小说(_ works: [作品], auth: 用户登录, bangumiAccount: Bangumi账户) async throws {
        for work in works {
            guard let vnID = work.vndbID else { continue }
            try await VNDB服务.shared.updateUserStatus(
                token: auth.token,
                vnID: vnID,
                status: .planning,
                existingLabels: []
            )
            资料库加入时间记录.record(userID: auth.userID, vnID: vnID)
            if PaperVNSync中心.已启用, bangumiAccount.isLoggedIn {
                try await bangumiAccount.synchronize(vndbID: vnID, status: .planning, rating: nil)
            }
        }
    }
}
