import SwiftUI
import UIKit

/// 索引条上的一段：当前排序下标签相同、连在一起的一组作品。
struct 资料库索引段: Identifiable, Hashable {
    let 标签: String
    /// 这一段第一部作品，拖到这一段时滚动到它
    let 首个编号: String
    let 封面: String?
    let sexual: Double?
    let violence: Double?
    let 数量: Int
    /// 这一段第一部作品在列表里的位置
    let 起始序号: Int

    var id: String { 首个编号 }
}

enum 资料库索引 {
    /// 按当前排序给每部作品一个标签（标题→首字母，发行日期→年份，评分→分数，最近更改→月份），
    /// 把连在一起的相同标签合成一段。
    static func 分段(
        _ 作品: [用户列表项目],
        排序: 用户列表排序,
        标题: (用户列表项目) -> String
    ) -> [资料库索引段] {
        var 结果: [资料库索引段] = []
        var 当前: (标签: String, 首个: 用户列表项目, 数量: Int, 起始: Int)?
        for (序号, item) in 作品.enumerated() {
            let 标签 = 标签(item, 排序: 排序, 标题: 标题)
            if let 段 = 当前, 段.标签 == 标签 {
                当前?.数量 += 1
            } else {
                if let 段 = 当前 { 结果.append(段落(段)) }
                当前 = (标签, item, 1, 序号)
            }
        }
        if let 段 = 当前 { 结果.append(段落(段)) }
        return 结果
    }

    private static func 段落(_ 段: (标签: String, 首个: 用户列表项目, 数量: Int, 起始: Int)) -> 资料库索引段 {
        资料库索引段(
            标签: 段.标签,
            首个编号: 段.首个.id,
            封面: 段.首个.vn.image?.thumbnail ?? 段.首个.vn.image?.url,
            sexual: 段.首个.vn.image?.sexual,
            violence: 段.首个.vn.image?.violence,
            数量: 段.数量,
            起始序号: 段.起始
        )
    }

    private static func 标签(_ item: 用户列表项目, 排序: 用户列表排序, 标题: (用户列表项目) -> String) -> String {
        switch 排序 {
        case .title:
            return 首字母(标题(item))
        case .releaseDate:
            guard let 日期 = item.vn.released, 日期.count >= 4, 日期.first?.isNumber == true else {
                return String(localized: "未定")
            }
            return String(日期.prefix(4))
        case .rating:
            guard let 评分 = item.vote else { return String(localized: "未评分") }
            return String(评分 / 10)
        case .averageRating:
            guard let 评分 = item.vn.rating else { return "–" }
            return String(Int(评分) / 10)
        case .lastModified:
            guard let 时间 = item.lastmod else { return "–" }
            return 月份(Date(timeIntervalSince1970: TimeInterval(时间)))
        }
    }

    /// 标题的首字母：日文、中文转成拉丁字母后取首字母，其余符号和数字归到“#”。
    private static func 首字母(_ 标题: String) -> String {
        let 拉丁 = 标题.applyingTransform(.toLatin, reverse: false)?
            .applyingTransform(.stripDiacritics, reverse: false) ?? 标题
        guard let 字 = 拉丁.uppercased().unicodeScalars.first(where: { !$0.properties.isWhitespace }),
              ("A"..."Z").contains(Character(字)) else {
            return "#"
        }
        return String(Character(字))
    }

    /// 今年的作品按月份，往年的按年份。
    private static func 月份(_ 日期: Date) -> String {
        let 日历 = Calendar.current
        if 日历.isDate(日期, equalTo: Date(), toGranularity: .year) {
            return 日期.formatted(.dateTime.month(.abbreviated))
        }
        return 日期.formatted(.dateTime.year())
    }
}

/// 按住拖动系统滚动条时在它旁边浮出的气泡，显示当前位置所在的一段
/// （月份、年份、首字母或分数）、封面和作品数；松手后淡出。
/// 不占位置、不拦截触摸，列表不需要为它让出空间。
struct 资料库滚动位置气泡: View {
    let 段: [资料库索引段]
    let 作品数: Int
    let 状态: 资料库滚动条状态

    @State private var 显示 = false
    @State private var 隐藏任务: Task<Void, Never>?
    /// 最后一次按住的位置，松手淡出时停在这里
    @State private var 气泡y: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both

    private let 气泡高度: CGFloat = 60

