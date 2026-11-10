import SwiftUI

/// 选择一处列表的样式，以及显示哪些信息、按什么顺序排列。
/// 顶部悬浮的预览随更改实时更新（带弹簧动画），更改也会立即用到对应的列表。
/// 资料库的在“资料库”设置里，搜索结果与制作人员、会社的在“搜索”设置里。
struct 列表信息设置页面: View {
    let 场景: 作品列表场景
    private let 标题: String

    private let 设置 = 作品列表设置.shared
    /// 选择器自己记住选中的样式，不直接绑定设置：快速连续切换时，
    /// 设置的更新和列表重新排版会把选择器拉回上一个样式。选中后再同步到设置。
    @State private var 选中样式: 作品列表样式

    init(场景: 作品列表场景, 标题: String? = nil) {
        self.场景 = 场景
        self.标题 = 标题 ?? 场景.localizedTitle
        _选中样式 = State(initialValue: 作品列表设置.shared.样式(for: 场景))
    }

    private var 整理后: 作品列表配置 { 设置.配置(for: 场景) }
    private var 当前样式: 作品列表样式 { 设置.样式(for: 场景) }

    /// 在动画里修改：背后列表里的信息跟着弹出、收起或换样式。
    private func 更新(_ 新配置: 作品列表配置) {
        withAnimation(.bouncy) {
            设置.设置配置(新配置, for: 场景)
        }
    }

    /// 把选中的样式同步到设置。换到可显示数量更少的样式时，自动取消勾选排在最后的几项。
    private func 应用样式(_ 新样式: 作品列表样式) {
        guard 新样式 != 当前样式 else { return }
        let 限制后 = Self.限制数量(整理后, 样式: 新样式)
        withAnimation(.bouncy) {
            设置.设置样式(新样式, for: 场景)
            if 限制后 != 整理后 { 设置.设置配置(限制后, for: 场景) }
        }
    }

