import Foundation
import SwiftUI
import UIKit
import SafariServices
import AuthenticationServices
@preconcurrency import Translation

enum PaperVN窗口布局 {
    static let iPad最小尺寸 = CGSize(width: 700, height: 700)
}

nonisolated enum 简介预览文本处理 {
    static func 外部显示文本(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        var lastContentIndex = lines.indices.last

        while let index = lastContentIndex, 是空白行(lines[index]) {
            lastContentIndex = index > lines.startIndex
                ? lines.index(before: index)
                : nil
        }

        guard let attributionIndex = lastContentIndex,
              是末尾署名行(lines[attributionIndex]) else {
            return text
        }

        lines.removeSubrange(attributionIndex...)
        while lines.last.map(是空白行) == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    static func 在截断空行显示省略号(
        _ text: String,
        lineIndex: Int
    ) -> String {
        var lines = text.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex),
              是空白行(lines[lineIndex]),
              lineIndex + 1 < lines.count else {
            return text
        }

        lines[lineIndex] = "…"
        return lines[...lineIndex].joined(separator: "\n")
    }

    private static func 是空白行(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func 是末尾署名行(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last else {
            return false
        }

        let bracketPairs: [Character: Character] = [
            "[": "]",
            "［": "］",
            "【": "】",
            "(": ")",
            "（": "）"
        ]
        return bracketPairs[first] == last
    }
}

struct 简介预览文本视图: View {
    let text: String
    let lineLimit: Int

    @State private var availableWidth: CGFloat = 0

    var body: some View {
        Text(verbatim: previewText)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                availableWidth = newWidth
            }
    }

    private var previewText: String {
        let externalText = 简介预览文本处理.外部显示文本(text)
        guard availableWidth > 0,
              let font = platformFont else {
            return externalText
        }

        let lines = externalText.components(separatedBy: .newlines)
        var visibleLineCount = 0
        var boundaryIndex: Int?

        for (index, line) in lines.enumerated() {
            let renderedLines = line.isEmpty
                ? 1
                : max(
                    1,
                    Int(ceil(measuredWidth(of: line, font: font) / availableWidth))
                )
            if visibleLineCount + renderedLines >= lineLimit {
                boundaryIndex = index
                break
            }
            visibleLineCount += renderedLines
        }

        guard let boundaryIndex,
              lines[boundaryIndex].trimmingCharacters(in: .whitespaces).isEmpty,
              boundaryIndex + 1 < lines.count else {
            return externalText
        }

        return 简介预览文本处理.在截断空行显示省略号(
            externalText,
            lineIndex: boundaryIndex
        )
    }

    private var platformFont: UIFont? {
        UIFont.preferredFont(forTextStyle: .body)
    }

    private func measuredWidth(of text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }
}

struct 平台滚动页面<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        List {
            content
        }
        .平台柔和滚动边缘(for: .top)
    }
}

struct 平台内容不可用视图: View {
    private let label: AnyView
    private let description: AnyView
    private let actions: AnyView

    init<Label: View, Description: View>(
        @ViewBuilder _ label: () -> Label,
        @ViewBuilder description: () -> Description
    ) {
        self.init(
            label,
            description: description,
            actions: {
                EmptyView()
            }
        )
    }

    init<Label: View, Description: View, Actions: View>(
        @ViewBuilder _ label: () -> Label,
        @ViewBuilder description: () -> Description,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = AnyView(label())
        self.description = AnyView(description())
        self.actions = AnyView(actions())
    }

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text? = nil
    ) {
        self.init(
            {
                Label(title, systemImage: systemImage)
            },
            description: {
                if let description {
                    description
                }
            },
            actions: {
                EmptyView()
            }
        )
    }

    var body: some View {
        ContentUnavailableView {
            if #available(iOS 27.0, *) {
                label.font(.title2.weight(.semibold))
            } else {
                label
            }
        } description: {
            if #available(iOS 27.0, *) {
                description.font(.body)
            } else {
                description
            }
        } actions: {
            actions
        }
    }

    static func search(text: String) -> Self {
        Self(
            {
                Label("未找到结果", systemImage: "magnifyingglass")
            },
            description: {
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("没有符合当前筛选条件的结果。")
                } else {
                    Text("没有与“\(text)”匹配的结果。")
                }
            },
            actions: {
                EmptyView()
            }
        )
    }
}

