import Foundation

nonisolated struct 推荐曝光记录: Codable, Hashable, Sendable {
    /// 连续展示但没有打开的天数，打开或冷却结束后清零。
    var 未打开展示天数 = 0
    var 最近展示日: Int?
    /// 冷却从触发后的第二天开始，当天的列表保持不变。
    var 冷却截止: Date?
}

/// 决定推荐列表每天如何展示：没打开的推荐逐日降权，连续展示过久就冷却；
/// 除前两名外按分数加权随机抽样，同一天内顺序不变。
nonisolated enum 推荐展示排序 {
    static let 固定数量 = 2
    static let 冷却前最多展示天数 = 5
    static let 冷却天数 = 14
    static let 每日展示衰减 = 0.90
    static let 抽样温度 = 0.05
    /// 每部作品的随机项保持这么多天，各作品错开更新日：列表逐日滚动，而不是每天整体重排。
    static let 抽样周期天数 = 3

    static func 排列(
        _ recommendations: [探索推荐],
        曝光: [String: 推荐曝光记录],
        种子: String,
        现在: Date,
        calendar: Calendar = .current
    ) -> [探索推荐] {
        let day = 日序号(现在, calendar: calendar)
        let ranked = recommendations
            .filter {
                !是否隐藏($0.visualNovel.id, 曝光: 曝光, 现在: 现在, calendar: calendar)
            }
            .map { recommendation in
                let shownDays = 当天开始时未打开天数(
                    曝光[recommendation.visualNovel.id],
                    today: day
                )
                return (
                    recommendation: recommendation,
                    score: recommendation.score * pow(每日展示衰减, Double(shownDays))
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.score - rhs.score) > 0.000_001 {
                    return lhs.score > rhs.score
                }
                return lhs.recommendation.visualNovel.id < rhs.recommendation.visualNovel.id
            }
        let fixed = ranked.prefix(固定数量).map(\.recommendation)
        let sampled = ranked.dropFirst(固定数量)
            .map { entry in
                let id = entry.recommendation.visualNovel.id
                let phase = Int(哈希("\(种子)|\(id)") % UInt64(抽样周期天数))
                let block = (day + phase) / 抽样周期天数
                return (
                    recommendation: entry.recommendation,
                    key: entry.score / 抽样温度 + 甘贝尔噪声("\(种子)|\(block)|\(id)")
                )
            }
            .sorted { $0.key > $1.key }
            .map(\.recommendation)
        return fixed + sampled
    }

    static func 是否隐藏(
        _ id: String,
        曝光: [String: 推荐曝光记录],
        现在: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if let record = 曝光[id],
           let cooldown = record.冷却截止,
           现在 < cooldown,
           record.最近展示日 != 日序号(现在, calendar: calendar) {
            return true
        }
        return false
    }

    /// 每天每条推荐只计一次；连续展示达到上限就进入冷却。
    static func 记录展示(
        _ ids: [String],
        曝光: inout [String: 推荐曝光记录],
        现在: Date,
        calendar: Calendar = .current
    ) {
        let today = 日序号(现在, calendar: calendar)
        for id in ids {
            var record = 曝光[id] ?? 推荐曝光记录()
            guard record.最近展示日 != today else { continue }
            if let cooldown = record.冷却截止, 现在 >= cooldown {
                record.冷却截止 = nil
                record.未打开展示天数 = 0
            }
            record.最近展示日 = today
            record.未打开展示天数 += 1
            if record.未打开展示天数 >= 冷却前最多展示天数, record.冷却截止 == nil,
               let tomorrow = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: 现在)
               ) {
                record.冷却截止 = calendar.date(byAdding: .day, value: 冷却天数, to: tomorrow)
            }
            曝光[id] = record
        }
    }

    static func 记录打开(
        _ id: String,
        曝光: inout [String: 推荐曝光记录]
    ) {
        var record = 曝光[id] ?? 推荐曝光记录()
        record.未打开展示天数 = 0
        record.冷却截止 = nil
        曝光[id] = record
    }

    /// 排序只看当天开始时的状态，当天新记录的展示不会让列表在同一天里变化。
    private static func 当天开始时未打开天数(
        _ record: 推荐曝光记录?,
        today: Int
    ) -> Int {
        guard let record else { return 0 }
        return max(0, record.未打开展示天数 - (record.最近展示日 == today ? 1 : 0))
    }

    static func 日序号(_ date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let start = calendar.date(from: components) else { return 0 }
        return Int((start.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    /// 由字符串确定的 Gumbel 噪声；加在 分数/温度 上排序即按 softmax 权重无放回抽样。
    private static func 甘贝尔噪声(_ key: String) -> Double {
        let uniform = (Double(哈希(key) >> 11) + 0.5) / 9_007_199_254_740_992
        return -log(-log(uniform))
    }

    private static func 哈希(_ key: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        hash ^= hash >> 33
        hash = hash &* 0xFF51_AFD7_ED55_8CCD
        hash ^= hash >> 33
        return hash
    }
}
