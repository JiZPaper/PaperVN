import StoreKit
import SwiftUI
import UIKit

/// 启动时向用户介绍新功能：一页一个功能，每页附带可以直接上手的演示。
/// 修订号变了才会再显示；只写新增和重新设计的功能，不写问题修复。
enum 新功能介绍 {
    static let 修订号 = "2026.10"
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
    case 全新搜索
    case 独立搜索Tab
    case 设置
    case 紧急回避
    case 拷贝
    case 补标
    case 推荐视觉小说
    case 贡献翻译
    /// 最后一页：开源与支持PaperVN
    case 开源

    /// “独立搜索Tab”只在iOS 27中提供。
    static var 当前系统页面: [Self] {
        allCases.filter { 页面 in
            if 页面 == .独立搜索Tab {
                if #available(iOS 27.0, *) { return true }
                return false
            }
            return true
        }
    }

    var 标题: LocalizedStringKey {
        switch self {
        case .全新搜索: "全新搜索"
        case .独立搜索Tab: "独立搜索Tab"
        case .设置: "重新设计的设置"
        case .紧急回避: "紧急回避"
        case .拷贝: "拷贝标题与名称"
        case .补标: "补标"
        case .推荐视觉小说: "推荐视觉小说"
        case .贡献翻译: "贡献翻译"
        case .开源: "PaperVN已开源"
        }
    }

    var 副标题: LocalizedStringKey {
        switch self {
        case .全新搜索: "输入几个字就能找到"
        case .独立搜索Tab: "让搜索单独显示"
        case .设置: "更快找到你要的选项"
        case .紧急回避: "翻转一下，立即隐藏"
        case .拷贝: "按住即可拷贝"
        case .补标: "补上真实的游玩日期"
        case .推荐视觉小说: "分享你喜欢的作品"
        case .贡献翻译: "让更多人读懂简介"
        case .开源: "而且永远免费"
        }
    }

    var 说明: LocalizedStringKey {
        switch self {
        case .全新搜索:
            "由Hiro智能驱动。自动排序，具有错拼纠正与模糊搜索能力。轻点下方的搜索词试试。"
        case .独立搜索Tab:
            "开启后，“搜索”将与其他Tab分开，显示在标签栏右侧。你也可以稍后在“设置”>“搜索”中更改。"
        case .设置:
            "按照iOS设置App重新设计。轻点下方的类别试试。"
        case .紧急回避:
            "紧急回避时使用最严格的安全限制直至退出App。"
        case .拷贝:
            "在详情页面中按住标题或名称即可拷贝各种语言的文本。按住下方的标题试试。"
        case .补标:
            "短时间内将视觉小说游玩状态从“计划游玩”修改为“已游玩”或“抛弃”时，询问是否修改自动填充的游玩日期。选取“已游玩”然后轻点“存储”试试。"
        case .推荐视觉小说:
            "写下你喜欢的视觉小说。通过后将作为“社区推荐”显示在Today中。轻点下方的横幅试试。"
        case .贡献翻译:
            "译文将在通过后加入VNDB-Description-Translations项目并在PaperVN App中使用。"
        case .开源:
            "过去一个月，我在PaperVN上的支出为\(PaperVN支出.本地货币金额)。如果你愿意做出行动支持PaperVN，我将感激不尽。"
        }
    }
}

struct 新功能介绍页面: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var 序号 = 0
    /// 换页方向：向后翻时新页面从右侧进入，返回时从左侧进入。
    @State private var 向后翻页 = true
    private let 页面 = 新功能页面.当前系统页面

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
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("上一页")
                    }
                }
            }
        }
        .interactiveDismissDisabled()
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
        case .全新搜索: 搜索演示()
        case .独立搜索Tab: 独立搜索Tab演示()
        case .设置: 设置演示()
        case .紧急回避: 紧急回避演示()
        case .拷贝: 拷贝演示()
        case .补标: 补标演示()
        case .推荐视觉小说: 推荐视觉小说演示()
        case .贡献翻译: 贡献翻译演示()
        case .开源: 支持PaperVN选项()
        }
    }
}

// MARK: - 演示通用

/// 演示用的作品数据（取自VNDB）：只在本页面中显示，不会写入资料库。
/// 封面与角色图片都是VNDB标为安全的图片，存储在“新功能演示”素材中，无需联网。
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
    static let SunnysideStories = 演示作品(
        id: "v69324",
        标题: "Summer Pockets Sunnyside Stories",
        副标题: "Summer Pockets Sunnyside Stories",
        开发商: "Key",
        日期: "2026-12-18",
        评分: nil,
        封面: nil,
        颜色: .orange,
        符号: "sun.horizon"
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
    static let 星空列车 = 演示作品(
        id: "v28297",
        标题: String(localized: "星空列车与白的旅行"),
        副标题: "星空鉄道とシロの旅",
        开发商: "Shiratamaco",
        日期: "2020-12-30",
        评分: "8.02",
        封面: "WhatsNewHoshizora",
        颜色: .indigo,
        符号: "tram"
    )
}

private struct 演示角色: Identifiable {
    let id: String
    let 名称: String
    let 图片: String
    let 颜色: Color

