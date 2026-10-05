import SwiftUI
import Combine
import CoreText
import ImageIO
import UIKit

enum 沉浸封面拖动参数 {
    static let 展开阈值: CGFloat = 180
    static let 收起阈值: CGFloat = 180
    static let 回弹交接余量: CGFloat = 12
    static let 滚动交接余量: CGFloat = 12
    static let 投影时长: CGFloat = 0.25
}

struct 沉浸封面拖动上下文 {
    let progress: CGFloat
    let progressBinding: Binding<CGFloat>
    let isExpanded: Bool
    let bounceOffset: CGFloat
    let onExpansionChanged: (Bool) -> Void
    let onBounceChanged: (CGFloat, Bool) -> Void
    let onGestureActivityChanged: (Bool) -> Void
}

struct 沉浸封面详情内容<Header: View, Content: View>: View {
    let header: (沉浸封面拖动上下文) -> Header
    let content: Content
    let onGestureActivityChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State private var bounceOffset: CGFloat = 0
    @State private var isExpanded = false

    init(
        onGestureActivityChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder header: @escaping (沉浸封面拖动上下文) -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.content = content()
        self.onGestureActivityChanged = onGestureActivityChanged
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            沉浸封面详情头部(
                header: header,
                bounceOffset: bounceOffset,
                isExpanded: isExpanded,
                onExpansionChanged: setExpanded,
                onBounceChanged: updateBounce,
                onGestureActivityChanged: onGestureActivityChanged
            )
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 32)
        .offset(y: bounceOffset)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
    }

    private func updateBounce(_ offset: CGFloat, settles: Bool) {
        guard bounceOffset != offset else { return }
        if settles {
            withAnimation(
                reduceMotion
                    ? nil
                    : .spring(response: 0.34, dampingFraction: 0.86)
            ) {
                bounceOffset = offset
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                bounceOffset = offset
            }
        }
    }
}

private struct 沉浸封面详情头部<Header: View>: View {
    let header: (沉浸封面拖动上下文) -> Header
    let bounceOffset: CGFloat
    let isExpanded: Bool
    let onExpansionChanged: (Bool) -> Void
    let onBounceChanged: (CGFloat, Bool) -> Void
    let onGestureActivityChanged: (Bool) -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        let context = 沉浸封面拖动上下文(
            progress: progress,
            progressBinding: $progress,
            isExpanded: isExpanded,
            bounceOffset: bounceOffset,
            onExpansionChanged: onExpansionChanged,
            onBounceChanged: onBounceChanged,
            onGestureActivityChanged: onGestureActivityChanged
        )

        header(context)
    }

}

struct 沉浸封面拖动图层<Content: View>: View {
    let isExpanded: Bool
    let hasImage: Bool
    let onExpansionChanged: (Bool) -> Void
    let onBounceChanged: (CGFloat, Bool) -> Void
    let onGestureActivityChanged: (Bool) -> Void
    let onTap: (() -> Void)?
    let content: (CGFloat) -> Content

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Binding private var progress: CGFloat
    @State private var feedbackCount = 0
    @State private var gestureIsActive = false
    @State private var gestureActivityGeneration = 0
    @State private var gestureStartedExpanded = false
    @State private var gestureThresholdCommitted = false

    init(
        isExpanded: Bool,
        hasImage: Bool,
        progress: Binding<CGFloat>,
        onExpansionChanged: @escaping (Bool) -> Void,
        onBounceChanged: @escaping (CGFloat, Bool) -> Void = { _, _ in },
        onGestureActivityChanged: @escaping (Bool) -> Void = { _ in },
        onTap: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.isExpanded = isExpanded
        self.hasImage = hasImage
        self._progress = progress
        self.onExpansionChanged = onExpansionChanged
        self.onBounceChanged = onBounceChanged
        self.onGestureActivityChanged = onGestureActivityChanged
        self.onTap = onTap
        self.content = content
    }

    @ViewBuilder
    var body: some View {
        if hasImage {
            content(progress)
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap?()
                }
                .background {
                    沉浸封面滚动拖动监听器(
                        isExpanded: isExpanded,
                        onBegan: beginGesture,
                        onChanged: updateProgress,
                        onEnded: finish,
                        onBounceChanged: onBounceChanged
                    )
                }
                .sensoryFeedback(.impact, trigger: feedbackCount)
                .onAppear {
                    setProgress(isExpanded ? 1 : 0)
                }
        } else {
            content(0)
        }
    }

    private func beginGesture() {
        gestureActivityGeneration += 1
        gestureIsActive = true
        onGestureActivityChanged(true)
        gestureStartedExpanded = isExpanded
        gestureThresholdCommitted = false
    }

    private func updateProgress(for translation: CGSize) -> Bool {
        guard hasImage else { return false }

        let vertical = translation.height
        if gestureStartedExpanded {
            let nextProgress = min(
                max(
                    1 + vertical / 沉浸封面拖动参数.收起阈值,
                    0
                ),
                1
            )
            setProgress(nextProgress, immediately: true)
            return true
        }

        if gestureThresholdCommitted {
            let nextProgress = min(
                max(
                    vertical / 沉浸封面拖动参数.展开阈值,
                    0
                ),
                1
            )
            setProgress(nextProgress, immediately: true)
            return true
        }

        guard abs(vertical) > abs(translation.width) * 1.15 else {
            return false
        }

        guard vertical >= 沉浸封面拖动参数.展开阈值 else {
            return false
        }

        gestureThresholdCommitted = true
        feedbackCount += 1
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.34, dampingFraction: 0.86)
        ) {
            setProgress(1)
        }
        return true
    }

    private func finish(
        translation: CGSize,
        projectedTranslation: CGSize
    ) -> Bool {
        guard hasImage else { return false }

        let projectedProgress: CGFloat
        if gestureStartedExpanded {
            projectedProgress = min(
                max(
                    1 + projectedTranslation.height
                        / 沉浸封面拖动参数.收起阈值,
                    0
                ),
                1
            )
        } else {
            projectedProgress = min(
                max(
                    projectedTranslation.height
                        / 沉浸封面拖动参数.展开阈值,
                    0
                ),
                1
            )
        }
        let shouldExpand = gestureStartedExpanded
            ? projectedProgress >= 0.5
            : gestureThresholdCommitted && projectedProgress >= 0.5
        gestureIsActive = false
        gestureActivityGeneration += 1
        let activityGeneration = gestureActivityGeneration

        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.34, dampingFraction: 0.86),
            completionCriteria: .logicallyComplete
        ) {
            setProgress(shouldExpand ? 1 : 0)
            if shouldExpand != isExpanded {
                onExpansionChanged(shouldExpand)
            }
        } completion: {
            guard self.gestureActivityGeneration == activityGeneration,
                  !self.gestureIsActive else {
                return
            }
            self.onGestureActivityChanged(false)
        }
        gestureStartedExpanded = false
        gestureThresholdCommitted = false
        return shouldExpand
    }

    private func setProgress(
        _ nextProgress: CGFloat,
        immediately: Bool = false
    ) {
        let clampedProgress = min(max(nextProgress, 0), 1)
        guard progress != clampedProgress else { return }
        if immediately {
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                progress = clampedProgress
            }
        } else {
            progress = clampedProgress
        }
    }
}

