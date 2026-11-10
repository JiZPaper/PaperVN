import SwiftUI

// MARK: - 场景与信息

/// 可以自定义列表信息的地方。每处各自记住显示哪些信息、按什么顺序排列。
/// 制作人员与会社详情里的作品列表跟随搜索结果（`.search`）。
enum 作品列表场景: String, CaseIterable, Identifiable {
    case library
    case search

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .library: String(localized: "资料库")
        case .search: String(localized: "搜索结果")
        }
    }

    var symbolName: String {
        switch self {
        case .library: "books.vertical"
        case .search: "magnifyingglass"
        }
    }

    var 设置键: String { "listInfo.\(rawValue)" }
    var 样式设置键: String { "listStyle.\(rawValue)" }

    /// 这里可以显示的信息，按默认顺序排列，以及默认是否显示。默认与加入自定义之前的显示一致。
    var 默认项: [作品列表配置.条目] {
        switch self {
        case .library:
            [
                .init(.status), .init(.released),
                .init(.myRating), .init(.rating),
                .init(.added, 显示: false), .init(.started, 显示: false),
                .init(.finished, 显示: false),
            ]
        case .search:
            [
                .init(.developers), .init(.type), .init(.released),
                .init(.rating), .init(.length, 显示: false),
                .init(.languages), .init(.platforms),
            ]
        }
    }

    var 默认配置: 作品列表配置 { 作品列表配置(项: 默认项) }

    /// 资料库的行没有副标题时，标题下面多留一点距离。
    fileprivate var 无副标题时标题下边距: CGFloat { self == .library ? 6 : 0 }
    fileprivate var 元数据间距: CGFloat { self == .library ? 列表行布局.元数据间距 : 8 }
}

/// 列表行里可以显示的一项信息。副标题不在其中：是否显示、显示哪种语言由“语言与地区”的副标题语言决定。
enum 作品列表信息: String, CaseIterable, Identifiable, Hashable {
    case status
    case developers
    case type
    case released
    case myRating
    case rating
    case length
    case added
    case started
    case finished
    case languages
    case platforms

    var id: Self { self }

    /// 元数据排在同一行里，放不下时换行；其他信息各占一行。
    var 是元数据: Bool {
        switch self {
        case .status, .developers, .languages, .platforms: false
        default: true
        }
    }

    var localizedTitle: String {
        switch self {
        case .status: String(localized: "状态")
        case .developers: String(localized: "开发商")
        case .type: String(localized: "类型")
        case .released: String(localized: "发行日期")
        case .myRating: String(localized: "评分")
        case .rating: String(localized: "平均评分")
        case .length: String(localized: "篇幅")
        case .added: String(localized: "添加日期")
        case .started: String(localized: "开始日期")
        case .finished: String(localized: "结束日期")
        case .languages: String(localized: "语言")
        case .platforms: String(localized: "平台")
        }
    }

    var symbolName: String {
        switch self {
        case .status: "bookmark"
        case .developers: "building.2"
        case .type: "square.stack"
        case .released: "calendar"
        case .myRating: "star"
        case .rating: "chart.bar.xaxis"
        case .length: "clock"
        case .added: "plus.circle"
        case .started: "flag"
        case .finished: "flag.checkered"
        case .languages: "globe"
        case .platforms: "desktopcomputer"
        }
    }
}

/// 元数据（日期、评分等）的排版样式，每处列表各自选择。
/// 列表风格：封面大小、状态的显示方式、其他信息的排版都不同。
enum 作品列表样式: String, CaseIterable, Identifiable {
    /// 标准封面；状态是胶囊；信息为图标加数值，一项接一项排列。
    case standard
    /// 小封面，标题和信息各只占一行，状态只用图标放在行尾，一屏能看更多作品。
    case compact
    /// 大封面，状态贴在封面底部；信息上面写名称、下面写数值，排成几栏。
    case poster
    /// 状态和其他信息都放在胶囊里。
    case capsule
    /// 名称在左、数值靠右，一项一行，中间用细线隔开，像设置里的“关于本机”；状态也是其中一行。
    case detailed

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .standard: String(localized: "标准")
        case .compact: String(localized: "紧凑")
        case .poster: String(localized: "海报")
        case .capsule: String(localized: "胶囊")
        case .detailed: String(localized: "详细")
        }
    }

    /// 日期、评分这类信息最多显示几项，按设置里的顺序取前面的；信息太多时行会很乱。
    var 最多信息数: Int {
        switch self {
        case .compact: 3
        case .detailed: 5
        default: 4
        }
    }

    /// 相对标准封面（72×100）的大小。
    fileprivate var 封面比例: CGFloat {
        switch self {
        case .compact: 0.62
        case .poster: 1.3
        default: 1
        }
    }
}

