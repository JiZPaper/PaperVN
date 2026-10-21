import Foundation

/// “为你推荐”里的一部动画、漫画或轻小说。
struct 作品推荐项: Identifiable, Hashable, Codable, Sendable {
    let 作品: 作品搜索结果
    let 分数: Double

    var id: String { 作品.id }
}

/// 用预装的作品推荐模型和本地资料库推荐动画、漫画与轻小说。计算只要几毫秒，每次打开 Today 都重新计算；
/// 标题和封面在线读取，上一次的结果存在缓存目录里，离线时也能显示。
@MainActor
final class 作品推荐中心 {
    static let shared = 作品推荐中心()

    /// 每种类型最多推荐多少部；Today 只显示前面一部分，其余用于每天轮换。
    nonisolated static let 每类数量 = 24

    private var 模型任务: Task<作品推荐模型?, Never>?

    private init() {}

    nonisolated static var 模型地址: URL? {
        Bundle.main.url(forResource: 作品推荐模型.资源名, withExtension: 作品推荐模型.扩展名)
    }

    private static var 缓存地址: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperVNWorkRecommendations.json")
    }

    private struct 缓存: Codable {
        let owner: String
        let modelID: String
        let items: [作品推荐项]
    }

    /// 模型约 3 MB，解压和解析在后台进行，只读一次。
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
    func 已缓存推荐() -> [作品推荐项] {
        guard let data = try? Data(contentsOf: Self.缓存地址),
              let cache = try? JSONDecoder().decode(缓存.self, from: data),
              cache.owner == 本地资料库.shared.所有者 ?? "",
              cache.modelID == Self.模型地址.flatMap(作品推荐模型.标识(of:)) else { return [] }
        return cache.items
    }

    /// 按资料库推荐动画、漫画与轻小说（`类型`里的视觉小说忽略），按分数排好，已补齐标题和封面。
    /// 资料库为空、或者没有一部作品在模型里时返回空。
    func 推荐(类型 types: Set<作品类型>, 包含成人内容: Bool) async -> [作品推荐项] {
        let library = 本地资料库.shared
        await library.等待载入()
        let feedback = library.条目.map { entry in
            作品推荐反馈(
                候选编号: 作品推荐模型.候选编号(条目ID: entry.id, 类型: entry.类型, malID: entry.malID),
                评分: entry.评分,
                状态: entry.状态
            )
        }
        let workTypes = types.subtracting([.visualNovel])
        guard !feedback.isEmpty, !workTypes.isEmpty, let model = await 模型() else { return [] }
        let scores = await Task.detached(priority: .userInitiated) {
            // 每种类型各取一份，混在一起显示时各类型都有足够的候选
            workTypes.flatMap { type in
                model.推荐(资料库: feedback, 类型: [type], 包含成人内容: 包含成人内容, 数量: Self.每类数量)
            }
        }.value
        guard !scores.isEmpty else { return [] }

        var details: [String: 作品搜索结果] = [:]
        for item in 已缓存推荐() { details[item.id] = item.作品 }
        let missing = scores.map(\.编号).filter { details[$0] == nil }
        // 作品聚合搜索.详情 每类一次最多读 50 部
        for chunk in stride(from: 0, to: missing.count, by: 50).map({ Array(missing[$0..<min($0 + 50, missing.count)]) }) {
            details.merge(await 作品聚合搜索.shared.详情(chunk)) { _, new in new }
        }
        let items = scores.compactMap { score in
            details[score.编号].map { 作品推荐项(作品: $0, 分数: score.分数) }
        }
        .sorted { $0.分数 > $1.分数 }
        if let modelID = Self.模型地址.flatMap(作品推荐模型.标识(of:)),
           let data = try? JSONEncoder().encode(缓存(owner: library.所有者 ?? "", modelID: modelID, items: items)) {
            try? data.write(to: Self.缓存地址, options: .atomic)
        }
        return items
    }
}
