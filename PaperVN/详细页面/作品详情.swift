import Combine
import SwiftUI
@preconcurrency import Translation

/// 从资料库或相关作品打开动画、漫画、轻小说详情页时传的参数。
nonisolated struct 作品详情目标: Hashable {
    let kind: MyAnimeList列表项.种类
    /// 没有 MAL ID 时为 0，用 AniList 或 Bangumi 的 ID 打开。
    let malID: Int
    let 标题: String
    let 封面: String?
    var aniListID: Int? = nil
    var bangumiID: Int? = nil
    /// 列表里已经有的各语言标题：进入详情页时直接按标题语言设置显示，不先闪一下英文或罗马字标题。
    var 多语言标题: [用户多语言标题]? = nil

    /// 作品在资料库里的编号，和同步时的编号规则一致（有 MAL ID 用 MAL，否则用 AniList、Bangumi）。
    var 作品键: String {
        let 分组 = kind == .anime ? "anime" : "manga"
        if malID > 0 { return "mal-\(分组):\(malID)" }
        if let aniListID { return "aniList-\(分组):\(aniListID)" }
        return "bangumi-\(分组):\(bangumiID ?? 0)"
    }

    var 平台ID: [资料库平台: String] {
        if malID > 0 { return [.myAnimeList: String(malID)] }
        if let aniListID { return [.aniList: String(aniListID)] }
        return bangumiID.map { [.bangumi: String($0)] } ?? [:]
    }
}

extension 本地资料库条目 {
    /// 打开详情页用的参数：有 MAL ID 用 MAL，否则用 AniList、Bangumi 的 ID（编号本身也带着平台 ID）。
    func 详情目标(标题: String) -> 作品详情目标? {
        let kind: MyAnimeList列表项.种类 = 类型 == .anime ? .anime : .manga
        if let malID { return 作品详情目标(kind: kind, malID: malID, 标题: 标题, 封面: 封面地址) }
        func 编号(_ platform: 资料库平台) -> Int? {
            if let value = 平台ID[platform], let id = Int(value) { return id }
            guard id.hasPrefix("\(platform.rawValue)-"), let value = id.split(separator: ":").last else { return nil }
            return Int(value)
        }
        let aniList = 编号(.aniList), bangumi = 编号(.bangumi)
        guard aniList != nil || bangumi != nil else { return nil }
        return 作品详情目标(kind: kind, malID: 0, 标题: 标题, 封面: 封面地址, aniListID: aniList, bangumiID: bangumi)
    }
}

/// 动画、漫画与轻小说的详情页。外观和视觉小说详情的沉浸外观走同一套机制：
/// 封面铺满页面顶部并逐层模糊渐隐，信息卡片叠在封面下半部分，文字颜色按封面取样决定；
/// 下拉封面可以展开查看完整封面。数据由 `作品详情服务` 整合 MyAnimeList、AniList 与 Bangumi。
struct 作品详情: View {
    let 目标: 作品详情目标

    @EnvironmentObject private var myAnimeListAccount: MyAnimeList账户
    @EnvironmentObject private var parentalControls: 家长控制中心
    @ObservedObject private var library = 本地资料库.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("subTitleLang") private var subTitleLang: 副标题语言 = .none
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    @AppStorage("staffNameLang") private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var 外观: 沉浸详情外观 { 已存沉浸详情外观.平台生效值 }

    @State private var detail: 作品详细信息?
    @State private var 评分文字宽度: CGFloat = 0
    @State private var 信息区宽度: CGFloat = 0
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var comments: [视觉小说评论] = []
    @State private var isLoadingComments = false
    @State private var showsMoreInfo = false
    @State private var showsRecordSheet = false
    /// 已登录的平台都无法同步这类作品时编辑资料库，提示需要登录的平台。
    @State private var 需要登录的平台: PaperVNSync中心.资料库编辑限制?
    @Namespace private var editNamespace
    @State private var showsAllTags = false
    @State private var 标签浏览目标: 标签浏览?
    @State private var showsAllComments = false
    @State private var showsDescriptionSheet = false
    @State private var isDescriptionTruncated = false
    // 简介的显示规则与视觉小说详情相同：未看完时可模糊、设备端翻译、截断时才打开完整简介
    @AppStorage("blurDescription") private var blurDescription = false
    @AppStorage("descriptionTranslationLanguage")
    private var targetLanguage: 简介翻译语言 = .simplifiedChinese
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()
    @State private var revealDescription = false
    @State private var translatedDescription: String?
    @State private var showTranslatedDescription = false
    @State private var isTranslatingDescription = false
    @State private var descriptionTranslationConfiguration: TranslationSession.Configuration?
    /// “简介”“评分”设置改变时刷新页面。
    @State private var 设置版本 = 0
    @State private var isSaving = false
    @State private var actionError: String?
    @State private var moreCommentsPullDistance: CGFloat = 0
    @State private var moreCommentsPullIsArmed = false
    @State private var moreCommentsPullFeedbackIssued = false
    @State private var moreCommentsPullFeedback = 0

    // 沉浸外观，与视觉小说详情相同
    @State private var heroGestureIsActive = false
    @State private var heroIsExpanded = false
    @State private var viewportSize: CGSize = .zero
    @State private var divisionFrame: CGRect?
    @State private var textSamples: [String: 沉浸玻璃文字取样结果] = [:]
    @State private var textSampleURL: URL?
    @State private var textSampleGeometry: 沉浸封面文字取样几何?
    @State private var textSamplingCoordinator =
        沉浸封面文字取样任务协调器(校准名称: "作品")
    @State private var loadedHeroImage: Image?
    @State private var loadedHeroImageURL: URL?
    @State private var loadedHeroImageSize: CGSize?
    @State private var outgoingHeroImage: Image?
    @State private var heroImageTransitionProgress: CGFloat = 1
    @State private var heroImageTransitionGeneration = 0

    private var entry: 本地资料库条目? {
        library.条目.first { $0.id == 目标.作品键 }
    }

    private var 类型: 作品类型 {
        detail?.类型 ?? entry?.类型 ?? (目标.kind == .anime ? .anime : .manga)
    }

    /// 详情与资料库记录里的标题合在一起，按标题语言设置选择。
    private var 多语言标题: [用户多语言标题] {
        作品多语言标题.合并([detail?.多语言标题 ?? [], entry?.多语言标题 ?? [], 目标.多语言标题 ?? []])
    }

    /// 标题的各语言版本已经有了（详情读完，或者列表、资料库里带着）。没有时先不显示标题，免得先显示英文再换掉。
    private var 标题已确定: Bool {
        detail != nil || !(entry?.多语言标题 ?? []).isEmpty || !(目标.多语言标题 ?? []).isEmpty
    }

    private var 主标题: 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: 多语言标题,
            defaultTitle: detail?.标题 ?? 目标.标题,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    private var 标题文本: String { 主标题.text }

    /// 导航栏标题：标题确定之前留空。
    private var 导航标题文本: String { 标题已确定 ? 标题文本 : "" }

    var body: some View {
        PaperVNSenkou门控 {
            详情内容
        }
    }

