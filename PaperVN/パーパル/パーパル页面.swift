import SwiftUI

struct パーパル页面: View {
    @Binding var isPresented: Bool

    @StateObject private var 视图模型 = パーパル对话视图模型()
    @Environment(\.accessibilityReduceMotion) private var 减弱动态効果
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage(パーパル偏好.称呼键)
    private var 称呼 = パーパル偏好.默认称呼

    @State private var 显示称呼编辑 = false
    @State private var 显示历史 = false
    @State private var 显示记忆设置 = false
    @State private var 输入框高度: CGFloat = 0
    @State private var 输入框单行高度: CGFloat = 0
    @FocusState private var 输入聚焦: Bool
    @Namespace private var 弹窗命名空间

    private let 底部锚点 = "パーパル底部锚点"
    private let 输入框最小高度: CGFloat = 44
    private let 输入框多行圆角: CGFloat = 24

    init(
        isPresented: Binding<Bool>,
        视图模型: パーパル对话视图模型 = パーパル对话视图模型()
    ) {
        _isPresented = isPresented
        _视图模型 = StateObject(wrappedValue: 视图模型)
    }

    private var 生効称呼: String {
        let 整理后 = 称呼.trimmingCharacters(in: .whitespacesAndNewlines)
        return 整理后.isEmpty ? パーパル偏好.默认称呼 : 整理后
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                    .ignoresSafeArea()

                对话内容
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        输入区
                    }
            }
                .navigationTitle(
                    Text(verbatim: 视图模型.当前会话.显示标题)
                )
                .平台柔和滚动边缘(for: .top)
                .平台内联导航标题()
                .平台沉浸导航栏()
                .toolbar { 工具栏 }
                .sheet(isPresented: $显示称呼编辑) {
                    称呼编辑Sheet(称呼: $称呼)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
        .sheet(isPresented: $显示历史) {
                    NavigationStack {
                        パーパル历史页面(isPresented: $显示历史) { 会话 in
                            视图模型.载入(会话: 会话)
                        }
                    }
                    .平台近全屏弹窗()
                }
                .sheet(isPresented: $显示记忆设置) {
                    NavigationStack {
                        パーパル设置页面(
                            isPresented: $显示记忆设置,
                            仅显示记忆: true
                        )
                    }
                    .平台近全屏弹窗()
                }
        }
        .interactiveDismissDisabled()
    }

    private var 对话内容: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(视图模型.消息列表) { 消息 in
                        消息行(消息)
                            .id(消息.id)
                    }

                    if 视图模型.正在生成 {
                        パーパル思考指示()
                            .padding(.leading, 4)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(底部锚点)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .scrollDisabled(视图模型.消息列表.isEmpty)
            .defaultScrollAnchor(.bottom)
            .overlay(alignment: .bottomLeading) {
                if 视图模型.消息列表.isEmpty {
                    欢迎区
                        .padding(.horizontal, 18)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            .animation(
                .easeOut(duration: 0.2),
                value: 视图模型.消息列表.isEmpty
            )
            .onChange(of: 视图模型.消息列表.count) { _, _ in
                滚动到底部(proxy, 动画: true)
            }
            .onChange(of: 视图模型.消息列表.last?.文本) { _, _ in
                滚动到底部(proxy, 动画: false)
            }
        }
    }

    private func 滚动到底部(_ proxy: ScrollViewProxy, 动画: Bool) {
        guard 动画, !减弱动态効果 else {
            proxy.scrollTo(底部锚点, anchor: .bottom)
            return
        }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(底部锚点, anchor: .bottom)
        }
    }

    private var 欢迎区: some View {
        パーパル空状态()
    }

    @ViewBuilder
    private func 消息行(_ 消息: パーパル消息) -> some View {
        switch 消息.角色 {
        case .user:
            HStack {
                Spacer(minLength: 44)
                Text(verbatim: 消息.文本)
                    .font(.body)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(
                        Color(uiColor: .systemGray5),
                        in: RoundedRectangle(
                            cornerRadius: 22,
                            style: .continuous
                        )
                    )
                    .contentShape(
                        [.interaction, .contextMenuPreview],
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = 消息.文本
                        } label: {
                            Label("拷贝", systemImage: "doc.on.doc")
                        }

                        if 视图模型.可以编辑最后一条消息,
                           视图模型.当前会话.消息.last(where: { $0.角色 == .user })?.id == 消息.id {
                            Button {
                                视图模型.开始编辑最后一条消息()
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                        }

                        if 视图模型.可以重新生成上一条用户消息,
                           视图模型.当前会话.消息.last(where: { $0.角色 == .user })?.id == 消息.id {
                            Button {
                                视图模型.重新生成()
                            } label: {
                                Label("重新生成", systemImage: "arrow.clockwise")
                            }
                        }
                    } preview: {
                        Text(verbatim: 消息.文本)
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .background(
                                Color(uiColor: .systemGray5),
                                in: RoundedRectangle(
                                    cornerRadius: 22,
                                    style: .continuous
                                )
                            )
                            .contentShape(
                                .contextMenuPreview,
                                RoundedRectangle(
                                    cornerRadius: 22,
                                    style: .continuous
                                )
                            )
                    }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("你说：\(消息.文本)"))
        case .assistant:
            VStack(alignment: .leading, spacing: 12) {
                if !消息.文本.isEmpty {
                    助手正文(消息.文本)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = 消息.文本
                            } label: {
                                Label("拷贝", systemImage: "doc.on.doc")
                            }
                        }
                        .transition(.scale.combined(with: .opacity))
                }

                if !消息.引用.isEmpty {
                    来源引用(消息.引用)
                        .transition(.scale.combined(with: .opacity))
                }

                if !消息.卡片.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(消息.卡片.enumerated()), id: \.element.id) { index, 引用 in
                            パーパル卡片视图(引用: 引用)

                            if index < 消息.卡片.count - 1 {
                                Divider()
                                    .padding(
                                        .leading,
                                        パーパル卡片布局.内边距
                                            + 列表封面布局.宽度
                                            + 12
                                    )
                                    .padding(.trailing, 16)
                            }
                        }
                    }
                    .background(
                        Color(uiColor: .systemBackground),
                        in: RoundedRectangle(
                            cornerRadius: パーパル卡片布局.外框圆角(
                                horizontalSizeClass: horizontalSizeClass
                            ),
                            style: .continuous
                        )
                    )
                    .modifier(パーパル卡片彩虹光效())
                    .transition(.scale.combined(with: .opacity))
                }

                回答版本栏(消息)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func 回答版本栏(_ 消息: パーパル消息) -> some View {
        let 回答总数 = 消息.回答总数
        if 回答总数 > 1 {
            HStack(spacing: 6) {
                Button {
                    视图模型.切换回答(
                        消息ID: 消息.id,
                        到索引: 消息.当前回答索引 - 1
                    )
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .background(
                            Color(uiColor: .tertiarySystemFill),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .disabled(视图模型.正在生成 || 消息.当前回答索引 == 0)
                .accessibilityLabel(Text("上一个回答"))
                .help("上一个回答")

                Text(verbatim: "\(消息.当前回答索引 + 1)/\(回答总数)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34)

                Button {
                    视图模型.切换回答(
                        消息ID: 消息.id,
                        到索引: 消息.当前回答索引 + 1
                    )
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 26, height: 26)
                        .background(
                            Color(uiColor: .tertiarySystemFill),
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
                .disabled(
                    视图模型.正在生成
                        || 消息.当前回答索引 >= 回答总数 - 1
                )
                .accessibilityLabel(Text("下一个回答"))
                .help("下一个回答")

            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private func 来源引用(_ 引用: [パーパル网络引用]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(引用) { 来源 in
                    Link(destination: 来源.地址) {
                        HStack(spacing: 6) {
                            来源图标(来源)
                                .accessibilityHidden(true)

                            Text(verbatim: 来源.显示文本)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Color(uiColor: .tertiarySystemFill),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("来源\(来源.显示文本)"))
                }
            }
            .padding(.horizontal, 18)
        }
        .padding(.horizontal, -18)
    }

    @ViewBuilder
    private func 来源图标(_ 来源: パーパル网络引用) -> some View {
        AsyncImage(url: 来源.图标地址) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFit()
            default:
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func 助手正文(_ 文本: String) -> Text {
        let 规范化文本 = 文本.replacingOccurrences(of: "]]\\(", with: "]](")
        let 选项 = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard let 富文本 = try? AttributedString(
            markdown: 规范化文本,
            options: 选项
        ) else {
            return Text(verbatim: 文本)
        }
        return Text(富文本)
    }

    private var 输入区: some View {
        VStack(spacing: 8) {
            if 视图模型.已用尽额度 {
                パーパル额度提示条 {
                    视图模型.新建对话()
                }
            } else if let 错误 = 视图模型.错误提示 {
                パーパル提示条(
                    文本: 错误,
                    符号: "exclamationmark.circle",
                    操作: { 视图模型.重试() }
                )
            }

            输入框
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background {
            パーパル底部区域光晕(强度: 底部区域光效强度)
                .padding(.bottom, -50)
        }
    }

    private var 输入框形状: AnyShape {
        let 单行高度 = 输入框单行高度 > 0
            ? 输入框单行高度
            : 输入框最小高度

        if 输入框高度 <= 单行高度 + 1 {
            return AnyShape(Capsule())
        } else {
            return AnyShape(
                RoundedRectangle(
                    cornerRadius: 输入框多行圆角,
                    style: .continuous
                )
            )
        }
    }

    private var 输入框: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(
                text: $视图模型.草稿,
                prompt: Text("与Paparu对话…"),
                axis: .vertical
            ) {
                Text("消息")
            }
            .lineLimit(1...5)
            .focused($输入聚焦)
            .disabled(
                视图模型.已用尽额度 && 视图模型.正在编辑消息ID == nil
            )
            .padding(.leading, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 输入框最小高度)
            .accessibilityIdentifier("assistant.input")

            发送按钮
                .padding(.trailing, 6)
        }
        .padding(.vertical, 2)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { 新高度 in
            输入框高度 = 新高度
            if 视图模型.草稿.isEmpty {
                输入框单行高度 = 新高度
            }
        }
        .background {
            パーパル输入框阴影(形状: 输入框形状)
        }
        .overlay {
            パーパル输入框彩虹描边(
                形状: 输入框形状,
                强度: 输入框光效强度
            )
        }
        .液态玻璃(.regular.interactive(), in: 输入框形状)
        .contentShape(输入框形状)
    }

    private var 输入框光效强度: Double {
        if 视图模型.已用尽额度 {
            return 0.3
        }
        return 输入聚焦 || 视图模型.正在生成 ? 1 : 0.72
    }

    private var 底部区域光效强度: Double {
        if 视图模型.已用尽额度 {
            return 0.2
        }
        return 输入聚焦 || 视图模型.正在生成 ? 0.8 : 0.5
    }

    private var 发送按钮: some View {
        Button {
            if 视图模型.正在生成 {
                视图模型.停止生成()
            } else {
                视图模型.发送()
            }
        } label: {
            Image(
                systemName: 视图模型.正在生成
                    ? "stop.fill"
                    : "arrow.up"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 30, height: 30)
            }
            .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!发送按钮可用)
        .opacity(发送按钮可用 ? 1 : 0.42)
        .accessibilityLabel(视图模型.正在生成 ? "停止" : "发送")
        .accessibilityIdentifier("assistant.send")
    }

    private var 发送按钮可用: Bool {
        视图模型.正在生成 || 视图模型.可以发送
    }

    @ToolbarContentBuilder
    private var 工具栏: some ToolbarContent {
        ToolbarItem(placement: .平台前导操作) {
            Menu {
                Button {
                    视图模型.新建对话()
                } label: {
                    Label("新对话", systemImage: "plus.bubble")
                }
                .disabled(!视图模型.可以新建对话)

                Button {
                    显示历史 = true
                } label: {
                    Label("最近对话", systemImage: "clock.arrow.circlepath")
                }

                Divider()

                Button {
                    显示记忆设置 = true
                } label: {
                    Label("记忆", systemImage: "brain")
                }

                Button {
                    显示称呼编辑 = true
                } label: {
                    Label("称呼", systemImage: "person.text.rectangle")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("更多")
            .accessibilityIdentifier("assistant.menu")
        }

        ToolbarItem(placement: .平台关闭操作) {
            Button {
                视图模型.停止生成()
                isPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("关闭")
            .accessibilityIdentifier("assistant.close")
        }
    }
}

struct パーパル提示条: View {
    let 文本: String
    var 符号 = "exclamationmark.circle"
    var 操作: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: 符号)
                .font(.caption)
            Text(verbatim: 文本)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let 操作 {
                Button("重试", action: 操作)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .液态玻璃(.regular, in: Capsule())
    }
}

struct パーパル额度提示条: View {
    let 开始新对话: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.full")
                .font(.caption)

            Text("已达到当前对话限额。")
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("新对话", action: 开始新对话)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityIdentifier("assistant.newConversation")
        }
        .foregroundStyle(.secondary)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
        .液态玻璃(.regular, in: Capsule())
    }
}

struct パーパル空状态: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("让Paparu寻找视觉小说或角色")
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

            Text("描述你记得的片段让Paparu找到它，或者让Paparu向你推荐视觉小说。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

struct 称呼编辑Sheet: View {
    @Binding var 称呼: String
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var 草稿: String

    init(称呼: Binding<String>) {
        _称呼 = 称呼
        _草稿 = State(initialValue: 称呼.wrappedValue)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(
                        "称呼",
                        text: $草稿,
                        prompt: Text(verbatim: パーパル偏好.默认称呼)
                    )
                    .textInputAutocapitalization(.never)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(保存)
                } header: {
                    Text("Paparu怎么称呼你")
                } footer: {
                    Text("默认为“\(パーパル偏好.默认称呼)”。")
                }

                if 草稿.trimmingCharacters(in: .whitespacesAndNewlines)
                    != パーパル偏好.默认称呼 {
                    Section {
                        Button("恢复默认称呼") {
                            草稿 = パーパル偏好.默认称呼
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("称呼")
            .平台柔和滚动边缘(for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        保存()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .onAppear {
            isFocused = true
        }
        .onDisappear {
            称呼 = 草稿
        }
    }

    private func 保存() {
        称呼 = 草稿
        dismiss()
    }
}

#Preview("空状态") {
    NavigationStack {
        ScrollView {
            パーパル空状态()
                .padding(.horizontal, 18)
                .padding(.top, 16)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .navigationTitle(Text(verbatim: "新对话"))
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
    }
}

#Preview("对话操作与回答切换") {
    @Previewable @State var isPresented = true

    let 旧回答 = パーパル回答版本(
        文本: "这是一份较早的回答。你可以在回答下方切换版本。",
        时间: Date(timeIntervalSinceNow: -120)
    )
    let 新回答 = パーパル回答版本(
        文本: "这是重新生成后的回答。长按用户消息可以拷贝或编辑。",
        时间: Date(timeIntervalSinceNow: -60)
    )
    let 助手消息 = パーパル消息(
        角色: .assistant,
        文本: 新回答.文本,
        时间: 新回答.时间,
        思考过程: nil,
        回答版本: [旧回答, 新回答],
        当前回答索引: 1
    )
    let 最后一条助手消息 = パーパル消息(
        角色: .assistant,
        文本: "当然可以，轻快一点的作品我也整理好了にゃ～"
    )
    let 会话 = パーパル会话(
        消息: [
            パーパル消息(
                角色: .user,
                文本: "帮我找一部有夏日小镇氛围的视觉小说。"
            ),
            助手消息,
            パーパル消息(
                角色: .user,
                文本: "再推荐一部节奏更轻快的。"
            ),
            最后一条助手消息
        ],
        标题: "夏日视觉小说推荐"
    )
    パーパル页面(
        isPresented: $isPresented,
        视图模型: パーパル对话视图模型(
            会话: 会话,
            错误提示: "网络不可用。"
        )
    )
}

#Preview("提示条") {
    VStack(spacing: 14) {
        パーパル提示条(
            文本: "Paparu遇到未知错误。",
            操作: { }
        )

        パーパル额度提示条 { }
    }
    .padding(20)
    .frame(maxHeight: .infinity)
    .background(Color(uiColor: .secondarySystemBackground))
}

#Preview("提示条·生成中光効") {
    VStack(spacing: 14) {
        パーパル提示条(
            文本: "请求已超时。",
            操作: { }
        )

        パーパル额度提示条 { }

        パーパル思考指示()
    }
    .padding(20)
    .frame(maxHeight: .infinity)
    .background(Color(uiColor: .secondarySystemBackground))
}

struct パーパル设置页面: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true
    var 仅显示记忆: Bool = false

    @ObservedObject private var 数据中心 = パーパル数据中心.shared
    @ObservedObject private var 记忆中心 = パーパル记忆中心.shared

    @AppStorage(パーパル偏好.称呼键)
    private var 称呼 = パーパル偏好.默认称呼

    @State private var 显示删除全部对话确认 = false
    @State private var 显示清除记忆确认 = false

    var body: some View {
        平台滚动页面 {
            if 仅显示记忆 {
                记忆区
            } else {
                称呼区
                记忆区
                对话区
                说明区
            }
        }
        .平台分组列表样式()
        .navigationTitle(Text(verbatim: 仅显示记忆 ? "记忆" : "Paparu"))
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .alert(
            "确定要删除所有对话吗？",
            isPresented: $显示删除全部对话确认
        ) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                数据中心.删除全部会话()
            }
        } message: {
            Text("删除所有对话后无法恢复。")
        }
        .alert(
            "确定要清除记忆吗？",
            isPresented: $显示清除记忆确认
        ) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                记忆中心.删除全部()
            }
        } message: {
            Text("清除记忆后无法恢复。")
        }
    }

    private var 称呼区: some View {
        Section {
            TextField(
                "称呼",
                text: $称呼,
                prompt: Text(verbatim: パーパル偏好.默认称呼)
            )
            .textInputAutocapitalization(.never)
            .submitLabel(.done)

            if 称呼.trimmingCharacters(in: .whitespacesAndNewlines)
                != パーパル偏好.默认称呼 {
                Button("恢复默认称呼") {
                    称呼 = パーパル偏好.默认称呼
                }
            }
        } header: {
            Text("Paparu怎么称呼你")
        } footer: {
            Text("留空时使用默认的「\(パーパル偏好.默认称呼)」。")
        }
        .listSectionSeparator(.visible, edges: .top)
    }

    private var 对话区: some View {
        Section {
            NavigationLink {
                パーパル历史页面(
                    isPresented: $isPresented,
                    showsDismissButton: false
                )
            } label: {
                LabeledContent {
                    Text(verbatim: 数据中心.可见会话.count.formatted())
                } label: {
                    Label("对话历史", systemImage: "bubble.left.and.bubble.right")
                }
            }

            if !数据中心.可见会话.isEmpty {
                Button("删除全部对话", role: .destructive) {
                    显示删除全部对话确认 = true
                }
            }
        } header: {
            Text("对话")
        } footer: {
            Text("对话文字历史只保存在这台设备上，不会同步到iCloud。")
        }
    }

    private var 记忆区: some View {
        Section {
            Toggle(isOn: Binding(
                get: { 记忆中心.已启用 },
                set: { 记忆中心.设置已启用($0) }
            )) {
                Text("记忆")
            }

            if 记忆中心.已启用 {
                Toggle(isOn: Binding(
                    get: { 记忆中心.iCloud同步已启用 },
                    set: { 记忆中心.设置iCloud同步($0) }
                )) {
                    Text("iCloud同步")
                }

                Button("清除记忆", role: .destructive) {
                    显示清除记忆确认 = true
                }
            }
        } header: {
            Text("记忆")
        } footer: {
            if 记忆中心.已启用 {
                Text("记住过去对话中的内容，并在新对话中参考这些上下文。")
            }
        }
    }

    private var 说明区: some View {
        Section {
        } footer: {

        }
    }
}

