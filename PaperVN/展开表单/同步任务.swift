import SwiftUI

/// 设置“资料库”里PaperVN Sync下方的同步任务页面：显示各平台的同步进度、问题和缺失的作品。
/// 资料库顶部的同步状态提示也会打开这个页面。
struct 同步任务页面: View {
    /// 从资料库顶部以弹出页面打开时显示关闭按钮。
    var showsCloseButton = false
    @EnvironmentObject private var bangumiAccount: Bangumi账户
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        同步任务内容(bangumiProgress: bangumiAccount.同步进度)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .平台关闭操作) {
                        Button {
                            dismiss()
                        } label: {
                            Label("关闭", systemImage: "xmark")
                        }
                    }
                }
            }
    }
}

private struct 同步任务内容: View {
    @ObservedObject var bangumiProgress: Bangumi同步进度
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var bangumiAccount: Bangumi账户
    @EnvironmentObject private var myAnimeListAccount: MyAnimeList账户
    @EnvironmentObject private var aniListAccount: AniList账户
    @EnvironmentObject private var annictAccount: Annict账户
    @EnvironmentObject private var tmdbAccount: TMDB账户
    @ObservedObject private var sync = PaperVNSync中心.shared
    @ObservedObject private var library = 本地资料库.shared
    @AppStorage(PaperVNSync中心.启用设置键) private var paperVNSyncEnabled = PaperVNSync中心.默认启用

