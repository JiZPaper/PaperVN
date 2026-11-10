import Combine
import SwiftUI

// MARK: - 问候语

/// 简报第一页的问候语：按当前时刻从几种说法里随机选一种，同一天同一时段内保持不变。
enum Today问候 {
    enum 说法: CaseIterable {
        case 早上好, 中午好, 晚上好, 安安, 新的一天, 还没睡, 夜猫子, 夕阳西下
    }

    static func 候选(小时 hour: Int) -> [说法] {
        switch hour {
        case 0..<5: [.还没睡, .夜猫子, .安安]
        case 5..<8: [.新的一天, .早上好, .安安]
        case 8..<11: [.早上好, .新的一天, .安安]
        case 11..<14: [.中午好, .安安]
        case 14..<17: [.安安]
        case 17..<19: [.夕阳西下, .安安]
        case 19..<23: [.晚上好, .安安]
        default: [.夜猫子, .晚上好, .还没睡]
        }
    }

    static func 选择(_ now: Date = Date()) -> 说法 {
        let calendar = Today放送表模型.日历
        let hour = calendar.component(.hour, from: now)
        let options = 候选(小时: hour)
        // 用日期和时段做种子：同一时段反复打开不会变来变去
        let day = calendar.ordinality(of: .day, in: .era, for: now) ?? 0
        let seed = day &* 31 &+ options.count &* 7 &+ hour / 3
        return options[abs(seed) % options.count]
    }

    static func 文本(_ 说法: 说法, 名字 name: String?, 时间 now: Date = Date()) -> String {
        // 没有登录任何账户时只用平常的问候语（“早上好。”），俏皮的说法要带着名字才自然
        guard let name else {
            switch Today放送表模型.日历.component(.hour, from: now) {
            case 5..<11: return String(localized: "早上好。")
            case 11..<14: return String(localized: "中午好。")
            case 14..<18: return String(localized: "下午好。")
            default: return String(localized: "晚上好。")
            }
        }
        return switch 说法 {
        case .早上好: String(localized: "早上好，\(name)。")
        case .中午好: String(localized: "中午好，\(name)。")
        case .晚上好: String(localized: "晚上好，\(name)。")
        case .安安: String(localized: "安安，\(name)。")
        case .新的一天: String(localized: "新的一天，\(name)。")
        case .还没睡: String(localized: "是谁还没睡呢，\(name)？")
        case .夜猫子: String(localized: "夜猫子\(name)，晚上好。")
        case .夕阳西下: String(localized: "夕阳西下，\(name)。")
        }
    }
}

/// 问候语里的名字：登录了哪个账户就用哪个账户的名字；登录了好几个时在设置里选择。
enum Today问候名称 {
    static let 来源键 = "todayGreetingNameSource"

    struct 账户: Identifiable, Hashable {
        /// 平台（资料库平台的 rawValue）。
        let id: String
        let 平台: String
        let 名字: String
    }

    @MainActor
    static func 账户列表(auth: 用户登录) -> [账户] {
        var result: [账户] = []
        let vndbName = auth.username.trimmingCharacters(in: .whitespacesAndNewlines)
        if auth.isLoggedIn, !vndbName.isEmpty {
            result.append(账户(id: 资料库平台.vndb.rawValue, 平台: 资料库平台.vndb.localizedTitle, 名字: vndbName))
        }
        for (platform, name) in PaperVNSync中心.shared.账户名称 {
            result.append(账户(id: platform.rawValue, 平台: platform.localizedTitle, 名字: name))
        }
        return result
    }

    /// 选中的账户不再登录时用第一个已登录的账户。
    @MainActor
    static func 名字(auth: 用户登录, 选择 source: String) -> String? {
        let accounts = 账户列表(auth: auth)
        return (accounts.first { $0.id == source } ?? accounts.first)?.名字
    }
}

// MARK: - 资料库里的角色生日

