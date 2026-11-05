import Combine
import Foundation

/// 资料库里的作品类型。
nonisolated enum 作品类型: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case anime
    case manga
    case lightNovel
    case visualNovel

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .anime: String(localized: "动画")
        case .manga: String(localized: "漫画")
        case .lightNovel: String(localized: "轻小说")
        case .visualNovel: String(localized: "视觉小说")
        }
    }

    var symbolName: String {
        switch self {
        case .anime: "play.square.stack"
        case .manga: "richtext.page.ja"
        case .lightNovel: "text.book.closed"
        case .visualNovel: "zipper.page"
        }
    }
}

/// 资料库状态。文案随作品类型变化：视觉小说是“游玩”，动画是“看”，漫画与轻小说是“读”。
nonisolated enum 资料库状态: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case inProgress
    case completed
    case onHold
    case dropped
    case planning

    var id: Self { self }

    /// 状态名称随作品类型变化：视觉小说是“游玩”，动画是“观看”，漫画与轻小说是“阅读”。
    func localizedTitle(for type: 作品类型) -> String {
        switch (self, type) {
        case (.inProgress, .visualNovel): String(localized: "游玩中")
        case (.inProgress, .anime): String(localized: "观看中")
        case (.inProgress, .manga), (.inProgress, .lightNovel): String(localized: "阅读中")
        case (.completed, .visualNovel): String(localized: "已游玩")
        case (.completed, .anime): String(localized: "已观看")
        case (.completed, .manga), (.completed, .lightNovel): String(localized: "已阅读")
        case (.onHold, _): String(localized: "搁置")
        case (.dropped, _): String(localized: "抛弃")
        case (.planning, .visualNovel): String(localized: "计划游玩")
        case (.planning, .anime): String(localized: "计划观看")
        case (.planning, .manga), (.planning, .lightNovel): String(localized: "计划阅读")
        }
    }

    init?(_ filter: 用户列表筛选) {
        switch filter {
        case .all: return nil
        case .playing: self = .inProgress
        case .finished: self = .completed
        case .stalled: self = .onHold
        case .dropped: self = .dropped
        case .planning: self = .planning
        }
    }

    var 用户列表筛选: 用户列表筛选 {
        switch self {
        case .inProgress: .playing
        case .completed: .finished
        case .onHold: .stalled
        case .dropped: .dropped
        case .planning: .planning
        }
    }
}

/// PaperVN Sync可以同步的平台。
enum 资料库平台: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case vndb
    case bangumi
    case myAnimeList
    case aniList
    case annict
    case tmdb

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .vndb: "VNDB"
        case .bangumi: String(localized: "Bangumi番组计划")
        case .myAnimeList: "MyAnimeList"
        case .aniList: "AniList"
        case .annict: "Annict"
        case .tmdb: "TMDB"
        }
    }
}

/// 本地资料库中的一条记录。本地资料库是事实来源，各平台的资料库由PaperVN Sync同步。
struct 本地资料库条目: Codable, Identifiable, Hashable {
    /// PaperVN ID。映射目录上线前，视觉小说暂用“vn:”加VNDB ID。
    var id: String
    var 类型: 作品类型
    var 平台ID: [资料库平台: String]
    var 状态: 资料库状态?
    /// 10–100，与VNDB的投票精度一致。
    var 评分: Int?
    var 开始日期: String?
    var 完成日期: String?
    var 备注: String?
    var 加入时间: Date?
    var 修改时间: Date?

    var 标题: String
    /// 各平台作品的平均评分，10–100。
    var 平均评分: Double?
    var 发行日期: String?
    var 封面地址: String?
    /// 动画是看到第几集，漫画与轻小说是读到第几话。
    var 进度: Int?
    var 总数: Int?
    /// 漫画与轻小说读到第几卷。
    var 卷数: Int?
    var 总卷数: Int?
    /// 用于在 Annict 等日文平台上查找作品。
    var 日文标题: String?
    /// 各语言的标题，显示时按标题语言设置选择（与视觉小说共用同一套规则）。
    var 多语言标题: [用户多语言标题]?

