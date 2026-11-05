import Foundation

/// 搜索页没有搜索词时，动画、漫画与轻小说列表的排序依据（AniList 的排序）。
/// 文案和默认值都照视觉小说的排序：“按…”，默认按开始日期从新到旧（视觉小说是按发行日期）。
enum 作品浏览排序: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case title, score, popularity, favourites, trending, startDate

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .title: String(localized: "按标题")
        case .score: String(localized: "按平均评分")
        case .popularity: String(localized: "按人气")
        case .favourites: String(localized: "按收藏人数")
        case .trending: String(localized: "按近期热度")
        case .startDate: String(localized: "按开始日期")
        }
    }

    var symbolName: String {
        switch self {
        case .title: "textformat"
        case .score: "chart.bar.xaxis"
        case .popularity: "person.2"
        case .favourites: "heart"
        case .trending: "flame"
        case .startDate: "calendar"
        }
    }

    /// 和视觉小说一样：标题默认升序，其他默认降序。
    var defaultIsDescending: Bool { self != .title }

    /// AniList 的排序参数。
    func aniList(降序: Bool) -> String {
        let base = switch self {
        case .popularity: "POPULARITY"
        case .score: "SCORE"
        case .trending: "TRENDING"
        case .favourites: "FAVOURITES"
        case .startDate: "START_DATE"
        case .title: "TITLE_ROMAJI"
        }
        return 降序 ? base + "_DESC" : base
    }
}

struct 作品浏览排序选择: Codable, Hashable, Sendable {
    var sort: 作品浏览排序 = .startDate
    var isDescending = true

    init(sort: 作品浏览排序 = .startDate) {
        self.sort = sort
        isDescending = sort.defaultIsDescending
    }
}

/// 动画、漫画与轻小说筛选里一个筛选项的种类。
enum 作品筛选字段: String, CaseIterable, Codable, Hashable, Identifiable {
    case 标签, 格式, 状态, 季度, 时间, 评分, 地区

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .标签: String(localized: "类型与标签")
        case .格式: String(localized: "格式")
        case .状态: String(localized: "状态")
        case .季度: String(localized: "季度")
        case .时间: String(localized: "开始时间")
        case .评分: String(localized: "评分")
        case .地区: String(localized: "地区")
        }
    }

    var systemImage: String {
        switch self {
        case .标签: "tag"
        case .格式: "rectangle.stack"
        case .状态: "hammer"
        case .季度: "leaf"
        case .时间: "calendar"
        case .评分: "chart.bar.xaxis"
        case .地区: "globe.asia.australia"
        }
    }

    /// 这种作品可以用的筛选项。季度只有动画有，轻小说只有一种格式。
    static func 可用字段(for type: 作品类型) -> [作品筛选字段] {
        allCases.filter { field in
            switch field {
            case .季度: type == .anime
            case .格式: !作品浏览筛选.格式选项(for: type).isEmpty
            default: true
            }
        }
    }

    /// AniList 能排除的只有类型、标签、格式与状态。
    var 可以排除: Bool {
        self == .标签 || self == .格式 || self == .状态
    }

    /// 季度与地区在 AniList 上只能选一个。
    var 单选: Bool {
        self == .季度 || self == .地区
    }
}

/// 一个筛选项：选中的值（类型与标签、格式等），或者范围（开始时间的年份、评分 10–100）。
struct 作品筛选条件: Codable, Hashable, Identifiable {
    var id = UUID()
    var field: 作品筛选字段
    var values: Set<String> = []
    var minimum: Int?
    var maximum: Int?

    var isConfigured: Bool {
        switch field {
        case .时间, .评分: minimum != nil || maximum != nil
        default: !values.isEmpty
        }
    }
}

/// 一组筛选条件，和视觉小说的筛选一样：显示或排除满足以下所有或任一条件的作品。
/// “所有”“任一”指一个筛选项里选中的多个值。
struct 作品筛选规则组: Codable, Hashable, Identifiable {
    var id = UUID()
    var matchMode: 视觉小说筛选匹配方式 = .all
    var isExcluded = false
    var conditions: [作品筛选条件] = []

    var configuredConditions: [作品筛选条件] { conditions.filter(\.isConfigured) }
    var isConfigured: Bool { !configuredConditions.isEmpty }
}

/// 动画、漫画与轻小说列表的筛选，编译成 AniList 的筛选参数。成人作品始终不列出。
/// AniList 的筛选能力比 VNDB 少：标签和类型只能“同时带有”或“都不带有”，排除只支持类型、标签、格式与状态，
/// 做不到的组合用 `冲突` 提示，不会悄悄改变意思。
struct 作品浏览筛选: Codable, Hashable {
    var rules: [作品筛选规则组] = []

    var isEmpty: Bool { !rules.contains(where: \.isConfigured) }

