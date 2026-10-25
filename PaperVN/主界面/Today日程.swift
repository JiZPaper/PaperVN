import Combine
import SwiftUI

// MARK: - 播出表数据

/// AniList 放送表里一部动画的一次放送。
struct Today放送: Identifiable, Hashable, Codable {
    /// AniList 放送表条目的 ID。
    let id: Int
    var 作品: 作品搜索结果
    /// 作品映射里的编号（例如“mal-anime:5114”），用来和资料库对上。
    let 作品键: String
    let 话数: Int
    let 总话数: Int?
    let 放送时间: Date
    let 人气: Int
    let 出品国家: String?

    /// 播出表默认只列出有一定人气的作品（AniList 上有很多儿童向的短篇和网络动画）；资料库里的作品不受限制。
    var 默认显示: Bool {
        出品国家 == "JP" ? 人气 >= 200 : 人气 >= 2_000
    }
}

/// 这一周（周一到周日，本地时区）各部动画的放送。数据来自 AniList 的放送表，
/// 中文名来自 Bangumi 的每日放送（按作品映射对上 Bangumi 条目，对不上时按原名对）。
/// 不含成人作品与剧场版。
@MainActor
final class Today放送表模型: ObservableObject {
    static let shared = Today放送表模型()

    @Published private(set) var 放送: [Today放送] = []
    @Published private(set) var 正在载入 = false
    @Published private(set) var 已载入 = false
    @Published private(set) var 错误信息: String?

    private var 本周开始: Date?
    private var 载入时间: Date?
    private var 载入任务: Task<Void, Never>?

    private static let 有效期: TimeInterval = 3 * 60 * 60
    private static let 最多页数 = 10
    private static let 格式: Set<String> = ["TV", "TV_SHORT", "ONA"]