    var body: some View {
        平台滚动页面 {
            if let text = PaperVNSync中心.待处理说明(sync.待处理) {
                Section {
                    Button {
                        sync.显示待处理 = true
                    } label: {
                        同步状态提示行(提示: .需要确认(text))
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                vndbRow
                bangumiRow
                animeRow(.myAnimeList, isLoggedIn: myAnimeListAccount.isLoggedIn)
                animeRow(.aniList, isLoggedIn: aniListAccount.isLoggedIn)
                animeRow(.annict, isLoggedIn: annictAccount.isLoggedIn)
                animeRow(.tmdb, isLoggedIn: tmdbAccount.isLoggedIn)
            } header: {
                Text("同步")
            } footer: {
                if bangumiAccount.isLoggedIn && paperVNSyncEnabled {
                    Text("Bangumi番组计划不提供PaperVN所需“从资料库删除”功能对应的API。无法向Bangumi番组计划同步资料库。")
                }
            }

            let unmatchedPlatforms = 资料库平台.allCases.filter { (sync.未匹配数[$0] ?? 0) > 0 }
            if !unmatchedPlatforms.isEmpty {
                Section {
                    ForEach(unmatchedPlatforms) { platform in
                        NavigationLink {
                            未匹配作品页面(平台: platform)
                        } label: {
                            LabeledContent(platform.localizedTitle) {
                                Text(sync.未匹配数[platform] ?? 0, format: .number)
                            }
                        }
                    }
                } header: {
                    Text("缺失的作品")
                } footer: {
                    Text("手动匹配找不到的作品。")
                }
            }

            if sync.隐藏数 > 0 {
                Section {
                    Button("显示已隐藏的作品") {
                        sync.显示隐藏的作品()
                    }
                } header: {
                    Text("已隐藏的作品")
                } footer: {
                    Text("分别保留资料库时，其他\(sync.隐藏数)部作品已在资料库中隐藏。")
                }
            }

            Section {
                资料库统计图(entries: library.条目)
            } header: {
                Text("统计信息")
            }
        }
        .平台分组列表样式()
        .navigationTitle("同步任务")
        .平台内联导航标题()
        .平台柔和滚动边缘(for: .top)
        .toolbar {
            ToolbarItem(placement: .平台主操作) {
                Button {
                    synchronizeNow()
                } label: {
                    Label("立即同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!auth.isLoggedIn || sync.正在同步 || bangumiProgress.isSynchronizing)
            }
        }
    }

    private var vndbRow: some View {
        任务行(
            title: "VNDB",
            isLoggedIn: auth.isLoggedIn,
            lastSynchronized: sync.最近同步时间[.vndb],
            state: sync.任务[.vndb]?.状态
        )
    }

    private var bangumiRow: some View {
        任务行(
            title: 资料库平台.bangumi.localizedTitle,
            isLoggedIn: bangumiAccount.isLoggedIn,
            lastSynchronized: sync.最近同步时间[.bangumi],
            state: paperVNSyncEnabled ? bangumiState : nil,
            isDisabled: !paperVNSyncEnabled,
            unmatchedCount: sync.未匹配数[.bangumi] ?? 0
        )
    }

    private func animeRow(_ platform: 资料库平台, isLoggedIn: Bool) -> some View {
        任务行(
            title: platform.localizedTitle,
            isLoggedIn: isLoggedIn,
            lastSynchronized: sync.最近同步时间[platform],
            state: paperVNSyncEnabled ? sync.任务[platform]?.状态 : nil,
            isDisabled: !paperVNSyncEnabled,
            unmatchedCount: sync.未匹配数[platform] ?? 0
        )
    }

    private var bangumiState: PaperVNSync中心.任务状态? {
        if bangumiProgress.isSynchronizing {
            return .进行中(已完成: bangumiProgress.已同步数, 总数: bangumiProgress.待同步总数)
        }
        // 视觉小说的推送之外，Bangumi 也参与动画、漫画与轻小说的同步；
        // 动画同步需要确认或失败时要显示出来，不能被视觉小说推送的结果盖住
        let animeState = sync.任务[.bangumi]?.状态
        switch animeState {
        case .进行中, .需要处理, .失败:
            return animeState
        default:
            break
        }
        if let message = bangumiProgress.synchronizationErrorMessage {
            return .失败(message)
        }
        return animeState
    }

    private func synchronizeNow() {
        let token = auth.token
        let userID = auth.userID
        // 还有没确认的更改时，同步会一直等着；手动同步时直接打开确认页面
        if sync.待处理 != nil {
            sync.显示待处理 = true
            return
        }
        Task {
            await sync.从VNDB导入(token: token, userID: userID, forceRefresh: true)
            await sync.同步动画漫画()
            if paperVNSyncEnabled {
                bangumiAccount.startLibrarySynchronization(vndbToken: token, userID: userID)
            }
        }
    }
}

/// 副标题说明登录状态与最近同步时间；右侧显示同步状态符号。
private struct 任务行: View {
    let title: String
    let isLoggedIn: Bool
    let lastSynchronized: Date?
    let state: PaperVNSync中心.任务状态?
    /// PaperVN Sync关闭时，只向平台推送的行显示“未开启”。
    var isDisabled = false
    /// 找不到对应作品、没有同步到该平台的作品数。
    var unmatchedCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                    subtitle
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if isLoggedIn {
                    statusLabel
                }
            }
            if isLoggedIn, case let .进行中(done, total) = state {
                if let total, total > 0 {
                    ProgressView(value: Double(min(done, total)), total: Double(total))
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
            }
            if isLoggedIn, case let .失败(message) = state {
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if isLoggedIn, unmatchedCount > 0 {
                Text("缺失\(unmatchedCount)部作品")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        // 分割线默认对齐到行内第一个文本，右侧状态文本会把它推短，这里改为从行首开始
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subtitle: some View {
        if !isLoggedIn {
            Text("未登录")
        } else if let lastSynchronized {
            // 每分钟刷新一次相对时间
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Text(verbatim: lastSynchronized.相对时间文本())
            }
        } else {
            Text("已登录")
        }
    }

    private var completedSymbol: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.green)
            .accessibilityLabel("已同步")
    }

    @ViewBuilder
    private var statusLabel: some View {
        if isDisabled {
            Text("未开启")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            switch state {
            case let .进行中(done, total):
                Group {
                    if let total {
                        Text(verbatim: "\(min(done, total).formatted())/\(total.formatted())")
                    } else {
                        Text("正在同步…")
                    }
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
            case .失败:
                // 和完成时的绿勾放在同一位置；原因显示在行下方
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .accessibilityLabel("未能同步")
            case .完成:
                completedSymbol
            case .需要处理:
                // 图标和绿勾同样大小、在同一位置；不用 Label，列表里的 Label 会给图标留出很宽的位置
                HStack(spacing: 4) {
                    Text("需要确认")
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.orange)
            case .等待, nil:
                // 本次启动还没同步过时，用保存的最近同步时间判断
                if lastSynchronized != nil {
                    completedSymbol
                }
            }
        }
    }
}

/// 本地资料库按作品类型的分布：总数、堆叠条形图与图例。
private struct 资料库统计图: View {
    let entries: [本地资料库条目]

    private struct 分组: Identifiable {
        let type: 作品类型
        let count: Int
        var id: 作品类型 { type }
    }

    private var groups: [分组] {
        作品类型.allCases.compactMap { type in
            let count = entries.lazy.filter { $0.类型 == type }.count
            return count > 0 ? 分组(type: type, count: count) : nil
        }
    }

    var body: some View {
        let groups = groups
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("作品")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: entries.count.formatted())
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
            }

            if !groups.isEmpty {
                分段条(groups: groups, total: entries.count)
                    .frame(height: 12)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    ForEach(groups) { group in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Self.color(group.type))
                                .frame(width: 8, height: 8)
                            Text(verbatim: group.type.localizedTitle)
                            Spacer()
                            Text(verbatim: group.count.formatted())
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// 各类型按比例排成一条，两端由整条胶囊裁出圆角。
    private struct 分段条: View {
        let groups: [分组]
        let total: Int

        var body: some View {
            GeometryReader { proxy in
                let spacing: CGFloat = 2
                let available = proxy.size.width - spacing * CGFloat(max(groups.count - 1, 0))
                HStack(spacing: spacing) {
                    ForEach(groups) { group in
                        Rectangle()
                            .fill(资料库统计图.color(group.type))
                            .frame(width: available * CGFloat(group.count) / CGFloat(max(total, 1)))
                    }
                }
            }
            .clipShape(Capsule())
        }
    }

    fileprivate static func color(_ type: 作品类型) -> Color {
        switch type {
        case .anime: .blue
        case .manga: .orange
        case .lightNovel: .green
        case .visualNovel: .purple
        }
    }
}

/// 资料库顶部和同步任务页面最上面的同步状态提示。
enum 同步状态提示: Equatable {
    /// 需要用户确认，点按后打开处理页面。
    case 需要确认(String)
    case 正在同步(已完成: Int, 总数: Int?, 平台: [资料库平台])
    case 失败([资料库平台])
    /// 还没被忽略的缺失作品数。
    case 缺失作品(Int)

    /// 一次只显示最要紧的一条：需要确认 → 正在同步 → 失败 → 缺失的作品。
    /// VNDB 导入时资料库本身会显示载入状态，不再提示正在同步。
    static func 当前(
        待处理: 同步会话?,
        任务: [资料库平台: PaperVNSync中心.同步任务],
        未匹配作品: [资料库平台: [未匹配作品]],
        已忽略缺失: Set<String>
    ) -> 同步状态提示? {
        if let text = PaperVNSync中心.待处理说明(待处理) {
            return .需要确认(text)
        }
        let running = 任务.values
            .filter { if case .进行中 = $0.状态 { $0.平台 != .vndb } else { false } }
            .sorted { $0.平台.rawValue < $1.平台.rawValue }
        if !running.isEmpty {
            var done = 0
            var total: Int? = 0
            for task in running {
                guard case let .进行中(finished, count) = task.状态 else { continue }
                done += finished
                total = total.flatMap { sum in count.map { sum + $0 } }
            }
            return .正在同步(已完成: done, 总数: total, 平台: running.map(\.平台))
        }
        let failed = 任务.values
            .filter { if case .失败 = $0.状态 { true } else { false } }
            .map(\.平台)
            .sorted { $0.rawValue < $1.rawValue }
        if !failed.isEmpty {
            return .失败(failed)
        }
        let missing = Set(未匹配作品.flatMap { platform, works in works.map { "\(platform.rawValue)|\($0.键)" } })
        if !missing.isSubset(of: 已忽略缺失) {
            return .缺失作品(missing.count)
        }
        return nil
    }
}

/// 同步状态提示的一行：左侧符号，标题与说明，右侧箭头；缺失的作品可以忽略。
struct 同步状态提示行: View {
    let 提示: 同步状态提示
    var 忽略: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                符号
                    .font(.title3)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(标题)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(verbatim: 说明)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if let 忽略 {
                    Button(action: 忽略) {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .tint(.secondary)
                    .accessibilityLabel("忽略")
                } else {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            if case let .正在同步(done, total?, _) = 提示, total > 0 {
                ProgressView(value: Double(min(done, total)), total: Double(total))
                    .padding(.leading, 40)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var 符号: some View {
        switch 提示 {
        case .需要确认:
            Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(.orange)
        case .正在同步:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, options: .repeat(.continuous))
        case .失败:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .缺失作品:
            Image(systemName: "questionmark.square.dashed")
                .foregroundStyle(.orange)
        }
    }

    private var 标题: LocalizedStringKey {
        switch 提示 {
        case .需要确认: "检查更改"
        case .正在同步: "正在同步"
        case .失败: "未能同步"
        case .缺失作品: "缺失的作品"
        }
    }

    private var 说明: String {
        switch 提示 {
        case let .需要确认(text): text
        case let .正在同步(_, _, platforms): platforms.map(\.localizedTitle).顿号并列
        case let .失败(platforms): platforms.map(\.localizedTitle).顿号并列
        case let .缺失作品(count): String(localized: "有\(count)部作品在其他平台上缺失。")
        }
    }
}

/// 账户页面里这个账户的同步方式：上面用动画演示资料库与平台之间的方向，下面选择。改变后重新同步。
struct 账户同步方式设置区: View {
    let 平台: 资料库平台
    @AppStorage private var stored: String
    @AppStorage(PaperVNSync中心.启用设置键) private var paperVNSyncEnabled = PaperVNSync中心.默认启用

    init(平台: 资料库平台) {
        self.平台 = 平台
        _stored = AppStorage(wrappedValue: 平台.默认同步方向.rawValue, 资料库平台.同步方向设置键(平台))
    }

    /// 读 stored，设置改变时刷新。
    private var 当前: 同步方向 {
        _ = stored
        return 平台.同步方向
    }

    var body: some View {
        if paperVNSyncEnabled {
            Section {
                同步方向演示(平台: 平台, 方向: 当前)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                Picker(selection: Binding(
                    get: { 当前 },
                    set: { value in
                        withAnimation(.smooth(duration: 0.3)) { stored = value.rawValue }
                        Task { await PaperVNSync中心.shared.同步动画漫画() }
                    }
                )) {
                    ForEach(平台.可选同步方向) { direction in
                        Text(verbatim: direction.localizedTitle).tag(direction)
                    }
                } label: {
                    Text("同步方式")
                }
            } header: {
                Text(verbatim: "PaperVN Sync")
            } footer: {
                Text(方向说明)
            }
        }
    }

    private var 方向说明: LocalizedStringKey {
        switch 当前 {
        case .双向: "资料库与\(平台.localizedTitle)互相同步。"
        case .仅导入: "\(平台.localizedTitle)上的更改会导入资料库，资料库中的更改不会同步到\(平台.localizedTitle)。"
        case .仅导出: "资料库中的更改会同步到\(平台.localizedTitle)，\(平台.localizedTitle)上的更改不会导入资料库。"
        case .无: "不与\(平台.localizedTitle)同步。"
        }
    }
}

/// 左边是资料库，右边是平台，中间的小方块沿着同步的方向移动；“无”时中间断开。
private struct 同步方向演示: View {
    let 平台: 资料库平台
    let 方向: 同步方向
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            端点(名称: String(localized: "资料库"), 符号: "books.vertical.fill", 启用: 方向 != .无)
            通道
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            端点(名称: 平台.localizedTitle, 符号: "person.crop.circle.fill", 启用: 方向 != .无)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: 方向.localizedTitle))
    }

    private func 端点(名称: String, 符号: String, 启用: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: 符号)
                .font(.title2)
                .foregroundStyle(启用 ? Color.accentColor : Color.secondary)
                .frame(width: 52, height: 52)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(verbatim: 名称)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 92)
    }

    @ViewBuilder
    private var 通道: some View {
        if 方向 == .无 {
            HStack(spacing: 6) {
                虚线
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                虚线
            }
        } else if reduceMotion {
            Image(systemName: 方向 == .双向 ? "arrow.left.arrow.right" : 方向 == .仅导入 ? "arrow.left" : "arrow.right")
                .font(.headline)
                .foregroundStyle(.tint)
        } else {
            TimelineView(.animation) { context in
                Canvas { graphics, size in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let midY = size.height / 2
                    var line = Path()
                    line.move(to: CGPoint(x: 0, y: midY))
                    line.addLine(to: CGPoint(x: size.width, y: midY))
                    graphics.stroke(line, with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
                    // 双向时两行小方块各走一个方向
                    let lanes: [(dy: CGFloat, forward: Bool)] = switch 方向 {
                    case .双向: [(-7, true), (7, false)]
                    case .仅导出: [(0, true)]
                    default: [(0, false)]
                    }
                    let count = 3
                    for lane in lanes {
                        for index in 0..<count {
                            var progress = (time / 2.2 + Double(index) / Double(count)).truncatingRemainder(dividingBy: 1)
                            if !lane.forward { progress = 1 - progress }
                            let x = 6 + (size.width - 12) * progress
                            // 两端淡入淡出
                            let fade = min(progress, 1 - progress) * 5
                            let rect = CGRect(x: x - 4, y: midY + lane.dy - 5, width: 8, height: 10)
                            graphics.opacity = min(fade, 1)
                            graphics.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.accentColor))
                            graphics.opacity = 1
                        }
                    }
                }
            }
        }
    }