    /// 视觉小说的完整VNDB记录，资料库行、编辑页与详情页仍然依赖它。
    var vndb: 用户列表项目?
    /// 在 PaperVN 中清除、VNDB上却清除不了的日期（VNDB API 不接受 null，见 `VNDB服务.patchUserList`）：
    /// "started"、"finished" → 清除时VNDB上的值。随条目同步到其他设备；VNDB修好之后删掉。
    var VNDB已清除日期: [String: String]?

    static func 视觉小说ID(_ vndbID: String) -> String { "vn:\(vndbID)" }

    /// 映射目录上线前，MAL 的作品暂用“mal-anime:”“mal-manga:”加 MAL ID。
    static func MyAnimeListID(_ kind: MyAnimeList列表项.种类, _ id: Int) -> String {
        "mal-\(kind.rawValue):\(id)"
    }

    init(id: String, 类型: 作品类型, 平台ID: [资料库平台: String], 标题: String, 加入时间: Date?) {
        self.id = id
        self.类型 = 类型
        self.平台ID = 平台ID
        self.标题 = 标题
        self.加入时间 = 加入时间
    }

    init(myAnimeList item: MyAnimeList列表项) {
        id = Self.MyAnimeListID(item.kind, item.id)
        类型 = item.类型
        平台ID = [.myAnimeList: String(item.id)]
        状态 = item.状态
        评分 = item.评分 > 0 ? item.评分 * 10 : nil
        开始日期 = item.开始日期
        完成日期 = item.完成日期
        备注 = nil
        加入时间 = nil
        修改时间 = item.修改时间
        标题 = item.标题
        平均评分 = item.平均评分.map { $0 * 10 }
        发行日期 = item.发行日期
        封面地址 = item.封面地址
        进度 = item.进度
        总数 = item.总数
        卷数 = item.卷数 > 0 ? item.卷数 : nil
        总卷数 = item.总卷数
        日文标题 = item.日文标题
        vndb = nil
    }

    /// MAL 记录在 MAL 上的种类与 ID。
    var myAnimeList: (kind: MyAnimeList列表项.种类, id: Int)? {
        guard let id = malID else { return nil }
        return (类型 == .anime ? .anime : .manga, id)
    }

    /// MAL ID：来自 MAL 本身，或者 AniList、Annict 记录里的对应关系（PaperVN ID 里也带着它）。
    var malID: Int? {
        if let value = 平台ID[.myAnimeList], let id = Int(value) { return id }
        guard id.hasPrefix("mal-"), let value = id.split(separator: ":").last else { return nil }
        return Int(value)
    }

    /// 按 `VNDB已清除日期` 去掉VNDB上清除不了的日期。VNDB上的日期已经改过的（例如在网站上改了），以VNDB为准，不再保持清除。
    mutating func 应用VNDB已清除日期(_ cleared: [String: String]) {
        guard let item = vndb else { return }
        var remaining: [String: String] = [:]
        remaining["started"] = cleared["started"].flatMap { $0 == item.started ? $0 : nil }
        remaining["finished"] = cleared["finished"].flatMap { $0 == item.finished ? $0 : nil }
        VNDB已清除日期 = remaining.isEmpty ? nil : remaining
        guard !remaining.isEmpty else { return }
        let clearsStarted = remaining["started"] != nil
        let clearsFinished = remaining["finished"] != nil
        if clearsStarted { 开始日期 = nil }
        if clearsFinished { 完成日期 = nil }
        vndb = 用户列表项目(
            id: item.id, added: item.added, lastmod: item.lastmod, vote: item.vote,
            started: clearsStarted ? nil : item.started,
            finished: clearsFinished ? nil : item.finished,
            notes: item.notes, labels: item.labels, releases: item.releases, vn: item.vn
        )
    }

