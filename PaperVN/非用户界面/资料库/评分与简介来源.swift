import Foundation

/// 评分可以采用的平台。各平台的评分口径和评分人数都不一样，视觉小说、动画、漫画、轻小说分别选择。
nonisolated enum 评分平台: String, CaseIterable, Identifiable, Sendable {
    case vndb
    case myAnimeList
    case aniList
    case bangumi
    case tmdb

    var id: Self { self }

    var title: String {
        switch self {
        case .vndb: "VNDB"
        case .myAnimeList: "MyAnimeList"
        case .aniList: "AniList"
        case .bangumi: String(localized: "Bangumi番组计划")
        case .tmdb: "TMDB"
        }
    }

    /// 这类作品能取到评分的平台。TMDB 只有动画。
    static func 可选(_ type: 作品类型) -> [评分平台] {
        switch type {
        case .visualNovel: [.vndb, .bangumi]
        case .anime: [.myAnimeList, .aniList, .bangumi, .tmdb]
        case .manga, .lightNovel: [.myAnimeList, .aniList, .bangumi]
        }
    }
}

nonisolated enum 评分计算方式: String, CaseIterable, Identifiable, Sendable {
    /// 按各平台评分人数的对数加权，人数多的平台占比更大。
    case weighted
    /// 各平台的评分直接取平均。
    case mean

    var id: Self { self }

    var title: String {
        switch self {
        case .weighted: String(localized: "加权平均")
        case .mean: String(localized: "平均数")
        }
    }
}

nonisolated enum 评分设置 {
    static func 来源键(_ type: 作品类型) -> String { "ratingSources.\(type.rawValue)" }
    static func 方式键(_ type: 作品类型) -> String { "ratingMethod.\(type.rawValue)" }

    /// 存储为逗号分隔的平台名，方便 `@AppStorage` 直接读写。
    static func 已选平台(_ type: 作品类型, defaults: UserDefaults = .standard) -> Set<评分平台> {
        let available = 评分平台.可选(type)
        if let raw = defaults.string(forKey: 来源键(type)) {
            let selected = 解析(raw).intersection(available)
            if !selected.isEmpty { return selected }
        }
        // 旧版视觉小说只能选“综合”“VNDB”“Bangumi番组计划”之一
        // 键与取值同 `评分数据来源`
        if type == .visualNovel, let legacy = defaults.string(forKey: "visualNovelRatingSource") {
            switch legacy {
            case "vndb": return [.vndb]
            case "bangumi": return [.bangumi]
            default: break
            }
        }
        return Set(available)
    }

    static func 解析(_ raw: String) -> Set<评分平台> {
        Set(raw.split(separator: ",").compactMap { 评分平台(rawValue: String($0)) })
    }

    static func 编码(_ platforms: Set<评分平台>) -> String {
        评分平台.allCases.filter(platforms.contains).map(\.rawValue).joined(separator: ",")
    }

    static func 计算方式(_ type: 作品类型, defaults: UserDefaults = .standard) -> 评分计算方式 {
        defaults.string(forKey: 方式键(type)).flatMap(评分计算方式.init(rawValue:)) ?? .weighted
    }

    /// 只用设置里选中的平台，评分都已换算到 10 分制。没有人数的平台按 100 人算。
    static func 合成(
        _ ratings: [(平台: 评分平台, 分数: Double, 人数: Int?)],
        type: 作品类型,
        defaults: UserDefaults = .standard
    ) -> (分数: Double, 人数: Int?)? {
        let selected = 已选平台(type, defaults: defaults)
        let used = ratings.filter { selected.contains($0.平台) && $0.分数 > 0 }
        guard !used.isEmpty else { return nil }
        let method = 计算方式(type, defaults: defaults)
        var weighted = 0.0, weights = 0.0
        for rating in used {
            let weight = method == .weighted ? log10(Double(max(rating.人数 ?? 100, 10))) : 1
            weighted += rating.分数 * weight
            weights += weight
        }
        let counts = used.compactMap(\.人数)
        return (weighted / weights, counts.isEmpty ? nil : counts.reduce(0, +))
    }
}

/// 动画、漫画与轻小说简介的来源。选中的平台没有简介时，按 MAL、AniList、TMDB 的顺序换用其他平台。
nonisolated enum 简介来源: String, CaseIterable, Identifiable, Sendable {
    case myAnimeList
    case aniList
    case tmdb
    /// 只在 Bangumi 上有的作品才会用到，设置里不提供。
    case bangumi

    var id: Self { self }

    var title: String {
        switch self {
        case .myAnimeList: "MyAnimeList"
        case .aniList: "AniList"
        case .tmdb: "TMDB"
        case .bangumi: String(localized: "Bangumi番组计划")
        }
    }

    static func 可选(_ type: 作品类型) -> [简介来源] {
        type == .anime ? [.myAnimeList, .aniList, .tmdb] : [.myAnimeList, .aniList]
    }

    static func 设置键(_ type: 作品类型) -> String { "synopsisSource.\(type.rawValue)" }

    /// 动画默认用 TMDB（有界面语言的简介），漫画和轻小说用 MAL。
    static func 默认值(_ type: 作品类型) -> 简介来源 {
        type == .anime ? .tmdb : .myAnimeList
    }

    static func 当前(_ type: 作品类型, defaults: UserDefaults = .standard) -> 简介来源 {
        defaults.string(forKey: 设置键(type))
            .flatMap(简介来源.init(rawValue:))
            .flatMap { 可选(type).contains($0) ? $0 : nil }
            ?? 默认值(type)
    }
}
