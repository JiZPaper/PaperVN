import SwiftUI

/// 加入资料库后，同一系列还有作品没加入时提醒（见 `系列补全`），可以选择后一起加入。
private struct 系列补全提醒修饰器: ViewModifier {
    @Binding var 结果: 系列补全.结果?
    let 添加: ([系列补全.作品]) async throws -> Void

    @State private var 选择中: 系列补全.结果?

    func body(content: Content) -> some View {
        content
            .alert(
                "要添加此系列的其他作品吗？",
                isPresented: Binding(
                    get: { 结果 != nil },
                    set: { if !$0 { 结果 = nil } }
                ),
                presenting: 结果
            ) { result in
                Button("忽略", role: .cancel) {
                    系列补全.忽略(result)
                }
                Button("选择作品…") {
                    选择中 = result
                }
            } message: { result in
                Text("此系列还有\(result.作品.count)部作品尚未添加到资料库。")
            }
            .sheet(item: $选择中) { result in
                系列作品选择(作品: result.作品, 添加: 添加)
                    .平台近全屏弹窗()
            }
    }
}

extension View {
    /// `添加` 按列表顺序把选中的作品加入资料库。
    func 系列补全提醒(
        _ 结果: Binding<系列补全.结果?>,
        添加: @escaping ([系列补全.作品]) async throws -> Void
    ) -> some View {
        modifier(系列补全提醒修饰器(结果: 结果, 添加: 添加))
    }
}

/// 选择同一系列里要一起加入资料库的作品，默认全部选中。
struct 系列作品选择: View {
    let 作品: [系列补全.作品]
    let 添加: ([系列补全.作品]) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var confirmation = 模糊解除确认器()
    @作品列表标题偏好读取 private var 标题偏好
    @State private var 已选: Set<String>
    @State private var 正在添加 = false
    @State private var 错误: String?

    init(作品: [系列补全.作品], 添加: @escaping ([系列补全.作品]) async throws -> Void) {
        self.作品 = 作品
        self.添加 = 添加
        _已选 = State(initialValue: Set(作品.map(\.id)))
    }

    var body: some View {
        NavigationStack {
            // 和“设置”里的多选列表一样，选中的在行尾显示勾号；左边的编辑圆圈太占地方
            List(作品) { work in
                let isSelected = 已选.contains(work.id)
                Button {
                    if isSelected { 已选.remove(work.id) } else { 已选.insert(work.id) }
                } label: {
                    HStack(spacing: 12) {
                        作品列表行(场景: .search, 内容: 行内容(work)) {
                            探索安全图片(
                                id: "series-\(work.id)",
                                url: work.条目.封面地址,
                                sexual: work.封面色情程度,
                                violence: work.封面暴力程度,
                                width: 列表封面布局.宽度,
                                height: 列表封面布局.高度,
                                confirmation: confirmation,
                                cornerRadius: 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass),
                                showsBorder: false
                            )
                        }
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            .disabled(正在添加)
            .navigationTitle(String(localized: "系列补全.选择作品", defaultValue: "选择作品"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .平台前导关闭操作) {
                    Button {
                        dismiss()
                    } label: {
                        Label("关闭", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if 正在添加 {
                        ProgressView()
                    } else {
                        添加按钮
                    }
                }
            }
            .alert(
                "无法添加到资料库",
                isPresented: Binding(
                    get: { 错误 != nil },
                    set: { if !$0 { 错误 = nil } }
                )
            ) {
                Button("好") {
                    错误 = nil
                }
            } message: {
                Text(verbatim: 错误 ?? "")
            }
        }
        .interactiveDismissDisabled(正在添加)
    }

    /// 右上角的添加按钮用强调色：iOS 26 是填色的玻璃按钮，iOS 18 的工具栏没有填色按钮，用加粗的加号。
    @ViewBuilder
    private var 添加按钮: some View {
        let button = Button {
            addSelected()
        } label: {
            Label(String(localized: "系列补全.添加", defaultValue: "添加"), systemImage: "plus")
        }
        .disabled(已选.isEmpty)
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.fontWeight(.semibold)
        }
    }

    private func 行内容(_ work: 系列补全.作品) -> 作品列表行内容 {
        let entry = work.条目
        let titles = 作品标题覆盖.shared.应用(entry.多语言标题, 作品键: entry.id, 类型: entry.类型) ?? entry.多语言标题
        var content = 作品列表行内容(
            主标题: 标题偏好.主标题(titles, 默认: entry.标题),
            副标题: 标题偏好.副标题(titles, 默认: entry.标题)
        )
        content.类型 = entry.类型
        content.发行日期 = work.日期
        return content
    }

    private func addSelected() {
        let selected = 作品.filter { 已选.contains($0.id) }
        guard !selected.isEmpty, !正在添加 else { return }
        正在添加 = true
        Task {
            defer { 正在添加 = false }
            do {
                try await 添加(selected)
                dismiss()
            } catch is CancellationError {
                return
            } catch {
                错误 = error.localizedDescription
            }
        }
    }
}