    static var 日历: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        return calendar
    }

    static func 本周(_ now: Date = Date()) -> DateInterval {
        let calendar = 日历
        return calendar.dateInterval(of: .weekOfYear, for: now)
            ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
    }

    /// 今天是本周的第几天（周一为 0）。
    static func 今天序号(_ now: Date = Date()) -> Int {
        let start = 本周(now).start
        return min(6, max(0, 日历.dateComponents([.day], from: start, to: 日历.startOfDay(for: now)).day ?? 0))
    }

    static func 日期(_ index: Int, 周开始 start: Date) -> Date {
        日历.date(byAdding: .day, value: index, to: start) ?? start
    }

    func 放送(第 index: Int) -> [Today放送] {
        guard let start = 本周开始 else { return [] }
        let day = Self.日期(index, 周开始: start)
        let next = Self.日期(index + 1, 周开始: start)
        return 放送
            .filter { $0.放送时间 >= day && $0.放送时间 < next }
            .sorted { $0.放送时间 < $1.放送时间 }
    }

    func 载入(强制刷新: Bool = false) async {
        let week = Self.本周()
        if !强制刷新, 本周开始 == week.start, let 载入时间,
           Date().timeIntervalSince(载入时间) < Self.有效期 {
            return
        }
        if let 载入任务 {
            await 载入任务.value
            return
        }
        let task = Task { await 执行载入(week) }
        载入任务 = task
        await task.value
        载入任务 = nil
    }

    private func 执行载入(_ week: DateInterval) async {
        if 本周开始 != week.start {
            // 换了一周：先清掉上一周的，再用这一周的缓存
            放送 = []
            if let cached = Self.读取缓存(), cached.周开始 == week.start {
                放送 = cached.放送
                本周开始 = week.start
                已载入 = true
                if Date().timeIntervalSince(cached.保存时间) < Self.有效期 {
                    载入时间 = cached.保存时间
                    return
                }
            }
        }

        正在载入 = true
        defer { 正在载入 = false }
        do {
            await 作品映射.预载()
            async let chinese = Self.Bangumi中文名()
            let items = try await Self.AniList放送(week)
            let names = await chinese
            let result = items.map { Self.补上中文名($0, names) }
            放送 = result
            本周开始 = week.start
            载入时间 = Date()
            错误信息 = nil
            Self.写入缓存(缓存(周开始: week.start, 保存时间: Date(), 放送: result))
        } catch {
            if 放送.isEmpty {
                错误信息 = error.localizedDescription
            }
        }
        已载入 = true
    }

    // MARK: AniList

    /// 放送表里的作品：作品本身的字段之外再带上人气和总话数。
    private struct 媒体: Decodable {
        let 作品: AniList作品
        let popularity: Int?
        let episodes: Int?

        private enum CodingKeys: String, CodingKey {
            case popularity, episodes
        }

        init(from decoder: Decoder) throws {
            作品 = try AniList作品(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            popularity = try container.decodeIfPresent(Int.self, forKey: .popularity)
            episodes = try container.decodeIfPresent(Int.self, forKey: .episodes)
        }
    }

    private static func AniList放送(_ week: DateInterval) async throws -> [Today放送] {
        struct 响应: Decodable {
            struct 页信息: Decodable { let hasNextPage: Bool? }
            struct 条目: Decodable { let id: Int; let episode: Int; let airingAt: Int; let media: 媒体? }
            struct 页: Decodable { let pageInfo: 页信息?; let airingSchedules: [条目] }
            struct 数据: Decodable { let Page: 页 }
            let data: 数据
        }
        var result: [Today放送] = []
        for page in 1...最多页数 {
            let data = try await 平台账户工具.graphQL(
                endpoint: AniListOAuth配置.endpoint,
                platform: "AniList",
                accessToken: nil,
                query: """
                query ($page: Int, $from: Int, $to: Int) {
                  Page(page: $page, perPage: 50) {
                    pageInfo { hasNextPage }
                    airingSchedules(airingAt_greater: $from, airingAt_lesser: $to, sort: [TIME]) {
                      id episode airingAt
                      media { \(AniList作品.字段) popularity episodes }
                    }
                  }
                }
                """,
                variables: [
                    "page": page,
                    "from": Int(week.start.timeIntervalSince1970) - 1,
                    "to": Int(week.end.timeIntervalSince1970),
                ]
            )
            let decoded = try JSONDecoder().decode(响应.self, from: data)
            result += decoded.data.Page.airingSchedules.compactMap { entry in
                guard let media = entry.media,
                      media.作品.isAdult != true,
                      let format = media.作品.format, 格式.contains(format) else { return nil }
                let work = media.作品
                let id = 作品搜索结果.编号(类型: .anime, malID: work.idMal ?? 0, aniListID: work.id)
                guard let item = work.结果(请求的编号: [id]).first else { return nil }
                let key = work.idMal.flatMap { 作品映射.查找(.myAnimeList, 平台ID: String($0), 类型: .anime)?.键 }
                    ?? 作品映射.查找(.aniList, 平台ID: String(work.id), 类型: .anime)?.键
                    ?? item.作品键
                return Today放送(
                    id: entry.id,
                    作品: item,
                    作品键: key,
                    话数: entry.episode,
                    总话数: media.episodes,
                    放送时间: Date(timeIntervalSince1970: TimeInterval(entry.airingAt)),
                    人气: media.popularity ?? 0,
                    出品国家: work.countryOfOrigin
                )
            }
            guard decoded.data.Page.pageInfo?.hasNextPage == true else { break }
        }
        return result
    }

    // MARK: Bangumi 中文名

    private struct 中文名表 {
        var 按条目: [Int: String] = [:]
        var 按原名: [String: String] = [:]
    }

    private static func Bangumi中文名() async -> 中文名表 {
        struct 星期: Decodable {
            struct 条目: Decodable { let id: Int; let name: String?; let name_cn: String? }
            let items: [条目]
        }
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/calendar")!, timeoutInterval: 10)
        request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let days = try? JSONDecoder().decode([星期].self, from: data) else {
            return 中文名表()
        }
        var table = 中文名表()
        for item in days.flatMap(\.items) {
            guard let chinese = item.name_cn?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !chinese.isEmpty, chinese != item.name else { continue }
            table.按条目[item.id] = chinese
            if let name = item.name {
                table.按原名[规范原名(name)] = chinese
            }
        }
        return table
    }

    private static func 规范原名(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.lowercased()
    }

    private static func 补上中文名(_ item: Today放送, _ table: 中文名表) -> Today放送 {
        let bangumiID = 作品映射.平台ID(item.作品键, 平台: .bangumi, 类型: .anime).flatMap(Int.init)
        let native = item.作品.多语言标题.first(where: \.main)?.title
        guard let chinese = bangumiID.flatMap({ table.按条目[$0] })
                ?? native.flatMap({ table.按原名[规范原名($0)] }) else {
            return item
        }
        var item = item
        // Bangumi 的中文名由用户编辑，按非官方标题处理
        item.作品.多语言标题 = 作品多语言标题.合并([
            item.作品.多语言标题,
            作品多语言标题.生成(原名: nil, 罗马字: nil, 中文: chinese),
        ])
        return item
    }

    // MARK: 缓存

    private struct 缓存: Codable {
        let 周开始: Date
        let 保存时间: Date
        let 放送: [Today放送]
    }

    private static var 缓存地址: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Today放送表.json")
    }

    private static func 读取缓存() -> 缓存? {
        guard let data = try? Data(contentsOf: 缓存地址) else { return nil }
        return try? JSONDecoder().decode(缓存.self, from: data)
    }

    private static func 写入缓存(_ value: 缓存) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: 缓存地址, options: .atomic)
    }
}

