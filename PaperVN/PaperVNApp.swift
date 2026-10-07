import SwiftUI
import UIKit

@main
struct PaperVNApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(为你推荐偏好分析设置.启用键)
    private var recommendationPreferenceAnalysisEnabled = true
    @StateObject private var premiumStore = PaperVNPremiumStore()
    @StateObject private var auth = 用户登录()
    @StateObject private var kunAccount = 鲲Galgame账户()
    @StateObject private var bangumiAccount = Bangumi账户()
    @StateObject private var parentalControls = 家长控制中心.shared
    @StateObject private var emergencyAvoidance = 紧急回避中心.shared
    @StateObject private var feedbackUpdateNotifier = 反馈更新提醒中心()
    @StateObject private var urlRouter = PaperVNURLRouter()
    @State private var showsRecommendationModelPrompt = false
    @State private var recommendationModelDownloadState = 推荐模型下载状态.shared

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
        为你推荐偏好分析设置.应用设备限制()
        推荐后台分析中心.shared.注册后台任务()

        缓存策略.应用URLCache配置()
    }

    var body: some Scene {
        let rootContent = TabBar()
        .environmentObject(premiumStore)
        .environmentObject(auth)
        .environmentObject(kunAccount)
        .environmentObject(bangumiAccount)
        .environmentObject(parentalControls)
        .environmentObject(urlRouter)
        .平台柔和滚动边缘(for: .top)
        .alert(item: $feedbackUpdateNotifier.alert) { alert in
            Alert(
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
                dismissButton: .default(Text("好")) {
                    feedbackUpdateNotifier.dismissCurrentAlert()
                }
            )
        }
        .alert(
            "下载偏好分析所需模型",
            isPresented: $showsRecommendationModelPrompt
        ) {
            Button("关闭“为你推荐”") {
                recommendationPreferenceAnalysisEnabled = false
                推荐后台分析中心.shared.停止分析()
            }
            if let size = recommendationModelDownloadState.serverFileSizeText {
                Button("下载（\(size)）") {
                    Task { await recommendationModelDownloadState.download() }
                }
            } else {
                Button("下载") {
                    Task { await recommendationModelDownloadState.download() }
                }
            }
        } message: {
            Text("从此版本开始，偏好分析所需的模型不再包含在PaperVN App中，偏好分析将用于Today页面的“为你推荐”部分。")
        }
        .简介翻译更新提示()
        .偏好分析模型更新提示()
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
            推荐后台分析中心.shared.启动需要的分析()
            presentRecommendationModelPromptIfNeeded()
        }
        .onOpenURL { url in
            _ = urlRouter.handle(url)
        }
        .onChange(of: recommendationPreferenceAnalysisEnabled) { _, enabled in
            if enabled && 为你推荐偏好分析设置.此设备支持 {
                推荐后台分析中心.shared.启动需要的分析()
            } else {
                推荐后台分析中心.shared.停止分析()
            }
        }
        .task {
            await parentalControls.synchronizeFamilyAuthorizationAtLaunch()
        }
        .task {
            await 简介翻译下载状态.shared.checkForUpdate()
        }
        .task {
            await recommendationModelDownloadState.checkForUpdate()
        }
        .task {
            await 智能搜索模型下载状态.shared.checkForUpdate()
        }
        .task(id: auth.token + "|" + auth.userID) {
            推荐后台分析中心.shared.启动需要的分析()
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
            推荐后台分析中心.shared.启动需要的分析()
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
                await recommendationModelDownloadState.checkForUpdate()
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

    private func presentRecommendationModelPromptIfNeeded() {
        recommendationModelDownloadState.refresh()
        guard 为你推荐偏好分析设置.已启用,
              !recommendationModelDownloadState.hasDownloadedModel,
              !recommendationModelDownloadState.isDownloading else {
            return
        }
        Task {
            await recommendationModelDownloadState.refreshServerFileSize()
            showsRecommendationModelPrompt = true
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