enum 平台列表分页 {
    static let 每页 = 40
    static let 预取余量 = 16
}

struct 平台持续加载指示器: View {
    var body: some View {
        ProgressView()
            .controlSize(.small)
    }
}

extension ToolbarItemPlacement {
    static var 平台主操作: ToolbarItemPlacement {
        .topBarTrailing
    }

    static var 平台前导操作: ToolbarItemPlacement {
        .topBarLeading
    }

    static var 平台关闭操作: ToolbarItemPlacement {
        .topBarTrailing
    }
}

extension View {
    @ViewBuilder
    func 平台根标签栏样式() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad,
           #available(iOS 18.0, *) {
            self.tabViewStyle(.sidebarAdaptable)
        } else {
            self
        }
    }

    @ViewBuilder
    func 平台标签栏搜索自动激活() -> some View {
        if #available(iOS 26.0, *) {
            self.tabViewSearchActivation(.automatic)
        } else {
            self
        }
    }

    @ViewBuilder
    func 平台根窗口尺寸() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.frame(
                minWidth: PaperVN窗口布局.iPad最小尺寸.width,
                minHeight: PaperVN窗口布局.iPad最小尺寸.height
            )
        } else {
            self
        }
    }

    func 平台内联导航标题() -> some View {
        self.navigationBarTitleDisplayMode(.inline)
    }

    func 平台分组列表样式() -> some View {
        self.listStyle(.insetGrouped)
    }

    @ViewBuilder
    func 平台缩放转场(sourceID: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            self
        }
    }

    func 平台Token输入样式() -> some View {
        self
            .textInputAutocapitalization(.never)
            .textContentType(.oneTimeCode)
            .keyboardType(.asciiCapable)
            .submitLabel(.done)
    }

    func 平台导航链接选择样式() -> some View {
        self.pickerStyle(.navigationLink)
    }

    func 平台全屏覆盖<覆盖内容: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> 覆盖内容
    ) -> some View {
        self.fullScreenCover(
            isPresented: isPresented,
            onDismiss: onDismiss,
            content: content
        )
    }

    func 平台近全屏弹窗(dragIndicator: Visibility = .visible) -> some View {
        self
            .presentationDetents([.fraction(0.98)])
            .presentationDragIndicator(dragIndicator)
    }

    @ViewBuilder
    func 平台匹配转场源(id: some Hashable, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func 平台搜索栏保持内容可见() -> some View {
        if #available(iOS 17.1, *) {
            self.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }

    @ViewBuilder
    func 平台隐藏导航标题占位(
        _ title: String,
        enabled: Bool = true
    ) -> some View {
        if enabled {
            self.toolbar {
                ToolbarItem(placement: .principal) {
                    Text(verbatim: title)
                        .hidden()
                        .accessibilityHidden(true)
                }
            }
        } else {
            self
        }
    }

    func 平台沉浸导航栏() -> some View {
        self
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    func 平台横向内容可溢出() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.modifier(iPad横向内容可溢出修饰器())
        } else {
            self
        }
    }

    @ViewBuilder
    func 平台横向书架(内容边距: CGFloat = 20) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.modifier(
                iPad横向书架修饰器(horizontalInset: 内容边距)
            )
        } else {
            self
        }
    }
}

extension View {
    /// iOS 26 及以上使用柔和滚动边缘效果；更早系统保持默认。
    @ViewBuilder
    func 平台柔和滚动边缘(for edges: Edge.Set) -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }

    /// iOS 26 及以上将内容延伸到安全区域外；更早系统保持默认。
    @ViewBuilder
    func 平台背景延伸效果() -> some View {
        if #available(iOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }

    /// iOS 26 及以上使用 `safeAreaBar`；更早系统退回 `safeAreaInset`。
    @ViewBuilder
    func 平台安全区域栏<栏内容: View>(
        edge: VerticalEdge,
        alignment: HorizontalAlignment = .center,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> 栏内容
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.safeAreaBar(
                edge: edge,
                alignment: alignment,
                spacing: spacing,
                content: content
            )
        } else {
            self.safeAreaInset(
                edge: edge,
                alignment: alignment,
                spacing: spacing,
                content: content
            )
        }
    }
}