    init(vndb item: 用户列表项目) {
        id = Self.视觉小说ID(item.id)
        类型 = .visualNovel
        var ids: [资料库平台: String] = [.vndb: item.id]
        if let bangumiID = 视觉小说外部ID目录.shared.ids(for: item.id).bangumiIDs.first {
            ids[.bangumi] = String(bangumiID)
        }
        平台ID = ids
        状态 = item.primaryStatus.flatMap(资料库状态.init)
        评分 = item.vote
        开始日期 = item.started
        完成日期 = item.finished
        备注 = item.notes
        加入时间 = item.added.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        修改时间 = item.lastmod.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        标题 = item.vn.title
        平均评分 = item.vn.rating
        发行日期 = item.vn.released
        vndb = item
    }
}

/// 本地资料库。按账户分别保存在应用支持目录中。
@MainActor
final class 本地资料库: ObservableObject {
    static let shared = 本地资料库()
    /// 没有登录 Paper Account 与VNDB、只登录了其他平台时，资料库属于此设备。
    nonisolated static let 本机所有者 = "local"

    @Published private(set) var 条目: [本地资料库条目] = [] {
        didSet { 修订号 &+= 1 }
    }
    /// 条目每变一次加一。页面用它判断资料库是否变化，不用逐项比较整个数组。
    @Published private(set) var 修订号 = 0
    /// 当前账户的资料库已经从磁盘读出（不代表已和平台同步）。
    @Published private(set) var 已载入 = false
    private(set) var 所有者: String?
    /// 资料库文件存在但读不出来。此时不保存、不同步，避免用空资料库覆盖原来的内容。
    private(set) var 载入失败 = false
    /// 可以安全写入：已经从磁盘读完，并且读取成功。
    var 可写入: Bool { 已载入 && !载入失败 && 所有者 != nil }

    /// 等资料库从磁盘读完。导入、同步之前都要先等它，否则会把还没读出来的资料库当成空的。
    func 等待载入() async {
        await 载入任务?.value
    }

    private var 载入任务: Task<Void, Never>?

    private init() {}

    /// 登录、退出或切换账户时调用。`迁移来源` 依次检查：新所有者还没有资料库时，
    /// 把第一个有资料库的来源（例如登录 Paper Account 前的VNDB资料库）整体搬过来，资料库跟着同一个人走。
    func 切换所有者(_ owner: String?, 迁移来源: [String] = []) {
        let owner = owner?.isEmpty == false ? owner : nil
        guard owner != 所有者 else { return }
        if let owner, !FileManager.default.fileExists(atPath: Self.文件地址(owner: owner).path()),
           let source = 迁移来源.first(where: { $0 != owner && FileManager.default.fileExists(atPath: Self.文件地址(owner: $0).path()) }) {
            Self.搬移资料库(从: source, 到: owner)
        }
        所有者 = owner
        资料库更改记录.shared.重置()
        条目 = []
        已载入 = false
        载入任务?.cancel()
        guard let owner else { return }
        let url = Self.文件地址(owner: owner)
        载入失败 = false
        载入任务 = Task { [weak self] in
            let values: [本地资料库条目]? = await Task.detached(priority: .userInitiated) {
                // 没有文件是正常的空资料库；有文件却读不出来时不能当成空的，否则下一次保存会把它覆盖掉
                guard let data = try? Data(contentsOf: url) else { return [本地资料库条目]() }
                guard var decoded = try? JSONDecoder().decode([本地资料库条目].self, from: data) else {
                    let backup = url.deletingPathExtension()
                        .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
                    try? FileManager.default.copyItem(at: url, to: backup)
                    return nil
                }
                // 显示之前先补上作品映射里预装的中文名，资料库一出现就是最终的标题
                Bangumi中文名补全.预装(&decoded)
                // 漫画、轻小说按以前读到的分类改正，旧版本分错的作品一出现就在正确的类型里
                书籍类型判定.改正(&decoded)
                return decoded
            }.value
            guard let self, !Task.isCancelled, self.所有者 == owner else { return }
            self.条目 = values ?? []
            self.载入失败 = values == nil
            self.已载入 = true
            if values != nil { 资料库更改记录.shared.载入(owner: owner, 条目: self.条目) }
            self.安排改正书籍类型()
        }
    }

