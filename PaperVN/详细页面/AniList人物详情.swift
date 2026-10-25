import SwiftUI

/// 动画、漫画与轻小说的角色、制作人员与动画公司的详情页（AniList）。
/// 外观与视觉小说的角色详情相同：图片铺满页面顶部并逐层模糊渐隐，信息卡片叠在图片下半部分，
/// 文字颜色按图片取样决定；下拉可以展开查看完整图片。沉浸机制与 `作品详情` 共用同一套组件。
/// 动画公司没有自己的图片，顶部用最热门作品的封面。
struct AniList人物详情: View {
    let 人物: AniList人物

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("staffNameLang") private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var 外观: 沉浸详情外观 { 已存沉浸详情外观.平台生效值 }

    @State private var 详情: AniList人物服务.详情?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var showsDescriptionSheet = false
    @State private var isDescriptionTruncated = false
    @Namespace private var zoom

    // 沉浸外观，与作品详情相同
    @State private var heroGestureIsActive = false
    @State private var heroIsExpanded = false
    @State private var viewportSize: CGSize = .zero
    @State private var divisionFrame: CGRect?
    @State private var textSamples: [String: 沉浸玻璃文字取样结果] = [:]
    @State private var textSampleURL: URL?
    @State private var textSampleGeometry: 沉浸封面文字取样几何?
    @State private var textSamplingCoordinator =
        沉浸封面文字取样任务协调器(校准名称: "角色")
    @State private var loadedHeroImage: Image?
    @State private var loadedHeroImageURL: URL?
    @State private var loadedHeroImageSize: CGSize?
    @State private var outgoingHeroImage: Image?
    @State private var heroImageTransitionProgress: CGFloat = 1
    @State private var heroImageTransitionGeneration = 0

    private var 名字: String { 详情?.名字 ?? 人物.名字 }
    private var 原名: String? { 详情?.原名 ?? 人物.原名 }

    private var 显示名称: String {
        人物名称工具.显示名称(name: 名字, original: 原名, 偏好: staffNameLang)
    }

    private var 备用名称: String? {
        人物名称工具.备用名称(name: 名字, original: 原名, 偏好: staffNameLang)
    }

    var body: some View {
        PaperVNSenkou门控 {
            详情内容
        }
    }

    private var 详情内容: some View {
        immersiveDetail
            .navigationTitle(Text(verbatim: 显示名称))
            .平台柔和滚动边缘(for: .top)
            .平台隐藏导航标题占位(显示名称)
            .平台内联导航标题()
            .task(id: 人物.id) { await load() }
            .onChange(of: colorScheme) { _, _ in
                textSamples = [:]
                textSampleURL = nil
                refreshTextSamples()
            }
            .sheet(isPresented: $showsDescriptionSheet) {
                if let 简介 = 详情?.简介 {
                    NavigationStack {
                        ScrollView {
                            Text(Self.富文本(简介))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                        .navigationTitle("简介")
                        .平台内联导航标题()
                        .toolbar {
                            ToolbarItem(placement: .平台关闭操作) {
                                Button {
                                    showsDescriptionSheet = false
                                } label: {
                                    Label("关闭", systemImage: "xmark")
                                }
                            }
                        }
                    }
                    .平台近全屏弹窗(dragIndicator: .visible)
                    .navigationTransition(.zoom(sourceID: "DescriptionSheet", in: zoom))
                }
            }
            .onDisappear {
                textSamplingCoordinator.cancel()
            }
    }

    // MARK: 载入

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let value = switch 人物.种类 {
            case .角色: try await AniList人物服务.角色详情(人物.anilistID)
            case .制作人员: try await AniList人物服务.制作人员详情(人物.anilistID)
            case .会社: try await AniList人物服务.动画公司详情(人物.anilistID)
            }
            withAnimation(.easeInOut(duration: 0.2)) { 详情 = value }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 页面结构

    private var imageURLs: [URL] {
        // 动画公司没有图片，用最热门作品的封面
        let candidates = 人物.种类 == .会社
            ? [详情?.作品.first?.作品.封面, 人物.作品?.封面]
            : [详情?.图片, 人物.图片]
        return candidates
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

                    if let 详情 {
                        lowerContent(详情)
                            .transition(.opacity)
                    } else if errorMessage == nil {
                        loadingContent
                            .transition(.opacity)
                    }
                }
            }
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

    // MARK: 图片

    private var pageHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    private var descriptionOverlap: CGFloat {
        horizontalSizeClass == .regular ? 110 : 82
    }

    private var heroSourceAspectRatio: CGFloat? {
        guard let size = loadedHeroImageSize,
              size.width > 0, size.height > 0 else {
            return nil
        }
        return size.width / size.height
    }

    private var 有简介: Bool {
        详情?.简介?.isEmpty == false
    }