private struct 沉浸封面滚动拖动监听器: UIViewRepresentable {
    let isExpanded: Bool
    let onBegan: () -> Void
    let onChanged: (CGSize) -> Bool
    let onEnded: (CGSize, CGSize) -> Bool
    let onBounceChanged: (CGFloat, Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isExpanded: isExpanded,
            onBegan: onBegan,
            onChanged: onChanged,
            onEnded: onEnded,
            onBounceChanged: onBounceChanged
        )
    }

    func makeUIView(context: Context) -> 沉浸封面滚动监听视图 {
        沉浸封面滚动监听视图 {
            context.coordinator.attach(to: $0)
        }
    }

    func updateUIView(
        _ view: 沉浸封面滚动监听视图,
        context: Context
    ) {
        context.coordinator.isExpanded = isExpanded
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onBounceChanged = onBounceChanged
        context.coordinator.attach(to: view)
    }

    static func dismantleUIView(
        _ view: 沉浸封面滚动监听视图,
        coordinator: Coordinator
    ) {
        coordinator.detach()
    }

    final class 沉浸封面滚动监听视图: UIView {
        let onHierarchyChanged: (UIView) -> Void

        init(onHierarchyChanged: @escaping (UIView) -> Void) {
            self.onHierarchyChanged = onHierarchyChanged
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isOpaque = false
        }

        required init?(coder: NSCoder) {
            nil
        }

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onHierarchyChanged(self)
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onHierarchyChanged(self)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            onHierarchyChanged(self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isExpanded: Bool
        var onBegan: () -> Void
        var onChanged: (CGSize) -> Bool
        var onEnded: (CGSize, CGSize) -> Bool
        var onBounceChanged: (CGFloat, Bool) -> Void
        var gestureStartedExpanded = false
        var coverOwnsGesture = false
        var nativeScrollPanIsDisabled = false
        var collapsedNativeBounceIsActive = false
        var collapsedRecoveryAnchor: CGFloat?
        var currentCoverTranslation: CGFloat = 0
        var lastReportedBounceOffset: CGFloat = 0
        weak var panGestureRecognizer: UIPanGestureRecognizer?
        weak var scrollView: UIScrollView?

        init(
            isExpanded: Bool,
            onBegan: @escaping () -> Void,
            onChanged: @escaping (CGSize) -> Bool,
            onEnded: @escaping (CGSize, CGSize) -> Bool,
            onBounceChanged: @escaping (CGFloat, Bool) -> Void
        ) {
            self.isExpanded = isExpanded
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onBounceChanged = onBounceChanged
        }

        func attach(to view: UIView) {
            guard let nextScrollView = enclosingScrollView(from: view) else {
                return
            }

            guard nextScrollView !== scrollView else { return }
            detach()

            let pan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delegate = self
            nextScrollView.addGestureRecognizer(pan)
            panGestureRecognizer = pan
            scrollView = nextScrollView
        }

        func detach() {
            restoreScrollPanIfNeeded()
            if let panGestureRecognizer {
                panGestureRecognizer.view?.removeGestureRecognizer(
                    panGestureRecognizer
                )
            }
            resetGestureState()
            panGestureRecognizer = nil
            scrollView = nil
        }

        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView = pan.view as? UIScrollView else {
                return false
            }
            let velocity = pan.velocity(in: scrollView.superview)
            guard abs(velocity.y) > abs(velocity.x) * 1.15 else {
                return false
            }

            let topOffset = -scrollView.adjustedContentInset.top
            if isExpanded {
                return velocity.y < 0
            }
            let topDistance = scrollView.contentOffset.y - topOffset
            guard topDistance <= 24 else {
                return false
            }
            return velocity.y > 0
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            guard let scrollPan = scrollView?.panGestureRecognizer else {
                return false
            }
            return gestureRecognizer === scrollPan
                || otherGestureRecognizer === scrollPan
        }

        @objc
        func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView else {
                return
            }
            let translationPoint = recognizer.translation(
                in: scrollView.superview
            )
            let translation = CGSize(
                width: translationPoint.x,
                height: translationPoint.y
            )

            switch recognizer.state {
            case .began:
                resetGestureState()
                gestureStartedExpanded = isExpanded
                coverOwnsGesture = gestureStartedExpanded
                currentCoverTranslation = translation.height
                reportBounceOffset(0, settles: false)
                onBegan()

                if coverOwnsGesture {
                    let topOffset = -scrollView.adjustedContentInset.top
                    scrollView.setContentOffset(
                        CGPoint(
                            x: scrollView.contentOffset.x,
                            y: topOffset
                        ),
                        animated: false
                    )
                    disableScrollPanIfNeeded(in: scrollView)
                }
                _ = onChanged(translation)
            case .changed:
                if gestureStartedExpanded {
                    currentCoverTranslation = translation.height
                    _ = onChanged(translation)
                    updateExpandedGestureScrollPosition(
                        translation: translation.height,
                        in: scrollView
                    )
                } else {
                    updateCollapsedGesture(
                        translation: translation,
                        velocity: recognizer.velocity(
                            in: scrollView.superview
                        ).y,
                        in: scrollView
                    )
                }
            case .ended:
                let velocity = recognizer.velocity(in: scrollView.superview)
                let projectedNativeBounceTranslation =
                    沉浸封面拖动参数.展开阈值
                    + velocity.y * 沉浸封面拖动参数.投影时长
                let capturesUpwardFling = !gestureStartedExpanded
                    && collapsedNativeBounceIsActive
                    && projectedNativeBounceTranslation
                        < 沉浸封面拖动参数.展开阈值 * 0.5
                if capturesUpwardFling {
                    collapsedNativeBounceIsActive = false
                    currentCoverTranslation = 沉浸封面拖动参数.展开阈值
                    stopNativeScrollAtTop(in: scrollView)
                }
                let nativeScrollOwnsEnding = !gestureStartedExpanded
                    && (!coverOwnsGesture || collapsedNativeBounceIsActive)
                let endingTranslation = CGSize(
                    width: translation.width,
                    height: currentCoverTranslation
                )
                let projectedTranslation = CGSize(
                    width: endingTranslation.width
                        + velocity.x * 沉浸封面拖动参数.投影时长,
                    height: collapsedNativeBounceIsActive
                        ? 沉浸封面拖动参数.展开阈值
                        : endingTranslation.height
                            + velocity.y * 沉浸封面拖动参数.投影时长
                )
                let shouldExpand = onEnded(
                    endingTranslation,
                    projectedTranslation
                )
                reportBounceOffset(0, settles: true)
                if !nativeScrollOwnsEnding {
                    settleScrollPosition(
                        shouldExpand: shouldExpand,
                        in: scrollView
                    )
                }
                restoreScrollPanIfNeeded()
                resetGestureState()
            case .cancelled, .failed:
                let endingTranslation = CGSize(
                    width: translation.width,
                    height: currentCoverTranslation
                )
                let shouldExpand = onEnded(
                    endingTranslation,
                    endingTranslation
                )
                reportBounceOffset(0, settles: true)
                let nativeScrollOwnsEnding = !gestureStartedExpanded
                    && (!coverOwnsGesture || collapsedNativeBounceIsActive)
                if !nativeScrollOwnsEnding {
                    settleScrollPosition(
                        shouldExpand: shouldExpand,
                        in: scrollView
                    )
                }
                restoreScrollPanIfNeeded()
                resetGestureState()
            default:
                break
            }
        }

        private func updateExpandedGestureScrollPosition(
            translation: CGFloat,
            in scrollView: UIScrollView
        ) {
            let topOffset = -scrollView.adjustedContentInset.top
            let contentOffset: CGFloat

            let scrollStart = 沉浸封面拖动参数.收起阈值
                + 沉浸封面拖动参数.滚动交接余量
            if translation < -scrollStart {
                contentOffset = -translation
                    - scrollStart
                reportBounceOffset(0, settles: false)
            } else if translation > 沉浸封面拖动参数.回弹交接余量 {
                contentOffset = 0
                reportBounceOffset(
                    rubberBandDistance(
                        translation
                            - 沉浸封面拖动参数.回弹交接余量,
                        dimension: scrollView.bounds.height
                    ),
                    settles: false
                )
            } else {
                contentOffset = 0
                reportBounceOffset(0, settles: false)
            }

            setScrollOffset(topOffset + contentOffset, in: scrollView)
        }

        private func updateCollapsedGesture(
            translation: CGSize,
            velocity: CGFloat,
            in scrollView: UIScrollView
        ) {
            if !coverOwnsGesture {
                currentCoverTranslation = translation.height
                guard onChanged(translation) else { return }
                coverOwnsGesture = true
                collapsedNativeBounceIsActive = true
                currentCoverTranslation = 沉浸封面拖动参数.展开阈值
                return
            }

            let topOffset = -scrollView.adjustedContentInset.top
            if collapsedNativeBounceIsActive {
                currentCoverTranslation = 沉浸封面拖动参数.展开阈值
                _ = onChanged(
                    CGSize(
                        width: translation.width,
                        height: currentCoverTranslation
                    )
                )

                guard velocity < 0,
                      scrollView.contentOffset.y >= topOffset - 2 else {
                    return
                }

                collapsedNativeBounceIsActive = false
                collapsedRecoveryAnchor = translation.height
                disableScrollPanIfNeeded(in: scrollView)
                setScrollOffset(topOffset, in: scrollView)
            }

            guard let collapsedRecoveryAnchor else { return }
            let effectiveTranslation = 沉浸封面拖动参数.展开阈值
                + translation.height
                - collapsedRecoveryAnchor
            currentCoverTranslation = effectiveTranslation
            _ = onChanged(
                CGSize(
                    width: translation.width,
                    height: effectiveTranslation
                )
            )

            let contentOffset: CGFloat

            let bounceStart = 沉浸封面拖动参数.展开阈值
                + 沉浸封面拖动参数.回弹交接余量
            if effectiveTranslation > bounceStart {
                contentOffset = 0
                reportBounceOffset(
                    rubberBandDistance(
                        effectiveTranslation - bounceStart,
                        dimension: scrollView.bounds.height
                    ),
                    settles: false
                )
            } else if effectiveTranslation
                >= -沉浸封面拖动参数.滚动交接余量 {
                contentOffset = 0
                reportBounceOffset(0, settles: false)
            } else {
                contentOffset = -effectiveTranslation
                    - 沉浸封面拖动参数.滚动交接余量
                reportBounceOffset(0, settles: false)
            }

            setScrollOffset(topOffset + contentOffset, in: scrollView)
        }

        private func setScrollOffset(
            _ verticalOffset: CGFloat,
            in scrollView: UIScrollView
        ) {
            guard scrollView.contentOffset.y != verticalOffset else { return }
            scrollView.setContentOffset(
                CGPoint(
                    x: scrollView.contentOffset.x,
                    y: verticalOffset
                ),
                animated: false
            )
        }

        private func reportBounceOffset(
            _ offset: CGFloat,
            settles: Bool
        ) {
            guard lastReportedBounceOffset != offset else { return }
            lastReportedBounceOffset = offset
            onBounceChanged(offset, settles)
        }

        private func rubberBandDistance(
            _ distance: CGFloat,
            dimension: CGFloat
        ) -> CGFloat {
            let dimension = max(dimension, 1)
            return (1 - 1 / (distance * 0.55 / dimension + 1))
                * dimension
        }

        private func settleScrollPosition(
            shouldExpand: Bool,
            in scrollView: UIScrollView
        ) {
            let topOffset = -scrollView.adjustedContentInset.top
            guard shouldExpand || scrollView.contentOffset.y < topOffset else {
                return
            }

            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                scrollView.contentOffset.y = topOffset
            }
        }

        private func disableScrollPanIfNeeded(in scrollView: UIScrollView) {
            guard !nativeScrollPanIsDisabled else { return }
            scrollView.panGestureRecognizer.isEnabled = false
            nativeScrollPanIsDisabled = true
        }

        private func stopNativeScrollAtTop(in scrollView: UIScrollView) {
            disableScrollPanIfNeeded(in: scrollView)
            scrollView.layer.removeAllAnimations()
            setScrollOffset(-scrollView.adjustedContentInset.top, in: scrollView)
        }

        private func restoreScrollPanIfNeeded() {
            guard nativeScrollPanIsDisabled else { return }
            scrollView?.panGestureRecognizer.isEnabled = true
            nativeScrollPanIsDisabled = false
        }

        private func resetGestureState() {
            gestureStartedExpanded = false
            coverOwnsGesture = false
            collapsedNativeBounceIsActive = false
            collapsedRecoveryAnchor = nil
            currentCoverTranslation = 0
        }

        private func enclosingScrollView(from view: UIView) -> UIScrollView? {
            var candidate = view.superview
            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                candidate = current.superview
            }
            return nil
        }
    }
}

enum 详情卡片样式 {
    static let 文本间距: CGFloat = 3
    static let 角色图片宽度: CGFloat = 112
    static let 角色图片高度: CGFloat = 146
}

enum 列表行布局 {
    static let 主副标题间距: CGFloat = 4
    static let 图标文字间距: CGFloat = 2
    static let 元数据间距: CGFloat = 12
}

enum 列表封面布局 {
    static let 宽度: CGFloat = 72
    static let 高度: CGFloat = 100

    static func 圆角(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular ? 10 : 16
    }
}

enum 评论卡片布局 {
    static let 圆角: CGFloat = 28
    static let 内边距: CGFloat = 14
    static let 顶部内边距: CGFloat = 10
    static var 内层圆角: CGFloat { 圆角 - 内边距 }
    static let 预览条数 = 3
}

enum 沉浸详情布局 {
    static let 主要信息间距: CGFloat = 14
    static let 媒体卡片宽度: CGFloat = 142
    static let 媒体卡片高度: CGFloat = 190
    static let 背景扩展透明缓冲: CGFloat = 256
    static let 紧凑内联标签上限 = 14
    static let 常规内联标签上限 = 28
}

struct 沉浸详情等高双栏布局: Layout {
    var spacing: CGFloat = 16
    var divisionFrame: CGRect?
    var horizontalInset: CGFloat = 0

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let width = resolvedWidth(for: proposal, subviews: subviews)
        let placements = resolvedPlacements(
            totalWidth: width,
            columnCount: subviews.count
        )
        let height = zip(subviews, placements).reduce(CGFloat.zero) {
            currentHeight,
            pair in
            let (subview, placement) = pair
            let size = subview.sizeThatFits(
                ProposedViewSize(width: placement.width, height: nil)
            )
            return max(currentHeight, size.height)
        }

        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard !subviews.isEmpty else { return }

        let placements = resolvedPlacements(
            totalWidth: bounds.width,
            columnCount: subviews.count
        )

        for (subview, placement) in zip(subviews, placements) {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + placement.minX,
                    y: bounds.minY
                ),
                anchor: .topLeading,
                proposal: ProposedViewSize(
                    width: placement.width,
                    height: bounds.height
                )
            )
        }
    }

    private func resolvedWidth(
        for proposal: ProposedViewSize,
        subviews: Subviews
    ) -> CGFloat {
        if let proposedWidth = proposal.width {
            return max(proposedWidth, 0)
        }

        let idealWidths = subviews.map {
            $0.sizeThatFits(.unspecified).width
        }
        return idealWidths.reduce(0, +)
            + spacing * CGFloat(max(subviews.count - 1, 0))
    }

    private func resolvedPlacements(
        totalWidth: CGFloat,
        columnCount: Int
    ) -> [ColumnPlacement] {
        if let divisionPlacements = resolvedDivisionPlacements(
            totalWidth: totalWidth,
            columnCount: columnCount
        ) {
            return divisionPlacements
        }

        let totalSpacing = spacing * CGFloat(max(columnCount - 1, 0))
        let columnWidth = max(
            (totalWidth - totalSpacing) / CGFloat(columnCount),
            0
        )
        return (0..<columnCount).map { index in
            ColumnPlacement(
                minX: CGFloat(index) * (columnWidth + spacing),
                width: columnWidth
            )
        }
    }

    private func resolvedDivisionPlacements(
        totalWidth: CGFloat,
        columnCount: Int
    ) -> [ColumnPlacement]? {
        guard columnCount == 1 || columnCount == 2,
              let divisionFrame,
              divisionFrame.width.isFinite,
              divisionFrame.height.isFinite,
              divisionFrame.height > divisionFrame.width else {
            return nil
        }

        let divisionMinX = divisionFrame.minX - horizontalInset
        let divisionMaxX = divisionFrame.maxX - horizontalInset
        guard divisionMinX.isFinite,
              divisionMaxX.isFinite,
              divisionMinX > 0,
              divisionMaxX < totalWidth,
              divisionMaxX >= divisionMinX else {
            return nil
        }

        let leadingPlacement = ColumnPlacement(
            minX: 0,
            width: divisionMinX
        )
        let trailingPlacement = ColumnPlacement(
            minX: divisionMaxX,
            width: totalWidth - divisionMaxX
        )

        if columnCount == 1 {
            return [trailingPlacement]
        }
        return [leadingPlacement, trailingPlacement]
    }

    private struct ColumnPlacement {
        let minX: CGFloat
        let width: CGFloat
    }
}

enum 沉浸详情外观: String, CaseIterable, Identifiable {
    case standard = "default"
    case clear
    case reduced

    static let 设置键 = "immersiveDetailAppearance"

    /// iOS 26 以下没有 Liquid Glass，统一按“减少使用”的材质外观呈现。
    var 平台生效值: Self {
        if #available(iOS 26.0, *) {
            return self
        }
        return .reduced
    }

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .standard: String(localized: "色调")
        case .clear: String(localized: "透明")
        case .reduced: String(localized: "减少使用")
        }
    }

    func glass(
        tint: Color? = nil,
        interactive: Bool = false
    ) -> 平台玻璃 {
        let base: 平台玻璃
        switch self {
        case .standard:
            base = .regular
        case .clear:
            base = .clear
        case .reduced:
            base = .regular
        }
        let tinted = base.tint(tint)
        return interactive ? tinted.interactive() : tinted
    }
}

/// 与 `Glass` 同形的描述值，iOS 26 以下也能构造；仅在 iOS 26 及以上按原调用顺序转成 `Glass`。
struct 平台玻璃 {
    private enum 基础 {
        case regular
        case clear
    }

    private enum 调整 {
        case tint(Color?)
        case interactive(Bool)
    }

    private let base: 基础
    private let adjustments: [调整]

    static var regular: Self {
        Self(base: .regular, adjustments: [])
    }

    static var clear: Self {
        Self(base: .clear, adjustments: [])
    }

    func tint(_ color: Color?) -> Self {
        Self(base: base, adjustments: adjustments + [.tint(color)])
    }

    func interactive(_ isEnabled: Bool = true) -> Self {
        Self(base: base, adjustments: adjustments + [.interactive(isEnabled)])
    }