    /// 用VNDB的完整列表更新视觉小说。VNDB暂时是视觉小说的权威来源，VNDB中没有的视觉小说会被移除。
    func 导入VNDB(_ items: [用户列表项目], owner: String) {
        // 资料库还没读完时导入，会只留下视觉小说，把动画、漫画与轻小说覆盖掉
        guard owner == 所有者, 可写入 else { return }
        let cleared = Dictionary(条目.compactMap { entry in entry.VNDB已清除日期.map { (entry.id, $0) } },
                                 uniquingKeysWith: { first, _ in first })
        let imported = items.map { item in
            var entry = 本地资料库条目(vndb: item)
            if let dates = cleared[entry.id] { entry.应用VNDB已清除日期(dates) }
            return entry
        }
        // VNDB上删掉的作品记为已删除，导入 Bangumi 的视觉小说时不再加回来；VNDB上有的作品取消这个记录
        let importedKeys = Set(imported.map(\.id))
        let removed = 条目.filter { $0.类型 == .visualNovel && !importedKeys.contains($0.id) }.map(\.id)
        var store = 同步状态存储.读取(owner: owner)
        store.本地已删除.formUnion(removed)
        store.本地已删除.subtract(importedKeys)
        store.保存(owner: owner)
        条目 = 条目.filter { $0.类型 != .visualNovel } + imported
        保存(原因: .VNDB导入)
    }

    /// 动画、漫画与轻小说（视觉小说以外的作品），按 PaperVN ID 索引。
    var 动画漫画条目: [String: 本地资料库条目] {
        Dictionary(条目.filter { $0.类型 != .visualNovel }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// PaperVN Sync 合并完成后，整体替换动画、漫画与轻小说。`原因` 区分一般同步与第一次同步时选择的导入方式。
    func 替换动画漫画(_ entries: [本地资料库条目], owner: String, 原因 reason: 资料库更改原因 = .同步) {
        guard owner == 所有者, 可写入 else { return }
        条目 = 条目.filter { $0.类型 == .visualNovel } + entries
        保存(原因: reason)
        安排改正书籍类型()
    }

    /// PaperVN Sync 认出的音乐（MV）、广告等不能导入的条目从资料库移除，平台上的记录不动。
    func 移除不可导入的条目(_ unsupported: 不可导入的条目, owner: String) {
        guard owner == 所有者, 可写入 else { return }
        let count = 条目.count
        条目.removeAll { $0.类型 != .visualNovel && unsupported.包含($0) }
        if 条目.count != count { 保存(原因: .自动整理) }
    }

    /// 回退、导入资料库或从云端恢复后整体换上新的作品。
    func 应用回退(_ entries: [本地资料库条目], owner: String) {
        guard owner == 所有者, 可写入 else { return }
        条目 = entries
        保存(原因: .回退)
        安排改正书籍类型()
    }

    /// 新加入资料库的作品（例如在详情页加入计划）。
    func 添加(_ entry: 本地资料库条目) {
        guard 所有者 != nil else { return }
        var entries = [entry]
        Bangumi中文名补全.预装(&entries)
        书籍类型判定.改正(&entries)
        var entry = entries[0]
        entry.加入时间 = entry.加入时间 ?? .now
        entry.修改时间 = .now
        条目.removeAll { $0.id == entry.id }
        条目.append(entry)
        保存()
        安排改正书籍类型()
    }

    private var 书籍类型任务: Task<Void, Never>?

    /// 漫画与轻小说按公开接口读到的分类改正（见 `书籍类型判定`），不需要登录任何平台。
    /// 依次执行：前一次还在读取时，这一次等它读完再看有没有新加入的作品。
    private func 安排改正书籍类型() {
        let previous = 书籍类型任务
        书籍类型任务 = Task { [weak self] in
            await previous?.value
            await self?.改正书籍类型()
        }
        // 以前导入的音乐（MV）等条目也在这些时候检查
        PaperVNSync中心.shared.安排检查不可导入的条目()
    }

    private func 改正书籍类型() async {
        guard 可写入, let owner = 所有者 else { return }
        let books = 条目.filter { $0.类型 == .manga || $0.类型 == .lightNovel }
        guard !books.isEmpty else { return }
        let token = try? await PaperVNSync中心.shared.bangumi?.validAccessToken()
        let types = await 书籍类型判定.读取(books, bangumiToken: token)
        guard 可写入, 所有者 == owner else { return }
        var entries = 条目
        var changed = false
        for index in entries.indices where entries[index].类型 == .manga || entries[index].类型 == .lightNovel {
            guard let type = types[entries[index].id], type != entries[index].类型 else { continue }
            entries[index].类型 = type
            changed = true
        }
        guard changed else { return }
        条目 = entries
        保存(原因: .自动整理)
    }

    /// 本地先改，改完由调用方推送到平台。
    func 更新(_ entry: 本地资料库条目) {
        guard let index = 条目.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        entry.修改时间 = .now
        条目[index] = entry
        保存()
    }

    /// 登录了VNDB与 Paper Account 时在编辑页清除的日期：VNDB上清除不了，只在资料库中清除，并记下VNDB上原来的值，
    /// 之后导入VNDB时继续保持清除（见 `本地资料库条目.VNDB已清除日期`）。
    func 记录VNDB已清除日期(vnID: String, started: String?, finished: String?) {
        guard 可写入, let index = 条目.firstIndex(where: { $0.id == 本地资料库条目.视觉小说ID(vnID) }) else { return }
        var entry = 条目[index]
        var cleared = entry.VNDB已清除日期 ?? [:]
        if let started { cleared["started"] = started }
        if let finished { cleared["finished"] = finished }
        entry.应用VNDB已清除日期(cleared)
        更新(entry)
    }

    func 删除(id: String) {
        条目.removeAll { $0.id == id }
        保存()
    }

    private func 保存(原因 reason: 资料库更改原因 = .手动编辑) {
        guard 可写入, let owner = 所有者 else { return }
        资料库更改记录.shared.资料库已保存(owner: owner, 原因: reason)
        let values = 条目
        let url = Self.文件地址(owner: owner)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(values) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: url, options: .atomic)
        }
    }

