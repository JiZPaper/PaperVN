import Foundation

/// “为你推荐”里的一部动画、漫画或轻小说。
struct 作品推荐项: Identifiable, Hashable, Codable, Sendable {
    let 作品: 作品搜索结果
    let 分数: Double

    var id: String { 作品.id }
}

/// “为你推荐”的结果：视觉小说用探索页面的格式显示。
struct 为你推荐结果: Codable, Sendable {
    var 作品: [作品推荐项] = []
    var 视觉小说: [探索推荐] = []

    var isEmpty: Bool { 作品.isEmpty && 视觉小说.isEmpty }
}

/// 详情页“相关”里按一部作品推荐的作品。
enum 相关推荐项: Identifiable, Hashable, Sendable {
    case 作品(作品搜索结果)
    case 视觉小说(探索视觉小说)

    var id: String {
        switch self {
        case .作品(let work): work.id
        case .视觉小说(let visualNovel): visualNovel.id
        }
    }

    var 类型: 作品类型 {
        switch self {
        case .作品(let work): work.类型
        case .视觉小说: .visualNovel
        }
    }
}

/// 用 App 内置（或下载更新）的推荐模型和本地资料库推荐动画、漫画、轻小说与视觉小说。计算只要几毫秒，
/// 每次打开 Today 都重新计算；标题和封面在线读取，上一次的结果存在缓存目录里，离线时也能显示。
@MainActor
final class 作品推荐中心 {
    static let shared = 作品推荐中心()

    /// 每种类型最多推荐多少部；Today 只显示前面一部分，其余用于每天轮换。
    nonisolated static let 每类数量 = 24

    private var 模型任务: Task<作品推荐模型?, Never>?
    /// 详情页“相关”：算好的结果与读到的标题和封面，只存在内存里。
    private var 相关推荐缓存: [String: [相关推荐项]] = [:]
    private var 作品信息缓存: [String: 作品搜索结果] = [:]
    private var 视觉小说信息缓存: [String: 探索视觉小说] = [:]

    /// 搜索用的偏好分数：资料库所有者与修订号相同时复用。
    private var 偏好缓存: (key: String, scores: [Float]?)?

    /// 详情页“相关”推荐多少部。
    nonisolated static let 相关数量 = 12

    private init() {}

    nonisolated static var 模型地址: URL? {
        推荐模型存储.当前URL
    }