extension View {
    func 平台键盘搜索栏避让(_ clearance: Binding<CGFloat>) -> some View {
        self
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillShowNotification
                )
            ) { notification in
                更新键盘搜索栏避让(clearance, isVisible: true, notification: notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification
                )
            ) { notification in
                更新键盘搜索栏避让(clearance, isVisible: false, notification: notification)
            }
    }
}

private func 更新键盘搜索栏避让(
    _ clearance: Binding<CGFloat>,
    isVisible: Bool,
    notification: Notification
) {
    let duration = (
        notification.userInfo?[
            UIResponder.keyboardAnimationDurationUserInfoKey
        ] as? NSNumber
    )?.doubleValue ?? 0.25

    withAnimation(.easeInOut(duration: max(duration, 0.22))) {
        clearance.wrappedValue = isVisible ? 64 : 0
    }
}

extension Color {
    static var 平台系统背景: Color {
        Color(uiColor: .systemBackground)
    }

    static var 平台分组背景: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    static var 平台次级分组背景: Color {
        Color(uiColor: .secondarySystemGroupedBackground)
    }
}

private struct 平台卡片容器修饰器: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let background: Color
    let stroke: Color
    let cornerRadius: CGFloat
    let lightModeShadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        let decoratedContent = content
            .background(background, in: shape)
            .clipShape(shape)
            .overlay {
                shape.stroke(stroke, lineWidth: 0.5)
            }

        if colorScheme == .light, lightModeShadowOpacity > 0 {
            decoratedContent.shadow(
                color: .black.opacity(lightModeShadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )
        } else {
            decoratedContent
        }
    }
}

extension View {
    func 平台卡片容器(
        background: Color,
        stroke: Color,
        cornerRadius: CGFloat,
        lightModeShadowOpacity: Double,
        shadowRadius: CGFloat,
        shadowY: CGFloat
    ) -> some View {
        modifier(
            平台卡片容器修饰器(
                background: background,
                stroke: stroke,
                cornerRadius: cornerRadius,
                lightModeShadowOpacity: lightModeShadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}

private struct iPad横向内容可溢出修饰器: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}

private struct iPad横向书架修饰器: ViewModifier {
    let horizontalInset: CGFloat
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ViewBuilder
    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .padding(.horizontal, -horizontalInset)
                .contentMargins(
                    .horizontal,
                    horizontalInset,
                    for: .scrollContent
                )
                .scrollClipDisabled()
                .ignoresSafeArea(.container, edges: .horizontal)
                .background {
                    iPad横向滚动方向锁定器()
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}

private struct iPad横向滚动方向锁定器: UIViewRepresentable {
    func makeUIView(context: Context) -> iPad横向滚动方向锁定视图 {
        iPad横向滚动方向锁定视图()
    }

    func updateUIView(
        _ uiView: iPad横向滚动方向锁定视图,
        context: Context
    ) {
        uiView.updateScrollView()
    }
}

private final class iPad横向滚动方向锁定视图: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateScrollView()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateScrollView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollView()
    }

    func updateScrollView() {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView,
               scrollView.contentSize.width > scrollView.bounds.width + 1 {
                scrollView.isDirectionalLockEnabled = true
                scrollView.alwaysBounceVertical = false
                return
            }
            candidate = view.superview
        }
    }
}

struct 内置Safari浏览器: View {
    let url: URL

    @EnvironmentObject private var parentalControls: 家长控制中心

    var body: some View {
        if parentalControls.allowsExternalURL(url) {
            browserContent
        } else {
            平台内容不可用视图(
                "链接已受限",
                systemImage: "shield.lefthalf.filled",
                description: Text("家长控制生效期间不能打开此站点。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var browserContent: some View {
        Safari浏览器控制器(url: url)
            .ignoresSafeArea()
    }
}

private struct Safari浏览器控制器: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let viewController = SFSafariViewController(url: url)
        viewController.dismissButtonStyle = .close
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}
}

/// 可存进 `@State` 的 `TranslationSession.Configuration`；端侧翻译仅 iOS 18 及以上可用。
struct 平台翻译配置: Equatable {
    private var storage: Any

    @available(iOS 18.0, *)
    init(source: Locale.Language? = nil, target: Locale.Language? = nil) {
        storage = TranslationSession.Configuration(source: source, target: target)
    }

