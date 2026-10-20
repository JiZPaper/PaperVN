import Combine
import Foundation

/// 资料库里的作品类型。
enum 作品类型: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
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
        case .anime: "play.tv"
        case .manga: "book.pages"
        case .lightNovel: "text.book.closed"
        case .visualNovel: "gamecontroller"
        }
    }
}

/// 资料库状态。文案随作品类型变化：视觉小说是“游玩”，动画是“看”，漫画与轻小说是“读”。
enum 资料库状态: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
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
        case .bangumi: "Bangumi"
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
    /// 用于在 Annict 等日文平台上查找作品。
    var 日文标题: String?
    /// 各语言的标题，显示时按标题语言设置选择（与视觉小说共用同一套规则）。
    var 多语言标题: [用户多语言标题]?

    /// 视觉小说的完整VNDB记录，资料库行、编辑页与详情页仍然依赖它。
    var vndb: 用户列表项目?

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

    /// 登录、退出或切换账户时调用。
    func 切换所有者(_ owner: String?) {
        let owner = owner?.isEmpty == false ? owner : nil
        guard owner != 所有者 else { return }
        所有者 = owner
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
                guard let decoded = try? JSONDecoder().decode([本地资料库条目].self, from: data) else {
                    let backup = url.deletingPathExtension()
                        .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
                    try? FileManager.default.copyItem(at: url, to: backup)
                    return nil
                }
                return decoded
            }.value
            guard let self, !Task.isCancelled, self.所有者 == owner else { return }
            self.条目 = values ?? []
            self.载入失败 = values == nil
            self.已载入 = true
        }
    }

    /// 用VNDB的完整列表更新视觉小说。VNDB暂时是视觉小说的权威来源，VNDB中没有的视觉小说会被移除。
    func 导入VNDB(_ items: [用户列表项目], owner: String) {
        // 资料库还没读完时导入，会只留下视觉小说，把动画、漫画与轻小说覆盖掉
        guard owner == 所有者, 可写入 else { return }
        let imported = items.map(本地资料库条目.init(vndb:))
        条目 = 条目.filter { $0.类型 != .visualNovel } + imported
        保存()
    }

    /// 动画、漫画与轻小说（视觉小说以外的作品），按 PaperVN ID 索引。
    var 动画漫画条目: [String: 本地资料库条目] {
        Dictionary(条目.filter { $0.类型 != .visualNovel }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// PaperVN Sync 合并完成后，整体替换动画、漫画与轻小说。
    func 替换动画漫画(_ entries: [本地资料库条目], owner: String) {
        guard owner == 所有者, 可写入 else { return }
        条目 = 条目.filter { $0.类型 == .visualNovel } + entries
        保存()
    }

    /// 新加入资料库的作品（例如在详情页加入计划）。
    func 添加(_ entry: 本地资料库条目) {
        guard 所有者 != nil else { return }
        var entry = entry
        entry.加入时间 = entry.加入时间 ?? .now
        entry.修改时间 = .now
        条目.removeAll { $0.id == entry.id }
        条目.append(entry)
        保存()
    }

    /// 本地先改，改完由调用方推送到平台。
    func 更新(_ entry: 本地资料库条目) {
        guard let index = 条目.firstIndex(where: { $0.id == entry.id }) else { return }
        var entry = entry
        entry.修改时间 = .now
        条目[index] = entry
        保存()
    }

    func 删除(id: String) {
        条目.removeAll { $0.id == id }
        保存()
    }

    private func 保存() {
        guard 可写入, let owner = 所有者 else { return }
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

    nonisolated private static func 文件地址(owner: String) -> URL {
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

    /// “2019-05-31”“2019-05”“2019”以及“TBA”之类的发行日期转成可比较的数值。
    private static func 发行日期排序值(_ value: String) -> Double? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard let year = parts.first else { return nil }
        let month = parts.count > 1 ? parts[1] : 12
        let day = parts.count > 2 ? parts[2] : 31
        return Double(year * 10_000 + month * 100 + day)
    }
}