extension Today生日角色 {
    static func vndb(_ character: 探索角色) -> Today生日角色 {
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

/// 资料库里的角色在今天和明天的生日：玩过或看过（游玩中、已玩、搁置、抛弃）的作品里的角色。
/// 视觉小说按资料库里的 VNDB 编号查询；动画、漫画与轻小说先从 AniList 读出各作品角色的生日，存成一张表
/// （生日不会变，表在缓存目录里保存，资料库加了新作品时才读新作品的），再从表里找出今明两天的。
@MainActor
final class Today资料库生日模型: ObservableObject {
    static let shared = Today资料库生日模型()

    /// 先今天、后明天。
    @Published private(set) var 角色: [Today生日角色] = []
    @Published private(set) var 已载入 = false

    var 今天的角色: [Today生日角色] { 角色.filter { !$0.是明天 } }

    private var 载入键: String?
    private static let 玩过的状态: Set<资料库状态> = [.completed, .inProgress, .onHold, .dropped]
    private static let 每次最多编号 = 100

    func 载入(资料库 entries: [本地资料库条目], 类型 types: Set<作品类型>) async {
        let calendar = Today放送表模型.日历
        let now = Date()
        let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let today = (month: calendar.component(.month, from: now), day: calendar.component(.day, from: now))
        let tomorrow = (month: calendar.component(.month, from: tomorrowDate), day: calendar.component(.day, from: tomorrowDate))
        let played = entries.filter { entry in
            entry.状态.map(Self.玩过的状态.contains) == true && types.contains(entry.类型)
        }
        let key = "\(today.month)-\(today.day)|\(played.count)|" + types.map(\.rawValue).sorted().joined(separator: ",")
        guard key != 载入键 else { return }
        载入键 = key

        let vnIDs = played
            .filter { $0.类型 == .visualNovel }
            .compactMap { $0.vndb?.id ?? $0.平台ID[.vndb] }
        let works = played.filter { $0.类型 != .visualNovel }

        async let visualNovel = Self.视觉小说角色(vnIDs, 今天: today, 明天: tomorrow)
        async let others = Today作品角色生日表.shared.角色(works, 今天: today, 明天: tomorrow)
        let (a, b) = await (visualNovel, others)
        guard 载入键 == key else { return }
        角色 = (a + b).filter { !$0.是明天 } + (a + b).filter(\.是明天)
        已载入 = true
    }

    private static func 视觉小说角色(
        _ ids: [String],
        今天 today: (month: Int, day: Int),
        明天 tomorrow: (month: Int, day: Int)
    ) async -> [Today生日角色] {
        var result: [Today生日角色] = []
        var seen: Set<String> = []
        for start in stride(from: 0, to: ids.count, by: 每次最多编号) {
            let chunk = Array(ids[start..<min(ids.count, start + 每次最多编号)])
            let characters = (try? await VNDB探索服务.shared.生日角色(日期: [today, tomorrow], 视觉小说: chunk)) ?? []
            for character in characters where seen.insert(character.id).inserted {
                var item = Today生日角色.vndb(character)
                item.是明天 = character.birthday?.first == tomorrow.month
                    && character.birthday?.dropFirst().first == tomorrow.day
                    && !(today.month == tomorrow.month && today.day == tomorrow.day)
                result.append(item)
            }
        }
        return result
    }
}

/// 资料库里动画、漫画与轻小说的角色生日表，按资料库条目编号保存在缓存目录里。
@MainActor
final class Today作品角色生日表 {
    static let shared = Today作品角色生日表()

    struct 作品项: Codable {
        struct 角色: Codable {
            let id: Int
            let 名字: String
            let 原名: String?
            let 图片: String?
            let 月: Int
            let 日: Int
        }
        let 作品: 作品搜索结果
        let 角色: [角色]
        let 读取时间: Date
    }

    private var 表: [String: 作品项]?
    private static let 有效期: TimeInterval = 30 * 86_400
    private static let 每批数量 = 25

    private static var 缓存地址: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Today资料库角色生日.json")
    }

    func 角色(
        _ entries: [本地资料库条目],
        今天 today: (month: Int, day: Int),
        明天 tomorrow: (month: Int, day: Int)
    ) async -> [Today生日角色] {
        guard !entries.isEmpty else { return [] }
        if 表 == nil {
            表 = (try? Data(contentsOf: Self.缓存地址)).flatMap { try? JSONDecoder().decode([String: 作品项].self, from: $0) } ?? [:]
        }
        await 补齐(entries)

        var result: [Today生日角色] = []
        var seen: Set<Int> = []
        for entry in entries {
            guard let item = 表?[entry.id] else { continue }
            for character in item.角色 {
                let isToday = character.月 == today.month && character.日 == today.day
                let isTomorrow = character.月 == tomorrow.month && character.日 == tomorrow.day
                guard isToday || isTomorrow, seen.insert(character.id).inserted else { continue }
                result.append(Today生日角色(
                    id: "anilist-\(character.id)",
                    名字: character.名字,
                    原名: character.原名,
                    图片: character.图片,
                    图片色情: nil,
                    图片暴力: nil,
                    来源: .作品(item.作品),
                    是明天: !isToday
                ))
            }
        }
        return result
    }

    /// 读取表里还没有、或者太久没更新的作品。遇到错误（例如请求太频繁）就先停下，下次再继续。
    private func 补齐(_ entries: [本地资料库条目]) async {
        let now = Date()
        let missing = entries.filter { entry in
            guard let item = 表?[entry.id] else { return true }
            return now.timeIntervalSince(item.读取时间) > Self.有效期
        }
        guard !missing.isEmpty else { return }

        // AniList 上动画是 ANIME，漫画与轻小说都是 MANGA；有 MAL ID 的按 MAL ID 查，否则按 AniList ID
        var batches: [(type: String, byMAL: Bool, ids: [Int], entries: [Int: [String]])] = []
        for type in ["ANIME", "MANGA"] {
            let group = missing.filter { ($0.类型 == .anime) == (type == "ANIME") }
            var mal: [Int: [String]] = [:]
            var aniList: [Int: [String]] = [:]
            for entry in group {
                if let malID = entry.malID {
                    mal[malID, default: []].append(entry.id)
                } else if let value = entry.平台ID[.aniList], let id = Int(value) {
                    aniList[id, default: []].append(entry.id)
                }
            }
            for (byMAL, table) in [(true, mal), (false, aniList)] {
                let ids = Array(table.keys).sorted()
                for start in stride(from: 0, to: ids.count, by: Self.每批数量) {
                    let chunk = Array(ids[start..<min(ids.count, start + Self.每批数量)])
                    batches.append((type, byMAL, chunk, table.filter { chunk.contains($0.key) }))
                }
            }
        }

        struct 响应: Decodable {
            struct 名字: Decodable { let full: String?; let native: String? }
            struct 图片: Decodable { let large: String?; let medium: String? }
            struct 生日: Decodable { let month: Int?; let day: Int? }
            struct 角色: Decodable { let id: Int; let name: 名字?; let image: 图片?; let dateOfBirth: 生日? }
            struct 角色列表: Decodable { let nodes: [角色] }
            struct 媒体: Decodable {
                let 作品: AniList作品
                let characters: 角色列表?
                private enum CodingKeys: String, CodingKey { case characters }
                init(from decoder: Decoder) throws {
                    作品 = try AniList作品(from: decoder)
                    characters = try decoder.container(keyedBy: CodingKeys.self)
                        .decodeIfPresent(角色列表.self, forKey: .characters)
                }
            }
            struct 页: Decodable { let media: [媒体] }
            struct 数据: Decodable { let Page: 页 }
            let data: 数据
        }

        for (index, batch) in batches.enumerated() {
            if index > 0 { try? await Task.sleep(for: .milliseconds(800)) }
            guard !Task.isCancelled,
                  let data = try? await 平台账户工具.graphQL(
                    endpoint: AniListOAuth配置.endpoint,
                    platform: "AniList",
                    accessToken: nil,
                    query: """
                    query ($ids: [Int]) {
                      Page(perPage: \(Self.每批数量)) {
                        media(\(batch.byMAL ? "idMal_in" : "id_in"): $ids, type: \(batch.type)) {
                          \(AniList作品.字段)
                          characters(perPage: 25, sort: [ROLE, FAVOURITES_DESC]) {
                            nodes { id name { full native } image { large medium } dateOfBirth { month day } }
                          }
                        }
                      }
                    }
                    """,
                    variables: ["ids": batch.ids]
                  ),
                  let decoded = try? JSONDecoder().decode(响应.self, from: data) else { break }

            var found: Set<Int> = []
            for media in decoded.data.Page.media {
                let work = media.作品
                guard let requested = batch.byMAL ? work.idMal : work.id,
                      let entryIDs = batch.entries[requested] else { continue }
                found.insert(requested)
                let characters = (media.characters?.nodes ?? []).compactMap { node -> 作品项.角色? in
                    guard let month = node.dateOfBirth?.month, let day = node.dateOfBirth?.day,
                          let name = node.name?.full ?? node.name?.native else { return nil }
                    return 作品项.角色(
                        id: node.id,
                        名字: name,
                        原名: node.name?.native,
                        图片: node.image?.large ?? node.image?.medium,
                        月: month,
                        日: day
                    )
                }
                let kind: 作品类型 = work.type == "ANIME" ? .anime : (work.format == "NOVEL" ? .lightNovel : .manga)
                let resultID = 作品搜索结果.编号(类型: kind, malID: work.idMal ?? 0, aniListID: work.id)
                guard let result = work.结果(请求的编号: [resultID]).first else { continue }
                for entryID in entryIDs {
                    表?[entryID] = 作品项(作品: result, 角色: work.isAdult == true ? [] : characters, 读取时间: Date())
                }
            }
            // AniList 上找不到的作品记一个空项，有效期内不再查
            for (id, entryIDs) in batch.entries where !found.contains(id) {
                for entryID in entryIDs where 表?[entryID] == nil {
                    表?[entryID] = 作品项(
                        作品: 作品搜索结果(id: entryID, 类型: .anime, malID: 0, 标题: "", 多语言标题: []),
                        角色: [],
                        读取时间: Date()
                    )
                }
            }
        }
        if let 表, let data = try? JSONEncoder().encode(表) {
            try? data.write(to: Self.缓存地址, options: .atomic)
        }
    }
}

// MARK: - 简报

/// 每天第一次打开Today时弹出的简报。和新功能介绍一样一页一页翻。
/// 1. 问候与过去一天的摘要（编辑维护）；2. 今天的Today卡片；3. 资料库里今天播出或发售的作品；
/// 4. 玩过或看过的作品里今天过生日的角色。没有内容的页面跳过。
struct Today简报页面<精选内容: View>: View {
    let 摘要: [Today摘要]
    let 有精选: Bool
    /// Debug 预览：资料库里没有内容时，“不要忘了…”和“还记得吗？”用今天的播出表和热门角色代替。
    var 示例 = false
    let onFinish: () -> Void
    @ViewBuilder let 精选: () -> 精选内容

