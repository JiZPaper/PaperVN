import SwiftUI
import UIKit

/// 启动时向用户介绍新功能：一页一个功能，每页附带可以直接上手的演示。
/// 修订号变了才会再显示；只写新增和重新设计的功能，不写问题修复。
enum 新功能介绍 {
    static let 修订号 = "2026.11"
    static let 已读修订号键 = "PaperVN.whatsNew.seenRevision"

    static var 应显示: Bool {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              !ProcessInfo.processInfo.arguments.contains("-PaperVNSkipWhatsNew") else {
            return false
        }
        return UserDefaults.standard.string(forKey: 已读修订号键) != 修订号
    }

    static func 标记已读() {
        UserDefaults.standard.set(修订号, forKey: 已读修订号键)
    }
}

enum 新功能页面: Hashable, CaseIterable {
    case Paper账户
    /// 只在用户于“Paper账户”一页登录后出现
    case 高级数据保护
    case 按标签搜索

    /// 在此弹窗中登录了Paper账户，才在它后面加入“高级数据保护”。
    static func 当前页面(已在此登录: Bool) -> [Self] {
        allCases.filter { $0 != .高级数据保护 || 已在此登录 }
    }

    var 标题: LocalizedStringKey {
        switch self {
        case .Paper账户: "Paper账户"
        case .高级数据保护: "高级数据保护"
        case .按标签搜索: "按标签搜索"
        }
    }

    var 副标题: LocalizedStringKey {
        switch self {
        case .Paper账户: "在设备之间同步资料库"
        case .高级数据保护: "端对端加密你的资料库"
        case .按标签搜索: "按住标签即可搜索"
        }
    }

    var 说明: LocalizedStringKey {
        switch self {
        case .Paper账户:
            "用于同步资料库、反馈、贡献翻译和Today推荐。删除PaperVN后重新登录即可恢复资料库。"
        case .高级数据保护:
            "对于你的大多数Paper Cloud数据，只有你的受信任设备可以访问对应的加密密钥。任何其他人，甚至是开发者，都无法访问这些数据。"
        case .按标签搜索:
            "在详情页面中按住标签或特征，即可搜索带有它的作品或角色，还可以在结果顶部添加更多标签。按住下方的标签试试。"
        }
    }
}

struct 新功能介绍页面: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var account = PaperAccount账户.shared
    @State private var 序号 = 0
    /// 换页方向：向后翻时新页面从右侧进入，返回时从左侧进入。
    @State private var 向后翻页 = true
    /// 在“Paper账户”一页登录后，下一页介绍高级数据保护。
    @State private var 已在此登录 = false
    private var 页面: [新功能页面] { 新功能页面.当前页面(已在此登录: 已在此登录) }

    private var 是最后一页: Bool { 序号 == 页面.count - 1 }

    var body: some View {
        NavigationStack {
            ZStack {
                新功能单页(页面: 页面[序号], 是第一页: 序号 == 0)
                    .id(页面[序号])
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: 向后翻页 ? .trailing : .leading),
                                removal: .move(edge: 向后翻页 ? .leading : .trailing)
                            )
                    )
            }
            .平台柔和滚动边缘(for: .bottom)
            .平台安全区域栏(edge: .bottom) {
                VStack(spacing: 14) {
                    页数指示
                    继续按钮
                        .frame(maxWidth: 320)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            // 第一页没有返回按钮，导航栏也要保持显示，否则文字会比其他页面高
            .toolbarVisibility(.visible, for: .navigationBar)
            .toolbar {
                if 序号 > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            翻页(到: 序号 - 1)
                        } label: {
                            Label("上一页", systemImage: "chevron.backward")
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: account.isLoggedIn) { 之前, 现在 in
            if !之前, 现在 { 已在此登录 = true }
        }
    }

    /// 与系统的页面指示器一样：当前页是一个拉长的胶囊，其余是小圆点。
    private var 页数指示: some View {
        HStack(spacing: 8) {
            ForEach(页面.indices, id: \.self) { 位置 in
                Capsule()
                    .fill(位置 == 序号 ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 位置 == 序号 ? 20 : 8, height: 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: 序号)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("第\(序号 + 1)页，共\(页面.count)页"))
    }

    @ViewBuilder
    private var 继续按钮: some View {
        let 按钮 = Button {
            if 是最后一页 {
                onFinish()
            } else {
                翻页(到: 序号 + 1)
            }
        } label: {
            Text(是最后一页 ? "开始使用PaperVN" : "继续")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)

        if #available(iOS 26.0, *) {
            按钮.buttonStyle(.glassProminent)
        } else {
            按钮.buttonStyle(.borderedProminent)
        }
    }

    /// 先更新方向，下一帧再换页：被移除的页面会沿用它上一次渲染时的转场，
    /// 方向和换页放在同一次更新里，返回时旧页面会往错误的方向滑出。
    private func 翻页(到 目标: Int) {
        guard 页面.indices.contains(目标), 目标 != 序号 else { return }
        向后翻页 = 目标 > 序号
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.4)) {
                序号 = 目标
            }
        }
    }
}

