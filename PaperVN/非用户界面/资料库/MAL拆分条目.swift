import Foundation

// MAL 偶尔把几部作品记成一个条目，分成几集（例如《劇場総集編ぼっち・ざ・ろっく！》Re: 与 Re:Re: 在 MAL 上是一个 2 集的条目）。
// 动画以 Annict 的划分为准，这几部是不同的作品：读取 MAL 时按集数把条目拆成几条记录（平台 ID 为“55357#1”“55357#2”），
// 写回 MAL 时再把这几部作品合成一个条目。

/// MAL 上和别的作品共用一个条目的作品：拆开读取、合并写入。
enum MAL拆分条目 {
    /// MAL 条目拆成的几部作品：后台审核的拆分优先，其次是预装映射里的。
    /// 后台拆分里的作品在预装映射里也有时，标题用映射里的（AniList 的原名、罗马字、英文，和详情页一致）。
    static func 部分(_ malID: Int, 类型 type: 作品类型) -> [作品映射.拆分部分]? {
        let preset = 作品映射.MAL拆分(malID, 类型: type)
        guard let calibrated = 作品匹配校准.shared.MAL拆分(malID, 类型: type) else { return preset }
        return calibrated.map { part in
            guard let known = preset?.first(where: { $0.键 == part.键 }) else { return part }
            return 作品映射.拆分部分(
                键: part.键, 集数: part.集数, 标题: known.标题, 罗马字: known.罗马字, 英文: known.英文, 原名语言: known.原名语言
            )
        }
    }

    /// 作品在 MAL 上和别的作品共用一个条目时，它的拆分条目 ID（“55357#2”）。
    static func 拆分ID(_ key: String, 类型 type: 作品类型) -> String? {
        let kind = 作品对应组.分组(type)
        for split in 作品匹配校准.shared.已拆分的MAL条目 where split.type == kind {
            if let index = 部分(split.malID, 类型: type)?.firstIndex(where: { $0.键 == key }) {
                return "\(split.malID)#\(index + 1)"
            }
        }
        // 预装映射里的拆分被后台的拆分取代时不再使用
        guard let id = 作品映射.MAL拆分ID(key, 类型: type), let malID = 作品映射.MAL拆分条目(id),
              作品匹配校准.shared.MAL拆分(malID, 类型: type) == nil else { return nil }
        return id
    }

    /// 把 MAL 的一条记录按集数拆成几部作品的记录。不需要拆分的记录原样返回。
    /// `基线` 是 MAL 上次同步完成时各部作品的值：如果它们合起来和这次读到的一样（MAL 上没有改过），沿用基线，
    /// 因为合并写入时丢掉的信息（例如两部不同的评分）从 MAL 上读不回来。
    static func 拆开(_ record: 平台资料库记录, 基线: [String: 同步快照]) -> [平台资料库记录] {
        guard record.平台 == .myAnimeList, let malID = Int(record.平台ID),
              let parts = 部分(malID, 类型: record.类型) else { return [record] }
        let previous = parts.map { 基线[$0.键] }
        let values: [同步快照?]
        if previous.contains(where: { $0 != nil }), let combined = 合并(previous, parts), 相符(combined, record.快照) {
            values = previous
        } else {
            values = 按集数分配(record.快照, parts)
        }
        let ownKey = 同步合并.键(类型: record.类型, malID: malID, 平台: .myAnimeList, 平台ID: record.平台ID)
        let lastPresent = values.lastIndex { $0 != nil }
        return parts.enumerated().compactMap { offset, part in
            guard let value = values[offset] else { return nil }
            // 标题一律用这部作品自己的：MAL 条目的标题是几部合在一起的（例如没有“Re:”），和详情页对不上。
            // 封面、平均评分属于编号和 MAL 条目相同的那一部
            let own = part.键 == ownKey
            return 平台资料库记录(
                平台: .myAnimeList,
                平台ID: "\(malID)#\(offset + 1)",
                类型: record.类型,
                malID: own ? malID : nil,
                标题: part.罗马字 ?? part.标题,
                日文标题: part.标题,
                封面地址: own ? record.封面地址 : nil,
                快照: value,
                总数: part.集数,
                平均评分: own ? record.平均评分 : nil,
                发行日期: own ? record.发行日期 : nil,
                // 开始日期给第一部，完成日期给最后一部
                开始日期: offset == 0 ? record.开始日期 : nil,
                完成日期: offset == lastPresent && value.状态 == .completed ? record.完成日期 : nil,
                修改时间: record.修改时间,
                多语言标题: 作品多语言标题.生成(
                    原名: part.标题,
                    原名语言: part.原名语言 ?? 作品映射.原名语言(record.类型, malID: malID) ?? "ja",
                    罗马字: part.罗马字,
                    英文: part.英文
                ),
                指定键: part.键
            )
        }
    }

