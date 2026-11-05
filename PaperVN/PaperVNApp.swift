import CoreSpotlight
import SwiftUI
import UIKit

@main
struct PaperVNApp: App {
    /// iPhone 平时锁竖屏、运行视觉小说时切横屏（界面方向.swift）
    @UIApplicationDelegateAdaptor(PaperVNAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var premiumStore = PaperVNPremiumStore()
    @StateObject private var auth = 用户登录()
    @StateObject private var kunAccount = 鲲Galgame账户()
    @StateObject private var bangumiAccount = Bangumi账户()
    @StateObject private var myAnimeListAccount = MyAnimeList账户()
    @StateObject private var aniListAccount = AniList账户()
    @StateObject private var annictAccount = Annict账户()
    @StateObject private var tmdbAccount = TMDB账户()
    @StateObject private var paperAccount = PaperAccount账户.shared
    @StateObject private var parentalControls = 家长控制中心.shared
    @StateObject private var emergencyAvoidance = 紧急回避中心.shared
    @StateObject private var feedbackUpdateNotifier = 反馈更新提醒中心.shared
    @StateObject private var urlRouter = PaperVNURLRouter()
    @State private var showsDelayedFreeNotice = false
    @State private var showsWhatsNew = false
    #if DEBUG
    /// 调试用：带 `-FeedbackDiagnosticsSample` 启动参数时直接打开错误报告编辑页，查看诊断信息（不需要登录）。
    @State private var showsFeedbackDiagnosticsSample = false
    /// 调试用：`-RunVisualNovelSample v7=/path/to/game` 把文件夹设为这部作品的文件夹并直接运行。
    @State private var 运行示例作品: String?
    #endif

    init() {
        guard ProcessInfo.processInfo.environment[
            "XCODE_RUNNING_FOR_PREVIEWS"
        ] != "1" else {
            return
        }

        PaperVN设置迁移.应用沉浸详情透明默认迁移()
        PaperVN设置迁移.清除助手数据()
        PaperVNConnect自动策略.准备初始状态()
        紧急回避中心.shared.startMonitoring()
        强制内容安全策略.应用到用户设置()
        为你推荐设置.移除设备限制()
        为你推荐设置.清除旧版数据()

        缓存策略.应用URLCache配置()
    }

    private var 资料库身份键: String {
        [
            String(auth.isRestoringSession), String(auth.isLoggedIn), auth.userID, paperAccount.资料?.id ?? "",
            String(myAnimeListAccount.isLoggedIn), String(aniListAccount.isLoggedIn), String(annictAccount.isLoggedIn),
            String(tmdbAccount.isLoggedIn), String(bangumiAccount.isLoggedIn),
        ].joined(separator: "|")
    }

    /// 资料库属于谁：登录了 Paper Account 时是 Paper Account（完全随它同步）；否则是VNDB账户；
    /// 只登录了其他平台时是此设备上的资料库。所有者变化时，资料库跟着搬过去。
    private func 更新资料库所有者() {
        guard !auth.isRestoringSession else { return }
        defer { Spotlight索引.shared.资料库所有者已确定() }
        #if DEBUG
        // 模拟器里不登录也能看资料库：换成示例条目
        if ProcessInfo.processInfo.arguments.contains("-LibrarySample") {
            var entries = 预览数据.资料库条目
            // 加上 MAL 上的音乐条目（Porter Robinson《Shelter》MV），看资料库检查能否认出并移除
            if ProcessInfo.processInfo.arguments.contains("-LibrarySampleMusic") {
                var music = 本地资料库条目(id: "mal-anime:34240", 类型: .anime, 平台ID: [.myAnimeList: "34240"], 标题: "Shelter", 加入时间: .now)
                music.状态 = .completed
                entries.append(music)
            }
            本地资料库.shared.预览载入(entries)
            if ProcessInfo.processInfo.arguments.contains("-LibrarySampleMusic") {
                PaperVNSync中心.shared.安排检查不可导入的条目()
            }
            return
        }
        #endif
        let vndb = auth.isLoggedIn && !auth.userID.isEmpty ? auth.userID : nil
        let others = myAnimeListAccount.isLoggedIn || aniListAccount.isLoggedIn || annictAccount.isLoggedIn
            || tmdbAccount.isLoggedIn || bangumiAccount.isLoggedIn
        let owner = paperAccount.资料.map { "pa-\($0.id)" } ?? vndb ?? (others ? 本地资料库.本机所有者 : nil)
        PaperVNSync中心.shared.VNDB已登录 = vndb != nil
        let previous = 本地资料库.shared.所有者
        本地资料库.shared.切换所有者(owner, 迁移来源: [previous, vndb, 本地资料库.本机所有者].compactMap { $0 })
        if owner != nil, paperAccount.isLoggedIn {
            Task { await paperAccount.同步资料库() }
        }
    }

    var body: some Scene {
        // 在任何页面出现之前把平台账户交给 PaperVN Sync。放在 onAppear 里太晚：
        // 资料库页面会先发起第一次同步，那时 PaperVN Sync 还不知道哪些平台已登录，这次同步就什么都不做。
        let _ = PaperVNSync中心.shared.连接账户(
            myAnimeList: myAnimeListAccount,
            aniList: aniListAccount,
            annict: annictAccount,
            tmdb: tmdbAccount,
            bangumi: bangumiAccount
        )
        let rootContent = TabBar()
        .environmentObject(premiumStore)
        .environmentObject(auth)
        .environmentObject(kunAccount)
        .environmentObject(bangumiAccount)
        .environmentObject(myAnimeListAccount)
        .environmentObject(aniListAccount)
        .environmentObject(annictAccount)
            .environmentObject(tmdbAccount)
        .environmentObject(parentalControls)
        .environmentObject(urlRouter)
        .平台柔和滚动边缘(for: .top)
        .modifier(同步待处理弹出())
        .sheet(isPresented: $showsDelayedFreeNotice, onDismiss: {
            延迟免费说明.标记已读()
            if 新功能介绍.应显示 {
                showsWhatsNew = true
            } else {
                开屏弹窗状态.shared.进行中 = false
            }
        }) {
            延迟免费说明页面 {
                showsDelayedFreeNotice = false
            }
            .平台近全屏弹窗()
        }
        .sheet(isPresented: $showsWhatsNew, onDismiss: {
            新功能介绍.标记已读()
            开屏弹窗状态.shared.进行中 = false
        }) {
            // 弹窗挂在 environmentObject 外层，里面登录Paper账户等页面要用的对象需要重新注入
            新功能介绍页面 {
                showsWhatsNew = false
            }
            .environmentObject(premiumStore)
            .environmentObject(auth)
            .environmentObject(kunAccount)
            .environmentObject(bangumiAccount)
            .environmentObject(myAnimeListAccount)
            .environmentObject(aniListAccount)
            .environmentObject(annictAccount)
            .environmentObject(tmdbAccount)
            .environmentObject(parentalControls)
            .environmentObject(urlRouter)
            .平台近全屏弹窗()
        }
        #if DEBUG
        .sheet(isPresented: $showsFeedbackDiagnosticsSample) {
            快速反馈页面(title: "诊断信息预览", description: "")
                .environmentObject(auth)
                .平台近全屏弹窗()
        }
        .fullScreenCover(isPresented: Binding(get: { 运行示例作品 != nil }, set: { if !$0 { 运行示例作品 = nil } })) {
            if let vnID = 运行示例作品 {
                视觉小说运行页面(vnID: vnID, 标题: vnID)
                    .onDisappear {
                        // 调试用：`-RunVisualNovelSampleNext v8=/path` 退出后接着运行另一部，测同一进程里换游戏
                        guard let value = UserDefaults.standard.string(forKey: "RunVisualNovelSampleNext"),
                              let separator = value.firstIndex(of: "="), vnID != String(value[..<separator]) else { return }
                        let next = String(value[..<separator])
                        let path = String(value[value.index(after: separator)...])
                        Task { @MainActor in
                            try? await 视觉小说文件夹中心.shared.设置(URL(fileURLWithPath: path), 作品: next)
                            try? await Task.sleep(for: .milliseconds(800))
                            运行示例作品 = next
                        }
                    }
            }
        }
        #endif
        .简介翻译更新提示()
        .为你推荐模型更新提示()
        .智能搜索模型更新提示()
        .environment(
            \.openURL,
            OpenURLAction { url in
                parentalControls.allowsExternalURL(url)
                    ? .systemAction(url)
                    : .discarded
            }
        )
        .平台根窗口尺寸()
        .onAppear {
            configureWindowSizeRestrictionsIfNeeded()
            emergencyAvoidance.startMonitoring()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                emergencyAvoidance.startMonitoring()
            }
            #if DEBUG
            // 看不能导入的条目的提示：-UnsupportedEntriesNoticeSample 0 是第一次读到，大于 0 是资料库里移除了几个
            if let value = UserDefaults.standard.string(forKey: "UnsupportedEntriesNoticeSample"), let removed = Int(value) {
                PaperVNSync中心.shared.不可导入提示 = .init(移除数: removed, 平台: [.myAnimeList, .aniList])
            }
            if let value = UserDefaults.standard.string(forKey: "RunVisualNovelSample"),
               let separator = value.firstIndex(of: "=") {
                let vnID = String(value[..<separator])
                let path = String(value[value.index(after: separator)...])
                Task { @MainActor in
                    try? await 视觉小说文件夹中心.shared.设置(URL(fileURLWithPath: path), 作品: vnID)
                    try? await Task.sleep(for: .milliseconds(800))
                    运行示例作品 = vnID
                }
            }
            if 快速反馈页面.调试预览 {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    showsFeedbackDiagnosticsSample = true
                }
            }
            #endif
            // 先弹延迟免费说明（只弹一次），关闭后再弹新功能介绍
            if 延迟免费说明.应显示 || 新功能介绍.应显示 {
                // 启动时窗口还没准备好，立即呈现会被系统忽略
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    if 延迟免费说明.应显示 {
                        showsDelayedFreeNotice = true
                    } else {
                        showsWhatsNew = true
                    }
                }
            }
        }
        .onOpenURL { url in
            _ = urlRouter.handle(url)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
            Spotlight索引.shared.打开(标识符: id, router: urlRouter)
        }
        // 启动后马上从磁盘读出资料库，Today的为你推荐、今日更新等不必等打开资料库页面。
        // 登录任一账户都可以使用资料库，登录状态一变就重新决定资料库属于谁
        .onChange(of: 资料库身份键, initial: true) { _, _ in
            更新资料库所有者()
        }
        .onChange(of: auth.userID, initial: true) { _, userID in
            guard auth.isLoggedIn, !userID.isEmpty else { return }
            // 已登录 Paper Account 时，把以前用这个VNDB账户提交的反馈、翻译与Today推荐转过去（每个组合只做一次）
            let token = auth.token
            Task { await PaperAccount账户.shared.迁移VNDB(token: token) }
        }
        .task {
            await parentalControls.synchronizeFamilyAuthorizationAtLaunch()
        }
        .task {
            await 简介翻译下载状态.shared.checkForUpdate()
        }
        .task {
            await 推荐模型下载状态.shared.checkForUpdate()
        }
        .task {
            await 智能搜索模型下载状态.shared.checkForUpdate()
        }
        .task {
            // 作品映射静默更新：不显示任何界面，下载在后台会话里进行
            作品映射更新.shared.启动()
            await 作品映射更新.shared.检查更新()
        }
        .task {
            // 后台设置的作品标题，静默读取
            await 作品标题覆盖.shared.检查更新()
        }
        .task {
            // 主题曲与 Apple Music 的对应表，静默更新
            await 主题曲映射更新.shared.检查更新()
        }
        .task(id: auth.token + "|" + auth.userID) {
            if !auth.isLoggedIn && !auth.isRestoringSession {
                PaperVNSync中心.shared.重置()
            }
        }
        // 反馈以 Paper Account 识别提交者
        .task(id: paperAccount.资料?.id ?? "") {
            guard let accountID = paperAccount.资料?.id else {
                feedbackUpdateNotifier.清除()
                return
            }
            await feedbackUpdateNotifier.refresh(
                token: try? await paperAccount.访问令牌(),
                userID: accountID
            )
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                emergencyAvoidance.startMonitoring()
            }
            if phase == .background,
               缓存策略.当前 == .less {
                Task {
                    await VNDB服务.shared.clearTransientDetailCache()
                }
            }
            guard phase == .active else { return }
            // 后台设置的作品标题等不经过资料库的变化，回到前台时补上
            Spotlight索引.shared.安排同步()
            Task {
                await PaperAccount账户.shared.关联设备()
                await 敏感内容网页设置.同步()
            }
            // 回到前台时取回其他设备在 Paper Account 上的资料库更改
            Task { await paperAccount.同步资料库() }
            Task {
                await premiumStore.refreshForActiveScene()
                if let accountID = paperAccount.资料?.id {
                    await feedbackUpdateNotifier.refresh(
                        token: try? await paperAccount.访问令牌(),
                        userID: accountID
                    )
                }
            }
            Task {
                await 简介翻译下载状态.shared.checkForUpdate()
            }
            Task {
                await 推荐模型下载状态.shared.checkForUpdate()
            }
            Task {
                await 作品映射更新.shared.检查更新()
            }
            Task {
                await 作品标题覆盖.shared.检查更新()
            }
            Task {
                await 主题曲映射更新.shared.检查更新()
            }
        }

        Self.makeWindow(content: rootContent)
        .windowResizability(.contentMinSize)
        // App 不在前台时作品映射下载完成或中断，系统在后台唤醒 App 交付事件
        .backgroundTask(.urlSession(作品映射更新.会话标识)) {
            await 作品映射更新.shared.处理后台事件()
        }
    }

    nonisolated private static func makeWindow<Content: View>(
        content: Content
    ) -> WindowGroup<Content> {
        WindowGroup(makeContent: {
            content
        })
    }

    private func configureWindowSizeRestrictionsIfNeeded() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.sizeRestrictions?.minimumSize =
                PaperVN窗口布局.iPad最小尺寸
        }
    }

}

