import Combine
import Foundation

/// 动画、漫画与轻小说分类下，标题菜单里可选的对象。会社（动画公司）只有动画有。
enum 作品浏览范围: String, CaseIterable, Identifiable, Hashable {
    case 作品, 角色, 制作人员, 会社

    var id: Self { self }

    static func 可用范围(for type: 作品类型) -> [作品浏览范围] {
        type == .anime ? allCases : [.作品, .角色, .制作人员]
    }

    var systemImage: String {
        switch self {
        case .作品: "square.stack"
        case .角色: "person.crop.rectangle.stack"
        case .制作人员: "person.text.rectangle"
        case .会社: "building.2"
        }
    }

    func localizedTitle(for type: 作品类型) -> String {
        switch self {
        case .作品: type.localizedTitle
        case .角色: String(localized: "角色")
        case .制作人员: String(localized: "制作人员")
        case .会社: String(localized: "动画公司")
        }
    }
}

/// AniList 上的一个角色、制作人员或动画公司（列表里的一行）。
struct AniList人物: Identifiable, Hashable {
    enum 人物种类: String, Hashable { case 角色, 制作人员, 会社 }

    let 种类: 人物种类
    let anilistID: Int
    let 名字: String
    let 原名: String?
    let 图片: String?
    /// 出自哪部作品（角色）、代表作（制作人员与动画公司）。
    let 作品: 作品搜索结果?

    var id: String { "\(种类.rawValue)-\(anilistID)" }
}

/// 角色、制作人员与动画公司的列表与详情，数据来自 AniList。不含成人作品。
@MainActor
enum AniList人物服务 {
    /// 每页取这么多部作品，再从作品里取出角色与制作人员：列表跟着所选的作品种类走（轻小说就是轻小说的角色）。
    private static let 每页作品数 = 20

    private static func 媒体条件(_ type: 作品类型) -> String {
        switch type {
        case .anime: "type: ANIME"
        case .lightNovel: "type: MANGA, format: NOVEL"
        default: "type: MANGA, format_not: NOVEL"
        }
    }

    private static func 作品(_ work: AniList作品, type: 作品类型) -> 作品搜索结果? {
        guard work.isAdult != true else { return nil }
        let id = 作品搜索结果.编号(类型: type, malID: work.idMal ?? 0, aniListID: work.id)
        return work.结果(请求的编号: [id]).first
    }

    struct 名字: Decodable { let full: String?; let native: String? }
    struct 图片: Decodable { let large: String?; let medium: String? }

