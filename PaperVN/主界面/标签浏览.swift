import SwiftUI

/// 从详情页的标签进入的列表：同时带有这些标签的视觉小说、角色（VNDB 的特征），或动画、漫画与轻小说（AniList 的类型与标签）。
/// 列表就是搜索页的浏览模式，对象固定；页面顶部的标签可以增减，其他条件在“筛选”里加，都只影响这一页，不改搜索 Tab。
struct 标签浏览: Hashable, Identifiable {
    enum 种类: Hashable {
        case 视觉小说
        case 角色
        case 作品(作品类型)
    }

    struct 标签: Hashable, Identifiable {
        /// 筛选用的值：VNDB 标签或特征的编号，AniList 类型或标签的原名
        let 值: String
        let 名称: String
        var id: String { 值 }
    }

    let 对象: 种类
    let 已选: [标签]
    /// 来源作品或角色的标签（按详情页的顺序），“+”菜单里先列出这些
    let 候选: [标签]

    var id: String { "\(对象)|" + 已选.map(\.值).joined(separator: ",") }
}

extension 标签浏览.标签 {
    /// 特征的名称带上所属的组，例如“棕色（头发）”：发色和瞳色都有“棕色”，只写名称分不清。
    static func 特征(值: String, 名称: String, 分组: String) -> Self {
        guard !分组.isEmpty else { return .init(值: 值, 名称: 名称) }
        return .init(值: 值, 名称: String(localized: "\(名称)（\(分组)）"))
    }
}

extension 标签浏览.种类 {
    var 是特征: Bool { self == .角色 }

    /// 详情页按住标签时的菜单项。
    var 查看单个标签标题: String {
        switch self {
        case .视觉小说: String(localized: "查看带有此标签的视觉小说")
        case .角色: String(localized: "查看带有此特征的角色")
        case .作品(.anime): String(localized: "查看带有此标签的动画")
        case .作品(.manga): String(localized: "查看带有此标签的漫画")
        case .作品(.lightNovel): String(localized: "查看带有此标签的轻小说")
        case .作品(.visualNovel): String(localized: "查看带有此标签的视觉小说")
        }
    }

    /// 结果页“+”菜单里来源作品或角色那一组的标题。
    var 候选标题: String {
        是特征 ? String(localized: "此角色的特征") : String(localized: "此作品的标签")
    }

    var 所有标签标题: String {
        是特征 ? String(localized: "所有特征…") : String(localized: "所有标签…")
    }

    var 添加标题: String {
        是特征 ? String(localized: "添加特征") : String(localized: "添加标签")
    }

    var 同时带有说明: String {
        是特征 ? String(localized: "同时带有以上所有特征") : String(localized: "同时带有以上所有标签")
    }

    var 图标: String {
        是特征 ? 搜索扩展筛选字段.trait.systemImage : "tag"
    }

    func 标题(数量 count: Int) -> String {
        if 是特征 {
            return count == 0 ? String(localized: "特征") : String(localized: "\(count)个特征")
        }
        return count == 0 ? String(localized: "标签") : String(localized: "\(count)个标签")
    }
}

/// 全部标签、全部特征页面的多选：轻点“选择”后勾选，底部“查看结果”；不在选择时轻点一个标签直接进入。
struct 标签多选: Equatable {
    var 正在选择 = false
    var 已选: [标签浏览.标签] = []
    var 目标: 标签浏览?

    func 选中(_ 值: String) -> Bool {
        已选.contains { $0.值 == 值 }
    }

    /// `全部` 是页面上能筛选的所有标签，按显示顺序，进入后作为“+”菜单的候选。
    mutating func 轻点(_ tag: 标签浏览.标签, 对象: 标签浏览.种类, 全部: [标签浏览.标签]) {
        if 正在选择 {
            if let index = 已选.firstIndex(where: { $0.值 == tag.值 }) {
                已选.remove(at: index)
            } else {
                已选.append(tag)
            }
        } else {
            目标 = 标签浏览(对象: 对象, 已选: [tag], 候选: 全部)
        }
    }
}

private struct 标签多选修饰器: ViewModifier {
    @Binding var 状态: 标签多选
    let 对象: 标签浏览.种类
    let 全部: [标签浏览.标签]