    /// 资料库、同步记录与更改记录一起搬到新的所有者名下。Paper Account 的同步基准属于账户本身，不搬。
    nonisolated static func 搬移资料库(从 source: String, 到 target: String) {
        let manager = FileManager.default
        let pairs = [
            (文件地址(owner: source), 文件地址(owner: target)),
            (同步状态存储.文件地址(owner: source), 同步状态存储.文件地址(owner: target)),
            (资料库更改记录.目录(source), 资料库更改记录.目录(target)),
        ]
        for (from, to) in pairs where manager.fileExists(atPath: from.path()) && !manager.fileExists(atPath: to.path()) {
            try? manager.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? manager.moveItem(at: from, to: to)
        }
    }

    nonisolated static func 文件地址(owner: String) -> URL {
        let safeOwner = owner.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? owner
        return URL.applicationSupportDirectory
            .appending(path: "本地资料库", directoryHint: .isDirectory)
            .appending(path: "\(safeOwner).json")
    }
}

/// 资料库在本地排序（以前由VNDB服务器排序）。没有值的作品总排在最后。
enum 资料库排序 {
    static func 排序(
        _ items: [用户列表项目],
        by sort: 用户列表排序,
        isDescending: Bool,
        title: (用户列表项目) -> String
    ) -> [用户列表项目] {
        if sort == .title {
            let keyed = items.map { (item: $0, title: title($0)) }
            return keyed.sorted { lhs, rhs in
                let order = lhs.title.localizedStandardCompare(rhs.title)
                if order != .orderedSame {
                    return isDescending ? order == .orderedDescending : order == .orderedAscending
                }
                return lhs.item.id < rhs.item.id
            }
            .map(\.item)
        }

        func value(_ item: 用户列表项目) -> Double? {
            switch sort {
            case .lastModified: (item.lastmod ?? item.added).map(Double.init)
            case .rating: item.vote.map(Double.init)
            case .averageRating: item.vn.rating
            case .releaseDate: item.vn.released.flatMap(发行日期排序值)
            case .title: nil
            }
        }

        let keyed = items.map { (item: $0, value: value($0)) }
        return keyed.sorted { lhs, rhs in
            switch (lhs.value, rhs.value) {
            case let (l?, r?) where l != r:
                return isDescending ? l > r : l < r
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                return lhs.item.id < rhs.item.id
            }
        }
        .map(\.item)
    }

