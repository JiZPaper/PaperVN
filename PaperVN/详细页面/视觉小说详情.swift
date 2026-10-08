import Foundation
import SwiftUI
@preconcurrency import Translation
import UIKit

private struct 外部浏览目标: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}

private struct 视觉小说标题拷贝项目: Identifiable {
    let id: String
    let label: String
    let value: String
}

private struct 视觉小说详情警报修饰器: ViewModifier {
    @Binding var translationError: String?
    @Binding var showLoginRequiredAlert: Bool
    @Binding var libraryActionError: String?
    @Binding var showLibraryDeleteConfirmation: Bool
    let navigationTitleText: String
    let deleteFromLibrary: () -> Void

    func body(content: Content) -> some View {
        content
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
            .alert("需要登录", isPresented: $showLoginRequiredAlert) {
                Button("好") { }
            } message: {
                Text("请先在资料库页面登录VNDB账户。")
            }
            .alert(
                "无法添加到资料库",
                isPresented: Binding(
                    get: { libraryActionError != nil },
                    set: { if !$0 { libraryActionError = nil } }
                )
            ) {
                Button("好") {
                    libraryActionError = nil
                }
            } message: {
                Text(verbatim: libraryActionError ?? "")
            }
            .alert(
                "从资料库删除",
                isPresented: $showLibraryDeleteConfirmation
            ) {
                Button("从资料库删除", role: .destructive) {
                    deleteFromLibrary()
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text(verbatim: String(
                    format: String(localized: "要从资料库删除“%@”吗？"),
                    navigationTitleText
                ))
            }
    }
}

private struct 视觉小说详情沉浸背景: View, Equatable {
    let imageURLs: [URL]
    let loadedImage: Image?
    let loadedImageURL: URL?
    let outgoingImage: Image?
    let aspectRatio: CGFloat?
    let transitionProgress: CGFloat
    let reduceMotion: Bool
    let onImageLoaded: (URL, Image, CGSize) -> Void
    let onImageReady: (URL) -> Void

    static func == (
        lhs: 视觉小说详情沉浸背景,
        rhs: 视觉小说详情沉浸背景
    ) -> Bool {
        lhs.imageURLs == rhs.imageURLs
            && lhs.loadedImageURL == rhs.loadedImageURL
            && (lhs.outgoingImage != nil) == (rhs.outgoingImage != nil)
            && lhs.aspectRatio == rhs.aspectRatio
            && lhs.transitionProgress == rhs.transitionProgress
            && lhs.reduceMotion == rhs.reduceMotion
            && (lhs.loadedImage != nil) == (rhs.loadedImage != nil)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.平台系统背景

                if !imageURLs.isEmpty {
                    imageLayer
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                        .scaleEffect(沉浸封面背景层参数.缩放)
                        .blur(radius: 沉浸封面背景层参数.模糊半径)
                        .saturation(沉浸封面背景层参数.饱和度)
                        .opacity(沉浸封面背景层参数.不透明度)

                    ForEach(imageURLs, id: \.absoluteString) { url in
                        CachedAsyncImage(
                            url: url,
                            contentMode: .fill,
                            onImageLoaded: onImageLoaded,
                            onImageReady: onImageReady
                        )
                        .frame(width: 1, height: 1)
                        .clipped()
                        .opacity(0)
                        .accessibilityHidden(true)
                    }
                }

                Color.平台系统背景.opacity(
                    沉浸封面背景层参数.系统背景覆盖不透明度
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var imageLayer: some View {
        if loadedImage != nil || outgoingImage != nil {
            ZStack {
                if let outgoingImage {
                    outgoingImage
                        .resizable()
                        .aspectRatio(aspectRatio, contentMode: .fill)
                }

                if let loadedImage {
                    loadedImage
                        .resizable()
                        .aspectRatio(aspectRatio, contentMode: .fill)
                        .opacity(transitionProgress)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: 0.3),
                            value: transitionProgress
                        )
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }
}

private enum 视觉小说沉浸取样框PreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func 视觉小说沉浸取样框(_ keys: [String]) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(
                    in: .named("ImmersiveDetailSampling")
                )
                if 视觉小说沉浸取样框有效(frame) {
                    Color.clear.preference(
                        key: 视觉小说沉浸取样框PreferenceKey.self,
                        value: Dictionary(
                            uniqueKeysWithValues: keys.map { ($0, frame) }
                        )
                    )
                } else {
                    Color.clear
                }
            }
        }
        .沉浸取样校准登记("视觉小说", keys: keys)
    }

    @ViewBuilder
    func 视觉小说沉浸取样框(_ frames: [String: CGRect]) -> some View {
        if frames.values.allSatisfy(视觉小说沉浸取样框有效) {
            preference(
                key: 视觉小说沉浸取样框PreferenceKey.self,
                value: frames
            )
        } else {
            self
        }
    }
}

private func 视觉小说沉浸取样框有效(_ frame: CGRect) -> Bool {
    frame.minX.isFinite
        && frame.minY.isFinite
        && frame.width.isFinite
        && frame.height.isFinite
        && frame.width > 0
        && frame.height > 0
}

/// 按初速度判断横向后才开始识别，并让系统返回手势优先，避免与竖向滚动和边缘右滑抢手势。
private struct 截屏水平拖动修饰器: ViewModifier {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize, CGSize) -> Void
    var onCancelled: () -> Void

    func body(content: Content) -> some View {
        content.gesture(
            截屏水平拖动手势(
                onChanged: onChanged,
                onEnded: onEnded,
                onCancelled: onCancelled
            )
        )
    }
}

private struct 截屏水平拖动手势: UIGestureRecognizerRepresentable {
    var onChanged: (CGSize) -> Void
    var onEnded: (CGSize, CGSize) -> Void
    var onCancelled: () -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gesture: 截屏水平拖动手势

        init(gesture: 截屏水平拖动手势) {
            self.gesture = gesture
        }

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer
            else {
                return false
            }

            let velocity = panGesture.velocity(in: panGesture.view)
            let horizontalVelocity = abs(velocity.x)
            let verticalVelocity = abs(velocity.y)
            return horizontalVelocity > 80
                && horizontalVelocity > verticalVelocity * 1.25
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(gesture: self)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func updateUIGestureRecognizer(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        context.coordinator.gesture = self
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        let translationPoint = recognizer.translation(in: recognizer.view)
        let translation = CGSize(
            width: translationPoint.x,
            height: translationPoint.y
        )

        switch recognizer.state {
        case .began, .changed:
            context.coordinator.gesture.onChanged(translation)
        case .ended:
            let velocity = recognizer.velocity(in: recognizer.view)
            let projectedTranslation = CGSize(
                width: translation.width + velocity.x * 0.18,
                height: translation.height + velocity.y * 0.18
            )
            context.coordinator.gesture.onEnded(
                translation,
                projectedTranslation
            )
        case .cancelled, .failed:
            context.coordinator.gesture.onCancelled()
        default:
            break
        }
    }
}

/// 在滚动视图底部继续上划时报告手指越过底部的距离，松手时结束。
/// 系统只提供回弹后的越界偏移，这里按 UIScrollView 的回弹曲线反解出手指位移，
/// 使阈值与拖动视觉保持以手指位移计。
/// `onEnded` 返回 true 时，等回弹归位后再调用 `onSettled`：
/// 回弹途中推入新页面会打断回弹，页面会瞬间跳回底部。
private struct 详情底部继续上划修饰器: ViewModifier {
    let isEnabled: Bool
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Bool
    let onSettled: () -> Void

    @State private var isInteracting = false
    @State private var isTracking = false
    @State private var isAwaitingSettle = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // ScrollGeometry 的 contentSize 已包含底部安全区，不能再加 contentInsets.bottom。
                let bottomOffset = max(
                    -geometry.contentInsets.top,
                    geometry.contentSize.height
                        - geometry.containerSize.height
                )
                let overscroll = max(geometry.contentOffset.y - bottomOffset, 0)
                return Self.fingerDistance(
                    forOverscroll: overscroll,
                    dimension: geometry.containerSize.height
                )
            } action: { _, distance in
                if isAwaitingSettle {
                    if distance <= 详情底部继续上划修饰器.归位容差 {
                        settle()
                    }
                    return
                }
                guard isEnabled, isInteracting else { return }
                if !isTracking {
                    guard distance > 0 else { return }
                    isTracking = true
                    onBegan()
                }
                onChanged(distance)
            }
            .onScrollPhaseChange { oldPhase, newPhase in
                if newPhase == .idle, isAwaitingSettle {
                    settle()
                    return
                }
                if newPhase == .interacting {
                    isInteracting = true
                    return
                }
                guard oldPhase == .interacting else { return }
                isInteracting = false
                guard isTracking else { return }
                isTracking = false
                isAwaitingSettle = onEnded()
            }
    }

    /// 越界换算成手指位移后小于此值即视为已回到底部。
    private static let 归位容差: CGFloat = 2

    private func settle() {
        isAwaitingSettle = false
        onSettled()
    }

    /// `overscroll = (1 - 1 / (x * 0.55 / d + 1)) * d` 的反函数。
    private static func fingerDistance(
        forOverscroll overscroll: CGFloat,
        dimension: CGFloat
    ) -> CGFloat {
        let dimension = max(dimension, 1)
        let overscroll = min(max(overscroll, 0), dimension * 0.99)
        return dimension / 0.55 * overscroll / (dimension - overscroll)
    }
}

private enum 视觉小说评论入口拖动参数 {
    static let 阈值: CGFloat = 144
    static let 最大视觉距离: CGFloat = 204
    static let 进度条宽度: CGFloat = 160
}

private struct 沉浸标签两行布局: Layout {
    var spacing: CGFloat = 8
    var forcePlaceMoreButton = false

    struct Cache {
        var sizes: [CGSize]
    }

    private struct Arrangement {
        var positions: [CGPoint?]
        var size: CGSize
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let idealWidth = cache.sizes.dropLast().reduce(CGFloat.zero) {
            $0 + $1.width + spacing
        }
        let width = proposal.width ?? max(idealWidth - spacing, 0)
        let result = arrangement(
            maxWidth: width,
            sizes: cache.sizes,
            forcePlaceMoreButton: forcePlaceMoreButton
        )