    var body: some View {
        List {
            Section {
                let 已满 = Self.计入数量的项数(整理后, 样式: 当前样式) >= 当前样式.最多信息数
                ForEach(整理后.项) { 条目 in
                    // 已经选满时，其他计入数量的信息变灰、不能再勾选
                    let 不可选 = 已满 && !条目.显示 && Self.计入数量(条目.信息, 样式: 当前样式)
                    Button {
                        切换(条目.信息)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: 条目.显示 ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(条目.显示 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                .contentTransition(.symbolEffect(.replace))
                                .symbolEffect(.bounce, value: 条目.显示)
                            Label {
                                Text(verbatim: 条目.信息.localizedTitle)
                            } icon: {
                                Image(systemName: 条目.信息.symbolName)
                            }
                            .foregroundStyle(不可选 ? .tertiary : .primary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(不可选)
                    .accessibilityAddTraits(条目.显示 ? .isSelected : [])
                }
                .onMove { source, destination in
                    var 项 = 整理后.项
                    项.move(fromOffsets: source, toOffset: destination)
                    更新(作品列表配置(项: 项))
                }
            } header: {
                // 样式选择器直接放在信息列表上方，不单独占一个分组
                Picker("样式", selection: $选中样式) {
                    ForEach(作品列表样式.allCases) { 样式 in
                        Text(verbatim: 样式.localizedTitle).tag(样式)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .textCase(nil)
                .padding(.horizontal, -16)
                .padding(.bottom, 8)
            } footer: {
                Text("当前样式最多显示\(当前样式.最多信息数)项信息。按住并拖移可以更改顺序。")
            }

            Section {
                Button("恢复默认") {
                    选中样式 = .standard
                    更新(Self.限制数量(场景.默认配置, 样式: .standard))
                }
                .disabled(整理后 == 场景.默认配置 && 当前样式 == .standard)
            }
        }
        // 始终显示拖移控制；没有删除操作，所以不会出现删除按钮
        .environment(\.editMode, .constant(.active))
        .平台分组列表样式()
        // 列表往上滚了多少：没滚动时预览没有阴影，内容开始滚到预览下面时才逐渐出现
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, 偏移 in
            滚动偏移 = 偏移
        }
        // 往上滚的列表滑到预览卡片下面，被卡片挡住后隐去，不会从预览上方露出来：
        // 遮罩的上边缘在卡片里面（卡片底部往上一个圆角的高度），切口藏在卡片后面看不见；
        // 左右和下边都不收，列表的其他部分不会被切掉
        .mask {
            GeometryReader { _ in
                Rectangle()
                    .padding(.top, -(预览下边距 + 卡片圆角))
            }
            .ignoresSafeArea(edges: [.horizontal, .bottom])
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            预览卡片
        }
        .onChange(of: 选中样式) { _, 新样式 in
            应用样式(新样式)
        }
        // 以前存的设置可能超出当前样式的数量，打开时按同样的规则取消勾选多出来的
        .onAppear {
            let 限制后 = Self.限制数量(整理后, 样式: 当前样式)
            if 限制后 != 整理后 { 设置.设置配置(限制后, for: 场景) }
        }
        .navigationTitle(标题)
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
    }

    // MARK: 预览

    @作品列表标题偏好读取 private var 标题偏好
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let 预览内边距: CGFloat = 12
    private let 预览下边距: CGFloat = 8

    /// 与封面同心：封面圆角加上封面到卡片边缘的距离。
    private var 卡片圆角: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) + 预览内边距
    }

    @State private var 滚动偏移: CGFloat = 0
    /// 没滚动时没有阴影，往上滚 24pt 内逐渐出现。
    private var 阴影可见度: CGFloat { min(max(滚动偏移 / 24, 0), 1) }

    /// 悬浮在列表上方，不放进列表：列表单元格高度变化时没有动画，封面会直接跳位。
    /// 往上滚的列表从预览下面滑进去，预览投下阴影；预览后面不填任何颜色。
    private var 预览卡片: some View {
        let 示例 = 作品列表示例.全部(场景: 场景, 标题偏好: 标题偏好)
        return VStack(spacing: 0) {
            ForEach(Array(示例.enumerated()), id: \.element.id) { index, 条目 in
                if index > 0 {
                    Divider()
                        .padding(.leading, 列表封面布局.宽度 + 12)
                        .padding(.vertical, 预览内边距)
                }
                作品列表示例行(场景: 场景, 条目: 条目)
            }
        }
        .padding(预览内边距)
        .background(Color.平台次级分组背景, in: RoundedRectangle(cornerRadius: 卡片圆角, style: .continuous))
        .padding(.horizontal, 16)
        // 列表滚到预览下面时投下阴影，看得出内容是从预览下面滑过去的
        .shadow(color: .black.opacity(0.12 * 阴影可见度), radius: 12, y: 6)
        .padding(.top, 4)
        .padding(.bottom, 预览下边距)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("预览"))
    }

    /// 计入样式数量限制的信息：日期、评分等；详细风格里状态也是其中一行。
    private static func 计入数量(_ 信息: 作品列表信息, 样式: 作品列表样式) -> Bool {
        信息.是元数据 || (信息 == .status && 样式 == .detailed)
    }

    private static func 计入数量的项数(_ 配置: 作品列表配置, 样式: 作品列表样式) -> Int {
        配置.项.filter { $0.显示 && 计入数量($0.信息, 样式: 样式) }.count
    }

    /// 超出样式可选数量时，从下往上取消勾选，直到不超出。
    private static func 限制数量(_ 配置: 作品列表配置, 样式: 作品列表样式) -> 作品列表配置 {
        var 结果 = 配置
        var 超出 = 计入数量的项数(配置, 样式: 样式) - 样式.最多信息数
        for index in 结果.项.indices.reversed() where 超出 > 0 {
            if 结果.项[index].显示 && 计入数量(结果.项[index].信息, 样式: 样式) {
                结果.项[index].显示 = false
                超出 -= 1
            }
        }
        return 结果
    }

    private func 切换(_ 信息: 作品列表信息) {
        var 项 = 整理后.项
        guard let index = 项.firstIndex(where: { $0.信息 == 信息 }) else { return }
        项[index].显示.toggle()
        更新(作品列表配置(项: 项))
    }
}

#if DEBUG
#Preview("列表信息") {
    NavigationStack {
        列表信息设置页面(场景: .search)
    }
}
#endif