    @available(iOS 26.0, *)
    var glass: Glass {
        var glass: Glass = switch base {
        case .regular: .regular
        case .clear: .clear
        }
        for adjustment in adjustments {
            switch adjustment {
            case let .tint(color):
                glass = glass.tint(color)
            case let .interactive(isEnabled):
                glass = glass.interactive(isEnabled)
            }
        }
        return glass
    }
}

private struct 液态玻璃Modifier<S: Shape>: ViewModifier {
    let glass: 平台玻璃
    let shape: S

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(沉浸详情外观.设置键)
    private var liquidGlassAppearance: 沉浸详情外观 = .clear

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), liquidGlassAppearance != .reduced {
            content.glassEffect(glass.glass, in: shape)
        } else {
            content
                .foregroundStyle(colorScheme == .dark ? Color.white : .black)
                .background {
                    shape.fill(.ultraThinMaterial)
                }
        }
    }
}

private struct 高透明材质按钮样式<S: Shape>: ButtonStyle {
    let shape: S
    let isProminent: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(colorScheme == .dark ? Color.white : .black)
            .padding(.horizontal, isProminent ? 14 : 10)
            .padding(.vertical, isProminent ? 10 : 8)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if isProminent {
                            shape.fill(Color.accentColor.opacity(0.16))
                        }
                    }
            }
            .overlay {
                shape.stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.45)
    }
}

private struct 液态玻璃醒目按钮Modifier<S: Shape>: ViewModifier {
    let shape: S

    @AppStorage(沉浸详情外观.设置键)
    private var liquidGlassAppearance: 沉浸详情外观 = .clear

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), liquidGlassAppearance != .reduced {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(
                高透明材质按钮样式(shape: shape, isProminent: true)
            )
        }
    }
}

private struct 液态玻璃按钮Modifier<S: Shape>: ViewModifier {
    let shape: S

    @AppStorage(沉浸详情外观.设置键)
    private var liquidGlassAppearance: 沉浸详情外观 = .clear

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), liquidGlassAppearance != .reduced {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(
                高透明材质按钮样式(shape: shape, isProminent: false)
            )
        }
    }
}

nonisolated enum 沉浸详情玻璃色调: Equatable, Sendable {
    case black
    case white

    @MainActor
    var color: Color {
        switch self {
        case .black: .black
        case .white: .white
        }
    }
}

nonisolated enum 沉浸玻璃色调阈值 {
    static let 最低封面不透明度 = 0.75
    static let 最低取样数 = 16
    static let 最低单色覆盖率 = 0.995
    static let 接近白色亮度 = 0.995
    static let 接近黑色亮度 = 0.005
}

struct 沉浸详情文字样式 {
    let appearance: 沉浸详情外观
    let sample: 沉浸玻璃文字取样结果?
    let fallbackColorScheme: ColorScheme

    private var usesAdaptiveColors: Bool {
        (appearance == .clear || appearance == .reduced) && sample != nil
    }

    private var usesDarkText: Bool? {
        sample?.dominantUsesDarkText ?? sample?.usesDarkText
    }

    private var elementUsesDarkText: Bool? {
        sample?.usesDarkText
    }

    var usesWhiteText: Bool {
        usesAdaptiveColors && usesDarkText == false
    }

    var colorAnimationKey: Int {
        guard usesAdaptiveColors else { return 0 }
        return usesDarkText == true ? 1 : 2
    }

    var primary: Color {
        guard usesAdaptiveColors else { return .primary }
        return usesDarkText == true ? .black : .white
    }

    var secondary: Color {
        guard usesAdaptiveColors else { return .secondary }
        return primary.opacity(usesWhiteText ? 0.92 : 0.78)
    }

    var tertiary: Color {
        guard usesAdaptiveColors else { return .secondary.opacity(0.7) }
        return primary.opacity(usesWhiteText ? 0.86 : 0.7)
    }

    var capsule: Color {
        guard usesAdaptiveColors else { return .secondary }
        return primary.opacity(usesWhiteText ? 0.78 : 0.62)
    }

    var colorScheme: ColorScheme {
        guard usesAdaptiveColors else { return fallbackColorScheme }
        return usesDarkText == true ? .light : .dark
    }

    var contrastShadowColor: Color {
        guard usesAdaptiveColors,
              sample?.needsContrastShadow == true else {
            return .clear
        }
        guard let elementUsesDarkText else { return .clear }
        return elementUsesDarkText
            ? .black.opacity(0.24)
            : .white.opacity(0.24)
    }

    var contrastShadowRadius: CGFloat {
        usesAdaptiveColors && sample?.needsContrastShadow == true ? 7 : 0
    }

    var contrastShadowYOffset: CGFloat {
        usesAdaptiveColors && sample?.needsContrastShadow == true ? 1 : 0
    }
}

nonisolated struct 沉浸玻璃文字取样结果: Equatable, Sendable {
    let usesDarkText: Bool
    let dominantUsesDarkText: Bool
    let needsContrastShadow: Bool
    let isNearlyUniformWhiteBackground: Bool
    let glassTint: 沉浸详情玻璃色调?
}

private struct 沉浸详情玻璃Modifier<S: Shape>: ViewModifier {
    let appearance: 沉浸详情外观
    let sample: 沉浸玻璃文字取样结果?
    let fallbackTint: Color?
    let interactive: Bool
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        let tint = appearance == .clear
            ? sample?.glassTint?.color ?? fallbackTint
            : nil
        let glassContent = content.modifier(
            液态玻璃Modifier(
                glass: appearance.glass(tint: tint, interactive: interactive),
                shape: shape
            )
        )
        if appearance == .reduced, let sample {
            glassContent.environment(
                \.colorScheme,
                sample.dominantUsesDarkText ? .light : .dark
            )
        } else {
            glassContent
        }
    }
}

private struct 高透明提亮材质背景Modifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .opacity(0.48)
                    .overlay {
                        shape.fill(.white.opacity(0.08))
                    }
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .stroke(.white.opacity(0.2), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

private struct 沉浸详情玻璃背景Modifier<S: Shape>: ViewModifier {
    let appearance: 沉浸详情外观
    let sample: 沉浸玻璃文字取样结果?
    let fallbackTint: Color?
    let usesBrightReducedMaterial: Bool
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if appearance == .reduced && usesBrightReducedMaterial {
            content.高透明提亮材质背景(in: shape)
        } else {
            let tint = appearance == .clear
                ? sample?.glassTint?.color ?? fallbackTint
                : nil
            content
                .background {
                    let glassShape = shape
                        .fill(.clear)
                        .modifier(
                            液态玻璃Modifier(
                                glass: appearance.glass(tint: tint),
                                shape: shape
                            )
                        )
                        .allowsHitTesting(false)
                    if appearance == .reduced, let sample {
                        glassShape.environment(
                            \.colorScheme,
                            sample.dominantUsesDarkText ? .light : .dark
                        )
                    } else {
                        glassShape
                    }
                }
        }
    }
}

private struct 沉浸详情解析文字颜色Modifier: AnimatableModifier {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var opacity: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(red, green),
                AnimatablePair(blue, opacity)
            )
        }
        set {
            red = newValue.first.first
            green = newValue.first.second
            blue = newValue.second.first
            opacity = newValue.second.second
        }
    }

    func body(content: Content) -> some View {
        content.foregroundStyle(
            Color(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                opacity: Double(opacity)
            )
        )
    }
}

private struct 沉浸详情文字颜色过渡Modifier: ViewModifier {
    let color: Color
    let animationKey: Int

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.self)
    private var environment

    func body(content: Content) -> some View {
        let resolved = color.resolve(in: environment)
        return content
            .modifier(
                沉浸详情解析文字颜色Modifier(
                    red: CGFloat(resolved.red),
                    green: CGFloat(resolved.green),
                    blue: CGFloat(resolved.blue),
                    opacity: CGFloat(resolved.opacity)
                )
            )
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.28),
                value: animationKey
            )
    }
}

extension View {
    func 高透明提亮材质背景<S: Shape>(in shape: S) -> some View {
        modifier(高透明提亮材质背景Modifier(shape: shape))
    }

    func 液态玻璃<S: Shape>(_ glass: 平台玻璃, in shape: S) -> some View {
        modifier(液态玻璃Modifier(glass: glass, shape: shape))
    }

    func 液态玻璃醒目按钮<S: Shape>(in shape: S) -> some View {
        modifier(液态玻璃醒目按钮Modifier(shape: shape))
    }

    func 液态玻璃按钮<S: Shape>(in shape: S) -> some View {
        modifier(液态玻璃按钮Modifier(shape: shape))
    }

    func 沉浸详情文字前景色(
        _ color: Color,
        style: 沉浸详情文字样式
    ) -> some View {
        modifier(
            沉浸详情文字颜色过渡Modifier(
                color: color,
                animationKey: style.colorAnimationKey
            )
        )
    }

    func 沉浸详情玻璃<S: Shape>(
        _ appearance: 沉浸详情外观,
        sample: 沉浸玻璃文字取样结果? = nil,
        fallbackTint: Color? = nil,
        interactive: Bool = false,
        in shape: S
    ) -> some View {
        modifier(
            沉浸详情玻璃Modifier(
                appearance: appearance,
                sample: sample,
                fallbackTint: fallbackTint,
                interactive: interactive,
                shape: shape
            )
        )
    }

    func 沉浸详情文字阴影(
        _ style: 沉浸详情文字样式
    ) -> some View {
        shadow(
            color: style.contrastShadowColor,
            radius: style.contrastShadowRadius,
            y: style.contrastShadowYOffset
        )
    }

    func 沉浸详情玻璃背景<S: Shape>(
        _ appearance: 沉浸详情外观,
        sample: 沉浸玻璃文字取样结果? = nil,
        fallbackTint: Color? = nil,
        usesBrightReducedMaterial: Bool = false,
        in shape: S
    ) -> some View {
        modifier(
            沉浸详情玻璃背景Modifier(
                appearance: appearance,
                sample: sample,
                fallbackTint: fallbackTint,
                usesBrightReducedMaterial: usesBrightReducedMaterial,
                shape: shape
            )
        )
    }
}