        return CGSize(
            width: proposal.width ?? result.size.width,
            height: result.size.height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        let result = arrangement(
            maxWidth: bounds.width,
            sizes: cache.sizes,
            forcePlaceMoreButton: forcePlaceMoreButton
        )

        for index in subviews.indices {
            guard let position = result.positions[index] else {
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX - 10_000,
                        y: bounds.minY - 10_000
                    ),
                    proposal: ProposedViewSize(width: 0, height: 0)
                )
                continue
            }

            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + position.x,
                    y: bounds.minY + position.y
                ),
                proposal: ProposedViewSize(cache.sizes[index])
            )
        }
    }

    private func arrangement(
        maxWidth: CGFloat,
        sizes: [CGSize],
        forcePlaceMoreButton: Bool
    ) -> Arrangement {
        guard !sizes.isEmpty else {
            return Arrangement(positions: [], size: .zero)
        }

        let availableWidth = max(maxWidth, 0)
        let moreIndex = sizes.index(before: sizes.endIndex)
        var positions = Array<CGPoint?>(repeating: nil, count: sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var line = 0
        var lineHeight: CGFloat = 0
        var maximumX: CGFloat = 0
        var overflowed = false

        for index in sizes.indices where index != moreIndex {
            let size = sizes[index]
            if x > 0, x + size.width > availableWidth {
                guard line == 0 else {
                    overflowed = true
                    break
                }
                y += lineHeight + spacing
                x = 0
                line = 1
                lineHeight = 0
            }

            positions[index] = CGPoint(x: x, y: y)
            maximumX = max(maximumX, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        guard overflowed || forcePlaceMoreButton else {
            return Arrangement(
                positions: positions,
                size: CGSize(width: maximumX, height: y + lineHeight)
            )
        }

        positions = Array(repeating: nil, count: sizes.count)
        x = 0
        y = 0
        lineHeight = 0
        var index = sizes.startIndex

        while index < moreIndex {
            let size = sizes[index]
            if x > 0, x + size.width > availableWidth {
                break
            }
            positions[index] = CGPoint(x: x, y: y)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            index += 1
        }

        y += lineHeight + spacing
        x = 0
        lineHeight = 0
        let moreSize = sizes[moreIndex]

        while index < moreIndex {
            let size = sizes[index]
            let requiredWidth = x + size.width + spacing + moreSize.width
            guard requiredWidth <= availableWidth else { break }

            positions[index] = CGPoint(x: x, y: y)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            index += 1
        }

        let moreX = x
        positions[moreIndex] = CGPoint(x: moreX, y: y)
        maximumX = max(x, moreX + moreSize.width)

        return Arrangement(
            positions: positions,
            size: CGSize(
                width: maximumX,
                height: y + max(lineHeight, moreSize.height)
            )
        )
    }
}

struct 视觉小说详情: View {
    let vnID: String
    private let initialTitle: String?
    private let initialTitles: [用户多语言标题]?
    private let initialImageURL: String?
    private let initialImageSexual: Double?
    private let initialImageViolence: Double?
    private let initialImageDimensions: [Int]?
    private let isFromRecommendation: Bool

    @Namespace private var editNamespace
    @Namespace private var descriptionNamespace
    @Namespace private var infoNamespace

    @ObservedObject private var auth: 用户登录
    @EnvironmentObject private var bangumiAccount: Bangumi账户
    @EnvironmentObject private var parentalControls: 家长控制中心
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.详情内容限制方式覆盖)
    private var contentRestrictionMethodOverride
    @AppStorage(活动地区偏好.设置键)
    private var activityRegionSelection = 活动地区偏好.默认值
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()
    @State private var detail: 视觉小说详细信息?
    @StateObject private var eventModel = PaperVN活动视图模型()
    @State private var userListItem: 用户列表项目?
    @State private var hasLoadedUserListItem = false
    @State private var isAddingToLibrary = false
    @State private var libraryActionError: String?
    @State private var pendingReleaseID: String?
    @State private var showLibraryDeleteConfirmation = false
    @State private var releases: [视觉小说发行版本] = []
    @State private var errorMessage: String?
    @State private var isLoadingDetail = true
    @State private var detailLoadGeneration = 0

    @State private var showTranslatedDescription = false
    @State private var showTranslatedTags = false
    @State private var translatedDescription: String?
    @State private var translatedTagNames: [String: String] = [:]
    @State private var translationError: String?
    @State private var isTranslatingDescription = false
    @State private var isTranslatingTags = false
    @State private var descriptionTranslationConfiguration: TranslationSession.Configuration?
    @State private var tagTranslationConfiguration: TranslationSession.Configuration?

    @State private var revealedTagIDs: Set<String> = []
    @State private var revealAverageRating = false
    @State private var revealHeroImage = false
    @State private var immersiveHeroGestureIsActive = false
    @State private var immersiveViewportSize: CGSize = .zero
    @State private var immersiveDivisionFrame: CGRect?
    @State private var revealDescription = false
    @State private var revealScreenshotIDs: Set<String> = []
    @State private var revealedRelatedImageIDs: Set<String> = []
    @State private var screenshotStackFrontIndex = 0
    @State private var screenshotStackDragOffset = CGSize.zero
    @State private var screenshotStackPromotionProgress: CGFloat = 0
    @State private var screenshotStackIsCompletingSwipe = false
    @State private var externalBrowserTarget: 外部浏览目标?
    @State private var showDescriptionSheet = false
    @State private var isDescriptionTruncated = false
    @State private var showEditSheet = false
    @State private var showInfoSheet = false
    @State private var showLoginRequiredAlert = false
    @State private var showAllTags = false
    @State private var tagsContentOpacity = 1.0
    @State private var isSwitchingTagLanguage = false
    @State private var expandedStaffRoles: Set<String> = []
    @State private var manualDescription: String?
    @State private var hasFinishedManualDescriptionLookup = false
    @State private var manualDescriptionLookupTimedOut = false
    @State private var manualDescriptionLookupKey: String?
    @State private var immersiveTextSamples:
        [String: 沉浸玻璃文字取样结果]
    @State private var immersiveTextSampleURL: URL?
    @State private var immersiveTextRevealURL: URL?
    @State private var immersiveTextSampleGeometry:
        沉浸封面文字取样几何?
    @State private var immersiveTextSamplingCoordinator =
        沉浸封面文字取样任务协调器(校准名称: "视觉小说")
    @State private var immersiveLoadedHeroImage: Image?
    @State private var immersiveLoadedHeroImageURL: URL?
    @State private var immersiveOutgoingHeroImage: Image?
    @State private var immersiveHeroImageTransitionProgress: CGFloat = 1
    @State private var immersiveHeroImageTransitionGeneration = 0
    @State private var externalComments: [视觉小说评论] = []
    @State private var isLoadingExternalComments = false
    @State private var externalCommentsError: String?
    @State private var commentDraft = ""
    @State private var isPublishingComment = false
    @State private var showAllComments = false
    @State private var moreCommentsPullDistance: CGFloat = 0
    @State private var moreCommentsPullIsArmed = false
    @State private var moreCommentsPullFeedbackIssued = false
    @State private var moreCommentsPullFeedback = 0
    @State private var unifiedRating: 统一视觉小说评分?

    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("subTitleLang") private var subTitleLang: 副标题语言 = .none
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    @AppStorage("staffNameLang") private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both
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
    @AppStorage("blurAverageRating") private var blurAverageRating = false
    @AppStorage("blurDescription") private var blurDescription = false
    @AppStorage(评分数据来源.设置键)
    private var ratingSource = 评分数据来源.combined.rawValue
    @AppStorage("combinedRatingVNDBWeight")
    private var combinedRatingVNDBWeight = 0.5
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var immersiveDetailAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }

    init(
        vnID: String,
        auth: 用户登录,
        initialTitle: String? = nil,
        initialTitles: [用户多语言标题]? = nil,
        initialImageURL: String? = nil,
        initialImageSexual: Double? = nil,
        initialImageViolence: Double? = nil,
        initialImageDimensions: [Int]? = nil,
        isFromRecommendation: Bool = false
    ) {
        let cachedDetail = VNDB服务.shared.loadCachedVNDetail(vnID: vnID)

        self.vnID = vnID
        _auth = ObservedObject(wrappedValue: auth)
        self.initialTitle = initialTitle
        self.initialTitles = initialTitles
        self.initialImageURL = initialImageURL
        self.initialImageSexual = initialImageSexual
        self.initialImageViolence = initialImageViolence
        self.initialImageDimensions = initialImageDimensions
        self.isFromRecommendation = isFromRecommendation
        _detail = State(initialValue: cachedDetail)
        _immersiveTextSamples = State(initialValue: [:])
        _immersiveTextSampleURL = State(initialValue: nil)
        _immersiveTextRevealURL = State(initialValue: nil)
    }

    var body: some View {
        let renderedDetail = displayedDetail
        let imageURLs = immersiveImageURLs(for: renderedDetail)

        immersiveDetail(renderedDetail, imageURLs: imageURLs)
        .navigationTitle(navigationTitleText)
        .平台柔和滚动边缘(for: .top)
        .平台隐藏导航标题占位(navigationTitleText)
        .平台内联导航标题()
        .toolbar {
            detailToolbar
        }
        .task(
            id: "\(vnID)|\(targetLanguage.rawValue)|\(descriptionTranslationMode.rawValue)"
        ) {
            let translationMode = VNDB简介翻译模式.current
            let lookupKey = manualDescriptionLookupKeyValue(
                mode: translationMode
            )
            let cachedResult = VNDB简介人工翻译.译文缓存结果(
                for: vnID,
                type: .visualNovel,
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
            } else {
                if let cachedTranslation = cachedResult.translation {
                    manualDescription = cachedTranslation
                }
                hasFinishedManualDescriptionLookup = true
                manualDescriptionLookupTimedOut = false
                manualDescriptionLookupKey = lookupKey
            }

            async let translation = VNDB简介人工翻译.译文结果(
                for: vnID,
                type: .visualNovel,
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
                    withAnimation(.easeInOut(duration: 0.22)) {
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
                withAnimation(.easeInOut(duration: 0.28)) {
                    manualDescription = resolvedResult.translation
                }
                return
            }
            withAnimation(.easeInOut(duration: 0.28)) {
                if let resolvedTranslation = resolvedResult.translation {
                    manualDescription = resolvedTranslation
                }
                hasFinishedManualDescriptionLookup = true
            }
        }
        .task(id: "comments|\(vnID)|\(评论数据来源.current.rawValue)|\(Steam评论语言.selected.map(\.rawValue).sorted().joined(separator: ","))") {
            guard 有评论来源ID else { return }
            await loadExternalComments()
        }
        .task(id: "events|\(eventActorNames.joined(separator: "|"))|\(eventRelatedTerms.joined(separator: "|"))|\(activityRegionSelection)") {
            guard !eventActorNames.isEmpty else { return }
            await eventModel.load(
                actorNames: eventActorNames,
                relatedTerms: eventRelatedTerms
            )
        }
        .task(id: "rating|\(vnID)|\(ratingSource)|\(combinedRatingVNDBWeight)|\(detail?.rating ?? -1)") {
            let value = detail ?? displayedDetail
            unifiedRating = await 视觉小说外部数据服务.shared.rating(
                vndbID: vnID,
                vndbRating: value.rating,
                vndbVoteCount: value.votecount
            )
        }
        .task(id: auth.userID) {
            await loadUserListItem()
        }
        .onAppear {
            guard isFromRecommendation else { return }
            推荐反馈中心.shared.记录打开(vnID, userID: auth.userID)
        }
        .onChange(of: colorScheme) { _, _ in
            immersiveTextSamples = [:]
            immersiveTextSampleURL = nil
            immersiveTextRevealURL = nil
            refreshImmersiveTextSamplesForCurrentAppearance()
        }
        .translationTask(descriptionTranslationConfiguration) { session in
            await translateDescription(using: session)
        }
        .translationTask(tagTranslationConfiguration) { session in
            await translateMissingTags(using: session)
        }
        .sheet(item: $externalBrowserTarget) { target in
            内置Safari浏览器(url: target.url)
                .平台近全屏弹窗()
        }
        .sheet(isPresented: $showDescriptionSheet) {
            if let detail {
                descriptionSheetContent(detail)
                    .navigationTransition(.zoom(
                        sourceID: "DescriptionSheet",
                        in: descriptionNamespace
                    ))
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if detail != nil {
                资料库编辑页面(
                    vnID: vnID,
                    title: navigationTitleResult,
                    token: auth.token,
                    currentItem: userListItem,
                    releases: releases,
                    initialReleaseID: pendingReleaseID
                ) {
                    await loadUserListItem(forceRefresh: true)
                }
                .平台近全屏弹窗(dragIndicator: .visible)
                .navigationTransition(.zoom(sourceID: "EditSheet", in: editNamespace))
            }
        }
        .sheet(isPresented: $showInfoSheet) {
            if let detail {
                detailInfoSheetContent(detail)
                    .navigationTransition(.zoom(
                        sourceID: "InfoSheet",
                        in: infoNamespace
                    ))
            }
        }
        .onChange(of: showEditSheet) { _, isPresented in
            if !isPresented {
                pendingReleaseID = nil
            }
        }
        .navigationDestination(isPresented: $showAllTags) {
            allTagsDestination
        }
        .navigationDestination(isPresented: $showAllComments) {
            评论列表页面(vndbID: vnID)
        }
        .onChange(of: showAllComments) { _, isPresented in
            guard !isPresented else { return }
            withAnimation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.34, dampingFraction: 0.82)
            ) {
                moreCommentsPullDistance = 0
                moreCommentsPullIsArmed = false
                moreCommentsPullFeedbackIssued = false
            }
        }
        .modifier(视觉小说详情警报修饰器(
            translationError: $translationError,
            showLoginRequiredAlert: $showLoginRequiredAlert,
            libraryActionError: $libraryActionError,
            showLibraryDeleteConfirmation: $showLibraryDeleteConfirmation,
            navigationTitleText: navigationTitleText,
            deleteFromLibrary: deleteFromLibrary
        ))
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
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .平台主操作) {
            editButton
        }

        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .平台主操作)
        }

        ToolbarItem(placement: .平台主操作) {
            Button {
                guard self.detail != nil else { return }
                showInfoSheet = true
            } label: {
                Image(systemName: "info.circle")
            }
            .disabled(self.detail == nil)
            .matchedTransitionSource(id: "InfoSheet", in: infoNamespace)
            .accessibilityLabel("更多信息")
        }
    }

    private var editButton: some View {
        Button {
            if shouldShowAddButton {
                addToPlanning()
            } else if auth.token.isEmpty || auth.userID.isEmpty {
                showLoginRequiredAlert = true
            } else {
                showEditSheet = true
            }
        } label: {
            if isAddingToLibrary {
                ProgressView()
            } else {
                Image(
                    systemName: shouldShowAddButton
                        ? "plus"
                        : "square.and.pencil"
                )
            }
        }
        .disabled(isAddingToLibrary)
        .matchedTransitionSource(id: "EditSheet", in: editNamespace)
        .accessibilityLabel(
            shouldShowAddButton ? "加入计划游玩" : "编辑资料库"
        )
    }

    private var displayedDetail: 视觉小说详细信息 {
        detail ?? 视觉小说详细信息(
            id: vnID,
            title: initialTitle ?? String(localized: "游戏详情"),
            titles: initialTitles,
            aliases: nil,
            olang: nil,
            devstatus: nil,
            released: nil,
            languages: nil,
            platforms: nil,
            image: initialImageURL.map {
                视觉小说图片(
                    id: nil,
                    url: $0,
                    thumbnail: nil,
                    sexual: initialImageSexual,
                    violence: initialImageViolence,
                    dims: initialImageDimensions
                )
            },
            length: nil,
            length_minutes: nil,
            length_votes: nil,
            description: nil,
            rating: nil,
            votecount: nil,
            tags: nil,
            developers: nil,
            screenshots: nil,
            relations: nil,
            staff: nil,
            va: nil,
            extlinks: nil
        )
    }

    private var eventActorNames: [String] {
        var values: [String] = []
        for relationship in displayedDetail.va ?? [] {
            values.append(relationship.staff.name)
            if let original = relationship.staff.original {
                values.append(original)
            }
        }
        return values
    }

    private var eventRelatedTerms: [String] {
        var values = [displayedDetail.title]
        values.append(contentsOf: displayedDetail.titles?.flatMap { title in
            [title.title, title.latin]
        }.compactMap { $0 } ?? [])
        values.append(contentsOf: displayedDetail.aliases ?? [])
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var shouldShowEventSection: Bool {
        !eventModel.events.isEmpty
    }

    private var allTagsDestination: some View {
        更多标签页面(
            tags: displayedDetail.sortedTags,
            spoilerUnlockedByProgress: hasFinishedOrDropped,
            showTranslatedText: $showTranslatedTags,
            translatedNames: $translatedTagNames
        )
    }

    private var navigationTitleText: String {
        navigationTitleResult.text
    }

    private var navigationTitleResult: 标题工具.标题结果 {
        let detail = displayedDetail
        return 标题工具.获取主标题(
            titles: detail.titles,
            defaultTitle: detail.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    private var hasFinishedOrDropped: Bool {
        userListItem?.primaryStatus == .finished
            || userListItem?.primaryStatus == .dropped
    }

    private var shouldShowAddButton: Bool {
        !auth.token.isEmpty
            && !auth.userID.isEmpty
            && hasLoadedUserListItem
            && userListItem == nil
    }

    private var shouldBlurAverageRating: Bool {
        blurAverageRating && userListItem?.vote == nil && !revealAverageRating
    }

    private func immersiveDetail(
        _ detail: 视觉小说详细信息,
        imageURLs: [URL]
    ) -> some View {
        let primaryInformation = immersivePrimaryInformationPresentation(
            detail
        )

        return ZStack {
            视觉小说详情沉浸背景(
                imageURLs: imageURLs,
                loadedImage: immersivePresentedHeroImage,
                loadedImageURL: immersiveLoadedHeroImageURL,
                outgoingImage: immersiveOutgoingHeroImage,
                aspectRatio: immersiveHeroSourceAspectRatio,
                transitionProgress: immersiveHeroImageTransitionProgress,
                reduceMotion: reduceMotion,
                onImageLoaded: { loadedURL, image, _ in
                    activateImmersiveHeroImage(image, for: loadedURL)
                },
                onImageReady: { loadedURL in
                    updateImmersiveTextSamples(for: loadedURL)
                }
            )
            .equatable()

            ScrollView {
                沉浸封面详情内容(
                    onGestureActivityChanged: updateImmersiveHeroGestureActivity
                ) { dragContext in
                    immersiveHeroAndPrimaryInformation(
                        detail,
                        imageURLs: imageURLs,
                        dragContext: dragContext,
                        primaryInformation: primaryInformation
                    )
                } content: {
                    if let screenshots = detail.screenshots,
                       !screenshots.isEmpty {
                        immersiveScreenshotStack(screenshots)
                    }

                    detailFailureCard
                        .padding(
                            .horizontal,
                            immersivePageHorizontalPadding
                        )

                    if isShowingInitialSkeleton {
                        immersiveLoadingContent
                            .transition(.opacity)
                    } else {
                        immersiveMediaContent(detail)
                            .transition(.opacity)
                    }
                }
            }
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
                        showAllComments = true
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
            immersiveViewportSize = size
        }
        .modifier(DivisionFrameModifier(divisionFrame: $immersiveDivisionFrame))
        .scrollIndicators(.hidden)
        .coordinateSpace(name: "ImmersiveDetailScroll")
        .onPreferenceChange(视觉小说沉浸取样框PreferenceKey.self) { frames in
            updateImmersiveTextSampleGeometry(from: frames)
        }
        .ignoresSafeArea(edges: .top)
        .平台沉浸导航栏()
    }

    private func immersiveHeroAndPrimaryInformation<PrimaryInformation: View>(
        _ detail: 视觉小说详细信息,
        imageURLs: [URL],
        dragContext: 沉浸封面拖动上下文,
        primaryInformation: PrimaryInformation
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            immersiveHero(
                detail,
                imageURLs: imageURLs,
                dragContext: dragContext
            )
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
        .coordinateSpace(name: "ImmersiveDetailSampling")
    }

    private func immersiveHero(
        _ detail: 视觉小说详细信息,
        imageURLs: [URL],
        dragContext: 沉浸封面拖动上下文
    ) -> some View {
        return GeometryReader { proxy in
            let width = proxy.size.width
            let heroHeight = proxy.size.height
            let fadeOverflow: CGFloat = 72
            let scrollFrame = proxy.frame(in: .named("ImmersiveDetailScroll"))
            let samplingFrame = proxy.frame(
                in: .named("ImmersiveDetailSampling")
            )
            let pullDown = scrollFrame.minY.isFinite
                ? max(scrollFrame.minY, 0)
                : 0
            let descriptionExtension = immersiveHeroDescriptionExtension(
                for: detail,
                imageURLs: imageURLs
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
                + (fadeOverflow + descriptionExtension)
                    * (1 - transitionProgress)
            let sampleImageFrame = CGRect(
                x: samplingFrame.minX,
                y: samplingFrame.minY - pullDown,
                width: width,
                height: heroHeight + fadeOverflow + descriptionExtension
            )
            let primaryInformationStart = heroHeight
                + 24
                - immersiveDescriptionOverlap
                + pullDown
            let regularTransitionStart = min(
                max(primaryInformationStart / renderedHeight, 0),
                1
            )
            let needsRestriction = shouldBlurImage(
                sexual: detail.image?.sexual,
                violence: detail.image?.violence
            )
            let isRestricted = needsRestriction && (
                contentRestrictionMethod == .hidden || !revealHeroImage
            )

            ZStack(alignment: .top) {
                if !imageURLs.isEmpty {
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
                                  canRevealImage(
                                    sexual: detail.image?.sexual
                                  ) else {
                                return
                            }
                            blurRevealConfirmation.request(id: "hero-image") {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    revealHeroImage = true
                                }
                            }
                        }
                    ) { pullProgress in
                        immersiveHeroImagePresentation(
                            loadedImage: immersivePresentedHeroImage,
                            extendsThroughDescription: descriptionExtension > 0,
                            regularTransitionStart: regularTransitionStart,
                            width: width,
                            heroHeight: heroHeight,
                            renderedHeight: renderedHeight,
                            backgroundHeight: heroHeight
                                + fadeOverflow
                                + descriptionExtension,
                            imageTopInset: imageTopInset,
                            minimumRasterHeight: heroHeight
                                + fadeOverflow
                                + descriptionExtension
                                + 160,
                            pullProgress: pullProgress
                        )
                        .应用不安全内容限制(
                            isRestricted,
                            method: contentRestrictionMethod,
                            blurRadius: 28
                        )
                        .animation(
                            .easeInOut(duration: 0.28),
                            value: revealHeroImage
                        )
                    }
                } else if isShowingInitialSkeleton {
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
        .frame(
            height: horizontalSizeClass == .regular ? 420 : nil
        )
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

        immersiveHeroBackgroundExtension {
            immersiveRasterizedHeroImage(
                loadedImage: loadedImage,
                extendsThroughDescription: extendsThroughDescription,
                regularTransitionStart: regularTransitionStart,
                revealProgress: transitionProgress,
                width: imageWidth,
                renderedHeight: presentationHeight,
                minimumRasterHeight: minimumRasterHeight
            )
        }
        .frame(width: imageWidth, height: presentationHeight)
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

    private var immersivePageHorizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 24 : 16
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

    private var immersiveDescriptionOverlap: CGFloat {
        horizontalSizeClass == .regular ? 154 : 82
    }

    private func immersivePrimaryInformation(
        _ detail: 视觉小说详细信息,
        showsContent: Bool = true
    ) -> some View {
        let tags = detail.sortedTags.filter { !shouldHideTag($0) }
        let hasDescription = detail.cleanDescription?.isEmpty == false
        let showsDescription = showsContent && shouldDisplayDescription
        let showsLoadingPlaceholders = self.detail == nil

        return VStack(
            alignment: .leading,
            spacing: 沉浸详情布局.主要信息间距
        ) {
            if horizontalSizeClass == .regular {
                沉浸详情等高双栏布局(
                    spacing: 16,
                    divisionFrame: immersiveDivisionFrame,
                    horizontalInset: immersivePageHorizontalPadding
                ) {
                    immersiveMetadata(
                        detail,
                        fillsAvailableHeight:
                            hasDescription || showsLoadingPlaceholders,
                        showsContent: showsContent
                    )
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    if hasDescription || showsLoadingPlaceholders {
                        immersiveDescriptionContent(
                            detail,
                            outerHorizontalPadding: 0,
                            fillsAvailableHeight: true,
                            showsContent: showsDescription
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .transition(.identity)
                    }
                }
                .padding(.horizontal, immersivePageHorizontalPadding)
                .transition(.identity)
            } else {
                immersiveMetadata(detail, showsContent: showsContent)
                    .padding(.horizontal, immersivePageHorizontalPadding)
                    .transition(.identity)

                if hasDescription || showsLoadingPlaceholders {
                    immersiveDescriptionContent(
                        detail,
                        outerHorizontalPadding: immersivePageHorizontalPadding,
                        showsContent: showsDescription
                    )
                    .transition(.identity)
                }
            }

            if !tags.isEmpty {
                immersiveInlineTags(tags)
                    .opacity(showsContent ? 1 : 0)
                    .allowsHitTesting(showsContent)
                    .transition(.identity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func immersiveHeroDescriptionExtension(
        for detail: 视觉小说详细信息,
        imageURLs: [URL]
    ) -> CGFloat {
        guard !imageURLs.isEmpty else { return 0 }

        let hasDescription = detail.cleanDescription?.isEmpty == false
        let hasVisibleTags = detail.sortedTags.contains {
            !shouldHideTag($0)
        }
        guard hasDescription || hasVisibleTags else { return 0 }

        if horizontalSizeClass == .regular {
            return hasVisibleTags ? 284 : 120
        }
        return hasVisibleTags ? 316 : 148
    }

    private func immersiveHeroImage(
        loadedImage: Image?,
        extendsThroughDescription: Bool,
        regularTransitionStart: CGFloat,
        revealProgress: CGFloat
    ) -> some View {
        immersiveHeroImageComposition(
            loadedImage: loadedImage,
            gradient: immersiveHeroGradient(
                extendsThroughDescription: extendsThroughDescription,
                regularTransitionStart: regularTransitionStart
            ),
            revealProgress: revealProgress
        )
    }

    private func immersiveHeroGradient(
        extendsThroughDescription: Bool,
        regularTransitionStart: CGFloat
    ) -> 沉浸封面渐变方案 {
        if extendsThroughDescription, horizontalSizeClass == .regular {
            return .常规(transitionStart: regularTransitionStart)
        }
        return extendsThroughDescription ? .紧凑延伸 : .紧凑标准
    }

    @ViewBuilder
    private func immersiveHeroBackgroundExtension<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .平台背景延伸效果()
    }

    private func immersiveRasterizedHeroImage(
        loadedImage: Image?,
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
            immersiveHeroImage(
                loadedImage: loadedImage,
                extendsThroughDescription: extendsThroughDescription,
                regularTransitionStart: regularTransitionStart,
                revealProgress: revealProgress
            )
            .frame(width: width, height: renderedHeight)
        }
        .frame(width: width, height: rasterHeight, alignment: .top)
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .frame(width: width, height: renderedHeight, alignment: .top)
        .clipped()
    }

    private func immersiveHeroImageComposition(
        loadedImage: Image?,
        gradient: 沉浸封面渐变方案,
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
                            stops: gradient.sharp.gradientStops,
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
                .blur(radius: gradient.mediumBlurRadius)
                .mask {
                    LinearGradient(
                        stops: gradient.medium.gradientStops,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .opacity(1 - revealProgress)

            immersiveHeroImageLayer(
                loadedImage: loadedImage,
                revealProgress: revealProgress
            )
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

    private func immersiveAlignedHeroImage(
        _ image: Image,
        revealProgress: CGFloat
    ) -> some View {
        GeometryReader { proxy in
            image
                .resizable()
                .aspectRatio(
                    immersiveHeroSourceAspectRatio,
                    contentMode: .fill
                )
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
        let dimensions = detail?.image?.dims ?? initialImageDimensions
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
        for detail: 视觉小说详细信息
    ) -> Bool {
        self.detail != nil || isShowingInitialSkeleton
    }

    private var immersiveSystemGlassTint: Color? {
        guard immersiveDetailAppearance == .clear,
              immersiveImageURLs(for: displayedDetail).isEmpty else {
            return nil
        }
        return colorScheme == .dark ? .black : .white
    }

    private func immersivePrimaryInformationPresentation(
        _ detail: 视觉小说详细信息
    ) -> AnyView {
        let showsContent = immersivePrimaryInformationIsVisible(for: detail)
        return AnyView(
            immersivePrimaryInformation(detail, showsContent: showsContent)
        )
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
        for url: URL
    ) {
        guard shouldAcceptImmersiveImage(at: url) else { return }

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

        guard shouldAnimate else { return }
        Task { @MainActor in
            await Task.yield()
            guard transitionGeneration
                    == immersiveHeroImageTransitionGeneration else {
                return
            }
            immersiveHeroImageTransitionProgress = 1
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
            immersiveHeroImageTransitionProgress = 1
        }
    }

    private func revealImmersiveTextIfNeeded(for url: URL) {
        guard detail != nil else { return }
        guard hasImmersiveTextSampleGeometry else { return }
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
        let imageURLs = immersiveImageURLs(for: displayedDetail)
        let descriptionExtension = immersiveHeroDescriptionExtension(
            for: displayedDetail,
            imageURLs: imageURLs
        )
        // 与 immersiveHero 中静止状态（无下拉）的过渡位置一致。
        let layerHeight = max(geometry.imageSize.height, 1)
        let heroHeight = layerHeight - 72 - descriptionExtension
        let request = 沉浸封面文字取样请求(
            url: url,
            layout: .visualNovel,
            background: colorScheme == .dark ? .dark : .light,
            gradient: descriptionExtension > 0
                && horizontalSizeClass == .regular
                ? .常规取样(
                    transitionStart: (heroHeight + 24 - immersiveDescriptionOverlap)
                        / layerHeight
                )
                : descriptionExtension > 0 ? .紧凑延伸 : .紧凑标准,
            itemCounts: [
                "tags": displayedDetail.sortedTags.filter {
                    !shouldHideTag($0)
                }.prefix(
                    horizontalSizeClass == .regular
                        ? 沉浸详情布局.常规内联标签上限
                        : 沉浸详情布局.紧凑内联标签上限
                ).count
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
            let needsReveal = revealsImmediately
                && immersiveTextRevealURL != request.url
            guard samplesChanged || needsInitialGeometry || needsReveal else {
                return
            }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                immersiveTextSampleGeometry = request.geometry
                immersiveTextSamples = samples
                immersiveTextSampleURL = request.url
                if revealsImmediately {
                    immersiveTextRevealURL = request.url
                }
            }
            if !revealsImmediately {
                revealImmersiveTextIfNeeded(for: request.url)
            }
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

    private func updateImmersiveTextSampleGeometry(
        from frames: [String: CGRect]
    ) {
        guard let imageFrame = frames["image"],
              视觉小说沉浸取样框有效(imageFrame) else {
            return
        }

        var regions: [String: CGRect] = [:]
        for (key, frame) in frames where key != "image" {
            guard 视觉小说沉浸取样框有效(frame) else { continue }
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
            regions: regions,
            viewportSize: immersiveViewportSize,
            contentOffsetY: horizontalSizeClass == .regular ? -60 : 0
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
        guard 视觉小说沉浸取样框有效(frame) else { return nil }

        func snapped(_ value: CGFloat) -> CGFloat {
            (value * 2).rounded() / 2
        }

        let snappedFrame = CGRect(
            x: snapped(frame.minX),
            y: snapped(frame.minY),
            width: snapped(frame.width),
            height: snapped(frame.height)
        )
        return 视觉小说沉浸取样框有效(snappedFrame)
            ? snappedFrame
            : nil
    }

    private func immersiveImageURLs(
        for detail: 视觉小说详细信息
    ) -> [URL] {
        [
            detail.image?.url,
            initialImageURL
        ]
        .compactMap { value -> URL? in
            guard let value,
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil,
                  !url.path.contains("/cv.t/") else {
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
            appearance: immersiveDetailAppearance,
            sample: immersiveTextSamples[key],
            fallbackColorScheme: colorScheme
        )
    }

    private func immersiveMetadata(
        _ detail: 视觉小说详细信息,
        fillsAvailableHeight: Bool = false,
        showsContent: Bool = true
    ) -> some View {
        let informationSampleKey = "metadata"
        let informationTextStyle = immersiveMetadataTextStyle(
            for: informationSampleKey
        )

        return VStack(
            alignment: .leading,
            spacing: fillsAvailableHeight ? 0 : 14
        ) {
            immersiveTitleContent(detail)

            if fillsAvailableHeight {
                Spacer(minLength: 14)
            }

            if isShowingInitialSkeleton {
                immersiveLoadingMetadata
            } else {
                immersiveStats(detail, textStyle: informationTextStyle)
                    .沉浸详情文字阴影(informationTextStyle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(showsContent ? 1 : 0)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .沉浸详情玻璃背景(
            immersiveDetailAppearance,
            sample: informationTextStyle.sample,
            fallbackTint: immersiveSystemGlassTint,
            usesBrightReducedMaterial: true,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .视觉小说沉浸取样框(["metadata"])
    }

    private func immersiveTitleContent(
        _ detail: 视觉小说详细信息
    ) -> some View {
        let sampleKey = "metadata.title"
        let textStyle = immersiveMetadataTextStyle(for: sampleKey)
        let main = 标题工具.获取主标题(
            titles: detail.titles,
            defaultTitle: detail.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
        let subtitle = 标题工具.获取副标题(
            titles: detail.titles,
            defaultTitle: detail.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            副标题设置: subTitleLang,
            允许非官方: allowUnofficialTitles
        )

        return VStack(alignment: .leading, spacing: 4) {
            Text(
                标题工具.生成富文本(
                    文本: main.text,
                    isJapanese: main.isJapanese,
                    基础大小: 22,
                    是粗体: true,
                    日文字体名称: "HiraginoSans-W6",
                    系统字体粗细: .bold,
                    语言代码: main.languageCode
                )
            )
            .沉浸详情文字前景色(textStyle.primary, style: textStyle)
            .lineLimit(2)
            .contextMenu {
                titleCopyContextMenu(for: detail)
            }

            if let subtitle {
                Text(
                    标题工具.生成富文本(
                        文本: subtitle.text,
                        isJapanese: subtitle.isJapanese,
                        基础大小: 15,
                        语言代码: subtitle.languageCode
                    )
                )
                .沉浸详情文字前景色(textStyle.secondary, style: textStyle)
                .fontWeight(.regular)
                .lineLimit(2)
            }
        }
        // 按文字实际占的宽度取样，不含标题右侧的空白。
        .视觉小说沉浸取样框(["metadata.title"])
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(textStyle)
    }

    private var immersiveLoadingMetadata: some View {
        let textStyle = immersiveMetadataTextStyle(for: "loading")

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                immersiveMetadataItem(
                    icon: "chart.bar.xaxis",
                    title: "评分",
                    text: "8.50（999人评分）",
                    valueLineLimit: 1,
                    valueMinimumScaleFactor: 0.82,
                    textStyle: textStyle
                )

                immersiveMetadataItem(
                    icon: "clock",
                    title: "篇幅",
                    text: "正在载入…",
                    textStyle: textStyle
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                immersiveMetadataItem(
                    icon: "calendar",
                    title: "发行日期",
                    text: "正在载入…",
                    textStyle: textStyle
                )

                immersiveMetadataItem(
                    icon: "checkmark.circle",
                    title: "开发状态",
                    text: "正在载入…",
                    textStyle: textStyle
                )
            }
            .padding(.leading, 6)
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
    }

    private func immersiveStats(
        _ detail: 视觉小说详细信息,
        textStyle: 沉浸详情文字样式
    ) -> some View {
        let rowSpacing: CGFloat = horizontalSizeClass == .regular ? 14 : 8
        let ratingText = unifiedRating?.shortText
            ?? detail.rating.map { String(format: "%.2f", $0 / 10) }
        let voteText = (unifiedRating?.voteCount ?? detail.votecount).map {
            String(localized: "\($0)人评分")
        }

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: rowSpacing) {
                if let ratingText {
                    immersiveMetadataItem(
                        icon: "chart.bar.xaxis",
                        title: "评分",
                        text: voteText.map {
                            "\(ratingText)（\($0)）"
                        } ?? ratingText,
                        valueLineLimit: 1,
                        valueMinimumScaleFactor: 0.82,
                        textStyle: immersiveMetadataTextStyle(for: "metadata.rating"),
                        sampleKey: "metadata.rating"
                    )
                    .blur(radius: shouldBlurAverageRating ? 6 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard shouldBlurAverageRating else { return }
                        blurRevealConfirmation.request(id: "average-rating") {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                revealAverageRating = true
                            }
                        }
                    }
                }

                immersiveMetadataItem(
                    icon: "clock",
                    title: "篇幅",
                    text: detail.displayLength,
                    textStyle: immersiveMetadataTextStyle(for: "metadata.length"),
                    sampleKey: "metadata.length"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: rowSpacing) {
                if let released = detail.released {
                    immersiveMetadataItem(
                        icon: "calendar",
                        title: "发行日期",
                        text: released,
                        textStyle: immersiveMetadataTextStyle(for: "metadata.release"),
                        sampleKey: "metadata.release"
                    )
                }

                immersiveMetadataItem(
                    icon: "checkmark.circle",
                    title: "开发状态",
                    text: detail.displayDevStatus,
                    textStyle: immersiveMetadataTextStyle(for: "metadata.status"),
                    sampleKey: "metadata.status"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)
        }
    }

    private func immersiveMetadataItem(
        icon: String,
        title: LocalizedStringKey,
        text: String,
        valueLineLimit: Int = 2,
        valueMinimumScaleFactor: CGFloat = 1,
        textStyle: 沉浸详情文字样式,
        sampleKey: String? = nil
    ) -> some View {
        return HStack(alignment: .top, spacing: 9) {
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
                    .minimumScaleFactor(valueMinimumScaleFactor)
                    .allowsTightening(valueLineLimit == 1)
            }
        }
        .视觉小说沉浸取样框(sampleKey.map { [$0] } ?? [])
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(textStyle)
    }

    private func immersiveInlineTags(
        _ tags: [视觉小说标签]
    ) -> some View {
        let sampleKey = "tags"
        let textStyle = immersiveMetadataTextStyle(for: sampleKey)
        let inlineTagLimit = horizontalSizeClass == .regular
            ? 沉浸详情布局.常规内联标签上限
            : 沉浸详情布局.紧凑内联标签上限
        let inlineTags = Array(tags.prefix(inlineTagLimit))
        let hasMoreTags = tags.count > inlineTags.count

        return 沉浸标签两行布局(
            spacing: 8,
            forcePlaceMoreButton: hasMoreTags
        ) {
            if targetLanguage.supportsAutomaticMetadataTranslation,
               tags.contains(where: {
                   VNDB标签人工翻译.界面译文(for: $0) == nil
               }) {
                Button {
                    requestTagTranslation(tags)
                } label: {
                    if isTranslatingTags {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "translate")
                            .font(.caption.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    showTranslatedTags
                        ? .blue
                        : textStyle.capsule
                )
                .沉浸详情文字阴影(textStyle)
                .沉浸详情玻璃(
                    immersiveDetailAppearance,
                    sample: textStyle.sample,
                    fallbackTint: immersiveSystemGlassTint,
                    interactive: true,
                    in: Circle()
                )
                .accessibilityLabel(
                    showTranslatedTags
                        ? "显示未人工翻译标签的原文"
                        : "自动翻译没有人工译文的标签"
                )
            }

            ForEach(Array(inlineTags.enumerated()), id: \.element.id) { index, tag in
                immersiveTagCapsule(
                    tag,
                    allTags: tags,
                    sampleKey: "tags.item.\(index)",
                    textStyle: immersiveMetadataTextStyle(
                        for: "tags.item.\(index)"
                    )
                )
            }

            Button {
                showAllTags = true
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
            .沉浸详情文字前景色(textStyle.capsule, style: textStyle)
            .沉浸详情文字阴影(textStyle)
            .contentShape(Capsule())
            .accessibilityLabel("查看更多标签")
        }
        .opacity(tagsContentOpacity)
        .padding(.horizontal, immersivePageHorizontalPadding)
    }

    private func immersiveTagCapsule(
        _ tag: 视觉小说标签,
        allTags: [视觉小说标签],
        sampleKey: String,
        textStyle: 沉浸详情文字样式
    ) -> some View {
        let blurred = shouldBlurTag(tag)
        let categoryStyle = 视觉小说标签类别样式(category: tag.category)

        return HStack(spacing: 6) {
            Image(systemName: categoryStyle.systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(categoryStyle.color)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)

            Text(verbatim: displayedTagName(tag))
                .font(.caption.weight(.semibold))
                .沉浸详情文字前景色(textStyle.capsule, style: textStyle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .沉浸详情文字阴影(textStyle)
            .高透明提亮材质背景(in: Capsule())
            .视觉小说沉浸取样框([sampleKey])
            .blur(radius: blurred ? 5 : 0)
            .contentShape(Capsule())
            .onTapGesture {
                guard blurred,
                      内容安全限制判定.允许手动解除模糊(
                          色情限制: isAdultTagRestricted(tag)
                      ) else {
                    return
                }
                blurRevealConfirmation.request(id: "tags") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        let blurredIDs = allTags
                            .filter {
                                shouldBlurTag($0)
                                    && 内容安全限制判定.允许手动解除模糊(
                                        色情限制: isAdultTagRestricted($0)
                                    )
                            }
                            .map(\.id)
                        revealedTagIDs.formUnion(blurredIDs)
                    }
                }
            }
    }

    @ViewBuilder
    private var detailFailureCard: some View {
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
                immersiveDetailAppearance,
                fallbackTint: immersiveSystemGlassTint,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
        }
    }

    private var immersiveLoadingContent: some View {
        VStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: index == 0 ? 190 : 260)
            }
        }
        .padding(.horizontal, immersivePageHorizontalPadding)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在载入…")
        .opacity(isLoadingDetail ? 1 : 0)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.3),
            value: isLoadingDetail
        )
    }

    @ViewBuilder
    private func immersiveMediaContent(
        _ detail: 视觉小说详细信息
    ) -> some View {
        if let relationships = detail.va, !relationships.isEmpty {
            let mergedRelationships = 视觉小说角色声优分组.合并(relationships)

            immersiveHorizontalSection("角色") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(mergedRelationships) { merged in
                            NavigationLink {
                                角色详情(
                                    auth: auth,
                                    relationships: merged.relationships
                                )
                            } label: {
                                immersiveCharacterCard(merged)
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
            }
        }

        let relations = visibleRelations(in: detail)
        if !relations.isEmpty {
            immersiveHorizontalSection("相关") {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(relations, id: \.id) { relation in
                            NavigationLink {
                                视觉小说详情(
                                    vnID: relation.id,
                                    auth: auth,
                                    initialTitle: relation.title,
                                    initialTitles: relation.titles,
                                    initialImageURL: relation.image?.url,
                                    initialImageSexual: relation.image?.sexual,
                                    initialImageViolence: relation.image?.violence,
                                    initialImageDimensions: relation.image?.dims
                                )
                            } label: {
                                immersiveRelationCard(relation)
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
            }
        }

        if !eventActorNames.isEmpty, shouldShowEventSection {
            PaperVN活动栏目(
                events: eventModel.events,
                isLoading: eventModel.isLoading,
                hasLoaded: eventModel.hasLoaded,
                errorMessage: eventModel.errorMessage,
                cardScene: .detail,
                液态玻璃外观: immersiveDetailAppearance,
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

        if 有评论来源ID {
            externalCommentsSection
        }
    }

    private var 有评论来源ID: Bool {
        let ids = 视觉小说外部ID目录.shared.ids(for: vnID)
        return !ids.bangumiIDs.isEmpty || !ids.steamIDs.isEmpty
    }

    private var hasMoreComments: Bool {
        externalComments.count > 评论卡片布局.预览条数
    }

    private var externalCommentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("评论")
                    .font(.title2.weight(.bold))
                Spacer()
                if isLoadingExternalComments {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if bangumiAccount.isLoggedIn, let profile = bangumiAccount.profile {
                commentComposer(displayName: profile.displayName)
            }

            if let externalCommentsError {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label {
                        Text(verbatim: externalCommentsError)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task {
                            await loadExternalComments(forceRefresh: true)
                        }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(isLoadingExternalComments)
                }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if externalComments.isEmpty {
                if isLoadingExternalComments {
                    ForEach(0..<评论卡片布局.预览条数, id: \.self) { 序号 in
                        评论加载占位卡片(序号: 序号)
                    }
                } else {
                    Text("无评论")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(externalComments.prefix(评论卡片布局.预览条数)) { comment in
                    评论卡片(
                        评论: comment,
                        预先布局完整正文: false
                    )
                }

                if hasMoreComments {
                    moreCommentsPullControl
                }
            }
        }
        .padding(.horizontal, immersivePageHorizontalPadding)
    }

    private var moreCommentsPullControl: some View {
        let remainingCount = max(
            externalComments.count - 评论卡片布局.预览条数,
            0
        )
        let progress = min(
            max(
                moreCommentsPullDistance
                    / 视觉小说评论入口拖动参数.阈值,
                0
            ),
            1
        )
        let isArmed = moreCommentsPullIsArmed

        return VStack(spacing: 10) {
            Label {
                Text(
                    isArmed
                        ? "松手查看所有评论"
                        : "上拉查看剩余\(remainingCount)条评论"
                )
            } icon: {
                Image(
                    systemName: isArmed
                        ? "checkmark.circle.fill"
                        : "chevron.up"
                )
                .symbolEffect(
                    .bounce.up,
                    options: .repeat(.periodic(delay: 1.6)),
                    isActive: !isArmed && progress == 0 && !reduceMotion
                )
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isArmed ? Color.blue : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
            .animation(.snappy(duration: 0.2), value: isArmed)

            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(
                    width: 视觉小说评论入口拖动参数.进度条宽度,
                    height: 6
                )
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.blue)
                        .frame(
                            width: 视觉小说评论入口拖动参数.进度条宽度
                                * progress
                        )
                }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact, trigger: moreCommentsPullFeedback)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("查看剩余\(remainingCount)条评论")
        .accessibilityHint("继续向上轻扫以查看所有评论")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            showAllComments = true
        }
    }

    private func updateMoreCommentsPull(distance: CGFloat) {
        let limitedDistance = min(
            max(distance, 0),
            视觉小说评论入口拖动参数.最大视觉距离
        )
        moreCommentsPullDistance = limitedDistance
        moreCommentsPullIsArmed = distance
            >= 视觉小说评论入口拖动参数.阈值

        if moreCommentsPullIsArmed,
           !moreCommentsPullFeedbackIssued {
            moreCommentsPullFeedbackIssued = true
            moreCommentsPullFeedback += 1
        }
    }

    /// 返回 true 表示要打开全部评论，由调用方在回弹归位后打开。
    private func finishMoreCommentsPull() -> Bool {
        if moreCommentsPullIsArmed {
            if !moreCommentsPullFeedbackIssued {
                moreCommentsPullFeedbackIssued = true
                moreCommentsPullFeedback += 1
            }
            moreCommentsPullIsArmed = true
            moreCommentsPullDistance = 视觉小说评论入口拖动参数.阈值
            return true
        } else {
            withAnimation(
                reduceMotion ? nil : .easeOut(duration: 0.18)
            ) {
                moreCommentsPullDistance = 0
                moreCommentsPullIsArmed = false
            }
            moreCommentsPullFeedbackIssued = false
            return false
        }
    }

    private func commentComposer(displayName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("撰写评论…", text: $commentDraft, axis: .vertical)
                .lineLimit(3...7)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color.secondary.opacity(0.14),
                    in: RoundedRectangle(
                        cornerRadius: 评论卡片布局.内层圆角,
                        style: .continuous
                    )
                )

            HStack(spacing: 10) {
                Text("以“\(displayName)”发布")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    Task { await publishExternalComment() }
                } label: {
                    if isPublishingComment {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("发布", systemImage: "paperplane.fill")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(
                    commentDraft.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty || isPublishingComment
                )
            }
        }
        .padding(评论卡片布局.内边距)
        .background(
            .regularMaterial,
            in: RoundedRectangle(
                cornerRadius: 评论卡片布局.圆角,
                style: .continuous
            )
        )
    }

    private func loadExternalComments(forceRefresh: Bool = false) async {
        guard 有评论来源ID else {
            externalComments = []
            externalCommentsError = nil
            isLoadingExternalComments = false
            return
        }
        isLoadingExternalComments = true
        externalCommentsError = nil
        defer { isLoadingExternalComments = false }
        do {
            let comments = try await 视觉小说外部数据服务.shared.comments(
                vndbID: vnID,
                forceRefresh: forceRefresh
            )
            withAnimation(.easeInOut(duration: 0.28)) {
                externalComments = comments
            }
        } catch is CancellationError {
            return
        } catch {
            externalCommentsError = error.localizedDescription
        }
    }

    private func publishExternalComment() async {
        let text = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard 有评论来源ID, !text.isEmpty, !isPublishingComment else { return }
        isPublishingComment = true
        defer { isPublishingComment = false }
        do {
            try await bangumiAccount.publishComment(
                vndbID: vnID,
                text: text,
                rating: nil
            )
            commentDraft = ""
            await loadExternalComments(forceRefresh: true)
        } catch {
            externalCommentsError = error.localizedDescription
        }
    }

    private func visibleRelations(
        in detail: 视觉小说详细信息
    ) -> [视觉小说相关] {
        guard detail.id == vnID else { return [] }

        return (detail.relations ?? []).filter { relation in
            !relation.id.isEmpty
                && relation.id != vnID
                && !relation.title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
        }
    }

    private func immersiveHorizontalSection<Content: View>(
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
    private func immersiveScreenshotStack(
        _ screenshots: [视觉小说截图]
    ) -> some View {
        if horizontalSizeClass == .regular {
            immersiveScreenshotShelf(screenshots)
        } else {
            immersiveScreenshotDeck(screenshots)
        }
    }

    private func immersiveScreenshotShelf(
        _ screenshots: [视觉小说截图]
    ) -> some View {
        let cardWidth: CGFloat = 360
        let cardHeight = cardWidth * 9 / 16

        return VStack(alignment: .leading, spacing: 10) {
            Text("截屏")
                .font(.title2.weight(.bold))
                .padding(.horizontal, immersivePageHorizontalPadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(screenshots, id: \.id) { screenshot in
                        immersiveScreenshotStackCard(
                            screenshot,
                            width: cardWidth,
                            height: cardHeight,
                            isFront: true
                        )
                        .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
                    }
                }
                .padding(.vertical, 6)
                .scrollTargetLayout()
            }
            .contentMargins(
                .horizontal,
                immersivePageHorizontalPadding,
                for: .scrollContent
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("截屏")
    }

    private func immersiveScreenshotDeck(
        _ screenshots: [视觉小说截图]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("截屏")
                    .font(.title2.weight(.bold))

                Spacer()

                if screenshots.count > 1 {
                    HStack(spacing: 0) {
                        ZStack(alignment: .trailing) {
                            Text(verbatim: "\(screenshots.count)")
                                .hidden()

                            Text(verbatim: "\(screenshotStackFrontIndex + 1)")
                                .contentTransition(
                                    .numericText(
                                        value: Double(
                                            screenshotStackFrontIndex + 1
                                        )
                                    )
                                )
                        }
                        .clipped()

                        Text(verbatim: "/\(screenshots.count)")
                    }
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .animation(
                        reduceMotion ? nil : .snappy(duration: 0.24),
                        value: screenshotStackFrontIndex
                    )
                    .accessibilityElement(children: .combine)
                }
            }

            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let cardHeight = cardWidth * 9 / 16

                let stack = ZStack {
                    ForEach(screenshots.indices, id: \.self) { index in
                        let depth = screenshotStackDepth(
                            of: index,
                            count: screenshots.count
                        )
                        let visibleDepth = min(depth, 4)
                        let promotedDepth = max(
                            0,
                            CGFloat(visibleDepth)
                                - screenshotStackPromotionProgress
                        )

                        immersiveScreenshotStackCard(
                            screenshots[index],
                            width: cardWidth,
                            height: cardHeight,
                            isFront: depth == 0
                        )
                        .scaleEffect(
                            depth == 0
                                ? 1
                                : 1 - promotedDepth * 0.025
                        )
                        .rotationEffect(
                            .degrees(
                                depth == 0
                                    ? Double(screenshotStackDragOffset.width / 60)
                                    : screenshotStackPromotedRotation(
                                        for: visibleDepth
                                    ) * 0.45
                            )
                        )
                        .offset(
                            x: depth == 0
                                ? screenshotStackDragOffset.width
                                : screenshotStackPromotedHorizontalOffset(
                                    for: visibleDepth
                                ) * 0.4,
                            y: depth == 0
                                ? screenshotStackDragOffset.height
                                : promotedDepth * 6
                        )
                        .opacity(
                            depth <= 3
                                ? 1
                                : depth == 4
                                    ? screenshotStackPromotionProgress
                                    : 0
                        )
                        .shadow(
                            color: .black.opacity(depth == 0 ? 0.1 : 0.05),
                            radius: depth == 0 ? 10 : 5,
                            y: depth == 0 ? 5 : 2
                        )
                        .zIndex(Double(screenshots.count - depth))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

                stack.modifier(
                    截屏水平拖动修饰器(
                        onChanged: { translation in
                            updateScreenshotStackHorizontalDrag(
                                translation: translation,
                                screenshotCount: screenshots.count,
                                containerWidth: geometry.size.width
                            )
                        },
                        onEnded: { _, projectedTranslation in
                            endScreenshotStackHorizontalDrag(
                                projectedWidth: projectedTranslation.width,
                                screenshotCount: screenshots.count,
                                containerWidth: geometry.size.width
                            )
                        },
                        onCancelled: cancelScreenshotStackHorizontalDrag
                    )
                )
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
        }
        .padding(.horizontal, immersivePageHorizontalPadding)
        .onChange(of: screenshots.map(\.id)) { _, _ in
            screenshotStackFrontIndex = 0
            screenshotStackDragOffset = .zero
            screenshotStackPromotionProgress = 0
            screenshotStackIsCompletingSwipe = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("截屏")
        .accessibilityValue(
            Text(
                verbatim: "\(screenshotStackFrontIndex + 1)/\(screenshots.count)"
            )
        )
    }

    private func immersiveScreenshotStackCard(
        _ screenshot: 视觉小说截图,
        width: CGFloat,
        height: CGFloat,
        isFront: Bool
    ) -> some View {
        let needsRestriction = shouldBlurImage(
            sexual: screenshot.sexual,
            violence: screenshot.violence
        )
        let isRevealed = revealScreenshotIDs.contains(screenshot.id)
        let isRestricted = needsRestriction && (
            contentRestrictionMethod == .hidden || !isRevealed
        )

        return ZStack {
            CachedAsyncImage(
                url: URL(
                    string: screenshot.url
                        ?? screenshot.thumbnail
                        ?? ""
                ),
                contentMode: .fill
            )
            .frame(width: width, height: height)
            .clipped()
            .应用不安全内容限制(
                isRestricted,
                method: contentRestrictionMethod,
                blurRadius: 24
            )
            .animation(
                .easeInOut(duration: 0.28),
                value: isRestricted
            )

            if isFront {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isRestricted,
                           contentRestrictionMethod == .blurred,
                           canRevealImage(sexual: screenshot.sexual) {
                            blurRevealConfirmation.request(
                                id: "screenshot-\(screenshot.id)"
                            ) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    let _ = revealScreenshotIDs.insert(
                                        screenshot.id
                                    )
                                }
                            }
                        }
                    }
            }
        }
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.1))
        .clipShape(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .contentShape(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }

    private func screenshotStackDepth(
        of index: Int,
        count: Int
    ) -> Int {
        guard count > 0 else { return 0 }
        return (index - screenshotStackFrontIndex + count) % count
    }

    private func screenshotStackRestingRotation(for depth: Int) -> Double {
        switch depth {
        case 0: return 0
        case 1: return -2.4
        case 2: return 2.1
        case 3: return -3.1
        case 4: return 2.8
        default: return -2.5
        }
    }

    private func screenshotStackPromotedRotation(
        for depth: Int
    ) -> Double {
        let current = screenshotStackRestingRotation(for: depth)
        let promoted = screenshotStackRestingRotation(
            for: max(0, depth - 1)
        )
        return current
            + (promoted - current)
                * Double(screenshotStackPromotionProgress)
    }

    private func screenshotStackRestingHorizontalOffset(
        for depth: Int
    ) -> CGFloat {
        switch depth {
        case 0: return 0
        case 1: return -8
        case 2: return 9
        case 3: return -11
        case 4: return 12
        default: return -10
        }
    }

    private func screenshotStackPromotedHorizontalOffset(
        for depth: Int
    ) -> CGFloat {
        let current = screenshotStackRestingHorizontalOffset(for: depth)
        let promoted = screenshotStackRestingHorizontalOffset(
            for: max(0, depth - 1)
        )
        return current
            + (promoted - current)
                * screenshotStackPromotionProgress
    }

    private func updateScreenshotStackHorizontalDrag(
        translation: CGSize,
        screenshotCount: Int,
        containerWidth: CGFloat
    ) {
        guard screenshotCount > 1,
              !screenshotStackIsCompletingSwipe else {
            return
        }

        screenshotStackDragOffset = CGSize(
            width: translation.width,
            height: translation.height * 0.18
        )
        screenshotStackPromotionProgress = min(
            1,
            abs(translation.width) / max(1, containerWidth * 0.32)
        )
    }

    private func endScreenshotStackHorizontalDrag(
        projectedWidth: CGFloat,
        screenshotCount: Int,
        containerWidth: CGFloat
    ) {
        guard screenshotCount > 1,
              !screenshotStackIsCompletingSwipe else {
            return
        }

        guard abs(projectedWidth) > 70 else {
            withAnimation(.spring(duration: 0.3, bounce: 0.25)) {
                screenshotStackDragOffset = .zero
                screenshotStackPromotionProgress = 0
            }
            return
        }

        completeScreenshotStackSwipe(
            direction: projectedWidth >= 0 ? 1 : -1,
            screenshotCount: screenshotCount,
            containerWidth: containerWidth
        )
    }

    private func cancelScreenshotStackHorizontalDrag() {
        withAnimation(.spring(duration: 0.3, bounce: 0.25)) {
            screenshotStackDragOffset = .zero
            screenshotStackPromotionProgress = 0
        }
    }

    private func completeScreenshotStackSwipe(
        direction: CGFloat,
        screenshotCount: Int,
        containerWidth: CGFloat
    ) {
        guard screenshotCount > 1,
              !screenshotStackIsCompletingSwipe else {
            return
        }

        if reduceMotion {
            screenshotStackFrontIndex =
                (screenshotStackFrontIndex + 1) % screenshotCount
            screenshotStackDragOffset = .zero
            screenshotStackPromotionProgress = 0
            return
        }

        screenshotStackIsCompletingSwipe = true
        withAnimation(.easeOut(duration: 0.28)) {
            screenshotStackDragOffset = CGSize(
                width: direction * (containerWidth + 180),
                height: screenshotStackDragOffset.height
            )
            screenshotStackPromotionProgress = 1
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(290))
            withTransaction(Transaction(animation: nil)) {
                screenshotStackFrontIndex =
                    (screenshotStackFrontIndex + 1) % screenshotCount
                screenshotStackDragOffset = .zero
                screenshotStackPromotionProgress = 0
                screenshotStackIsCompletingSwipe = false
            }
        }
    }

    private func immersiveCharacterCard(
        _ merged: 视觉小说角色声优分组
    ) -> some View {
        let relationship = merged.primary
        let characterName = 人物名称工具.显示名称(
            name: relationship.character.name,
            original: relationship.character.original,
            偏好: staffNameLang
        )
        var seenStaff: Set<String> = []
        let staffNames = merged.relationships.compactMap { voice -> String? in
            guard seenStaff.insert(voice.staff.id).inserted else {
                return nil
            }
            return 人物名称工具.显示名称(
                name: voice.staff.name,
                original: voice.staff.original,
                偏好: staffNameLang
            )
        }
        let cardWidth = 沉浸详情布局.媒体卡片宽度
        let cardHeight = 沉浸详情布局.媒体卡片高度

        return ZStack(alignment: .bottomLeading) {
            restrictedCardImage(
                id: "detail-character-\(relationship.character.id)",
                url: relationship.character.image?.url,
                sexual: relationship.character.image?.sexual,
                violence: relationship.character.image?.violence,
                width: cardWidth,
                height: cardHeight,
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
                        文本: characterName,
                        isJapanese: staffNameLang == .original,
                        基础大小: 14,
                        是粗体: true,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(1)

                if !staffNames.isEmpty {
                    Text(voiceActorNamesText(staffNames))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                }
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
        .contentShape(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private func immersiveRelationCard(
        _ relation: 视觉小说相关
    ) -> some View {
        let titleResult = 标题工具.获取主标题(
            titles: relation.titles,
            defaultTitle: relation.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
        let cardWidth = 沉浸详情布局.媒体卡片宽度
        let cardHeight = 沉浸详情布局.媒体卡片高度

        return ZStack(alignment: .bottomLeading) {
            restrictedCardImage(
                id: "detail-relation-\(relation.id)",
                url: relation.image?.url ?? relation.image?.thumbnail,
                sexual: relation.image?.sexual,
                violence: relation.image?.violence,
                width: cardWidth,
                height: cardHeight,
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
                        文本: titleResult.text,
                        isJapanese: titleResult.isJapanese,
                        基础大小: 14,
                        是粗体: true,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言代码: titleResult.languageCode
                    )
                )
                .foregroundStyle(.white)
                .lineLimit(1)

                Text(verbatim: relation.relationTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 9)
        .contentShape(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private func immersiveDescriptionContent(
        _ detail: 视觉小说详细信息,
        outerHorizontalPadding: CGFloat,
        fillsAvailableHeight: Bool = false,
        showsContent: Bool = true
    ) -> some View {
        let original = detail.cleanDescription
        let hasDescription = original?.isEmpty == false
        let textStyle = immersiveMetadataTextStyle(for: "description.text")
        let isHidden =
            blurDescription &&
            !hasFinishedOrDropped &&
            !revealDescription

        return Group {
            if let original, !original.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Group {
                        if isHidden {
                            immersiveDescriptionText(
                                original,
                                style: textStyle
                            )
                                .textSelection(.disabled)
                                .blur(radius: 7)
                        } else {
                            immersiveDescriptionText(
                                original,
                                style: textStyle
                            )
                                .textSelection(.enabled)
                        }
                    }
                    .lineLimit(5)
                    .fontWeight(.regular)
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
                                    ? "显示视觉小说简介原文"
                                    : "翻译视觉小说简介"
                            )
                        }

                        descriptionParticipationButton(
                            style: .icon(tint: textStyle.secondary)
                        )
                    }
                }
                .沉浸详情文字阴影(textStyle)
                .opacity(showsContent ? 1 : 0)
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
        .frame(
            maxHeight: fillsAvailableHeight ? .infinity : nil,
            alignment: .topLeading
        )
        .沉浸详情玻璃背景(
            immersiveDetailAppearance,
            sample: textStyle.sample,
            fallbackTint: immersiveSystemGlassTint,
            usesBrightReducedMaterial: true,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .matchedTransitionSource(
            id: "DescriptionSheet",
            in: descriptionNamespace
        )
        .onTapGesture {
            guard hasDescription, showsContent else { return }
            if isHidden {
                blurRevealConfirmation.request(id: "description") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        revealDescription = true
                    }
                }
            } else if isDescriptionTruncated {
                showDescriptionSheet = true
            }
        }
        .allowsHitTesting(hasDescription && showsContent)
        .accessibilityHidden(!hasDescription || !showsContent)
        .视觉小说沉浸取样框(["description", "description.text"])
        .padding(.horizontal, outerHorizontalPadding)
    }

    private func detailInfoSheetContent(
        _ detail: 视觉小说详细信息
    ) -> some View {
        NavigationStack {
            平台滚动页面 {
                supportSection(detail)
                releaseInfoSection
                developersSection(detail)
                staffSection(detail)
                externalLinksSection(detail)
            }
            .平台分组列表样式()
            .navigationTitle("更多信息")
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .平台主操作) {
                    Button {
                        showInfoSheet = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .平台近全屏弹窗()
    }

    @ViewBuilder
    private var releaseInfoSection: some View {
        Section {
            NavigationLink {
                releaseVersionsPage
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                        .frame(width: 22)

                    Text("发行版本")
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Text(verbatim: releases.count.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var releaseVersionsPage: some View {
        GeometryReader { proxy in
            平台滚动页面 {
                if releases.isEmpty {
                    平台内容不可用视图(
                        "无发行版本",
                        systemImage: "shippingbox"
                    )
                    .frame(
                        maxWidth: .infinity,
                        minHeight: max(proxy.size.height, 320)
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(releases) { release in
                            NavigationLink {
                                探索发行版本详情(
                                    item: explorationRelease(from: release),
                                    auth: auth,
                                    openedFromVisualNovelDetail: true
                                )
                            } label: {
                                let titleResult = releaseTitleResult(for: release)
                                VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                                    多语言列表文本(
                                        titleResult,
                                        层级: .主标题,
                                        系统字体粗细: titleResult.languageCode
                                            == 标题语言.chinese.langCode ? .medium : nil
                                    )

                                    if !release.displaySubtitle.isEmpty {
                                        Text(verbatim: release.displaySubtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                releaseLibraryActionButton(for: release)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                if userListItem != nil {
                                    Button(role: .destructive) {
                                        showLibraryDeleteConfirmation = true
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    .disabled(isAddingToLibrary)
                                }
                            }
                            .contextMenu {
                                releaseContextMenu(for: release)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .平台分组列表样式()
        .navigationTitle("发行版本")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
    }

    private func releaseTitleResult(
        for release: 视觉小说发行版本
    ) -> 标题工具.标题结果 {
        let titles = release.languages?.compactMap { language -> 用户多语言标题? in
            guard let title = language.title,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return 用户多语言标题(
                lang: language.lang,
                title: title,
                latin: language.latin,
                official: language.mtl != true,
                main: language.main == true
            )
        }

        return 标题工具.获取主标题(
            titles: titles,
            defaultTitle: release.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    @ViewBuilder
    private func releaseContextMenu(
        for release: 视觉小说发行版本
    ) -> some View {
        let title = releaseTitleResult(for: release)
        Button {
            UIPasteboard.general.string = title.text
        } label: {
            Label("拷贝标题", systemImage: "doc.on.doc")
        }

        if !release.displaySubtitle.isEmpty {
            Button {
                UIPasteboard.general.string = release.displaySubtitle
            } label: {
                Label("拷贝副标题", systemImage: "doc.on.doc")
            }
        }

        releaseLibraryActionButton(for: release)

        if !parentalControls.policy.blocksUntrustedExternalLinks,
           let url = URL(string: "https://vndb.org/\(release.id)") {
            ShareLink(item: url) {
                Label("共享", systemImage: "square.and.arrow.up")
            }
        }

        if userListItem != nil {
            Divider()
            Button(role: .destructive) {
                showLibraryDeleteConfirmation = true
            } label: {
                Label("从资料库删除", systemImage: "trash")
            }
        }
    }

    private func releaseLibraryActionButton(
        for release: 视觉小说发行版本
    ) -> some View {
        Button {
            performReleaseLibraryAction(for: release)
        } label: {
            Label(
                userListItem == nil
                    ? String(localized: "添加到资料库")
                    : String(localized: "编辑"),
                systemImage: userListItem == nil
                    ? "plus"
                    : "square.and.pencil"
            )
        }
        .tint(.blue)
        .disabled(isAddingToLibrary)
    }

    private func performReleaseLibraryAction(
        for release: 视觉小说发行版本
    ) {
        guard hasLoadedUserListItem else {
            if auth.token.isEmpty || auth.userID.isEmpty {
                showLoginRequiredAlert = true
            }
            return
        }

        if userListItem == nil {
            addToPlanning(selectedReleaseID: release.id)
        } else {
            pendingReleaseID = userListItem?.releases?.first?.id == nil
                ? release.id
                : nil
            showEditSheet = true
        }
    }

    private var isShowingInitialSkeleton: Bool {
        detail == nil && isLoadingDetail && errorMessage == nil
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

        if let cachedDetail = VNDB服务.shared.loadCachedVNDetail(vnID: vnID) {
            presentLoadedDetail(cachedDetail)
            presentPreloadedImmersiveHeroImageIfNeeded()
        }
        if let cachedReleases = VNDB服务.shared.loadCachedVNReleases(
            vnID: vnID
        ) {
            releases = cachedReleases
        }
        do {
            async let detailRequest = VNDB服务.shared.fetchVNDetail(
                vnID: vnID,
                forceRefresh: forceRefresh
            )
            async let releaseRequest = VNDB服务.shared.fetchVNReleases(
                vnID: vnID,
                forceRefresh: forceRefresh
            )
            let fetchedDetail = try await detailRequest
            guard requestedGeneration == detailLoadGeneration,
                  !Task.isCancelled else {
                return
            }
            presentLoadedDetail(fetchedDetail)
            presentPreloadedImmersiveHeroImageIfNeeded()
            if let fetchedReleases = try? await releaseRequest,
               requestedGeneration == detailLoadGeneration,
               !Task.isCancelled {
                if releases != fetchedReleases {
                    withAnimation(.smooth(duration: 0.38)) {
                        releases = fetchedReleases
                    }
                }
            }
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

    private func presentLoadedDetail(_ loadedDetail: 视觉小说详细信息) {
        guard detail != loadedDetail else { return }

        guard detail != nil, !reduceMotion else {
            detail = loadedDetail
            return
        }

        withAnimation(.smooth(duration: 0.38)) {
            detail = loadedDetail
        }
    }

    private func loadUserListItem(forceRefresh: Bool = false) async {
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
            userListItem = nil
            hasLoadedUserListItem = false
            return
        }

        if let cached = VNDB服务.shared.loadCachedUserListItem(
            userID: auth.userID,
            vnID: vnID
        ) {
            userListItem = cached
            hasLoadedUserListItem = true
        } else if !hasLoadedUserListItem {
            userListItem = nil
        }

        do {
            userListItem = try await VNDB服务.shared.fetchUserListItem(
                token: auth.token,
                userID: auth.userID,
                vnID: vnID,
                forceRefresh: forceRefresh
            )
            hasLoadedUserListItem = true
        } catch is CancellationError {
            return
        } catch {
            if userListItem == nil {
                hasLoadedUserListItem = false
            }
        }
    }

    private func addToPlanning(selectedReleaseID: String? = nil) {
        guard !isAddingToLibrary else { return }
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
            showLoginRequiredAlert = true
            return
        }

        isAddingToLibrary = true
        libraryActionError = nil
        Task { @MainActor in
            do {
                try await VNDB服务.shared.updateUserStatus(
                    token: auth.token,
                    vnID: vnID,
                    status: .planning,
                    existingLabels: []
                )
                if let selectedReleaseID {
                    try await VNDB服务.shared.updateReleaseSelection(
                        token: auth.token,
                        existingReleaseIDs: [],
                        selectedReleaseID: selectedReleaseID
                    )
                }
                资料库加入时间记录.record(userID: auth.userID, vnID: vnID)
                if UserDefaults.standard.bool(
                    forKey: Bangumi账户.同步设置键
                ), bangumiAccount.isLoggedIn {
                    try await bangumiAccount.synchronize(
                        vndbID: vnID,
                        status: .planning,
                        rating: nil
                    )
                }
                await loadUserListItem(forceRefresh: true)
            } catch {
                libraryActionError = error.localizedDescription
            }
            isAddingToLibrary = false
        }
    }

    private func deleteFromLibrary() {
        guard !isAddingToLibrary else { return }
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
            showLoginRequiredAlert = true
            return
        }

        isAddingToLibrary = true
        libraryActionError = nil
        Task { @MainActor in
            defer { isAddingToLibrary = false }
            do {
                try await VNDB服务.shared.deleteUserListEntry(
                    token: auth.token,
                    vnID: vnID
                )
                userListItem = nil
                hasLoadedUserListItem = true
            } catch is CancellationError {
                return
            } catch {
                libraryActionError = error.localizedDescription
            }
        }
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
            for: vnID,
            type: .visualNovel,
            language: targetLanguage,
            mode: VNDB简介翻译模式.current
        )
    }

    private func manualDescriptionLookupKeyValue(
        mode: VNDB简介翻译模式
    ) -> String {
        "\(vnID)|\(targetLanguage.rawValue)|\(mode.rawValue)"
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

    private func requestTagTranslation(_ tags: [视觉小说标签]) {
        guard !isSwitchingTagLanguage else { return }
        let targetValue = !showTranslatedTags
        isSwitchingTagLanguage = true

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.14)) {
                tagsContentOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.14))
            showTranslatedTags = targetValue
            if targetValue {
                prepareTagTranslation(tags)
            }
            withAnimation(.easeIn(duration: 0.18)) {
                tagsContentOpacity = 1
            }
            isSwitchingTagLanguage = false
        }
    }

    private func prepareTagTranslation(_ tags: [视觉小说标签]) {
        let missing = tags.filter {
            VNDB标签人工翻译.界面译文(for: $0) == nil
                && translatedTagNames[$0.id] == nil
        }

        guard !missing.isEmpty else { return }

        if var configuration = tagTranslationConfiguration {
            configuration.source = Locale.Language(identifier: "en")
            configuration.target = targetLanguage.localeLanguage
            configuration.invalidate()
            tagTranslationConfiguration = configuration
        } else {
            tagTranslationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
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

    private func translateMissingTags(using session: TranslationSession) async {
        guard let tags = detail?.sortedTags else { return }

        let missing = tags.filter {
            VNDB标签人工翻译.界面译文(for: $0) == nil
                && translatedTagNames[$0.id] == nil
        }

        guard !missing.isEmpty else { return }

        await MainActor.run {
            isTranslatingTags = true
            translationError = nil
        }

        let requestInputs = missing.map { ($0.name, $0.id) }
        let requests = await Task.detached {
            requestInputs.map { sourceText, clientIdentifier in
                TranslationSession.Request(
                    sourceText: sourceText,
                    clientIdentifier: clientIdentifier
                )
            }
        }.value

        do {
            let responses = try await session.translations(from: requests)
            let translated = responses.reduce(into: [String: String]()) { result, response in
                if let id = response.clientIdentifier {
                    result[id] = response.targetText
                }
            }

            await applyTranslatedTagNames(translated)
        } catch is CancellationError {
            await MainActor.run {
                isTranslatingTags = false
                showTranslatedTags = false
            }
        } catch {
            await MainActor.run {
                isTranslatingTags = false
                showTranslatedTags = false
                translationError = (error as? CocoaError)?.code == .userCancelled
                    ? nil
                    : error.localizedDescription
            }
        }
    }

    @MainActor
    private func applyTranslatedTagNames(
        _ translated: [String: String]
    ) async {
        if showTranslatedTags {
            withAnimation(.easeOut(duration: 0.14)) {
                tagsContentOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.14))
        }

        translatedTagNames.merge(translated) { _, new in new }
        isTranslatingTags = false

        if showTranslatedTags {
            withAnimation(.easeIn(duration: 0.18)) {
                tagsContentOpacity = 1
            }
        }
    }

    private func shouldBlurImage(sexual: Double?, violence: Double?) -> Bool {
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

    private var spoilerSetting: 剧透标签模糊设置 {
        剧透标签模糊设置(rawValue: spoilerTagBlurLevel) ?? .majorOnly
    }

    private func shouldBlurTag(_ tag: 视觉小说标签) -> Bool {
        guard !shouldHideTag(tag),
              !revealedTagIDs.contains(tag.id) else {
            return false
        }

        let spoilerHidden =
            !hasFinishedOrDropped &&
            spoilerSetting.shouldBlur(spoilerLevel: tag.spoiler)
        let adultBlurred = isAdultTagRestricted(tag)
            && contentRestrictionMethod == .blurred

        return spoilerHidden || adultBlurred
    }

    private func shouldHideTag(_ tag: 视觉小说标签) -> Bool {
        isAdultTagRestricted(tag) && contentRestrictionMethod == .hidden
    }

    private func isAdultTagRestricted(_ tag: 视觉小说标签) -> Bool {
        内容安全限制判定.色情标签需要限制(
            tag.isAdultContent,
            enabled: contentFilterEnabled,
            mode: filterMode
        )
    }

    @ViewBuilder
    private func titleCopyContextMenu(
        for detail: 视觉小说详细信息
    ) -> some View {
        ForEach(titleCopyItems(for: detail)) { item in
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

    private func titleCopyItems(
        for detail: 视觉小说详细信息
    ) -> [视觉小说标题拷贝项目] {
        let languages: [标题语言] = [
            .japanese,
            .chinese,
            .traditionalChinese,
            .korean,
            .english,
            .romanized
        ]
        let acceptedTitles = (detail.titles ?? []).filter {
            allowUnofficialTitles || $0.official
        }
        var items: [视觉小说标题拷贝项目] = []

        if let originalItem = originalTitleCopyItem(
            detail: detail,
            acceptedTitles: acceptedTitles
        ) {
            items.append(originalItem)
        }

        for language in languages {
            guard let value = copyTitleValue(
                for: language,
                detail: detail,
                acceptedTitles: acceptedTitles
            ) else {
                continue
            }
            appendTitleCopyItem(
                to: &items,
                id: language.rawValue,
                label: String(localized: "拷贝\(language.localizedTitle)标题"),
                value: value
            )
        }

        if items.isEmpty {
            items.append(
                视觉小说标题拷贝项目(
                    id: "fallback",
                    label: String(localized: "拷贝标题"),
                    value: detail.title
                )
            )
        }
        return items
    }

    private func originalTitleCopyItem(
        detail: 视觉小说详细信息,
        acceptedTitles: [用户多语言标题]
    ) -> 视觉小说标题拷贝项目? {
        let explicitCode = detail.olang?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let mainTitle = acceptedTitles.first(where: { $0.main })
            ?? acceptedTitles.first
        let originalCode = explicitCode.flatMap { $0.isEmpty ? nil : $0 }
            ?? mainTitle?.lang
        guard let originalCode, !originalCode.isEmpty,
              !isSupportedCopyLanguage(originalCode) else {
            return nil
        }

        let title = acceptedTitles.first(where: {
            normalizedCopyLanguageCode($0.lang)
                == normalizedCopyLanguageCode(originalCode)
                && $0.main
        })?.title
            ?? acceptedTitles.first(where: {
                normalizedCopyLanguageCode($0.lang)
                    == normalizedCopyLanguageCode(originalCode)
            })?.title
            ?? mainTitle?.title
            ?? detail.title
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        let languageName = VNDB显示工具.语言名称(
            originalCode,
            fallbackName: String(localized: "原语言")
        )
        return 视觉小说标题拷贝项目(
            id: "original-\(normalizedCopyLanguageCode(originalCode))",
            label: String(localized: "拷贝\(languageName)标题"),
            value: title
        )
    }

    private func copyTitleValue(
        for language: 标题语言,
        detail: 视觉小说详细信息,
        acceptedTitles: [用户多语言标题]
    ) -> String? {
        if language == .romanized {
            let title = acceptedTitles.first(where: {
                $0.main && !($0.latin ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            }) ?? acceptedTitles.first(where: {
                !($0.latin ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            })
            return title?.latin?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }

        guard let languageCode = language.langCode else { return nil }
        if let title = acceptedTitles.first(where: {
            normalizedCopyLanguageCode($0.lang)
                == normalizedCopyLanguageCode(languageCode)
        })?.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }

        guard let originalCode = detail.olang,
              normalizedCopyLanguageCode(originalCode)
                == normalizedCopyLanguageCode(languageCode),
              !detail.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty else {
            return nil
        }
        return detail.title
    }

    private func appendTitleCopyItem(
        to items: inout [视觉小说标题拷贝项目],
        id: String,
        label: String,
        value: String
    ) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !items.contains(where: { $0.id == id }) else {
            return
        }
        items.append(
            视觉小说标题拷贝项目(id: id, label: label, value: value)
        )
    }

    private func isSupportedCopyLanguage(_ code: String) -> Bool {
        let normalized = normalizedCopyLanguageCode(code)
        return ["ja", "zh-hans", "zh-hant", "ko", "en"].contains(normalized)
    }

    private func normalizedCopyLanguageCode(_ code: String) -> String {
        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
        switch normalized {
        case "zh", "zh-cn", "zh-sg", "zh-hans":
            return "zh-hans"
        case "zh-tw", "zh-hk", "zh-mo", "zh-hant":
            return "zh-hant"
        case let value where value.hasPrefix("ja-"):
            return "ja"
        case let value where value.hasPrefix("ko-"):
            return "ko"
        case let value where value.hasPrefix("en-"):
            return "en"
        default:
            return normalized
        }
    }

    private func displayedTagName(_ tag: 视觉小说标签) -> String {
        if let manual = VNDB标签人工翻译.界面译文(for: tag) {
            return manual
        }

        guard showTranslatedTags else { return tag.name }
        return translatedTagNames[tag.id] ?? tag.name
    }

    private func descriptionText(
        _ original: String,
        foregroundColor: Color = .primary
    ) -> some View {
        简介预览文本视图(
            text: displayedDescription(original),
            lineLimit: 7,
            onTruncationChange: { isDescriptionTruncated = $0 }
        )
            .font(.body)
            .foregroundStyle(foregroundColor)
            .contentTransition(.opacity)
    }

    private func immersiveDescriptionText(
        _ original: String,
        style: 沉浸详情文字样式
    ) -> some View {
        descriptionText(original, foregroundColor: style.primary)
            .沉浸详情文字前景色(style.primary, style: style)
    }

    private func descriptionSheetContent(_ detail: 视觉小说详细信息) -> some View {
        NavigationStack {
            ScrollView {
                Text(
                    verbatim: 简介预览文本处理.外部显示文本(
                        displayedDescription(detail.cleanDescription ?? "")
                    )
                )
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("视觉小说简介")
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .平台前导操作) {
                    Button {
                        showDescriptionSheet = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }

                ToolbarItem(placement: .平台主操作) {
                    descriptionParticipationButton(style: .toolbar)
                }
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
        let originalTitle = 简介翻译条目名称.原语言标题(
            titles: detail.titles,
            defaultTitle: detail.title
        )
        return VNDB简介翻译条目(
            id: vnID,
            type: .visualNovel,
            name: originalTitle,
            romanizedName: detail.title,
            titles: detail.titles?.map(VNDB简介翻译标题.init),
            displayName: navigationTitleResult.text,
            originalName: originalTitle == detail.title ? nil : originalTitle,
            source: source,
            displaySource: displaySource,
            displayIsJapanese: navigationTitleResult.isJapanese,
            displayLanguageCode: navigationTitleResult.languageCode
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

    private func voiceActorNamesText(_ names: [String]) -> AttributedString {
        var result = AttributedString()

        for (index, name) in names.enumerated() {
            if index > 0 {
                var separator = AttributedString(" / ")
                separator.font = .system(.caption, weight: .medium)
                result += separator
            }

            result += 标题工具.生成富文本(
                文本: name,
                isJapanese: staffNameLang == .original,
                基础大小: 12,
                日文字体名称: "HiraginoSans-W4",
                系统字体粗细: .medium,
                语言来源已知: false,
                空格视为日语: true
            )
        }

        return result
    }

    @ViewBuilder
    private func supportSection(_ detail: 视觉小说详细信息) -> some View {
        let platforms = detail.platforms ?? []
        let languages = detail.languages ?? []

        if !platforms.isEmpty || !languages.isEmpty {
            Section {
                if !platforms.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        supportHeading(
                            "平台",
                            systemImage: "desktopcomputer.and.macbook"
                        )

                        FlowLayout(spacing: 7) {
                            ForEach(platforms, id: \.self) { platform in
                                supportBadge(
                                    VNDB显示工具.平台名称(platform),
                                    systemImage:
                                        VNDB显示工具.平台图标(platform)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !languages.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        supportHeading(
                            "语言",
                            systemImage: "globe"
                        )

                        FlowLayout(spacing: 7) {
                            ForEach(languages, id: \.self) { language in
                                supportBadge(
                                    VNDB显示工具.语言名称(language)
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func supportBadge(
        _ text: String,
        systemImage: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .frame(width: 16, height: 16)
            }
            Text(verbatim: text)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func supportHeading(
        _ title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private func developersSection(_ detail: 视觉小说详细信息) -> some View {
        if let developers = detail.developers, !developers.isEmpty {
            Section("开发商") {
                ForEach(developers, id: \.id) { developer in
                    HStack(spacing: 12) {
                        Image(systemName: "building.2")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        多语言列表文本(
                            文本: 人物名称工具.显示名称(
                                name: developer.name,
                                original: developer.original,
                                偏好: staffNameLang
                            ),
                            isJapanese: staffNameLang == .original,
                            层级: .主标题,
                            日文字体名称: "HiraginoSans-W4",
                            系统字体粗细: .regular,
                            语言来源已知: false,
                            空格视为日语: true
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func staffSection(_ detail: 视觉小说详细信息) -> some View {
        if let staff = detail.staff, !staff.isEmpty {
            let grouped = Dictionary(grouping: staff, by: \.roleGroupKey)
            let roles = grouped.keys.sorted {
                (grouped[$0]?.first?.roleSortOrder ?? 99)
                    < (grouped[$1]?.first?.roleSortOrder ?? 99)
            }

            Section("制作人员") {
                ForEach(roles, id: \.self) { role in
                    if let members = grouped[role], let first = members.first {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedStaffRoles.contains(role) },
                                set: { isExpanded in
                                    withAnimation(.easeInOut(duration: 0.24)) {
                                        if isExpanded {
                                            expandedStaffRoles.insert(role)
                                        } else {
                                            expandedStaffRoles.remove(role)
                                        }
                                    }
                                }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(
                                    Array(members.enumerated()),
                                    id: \.offset
                                ) { _, member in
                                    VStack(alignment: .leading, spacing: 4) {
                                        多语言列表文本(
                                            文本: 人物名称工具.显示名称(
                                                name: member.name,
                                                original: member.original,
                                                偏好: staffNameLang
                                            ),
                                            isJapanese: staffNameLang == .original,
                                            层级: .主标题,
                                            日文字体名称: "HiraginoSans-W4",
                                            系统字体粗细: .regular,
                                            语言来源已知: false,
                                            空格视为日语: true
                                        )

                                        if let note = member.note,
                                           !note.isEmpty {
                                            Text(verbatim: note)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                                }
                            }
                            .padding(.top, 8)
                            .padding(.leading, 32)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: staffIcon(for: first.role))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)

                                Text(verbatim: first.roleTitle)
                                    .foregroundStyle(.primary)

                                Spacer(minLength: 8)

                                Text("\(members.count)人")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accentColor(Color.secondary)
                        .animation(
                            .easeInOut(duration: 0.24),
                            value: expandedStaffRoles.contains(role)
                        )
                    }
                }
            }
        }
    }

    private func staffIcon(for role: String) -> String {
        switch role {
        case "scenario": return "text.book.closed"
        case "chardesign": return "paintbrush"
        case "art": return "pencil.and.outline"
        case "music": return "music.quarternote.3"
        case "songs": return "music.microphone"
        case "director": return "megaphone"
        case "staff": return "wrench.and.screwdriver"
        default: return "person.2"
        }
    }

    private func explorationRelease(
        from release: 视觉小说发行版本
    ) -> 探索发行版本 {
        let visualNovel = 探索发行作品(
            id: displayedDetail.id,
            title: displayedDetail.title,
            titles: displayedDetail.titles?.map {
                探索多语言标题(
                    lang: $0.lang,
                    title: $0.title,
                    latin: $0.latin,
                    official: $0.official,
                    main: $0.main
                )
            },
            image: displayedDetail.image.map {
                探索图片(
                    id: $0.id,
                    url: $0.url,
                    thumbnail: $0.thumbnail,
                    dims: $0.dims,
                    sexual: $0.sexual,
                    violence: $0.violence
                )
            },
            releaseType: release.releaseType
        )

        return 探索发行版本(
            id: release.id,
            title: release.title,
            alttitle: release.alttitle,
            releaseType: release.releaseType,
            languages: release.languages?.map {
                探索发行语言(
                    lang: $0.lang,
                    title: $0.title,
                    latin: $0.latin,
                    mtl: $0.mtl,
                    main: $0.main
                )
            },
            platforms: release.platforms,
            media: nil,
            visualNovels: [visualNovel],
            producers: nil,
            images: nil,
            released: release.released,
            minimumAge: nil,
            patch: nil,
            freeware: nil,
            uncensored: nil,
            official: release.official,
            hasAdultContent: nil,
            resolution: nil,
            engine: nil,
            voiced: nil,
            notes: nil,
            gtin: nil,
            catalog: nil,
            externalLinks: nil
        )
    }

    @ViewBuilder
    private func externalLinksSection(_ detail: 视觉小说详细信息) -> some View {
        if let links = detail.extlinks, !links.isEmpty {
            Section("外部链接") {
                ForEach(links, id: \.url) { link in
                    if let url = externalURL(from: link.url) {
                        Button {
                            externalBrowserTarget = 外部浏览目标(url: url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "safari")
                                    .foregroundStyle(.blue)
                                    .frame(width: 22)

                                Text(verbatim: link.displayName)
                                    .foregroundStyle(.blue)

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

    private func externalURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let url: URL?
        if let components = URLComponents(string: trimmed),
           components.scheme != nil {
            url = components.url
        } else {
            url = URLComponents(string: "https://\(trimmed)")?.url
        }

        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
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