    static let 鸣濑白羽 = 演示角色(id: "c55091", 名称: String(localized: "鸣濑白羽"), 图片: "WhatsNewShiroha", 颜色: .cyan)
    static let 久岛鸥 = 演示角色(id: "c55092", 名称: String(localized: "久岛鸥"), 图片: "WhatsNewKamome", 颜色: .orange)
    static let 空门苍 = 演示角色(id: "c55093", 名称: String(localized: "空门苍"), 图片: "WhatsNewAo", 颜色: .blue)
    static let 亚托莉 = 演示角色(id: "c87815", 名称: String(localized: "亚托莉"), 图片: "WhatsNewAtriCharacter", 颜色: .blue)
    static let 斑鸠夏生 = 演示角色(id: "c87816", 名称: String(localized: "斑鸠夏生"), 图片: "WhatsNewNatsuki", 颜色: .gray)
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

private extension Color {
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

// MARK: - 全新搜索

private struct 搜索演示: View {
    private enum 搜索词: String, CaseIterable, Identifiable {
        case 亚托莉
        case 夏日岛可梦
        case 白羽

        var id: Self { self }

        /// 显示和输入的搜索词。“夏日岛可梦”是中文玩家的叫法，其他语言改用简称“SP”。
        var 查询: String {
            switch self {
            case .亚托莉: String(localized: "亚托莉")
            case .夏日岛可梦: String(localized: "夏日岛可梦")
            case .白羽: String(localized: "白羽")
            }
        }

        var 作品: 演示作品 {
            self == .亚托莉 ? .ATRI : .SummerPockets
        }

        /// 角色比作品更像搜索目标时自动展开，与搜索页面一致。
        var 自动展开: Bool { self == .白羽 }

        var 角色: [演示角色] {
            switch self {
            case .亚托莉: [.亚托莉, .斑鸠夏生]
            case .夏日岛可梦, .白羽: [.鸣濑白羽, .空门苍, .久岛鸥]
            }
        }

        var 系列: [演示作品] {
            self == .亚托莉 ? [] : [.SunnysideStories, .夏日绚烂之中]
        }