/// 资料库里的动画，按作品编号、MAL ID 或 AniList ID 查找。
struct Today资料库动画索引 {
    private var 条目: [String: 本地资料库条目] = [:]

    init(_ entries: [本地资料库条目]) {
        for entry in entries where entry.类型 == .anime {
            条目[entry.id] = entry
            if let malID = entry.malID {
                条目["mal-anime:\(malID)"] = entry
            }
            if let aniListID = entry.平台ID[.aniList] {
                条目["aniList-anime:\(aniListID)"] = entry
            }
        }
    }

    func 查找(_ item: Today放送) -> 本地资料库条目? {
        条目[item.作品键]
            ?? (item.作品.malID > 0 ? 条目["mal-anime:\(item.作品.malID)"] : nil)
            ?? item.作品.aniListID.flatMap { 条目["aniList-anime:\($0)"] }
    }
}

enum Today日程格式 {
    static func 时间(_ date: Date) -> String {
        中西文间距.去除空格(date.formatted(date: .omitted, time: .shortened))
    }

    static func 话数(_ episode: Int) -> String {
        String(localized: "第\(episode)话")
    }

    static let 卡片圆角: CGFloat = 28
}

extension View {
    func Today日程卡片() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .平台卡片容器(
                background: Color.平台次级分组背景,
                stroke: .clear,
                cornerRadius: Today日程格式.卡片圆角,
                lightModeShadowOpacity: 0,
                shadowRadius: 10,
                shadowY: 0
            )
    }

    fileprivate func Today日程占位() -> some View {
        frame(maxWidth: .infinity, minHeight: 180)
            .background(
                Color.平台次级分组背景,
                in: RoundedRectangle(cornerRadius: Today日程格式.卡片圆角, style: .continuous)
            )
    }

    /// 横向书架画到页面边缘外，左右各留出与页面相同的 20pt 边距。
    fileprivate func Today日程书架() -> some View {
        padding(.horizontal, -20)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .scrollClipDisabled()
    }
}

/// 播出表、角色生日与为你推荐共用的海报尺寸。
enum Today海报 {
    static let 宽度: CGFloat = 124
    static let 高度: CGFloat = 宽度 * 1.42
    static let 圆角: CGFloat = 16

    /// 播出表与为你推荐的书架：一屏露出两张完整海报和第三张的开头。
    static func 书架宽度(容器: CGFloat) -> CGFloat {
        min((容器 - 14 * 2 - 28) / 2, 200)
    }
}

extension View {
    /// 按书架宽度排出海报，高度跟随宽度。
    func Today书架海报尺寸() -> some View {
        Color.clear
            .aspectRatio(Today海报.宽度 / Today海报.高度, contentMode: .fit)
            .containerRelativeFrame(.horizontal) { length, _ in
                Today海报.书架宽度(容器: length)
            }
            .overlay { self }
    }
}