/// 一处列表显示的信息与顺序。存储为“status,released,-added”：按顺序列出，不显示的前面加“-”。
struct 作品列表配置: RawRepresentable, Equatable {
    struct 条目: Hashable, Identifiable {
        var 信息: 作品列表信息
        var 显示: Bool

        var id: 作品列表信息 { 信息 }

        init(_ 信息: 作品列表信息, 显示: Bool = true) {
            self.信息 = 信息
            self.显示 = 显示
        }
    }

    var 项: [条目]

    init(项: [条目]) {
        self.项 = 项
    }

    init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        项 = rawValue.split(separator: ",").compactMap { part in
            let 隐藏 = part.hasPrefix("-")
            return 作品列表信息(rawValue: String(隐藏 ? part.dropFirst() : part))
                .map { 条目($0, 显示: !隐藏) }
        }
    }

    var rawValue: String {
        项.map { ($0.显示 ? "" : "-") + $0.信息.rawValue }.joined(separator: ",")
    }

    /// 按场景整理：去掉这里没有的信息和重复项；以后新增的信息按默认是否显示加在最后。
    func 整理(for 场景: 作品列表场景) -> 作品列表配置 {
        let 默认 = 场景.默认项
        let 可选 = Set(默认.map(\.信息))
        var 已有 = Set<作品列表信息>()
        var 结果 = 项.filter { 可选.contains($0.信息) && 已有.insert($0.信息).inserted }
        结果 += 默认.filter { !已有.contains($0.信息) }
        return 作品列表配置(项: 结果)
    }

    func 显示的信息(for 场景: 作品列表场景) -> [作品列表信息] {
        整理(for: 场景).项.filter(\.显示).map(\.信息)
    }
}

// MARK: - 设置中心

/// 各处列表的信息与样式。列表行直接观察它：设置页在 `withAnimation` 里修改，
/// 背后的真实列表就跟着同一个动画变化（用 `@AppStorage` 时，UserDefaults 的变化通知不带动画）。
@MainActor
@Observable
final class 作品列表设置 {
    static let shared = 作品列表设置()

    private var 配置们: [作品列表场景: 作品列表配置] = [:]
    private var 样式们: [作品列表场景: 作品列表样式] = [:]

    private init() {
        let defaults = UserDefaults.standard
        for 场景 in 作品列表场景.allCases {
            配置们[场景] = defaults.string(forKey: 场景.设置键)
                .flatMap(作品列表配置.init(rawValue:))?
                .整理(for: 场景) ?? 场景.默认配置
            样式们[场景] = defaults.string(forKey: 场景.样式设置键)
                .flatMap(作品列表样式.init(rawValue:)) ?? .standard
        }
    }

    func 配置(for 场景: 作品列表场景) -> 作品列表配置 {
        配置们[场景] ?? 场景.默认配置
    }

    func 样式(for 场景: 作品列表场景) -> 作品列表样式 {
        样式们[场景] ?? .standard
    }

    func 设置配置(_ 配置: 作品列表配置, for 场景: 作品列表场景) {
        配置们[场景] = 配置
        UserDefaults.standard.set(配置.rawValue, forKey: 场景.设置键)
    }

    func 设置样式(_ 样式: 作品列表样式, for 场景: 作品列表场景) {
        样式们[场景] = 样式
        UserDefaults.standard.set(样式.rawValue, forKey: 场景.样式设置键)
    }
}

// MARK: - 行内容

/// 一行作品显示的全部信息。各处的数据模型各自转成它，没有的信息留空，显示时跳过。
struct 作品列表行内容 {
    enum 平均评分值 {
        /// 按评分设置合成的视觉小说评分（`视觉小说统一评分标签`）。
        case 视觉小说(vndbID: String, rating: Double?, voteCount: Int?)
        /// 10–100。
        case 数值(Double)
    }

    struct 人名: Hashable {
        let name: String
        let original: String?
    }

    var 主标题: 标题工具.标题结果
    var 副标题: 标题工具.标题结果?
    var 状态: (symbolName: String, title: String)?
    var 开发商: [人名] = []
    var 类型: 作品类型?
    var 发行日期: String?
    /// 动画看到第几话、漫画与轻小说读到第几话。不单独显示，跟在状态后面。
    var 进度: (symbolName: String, text: String)?
    /// 10–100。
    var 我的评分: Int?
    var 平均评分: 平均评分值?
    /// 平均评分是否暂时模糊（没有自己的评分时可以设置为先不看平均评分）。
    var 平均评分已模糊 = false
    var 显示平均评分: (() -> Void)?
    var 篇幅: String?
    var 添加日期: String?
    var 开始日期: String?
    var 结束日期: String?
    /// VNDB 语言代码。
    var 语言: [String] = []
    /// VNDB 平台代码。
    var 平台: [String] = []