        var 分类数量: Int {
            (角色.isEmpty ? 0 : 1) + (系列.isEmpty ? 0 : 1)
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var 输入 = ""
    @State private var 结果: 搜索词?
    @State private var 正在搜索 = false
    @State private var 平铺数量 = 0
    @State private var 动画代次 = 0
    @State private var 输入任务: Task<Void, Never>?

    /// 与 iPad 上的搜索页面一致：排序和筛选在左上角，搜索框在右上角，结果分两列。
    private var iPad布局: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            演示区域(内层圆角: 卡片圆角) {
                VStack(spacing: 14) {
                    if iPad布局 {
                        HStack(spacing: 12) {
                            排序筛选按钮
                            Spacer(minLength: 0)
                            搜索框
                                .frame(maxWidth: 280)
                        }
                        // 弹窗比搜索页面窄，搜索结果一列优先占宽度，右列只示意还有其他结果
                        HStack(alignment: .top, spacing: 16) {
                            结果区域
                                .frame(maxWidth: .infinity)
                                .layoutPriority(1)
                            其他结果
                                .frame(width: 220)
                        }
                    } else {
                        搜索框
                        结果区域
                    }
                }
            }

            HStack(spacing: 8) {
                ForEach(搜索词.allCases) { 词 in
                    Button {
                        搜索(词)
                    } label: {
                        Text(verbatim: 词.查询)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(结果 == 词 ? .accentColor : .secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            guard 输入.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(500))
            搜索(.亚托莉)
        }
        .onDisappear { 输入任务?.cancel() }
    }

    private var 搜索框: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(verbatim: 输入.isEmpty ? String(localized: "搜索VNDB") : 输入)
                .foregroundStyle(输入.isEmpty ? .tertiary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if 正在搜索 {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color.平台次级分组背景, in: Capsule())
        .accessibilityElement(children: .combine)
    }

    /// iPad 工具栏左上角的排序和筛选按钮（只是外观）。
    private var 排序筛选按钮: some View {
        HStack(spacing: 18) {
            Image(systemName: "arrow.up.arrow.down")
            Image(systemName: "line.3.horizontal.decrease")
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Color.平台次级分组背景, in: Capsule())
        .accessibilityHidden(true)
    }

    /// 右列：示意其他搜索结果的淡色占位卡片，不放具体作品，免得把无关作品当成搜索结果。
    private var 其他结果: some View {
        VStack(spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 封面圆角, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 54, height: 54 * 列表封面布局.高度 / 列表封面布局.宽度)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach([1.0, 0.7, 0.45], id: \.self) { 比例 in
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .scaleEffect(x: 比例, anchor: .leading)
                        }
                    }
                }
                .padding(卡片内边距)
                .background(Color.平台次级分组背景, in: RoundedRectangle(cornerRadius: 卡片圆角, style: .continuous))
            }
        }
        .opacity(结果 == nil ? 0 : 0.6)
        .animation(.smooth(duration: 0.35), value: 结果)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var 结果区域: some View {
        ZStack(alignment: .top) {
            if let 结果 {
                VStack(spacing: 12) {
                    作品组(结果)
                }
                .transition(.opacity.combined(with: .offset(y: 8)))
            } else if 输入.isEmpty {
                Text("轻点下方的搜索词")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: 160, alignment: .top)
    }

    private var 已展开: Bool { 平铺数量 > 0 }

    private func 作品组(_ 词: 搜索词) -> some View {
        let 框内边距: CGFloat = 8
        return 卡片堆叠布局(平铺数量: 平铺数量, 露出: 9, 内缩: 0, 胶囊间距: 22) {
            综合卡片 {
                作品行(词.作品, 封面宽度: 54)
            }
            .overlay(alignment: .bottom) {
                摘要胶囊(词)
                    .offset(y: 11)
            }
            .shadow(color: .black.opacity(已展开 ? 0 : 0.1), radius: 3, y: 1)
            .zIndex(3)

            分类卡片(序号: 0) {
                ForEach(Array(词.角色.enumerated()), id: \.element.id) { 序号, 角色 in
                    if 序号 > 0 { 分隔线 }
                    下属行 {
                        HStack(spacing: 10) {
                            演示封面(颜色: 角色.颜色, 符号: "person.fill", 图片: 角色.图片, 宽度: 32)
                            Text(verbatim: 角色.名称)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
            }
            .zIndex(2)

            if !词.系列.isEmpty {
                分类卡片(序号: 1) {
                    ForEach(Array(词.系列.enumerated()), id: \.element.id) { 序号, 作品 in
                        if 序号 > 0 { 分隔线 }
                        下属行 {
                            作品行(作品, 封面宽度: 32, 紧凑: true)
                        }
                    }
                }
                .zIndex(1)
            }
        }
        .padding(已展开 ? 框内边距 : 0)
        .background {
            if 已展开 {
                RoundedRectangle(cornerRadius: 卡片圆角 + 框内边距, style: .continuous)
                    .fill(Color(uiColor: .systemGray5))
                    .transition(.opacity)
            }
        }
    }

    private var 分隔线: some View {
        Divider().padding(.leading, 12 + 32 + 10)
    }

    private func 作品行(_ 作品: 演示作品, 封面宽度: CGFloat, 紧凑: Bool = false) -> some View {
        HStack(spacing: 10) {
            演示封面(颜色: 作品.颜色, 符号: 作品.符号, 图片: 作品.封面, 宽度: 封面宽度)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: 作品.标题)
                    .font(紧凑 ? .subheadline.weight(.medium) : .body.weight(.semibold))
                    .lineLimit(1)
                if !紧凑, 作品.副标题 != 作品.标题 {
                    Text(verbatim: 作品.副标题)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        }
    }

    private func 摘要胶囊(_ 词: 搜索词) -> some View {
        var 部分 = [String(localized: "角色 \(词.角色.count)")]
        if !词.系列.isEmpty {
            部分.append(String(localized: "系列 \(词.系列.count)"))
        }
        return Button(action: 切换) {
            HStack(spacing: 4) {
                Image(systemName: "square.stack")
                Text(verbatim: 部分.joined(separator: " · "))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(已展开 ? 180 : 0))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Color(uiColor: 已展开 ? .systemGray5 : .systemGroupedBackground),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(已展开 ? "已展开" : "已收起"))
    }

    /// 与搜索页面的分类卡片一致：收起时叠在作品卡片后面，只露出边缘。
    private func 分类卡片<Content: View>(序号: Int, @ViewBuilder content: () -> Content) -> some View {
        let 本卡已展开 = 序号 < 平铺数量
        let 深度 = 序号 - 平铺数量 + 1
        let 形状 = RoundedRectangle(cornerRadius: 下属行圆角 + 4, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(4)
        .opacity(本卡已展开 ? 1 : 0)
        .allowsHitTesting(本卡已展开)
        .frame(
            maxWidth: .infinity,
            minHeight: 本卡已展开 ? nil : 0,
            maxHeight: 本卡已展开 ? nil : .infinity,
            alignment: .topLeading
        )
        .background {
            形状.fill(Color.平台次级分组背景)
            形状.fill(Color.primary.opacity(本卡已展开 ? 0 : 0.05 * Double(min(深度, 2))))
        }
        .clipShape(形状)
        .overlay {
            if !本卡已展开 {
                形状.fill(Color.clear)
                    .contentShape(形状)
                    .onTapGesture(perform: 切换)
            }
        }
        .shadow(color: .black.opacity(本卡已展开 ? 0 : 0.08), radius: 2, y: 1)
        .accessibilityHidden(!本卡已展开)
    }

    private func 下属行<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let 行形状 = RoundedRectangle(cornerRadius: 下属行圆角, style: .continuous)
        return Button {} label: {
            HStack(spacing: 8) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .padding(.trailing, 4)
            .contentShape(行形状)
        }
        .buttonStyle(综合搜索卡片按钮样式(形状: 行形状))
    }

    private func 综合卡片<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let 形状 = RoundedRectangle(cornerRadius: 卡片圆角, style: .continuous)
        return Button {} label: {
            HStack(spacing: 8) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(卡片内边距)
            .padding(.trailing, 6)
            .background(Color.平台次级分组背景, in: 形状)
            .contentShape(形状)
        }
        .buttonStyle(综合搜索卡片按钮样式(形状: 形状))
    }

    /// 封面与卡片圆角同心，比例与搜索页面一致。
    private var 封面圆角: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) * 54 / 列表封面布局.宽度
    }

    private var 卡片内边距: CGFloat { 封面圆角 * 10 / 16 }

    private var 卡片圆角: CGFloat { 封面圆角 + 卡片内边距 }

    private var 下属行圆角: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) * 32 / 列表封面布局.宽度 + 8
    }