    /// 视觉小说以外的作品（没有VNDB记录）按同样的规则排序。
    static func 排序(
        _ entries: [本地资料库条目],
        by sort: 用户列表排序,
        isDescending: Bool,
        title: (本地资料库条目) -> String = \.标题
    ) -> [本地资料库条目] {
        if sort == .title {
            let titles = Dictionary(entries.map { ($0.id, title($0)) }, uniquingKeysWith: { first, _ in first })
            return entries.sorted { lhs, rhs in
                let order = (titles[lhs.id] ?? lhs.标题).localizedStandardCompare(titles[rhs.id] ?? rhs.标题)
                if order != .orderedSame {
                    return isDescending ? order == .orderedDescending : order == .orderedAscending
                }
                return lhs.id < rhs.id
            }
        }

        func value(_ entry: 本地资料库条目) -> Double? {
            switch sort {
            case .lastModified: (entry.修改时间 ?? entry.加入时间)?.timeIntervalSince1970
            case .rating: entry.评分.map(Double.init)
            case .averageRating: entry.平均评分
            case .releaseDate: entry.发行日期.flatMap(发行日期排序值)
            case .title: nil
            }
        }

        return entries
            .map { (entry: $0, value: value($0)) }
            .sorted { lhs, rhs in
                switch (lhs.value, rhs.value) {
                case let (l?, r?) where l != r:
                    return isDescending ? l > r : l < r
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return lhs.entry.id < rhs.entry.id
                }
            }
            .map(\.entry)
    }

    /// 视觉小说还未发行：VNDB没有日期或写着“TBA”都算；只有年份或年月时按最晚的那天算（VNDB用它表示还没定下具体日期）。
    static func 未发行(_ item: 用户列表项目) -> Bool {
        guard let value = item.vn.released.flatMap(发行日期排序值) else { return true }
        return value > 今天的日期值
    }

    /// 动画、漫画、轻小说还未发行或播出：没有日期时不算（可能只是平台没提供）；
    /// 只有年份或年月时按最早的那天算，Annict之类只给年份的作品不会整年都被当作未播出。
    static func 未发行(_ entry: 本地资料库条目) -> Bool {
        guard let released = entry.发行日期, !released.isEmpty else { return false }
        let parts = released.split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first else { return true }
        let month = parts.count > 1 ? parts[1] : 1
        let day = parts.count > 2 ? parts[2] : 1
        return Double(year * 10_000 + month * 100 + day) > 今天的日期值
    }

    private static var 今天的日期值: Double {
        let today = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return Double((today.year ?? 0) * 10_000 + (today.month ?? 0) * 100 + (today.day ?? 0))
    }

    /// “2019-05-31”“2019-05”“2019”以及“TBA”之类的发行日期转成可比较的数值。
    private static func 发行日期排序值(_ value: String) -> Double? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first else { return nil }
        let month = parts.count > 1 ? parts[1] : 12
        let day = parts.count > 2 ? parts[2] : 31
        return Double(year * 10_000 + month * 100 + day)
    }
}

#if DEBUG
extension 本地资料库 {
    /// 预览用：换成示例条目，不读写磁盘。
    func 预览载入(_ entries: [本地资料库条目]) {
        载入任务?.cancel()
        所有者 = "preview"
        载入失败 = false
        条目 = entries
        已载入 = true
    }
}
#endif

// MARK: - 没登录VNDB时的视觉小说