    private var 虚线: some View {
        Line()
            .stroke(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 5]))
            .frame(height: 2)
    }

    private nonisolated struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
    }
}

#if DEBUG
// MARK: - 预览

#Preview("同步任务") {
    let bangumi = 预览数据.bangumi(已登录: true)
    预览状态切换([
        .init("各平台已登录", 准备: {
            本地资料库.shared.预览载入(预览数据.资料库条目)
            bangumi.同步进度.isSynchronizing = true
            bangumi.同步进度.已同步数 = 14
            bangumi.同步进度.待同步总数 = 40
            PaperVNSync中心.shared.预览设置(
                待处理: 预览数据.检查更改会话(),
                任务: [
                    .vndb: .完成(.now),
                    .myAnimeList: .进行中(已完成: 37, 总数: 52),
                    .aniList: .完成(.now),
                    .annict: .失败(String(localized: "无法读取账户信息，请重新登录。")),
                    .tmdb: .需要处理,
                ],
                最近同步时间: [
                    .vndb: Date(timeIntervalSinceNow: -120),
                    .aniList: Date(timeIntervalSinceNow: -3_600),
                    .tmdb: Date(timeIntervalSinceNow: -86_400 * 2),
                ],
                未匹配作品: 预览数据.未匹配,
                隐藏数: 12
            )
        }) {
            NavigationStack { 同步任务页面() }
                // 离视图更近的环境对象优先，覆盖预览环境里的Bangumi账户
                .environmentObject(bangumi)
        },
        .init("未登录", 准备: {
            本地资料库.shared.预览载入([])
            PaperVNSync中心.shared.预览设置()
        }) {
            NavigationStack { 同步任务页面() }
                .预览环境(已登录: false)
        },
        .init("PaperVN Sync已关闭", 准备: {
            本地资料库.shared.预览载入(预览数据.资料库条目)
            PaperVNSync中心.shared.预览设置(任务: [.vndb: .完成(.now)], 最近同步时间: [.vndb: .now])
        }) {
            NavigationStack { 同步任务页面() }
                .defaultAppStorage(预览数据.设置("同步关闭", [PaperVNSync中心.启用设置键: false]))
        },
    ])
    .预览环境()
}
#endif
