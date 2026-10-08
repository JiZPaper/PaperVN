import Foundation
import zlib

// 用构建器导出的留出用户离线评估“为你推荐”。
// 这些用户被隐藏的评分没有参与协同模型训练，所以不会有数据泄漏。
// 由 Tools/运行推荐离线评估.sh 与 App 的推荐源码一起编译，计算流程与 App 完全相同。

struct 评估文件: Decodable {
    struct 用户: Decodable {
        let visible: [[Int]]
        let hidden: [[Int]]
    }

    let users: [用户]
}

struct 用户结果 {
    var 有留出喜欢作品 = false
    var 前12命中 = 0
    var ndcg12 = 0.0
    var 召回48 = 0.0
    var 前12: [String] = []
    var 前12评分人数: [Int] = []
    var 资料库评分人数中位数 = 0
    var 前12协同理由数 = 0
    var 前12探索项数 = 0
    var 新展示两周作品数 = 0
    var 旧展示两周作品数 = 0
    var 新展示相邻日重合 = 0.0
    var 旧展示相邻日重合 = 0.0
}

struct 参数 {
    var model = URL(fileURLWithPath: ".build/vndb-recommendation-model/VNDBRecommendationModel.json.gz")
    var users = URL(fileURLWithPath: ".build/vndb-recommendation-model/evaluation-users.json.gz")
    var count = 300
    var output: URL?

    init(_ arguments: [String]) {
        var iterator = arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            guard let value = iterator.next() else { break }
            switch flag {
            case "--model": model = URL(fileURLWithPath: value)
            case "--users": users = URL(fileURLWithPath: value)
            case "--count": count = Int(value) ?? count
            case "--output": output = URL(fileURLWithPath: value)
            default: break
            }
        }
    }
}

func 解压(_ url: URL) throws -> Data {
    guard let file = gzopen(url.path(percentEncoded: false), "rb") else {
        throw CocoaError(.fileReadNoSuchFile)
    }
    defer { gzclose(file) }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1 << 18)
    while true {
        let count = gzread(file, &buffer, UInt32(buffer.count))
        guard count >= 0 else { throw CocoaError(.fileReadCorruptFile) }
        guard count > 0 else { break }
        result.append(buffer, count: Int(count))
    }
    return result
}

func 中位数(_ values: [Int]) -> Int {
    guard !values.isEmpty else { return 0 }
    return values.sorted()[values.count / 2]
}

func 相邻日平均重合(_ days: [Set<String>]) -> Double {
    guard days.count > 1 else { return 1 }
    let overlaps = zip(days, days.dropFirst()).map { lhs, rhs in
        Double(lhs.intersection(rhs).count) / Double(max(1, lhs.union(rhs).count))
    }
    return overlaps.reduce(0, +) / Double(overlaps.count)
}

/// 本次改动之前 App 的展示方式：固定前 8 名，其余按天轮换。
func 旧版每日展示(_ ids: [String], 种子: String, 日: Int) -> [String] {
    guard ids.count > 12 else { return ids }
    let fixed = Array(ids.prefix(8))
    let rotating = Array(ids.dropFirst(8))
    let seed = 种子.utf8.reduce(UInt64(1_469_598_103_934_665_603)) {
        ($0 ^ UInt64($1)) &* 1_099_511_628_211
    }
    let offset = Int((seed &+ UInt64(日)) % UInt64(rotating.count))
    return fixed + Array(rotating[offset...]) + Array(rotating[..<offset])
}

let 参数值 = 参数(CommandLine.arguments)
var 日历 = Calendar(identifier: .gregorian)
日历.timeZone = TimeZone(identifier: "UTC")!
let 开始日 = 日历.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))

let 开始 = Date()
guard let model = try VNDB离线推荐模型加载器.load(url: 参数值.model) else {
    fatalError("无法读取模型：\(参数值.model.path)")
}
let 评估用户 = try JSONDecoder()
    .decode(评估文件.self, from: 解压(参数值.users))
    .users
    .prefix(参数值.count)