    private var 详情内容: some View {
        immersiveDetail
            .navigationTitle(Text(verbatim: 导航标题文本))
            .平台柔和滚动边缘(for: .top)
            .平台隐藏导航标题占位(导航标题文本)
            .平台内联导航标题()
            .toolbar { toolbarContent }
            .task(id: 目标) { await load(forceRefresh: false) }
            .onChange(of: colorScheme) { _, _ in
                textSamples = [:]
                textSampleURL = nil
                refreshTextSamples()
            }
            .sheet(isPresented: $showsMoreInfo) {
                if let detail {
                    作品更多信息(detail: detail, 显示状态: 评分独占一行 && detail.开始日期 != nil) { showsMoreInfo = false }
                        .environmentObject(parentalControls)
                        .平台近全屏弹窗(dragIndicator: .visible)
                        // 和视觉小说详情一样，从右上角的按钮放大出来
                        .navigationTransition(.zoom(sourceID: "InfoSheet", in: editNamespace))
                }
            }
            .无法编辑资料库提示($需要登录的平台)
            .sheet(isPresented: $showsRecordSheet) {
                if let entry {
                    作品资料库编辑页面(entry: entry, title: 主标题)
                        .平台近全屏弹窗(dragIndicator: .visible)
                        .navigationTransition(.zoom(sourceID: "EditSheet", in: editNamespace))
                }
            }
            .sheet(isPresented: $showsDescriptionSheet) {
                if let 简介 = 显示简介 {
                    作品简介页面(简介: 简介) { showsDescriptionSheet = false }
                        .navigationTransition(.zoom(sourceID: "DescriptionSheet", in: editNamespace))
                }
            }
            .translationTask(descriptionTranslationConfiguration) { session in
                await translateDescription(using: session)
            }
            .onChange(of: 原始简介) { _, _ in
                translatedDescription = nil
                showTranslatedDescription = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).receive(on: RunLoop.main)) { _ in
                设置版本 += 1
            }
            .overlay(alignment: .bottom) {
                模糊解除提示(isPresented: blurRevealConfirmation.isPromptVisible)
                    .padding(.bottom, 18)
            }
            .navigationDestination(item: $标签浏览目标) { 浏览 in
                搜索(showsSearchField: false, 标签浏览: 浏览)
            }
            .navigationDestination(isPresented: $showsAllTags) {
                作品全部标签页面(
                    对象: .作品(类型),
                    类型: detail?.类型标签 ?? [],
                    标签: detail?.标签 ?? []
                )
            }
            .navigationDestination(isPresented: $showsAllComments) {
                作品评论列表页面(评论: comments)
            }
            .onChange(of: showsAllComments) { _, isPresented in
                guard !isPresented else { return }
                withAnimation(
                    reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)
                ) {
                    moreCommentsPullDistance = 0
                    moreCommentsPullIsArmed = false
                    moreCommentsPullFeedbackIssued = false
                }
            }
            .alert(
                "无法完成操作",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("好", role: .cancel) { }
            } message: {
                Text(verbatim: actionError ?? "")
            }
            .onDisappear {
                blurRevealConfirmation.cancel()
                textSamplingCoordinator.cancel()
            }
    }

    // MARK: 简介

    /// 按“简介”设置选择的简介。
    private var 当前简介: 作品详细信息.简介文本? {
        _ = 设置版本
        return detail?.简介(偏好: 简介来源.当前(类型))
    }

    /// 去掉结尾的来源说明（例如 MAL 的“[Written by MAL Rewrite]”），与视觉小说简介相同。
    private var 原始简介: String? {
        当前简介.map { 简介预览文本处理.外部显示文本($0.文本) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var 显示简介: String? {
        guard let 原始简介 else { return nil }
        return showTranslatedDescription ? translatedDescription ?? 原始简介 : 原始简介
    }

    private var 已看完或抛弃: Bool {
        entry?.状态 == .completed || entry?.状态 == .dropped
    }

    /// 简介已经是翻译目标语言时不提供翻译。
    private var 提供简介翻译: Bool {
        guard let language = 当前简介?.语言 else { return true }
        let source = Locale.Language(identifier: language)
        let target = targetLanguage.localeLanguage
        guard source.languageCode == target.languageCode else { return true }
        return source.maximalIdentifier.contains("Hant") != target.maximalIdentifier.contains("Hant")
    }

    private func requestDescriptionTranslation() {
        if translatedDescription != nil {
            withAnimation(.easeInOut(duration: 0.2)) {
                showTranslatedDescription.toggle()
            }
            return
        }
        showTranslatedDescription = true
        if var configuration = descriptionTranslationConfiguration {
            configuration.source = nil
            configuration.target = targetLanguage.localeLanguage
            configuration.invalidate()
            descriptionTranslationConfiguration = configuration
        } else {
            descriptionTranslationConfiguration = TranslationSession.Configuration(
                source: nil,
                target: targetLanguage.localeLanguage
            )
        }
    }

    private func translateDescription(using session: TranslationSession) async {
        guard let 原始简介, translatedDescription == nil else { return }
        isTranslatingDescription = true
        do {
            let response = try await session.translate(原始简介)
            translatedDescription = response.targetText
            showTranslatedDescription = true
        } catch {
            showTranslatedDescription = false
        }
        isTranslatingDescription = false
    }

    // MARK: 载入

    private func load(forceRefresh: Bool) async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        let token = myAnimeListAccount.isLoggedIn
            ? try? await myAnimeListAccount.validAccessToken()
            : nil
        do {
            let value = 目标.malID > 0
                ? try await 作品详情服务.shared.详情(
                    kind: 目标.kind,
                    malID: 目标.malID,
                    accessToken: token,
                    forceRefresh: forceRefresh
                )
                : try await 作品详情服务.shared.详情(
                    kind: 目标.kind,
                    aniListID: 目标.aniListID,
                    bangumiID: 目标.bangumiID,
                    bangumiToken: try? await PaperVNSync中心.shared.bangumi?.validAccessToken(),
                    forceRefresh: forceRefresh
                )
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                detail = value
            }
            refreshTextSamples()
            if let bangumiID = value.bangumiID {
                isLoadingComments = true
                comments = (try? await 视觉小说外部数据服务.shared.bangumiComments(
                    subjectID: bangumiID
                )) ?? []
                isLoadingComments = false
            }
        } catch {
            if detail == nil { errorMessage = error.localizedDescription }
        }
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .平台主操作) {
            recordButton
        }
        .平台可见优先级(.高)
        .平台优先纵向栏()

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .平台主操作)
        }

        ToolbarItem(placement: .平台主操作) {
            Button {
                showsMoreInfo = true
            } label: {
                工具栏圆形图标标签("更多信息", systemImage: "info.circle")
            }
            .disabled(detail == nil)
            .matchedTransitionSource(id: "InfoSheet", in: editNamespace)
        }
        .平台可见优先级(.低)
        .平台优先纵向栏()
    }

    private var 加入计划标题: String {
        类型 == .anime
            ? String(localized: "加入计划观看")
            : String(localized: "加入计划阅读")
    }

    @ViewBuilder
    private var recordButton: some View {
        if entry != nil {
            Button {
                需要登录的平台 = PaperVNSync中心.shared.需要登录才能编辑(类型)
                if 需要登录的平台 == nil { showsRecordSheet = true }
            } label: {
                工具栏圆形图标标签("编辑资料库", systemImage: "square.and.pencil")
            }
            .matchedTransitionSource(id: "EditSheet", in: editNamespace)
        } else {
            Button {
                addToPlanning()
            } label: {
                if isSaving {
                    ProgressView()
                } else {
                    工具栏圆形图标标签(加入计划标题, systemImage: "plus")
                }
            }
            .disabled(isSaving)
        }
    }

    private func addToPlanning() {
        需要登录的平台 = PaperVNSync中心.shared.需要登录才能编辑(类型)
        guard 需要登录的平台 == nil else { return }
        isSaving = true
        var entry = 本地资料库条目(
            id: 目标.作品键,
            类型: 类型,
            平台ID: 目标.平台ID,
            标题: detail?.标题 ?? 目标.标题,
            加入时间: .now
        )
        entry.状态 = .planning
        entry.封面地址 = 目标.封面
        entry.日文标题 = detail?.日文标题
        entry.多语言标题 = detail?.多语言标题
        Task {
            defer { isSaving = false }
            do {
                try await PaperVNSync中心.shared.添加(entry)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: 页面结构

    private var imageURLs: [URL] {
        [detail?.封面, 目标.封面]
            .compactMap { value -> URL? in
                guard let value,
                      let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      url.host != nil else {
                    return nil
                }
                return url
            }
            .reduce(into: []) { urls, url in
                if !urls.contains(url) { urls.append(url) }
            }
    }

    private var immersiveDetail: some View {
        let urls = imageURLs

        return ZStack {
            视觉小说详情沉浸背景(
                imageURLs: urls,
                loadedImage: loadedHeroImage,
                loadedImageURL: loadedHeroImageURL,
                outgoingImage: outgoingHeroImage,
                aspectRatio: heroSourceAspectRatio,
                transitionProgress: heroImageTransitionProgress,
                reduceMotion: reduceMotion,
                onImageLoaded: { url, image, size in
                    activateHeroImage(image, size: size, for: url)
                },
                onImageReady: { url in
                    updateTextSamples(for: url)
                }
            )
            .equatable()

            ScrollView {
                沉浸封面详情内容(
                    onGestureActivityChanged: updateHeroGestureActivity
                ) { dragContext in
                    heroAndPrimaryInformation(imageURLs: urls, dragContext: dragContext)
                        .onChange(of: dragContext.isExpanded) { _, isExpanded in
                            updateHeroExpansion(isExpanded)
                        }
                } content: {
                    failureCard
                        .padding(.horizontal, pageHorizontalPadding)

                    if let detail {
                        mediaContent(detail)
                            .transition(.opacity)
                    } else if errorMessage == nil {
                        loadingContent
                            .transition(.opacity)
                    }
                }
            }
            // 与视觉小说详情相同：在页面底部继续上拉打开全部评论
            .modifier(
                详情底部继续上划修饰器(
                    isEnabled: hasMoreComments,
                    onBegan: {
                        moreCommentsPullDistance = 0
                        moreCommentsPullIsArmed = false
                        moreCommentsPullFeedbackIssued = false
                    },
                    onChanged: updateMoreCommentsPull,
                    onEnded: finishMoreCommentsPull,
                    onSettled: {
                        showsAllComments = true
                    }
                )
            )
            .平台横向内容可溢出()
            .scrollBounceBehavior(.always, axes: .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            viewportSize = size
        }
        .沉浸详情折叠区域(读取到: $divisionFrame)
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "ImmersiveDetailScroll")
        .onPreferenceChange(视觉小说沉浸取样框PreferenceKey.self) { frames in
            updateTextSampleGeometry(from: frames)
        }
        .ignoresSafeArea(edges: .top)
        .平台沉浸导航栏()
    }

    private func heroAndPrimaryInformation(
        imageURLs: [URL],
        dragContext: 沉浸封面拖动上下文
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            hero(imageURLs: imageURLs, dragContext: dragContext)
                .ignoresSafeArea(.container, edges: .horizontal)

            let overlap = descriptionOverlap
            let cardProgress = min(max(dragContext.progress, 0), 1)
            let cardOffset = overlap * cardProgress
            primaryInformation
                .padding(.top, -overlap)
                .padding(.bottom, cardOffset)
                .compositingGroup()
                .offset(y: cardOffset)
        }
        .coordinateSpace(name: "ImmersiveDetailSampling")
    }

    // MARK: 封面

    private var pageHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    private var descriptionOverlap: CGFloat {
        horizontalSizeClass == .regular ? 154 : 82
    }

    private var heroSourceAspectRatio: CGFloat? {
        guard let size = loadedHeroImageSize,
              size.width > 0, size.height > 0 else {
            return nil
        }
        return size.width / size.height
    }

    private var 有简介: Bool {
        原始简介 != nil
    }

    /// 封面渐隐延伸到简介和标签下方的长度，与视觉小说详情一致。
    private func heroDescriptionExtension(imageURLs: [URL]) -> CGFloat {
        guard !imageURLs.isEmpty else { return 0 }
        // 详情还没载入时按有简介和标签算：载入后封面区域不再变高，封面不会跟着放大
        let hasTags = detail == nil || !显示标签.isEmpty
        guard detail == nil || 有简介 || hasTags else { return 0 }
        if horizontalSizeClass == .regular {
            return hasTags ? 284 : 120
        }
        return hasTags ? 316 : 148
    }

    private func hero(
        imageURLs: [URL],
        dragContext: 沉浸封面拖动上下文
    ) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let heroHeight = proxy.size.height
            let fadeOverflow: CGFloat = 72
            let scrollFrame = proxy.frame(in: .named("ImmersiveDetailScroll"))
            let samplingFrame = proxy.frame(in: .named("ImmersiveDetailSampling"))
            let pullDown = scrollFrame.minY.isFinite ? max(scrollFrame.minY, 0) : 0
            let descriptionExtension = heroDescriptionExtension(imageURLs: imageURLs)
            let expandedHeroHeight = expandedHeroHeight(
                width: width,
                collapsedHeight: heroHeight
            )
            let transitionProgress = min(max(dragContext.progress, 0), 1)
            let expandedImageTopInset = max(
                (viewportSize.height - expandedHeroHeight) / 2,
                0
            )
            let imageTopInset = expandedImageTopInset * transitionProgress
            let layoutHeroHeight = heroHeight
                + (expandedHeroHeight - heroHeight) * transitionProgress
            let renderedHeight = layoutHeroHeight
                + imageTopInset
                + pullDown
                + (fadeOverflow + descriptionExtension) * (1 - transitionProgress)
            let sampleImageFrame = CGRect(
                x: samplingFrame.minX,
                y: samplingFrame.minY - pullDown,
                width: width,
                height: heroHeight + fadeOverflow + descriptionExtension
            )
            let primaryInformationStart = heroHeight + 24 - descriptionOverlap + pullDown
            let regularTransitionStart = min(
                max(primaryInformationStart / renderedHeight, 0),
                1
            )

            ZStack(alignment: .top) {
                if !imageURLs.isEmpty {
                    沉浸封面拖动图层(
                        isExpanded: dragContext.isExpanded,
                        hasImage: true,
                        progress: dragContext.progressBinding,
                        onExpansionChanged: dragContext.onExpansionChanged,
                        onBounceChanged: dragContext.onBounceChanged,
                        onGestureActivityChanged: dragContext.onGestureActivityChanged,
                        onTap: nil
                    ) { pullProgress in
                        heroImagePresentation(
                            extendsThroughDescription: descriptionExtension > 0,
                            regularTransitionStart: regularTransitionStart,
                            width: width,
                            heroHeight: heroHeight,
                            renderedHeight: renderedHeight,
                            backgroundHeight: heroHeight + fadeOverflow + descriptionExtension,
                            imageTopInset: imageTopInset,
                            minimumRasterHeight: heroHeight
                                + fadeOverflow
                                + descriptionExtension
                                + 160,
                            pullProgress: pullProgress
                        )
                    }
                } else if detail == nil, errorMessage == nil {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        ProgressView()
                    }
                    .frame(width: width, height: renderedHeight)
                } else {
                    平台内容不可用视图("无封面", systemImage: "photo")
                        .frame(width: width, height: renderedHeight)
                }
            }
            .frame(width: width, height: renderedHeight)
            .offset(y: -pullDown)
            .视觉小说沉浸取样框(["image": sampleImageFrame])
        }
        .frame(height: horizontalSizeClass == .regular ? 420 : nil)
        .aspectRatio(
            horizontalSizeClass == .regular ? nil : 1 / 0.72,
            contentMode: .fit
        )
        .frame(maxWidth: .infinity)
        .padding(.bottom, heroLayoutExtension(pullProgress: dragContext.progress))
        .offset(y: -dragContext.bounceOffset)
    }

    private func heroImagePresentation(
        extendsThroughDescription: Bool,
        regularTransitionStart: CGFloat,
        width: CGFloat,
        heroHeight: CGFloat,
        renderedHeight: CGFloat,
        backgroundHeight: CGFloat,
        imageTopInset: CGFloat,
        minimumRasterHeight: CGFloat,
        pullProgress: CGFloat
    ) -> some View {
        let transitionProgress = min(max(pullProgress, 0), 1)
        let sourceAspectRatio = heroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(
            min(width - horizontalInset, heroHeight * sourceAspectRatio),
            1
        )
        let expandedHeight = max(expandedWidth / sourceAspectRatio, 1)
        let imageWidth = width + (expandedWidth - width) * transitionProgress
        let presentationHeight = backgroundHeight
            + (expandedHeight - backgroundHeight) * transitionProgress
        let cornerRadius = 28 * transitionProgress

        return rasterizedHeroImage(
            extendsThroughDescription: extendsThroughDescription,
            regularTransitionStart: regularTransitionStart,
            revealProgress: transitionProgress,
            width: imageWidth,
            renderedHeight: presentationHeight,
            minimumRasterHeight: minimumRasterHeight
        )
        .平台背景延伸效果()
        .frame(width: imageWidth, height: presentationHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .top)
        .offset(y: imageTopInset)
        .frame(width: width, height: renderedHeight, alignment: .top)
    }

    private func expandedHeroHeight(width: CGFloat, collapsedHeight: CGFloat) -> CGFloat {
        let sourceAspectRatio = heroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(
            min(width - horizontalInset, collapsedHeight * sourceAspectRatio),
            1
        )
        return max(expandedWidth / sourceAspectRatio, 1)
    }

    private func heroLayoutExtension(pullProgress: CGFloat) -> CGFloat {
        let width = viewportSize.width
        guard width > 0, viewportSize.height > 0 else { return 0 }
        let transitionProgress = min(max(pullProgress, 0), 1)
        let collapsedHeight = horizontalSizeClass == .regular ? CGFloat(420) : width * 0.72
        let expandedHeight = expandedHeroHeight(width: width, collapsedHeight: collapsedHeight)
        let expandedTopInset = max((viewportSize.height - expandedHeight) / 2, 0)
        return max(expandedTopInset + expandedHeight - collapsedHeight, 0) * transitionProgress
    }

    private func heroGradient(
        extendsThroughDescription: Bool,
        regularTransitionStart: CGFloat
    ) -> 沉浸封面渐变方案 {
        if extendsThroughDescription, horizontalSizeClass == .regular {
            return .常规(transitionStart: regularTransitionStart)
        }
        return extendsThroughDescription ? .紧凑延伸 : .紧凑标准
    }

    private func rasterizedHeroImage(
        extendsThroughDescription: Bool,
        regularTransitionStart: CGFloat,
        revealProgress: CGFloat,
        width: CGFloat,
        renderedHeight: CGFloat,
        minimumRasterHeight: CGFloat
    ) -> some View {
        let rasterBucket: CGFloat = 128
        let rasterHeight = max(
            (minimumRasterHeight / rasterBucket).rounded(.up) * rasterBucket,
            (renderedHeight / rasterBucket).rounded(.up) * rasterBucket
        )

        return ZStack(alignment: .top) {
            heroImageComposition(
                gradient: heroGradient(
                    extendsThroughDescription: extendsThroughDescription,
                    regularTransitionStart: regularTransitionStart
                ),
                revealProgress: revealProgress
            )
            .frame(width: width, height: renderedHeight)
        }
        .frame(width: width, height: rasterHeight, alignment: .top)
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .frame(width: width, height: renderedHeight, alignment: .top)
        .clipped()
    }

    /// 清晰、中等模糊、重度模糊三层封面按渐变叠加，再整体渐隐，与视觉小说详情相同。
    private func heroImageComposition(
        gradient: 沉浸封面渐变方案,
        revealProgress: CGFloat
    ) -> some View {
        let revealProgress = min(max(revealProgress, 0), 1)

        return ZStack {
            heroImageLayer(revealProgress: revealProgress)
                .mask {
                    ZStack {
                        LinearGradient(
                            stops: gradient.sharp.gradientStops,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Color.white.opacity(revealProgress)
                    }
                }

            heroImageLayer(revealProgress: revealProgress)
                .blur(radius: gradient.mediumBlurRadius)
                .mask {
                    LinearGradient(
                        stops: gradient.medium.gradientStops,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(1 - revealProgress)

            heroImageLayer(revealProgress: revealProgress)
                .blur(radius: gradient.heavyBlurRadius)
                .mask {
                    LinearGradient(
                        stops: gradient.heavy.gradientStops,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(1 - revealProgress)
        }
        .compositingGroup()
        .mask {
            ZStack {
                LinearGradient(
                    stops: gradient.fade.gradientStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
                Color.white.opacity(revealProgress)
            }
        }
    }

    @ViewBuilder
    private func heroImageLayer(revealProgress: CGFloat) -> some View {
        if loadedHeroImage != nil || outgoingHeroImage != nil {
            ZStack {
                if let outgoingHeroImage {
                    alignedHeroImage(outgoingHeroImage, revealProgress: revealProgress)
                }
                if let loadedHeroImage {
                    alignedHeroImage(loadedHeroImage, revealProgress: revealProgress)
                        .opacity(heroImageTransitionProgress)
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.3),
                            value: heroImageTransitionProgress
                        )
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    private func alignedHeroImage(_ image: Image, revealProgress: CGFloat) -> some View {
        GeometryReader { proxy in
            image
                .resizable()
                .aspectRatio(heroSourceAspectRatio, contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .offset(y: horizontalSizeClass == .regular ? -60 * (1 - revealProgress) : 0)
        }
        .clipped()
    }

    private func activateHeroImage(_ image: Image, size: CGSize, for url: URL) {
        guard shouldAcceptImage(at: url) else { return }

        let shouldCrossfade = !reduceMotion
            && loadedHeroImage != nil
            && loadedHeroImageURL != url
        let shouldFadeIn = !reduceMotion && loadedHeroImage == nil
        let shouldAnimate = shouldCrossfade || shouldFadeIn
        heroImageTransitionGeneration += 1
        let generation = heroImageTransitionGeneration

        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            outgoingHeroImage = shouldCrossfade ? loadedHeroImage : nil
            loadedHeroImage = image
            loadedHeroImageURL = url
            loadedHeroImageSize = size
            heroImageTransitionProgress = shouldAnimate ? 0 : 1
        }

        guard shouldAnimate else { return }
        Task { @MainActor in
            await Task.yield()
            guard generation == heroImageTransitionGeneration else { return }
            heroImageTransitionProgress = 1
            try? await Task.sleep(for: .seconds(0.32))
            guard generation == heroImageTransitionGeneration else { return }
            var cleanup = Transaction()
            cleanup.animation = nil
            cleanup.disablesAnimations = true
            withTransaction(cleanup) {
                outgoingHeroImage = nil
            }
        }
    }

    /// 优先显示 MAL 的大图；先载入的列表缩略图只在大图到之前顶上。
    private func shouldAcceptImage(at url: URL) -> Bool {
        let urls = imageURLs
        guard let candidate = urls.firstIndex(of: url) else { return false }
        guard let loadedHeroImageURL,
              let loaded = urls.firstIndex(of: loadedHeroImageURL) else {
            return true
        }
        return candidate <= loaded
    }

    // MARK: 文字取样

    private var currentImageURL: URL? {
        let urls = imageURLs
        if let loadedHeroImageURL, urls.contains(loadedHeroImageURL) {
            return loadedHeroImageURL
        }
        return urls.first
    }

    private func textStyle(for key: String) -> 沉浸详情文字样式 {
        沉浸详情文字样式(
            appearance: 外观,
            sample: textSamples[key],
            fallbackColorScheme: colorScheme
        )
    }

    private var systemGlassTint: Color? {
        guard 外观 == .clear, imageURLs.isEmpty else { return nil }
        return colorScheme == .dark ? .black : .white
    }

    private func updateTextSamples(for url: URL) {
        guard shouldAcceptImage(at: url),
              let geometry = textSamplingCoordinator.latestGeometry ?? textSampleGeometry else {
            return
        }
        scheduleTextSamples(for: url, geometry: geometry)
    }

    private func refreshTextSamples() {
        guard let url = currentImageURL,
              let geometry = textSamplingCoordinator.latestGeometry ?? textSampleGeometry else {
            return
        }
        scheduleTextSamples(for: url, geometry: geometry)
    }

    private func scheduleTextSamples(for url: URL, geometry: 沉浸封面文字取样几何) {
        let descriptionExtension = heroDescriptionExtension(imageURLs: imageURLs)
        // 与 hero 中静止状态（无下拉）的过渡位置一致。
        let layerHeight = max(geometry.imageSize.height, 1)
        let heroHeight = layerHeight - 72 - descriptionExtension
        let request = 沉浸封面文字取样请求(
            url: url,
            layout: .visualNovel,
            background: colorScheme == .dark ? .dark : .light,
            gradient: descriptionExtension > 0 && horizontalSizeClass == .regular
                ? .常规取样(
                    transitionStart: (heroHeight + 24 - descriptionOverlap) / layerHeight
                )
                : descriptionExtension > 0 ? .紧凑延伸 : .紧凑标准,
            itemCounts: ["tags": 内联标签.count],
            geometry: geometry
        )
        textSamplingCoordinator.submit(request) { request, samples in
            guard !heroGestureIsActive else {
                textSamplingCoordinator.cancel()
                return
            }
            guard currentImageURL == request.url,
                  shouldAcceptImage(at: request.url) else {
                return
            }
            guard textSampleURL != request.url
                    || textSamples != samples
                    || textSampleGeometry == nil else {
                return
            }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                textSampleGeometry = request.geometry
                textSamples = samples
                textSampleURL = request.url
            }
        }
    }

    private func updateTextSampleGeometry(from frames: [String: CGRect]) {
        guard let imageFrame = frames["image"],
              视觉小说沉浸取样框有效(imageFrame) else {
            return
        }

        func snapped(_ value: CGFloat) -> CGFloat {
            (value * 2).rounded() / 2
        }

        var regions: [String: CGRect] = [:]
        for (key, frame) in frames where key != "image" {
            let relative = frame.offsetBy(dx: -imageFrame.minX, dy: -imageFrame.minY)
            let snappedFrame = CGRect(
                x: snapped(relative.minX),
                y: snapped(relative.minY),
                width: snapped(relative.width),
                height: snapped(relative.height)
            )
            guard 视觉小说沉浸取样框有效(snappedFrame) else { continue }
            regions[key] = snappedFrame
        }

        let geometry = 沉浸封面文字取样几何(
            imageSize: CGSize(width: imageFrame.width, height: imageFrame.height),
            regions: regions,
            viewportSize: viewportSize,
            contentOffsetY: horizontalSizeClass == .regular ? -60 : 0,
            封面已展开: heroIsExpanded
        )
        guard textSamplingCoordinator.latestGeometry != geometry else { return }
        textSamplingCoordinator.remember(geometry)
        guard !heroGestureIsActive, let url = currentImageURL else { return }
        scheduleTextSamples(for: url, geometry: geometry)
    }

    /// 下拉展开或收起封面时，信息卡片背后的背景整个换掉，需要按新的状态重新取样。
    private func updateHeroExpansion(_ isExpanded: Bool) {
        guard heroIsExpanded != isExpanded else { return }
        heroIsExpanded = isExpanded
        guard var geometry = textSamplingCoordinator.latestGeometry ?? textSampleGeometry else {
            return
        }
        geometry.封面已展开 = isExpanded
        textSamplingCoordinator.remember(geometry)
        guard !heroGestureIsActive, let url = currentImageURL else { return }
        scheduleTextSamples(for: url, geometry: geometry)
    }

    private func updateHeroGestureActivity(_ isActive: Bool) {
        guard heroGestureIsActive != isActive else { return }
        heroGestureIsActive = isActive
        if isActive {
            textSamplingCoordinator.cancel()
        } else {
            refreshTextSamples()
        }
    }

    // MARK: 主要信息

    private var primaryInformation: some View {
        let showsDescriptionCard = 有简介 || detail == nil

        return VStack(alignment: .leading, spacing: 沉浸详情布局.主要信息间距) {
            if horizontalSizeClass == .regular {
                沉浸详情等高双栏布局(
                    spacing: 16,
                    divisionFrame: divisionFrame,
                    horizontalInset: pageHorizontalPadding
                ) {
                    metadata(fillsAvailableHeight: showsDescriptionCard)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if showsDescriptionCard {
                        descriptionContent(fillsAvailableHeight: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, pageHorizontalPadding)
            } else {
                metadata()
                    .padding(.horizontal, pageHorizontalPadding)

                if showsDescriptionCard {
                    descriptionContent()
                        .padding(.horizontal, pageHorizontalPadding)
                }
            }

            if !显示标签.isEmpty {
                inlineTags
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadata(fillsAvailableHeight: Bool = false) -> some View {
        let style = textStyle(for: "metadata")

        return VStack(alignment: .leading, spacing: fillsAvailableHeight ? 0 : 14) {
            titleContent

            if fillsAvailableHeight {
                Spacer(minLength: 14)
            }

            if let detail {
                stats(detail)
                    .沉浸详情文字阴影(style)
            } else {
                loadingStats
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
        .沉浸详情玻璃背景(
            外观,
            sample: style.sample,
            fallbackTint: systemGlassTint,
            usesBrightReducedMaterial: true,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .视觉小说沉浸取样框(["metadata"])
    }

    /// 长按标题时可以拷贝的各语言标题，和视觉小说详情一致：按日文、简体中文、繁体中文、韩文、英文、罗马字列出。
    private var 标题拷贝项目: [(label: String, value: String)] {
        let accepted = 多语言标题.filter { allowUnofficialTitles || $0.official }
        var items: [(label: String, value: String)] = []
        func append(_ label: String, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
                  !items.contains(where: { $0.label == label }) else { return }
            items.append((label, value))
        }
        let languages: [标题语言] = [.japanese, .chinese, .traditionalChinese, .korean, .english]
        for language in languages {
            guard let code = language.langCode else { continue }
            append(String(localized: "拷贝\(language.localizedTitle)标题"), accepted.first { $0.lang == code }?.title)
        }
        let romanized = accepted.first { $0.main && !($0.latin ?? "").isEmpty } ?? accepted.first { !($0.latin ?? "").isEmpty }
        append(String(localized: "拷贝\(标题语言.romanized.localizedTitle)标题"), romanized?.latin)
        if items.isEmpty {
            append(String(localized: "拷贝标题"), 标题文本)
        }
        return items
    }

    /// 副标题按“副标题语言”设置显示，和视觉小说详情一致。
    private var 副标题: 标题工具.标题结果? {
        标题工具.获取副标题(
            titles: 多语言标题,
            defaultTitle: detail?.标题 ?? 目标.标题,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            副标题设置: subTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    private var titleContent: some View {
        let style = textStyle(for: "metadata.title")

        return VStack(alignment: .leading, spacing: 4) {
            Text(
                标题工具.生成富文本(
                    文本: 标题文本,
                    isJapanese: 主标题.isJapanese,
                    基础大小: 22,
                    是粗体: true,
                    日文字体名称: "HiraginoSans-W6",
                    系统字体粗细: .bold,
                    语言代码: 主标题.languageCode
                )
            )
            .沉浸详情文字前景色(style.primary, style: style)
            .lineLimit(2)
            // 标题确定之前占着位置但不显示，读完后淡入
            .opacity(标题已确定 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: 标题已确定)
            .contextMenu {
                ForEach(标题拷贝项目, id: \.label) { item in
                    Button {
                        UIPasteboard.general.string = item.value
                    } label: {
                        Label {
                            Text(verbatim: item.label)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            }

            if let 副标题 {
                Text(
                    标题工具.生成富文本(
                        文本: 副标题.text,
                        isJapanese: 副标题.isJapanese,
                        基础大小: 15,
                        语言代码: 副标题.languageCode
                    )
                )
                .沉浸详情文字前景色(style.secondary, style: style)
                .fontWeight(.regular)
                .lineLimit(2)
            }
        }
        // 按文字实际占的宽度取样，不含标题右侧的空白。
        .视觉小说沉浸取样框(["metadata.title"])
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(style)
    }

    private var loadingStats: some View {
        let style = textStyle(for: "loading")

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                metadataItem(icon: "chart.bar.xaxis", title: "评分", text: "8.50（999人评分）", style: style)
                metadataItem(icon: "clock", title: "篇幅", text: "正在载入…", style: style)
            }
            VStack(alignment: .leading, spacing: 8) {
                metadataItem(icon: "calendar", title: "发行日期", text: "正在载入…", style: style)
                metadataItem(icon: "checkmark.circle", title: "状态", text: "正在载入…", style: style)
            }
            .padding(.leading, 6)
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
    }

    /// 评分文字缩到最小（0.82）仍放不下半栏时（热门动画的评分人数很多），评分独占一行，放送状态移到“更多信息”。
    private var 评分独占一行: Bool {
        guard 评分文字宽度 > 0, 信息区宽度 > 0 else { return false }
        // 两栏间距 10，每栏左侧是 18 宽的图标和 9 的间距
        let columnTextWidth = (信息区宽度 - 10) / 2 - 18 - 9
        return 评分文字宽度 * 0.82 > columnTextWidth
    }

    private func stats(_ detail: 作品详细信息) -> some View {
        let rowSpacing: CGFloat = horizontalSizeClass == .regular ? 14 : 8
        // AniList 只有人气没有评分人数，不计入人数
        let 已选平台 = 评分设置.已选平台(detail.类型)
        let 评分人数 = [
            已选平台.contains(.myAnimeList) && detail.MAL评分 != nil ? detail.MAL评分人数 : nil,
            已选平台.contains(.bangumi) && detail.Bangumi评分 != nil ? detail.Bangumi评分人数 : nil,
            已选平台.contains(.tmdb) && detail.TMDB评分 != nil ? detail.TMDB评分人数 : nil
        ].compactMap { $0 }
        let voteText = 评分人数.isEmpty
            ? nil
            : String(localized: "\(评分人数.reduce(0, +))人评分")
        let ratingText = detail.综合评分.map { score in
            let value = String(format: "%.2f", score.分数)
            return voteText.map { "\(value)（\($0)）" } ?? value
        }

        let rating = ratingText.map { text in
            metadataItem(
                icon: "chart.bar.xaxis",
                title: "评分",
                text: text,
                valueLineLimit: 1,
                valueMinimumScaleFactor: 0.82,
                style: textStyle(for: "metadata.rating"),
                sampleKey: "metadata.rating"
            )
        }
        let length = metadataItem(
            icon: "clock",
            title: "篇幅",
            text: Self.篇幅(detail) ?? String(localized: "未知"),
            style: textStyle(for: "metadata.length"),
            sampleKey: "metadata.length"
        )
        let release = detail.开始日期.map { 日期 in
            metadataItem(
                icon: "calendar",
                title: detail.kind == .anime ? "放送开始" : "连载开始",
                text: 日期,
                style: textStyle(for: "metadata.release"),
                sampleKey: "metadata.release"
            )
        }
        let status = metadataItem(
            icon: "checkmark.circle",
            title: detail.kind == .anime ? "放送状态" : "连载状态",
            text: Self.状态文本(detail),
            style: textStyle(for: "metadata.status"),
            sampleKey: "metadata.status"
        )

        return Group {
            if 评分独占一行, let rating {
                VStack(alignment: .leading, spacing: rowSpacing) {
                    rating
                    HStack(alignment: .top, spacing: 10) {
                        length
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Group {
                            if let release { release } else { status }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 6)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        rating
                        length
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: rowSpacing) {
                        release
                        status
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                }
            }
        }
        // 量出评分文字原本的宽度和信息区的宽度，决定评分是否独占一行
        .background(alignment: .topLeading) {
            if let ratingText {
                Text(verbatim: ratingText)
                    .font(.subheadline.weight(.regular))
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { 评分文字宽度 = $0 }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { 信息区宽度 = $0 }
    }

    static func 状态文本(_ detail: 作品详细信息) -> String {
        detail.状态.flatMap(发行状态) ?? String(localized: "未知")
    }

    private func metadataItem(
        icon: String,
        title: LocalizedStringKey,
        text: String,
        valueLineLimit: Int = 2,
        valueMinimumScaleFactor: CGFloat = 1,
        style: 沉浸详情文字样式,
        sampleKey: String? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.subheadline)
                .沉浸详情文字前景色(style.secondary, style: style)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .沉浸详情文字前景色(style.tertiary, style: style)

                Text(verbatim: text)
                    .font(.subheadline.weight(.regular))
                    .沉浸详情文字前景色(style.primary, style: style)
                    .lineLimit(valueLineLimit)
                    .minimumScaleFactor(valueMinimumScaleFactor)
                    .allowsTightening(valueLineLimit == 1)
            }
        }
        .视觉小说沉浸取样框(sampleKey.map { [$0] } ?? [])
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(style)
    }

    private func descriptionText(_ text: String, style: 沉浸详情文字样式) -> some View {
        简介预览文本视图(
            text: text,
            lineLimit: 7,
            onTruncationChange: { isDescriptionTruncated = $0 }
        )
        .font(.body)
        .沉浸详情文字前景色(style.primary, style: style)
        .contentTransition(.opacity)
    }

    private func descriptionContent(fillsAvailableHeight: Bool = false) -> some View {
        let style = textStyle(for: "description.text")
        let 简介 = 显示简介
        let isHidden = blurDescription && !已看完或抛弃 && !revealDescription

        return Group {
            if let 简介 {
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if isHidden {
                            descriptionText(简介, style: style)
                                .textSelection(.disabled)
                                .blur(radius: 7)
                        } else {
                            descriptionText(简介, style: style)
                                .textSelection(.enabled)
                        }
                    }
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if 提供简介翻译 {
                        Button {
                            requestDescriptionTranslation()
                        } label: {
                            if isTranslatingDescription {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "translate")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(showTranslatedDescription ? Color.blue : style.secondary)
                        .accessibilityLabel(showTranslatedDescription ? "显示简介原文" : "翻译简介")
                    }
                }
                .沉浸详情文字阴影(style)
            } else {
                简介预览文本视图(
                    text: String(repeating: "正在载入", count: 96),
                    lineLimit: 5
                )
                .font(.body)
                .opacity(0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .topLeading)
        .沉浸详情玻璃背景(
            外观,
            sample: style.sample,
            fallbackTint: systemGlassTint,
            usesBrightReducedMaterial: true,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .matchedTransitionSource(id: "DescriptionSheet", in: editNamespace)
        .onTapGesture {
            guard 简介 != nil else { return }
            if isHidden {
                blurRevealConfirmation.request(id: "description") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        revealDescription = true
                    }
                }
            } else if isDescriptionTruncated {
                showsDescriptionSheet = true
            }
        }
        .allowsHitTesting(简介 != nil)
        .视觉小说沉浸取样框(["description", "description.text"])
    }

    // MARK: 标签

    /// MAL 的类型和 AniList 的非剧透、非色情标签，按名称去重；色情标签只在全部标签页面按内容限制设置显示。
    private var 显示标签: [String] {
        guard let detail else { return [] }
        return Self.去重(detail.类型标签 + detail.标签.filter { !$0.是剧透 && !$0.是成人 }.map(\.名称))
    }

    private var 剧透标签: [String] {
        guard let detail else { return [] }
        let shown = Set(显示标签.map { $0.lowercased() })
        return Self.去重(detail.标签.filter { $0.是剧透 || $0.是成人 }.map(\.名称))
            .filter { !shown.contains($0.lowercased()) }
    }

    private var 内联标签: [String] {
        Array(显示标签.prefix(
            horizontalSizeClass == .regular
                ? 沉浸详情布局.常规内联标签上限
                : 沉浸详情布局.紧凑内联标签上限
        ))
    }

    /// 内联标签按住时的“查看带有此标签的…”：能筛选的类型与标签，作为结果页“+”菜单的候选。
    private var 可筛选标签: [标签浏览.标签] {
        var seen = Set<String>()
        return 显示标签.compactMap(浏览标签).filter { seen.insert($0.值).inserted }
    }

    private func 浏览标签(_ name: String) -> 标签浏览.标签? {
        作品浏览筛选.筛选值(类型或标签: name).map {
            标签浏览.标签(值: $0, 名称: AniList标签.显示名称(name))
        }
    }

    private var inlineTags: some View {
        let style = textStyle(for: "tags")
        let tags = 内联标签
        let hasMore = 显示标签.count > tags.count || !剧透标签.isEmpty
        let 全部 = 可筛选标签

        return 沉浸标签两行布局(spacing: 8, forcePlaceMoreButton: hasMore) {
            ForEach(Array(tags.enumerated()), id: \.element) { index, tag in
                let itemStyle = textStyle(for: "tags.item.\(index)")
                Text(verbatim: AniList标签.显示名称(tag))
                    .font(.caption.weight(.semibold))
                    .沉浸详情文字前景色(itemStyle.capsule, style: itemStyle)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .沉浸详情文字阴影(itemStyle)
                    .高透明提亮材质背景(in: Capsule())
                    .视觉小说沉浸取样框(["tags.item.\(index)"])
                    .标签浏览菜单(浏览标签(tag), 对象: .作品(类型), 全部: 全部, 目标: $标签浏览目标)
            }

            Button {
                showsAllTags = true
            } label: {
                HStack(spacing: 6) {
                    Text("更多")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .frame(width: 12, height: 12)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .高透明提亮材质背景(in: Capsule())
            }
            .buttonStyle(详情更多入口按钮样式())
            .沉浸详情文字前景色(style.capsule, style: style)
            .沉浸详情文字阴影(style)
            .contentShape(Capsule())
            .accessibilityLabel("查看更多标签")
        }
        .padding(.horizontal, pageHorizontalPadding)
    }

    // MARK: 下方内容

    @ViewBuilder
    private var failureCard: some View {
        if let errorMessage, detail == nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("无法载入", systemImage: "exclamationmark.triangle")
                    .font(.headline)

                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("重试") {
                    Task { await load(forceRefresh: true) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .沉浸详情玻璃(
                外观,
                fallbackTint: systemGlassTint,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
    }

    private var loadingContent: some View {
        VStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: index == 0 ? 190 : 260)
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
    }

    @ViewBuilder
    private func mediaContent(_ detail: 作品详细信息) -> some View {
        if !detail.角色.isEmpty {
            horizontalSection("角色") {
                ForEach(detail.角色) { character in
                    // 角色来自 AniList，点按打开角色详情（出场作品与声优）
                    NavigationLink {
                        AniList人物详情(人物: AniList人物(
                            种类: .角色,
                            anilistID: character.id,
                            名字: character.名字,
                            原名: character.原名,
                            图片: character.图片,
                            作品: nil
                        ))
                        .navigationTransition(.zoom(sourceID: "character-\(character.id)", in: editNamespace))
                    } label: {
                    // 角色名、声优名与视觉小说详情一样按“制作人员语言”设置显示
                    mediaCard(
                        imageURL: character.图片,
                        // 与视觉小说详情的角色卡片相同：日文用冬青黑体 W6，其他文字用系统粗体
                        title: 标题工具.生成富文本(
                            文本: 人物名称工具.显示名称(name: character.名字, original: character.原名, 偏好: staffNameLang),
                            isJapanese: staffNameLang == .original,
                            基础大小: 14,
                            是粗体: true,
                            日文字体名称: "HiraginoSans-W6",
                            系统字体粗细: .bold,
                            语言来源已知: false,
                            空格视为日语: true
                        ),
                        subtitle: character.声优.map {
                            人物名称工具.生成富文本(
                                name: $0,
                                original: character.声优原名,
                                偏好: staffNameLang,
                                基础大小: 12,
                                系统字体粗细: .medium
                            )
                        }
                    )
                    .matchedTransitionSource(id: "character-\(character.id)", in: editNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if !detail.相关.isEmpty {
            horizontalSection("相关") {
                ForEach(detail.相关) { related in
                    // 不用 NavigationLink(value:)：Today 等导航栈没有注册作品详情目标，点按没有反应
                    NavigationLink {
                        作品详情(目标: 作品详情目标(
                            kind: related.kind,
                            malID: related.malID,
                            标题: related.标题,
                            封面: related.封面,
                            多语言标题: related.多语言标题
                        ))
                        .navigationTransition(.zoom(sourceID: "related-\(related.id)", in: editNamespace))
                    } label: {
                        mediaCard(
                            imageURL: related.封面,
                            title: 相关作品标题(related),
                            subtitle: related.关系.isEmpty ? nil : AttributedString(related.关系)
                        )
                        .matchedTransitionSource(id: "related-\(related.id)", in: editNamespace)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if detail.bangumiID != nil {
            commentsSection
        }
    }

    private func horizontalSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, pageHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    content()
                }
                .padding(.vertical, 6)
            }
            .contentMargins(.horizontal, pageHorizontalPadding, for: .scrollContent)
            .scrollClipDisabled()
        }
    }

    /// 相关作品的标题按标题语言设置选择，字体规则与视觉小说详情的相关卡片相同。
    private func 相关作品标题(_ related: 作品详细信息.相关作品) -> AttributedString {
        let title = 标题工具.获取主标题(
            titles: related.多语言标题,
            defaultTitle: related.标题,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
        return 标题工具.生成富文本(
            文本: title.text,
            isJapanese: title.isJapanese,
            基础大小: 14,
            是粗体: true,
            日文字体名称: "HiraginoSans-W6",
            系统字体粗细: .bold,
            语言代码: title.languageCode
        )
    }

    /// 与视觉小说详情的角色、相关卡片相同：图片铺满，底部渐暗后叠文字。
    private func mediaCard(imageURL: String?, title: AttributedString, subtitle: AttributedString?) -> some View {
        let cardWidth = 沉浸详情布局.媒体卡片宽度
        let cardHeight = 沉浸详情布局.媒体卡片高度
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)

        return ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: imageURL.flatMap(URL.init(string:)), contentMode: .fill)
                .frame(width: cardWidth, height: cardHeight)
                .background(Color.secondary.opacity(0.12))
                .clipShape(shape)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.24), location: 0.64),
                    .init(color: .black.opacity(0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(shape)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(shape)
        .overlay {
            shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
        .contentShape(shape)
    }

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("评论")
                    .font(.title2.weight(.bold))
                Spacer()
                if isLoadingComments {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if comments.isEmpty {
                if isLoadingComments {
                    ForEach(0..<评论卡片布局.预览条数, id: \.self) { 序号 in
                        评论加载占位卡片(序号: 序号)
                    }
                } else {
                    Text("无评论")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(comments.prefix(评论卡片布局.预览条数)) { comment in
                    评论卡片(评论: comment, 预先布局完整正文: false)
                }

                if hasMoreComments {
                    上拉查看全部评论提示(
                        剩余条数: comments.count - 评论卡片布局.预览条数,
                        拖动距离: moreCommentsPullDistance,
                        已到阈值: moreCommentsPullIsArmed,
                        反馈次数: moreCommentsPullFeedback
                    ) {
                        showsAllComments = true
                    }
                }
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
    }

    private var hasMoreComments: Bool {
        comments.count > 评论卡片布局.预览条数
    }

    private func updateMoreCommentsPull(distance: CGFloat) {
        moreCommentsPullDistance = min(max(distance, 0), 视觉小说评论入口拖动参数.最大视觉距离)
        moreCommentsPullIsArmed = distance >= 视觉小说评论入口拖动参数.阈值
        if moreCommentsPullIsArmed, !moreCommentsPullFeedbackIssued {
            moreCommentsPullFeedbackIssued = true
            moreCommentsPullFeedback += 1
        }
    }

    /// 返回 true 表示要打开全部评论，由修饰器在回弹归位后打开。
    private func finishMoreCommentsPull() -> Bool {
        if moreCommentsPullIsArmed {
            if !moreCommentsPullFeedbackIssued {
                moreCommentsPullFeedbackIssued = true
                moreCommentsPullFeedback += 1
            }
            moreCommentsPullDistance = 视觉小说评论入口拖动参数.阈值
            return true
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            moreCommentsPullDistance = 0
            moreCommentsPullIsArmed = false
        }
        moreCommentsPullFeedbackIssued = false
        return false
    }

    // MARK: 文案

    /// 按显示名称去重：MAL 的“Medical”和 AniList 的“Medicine”翻译后都是“医疗”。
    private static func 去重(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert(AniList标签.显示名称($0).lowercased()).inserted }
    }

    private static func 发行状态(_ value: String) -> String? {
        switch value {
        case "finished_airing", "finished": String(localized: "已完结")
        case "currently_airing": String(localized: "放送中")
        case "currently_publishing": String(localized: "连载中")
        case "not_yet_aired", "not_yet_published": String(localized: "未开始")
        case "on_hiatus": String(localized: "休刊")
        case "discontinued": String(localized: "已中止")
        default: nil
        }
    }

    private static func 篇幅(_ detail: 作品详细信息) -> String? {
        if detail.kind == .anime {
            switch (detail.集数, detail.单集分钟) {
            case let (episodes?, minutes?): return String(localized: "\(episodes)话 × \(minutes)分钟")
            // 和漫画的“%lld话”中文相同，但其他语言是“集”，用单独的键
            case let (episodes?, nil): return String(localized: "动画话数", defaultValue: "\(episodes)话")
            default: return nil
            }
        }
        let parts = [
            detail.卷数.map { String(localized: "\($0)卷") },
            detail.话数.map { String(localized: "\($0)话") },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// 编辑资料库里这部作品的状态和进度，修改会经 PaperVN Sync 写回 MyAnimeList。

/// 完整简介，来源按“简介”设置选择。
private struct 作品简介页面: View {
    let 简介: String
    let closeAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(verbatim: 简介)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("简介")
            .仅顶部可下拉关闭()
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: closeAction) {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
        }
        .平台近全屏弹窗(dragIndicator: .visible)
    }
}

/// 全部标签：MAL 的类型在最前，AniList 标签按分类分组、组内按相关度排序；剧透与色情标签原位模糊，轻点两次显示。
private struct 作品全部标签页面: View {
    private struct 分组: Identifiable {
        let 分类: String
        let 标签: [作品详细信息.标签]
        var id: String { 分类 }
    }

    let 对象: 标签浏览.种类
    let 类型: [String]
    let 标签: [作品详细信息.标签]

    @Environment(\.详情内容限制方式覆盖)
    private var contentRestrictionMethodOverride
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var storedContentRestrictionMethod: 内容限制方式 = .blurred

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var revealedTagIDs: Set<String> = []
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()
    @State private var 多选 = 标签多选()

    /// AniList 分类的显示顺序，表外的分类排在后面。
    private static let 分类顺序 = ["Theme", "Setting", "Cast", "Demographic", "Technical", "Sexual Content"]

    private var contentRestrictionMethod: 内容限制方式 {
        contentRestrictionMethodOverride ?? storedContentRestrictionMethod
    }

    private var 显示类型: [String] {
        var seen = Set<String>()
        return 类型.filter { seen.insert(AniList标签.显示名称($0).lowercased()).inserted }
    }

    private var 分组列表: [分组] {
        var seen = Set(显示类型.map { AniList标签.显示名称($0).lowercased() })
        let visible = 标签.filter { tag in
            !(isAdultRestricted(tag) && contentRestrictionMethod == .hidden)
                && seen.insert(AniList标签.显示名称(tag.名称).lowercased()).inserted
        }
        var groups: [String: [作品详细信息.标签]] = [:]
        for tag in visible {
            groups[tag.分类 ?? "", default: []].append(tag)
        }
        return groups.keys
            .sorted { lhs, rhs in
                let l = Self.分类顺序.firstIndex(of: lhs) ?? Self.分类顺序.count
                let r = Self.分类顺序.firstIndex(of: rhs) ?? Self.分类顺序.count
                return l == r ? lhs < rhs : l < r
            }
            .map { key in
                分组(分类: key, 标签: groups[key, default: []].sorted { ($0.相关度 ?? 0) > ($1.相关度 ?? 0) })
            }
    }

    var body: some View {
        let groups = 分组列表

        平台滚动页面 {
            if !显示类型.isEmpty {
                Section("类型") {
                    标签分栏(items: 显示类型, id: \.self, columns: 标签相关度行.列数(horizontalSizeClass)) { name in
                        let tag = 浏览标签(name)
                        标签相关度行(
                            名称: AniList标签.显示名称(name),
                            选中: 多选.正在选择 ? tag.map { 多选.选中($0.值) } : nil,
                            可轻点: tag != nil
                        )
                        .onTapGesture {
                            guard let tag else { return }
                            withAnimation(.snappy(duration: 0.2)) {
                                多选.轻点(tag, 对象: 对象, 全部: 可筛选标签)
                            }
                        }
                    }
                }
            }

            ForEach(groups) { group in
                Section {
                    标签分栏(
                        items: group.标签,
                        id: \.id,
                        columns: 标签相关度行.列数(horizontalSizeClass)
                    ) { tag in
                        let blurred = shouldBlur(tag)
                        let filterTag = 浏览标签(tag.名称)
                        标签相关度行(
                            名称: AniList标签.显示名称(tag.名称),
                            数值文本: tag.相关度.map { "\($0)%" },
                            已模糊: blurred,
                            选中: 多选.正在选择 && !blurred ? filterTag.map { 多选.选中($0.值) } : nil,
                            可轻点: filterTag != nil
                        )
                        .onTapGesture {
                            guard blurred else {
                                guard let filterTag else { return }
                                withAnimation(.snappy(duration: 0.2)) {
                                    多选.轻点(filterTag, 对象: 对象, 全部: 可筛选标签)
                                }
                                return
                            }
                            guard 内容安全限制判定.允许手动解除模糊(色情限制: isAdultRestricted(tag)) else { return }
                            blurRevealConfirmation.request(id: "all-tags") {
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    revealedTagIDs.formUnion(
                                        标签
                                            .filter { 内容安全限制判定.允许手动解除模糊(色情限制: isAdultRestricted($0)) }
                                            .map(\.id)
                                    )
                                }
                            }
                        }
                    }
                } header: {
                    Text(verbatim: group.分类.isEmpty ? String(localized: "其他") : AniList标签.分类名称(group.分类))
                }
            }
        }
        .平台分组列表样式()
        .支持标签多选($多选, 对象: 对象, 全部: 可筛选标签)
        .navigationTitle("标签")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .overlay(alignment: .bottom) {
            模糊解除提示(isPresented: blurRevealConfirmation.isPromptVisible)
                .padding(.bottom, 18)
        }
        .onDisappear {
            blurRevealConfirmation.cancel()
        }
    }

    private func isAdultRestricted(_ tag: 作品详细信息.标签) -> Bool {
        内容安全限制判定.色情标签需要限制(tag.是成人, enabled: contentFilterEnabled, mode: filterMode)
    }

    /// 能用来筛选的类型或标签；Bangumi 的用户标签和 MAL 独有的类型为 nil。
    private func 浏览标签(_ name: String) -> 标签浏览.标签? {
        作品浏览筛选.筛选值(类型或标签: name).map {
            标签浏览.标签(值: $0, 名称: AniList标签.显示名称(name))
        }
    }

    /// 按页面上的顺序，能筛选且没有模糊的类型与标签：结果页“+”菜单的候选。MAL 的两个类型对应同一个时只留一个。
    private var 可筛选标签: [标签浏览.标签] {
        var seen = Set<String>()
        let names = 显示类型 + 分组列表.flatMap(\.标签).filter { !shouldBlur($0) }.map(\.名称)
        return names.compactMap(浏览标签).filter { seen.insert($0.值).inserted }
    }

    private func shouldBlur(_ tag: 作品详细信息.标签) -> Bool {
        guard !revealedTagIDs.contains(tag.id) else { return false }
        return tag.是剧透 || (isAdultRestricted(tag) && contentRestrictionMethod == .blurred)
    }
}

/// 全部 Bangumi 吐槽。
private struct 作品评论列表页面: View {
    let 评论: [视觉小说评论]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(评论) { comment in
                    评论卡片(评论: comment)
                }
            }
            .padding(16)
        }
        .background(Color.平台分组背景.ignoresSafeArea())
        .navigationTitle("评论")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
    }
}

/// “更多信息”：制作、连载、原作、分级、制作人员与外部链接，排列方式与视觉小说详情相同。
private struct 作品更多信息: View {
    private struct 外部浏览目标: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    /// 同一职位的制作人员，括号里的集数等作为备注。
    private struct 职位分组: Identifiable {
        let 职位: String
        var 成员: [(人员: 作品详细信息.人员, 备注: String?)]
        var id: String { 职位 }
    }

    @AppStorage("staffNameLang") private var staffNameLang: 制作人员语言 = .romaji
    let detail: 作品详细信息
    /// 详情页的评分独占一行、没有位置显示放送状态时，在这里显示。
    var 显示状态 = false
    let closeAction: () -> Void
    @EnvironmentObject private var parentalControls: 家长控制中心
    @State private var expandedStaffRoles: Set<String> = []
    @State private var externalBrowserTarget: 外部浏览目标?

    var body: some View {
        NavigationStack {
            平台滚动页面 {
                Section {
                    if let 媒体类型 = detail.媒体类型 {
                        LabeledContent("媒体类型") { Text(verbatim: Self.媒体类型名称(媒体类型)) }
                    }
                    if let 原作 = detail.原作 {
                        LabeledContent("原作") { Text(verbatim: Self.原作名称(原作)) }
                    }
                    if 显示状态 {
                        LabeledContent(detail.kind == .anime ? "放送状态" : "连载状态") {
                            Text(verbatim: 作品详情.状态文本(detail))
                        }
                    }
                    if let 分级 = detail.年龄分级 {
                        // MAL 的分级代码（g、pg_13、r+）写成通常的形式
                        LabeledContent("年龄分级") { Text(verbatim: 分级.replacingOccurrences(of: "_", with: "-").uppercased()) }
                    }
                }

                if !detail.制作.isEmpty {
                    Section(detail.kind == .anime ? "动画制作" : "作者") {
                        ForEach(detail.制作, id: \.self) { name in
                            HStack(spacing: 12) {
                                Image(systemName: detail.kind == .anime ? "building.2" : "person")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(verbatim: name)
                            }
                        }
                    }
                }
                if !detail.连载.isEmpty {
                    Section("连载") {
                        ForEach(detail.连载, id: \.self) { name in
                            HStack(spacing: 12) {
                                Image(systemName: "newspaper")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                Text(verbatim: name)
                            }
                        }
                    }
                }
                staffSection
                externalLinksSection
            }
            .平台分组列表样式()
            .仅顶部可下拉关闭()
            .navigationTitle("更多信息")
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .平台关闭操作) {
                    Button(action: closeAction) {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
        }
        .sheet(item: $externalBrowserTarget) { target in
            内置Safari浏览器(url: target.url)
                .平台近全屏弹窗()
        }
    }

    /// MAL 的媒体类型（tv、movie、light_novel），MAL 拿不到时是 AniList 的格式（TV、MOVIE、NOVEL）。
    private static func 媒体类型名称(_ value: String) -> String {
        switch value.lowercased() {
        case "tv", "tv_short": "TV"
        case "movie": String(localized: "剧场版")
        case "ova": "OVA"
        case "ona": "ONA"
        case "special": String(localized: "特别篇")
        case "tv_special": String(localized: "电视特别篇")
        case "music": String(localized: "音乐")
        case "cm": String(localized: "广告")
        case "pv": "PV"
        case "manga": String(localized: "漫画")
        case "light_novel": String(localized: "轻小说")
        case "novel": String(localized: "小说")
        case "one_shot": String(localized: "短篇")
        case "doujinshi": String(localized: "同人志")
        case "manhwa": String(localized: "韩国漫画")
        case "manhua": String(localized: "中国漫画")
        case "oel": String(localized: "原创英文漫画")
        default: value.replacingOccurrences(of: "_", with: " ").uppercased()
        }
    }

    /// MAL 与 AniList 的原作类型。
    private static func 原作名称(_ value: String) -> String {
        switch value.lowercased() {
        case "original": String(localized: "原创")
        case "manga": String(localized: "漫画")
        case "4_koma_manga": String(localized: "四格漫画")
        case "web_manga": String(localized: "网络漫画")
        case "digital_manga": String(localized: "电子漫画")
        case "novel": String(localized: "小说")
        case "light_novel": String(localized: "轻小说")
        case "web_novel": String(localized: "网络小说")
        case "visual_novel": String(localized: "视觉小说")
        case "game", "video_game": String(localized: "游戏")
        case "card_game": String(localized: "卡牌游戏")
        case "book": String(localized: "书籍")
        case "picture_book": String(localized: "绘本")
        case "radio": String(localized: "广播")
        case "music": String(localized: "音乐")
        case "mixed_media", "multimedia_project": String(localized: "跨媒体企划")
        case "doujinshi": String(localized: "同人志")
        case "anime": String(localized: "动画")
        case "live_action": String(localized: "真人作品")
        case "other": String(localized: "其他")
        default: value.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// 按职位分组，组的顺序沿用 AniList 的相关度排序。
    private var 职位分组列表: [职位分组] {
        var groups: [职位分组] = []
        for person in detail.制作人员 {
            let (role, note) = AniList职位.拆分(person.职责)
            if let index = groups.firstIndex(where: { $0.职位 == role }) {
                groups[index].成员.append((person, note))
            } else {
                groups.append(职位分组(职位: role, 成员: [(person, note)]))
            }
        }
        return groups
    }

    @ViewBuilder
    private var staffSection: some View {
        let groups = 职位分组列表
        if !groups.isEmpty {
            Section("制作人员") {
                ForEach(groups) { group in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedStaffRoles.contains(group.职位) },
                            set: { isExpanded in
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    if isExpanded {
                                        expandedStaffRoles.insert(group.职位)
                                    } else {
                                        expandedStaffRoles.remove(group.职位)
                                    }
                                }
                            }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(group.成员.enumerated()), id: \.offset) { _, member in
                                VStack(alignment: .leading, spacing: 4) {
                                    多语言列表文本(
                                        文本: 人物名称工具.显示名称(
                                            name: member.人员.名字,
                                            original: member.人员.原名,
                                            偏好: staffNameLang
                                        ),
                                        isJapanese: staffNameLang == .original,
                                        层级: .主标题,
                                        日文字体名称: "HiraginoSans-W4",
                                        系统字体粗细: .regular,
                                        语言来源已知: false,
                                        空格视为日语: true
                                    )

                                    if let note = member.备注 {
                                        Text(verbatim: AniList职位.备注(note))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 8)
                        .padding(.leading, 32)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: AniList职位.图标(group.职位))
                                .foregroundStyle(.secondary)
                                .frame(width: 22)

                            Text(verbatim: AniList职位.显示名称(group.职位))
                                .foregroundStyle(.primary)

                            Spacer(minLength: 8)

                            Text("\(group.成员.count)人")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accentColor(Color.secondary)
                    .animation(.easeInOut(duration: 0.24), value: expandedStaffRoles.contains(group.职位))
                }
            }
        }
    }

    private var 外部链接: [(名称: String, 地址: URL)] {
        var links: [(String, URL)] = []
        if let url = detail.malURL { links.append(("MyAnimeList", url)) }
        if let url = detail.bangumiURL { links.append((String(localized: "Bangumi番组计划"), url)) }
        for link in detail.外部链接 {
            guard let url = URL(string: link.地址),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  !links.contains(where: { $0.1 == url }) else { continue }
            links.append((link.站点 == "Official Site" ? String(localized: "官方网站") : link.站点, url))
        }
        return links
    }

    @ViewBuilder
    private var externalLinksSection: some View {
        let links = 外部链接
        if !parentalControls.policy.blocksUntrustedExternalLinks, !links.isEmpty {
            Section("外部链接") {
                ForEach(links, id: \.地址) { link in
                    Button {
                        externalBrowserTarget = 外部浏览目标(url: link.地址)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "safari")
                                .foregroundStyle(Color.blue)
                                .frame(width: 22)

                            Text(verbatim: link.名称)
                                .foregroundStyle(Color.blue)

                            Spacer(minLength: 8)

                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tint(.blue)
                }
            }
        }
    }
}

#if DEBUG
// MARK: - 预览

// 详情页从 MyAnimeList、AniList 与 Bangumi 实时读取，预览需要联网；子页面使用示例数据。

#Preview("作品详情") {
    let 载入资料库 = { 本地资料库.shared.预览载入(预览数据.资料库条目) }
    预览状态切换([
        .init("动画", 准备: 载入资料库) {
            NavigationStack { 作品详情(目标: 预览数据.芙莉莲.详情目标) }
        },
        .init("动画（不在资料库中）", 准备: 载入资料库) {
            NavigationStack { 作品详情(目标: 预览数据.芙莉莲第二季.详情目标) }
        },
        .init("漫画", 准备: 载入资料库) {
            NavigationStack { 作品详情(目标: 预览数据.剑风传奇.详情目标) }
        },
        .init("轻小说", 准备: 载入资料库) {
            NavigationStack { 作品详情(目标: 预览数据.狼与香辛料.详情目标) }
        },
        .init("无法获取", 准备: 载入资料库) {
            NavigationStack { 作品详情(目标: 作品详情目标(kind: .anime, malID: 0, 标题: "不存在的作品", 封面: nil)) }
        },
    ])
    .预览环境()
}

#Preview("作品详情：子页面") {
    let detail = 预览数据.芙莉莲详情
    预览状态切换([
        .init("简介") {
            作品简介页面(简介: detail.简介 ?? "") {}
        },
        .init("全部标签") {
            NavigationStack {
                作品全部标签页面(对象: .作品(detail.类型), 类型: detail.类型标签, 标签: detail.标签)
            }
        },
        .init("评论") {
            NavigationStack { 作品评论列表页面(评论: 预览数据.评论) }
        },
        .init("更多信息") {
            作品更多信息(detail: detail) {}
        },
    ])
    .预览环境()
}
#endif