struct パーパル历史页面: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true
    var 选择: ((パーパル会话) -> Void)?

    @ObservedObject private var 数据中心 = パーパル数据中心.shared
    @State private var 显示清空确认 = false

    var body: some View {
        平台滚动页面 {
            if 数据中心.可见会话.isEmpty {
                Section {
                    平台内容不可用视图(
                        "暂无对话",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("与Paparu对话以查看最近对话。")
                    )
                }
            } else {
                Section {
                    ForEach(数据中心.可见会话) { 会话 in
                        会话条目(会话)
                    }
                    .onDelete { 索引 in
                        let 会话 = 数据中心.可见会话
                        for index in 索引 {
                            guard 会话.indices.contains(index) else { continue }
                            数据中心.删除会话(id: 会话[index].id)
                        }
                    }
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("最近对话")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if !数据中心.可见会话.isEmpty {
                ToolbarItem(placement: .平台主操作) {
                    Menu {
                        Button(role: .destructive) {
                            显示清空确认 = true
                        } label: {
                            Label("删除所有对话", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多")
                }
            }

            if showsDismissButton {
                if !数据中心.可见会话.isEmpty {
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .平台主操作)
                    }
                }

                ToolbarItem(placement: .平台主操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .alert(
            "确定要删除所有对话吗？",
            isPresented: $显示清空确认
        ) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) {
                数据中心.删除全部会话()
            }
        } message: {
            Text("删除所有对话后无法恢复。")
        }
    }

    @ViewBuilder
    private func 会话条目(_ 会话: パーパル会话) -> some View {
        if let 选择 {
            Button {
                选择(会话)
                isPresented = false
            } label: {
                会话行(会话)
            }
            .buttonStyle(.plain)
            .contextMenu {
                长按删除按钮(会话)
            }
        } else {
            会话行(会话)
                .contextMenu {
                    长按删除按钮(会话)
                }
        }
    }

    private func 长按删除按钮(_ 会话: パーパル会话) -> some View {
        Button(role: .destructive) {
            立即删除(会话)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private func 立即删除(_ 会话: パーパル会话) {
        数据中心.删除会话(id: 会话.id)
    }

    private func 会话行(_ 会话: パーパル会话) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: 会话.显示标题)
                .font(.body)
                .lineLimit(2)

            Text(会话.更新时间, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