let 作品 = Dictionary(
    model.visualNovels.map { ($0.id, $0) },
    uniquingKeysWith: { first, _ in first }
)
let 角色证据 = VNDB离线推荐计算.角色证据按作品分组(model.characters)
print(String(
    format: "已载入模型 %@（%d 部作品），评估 %d 名留出用户（%.0f 秒）。",
    model.模型标识,
    model.visualNovels.count,
    评估用户.count,
    Date().timeIntervalSince(开始)
))

@Sendable func 资料库项目(_ visualNovel: 探索视觉小说, vote: Int) -> 探索用户列表项目 {
    探索用户列表项目(
        id: visualNovel.id,
        added: nil,
        voted: nil,
        lastModified: nil,
        vote: vote,
        started: nil,
        finished: nil,
        labels: [探索用户列表标签(id: 7, label: "Voted")],
        vn: 探索用户列表视觉小说(
            title: visualNovel.title,
            titles: visualNovel.titles,
            image: visualNovel.image,
            rating: visualNovel.rating,
            voteCount: visualNovel.voteCount,
            released: visualNovel.released,
            languages: visualNovel.languages,
            platforms: visualNovel.platforms,
            length: visualNovel.length,
            lengthMinutes: visualNovel.lengthMinutes,
            tags: visualNovel.tags,
            developers: visualNovel.developers,
            relations: visualNovel.relations
        )
    )
}

func 评估(_ user: 评估文件.用户, 序号: Int) -> 用户结果? {
    let library = user.visible.compactMap { pair -> 探索用户列表项目? in
        guard pair.count == 2, let visualNovel = 作品["v\(pair[0])"] else { return nil }
        return 资料库项目(visualNovel, vote: pair[1])
    }
    guard library.count >= 5 else { return nil }
    let libraryIDs = Set(library.map(\.id))
    let rating = VNDB离线低秩推荐算法.评分信号参数(library.compactMap(\.vote))
    let liked = Set(user.hidden.compactMap { pair -> String? in
        guard pair.count == 2 else { return nil }
        let id = "v\(pair[0])"
        let signal = tanh((Double(pair[1]) - rating.center) / rating.scale) * rating.confidence
        return signal > 0.3 && 作品[id] != nil && !libraryIDs.contains(id) ? id : nil
    })

    let context = VNDB离线推荐计算.准备(
        model: model,
        library: library,
        excludedIDs: libraryIDs,
        characterEvidence: 角色证据
    )
    let recommendations = VNDB离线推荐计算.排序(
        model: model,
        context: context,
        excludedIDs: libraryIDs,
        limit: 48
    ).recommendations
    let ids = recommendations.map(\.visualNovel.id)

    var result = 用户结果()
    result.前12 = Array(ids.prefix(12))
    result.前12评分人数 = recommendations.prefix(12).map { $0.visualNovel.voteCount ?? 0 }
    result.资料库评分人数中位数 = 中位数(library.map { $0.vn.voteCount ?? 0 })
    result.前12协同理由数 = recommendations.prefix(12).count {
        if case .similarUsers = $0.reason { true } else { false }
    }
    result.前12探索项数 = recommendations.prefix(12).count { $0.evidence?.isExploration == true }
    if !liked.isEmpty {
        result.有留出喜欢作品 = true
        result.前12命中 = ids.prefix(12).count { liked.contains($0) }
        let gain = ids.prefix(12).enumerated().reduce(0.0) { partial, entry in
            partial + (liked.contains(entry.element) ? 1 / log2(Double(entry.offset) + 2) : 0)
        }
        let ideal = (0..<min(12, liked.count)).reduce(0.0) { $0 + 1 / log2(Double($1) + 2) }
        result.ndcg12 = gain / ideal
        result.召回48 = Double(ids.prefix(48).count { liked.contains($0) }) / Double(liked.count)
    }

    // 两周展示模拟：用户每天都看到列表，但从不点开。
    var exposure: [String: 推荐曝光记录] = [:]
    var newDays: [Set<String>] = []
    var oldDays: [Set<String>] = []
    for day in 0..<14 {
        let date = 日历.date(byAdding: .day, value: day, to: 开始日)!
        let shown = 推荐展示排序.排列(
            recommendations,
            曝光: exposure,
            种子: "u\(序号)",
            现在: date,
            calendar: 日历
        ).prefix(12).map(\.visualNovel.id)
        推荐展示排序.记录展示(shown, 曝光: &exposure, 现在: date, calendar: 日历)
        newDays.append(Set(shown))
        oldDays.append(Set(旧版每日展示(ids, 种子: "u\(序号)", 日: day).prefix(12)))
    }
    result.新展示两周作品数 = newDays.reduce(into: Set<String>()) { $0.formUnion($1) }.count
    result.旧展示两周作品数 = oldDays.reduce(into: Set<String>()) { $0.formUnion($1) }.count
    result.新展示相邻日重合 = 相邻日平均重合(newDays)
    result.旧展示相邻日重合 = 相邻日平均重合(oldDays)
    return result
}