    /// 按手指（滚动条）在可移动范围里的位置找到所在的一段；段按起始序号升序，二分查找
    private func 当前段(比例: CGFloat) -> 资料库索引段? {
        guard 作品数 > 0, !段.isEmpty else { return nil }
        let 序号 = min(Int(min(max(比例, 0), 1) * CGFloat(作品数)), 作品数 - 1)
        var 低 = 0
        var 高 = 段.count - 1
        while 低 < 高 {
            let 中 = (低 + 高 + 1) / 2
            if 段[中].起始序号 <= 序号 { 低 = 中 } else { 高 = 中 - 1 }
        }
        return 段[低]
    }

    var body: some View {
        GeometryReader { proxy in
            let 顶部 = proxy.frame(in: .global).minY
            if let 当前段 = 当前段(比例: (气泡y - 顶部) / max(proxy.size.height, 1)) {
                气泡(当前段)
                    .fixedSize()
                    // 跟着手指（也就是滚动条）上下移动，停在它左边；
                    // 不跟滚动比例走，列表估算行高时比例会跳动，气泡会抖
                    .offset(
                        x: -28,
                        y: min(max(气泡y - 顶部 - 气泡高度 / 2, 0), max(proxy.size.height - 气泡高度, 0))
                    )
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                    .opacity(显示 ? 1 : 0)
                    .scaleEffect(显示 ? 1 : 0.85, anchor: .trailing)
                    .animation(.snappy(duration: 0.15), value: 当前段.id)
                    .sensoryFeedback(.selection, trigger: 当前段.id)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: 状态.按住位置) { _, 位置 in
            if let 位置 {
                隐藏任务?.cancel()
                气泡y = 位置
                if !显示 {
                    withAnimation(.easeOut(duration: 0.15)) { 显示 = true }
                }
            } else {
                隐藏任务?.cancel()
                隐藏任务 = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) { 显示 = false }
                }
            }
        }
    }

    private func 气泡(_ 项: 资料库索引段) -> some View {
        let 圆角 = 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) * 0.6
        return HStack(spacing: 10) {
            CachedAsyncImage(url: URL(string: 项.封面 ?? ""), contentMode: .fill)
                .frame(width: 32, height: 44)
                .background(Color.secondary.opacity(0.1))
                .应用不安全内容限制(
                    内容安全限制判定.图片需要限制(
                        sexual: 项.sexual,
                        violence: 项.violence,
                        enabled: contentFilterEnabled,
                        sexualThreshold: sexualThreshold,
                        violenceThreshold: violenceThreshold,
                        mode: filterMode
                    ),
                    method: .blurred,
                    blurRadius: 10
                )
                .clipShape(RoundedRectangle(cornerRadius: 圆角, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: 项.标签)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(verbatim: String(localized: "\(项.数量)部作品"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .padding(.trailing, 6)
        .液态玻璃(.regular, in: RoundedRectangle(cornerRadius: 圆角 + 8, style: .continuous))
    }
}

/// 按住滚动条时手指在屏幕上的纵坐标（全局坐标），没有按住时为 nil。
/// 单独放在一个可观察对象里，只有气泡读取它，资料库页面不会因为它每帧重绘。
@Observable
final class 资料库滚动条状态 {
    var 按住位置: CGFloat?
}

/// 检测用户是否在按住拖动系统滚动条。SwiftUI 不提供这个信息，所以在列表的滚动视图上
/// 加一个与系统手势同时识别的拖动手势来判断：拖动内容时手指往下、内容往上走；
/// 拖动滚动条时手指往下、内容也往下走（而且走得快得多）。
/// 判定为拖动滚动条后，回调手指在屏幕上的纵坐标；松手时回调 nil。
struct 资料库滚动条拖动检测: UIViewRepresentable {
    let 回调: (CGFloat?) -> Void

    func makeCoordinator() -> 协调器 { 协调器() }

    func makeUIView(context: Context) -> 探测视图 {
        let 视图 = 探测视图()
        视图.协调器 = context.coordinator
        视图.isUserInteractionEnabled = false
        return 视图
    }

    func updateUIView(_ uiView: 探测视图, context: Context) {
        context.coordinator.回调 = 回调
    }

    final class 探测视图: UIView {
        weak var 协调器: 协调器?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            // 等 List 的滚动视图放进视图层级后再找
            DispatchQueue.main.async { [weak self] in
                guard let self, let 滚动视图 = self.找滚动视图() else { return }
                self.协调器?.连接(滚动视图)
            }
        }

        /// 从自己往上找，在每一层的子视图里找面积最大、包含自己位置的滚动视图（就是 List）。
        private func 找滚动视图() -> UIScrollView? {
            guard let window else { return nil }
            let 中心 = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
            var 当前: UIView? = superview
            while let 视图 = 当前 {
                var 最佳: UIScrollView?
                func 搜索(_ v: UIView) {
                    if let 滚动 = v as? UIScrollView,
                       滚动.convert(滚动.bounds, to: window).contains(中心),
                       滚动.bounds.height > (最佳?.bounds.height ?? 0) {
                        最佳 = 滚动
                    }
                    v.subviews.forEach(搜索)
                }
                搜索(视图)
                if let 最佳 { return 最佳 }
                当前 = 视图.superview
            }
            return nil
        }
    }

    final class 协调器: NSObject, UIGestureRecognizerDelegate {
        var 回调: ((CGFloat?) -> Void)?
        private weak var 滚动视图: UIScrollView?
        private let 手势 = UIPanGestureRecognizer()
        private var 上次手指y: CGFloat = 0
        private var 上次偏移y: CGFloat = 0
        private var 同向距离: CGFloat = 0
        private var 正在拖动滚动条 = false

        override init() {
            super.init()
            手势.addTarget(self, action: #selector(处理(_:)))
            手势.delegate = self
            手势.cancelsTouchesInView = false
            手势.delaysTouchesBegan = false
        }

        func 连接(_ 滚动视图: UIScrollView) {
            guard self.滚动视图 !== 滚动视图 else { return }
            self.滚动视图?.removeGestureRecognizer(手势)
            self.滚动视图 = 滚动视图
            滚动视图.addGestureRecognizer(手势)
        }

        @objc private func 处理(_ 手势: UIPanGestureRecognizer) {
            guard let 滚动视图, let window = 滚动视图.window else { return }
            let 手指y = 手势.location(in: window).y
            let 偏移y = 滚动视图.contentOffset.y
            switch 手势.state {
            case .began:
                上次手指y = 手指y
                上次偏移y = 偏移y
                同向距离 = 0
                正在拖动滚动条 = false
            case .changed:
                let 手指变化 = 手指y - 上次手指y
                let 偏移变化 = 偏移y - 上次偏移y
                上次手指y = 手指y
                上次偏移y = 偏移y
                if !正在拖动滚动条 {
                    // 拖动滚动条时系统自己的拖动内容手势不起作用，内容却在动
                    let 系统拖动中 = [.began, .changed].contains(滚动视图.panGestureRecognizer.state)
                    // 手指和内容同向移动、内容走得比手指快：在拖动滚动条
                    if 手指变化 != 0, 偏移变化 != 0,
                       !系统拖动中 || ((手指变化 > 0) == (偏移变化 > 0) && abs(偏移变化) > abs(手指变化) * 1.5) {
                        同向距离 += abs(手指变化)
                    } else if 手指变化 != 0, 偏移变化 != 0 {
                        同向距离 = 0
                    }
                    正在拖动滚动条 = 同向距离 > 6
                }
                if 正在拖动滚动条 { 回调?(手指y) }
            default:
                if 正在拖动滚动条 { 回调?(nil) }
                正在拖动滚动条 = false
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}

#if DEBUG
// MARK: - 预览

#Preview("资料库：滚动位置气泡") {
    // 模拟按住系统滚动条：每隔一段时间移动到下一段
    let 段 = 预览数据.资料库条目.prefix(4).enumerated().map { index, entry in
        资料库索引段(
            标签: ["10月", "9月", "2025年", "2024年"][index],
            首个编号: entry.id,
            封面: entry.封面地址,
            sexual: nil,
            violence: nil,
            数量: [3, 8, 41, 96][index],
            起始序号: [0, 3, 11, 52][index]
        )
    }
    let 状态 = 资料库滚动条状态()
    GeometryReader { proxy in
        资料库滚动位置气泡(段: 段, 作品数: 148, 状态: 状态)
            .padding(.vertical, 24)
            .task {
                let 顶部 = proxy.frame(in: .global).minY + 24
                let 高度 = proxy.size.height - 48
                for 比例 in stride(from: 0.05, through: 0.95, by: 0.15) {
                    状态.按住位置 = 顶部 + 高度 * 比例
                    try? await Task.sleep(for: .seconds(1))
                }
                状态.按住位置 = nil
            }
    }
}
#endif