enum PaperVN设置迁移 {
    static let 沉浸详情透明默认迁移键 =
        "PaperVN.didApplyImmersiveDetailTransparencyMigration.1.5.0.3"
    private static let 旧详情视图设置键 = "visualNovelDetailView"
    private static let 沉浸详情设置值 = "immersive"
    private static let 助手数据清除键 = "PaperVN.didRemoveAssistantData"
    private static let 助手本地数据键 = [
        "paperVNAssistantConversationsV1",
        "paperVNAssistantHonorific",
        "paperVNAssistantMemoryEnabledV1",
        "paperVNAssistantMemorySummaryV2",
        "paperVNAssistantMemoryClearedAtV1",
        "paperVNAssistantMemoryICloudSyncEnabledV1",
        "paperVNAssistantMemoriesV1",
        "com.jizpaper.PaperVN.paparu.remoteConfiguration",
    ]
    private static let 助手云端数据键 = [
        "paperVNAssistantMemorySummaryV2",
        "paperVNAssistantMemoryClearedAtV1",
    ]

    /// Paparu 对话功能已移除，清除它在本机和 iCloud 中留下的对话、称呼与记忆摘要。
    static func 清除助手数据(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: 助手数据清除键) else { return }
        for 键 in 助手本地数据键 {
            defaults.removeObject(forKey: 键)
        }
        let 云端 = NSUbiquitousKeyValueStore.default
        for 键 in 助手云端数据键 {
            云端.removeObject(forKey: 键)
        }
        云端.synchronize()
        defaults.set(true, forKey: 助手数据清除键)
    }

    static func 应用沉浸详情透明默认迁移(
        defaults: UserDefaults = .standard
    ) {
        if defaults.string(forKey: 旧详情视图设置键) == "tiled" {
            defaults.set(
                沉浸详情设置值,
                forKey: 旧详情视图设置键
            )
        }

        guard !defaults.bool(forKey: 沉浸详情透明默认迁移键) else { return }

        defaults.set(
            沉浸详情设置值,
            forKey: 旧详情视图设置键
        )
        defaults.set(
            沉浸详情外观.clear.rawValue,
            forKey: 沉浸详情外观.设置键
        )
        defaults.set(true, forKey: 沉浸详情透明默认迁移键)
    }
}