    func body(content: Content) -> some View {
        content
            .toolbar {
                if !全部.isEmpty {
                    ToolbarItem(placement: .平台主操作) {
                        Button {
                            withAnimation(.snappy(duration: 0.24)) {
                                状态.正在选择.toggle()
                                状态.已选 = []
                            }
                        } label: {
                            状态.正在选择 ? Text("取消") : Text("选择")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if 状态.正在选择 {
                    Button {
                        状态.目标 = 标签浏览(对象: 对象, 已选: 状态.已选, 候选: 全部)
                    } label: {
                        Text("查看结果")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .液态玻璃醒目按钮(in: Capsule())
                    .disabled(状态.已选.isEmpty)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationDestination(item: $状态.目标) { 浏览 in
                搜索(showsSearchField: false, 标签浏览: 浏览)
            }
            .onChange(of: 状态.目标) { _, 目标 in
                // 从结果页返回后退出选择
                guard 目标 == nil, 状态.正在选择 else { return }
                状态.正在选择 = false
                状态.已选 = []
            }
    }
}

extension View {
    /// 全部标签、全部特征页面的“选择”按钮、底部“查看结果”和进入结果页。
    func 支持标签多选(_ 状态: Binding<标签多选>, 对象: 标签浏览.种类, 全部: [标签浏览.标签]) -> some View {
        modifier(标签多选修饰器(状态: 状态, 对象: 对象, 全部: 全部))
    }

    /// 详情页的内联标签：按住时“查看带有此标签的…”。`tag` 为 nil（模糊中或不能筛选）时没有菜单。
    func 标签浏览菜单(
        _ tag: 标签浏览.标签?,
        对象: 标签浏览.种类,
        全部: [标签浏览.标签],
        目标: Binding<标签浏览?>
    ) -> some View {
        // 菜单内容为空时系统不弹出菜单，模糊中的标签按住没有反应
        contentShape(.contextMenuPreview, Capsule())
        .contextMenu {
            if let tag {
                Button {
                    目标.wrappedValue = 标签浏览(对象: 对象, 已选: [tag], 候选: 全部)
                } label: {
                    Label(对象.查看单个标签标题, systemImage: 对象.图标)
                }
            }
        }
    }
}

/// 结果页顶部的标签：每个可以移除（只剩一个时不能），末尾“+”加来源作品的其他标签或打开筛选选择任意标签。
struct 标签浏览栏: View {
    let 对象: 标签浏览.种类
    /// 当前的标签（值与显示名称）
    let 标签: [标签浏览.标签]
    let 候选: [标签浏览.标签]
    /// 这组条件是否还是“同时带有”（在筛选里改成“任一”或“排除”后不显示说明）
    let 同时带有: Bool
    let 移除: (String) -> Void
    let 添加: (标签浏览.标签) -> Void
    let 打开筛选: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(标签) { tag in
                        胶囊(tag)
                    }
                    添加菜单
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            if 同时带有, 标签.count > 1 {
                Text(verbatim: 对象.同时带有说明)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func 胶囊(_ tag: 标签浏览.标签) -> some View {
        let 可移除 = 标签.count > 1
        return Button {
            guard 可移除 else { return }
            withAnimation(.snappy(duration: 0.24)) { 移除(tag.值) }
        } label: {
            HStack(spacing: 5) {
                Text(verbatim: tag.名称)
                    .lineLimit(1)
                if 可移除 {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 4)
        }
        .buttonBorderShape(.capsule)
        .液态玻璃按钮(in: Capsule())
        .allowsHitTesting(可移除)
        .accessibilityLabel(Text(verbatim: tag.名称))
        .accessibilityHint(可移除 ? Text("移除") : Text(verbatim: ""))
    }

    private var 添加菜单: some View {
        let 已有 = Set(标签.map(\.值))
        // 候选按相关度排列，只列前面的，“所有标签…”不会被挤到菜单很下面
        let 可加 = 候选.filter { !已有.contains($0.值) }.prefix(8)
        return Menu {
            if !可加.isEmpty {
                Section(对象.候选标题) {
                    ForEach(Array(可加)) { tag in
                        Button {
                            withAnimation(.snappy(duration: 0.24)) { 添加(tag) }
                        } label: {
                            Label {
                                Text(verbatim: tag.名称)
                            } icon: {
                                Image(systemName: 对象.图标)
                            }
                        }
                    }
                }
            }
            Button(action: 打开筛选) {
                Label(对象.所有标签标题, systemImage: "line.3.horizontal.decrease")
            }
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(height: 20)
        }
        .buttonBorderShape(.capsule)
        .液态玻璃按钮(in: Capsule())
        .accessibilityLabel(Text(verbatim: 对象.添加标题))
    }
}