extension View {
    /// 海报下半部分渐暗，文字写在渐暗的部分里（白字、深色外观的次要文字）。
    func Today海报信息<Info: View>(@ViewBuilder _ info: () -> Info) -> some View {
        overlay {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0), location: 0.4),
                    .init(color: .black.opacity(0.35), location: 0.65),
                    .init(color: .black.opacity(0.82), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 2) {
                info()
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .padding(10)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - 今日更新

/// 资料库里今天有新一话的动画（观看中、计划观看），以及今天发售的视觉小说。
enum Today今日更新条目: Identifiable {
    case 放送(Today放送, 本地资料库条目)
    case 发售(本地资料库条目)

    var id: String {
        switch self {
        case let .放送(item, _): "airing-\(item.id)"
        case let .发售(entry): "release-\(entry.id)"
        }
    }

    @MainActor
    static func 今天(
        资料库 entries: [本地资料库条目],
        放送表 schedule: Today放送表模型,
        动画: Bool,
        视觉小说: Bool
    ) -> [Today今日更新条目] {
        var result: [Today今日更新条目] = []
        if 视觉小说 {
            let today = Today放送表模型.日历.startOfDay(for: Date()).formatted(.iso8601.year().month().day())
            result += entries
                .filter { entry in
                    entry.类型 == .visualNovel
                        && entry.发行日期 == today
                        && entry.状态 != .completed && entry.状态 != .dropped
                }
                .map(Today今日更新条目.发售)
        }
        if 动画 {
            let index = Today资料库动画索引(entries)
            result += schedule.放送(第: Today放送表模型.今天序号()).compactMap { item in
                guard let entry = index.查找(item),
                      entry.状态 == .inProgress || entry.状态 == .planning else { return nil }
                return .放送(item, entry)
            }
        }
        return result
    }
}

/// 今日更新的卡片。没有的时候整块不显示。
struct Today今日更新栏目: View {
    let usesWideLayout: Bool
    let zoom: Namespace.ID

    @ObservedObject private var schedule = Today放送表模型.shared
    @ObservedObject private var library = 本地资料库.shared
    @ObservedObject private var senkou = PaperVNSenkou中心.shared

    var body: some View {
        let items = Today今日更新条目.今天(
            资料库: library.条目,
            放送表: schedule,
            动画: !senkou.隐藏延迟免费功能,
            视觉小说: true
        )
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("今日更新")
                    .font(.title2.weight(.bold))
                Today今日更新列表(items: items, usesWideLayout: usesWideLayout, zoom: zoom)
            }
            .accessibilityIdentifier("today.updates")
        }
    }
}

/// 今日更新的行，放在一张卡片里。Today页面和简报的“不要忘了…”共用。
struct Today今日更新列表: View {
    let items: [Today今日更新条目]
    let usesWideLayout: Bool

