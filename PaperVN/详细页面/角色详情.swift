import Foundation
import SwiftUI
@preconcurrency import Translation
import UIKit

private struct 角色名称拷贝项目: Identifiable {
    let id: String
    let label: String
    let value: String
}

private enum 角色信息提示: String, Identifiable {
    case bloodType

    var id: String { rawValue }
}

private enum 角色沉浸取样框PreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func 角色沉浸取样框(_ keys: [String]) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(
                    in: .named("ImmersiveCharacterSampling")
                )
                if 角色沉浸取样框有效(frame) {
                    Color.clear.preference(
                        key: 角色沉浸取样框PreferenceKey.self,
                        value: Dictionary(
                            uniqueKeysWithValues: keys.map { ($0, frame) }
                        )
                    )
                } else {
                    Color.clear
                }
            }
        }
    }

    @ViewBuilder
    func 角色沉浸取样框(_ frames: [String: CGRect]) -> some View {
        if frames.values.allSatisfy(角色沉浸取样框有效) {
            preference(
                key: 角色沉浸取样框PreferenceKey.self,
                value: frames
            )
        } else {
            self
        }
    }
}

private func 角色沉浸取样框有效(_ frame: CGRect) -> Bool {
    frame.minX.isFinite
        && frame.minY.isFinite
        && frame.width.isFinite
        && frame.height.isFinite
        && frame.width > 0
        && frame.height > 0
}

struct 角色详情: View {
    let characterID: String
    private let initialName: String
    private let initialOriginal: String?
    private let initialAliases: [String]?
    private let initialImage: 角色图片?
    let relationships: [视觉小说声优关系]