    enum 页: Hashable {
        case 摘要, 精选, 更新, 生日
    }

    @EnvironmentObject private var auth: 用户登录
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locale) private var locale
    @ObservedObject private var schedule = Today放送表模型.shared
    @ObservedObject private var library = 本地资料库.shared
    @ObservedObject private var sync = PaperVNSync中心.shared
    @ObservedObject private var birthdays = Today资料库生日模型.shared
    @ObservedObject private var popularBirthdays = Today生日模型.shared

    @AppStorage(Today问候名称.来源键) private var nameSource = ""

    @State private var 当前: 页 = .摘要
    /// 换页方向：向后翻时新页面从右侧进入，返回时从左侧进入。
    @State private var 向后翻页 = true
    @State private var 问候 = Today问候.选择()
    @State private var 打开的摘要: Today摘要?
    @Namespace private var 摘要转场

    private var enabledTypes: Set<作品类型> {
        // “显示类型”只影响搜索结果，Today 显示所有类型
        Set(作品类型.allCases)
    }

    private var 更新: [Today今日更新条目] {
        let items = Today今日更新条目.今天(资料库: library.条目, 放送表: schedule, 动画: true, 视觉小说: true)
        guard 示例, items.isEmpty else { return items }
        return schedule.放送(第: Today放送表模型.今天序号()).filter(\.默认显示).prefix(3).map { item in
            var entry = 本地资料库条目(id: item.作品键, 类型: .anime, 平台ID: [:], 标题: item.作品.标题, 加入时间: nil)
            entry.状态 = .inProgress
            return .放送(item, entry)
        }
    }