private struct 新功能单页: View {
    let 页面: 新功能页面
    let 是第一页: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    if 是第一页 {
                        Text("PaperVN新功能")
                            .font(.headline)
                            .foregroundStyle(.tint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(页面.标题)
                            .foregroundStyle(.primary)
                        Text(页面.副标题)
                            .foregroundStyle(.secondary)
                    }
                    .font(.largeTitle.bold())
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                Text(页面.说明)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                演示
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // 内容从页数指示上方开始渐渐淡出，在底栏（页数指示、继续按钮、主屏幕指示器）下面持续变淡直到屏幕底部，
        // 不会中途突然断开；页数指示处只剩淡淡的内容，不影响辨认。底部安全区域已包含底栏高度
        .mask {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.2), location: 0.25),
                            .init(color: .black.opacity(0.06), location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.safeAreaInsets.bottom + 24)
                }
                .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var 演示: some View {
        switch 页面 {
        case .Paper账户: Paper账户演示()
        case .高级数据保护: 高级数据保护演示()
        case .按标签搜索: 按标签搜索演示()
        }
    }
}

// MARK: - 演示通用

/// 演示用的作品数据（取自VNDB）：只在本页面中显示，不会写入资料库。
/// 封面都是VNDB标为安全的图片，存储在“新功能演示”素材中，无需联网。
private struct 演示作品: Identifiable {
    let id: String
    let 标题: String
    let 副标题: String
    let 开发商: String
    let 日期: String
    let 评分: String?
    let 封面: String?
    let 颜色: Color
    let 符号: String

    static let SummerPockets = 演示作品(
        id: "v20424",
        标题: "Summer Pockets",
        副标题: "Summer Pockets",
        开发商: "Key",
        日期: "2018-06-29",
        评分: "8.46",
        封面: "WhatsNewSummerPockets",
        颜色: .cyan,
        符号: "sun.max"
    )
    static let 夏日绚烂之中 = 演示作品(
        id: "v50957",
        标题: String(localized: "夏日口袋：夏日绚烂之中"),
        副标题: "「Summer Pockets」ショートストーリー ～夏の眩しさの中で～【空門 蒼 編】",
        开发商: "Guangda Gal Jiaoliu Hui",
        日期: "2024-04-07",
        评分: "7.42",
        封面: nil,
        颜色: .teal,
        符号: "book.closed"
    )
    static let ATRI = 演示作品(
        id: "v27448",
        标题: String(localized: "亚托莉 -我挚爱的时光-"),
        副标题: "ATRI -My Dear Moments-",
        开发商: "Makura",
        日期: "2020-06-18",
        评分: "7.76",
        封面: "WhatsNewATRICover",
        颜色: .blue,
        符号: "water.waves"
    )
}

private struct 演示封面: View {
    let 颜色: Color
    let 符号: String
    var 图片: String?
    var 宽度: CGFloat = 54

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let 圆角 = 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
            * 宽度 / 列表封面布局.宽度
        let 形状 = RoundedRectangle(cornerRadius: 圆角, style: .continuous)
        形状
            .fill(颜色.gradient)
            .overlay {
                if let 图片 {
                    Image(图片)
                        .resizable()
                        .scaledToFill()
                } else {
                    占位符号
                }
            }
            .frame(
                width: 宽度,
                height: 宽度 * 列表封面布局.高度 / 列表封面布局.宽度
            )
            .clipShape(形状)
            .accessibilityHidden(true)
    }

    private var 占位符号: some View {
        Image(systemName: 符号)
            .font(.system(size: 宽度 * 0.38, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
    }
}

extension Color {
    /// 弹窗在深色模式下是抬升的背景，分组背景会和它混在一起；
    /// 演示区域固定使用基础层级的分组背景，里面的卡片仍与真实页面一致。
    static let 演示区域背景 = Color(uiColor: UIColor { traits in
        UIColor.systemGroupedBackground.resolvedColor(
            with: traits.modifyingTraits { $0.userInterfaceLevel = .base }
        )
    })
}

/// 放演示内容的灰色圆角区域。
/// 外框圆角 = 贴边内容的圆角 + 内边距，与内容保持同心。
private struct 演示区域<Content: View>: View {
    var 内边距: CGFloat = 12
    var 内层圆角: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(内边距)
            .frame(maxWidth: .infinity)
            .background(
                Color.演示区域背景,
                in: RoundedRectangle(cornerRadius: 内层圆角 + 内边距, style: .continuous)
            )
    }
}