    private func 搜索(_ 词: 搜索词) {
        输入任务?.cancel()
        动画代次 += 1
        输入任务 = Task { @MainActor in
            withAnimation(.smooth(duration: 0.2)) {
                结果 = nil
            }
            输入 = ""
            for 字符 in 词.查询 {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 20 : 120))
                guard !Task.isCancelled else { return }
                输入.append(字符)
            }
            正在搜索 = true
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            正在搜索 = false
            平铺数量 = 词.自动展开 ? 词.分类数量 : 0
            withAnimation(.smooth(duration: 0.35)) {
                结果 = 词
            }
        }
    }

    /// 与搜索页面一致：一张接一张地弹出或收回。
    private func 切换() {
        let 当前 = 平铺数量
        let 目标 = 当前 > 0 ? 0 : (结果?.分类数量 ?? 0)
        guard 目标 != 当前 else { return }
        动画代次 += 1
        let 代次 = 动画代次
        let 步骤 = 目标 > 当前 ? Array((当前 + 1)...目标) : Array((目标..<当前).reversed())
        Task { @MainActor in
            for (序号, 数量) in 步骤.enumerated() {
                if 序号 > 0 {
                    try? await Task.sleep(for: .milliseconds(目标 > 当前 ? 55 : 40))
                }
                guard 动画代次 == 代次 else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    平铺数量 = 数量
                }
            }
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

// MARK: - 独立搜索Tab

private struct 独立搜索Tab演示: View {
    @AppStorage(搜索设置偏好.独立搜索Tab设置键)
    private var 独立搜索Tab = 搜索设置偏好.独立搜索Tab默认值
    @Namespace private var namespace

    var body: some View {
        VStack(spacing: 14) {
            // 标签栏胶囊高56、离边缘16
            演示区域(内边距: 0, 内层圆角: 28 + 16) {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 120, height: 22)
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.平台次级分组背景)
                                .frame(height: 54)
                        }
                    }
                    .padding(16)
                    .accessibilityHidden(true)

                    标签栏
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }

            演示设置行 {
                Toggle("独立搜索Tab", isOn: $独立搜索Tab.animation(.spring(response: 0.4, dampingFraction: 0.8)))
            }
        }
    }

    private var 标签栏: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                标签项("Today", systemImage: "doc.text.image", 选中: true)
                标签项("资料库", systemImage: "square.stack.fill", 选中: false)
                if !独立搜索Tab {
                    标签项("搜索", systemImage: "magnifyingglass", 选中: false)
                        .matchedGeometryEffect(id: "search", in: namespace)
                }
            }
            .padding(4)
            .background(.bar, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)

            if 独立搜索Tab {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 56, height: 56)
                    .background(.bar, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .matchedGeometryEffect(id: "search", in: namespace)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(独立搜索Tab ? "“搜索”与其他Tab分开显示" : "“搜索”与其他Tab一起显示"))
    }

    private func 标签项(_ 标题: LocalizedStringKey, systemImage: String, 选中: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
            Text(标题)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(选中 ? Color.accentColor : .primary)
        .frame(width: 72, height: 48)
        .background {
            if 选中 {
                Capsule().fill(Color.primary.opacity(0.08))
            }
        }
    }
}

// MARK: - 设置

private struct 设置演示: View {
    private enum 类别: String, CaseIterable, Identifiable {
        case 内容与安全限制
        case 通用
        case Today
        case 资料库
        case 搜索

        var id: Self { self }

        var 标题: LocalizedStringKey { LocalizedStringKey(rawValue) }

        var 说明: LocalizedStringKey {
            switch self {
            case .内容与安全限制: "限制不安全的内容或剧透内容显示。"
            case .通用: "管理PaperVN的整体设置和偏好设置，例如语言与地区等。"
            case .Today: "管理Today页面的偏好设置。"
            case .资料库: "管理资料库页面的偏好设置。"
            case .搜索: "管理搜索页面的偏好设置。"
            }
        }

        var 符号: String {
            switch self {
            case .内容与安全限制: "hand.raised.fill"
            case .通用: "gear"
            case .Today: "newspaper.fill"
            case .资料库: "books.vertical.fill"
            case .搜索: "magnifyingglass"
            }
        }

        var 颜色: Color { self == .内容与安全限制 ? .blue : .gray }

        /// 类别里的部分项目，与真实设置页面一致。
        var 子项目: [(标题: LocalizedStringKey, 符号: String, 颜色: Color)] {
            switch self {
            case .内容与安全限制:
                [("安全限制", "exclamationmark.shield.fill", .indigo),
                 ("剧透内容", "eye.slash.fill", .indigo),
                 ("适龄体验", "person.crop.circle.badge.checkmark", .blue)]
            case .通用:
                [("关于", "info.circle.fill", .gray),
                 ("储存空间", "internaldrive.fill", .gray),
                 ("语言与地区", "globe", .blue)]
            case .Today, .资料库, .搜索:
                []
            }
        }
    }

    @State private var 选中: 类别?