    /// 简报只说今天的生日。
    private var 生日角色: [Today生日角色] {
        let today = birthdays.今天的角色
        guard 示例, today.isEmpty else { return today }
        return Array(popularBirthdays.角色.prefix(9))
    }

    /// 关闭的作品类型的摘要不显示（角色属于视觉小说）。
    private var 显示的摘要: [Today摘要] {
        摘要.filter { item in
            guard let subject = item.subject else { return true }
            return enabledTypes.contains(subject.type.作品类型 ?? .visualNovel)
        }
    }

    private var 页面: [页] {
        var pages: [页] = [.摘要]
        if 有精选 { pages.append(.精选) }
        if !更新.isEmpty { pages.append(.更新) }
        if !生日角色.isEmpty { pages.append(.生日) }
        return pages
    }

    private var 序号: Int { 页面.firstIndex(of: 当前) ?? 0 }
    private var 是最后一页: Bool { 序号 == 页面.count - 1 }

    var body: some View {
        ZStack {
            单页(当前)
                .id(当前)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: 向后翻页 ? .trailing : .leading),
                            removal: .move(edge: 向后翻页 ? .leading : .trailing)
                        )
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 不能 clipped()：内容要滚到顶栏和底栏下面，柔和滚动边缘才有东西可以淡出
        .background(Color.平台分组背景.ignoresSafeArea())
        .平台柔和滚动边缘(for: .top)
        .平台柔和滚动边缘(for: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        // 第一页没有返回按钮，导航栏也要保持显示，否则标题会比其他页面高
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbar {
            if 序号 > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        翻页(到: 序号 - 1)
                    } label: {
                        Label("上一页", systemImage: "chevron.backward")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onFinish) {
                    Label("关闭", systemImage: "xmark")
                }
            }
        }
        .平台安全区域栏(edge: .bottom) {
            VStack(spacing: 14) {
                页数指示
                继续按钮
                    .frame(maxWidth: 320)
            }
            .padding(.horizontal, 28)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $打开的摘要) { item in
            if let introduction = item.introduction {
                Today介绍页面(摘要: item, introduction: introduction)
                    .平台近全屏弹窗(dragIndicator: .visible)
                    .navigationTransition(.zoom(sourceID: item.id, in: 摘要转场))
            }
        }
        .task(id: "\(library.修订号)|\(enabledTypes.map(\.rawValue).sorted())") {
            await Today资料库生日模型.shared.载入(资料库: library.条目, 类型: enabledTypes)
        }
    }

    private func 单页(_ page: 页) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                标题(page)
                内容(page)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        // 与新功能介绍一样：内容在底栏（页数指示、继续按钮）下面渐渐淡出
        .mask {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.2), location: 0.25),
                            .init(color: .black.opacity(0.06), location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.safeAreaInsets.bottom + 24)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func 标题(_ page: 页) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if page == .摘要 {
                Text(verbatim: "PaperVN Today")
                    .font(.headline)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: 标题文字(page))
                    .foregroundStyle(.primary)
                Text(verbatim: 副标题文字(page))
                    .foregroundStyle(.secondary)
            }
            .font(.largeTitle.bold())
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func 标题文字(_ page: 页) -> String {
        switch page {
        case .摘要: Today问候.文本(问候, 名字: Today问候名称.名字(auth: auth, 选择: nameSource))
        case .精选: String(localized: "我们为你选出了一些作品")
        case .更新: String(localized: "不要忘了…")
        case .生日: String(localized: "还记得吗？")
        }
    }

    private func 副标题文字(_ page: 页) -> String {
        switch page {
        case .摘要:
            显示的摘要.isEmpty
                ? 中西文间距.去除空格(Date().formatted(.dateTime.month().day().weekday(.wide).locale(locale)))
                : String(localized: "过去一天的摘要")
        case .精选: String(localized: "来自社区推荐")
        case .更新: String(localized: "有\(更新.count)部作品今日播出或发行")
        case .生日: String(localized: "玩过或看过的作品中有\(生日角色.count)名角色生日")
        }
    }

    @ViewBuilder
    private func 内容(_ page: 页) -> some View {
        switch page {
        case .摘要:
            VStack(spacing: 14) {
                ForEach(显示的摘要) { item in
                    Today摘要卡片(item: item) {
                        打开的摘要 = item
                    }
                    .matchedTransitionSource(id: item.id, in: 摘要转场)
                }
            }
        case .精选:
            精选()
        case .更新:
            Today今日更新列表(items: 更新, usesWideLayout: false, zoom: 摘要转场)
        case .生日:
            // 卡片宽度跟随列宽（以前是固定宽度，列比卡片窄时相邻的卡片会重叠）
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(生日角色) { character in
                    Today生日角色单元(character: character, zoom: 摘要转场)
                }
            }
        }
    }

    /// 与系统的页面指示器一样：当前页是一个拉长的胶囊，其余是小圆点。
    private var 页数指示: some View {
        HStack(spacing: 8) {
            ForEach(页面.indices, id: \.self) { 位置 in
                Capsule()
                    .fill(位置 == 序号 ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 位置 == 序号 ? 20 : 8, height: 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: 序号)
        .animation(.smooth(duration: 0.3), value: 页面.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("第\(序号 + 1)页，共\(页面.count)页"))
    }

    @ViewBuilder
    private var 继续按钮: some View {
        let 按钮 = Button {
            if 是最后一页 {
                onFinish()
            } else {
                翻页(到: 序号 + 1)
            }
        } label: {
            Text(是最后一页 ? "进入Today" : "继续")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)

        if #available(iOS 26.0, *) {
            按钮.buttonStyle(.glassProminent)
        } else {
            按钮.buttonStyle(.borderedProminent)
        }
    }

    /// 先更新方向，下一帧再换页：被移除的页面会沿用它上一次渲染时的转场。
    private func 翻页(到 目标: Int) {
        let pages = 页面
        guard pages.indices.contains(目标), 目标 != 序号 else { return }
        向后翻页 = 目标 > 序号
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.4)) {
                当前 = pages[目标]
            }
        }
    }
}