    /// MAL 条目的值按集数分给各部：看到第几集，那一集之前的几部都算看完；
    /// 计划观看、搁置、弃坑时还没看完的几部也是这个状态，在看时只有正在看的那一部记为在看。
    static func 按集数分配(_ value: 同步快照, _ parts: [作品映射.拆分部分]) -> [同步快照?] {
        let progress = value.进度 ?? 0
        var start = 0
        var watchingAssigned = false
        return parts.map { part in
            defer { start += part.集数 }
            if value.状态 == .completed || progress >= start + part.集数 {
                return 同步快照(状态: .completed, 评分: value.评分, 进度: part.集数)
            }
            if value.状态 == .inProgress {
                guard !watchingAssigned else { return nil }
                watchingAssigned = true
            }
            return 同步快照(状态: value.状态, 评分: value.评分, 进度: progress - start)
        }
    }

    /// 几部作品合成 MAL 条目的值。都不在资料库里时为 nil（从 MAL 删除）。
    /// - 进度：从第一部起连续看完的集数，加上之后正在看的那一部看到的集数。
    /// - 状态：都看完才算看完；还没看完的第一部的状态，有一部看过或在看时“计划观看”算在看。
    /// - 评分：只有一个分数（各部相同或只评了一部）时才写，各部分数不同时为 nil，MAL 上的评分保持原样。
    static func 合并(_ values: [同步快照?], _ parts: [作品映射.拆分部分]) -> 同步快照? {
        let present = values.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        var progress = 0
        for (value, part) in zip(values, parts) {
            guard let value else { break }
            if value.状态 == .completed {
                progress += part.集数
                continue
            }
            progress += min(value.进度 ?? 0, part.集数)
            break
        }
        let unfinished = present.filter { $0.状态 != .completed }
        let status: 资料库状态
        if let first = unfinished.first {
            let started = present.contains { $0.状态 == .completed || $0.状态 == .inProgress }
            status = first.状态 == .planning && started ? .inProgress : first.状态
        } else {
            status = present.count == values.count ? .completed : .inProgress
        }
        let scores = Set(present.compactMap(\.评分))
        return 同步快照(状态: status, 评分: scores.count == 1 ? scores.first : nil, 进度: progress)
    }

    /// 合成的值和 MAL 上的一样。合成值没有评分时表示不改 MAL 上的评分，任何评分都算一样。
    static func 相符(_ combined: 同步快照, _ current: 同步快照) -> Bool {
        combined.状态 == current.状态 && (combined.进度 ?? 0) == (current.进度 ?? 0)
            && (combined.评分 == nil || combined.评分 == current.评分)
    }

    /// 写回 MAL 时这几部作品各自的值。`值` 给出某部作品现在的值（不在资料库里时为 nil）。
    static func 写回值(_ malID: Int, 类型 type: 作品类型, 值: (作品映射.拆分部分) -> 同步快照?) -> (parts: [作品映射.拆分部分], 合并: 同步快照?)? {
        guard let parts = 部分(malID, 类型: type) else { return nil }
        return (parts, 合并(parts.map(值), parts))
    }
}