    init(主标题: 标题工具.标题结果, 副标题: 标题工具.标题结果?) {
        self.主标题 = 主标题
        self.副标题 = 副标题
    }

    /// 列表里的篇幅：有时长时显示时长，否则显示篇幅类别。
    static func 篇幅文本(minutes: Int?, length: Int?) -> String? {
        if let minutes, minutes > 0 {
            let hours = minutes / 60
            return hours > 0
                ? String(localized: "\(hours)小时")
                : String(localized: "\(minutes)分钟")
        }
        switch length {
        case 1: return String(localized: "超短篇")
        case 2: return String(localized: "短篇")
        case 3: return String(localized: "中篇")
        case 4: return String(localized: "长篇")
        case 5: return String(localized: "超长篇")
        default: return nil
        }
    }

    static func 日期文本(_ date: Date?) -> String? {
        date?.formatted(.iso8601.year().month().day())
    }

    fileprivate func 有内容(_ 信息: 作品列表信息) -> Bool {
        switch 信息 {
        case .status: 状态 != nil
        case .developers: !开发商.isEmpty
        case .type: 类型 != nil
        case .released: 发行日期 != nil
        case .myRating: 我的评分 != nil
        case .rating: 平均评分 != nil
        case .length: 篇幅 != nil
        case .added: 添加日期 != nil
        case .started: 开始日期 != nil
        case .finished: 结束日期 != nil
        case .languages: !语言.isEmpty
        case .platforms: !平台.isEmpty
        }
    }
}

// MARK: - 行

/// 资料库、搜索结果、制作人员与会社的作品行：封面、标题和副标题固定，其余信息按该处的列表信息设置显示。
struct 作品列表行<Cover: View>: View {
    let 场景: 作品列表场景
    let 内容: 作品列表行内容
    /// 设置页面的预览直接传入正在编辑的配置与样式；其他地方读取已存储的设置。
    private let 指定配置: 作品列表配置?
    private let 指定样式: 作品列表样式?
    private let 封面: Cover

    private let 设置 = 作品列表设置.shared
    @ScaledMetric(relativeTo: .caption2) private var 紧凑行高: CGFloat = 16
    @AppStorage("staffNameLang") private var staffNameLang: 制作人员语言 = .romaji

    init(
        场景: 作品列表场景,
        内容: 作品列表行内容,
        配置: 作品列表配置? = nil,
        样式: 作品列表样式? = nil,
        @ViewBuilder 封面: () -> Cover
    ) {
        self.场景 = 场景
        self.内容 = 内容
        self.指定配置 = 配置
        self.指定样式 = 样式
        self.封面 = 封面()
    }

    private var 样式: 作品列表样式 { 指定样式 ?? 设置.样式(for: 场景) }

    private enum 段: Identifiable {
        case 行([作品列表信息])
        /// 元数据组按出现的先后编号：组里的信息增减时组本身保持不变，只有那一项弹出或收起。
        case 元数据(序号: Int, [作品列表信息])

        var id: String {
            switch self {
            case let .行(items): items[0].rawValue
            case let .元数据(序号, _): "metadata-\(序号)"
            }
        }
    }

    /// 相邻的元数据放进同一组；相邻的语言和平台合成一行（与原来的显示一致）。
    private var 段们: [段] {
        let 信息 = (指定配置 ?? 设置.配置(for: 场景)).显示的信息(for: 场景)
            .filter(内容.有内容)
            // 海报风格的状态贴在封面上，紧凑风格的状态是行尾的图标，都不在文字里
            .filter { !((样式 == .poster || 样式 == .compact) && $0 == .status) }
        var 结果: [段] = []
        var 元数据组数 = 0
        var 元数据项数 = 0
        for item in 信息 {
            if 是元数据(item) {
                元数据项数 += 1
                if 元数据项数 > 样式.最多信息数 { continue }
            }
            switch (结果.last, 是元数据(item)) {
            case let (.元数据(序号, items)?, true):
                结果[结果.count - 1] = .元数据(序号: 序号, items + [item])
            case let (.行(items)?, false)
                where items.last.map({ Self.可合并($0, item) }) == true:
                结果[结果.count - 1] = .行(items + [item])
            case (_, true):
                结果.append(.元数据(序号: 元数据组数, [item]))
                元数据组数 += 1
            case (_, false):
                结果.append(.行([item]))
            }
        }
        return 结果
    }