    var body: some View {
        演示区域(内边距: 12, 内层圆角: 22) {
            ZStack(alignment: .topLeading) {
                if let 选中 {
                    VStack(alignment: .leading, spacing: 16) {
                        Button {
                            withAnimation(.smooth(duration: 0.3)) { self.选中 = nil }
                        } label: {
                            Label("设置", systemImage: "chevron.backward")
                                .font(.subheadline.weight(.medium))
                        }
                        .buttonStyle(.borderless)

                        设置类别介绍(
                            title: 选中.标题,
                            description: 选中.说明,
                            systemImage: 选中.符号,
                            color: 选中.颜色
                        )
                        .padding(16)
                        .background(
                            Color.平台次级分组背景,
                            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                        )

                        if !选中.子项目.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(选中.子项目.enumerated()), id: \.offset) { 序号, 项目 in
                                    if 序号 > 0 {
                                        Divider().padding(.leading, 56)
                                    }
                                    行(设置项目标签(项目.标题, systemImage: 项目.符号, color: 项目.颜色))
                                }
                            }
                            .background(
                                Color.平台次级分组背景,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                            )
                            .accessibilityHidden(true)
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(类别.allCases.enumerated()), id: \.element.id) { 序号, 项目 in
                            if 序号 > 0 {
                                Divider().padding(.leading, 56)
                            }
                            Button {
                                withAnimation(.smooth(duration: 0.3)) { 选中 = 项目 }
                            } label: {
                                行(设置项目标签(项目.标题, systemImage: 项目.符号, color: 项目.颜色))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(
                        Color.平台次级分组背景,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(minHeight: 240, alignment: .top)
            .clipped()
        }
    }

    private func 行(_ 标签: 设置项目标签) -> some View {
        HStack {
            标签
            Spacer()
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

// MARK: - 紧急回避

private struct 紧急回避演示: View {
    @AppStorage(紧急回避设置.启用键)
    private var 紧急回避已开启 = false
    @ObservedObject private var 紧急回避 = 紧急回避中心.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var 旋转角度 = 0.0
    @State private var 已回避 = false
    @State private var 正在翻转 = false
    @State private var 显示背面 = false

    private var 开关标题: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? String(localized: "翻转iPad以紧急回避")
            : String(localized: "翻转iPhone以紧急回避")
    }

    /// 演示用的四张封面，其中两张代表可能不安全的内容。
    private let 封面: [(颜色: Color, 符号: String, 不安全: Bool)] = [
        (.teal, "clock.arrow.2.circlepath", false),
        (.purple, "moon.stars", true),
        (.orange, "leaf", false),
        (.red, "flame", true),
    ]

    var body: some View {
        VStack(spacing: 14) {
            演示设置行 {
                Toggle(isOn: $紧急回避已开启) {
                    Text(verbatim: 开关标题)
                }
                .disabled(紧急回避.isActive)
            }

            演示区域(内边距: 20, 内层圆角: 8) {
                VStack(spacing: 16) {
                    // 正面始终参与布局，翻到背面时只是隐藏，避免尺寸跳动
                    模拟屏幕
                        .opacity(显示背面 ? 0 : 1)
                        .overlay {
                            if 显示背面 {
                                手机背面
                                    // 背面本身转半圈，翻到180度时正好朝向用户而不是镜像
                                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                            }
                        }
                    .rotation3DEffect(
                        .degrees(旋转角度),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.5
                    )

                    Button {
                        已回避 ? 还原() : 翻转()
                    } label: {
                        Label(
                            已回避 ? "还原" : "模拟翻转",
                            systemImage: 已回避 ? "arrow.uturn.backward" : "arrow.left.arrow.right"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(正在翻转)
                }
            }
        }
    }

    private let 屏幕圆角: CGFloat = 28
    private let 屏幕内边距: CGFloat = 12

    private var 模拟屏幕: some View {
        let 封面圆角 = 屏幕圆角 - 屏幕内边距
        return VStack(spacing: 10) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(Array(封面.enumerated()), id: \.offset) { _, 项目 in
                    ZStack {
                        if 已回避 && 项目.不安全 {
                            RoundedRectangle(cornerRadius: 封面圆角, style: .continuous)
                                .fill(Color.secondary.opacity(0.2))
                                .overlay {
                                    Image(systemName: "eye.slash")
                                        .foregroundStyle(.secondary)
                                }
                        } else {
                            RoundedRectangle(cornerRadius: 封面圆角, style: .continuous)
                                .fill(项目.颜色.gradient)
                                .overlay {
                                    Image(systemName: 项目.符号)
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.92))
                                }
                        }
                    }
                    .aspectRatio(列表封面布局.宽度 / 列表封面布局.高度, contentMode: .fit)
                }
            }

            Text(已回避 ? "已隐藏不安全的内容" : "资料库")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(屏幕内边距)
        .frame(width: 168)
        .background(
            Color.平台次级分组背景,
            in: RoundedRectangle(cornerRadius: 屏幕圆角, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 屏幕圆角, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(已回避 ? "已隐藏不安全的内容" : "模拟的资料库"))
    }

    /// 翻过去后看到的机身背面，大小与屏幕一致。
    private var 手机背面: some View {
        RoundedRectangle(cornerRadius: 屏幕圆角, style: .continuous)
            .fill(Color(uiColor: .systemGray4))
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 屏幕圆角 - 屏幕内边距, style: .continuous)
                    .fill(Color(uiColor: .systemGray3))
                    .frame(width: 56, height: 56)
                    .padding(屏幕内边距)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 屏幕圆角, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 3)
            }
    }

    /// 与实际操作一致：左右翻转180度，再转回来，紧急回避随即生效。
    private func 翻转() {
        正在翻转 = true
        Task { @MainActor in
            if reduceMotion {
                withAnimation(.smooth(duration: 0.3)) { 已回避 = true }
            } else {
                let 半程 = 0.28
                withAnimation(.easeIn(duration: 半程)) { 旋转角度 = 90 }
                try? await Task.sleep(for: .seconds(半程))
                显示背面 = true
                withAnimation(.easeOut(duration: 半程)) { 旋转角度 = 180 }
                try? await Task.sleep(for: .seconds(半程 + 0.35))
                withAnimation(.easeIn(duration: 半程)) { 旋转角度 = 90 }
                try? await Task.sleep(for: .seconds(半程))
                显示背面 = false
                已回避 = true
                withAnimation(.easeOut(duration: 半程)) { 旋转角度 = 0 }
                try? await Task.sleep(for: .seconds(半程))
            }
            正在翻转 = false
            UIAccessibility.post(
                notification: .announcement,
                argument: String(localized: "已隐藏不安全的内容")
            )
        }
    }

    private func 还原() {
        withAnimation(.smooth(duration: 0.3)) { 已回避 = false }
    }
}

// MARK: - 拷贝

/// 视觉小说详情页面的上半部分：封面从清晰逐渐过渡到模糊并淡出，
/// 资料卡片压在封面下缘，使用与详情页面相同的液态玻璃外观。按住标题的菜单与真实页面相同。
private struct 拷贝演示: View {
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    @State private var 反馈: String?

    private let 作品 = 演示作品.ATRI
    /// 与详情页面一致：封面高度为宽度的0.72倍，资料卡片向上压住封面82pt，封面再往下延伸72pt淡出。
    private let 封面高宽比: CGFloat = 0.72
    private let 卡片压住封面: CGFloat = 82
    private let 淡出延伸: CGFloat = 72

    /// 与详情页面相同的菜单项目和文案。
    private let 标题菜单: [(标题: String, 值: String)] = [
        (标题语言.japanese, "ATRI -My Dear Moments-"),
        (标题语言.chinese, "亚托莉 -我挚爱的时光-"),
        (标题语言.traditionalChinese, "亞托莉 -我摯愛的時光-"),
        (标题语言.english, "ATRI -My Dear Moments-"),
    ].map { 语言, 值 in
        (String(localized: "拷贝\(语言.localizedTitle)标题"), 值)
    }

    private var 外观: 沉浸详情外观 { 已存沉浸详情外观.平台生效值 }

    private var 文字样式: 沉浸详情文字样式 {
        沉浸详情文字样式(appearance: 外观, sample: nil, fallbackColorScheme: .light)
    }

    @State private var 宽度: CGFloat = 320
    private let 卡片外边距: CGFloat = 12
    private let 卡片圆角: CGFloat = 26

    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                封面图层
                    .frame(width: 宽度, height: 宽度 * 封面高宽比 + 淡出延伸)
                    .frame(maxHeight: .infinity, alignment: .top)

                资料卡片
                    .padding(.top, 宽度 * 封面高宽比 + 24 - 卡片压住封面)
                    .padding([.horizontal, .bottom], 卡片外边距)
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { 新宽度 in
                if 新宽度 > 0 { 宽度 = 新宽度 }
            }
            .background(Color.演示区域背景)
            // 与资料卡片同心
            .clipShape(RoundedRectangle(cornerRadius: 卡片圆角 + 卡片外边距, style: .continuous))

            演示反馈(文本: $反馈)
        }
    }