// MARK: - 摘要卡片

/// 摘要搭配的作品或角色读取到的资料。
enum Today摘要主题: Hashable {
    case 视觉小说(探索视觉小说)
    case 角色(探索角色)
    case 作品(作品搜索结果)

    var 图片: (url: String?, sexual: Double?, violence: Double?) {
        switch self {
        case let .视觉小说(vn): (vn.image?.url, vn.image?.sexual, vn.image?.violence)
        case let .角色(character): (character.image?.url, character.image?.sexual, character.image?.violence)
        case let .作品(work): (work.封面, work.成人内容 ? 2 : nil, nil)
        }
    }
}

@MainActor
final class Today摘要主题缓存 {
    static let shared = Today摘要主题缓存()
    private var 主题: [String: Today摘要主题] = [:]

    private static func 键(_ subject: Today关联内容) -> String {
        "\(subject.type.rawValue):\(subject.id)"
    }

    func 已缓存(_ subject: Today关联内容) -> Today摘要主题? {
        主题[Self.键(subject)]
    }

    func 读取(_ subject: Today关联内容) async -> Today摘要主题? {
        let key = Self.键(subject)
        if let cached = 主题[key] { return cached }
        let value: Today摘要主题?
        switch subject.type {
        case .visualNovel:
            value = (try? await VNDB探索服务.shared.视觉小说(编号: [subject.id]))?.first.map { .视觉小说($0) }
        case .character:
            value = (try? await VNDB探索服务.shared.角色详情(id: subject.id)).flatMap { $0 }.map { .角色($0) }
        case .anime, .manga, .lightNovel:
            value = await 作品聚合搜索.shared.详情([subject.id])[subject.id].map { .作品($0) }
        }
        if let value { 主题[key] = value }
        return value
    }
}

