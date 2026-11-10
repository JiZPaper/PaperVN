import Combine
import Foundation
import SwiftUI
import UIKit

// 发行版本详情页面。

struct 发行版本详情: View {
    let item: 探索发行版本
    let openedFromVisualNovelDetail: Bool

    @ObservedObject var auth: 用户登录
    @StateObject private var confirmation = 模糊解除确认器()
    @State private var detailedItem: 探索发行版本?
    @State private var browserURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.详情内容限制方式覆盖)
    private var contentRestrictionMethodOverride
    @AppStorage("contentFilterEnabled")
    private var contentFilterEnabled = false
    @AppStorage("sexualThreshold")
    private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold")
    private var violenceThreshold: Double = 1
    @AppStorage("filterMode")
    private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var storedContentRestrictionMethod: 内容限制方式 = .blurred
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var immersiveDetailAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }
    @State private var revealHeroImage = false
    @State private var immersiveHeroGestureIsActive = false
    @State private var immersiveHeroIsExpanded = false
    @State private var immersiveViewportSize: CGSize = .zero
    @State private var immersiveDivisionFrame: CGRect?
    @State private var immersiveTextSamples: [String: 沉浸玻璃文字取样结果] = [:]
    @State private var immersiveTextSampleURL: URL?
    @State private var immersiveTextRevealURL: URL?
    @State private var immersiveTextSampleGeometry: 沉浸封面文字取样几何?
    @State private var immersiveTextSamplingCoordinator = 沉浸封面文字取样任务协调器(校准名称: "发行版本")
    @State private var immersiveLoadedHeroImage: Image?
    @State private var immersiveLoadedHeroImageURL: URL?
    @State private var immersiveLoadedHeroAspectRatio: CGFloat?
    @State private var immersiveOutgoingHeroImage: Image?
    @State private var immersiveHeroImageTransitionProgress: CGFloat = 1
    @State private var immersiveHeroImageTransitionGeneration = 0
    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji

    init(
        item: 探索发行版本,
        auth: 用户登录,
        openedFromVisualNovelDetail: Bool = false
    ) {
        self.item = item
        self.openedFromVisualNovelDetail = openedFromVisualNovelDetail
        _auth = ObservedObject(wrappedValue: auth)
    }

    var body: some View {
        ZStack {
            releaseBackdrop

            ScrollView {
                沉浸封面详情内容(
                    onGestureActivityChanged: updateImmersiveHeroGestureActivity
                ) { dragContext in
                    releaseHeroAndPrimaryInformation(dragContext)
                        .onChange(of: dragContext.isExpanded) { _, isExpanded in
                            updateImmersiveHeroExpansion(isExpanded)
                        }
                } content: {
                    releaseContent
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            immersiveViewportSize = size
        }
        .沉浸详情折叠区域(读取到: $immersiveDivisionFrame)
        .coordinateSpace(name: "ReleaseImmersiveDetailScroll")
        .onPreferenceChange(
            探索发行版本沉浸取样框PreferenceKey.self
        ) { frames in
            updateImmersiveTextSampleGeometry(from: frames)
        }
        .navigationTitle(displayedReleaseTitle)
        .平台柔和滚动边缘(for: .top)
        .平台隐藏导航标题占位(displayedReleaseTitle)
        .平台内联导航标题()
        .toolbar {
            if !validExternalLinks.isEmpty {
                ToolbarItem(placement: .平台主操作) {
                    externalLinksToolbarControl
                }
            }

            if showsIncludedWorksToolbarControl,
               !validExternalLinks.isEmpty {
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .平台主操作)
                }
            }

            if showsIncludedWorksToolbarControl {
                ToolbarItem(placement: .平台主操作) {
                    includedWorksToolbarControl
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .平台沉浸导航栏()
        .task(id: item.id) {
            guard let fetchedItem = try? await VNDB探索服务.shared.发行详情(
                id: item.id
            ), !Task.isCancelled else {
                return
            }
            detailedItem = fetchedItem
            presentPreloadedImmersiveHeroImageIfNeeded()
        }
        .onChange(of: colorScheme) { _, _ in
            immersiveTextSamples = [:]
            immersiveTextSampleURL = nil
            immersiveTextRevealURL = nil
            refreshImmersiveTextSamplesForCurrentAppearance()
        }
        .onDisappear {
            confirmation.cancel()
            immersiveTextSamplingCoordinator.cancel()
        }
        .overlay(alignment: .bottom) {
            模糊解除提示(isPresented: confirmation.isPromptVisible)
                .padding(.bottom, 12)
        }
        .sheet(
            isPresented: Binding(
                get: { browserURL != nil },
                set: { if !$0 { browserURL = nil } }
            )
        ) {
            if let browserURL {
                内置Safari浏览器(url: browserURL)
                    .平台近全屏弹窗()
            }
        }
    }

    private var contentRestrictionMethod: 内容限制方式 {
        contentRestrictionMethodOverride ?? storedContentRestrictionMethod
    }

    private var releaseImage: 探索发行图片? {
        guard !openedFromVisualNovelDetail else { return nil }
        return displayedItem.images?.first {
            $0.url != nil || $0.thumbnail != nil
        }
            ?? item.images?.first {
                $0.url != nil || $0.thumbnail != nil
            }
    }

    private var releaseImageURLs: [URL] {
        let values: [String?]
        if openedFromVisualNovelDetail {
            values = [
                item.visualNovels?.first?.image?.url,
                displayedItem.visualNovels?.first?.image?.url
            ]
        } else if let releaseImage {
            values = [releaseImage.url, releaseImage.thumbnail]
        } else {
            values = [
                displayedItem.visualNovels?.first?.image?.url,
                displayedItem.visualNovels?.first?.image?.thumbnail,
                item.visualNovels?.first?.image?.url,
                item.visualNovels?.first?.image?.thumbnail
            ]
        }
        return values
            .compactMap { value -> URL? in
                guard let value, let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      (scheme == "http" || scheme == "https"),
                      url.host != nil,
                      !openedFromVisualNovelDetail || !url.path.contains("/cv.t/") else {
                    return nil
                }
                return url
            }
            .reduce(into: []) { urls, url in
                if !urls.contains(url) { urls.append(url) }
            }
    }

    private var immersivePresentedHeroImage: Image? {
        immersiveLoadedHeroImage
    }

    private var releaseHeroSourceAspectRatio: CGFloat? {
        if openedFromVisualNovelDetail {
            let dimensions = item.visualNovels?.first?.image?.dims
                ?? displayedItem.visualNovels?.first?.image?.dims
            if let dimensions,
               dimensions.count >= 2,
               dimensions[0] > 0,
               dimensions[1] > 0 {
                return CGFloat(dimensions[0]) / CGFloat(dimensions[1])
            }
        }
        if let immersiveLoadedHeroAspectRatio,
           immersiveLoadedHeroAspectRatio.isFinite,
           immersiveLoadedHeroAspectRatio > 0 {
            return immersiveLoadedHeroAspectRatio
        }
        let dimensions = releaseImage?.dims
            ?? item.visualNovels?.first?.image?.dims
            ?? displayedItem.visualNovels?.first?.image?.dims
        guard let dimensions, dimensions.count >= 2, dimensions[0] > 0, dimensions[1] > 0 else { return nil }
        return CGFloat(dimensions[0]) / CGFloat(dimensions[1])
    }

    private var releaseImageSexual: Double? {
        if openedFromVisualNovelDetail {
            return item.visualNovels?.first?.image?.sexual
                ?? displayedItem.visualNovels?.first?.image?.sexual
        }
        return releaseImage?.sexual
            ?? displayedItem.visualNovels?.first?.image?.sexual
            ?? item.visualNovels?.first?.image?.sexual
    }

    private var releaseImageViolence: Double? {
        if openedFromVisualNovelDetail {
            return item.visualNovels?.first?.image?.violence
                ?? displayedItem.visualNovels?.first?.image?.violence
        }
        return releaseImage?.violence
            ?? displayedItem.visualNovels?.first?.image?.violence
            ?? item.visualNovels?.first?.image?.violence
    }

    private var releaseImageIsRestricted: Bool {
        内容安全限制判定.图片需要限制(
            sexual: releaseImageSexual,
            violence: releaseImageViolence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        ) && !revealHeroImage
    }

    private var canRevealReleaseImage: Bool {
        内容安全限制判定.图片允许手动解除模糊(
            sexual: releaseImageSexual,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            mode: filterMode
        )
    }

    private var releaseBackdrop: some View {
        GeometryReader { proxy in
            ZStack {
                Color.平台系统背景
                if !releaseImageURLs.isEmpty {
                    releaseBackdropImageLayer(loadedImage: immersivePresentedHeroImage)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(沉浸封面背景层参数.缩放)
                        .blur(radius: 沉浸封面背景层参数.模糊半径)
                        .saturation(沉浸封面背景层参数.饱和度)
                        .opacity(沉浸封面背景层参数.不透明度)
                    ForEach(releaseImageURLs, id: \.absoluteString) { url in
                        CachedAsyncImage(
                            url: url,
                            contentMode: .fill,
                            onImageLoaded: { loadedURL, image, imageSize in
                                activateImmersiveHeroImage(
                                    image,
                                    for: loadedURL,
                                    imageSize: imageSize
                                )
                            },
                            onImageReady: { loadedURL in
                                updateImmersiveTextSamples(for: loadedURL)
                            }
                        )
                        .frame(width: 1, height: 1)
                        .clipped()
                        .opacity(0)
                        .accessibilityHidden(true)
                    }
                }
                Color.平台系统背景.opacity(沉浸封面背景层参数.系统背景覆盖不透明度)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func releaseHeroAndPrimaryInformation(
        _ dragContext: 沉浸封面拖动上下文
    ) -> some View {
        let cardProgress = min(max(dragContext.progress, 0), 1)
        let cardOffset = releaseInformationOverlap * cardProgress

        return VStack(alignment: .leading, spacing: 24) {
            releaseHero(dragContext)
            releasePrimaryInformationAvoidingFold
                .padding(.top, -releaseInformationOverlap)
                .padding(.bottom, cardOffset)
                .compositingGroup()
                .offset(y: cardOffset)
        }
        .coordinateSpace(name: "ReleaseImmersiveDetailSampling")
    }

    private func releaseHero(
        _ dragContext: 沉浸封面拖动上下文
    ) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let heroHeight = max(proxy.size.height, 1)
            let fadeOverflow: CGFloat = 72
            let scrollFrame = proxy.frame(in: .named("ReleaseImmersiveDetailScroll"))
            let samplingFrame = proxy.frame(in: .named("ReleaseImmersiveDetailSampling"))
            let pullDown = scrollFrame.minY.isFinite ? max(scrollFrame.minY, 0) : 0
            let expandedHeroHeight = releaseExpandedHeroHeight(width: width, collapsedHeight: heroHeight)
            let transitionProgress = min(max(dragContext.progress, 0), 1)
            let expandedImageTopInset = max((immersiveViewportSize.height - expandedHeroHeight) / 2, 0)
            let imageTopInset = expandedImageTopInset * transitionProgress
            let layoutHeroHeight = heroHeight + (expandedHeroHeight - heroHeight) * transitionProgress
            let informationExtension = releaseHeroInformationExtension
            let extendsThroughInformation = informationExtension > 0
            let renderedHeight = layoutHeroHeight
                + imageTopInset
                + pullDown
                + (fadeOverflow + informationExtension) * (1 - transitionProgress)
            let sampleImageFrame = CGRect(
                x: samplingFrame.minX,
                y: samplingFrame.minY - pullDown,
                width: width,
                height: heroHeight + fadeOverflow + informationExtension
            )
            let primaryInformationStart = heroHeight + 24 + pullDown
            let blurTransitionStart = min(
                max(
                    extendsThroughInformation
                        ? primaryInformationStart / renderedHeight
                        : 0.46,
                    0
                ),
                1
            )
            let hasImage = !releaseImageURLs.isEmpty

            沉浸封面拖动图层(
                isExpanded: dragContext.isExpanded,
                hasImage: hasImage,
                progress: dragContext.progressBinding,
                onExpansionChanged: dragContext.onExpansionChanged,
                onBounceChanged: dragContext.onBounceChanged,
                onGestureActivityChanged: dragContext.onGestureActivityChanged,
                onTap: {
                    guard releaseImageIsRestricted,
                          contentRestrictionMethod == .blurred,
                          canRevealReleaseImage else { return }
                    confirmation.request(id: "release-hero-image") {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            revealHeroImage = true
                        }
                    }
                }
            ) { progress in
                releaseHeroImagePresentation(
                    loadedImage: immersivePresentedHeroImage,
                    extendsThroughInformation: extendsThroughInformation,
                    width: width,
                    heroHeight: heroHeight,
                    renderedHeight: renderedHeight,
                    backgroundHeight: heroHeight + fadeOverflow + informationExtension,
                    imageTopInset: imageTopInset,
                    minimumRasterHeight: heroHeight + fadeOverflow + informationExtension + 160,
                    blurTransitionStart: blurTransitionStart,
                    pullProgress: progress
                )
                .应用不安全内容限制(releaseImageIsRestricted, method: contentRestrictionMethod, blurRadius: 28)
                .animation(.easeInOut(duration: 0.28), value: revealHeroImage)
            }
            .frame(width: width, height: renderedHeight)
            .offset(y: -pullDown)
            .发行版本沉浸取样框(["image": sampleImageFrame])
        }
        .frame(height: horizontalSizeClass == .regular ? 420 : nil)
        .aspectRatio(
            horizontalSizeClass == .regular ? nil : 1 / 0.72,
            contentMode: .fit
        )
        .frame(maxWidth: .infinity)
        .padding(.bottom, releaseHeroLayoutExtension(pullProgress: dragContext.progress))
        .offset(y: -dragContext.bounceOffset)
        .accessibilityElement(children: .contain)
    }

    private func releaseExpandedHeroHeight(width: CGFloat, collapsedHeight: CGFloat) -> CGFloat {
        let sourceAspectRatio = releaseHeroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(min(width - horizontalInset, collapsedHeight * sourceAspectRatio), 1)
        return max(expandedWidth / sourceAspectRatio, 1)
    }

    private func releaseHeroLayoutExtension(pullProgress: CGFloat) -> CGFloat {
        let width = immersiveViewportSize.width
        guard width > 0, immersiveViewportSize.height > 0 else { return 0 }
        let transitionProgress = min(max(pullProgress, 0), 1)
        let collapsedHeight = horizontalSizeClass == .regular ? CGFloat(420) : width * 0.72
        let expandedHeight = releaseExpandedHeroHeight(width: width, collapsedHeight: collapsedHeight)
        let expandedTopInset = max((immersiveViewportSize.height - expandedHeight) / 2, 0)
        return max(expandedTopInset + expandedHeight - collapsedHeight, 0) * transitionProgress
    }

    private var releaseHeroInformationExtension: CGFloat {
        guard !releaseImageURLs.isEmpty else { return 0 }
        return horizontalSizeClass == .regular ? 284 : 316
    }

    @ViewBuilder
    private func releaseHeroImagePresentation(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        width: CGFloat,
        heroHeight: CGFloat,
        renderedHeight: CGFloat,
        backgroundHeight: CGFloat,
        imageTopInset: CGFloat,
        minimumRasterHeight: CGFloat,
        blurTransitionStart: CGFloat,
        pullProgress: CGFloat
    ) -> some View {
        let progress = min(max(pullProgress, 0), 1)
        let sourceAspectRatio = releaseHeroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(min(width - horizontalInset, heroHeight * sourceAspectRatio), 1)
        let expandedHeight = max(expandedWidth / sourceAspectRatio, 1)
        let imageWidth = width + (expandedWidth - width) * progress
        let presentationHeight = backgroundHeight + (expandedHeight - backgroundHeight) * progress
        let cornerRadius = 28 * progress

        releaseRasterizedHeroImage(
            loadedImage: loadedImage,
            extendsThroughInformation: extendsThroughInformation,
            width: imageWidth,
            renderedHeight: presentationHeight,
            minimumRasterHeight: minimumRasterHeight,
            revealProgress: progress,
            blurTransitionStart: blurTransitionStart
        )
        .平台背景延伸效果()
        .frame(width: imageWidth, height: presentationHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .top)
        .offset(y: imageTopInset)
        .frame(width: width, height: renderedHeight, alignment: .top)
    }

    @ViewBuilder
    private func releaseRasterizedHeroImage(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        width: CGFloat,
        renderedHeight: CGFloat,
        minimumRasterHeight: CGFloat,
        revealProgress: CGFloat,
        blurTransitionStart: CGFloat
    ) -> some View {
        let rasterBucket: CGFloat = 128
        let rasterHeight = max(
            (minimumRasterHeight / rasterBucket).rounded(.up) * rasterBucket,
            (renderedHeight / rasterBucket).rounded(.up) * rasterBucket
        )
        ZStack(alignment: .top) {
            releaseHeroImage(
                loadedImage: loadedImage,
                extendsThroughInformation: extendsThroughInformation,
                blurTransitionStart: blurTransitionStart,
                revealProgress: revealProgress
            )
            .frame(width: width, height: renderedHeight)
        }
        .frame(width: width, height: rasterHeight, alignment: .top)
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .frame(width: width, height: renderedHeight, alignment: .top)
        .clipped()
    }

    private func releaseHeroImage(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        blurTransitionStart: CGFloat,
        revealProgress: CGFloat
    ) -> some View {
        let gradient: 沉浸封面渐变方案 = if extendsThroughInformation, horizontalSizeClass == .regular {
            .常规(transitionStart: blurTransitionStart)
        } else {
            extendsThroughInformation ? .紧凑延伸 : .紧凑标准
        }
        return releaseHeroImageComposition(
            loadedImage: loadedImage,
            gradient: gradient,
            revealProgress: revealProgress
        )
    }

    private func releaseHeroImageComposition(
        loadedImage: Image?,
        gradient: 沉浸封面渐变方案,
        revealProgress: CGFloat
    ) -> some View {
        let progress = min(max(revealProgress, 0), 1)
        return ZStack {
            releaseHeroImageLayer(loadedImage: loadedImage, revealProgress: progress)
                .mask {
                    ZStack {
                        LinearGradient(stops: gradient.sharp.gradientStops, startPoint: .top, endPoint: .bottom)
                        Color.white.opacity(progress)
                    }
                }
            releaseHeroImageLayer(loadedImage: loadedImage, revealProgress: progress)
                .blur(radius: gradient.mediumBlurRadius)
                .mask { LinearGradient(stops: gradient.medium.gradientStops, startPoint: .top, endPoint: .bottom) }
                .opacity(1 - progress)
            releaseHeroImageLayer(loadedImage: loadedImage, revealProgress: progress)
                .blur(radius: gradient.heavyBlurRadius)
                .mask { LinearGradient(stops: gradient.heavy.gradientStops, startPoint: .top, endPoint: .bottom) }
                .opacity(1 - progress)
        }
        .compositingGroup()
        .mask {
            ZStack {
                LinearGradient(stops: gradient.fade.gradientStops, startPoint: .top, endPoint: .bottom)
                Color.white.opacity(progress)
            }
        }
    }

    @ViewBuilder
    private func releaseHeroImageLayer(loadedImage: Image?, revealProgress: CGFloat) -> some View {
        if loadedImage != nil || immersiveOutgoingHeroImage != nil {
            ZStack {
                if let immersiveOutgoingHeroImage {
                    releaseAlignedHeroImage(immersiveOutgoingHeroImage, revealProgress: revealProgress)
                }
                if let loadedImage {
                    releaseAlignedHeroImage(loadedImage, revealProgress: revealProgress)
                        .opacity(immersiveHeroImageTransitionProgress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: immersiveHeroImageTransitionProgress)
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    private func releaseAlignedHeroImage(_ image: Image, revealProgress: CGFloat) -> some View {
        GeometryReader { proxy in
            image.resizable()
                .aspectRatio(releaseHeroSourceAspectRatio, contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .offset(y: horizontalSizeClass == .regular ? -60 * (1 - revealProgress) : 0)
        }
        .clipped()
    }

    @ViewBuilder
    private func releaseBackdropImageLayer(loadedImage: Image?) -> some View {
        if loadedImage != nil || immersiveOutgoingHeroImage != nil {
            ZStack {
                if let immersiveOutgoingHeroImage {
                    immersiveOutgoingHeroImage.resizable().aspectRatio(releaseHeroSourceAspectRatio, contentMode: .fill)
                }
                if let loadedImage {
                    loadedImage.resizable().aspectRatio(releaseHeroSourceAspectRatio, contentMode: .fill)
                        .opacity(immersiveHeroImageTransitionProgress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: immersiveHeroImageTransitionProgress)
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    private var releaseImmersivePrimaryInformationIsVisible: Bool {
        guard immersiveDetailAppearance == .clear else { return true }
        guard !releaseImageURLs.isEmpty else { return true }
        guard immersiveTextSampleGeometry != nil,
              let url = immersiveLoadedHeroImageURL else { return false }
        return immersiveTextSampleURL == url && immersiveTextRevealURL == url
    }

    private var immersiveSystemGlassTint: Color? {
        guard immersiveDetailAppearance == .clear,
              releaseImageURLs.isEmpty else {
            return nil
        }
        return colorScheme == .dark ? .black : .white
    }

    private func releaseMetadataTextStyle(for key: String) -> 沉浸详情文字样式 {
        沉浸详情文字样式(
            appearance: immersiveDetailAppearance,
            sample: immersiveTextSamples[key],
            fallbackColorScheme: colorScheme
        )
    }

    private var currentImmersiveImageURL: URL? {
        if let loaded = immersiveLoadedHeroImageURL, releaseImageURLs.contains(loaded) {
            return loaded
        }
        return releaseImageURLs.first
    }

    private func shouldAcceptImmersiveImage(at url: URL) -> Bool {
        guard let candidate = releaseImageURLs.firstIndex(of: url) else { return false }
        guard let loaded = immersiveLoadedHeroImageURL,
              let loadedIndex = releaseImageURLs.firstIndex(of: loaded) else { return true }
        return candidate <= loadedIndex
    }

    private func updateImmersiveTextSamples(for url: URL) {
        guard shouldAcceptImmersiveImage(at: url),
              let geometry = immersiveTextSamplingCoordinator.latestGeometry ?? immersiveTextSampleGeometry else { return }
        scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: false)
    }

    private func activateImmersiveHeroImage(
        _ image: Image,
        for url: URL,
        imageSize: CGSize
    ) {
        guard shouldAcceptImmersiveImage(at: url) else { return }
        if imageSize.width > 0, imageSize.height > 0 {
            immersiveLoadedHeroAspectRatio = imageSize.width / imageSize.height
        }
        let canPresent = true
        let shouldCrossfade = canPresent && !reduceMotion && immersiveLoadedHeroImage != nil && immersiveLoadedHeroImageURL != url
        let shouldFadeIn = canPresent && !reduceMotion && immersiveLoadedHeroImage == nil
        immersiveHeroImageTransitionGeneration += 1
        let generation = immersiveHeroImageTransitionGeneration
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            immersiveOutgoingHeroImage = shouldCrossfade ? immersiveLoadedHeroImage : nil
            immersiveLoadedHeroImage = image
            immersiveLoadedHeroImageURL = url
            immersiveHeroImageTransitionProgress = (shouldCrossfade || shouldFadeIn) ? 0 : (canPresent ? 1 : 0)
        }
        guard shouldCrossfade || shouldFadeIn else { return }
        Task { @MainActor in
            await Task.yield()
            guard generation == immersiveHeroImageTransitionGeneration else { return }
            immersiveHeroImageTransitionProgress = 1
            try? await Task.sleep(for: .seconds(0.32))
            guard generation == immersiveHeroImageTransitionGeneration else { return }
            var cleanup = Transaction()
            cleanup.animation = nil
            cleanup.disablesAnimations = true
            withTransaction(cleanup) { immersiveOutgoingHeroImage = nil }
        }
    }

    private func presentPreloadedImmersiveHeroImageIfNeeded() {
        guard immersiveLoadedHeroImage != nil,
              let url = immersiveLoadedHeroImageURL else { return }
        updateImmersiveTextSamples(for: url)
        guard immersiveHeroImageTransitionProgress < 1 else { return }
        immersiveHeroImageTransitionGeneration += 1
        let generation = immersiveHeroImageTransitionGeneration
        if reduceMotion {
            immersiveHeroImageTransitionProgress = 1
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard immersiveLoadedHeroImageURL == url,
                  generation == immersiveHeroImageTransitionGeneration else { return }
            immersiveHeroImageTransitionProgress = 1
        }
    }

    private func refreshImmersiveTextSamplesForCurrentAppearance() {
        guard let url = currentImmersiveImageURL,
              let geometry = immersiveTextSamplingCoordinator.latestGeometry ?? immersiveTextSampleGeometry else { return }
        scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: true)
    }

    /// 与 releaseHero 静止状态（无下拉）的遮罩一致。
    private func releaseSamplingGradient(geometry: 沉浸封面文字取样几何) -> 沉浸封面渐变方案 {
        let informationExtension = releaseHeroInformationExtension
        guard informationExtension > 0 else { return .紧凑标准 }
        guard horizontalSizeClass == .regular else { return .紧凑延伸 }
        let layerHeight = max(geometry.imageSize.height, 1)
        let heroHeight = layerHeight - 72 - informationExtension
        return .常规取样(transitionStart: (heroHeight + 24) / layerHeight)
    }

    private func scheduleImmersiveTextSamples(for url: URL, geometry: 沉浸封面文字取样几何, revealsImmediately: Bool) {
        let request = 沉浸封面文字取样请求(
            url: url,
            layout: .visualNovel,
            background: colorScheme == .dark ? .dark : .light,
            gradient: releaseSamplingGradient(geometry: geometry),
            // 发行版本页只显示元数据，不计算并不存在的标签胶囊。
            itemCounts: ["tags": 0],
            geometry: geometry
        )
        immersiveTextSamplingCoordinator.submit(request) { request, samples in
            guard !immersiveHeroGestureIsActive,
                  currentImmersiveImageURL == request.url,
                  shouldAcceptImmersiveImage(at: request.url) else { return }
            // 显示效果没变时不写状态，避免下拉等连续几何变化逐帧刷新整页。
            let samplesChanged = immersiveTextSampleURL != request.url
                || immersiveTextSamples != samples
            guard samplesChanged
                    || immersiveTextSampleGeometry == nil
                    || (revealsImmediately && immersiveTextRevealURL != request.url)
            else { return }
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                immersiveTextSampleGeometry = request.geometry
                immersiveTextSamples = samples
                immersiveTextSampleURL = request.url
                if revealsImmediately { immersiveTextRevealURL = request.url }
            }
            if !revealsImmediately {
                Task { @MainActor in
                    await Task.yield()
                    guard immersiveTextSampleURL == request.url else { return }
                    withAnimation(.easeOut(duration: 0.18)) { immersiveTextRevealURL = request.url }
                }
            }
        }
    }

    private func updateImmersiveTextSampleGeometry(from frames: [String: CGRect]) {
        guard let imageFrame = frames["image"], 探索发行版本沉浸取样框有效(imageFrame) else { return }
        var regions: [String: CGRect] = [:]
        for (key, frame) in frames where key != "image" {
            guard 探索发行版本沉浸取样框有效(frame) else { continue }
            let relative = frame.offsetBy(dx: -imageFrame.minX, dy: -imageFrame.minY)
            guard let sample = releaseImmersiveSamplingFrame(relative) else { continue }
            regions[key] = sample
        }
        let geometry = 沉浸封面文字取样几何(
            imageSize: CGSize(width: imageFrame.width, height: imageFrame.height),
            regions: regions,
            viewportSize: immersiveViewportSize,
            contentOffsetY: horizontalSizeClass == .regular ? -60 : 0,
            封面已展开: immersiveHeroIsExpanded
        )
        guard immersiveTextSamplingCoordinator.latestGeometry != geometry else { return }
        immersiveTextSamplingCoordinator.remember(geometry)
        guard !immersiveHeroGestureIsActive, let url = currentImmersiveImageURL else { return }
        scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: true)
    }

    /// 下拉展开或收起封面时，信息卡片背后的背景整个换掉，需要按新的状态重新取样。
    private func updateImmersiveHeroExpansion(_ isExpanded: Bool) {
        guard immersiveHeroIsExpanded != isExpanded else { return }
        immersiveHeroIsExpanded = isExpanded
        guard var geometry = immersiveTextSamplingCoordinator.latestGeometry
                ?? immersiveTextSampleGeometry else {
            return
        }
        geometry.封面已展开 = isExpanded
        immersiveTextSamplingCoordinator.remember(geometry)
        guard !immersiveHeroGestureIsActive,
              let url = currentImmersiveImageURL else {
            return
        }
        scheduleImmersiveTextSamples(
            for: url,
            geometry: geometry,
            revealsImmediately: true
        )
    }

    private func updateImmersiveHeroGestureActivity(_ isActive: Bool) {
        guard immersiveHeroGestureIsActive != isActive else { return }
        immersiveHeroGestureIsActive = isActive
        if isActive {
            immersiveTextSamplingCoordinator.cancel()
        } else if let url = currentImmersiveImageURL,
                  let geometry = immersiveTextSamplingCoordinator.latestGeometry ?? immersiveTextSampleGeometry {
            scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: true)
        }
    }

    private func releaseImmersiveSamplingFrame(_ frame: CGRect) -> CGRect? {
        guard 探索发行版本沉浸取样框有效(frame) else { return nil }
        func snapped(_ value: CGFloat) -> CGFloat { (value * 2).rounded() / 2 }
        let result = CGRect(x: snapped(frame.minX), y: snapped(frame.minY), width: snapped(frame.width), height: snapped(frame.height))
        return 探索发行版本沉浸取样框有效(result) ? result : nil
    }

    /// iPhone Duo 横向半折叠时，信息卡移到折叠区域一侧，与视觉小说详情的单栏处理一致。
    @ViewBuilder
    private var releasePrimaryInformationAvoidingFold: some View {
        if horizontalSizeClass == .regular {
            沉浸详情等高双栏布局(divisionFrame: immersiveDivisionFrame) {
                releasePrimaryInformation
            }
        } else {
            releasePrimaryInformation
        }
    }

    private var releasePrimaryInformation: some View {
        let textStyle = releaseMetadataTextStyle(for: "metadata")
        let titleStyle = releaseMetadataTextStyle(for: "metadata.title")
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    标题工具.生成富文本(
                        文本: displayedReleaseTitle,
                        isJapanese: staffNameLang == .original,
                        基础大小: 24,
                        是粗体: true,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                )
                .沉浸详情文字前景色(titleStyle.primary, style: titleStyle)
                .fixedSize(horizontal: false, vertical: true)

                if let alternateReleaseTitle {
                    Text(
                        标题工具.生成富文本(
                            文本: alternateReleaseTitle,
                            isJapanese: staffNameLang != .original,
                            基础大小: 16,
                            语言来源已知: false,
                            空格视为日语: true
                        )
                    )
                    .沉浸详情文字前景色(titleStyle.secondary, style: titleStyle)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .沉浸详情文字阴影(titleStyle)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = displayedReleaseTitle
                } label: {
                    Label("拷贝标题", systemImage: "doc.on.doc")
                }

                if let alternateReleaseTitle {
                    Button {
                        UIPasteboard.general.string = alternateReleaseTitle
                    } label: {
                        Label("拷贝副标题", systemImage: "doc.on.doc")
                    }
                }
            }
            .发行版本沉浸取样框(["metadata.title"])

            releasePrimaryMetadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .沉浸详情玻璃背景(
            immersiveDetailAppearance,
            sample: textStyle.sample,
            fallbackTint: immersiveSystemGlassTint,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .发行版本沉浸取样框(["metadata"])
        .environment(\.colorScheme, titleStyle.colorScheme)
        .opacity(releaseImmersivePrimaryInformationIsVisible ? 1 : 0)
        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
    }

    private var releasePrimaryMetadata: some View {
        let rowSpacing: CGFloat = horizontalSizeClass == .regular ? 14 : 8
        return LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 16, alignment: .topLeading),
                GridItem(.flexible(minimum: 0), alignment: .topLeading)
            ],
            alignment: .leading,
            spacing: rowSpacing
        ) {
            if let released = displayedItem.released {
                releaseMetadataItem(
                    icon: "calendar",
                    title: "发行日期",
                    text: released,
                    textStyle: releaseMetadataTextStyle(for: "metadata.release"),
                    sampleKey: "metadata.release"
                )
            }

            if let releaseLanguagesText {
                releaseMetadataItem(
                    icon: "character.book.closed",
                    title: "语言",
                    text: releaseLanguagesText,
                    textStyle: releaseMetadataTextStyle(for: "metadata.rating"),
                    sampleKey: "metadata.rating"
                )
            }

            if let releaseType = displayedItem.releaseType {
                releaseMetadataItem(
                    icon: "shippingbox",
                    title: "发行类型",
                    text: releaseTypeName(releaseType),
                    textStyle: releaseMetadataTextStyle(for: "metadata.status"),
                    sampleKey: "metadata.status"
                )
            }
        }
    }

    private func releaseMetadataItem(
        icon: String,
        title: LocalizedStringKey,
        text: String,
        valueLineLimit: Int = 2,
        textStyle: 沉浸详情文字样式,
        sampleKey: String
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.subheadline)
                .沉浸详情文字前景色(textStyle.secondary, style: textStyle)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .沉浸详情文字前景色(textStyle.tertiary, style: textStyle)

                Text(verbatim: text)
                    .font(.subheadline.weight(.regular))
                    .沉浸详情文字前景色(textStyle.primary, style: textStyle)
                    .lineLimit(valueLineLimit)
            }
        }
        // 按文字实际占的宽度取样，不含格子里的空白。
        .发行版本沉浸取样框([sampleKey])
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(textStyle)
    }

    private var releaseContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            releaseFactsSection
            releaseProducersSection
            releaseNotesSection
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
    }

    private var releaseFactsSection: some View {
        releaseCard(title: "版本信息") {
            VStack(spacing: 0) {
                ForEach(Array(releaseFactItems.enumerated()), id: \.element.id) { index, item in
                    if let value = item.value {
                        releaseFact(item.title, value: value, icon: item.icon)
                    } else {
                        releaseBooleanFact(item.title, icon: item.icon)
                    }
                    if index < releaseFactItems.count - 1 {
                        releaseFactDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var releaseProducersSection: some View {
        if let producers = displayedItem.producers, !producers.isEmpty {
            releaseCard(title: "开发与发行商") {
                VStack(spacing: 0) {
                    ForEach(Array(producers.enumerated()), id: \.element.id) { index, producer in
                        releaseProducerRow(producer)
                        if index < producers.count - 1 {
                            releaseFactDivider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var releaseNotesSection: some View {
        if let notes = displayedItem.notes, !notes.isEmpty {
            releaseCard(title: "备注") {
                Text(verbatim: notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .textSelection(.enabled)
            }
        }
    }

    private func releaseCard<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let textStyle = 沉浸详情文字样式(
            appearance: .standard,
            sample: nil,
            fallbackColorScheme: colorScheme
        )
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .沉浸详情文字前景色(textStyle.primary, style: textStyle)
                .沉浸详情文字阴影(textStyle)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, colorScheme)
    }

    private func releaseFact(
        _ label: LocalizedStringKey,
        value: String,
        icon: String
    ) -> some View {
        releaseFactLayout(label, icon: icon) {
            Text(verbatim: value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseBooleanFact(
        _ label: LocalizedStringKey,
        icon: String
    ) -> some View {
        releaseFactLayout(label, icon: icon) {
            Text("是")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func releaseFactLayout<Value: View>(
        _ label: LocalizedStringKey,
        icon: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                value()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
    }

    private func releaseFactDivider() -> some View {
        Divider()
            .padding(.leading, 50)
    }

    private var releaseFactItems: [探索发行版本信息项] {
        var items: [探索发行版本信息项] = []

        if let platforms = displayedItem.platforms, !platforms.isEmpty {
            items.append(
                .init(
                    id: "platforms",
                    title: "平台",
                    value: ListFormatter.localizedString(byJoining: platforms.map { VNDB显示工具.平台名称($0) }),
                    icon: "gamecontroller"
                )
            )
        }
        if let engine = displayedItem.engine, !engine.isEmpty {
            items.append(.init(id: "engine", title: "引擎", value: engine, icon: "gearshape.2"))
        }
        if let minimumAge = displayedItem.minimumAge {
            items.append(
                .init(
                    id: "minimum-age",
                    title: "分级",
                    value: "\(minimumAge.formatted())+",
                    icon: "person.badge.shield.checkmark"
                )
            )
        }
        if let resolution = displayedItem.resolution {
            items.append(.init(id: "resolution", title: "分辨率", value: resolutionText(resolution), icon: "rectangle.on.rectangle"))
        }
        if let voiced = displayedItem.voiced {
            items.append(.init(id: "voiced", title: "语音", value: voicedText(voiced), icon: "waveform"))
        }
        if let releaseMediaText {
            items.append(.init(id: "media", title: "介质", value: releaseMediaText, icon: "opticaldisc"))
        }
        if displayedItem.patch == true {
            items.append(.init(id: "patch", title: "补丁", value: nil, icon: "wrench.and.screwdriver"))
        }
        if displayedItem.freeware == true {
            items.append(.init(id: "freeware", title: "免费版本", value: nil, icon: "gift"))
        }
        if displayedItem.uncensored == true {
            items.append(.init(id: "uncensored", title: "无码版本", value: nil, icon: "eye"))
        }
        if displayedItem.official == true {
            items.append(.init(id: "official", title: "官方版本", value: nil, icon: "checkmark.seal"))
        }
        if displayedItem.hasAdultContent == true {
            items.append(.init(id: "adult-content", title: "成人内容", value: nil, icon: "exclamationmark.triangle"))
        }
        if let gtin = displayedItem.gtin, !gtin.isEmpty {
            items.append(.init(id: "gtin", title: "GTIN", value: gtin, icon: "barcode"))
        }
        if let catalog = displayedItem.catalog, !catalog.isEmpty {
            items.append(.init(id: "catalog", title: "目录编号", value: catalog, icon: "list.number"))
        }
        return items
    }

    private func releaseProducerRow(
        _ producer: 探索发行会社
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "building.2")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                多语言列表文本(
                    文本: 人物名称工具.显示名称(
                        name: producer.name,
                        original: producer.original,
                        偏好: staffNameLang
                    ),
                    isJapanese: staffNameLang == .original,
                    层级: .主标题,
                    日文字体名称: "HiraginoSans-W4",
                    系统字体粗细: .regular,
                    语言来源已知: false,
                    空格视为日语: true
                )
                let roles = [
                    producer.developer == true ? String(localized: "开发商") : nil,
                    producer.publisher == true ? String(localized: "发行商") : nil
                ].compactMap { $0 }
                if !roles.isEmpty {
                    Text(verbatim: ListFormatter.localizedString(byJoining: roles))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var releaseInformationOverlap: CGFloat {
        horizontalSizeClass == .regular ? 154 : 82
    }

    private func releaseTypeName(_ value: String) -> String {
        switch value.lowercased() {
        case "complete": return String(localized: "完整版本")
        case "partial": return String(localized: "部分版本")
        case "trial": return String(localized: "试玩版本")
        case "patch": return String(localized: "补丁")
        case "add-on": return String(localized: "追加内容")
        case "demo": return String(localized: "演示版本")
        case "other": return String(localized: "其他")
        default: return value
        }
    }

    private func resolutionText(_ resolution: 探索发行分辨率) -> String {
        switch resolution {
        case let .dimensions(dimensions):
            return dimensions.map(String.init).joined(separator: "×")
        case let .text(value):
            return value
        }
    }

    private func voicedText(_ value: Int) -> String {
        switch value {
        case 0: return String(localized: "无语音")
        case 1: return String(localized: "部分语音")
        case 2: return String(localized: "完整语音")
        default: return value.formatted()
        }
    }

    private var displayedItem: 探索发行版本 {
        detailedItem ?? item
    }

    private var displayedReleaseTitle: String {
        人物名称工具.显示名称(
            name: displayedItem.title,
            original: displayedItem.alttitle,
            偏好: staffNameLang
        )
    }

    private var alternateReleaseTitle: String? {
        人物名称工具.备用名称(
            name: displayedItem.title,
            original: displayedItem.alttitle,
            偏好: staffNameLang
        )
    }

    private var releaseLanguagesText: String? {
        guard let languages = displayedItem.languages,
              !languages.isEmpty else { return nil }
        let text = ListFormatter.localizedString(
            byJoining: languages.map { VNDB显示工具.语言名称($0.lang) }
        )
        return text.isEmpty ? nil : text
    }

    private var releaseMediaText: String? {
        guard let media = displayedItem.media,
              !media.isEmpty else { return nil }
        let text = ListFormatter.localizedString(
            byJoining: media.map { medium in
                medium.quantity == 1
                    ? medium.medium
                    : "\(medium.medium)×\(medium.quantity.formatted())"
            }
        )
        return text.isEmpty ? nil : text
    }

    private var includedVisualNovels: [探索发行作品] {
        if let visualNovels = displayedItem.visualNovels,
           !visualNovels.isEmpty {
            return visualNovels
        }
        return item.visualNovels ?? []
    }

    private var showsIncludedWorksToolbarControl: Bool {
        !openedFromVisualNovelDetail && !includedVisualNovels.isEmpty
    }

    private var validExternalLinks: [(link: 探索外链, url: URL)] {
        (displayedItem.externalLinks ?? []).compactMap { link in
            guard let url = URL(string: link.url),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else { return nil }
            return (link, url)
        }
    }

    @ViewBuilder
    private var includedWorksToolbarControl: some View {
        if includedVisualNovels.count == 1,
           let visualNovel = includedVisualNovels.first {
            NavigationLink {
                includedVisualNovelDestination(visualNovel)
            } label: {
                Image(systemName: 搜索范围.visualNovel.systemImage)
                    .frame(width: 24, height: 24)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("查看包含作品")
        } else {
            Menu {
                ForEach(includedVisualNovels) { visualNovel in
                    NavigationLink {
                        includedVisualNovelDestination(visualNovel)
                    } label: {
                        Text(verbatim: displayedTitle(for: visualNovel).text)
                    }
                }
            } label: {
                Image(systemName: 搜索范围.visualNovel.systemImage)
                    .frame(width: 24, height: 24)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("选择包含作品")
        }
    }

    @ViewBuilder
    private var externalLinksToolbarControl: some View {
        if validExternalLinks.count == 1,
           let externalLink = validExternalLinks.first {
            Button {
                browserURL = externalLink.url
            } label: {
                Image(systemName: "link")
                    .font(.body)
            }
            .accessibilityLabel("外部链接")
        } else {
            Menu {
                ForEach(Array(validExternalLinks.enumerated()), id: \.offset) { _, externalLink in
                    Button {
                        browserURL = externalLink.url
                    } label: {
                        Label {
                            Text(verbatim: externalLinkTitle(externalLink.link))
                        } icon: {
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }
            } label: {
                Image(systemName: "link")
                    .font(.body)
            }
            .accessibilityLabel("外部链接")
        }
    }

    private func externalLinkTitle(_ link: 探索外链) -> String {
        if let name = link.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        let label = link.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? link.url : label
    }

    private func includedVisualNovelDestination(
        _ visualNovel: 探索发行作品
    ) -> some View {
        视觉小说详情(
            vnID: visualNovel.id,
            auth: auth,
            initialTitle: visualNovel.title,
            initialTitles: visualNovel.详情多语言标题,
            initialImageURL: visualNovel.image?.url,
            initialImageSexual: visualNovel.image?.sexual,
            initialImageViolence: visualNovel.image?.violence,
            initialImageDimensions: visualNovel.image?.dims
        )
    }

    private func displayedTitle(
        for vn: 探索发行作品
    ) -> 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: vn.titles?.map {
                用户多语言标题(
                    lang: $0.lang,
                    title: $0.title,
                    latin: $0.latin,
                    official: $0.official ?? false,
                    main: $0.main ?? false
                )
            },
            defaultTitle: vn.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }
}