extension 本地资料库 {
    private static let 默认标签名称: [Int: String] = [
        1: "Playing", 2: "Finished", 3: "Stalled", 4: "Dropped", 5: "Wishlist", 6: "Blacklist", 7: "Voted",
    ]

    /// 没登录VNDB时，视觉小说的更改只写进本地资料库（随 Paper Account 同步），登录VNDB后再写入VNDB。
    /// `values` 与VNDB的 PATCH /ulist 一致：labels、labels_set、labels_unset、vote、started、finished、notes。
    func 本地写入视觉小说(vnID: String, values: [String: Any]) async throws {
        guard let owner = 所有者, 可写入 else { throw 资料库回退错误.需要登录 }
        let key = 本地资料库条目.视觉小说ID(vnID)
        let existing = 条目.first { $0.id == key }
        let item: 用户列表项目
        if let current = existing?.vndb {
            item = current
        } else {
            let details = try await VNDB服务.shared.fetchUserListDetails(vnID: vnID)
            item = 用户列表项目(
                id: vnID, added: Int(Date.now.timeIntervalSince1970), vote: nil, started: nil, finished: nil,
                notes: nil, labels: [], releases: nil, vn: details
            )
        }

        var labelIDs = Set((item.labels ?? []).map(\.id))
        if let labels = values["labels"] as? [Int] { labelIDs = Set(labels) }
        if let added = values["labels_set"] as? [Int] { labelIDs.formUnion(added) }
        if let removed = values["labels_unset"] as? [Int] { labelIDs.subtract(removed) }
        func text(_ key: String, _ current: String?) -> String? {
            guard values.keys.contains(key) else { return current }
            return values[key] as? String
        }
        let vote: Int? = values.keys.contains("vote") ? values["vote"] as? Int : item.vote
        if vote != nil { labelIDs.insert(7) } else { labelIDs.remove(7) }
        let names = Dictionary((item.labels ?? []).map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
        let updated = 用户列表项目(
            id: item.id,
            added: item.added,
            lastmod: Int(Date.now.timeIntervalSince1970),
            vote: vote,
            started: text("started", item.started),
            finished: text("finished", item.finished),
            notes: text("notes", item.notes),
            labels: labelIDs.sorted().map { 用户列表项目.用户列表标签(id: $0, label: names[$0] ?? Self.默认标签名称[$0] ?? "") },
            releases: item.releases,
            vn: item.vn
        )
        var entry = 本地资料库条目(vndb: updated)
        if let existing {
            entry.平台ID.merge(existing.平台ID) { new, _ in new }
            entry.加入时间 = existing.加入时间
        }
        添加(entry)
        var store = 同步状态存储.读取(owner: owner)
        store.待推送VNDB.insert(key)
        store.本地已删除.remove(key)
        store.保存(owner: owner)
    }

    /// Bangumi番组计划上收藏的视觉小说加入资料库（只加资料库里还没有的），并记为待写入VNDB。
    func 导入视觉小说(_ entries: [本地资料库条目], owner: String) {
        guard owner == 所有者, 可写入 else { return }
        let existing = Set(条目.map(\.id))
        let added = entries.filter { !existing.contains($0.id) }
        guard !added.isEmpty else { return }
        var values = added
        Bangumi中文名补全.预装(&values)
        条目 += values
        保存(原因: .同步)
        var store = 同步状态存储.读取(owner: owner)
        store.待推送VNDB.formUnion(added.map(\.id))
        store.保存(owner: owner)
    }

    func 记录已删除视觉小说(_ keys: [String]) {
        guard let owner = 所有者, !keys.isEmpty else { return }
        var store = 同步状态存储.读取(owner: owner)
        store.本地已删除.formUnion(keys)
        store.保存(owner: owner)
    }

    func 本地删除视觉小说(vnID: String) {
        guard let owner = 所有者, 可写入 else { return }
        let key = 本地资料库条目.视觉小说ID(vnID)
        删除(id: key)
        var store = 同步状态存储.读取(owner: owner)
        store.待推送VNDB.insert(key)
        store.本地已删除.insert(key)
        store.保存(owner: owner)
    }
}
