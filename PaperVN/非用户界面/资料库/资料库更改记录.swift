import Combine
import Foundation

/// 资料库的一份完整快照。导出的文件与 Paper Cloud 共用这一种格式。
/// 字段名与服务器的检查一致（formatVersion、owner、createdAt、reason、appVersion、entries、sync、changes），改动时两边一起改。
nonisolated struct 资料库快照: Codable {
    var formatVersion = 1
    var owner: String
    var createdAt: Date
    var reason: String?
    var appVersion: String?
    var entries: [本地资料库条目]
    /// 同步的基线与待推送的作品。导出的文件不带它；Paper Cloud 带上，重新安装后第一次同步更准确。
    var sync: 同步状态存储?
    /// 最近更改，最早的在前。导出的文件不带它；Paper Cloud 带上，各设备显示同一份最近更改。
    var changes: [资料库更改]?

    static let 当前App版本 = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

    static func 编码器() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func 解码器() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// 一次更改的来源。同一时间段内发生的几种更改合并成一条，按优先级取最重要的来源。
/// 编码成一个字符串（“覆盖资料库:anilist”），与旧版只有名称的记录兼容。
enum 资料库更改原因: Codable, Hashable {
    case 自动整理
    case 手动编辑
    case VNDB导入
    /// PaperVN Sync 的一般同步。
    case 同步
    /// 第一次同步时选择“合并”。
    case 合并资料库
    /// 第一次同步时选择以某个来源为准；nil 是此设备上的资料库。
    case 覆盖资料库(资料库平台?)
    /// 第一次同步时选择分别保留、资料库显示某个来源。
    case 分别保留(资料库平台?)
    case 导入文件
    case 从云端恢复
    case 回退
    case 云端同步

    init(导入方式 method: 导入方式?) {
        switch method {
        case nil: self = .同步
        case .合并: self = .合并资料库
        case let .为准(source): self = .覆盖资料库(Self.平台(source))
        case let .分别保留(source): self = .分别保留(Self.平台(source))
        }
    }

    private static func 平台(_ source: 同步来源) -> 资料库平台? {
        if case let .平台(platform) = source { return platform }
        return nil
    }

    var 标题: String {
        switch self {
        case .自动整理: String(localized: "整理作品类型")
        case .手动编辑: String(localized: "编辑资料库")
        case .VNDB导入: String(localized: "从VNDB导入")
        case .同步: String(localized: "同步资料库")
        case .合并资料库: String(localized: "合并资料库")
        case let .覆盖资料库(platform?): String(localized: "使用\(platform.localizedTitle)账户覆盖资料库")
        case .覆盖资料库(nil): String(localized: "以\(同步来源.本地名称)为准")
        case let .分别保留(platform?): String(localized: "显示\(platform.localizedTitle)账户的资料库")
        case .分别保留(nil): String(localized: "显示\(同步来源.本地名称)")
        case .导入文件: String(localized: "导入资料库")
        case .从云端恢复: String(localized: "从Paper账户恢复")
        case .回退: String(localized: "回退")
        case .云端同步: String(localized: "与其他设备同步")
        }
    }

    /// 回退与合并其他设备的更改不另记一条：回退会删掉被回退的记录，其他设备的记录随 Paper Cloud 一起取回。
    var 记录更改: Bool { self != .回退 && self != .云端同步 }

    fileprivate var 优先级: Int {
        switch self {
        case .自动整理: 0
        case .手动编辑: 1
        case .VNDB导入: 2
        case .同步, .云端同步: 3
        case .合并资料库, .覆盖资料库, .分别保留: 4
        case .导入文件, .从云端恢复, .回退: 5
        }
    }

    private var 编码值: String {
        switch self {
        case .自动整理: "自动整理"
        case .手动编辑: "手动编辑"
        case .VNDB导入: "VNDB导入"
        case .同步: "同步"
        case .合并资料库: "合并资料库"
        case let .覆盖资料库(platform): "覆盖资料库" + (platform.map { ":\($0.rawValue)" } ?? "")
        case let .分别保留(platform): "分别保留" + (platform.map { ":\($0.rawValue)" } ?? "")
        case .导入文件: "导入文件"
        case .从云端恢复: "从云端恢复"
        case .回退: "回退"
        case .云端同步: "云端同步"
        }
    }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        let platform = parts.count > 1 ? 资料库平台(rawValue: parts[1]) : nil
        switch parts.first ?? "" {
        case "自动整理": self = .自动整理
        case "VNDB导入": self = .VNDB导入
        case "同步": self = .同步
        case "合并资料库": self = .合并资料库
        case "覆盖资料库": self = .覆盖资料库(platform)
        case "分别保留": self = .分别保留(platform)
        case "导入文件": self = .导入文件
        case "从云端恢复": self = .从云端恢复
        case "回退": self = .回退
        case "云端同步": self = .云端同步
        default: self = .手动编辑
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(编码值)
    }
}

/// 最近更改中的一条：这次更改前后不同的作品。只保存差异，随 Paper Cloud 上传到其他设备。
struct 资料库更改: Codable, Identifiable, Hashable {
    let id: UUID
    var 时间: Date
    var 原因: 资料库更改原因
    var 差异: [资料库差异项]

    /// 做了什么操作，例如“添加“某作品”到资料库”“合并资料库”。
    var 标题: String {
        guard 原因 == .手动编辑 else { return 原因.标题 }
        guard 差异.count == 1, let item = 差异.first else { return 原因.标题 }
        switch item.种类 {
        case .新增: return String(localized: "添加“\(item.标题)”到资料库")
        case .删除: return String(localized: "从资料库删除“\(item.标题)”")
        case .修改: return String(localized: "编辑“\(item.标题)”")
        }
    }

    /// 资料库变成了什么，例如“添加“某作品”、删除“另一部作品””。
    var 摘要: String {
        let parts = [资料库差异项.种类.新增, .删除, .修改].compactMap { kind in
            Self.描述(差异.filter { $0.种类 == kind }, 种类: kind)
        }
        return parts.isEmpty ? String(localized: "没有更改") : parts.formatted(.list(type: .and, width: .narrow))
    }

    private static func 描述(_ items: [资料库差异项], 种类 kind: 资料库差异项.种类) -> String? {
        guard let first = items.first?.标题 else { return nil }
        let second = items.count > 1 ? items[1].标题 : ""
        switch (kind, items.count) {
        case (.新增, 1): return String(localized: "添加“\(first)”")
        case (.新增, 2): return String(localized: "添加“\(first)”和“\(second)”")
        case (.新增, _): return String(localized: "添加“\(first)”等\(items.count)部作品")
        case (.删除, 1): return String(localized: "删除“\(first)”")
        case (.删除, 2): return String(localized: "删除“\(first)”和“\(second)”")
        case (.删除, _): return String(localized: "删除“\(first)”等\(items.count)部作品")
        case (.修改, 1): return String(localized: "更改“\(first)”")
        case (.修改, 2): return String(localized: "更改“\(first)”和“\(second)”")
        case (.修改, _): return String(localized: "更改“\(first)”等\(items.count)部作品")
        }
    }
}

/// 一部作品在两份资料库之间的差异。只比较用户自己记录的内容（状态、评分、进度、日期与备注），
/// 封面、平均评分这些随平台更新的信息不算更改。
struct 资料库差异项: Codable, Identifiable, Hashable {
    enum 种类: Hashable { case 新增, 删除, 修改 }

    let id: String
    let 之前: 本地资料库条目?
    let 之后: 本地资料库条目?

    var 种类: 种类 {
        if 之前 == nil { return .新增 }
        if 之后 == nil { return .删除 }
        return .修改
    }

    var 条目: 本地资料库条目 { (之后 ?? 之前)! }
    var 标题: String { 条目.标题 }
    var 类型: 作品类型 { 条目.类型 }

    /// 修改了哪些字段：名称、之前、之后。
    var 字段变化: [(名称: String, 之前: String, 之后: String)] {
        guard let 之前, let 之后 else { return [] }
        return Self.字段(之前).indices.compactMap { index in
            let old = Self.字段(之前)[index]
            let new = Self.字段(之后)[index]
            return old.值 == new.值 ? nil : (old.名称, old.值, new.值)
        }
    }

    private static func 字段(_ entry: 本地资料库条目) -> [(名称: String, 值: String)] {
        let none = String(localized: "无")
        return [
            (String(localized: "状态"), entry.状态?.localizedTitle(for: entry.类型) ?? none),
            (String(localized: "评分"), entry.评分.map { String(format: "%.1f", Double($0) / 10) } ?? none),
            (String(localized: "进度"), entry.进度.map { String($0) } ?? none),
            (String(localized: "已读卷数"), entry.卷数.map { String($0) } ?? none),
            (String(localized: "开始日期"), entry.开始日期 ?? none),
            (String(localized: "结束日期"), entry.完成日期 ?? none),
            (String(localized: "备注"), entry.备注?.isEmpty == false ? entry.备注! : none),
        ]
    }

    /// 前后没有用户可见的区别（先添加又删除、改了又改回来）。
    var 无变化: Bool {
        switch (之前, 之后) {
        case (nil, nil): true
        case let (a?, b?): Self.用户记录相同(a, b)
        default: false
        }
    }

    static func 用户记录相同(_ a: 本地资料库条目, _ b: 本地资料库条目) -> Bool {
        a.状态 == b.状态 && a.评分 == b.评分 && a.进度 == b.进度 && a.卷数 == b.卷数
            && a.开始日期 == b.开始日期 && a.完成日期 == b.完成日期
            && (a.备注 ?? "") == (b.备注 ?? "")
    }

    /// 从 `之前` 到 `之后` 的所有差异，按标题排序。
    static func 比较(之前 before: [本地资料库条目], 之后 after: [本地资料库条目]) -> [资料库差异项] {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [资料库差异项] = []
        for key in Set(old.keys).union(new.keys) {
            switch (old[key], new[key]) {
            case let (a?, b?) where !用户记录相同(a, b): items.append(资料库差异项(id: key, 之前: a, 之后: b))
            case let (nil, b?): items.append(资料库差异项(id: key, 之前: nil, 之后: b))
            case let (a?, nil): items.append(资料库差异项(id: key, 之前: a, 之后: nil))
            default: break
            }
        }
        return 排序(items)
    }

    /// 连续两次更改合成一次：每部作品取较早一次的“之前”和较晚一次的“之后”，前后相同的去掉。
    static func 合并(_ older: [资料库差异项], _ newer: [资料库差异项]) -> [资料库差异项] {
        var result = Dictionary(older.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in newer {
            let before = result[item.id].map(\.之前) ?? item.之前
            result[item.id] = 资料库差异项(id: item.id, 之前: before, 之后: item.之后)
        }
        return 排序(result.values.filter { !$0.无变化 })
    }

    private static func 排序(_ items: [资料库差异项]) -> [资料库差异项] {
        items.sorted { $0.标题.localizedStandardCompare($1.标题) == .orderedAscending }
    }

    static func == (lhs: 资料库差异项, rhs: 资料库差异项) -> Bool { lhs.id == rhs.id && lhs.之前 == rhs.之前 && lhs.之后 == rhs.之后 }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    private enum CodingKeys: String, CodingKey { case id, 之前, 之后 }
}

/// 最近10次更改。每次资料库变化后记下前后不同的作品，开启 Paper Cloud 时随资料库一起上传，
/// 各设备合并后显示同一份。回退会删掉被回退的记录，所以回退本身不再另记一条。
@MainActor
final class 资料库更改记录: ObservableObject {
    static let shared = 资料库更改记录()
    static let 最多更改数 = 10

    /// 最新的在前。
    @Published private(set) var 更改: [资料库更改] = []
    @Published private(set) var 正在回退 = false

    private var 所有者: String?
    private var 已载入 = false
    /// 上一次记录时资料库的样子，判断这次是否真的有更改。
    private var 最新条目: [本地资料库条目] = []
    private var 待记录原因: 资料库更改原因?
    private var 待记录任务: Task<Void, Never>?
    /// 回退、导入时由调用方指定原因，期间资料库的保存不再单独记录。
    private var 指定原因: 资料库更改原因?

    private init() {}

    /// 最早的在前，上传到 Paper Cloud 用。
    var 全部更改: [资料库更改] { 更改.reversed() }

    // MARK: 载入

    /// 资料库从磁盘读完后调用。
    func 载入(owner: String, 条目 entries: [本地资料库条目]) {
        guard 所有者 != owner || !已载入 else { return }
        所有者 = owner
        已载入 = true
        待记录任务?.cancel()
        待记录原因 = nil
        let directory = Self.目录(owner)
        if let data = try? Data(contentsOf: directory.appending(path: "changes.json")),
           let value = try? 资料库快照.解码器().decode([资料库更改].self, from: data) {
            更改 = value.reversed()
            最新条目 = 读取快照("latest.zlib")?.entries ?? entries
        } else {
            更改 = 迁移旧记录().reversed()
            最新条目 = entries
            保存()
        }
    }

    func 重置() {
        待记录任务?.cancel()
        所有者 = nil
        已载入 = false
        最新条目 = []
        更改 = []
    }

    // MARK: 记录

    /// 资料库每次保存时调用。2秒内的多次保存（同步时先导入VNDB、再合并其他平台、再整理类型）合成一条。
    func 资料库已保存(owner: String, 原因 reason: 资料库更改原因) {
        guard owner == 所有者 else { return }
        let reason = 指定原因 ?? reason
        if let pending = 待记录原因, pending.优先级 >= reason.优先级 {
            // 保留优先级更高的原因
        } else {
            待记录原因 = reason
        }
        待记录任务?.cancel()
        待记录任务 = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.写入待记录()
        }
    }

    /// 立即写入还在等待合并的更改（例如回退前，确保对比的是最新的资料库）。
    func 立即写入() {
        guard 待记录原因 != nil else { return }
        待记录任务?.cancel()
        写入待记录()
    }

    private func 写入待记录() {
        guard let reason = 待记录原因, let owner = 所有者, 已载入,
              本地资料库.shared.所有者 == owner else { return }
        待记录原因 = nil
        let entries = 本地资料库.shared.条目
        let differences = 资料库差异项.比较(之前: 最新条目, 之后: entries)
        最新条目 = entries

        guard !differences.isEmpty, reason.记录更改 else {
            保存()
            return
        }

        var list = 全部更改
        // 自动整理并入上一条；10分钟内对同一部作品的连续编辑也并成一条，免得10条记录很快被占满
        if let latest = list.last,
           reason == .自动整理
            || (reason == .手动编辑 && latest.原因 == .手动编辑 && Date.now.timeIntervalSince(latest.时间) < 600
                && Set(latest.差异.map(\.id)) == Set(differences.map(\.id))) {
            let merged = 资料库差异项.合并(latest.差异, differences)
            list.removeLast()
            if !merged.isEmpty {
                list.append(资料库更改(id: latest.id, 时间: .now, 原因: latest.原因, 差异: merged))
            }
        } else {
            list.append(资料库更改(id: UUID(), 时间: .now, 原因: reason, 差异: differences))
            list = Array(list.suffix(Self.最多更改数))
        }
        更改 = list.reversed()
        保存()
        PaperAccount账户.shared.安排备份(原因: reason)
    }

    // MARK: 回退

    struct 回退结果 {
        var 已回退 = 0
        var 失败: [(标题: String, 原因: String)] = []
    }

    enum 回退位置 {
        /// 撤销这次及之后的所有更改。
        case 之前
        /// 只撤销这次之后的更改。
        case 之后
    }

    /// 把资料库回退到某次更改之前或之后，并删掉被回退的记录。
    func 回退(_ change: 资料库更改, 到 position: 回退位置, vndbToken: String) async -> 回退结果 {
        立即写入()
        guard let index = 更改.firstIndex(where: { $0.id == change.id }) else { return 回退结果() }
        let reverted = Array(更改.prefix(position == .之前 ? index + 1 : index))
        guard !reverted.isEmpty else { return 回退结果() }
        // 从最新往前逐条撤销：同一部作品以最早那次更改之前的样子为准
        var targets: [String: 本地资料库条目?] = [:]
        for record in reverted {
            for item in record.差异 { targets.updateValue(item.之前, forKey: item.id) }
        }
        let result = await 应用(targets, 原因: .回退, vndbToken: vndbToken)
        let ids = Set(reverted.map(\.id))
        更改.removeAll { ids.contains($0.id) }
        保存()
        PaperAccount账户.shared.安排备份(原因: .回退)
        return result
    }

    /// 把选中的作品改成 `目标` 中的样子（nil 表示从资料库删除）。
    /// 视觉小说直接写入VNDB；动画、漫画与轻小说先改资料库，再交给PaperVN Sync推送到已登录的平台。
    func 应用(
        _ targets: [String: 本地资料库条目?],
        原因 reason: 资料库更改原因,
        vndbToken: String,
        同步状态 restoredSync: 同步状态存储? = nil
    ) async -> 回退结果 {
        guard let owner = 本地资料库.shared.所有者, 本地资料库.shared.可写入 else { return 回退结果() }
        立即写入()
        正在回退 = true
        defer { 正在回退 = false }
        指定原因 = reason
        defer { 指定原因 = nil }

        var result = 回退结果()
        let current = Dictionary(本地资料库.shared.条目.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var entries = current
        var changedOthers: [(之前: 本地资料库条目?, 之后: 本地资料库条目?)] = []

        for (key, target) in targets {
            let existing = current[key]
            switch (existing, target) {
            case (nil, nil): continue
            case let (a?, b?) where 资料库差异项.用户记录相同(a, b): continue
            default: break
            }
            // 修改时间记为现在，与其他设备合并时以这次为准
            var target = target
            target?.修改时间 = .now
            let type = (target ?? existing)!.类型
            let title = (target ?? existing)!.标题
            if type == .visualNovel {
                let vnID = (target ?? existing)!.平台ID[.vndb] ?? String(key.dropFirst(3))
                do {
                    try await Self.写入VNDB(vnID: vnID, 目标: target, token: vndbToken)
                    entries[key] = target
                    result.已回退 += 1
                } catch {
                    result.失败.append((title, error.localizedDescription))
                }
            } else {
                entries[key] = target
                changedOthers.append((existing, target))
                result.已回退 += 1
            }
        }

        if let restoredSync, 同步状态存储.读取(owner: owner).基线.isEmpty {
            // 重新安装后从云端恢复：本机还没有同步记录时换上备份里的
            restoredSync.保存(owner: owner)
        }
        本地资料库.shared.应用回退(Array(entries.values), owner: owner)
        PaperVNSync中心.shared.标记待推送(changedOthers)
        立即写入()
        if !changedOthers.isEmpty {
            Task { await PaperVNSync中心.shared.同步动画漫画() }
        }
        return result
    }

    /// Paper Cloud 同步合并后换上新的资料库与最近更改。改动的视觉小说等登录VNDB时写入VNDB，
    /// 其他作品标记待推送，由 PaperVN Sync 写入已登录的平台。
    func 合并云端(
        _ merged: [本地资料库条目],
        同步状态 restoredSync: 同步状态存储?,
        云端更改 remoteChanges: [资料库更改]?,
        基准更改ID baseIDs: Set<UUID>
    ) async {
        guard let owner = 本地资料库.shared.所有者, 本地资料库.shared.可写入 else { return }
        立即写入()
        if let remoteChanges { 合并更改(remoteChanges, 基准: baseIDs) }
        let differences = 资料库差异项.比较(之前: 本地资料库.shared.条目, 之后: merged)
        let added = Set(merged.map(\.id)).subtracting(本地资料库.shared.条目.map(\.id))
        guard !differences.isEmpty || !added.isEmpty else { return }
        指定原因 = .云端同步
        defer { 指定原因 = nil }
        if let restoredSync, 同步状态存储.读取(owner: owner).基线.isEmpty {
            restoredSync.保存(owner: owner)
        }
        本地资料库.shared.应用回退(merged, owner: owner)
        var store = 同步状态存储.读取(owner: owner)
        for item in differences where item.类型 == .visualNovel {
            store.待推送VNDB.insert(item.id)
            if item.之后 == nil { store.本地已删除.insert(item.id) } else { store.本地已删除.remove(item.id) }
        }
        store.保存(owner: owner)
        let others = differences.filter { $0.类型 != .visualNovel }.map { (之前: $0.之前, 之后: $0.之后) }
        PaperVNSync中心.shared.标记待推送(others)
        立即写入()
        if !others.isEmpty {
            Task { await PaperVNSync中心.shared.同步动画漫画() }
        }
    }

    /// 三方合并最近更改：上次同步后本机新增的记录保留，本机删掉（回退）的不再从云端加回来，
    /// 其他设备删掉的本机也删掉。
    private func 合并更改(_ remote: [资料库更改], 基准 base: Set<UUID>) {
        let local = Dictionary(更改.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let removedHere = base.subtracting(local.keys)
        var result: [UUID: 资料库更改] = [:]
        for change in remote where !removedHere.contains(change.id) {
            result[change.id] = change
        }
        for change in local.values where !base.contains(change.id) || (result[change.id].map { $0.时间 < change.时间 } ?? false) {
            result[change.id] = change
        }
        let list = result.values.sorted { $0.时间 < $1.时间 }.suffix(Self.最多更改数)
        guard Array(list.reversed()) != 更改 else { return }
        更改 = list.reversed()
        保存()
    }

    private static func 写入VNDB(vnID: String, 目标 target: 本地资料库条目?, token: String) async throws {
        // 没登录VNDB时 VNDB服务 会改为写入本地资料库
        guard let target else {
            try await VNDB服务.shared.deleteUserListEntry(token: token, vnID: vnID)
            return
        }
        try await VNDB服务.shared.restoreUserListEntry(
            token: token,
            vnID: vnID,
            labels: (target.vndb?.labels ?? []).map(\.id).filter { $0 != 7 && !(1...5).contains($0) }
                + [target.状态?.用户列表筛选.labelID].compactMap { $0 },
            vote: target.评分,
            started: target.开始日期,
            finished: target.完成日期,
            notes: target.备注
        )
    }

    // MARK: 存储

    nonisolated static func 目录(_ owner: String) -> URL {
        let safeOwner = owner.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? owner
        return URL.applicationSupportDirectory
            .appending(path: "资料库更改记录", directoryHint: .isDirectory)
            .appending(path: safeOwner, directoryHint: .isDirectory)
    }

    /// 最近更改写入 changes.json；上一次记录时的资料库压缩后写入 latest.zlib，App 被关掉后还能找出没记下的更改。
    private func 保存() {
        guard let owner = 所有者 else { return }
        let directory = Self.目录(owner)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? 资料库快照.编码器().encode(全部更改) {
            try? data.write(to: directory.appending(path: "changes.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        let snapshot = 资料库快照(owner: owner, createdAt: .now, reason: nil, appVersion: 资料库快照.当前App版本, entries: 最新条目)
        if let json = try? 资料库快照.编码器().encode(snapshot),
           let data = try? (json as NSData).compressed(using: .zlib) as Data {
            try? data.write(to: directory.appending(path: "latest.zlib"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func 读取快照(_ file: String) -> 资料库快照? {
        guard let owner = 所有者, !file.isEmpty,
              let data = try? Data(contentsOf: Self.目录(owner).appending(path: file)),
              let json = try? (data as NSData).decompressed(using: .zlib) as Data else { return nil }
        return try? 资料库快照.解码器().decode(资料库快照.self, from: json)
    }

    /// 旧版每次更改保存一份完整快照（index.json 与各 .zlib）：换算成前后差异，然后删掉旧文件。
    private func 迁移旧记录() -> [资料库更改] {
        struct 旧更改: Decodable {
            let id: UUID
            let 时间: Date
            let 原因: 资料库更改原因
            let 快照文件: String
        }
        struct 旧索引: Decodable {
            let 基准: String
            let 更改: [旧更改]
        }
        guard let owner = 所有者 else { return [] }
        let directory = Self.目录(owner)
        guard let data = try? Data(contentsOf: directory.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(旧索引.self, from: data) else { return [] }
        var result: [资料库更改] = []
        var previous = 读取快照(index.基准)?.entries
        for change in index.更改 {
            guard let after = 读取快照(change.快照文件)?.entries else { continue }
            if let before = previous {
                let differences = 资料库差异项.比较(之前: before, 之后: after)
                if !differences.isEmpty, change.原因.记录更改 {
                    result.append(资料库更改(id: change.id, 时间: change.时间, 原因: change.原因, 差异: differences))
                }
            }
            previous = after
        }
        let files = [index.基准] + index.更改.map(\.快照文件) + ["index.json"]
        for file in files where !file.isEmpty {
            try? FileManager.default.removeItem(at: directory.appending(path: file))
        }
        return result
    }
}

enum 资料库回退错误: LocalizedError {
    case 需要登录

    var errorDescription: String? {
        switch self {
        case .需要登录: String(localized: "登录Paper账户或任意平台账户后才能使用资料库。")
        }
    }
}

extension PaperVNSync中心 {
    /// 回退、导入或恢复后，把改动的动画、漫画与轻小说标记为待推送：下次同步时写入已登录的平台，
    /// 而不是被平台上的旧记录盖回来。删除的作品记入“在 PaperVN 中删除”，同步时不会再恢复。
    func 标记待推送(_ changes: [(之前: 本地资料库条目?, 之后: 本地资料库条目?)]) {
        guard !changes.isEmpty, let owner = 本地资料库.shared.所有者 else { return }
        var store = 同步状态存储.读取(owner: owner)
        for change in changes {
            guard let entry = change.之后 ?? change.之前 else { continue }
            let platforms = 已登录平台.filter { $0.可导出 && $0.同步能力.支持的类型.contains(entry.类型) }
            store.待推送[entry.id, default: []].formUnion(platforms)
            if store.待推送[entry.id]?.isEmpty == true { store.待推送[entry.id] = nil }
            if change.之后 == nil {
                store.本地已删除.insert(entry.id)
            } else {
                store.本地已删除.remove(entry.id)
            }
        }
        store.保存(owner: owner)
    }
}