    /// 图片渐隐延伸到简介下方的长度，与角色详情一致。
    private func heroDescriptionExtension(imageURLs: [URL]) -> CGFloat {
        guard !imageURLs.isEmpty else { return 0 }
        guard 详情 == nil || 有简介 else { return 0 }
        return horizontalSizeClass == .regular ? 120 : 148
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
                } else if 详情 == nil, errorMessage == nil {
                    ZStack {
                        Color.secondary.opacity(0.12)
                        ProgressView()
                    }
                    .frame(width: width, height: renderedHeight)
                } else {
                    平台内容不可用视图("无图像", systemImage: "photo")
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

    /// 清晰、中等模糊、重度模糊三层图片按渐变叠加，再整体渐隐，与角色详情相同。
    private func heroImageComposition(
        gradient: 沉浸封面渐变方案,
        revealProgress: CGFloat
    ) -> some View {
        let revealProgress = min(max(revealProgress, 0), 1)

        return ZStack {
            heroImageLayer(revealProgress: revealProgress)
                .mask {
                    ZStack {
                        LinearGradient(stops: gradient.sharp.gradientStops, startPoint: .top, endPoint: .bottom)
                        Color.white.opacity(revealProgress)
                    }
                }

            heroImageLayer(revealProgress: revealProgress)
                .blur(radius: gradient.mediumBlurRadius)
                .mask {
                    LinearGradient(stops: gradient.medium.gradientStops, startPoint: .top, endPoint: .bottom)
                }
                .opacity(1 - revealProgress)

            heroImageLayer(revealProgress: revealProgress)
                .blur(radius: gradient.heavyBlurRadius)
                .mask {
                    LinearGradient(stops: gradient.heavy.gradientStops, startPoint: .top, endPoint: .bottom)
                }
                .opacity(1 - revealProgress)
        }
        .compositingGroup()
        .mask {
            ZStack {
                LinearGradient(stops: gradient.fade.gradientStops, startPoint: .top, endPoint: .bottom)
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

    /// 角色与人物的图片是竖图，顶部对齐，脸不会被裁掉。
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
            itemCounts: ["profile": 详情?.资料.count ?? 0],
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
        let showsDescriptionCard = 有简介 || (详情 == nil && 人物.种类 != .会社)

        return VStack(alignment: .leading, spacing: 沉浸详情布局.主要信息间距) {
            if horizontalSizeClass == .regular {
                沉浸详情等高双栏布局(
                    spacing: 16,
                    divisionFrame: divisionFrame,
                    horizontalInset: pageHorizontalPadding
                ) {
                    identity(fillsAvailableHeight: showsDescriptionCard)
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if showsDescriptionCard {
                        descriptionContent(fillsAvailableHeight: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, pageHorizontalPadding)
            } else {
                identity()
                    .padding(.horizontal, pageHorizontalPadding)

                if showsDescriptionCard {
                    descriptionContent()
                        .padding(.horizontal, pageHorizontalPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 名字与原名（不显示别名），下面是生日、性别等资料，和视觉小说的角色详情一样放在一张玻璃卡片里。
    private func identity(fillsAvailableHeight: Bool = false) -> some View {
        let style = textStyle(for: "metadata")
        let titleStyle = textStyle(for: "metadata.title")

        return VStack(alignment: .leading, spacing: fillsAvailableHeight ? 0 : 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    标题工具.生成富文本(
                        文本: 显示名称,
                        isJapanese: staffNameLang == .original,
                        基础大小: 22,
                        是粗体: true,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言来源已知: false,
                        空格视为日语: staffNameLang == .original
                    )
                )
                .沉浸详情文字前景色(titleStyle.primary, style: titleStyle)
                .lineLimit(2)
                .contextMenu {
                    ForEach([名字, 原名].compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { name in
                        Button {
                            UIPasteboard.general.string = name
                        } label: {
                            Label {
                                Text(verbatim: String(localized: "拷贝“\(name)”"))
                            } icon: {
                                Image(systemName: "doc.on.doc")
                            }
                        }
                    }
                }

                if let 备用名称 {
                    Text(verbatim: 备用名称)
                        .font(.subheadline)
                        .沉浸详情文字前景色(titleStyle.secondary, style: titleStyle)
                        .lineLimit(1)
                }
            }
            .视觉小说沉浸取样框(["metadata.title"])
            .frame(maxWidth: .infinity, alignment: .leading)
            .沉浸详情文字阴影(titleStyle)

            if fillsAvailableHeight {
                Spacer(minLength: 14)
            }

            if let 详情 {
                if !详情.资料.isEmpty {
                    profile(详情.资料)
                        .沉浸详情文字阴影(style)
                }
            } else {
                loadingProfile
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

    /// 资料分两栏排开，和视觉小说详情的信息格一样。
    private func profile(_ items: [(标题: String, 内容: String)]) -> some View {
        let rowSpacing: CGFloat = horizontalSizeClass == .regular ? 14 : 8
        let left = items.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
        let right = items.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(left, id: \.标题) { item in
                    profileItem(item, index: items.firstIndex { $0.标题 == item.标题 } ?? 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: rowSpacing) {
                ForEach(right, id: \.标题) { item in
                    profileItem(item, index: items.firstIndex { $0.标题 == item.标题 } ?? 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
    }

    private func profileItem(_ item: (标题: String, 内容: String), index: Int) -> some View {
        let key = "metadata.profile.\(index)"
        let style = textStyle(for: key)
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: Self.资料图标(item.标题))
                .font(.subheadline)
                .沉浸详情文字前景色(style.secondary, style: style)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.标题)
                    .font(.caption2.weight(.medium))
                    .沉浸详情文字前景色(style.tertiary, style: style)

                Text(verbatim: item.内容)
                    .font(.subheadline.weight(.regular))
                    .沉浸详情文字前景色(style.primary, style: style)
                    .lineLimit(2)
            }
        }
        .视觉小说沉浸取样框([key])
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(style)
    }

    private static func 资料图标(_ title: String) -> String {
        switch title {
        case String(localized: "生日"): "gift"
        case String(localized: "性别"): "person"
        case String(localized: "年龄"): "hourglass"
        case String(localized: "血型"): "drop"
        case String(localized: "职业"): "briefcase"
        case String(localized: "出身地"): "mappin.and.ellipse"
        default: "info.circle"
        }
    }

    private var loadingProfile: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "生日 12月31日")
                Text(verbatim: "年龄 17")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "性别 女")
                Text(verbatim: "血型 A")
            }
        }
        .font(.subheadline)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
    }

    private func descriptionContent(fillsAvailableHeight: Bool = false) -> some View {
        let style = textStyle(for: "description.text")
        let 简介 = 详情?.简介

        return Group {
            if let 简介, !简介.isEmpty {
                简介预览文本视图(
                    text: 简介,
                    lineLimit: 7,
                    onTruncationChange: { isDescriptionTruncated = $0 }
                )
                .font(.body)
                .沉浸详情文字前景色(style.primary, style: style)
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .matchedTransitionSource(id: "DescriptionSheet", in: zoom)
        .onTapGesture {
            guard 简介?.isEmpty == false, isDescriptionTruncated else { return }
            showsDescriptionSheet = true
        }
        .allowsHitTesting(简介?.isEmpty == false)
        .视觉小说沉浸取样框(["description", "description.text"])
    }

    // MARK: 下方内容

    @ViewBuilder
    private var failureCard: some View {
        if let errorMessage, 详情 == nil {
            VStack(alignment: .leading, spacing: 10) {
                Label("无法载入", systemImage: "exclamationmark.triangle")
                    .font(.headline)

                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("重试") {
                    Task { await load() }
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
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 230)
            }
        }
        .padding(.horizontal, pageHorizontalPadding)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
    }

    /// 角色：声优、出场作品；制作人员：配音的角色、参与作品；动画公司：主要作品。卡片与视觉小说角色详情相同。
    @ViewBuilder
    private func lowerContent(_ 详情: AniList人物服务.详情) -> some View {
        if !详情.相关人物.isEmpty {
            horizontalSection(人物.种类 == .角色 ? "声优" : "配音的角色") {
                ForEach(详情.相关人物) { item in
                    NavigationLink {
                        AniList人物详情(人物: item)
                            .navigationTransition(.zoom(sourceID: item.id, in: zoom))
                    } label: {
                        mediaCard(
                            imageURL: item.图片,
                            // 卡片标题与视觉小说详情的角色卡片相同（W6 + 粗体）；`人物名称工具.生成富文本` 固定 W4，配粗体会日文细、拉丁字母粗
                            title: 标题工具.生成富文本(
                                文本: 人物名称工具.显示名称(name: item.名字, original: item.原名, 偏好: staffNameLang),
                                isJapanese: staffNameLang == .original,
                                基础大小: 14,
                                是粗体: true,
                                日文字体名称: "HiraginoSans-W6",
                                系统字体粗细: .bold,
                                语言来源已知: false,
                                空格视为日语: true
                            ),
                            subtitle: nil
                        )
                        .matchedTransitionSource(id: item.id, in: zoom)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        if !详情.作品.isEmpty {
            horizontalSection(作品标题) {
                ForEach(详情.作品) { item in
                    NavigationLink {
                        作品详情(目标: item.作品.详情目标)
                            .navigationTransition(.zoom(sourceID: "work-\(item.id)", in: zoom))
                    } label: {
                        mediaCard(
                            imageURL: item.作品.封面,
                            title: 作品标题富文本(item.作品),
                            subtitle: item.说明.map { AttributedString($0) }
                        )
                        .matchedTransitionSource(id: "work-\(item.id)", in: zoom)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var 作品标题: LocalizedStringKey {
        switch 人物.种类 {
        case .角色: "出场作品"
        case .制作人员: "参与作品"
        case .会社: "主要作品"
        }
    }

    private func 作品标题富文本(_ work: 作品搜索结果) -> AttributedString {
        let title = 标题工具.获取主标题(
            titles: work.多语言标题,
            defaultTitle: work.标题,
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

    private static func 富文本(_ markdown: String) -> AttributedString {
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(markdown)
    }
}