    /// 在设置里开关信息或切换样式时，信息按弹簧动画缩放着弹出或收起（动画本身由设置页面的 `.bouncy` 提供）。
    private static var 信息过渡: AnyTransition {
        .scale(scale: 0.4, anchor: .leading).combined(with: .opacity)
    }

    /// 详细风格里，状态和日期、评分等一样是表格里的一行。
    private func 是元数据(_ item: 作品列表信息) -> Bool {
        item.是元数据 || (item == .status && 样式 == .detailed)
    }

    private static func 可合并(_ a: 作品列表信息, _ b: 作品列表信息) -> Bool {
        Set([a, b]) == [.languages, .platforms]
    }

    var body: some View {
        let 段们 = 段们

        let 比例 = 样式.封面比例
        HStack(alignment: .center, spacing: 12) {
            封面
                .scaleEffect(比例)
                .frame(width: 列表封面布局.宽度 * 比例, height: 列表封面布局.高度 * 比例)
                .overlay(alignment: .bottom) {
                    if 样式 == .poster, 显示状态, let status = 内容.状态 {
                        封面状态标签(status)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 6)
                        .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
                    }
                }

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                多语言列表文本(
                    内容.主标题,
                    层级: .主标题,
                    系统字体粗细: 内容.主标题.languageCode
                        == 标题语言.chinese.langCode ? .medium : nil
                )
                .foregroundStyle(.primary)
                .lineLimit(样式 == .compact ? 1 : 2)
                .truncationMode(.tail)
                .padding(.bottom, 内容.副标题 == nil ? 场景.无副标题时标题下边距 : 0)

                if let subtitle = 内容.副标题 {
                    多语言列表文本(subtitle, 层级: .副标题)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ForEach(段们) { 段 in
                    switch 段 {
                    case let .行(items):
                        行视图(items)
                            .transition(Self.信息过渡)
                    case let .元数据(_, items):
                        元数据组(items)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            // 先占满整行再加过渡：组里的信息全部关掉后再打开一项时，整组随它一起弹出。
                            // 不占满时，缩放过渡会让 VStack 只给这一组最窄的宽度，信息被挤成多行
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(Self.信息过渡)
                    }
                }
            }

            Spacer(minLength: 0)

            if 样式 == .compact, 显示状态, let status = 内容.状态 {
                // 状态图标，下面是看到第几话
                VStack(spacing: 2) {
                    Image(systemName: status.symbolName)
                        .font(.subheadline)
                    if let 进度 = 内容.进度?.text {
                        Text(verbatim: 进度)
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: [status.title, 内容.进度?.text].compactMap { $0 }.joined(separator: " ")))
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func 行视图(_ items: [作品列表信息]) -> some View {
        if items.count > 1 {
            // 语言与平台
            Text(verbatim: items.compactMap(可用性文本).joined(separator: "·"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        } else if let item = items.first {
            switch item {
            case .status:
                if let status = 内容.状态 {
                    资料库状态标签(symbolName: status.symbolName, title: status.title, 进度: 内容.进度?.text)
                }
            case .developers:
                开发商视图
            case .languages, .platforms:
                if let text = 可用性文本(item) {
                    Text(verbatim: text)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            default:
                EmptyView()
            }
        }
    }

    /// 这一处列表设置了显示状态（海报风格的封面标签也跟随这个设置）。
    private var 显示状态: Bool {
        (指定配置 ?? 设置.配置(for: 场景)).显示的信息(for: 场景).contains(.status)
    }

    /// 海报风格：贴在封面底部的状态标签。状态一行、进度一行，封面再窄也不会截断。
    private func 封面状态标签(_ status: (symbolName: String, title: String)) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: status.symbolName)
                Text(verbatim: status.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let 进度 = 内容.进度?.text {
                Text(verbatim: 进度)
                    .monospacedDigit()
                    .opacity(0.75)
            }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        // 深色模糊底，不用颜色，盖在封面上也看得清
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var 开发商视图: some View {
        let names = ListFormatter.localizedString(byJoining:
            内容.开发商.prefix(2).map {
                人物名称工具.显示名称(name: $0.name, original: $0.original, 偏好: staffNameLang)
            }
        )
        return Text(
            标题工具.生成富文本(
                文本: names,
                isJapanese: staffNameLang == .original,
                基础大小: 12,
                日文字体名称: "HiraginoSans-W4",
                语言来源已知: false,
                空格视为日语: true
            )
        )
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func 可用性文本(_ item: 作品列表信息) -> String? {
        let names: [String] = switch item {
        case .languages: 内容.语言.prefix(3).map { VNDB显示工具.语言名称($0) }
        case .platforms: 内容.平台.prefix(2).map { VNDB显示工具.平台名称($0) }
        default: []
        }
        return names.isEmpty ? nil : ListFormatter.localizedString(byJoining: names)
    }

    // MARK: 元数据

    /// 各样式共用同一个布局和同一批视图，切换样式时只改参数：
    /// 各项移到新位置，胶囊底色、名称与分隔线淡入淡出，不会整组拆掉重建。
    private func 元数据组(_ items: [作品列表信息]) -> some View {
        let 详细 = 样式 == .detailed
        let 胶囊 = 样式 == .capsule
        let 分栏 = 样式 == .poster
        let 紧凑 = 样式 == .compact
        let 项布局 = 分栏
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
            : AnyLayout(HStackLayout(spacing: 3))
        return 作品列表元数据布局(
            每行一项: 详细,
            栏数: 分栏 ? 2 : 0,
            间距: 胶囊 ? 6 : 分栏 ? 12 : 场景.元数据间距,
            行距: 胶囊 || 分栏 ? 6 : 详细 ? 9 : 2
        ) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                元数据项(item) { icon, text in
                    项布局 {
                        if 详细 {
                            // 名称在左、数值靠右
                            Text(verbatim: item.localizedTitle)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .transition(.opacity)
                            Spacer(minLength: 12)
                        } else if 分栏 {
                            Text(verbatim: item.localizedTitle)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity)
                        } else {
                            Image(systemName: icon)
                                .foregroundStyle(.tertiary)
                                .transition(.opacity)
                        }
                        HStack(spacing: 4) {
                            Text(verbatim: text)
                            // 状态后面跟着看到第几话
                            if item == .status, let 进度 = 内容.进度?.text {
                                Text(verbatim: 进度)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(分栏 ? .caption.weight(.semibold) : 详细 ? .caption.weight(.medium) : .caption2)
                        .foregroundStyle(详细 ? .primary : .secondary)
                        .lineLimit(1)
                        // 分栏较窄，日期等放不下时稍微缩小，不截断
                        .minimumScaleFactor(分栏 ? 0.8 : 1)
                    }
                    .padding(.horizontal, 胶囊 ? 8 : 0)
                    .padding(.vertical, 胶囊 ? 3 : 0)
                    .background {
                        Capsule()
                            .fill(Color.secondary.opacity(0.08))
                            .overlay {
                                Capsule().stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
                            }
                            .opacity(胶囊 ? 1 : 0)
                    }
                    .overlay(alignment: .top) {
                        // 详细风格各行之间的细线
                        if 详细 && index > 0 {
                            Divider()
                                .offset(y: -5)
                                .transition(.opacity)
                        }
                    }
                }
                .transition(Self.信息过渡)
            }
        }
        .padding(.vertical, 胶囊 || 分栏 ? 2 : 详细 ? 4 : 0)
        // 紧凑风格只显示一行，放不下的信息不换行
        .frame(height: 紧凑 ? 紧凑行高 : nil, alignment: .topLeading)
        // 只有紧凑风格要裁掉放不下的信息；其他风格不裁，平均评分的模糊才能自然向外散开，不会被切成一条直边
        .clipShape(Rectangle().inset(by: 紧凑 ? 0 : -12))
    }

    /// 一项元数据：取出图标和文字交给各样式排版。视觉小说的平均评分要等合成结果，没有评分时整项不显示。
    @ViewBuilder
    private func 元数据项<外观视图: View>(
        _ item: 作品列表信息,
        @ViewBuilder 外观: @escaping (String, String) -> 外观视图
    ) -> some View {
        let icon = 元数据图标名称(item)
        if item == .rating, case let .视觉小说(vndbID, rating, voteCount)? = 内容.平均评分 {
            视觉小说统一评分内容(vndbID: vndbID, vndbRating: rating, vndbVoteCount: voteCount) { text in
                可模糊平均评分(外观(icon, text))
            }
        } else if let text = 元数据文本(item) {
            if item == .rating {
                可模糊平均评分(外观(icon, text))
            } else {
                外观(icon, text)
            }
        }
    }

    /// 没有自己的评分时可以先不看平均评分：模糊显示，点按后解除（第一次点按先提示，再点按一次才解除，由调用方处理）。
    /// 模糊与清晰是同一个视图，只改模糊半径：解除时数字从模糊渐渐变清楚，不会整项淡出再淡入。
    private func 可模糊平均评分<V: View>(_ view: V) -> some View {
        let 模糊 = 内容.平均评分已模糊 && 内容.显示平均评分 != nil
        return view
            .blur(radius: 模糊 ? 4 : 0)
            .overlay {
                if 模糊, let reveal = 内容.显示平均评分 {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: reveal)
                        .accessibilityLabel("连按两次以解除模糊")
                }
            }
    }

    /// 类型与状态的图标随作品而变，其他用信息本身的图标。
    private func 元数据图标名称(_ item: 作品列表信息) -> String {
        switch item {
        case .type: 内容.类型?.symbolName ?? item.symbolName
        case .status: 内容.状态?.symbolName ?? item.symbolName
        default: item.symbolName
        }
    }

    private func 元数据文本(_ item: 作品列表信息) -> String? {
        switch item {
        case .type: 内容.类型?.localizedTitle
        case .status: 内容.状态?.title
        case .released: 内容.发行日期
        case .myRating: 内容.我的评分.map { String(format: "%.0f", Double($0) / 10) }
        case .rating:
            if case let .数值(value)? = 内容.平均评分 { String(format: "%.2f", value / 10) } else { nil }
        case .length: 内容.篇幅
        case .added: 内容.添加日期
        case .started: 内容.开始日期
        case .finished: 内容.结束日期
        default: nil
        }
    }
}

/// 元数据的排列：一项接一项、放不下时整项换行（标准、胶囊），或者每项一行（详细）。
/// 三种样式都用它，切换时 SwiftUI 会把每一项从旧位置移动到新位置。
private struct 作品列表元数据布局: Layout {
    var 每行一项: Bool
    /// 大于 0 时按固定的栏数排成等宽的几栏，各项上下对齐（海报风格）。
    var 栏数: Int = 0
    var 间距: CGFloat
    var 行距: CGFloat

    private func 栏宽(_ 宽度: CGFloat) -> CGFloat {
        (宽度 - 间距 * CGFloat(栏数 - 1)) / CGFloat(栏数)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let 行们 = 排列(subviews, 宽度: proposal.width ?? .infinity)
        let 宽 = 行们.map(\.宽).max() ?? 0
        let 高 = 行们.map(\.高).reduce(0, +) + 行距 * CGFloat(max(行们.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, 宽) } ?? 宽, height: 高)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for 行 in 排列(subviews, 宽度: bounds.width) {
            var x = bounds.minX
            for (下标, 尺寸) in 行.项 {
                let 宽 = 栏数 > 0 ? 栏宽(bounds.width) : 每行一项 ? bounds.width : min(尺寸.width, bounds.width)
                subviews[下标].place(
                    at: CGPoint(x: x, y: y + (栏数 > 0 ? 0 : (行.高 - 尺寸.height) / 2)),
                    proposal: ProposedViewSize(width: 宽, height: 尺寸.height)
                )
                x += (栏数 > 0 ? 宽 : 尺寸.width) + 间距
            }
            y += 行.高 + 行距
        }
    }

    private struct 行 {
        var 项: [(Int, CGSize)] = []
        var 宽: CGFloat = 0
        var 高: CGFloat = 0
    }

    private func 排列(_ subviews: Subviews, 宽度: CGFloat) -> [行] {
        var 行们: [行] = []
        var 当前 = 行()
        for (下标, subview) in subviews.enumerated() {
            // 每行一项时占满整行（详细风格的数值靠右）；分栏时按栏宽排版
            let 提议: ProposedViewSize = if 栏数 > 0 && 宽度.isFinite {
                ProposedViewSize(width: 栏宽(宽度), height: nil)
            } else if 每行一项 && 宽度.isFinite {
                ProposedViewSize(width: 宽度, height: nil)
            } else {
                .unspecified
            }
            let 尺寸 = subview.sizeThatFits(提议)
            // 没有内容的项（例如还没有评分）不占位置
            guard 尺寸.width > 0 else { continue }
            let 新宽 = 当前.项.isEmpty ? 尺寸.width : 当前.宽 + 间距 + 尺寸.width
            let 换行 = 栏数 > 0 ? 当前.项.count >= 栏数 : (每行一项 || 新宽 > 宽度)
            if !当前.项.isEmpty, 换行 {
                行们.append(当前)
                当前 = 行()
            }
            当前.宽 = 当前.项.isEmpty ? 尺寸.width : 当前.宽 + 间距 + 尺寸.width
            当前.高 = max(当前.高, 尺寸.height)
            当前.项.append((下标, 尺寸))
        }
        if !当前.项.isEmpty { 行们.append(当前) }
        return 行们
    }
}

// MARK: - 各处数据转成行内容

extension 作品列表行内容 {
    struct 标题偏好 {
        let 偏好: 标题语言
        let 回退: 标题语言
        let 副标题: 副标题语言
        let 允许非官方: Bool

        func 主标题(_ titles: [用户多语言标题]?, 默认: String) -> 标题工具.标题结果 {
            标题工具.获取主标题(titles: titles, defaultTitle: 默认, 偏好: 偏好, 回退: 回退, 允许非官方: 允许非官方)
        }

        func 副标题(_ titles: [用户多语言标题]?, 默认: String) -> 标题工具.标题结果? {
            标题工具.获取副标题(
                titles: titles, defaultTitle: 默认, 偏好: 偏好, 回退: 回退,
                副标题设置: 副标题, 允许非官方: 允许非官方
            )
        }
    }

    /// 资料库里的视觉小说（VNDB 列表）。
    init(_ item: 用户列表项目, 标题: 标题偏好) {
        self.init(
            主标题: 标题.主标题(item.显示用多语言标题, 默认: item.vn.title),
            副标题: 标题.副标题(item.显示用多语言标题, 默认: item.vn.title)
        )
        状态 = item.primaryStatus.map { ($0.symbolName, $0.localizedTitle) }
        发行日期 = item.vn.released
        我的评分 = item.vote
        平均评分 = .视觉小说(vndbID: item.id, rating: item.vn.rating, voteCount: item.vn.votecount)
        添加日期 = Self.日期文本(item.added.map { Date(timeIntervalSince1970: TimeInterval($0)) })
        开始日期 = item.started
        结束日期 = item.finished
    }

    /// 资料库里的动画、漫画与轻小说。
    init(_ entry: 本地资料库条目, 标题: 标题偏好) {
        self.init(
            主标题: entry.显示标题(偏好: 标题.偏好, 回退: 标题.回退, 允许非官方: 标题.允许非官方),
            副标题: 标题.副标题(entry.显示用多语言标题, 默认: entry.标题)
        )
        状态 = entry.状态.map { ($0.用户列表筛选.symbolName, $0.localizedTitle(for: entry.类型)) }
        发行日期 = entry.发行日期
        进度 = entry.进度.map { 进度 in
            (entry.类型 == .anime ? "play.rectangle" : "book", entry.总数.map { "\(进度)/\($0)" } ?? "\(进度)")
        }
        我的评分 = entry.评分
        平均评分 = entry.平均评分.map { .数值($0) }
        添加日期 = Self.日期文本(entry.加入时间)
        开始日期 = entry.开始日期
        结束日期 = entry.完成日期
    }

    /// 搜索到的视觉小说。
    init(_ item: 视觉小说搜索结果, 主标题: 标题工具.标题结果, 标题: 标题偏好) {
        let titles = 作品标题覆盖.shared.应用(item.titles, 作品键: 本地资料库条目.视觉小说ID(item.id), 类型: .visualNovel)
        self.init(主标题: 主标题, 副标题: 标题.副标题(titles, 默认: item.title))
        开发商 = (item.developers ?? []).map { 人名(name: $0.name, original: $0.original) }
        发行日期 = item.released
        平均评分 = .视觉小说(vndbID: item.id, rating: item.rating, voteCount: item.votecount)
        篇幅 = Self.篇幅文本(minutes: item.length_minutes, length: item.length)
        语言 = item.languages ?? []
        平台 = item.platforms ?? []
    }

    /// 搜索到的动画、漫画与轻小说。
    init(_ item: 作品搜索结果, 标题: 标题偏好) {
        let titles = 作品标题覆盖.shared.应用(item.多语言标题, 作品键: item.作品键, 类型: item.类型)
        self.init(
            主标题: 标题.主标题(titles, 默认: item.标题),
            副标题: 标题.副标题(titles, 默认: item.标题)
        )
        类型 = item.类型
        发行日期 = item.年份.map(String.init)
    }

    /// 制作人员与会社的作品一览。
    init(_ item: 探索视觉小说, 标题: 标题偏好) {
        let titles = 作品标题覆盖.shared.应用(item.详情多语言标题, 作品键: 本地资料库条目.视觉小说ID(item.id), 类型: .visualNovel)
        self.init(
            主标题: 标题.主标题(titles, 默认: item.title),
            副标题: 标题.副标题(titles, 默认: item.title)
        )
        开发商 = (item.developers ?? []).map { 人名(name: $0.name, original: $0.original) }
        发行日期 = item.released
        平均评分 = .视觉小说(vndbID: item.id, rating: item.rating, voteCount: item.voteCount)
        篇幅 = Self.篇幅文本(minutes: item.lengthMinutes, length: item.length)
        语言 = item.languages ?? []
        平台 = item.platforms ?? []
    }
}

/// 读取标题语言设置，供各处把数据转成行内容。
@propertyWrapper
struct 作品列表标题偏好读取: DynamicProperty {
    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("subTitleLang") private var subTitleLang: 副标题语言 = .none
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false

    var wrappedValue: 作品列表行内容.标题偏好 {
        .init(偏好: preferredTitleLang, 回退: fallbackTitleLang, 副标题: subTitleLang, 允许非官方: allowUnofficialTitles)
    }
}

// MARK: - 编辑时的示例作品

/// 列表信息设置页面预览用的示例作品：每项信息都有值，勾选或取消勾选都能在预览里看到变化。
enum 作品列表示例 {
    struct 条目: Identifiable {
        let id: String
        let 内容: 作品列表行内容
        let 内置封面: String?
        let 类型: 作品类型
    }

    private static let 标题 = [
        用户多语言标题(lang: "ja", title: "Summer Pockets", latin: nil, official: true, main: true),
        用户多语言标题(lang: "zh-Hans", title: "夏日口袋", latin: nil, official: true, main: false),
    ]

    /// 动画示例用 ATRI（2024 年的 TV 动画），封面用内置的 ATRI 图片，不用联网。
    private static let 动画标题 = [
        用户多语言标题(lang: "ja", title: "ATRI -My Dear Moments-", latin: nil, official: true, main: true),
        用户多语言标题(lang: "zh-Hans", title: "亚托莉 -我挚爱的时光-", latin: nil, official: true, main: false),
    ]

    /// 示例作品：标题、开发商与日期取自 VNDB 与 MyAnimeList，评分等数字是大致的值，资料库部分是虚构的。
    static func 全部(场景: 作品列表场景, 标题偏好: 作品列表行内容.标题偏好) -> [条目] {
        var 视觉小说 = 作品列表行内容(
            主标题: 标题偏好.主标题(标题, 默认: "Summer Pockets"),
            副标题: 标题偏好.副标题(标题, 默认: "Summer Pockets")
        )
        视觉小说.开发商 = [.init(name: "Key", original: nil)]
        视觉小说.发行日期 = "2018-06-29"
        视觉小说.平均评分 = .数值(84.6)
        视觉小说.篇幅 = 作品列表行内容.篇幅文本(minutes: 2280, length: 4)
        视觉小说.语言 = ["ja", "zh-Hans", "en"]
        视觉小说.平台 = ["win", "swi", "ps4"]

        var 动画 = 作品列表行内容(
            主标题: 标题偏好.主标题(动画标题, 默认: "ATRI -My Dear Moments-"),
            副标题: 标题偏好.副标题(动画标题, 默认: "ATRI -My Dear Moments-")
        )
        动画.类型 = .anime

        switch 场景 {
        case .library:
            视觉小说.状态 = (用户列表筛选.finished.symbolName, 用户列表筛选.finished.localizedTitle)
            视觉小说.我的评分 = 90
            视觉小说.添加日期 = "2025-07-20"
            视觉小说.开始日期 = "2025-07-21"
            视觉小说.结束日期 = "2025-08-31"
            动画.发行日期 = "2024-07-13"
            动画.状态 = (资料库状态.inProgress.用户列表筛选.symbolName, 资料库状态.inProgress.localizedTitle(for: .anime))
            动画.进度 = ("play.rectangle", "7/13")
            动画.我的评分 = 80
            动画.平均评分 = .数值(70.2)
            动画.添加日期 = "2024-07-10"
            动画.开始日期 = "2024-07-13"
            return [
                条目(id: "sample-vn", 内容: 视觉小说, 内置封面: "WhatsNewSummerPockets", 类型: .visualNovel),
                条目(id: "sample-anime", 内容: 动画, 内置封面: "WhatsNewATRICover", 类型: .anime),
            ]
        case .search:
            动画.发行日期 = "2024"
            return [
                条目(id: "sample-vn", 内容: 视觉小说, 内置封面: "WhatsNewSummerPockets", 类型: .visualNovel),
                条目(id: "sample-anime", 内容: 动画, 内置封面: "WhatsNewATRICover", 类型: .anime),
            ]
        }
    }
}

/// 示例作品的一行，封面用内置图片或作品类型图标。
struct 作品列表示例行: View {
    let 场景: 作品列表场景
    let 条目: 作品列表示例.条目
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        作品列表行(场景: 场景, 内容: 条目.内容) {
            let 圆角 = 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
            Group {
                if let 封面 = 条目.内置封面 {
                    Image(封面)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.12)
                        .overlay {
                            Image(systemName: 条目.类型.symbolName)
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
            .clipShape(RoundedRectangle(cornerRadius: 圆角, style: .continuous))
            .accessibilityHidden(true)
        }
        .allowsHitTesting(false)
    }
}