    /// 没有搜索词时的列表：AniList 上热门作品里的角色或制作人员，按作品热度排列；动画公司按收藏数。
    static func 列表(_ scope: 作品浏览范围, 类型 type: 作品类型, 页码 page: Int) async throws -> (结果: [AniList人物], 还有更多: Bool) {
        if scope == .会社 { return try await 动画公司(页码: page) }

        struct 节点: Decodable { let id: Int; let name: 名字?; let image: 图片? }
        struct 列表: Decodable { let nodes: [节点] }
        struct 媒体: Decodable {
            let 作品: AniList作品
            let characters: 列表?
            let staff: 列表?
            private enum CodingKeys: String, CodingKey { case characters, staff }
            init(from decoder: Decoder) throws {
                作品 = try AniList作品(from: decoder)
                let container = try decoder.container(keyedBy: CodingKeys.self)
                characters = try container.decodeIfPresent(列表.self, forKey: .characters)
                staff = try container.decodeIfPresent(列表.self, forKey: .staff)
            }
        }
        struct 响应: Decodable {
            struct 页信息: Decodable { let hasNextPage: Bool? }
            struct 页: Decodable { let pageInfo: 页信息?; let media: [媒体] }
            struct 数据: Decodable { let Page: 页 }
            let data: 数据
        }
        let 子查询 = scope == .角色
            ? "characters(sort: [ROLE, FAVOURITES_DESC], perPage: 6) { nodes { id name { full native } image { large medium } } }"
            : "staff(sort: [RELEVANCE], perPage: 3) { nodes { id name { full native } image { large medium } } }"
        let data = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query ($page: Int) {
              Page(page: $page, perPage: \(每页作品数)) {
                pageInfo { hasNextPage }
                media(\(媒体条件(type)), sort: [POPULARITY_DESC, ID], isAdult: false) {
                  \(AniList作品.字段)
                  \(子查询)
                }
              }
            }
            """,
            variables: ["page": page]
        )
        let decoded = try JSONDecoder().decode(响应.self, from: data)
        var result: [AniList人物] = []
        for media in decoded.data.Page.media {
            let work = 作品(media.作品, type: type)
            for node in (scope == .角色 ? media.characters : media.staff)?.nodes ?? [] {
                guard let name = node.name?.full ?? node.name?.native else { continue }
                result.append(AniList人物(
                    种类: scope == .角色 ? .角色 : .制作人员,
                    anilistID: node.id,
                    名字: name,
                    原名: node.name?.native,
                    图片: node.image?.large ?? node.image?.medium,
                    作品: work
                ))
            }
        }
        return (result, decoded.data.Page.pageInfo?.hasNextPage ?? !result.isEmpty)
    }

    private static func 动画公司(页码 page: Int) async throws -> (结果: [AniList人物], 还有更多: Bool) {
        struct 作品列表: Decodable { let nodes: [AniList作品] }
        struct 公司: Decodable { let id: Int; let name: String; let isAnimationStudio: Bool?; let media: 作品列表? }
        struct 响应: Decodable {
            struct 页信息: Decodable { let hasNextPage: Bool? }
            struct 页: Decodable { let pageInfo: 页信息?; let studios: [公司] }
            struct 数据: Decodable { let Page: 页 }
            let data: 数据
        }
        let data = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query ($page: Int) {
              Page(page: $page, perPage: 50) {
                pageInfo { hasNextPage }
                studios(sort: [FAVOURITES_DESC, ID]) {
                  id name isAnimationStudio
                  media(isMain: true, sort: [POPULARITY_DESC], perPage: 1) { nodes { \(AniList作品.字段) } }
                }
              }
            }
            """,
            variables: ["page": page]
        )
        let decoded = try JSONDecoder().decode(响应.self, from: data)
        let result = decoded.data.Page.studios
            .filter { $0.isAnimationStudio != false }
            .map { studio in
                AniList人物(
                    种类: .会社,
                    anilistID: studio.id,
                    名字: studio.name,
                    原名: nil,
                    图片: nil,
                    作品: studio.media?.nodes.first.flatMap { 作品($0, type: .anime) }
                )
            }
        return (result, decoded.data.Page.pageInfo?.hasNextPage ?? !result.isEmpty)
    }

    // MARK: 详情

    struct 出演作品: Identifiable, Hashable {
        let 作品: 作品搜索结果
        /// 角色的主角／配角，或者制作人员的职责。
        let 说明: String?
        var id: String { 作品.id + (说明 ?? "") }
    }

    struct 详情 {
        var 名字: String
        var 原名: String?
        var 别名: [String] = []
        var 图片: String?
        var 简介: String?
        /// 生日、性别、年龄、血型、职业等，按显示顺序。
        var 资料: [(标题: String, 内容: String)] = []
        var 作品: [出演作品] = []
        /// 角色的声优、制作人员配音的角色。
        var 相关人物: [AniList人物] = []
    }

    private static func 生日(_ date: (year: Int?, month: Int?, day: Int?)?) -> String? {
        guard let date, let month = date.month else { return nil }
        var components = DateComponents()
        components.year = date.year
        components.month = month
        components.day = date.day
        guard let value = Calendar(identifier: .gregorian).date(from: components) else { return nil }
        let style: Date.FormatStyle = switch (date.year, date.day) {
        case (.some, .some): .dateTime.year().month().day()
        case (nil, .some): .dateTime.month().day()
        case (.some, nil): .dateTime.year().month()
        case (nil, nil): .dateTime.month()
        }
        return 中西文间距.去除空格(value.formatted(style))
    }

    struct 日期: Decodable { let year: Int?; let month: Int?; let day: Int? }

    static func 角色详情(_ id: Int) async throws -> 详情 {
        struct 声优: Decodable { let id: Int; let name: 名字?; let image: 图片? }
        struct 边: Decodable { let characterRole: String?; let voiceActors: [声优]?; let node: AniList作品? }
        struct 作品列表: Decodable { let edges: [边] }
        struct 角色: Decodable {
            struct 角色名字: Decodable { let full: String?; let native: String?; let alternative: [String]? }
            let name: 角色名字?
            let image: 图片?
            let description: String?
            let gender: String?
            let age: String?
            let bloodType: String?
            let dateOfBirth: 日期?
            let media: 作品列表?
        }
        struct 响应: Decodable { struct 数据: Decodable { let Character: 角色? }; let data: 数据 }
        let data = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query ($id: Int) {
              Character(id: $id) {
                name { full native alternative } image { large medium } description(asHtml: false)
                gender age bloodType dateOfBirth { year month day }
                media(sort: [POPULARITY_DESC], perPage: 25) {
                  edges {
                    characterRole
                    voiceActors(language: JAPANESE, sort: [RELEVANCE]) { id name { full native } image { large medium } }
                    node { \(AniList作品.字段) }
                  }
                }
              }
            }
            """,
            variables: ["id": id]
        )
        guard let character = try JSONDecoder().decode(响应.self, from: data).data.Character else {
            throw 作品详情错误.unavailable
        }
        var result = 详情(
            名字: character.name?.full ?? character.name?.native ?? "",
            原名: character.name?.native,
            别名: (character.name?.alternative ?? []).filter { !$0.isEmpty },
            图片: character.image?.large ?? character.image?.medium,
            简介: AniList文本.简介(character.description)
        )
        if let birthday = 生日(character.dateOfBirth.map { ($0.year, $0.month, $0.day) }) {
            result.资料.append((String(localized: "生日"), birthday))
        }
        if let gender = character.gender { result.资料.append((String(localized: "性别"), AniList文本.性别(gender))) }
        if let age = character.age { result.资料.append((String(localized: "年龄"), age)) }
        if let bloodType = character.bloodType { result.资料.append((String(localized: "血型"), bloodType)) }
        var actors: [AniList人物] = []
        var seenActors: Set<Int> = []
        for edge in character.media?.edges ?? [] {
            guard let node = edge.node else { continue }
            let type: 作品类型 = node.type == "ANIME" ? .anime : (node.format == "NOVEL" ? .lightNovel : .manga)
            if let work = 作品(node, type: type) {
                result.作品.append(出演作品(作品: work, 说明: AniList文本.角色定位(edge.characterRole)))
            }
            for actor in edge.voiceActors ?? [] where seenActors.insert(actor.id).inserted {
                guard let name = actor.name?.full ?? actor.name?.native else { continue }
                actors.append(AniList人物(种类: .制作人员, anilistID: actor.id, 名字: name, 原名: actor.name?.native, 图片: actor.image?.large ?? actor.image?.medium, 作品: nil))
            }
        }
        result.相关人物 = actors
        return result
    }

    static func 制作人员详情(_ id: Int) async throws -> 详情 {
        struct 边: Decodable { let staffRole: String?; let node: AniList作品? }
        struct 作品列表: Decodable { let edges: [边] }
        struct 角色节点: Decodable { let id: Int; let name: 名字?; let image: 图片? }
        struct 角色列表: Decodable { let nodes: [角色节点] }
        struct 人员: Decodable {
            let name: 名字?
            let image: 图片?
            let description: String?
            let primaryOccupations: [String]?
            let gender: String?
            let homeTown: String?
            let dateOfBirth: 日期?
            let staffMedia: 作品列表?
            let characters: 角色列表?
        }
        struct 响应: Decodable { struct 数据: Decodable { let Staff: 人员? }; let data: 数据 }
        let data = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query ($id: Int) {
              Staff(id: $id) {
                name { full native } image { large medium } description(asHtml: false)
                primaryOccupations gender homeTown dateOfBirth { year month day }
                staffMedia(sort: [POPULARITY_DESC], perPage: 25) { edges { staffRole node { \(AniList作品.字段) } } }
                characters(sort: [FAVOURITES_DESC], perPage: 20) { nodes { id name { full native } image { large medium } } }
              }
            }
            """,
            variables: ["id": id]
        )
        guard let staff = try JSONDecoder().decode(响应.self, from: data).data.Staff else {
            throw 作品详情错误.unavailable
        }
        var result = 详情(
            名字: staff.name?.full ?? staff.name?.native ?? "",
            原名: staff.name?.native,
            图片: staff.image?.large ?? staff.image?.medium,
            简介: AniList文本.简介(staff.description)
        )
        if let occupations = staff.primaryOccupations, !occupations.isEmpty {
            result.资料.append((String(localized: "职业"), 中西文间距.去除空格(ListFormatter.localizedString(byJoining: occupations.map(AniList职位.显示名称)))))
        }
        if let birthday = 生日(staff.dateOfBirth.map { ($0.year, $0.month, $0.day) }) {
            result.资料.append((String(localized: "生日"), birthday))
        }
        if let gender = staff.gender { result.资料.append((String(localized: "性别"), AniList文本.性别(gender))) }
        if let homeTown = staff.homeTown { result.资料.append((String(localized: "出身地"), homeTown)) }
        var seen: Set<String> = []
        for edge in staff.staffMedia?.edges ?? [] {
            guard let node = edge.node else { continue }
            let type: 作品类型 = node.type == "ANIME" ? .anime : (node.format == "NOVEL" ? .lightNovel : .manga)
            guard let work = 作品(node, type: type) else { continue }
            // 同一部作品的多个职责合成一行
            if seen.insert(work.id).inserted {
                result.作品.append(出演作品(作品: work, 说明: edge.staffRole.map(AniList职位.完整显示名称)))
            } else if let index = result.作品.firstIndex(where: { $0.作品.id == work.id }), let role = edge.staffRole {
                let old = result.作品[index]
                let separator = AniList职位.使用中日文标点 ? "、" : ", "
                result.作品[index] = 出演作品(作品: old.作品, 说明: [old.说明, AniList职位.完整显示名称(role)].compactMap { $0 }.joined(separator: separator))
            }
        }
        result.相关人物 = (staff.characters?.nodes ?? []).compactMap { node in
            guard let name = node.name?.full ?? node.name?.native else { return nil }
            return AniList人物(种类: .角色, anilistID: node.id, 名字: name, 原名: node.name?.native, 图片: node.image?.large ?? node.image?.medium, 作品: nil)
        }
        return result
    }

    static func 动画公司详情(_ id: Int) async throws -> 详情 {
        struct 作品列表: Decodable { let nodes: [AniList作品] }
        struct 公司: Decodable { let name: String; let media: 作品列表? }
        struct 响应: Decodable { struct 数据: Decodable { let Studio: 公司? }; let data: 数据 }
        let data = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query ($id: Int) {
              Studio(id: $id) {
                name
                media(isMain: true, sort: [POPULARITY_DESC], perPage: 50) { nodes { \(AniList作品.字段) } }
              }
            }
            """,
            variables: ["id": id]
        )
        guard let studio = try JSONDecoder().decode(响应.self, from: data).data.Studio else {
            throw 作品详情错误.unavailable
        }
        var result = 详情(名字: studio.name)
        result.作品 = (studio.media?.nodes ?? []).compactMap { node in
            作品(node, type: .anime).map { 出演作品(作品: $0, 说明: $0.年份.map(String.init)) }
        }
        return result
    }
}

/// AniList 文本的整理：简介里的剧透块、链接与 HTML 换行，以及固定取值的翻译。
nonisolated enum AniList文本 {
    static func 简介(_ text: String?) -> String? {
        guard var text, !text.isEmpty else { return nil }
        // ~!剧透!~ 整段去掉，[文字](链接) 只留文字，粗体标记去掉
        text = text.replacingOccurrences(of: #"(?s)~!.*?!~"#, with: "", options: [.regularExpression])
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        // 详情页的简介预览是纯文本，粗体标记直接去掉
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func 性别(_ value: String) -> String {
        switch value.lowercased() {
        case "male": String(localized: "男")
        case "female": String(localized: "女")
        default: value
        }
    }

    static func 角色定位(_ role: String?) -> String? {
        switch role {
        case "MAIN": String(localized: "主角")
        case "SUPPORTING": String(localized: "配角")
        case "BACKGROUND": String(localized: "背景角色")
        default: nil
        }
    }
}

/// 搜索页动画、漫画与轻小说分类下角色、制作人员与动画公司的列表（分页加载）。
@MainActor
final class AniList人物浏览视图模型: ObservableObject {
    struct 键: Hashable { let type: 作品类型; let scope: 作品浏览范围 }

    @Published private(set) var 结果: [键: [AniList人物]] = [:]
    @Published private(set) var 状态: [键: 搜索视图模型.页面状态] = [:]
    @Published private(set) var 正在加载下一页: Set<键> = []
    @Published private(set) var 下一页错误: [键: String] = [:]
    private var 还有更多: [键: Bool] = [:]
    private var 当前页: [键: Int] = [:]

    func 页面状态(_ key: 键) -> 搜索视图模型.页面状态 { 状态[key] ?? .idle }

    func 加载首页(_ key: 键, 强制: Bool = false) {
        switch 页面状态(key) {
        case .loaded, .loading, .empty: guard 强制 else { return }
        case .idle, .failed: break
        }
        状态[key] = .loading
        Task {
            do {
                let page = try await AniList人物服务.列表(key.scope, 类型: key.type, 页码: 1)
                结果[key] = Self.去重(page.结果)
                还有更多[key] = page.还有更多
                当前页[key] = 1
                状态[key] = page.结果.isEmpty ? .empty : .loaded
            } catch {
                状态[key] = .failed(error.localizedDescription)
            }
        }
    }

    func 加载下一页(_ key: 键) {
        guard 页面状态(key) == .loaded, 还有更多[key] == true, !正在加载下一页.contains(key) else { return }
        正在加载下一页.insert(key)
        下一页错误[key] = nil
        let next = (当前页[key] ?? 1) + 1
        Task {
            defer { 正在加载下一页.remove(key) }
            do {
                let page = try await AniList人物服务.列表(key.scope, 类型: key.type, 页码: next)
                结果[key] = Self.去重((结果[key] ?? []) + page.结果)
                还有更多[key] = page.还有更多
                当前页[key] = next
            } catch {
                下一页错误[key] = error.localizedDescription
            }
        }
    }

    /// 同一个人出现在好几部作品里时只留第一次（作品更热门的那次）。
    private static func 去重(_ items: [AniList人物]) -> [AniList人物] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }
}