/// 演示中可以直接更改真实设置的一行。
private struct 演示设置行<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(
                Color.演示区域背景,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
    }
}

/// 演示操作后的反馈，显示一会儿后自动消失。
private struct 演示反馈: View {
    @Binding var 文本: String?

    var body: some View {
        ZStack {
            if let 文本 {
                Text(verbatim: 文本)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.演示区域背景, in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .id(文本)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36)
        .animation(.smooth(duration: 0.25), value: 文本)
        .accessibilityElement(children: .combine)
        .task(id: 文本) {
            guard let 文本 else { return }
            UIAccessibility.post(notification: .announcement, argument: 文本)
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.文本 = nil
        }
    }
}

private struct 演示元数据标签样式: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

// MARK: - Paper账户

/// 真实的“通过Apple登录”按钮；登录后换成账户状态，并在下一页介绍高级数据保护。
private struct Paper账户演示: View {
    @ObservedObject private var account = PaperAccount账户.shared
    @State private var 错误信息: String?

    var body: some View {
        Group {
            if let 资料 = account.资料 {
                演示设置行 {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.title2)
                            .foregroundStyle(.indigo)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Paper账户")
                                .font(.body.weight(.semibold))
                            if let 昵称 = 资料.nickname, !昵称.isEmpty {
                                Text(verbatim: 昵称)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Label("已登录", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.vertical, 10)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            } else {
                Paper账户登录按钮(errorMessage: $错误信息)
                    .frame(maxWidth: 320)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: account.isLoggedIn)
        .task {
            if !account.isLoggedIn { await account.准备登录() }
        }
        .alert("Paper账户", isPresented: Binding(get: { 错误信息 != nil }, set: { if !$0 { 错误信息 = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: 错误信息 ?? "")
        }
    }
}

// MARK: - 高级数据保护

/// 与Paper账户页面相同的真实开关：打开高级数据保护时同样先确认并设置恢复密钥。
private struct 高级数据保护演示: View {
    @ObservedObject private var account = PaperAccount账户.shared
    @State private var 错误信息: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            演示设置行 {
                Toggle("Paper Cloud", isOn: Binding(get: { account.自动备份 }, set: { account.自动备份 = $0 }))
            }
            演示设置行 {
                高级数据保护开关(errorMessage: $错误信息)
            }
            Text("将资料库上传到Paper Cloud，并在你的设备之间同步。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Paper账户", isPresented: Binding(get: { 错误信息 != nil }, set: { if !$0 { 错误信息 = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: 错误信息 ?? "")
        }
    }
}

// MARK: - 按标签搜索

/// 详情页面的标签：按住时的菜单与真实页面相同（标签浏览菜单），选取后换成结果页顶部的标签栏（标签浏览栏）和结果。
/// 标签只是演示数据，结果只在这几部演示作品里筛选。
private struct 按标签搜索演示: View {
    private static let 夏天 = 标签浏览.标签(值: "summer", 名称: String(localized: "夏天"))
    private static let 岛屿 = 标签浏览.标签(值: "island", 名称: String(localized: "岛屿"))
    private static let 海边 = 标签浏览.标签(值: "seaside", 名称: String(localized: "海边"))
    private static let 乡村 = 标签浏览.标签(值: "countryside", 名称: String(localized: "乡村"))

    /// 详情页面上的作品和它的标签
    private let 来源 = 演示作品.SummerPockets
    private let 来源标签 = [夏天, 岛屿, 海边, 乡村]

    private let 作品标签: [(作品: 演示作品, 标签: Set<String>)] = [
        (.SummerPockets, ["summer", "island", "seaside", "countryside"]),
        (.ATRI, ["summer", "seaside", "countryside"]),
        (.夏日绚烂之中, ["summer", "island"]),
    ]

    @State private var 目标: 标签浏览?
    @State private var 当前标签: [标签浏览.标签] = []
    @State private var 反馈: String?

    private let 内层圆角: CGFloat = 22

    var body: some View {
        VStack(spacing: 10) {
            演示区域(内边距: 12, 内层圆角: 内层圆角) {
                ZStack(alignment: .topLeading) {
                    if 当前标签.isEmpty {
                        详情
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    } else {
                        结果
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 内层圆角 + 12, style: .continuous))

            演示反馈(文本: $反馈)
        }
        .onChange(of: 目标) { _, 新目标 in
            guard let 新目标 else { return }
            withAnimation(.smooth(duration: 0.35)) { 当前标签 = 新目标.已选 }
            反馈 = String(localized: "演示已完成")
        }
    }

    private var 详情: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                演示封面(颜色: 来源.颜色, 符号: 来源.符号, 图片: 来源.封面, 宽度: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: 来源.标题)
                        .font(.headline)
                        .lineLimit(1)
                    Text(verbatim: 来源.开发商)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            FlowLayout(spacing: 8) {
                ForEach(来源标签) { tag in
                    标签胶囊(tag)
                }
            }
        }
        .padding(4)
    }

    /// 与详情页面的内联标签相同：内容类标签的图标、半透明提亮材质的胶囊。
    private func 标签胶囊(_ tag: 标签浏览.标签) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "book.pages.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tint)
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
            Text(verbatim: tag.名称)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .高透明提亮材质背景(in: Capsule())
        .contentShape(Capsule())
        .标签浏览菜单(tag, 对象: .视觉小说, 全部: 来源标签, 来源: 来源.标题, 目标: $目标)
    }

    private var 结果: some View {
        let 已选 = Set(当前标签.map(\.值))
        let 结果作品 = 作品标签.filter { 已选.isSubset(of: $0.标签) }.map(\.作品)

        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.smooth(duration: 0.35)) {
                    当前标签 = []
                    目标 = nil
                }
            } label: {
                Label {
                    Text(verbatim: 来源.标题)
                } icon: {
                    Image(systemName: "chevron.backward")
                }
                .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .padding(.bottom, 4)

            // 与搜索页一样贴着两侧滚动
            标签浏览栏(
                对象: .视觉小说,
                标签: 当前标签,
                候选: 来源标签,
                来源名称: 来源.标题,
                同时带有: true,
                移除: { 值 in 当前标签.removeAll { $0.值 == 值 } },
                添加: { tag in 当前标签.append(tag) },
                打开筛选: { 反馈 = String(localized: "演示已完成") }
            )
            .padding(.horizontal, -12)

            VStack(spacing: 0) {
                ForEach(Array(结果作品.enumerated()), id: \.element.id) { 位置, 作品 in
                    if 位置 > 0 {
                        Divider().padding(.leading, 12 + 44 + 10)
                    }
                    作品行(作品)
                }
            }
            .padding(.vertical, 4)
            .background(
                Color(uiColor: .secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 内层圆角, style: .continuous)
            )
            .animation(.smooth(duration: 0.3), value: 当前标签)
        }
    }

    private func 作品行(_ 作品: 演示作品) -> some View {
        HStack(spacing: 10) {
            演示封面(颜色: 作品.颜色, 符号: 作品.符号, 图片: 作品.封面, 宽度: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: 作品.标题)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(作品.日期, systemImage: "calendar")
                    if let 评分 = 作品.评分 {
                        Label(评分, systemImage: "chart.bar.xaxis")
                    }
                }
                .labelStyle(演示元数据标签样式())
                .lineLimit(1)
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }
}

#if DEBUG
#Preview("新功能介绍") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            新功能介绍页面 {}
                .预览环境()
        }
}

extension 新功能介绍页面 {
    /// 预览用：从指定的一页开始显示。
    init(起始页面: 新功能页面, onFinish: @escaping () -> Void) {
        self.init(onFinish: onFinish)
        _已在此登录 = State(initialValue: 起始页面 == .高级数据保护)
        _序号 = State(initialValue: 新功能页面.当前页面(已在此登录: 起始页面 == .高级数据保护)
            .firstIndex(of: 起始页面) ?? 0)
    }
}

#Preview("新功能介绍：各页") {
    预览状态切换(新功能页面.allCases.map { 页面 in
        .init(名称: Text(页面.标题)) { 新功能介绍页面(起始页面: 页面) {} }
    })
    .预览环境()
}
#endif