    /// 与详情页面相同的三层封面：清晰、中度模糊、重度模糊，各自按渐变遮罩叠加，最后整体淡出。
    private var 封面图层: some View {
        ZStack {
            封面
                .mask {
                    LinearGradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.46),
                        .init(color: .white.opacity(0.5), location: 0.64),
                        .init(color: .clear, location: 0.84)
                    ], startPoint: .top, endPoint: .bottom)
                }
            封面
                .blur(radius: 18)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.35),
                        .init(color: .white.opacity(0.4), location: 0.49),
                        .init(color: .white, location: 0.7),
                        .init(color: .white.opacity(0.55), location: 0.82),
                        .init(color: .clear, location: 0.96)
                    ], startPoint: .top, endPoint: .bottom)
                }
            封面
                .blur(radius: 42)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .clear, location: 0.64),
                        .init(color: .white.opacity(0.5), location: 0.76),
                        .init(color: .white, location: 0.88),
                        .init(color: .white.opacity(0.45), location: 0.98),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
        .compositingGroup()
        .mask {
            LinearGradient(stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.46),
                .init(color: .white.opacity(0.86), location: 0.58),
                .init(color: .white.opacity(0.62), location: 0.7),
                .init(color: .white.opacity(0.34), location: 0.82),
                .init(color: .white.opacity(0.1), location: 0.91),
                .init(color: .clear, location: 0.97),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .accessibilityHidden(true)
    }

    private var 封面: some View {
        Image(作品.封面 ?? "")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
    }

    private var 资料卡片: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: 作品.副标题)
                    .font(.system(size: 22, weight: .bold))
                    .沉浸详情文字前景色(文字样式.primary, style: 文字样式)
                    .lineLimit(2)
                    .contextMenu { 菜单 }

                if 作品.标题 != 作品.副标题 {
                    Text(verbatim: 作品.标题)
                        .font(.system(size: 15))
                        .沉浸详情文字前景色(文字样式.secondary, style: 文字样式)
                        .lineLimit(2)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    资料项("chart.bar.xaxis", "评分", "7.76（\(String(localized: "\(3658)人评分"))）")
                    资料项("clock", "篇幅", String(localized: "\(13)小时\(19)分钟"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    资料项("calendar", "发行日期", 作品.日期)
                    资料项("checkmark.circle", "开发状态", String(localized: "已完结"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .沉浸详情玻璃背景(
            外观,
            usesBrightReducedMaterial: true,
            in: RoundedRectangle(cornerRadius: 卡片圆角, style: .continuous)
        )
    }

    private func 资料项(_ 图标: String, _ 标题: LocalizedStringKey, _ 值: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: 图标)
                .font(.subheadline)
                .沉浸详情文字前景色(文字样式.secondary, style: 文字样式)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(标题)
                    .font(.caption2.weight(.medium))
                    .沉浸详情文字前景色(文字样式.tertiary, style: 文字样式)
                Text(verbatim: 值)
                    .font(.subheadline)
                    .沉浸详情文字前景色(文字样式.primary, style: 文字样式)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var 菜单: some View {
        ForEach(标题菜单, id: \.标题) { 项 in
            Button {
                UIPasteboard.general.string = 项.值
                反馈 = String(localized: "演示已完成")
            } label: {
                Label {
                    Text(verbatim: 项.标题)
                } icon: {
                    Image(systemName: "doc.on.doc")
                }
            }
        }
    }
}

/// Today卡片的大图：存储在素材中的VNDB封面。
private struct 演示大图: View {
    let 图片: String?
    let 颜色: Color

    var body: some View {
        ZStack {
            Rectangle().fill(颜色.gradient)
            if let 图片 {
                Image(图片)
                    .resizable()
                    .scaledToFill()
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 补标

private struct 补标演示: View {
    @State private var 状态: 用户列表筛选 = .planning
    @State private var 开始日期: Date?
    @State private var 结束日期: Date?
    @State private var 显示补标提示 = false
    @State private var 反馈: String?

    private let 作品 = 演示作品.星空列车

    var body: some View {
        VStack(spacing: 10) {
            演示区域(内边距: 16, 内层圆角: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        演示封面(颜色: 作品.颜色, 符号: 作品.符号, 图片: 作品.封面, 宽度: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: 作品.标题)
                                .font(.headline)
                            Text("刚刚加入资料库")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("存储", action: 存储)
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                            .disabled(状态 == .planning)
                    }
                    .padding(.horizontal, 4)

                    卡片 {
                        ForEach(Array([用户列表筛选.planning, .playing, .finished, .dropped].enumerated()), id: \.element) { 序号, 项目 in
                            if 序号 > 0 {
                                Divider().padding(.leading, 48)
                            }
                            Button {
                                选择(项目)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: 项目.symbolName)
                                        .foregroundStyle(.tint)
                                        .frame(width: 24)
                                    Text(verbatim: 项目.localizedTitle)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if 状态 == 项目 {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(状态 == 项目 ? .isSelected : [])
                        }
                    }

                    卡片 {
                        日期行("开始日期", 日期: 开始日期)
                        Divider().padding(.leading, 12)
                        日期行("结束日期", 日期: 结束日期)
                    }
                }
            }

            演示反馈(文本: $反馈)
        }
        .alert("这是补标吗？", isPresented: $显示补标提示) {
            Button("修改日期") {
                反馈 = String(localized: "演示已完成")
            }
            Button("留空日期") {
                withAnimation(.smooth(duration: 0.25)) {
                    开始日期 = nil
                    结束日期 = nil
                }
                完成存储()
            }
            Button("无需操作", role: .cancel) {
                完成存储()
            }
        } message: {
            Text(verbatim: String(
                format: String(localized: "你似乎已经玩过“%@”。自动填充的游玩日期可能不准确。"),
                作品.标题
            ))
        }
    }

    private func 卡片<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            Color.平台次级分组背景,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func 日期行(_ 标题: LocalizedStringKey, 日期: Date?) -> some View {
        HStack {
            Text(标题)
            Spacer()
            Group {
                if let 日期 {
                    Text(日期, format: .dateTime.year().month().day())
                } else {
                    Text("无")
                }
            }
            .foregroundStyle(.secondary)
            .contentTransition(.opacity)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// 与编辑页面一致：标为“游玩中”或“已游玩”时自动填充今天的日期。
    private func 选择(_ 新状态: 用户列表筛选) {
        let 今天 = Calendar.current.startOfDay(for: Date())
        withAnimation(.smooth(duration: 0.25)) {
            状态 = 新状态
            开始日期 = 新状态 == .playing || 新状态 == .finished ? 今天 : nil
            结束日期 = 新状态 == .finished ? 今天 : nil
        }
    }

    private func 存储() {
        if 状态 == .finished || 状态 == .dropped {
            显示补标提示 = true
        } else {
            完成存储()
        }
    }

    private func 完成存储() {
        反馈 = String(localized: "演示已完成")
        withAnimation(.smooth(duration: 0.25)) {
            状态 = .planning
            开始日期 = nil
            结束日期 = nil
        }
    }
}

// MARK: - 推荐视觉小说

private struct 推荐视觉小说演示: View {
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    @State private var 显示推荐页面 = false

    private let 作品 = 演示作品.星空列车

    var body: some View {
        演示区域(内边距: 14, 内层圆角: 26) {
            VStack(alignment: .leading, spacing: 14) {
                // 与Today页面顶部的横幅一致，轻点即可开始推荐
                Button {
                    显示推荐页面 = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tint)
                        Text("用更多的视觉小说把Today填满吧～")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.平台次级分组背景, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }
                .buttonStyle(.plain)

                社区推荐卡片
            }
        }
        .sheet(isPresented: $显示推荐页面) {
            Today推荐页面(vndbAccount: auth.vndb账户)
                .平台近全屏弹窗(dragIndicator: .hidden)
        }
    }

    /// 与Today页面的社区推荐卡片一致：正方形封面区域，底部是液态玻璃的“相关作品”行。
    private var 社区推荐卡片: some View {
        let 圆角: CGFloat = 26
        let 玻璃内边距: CGFloat = 8
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("社区推荐")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 1)

                Spacer(minLength: 0)

                Text("“这可不是……梦。”")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(18)
            .aspectRatio(1, contentMode: .fit)

            相关作品行
                .frame(height: 66)
                .沉浸详情玻璃(
                    外观,
                    in: RoundedRectangle(cornerRadius: 圆角 - 玻璃内边距, style: .continuous)
                )
                .padding([.horizontal, .bottom], 玻璃内边距)
        }
        .background {
            GeometryReader { proxy in
                let 卡片高 = proxy.size.width
                let 总高 = proxy.size.height
                // 与Today图片加载器一致：底部完全模糊，向上平滑过渡到卡片高度的42%处
                let 模糊起点 = 总高 > 0 ? 卡片高 * 0.42 / 总高 : 0.3
                // Today图片加载器在原图上做48像素的高斯模糊（封面原图不会被放大），换算成显示尺寸
                let 原图像素宽 = CGFloat(作品.封面.flatMap { UIImage(named: $0)?.cgImage?.width } ?? 400)
                let 模糊半径 = proxy.size.width * 48 / max(原图像素宽, 1)
                ZStack {
                    演示大图(图片: 作品.封面, 颜色: 作品.颜色)
                    演示大图(图片: 作品.封面, 颜色: 作品.颜色)
                        .blur(radius: 模糊半径, opaque: true)
                        .mask {
                            // 与CISmoothLinearGradient一样按平滑曲线过渡
                            LinearGradient(
                                stops: [0, 0.25, 0.5, 0.75, 1].map { t in
                                    Gradient.Stop(
                                        color: .white.opacity(t * t * (3 - 2 * t)),
                                        location: 模糊起点 + (1 - 模糊起点) * t
                                    )
                                },
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                }
                .frame(width: proxy.size.width, height: 总高)
                .clipped()
            }
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.36),
                            .init(color: .black.opacity(0.18), location: 0.58),
                            .init(color: .black.opacity(0.38), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 圆角, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var 相关作品行: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.headline)
                .foregroundStyle(玻璃文字颜色.opacity(0.9))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("相关作品")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(玻璃文字颜色.opacity(0.78))
                Text(verbatim: 作品.标题)
                    .font(.body.weight(.bold))
                    .foregroundStyle(玻璃文字颜色)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("查看")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(玻璃文字颜色)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(玻璃文字颜色.opacity(0.18), in: Capsule())
                .overlay {
                    Capsule().stroke(玻璃文字颜色.opacity(0.24), lineWidth: 0.5)
                }
        }
        .padding(.horizontal, 16)
    }

    private var 外观: 沉浸详情外观 { 已存沉浸详情外观.平台生效值 }

    /// 与Today页面一致：透明或降低透明度的玻璃上用白色文字。
    private var 玻璃文字颜色: Color {
        switch 外观 {
        case .clear, .reduced: .white
        case .standard: colorScheme == .dark ? .white : .black
        }
    }
}

// MARK: - 贡献翻译

private struct 贡献翻译演示: View {
    @State private var 显示译文 = true

    var body: some View {
        演示区域(内边距: 16, 内层圆角: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("简介", selection: $显示译文.animation(.smooth(duration: 0.25))) {
                    Text("原文").tag(false)
                    Text("译文").tag(true)
                }
                .pickerStyle(.segmented)

                ZStack(alignment: .topLeading) {
                    if 显示译文 {
                        Text("在逐渐被上涨的海水淹没的海边小镇，夏生从海底打捞起一位沉睡的少女型机器人——亚托莉……")
                            .transition(.opacity)
                    } else {
                        // 原文是英语简介；英语界面下改为显示日语原文，与译文区分
                        Text("In a seaside town slowly sinking beneath the rising sea, Natsuki salvages a sleeping robot girl named Atri from the ocean floor...")
                            .transition(.opacity)
                    }
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
                .padding(14)
                .background(
                    Color.平台次级分组背景,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
            }
        }
    }
}

// MARK: - 开源

/// 开发者过去一个月的支出。其他语言按固定汇率换算成当地货币显示。
enum PaperVN支出 {
    static let 人民币金额 = 725.91

    /// 1元人民币可兑换的外币，取自open.er-api.com（2026-10-07）。
    private static let 汇率: [String: (货币: String, 汇率: Double)] = [
        "en": ("USD", 0.148989),
        "ja": ("JPY", 23.57456),
        "ko": ("KRW", 201.694232),
        "zh-Hant": ("TWD", 4.750594),
        "de": ("EUR", 0.132433),
        "pl": ("PLN", 0.572574),
    ]

    static var 本地货币金额: String {
        let 语言 = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        guard let 换算 = 汇率[语言] else {
            return String(localized: "\(人民币金额.formatted(.number.precision(.fractionLength(2))))元")
        }
        return (人民币金额 * 换算.汇率).formatted(
            .currency(code: 换算.货币).locale(Locale(identifier: 语言))
        )
    }
}

private struct 支持PaperVN选项: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.requestReview) private var requestReview
    @State private var 显示Premium = false

    private static let 仓库地址 = URL(string: "https://github.com/JiZPaper/PaperVN")!

    var body: some View {
        VStack(spacing: 0) {
            // 用系统的评分窗口，不跳转到App Store
            行("在App Store中评分", systemImage: "star.fill", color: .blue, 外部链接: false) {
                requestReview()
            }
            分隔线
            行("PaperVN Premium", systemImage: "heart.fill", color: .pink, 外部链接: false) {
                显示Premium = true
            }
            分隔线
            行("在GitHub中查看", systemImage: "chevron.left.forwardslash.chevron.right", color: .gray, 外部链接: true) {
                openURL(Self.仓库地址)
            }
        }
        .background(
            Color.演示区域背景,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .sheet(isPresented: $显示Premium) {
            NavigationStack {
                PaperVNPremiumView()
                    .toolbar {
                        ToolbarItem(placement: .平台关闭操作) {
                            Button {
                                显示Premium = false
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("关闭")
                        }
                    }
            }
            .平台近全屏弹窗(dragIndicator: .hidden)
        }
    }

    private var 分隔线: some View {
        Divider().padding(.leading, 56)
    }

    private func 行(
        _ 标题: LocalizedStringKey,
        systemImage: String,
        color: Color,
        外部链接: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                设置项目标签(标题, systemImage: systemImage, color: color)
                Spacer()
                Image(systemName: 外部链接 ? "arrow.up.forward" : "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            新功能介绍页面 {}
        }
        .environmentObject(用户登录(previewing: true))
}
