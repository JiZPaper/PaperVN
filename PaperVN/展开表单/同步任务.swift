import SwiftUI

/// “账户与设置”里的同步任务页面：显示PaperVN Sync各平台的同步进度。
struct 同步任务页面: View {
    @EnvironmentObject private var bangumiAccount: Bangumi账户

    var body: some View {
        同步任务内容(bangumiProgress: bangumiAccount.同步进度)
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
            if sync.待处理 != nil {
                Section {
                    Button {
                        sync.显示待处理 = true
                    } label: {
                        Label("检查更改", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                } footer: {
                    Text("确认以同步动画、漫画与轻小说。")
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
                    Text("Bangumi上的动画、漫画与轻小说只会导入到资料库，资料库中的更改不会同步到Bangumi。")
                }
            }

            let loggedInPlatforms: [资料库平台] = [
                bangumiAccount.isLoggedIn ? .bangumi : nil,
                myAnimeListAccount.isLoggedIn ? .myAnimeList : nil,
                aniListAccount.isLoggedIn ? .aniList : nil,
                annictAccount.isLoggedIn ? .annict : nil,
                tmdbAccount.isLoggedIn ? .tmdb : nil,
            ].compactMap { $0 }
            if paperVNSyncEnabled, !loggedInPlatforms.isEmpty {
                Section {
                    ForEach(loggedInPlatforms) { platform in
                        同步方向选择(平台: platform)
                    }
                } header: {
                    Text("同步方式")
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
                    Text("分别保留资料库时，其他账户中的\(sync.隐藏数)部作品已在资料库中隐藏。")
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
            title: "Bangumi",
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
                Text("有\(unmatchedCount)部作品在此平台上缺失，未同步")
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
                    .accessibilityLabel("同步失败")
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

/// 一个账户的同步方式。改变后重新同步。
private struct 同步方向选择: View {
    let 平台: 资料库平台
    @AppStorage private var stored: String

    init(平台: 资料库平台) {
        self.平台 = 平台
        _stored = AppStorage(wrappedValue: 平台.默认同步方向.rawValue, 资料库平台.同步方向设置键(平台))
    }

    var body: some View {
        Picker(selection: Binding(
            get: { 平台.同步方向 },
            set: { value in
                stored = value.rawValue
                Task { await PaperVNSync中心.shared.同步动画漫画() }
            }
        )) {
            ForEach(平台.可选同步方向) { direction in
                Text(verbatim: direction.localizedTitle).tag(direction)
            }
        } label: {
            Text(verbatim: 平台.localizedTitle)
        }
        // 读一次 stored，设置改变时刷新这一行
        .id(stored)
    }
}
