import SwiftUI
import UIKit

@main
struct PaperVNApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var premiumStore = PaperVNPremiumStore()
    @StateObject private var auth = 用户登录()
    @StateObject private var kunAccount = 鲲Galgame账户()
    @StateObject private var bangumiAccount = Bangumi账户()
    @StateObject private var myAnimeListAccount = MyAnimeList账户()
    @StateObject private var aniListAccount = AniList账户()
    @StateObject private var annictAccount = Annict账户()
    @StateObject private var tmdbAccount = TMDB账户()
    @StateObject private var parentalControls = 家长控制中心.shared
    @StateObject private var emergencyAvoidance = 紧急回避中心.shared
    @StateObject private var feedbackUpdateNotifier = 反馈更新提醒中心()
    @StateObject private var urlRouter = PaperVNURLRouter()
    @State private var showsDelayedFreeNotice = false

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
            开屏弹窗状态.shared.进行中 = false
        }) {
            延迟免费说明页面 {
                showsDelayedFreeNotice = false
            }
            .平台近全屏弹窗()
        }
        .alert(item: $feedbackUpdateNotifier.alert) { alert in
            Alert(
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
                dismissButton: .default(Text("好")) {
                    feedbackUpdateNotifier.dismissCurrentAlert()
                }
            )
        }
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
            if 延迟免费说明.应显示 {
                // 启动时窗口还没准备好，立即呈现会被系统忽略
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    showsDelayedFreeNotice = true
                }
            }
        }
        .onOpenURL { url in
            _ = urlRouter.handle(url)
        }
        // 启动后马上从磁盘读出资料库，Today的为你推荐、今日更新等不必等打开资料库页面
        .onChange(of: auth.userID, initial: true) { _, userID in
            guard auth.isLoggedIn, !userID.isEmpty else { return }
            本地资料库.shared.切换所有者(userID)
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
        .task(id: auth.token + "|" + auth.userID) {
            if !auth.isLoggedIn && !auth.isRestoringSession {
                PaperVNSync中心.shared.重置()
            }
            await feedbackUpdateNotifier.refresh(
                token: auth.isLoggedIn ? auth.token : nil,
                userID: auth.isLoggedIn ? auth.userID : ""
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
            Task { await 敏感内容网页设置.同步() }
            Task {
                await premiumStore.refreshForActiveScene()
                await feedbackUpdateNotifier.refresh(
                    token: auth.isLoggedIn ? auth.token : nil,
                    userID: auth.isLoggedIn ? auth.userID : ""
                )
            }
            Task {
                await 简介翻译下载状态.shared.checkForUpdate()
            }
            Task {
                await 推荐模型下载状态.shared.checkForUpdate()
            }
        }

        Self.makeWindow(content: rootContent)
        .windowResizability(.contentMinSize)
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