/// 一条摘要：配图（有的话）与文字；没有配图时搭配的作品封面或角色头像在文字右侧。
/// 写了介绍时，点按整张卡片打开介绍页（和Today卡片的介绍页一样）。
struct Today摘要卡片: View {
    let item: Today摘要
    let onOpen: () -> Void

    @State private var 主题: Today摘要主题?

    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod") private var contentRestrictionMethod: 内容限制方式 = .blurred

    private static let 圆角: CGFloat = 24

    var body: some View {
        if item.可以打开 {
            Button(action: onOpen) {
                卡片
            }
            .buttonStyle(.plain)
        } else {
            卡片
        }
    }

    private var 卡片: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = item.image {
                Color.clear
                    .aspectRatio(image.aspectRatio, contentMode: .fit)
                    .overlay {
                        Today异步图片(url: image.url, maximumPixelSize: 1_600)
                    }
                    .clipped()
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Today摘要文字.富文本(item.text))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let detail = item.detail {
                        Text(Today摘要文字.富文本(detail))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    // 有介绍页的摘要可以点按，用强调色标出来
                    if item.可以打开 {
                        HStack(spacing: 2) {
                            Text("进一步了解")
                            Image(systemName: "chevron.forward")
                                .imageScale(.small)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let subject = item.subject, item.image == nil {
                    主题封面(subject)
                }
            }
            .padding(18)
        }
        .background(Color.平台次级分组背景)
        .clipShape(RoundedRectangle(cornerRadius: Self.圆角, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Self.圆角, style: .continuous))
        .task(id: item.subject.map { "\($0.type.rawValue):\($0.id)" }) {
            guard let subject = item.subject else { return }
            主题 = await Today摘要主题缓存.shared.读取(subject)
        }
    }