    /// 只保留这种作品可以用的筛选项（切换类型时用）。
    func 适用于(_ type: 作品类型) -> 作品浏览筛选 {
        let fields = Set(作品筛选字段.可用字段(for: type))
        var result = self
        for index in result.rules.indices {
            result.rules[index].conditions.removeAll { !fields.contains($0.field) }
        }
        result.rules.removeAll { $0.conditions.isEmpty }
        return result
    }

    /// 这组设置在 AniList 上做不到时的说明；做得到时为 nil。
    static func 冲突(_ rule: 作品筛选规则组) -> String? {
        let conditions = rule.configuredConditions
        if rule.isExcluded {
            if conditions.count > 1 {
                return String(localized: "排除时一组筛选条件里只能有一个筛选项。")
            }
            if let condition = conditions.first {
                if !condition.field.可以排除 {
                    return String(localized: "“\(condition.field.localizedTitle)”不能用来排除。")
                }
                if rule.matchMode == .all, condition.values.count > 1 {
                    return String(localized: "排除多个值时请选择“任一”。")
                }
            }
        } else if rule.matchMode == .any,
                  conditions.contains(where: { $0.field == .标签 && $0.values.count > 1 }) {
            return String(localized: "类型与标签只能要求同时带有，请选择“所有”或只选一个。")
        }
        return nil
    }

    var 第一个冲突: (序号: Int, 说明: String)? {
        for (index, rule) in rules.enumerated() where rule.isConfigured {
            if let message = Self.冲突(rule) { return (index + 1, message) }
        }
        return nil
    }

    /// AniList 查询参数（逗号开头，直接接在其他参数后面）。各组之间都要满足。
    func aniList参数(类型 type: 作品类型) -> String {
        var genreIn = Set<String>(), genreNotIn = Set<String>()
        var tagIn = Set<String>(), tagNotIn = Set<String>()
        var formatIn: Set<String>?, formatNotIn = Set<String>()
        var statusIn: Set<String>?, statusNotIn = Set<String>()
        var season: String?, country: String?
        var yearMin: Int?, yearMax: Int?, scoreMin: Int?, scoreMax: Int?

        for rule in 适用于(type).rules where rule.isConfigured && Self.冲突(rule) == nil {
            for condition in rule.configuredConditions {
                let values = condition.values
                switch condition.field {
                case .标签:
                    let genres = values.filter(作品浏览筛选.类型名称.contains)
                    let tags = values.subtracting(genres)
                    if rule.isExcluded {
                        genreNotIn.formUnion(genres); tagNotIn.formUnion(tags)
                    } else {
                        genreIn.formUnion(genres); tagIn.formUnion(tags)
                    }
                case .格式:
                    if rule.isExcluded { formatNotIn.formUnion(values) }
                    else { formatIn = formatIn.map { $0.intersection(values) } ?? values }
                case .状态:
                    if rule.isExcluded { statusNotIn.formUnion(values) }
                    else { statusIn = statusIn.map { $0.intersection(values) } ?? values }
                case .季度:
                    season = values.first
                case .地区:
                    country = values.first
                case .时间:
                    if let value = condition.minimum { yearMin = max(yearMin ?? value, value) }
                    if let value = condition.maximum { yearMax = min(yearMax ?? value, value) }
                case .评分:
                    if let value = condition.minimum { scoreMin = max(scoreMin ?? value, value) }
                    if let value = condition.maximum { scoreMax = min(scoreMax ?? value, value) }
                }
            }
        }

        // 漫画与轻小说在 AniList 上是同一种类型，用格式区分
        switch type {
        case .lightNovel:
            formatIn = ["NOVEL"]
            formatNotIn = []
        case .manga:
            formatNotIn.insert("NOVEL")
        case .anime:
            // 音乐（MV）不是作品，不列出（和 PaperVN Sync 不导入的条目一致）；以前存下的筛选里选了它也去掉
            formatIn?.remove("MUSIC")
            formatNotIn.insert("MUSIC")
        default:
            break
        }

        func list(_ values: Set<String>, quoted: Bool = false) -> String {
            "[" + values.sorted().map { quoted ? "\"\($0)\"" : $0 }.joined(separator: ", ") + "]"
        }
        var parts: [String] = []
        if let formatIn { parts.append("format_in: \(list(formatIn))") }
        if !formatNotIn.isEmpty { parts.append("format_not_in: \(list(formatNotIn))") }
        if let statusIn { parts.append("status_in: \(list(statusIn))") }
        if !statusNotIn.isEmpty { parts.append("status_not_in: \(list(statusNotIn))") }
        if type == .anime, let season { parts.append("season: \(season)") }
        // FuzzyDateInt 是 YYYYMMDD：大于某年的 0000 即从那年开始，小于下一年的 0000 即到那年为止
        if let yearMin { parts.append("startDate_greater: \(yearMin * 10_000)") }
        if let yearMax { parts.append("startDate_lesser: \((yearMax + 1) * 10_000)") }
        if let scoreMin { parts.append("averageScore_greater: \(scoreMin - 1)") }
        if let scoreMax { parts.append("averageScore_lesser: \(scoreMax + 1)") }
        if let country { parts.append("countryOfOrigin: \"\(country)\"") }
        if !genreIn.isEmpty { parts.append("genre_in: \(list(genreIn, quoted: true))") }
        if !genreNotIn.isEmpty { parts.append("genre_not_in: \(list(genreNotIn, quoted: true))") }
        if !tagIn.isEmpty { parts.append("tag_in: \(list(tagIn, quoted: true))") }
        if !tagNotIn.isEmpty { parts.append("tag_not_in: \(list(tagNotIn, quoted: true))") }
        return parts.isEmpty ? "" : ", " + parts.joined(separator: ", ")
    }