    @available(iOS 18.0, *)
    var configuration: TranslationSession.Configuration {
        get { storage as! TranslationSession.Configuration }
        set { storage = newValue }
    }

    @available(iOS 18.0, *)
    var source: Locale.Language? {
        get { configuration.source }
        set { configuration.source = newValue }
    }

    @available(iOS 18.0, *)
    var target: Locale.Language? {
        get { configuration.target }
        set { configuration.target = newValue }
    }

    @available(iOS 18.0, *)
    mutating func invalidate() {
        configuration.invalidate()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        if #available(iOS 18.0, *) {
            return lhs.configuration == rhs.configuration
        }
        return true
    }
}

struct 平台翻译会话 {
    private let storage: Any

    @available(iOS 18.0, *)
    init(_ session: TranslationSession) {
        storage = session
    }

    @available(iOS 18.0, *)
    var session: TranslationSession {
        storage as! TranslationSession
    }
}

extension View {
    @ViewBuilder
    func 平台翻译任务(
        _ configuration: 平台翻译配置?,
        action: @escaping (平台翻译会话) async -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            self.translationTask(configuration?.configuration) { session in
                await action(平台翻译会话(session))
            }
        } else {
            self
        }
    }
}

extension ASWebAuthenticationSession {
    /// iOS 17.4 及以上使用 `Callback.customScheme`；更早系统使用等价的 `callbackURLScheme`。
    convenience init(
        url: URL,
        平台自定义Scheme scheme: String,
        completionHandler: @escaping ASWebAuthenticationSession.CompletionHandler
    ) {
        if #available(iOS 17.4, *) {
            self.init(
                url: url,
                callback: .customScheme(scheme),
                completionHandler: completionHandler
            )
        } else {
            self.init(
                url: url,
                callbackURLScheme: scheme,
                completionHandler: completionHandler
            )
        }
    }
}

/// `ScrollGeometry` 中本项目用到的字段；iOS 17 也能构造。
struct 平台滚动几何 {
    let contentOffset: CGPoint
    let contentSize: CGSize
    let contentInsets: EdgeInsets
    let containerSize: CGSize
}

extension View {
    /// iOS 18 及以上监听滚动几何变化；更早系统不提供回调，保持初始状态。
    @ViewBuilder
    func 平台滚动几何变化<T: Equatable>(
        for type: T.Type,
        of transform: @escaping (平台滚动几何) -> T,
        action: @escaping (_ oldValue: T, _ newValue: T) -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: type) { geometry in
                transform(
                    平台滚动几何(
                        contentOffset: geometry.contentOffset,
                        contentSize: geometry.contentSize,
                        contentInsets: geometry.contentInsets,
                        containerSize: geometry.containerSize
                    )
                )
            } action: { oldValue, newValue in
                action(oldValue, newValue)
            }
        } else {
            self
        }
    }

    /// iOS 18 及以上按内容尺寸确定弹窗大小；更早系统使用默认尺寸。
    @ViewBuilder
    func 平台弹窗贴合内容尺寸() -> some View {
        if #available(iOS 18.0, *) {
            self.presentationSizing(.fitted)
        } else {
            self
        }
    }
}

extension ViewAlignedScrollTargetBehavior.LimitBehavior {
    /// iOS 18 及以上每次只滚动一个视图；iOS 17 使用最接近的 `.always`。
    static var 平台逐个: Self {
        if #available(iOS 18.0, *) {
            return .alwaysByOne
        }
        return .always
    }
}

/// 较新 SF Symbols 在旧系统上的替代图标。
enum 平台符号 {
    static var 翻译: String {
        if #available(iOS 17.4, *) { return "translate" }
        return "character.bubble"
    }

    static var 反馈编辑: String {
        if #available(iOS 18.0, *) { return "bubble.and.pencil" }
        return "square.and.pencil"
    }

    static var 计划中: String {
        if #available(iOS 18.0, *) {
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
        return "clock.arrow.circlepath"
    }

    static var 平台设备: String {
        if #available(iOS 18.0, *) { return "desktopcomputer.and.macbook" }
        return "desktopcomputer"
    }

    static var 文件: String {
        if #available(iOS 18.0, *) { return "document" }
        return "doc"
    }

    static var 歌曲: String {
        if #available(iOS 18.0, *) { return "music.microphone" }
        return "music.mic"
    }
}