    /// 没有配图时文字右侧的封面（角色是圆形头像）。
    private func 主题封面(_ subject: Today关联内容) -> some View {
        let isCharacter = subject.type == .character
        let image = 主题?.图片
        let isRestricted = 内容安全限制判定.图片需要限制(
            sexual: image?.sexual,
            violence: image?.violence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
        let shape = isCharacter
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        return Today异步图片(url: URL(string: image?.url ?? ""), maximumPixelSize: 400)
            .frame(width: isCharacter ? 64 : 60, height: isCharacter ? 64 : 84)
            .应用不安全内容限制(isRestricted, method: contentRestrictionMethod, blurRadius: 10)
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
    }
}

enum Today摘要文字 {
    static func 富文本(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}

extension Today介绍页面 {
    /// 摘要的介绍页：封面用自己配的图，没有时用搭配的作品封面或角色图片。
    @MainActor
    init(摘要 item: Today摘要, introduction: Today介绍内容) {
        let subject = item.subject
        let cached = subject.flatMap { Today摘要主题缓存.shared.已缓存($0) }
        self.init(
            imageURL: item.image?.url ?? cached?.图片.url.flatMap(URL.init(string:)),
            visualNovelID: subject?.type == .visualNovel ? subject?.id ?? "" : "",
            eyebrow: String(localized: "过去一天的摘要"),
            description: Today摘要文字.富文本(item.text),
            releaseDate: item.detail,
            introduction: introduction
        )
    }
}

// MARK: - 示例

#if DEBUG
extension Today摘要 {
    /// 预览简报用的示例摘要（只在 Debug 构建、带 `-TodayBriefingSample` 启动参数时使用）。
    /// 文字是示例，不是真实消息。
    static let 示例: [Today摘要] = [
        Today摘要(
            id: "sample-1",
            text: "《とける風花とシロうさぎ》公开了新的宣传图。",
            detail: "示例摘要：可以配一张自己的图，同时搭配作品。",
            subject: Today关联内容(type: .visualNovel, id: "v60331", title: "とける風花とシロうさぎ", original: nil),
            image: Today图片(path: "images/2026-08-07/v60331.jpg", width: 1200, height: 849),
            introduction: Today介绍内容(blocks: [
                Today介绍段落(markdown: "这里是点开摘要后的**详细描述**，和Today卡片的介绍页一样，用`introduction`编写。\n\n"),
                Today介绍段落(style: .secondary, markdown: "灰色的段落可以写补充说明。"),
            ])
        ),
        Today摘要(
            id: "sample-2",
            text: "《葬送的芙莉莲》第二季的新一话播出后，社区评价“**节奏刚刚好**”。",
            detail: "示例摘要：不配图时，作品封面显示在右侧。",
            subject: Today关联内容(type: .anime, id: "a52991", title: "葬送のフリーレン", original: nil),
            introduction: Today介绍内容(blocks: [
                Today介绍段落(markdown: "示例介绍：没有配图时，介绍页顶部使用作品封面。"),
            ])
        ),
        Today摘要(
            id: "sample-3",
            text: "今天是宫泽有纪宁的生日。",
            detail: "示例摘要：没有写介绍时，卡片不能点开。",
            subject: Today关联内容(type: .character, id: "c15850", title: "宮沢有紀寧", original: "宮沢 有紀寧")
        ),
        Today摘要(
            id: "sample-4",
            text: "只有文字的摘要也可以。"
        ),
    ]
}
#endif
