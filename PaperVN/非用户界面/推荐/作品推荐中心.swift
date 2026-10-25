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

/// 用 App 内置（或下载更新）的推荐模型和本地资料库推荐动画、漫画、轻小说与视觉小说。计算只要几毫秒，
/// 每次打开 Today 都重新计算；标题和封面在线读取，上一次的结果存在缓存目录里，离线时也能显示。
@MainActor
final class 作品推荐中心 {
    static let shared = 作品推荐中心()

    /// 每种类型最多推荐多少部；Today 只显示前面一部分，其余用于每天轮换。
    nonisolated static let 每类数量 = 24

    private var 模型任务: Task<作品推荐模型?, Never>?

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
        let modelID: String
        let result: 为你推荐结果
    }

    /// 下载了模型更新或删除了更新后调用，下次推荐时重新读取。
    func 模型文件已变更() {
        模型任务 = nil
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

    /// 上一次算好的推荐（同一个资料库、同一个模型）。
    func 已缓存推荐() -> 为你推荐结果 {
        guard let data = try? Data(contentsOf: Self.缓存地址),
              let cache = try? JSONDecoder().decode(缓存.self, from: data),
              cache.owner == 本地资料库.shared.所有者 ?? "",
              cache.modelID == Self.模型地址.flatMap(作品推荐模型.标识(of:)) else { return 为你推荐结果() }
        return cache.result
    }

    /// 按资料库推荐`类型`里的作品，按分数排好，已补齐标题和封面。
    /// 资料库为空、或者没有一部作品在模型里时返回空。
    func 推荐(类型 types: Set<作品类型>, 包含成人内容: Bool) async -> 为你推荐结果 {
        let library = 本地资料库.shared
        await library.等待载入()
        let feedback = library.条目.map { entry in
            作品推荐反馈(
                候选编号: 作品推荐模型.候选编号(条目ID: entry.id, 类型: entry.类型, malID: entry.malID),
                评分: entry.评分,
                状态: entry.状态
            )
        }
        guard !feedback.isEmpty, !types.isEmpty, let model = await 模型() else { return 为你推荐结果() }
        let scores = await Task.detached(priority: .userInitiated) {
            // 每种类型各取一份，混在一起显示时各类型都有足够的候选
            types.flatMap { type in
                model.推荐(资料库: feedback, 类型: [type], 包含成人内容: 包含成人内容, 数量: Self.每类数量)
            }
        }.value
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
        if !missingVisualNovels.isEmpty,
           let fetched = try? await VNDB探索服务.shared.视觉小说(编号: missingVisualNovels) {
            for item in fetched { visualNovels[item.id] = item }
        }

        var result = 为你推荐结果()
        result.作品 = workScores.compactMap { score in
            details[score.编号].map { 作品推荐项(作品: $0, 分数: score.分数) }
        }
        .sorted { $0.分数 > $1.分数 }
        result.视觉小说 = visualNovelScores.compactMap { score in
            visualNovels[score.编号].map { 探索推荐(visualNovel: $0, score: score.分数, reason: .similarUsers) }
        }
        .sorted { $0.score > $1.score }
        if let modelID = Self.模型地址.flatMap(作品推荐模型.标识(of:)),
           let data = try? JSONEncoder().encode(缓存(owner: library.所有者 ?? "", modelID: modelID, result: result)) {
            try? data.write(to: Self.缓存地址, options: .atomic)
        }
        return result
    }
}
