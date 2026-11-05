import Foundation

extension PaperVNSync中心 {
    /// 把 Bangumi番组计划游戏收藏里的视觉小说导入资料库。
    ///
    /// Bangumi 的“游戏”也包括一般游戏，所以只导入能对应到VNDB作品、并且在VNDB上查得到的条目；
    /// 对应不上或VNDB里没有的不导入。只添加资料库里还没有的作品，不改已有作品（视觉小说以 PaperVN 与VNDB为准，
    /// 已有作品的状态由 Bangumi 推送写过去），也不加回在 PaperVN 或VNDB中删除过的作品（Bangumi 删不掉收藏）。
    /// 导入的作品记为待写入VNDB：登录VNDB时，下一次导入VNDB前会先写进去。
    func 导入Bangumi视觉小说() async {
        guard Self.已启用, let bangumi, bangumi.isLoggedIn, 资料库平台.bangumi.同步方向 != .无,
              let owner = 本地资料库.shared.所有者 else { return }
        await 本地资料库.shared.等待载入()
        guard 本地资料库.shared.可写入, 本地资料库.shared.所有者 == owner,
              let collections = try? await bangumi.读取游戏收藏() else { return }

        let deleted = 同步状态存储.读取(owner: owner).本地已删除
        let existing = Set(本地资料库.shared.条目.map(\.id))
        let vndbID = 视觉小说外部ID目录.shared.Bangumi反查()
        var candidates: [String: (type: Int, rate: Int, comment: String?)] = [:]
        // 按条目编号排序，同一部作品有几个 Bangumi 条目时结果固定
        for (subject, value) in collections.sorted(by: { $0.key < $1.key }) {
            guard let vnID = vndbID(subject) else { continue }
            let key = 本地资料库条目.视觉小说ID(vnID)
            guard !existing.contains(key), !deleted.contains(key), candidates[vnID] == nil else { continue }
            candidates[vnID] = value
        }
        guard !candidates.isEmpty,
              let details = try? await VNDB服务.shared.fetchUserListDetails(vnIDs: Array(candidates.keys)) else { return }

        let now = Int(Date.now.timeIntervalSince1970)
        let entries: [本地资料库条目] = candidates.compactMap { vnID, value in
            // VNDB里查不到的不是视觉小说（或者映射已经过时），不导入
            guard let detail = details[vnID], let status = Self.资料库状态(Bangumi收藏类型: value.type),
                  let labelID = status.用户列表筛选.labelID else { return nil }
            let comment = value.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
            let item = 用户列表项目(
                id: vnID, added: now, lastmod: now,
                vote: value.rate > 0 ? value.rate * 10 : nil,
                started: nil, finished: nil,
                notes: comment?.isEmpty == false ? comment : nil,
                labels: [用户列表项目.用户列表标签(id: labelID, label: "")] + (value.rate > 0 ? [用户列表项目.用户列表标签(id: 7, label: "")] : []),
                releases: nil,
                vn: detail
            )
            return 本地资料库条目(vndb: item)
        }
        guard 本地资料库.shared.所有者 == owner else { return }
        本地资料库.shared.导入视觉小说(entries, owner: owner)
    }

    /// Bangumi 收藏类型：1 想玩、2 玩过、3 在玩、4 搁置、5 抛弃。
    nonisolated static func 资料库状态(Bangumi收藏类型 type: Int) -> 资料库状态? {
        switch type {
        case 1: .planning
        case 2: .completed
        case 3: .inProgress
        case 4: .onHold
        case 5: .dropped
        default: nil
        }
    }
}