    private static var 缓存地址: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperVNWorkRecommendations.json")
    }

    private struct 缓存: Codable {
        let owner: String
        let result: 为你推荐结果
    }

    /// 下载了模型更新或删除了更新后调用，下次推荐时重新读取。
    func 模型文件已变更() {
        模型任务 = nil
        相关推荐缓存 = [:]
    }

    /// 解压和解析在后台进行，只读一次。
    func 模型() async -> 作品推荐模型? {
        if let 模型任务 { return await 模型任务.value }
        let task = Task.detached(priority: .utility) { () -> 作品推荐模型? in
            guard let url = Self.模型地址 else { return nil }
            return try? 作品推荐模型(url: url)
        }
        模型任务 = task
        return await task.value
    }

    private static func 反馈(_ library: 本地资料库) -> [作品推荐反馈] {
        library.条目.map { entry in
            作品推荐反馈(
                候选编号: 作品推荐模型.候选编号(条目ID: entry.id, 类型: entry.类型, malID: entry.malID),
                评分: entry.评分,
                状态: entry.状态
            )
        }
    }

    /// 搜索按相关程度排序时参考的偏好：`编号`（智能搜索的作品编号，“a5114”“v17”）→ 这个资料库对它的推荐分数，
    /// 每类标准化（平均 0、标准差 1）。没有资料库、关闭“为你推荐”或作品不在模型里时不包含。
    func 偏好分数(编号 keys: [String]) async -> [String: Float] {
        guard 为你推荐设置.已启用, !keys.isEmpty else { return [:] }
        let library = 本地资料库.shared
        await library.等待载入()
        guard !library.条目.isEmpty, let model = await 模型() else { return [:] }
        let cacheKey = "\(library.所有者 ?? "")|\(library.修订号)|\(model.标识)"
        let scores: [Float]?
        if let cached = 偏好缓存, cached.key == cacheKey {
            scores = cached.scores
        } else {
            let feedback = Self.反馈(library)
            scores = await Task.detached(priority: .userInitiated) { model.偏好分数(资料库: feedback) }.value
            偏好缓存 = (cacheKey, scores)
        }
        guard let scores else { return [:] }
        var result: [String: Float] = [:]
        for key in keys {
            if let index = model.下标[key.lowercased()] { result[key] = scores[index] }
        }
        return result
    }

    /// 搜索把同一企划的动画排在一起用：作品编号 → 企划（推荐模型的系列划分）。模型读不到时为空。
    func 企划(编号 keys: [String]) async -> [String: Int32] {
        guard !keys.isEmpty, let model = await 模型() else { return [:] }
        return model.企划(keys)
    }

    /// 和这部作品同一企划的其他作品（同一类型），最多 `数量` 部。
    func 同企划作品(编号 key: String, 数量: Int) async -> [String] {
        guard let model = await 模型() else { return [] }
        return Array(model.同企划作品(key).prefix(数量))
    }

    /// 上一次算好的推荐（同一个资料库）。模型更新后也继续使用，算出新结果前先显示，标题和封面也能复用。
    func 已缓存推荐() -> 为你推荐结果 {
        guard let data = try? Data(contentsOf: Self.缓存地址),
              let cache = try? JSONDecoder().decode(缓存.self, from: data),
              cache.owner == 本地资料库.shared.所有者 ?? "" else { return 为你推荐结果() }
        return cache.result
    }

    /// 按资料库推荐`类型`里的作品，按分数排好，已补齐标题和封面。
    /// 资料库为空、或者没有一部作品在模型里时返回空。
    /// 被取消时抛出 `CancellationError`，缓存不变；一部作品的信息都读不到时抛出错误，不返回空结果。
    func 推荐(类型 types: Set<作品类型>, 包含成人内容: Bool) async throws -> 为你推荐结果 {
        let library = 本地资料库.shared
        await library.等待载入()
        let feedback = Self.反馈(library)
        guard !feedback.isEmpty, !types.isEmpty else { return 为你推荐结果() }
        guard let model = await 模型() else {
            模型任务 = nil
            throw 作品推荐模型错误.文件无效
        }
        let scores = await Task.detached(priority: .userInitiated) {
            // 每种类型各取一份，混在一起显示时各类型都有足够的候选
            types.flatMap { type in
                model.推荐(资料库: feedback, 类型: [type], 包含成人内容: 包含成人内容, 数量: Self.每类数量)
            }
        }.value
        try Task.checkCancellation()
        guard !scores.isEmpty else { return 为你推荐结果() }

        let cached = 已缓存推荐()
        let visualNovelScores = scores.filter { 作品推荐模型.类型(of: $0.编号) == .visualNovel }
        let workScores = scores.filter { 作品推荐模型.类型(of: $0.编号) != .visualNovel }

        var details: [String: 作品搜索结果] = [:]
        for item in cached.作品 { details[item.id] = item.作品 }
        let missing = workScores.map(\.编号).filter { details[$0] == nil }
        // 作品聚合搜索.详情 每类一次最多读 50 部
        for chunk in stride(from: 0, to: missing.count, by: 50).map({ Array(missing[$0..<min($0 + 50, missing.count)]) }) {
            details.merge(await 作品聚合搜索.shared.详情(chunk)) { _, new in new }
        }

        var visualNovels: [String: 探索视觉小说] = [:]
        for item in cached.视觉小说 { visualNovels[item.id] = item.visualNovel }
        let missingVisualNovels = visualNovelScores.map(\.编号).filter { visualNovels[$0] == nil }
        var visualNovelsFailed = false
        if !missingVisualNovels.isEmpty {
            do {
                for item in try await VNDB探索服务.shared.视觉小说(编号: missingVisualNovels) {
                    visualNovels[item.id] = item
                }
            } catch {
                visualNovelsFailed = true
            }
        }
        // 取消时网络请求会失败，不能当成读取失败
        try Task.checkCancellation()

        var result = 为你推荐结果()
        result.作品 = workScores.compactMap { score in
            details[score.编号].map { 作品推荐项(作品: $0, 分数: score.分数) }
        }
        .sorted { $0.分数 > $1.分数 }
        result.视觉小说 = visualNovelScores.compactMap { score in
            visualNovels[score.编号].map { 探索推荐(visualNovel: $0, score: score.分数, reason: .similarUsers) }
        }
        .sorted { $0.score > $1.score }

        // 有一类完全读不到时，这一类保留上一次的结果，也不写缓存
        let worksFailed = !workScores.isEmpty && result.作品.isEmpty
        if worksFailed {
            result.作品 = cached.作品.filter { 包含成人内容 || !$0.作品.成人内容 }
        }
        visualNovelsFailed = visualNovelsFailed || (!visualNovelScores.isEmpty && result.视觉小说.isEmpty)
        if visualNovelsFailed, result.视觉小说.isEmpty {
            result.视觉小说 = cached.视觉小说
        }
        if result.isEmpty { throw 作品推荐模型错误.无法读取作品信息 }
        if !worksFailed, !visualNovelsFailed,
           let data = try? JSONEncoder().encode(缓存(owner: library.所有者 ?? "", result: result)) {
            try? data.write(to: Self.缓存地址, options: .atomic)
        }
        return result
    }

    /// 详情页“相关”：以一部作品推荐同一类型的其他作品，已补齐标题和封面。
    /// 资料库里有作品时结合资料库推荐、并排除资料库里已有的系列；没有资料库（未登录）时只按这部作品推荐。
    /// `作品`是这部作品在模型里的候选编号（见 `作品推荐模型.候选编号`）；不在模型里或读不到作品信息时返回空。
    func 相关推荐(作品 candidates: [String], 类型 type: 作品类型, 包含成人内容: Bool) async -> [相关推荐项] {
        guard !candidates.isEmpty else { return [] }
        let library = 本地资料库.shared
        await library.等待载入()
        let cacheKey = "\(candidates.joined(separator: ","))|\(type.rawValue)|\(包含成人内容)"
            + "|\(library.所有者 ?? "")|\(library.修订号)"
        if let cached = 相关推荐缓存[cacheKey] { return cached }
        guard let model = await 模型() else {
            模型任务 = nil
            return []
        }
        // 关闭“为你推荐”时不参考资料库
        let feedback = 为你推荐设置.已启用 ? Self.反馈(library) : []
        let scores = await Task.detached(priority: .userInitiated) {
            model.相关推荐(作品: candidates, 资料库: feedback, 类型: type, 包含成人内容: 包含成人内容, 数量: Self.相关数量)
        }.value
        guard !scores.isEmpty, !Task.isCancelled else { return [] }

        let keys = scores.map(\.编号)
        var failed = false
        if type == .visualNovel {
            let missing = keys.filter { 视觉小说信息缓存[$0] == nil }
            if !missing.isEmpty {
                do {
                    for item in try await VNDB探索服务.shared.视觉小说(编号: missing) {
                        视觉小说信息缓存[item.id] = item
                    }
                } catch {
                    failed = true
                }
            }
        } else {
            let missing = keys.filter { 作品信息缓存[$0] == nil }
            if !missing.isEmpty {
                作品信息缓存.merge(await 作品聚合搜索.shared.详情(missing)) { _, new in new }
            }
        }
        guard !Task.isCancelled else { return [] }

        let result: [相关推荐项] = keys.compactMap { key in
            type == .visualNovel ? 视觉小说信息缓存[key].map { .视觉小说($0) } : 作品信息缓存[key].map { .作品($0) }
        }
        // 读不到的作品下次再试；全部读到时才缓存
        if !failed, result.count == keys.count { 相关推荐缓存[cacheKey] = result }
        return result
    }
}
