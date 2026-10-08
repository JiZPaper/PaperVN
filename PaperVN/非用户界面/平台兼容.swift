import Foundation
import SwiftUI
import UIKit
import SafariServices

enum PaperVN窗口布局 {
    static let iPad最小尺寸 = CGSize(width: 700, height: 700)
}

nonisolated enum 简介预览文本处理 {
    /// 去掉简介结尾 [] / （）里的来源信息，原文和译文共用。
    static func 外部显示文本(_ text: String) -> String {
        var lines = 规范换行(text).components(separatedBy: "\n")
        while lines.last.map(是空白行) == true {
            lines.removeLast()
        }
        guard lines.count > 1 || lines.first.map(是空白行) == false,
              let lastLine = lines.last,
              let trimmedLine = 去掉末尾来源(lastLine),
              lines.count > 1 || !是空白行(trimmedLine) else {
            return lines.joined(separator: "\n")
        }

        if 是空白行(trimmedLine) {
            lines.removeLast()
            while lines.last.map(是空白行) == true {
                lines.removeLast()
            }
        } else {
            lines[lines.count - 1] = trimmedLine
        }
        return lines.joined(separator: "\n")
    }

    static func 规范换行(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }

    static func 是空白行(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static let 括号对: [Character: Character] = [
        "]": "[",
        "］": "［",
        "】": "【",
        ")": "(",
        "）": "（"
    ]

    private static let 来源关键词 = [
        "from", "source", "translated", "edited", "taken", "adapted",
        "wikipedia", "getchu", "official", "website", "dlsite", "steam",
        "来源", "来自", "摘自", "出自", "引自", "译自", "节选", "官网",
        "官方", "翻译", "維基", "维基", "出典", "引用", "公式", "より"
    ]

    /// 返回去掉末尾来源后的行；没有来源时返回 nil。
    /// 整行都是括号时直接视为来源，行内结尾括号需含来源关键词。
    private static func 去掉末尾来源(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let closing = trimmed.last,
              let opening = 括号对[closing] else {
            return nil
        }

        var depth = 0
        var openingIndex: String.Index?
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            index = trimmed.index(before: index)
            let character = trimmed[index]
            if character == closing {
                depth += 1
            } else if character == opening {
                depth -= 1
                if depth == 0 {
                    openingIndex = index
                    break
                }
            }
        }
        guard let openingIndex else { return nil }

        if openingIndex == trimmed.startIndex {
            return ""
        }

        let content = trimmed[openingIndex...].lowercased()
        guard 来源关键词.contains(where: content.contains) else {
            return nil
        }
        return String(trimmed[..<openingIndex])
            .trimmingCharacters(in: .whitespaces)
    }
}

struct 简介预览文本视图: View {
    let text: String
    let lineLimit: Int
    var onTruncationChange: ((Bool) -> Void)? = nil

    @State private var visibleHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var prefixHeights: [String: CGFloat] = [:]

    var body: some View {
        Text(verbatim: previewText)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                visibleHeight = newHeight
            }
            .background(alignment: .topLeading) {
                measurementViews
                    .hidden()
                    .accessibilityHidden(true)
            }
            .onChange(of: isTruncated, initial: true) { _, newValue in
                onTruncationChange?(newValue)
            }
    }

    private var isTruncated: Bool {
        visibleHeight > 0 && fullHeight > visibleHeight + 1
    }

    /// 合并连续空行后的显示文本。
    private var lines: [String] {
        var result: [String] = []
        for line in 简介预览文本处理.外部显示文本(text)
            .components(separatedBy: "\n") {
            if 简介预览文本处理.是空白行(line),
               result.last.map(简介预览文本处理.是空白行) ?? true {
                continue
            }
            result.append(简介预览文本处理.是空白行(line) ? "" : line)
        }
        return result
    }

    /// 后面还有内容的空行位置。
    private var blankLineCandidates: [Int] {
        guard lineLimit >= 2 else { return [] }
        let lines = lines
        return lines.indices.filter {
            $0 > 0 && $0 + 1 < lines.count && lines[$0].isEmpty
        }
    }

    private func prefix(before index: Int) -> String {
        lines[..<index].joined(separator: "\n")
    }

    private var candidatePrefixes: [String] {
        blankLineCandidates.map(prefix(before:))
    }

    // SwiftUI 对中日文按词断行，无法用 TextKit 复现，
    // 因此直接用隐藏的 Text 量出空行前那段文字占几行。
    @ViewBuilder
    private var measurementViews: some View {
        ZStack(alignment: .topLeading) {
            let fullText = lines.joined(separator: "\n")
            measuredText(fullText, lineLimit: nil) {
                fullHeight = $0
            }
            .id(fullText)

            // 以文字本身为标识，文字变化时重建视图以重新触发测量。
            ForEach(candidatePrefixes, id: \.self) { prefix in
                measuredText(prefix, lineLimit: nil) {
                    prefixHeights["all|\(prefix)"] = $0
                }
                measuredText(prefix, lineLimit: lineLimit - 1) {
                    prefixHeights["fits|\(prefix)"] = $0
                }
                if lineLimit >= 3 {
                    measuredText(prefix, lineLimit: lineLimit - 2) {
                        prefixHeights["short|\(prefix)"] = $0
                    }
                }
            }
        }
    }

    private func measuredText(
        _ string: String,
        lineLimit: Int?,
        onHeight: @escaping (CGFloat) -> Void
    ) -> some View {
        Text(verbatim: string)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { newHeight in
                onHeight(newHeight)
            }
    }

    /// 空行前的文字正好占 lineLimit - 1 行，即该空行落在最后一行可见位置。
    private func blankLineIsLastVisible(_ index: Int) -> Bool {
        let prefix = prefix(before: index)
        guard let all = prefixHeights["all|\(prefix)"],
              let fits = prefixHeights["fits|\(prefix)"],
              all > 0,
              abs(all - fits) < 0.5 else {
            return false
        }
        guard lineLimit >= 3 else { return true }
        guard let short = prefixHeights["short|\(prefix)"] else {
            return false
        }
        return short < fits - 0.5
    }

    private var previewText: String {
        let lines = lines
        // 最后一行可见的是空行且后面还有内容时，系统不会显示省略号，手动补上。
        guard let index = blankLineCandidates.first(
            where: blankLineIsLastVisible
        ) else {
            return lines.joined(separator: "\n")
        }
        return (lines[..<index] + ["…"]).joined(separator: "\n")
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
        if UIDevice.current.userInterfaceIdiom == .pad {
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
    /// iOS 26 起底部搜索框会悬浮在键盘上方，键盘安全区只把底部栏托到键盘顶部，
    /// 需要再让出搜索框的高度；更早系统的搜索框在顶部，不需要额外避让。
    @ViewBuilder
    func 平台键盘搜索栏避让(_ clearance: Binding<CGFloat>) -> some View {
        if #available(iOS 26.0, *) {
            self.键盘搜索栏避让(clearance)
        } else {
            self
        }
    }

    private func 键盘搜索栏避让(_ clearance: Binding<CGFloat>) -> some View {
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
        } else {
            content
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