struct 详情更多入口按钮样式: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(
                configuration.isPressed && !reduceMotion ? 0.96 : 1
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

nonisolated enum 沉浸封面文字分析布局: Equatable, Sendable {
    case visualNovel
    case character
}

nonisolated enum 沉浸详情背景色调: Sendable {
    case light
    case dark

    var luminance: Double {
        switch self {
        case .light: return 1
        case .dark: return 0
        }
    }
}

nonisolated struct 沉浸封面文字取样几何: Sendable, Equatable {
    let imageSize: CGSize
    let regions: [String: CGRect]
}

nonisolated struct 沉浸封面文字取样请求: Sendable, Equatable {
    let url: URL
    let layout: 沉浸封面文字分析布局
    let background: 沉浸详情背景色调
    let extendsThroughInformation: Bool
    let itemCounts: [String: Int]
    let geometry: 沉浸封面文字取样几何
}

@MainActor
final class 沉浸封面文字取样任务协调器 {
    private var task: Task<Void, Never>?
    private var generation = 0
    private var currentRequest: 沉浸封面文字取样请求?
    private(set) var latestGeometry: 沉浸封面文字取样几何?

    func remember(_ geometry: 沉浸封面文字取样几何) {
        latestGeometry = geometry
    }

    func submit(
        _ request: 沉浸封面文字取样请求,
        apply: @escaping @MainActor (
            沉浸封面文字取样请求,
            [String: 沉浸玻璃文字取样结果]
        ) -> Void
    ) {
        latestGeometry = request.geometry
        guard currentRequest != request else { return }

        generation += 1
        let submittedGeneration = generation
        currentRequest = request
        task?.cancel()
        task = Task {
            let samples = await 沉浸封面文字分析缓存.shared
                .textSamplesAsync(for: request)
            guard !Task.isCancelled,
                  generation == submittedGeneration,
                  currentRequest == request else {
                return
            }
            guard !samples.isEmpty else {
                currentRequest = nil
                return
            }
            apply(request, samples)
        }
    }

    func cancel() {
        generation += 1
        currentRequest = nil
        task?.cancel()
        task = nil
    }
}

nonisolated struct 沉浸封面亮度图: Sendable {
    let width: Int
    let height: Int
    let luminances: [UInt8]

    private struct RegionDefinition {
        let key: String
        let group: String
        let regions: [CGRect]
    }

    private struct TextSampleMetrics {
        var lightBackgroundCount = 0
        var darkBackgroundCount = 0
        var nearlyWhiteBackgroundCount = 0
        var nearlyBlackBackgroundCount = 0
        var tintCandidateSampleCount = 0
        var luminanceTotal: Double = 0

        var usesDarkText: Bool {
            let sampleCount = lightBackgroundCount + darkBackgroundCount
            guard sampleCount > 0 else { return false }
            let averageLuminance = luminanceTotal / Double(sampleCount)
            let lightBackgroundRatio = Double(lightBackgroundCount)
                / Double(sampleCount)
            return lightBackgroundRatio >= 0.5 && averageLuminance >= 0.18
        }

        var glassTint: 沉浸详情玻璃色调? {
            guard tintCandidateSampleCount >= 沉浸玻璃色调阈值.最低取样数
            else { return nil }
            let sampleCount = Double(tintCandidateSampleCount)
            let nearlyWhiteRatio = Double(nearlyWhiteBackgroundCount)
                / sampleCount
            if nearlyWhiteRatio >= 沉浸玻璃色调阈值.最低单色覆盖率 {
                return .white
            }
            let nearlyBlackRatio = Double(nearlyBlackBackgroundCount)
                / sampleCount
            return nearlyBlackRatio >= 沉浸玻璃色调阈值.最低单色覆盖率
                ? .black
                : nil
        }

    }

    func textSamples(
        for layout: 沉浸封面文字分析布局,
        background: 沉浸详情背景色调,
        extendsThroughInformation: Bool,
        itemCounts: [String: Int] = [:],
        geometry: 沉浸封面文字取样几何? = nil
    ) -> [String: 沉浸玻璃文字取样结果] {
        guard !Task.isCancelled else { return [:] }
        let regions: [RegionDefinition]
        switch layout {
        case .visualNovel:
            regions = [
                RegionDefinition(
                    key: "metadata",
                    group: "metadata",
                    regions: [CGRect(x: 0.04, y: 0.31, width: 0.92, height: 0.25)]
                ),
                RegionDefinition(
                    key: "metadata.title",
                    group: "metadata",
                    regions: [CGRect(x: 0.04, y: 0.31, width: 0.92, height: 0.11)]
                ),
                RegionDefinition(
                    key: "metadata.rating",
                    group: "metadata",
                    regions: [CGRect(x: 0.04, y: 0.42, width: 0.44, height: 0.08)]
                ),
                RegionDefinition(
                    key: "metadata.length",
                    group: "metadata",
                    regions: [CGRect(x: 0.04, y: 0.50, width: 0.44, height: 0.09)]
                ),
                RegionDefinition(
                    key: "metadata.release",
                    group: "metadata",
                    regions: [CGRect(x: 0.52, y: 0.42, width: 0.44, height: 0.08)]
                ),
                RegionDefinition(
                    key: "metadata.status",
                    group: "metadata",
                    regions: [CGRect(x: 0.52, y: 0.50, width: 0.44, height: 0.09)]
                ),
                RegionDefinition(
                    key: "description",
                    group: "description",
                    regions: [CGRect(x: 0.02, y: 0.51, width: 0.96, height: 0.26)]
                ),
                RegionDefinition(
                    key: "description.text",
                    group: "description",
                    regions: [CGRect(x: 0.02, y: 0.51, width: 0.82, height: 0.26)]
                ),
                RegionDefinition(
                    key: "tags",
                    group: "tags",
                    regions: [CGRect(x: 0, y: 0.57, width: 1, height: 0.41)]
                )
            ] + tagDefinitions(
                group: "tags",
                startY: 0.57,
                count: itemCounts["tags"] ?? 28
            )
        case .character:
            regions = [
                RegionDefinition(
                    key: "metadata",
                    group: "metadata",
                    regions: [CGRect(x: 0.04, y: 0.31, width: 0.92, height: 0.25)]
                ),
                RegionDefinition(
                    key: "metadata.title",
                    group: "metadata",
                    regions: [CGRect(x: 0.04, y: 0.31, width: 0.92, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.age",
                    group: "metadata",
                    regions: [CGRect(x: 0, y: 0.41, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.birthday",
                    group: "metadata",
                    regions: [CGRect(x: 0.25, y: 0.41, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.gender",
                    group: "metadata",
                    regions: [CGRect(x: 0.50, y: 0.41, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.bloodType",
                    group: "metadata",
                    regions: [CGRect(x: 0.75, y: 0.41, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.height",
                    group: "metadata",
                    regions: [CGRect(x: 0, y: 0.51, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.weight",
                    group: "metadata",
                    regions: [CGRect(x: 0.25, y: 0.51, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.bust",
                    group: "metadata",
                    regions: [CGRect(x: 0.50, y: 0.51, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.waist",
                    group: "metadata",
                    regions: [CGRect(x: 0.75, y: 0.51, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.hips",
                    group: "metadata",
                    regions: [CGRect(x: 0, y: 0.61, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "metadata.cup",
                    group: "metadata",
                    regions: [CGRect(x: 0.25, y: 0.61, width: 0.25, height: 0.10)]
                ),
                RegionDefinition(
                    key: "description",
                    group: "description",
                    regions: [CGRect(x: 0.02, y: 0.52, width: 0.96, height: 0.24)]
                ),
                RegionDefinition(
                    key: "description.text",
                    group: "description",
                    regions: [CGRect(x: 0.02, y: 0.52, width: 0.82, height: 0.24)]
                ),
                RegionDefinition(
                    key: "traits",
                    group: "traits",
                    regions: [CGRect(x: 0, y: 0.5, width: 1, height: 0.48)]
                )
            ] + tagDefinitions(
                group: "traits",
                startY: 0.50,
                count: itemCounts["traits"] ?? 28
            )
        }

        var metricsByKey: [String: TextSampleMetrics] = [:]
        for definition in regions {
            guard !Task.isCancelled else { return [:] }
            let metrics: TextSampleMetrics?
            if let frame = geometry?.regions[definition.key],
               let geometry {
                metrics = textSampleMetrics(
                    inRenderedRegions: [frame],
                    imageSize: geometry.imageSize,
                    background: background,
                    extendsThroughInformation: extendsThroughInformation
                )
            } else {
                metrics = textSampleMetrics(
                    in: definition.regions,
                    background: background,
                    extendsThroughInformation: extendsThroughInformation
                )
            }
            if let metrics {
                metricsByKey[definition.key] = metrics
            }
        }

        var groupVotes: [String: (darkText: Int, whiteText: Int)] = [:]
        for definition in regions where definition.key != definition.group {
            guard let metrics = metricsByKey[definition.key] else { continue }
            if metrics.usesDarkText {
                groupVotes[definition.group, default: (0, 0)].darkText += 1
            } else {
                groupVotes[definition.group, default: (0, 0)].whiteText += 1
            }
        }

        return regions.reduce(into: [:]) { samples, definition in
            guard let metrics = metricsByKey[definition.key] else { return }
            let localUsesDarkText = metrics.usesDarkText
            let votes = groupVotes[definition.group]
            let dominantUsesDarkText: Bool
            if let votes,
               votes.darkText + votes.whiteText > 0 {
                dominantUsesDarkText = votes.darkText >= votes.whiteText
            } else {
                dominantUsesDarkText = localUsesDarkText
            }
            samples[definition.key] = 沉浸玻璃文字取样结果(
                usesDarkText: localUsesDarkText,
                dominantUsesDarkText: dominantUsesDarkText,
                needsContrastShadow: definition.key != definition.group
                    && localUsesDarkText != dominantUsesDarkText,
                isNearlyUniformWhiteBackground:
                    metrics.glassTint == .white,
                glassTint: metrics.glassTint
            )
        }
    }

    private func tagDefinitions(
        group: String,
        startY: CGFloat,
        count: Int
    ) -> [RegionDefinition] {
        (0..<max(count, 0)).map { index in
            let column = index % 4
            let row = index / 4
            let rowHeight: CGFloat = 0.058
            return RegionDefinition(
                key: "\(group).item.\(index)",
                group: group,
                regions: [
                    CGRect(
                        x: CGFloat(column) * 0.25,
                        y: min(0.98, startY + CGFloat(row) * rowHeight),
                        width: 0.25,
                        height: rowHeight + 0.035
                    )
                ]
            )
        }
    }

    private func textSampleMetrics(
        in regions: [CGRect],
        background: 沉浸详情背景色调,
        extendsThroughInformation: Bool
    ) -> TextSampleMetrics? {
        var metrics = TextSampleMetrics()

        for region in regions {
            let minX = max(0, Int((region.minX * CGFloat(width)).rounded(.down)))
            let maxX = min(width, Int((region.maxX * CGFloat(width)).rounded(.up)))
            let minY = max(0, Int((region.minY * CGFloat(height)).rounded(.down)))
            let maxY = min(height, Int((region.maxY * CGFloat(height)).rounded(.up)))
            guard minX < maxX, minY < maxY else { continue }

            for y in minY..<maxY {
                guard !Task.isCancelled else { return nil }
                for x in minX..<maxX {
                    let rawLuminance = Double(luminances[y * width + x]) / 255
                    let normalizedY = CGFloat(y) / CGFloat(max(height - 1, 1))
                    let heroOpacity = imageOpacity(
                        at: normalizedY,
                        extendsThroughInformation: extendsThroughInformation
                    )
                    let backdropImageWeight = 0.56 * (1 - 0.2)
                    let heroImageWeight = heroOpacity
                        + (1 - heroOpacity) * backdropImageWeight
                    let backgroundWeight = 1 - heroImageWeight
                    let luminance = rawLuminance * heroImageWeight
                        + background.luminance * backgroundWeight
                    record(
                        luminance,
                        rawLuminance: rawLuminance,
                        heroOpacity: heroOpacity,
                        in: &metrics
                    )
                }
            }
        }

        let sampleCount = metrics.lightBackgroundCount
            + metrics.darkBackgroundCount
        guard sampleCount > 0 else { return nil }
        return metrics
    }

    private func textSampleMetrics(
        inRenderedRegions regions: [CGRect],
        imageSize: CGSize,
        background: 沉浸详情背景色调,
        extendsThroughInformation: Bool
    ) -> TextSampleMetrics? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        var metrics = TextSampleMetrics()

        for region in regions where !region.isEmpty {
            let columnCount = max(
                4,
                min(48, Int((region.width / 4).rounded(.up)))
            )
            let rowCount = max(
                4,
                min(48, Int((region.height / 4).rounded(.up)))
            )

            for row in 0..<rowCount {
                guard !Task.isCancelled else { return nil }
                let renderedY = (
                    region.minY
                        + (CGFloat(row) + 0.5) / CGFloat(rowCount)
                            * region.height
                ) / imageSize.height
                for column in 0..<columnCount {
                    let renderedX = (
                        region.minX
                            + (CGFloat(column) + 0.5) / CGFloat(columnCount)
                                * region.width
                    ) / imageSize.width
                    guard let rawLuminance = luminance(
                        atRenderedX: renderedX,
                        y: renderedY,
                        imageSize: imageSize
                    ) else {
                        record(background.luminance, in: &metrics)
                        continue
                    }

                    let heroOpacity = imageOpacity(
                        at: renderedY,
                        extendsThroughInformation: extendsThroughInformation
                    )
                    let backdropImageWeight = 0.56 * (1 - 0.2)
                    let heroImageWeight = heroOpacity
                        + (1 - heroOpacity) * backdropImageWeight
                    let backgroundWeight = 1 - heroImageWeight
                    let luminance = rawLuminance * heroImageWeight
                        + background.luminance * backgroundWeight
                    record(
                        luminance,
                        rawLuminance: rawLuminance,
                        heroOpacity: heroOpacity,
                        in: &metrics
                    )
                }
            }
        }

        let sampleCount = metrics.lightBackgroundCount
            + metrics.darkBackgroundCount
        guard sampleCount > 0 else { return nil }
        return metrics
    }

    private func luminance(
        atRenderedX renderedX: CGFloat,
        y renderedY: CGFloat,
        imageSize: CGSize
    ) -> Double? {
        guard (0...1).contains(renderedX),
              (0...1).contains(renderedY) else {
            return nil
        }

        let sourceAspectRatio = CGFloat(width) / CGFloat(max(height, 1))
        let renderedAspectRatio = imageSize.width / imageSize.height
        var sourceX = renderedX
        var sourceY = renderedY

        if sourceAspectRatio > renderedAspectRatio {
            let visibleWidth = renderedAspectRatio / sourceAspectRatio
            sourceX = (1 - visibleWidth) / 2 + renderedX * visibleWidth
        } else if sourceAspectRatio < renderedAspectRatio {
            let visibleHeight = sourceAspectRatio / renderedAspectRatio
            sourceY = renderedY * visibleHeight
        }

        guard (0...1).contains(sourceX),
              (0...1).contains(sourceY) else {
            return nil
        }
        let x = min(width - 1, max(0, Int(sourceX * CGFloat(width))))
        let y = min(height - 1, max(0, Int(sourceY * CGFloat(height))))
        return Double(luminances[y * width + x]) / 255
    }

    private func record(
        _ luminance: Double,
        rawLuminance: Double? = nil,
        heroOpacity: Double = 0,
        in metrics: inout TextSampleMetrics
    ) {
        metrics.luminanceTotal += luminance
        if let rawLuminance,
           heroOpacity >= 沉浸玻璃色调阈值.最低封面不透明度 {
            metrics.tintCandidateSampleCount += 1
            if rawLuminance >= 沉浸玻璃色调阈值.接近白色亮度 {
                metrics.nearlyWhiteBackgroundCount += 1
            }
            if rawLuminance <= 沉浸玻璃色调阈值.接近黑色亮度 {
                metrics.nearlyBlackBackgroundCount += 1
            }
        }
        if luminance >= 0.18 {
            metrics.lightBackgroundCount += 1
        } else {
            metrics.darkBackgroundCount += 1
        }
    }

    private func imageOpacity(
        at location: CGFloat,
        extendsThroughInformation: Bool
    ) -> Double {
        let stops: [(location: CGFloat, opacity: Double)] =
            extendsThroughInformation
            ? [
                (0, 1),
                (0.5, 1),
                (0.62, 0.86),
                (0.76, 0.58),
                (0.86, 0.3),
                (0.95, 0.08),
                (1, 0)
            ]
            : [
                (0, 1),
                (0.46, 1),
                (0.58, 0.86),
                (0.7, 0.62),
                (0.82, 0.34),
                (0.91, 0.1),
                (0.97, 0),
                (1, 0)
            ]

        guard let upperIndex = stops.firstIndex(where: {
            $0.location >= location
        }) else {
            return stops.last?.opacity ?? 0
        }
        guard upperIndex > 0 else { return stops[upperIndex].opacity }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let span = max(upper.location - lower.location, 0.0001)
        let progress = (location - lower.location) / span
        return lower.opacity + (upper.opacity - lower.opacity) * Double(progress)
    }
}

nonisolated final class 沉浸封面文字分析缓存: @unchecked Sendable {
    static let shared = 沉浸封面文字分析缓存()

    private let lock = NSLock()
    private var maps: [String: 沉浸封面亮度图] = [:]
    private var preparationTasks: [
        String: Task<沉浸封面亮度图?, Never>
    ] = [:]

    nonisolated func containsMap(for url: URL) -> Bool {
        lock.withLock {
            maps[url.absoluteString] != nil
        }
    }

    nonisolated func textSamples(
        for url: URL,
        layout: 沉浸封面文字分析布局,
        background: 沉浸详情背景色调,
        extendsThroughInformation: Bool,
        itemCounts: [String: Int] = [:],
        geometry: 沉浸封面文字取样几何? = nil
    ) -> [String: 沉浸玻璃文字取样结果] {
        let map = lock.withLock {
            maps[url.absoluteString]
        }
        return map?.textSamples(
            for: layout,
            background: background,
            extendsThroughInformation: extendsThroughInformation,
            itemCounts: itemCounts,
            geometry: geometry
        ) ?? [:]
    }

    nonisolated func textSamplesAsync(
        for request: 沉浸封面文字取样请求
    ) async -> [String: 沉浸玻璃文字取样结果] {
        let map = lock.withLock {
            maps[request.url.absoluteString]
        }
        guard let map else { return [:] }

        let samplingTask = Task.detached(priority: .userInitiated) {
            map.textSamples(
                for: request.layout,
                background: request.background,
                extendsThroughInformation: request.extendsThroughInformation,
                itemCounts: request.itemCounts,
                geometry: request.geometry
            )
        }
        return await withTaskCancellationHandler {
            await samplingTask.value
        } onCancel: {
            samplingTask.cancel()
        }
    }

    nonisolated func prepare(data: Data, for url: URL) async {
        let key = url.absoluteString
        let task: Task<沉浸封面亮度图?, Never>? = lock.withLock {
            if maps[key] != nil {
                return nil
            }
            if let existing = preparationTasks[key] {
                return existing
            }
            let task = Task.detached(priority: .utility) {
                Self.makeLuminanceMap(from: data)
            }
            preparationTasks[key] = task
            return task
        }
        guard let task else { return }
        let map = await task.value

        lock.withLock {
            preparationTasks.removeValue(forKey: key)
            if maps[key] == nil, let map {
                maps[key] = map
            }
        }
    }

    nonisolated private static func makeLuminanceMap(
        from data: Data
    ) -> 沉浸封面亮度图? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 96
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options
        ) else {
            return nil
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let rendered = pixels.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.draw(
                image,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            return true
        }
        guard rendered else { return nil }

        var luminances = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = y * bytesPerRow + x * 4
                let red = linearized(Double(pixels[pixelIndex]) / 255)
                let green = linearized(Double(pixels[pixelIndex + 1]) / 255)
                let blue = linearized(Double(pixels[pixelIndex + 2]) / 255)
                let luminance = red * 0.2126
                    + green * 0.7152
                    + blue * 0.0722
                luminances[y * width + x] = UInt8(
                    max(0, min(255, Int((luminance * 255).rounded())))
                )
            }
        }
        return 沉浸封面亮度图(
            width: width,
            height: height,
            luminances: luminances
        )
    }

    nonisolated private static func linearized(_ component: Double) -> Double {
        if component <= 0.04045 {
            return component / 12.92
        }
        return pow((component + 0.055) / 1.055, 2.4)
    }
}

@MainActor
final class 模糊解除确认器: ObservableObject {
    @Published private(set) var pendingID: String?

    private var expirationTask: Task<Void, Never>?

    var isPromptVisible: Bool {
        pendingID != nil
    }

    func request(id: String, reveal: () -> Void) {
        guard 家长控制中心.shared.canRevealRestrictedContent else {
            cancel()
            return
        }

        if pendingID == id {
            expirationTask?.cancel()
            expirationTask = nil
            withAnimation(.easeInOut(duration: 0.18)) {
                pendingID = nil
            }
            reveal()
            return
        }

        expirationTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            pendingID = id
        }

        expirationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1.8))
            } catch {
                return
            }

            guard let self, self.pendingID == id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                self.pendingID = nil
            }
            self.expirationTask = nil
        }
    }

    func cancel() {
        expirationTask?.cancel()
        expirationTask = nil
        pendingID = nil
    }
}

struct 模糊解除提示: View {
    let isPresented: Bool

    var body: some View {
        if isPresented {
            Label(prompt, systemImage: "hand.tap")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .液态玻璃(.regular, in: Capsule())
                .transition(.opacity)
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private var prompt: LocalizedStringKey {
        "再次轻触以解除模糊"
    }
}

enum 标题语言: String, CaseIterable, Identifiable {
    case original = "原语言"
    case japanese = "日语"
    case chinese = "简体中文"
    case traditionalChinese = "繁体中文"
    case korean = "韩语"
    case english = "英语"
    case romanized = "罗马字"

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .original: return String(localized: "原语言")
        case .japanese: return String(localized: "日语")
        case .chinese: return String(localized: "简体中文")
        case .traditionalChinese: return String(localized: "繁体中文")
        case .korean: return String(localized: "韩语")
        case .english: return String(localized: "英语")
        case .romanized: return String(localized: "罗马字")
        }
    }

    var langCode: String? {
        switch self {
        case .original: return nil
        case .japanese: return "ja"
        case .chinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .korean: return "ko"
        case .english: return "en"
        case .romanized: return nil
        }
    }
}

enum 简介翻译语言: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case korean = "ko"

    var id: String { rawValue }

    var localeLanguage: Locale.Language {
        Locale.Language(identifier: rawValue)
    }

        var title: String {
            switch self {
            case .simplifiedChinese: return String(localized: "简体中文")
            case .traditionalChinese: return String(localized: "繁体中文")
            case .japanese: return String(localized: "日语")
            case .korean: return String(localized: "韩语")
            }
        }

        var locale: Locale {
            Locale(identifier: rawValue)
        }

        var supportsAutomaticMetadataTranslation: Bool {
            switch self {
            case .simplifiedChinese, .traditionalChinese, .japanese, .korean:
                return false
            }
        }
    }

    enum 制作人员语言: String, CaseIterable, Identifiable {
        case original = "原语言"
        case romaji = "罗马音/英语"

        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .original: return String(localized: "原语言")
            case .romaji: return String(localized: "英语")
            }
        }
    }

    enum 内容过滤模式: String, CaseIterable, Identifiable {
        case sexualOnly = "色情"
        case violenceOnly = "暴力"
        case both = "色情与暴力"

        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .sexualOnly: return String(localized: "色情")
            case .violenceOnly: return String(localized: "暴力")
            case .both: return String(localized: "色情与暴力")
            }
        }
    }

    enum 内容限制方式: String, CaseIterable, Identifiable {
        case hidden
        case blurred

        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .hidden: return String(localized: "隐藏")
            case .blurred: return String(localized: "模糊")
            }
        }
    }

    enum 强制内容安全策略 {
        static let 色情阈值 = 0.8
        static let 最大色情阈值 = 2.0

        static let 高级设置解锁键 = "contentSafetyAdvancedControlsUnlocked"
        private static var 禁止解锁Token: String? { 内容安全私有配置.禁止解锁Token }
        private static let 当前Token禁止键 = "contentSafetyUnlockBlockedForCurrentToken"

        static func 可使用高级设置(
            token: String? = nil,
            defaults: UserDefaults = .standard
        ) -> Bool {
            guard defaults.bool(forKey: 高级设置解锁键) else { return false }
            if let token {
                return token != 禁止解锁Token
            }
            return !defaults.bool(forKey: 当前Token禁止键)
        }

        static var 当前色情阈值上限: Double {
            可使用高级设置() ? 最大色情阈值 : 色情阈值
        }

        @discardableResult
        static func 尝试解锁(
            token: String,
            defaults: UserDefaults = .standard
        ) -> Bool {
            guard token != 禁止解锁Token else {
                应用到用户设置(defaults, token: token)
                return false
            }
            defaults.set(true, forKey: 高级设置解锁键)
            应用到用户设置(defaults, token: token)
            return true
        }

        static func 同步当前Token(
            _ token: String,
            defaults: UserDefaults = .standard
        ) {
            let isBlocked = token == 禁止解锁Token
            defaults.set(isBlocked, forKey: 当前Token禁止键)
            if isBlocked {
                应用到用户设置(defaults, token: token)
            }
        }

        static func 应用到用户设置(
            _ defaults: UserDefaults = .standard,
            保留更严格阈值: Bool = true,
            token: String? = nil
        ) {
            if 紧急回避设置.会话正在进行(defaults: defaults) {
                紧急回避设置.应用最严格限制(to: defaults)
                return
            }

            let allowsAdvancedSettings = 可使用高级设置(
                token: token,
                defaults: defaults
            )
            if !allowsAdvancedSettings,
               defaults.object(forKey: "contentFilterEnabled") as? Bool != true {
                defaults.set(true, forKey: "contentFilterEnabled")
            }

            let storedThreshold = 保留更严格阈值
                ? defaults.object(forKey: "sexualThreshold") as? Double
                : nil
            let thresholdLimit = allowsAdvancedSettings
                ? 最大色情阈值
                : 色情阈值
            let requiredThreshold = min(
                max(storedThreshold ?? 色情阈值, 0),
                thresholdLimit
            )
            if storedThreshold != requiredThreshold {
                defaults.set(requiredThreshold, forKey: "sexualThreshold")
            }

            let storedMode = defaults.string(forKey: "filterMode")
            if !内容过滤模式.allCases.contains(where: {
                $0.rawValue == storedMode
            }) {
                defaults.set(内容过滤模式.both.rawValue, forKey: "filterMode")
            }
        }
    }

    enum 内容安全高级设置解锁入口 {
        static var 角色ID: String? { 内容安全私有配置.解锁角色?.id }
        static var 固定角色结果: 角色搜索结果? { 内容安全私有配置.解锁角色 }

        static func 是触发搜索(_ query: String) -> Bool {
            guard let 搜索词 = 内容安全私有配置.解锁搜索词,
                  固定角色结果 != nil else { return false }
            return query.trimmingCharacters(in: .whitespacesAndNewlines) == 搜索词
        }

        static func 合并固定结果(
            _ results: [角色搜索结果],
            query: String
        ) -> [角色搜索结果] {
            guard 是触发搜索(query), let 固定角色结果 else { return results }
            return [固定角色结果] + results.filter { $0.id != 固定角色结果.id }
        }
    }

    private struct 详情内容限制方式覆盖键: EnvironmentKey {
        static let defaultValue: 内容限制方式? = nil
    }

    extension EnvironmentValues {
        var 详情内容限制方式覆盖: 内容限制方式? {
            get { self[详情内容限制方式覆盖键.self] }
            set { self[详情内容限制方式覆盖键.self] = newValue }
        }
    }

    private struct 不安全内容限制效果: ViewModifier {
        let isRestricted: Bool
        let method: 内容限制方式
        let blurRadius: CGFloat

        @ViewBuilder
        func body(content: Content) -> some View {
            if isRestricted && method == .hidden {
                content
                    .hidden()
                    .accessibilityHidden(true)
            } else {
                content
                    .blur(radius: isRestricted ? blurRadius : 0)
            }
        }
    }

    enum 内容安全限制判定 {
        static func 色情图片需要限制(
            sexual: Double?,
            enabled: Bool,
            sexualThreshold: Double,
            mode: 内容过滤模式
        ) -> Bool {
            guard 色情内容需要限制(enabled: enabled, mode: mode) else {
                return false
            }
            return (sexual ?? 0) > min(
                sexualThreshold,
                强制内容安全策略.当前色情阈值上限
            )
        }

        static func 图片允许手动解除模糊(
            sexual: Double?,
            enabled: Bool,
            sexualThreshold: Double,
            mode: 内容过滤模式,
            defaults: UserDefaults = .standard
        ) -> Bool {
            允许手动解除模糊(
                色情限制: 色情图片需要限制(
                    sexual: sexual,
                    enabled: enabled,
                    sexualThreshold: sexualThreshold,
                    mode: mode
                ),
                defaults: defaults
            )
        }

        static func 允许手动解除模糊(
            色情限制: Bool,
            defaults: UserDefaults = .standard
        ) -> Bool {
            !色情限制 || 强制内容安全策略.可使用高级设置(defaults: defaults)
        }

        static func 色情标签需要限制(
            _ isAdultContent: Bool,
            enabled: Bool,
            mode: 内容过滤模式
        ) -> Bool {
            isAdultContent && 色情内容需要限制(enabled: enabled, mode: mode)
        }

        static func 色情特征需要限制(
            _ isSexual: Bool?,
            enabled: Bool,
            mode: 内容过滤模式
        ) -> Bool {
            isSexual == true && 色情内容需要限制(
                enabled: enabled,
                mode: mode
            )
        }

        static func 图片需要限制(
            sexual: Double?,
            violence: Double?,
            enabled: Bool,
            sexualThreshold: Double,
            violenceThreshold: Double,
            mode: 内容过滤模式
        ) -> Bool {
            let sexualRestricted = 色情图片需要限制(
                sexual: sexual,
                enabled: enabled,
                sexualThreshold: sexualThreshold,
                mode: mode
            )
            guard enabled else { return false }
            let violenceValue = violence ?? 0

            switch mode {
            case .sexualOnly:
                return sexualRestricted
            case .violenceOnly:
                return violenceValue > violenceThreshold
            case .both:
                return sexualRestricted || violenceValue > violenceThreshold
            }
        }

        static func 视觉小说需要限制(
            _ item: 视觉小说搜索结果,
            enabled: Bool,
            sexualThreshold: Double,
            violenceThreshold: Double,
            mode: 内容过滤模式
        ) -> Bool {
            if 图片需要限制(
                sexual: item.image?.sexual,
                violence: item.image?.violence,
                enabled: enabled,
                sexualThreshold: sexualThreshold,
                violenceThreshold: violenceThreshold,
                mode: mode
            ) {
                return true
            }

            return 色情内容需要限制(enabled: enabled, mode: mode)
                && item.tags?.contains(where: \.isAdultContent) == true
        }

        private static func 色情内容需要限制(
            enabled: Bool,
            mode: 内容过滤模式
        ) -> Bool {
            enabled && mode != .violenceOnly
        }
    }

    extension View {
        func 应用不安全内容限制(
            _ isRestricted: Bool,
            method: 内容限制方式,
            blurRadius: CGFloat
        ) -> some View {
            modifier(
                不安全内容限制效果(
                    isRestricted: isRestricted,
                    method: method,
                    blurRadius: blurRadius
                )
            )
        }
    }

    enum 副标题语言: String, CaseIterable, Identifiable {
        case none = "无"
        case original = "原语言"
        case japanese = "日语"
        case chinese = "简体中文"
        case traditionalChinese = "繁体中文"
        case korean = "韩语"
        case english = "英语"
        case romanized = "罗马字"

        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .none: return String(localized: "无")
            case .original: return String(localized: "原语言")
            case .japanese: return String(localized: "日语")
            case .chinese: return String(localized: "简体中文")
            case .traditionalChinese: return String(localized: "繁体中文")
            case .korean: return String(localized: "韩语")
            case .english: return String(localized: "英语")
            case .romanized: return String(localized: "罗马字")
            }
        }

        var langCode: String? {
            switch self {
            case .none, .original: return nil
            case .chinese: return "zh-Hans"
            case .traditionalChinese: return "zh-Hant"
            case .korean: return "ko"
            case .english: return "en"
            case .japanese: return "ja"
            case .romanized: return nil
            }
        }

        var 对应的标题语言: 标题语言 {
            switch self {
            case .none, .original: return .original
            case .chinese: return .chinese
            case .traditionalChinese: return .traditionalChinese
            case .korean: return .korean
            case .english: return .english
            case .japanese: return .japanese
            case .romanized: return .romanized
            }
        }
    }

    struct 人物名称工具 {
        static func 显示名称(name: String, original: String?, 偏好: 制作人员语言) -> String {
            if 偏好 == .original,
               let original,
               !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return original
            }
            return name
        }

        static func 备用名称(name: String, original: String?, 偏好: 制作人员语言) -> String? {
            guard let original, !original.isEmpty, original != name else { return nil }
            return 偏好 == .original ? name : original
        }

        static func 生成富文本(
            name: String,
            original: String?,
            偏好: 制作人员语言,
            基础大小: CGFloat,
            系统字体粗细: Font.Weight? = nil
        ) -> AttributedString {
            标题工具.生成富文本(
                文本: 显示名称(name: name, original: original, 偏好: 偏好),
                isJapanese: 偏好 == .original,
                基础大小: 基础大小,
                日文字体名称: "HiraginoSans-W4",
                系统字体粗细: 系统字体粗细,
                语言来源已知: false,
                空格视为日语: true
            )
        }

    }

    struct VNDB显示工具 {
        static func 平台名称(
            _ code: String,
            fallbackName: String? = nil
        ) -> String {
            switch code.lowercased() {
            case "win": return String(localized: "Windows")
            case "mac": return String(localized: "macOS")
            case "lin": return String(localized: "Linux")
            case "ios": return String(localized: "iOS")
            case "and": return String(localized: "Android")
            case "web": return String(localized: "网页")
            case "dos": return String(localized: "DOS")
            case "switch": return String(localized: "Nintendo Switch")
            case "ps5": return String(localized: "PlayStation 5")
            case "ps4": return String(localized: "PlayStation 4")
            case "ps3": return String(localized: "PlayStation 3")
            case "ps2": return String(localized: "PlayStation 2")
            case "ps1": return String(localized: "PlayStation")
            case "psv": return String(localized: "PlayStation Vita")
            case "psp": return String(localized: "PSP")
            case "xboxx": return String(localized: "Xbox Series")
            case "xone": return String(localized: "Xbox One")
            case "x360": return String(localized: "Xbox 360")
            case "n3ds": return String(localized: "Nintendo 3DS")
            case "nds": return String(localized: "Nintendo DS")
            case "wiiu": return String(localized: "Wii U")
            case "wii": return String(localized: "Wii")
            case "dc": return String(localized: "Dreamcast")
            case "sat": return String(localized: "Sega Saturn")
            case "sfc": return String(localized: "Super Nintendo")
            case "nes": return String(localized: "Nintendo Entertainment System")
            case "gba": return String(localized: "Game Boy Advance")
            case "gbc": return String(localized: "Game Boy Color")
            case "pce": return String(localized: "PC Engine")
            case "pcfx": return String(localized: "PC-FX")
            case "p98": return String(localized: "PC-98")
            case "p88": return String(localized: "PC-88")
            case "fmt": return String(localized: "FM Towns")
            case "msx": return String(localized: "MSX")
            case "x68": return String(localized: "Sharp X68000")
            case "ws": return String(localized: "WonderSwan")
            case "ngp": return String(localized: "Neo Geo Pocket")
            case "dvd": return String(localized: "DVD Player")
            case "bdp": return String(localized: "Blu-ray Player")
            default:
                if let fallbackName, !fallbackName.isEmpty {
                    return fallbackName
                }
                return code.uppercased()
            }
        }

        static func 平台图标(_ code: String) -> String {
            switch code.lowercased() {
            case "win", "mac", "lin", "dos", "p98", "p88", "fmt", "msx", "x68":
                return "desktopcomputer"
            case "ios":
                return "iphone.gen3"
            case "and":
                return "rectangle.portrait"
            case "web":
                return "globe"
            case "switch", "psv", "psp", "n3ds", "nds", "gba", "gbc", "ws", "ngp":
                return "handheld"
            case "ps5", "ps4", "ps3", "ps2", "ps1":
                return "playstation.logo"
            case "xboxx", "xone", "x360":
                return "xbox.logo"
            case "wiiu", "wii", "dc", "sat", "sfc", "nes", "pce", "pcfx":
                return "gamecontroller"
            case "dvd", "bdp":
                return "opticaldisc"
            default:
                return "display"
            }
        }

        static func 语言名称(
            _ code: String,
            fallbackName: String? = nil
        ) -> String {
            switch code.lowercased() {
            case "ar": return String(localized: "阿拉伯语")
            case "bg": return String(localized: "保加利亚语")
            case "ca": return String(localized: "加泰罗尼亚语")
            case "ck", "chr": return String(localized: "切罗基语")
            case "cs": return String(localized: "捷克语")
            case "da": return String(localized: "丹麦语")
            case "de": return String(localized: "德语")
            case "el": return String(localized: "希腊语")
            case "en": return String(localized: "英语")
            case "eo": return String(localized: "世界语")
            case "es": return String(localized: "西班牙语")
            case "eu": return String(localized: "巴斯克语")
            case "fa": return String(localized: "波斯语")
            case "fi": return String(localized: "芬兰语")
            case "fr": return String(localized: "法语")
            case "ga": return String(localized: "爱尔兰语")
            case "he": return String(localized: "希伯来语")
            case "hi": return String(localized: "印地语")
            case "hr": return String(localized: "克罗地亚语")
            case "hu": return String(localized: "匈牙利语")
            case "id": return String(localized: "印度尼西亚语")
            case "it": return String(localized: "意大利语")
            case "ja": return String(localized: "日语")
            case "ko": return String(localized: "韩语")
            case "lt": return String(localized: "立陶宛语")
            case "lv": return String(localized: "拉脱维亚语")
            case "ms": return String(localized: "马来语")
            case "nl": return String(localized: "荷兰语")
            case "no": return String(localized: "挪威语")
            case "pl": return String(localized: "波兰语")
            case "pt-br": return String(localized: "巴西葡萄牙语")
            case "pt-pt", "pt": return String(localized: "葡萄牙语")
            case "ro": return String(localized: "罗马尼亚语")
            case "ru": return String(localized: "俄语")
            case "sk": return String(localized: "斯洛伐克语")
            case "sl": return String(localized: "斯洛文尼亚语")
            case "sr": return String(localized: "塞尔维亚语")
            case "sv": return String(localized: "瑞典语")
            case "ta": return String(localized: "泰米尔语")
            case "th": return String(localized: "泰语")
            case "tr": return String(localized: "土耳其语")
            case "uk": return String(localized: "乌克兰语")
            case "ur": return String(localized: "乌尔都语")
            case "vi": return String(localized: "越南语")
            case "zh", "zh-hans": return String(localized: "简体中文")
            case "zh-hant": return String(localized: "繁体中文")
            default:
                return Locale.current.localizedString(forLanguageCode: code)
                ?? Locale.current.localizedString(forIdentifier: code)
                ?? fallbackName
                ?? code
            }
        }

        static func 声优语言名称(_ value: String) -> String {
            let normalized = value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")

            let languageCodes: [String: String] = [
                "arabic": "ar", "bulgarian": "bg", "catalan": "ca",
                "czech": "cs", "danish": "da", "german": "de",
                "greek": "el", "english": "en", "esperanto": "eo",
                "spanish": "es", "basque": "eu", "persian": "fa",
                "farsi": "fa", "finnish": "fi", "french": "fr",
                "irish": "ga", "hebrew": "he", "hindi": "hi",
                "croatian": "hr", "hungarian": "hu", "indonesian": "id",
                "italian": "it", "japanese": "ja", "korean": "ko",
                "lithuanian": "lt", "latvian": "lv", "malay": "ms",
                "dutch": "nl", "norwegian": "no", "polish": "pl",
                "portuguese": "pt", "romanian": "ro", "russian": "ru",
                "slovak": "sk", "slovenian": "sl", "serbian": "sr",
                "swedish": "sv", "tamil": "ta", "thai": "th",
                "turkish": "tr", "ukrainian": "uk", "urdu": "ur",
                "vietnamese": "vi"
            ]

            switch normalized {
            case "chinese", "mandarin", "mandarin chinese", "zh", "zh-cn",
                "zh-hans":
                return String(localized: "普通话")
            case "traditional chinese", "cantonese", "zh-tw", "zh-hant":
                return String(localized: "繁体中文")
            default:
                if let code = languageCodes[normalized] {
                    return 语言名称(code)
                }
                return value
            }
        }

    }

    struct 视觉小说标签类别样式 {
        let title: String
        let systemImage: String
        let color: Color

        init(category: String?) {
            switch category {
            case "ero":
                title = String(localized: "色情")
                systemImage = "exclamationmark.triangle.fill"
                color = .pink
            case "tech":
                title = String(localized: "技术")
                systemImage = "gearshape.fill"
                color = .secondary
            default:
                title = String(localized: "内容")
                systemImage = "book.pages.fill"
                color = .accentColor
            }
        }

        init(_ category: 探索标签类别) {
            self.init(category: category.rawValue)
        }
    }

    struct 视觉小说标签胶囊: View {
        let tag: 视觉小说标签
        let text: String
        var isBlurred = false
        var isHidden = false
        var showsRating = false

        private var categoryStyle: 视觉小说标签类别样式 {
            视觉小说标签类别样式(category: tag.category)
        }

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: categoryStyle.systemImage)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(categoryStyle.color)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if showsRating {
                        Text("权重\(tag.rating, specifier: "%.1f")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, showsRating ? 7 : 6)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(categoryStyle.color.opacity(0.28), lineWidth: 0.75)
            }
            .compositingGroup()
            .blur(radius: isBlurred ? 5 : 0)
            .opacity(isBlurred ? 0.72 : 1)
            .应用不安全内容限制(
                isHidden,
                method: .hidden,
                blurRadius: 0
            )
            .animation(.easeInOut(duration: 0.28), value: isBlurred)
            .animation(.easeInOut(duration: 0.28), value: isHidden)
            .accessibilityLabel(
                isHidden ? Text("内容已隐藏") : Text(verbatim: text)
            )
        }
    }

    enum VNDB标签人工翻译 {
        private static let 日语人工译文表 = 读取人工译文表(target: .japanese)
        private static let 简体中文人工译文表 = 读取人工译文表(target: .simplifiedChinese)
        private static let 繁体中文人工译文表 = 读取人工译文表(target: .traditionalChinese)
        private static let 韩语人工译文表 = 读取人工译文表(target: .korean)

        static func 界面译文(for tag: 视觉小说标签) -> String? {
            guard let language = VNDB人工译文界面语言.current else {
                return nil
            }

            switch language {
            case .english:
                return tag.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : tag.name
            case .japanese:
                return 译文(for: tag, target: .japanese)
            case .simplifiedChinese:
                return 译文(for: tag, target: .simplifiedChinese)
            case .traditionalChinese:
                return 译文(for: tag, target: .traditionalChinese)
            case .korean:
                return 译文(for: tag, target: .korean)
            }
        }

        static func 译文(
            for tag: 视觉小说标签,
            target: 简介翻译语言
        ) -> String? {
            let key = tag.name == "Type" ? "Type_tag" : tag.name

            if let value = 人工译文表(target: target)[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }

            let localized = String(
                localized: String.LocalizationValue(key),
                table: "VNDBTags",
                bundle: .main,
                locale: target.locale
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !localized.isEmpty, localized != key, localized != tag.name else {
                return nil
            }

            return localized
        }

        private static func 人工译文表(
            target: 简介翻译语言
        ) -> [String: String] {
            switch target {
            case .japanese:
                return 日语人工译文表
            case .simplifiedChinese:
                return 简体中文人工译文表
            case .traditionalChinese:
                return 繁体中文人工译文表
            case .korean:
                return 韩语人工译文表
            }
        }

        private static func 读取人工译文表(
            target: 简介翻译语言
        ) -> [String: String] {
            guard
                let localizationPath = Bundle.main.path(
                    forResource: target.rawValue,
                    ofType: "lproj"
                ),
                let localizedBundle = Bundle(path: localizationPath),
                let tableURL = localizedBundle.url(
                    forResource: "VNDBTags",
                    withExtension: "strings"
                ),
                let data = try? Data(contentsOf: tableURL),
                let propertyList = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ),
                let table = propertyList as? [String: String]
            else {
                return [:]
            }

            return table
        }
    }

    enum VNDB特征人工翻译 {
        private static let 日语人工译文表 = 读取人工译文表(target: .japanese)
        private static let 简体中文人工译文表 = 读取人工译文表(target: .simplifiedChinese)
        private static let 繁体中文人工译文表 = 读取人工译文表(target: .traditionalChinese)
        private static let 韩语人工译文表 = 读取人工译文表(target: .korean)

        static func 界面译文(_ source: String) -> String? {
            guard let language = VNDB人工译文界面语言.current else {
                return nil
            }

            switch language {
            case .english:
                return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : source
            case .japanese:
                return 译文(source, target: .japanese)
            case .simplifiedChinese:
                return 译文(source, target: .simplifiedChinese)
            case .traditionalChinese:
                return 译文(source, target: .traditionalChinese)
            case .korean:
                return 译文(source, target: .korean)
            }
        }

        static func 译文(
            _ source: String,
            target: 简介翻译语言
        ) -> String? {
            let key = "trait.\(source)"

            if let value = 人工译文表(target: target)[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }

            let localized = String(
                localized: String.LocalizationValue(key),
                table: "VNDBTraits",
                bundle: .main,
                locale: target.locale
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !localized.isEmpty, localized != key, localized != source else {
                return nil
            }
            return localized
        }

        private static func 人工译文表(
            target: 简介翻译语言
        ) -> [String: String] {
            switch target {
            case .japanese:
                return 日语人工译文表
            case .simplifiedChinese:
                return 简体中文人工译文表
            case .traditionalChinese:
                return 繁体中文人工译文表
            case .korean:
                return 韩语人工译文表
            }
        }

        private static func 读取人工译文表(
            target: 简介翻译语言
        ) -> [String: String] {
            guard
                let localizationPath = Bundle.main.path(
                    forResource: target.rawValue,
                    ofType: "lproj"
                ),
                let localizedBundle = Bundle(path: localizationPath),
                let tableURL = localizedBundle.url(
                    forResource: "VNDBTraits",
                    withExtension: "strings"
                ),
                let data = try? Data(contentsOf: tableURL),
                let propertyList = try? PropertyListSerialization.propertyList(
                    from: data,
                    options: [],
                    format: nil
                ),
                let table = propertyList as? [String: String]
            else {
                return [:]
            }

            return table
        }
    }

    private enum VNDB人工译文界面语言 {
        case english
        case japanese
        case simplifiedChinese
        case traditionalChinese
        case korean

        static var current: Self? {
            guard let identifier = Bundle.main.preferredLocalizations.first?
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            else {
                return nil
            }

            if identifier == "en" || identifier.hasPrefix("en-") {
                return .english
            }
            if identifier == "ja" || identifier.hasPrefix("ja-") {
                return .japanese
            }
            if identifier == "zh-hans" || identifier.hasPrefix("zh-hans-") {
                return .simplifiedChinese
            }
            if identifier == "zh-hant" || identifier.hasPrefix("zh-hant-") {
                return .traditionalChinese
            }
            if identifier == "ko" || identifier.hasPrefix("ko-") {
                return .korean
            }
            return nil
        }
    }

struct 标题工具 {
    struct 标题结果 {
        let text: String
        let isJapanese: Bool
        let languageCode: String?

        init(
            text: String,
            isJapanese: Bool,
            languageCode: String? = nil
        ) {
            self.text = text
            self.isJapanese = isJapanese
            self.languageCode = languageCode
        }
    }

    static func 获取主标题(
        titles: [用户多语言标题]?,
        defaultTitle: String,
        偏好: 标题语言,
        回退: 标题语言,
        允许非官方: Bool = false
    ) -> 标题结果 {
        if let title = 查找标题(
            titles: titles,
            lang: 偏好,
            允许非官方: 允许非官方
        ) {
            return title
        }
        if let title = 查找标题(
            titles: titles,
            lang: 回退,
            允许非官方: 允许非官方
        ) {
            return title
        }
        return 标题结果(
            text: defaultTitle,
            isJapanese: requiresJapaneseFont(defaultTitle),
            languageCode: requiresJapaneseFont(defaultTitle) ? "ja" : nil
        )
    }

    static func 获取副标题(
        titles: [用户多语言标题]?,
        defaultTitle: String,
        偏好: 标题语言,
        回退: 标题语言,
        副标题设置: 副标题语言,
        允许非官方: Bool = false
    ) -> 标题结果? {
        guard let titles else { return nil }

        let result: 标题结果?
        switch 副标题设置 {
        case .none: return nil
        case .original:
            result = 查找标题(
                titles: titles,
                lang: .original,
                允许非官方: 允许非官方
            )
        case .chinese:
            result = 查找标题(
                titles: titles,
                lang: .chinese,
                允许非官方: 允许非官方
            )
        case .traditionalChinese:
            result = 查找标题(
                titles: titles,
                lang: .traditionalChinese,
                允许非官方: 允许非官方
            )
        case .korean:
            result = 查找标题(
                titles: titles,
                lang: .korean,
                允许非官方: 允许非官方
            )
        case .english:
            result = 查找标题(
                titles: titles,
                lang: .english,
                允许非官方: 允许非官方
            )
        case .japanese:
            result = 查找标题(
                titles: titles,
                lang: .japanese,
                允许非官方: 允许非官方
            )
        case .romanized:
            result = 查找标题(
                titles: titles,
                lang: .romanized,
                允许非官方: 允许非官方
            )
        }

        guard let result else { return nil }
        let main = 获取主标题(
            titles: titles,
            defaultTitle: defaultTitle,
            偏好: 偏好,
            回退: 回退,
            允许非官方: 允许非官方
        )
        return main.text == result.text ? nil : result
    }

    private static func 查找标题(
        titles: [用户多语言标题]?,
        lang: 标题语言,
        允许非官方: Bool
    ) -> 标题结果? {
        guard let titles else { return nil }

        if lang == .original {
            if let main = titles.first(where: {
                $0.main && (允许非官方 || $0.official)
            }) {
                return 标题结果(
                    text: main.title,
                    isJapanese: main.lang == "ja",
                    languageCode: main.lang
                )
            }
            if let first = titles.first(where: {
                允许非官方 || $0.official
            }) {
                return 标题结果(
                    text: first.title,
                    isJapanese: first.lang == "ja",
                    languageCode: first.lang
                )
            }
            return nil
        }

        if lang == .romanized {
            let candidates = titles.filter {
                允许非官方 || $0.official
            }
            let match = candidates.first(where: {
                $0.main && !($0.latin ?? "").isEmpty
            }) ?? candidates.first(where: {
                !($0.latin ?? "").isEmpty
            })
            guard let romanized = match?.latin,
                  !romanized.trimmingCharacters(
                    in: .whitespacesAndNewlines
                  ).isEmpty else {
                return nil
            }
            return 标题结果(
                text: romanized,
                isJapanese: false,
                languageCode: nil
            )
        }

        guard let match = titles.first(where: {
            $0.lang == lang.langCode && (允许非官方 || $0.official)
        }) else {
            return nil
        }
        return 标题结果(
            text: match.title,
            isJapanese: match.lang == "ja",
            languageCode: match.lang
        )
    }

    static func 生成富文本(
        文本: String,
        isJapanese: Bool,
        基础大小: CGFloat,
        是粗体: Bool = false,
        日文字体名称: String = "HiraginoSans-W5",
        系统字体粗细: Font.Weight? = nil,
        语言来源已知: Bool = true,
        空格视为日语: Bool = false,
        语言代码: String? = nil
    ) -> AttributedString {
        生成富文本(
            文本: 文本,
            isJapanese: isJapanese,
            基础大小: 基础大小,
            是粗体: 是粗体,
            日文字体名称: 日文字体名称,
            系统字体粗细: 系统字体粗细,
            语言来源已知: 语言来源已知,
            空格视为日语: 空格视为日语,
            语言代码: 语言代码,
            精确字号: false
        )
    }

    static func 生成富文本(
        文本: String,
        isJapanese: Bool,
        基础大小: CGFloat,
        是粗体: Bool = false,
        日文字体名称: String = "HiraginoSans-W5",
        系统字体粗细: Font.Weight? = nil,
        语言来源已知: Bool = true,
        空格视为日语: Bool = false,
        语言代码: String? = nil,
        精确字号: Bool,
        辅助功能粗体: Bool = false
    ) -> AttributedString {
        var attributed = AttributedString(文本)
        let defaultWeight = 系统字体粗细 ?? (是粗体 ? .semibold : .regular)
        let textStyle = textStyle(for: 基础大小)
        let makeFont: (Font.Weight) -> Font = { weight in
            精确字号
                ? .system(size: 基础大小, weight: weight)
                : .system(textStyle, weight: weight)
        }
        let defaultFont = makeFont(defaultWeight)
        let normalizedLanguageCode = normalizedLanguageCode(语言代码)
        let sharedHanName = 语言代码 == nil
            && 空格视为日语
            && isSharedHanName(文本)
        let hanNameHasInternalWhitespace = 语言代码 == nil
            && 空格视为日语
            && isHanOnlyNameTextWithInternalWhitespace(文本)
        let hanNameIsChinese = sharedHanName
            && (
                !containsInternalWhitespace(文本)
                || spacedHanNameShouldUseChineseTypography(文本)
            )
        let spacedHanNameSuggestsJapanese = hanNameHasInternalWhitespace
            && !hanNameIsChinese
        let effectiveIsJapanese = (isJapanese && !hanNameIsChinese)
            || spacedHanNameSuggestsJapanese
        let usesJapaneseTypography = normalizedLanguageCode.map {
            $0 == "ja" || $0.hasPrefix("ja-")
        } ?? effectiveIsJapanese

        attributed.font = defaultFont

        if usesJapaneseTypography,
           (
               语言来源已知
               || requiresJapaneseFont(文本)
               || spacedHanNameSuggestsJapanese
           ) {
            let resolvedJapaneseFontName = 辅助功能粗体
                ? japaneseFontName(
                    for: 日文字体名称,
                    boldText: true
                )
                : 日文字体名称
            let japaneseFont = 精确字号
                ? Font.custom(resolvedJapaneseFontName, fixedSize: 基础大小)
                : makeFont(japaneseWeight(for: 日文字体名称))
            applyTypography(
                languageIdentifier: "ja",
                font: japaneseFont,
                to: "[\\p{Han}\\p{Hiragana}\\p{Katakana}]",
                in: 文本,
                attributed: &attributed
            )
            return attributed
        }

        guard let chineseLanguageIdentifier = chineseLanguageIdentifier(
                  languageCode: normalizedLanguageCode,
                  isJapanese: effectiveIsJapanese,
                  text: 文本
              ) else {
            return attributed
        }

        let chineseFont = 精确字号
            ? chineseFontName(
                languageCode: normalizedLanguageCode,
                isJapanese: effectiveIsJapanese,
                text: 文本,
                weight: 辅助功能粗体
                    ? boldTextWeight(for: defaultWeight)
                    : defaultWeight
            ).map { Font.custom($0, fixedSize: 基础大小) }
            : nil

        applyTypography(
            languageIdentifier: chineseLanguageIdentifier,
            font: chineseFont,
            to: "[\\p{Han}]",
            in: 文本,
            attributed: &attributed
        )
        return attributed
    }

    static func 生成格式化标题富文本(
        格式: String,
        标题: 标题结果,
        基础大小: CGFloat,
        是粗体: Bool = false
    ) -> AttributedString {
        let surroundingFont = Font.system(
            textStyle(for: 基础大小),
            weight: 是粗体 ? .semibold : .regular
        )

        guard let placeholderRange = 格式.range(of: "%@") else {
            var fallback = AttributedString(格式)
            fallback.font = surroundingFont
            return fallback
        }

        var result = AttributedString(格式[..<placeholderRange.lowerBound])
        result.font = surroundingFont
        result += 生成富文本(
            文本: 标题.text,
            isJapanese: 标题.isJapanese,
            基础大小: 基础大小,
            是粗体: 是粗体,
            语言代码: 标题.languageCode
        )

        var suffix = AttributedString(格式[placeholderRange.upperBound...])
        suffix.font = surroundingFont
        result += suffix
        return result
    }

    private static var isJapaneseInterfaceLanguage: Bool {
        let identifiers = [
            Bundle.main.preferredLocalizations.first,
            Locale.preferredLanguages.first,
            Locale.current.language.languageCode?.identifier
        ]
        return identifiers.compactMap { $0 }.contains { identifier in
            let normalized = identifier
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            return normalized == "ja" || normalized.hasPrefix("ja-")
        }
    }

    private static func normalizedLanguageCode(_ code: String?) -> String? {
        guard let code else { return nil }
        return code
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private static func chineseLanguageIdentifier(
        languageCode: String?,
        isJapanese: Bool,
        text: String
    ) -> String? {
        if let languageCode {
            guard languageCode == "zh" || languageCode.hasPrefix("zh-") else {
                return nil
            }
            return languageCode.contains("hant") ? "zh-Hant" : "zh-Hans"
        }

        guard isJapaneseInterfaceLanguage,
              !isJapanese,
              containsHan(text),
              !requiresJapaneseFont(text) else {
            return nil
        }
        return "zh-Hans"
    }

    private static func chineseFontName(
        languageCode: String?,
        isJapanese: Bool,
        text: String,
        weight: Font.Weight
    ) -> String? {
        let family: String
        if let languageCode {
            guard languageCode == "zh" || languageCode.hasPrefix("zh-") else {
                return nil
            }
            family = languageCode.contains("hant")
                ? "PingFangTC"
                : "PingFangSC"
        } else {
            guard !isJapanese,
                  containsHan(text),
                  !requiresJapaneseFont(text) else {
                return nil
            }
            family = "PingFangSC"
        }

        let weightName = pingFangWeightName(
            weight,
            isSimplifiedChinese: family == "PingFangSC"
        )
        return "\(family)-\(weightName)"
    }

    private static func pingFangWeightName(
        _ weight: Font.Weight,
        isSimplifiedChinese: Bool
    ) -> String {
        if isSimplifiedChinese {
            switch weight {
            case .ultraLight: return "Ultralight"
            case .thin: return "Thin"
            case .light: return "Light"
            case .medium: return "Medium"
            case .semibold, .bold, .heavy, .black: return "Semibold"
            default: return "Regular"
            }
        }

        switch weight {
        case .ultraLight: return "Ultralight"
        case .thin: return "Thin"
        case .light: return "Light"
        case .medium: return "Regular"
        case .semibold, .bold: return "Medium"
        case .heavy, .black: return "Semibold"
        default: return "Regular"
        }
    }

    private static func boldTextWeight(for weight: Font.Weight) -> Font.Weight {
        switch weight {
        case .ultraLight, .thin, .light, .regular: .semibold
        case .medium: .bold
        case .semibold, .bold: .heavy
        case .heavy, .black: .black
        default: .semibold
        }
    }

    private static func textStyle(for baseSize: CGFloat) -> Font.TextStyle {
        switch baseSize {
        case ..<11.5: .caption2
        case ..<12.5: .caption
        case ..<13.5: .footnote
        case ..<15.5: .subheadline
        case ..<16.5: .callout
        case ..<18.5: .body
        case ..<21: .title3
        case ..<25.5: .title2
        case ..<31: .title
        default: .largeTitle
        }
    }

    private static func japaneseWeight(
        for fontName: String
    ) -> Font.Weight {
        switch fontName.split(separator: "-").last {
        case "W1", "W2": .light
        case "W3", "W4": .regular
        case "W5": .medium
        case "W6": .semibold
        case "W7": .bold
        case "W8": .heavy
        case "W9": .black
        default: .regular
        }
    }

    private static func japaneseFontName(
        for fontName: String,
        boldText: Bool
    ) -> String {
        guard boldText else { return fontName }

        var components = fontName.split(separator: "-")
        guard let weightComponent = components.popLast(),
              weightComponent.first == "W",
              let weight = Int(weightComponent.dropFirst()) else {
            return fontName
        }

        components.append(Substring("W\(min(weight + 1, 9))"))
        return components.joined(separator: "-")
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            isHanScalar(scalar)
        }
    }

    private static func isSharedHanName(_ text: String) -> Bool {
        guard isHanOnlyNameText(text),
              !requiresJapaneseFont(text) else {
            return false
        }

        return true
    }

    private static func isHanOnlyNameText(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        return !scalars.isEmpty
            && scalars.contains(where: isHanScalar)
            && scalars.allSatisfy(isHanScalar)
    }

    private static func isHanOnlyNameTextWithInternalWhitespace(
        _ text: String
    ) -> Bool {
        containsInternalWhitespace(text) && isHanOnlyNameText(text)
    }

    private static func spacedHanNameShouldUseChineseTypography(
        _ text: String
    ) -> Bool {
        guard containsInternalWhitespace(text) else {
            return false
        }

        let components = text.split(whereSeparator: \.isWhitespace)
        guard components.count == 2,
              components.allSatisfy({ component in
                  !component.isEmpty
                      && component.unicodeScalars.allSatisfy(isHanScalar)
              }) else {
            return false
        }

        let lengths = components.map { $0.unicodeScalars.count }
        return lengths == [1, 2] || lengths == [2, 2]
    }

    private static func isHanScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0xF900...0xFAFF,
             0x20000...0x2FA1F:
            true
        default:
            false
        }
    }

    static func 日文句子需要中文字体(
        _ 句子: Substring,
        日文字体名称: String
    ) -> Bool {
        let 字体 = CTFontCreateWithName(日文字体名称 as CFString, 17, nil)
        var 字符: [UniChar] = []
        var 汉字索引: [Int] = []
        var UTF16位置 = 0

        for 标量 in 句子.unicodeScalars {
            let 标量字符 = Array(String(标量).utf16)
            if isHanScalar(标量) {
                汉字索引.append(contentsOf: 标量字符.indices.map { UTF16位置 + $0 })
            }
            字符.append(contentsOf: 标量字符)
            UTF16位置 += 标量字符.count
        }

        guard !字符.isEmpty, !汉字索引.isEmpty else { return false }
        var 字形 = [CGGlyph](repeating: 0, count: 字符.count)
        _ = 字符.withUnsafeBufferPointer { 字符指针 in
            字形.withUnsafeMutableBufferPointer { 字形指针 in
                guard let 字符地址 = 字符指针.baseAddress,
                      let 字形地址 = 字形指针.baseAddress else {
                    return false
                }
                return CTFontGetGlyphsForCharacters(
                    字体,
                    字符地址,
                    字形地址,
                    字符.count
                )
            }
        }
        return 汉字索引.contains { 字形[$0] == 0 }
    }

    private static func applyTypography(
        languageIdentifier: String,
        font: Font?,
        to pattern: String,
        in text: String,
        attributed: inout AttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let nsString = text as NSString
        for match in regex.matches(
            in: text,
            range: NSRange(location: 0, length: nsString.length)
        ) {
            if let range = Range(match.range, in: attributed) {
                attributed[range].languageIdentifier = languageIdentifier
                if let font {
                    attributed[range].font = font
                }
            }
        }
    }

    private static func requiresJapaneseFont(_ text: String) -> Bool {
        let japaneseSpecificKanji = Set(
            "働凪凧匂峠榊辻畑腺枠栃塀込麿躾雫颪凩俣杢杣籾粁粂糎糀膤錺鋲鞆鰯"
        )

        if text.contains(where: { japaneseSpecificKanji.contains($0) }) {
            return true
        }

        return text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,
                0x31F0...0x31FF,
                0xFF66...0xFF9D,
                0x1AFF0...0x1AFFF,
                0x1B100...0x1B16F:
                return true
            default:
                return false
            }
        }
    }

    private static func containsInternalWhitespace(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .contains(where: \.isWhitespace)
    }
}