    @ObservedObject private var auth: 用户登录
    @Namespace private var descriptionNamespace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.详情内容限制方式覆盖)
    private var contentRestrictionMethodOverride
    @AppStorage(活动地区偏好.设置键)
    private var activityRegionSelection = 活动地区偏好.默认值

    @State private var detail: 角色详细信息?
    @StateObject private var eventModel = PaperVN活动视图模型()
    @State private var errorMessage: String?
    @State private var isLoadingDetail = true
    @State private var detailLoadGeneration = 0
    @State private var revealImage = false
    @State private var immersiveViewportSize: CGSize = .zero
    @State private var immersiveDivisionFrame: CGRect?
    @State private var revealedRelatedImageIDs: Set<String> = []
    @State private var revealedTraitIDs: Set<String> = []
    @State private var showTranslatedTraits = false
    @State private var showAllTraits = false
    @State private var traitsContentOpacity = 1.0
    @State private var isSwitchingTraitLanguage = false
    @State private var characterInfoPopover: 角色信息提示?
    @State private var showDescriptionSheet = false
    @State private var showTranslatedDescription = false
    @State private var translatedDescription: String?
    @State private var isTranslatingDescription = false
    @State private var descriptionTranslationConfiguration:
        TranslationSession.Configuration?
    @State private var translationError: String?
    @State private var manualDescription: String?
    @State private var hasFinishedManualDescriptionLookup = false
    @State private var manualDescriptionLookupTimedOut = false
    @State private var manualDescriptionLookupKey: String?
    @State private var manualDescriptionPresentationOpacity = 1.0
    @State private var immersiveTextSamples:
        [String: 沉浸玻璃文字取样结果]
    @State private var immersiveTextSampleURL: URL?
    @State private var immersiveTextRevealURL: URL?
    @State private var immersiveTextSampleGeometry:
        沉浸封面文字取样几何?
    @State private var immersiveTextSamplingCoordinator =
        沉浸封面文字取样任务协调器()
    @State private var immersiveHeroGestureIsActive = false
    @State private var immersiveAutomaticAppearance: 沉浸详情外观?
    @State private var immersiveAutomaticAppearanceURL: URL?
    @State private var immersiveLoadedHeroImage: Image?
    @State private var immersiveLoadedHeroImageURL: URL?
    @State private var immersiveLoadedHeroAspectRatio: CGFloat?
    @State private var immersiveOutgoingHeroImage: Image?
    @State private var immersiveHeroImageTransitionProgress: CGFloat = 1
    @State private var immersiveHeroImageTransitionGeneration = 0
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()

    @AppStorage("staffNameLang")
    private var nameLanguage: 制作人员语言 = .romaji
    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
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

    private var contentRestrictionMethod: 内容限制方式 {
        contentRestrictionMethodOverride ?? storedContentRestrictionMethod
    }
    @AppStorage("spoilerTagBlurLevel")
    private var spoilerTagBlurLevel = 剧透标签模糊设置.majorOnly.rawValue
    @AppStorage("descriptionTranslationLanguage")
    private var targetLanguage: 简介翻译语言 = .simplifiedChinese
    @AppStorage(VNDB简介翻译模式.设置键)
    private var descriptionTranslationMode: VNDB简介翻译模式 = .openSourceFetch
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var immersiveDetailAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }

    init(auth: 用户登录, relationship: 视觉小说声优关系) {
        self.init(
            characterID: relationship.character.id,
            auth: auth,
            initialName: relationship.character.name,
            initialOriginal: relationship.character.original,
            initialAliases: relationship.character.aliases,
            initialImage: relationship.character.image,
            relationships: [relationship]
        )
    }

    init(auth: 用户登录, relationships: [视觉小说声优关系]) {
        precondition(!relationships.isEmpty, "角色声优关系不能为空")
        let character = relationships[0].character
        self.init(
            characterID: character.id,
            auth: auth,
            initialName: character.name,
            initialOriginal: character.original,
            initialAliases: character.aliases,
            initialImage: character.image,
            relationships: relationships
        )
    }

    init(
        characterID: String,
        auth: 用户登录,
        initialName: String,
        initialOriginal: String? = nil,
        initialAliases: [String]? = nil,
        initialImage: 角色图片? = nil,
        relationships: [视觉小说声优关系] = []
    ) {
        let cachedDetail = VNDB服务.shared.loadCachedCharacterDetail(
            characterID: characterID
        )

        self.characterID = characterID
        _auth = ObservedObject(wrappedValue: auth)
        self.initialName = initialName
        self.initialOriginal = initialOriginal
        self.initialAliases = initialAliases
        self.initialImage = initialImage
        self.relationships = relationships
        _detail = State(initialValue: cachedDetail)
        _immersiveTextSamples = State(initialValue: [:])
        _immersiveTextSampleURL = State(initialValue: nil)
        _immersiveTextRevealURL = State(initialValue: nil)
    }

    private var displayedDetail: 角色详细信息 {
        detail ?? 角色详细信息(
            id: characterID,
            name: initialName,
            original: initialOriginal,
            aliases: initialAliases,
            description: nil,
            image: initialImage,
            blood_type: nil,
            height: nil,
            weight: nil,
            bust: nil,
            waist: nil,
            hips: nil,
            cup: nil,
            age: nil,
            birthday: nil,
            sex: nil,
            gender: nil,
            vns: nil,
            traits: nil
        )
    }

    private var characterName: String {
        人物名称工具.显示名称(
            name: detail?.name ?? initialName,
            original: detail?.original ?? initialOriginal,
            偏好: nameLanguage
        )
    }

    private func voiceActorName(
        for relationship: 视觉小说声优关系
    ) -> String {
        人物名称工具.显示名称(
            name: relationship.staff.name,
            original: relationship.staff.original,
            偏好: nameLanguage
        )
    }

    var body: some View {
        immersiveContent(displayedDetail)
        .navigationTitle(characterName)
        .平台柔和滚动边缘(for: .top)
        .平台隐藏导航标题占位(characterName)
        .平台内联导航标题()
        .task(
            id: "\(characterID)|\(targetLanguage.rawValue)|\(descriptionTranslationMode.rawValue)"
        ) {
            let translationMode = VNDB简介翻译模式.current
            let lookupKey = manualDescriptionLookupKeyValue(
                mode: translationMode
            )
            let cachedResult = VNDB简介人工翻译.译文缓存结果(
                for: characterID,
                type: .character,
                language: targetLanguage,
                mode: translationMode
            )
            let hasReusableLookupResult = cachedResult.isResolved
                || (
                    manualDescriptionLookupKey == lookupKey
                    && hasFinishedManualDescriptionLookup
                )

            if !hasReusableLookupResult {
                hasFinishedManualDescriptionLookup = false
                manualDescriptionLookupTimedOut = false
                manualDescription = nil
                translatedDescription = nil
                showTranslatedDescription = false
                manualDescriptionLookupKey = lookupKey
                manualDescriptionPresentationOpacity = 1
            } else {
                if let cachedTranslation = cachedResult.translation {
                    manualDescription = cachedTranslation
                }
                hasFinishedManualDescriptionLookup = true
                manualDescriptionLookupTimedOut = false
                manualDescriptionLookupKey = lookupKey
                manualDescriptionPresentationOpacity = 1
            }

            async let translation = VNDB简介人工翻译.译文结果(
                for: characterID,
                type: .character,
                language: targetLanguage,
                mode: translationMode
            )
            let timeoutTask: Task<Void, Never>?
            if hasReusableLookupResult {
                timeoutTask = nil
            } else {
                timeoutTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        return
                    }
                    guard !hasFinishedManualDescriptionLookup else { return }
                    updateManualDescriptionPresentation(for: lookupKey) {
                        manualDescriptionLookupTimedOut = true
                    }
                }
            }
            await loadDetail(forceRefresh: true)
            let resolvedResult = await translation
            timeoutTask?.cancel()

            guard !hasReusableLookupResult else {
                guard resolvedResult.isResolved,
                      resolvedResult.translation != manualDescription else {
                    return
                }
                updateManualDescriptionPresentation(for: lookupKey) {
                    manualDescription = resolvedResult.translation
                }
                return
            }
            updateManualDescriptionPresentation(for: lookupKey) {
                if let resolvedTranslation = resolvedResult.translation {
                    manualDescription = resolvedTranslation
                }
                hasFinishedManualDescriptionLookup = true
            }
        }
        .task(id: "events|\(eventActorNames.joined(separator: "|"))|\(eventRelatedTerms.joined(separator: "|"))|\(activityRegionSelection)") {
            guard !eventActorNames.isEmpty else { return }
            await eventModel.load(
                actorNames: eventActorNames,
                relatedTerms: eventRelatedTerms
            )
        }
        .onChange(of: colorScheme) { _, _ in
            immersiveTextSamples = [:]
            immersiveTextSampleURL = nil
            immersiveTextRevealURL = nil
            immersiveAutomaticAppearance = nil
            immersiveAutomaticAppearanceURL = nil
            refreshImmersiveTextSamplesForCurrentAppearance()
        }
        .onChange(of: isLoadingDetail) { _, isLoading in
            guard !isLoading else { return }
            scheduleImmersiveAppearanceRefresh()
        }
        .translationTask(descriptionTranslationConfiguration) { session in
            await translateDescription(using: session)
        }
        .navigationDestination(isPresented: $showAllTraits) {
            更多特征页面(
                traits: displayedDetail.traits ?? [],
                showTranslatedTraits: $showTranslatedTraits
            )
        }
        .sheet(isPresented: $showDescriptionSheet) {
            if let detail {
                characterDescriptionSheet(detail)
                    .navigationTransition(.zoom(
                        sourceID: "CharacterDescriptionSheet",
                        in: descriptionNamespace
                    ))
            }
        }
        .overlay(alignment: .bottom) {
            模糊解除提示(
                isPresented: blurRevealConfirmation.isPromptVisible
            )
            .padding(.bottom, 18)
        }
        .onDisappear {
            blurRevealConfirmation.cancel()
            immersiveTextSamplingCoordinator.cancel()
        }
        .alert(
            "无法翻译",
            isPresented: Binding(
                get: { translationError != nil },
                set: { if !$0 { translationError = nil } }
            )
        ) {
            Button("好") {
                translationError = nil
            }
        } message: {
            Text(verbatim: translationError ?? "")
        }
    }

    private func immersiveContent(_ detail: 角色详细信息) -> some View {
        let primaryInformation = immersivePrimaryInformationPresentation(
            detail
        )

        return ZStack {
            immersiveBackdrop(detail)

            ScrollView(.vertical) {
                沉浸封面详情内容(
                    onGestureActivityChanged: updateImmersiveHeroGestureActivity
                ) { dragContext in
                    immersiveHeroAndPrimaryInformation(
                        detail,
                        dragContext: dragContext,
                        primaryInformation: primaryInformation
                    )
                } content: {
                    if !uniqueVoiceRelationships.isEmpty
                        || isShowingInitialSkeleton
                        || detail.vns?.isEmpty == false
                        || errorMessage != nil {
                        if !uniqueVoiceRelationships.isEmpty {
                            immersiveVoiceActors
                        }

                        if isShowingInitialSkeleton {
                            immersiveLoadingContent
                        } else {
                            immersiveAppearances(detail)
                        }

                        immersiveFailureCard
                            .padding(
                                .horizontal,
                                immersivePageHorizontalPadding
                            )
                    }

                    if !uniqueVoiceRelationships.isEmpty,
                       shouldShowEventSection {
                        PaperVN活动栏目(
                            events: eventModel.events,
                            isLoading: eventModel.isLoading,
                            hasLoaded: eventModel.hasLoaded,
                            errorMessage: eventModel.errorMessage,
                            cardScene: .detail,
                            液态玻璃外观: resolvedImmersiveDetailAppearance,
                            液态玻璃回退色调: immersiveSystemGlassTint,
                            horizontalInset: immersivePageHorizontalPadding,
                            hidesWhenEmpty: true,
                            onRetry: {
                                Task {
                                    await eventModel.load(
                                        actorNames: eventActorNames,
                                        relatedTerms: eventRelatedTerms,
                                        forceRefresh: true
                                    )
                                }
                            }
                        )
                        .padding(.horizontal, immersivePageHorizontalPadding)
                        .transition(.opacity)
                    }
                }
            }
            .平台横向内容可溢出()
            .scrollBounceBehavior(.always, axes: .vertical)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            immersiveViewportSize = size
        }
        .modifier(DivisionFrameModifier(divisionFrame: $immersiveDivisionFrame))
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "ImmersiveCharacterScroll")
        .onPreferenceChange(角色沉浸取样框PreferenceKey.self) { frames in
            updateImmersiveTextSampleGeometry(from: frames)
        }
        .onAppear {
            scheduleImmersiveAppearanceRefresh()
        }
        .ignoresSafeArea(edges: .top)
        .平台沉浸导航栏()
    }

    private func immersiveHeroAndPrimaryInformation<PrimaryInformation: View>(
        _ detail: 角色详细信息,
        dragContext: 沉浸封面拖动上下文,
        primaryInformation: PrimaryInformation
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            immersiveHero(detail, dragContext: dragContext)
                .ignoresSafeArea(.container, edges: .horizontal)

            let overlap = immersiveDescriptionOverlap
            let cardProgress = min(max(dragContext.progress, 0), 1)
            let cardOffset = overlap * cardProgress
            primaryInformation
                .padding(.top, -overlap)
                .padding(.bottom, cardOffset)
                .compositingGroup()
                .offset(y: cardOffset)
                .accessibilityHidden(
                    !immersivePrimaryInformationIsVisible(for: detail)
                )
        }
        .coordinateSpace(name: "ImmersiveCharacterSampling")
    }

    private var immersivePageHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
    }

    private var immersiveDescriptionOverlap: CGFloat {
        horizontalSizeClass == .regular ? 110 : 82
    }

    private func immersivePrimaryInformation(
        _ detail: 角色详细信息,
        showsContent: Bool = true
    ) -> AnyView {
        let hasDescription = detail.cleanDescription?.isEmpty == false
        let showsLoadingPlaceholders = self.detail == nil
        let showsDescription = showsContent && shouldDisplayDescription

        return AnyView(VStack(
            alignment: .leading,
            spacing: 沉浸详情布局.主要信息间距
        ) {
            if horizontalSizeClass == .regular {
                沉浸详情等高双栏布局(
                    spacing: 16,
                    divisionFrame: immersiveDivisionFrame,
                    horizontalInset: immersivePageHorizontalPadding
                ) {
                    AnyView(immersiveIdentity(
                        detail,
                        fillsAvailableHeight:
                            hasDescription || showsLoadingPlaceholders,
                        showsContent: showsContent
                    ))
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if hasDescription || showsLoadingPlaceholders {
                        AnyView(immersiveDescription(
                            detail,
                            outerHorizontalPadding: 0,
                            fillsAvailableHeight: true,
                            showsContent: showsDescription
                        ))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .transition(.identity)
                    }
                }
                .padding(.horizontal, immersivePageHorizontalPadding)
                .transition(.identity)
            } else {
                AnyView(immersiveIdentity(detail, showsContent: showsContent))
                    .padding(.horizontal, immersivePageHorizontalPadding)
                    .transition(.identity)

                if hasDescription || showsLoadingPlaceholders {
                    AnyView(immersiveDescription(
                        detail,
                        outerHorizontalPadding: immersivePageHorizontalPadding,
                        showsContent: showsDescription
                    ))
                    .transition(.identity)
                }
            }

            AnyView(immersiveTraits(detail))
                .opacity(showsContent ? 1 : 0)
                .allowsHitTesting(showsContent)
                .transition(.identity)
        }
        .frame(maxWidth: .infinity, alignment: .leading))
    }

    private func immersiveBackdrop(_ detail: 角色详细信息) -> some View {
        GeometryReader { proxy in
            ZStack {
                Color.平台系统背景

                if !immersiveImageURLs(for: detail).isEmpty {
                    immersiveBackdropImageLayer(
                        loadedImage: immersivePresentedHeroImage
                    )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.55)
                        .blur(radius: 96)
                        .saturation(1.18)
                        .opacity(0.56)

                    ForEach(
                        immersiveImageURLs(for: detail),
                        id: \.absoluteString
                    ) { url in
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

                Color.平台系统背景.opacity(0.2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private func immersiveHero(
        _ detail: 角色详细信息,
        dragContext: 沉浸封面拖动上下文
    ) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width.isFinite
                ? max(proxy.size.width, 0)
                : 0
            let heroHeight = proxy.size.height.isFinite
                ? max(proxy.size.height, 0)
                : 0
            let fadeOverflow: CGFloat = 72
            let heroFrame = proxy.frame(
                in: .named("ImmersiveCharacterScroll")
            )
            let samplingFrame = proxy.frame(
                in: .named("ImmersiveCharacterSampling")
            )
            let pullDown = heroFrame.minY.isFinite
                ? max(heroFrame.minY, 0)
                : 0
            let informationExtension = immersiveHeroInformationExtension(
                for: detail
            )
            let expandedHeroHeight = immersiveExpandedHeroHeight(
                width: width,
                collapsedHeight: heroHeight
            )
            let transitionProgress = min(
                max(dragContext.progress, 0),
                1
            )
            let expandedImageTopInset = max(
                (immersiveViewportSize.height - expandedHeroHeight) / 2,
                0
            )
            let imageTopInset = expandedImageTopInset
                * transitionProgress
            let layoutHeroHeight = heroHeight
                + (expandedHeroHeight - heroHeight)
                    * transitionProgress
            let renderedHeight = layoutHeroHeight
                + imageTopInset
                + pullDown
                + (fadeOverflow + informationExtension)
                    * (1 - transitionProgress)
            let sampleImageFrame = CGRect(
                x: samplingFrame.minX,
                y: samplingFrame.minY - pullDown
                    + (horizontalSizeClass == .regular ? -60 : 0),
                width: width,
                height: heroHeight + fadeOverflow + informationExtension
            )
            let needsRestriction = shouldBlurImage(
                sexual: detail.image?.sexual,
                violence: detail.image?.violence
            )
            let isRestricted = needsRestriction && (
                contentRestrictionMethod == .hidden || !revealImage
            )

            ZStack(alignment: .top) {
                if !immersiveImageURLs(for: detail).isEmpty {
                    沉浸封面拖动图层(
                        isExpanded: dragContext.isExpanded,
                        hasImage: true,
                        progress: dragContext.progressBinding,
                        onExpansionChanged:
                            dragContext.onExpansionChanged,
                        onBounceChanged: dragContext.onBounceChanged,
                        onGestureActivityChanged:
                            dragContext.onGestureActivityChanged,
                        onTap: {
                            guard isRestricted,
                                  contentRestrictionMethod == .blurred,
                                  canRevealImage(sexual: detail.image?.sexual) else {
                                return
                            }
                            blurRevealConfirmation.request(id: "character-image") {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    revealImage = true
                                }
                            }
                        }
                    ) { pullProgress in
                        immersiveHeroImagePresentation(
                            loadedImage: immersivePresentedHeroImage,
                            extendsThroughInformation: informationExtension > 0,
                            width: width,
                            heroHeight: heroHeight,
                            renderedHeight: renderedHeight,
                            backgroundHeight: heroHeight
                                + fadeOverflow
                                + informationExtension,
                            imageTopInset: imageTopInset,
                            pullProgress: pullProgress
                        )
                        .应用不安全内容限制(
                            isRestricted,
                            method: contentRestrictionMethod,
                            blurRadius: 28
                        )
                        .animation(
                            .easeInOut(duration: 0.28),
                            value: revealImage
                        )
                    }
                } else if isShowingInitialSkeleton {
                    ZStack {
                        Color.secondary.opacity(0.12)
                            .mask {
                                LinearGradient(
                                    stops: [
                                        .init(color: .white, location: 0),
                                        .init(color: .white, location: 0.58),
                                        .init(
                                            color: .white.opacity(0.42),
                                            location: 0.82
                                        ),
                                        .init(color: .clear, location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                        ProgressView()
                    }
                    .frame(width: width, height: renderedHeight)
                } else {
                    平台内容不可用视图(
                        "无角色图片",
                        systemImage: "person.crop.rectangle"
                    )
                    .frame(width: width, height: renderedHeight)
                }
            }
            .frame(width: width, height: renderedHeight)
            .offset(y: -pullDown)
            .角色沉浸取样框(["image": sampleImageFrame])
        }
        .frame(height: horizontalSizeClass == .regular ? 420 : nil)
        .aspectRatio(
            horizontalSizeClass == .regular ? nil : 1 / 0.72,
            contentMode: .fit
        )
        .frame(maxWidth: .infinity)
        .padding(
            .bottom,
            immersiveHeroLayoutExtension(
                pullProgress: dragContext.progress
            )
        )
        .offset(y: -dragContext.bounceOffset)
    }

    @ViewBuilder
    private func immersiveHeroImagePresentation(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        width: CGFloat,
        heroHeight: CGFloat,
        renderedHeight: CGFloat,
        backgroundHeight: CGFloat,
        imageTopInset: CGFloat,
        pullProgress: CGFloat
    ) -> some View {
        let transitionProgress = min(max(pullProgress, 0), 1)
        let sourceAspectRatio = immersiveHeroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(
            min(width - horizontalInset, heroHeight * sourceAspectRatio),
            1
        )
        let expandedHeight = max(expandedWidth / sourceAspectRatio, 1)
        let imageWidth = width
            + (expandedWidth - width) * transitionProgress
        let presentationHeight = backgroundHeight
            + (expandedHeight - backgroundHeight) * transitionProgress
        let cornerRadius = 28 * transitionProgress

        immersiveHeroImage(
            loadedImage: loadedImage,
            extendsThroughInformation: extendsThroughInformation,
            revealProgress: transitionProgress
        )
        .frame(width: imageWidth, height: presentationHeight)
        .padding(
            .bottom,
            沉浸详情布局.背景扩展透明缓冲
        )
        .平台背景延伸效果()
        .padding(
            .bottom,
            -沉浸详情布局.背景扩展透明缓冲
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .frame(maxWidth: .infinity, alignment: .top)
        .offset(y: imageTopInset)
        .frame(width: width, height: renderedHeight, alignment: .top)
    }

    private func immersiveExpandedHeroHeight(
        width: CGFloat,
        collapsedHeight: CGFloat
    ) -> CGFloat {
        let sourceAspectRatio = immersiveHeroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(
            min(width - horizontalInset, collapsedHeight * sourceAspectRatio),
            1
        )
        return max(expandedWidth / sourceAspectRatio, 1)
    }

    private func immersiveHeroLayoutExtension(
        pullProgress: CGFloat
    ) -> CGFloat {
        let width = immersiveViewportSize.width
        guard width > 0, immersiveViewportSize.height > 0 else { return 0 }
        let transitionProgress = min(
            max(pullProgress, 0),
            1
        )
        let collapsedHeight = horizontalSizeClass == .regular
            ? CGFloat(420)
            : width * 0.72
        let expandedHeight = immersiveExpandedHeroHeight(
            width: width,
            collapsedHeight: collapsedHeight
        )
        let expandedTopInset = max(
            (immersiveViewportSize.height - expandedHeight) / 2,
            0
        )
        return max(
            expandedTopInset + expandedHeight - collapsedHeight,
            0
        ) * transitionProgress
    }

    private func immersiveHeroInformationExtension(
        for detail: 角色详细信息
    ) -> CGFloat {
        guard !immersiveImageURLs(for: detail).isEmpty else { return 0 }

        let hasDescription = detail.cleanDescription?.isEmpty == false
        let hasVisibleTraits = detail.traits?.contains {
            !shouldHideTrait($0)
        } == true
        guard hasDescription || hasVisibleTraits else { return 0 }

        if horizontalSizeClass == .regular {
            return hasVisibleTraits ? 284 : 164
        }
        return hasVisibleTraits ? 316 : 192
    }

    @ViewBuilder
    private func immersiveHeroImage(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        revealProgress: CGFloat
    ) -> some View {
        if extendsThroughInformation {
            immersiveHeroImageComposition(
                loadedImage: loadedImage,
                sharpStops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.32),
                    .init(color: .white.opacity(0.78), location: 0.37),
                    .init(color: .white.opacity(0.38), location: 0.44),
                    .init(color: .clear, location: 0.54)
                ],
                mediumBlurRadius: 16,
                mediumStops: [
                    .init(color: .clear, location: 0.3),
                    .init(color: .white.opacity(0.5), location: 0.39),
                    .init(color: .white, location: 0.54),
                    .init(color: .white, location: 0.74),
                    .init(color: .white.opacity(0.46), location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                heavyBlurRadius: 36,
                heavyStops: [
                    .init(color: .clear, location: 0.58),
                    .init(color: .white.opacity(0.4), location: 0.66),
                    .init(color: .white, location: 0.78),
                    .init(color: .white, location: 0.88),
                    .init(color: .white.opacity(0.36), location: 0.97),
                    .init(color: .clear, location: 1)
                ],
                fadeStops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.5),
                    .init(color: .white.opacity(0.86), location: 0.62),
                    .init(color: .white.opacity(0.58), location: 0.76),
                    .init(color: .white.opacity(0.3), location: 0.86),
                    .init(color: .white.opacity(0.08), location: 0.95),
                    .init(color: .clear, location: 1)
                ],
                revealProgress: revealProgress
            )
        } else {
            immersiveHeroImageComposition(
                loadedImage: loadedImage,
                sharpStops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.46),
                    .init(color: .white.opacity(0.5), location: 0.64),
                    .init(color: .clear, location: 0.84)
                ],
                mediumBlurRadius: 18,
                mediumStops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: .white.opacity(0.4), location: 0.49),
                    .init(color: .white, location: 0.7),
                    .init(color: .white.opacity(0.55), location: 0.82),
                    .init(color: .clear, location: 0.96)
                ],
                heavyBlurRadius: 42,
                heavyStops: [
                    .init(color: .clear, location: 0.64),
                    .init(color: .white.opacity(0.5), location: 0.76),
                    .init(color: .white, location: 0.88),
                    .init(color: .white.opacity(0.45), location: 0.98),
                    .init(color: .clear, location: 1)
                ],
                fadeStops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.46),
                    .init(color: .white.opacity(0.86), location: 0.58),
                    .init(color: .white.opacity(0.62), location: 0.7),
                    .init(color: .white.opacity(0.34), location: 0.82),
                    .init(color: .white.opacity(0.1), location: 0.91),
                    .init(color: .clear, location: 0.97),
                    .init(color: .clear, location: 1)
                ],
                revealProgress: revealProgress
            )
        }
    }

    private func immersiveHeroImageComposition(
        loadedImage: Image?,
        sharpStops: [Gradient.Stop],
        mediumBlurRadius: CGFloat,
        mediumStops: [Gradient.Stop],
        heavyBlurRadius: CGFloat,
        heavyStops: [Gradient.Stop],
        fadeStops: [Gradient.Stop],
        revealProgress: CGFloat
    ) -> some View {
        let revealProgress = min(max(revealProgress, 0), 1)

        return ZStack {
            immersiveHeroImageLayer(
                loadedImage: loadedImage,
                revealProgress: revealProgress
            )
                .mask {
                    ZStack {
                        LinearGradient(
                            stops: sharpStops,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        Color.white.opacity(revealProgress)
                    }
                }

            immersiveHeroImageLayer(
                loadedImage: loadedImage,
                revealProgress: revealProgress
            )
                .blur(radius: mediumBlurRadius)
                .mask {
                    LinearGradient(
                        stops: mediumStops,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(1 - revealProgress)

            immersiveHeroImageLayer(
                loadedImage: loadedImage,
                revealProgress: revealProgress
            )
                .blur(radius: heavyBlurRadius)
                .mask {
                    LinearGradient(
                        stops: heavyStops,
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
                    stops: fadeStops,
                    startPoint: .top,
                    endPoint: .bottom
                )
                Color.white.opacity(revealProgress)
            }
        }
    }

    @ViewBuilder
    private func immersiveHeroImageLayer(
        loadedImage: Image?,
        revealProgress: CGFloat
    ) -> some View {
        if loadedImage != nil || immersiveOutgoingHeroImage != nil {
            ZStack {
                if let immersiveOutgoingHeroImage {
                    immersiveAlignedHeroImage(
                        immersiveOutgoingHeroImage,
                        revealProgress: revealProgress
                    )
                }

                if let loadedImage {
                    immersiveAlignedHeroImage(
                        loadedImage,
                        revealProgress: revealProgress
                    )
                        .opacity(immersiveHeroImageTransitionProgress)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.3),
                            value: immersiveHeroImageTransitionProgress
                        )
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    @ViewBuilder
    private func immersiveBackdropImageLayer(
        loadedImage: Image?
    ) -> some View {
        if loadedImage != nil || immersiveOutgoingHeroImage != nil {
            ZStack {
                if let immersiveOutgoingHeroImage {
                    immersiveOutgoingHeroImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }

                if let loadedImage {
                    loadedImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(immersiveHeroImageTransitionProgress)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.3),
                            value: immersiveHeroImageTransitionProgress
                        )
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    private func immersiveAlignedHeroImage(
        _ image: Image,
        revealProgress: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .top
                )
                .offset(
                    y: horizontalSizeClass == .regular
                        ? -60 * (1 - revealProgress)
                        : 0
                )
        }
        .clipped()
    }

    private var immersiveHeroSourceAspectRatio: CGFloat? {
        if let immersiveLoadedHeroAspectRatio,
           immersiveLoadedHeroAspectRatio.isFinite,
           immersiveLoadedHeroAspectRatio > 0 {
            return immersiveLoadedHeroAspectRatio
        }
        let dimensions = detail?.image?.dims ?? initialImage?.dims
        guard let dimensions,
              dimensions.count >= 2,
              dimensions[0] > 0,
              dimensions[1] > 0 else {
            return nil
        }
        return CGFloat(dimensions[0]) / CGFloat(dimensions[1])
    }

    private var immersivePresentedHeroImage: Image? {
        guard detail != nil else { return nil }
        return immersiveLoadedHeroImage
    }

    private func immersivePrimaryInformationIsVisible(
        for detail: 角色详细信息
    ) -> Bool {
        guard resolvedImmersiveDetailAppearance == .clear else {
            return true
        }
        guard self.detail != nil else { return false }
        guard !immersiveImageURLs(for: detail).isEmpty else { return true }
        guard hasImmersiveTextSampleGeometry else { return false }
        guard let url = immersiveLoadedHeroImageURL else { return false }
        return immersiveTextSampleURL == url
            && immersiveTextRevealURL == url
    }

    private var resolvedImmersiveDetailAppearance: 沉浸详情外观 {
        guard immersiveDetailAppearance == .clear else {
            return immersiveDetailAppearance
        }
        guard detail != nil else { return .clear }
        guard !immersiveImageURLs(for: displayedDetail).isEmpty else {
            return .clear
        }
        guard let currentImmersiveImageURL,
              immersiveAutomaticAppearanceURL == currentImmersiveImageURL,
              let immersiveAutomaticAppearance else {
            return .clear
        }
        return immersiveAutomaticAppearance
    }

    private var immersiveSystemGlassTint: Color? {
        guard immersiveDetailAppearance == .clear,
              immersiveImageURLs(for: displayedDetail).isEmpty else {
            return nil
        }
        return colorScheme == .dark ? .black : .white
    }

    @ViewBuilder
    private func immersivePrimaryInformationPresentation(
        _ detail: 角色详细信息
    ) -> some View {
        let showsContent = immersivePrimaryInformationIsVisible(for: detail)
        immersivePrimaryInformation(detail, showsContent: showsContent)
    }

    private func updateImmersiveTextSamples(for url: URL) {
        guard shouldAcceptImmersiveImage(at: url) else {
            return
        }
        guard let geometry = immersiveTextSamplingCoordinator.latestGeometry
                ?? immersiveTextSampleGeometry else {
            return
        }
        scheduleImmersiveTextSamples(
            for: url,
            geometry: geometry,
            revealsImmediately: false
        )
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
        if immersiveLoadedHeroImageURL == url,
           immersiveLoadedHeroImage != nil {
            updateImmersiveTextSamples(for: url)
            return
        }

        if immersiveLoadedHeroImageURL != url,
           immersiveAutomaticAppearanceURL != url {
            immersiveAutomaticAppearance = nil
            immersiveAutomaticAppearanceURL = nil
        }

        let canPresent = detail != nil
        let shouldCrossfade = canPresent
            && !reduceMotion
            && immersiveLoadedHeroImage != nil
            && immersiveLoadedHeroImageURL != url
        let shouldFadeIn = canPresent
            && !reduceMotion
            && immersiveLoadedHeroImage == nil
        let shouldAnimate = shouldCrossfade || shouldFadeIn
        immersiveHeroImageTransitionGeneration += 1
        let transitionGeneration = immersiveHeroImageTransitionGeneration

        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            immersiveOutgoingHeroImage = shouldCrossfade
                ? immersiveLoadedHeroImage
                : nil
            immersiveLoadedHeroImage = image
            immersiveLoadedHeroImageURL = url
            immersiveHeroImageTransitionProgress = shouldAnimate
                ? 0
                : (canPresent ? 1 : 0)
        }

        updateImmersiveTextSamples(for: url)

        guard shouldAnimate else { return }
        Task { @MainActor in
            await Task.yield()
            guard transitionGeneration
                    == immersiveHeroImageTransitionGeneration else {
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                immersiveHeroImageTransitionProgress = 1
            }
            try? await Task.sleep(for: .seconds(0.32))
            guard transitionGeneration
                    == immersiveHeroImageTransitionGeneration else {
                return
            }
            var cleanupTransaction = Transaction()
            cleanupTransaction.animation = nil
            cleanupTransaction.disablesAnimations = true
            withTransaction(cleanupTransaction) {
                immersiveOutgoingHeroImage = nil
            }
        }
    }

    private func presentPreloadedImmersiveHeroImageIfNeeded() {
        guard detail != nil,
              immersiveLoadedHeroImage != nil,
              let url = immersiveLoadedHeroImageURL else {
            return
        }

        updateImmersiveTextSamples(for: url)
        guard immersiveHeroImageTransitionProgress < 1 else { return }

        immersiveHeroImageTransitionGeneration += 1
        let transitionGeneration = immersiveHeroImageTransitionGeneration
        if reduceMotion {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                immersiveHeroImageTransitionProgress = 1
            }
            return
        }

        Task { @MainActor in
            await Task.yield()
            guard detail != nil,
                  immersiveLoadedHeroImageURL == url,
                  transitionGeneration
                    == immersiveHeroImageTransitionGeneration else {
                return
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                immersiveHeroImageTransitionProgress = 1
            }
        }
    }

    private func revealImmersiveTextIfNeeded(for url: URL) {
        guard detail != nil else { return }
        guard hasImmersiveTextSampleGeometry else { return }
        guard hasResolvedImmersiveAutomaticAppearance(for: url) else {
            return
        }
        guard immersiveTextRevealURL != url else { return }

        Task { @MainActor in
            await Task.yield()
            guard immersiveTextSampleURL == url else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                immersiveTextRevealURL = url
            }
        }
    }

    private func refreshImmersiveTextSamplesForCurrentAppearance() {
        guard let url = currentImmersiveImageURL,
              let geometry = immersiveTextSamplingCoordinator.latestGeometry
                ?? immersiveTextSampleGeometry else {
            return
        }
        scheduleImmersiveTextSamples(
            for: url,
            geometry: geometry,
            revealsImmediately: true
        )
    }

    private func scheduleImmersiveTextSamples(
        for url: URL,
        geometry: 沉浸封面文字取样几何,
        revealsImmediately: Bool
    ) {
        let request = 沉浸封面文字取样请求(
            url: url,
            layout: .character,
            background: colorScheme == .dark ? .dark : .light,
            extendsThroughInformation:
                immersiveHeroInformationExtension(for: displayedDetail) > 0,
            itemCounts: [
                "traits": displayedDetail.traits?.filter {
                    !shouldHideTrait($0)
                }.prefix(7).count ?? 0
            ],
            geometry: geometry
        )
        immersiveTextSamplingCoordinator.submit(request) { request, samples in
            guard !immersiveHeroGestureIsActive else {
                immersiveTextSamplingCoordinator.cancel()
                return
            }
            guard currentImmersiveImageURL == request.url,
                  shouldAcceptImmersiveImage(at: request.url) else {
                return
            }

            let samplesChanged = immersiveTextSampleURL != request.url
                || immersiveTextSamples != samples
            let needsInitialGeometry = immersiveTextSampleGeometry == nil
            let needsAutomaticAppearance =
                !hasResolvedImmersiveAutomaticAppearance(for: request.url)
            let needsReveal = revealsImmediately
                && immersiveTextRevealURL != request.url
            guard samplesChanged
                    || needsInitialGeometry
                    || needsAutomaticAppearance
                    || needsReveal else {
                return
            }

            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                immersiveTextSampleGeometry = request.geometry
                immersiveTextSamples = samples
                immersiveTextSampleURL = request.url
            }
            resolveImmersiveAutomaticAppearance(
                for: request.url,
                samples: samples
            )
            guard hasResolvedImmersiveAutomaticAppearance(for: request.url)
            else {
                return
            }
            if revealsImmediately {
                var revealTransaction = Transaction()
                revealTransaction.animation = nil
                withTransaction(revealTransaction) {
                    immersiveTextRevealURL = request.url
                }
            } else {
                revealImmersiveTextIfNeeded(for: request.url)
            }
        }
    }

    private func scheduleImmersiveAppearanceRefresh() {
        Task { @MainActor in
            await Task.yield()
            refreshImmersiveTextSamplesForCurrentAppearance()
            try? await Task.sleep(for: .milliseconds(120))
            refreshImmersiveTextSamplesForCurrentAppearance()
        }
    }

    private var currentImmersiveImageURL: URL? {
        let urls = immersiveImageURLs(for: displayedDetail)
        if let immersiveLoadedHeroImageURL,
           urls.contains(immersiveLoadedHeroImageURL) {
            return immersiveLoadedHeroImageURL
        }
        return urls.first
    }

    private var hasImmersiveTextSampleGeometry: Bool {
        guard let geometry = immersiveTextSampleGeometry,
              geometry.imageSize.width > 0,
              geometry.imageSize.height > 0,
              let metadataFrame = geometry.regions["metadata"] else {
            return false
        }
        return !metadataFrame.isEmpty
    }

    private func hasResolvedImmersiveAutomaticAppearance(
        for url: URL
    ) -> Bool {
        immersiveDetailAppearance != .clear
            || (
                immersiveAutomaticAppearanceURL == url
                    && immersiveAutomaticAppearance != nil
            )
    }

    private func resolveImmersiveAutomaticAppearance(
        for url: URL,
        samples: [String: 沉浸玻璃文字取样结果]
    ) {
        guard immersiveDetailAppearance == .clear,
              detail != nil,
              currentImmersiveImageURL == url,
              hasImmersiveTextSampleGeometry,
              immersiveAutomaticAppearanceURL != url else {
            return
        }

        var sampleKeys = ["metadata"]
        if displayedDetail.cleanDescription?.isEmpty == false {
            guard immersiveTextSampleGeometry?.regions["description"] != nil
            else {
                return
            }
            sampleKeys.append("description")
        }
        if let traits = displayedDetail.traits {
            let traitCount = traits.filter { !shouldHideTrait($0) }
                .prefix(7)
                .count
            sampleKeys += (0..<traitCount).compactMap { index in
                let key = "traits.item.\(index)"
                return immersiveTextSampleGeometry?.regions[key] == nil
                    ? nil
                    : key
            }
        }

        guard sampleKeys.allSatisfy({ samples[$0] != nil }) else { return }

        let appearance: 沉浸详情外观 = .clear
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            immersiveAutomaticAppearance = appearance
            immersiveAutomaticAppearanceURL = url
        }
    }

    private func updateImmersiveTextSampleGeometry(
        from frames: [String: CGRect]
    ) {
        guard let imageFrame = frames["image"],
              角色沉浸取样框有效(imageFrame) else {
            return
        }
        var regions: [String: CGRect] = [:]
        for (key, frame) in frames where key != "image" {
            guard 角色沉浸取样框有效(frame) else { continue }
            let relativeFrame = frame.offsetBy(
                dx: -imageFrame.minX,
                dy: -imageFrame.minY
            )
            guard let samplingFrame = immersiveSamplingFrame(relativeFrame)
            else {
                continue
            }
            regions[key] = samplingFrame
        }
        let geometry = 沉浸封面文字取样几何(
            imageSize: CGSize(width: imageFrame.width, height: imageFrame.height),
            regions: regions
        )
        guard immersiveTextSamplingCoordinator.latestGeometry != geometry else {
            return
        }
        immersiveTextSamplingCoordinator.remember(geometry)
        guard !immersiveHeroGestureIsActive else { return }
        guard let url = currentImmersiveImageURL else { return }
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
            return
        }
        guard !isActive,
              let url = currentImmersiveImageURL,
              let geometry = immersiveTextSamplingCoordinator.latestGeometry
                ?? immersiveTextSampleGeometry else {
            return
        }
        scheduleImmersiveTextSamples(
            for: url,
            geometry: geometry,
            revealsImmediately: true
        )
    }

    private func immersiveSamplingFrame(_ frame: CGRect) -> CGRect? {
        guard 角色沉浸取样框有效(frame) else { return nil }
        func snapped(_ value: CGFloat) -> CGFloat {
            (value * 2).rounded() / 2
        }
        let snappedFrame = CGRect(
            x: snapped(frame.minX),
            y: snapped(frame.minY),
            width: snapped(frame.width),
            height: snapped(frame.height)
        )
        return 角色沉浸取样框有效(snappedFrame) ? snappedFrame : nil
    }

    private func immersiveImageURLs(
        for detail: 角色详细信息
    ) -> [URL] {
        [detail.image?.url, initialImage?.url]
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
                if !urls.contains(url) {
                    urls.append(url)
                }
            }
    }

    private func shouldAcceptImmersiveImage(at url: URL) -> Bool {
        let urls = immersiveImageURLs(for: displayedDetail)
        guard let candidatePriority = urls.firstIndex(of: url) else {
            return false
        }
        guard let immersiveLoadedHeroImageURL,
              let loadedPriority = urls.firstIndex(
                of: immersiveLoadedHeroImageURL
              ) else {
            return true
        }
        return candidatePriority <= loadedPriority
    }

    private func immersiveMetadataTextStyle(
        for key: String
    ) -> 沉浸详情文字样式 {
        沉浸详情文字样式(
            appearance: resolvedImmersiveDetailAppearance,
            sample: immersiveTextSamples[key],
            fallbackColorScheme: colorScheme
        )
    }

    private func immersiveIdentity(
        _ detail: 角色详细信息,
        fillsAvailableHeight: Bool = false,
        showsContent: Bool = true
    ) -> some View {
        let titleSampleKey = "metadata.title"
        let titleTextStyle = immersiveMetadataTextStyle(for: titleSampleKey)
        let informationSampleKey = "metadata"
        let informationTextStyle = immersiveMetadataTextStyle(
            for: informationSampleKey
        )

        return VStack(
            alignment: .leading,
            spacing: fillsAvailableHeight ? 0 : 9
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    标题工具.生成富文本(
                        文本: characterName,
                        isJapanese: nameLanguage == .original,
                        基础大小: 22,
                        是粗体: true,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                )
                .沉浸详情文字前景色(titleTextStyle.primary, style: titleTextStyle)
                .lineLimit(2)
                .contextMenu {
                    nameCopyContextMenu(for: detail)
                }

                if let secondary = 人物名称工具.备用名称(
                    name: detail.name,
                    original: detail.original,
                    偏好: nameLanguage
                ) {
                    Text(
                        标题工具.生成富文本(
                            文本: secondary,
                            isJapanese: nameLanguage != .original,
                            基础大小: 15,
                            语言来源已知: false,
                            空格视为日语: true
                        )
                    )
                    .沉浸详情文字前景色(titleTextStyle.secondary, style: titleTextStyle)
                    .fontWeight(.regular)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .沉浸详情文字阴影(titleTextStyle)

            if fillsAvailableHeight {
                Spacer(minLength: 9)
            }

            if isShowingInitialSkeleton {
                immersiveLoadingStats
            } else {
                immersiveStats(detail, textStyle: informationTextStyle)
                    .沉浸详情文字阴影(informationTextStyle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(showsContent ? 1 : 0)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .沉浸详情玻璃背景(
            resolvedImmersiveDetailAppearance,
            sample: informationTextStyle.sample,
            fallbackTint: immersiveSystemGlassTint,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .角色沉浸取样框(["metadata"])
    }

    private func immersiveStats(
        _ detail: 角色详细信息,
        textStyle: 沉浸详情文字样式
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible())
            ],
            alignment: .leading,
            spacing: 7
        ) {
            if let age = detail.age {
                immersiveCharacterMetadataItem(
                    icon: "birthday.cake",
                    title: "年龄",
                    text: ageText(age),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.age")
                )
            }
            if let birthday = birthdayText(detail.birthday) {
                immersiveCharacterMetadataItem(
                    icon: "calendar",
                    title: "生日",
                    text: birthday,
                    textStyle: immersiveMetadataTextStyle(for: "metadata.birthday")
                )
            }
            if resolvedCharacterValue(detail.sex) != nil
                || resolvedCharacterValue(detail.gender) != nil {
                immersiveCharacterMetadataItem(
                    icon: "person.crop.circle",
                    title: "性别",
                    text: combinedGenderText(detail),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.gender")
                )
            }
            if let bloodType = detail.blood_type {
                immersiveCharacterMetadataItem(
                    icon: "drop",
                    title: "血型",
                    text: bloodTypeText(bloodType),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.bloodType")
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    characterInfoPopover = .bloodType
                }
                .popover(
                    isPresented: infoPopoverBinding(.bloodType),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("血型")
                            .font(.headline)
                        Text(verbatim: bloodTypeText(bloodType))
                            .font(.title3.weight(.semibold))
                    }
                    .padding(16)
                    .frame(width: 250, alignment: .leading)
                    .presentationCompactAdaptation(.popover)
                }
            }
            if let height = detail.height {
                immersiveCharacterMetadataItem(
                    icon: "ruler",
                    title: "身高",
                    text: heightText(height),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.height")
                )
            }
            if let weight = detail.weight {
                immersiveCharacterMetadataItem(
                    icon: "scalemass",
                    title: "体重",
                    text: weightText(weight),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.weight")
                )
            }
            if let bust = detail.bust {
                immersiveCharacterMetadataItem(
                    icon: "circle.lefthalf.filled",
                    title: "胸围",
                    text: heightText(bust),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.bust")
                )
            }
            if let waist = detail.waist {
                immersiveCharacterMetadataItem(
                    icon: "circle.lefthalf.filled",
                    title: "腰围",
                    text: heightText(waist),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.waist")
                )
            }
            if let hips = detail.hips {
                immersiveCharacterMetadataItem(
                    icon: "circle.lefthalf.filled",
                    title: "臀围",
                    text: heightText(hips),
                    textStyle: immersiveMetadataTextStyle(for: "metadata.hips")
                )
            }
            if let cup = detail.cup, !cup.isEmpty {
                immersiveCharacterMetadataItem(
                    icon: "circle.lefthalf.filled",
                    title: "罩杯",
                    text: cup,
                    textStyle: immersiveMetadataTextStyle(for: "metadata.cup")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var immersiveLoadingStats: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible(), spacing: 6),
                GridItem(.flexible())
            ],
            alignment: .leading,
            spacing: 7
        ) {
            immersiveCharacterMetadataItem(
                icon: "birthday.cake",
                title: "年龄",
                text: ageText(18)
            )
            immersiveCharacterMetadataItem(
                icon: "calendar",
                title: "生日",
                text: birthdayText([1, 1]) ?? unknownText
            )
            immersiveCharacterMetadataItem(
                icon: "person.crop.circle",
                title: "性别",
                text: unknownText
            )
            immersiveCharacterMetadataItem(
                icon: "ruler",
                title: "身高",
                text: heightText(160)
            )
            immersiveCharacterMetadataItem(
                icon: "scalemass",
                title: "体重",
                text: weightText(50)
            )
            immersiveCharacterMetadataItem(
                icon: "circle.lefthalf.filled",
                title: "胸围",
                text: heightText(80)
            )
            immersiveCharacterMetadataItem(
                icon: "circle.lefthalf.filled",
                title: "腰围",
                text: heightText(60)
            )
            immersiveCharacterMetadataItem(
                icon: "circle.lefthalf.filled",
                title: "臀围",
                text: heightText(80)
            )
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
    }

    private func immersiveCharacterMetadataItem(
        icon: String,
        title: LocalizedStringKey,
        text: String,
        textStyle: 沉浸详情文字样式? = nil
    ) -> some View {
        let resolvedTextStyle = textStyle
            ?? immersiveMetadataTextStyle(for: "loading")

        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .沉浸详情文字前景色(resolvedTextStyle.secondary, style: resolvedTextStyle)
                .frame(width: 15, height: 17)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .沉浸详情文字前景色(resolvedTextStyle.tertiary, style: resolvedTextStyle)

                Text(verbatim: text)
                    .font(.subheadline.weight(.regular))
                    .沉浸详情文字前景色(resolvedTextStyle.primary, style: resolvedTextStyle)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(resolvedTextStyle)
    }

    private func immersiveDescription(
        _ detail: 角色详细信息,
        outerHorizontalPadding: CGFloat,
        fillsAvailableHeight: Bool = false,
        showsContent: Bool = true
    ) -> some View {
        let original = detail.cleanDescription
        let hasDescription = original?.isEmpty == false
        let textStyle = immersiveMetadataTextStyle(for: "description.text")

        return Group {
            if let original, !original.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    简介预览文本视图(
                        text: displayedDescription(original),
                        lineLimit: 7
                    )
                    .font(.body)
                    .沉浸详情文字前景色(textStyle.primary, style: textStyle)
                    .fontWeight(.regular)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 14) {
                        if shouldOfferOnDeviceDescriptionTranslation {
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
                            .foregroundStyle(
                                showTranslatedDescription
                                    ? .blue
                                    : textStyle.secondary
                            )
                            .accessibilityLabel(
                                showTranslatedDescription
                                    ? "显示简介原文"
                                    : "翻译简介"
                            )
                        }

                        descriptionParticipationButton(
                            style: .icon(tint: textStyle.secondary)
                        )
                    }
                }
                .沉浸详情文字阴影(textStyle)
                .opacity(
                    showsContent
                        ? manualDescriptionPresentationOpacity
                        : 0
                )
            } else {
                简介预览文本视图(
                    text: String(repeating: "正在载入", count: 128),
                    lineLimit: 7
                )
                .font(.body)
                .opacity(0)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .沉浸详情玻璃背景(
            resolvedImmersiveDetailAppearance,
            sample: immersiveTextSamples["description"],
            fallbackTint: immersiveSystemGlassTint,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .matchedTransitionSource(
            id: "CharacterDescriptionSheet",
            in: descriptionNamespace
        )
        .onTapGesture {
            guard hasDescription, showsContent else { return }
            showDescriptionSheet = true
        }
        .allowsHitTesting(
            hasDescription
                && showsContent
                && manualDescriptionPresentationOpacity > 0.99
        )
        .accessibilityHidden(!hasDescription || !showsContent)
        .角色沉浸取样框(["description", "description.text"])
        .padding(.horizontal, outerHorizontalPadding)
    }

    @ViewBuilder
    private func immersiveTraits(_ detail: 角色详细信息) -> some View {
        if let traits = detail.traits, !traits.isEmpty {
            let visibleTraits = traits.filter { !shouldHideTrait($0) }
            if !visibleTraits.isEmpty {
                let sampleKey = "traits"
                let textStyle = immersiveMetadataTextStyle(for: sampleKey)

                FlowLayout(spacing: 8) {
                    if targetLanguage.supportsAutomaticMetadataTranslation {
                        Button {
                            switchTraitTranslation()
                        } label: {
                            Image(systemName: "translate")
                                .font(.caption.weight(.semibold))
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            showTranslatedTraits
                                ? .blue
                                : textStyle.capsule
                        )
                        .沉浸详情文字阴影(textStyle)
                        .沉浸详情玻璃(
                            resolvedImmersiveDetailAppearance,
                            sample: textStyle.sample,
                            fallbackTint: immersiveSystemGlassTint,
                            interactive: true,
                            in: Circle()
                        )
                    }

                    ForEach(
                        Array(visibleTraits.prefix(7).enumerated()),
                        id: \.element.id
                    ) { index, trait in
                        immersiveTraitCapsule(
                            trait,
                            allTraits: traits,
                            sampleKey: "traits.item.\(index)",
                            textStyle: immersiveMetadataTextStyle(
                                for: "traits.item.\(index)"
                            )
                        )
                            .opacity(traitsContentOpacity)
                    }

                    if visibleTraits.count > 7 {
                        Button {
                            showAllTraits = true
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .frame(width: 12, height: 30)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
                        .buttonStyle(详情更多入口按钮样式())
                        .沉浸详情文字前景色(textStyle.capsule, style: textStyle)
                        .沉浸详情文字阴影(textStyle)
                        .沉浸详情玻璃(
                            resolvedImmersiveDetailAppearance,
                            sample: textStyle.sample,
                            fallbackTint: immersiveSystemGlassTint,
                            in: Capsule()
                        )
                        .contentShape(Capsule())
                        .accessibilityLabel("查看更多特征")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, immersivePageHorizontalPadding)
            }
        }
    }

    private func immersiveTraitCapsule(
        _ trait: 角色特征,
        allTraits: [角色特征],
        sampleKey: String,
        textStyle: 沉浸详情文字样式
    ) -> some View {
        let blurred = shouldBlurTrait(trait)

        return traitCapsuleContent(
            name: displayedTraitText(trait.name),
            groupName: displayedTraitText(trait.group_name),
            groupColor: textStyle.capsule.opacity(0.76)
        )
        .沉浸详情文字前景色(textStyle.capsule, style: textStyle)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .沉浸详情文字阴影(textStyle)
        .沉浸详情玻璃(
            resolvedImmersiveDetailAppearance,
            sample: textStyle.sample,
            fallbackTint: immersiveSystemGlassTint,
            in: Capsule()
        )
        .角色沉浸取样框([sampleKey])
        .blur(radius: blurred ? 5 : 0)
        .contentShape(Capsule())
        .onTapGesture {
            guard blurred,
                  内容安全限制判定.允许手动解除模糊(
                    色情限制: isAdultTraitRestricted(trait)
                  ) else {
                return
            }
            blurRevealConfirmation.request(id: "traits") {
                withAnimation(.easeInOut(duration: 0.22)) {
                    revealedTraitIDs.formUnion(allTraits.map(\.id))
                }
            }
        }
    }

    private var immersiveVoiceActors: some View {
        characterImmersiveSection("声优") {
            VStack(spacing: 0) {
                ForEach(
                    Array(uniqueVoiceRelationships.enumerated()),
                    id: \.element.staff.id
                ) { index, voice in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            多语言列表文本(
                                文本: voiceActorName(for: voice),
                                isJapanese: nameLanguage == .original,
                                层级: .主标题,
                                日文字体名称: "HiraginoSans-W4",
                                系统字体粗细: .regular,
                                语言来源已知: false,
                                空格视为日语: true
                            )

                            if let note = voice.note, !note.isEmpty {
                                Text(
                                    verbatim: VNDB显示工具.声优语言名称(note)
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < uniqueVoiceRelationships.count - 1 {
                        Divider()
                            .padding(.leading, 50)
                    }
                }
            }
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
    }

    @ViewBuilder
    private func immersiveAppearances(_ detail: 角色详细信息) -> some View {
        if let visualNovels = detail.vns, !visualNovels.isEmpty {
            characterImmersiveHorizontalSection("登场作品") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(uniqueVisualNovels(visualNovels), id: \.id) { visualNovel in
                            NavigationLink {
                                视觉小说详情(
                                    vnID: visualNovel.id,
                                    auth: auth,
                                    initialTitle: visualNovel.title,
                                    initialTitles: visualNovel.titles,
                                    initialImageURL: visualNovel.image?.url,
                                    initialImageSexual: visualNovel.image?.sexual,
                                    initialImageViolence: visualNovel.image?.violence,
                                    initialImageDimensions: visualNovel.image?.dims
                                )
                            } label: {
                                immersiveAppearanceCard(visualNovel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .contentMargins(
                    .horizontal,
                    immersivePageHorizontalPadding,
                    for: .scrollContent
                )
                .scrollClipDisabled()
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func immersiveAppearanceCard(
        _ visualNovel: 角色视觉小说关系
    ) -> some View {
        let title = 标题工具.获取主标题(
            titles: visualNovel.titles,
            defaultTitle: visualNovel.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )

        return ZStack(alignment: .bottomLeading) {
            restrictedCardImage(
                id: "character-vn-\(visualNovel.id)",
                url: visualNovel.image?.url ?? visualNovel.image?.thumbnail,
                sexual: visualNovel.image?.sexual,
                violence: visualNovel.image?.violence,
                width: 沉浸详情布局.媒体卡片宽度,
                height: 沉浸详情布局.媒体卡片高度,
                cornerRadius: 26
            )

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.24), location: 0.64),
                    .init(color: .black.opacity(0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(
                    标题工具.生成富文本(
                        文本: title.text,
                        isJapanese: title.isJapanese,
                        基础大小: 14,
                        是粗体: true,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言代码: title.languageCode
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(2)

                Text(verbatim: visualNovel.roleTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(
            width: 沉浸详情布局.媒体卡片宽度,
            height: 沉浸详情布局.媒体卡片高度
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
    }

    private func characterImmersiveSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.bold))

            content()
        }
        .padding(.horizontal, immersivePageHorizontalPadding)
    }

    private func characterImmersiveHorizontalSection<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title2.weight(.bold))
                .padding(.horizontal, immersivePageHorizontalPadding)

            content()
        }
    }

    @ViewBuilder
    private var immersiveFailureCard: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    detail == nil ? "无法载入" : "无法载入",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.headline)

                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("重试") {
                    Task {
                        await loadDetail(forceRefresh: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoadingDetail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .沉浸详情玻璃(
                resolvedImmersiveDetailAppearance,
                fallbackTint: immersiveSystemGlassTint,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
    }

    private var immersiveLoadingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登场作品")
                .font(.title2.weight(.bold))

            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(
                            width: 沉浸详情布局.媒体卡片宽度,
                            height: 沉浸详情布局.媒体卡片高度
                        )
                }
            }
        }
        .padding(.horizontal, immersivePageHorizontalPadding)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
    }

    private var isShowingInitialSkeleton: Bool {
        detail == nil && isLoadingDetail && errorMessage == nil
    }

    private func characterDescriptionSheet(
        _ detail: 角色详细信息
    ) -> some View {
        NavigationStack {
            ScrollView {
                Text(
                    verbatim: 简介预览文本处理.外部显示文本(
                        displayedDescription(detail.cleanDescription ?? "")
                    )
                )
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("简介")
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                Text(
                    verbatim: 简介预览文本处理.外部显示文本(
                        displayedDescription(detail.cleanDescription ?? "")
                    )
                )
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .平台近全屏弹窗()
    }

    private func displayedDescription(_ original: String) -> String {
        if let manualDescription {
            return manualDescription
        }
        if let cachedManualDescription {
            return cachedManualDescription
        }
        guard showTranslatedDescription else { return original }
        return translatedDescription ?? original
    }

    @ViewBuilder
    private func descriptionParticipationButton(
        style: 简介翻译参与按钮.样式
    ) -> some View {
        if let entry = descriptionTranslationEntry {
            简介翻译参与按钮(
                auth: auth,
                entry: entry,
                targetLanguage: targetLanguage,
                knownHasTranslation: projectDescriptionHasTranslation,
                resolvesIndependently:
                    descriptionTranslationMode == .automaticOnDevice,
                style: style
            )
        }
    }

    private var descriptionTranslationEntry: VNDB简介翻译条目? {
        let detail = detail ?? displayedDetail
        guard let source = detail.description,
              let displaySource = detail.cleanDescription,
              !displaySource.isEmpty else {
            return nil
        }
        let original = detail.original?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return VNDB简介翻译条目(
            id: characterID,
            type: .character,
            name: original.isEmpty ? detail.name : original,
            romanizedName: detail.name,
            titles: nil,
            displayName: characterName,
            originalName: detail.original,
            source: source,
            displaySource: displaySource,
            displayIsJapanese: nameLanguage == .original
        )
    }

    private var projectDescriptionHasTranslation: Bool? {
        if manualDescription != nil || cachedManualDescription != nil {
            return true
        }
        if hasFinishedManualDescriptionLookup || cachedManualLookupIsResolved {
            return false
        }
        return nil
    }

    private var shouldOfferOnDeviceDescriptionTranslation: Bool {
        guard manualDescription == nil,
              cachedManualDescription == nil else {
            return false
        }
        return VNDB简介翻译模式.current == .automaticOnDevice
            || cachedManualLookupIsResolved
            || hasFinishedManualDescriptionLookup
            || manualDescriptionLookupTimedOut
    }

    private var shouldDisplayDescription: Bool {
        manualDescription != nil
            || cachedManualDescription != nil
            || cachedManualLookupIsResolved
            || hasFinishedManualDescriptionLookup
            || manualDescriptionLookupTimedOut
    }

    private var cachedManualDescription: String? {
        guard manualDescriptionLookupKey == nil
                || hasFinishedManualDescriptionLookup
                || manualDescriptionLookupTimedOut else {
            return nil
        }
        return manualDescriptionCacheResult.translation
    }

    private var cachedManualLookupIsResolved: Bool {
        guard manualDescriptionLookupKey == nil
                || hasFinishedManualDescriptionLookup
                || manualDescriptionLookupTimedOut else {
            return false
        }
        return manualDescriptionCacheResult.isResolved
    }

    private var manualDescriptionCacheResult: VNDB简介译文缓存结果 {
        VNDB简介人工翻译.译文缓存结果(
            for: characterID,
            type: .character,
            language: targetLanguage,
            mode: VNDB简介翻译模式.current
        )
    }

    private func manualDescriptionLookupKeyValue(
        mode: VNDB简介翻译模式
    ) -> String {
        "\(characterID)|\(targetLanguage.rawValue)|\(mode.rawValue)"
    }

    private func updateManualDescriptionPresentation(
        for lookupKey: String,
        updates: () -> Void
    ) {
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            manualDescriptionPresentationOpacity = 0
            updates()
        }

        Task { @MainActor in
            await Task.yield()
            guard manualDescriptionLookupKey == lookupKey,
                  shouldDisplayDescription else {
                return
            }
            withAnimation(.easeInOut(duration: 0.18)) {
                manualDescriptionPresentationOpacity = 1
            }
        }
    }

    private func requestDescriptionTranslation() {
        guard manualDescription == nil else { return }

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
        guard manualDescription == nil,
              let description = detail?.cleanDescription,
              !description.isEmpty,
              translatedDescription == nil else { return }

        await MainActor.run {
            isTranslatingDescription = true
            translationError = nil
        }

        do {
            let response = try await session.translate(description)
            await MainActor.run {
                translatedDescription = response.targetText
                showTranslatedDescription = true
                isTranslatingDescription = false
            }
        } catch is CancellationError {
            await MainActor.run {
                isTranslatingDescription = false
                showTranslatedDescription = false
            }
        } catch {
            await MainActor.run {
                isTranslatingDescription = false
                showTranslatedDescription = false
                translationError = (error as? CocoaError)?.code == .userCancelled
                    ? nil
                    : error.localizedDescription
            }
        }
    }

    private func title(_ detail: 角色详细信息) -> some View {
        VStack(spacing: 4) {
            Text(
                标题工具.生成富文本(
                    文本: characterName,
                    isJapanese: nameLanguage == .original,
                    基础大小: 24,
                    是粗体: true,
                    语言来源已知: false,
                    空格视为日语: true
                )
            )
                .multilineTextAlignment(.center)
                .contextMenu {
                    nameCopyContextMenu(for: detail)
                }

            if let secondary = 人物名称工具.备用名称(
                name: detail.name,
                original: detail.original,
                偏好: nameLanguage
            ) {
                Text(
                    标题工具.生成富文本(
                        文本: secondary,
                        isJapanese: nameLanguage != .original,
                        基础大小: 16,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        }
        .padding(.top, 7)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func nameCopyContextMenu(
        for detail: 角色详细信息
    ) -> some View {
        ForEach(nameCopyItems(for: detail)) { item in
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

    private func nameCopyItems(
        for detail: 角色详细信息
    ) -> [角色名称拷贝项目] {
        let original = detail.original?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let name = detail.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var items: [角色名称拷贝项目] = []

        if let original, !original.isEmpty {
            let language = inferredCharacterLanguage(original)
            let label = language.map {
                String(localized: "拷贝\($0.localizedTitle)名称")
            } ?? String(localized: "拷贝原文名称")
            items.append(
                角色名称拷贝项目(
                    id: "original",
                    label: label,
                    value: original
                )
            )
        }

        if !name.isEmpty {
            let originalLanguage = original.flatMap {
                inferredCharacterLanguage($0)
            }
            let language: 标题语言
            if let originalLanguage,
               originalLanguage != .english {
                language = .romanized
            } else {
                language = inferredCharacterLanguage(name) ?? .english
            }
            appendNameCopyItem(
                to: &items,
                id: language.rawValue,
                label: String(localized: "拷贝\(language.localizedTitle)名称"),
                value: name
            )
        }

        return items
    }

    private func appendNameCopyItem(
        to items: inout [角色名称拷贝项目],
        id: String,
        label: String,
        value: String
    ) {
        guard !items.contains(where: { $0.value == value }) else { return }
        items.append(
            角色名称拷贝项目(id: id, label: label, value: value)
        )
    }

    private func inferredCharacterLanguage(
        _ value: String
    ) -> 标题语言? {
        var containsJapanese = false
        var containsKorean = false
        var containsCJK = false
        var containsLatin = false

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
                containsJapanese = true
            case 0xAC00...0xD7AF:
                containsKorean = true
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                containsCJK = true
            case 0x0041...0x005A, 0x0061...0x007A:
                containsLatin = true
            default:
                continue
            }
        }

        if containsJapanese { return .japanese }
        if containsKorean { return .korean }
        if containsCJK { return .chinese }
        if containsLatin { return .english }
        return nil
    }

    private func ageText(_ age: Int) -> String {
        String(localized: "\(age)岁")
    }

    private func heightText(_ height: Int) -> String {
        String(
            format: String(localized: "%lldcm"),
            locale: Locale.current,
            arguments: [Int64(height)]
        )
    }

    private func weightText(_ weight: Int) -> String {
        String(
            format: String(localized: "%lldkg"),
            locale: Locale.current,
            arguments: [Int64(weight)]
        )
    }

    private func bloodTypeText(_ bloodType: String) -> String {
        String(
            format: String(localized: "%@型"),
            locale: Locale.current,
            arguments: [bloodType.uppercased()]
        )
    }

    private func infoPopoverBinding(
        _ info: 角色信息提示
    ) -> Binding<Bool> {
        Binding(
            get: { characterInfoPopover == info },
            set: { isPresented in
                if !isPresented, characterInfoPopover == info {
                    characterInfoPopover = nil
                }
            }
        )
    }

    private func traitCapsuleContent(
        name: String,
        groupName: String,
        groupColor: Color = .secondary
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: name)
                .font(.caption.weight(.semibold))
            Text(verbatim: groupName)
                .font(.caption2)
                .foregroundStyle(groupColor)
        }
    }

    private var uniqueVoiceRelationships: [视觉小说声优关系] {
        var seen: Set<String> = []
        return relationships.filter {
            seen.insert($0.staff.id).inserted
        }
    }

    private var eventActorNames: [String] {
        var values: [String] = []
        for relationship in uniqueVoiceRelationships {
            values.append(relationship.staff.name)
            if let original = relationship.staff.original {
                values.append(original)
            }
        }
        return values
    }

    private var eventRelatedTerms: [String] {
        let visualNovels = displayedDetail.vns ?? []
        return visualNovels
            .flatMap { visualNovel in
                [visualNovel.title]
                    + (visualNovel.titles?.flatMap { title in
                        [title.title, title.latin].compactMap { $0 }
                    } ?? [])
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var shouldShowEventSection: Bool {
        !eventModel.events.isEmpty
    }

    @ViewBuilder
    private func appearances(_ detail: 角色详细信息) -> some View {
        if let visualNovels = detail.vns, !visualNovels.isEmpty {
            Section("登场作品") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(
                            uniqueVisualNovels(visualNovels),
                            id: \.id
                        ) { visualNovel in
                            NavigationLink {
                                视觉小说详情(
                                    vnID: visualNovel.id,
                                    auth: auth,
                                    initialTitle: visualNovel.title,
                                    initialTitles: visualNovel.titles,
                                    initialImageURL: visualNovel.image?.url,
                                    initialImageSexual: visualNovel.image?.sexual,
                                    initialImageViolence: visualNovel.image?.violence,
                                    initialImageDimensions: visualNovel.image?.dims
                                )
                            } label: {
                                appearanceCard(visualNovel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 14)
                }
                .平台横向书架()
                .listRowInsets(
                    EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private func appearanceCard(
        _ visualNovel: 角色视觉小说关系
    ) -> some View {
        let title = 标题工具.获取主标题(
            titles: visualNovel.titles,
            defaultTitle: visualNovel.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )

        return VStack(alignment: .leading, spacing: 7) {
            restrictedCardImage(
                id: "character-vn-\(visualNovel.id)",
                url: visualNovel.image?.url ?? visualNovel.image?.thumbnail,
                sexual: visualNovel.image?.sexual,
                violence: visualNovel.image?.violence,
                width: 详情卡片样式.角色图片宽度,
                height: 详情卡片样式.角色图片高度,
                cornerRadius: 26
            )

            VStack(alignment: .leading, spacing: 详情卡片样式.文本间距) {
                Text(
                    标题工具.生成富文本(
                        文本: title.text,
                        isJapanese: title.isJapanese,
                        基础大小: 14,
                        是粗体: true,
                        语言代码: title.languageCode
                    )
                )
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

                Text(verbatim: visualNovel.roleTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 详情卡片样式.角色图片宽度, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var unknownText: String {
        String(localized: "未知")
    }

    private func switchTraitTranslation() {
        guard !isSwitchingTraitLanguage else { return }
        let targetValue = !showTranslatedTraits
        isSwitchingTraitLanguage = true

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.14)) {
                traitsContentOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.14))
            showTranslatedTraits = targetValue
            withAnimation(.easeIn(duration: 0.18)) {
                traitsContentOpacity = 1
            }
            isSwitchingTraitLanguage = false
        }
    }

    private func displayedTraitText(_ source: String) -> String {
        if let manual = VNDB特征人工翻译.界面译文(source) {
            return manual
        }
        guard showTranslatedTraits else { return source }
        return VNDB特征人工翻译.译文(
            source,
            target: targetLanguage
        ) ?? source
    }

    private func loadDetail(forceRefresh: Bool = false) async {
        detailLoadGeneration += 1
        let requestedGeneration = detailLoadGeneration
        isLoadingDetail = true
        errorMessage = nil
        defer {
            if requestedGeneration == detailLoadGeneration {
                isLoadingDetail = false
            }
        }

        if let cached = VNDB服务.shared.loadCachedCharacterDetail(
            characterID: characterID
        ) {
            presentLoadedDetail(cached)
            presentPreloadedImmersiveHeroImageIfNeeded()
        }
        do {
            let fetchedDetail = try await VNDB服务.shared.fetchCharacterDetail(
                characterID: characterID,
                forceRefresh: forceRefresh
            )
            guard requestedGeneration == detailLoadGeneration,
                  !Task.isCancelled else {
                return
            }
            presentLoadedDetail(fetchedDetail)
            presentPreloadedImmersiveHeroImageIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            guard requestedGeneration == detailLoadGeneration,
                  !Task.isCancelled else {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func presentLoadedDetail(_ loadedDetail: 角色详细信息) {
        guard detail != loadedDetail else { return }

        guard detail != nil, !reduceMotion else {
            detail = loadedDetail
            return
        }

        withAnimation(.smooth(duration: 0.38)) {
            detail = loadedDetail
        }
    }

    private func shouldBlurImage(
        sexual: Double?,
        violence: Double?
    ) -> Bool {
        内容安全限制判定.图片需要限制(
            sexual: sexual,
            violence: violence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
    }

    private func canRevealImage(sexual: Double?) -> Bool {
        内容安全限制判定.图片允许手动解除模糊(
            sexual: sexual,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            mode: filterMode
        )
    }

    private func restrictedCardImage(
        id: String,
        url: String?,
        sexual: Double?,
        violence: Double?,
        width: CGFloat,
        height: CGFloat,
        cornerRadius: CGFloat
    ) -> some View {
        let needsRestriction = shouldBlurImage(
            sexual: sexual,
            violence: violence
        )
        let isRevealed = revealedRelatedImageIDs.contains(id)
        let isRestricted = needsRestriction && (
            contentRestrictionMethod == .hidden || !isRevealed
        )

        return ZStack {
            CachedAsyncImage(
                url: URL(string: url ?? ""),
                contentMode: .fill
            )
            .frame(width: width, height: height)
            .clipped()
            .应用不安全内容限制(
                isRestricted,
                method: contentRestrictionMethod,
                blurRadius: 20
            )

            if isRestricted,
               contentRestrictionMethod == .blurred,
               canRevealImage(sexual: sexual) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        blurRevealConfirmation.request(id: id) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                let _ = revealedRelatedImageIDs.insert(id)
                            }
                        }
                    }
                    .accessibilityLabel("连按两次以解除模糊")
            }
        }
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.1))
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    private func shouldBlurTrait(_ trait: 角色特征) -> Bool {
        guard !shouldHideTrait(trait),
              !revealedTraitIDs.contains(trait.id) else {
            return false
        }
        let spoilerSetting =
            剧透标签模糊设置(rawValue: spoilerTagBlurLevel) ?? .majorOnly
        let spoilerHidden = spoilerSetting.shouldBlur(
            spoilerLevel: trait.spoiler
        )
        let adultBlurred = isAdultTraitRestricted(trait)
            && contentRestrictionMethod == .blurred
        return spoilerHidden || adultBlurred
    }

    private func shouldHideTrait(_ trait: 角色特征) -> Bool {
        isAdultTraitRestricted(trait) && contentRestrictionMethod == .hidden
    }

    private func isAdultTraitRestricted(_ trait: 角色特征) -> Bool {
        内容安全限制判定.色情特征需要限制(
            trait.sexual,
            enabled: contentFilterEnabled,
            mode: filterMode
        )
    }

    private func uniqueVisualNovels(
        _ visualNovels: [角色视觉小说关系]
    ) -> [角色视觉小说关系] {
        var seen: Set<String> = []
        return visualNovels.filter { seen.insert($0.id).inserted }
    }

    private func birthdayText(_ birthday: [Int]?) -> String? {
        guard let birthday, birthday.count >= 2 else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        // 用闰年承载月日，确保2月29日也能生成日期
        guard let date = calendar.date(
            from: DateComponents(year: 2000, month: birthday[0], day: birthday[1])
        ) else { return nil }
        return date.formatted(
            Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).day()
        )
    }

    private func combinedGenderText(_ detail: 角色详细信息) -> String {
        let sex = resolvedCharacterValue(detail.sex)
        let gender = resolvedCharacterValue(detail.gender)

        switch (sex, gender) {
        case ("m", "m"):
            return String(localized: "男性")
        case ("f", "f"):
            return String(localized: "女性")
        case ("m", "f"):
            return "MtF"
        case ("f", "m"):
            return "FtM"
        case (_, let gender?):
            return genderTitle(gender)
        case (let sex?, nil):
            return sexTitle(sex)
        default:
            return unknownText
        }
    }

    private func resolvedCharacterValue(_ values: [String?]?) -> String? {
        guard let values else { return nil }
        if values.indices.contains(1), let actualValue = values[1] {
            return actualValue
        }
        return values.first ?? nil
    }

    private func sexTitle(_ value: String) -> String {
        switch value {
        case "m": return String(localized: "男性")
        case "f": return String(localized: "女性")
        case "b": return String(localized: "双性")
        case "n": return String(localized: "无性")
        default: return value.uppercased()
        }
    }

    private func genderTitle(_ value: String) -> String {
        switch value {
        case "m": return String(localized: "男性")
        case "f": return String(localized: "女性")
        case "o": return String(localized: "非二元")
        case "a": return String(localized: "不明确")
        default: return value.uppercased()
        }
    }

}

private struct DivisionFrameModifier: ViewModifier {
    @Binding var divisionFrame: CGRect?

    func body(content: Content) -> some View {
        #if compiler(>=6.5)
        if #available(iOS 27.1, *) {
            content
                .onGeometryChange(for: CGRect?.self) { proxy in
                    proxy.reservedRegions(kind: .division)
                        .first(where: \.isActive)?
                        .frame
                } action: { frame in
                    divisionFrame = frame
                }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