    @EnvironmentObject private var auth: 用户登录
    /// 页面的转场命名空间：每个卡片自己建的命名空间系统找不到来源，会从屏幕中间放大。
    let zoom: Namespace.ID

    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod") private var contentRestrictionMethod: 内容限制方式 = .blurred

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                    .padding(usesWideLayout ? 12 : 14)

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 90)
                }
            }
        }
        .Today日程卡片()
    }

    @ViewBuilder
    private func row(_ item: Today今日更新条目) -> some View {
        switch item {
        case let .放送(airing, entry):
            Senkou导航链接(zoomSourceID: "today-\(item.id)", in: zoom) {
                作品详情(目标: airing.作品.详情目标)
                    .navigationTransition(.zoom(sourceID: "today-\(item.id)", in: zoom))
            } label: {
                Today日程封面行(
                    封面: URL(string: airing.作品.封面 ?? entry.封面地址 ?? ""),
                    标题: 标题工具.获取主标题(
                        titles: airing.作品.多语言标题,
                        defaultTitle: airing.作品.标题,
                        偏好: preferredTitleLang,
                        回退: fallbackTitleLang,
                        允许非官方: allowUnofficialTitles
                    ),
                    isRestricted: false,
                    restrictionMethod: contentRestrictionMethod
                ) {
                    探索元数据(systemImage: 作品类型.anime.symbolName, text: Today日程格式.话数(airing.话数))
                    探索元数据(systemImage: "clock", text: Today日程格式.时间(airing.放送时间))
                } 附注: {
                    if let status = entry.状态 {
                        Text(status.localizedTitle(for: .anime))
                    }
                }
                .matchedTransitionSource(id: "today-\(item.id)", in: zoom)
            }
            .buttonStyle(.plain)
        case let .发售(entry):
            let vn = entry.vndb?.vn
            NavigationLink {
                视觉小说详情(
                    vnID: entry.vndb?.id ?? entry.平台ID[.vndb] ?? "",
                    auth: auth,
                    initialTitle: entry.标题,
                    initialTitles: vn?.titles ?? entry.多语言标题,
                    initialImageURL: vn?.image?.url ?? entry.封面地址,
                    initialImageSexual: vn?.image?.sexual,
                    initialImageViolence: vn?.image?.violence,
                    initialImageDimensions: vn?.image?.dims
                )
                .navigationTransition(.zoom(sourceID: "today-\(item.id)", in: zoom))
            } label: {
                Today日程封面行(
                    封面: URL(string: vn?.image?.url ?? entry.封面地址 ?? ""),
                    标题: 标题工具.获取主标题(
                        titles: vn?.titles ?? entry.多语言标题,
                        defaultTitle: entry.标题,
                        偏好: preferredTitleLang,
                        回退: fallbackTitleLang,
                        允许非官方: allowUnofficialTitles
                    ),
                    isRestricted: 内容安全限制判定.图片需要限制(
                        sexual: vn?.image?.sexual,
                        violence: vn?.image?.violence,
                        enabled: contentFilterEnabled,
                        sexualThreshold: sexualThreshold,
                        violenceThreshold: violenceThreshold,
                        mode: filterMode
                    ),
                    restrictionMethod: contentRestrictionMethod
                ) {
                    探索元数据(systemImage: 作品类型.visualNovel.symbolName, text: 作品类型.visualNovel.localizedTitle)
                    探索元数据(systemImage: "calendar", text: String(localized: "今天发售"))
                } 附注: {
                    if let status = entry.状态 {
                        Text(status.localizedTitle(for: .visualNovel))
                    }
                }
                .matchedTransitionSource(id: "today-\(item.id)", in: zoom)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 今日更新的一行：封面、标题、元数据，下面是资料库状态。排版与“为你推荐”的行一致。
private struct Today日程封面行<Metadata: View, Note: View>: View {
    let 封面: URL?
    let 标题: 标题工具.标题结果
    let isRestricted: Bool
    let restrictionMethod: 内容限制方式
    @ViewBuilder let 元数据: Metadata
    @ViewBuilder let 附注: Note

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let cornerRadius = 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
        HStack(alignment: .center, spacing: 12) {
            Today异步图片(url: 封面, maximumPixelSize: 1_200)
                .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .应用不安全内容限制(isRestricted, method: restrictionMethod, blurRadius: 16)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                多语言列表文本(
                    标题,
                    层级: .主标题,
                    日文字体名称: "HiraginoSans-W5",
                    系统字体粗细: 标题.languageCode == 标题语言.chinese.langCode ? .medium : nil,
                    语言来源已知: 标题.languageCode != nil
                )
                .lineLimit(2)

                HStack(spacing: 8) {
                    元数据
                }

                附注
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 20)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 播出表

/// 这一周的新番播出表：上面是星期，下面是当天的动画海报，按放送时间横向排开。没有标题。
/// 打开时停在今天下一部要播出的作品；资料库里的作品标出状态。
struct Today播出表栏目: View {
    let usesWideLayout: Bool
    let zoom: Namespace.ID

    @ObservedObject private var schedule = Today放送表模型.shared
    @ObservedObject private var library = 本地资料库.shared
    @State private var selectedDay: Int?
    @State private var scrolledID: Int?

    private var day: Int { selectedDay ?? Today放送表模型.今天序号() }

    var body: some View {
        let index = Today资料库动画索引(library.条目)
        let items = schedule.放送(第: day).filter { $0.默认显示 || index.查找($0) != nil }
        let isToday = day == Today放送表模型.今天序号()
        let now = Date()
        let nextID = isToday ? items.first(where: { $0.放送时间 > now })?.id : nil

        // 不显示标题：星期条本身就说明了这是播出表
        VStack(alignment: .leading, spacing: 14) {
            if !schedule.放送.isEmpty {
                Today星期条(selection: Binding(
                    get: { day },
                    set: { newValue in
                        withAnimation(.snappy(duration: 0.25)) { selectedDay = newValue }
                    }
                ))

                if items.isEmpty {
                    Text("这一天没有放送")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(items) { item in
                                Today放送海报(
                                    item: item,
                                    entry: index.查找(item),
                                    isNext: item.id == nextID
                                ,
                                    zoom: zoom)
                                .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollIndicators(.hidden)
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $scrolledID, anchor: .leading)
                    .Today日程书架()
                    // 换一天时重新建立书架，回到最前面；今天停在下一部要播出的作品
                    .onAppear { scrolledID = nextID }
                    .id(day)
                }
            } else if let message = schedule.错误信息 {
                探索加载失败提示(message: message) {
                    Task { await schedule.载入(强制刷新: true) }
                }
                .padding(18)
                .Today日程占位()
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在载入放送表…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .Today日程占位()
            }
        }
        .accessibilityIdentifier("today.airingSchedule")
    }
}

/// 一周七天的选择条，外观像分段控件。今天用强调色标出。
private struct Today星期条: View {
    @Binding var selection: Int

    @Environment(\.locale) private var locale
    @Namespace private var namespace

    var body: some View {
        let start = Today放送表模型.本周().start
        let today = Today放送表模型.今天序号()

        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                let date = Today放送表模型.日期(index, 周开始: start)
                let isSelected = index == selection
                Button {
                    selection = index
                } label: {
                    VStack(spacing: 1) {
                        Text(date.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                            .font(.caption2.weight(.semibold))
                        Text(verbatim: String(Today放送表模型.日历.component(.day, from: date)))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(
                        isSelected ? AnyShapeStyle(.white)
                            : index == today ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(.tint)
                                .matchedGeometryEffect(id: "selection", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(date.formatted(.dateTime.month().day().weekday(.wide).locale(locale)))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.平台次级分组背景, in: Capsule())
    }
}

/// 播出表里的一部动画：海报左上角是放送时间（下一部要播出的用强调色），下面是标题与第几话。
private struct Today放送海报: View {
    let item: Today放送
    let entry: 本地资料库条目?
    let isNext: Bool

    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    /// 页面的转场命名空间：每个卡片自己建的命名空间系统找不到来源，会从屏幕中间放大。
    let zoom: Namespace.ID

    private var title: 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: item.作品.多语言标题,
            defaultTitle: item.作品.标题,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    var body: some View {
        let aired = item.放送时间 <= Date()

        Senkou导航链接(zoomSourceID: "today-\(item.id)", in: zoom) {
            作品详情(目标: item.作品.详情目标)
                .navigationTransition(.zoom(sourceID: "today-\(item.id)", in: zoom))
        } label: {
            Today异步图片(url: URL(string: item.作品.封面 ?? ""), maximumPixelSize: 800)
                .Today书架海报尺寸()
                .Today海报信息 {
                    多语言列表文本(
                        title,
                        层级: .下属标题,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: title.languageCode == 标题语言.chinese.langCode ? .semibold : .bold,
                        语言来源已知: title.languageCode != nil
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Text(Today日程格式.话数(item.话数))
                            .opacity(0.8)
                        if let status = entry?.状态 {
                            Text(status.localizedTitle(for: .anime))
                                .fontWeight(.semibold)
                        }
                    }
                    .font(.caption2)
                    .lineLimit(1)
                }
                .overlay(alignment: .topLeading) {
                    Text(verbatim: Today日程格式.时间(item.放送时间))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isNext ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if isNext {
                                Capsule().fill(.tint)
                            } else {
                                Capsule().fill(.regularMaterial)
                            }
                        }
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: Today海报.圆角, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Today海报.圆角, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .opacity(aired ? 0.72 : 1)
                // 从海报放大进入详情页
                .matchedTransitionSource(id: "today-\(item.id)", in: zoom)
                .contentShape(RoundedRectangle(cornerRadius: Today海报.圆角, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 今日生日

/// 一个过生日的角色。资料库里的角色来自 `Today资料库生日模型`；`Today生日模型` 是 AniList 与 VNDB 上较受欢迎的，只用于 Debug 预览。
struct Today生日角色: Identifiable, Hashable {
    enum 来源: Hashable {
        case 视觉小说(探索角色)
        case 作品(作品搜索结果)
    }

    let id: String
    let 名字: String
    let 原名: String?
    let 图片: String?
    let 图片色情: Double?
    let 图片暴力: Double?
    let 来源: 来源
    /// 生日是明天（否则是今天）。
    var 是明天 = false
}

@MainActor
final class Today生日模型: ObservableObject {
    static let shared = Today生日模型()

    @Published private(set) var 角色: [Today生日角色] = []
    @Published private(set) var 已载入 = false

    private var 载入键: String?
    private static let 每个来源最多 = 10

    func 载入(类型 types: Set<作品类型>) async {
        let now = Date()
        let calendar = Today放送表模型.日历
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        let key = "\(month)-\(day)|" + types.map(\.rawValue).sorted().joined(separator: ",")
        guard key != 载入键 else { return }
        载入键 = key

        async let visualNovel = types.contains(.visualNovel)
            ? Self.视觉小说角色(月: month, 日: day) : []
        async let works = Self.AniList角色(types.subtracting([.visualNovel]))
        let (a, b) = await (works, visualNovel)
        // 两个来源交替排列
        var merged: [Today生日角色] = []
        for index in 0..<max(a.count, b.count) {
            if index < a.count { merged.append(a[index]) }
            if index < b.count { merged.append(b[index]) }
        }
        guard 载入键 == key else { return }
        角色 = merged
        // 一个也没有时（可能是请求失败）下次再试
        if merged.isEmpty { 载入键 = nil }
        已载入 = true
    }

    private static func 视觉小说角色(月 month: Int, 日 day: Int) async -> [Today生日角色] {
        let characters = (try? await VNDB探索服务.shared.今日生日角色(月: month, 日: day)) ?? []
        return characters.prefix(每个来源最多).map { character in
            Today生日角色(
                id: "vndb-\(character.id)",
                名字: character.name,
                原名: character.original,
                图片: character.image?.url,
                图片色情: character.image?.sexual,
                图片暴力: character.image?.violence,
                来源: .视觉小说(character)
            )
        }
    }

    private static func AniList角色(_ types: Set<作品类型>) async -> [Today生日角色] {
        guard !types.isEmpty else { return [] }
        struct 响应: Decodable {
            struct 名字: Decodable { let full: String?; let native: String? }
            struct 图片: Decodable { let large: String?; let medium: String? }
            struct 作品列表: Decodable { let nodes: [AniList作品] }
            struct 角色: Decodable { let id: Int; let name: 名字?; let image: 图片?; let media: 作品列表? }
            struct 页: Decodable { let characters: [角色] }
            struct 数据: Decodable { let Page: 页 }
            let data: 数据
        }
        guard let data = try? await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: nil,
            query: """
            query {
              Page(perPage: 30) {
                characters(isBirthday: true, sort: [FAVOURITES_DESC]) {
                  id name { full native } image { large medium }
                  media(perPage: 1, sort: [POPULARITY_DESC]) { nodes { \(AniList作品.字段) } }
                }
              }
            }
            """
        ), let decoded = try? JSONDecoder().decode(响应.self, from: data) else {
            return []
        }
        let characters = decoded.data.Page.characters.compactMap { character -> Today生日角色? in
            guard let media = character.media?.nodes.first, media.isAdult != true,
                  let name = character.name?.full ?? character.name?.native else { return nil }
            let kind: 作品类型 = media.type == "ANIME" ? .anime : (media.format == "NOVEL" ? .lightNovel : .manga)
            guard types.contains(kind) else { return nil }
            let id = 作品搜索结果.编号(类型: kind, malID: media.idMal ?? 0, aniListID: media.id)
            guard let work = media.结果(请求的编号: [id]).first else { return nil }
            return Today生日角色(
                id: "anilist-\(character.id)",
                名字: name,
                原名: character.name?.native,
                图片: character.image?.large ?? character.image?.medium,
                图片色情: nil,
                图片暴力: nil,
                来源: .作品(work)
            )
        }
        return Array(characters.prefix(每个来源最多))
    }
}

/// 一个过生日的角色：竖版卡片铺满角色图片，下方渐暗，写着名字与所在作品。
/// 点按打开角色（VNDB）或作品（AniList）详情。宽度由外面决定。
struct Today生日角色单元: View {
    let character: Today生日角色

    @EnvironmentObject private var auth: 用户登录

    @AppStorage("staffNameLang") private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod") private var contentRestrictionMethod: 内容限制方式 = .blurred
    /// 页面的转场命名空间：每个卡片自己建的命名空间系统找不到来源，会从屏幕中间放大。
    let zoom: Namespace.ID

    private static let 圆角: CGFloat = Today海报.圆角

    var body: some View {
        Senkou导航链接(需要订阅: 是动画漫画, zoomSourceID: character.id, in: zoom) {
            destination
                .navigationTransition(.zoom(sourceID: character.id, in: zoom))
        } label: {
            card
                .matchedTransitionSource(id: character.id, in: zoom)
        }
        .buttonStyle(.plain)
    }

    private var card: some View {
        let name = 人物名称工具.显示名称(name: character.名字, original: character.原名, 偏好: staffNameLang)
        let isRestricted = 内容安全限制判定.图片需要限制(
            sexual: character.图片色情,
            violence: character.图片暴力,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
        // 宽度跟随所在的列，高度按海报比例
        return Color.clear
            .aspectRatio(Today海报.宽度 / Today海报.高度, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                Today异步图片(url: URL(string: character.图片 ?? ""), maximumPixelSize: 600)
                    .应用不安全内容限制(isRestricted, method: contentRestrictionMethod, blurRadius: 16)
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.4),
                        .init(color: .black.opacity(0.35), location: 0.65),
                        .init(color: .black.opacity(0.82), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    多语言列表文本(
                        文本: name,
                        isJapanese: staffNameLang == .original,
                        层级: .下属标题,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言来源已知: false,
                        // 罗马字名字要能在空格处换行
                        空格视为日语: staffNameLang == .original
                    )
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                    if let work = workTitle {
                        Text(verbatim: work)
                            .font(.caption2)
                            .opacity(0.8)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.white)
                .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.圆角, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Self.圆角, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Self.圆角, style: .continuous))
            .accessibilityElement(children: .combine)
    }

    private var workTitle: String? {
        switch character.来源 {
        case let .视觉小说(item):
            guard let vn = item.visualNovels?.first(where: { ($0.spoiler ?? 0) == 0 }) ?? item.visualNovels?.first else {
                return nil
            }
            let titles = vn.titles?.map {
                用户多语言标题(lang: $0.lang, title: $0.title, latin: $0.latin, official: $0.official ?? false, main: $0.main ?? false)
            }
            return 标题工具.获取主标题(
                titles: titles,
                defaultTitle: vn.title,
                偏好: preferredTitleLang,
                回退: fallbackTitleLang,
                允许非官方: allowUnofficialTitles
            ).text
        case let .作品(work):
            return 标题工具.获取主标题(
                titles: work.多语言标题,
                defaultTitle: work.标题,
                偏好: preferredTitleLang,
                回退: fallbackTitleLang,
                允许非官方: allowUnofficialTitles
            ).text
        }
    }

    private var 是动画漫画: Bool {
        if case .作品 = character.来源 { true } else { false }
    }

    @ViewBuilder
    private var destination: some View {
        switch character.来源 {
        case let .视觉小说(item):
            角色详情(
                characterID: item.id,
                auth: auth,
                initialName: item.name,
                initialOriginal: item.original,
                initialAliases: item.aliases
            )
        case let .作品(work):
            作品详情(目标: work.详情目标)
        }
    }
}