    struct 选项: Identifiable, Hashable {
        let 值: String
        let 标题: String
        var id: String { 值 }
    }

    static func 格式选项(for type: 作品类型) -> [选项] {
        switch type {
        case .anime:
            [
                选项(值: "TV", 标题: String(localized: "TV动画")),
                选项(值: "TV_SHORT", 标题: String(localized: "TV短篇")),
                选项(值: "MOVIE", 标题: String(localized: "剧场版")),
                选项(值: "OVA", 标题: "OVA"),
                选项(值: "ONA", 标题: "ONA"),
                选项(值: "SPECIAL", 标题: String(localized: "特别篇")),
            ]
        case .manga:
            [
                选项(值: "MANGA", 标题: String(localized: "连载漫画")),
                选项(值: "ONE_SHOT", 标题: String(localized: "短篇漫画")),
            ]
        case .lightNovel, .visualNovel:
            []
        }
    }

    static func 状态选项(for type: 作品类型) -> [选项] {
        let releasing = type == .anime ? String(localized: "放送中") : String(localized: "连载中")
        let upcoming = type == .anime ? String(localized: "尚未放送") : String(localized: "尚未连载")
        return [
            选项(值: "RELEASING", 标题: releasing),
            选项(值: "FINISHED", 标题: String(localized: "已完结")),
            选项(值: "NOT_YET_RELEASED", 标题: upcoming),
            选项(值: "HIATUS", 标题: String(localized: "休刊中")),
            选项(值: "CANCELLED", 标题: String(localized: "已中止")),
        ]
    }

    static let 季度选项: [选项] = [
        选项(值: "WINTER", 标题: String(localized: "冬季（1月）")),
        选项(值: "SPRING", 标题: String(localized: "春季（4月）")),
        选项(值: "SUMMER", 标题: String(localized: "夏季（7月）")),
        选项(值: "FALL", 标题: String(localized: "秋季（10月）")),
    ]

    static let 地区选项: [选项] = [
        选项(值: "JP", 标题: String(localized: "日本")),
        选项(值: "CN", 标题: String(localized: "中国大陆")),
        选项(值: "KR", 标题: String(localized: "韩国")),
        选项(值: "TW", 标题: String(localized: "中国台湾")),
    ]

    /// AniList 的类型（不含成人类型）。和标签放在同一个筛选项里，查询时分开。
    static let 类型名称: [String] = [
        "Action", "Adventure", "Comedy", "Drama", "Ecchi", "Fantasy", "Horror", "Mahou Shoujo", "Mecha",
        "Music", "Mystery", "Psychological", "Romance", "Sci-Fi", "Slice of Life", "Sports", "Supernatural", "Thriller",
    ]

    /// 详情页的一个类型或标签用来筛选时的值：AniList 的类型和（非成人）标签原样使用，MAL 的类型换成意思相同的 AniList 类型或标签。
    /// 对不上的返回 nil（Bangumi 的用户标签、MAL 独有的类型，例如 Award Winning），详情页不提供入口。
    static func 筛选值(类型或标签 name: String) -> String? {
        if 类型名称.contains(name) || 可筛选标签.contains(name) { return name }
        return MAL类型对应[name]
    }

    private static let 可筛选标签: Set<String> = Set(AniList标签.目录.flatMap(\.标签))

    /// MAL 与 AniList 名称不同、意思相同的类型。名称相同的（Action、Isekai、Shounen 等）不用列。
    private static let MAL类型对应: [String: String] = [
        "Adult Cast": "Primarily Adult Cast",
        "Anthropomorphic": "Anthropomorphism",
        "Boys Love": "Boys' Love",
        "CGDCT": "Cute Girls Doing Cute Things",
        "Childcare": "Parenthood",
        "Girls Love": "Yuri",
        "Gourmet": "Food",
        "Harem": "Female Harem",
        "Idols (Female)": "Idol",
        "Idols (Male)": "Idol",
        "Love Polygon": "Love Triangle",
        "Magical Sex Shift": "Gender Bending",
        "Medical": "Medicine",
        "Organized Crime": "Criminal Organization",
        "Reverse Harem": "Male Harem",
        "Suspense": "Thriller",
        "Time Travel": "Time Manipulation",
        "Video Game": "Video Games",
        "Workplace": "Work",
    ]
}