enum 多语言列表文字层级: Equatable {
    case 主标题
    case 副标题

    fileprivate var 基础大小: CGFloat {
        switch self {
        case .主标题: 16
        case .副标题: 14
        }
    }

    fileprivate var 相对文字样式: Font.TextStyle {
        switch self {
        case .主标题: .callout
        case .副标题: .subheadline
        }
    }

    fileprivate var 是粗体: Bool {
        self != .副标题
    }
}

struct 多语言列表文本: View {
    let 文本: String
    let isJapanese: Bool
    let 语言代码: String?
    let 层级: 多语言列表文字层级
    let 日文字体名称: String
    let 系统字体粗细: Font.Weight?
    let 语言来源已知: Bool
    let 空格视为日语: Bool

    @Environment(\.legibilityWeight) private var legibilityWeight
    @ScaledMetric private var 字体大小: CGFloat

    init(
        _ title: 标题工具.标题结果,
        层级: 多语言列表文字层级,
        日文字体名称: String = "HiraginoSans-W5",
        系统字体粗细: Font.Weight? = nil,
        语言来源已知: Bool = true
    ) {
        self.init(
            文本: title.text,
            isJapanese: title.isJapanese,
            语言代码: title.languageCode,
            层级: 层级,
            日文字体名称: 日文字体名称,
            系统字体粗细: 系统字体粗细,
            语言来源已知: 语言来源已知
        )
    }