var 结果 = [用户结果?](repeating: nil, count: 评估用户.count)
let 锁 = NSLock()
let 用户列表 = Array(评估用户)
DispatchQueue.concurrentPerform(iterations: 用户列表.count) { index in
    let value = 评估(用户列表[index], 序号: index)
    锁.lock()
    结果[index] = value
    锁.unlock()
}
let 有效结果 = 结果.compactMap { $0 }
let 有留出 = 有效结果.filter(\.有留出喜欢作品)
func 平均(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

var 出现次数: [String: Int] = [:]
for result in 有效结果 {
    for id in result.前12 { 出现次数[id, default: 0] += 1 }
}
let 最常出现 = 出现次数.sorted { $0.value > $1.value }.prefix(5).map { id, count in
    "\(作品[id]?.title ?? id)（\(count) 人）"
}
let 前12总数 = 有效结果.reduce(0) { $0 + $1.前12.count }
let 指标: [(String, String)] = [
    ("有效用户", "\(有效结果.count)（含留出喜欢作品 \(有留出.count)）"),
    ("NDCG@12", String(format: "%.4f", 平均(有留出.map(\.ndcg12)))),
    ("前 12 名至少命中 1 部", String(format: "%.1f%%", 100 * Double(有留出.count { $0.前12命中 > 0 }) / Double(max(1, 有留出.count)))),
    ("Recall@48", String(format: "%.4f", 平均(有留出.map(\.召回48)))),
    ("前 12 名覆盖的不同作品", "\(出现次数.count) / \(前12总数)"),
    ("最常出现的作品", 最常出现.joined(separator: "、")),
    ("前 12 名评分人数中位数", "\(中位数(有效结果.flatMap(\.前12评分人数)))（资料库 \(中位数(有效结果.map(\.资料库评分人数中位数)))）"),
    ("前 12 名中“相似用户”理由占比", String(format: "%.1f%%", 100 * Double(有效结果.reduce(0) { $0 + $1.前12协同理由数 }) / Double(max(1, 前12总数)))),
    ("前 12 名中探索项占比", String(format: "%.1f%%", 100 * Double(有效结果.reduce(0) { $0 + $1.前12探索项数 }) / Double(max(1, 前12总数)))),
    ("两周内展示过的不同作品（新 / 旧）", String(format: "%.1f / %.1f", 平均(有效结果.map { Double($0.新展示两周作品数) }), 平均(有效结果.map { Double($0.旧展示两周作品数) }))),
    ("相邻两天的展示重合度（新 / 旧）", String(format: "%.2f / %.2f", 平均(有效结果.map(\.新展示相邻日重合)), 平均(有效结果.map(\.旧展示相邻日重合)))),
]
print("\n| 指标 | 结果 |\n|---|---|")
for (name, value) in 指标 { print("| \(name) | \(value) |") }
print(String(format: "\n用时 %.0f 秒。", Date().timeIntervalSince(开始)))

if let output = 参数值.output {
    let report = Dictionary(uniqueKeysWithValues: 指标.map { ($0.0, $0.1) })
    let data = try JSONSerialization.data(
        withJSONObject: ["model": model.模型标识, "metrics": report],
        options: [.prettyPrinted, .sortedKeys]
    )
    try data.write(to: output)
    print("已写入 \(output.path)")
}