    init(
        文本: String,
        isJapanese: Bool,
        语言代码: String? = nil,
        层级: 多语言列表文字层级,
        日文字体名称: String = "HiraginoSans-W5",
        系统字体粗细: Font.Weight? = nil,
        语言来源已知: Bool = true,
        空格视为日语: Bool = false
    ) {
        self.文本 = 文本
        self.isJapanese = isJapanese
        self.语言代码 = 语言代码
        self.层级 = 层级
        self.日文字体名称 = 日文字体名称
        self.系统字体粗细 = 系统字体粗细
        self.语言来源已知 = 语言来源已知
        self.空格视为日语 = 空格视为日语
        _字体大小 = ScaledMetric(
            wrappedValue: 层级.基础大小,
            relativeTo: 层级.相对文字样式
        )
    }

    var body: some View {
        Text(
            标题工具.生成富文本(
                文本: 文本,
                isJapanese: isJapanese,
                基础大小: 字体大小,
                是粗体: 层级.是粗体,
                日文字体名称: 日文字体名称,
                系统字体粗细: 系统字体粗细,
                语言来源已知: 语言来源已知,
                空格视为日语: 空格视为日语,
                语言代码: 语言代码,
                精确字号: true,
                辅助功能粗体: legibilityWeight == .bold
            )
        )
    }
}
