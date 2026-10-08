import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import simd

// MARK: - 视图与取样共用的渲染参数

/// 全屏模糊底图的参数。三个沉浸详情页的底图和取样器都读这里，改一处两边同步。
nonisolated enum 沉浸封面背景层参数 {
    static let 缩放: CGFloat = 1.55
    static let 模糊半径: CGFloat = 96
    static let 饱和度: Double = 1.18
    static let 不透明度: Double = 0.56
    static let 系统背景覆盖不透明度: Double = 0.2
}

/// 文字直接所在的表面。
nonisolated enum 沉浸取样表面: String, Sendable, CaseIterable {
    /// `沉浸详情玻璃` / `沉浸详情玻璃背景`，可以加补偿色调。
    case 透明玻璃
    /// `高透明提亮材质背景`，不接受色调。
    case 提亮材质
}

nonisolated enum 沉浸取样校准常量 {
    /// SwiftUI `blur(radius:)` 在编码空间做高斯模糊，标准差约为半径的 0.77 倍（ImageRenderer 实测，见 沉浸封面文字取样Tests）。
    static let 模糊半径换算标准差 = 0.77

    /// 表面自身对背景的影响：编码空间里向白色（正值）或黑色（负值）混合的比例。
    /// 2026-10 用真机截图拟合（封面原图按页面几何合成后与截图逐点比对）：
    /// 透明玻璃在浅色模式下几乎不改变背景（-0.03，取 0）；深色模式下明显提亮，
    /// 两张截图联合拟合 0.23，误差由 0.16/0.09 降到约 0.07。提亮材质尚未测定。
    /// 也可用 Debug 校准工具测定：启动参数 `-PaperVNImmersiveCalibration YES -PaperVNImmersiveCalibrationNoTint YES`。
    static func 表面提亮(_ surface: 沉浸取样表面, background: 沉浸详情背景色调) -> Float {
        switch (surface, background) {
        case (.透明玻璃, .light): 0
        case (.透明玻璃, .dark): 0.23
        case (.提亮材质, .light): 0
        case (.提亮材质, .dark): 0
        }
    }
}

nonisolated struct 沉浸封面遮罩节点: Equatable, Sendable {
    let location: CGFloat
    let opacity: Double

    init(_ opacity: Double, at location: CGFloat) {
        self.opacity = opacity
        self.location = location
    }
}

extension [沉浸封面遮罩节点] {
    var gradientStops: [Gradient.Stop] {
        map { .init(color: .white.opacity($0.opacity), location: $0.location) }
    }

    /// 与 `LinearGradient` 相同的插值：首节点之前取首值，末节点之后取末值，中间线性。
    nonisolated func 不透明度(at location: CGFloat) -> Double {
        guard let first, let last else { return 0 }
        guard location > first.location else { return first.opacity }
        guard location < last.location else { return last.opacity }
        guard let upperIndex = firstIndex(where: { $0.location >= location }),
              upperIndex > 0 else {
            return first.opacity
        }
        let lower = self[upperIndex - 1]
        let upper = self[upperIndex]
        let span = upper.location - lower.location
        guard span > 0.0001 else { return upper.opacity }
        let progress = Double((location - lower.location) / span)
        return lower.opacity + (upper.opacity - lower.opacity) * progress
    }
}

/// 封面的三层遮罩（清晰、中度模糊、重度模糊）和整体渐隐。视图按它绘制，取样器按它模拟。
nonisolated struct 沉浸封面渐变方案: Equatable, Sendable {
    let sharp: [沉浸封面遮罩节点]
    let mediumBlurRadius: CGFloat
    let medium: [沉浸封面遮罩节点]
    let heavyBlurRadius: CGFloat
    let heavy: [沉浸封面遮罩节点]
    let fade: [沉浸封面遮罩节点]

    /// 紧凑宽度、封面延伸到信息区下方。
    static let 紧凑延伸 = Self(
        sharp: [
            .init(1, at: 0), .init(1, at: 0.32), .init(0.78, at: 0.37),
            .init(0.38, at: 0.44), .init(0, at: 0.54)
        ],
        mediumBlurRadius: 16,
        medium: [
            .init(0, at: 0.3), .init(0.5, at: 0.39), .init(1, at: 0.54),
            .init(1, at: 0.74), .init(0.46, at: 0.88), .init(0, at: 1)
        ],
        heavyBlurRadius: 36,
        heavy: [
            .init(0, at: 0.58), .init(0.4, at: 0.66), .init(1, at: 0.78),
            .init(1, at: 0.88), .init(0.36, at: 0.97), .init(0, at: 1)
        ],
        fade: [
            .init(1, at: 0), .init(1, at: 0.5), .init(0.86, at: 0.62),
            .init(0.58, at: 0.76), .init(0.3, at: 0.86),
            .init(0.08, at: 0.95), .init(0, at: 1)
        ]
    )

    /// 紧凑宽度、封面只覆盖标题区。
    static let 紧凑标准 = Self(
        sharp: [
            .init(1, at: 0), .init(1, at: 0.46), .init(0.5, at: 0.64),
            .init(0, at: 0.84)
        ],
        mediumBlurRadius: 18,
        medium: [
            .init(0, at: 0.35), .init(0.4, at: 0.49), .init(1, at: 0.7),
            .init(0.55, at: 0.82), .init(0, at: 0.96)
        ],
        heavyBlurRadius: 42,
        heavy: [
            .init(0, at: 0.64), .init(0.5, at: 0.76), .init(1, at: 0.88),
            .init(0.45, at: 0.98), .init(0, at: 1)
        ],
        fade: [
            .init(1, at: 0), .init(1, at: 0.46), .init(0.86, at: 0.58),
            .init(0.62, at: 0.7), .init(0.34, at: 0.82),
            .init(0.1, at: 0.91), .init(0, at: 0.97), .init(0, at: 1)
        ]
    )

    /// 常规宽度、封面延伸到信息区下方；`transitionStart` 是信息区顶部在封面中的相对位置。
    static func 常规(transitionStart: CGFloat) -> Self {
        let start = min(max(transitionStart, 0), 1)
        func after(_ progress: CGFloat) -> CGFloat {
            start + (1 - start) * progress
        }
        return Self(
            sharp: [
                .init(1, at: 0), .init(1, at: max(start - 0.08, 0)),
                .init(0.76, at: start), .init(0.34, at: after(0.17)),
                .init(0, at: after(0.34))
            ],
            mediumBlurRadius: 18,
            medium: [
                .init(0, at: max(start - 0.09, 0)),
                .init(0.42, at: max(start - 0.03, 0)),
                .init(1, at: after(0.24)), .init(1, at: after(0.61)),
                .init(0.42, at: after(0.85)), .init(0, at: 1)
            ],
            heavyBlurRadius: 42,
            heavy: [
                .init(0, at: after(0.1)), .init(0.42, at: after(0.27)),
                .init(1, at: after(0.51)), .init(1, at: after(0.76)),
                .init(0.34, at: after(0.92)), .init(0, at: 1)
            ],
            fade: [
                .init(1, at: 0), .init(1, at: start),
                .init(0.86, at: after(0.24)), .init(0.6, at: after(0.51)),
                .init(0.32, at: after(0.7)), .init(0.08, at: after(0.9)),
                .init(0, at: 1)
            ]
        )
    }

    /// 取样请求用：把连续变化的过渡位置量化，避免下拉时每帧都重新取样。
    static func 常规取样(transitionStart: CGFloat) -> Self {
        常规(transitionStart: (transitionStart * 100).rounded() / 100)
    }
}

// MARK: - 取样请求与结果

nonisolated enum 沉浸封面文字分析布局: Equatable, Sendable {
    case visualNovel
    case character
}

nonisolated enum 沉浸详情背景色调: Sendable {
    case light
    case dark

    /// 系统背景的编码值（浅色为白，深色为黑）。
    var encoded: Float {
        switch self {
        case .light: 1
        case .dark: 0
        }
    }
}

nonisolated struct 沉浸封面文字取样几何: Sendable, Equatable {
    /// 封面图层（含渐隐延伸）的尺寸，区域坐标都相对它的左上角。
    let imageSize: CGSize
    let regions: [String: CGRect]
    /// 页面视口尺寸，用于模拟全屏模糊底图；缺省时按封面宽度估算。
    var viewportSize: CGSize?
    /// 封面内容相对图层的竖直偏移（常规宽度下封面整体上移 60pt）。
    var contentOffsetY: CGFloat = 0
}

nonisolated struct 沉浸封面文字取样请求: Sendable, Equatable {
    let url: URL
    let layout: 沉浸封面文字分析布局
    let background: 沉浸详情背景色调
    let gradient: 沉浸封面渐变方案
    let itemCounts: [String: Int]
    let geometry: 沉浸封面文字取样几何

    /// 同一画面在另一种外观下的请求，用于预先计算，切换深浅模式时直接命中。
    var 另一外观: Self {
        Self(
            url: url,
            layout: layout,
            background: background == .light ? .dark : .light,
            gradient: gradient,
            itemCounts: itemCounts,
            geometry: geometry
        )
    }
}

nonisolated struct 沉浸详情玻璃色调: Equatable, Sendable {
    enum 基色: Equatable, Sendable {
        case black
        case white
    }

    let 明暗: 基色
    let 不透明度: Double

    @MainActor
    var color: Color {
        let base: Color = 明暗 == .black ? .black : .white
        return 不透明度 >= 1 ? base : base.opacity(不透明度)
    }
}

/// 文字背后（含玻璃）的相对亮度分布。
nonisolated struct 沉浸取样亮度统计: Equatable, Sendable {
    let p10: Double
    let p50: Double
    let p90: Double
    let 样本数: Int
    let 接近白色占比: Double
    let 接近黑色占比: Double

    init(
        p10: Double,
        p50: Double,
        p90: Double,
        样本数: Int,
        接近白色占比: Double = 0,
        接近黑色占比: Double = 0
    ) {
        self.p10 = p10
        self.p50 = p50
        self.p90 = p90
        self.样本数 = 样本数
        self.接近白色占比 = 接近白色占比
        self.接近黑色占比 = 接近黑色占比
    }

    init?(luminances: [Double]) {
        guard !luminances.isEmpty else { return nil }
        let sorted = luminances.sorted()
        func percentile(_ value: Double) -> Double {
            let index = Int((Double(sorted.count - 1) * value).rounded())
            return sorted[min(max(index, 0), sorted.count - 1)]
        }
        let count = Double(sorted.count)
        self.init(
            p10: percentile(0.1),
            p50: percentile(0.5),
            p90: percentile(0.9),
            样本数: sorted.count,
            接近白色占比: Double(sorted.count(where: {
                $0 >= 沉浸文字配色判定.接近白色亮度
            })) / count,
            接近黑色占比: Double(sorted.count(where: {
                $0 <= 沉浸文字配色判定.接近黑色亮度
            })) / count
        )
    }
}

nonisolated struct 沉浸玻璃文字取样结果: Equatable, Sendable {
    /// 这个元素最终使用的文字颜色（已与所在组协调）。
    let usesDarkText: Bool
    /// 所在组多数元素的颜色。
    let groupUsesDarkText: Bool
    /// 即使补偿着色后最差处仍低于 Lc 30，需要文字阴影兜底。
    let needsContrastShadow: Bool
    /// 透明玻璃的补偿色调；纯白/纯黑背景时为不透明色调以显出玻璃。
    let glassTint: 沉浸详情玻璃色调?
    let 亮度统计: 沉浸取样亮度统计
    var 表面: 沉浸取样表面 = .透明玻璃

    /// 只比较影响显示的字段。亮度统计每次取样都有细微差别，若参与比较，
    /// 下拉等连续几何变化会让页面逐帧整页刷新，而画面其实没有变化。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.usesDarkText == rhs.usesDarkText
            && lhs.groupUsesDarkText == rhs.groupUsesDarkText
            && lhs.needsContrastShadow == rhs.needsContrastShadow
            && lhs.glassTint == rhs.glassTint
            && lhs.表面 == rhs.表面
    }
}

// MARK: - 配色判定

/// 按对比度而非平均亮度选择黑字或白字。文字颜色只取决于画面本身：同一画面在浅色、深色模式下颜色相同；
/// 深浅模式只影响玻璃补偿色调的方向。
nonisolated enum 沉浸文字配色判定 {
    // 可读度用 APCA Lc（绝对值，0～约 106）。WCAG 2 对比度在中间调背景上会过度偏向黑字
    //（分界约在亮度 0.18），APCA 区分极性、分界约在 0.33，更符合实际观感。

    /// 校准报告里视为“判错”的最小得分差（Lc）。
    static let 判错容差 = 8.0
    /// 大号粗体文字清楚可读的下限，组内例外规则以此为准。
    static let 最低可读度 = 45.0
    /// 玻璃尽量保持透明：只有最差处低于 Lc 30（十分难以看清）才着色或加阴影，而且只补到 Lc 40 为止。
    static let 着色触发可读度 = 30.0
    static let 着色目标可读度 = 40.0
    static let 最大补偿着色 = 0.25
    static let 着色步长 = 0.05
    static let 接近白色亮度 = 0.995
    static let 接近黑色亮度 = 0.005
    static let 单色覆盖率 = 0.995
    static let 最低单色样本数 = 16

    /// APCA 0.0.98G：文字与背景的可读度 |Lc|。
    static func 可读度(文字 text: Double, 背景 background: Double) -> Double {
        func clamped(_ y: Double) -> Double {
            y < 0.022 ? y + pow(0.022 - y, 1.414) : y
        }
        let textY = clamped(max(text, 0))
        let backgroundY = clamped(max(background, 0))
        if backgroundY > textY {
            let s = (pow(backgroundY, 0.56) - pow(textY, 0.57)) * 1.14
            return s < 0.1 ? 0 : (s - 0.027) * 100
        }
        let s = (pow(backgroundY, 0.65) - pow(textY, 0.62)) * 1.14
        return s > -0.1 ? 0 : -(s + 0.027) * 100
    }

    /// 黑字最怕背景里最暗的部分，白字最怕最亮的部分；`tint` 是同向补偿着色的不透明度。
    static func 最差可读度(
        _ stats: 沉浸取样亮度统计,
        usesDarkText: Bool,
        tint: Double = 0
    ) -> Double {
        if usesDarkText {
            return 可读度(文字: 0, 背景: 着色后亮度(stats.p10, 着色: tint, 朝白色: true))
        }
        return 可读度(文字: 1, 背景: 着色后亮度(stats.p90, 着色: tint, 朝白色: false))
    }

    /// 正值偏向黑字。最差情况和中位数各占一半，既保底又不被少量高光左右。
    static func 黑字裕量(_ stats: 沉浸取样亮度统计) -> Double {
        let dark = 0.5 * 最差可读度(stats, usesDarkText: true)
            + 0.5 * 可读度(文字: 0, 背景: stats.p50)
        let white = 0.5 * 最差可读度(stats, usesDarkText: false)
            + 0.5 * 可读度(文字: 1, 背景: stats.p50)
        return dark - white
    }

    /// 能看清时只按画面选色，深浅模式下结果相同。
    /// 十分难以看清、需要玻璃补偿时，浅色模式偏向黑字加提亮，深色模式偏向白字加压暗——
    /// 色调与文字总是配套的；偏好的组合补偿后仍看不清时才退回画面本身更好的颜色。
    static func 使用黑字(
        _ stats: 沉浸取样亮度统计,
        背景 background: 沉浸详情背景色调? = nil,
        可着色 canTint: Bool = true
    ) -> Bool {
        let unbiased = 黑字裕量(stats) >= 0
        guard let background, canTint,
              最差可读度(stats, usesDarkText: unbiased) < 着色触发可读度 else {
            return unbiased
        }
        let preferred = background == .light
        guard preferred != unbiased else { return unbiased }
        let tint = 补偿着色(stats, usesDarkText: preferred)
        return 最差可读度(stats, usesDarkText: preferred, tint: tint) >= 着色触发可读度
            ? preferred
            : unbiased
    }

    /// 十分难以看清时，让最差处恢复到 Lc 40 所需的最小同向着色（白字配黑色、黑字配白色），按步长取；否则为 0。
    static func 补偿着色(
        _ stats: 沉浸取样亮度统计,
        usesDarkText: Bool
    ) -> Double {
        guard 最差可读度(stats, usesDarkText: usesDarkText) < 着色触发可读度 else {
            return 0
        }
        var tint = 着色步长
        while tint < 最大补偿着色 - 0.0001,
              最差可读度(stats, usesDarkText: usesDarkText, tint: tint) < 着色目标可读度 {
            tint += 着色步长
        }
        return min(tint, 最大补偿着色)
    }

    static func 着色后亮度(
        _ luminance: Double,
        着色 tint: Double,
        朝白色 towardsWhite: Bool
    ) -> Double {
        guard tint > 0 else { return luminance }
        let encoded = 编码(luminance)
        let tinted = towardsWhite
            ? encoded + (1 - encoded) * tint
            : encoded * (1 - tint)
        return 线性(tinted)
    }

    static func 线性(_ encoded: Double) -> Double {
        encoded <= 0.04045
            ? encoded / 12.92
            : pow((encoded + 0.055) / 1.055, 2.4)
    }

    static func 编码(_ linear: Double) -> Double {
        linear <= 0.0031308
            ? linear * 12.92
            : 1.055 * pow(linear, 1 / 2.4) - 0.055
    }

    /// 把一组区域的统计协调成最终结果。
    static func 协调(
        统计 metrics: [String: 沉浸取样亮度统计],
        分组 groups: [String: String],
        表面 surfaces: [String: 沉浸取样表面] = [:],
        统一 unified: [String: String] = [:],
        背景 background: 沉浸详情背景色调? = nil
    ) -> [String: 沉浸玻璃文字取样结果] {
        func canTint(_ key: String) -> Bool {
            (surfaces[key] ?? .透明玻璃) == .透明玻璃
        }
        func tint(_ key: String, _ stats: 沉浸取样亮度统计, _ dark: Bool) -> Double {
            canTint(key) ? 补偿着色(stats, usesDarkText: dark) : 0
        }
        var local: [String: Bool] = [:]
        for (key, stats) in metrics {
            local[key] = 使用黑字(stats, 背景: background, 可着色: canTint(key))
        }

        // 必须统一颜色的一组：选让其中最难看清的一项尽量清楚的颜色；两种都看不清时按模式（浅色黑字、深色白字）。
        let unifiedSets = Dictionary(grouping: unified.keys.filter { metrics[$0] != nil }) {
            unified[$0]!
        }
        for keys in unifiedSets.values {
            let members = keys.compactMap { metrics[$0] }
            let dark = members.map { 最差可读度($0, usesDarkText: true) }.min() ?? 0
            let white = members.map { 最差可读度($0, usesDarkText: false) }.min() ?? 0
            let usesDark: Bool
            if max(dark, white) < 着色触发可读度, let background {
                usesDark = background == .light
            } else if abs(dark - white) < 1 {
                usesDark = members.map(黑字裕量).reduce(0, +) >= 0
            } else {
                usesDark = dark > white
            }
            for key in keys { local[key] = usesDark }
        }

        var votes: [String: (dark: Int, white: Int)] = [:]
        for (key, group) in groups where key != group {
            guard let usesDark = local[key] else { continue }
            if usesDark {
                votes[group, default: (0, 0)].dark += 1
            } else {
                votes[group, default: (0, 0)].white += 1
            }
        }

        func groupUsesDark(_ group: String) -> Bool? {
            guard let vote = votes[group], vote.dark + vote.white > 0 else {
                return nil
            }
            if vote.dark == vote.white {
                return local[group] ?? true
            }
            return vote.dark > vote.white
        }

        var decisions: [String: (usesDark: Bool, group: Bool, tint: Double)] = [:]
        for (key, stats) in metrics {
            guard let group = groups[key], let ownChoice = local[key] else {
                continue
            }
            let dominant = groupUsesDark(group) ?? ownChoice
            var usesDark = key == group ? dominant : ownChoice
            if key != group, unified[key] == nil, ownChoice != dominant {
                // 跟随组色以保持一致；只有组色在这里补偿后仍低于 Lc 45、
                // 且自己的颜色确实更清楚时才例外。
                func legibility(_ dark: Bool) -> Double {
                    最差可读度(stats, usesDarkText: dark, tint: tint(key, stats, dark))
                }
                let dominantLegibility = legibility(dominant)
                if dominantLegibility >= 最低可读度
                    || legibility(ownChoice) <= dominantLegibility {
                    usesDark = dominant
                }
            }
            decisions[key] = (
                usesDark,
                dominant,
                tint(key, stats, usesDark)
            )
        }

        // 同组同色、且确实需要着色的胶囊使用相同强度，避免深浅不一；不需要的保持透明。
        var groupTint: [String: Double] = [:]
        for (key, decision) in decisions where decision.tint > 0 {
            guard let group = groups[key], key != group else { continue }
            let tintKey = "\(group).\(decision.usesDark)"
            groupTint[tintKey] = max(groupTint[tintKey] ?? 0, decision.tint)
        }

        var results: [String: 沉浸玻璃文字取样结果] = [:]
        for (key, decision) in decisions {
            guard let stats = metrics[key], let group = groups[key] else {
                continue
            }
            let tint = key == group || decision.tint == 0
                ? decision.tint
                : groupTint["\(group).\(decision.usesDark)"] ?? decision.tint
            let glassTint: 沉浸详情玻璃色调?
            if !canTint(key) {
                glassTint = nil
            } else if stats.样本数 >= 最低单色样本数,
               stats.接近白色占比 >= 单色覆盖率 {
                glassTint = .init(明暗: .white, 不透明度: 1)
            } else if stats.样本数 >= 最低单色样本数,
                      stats.接近黑色占比 >= 单色覆盖率 {
                glassTint = .init(明暗: .black, 不透明度: 1)
            } else if tint > 0 {
                glassTint = .init(
                    明暗: decision.usesDark ? .white : .black,
                    不透明度: tint
                )
            } else {
                glassTint = nil
            }
            results[key] = 沉浸玻璃文字取样结果(
                usesDarkText: decision.usesDark,
                groupUsesDarkText: decision.group,
                needsContrastShadow: 最差可读度(
                    stats,
                    usesDarkText: decision.usesDark,
                    tint: tint
                ) < 着色触发可读度,
                glassTint: glassTint,
                亮度统计: stats,
                表面: surfaces[key] ?? .透明玻璃
            )
        }
        return results
    }
}

// MARK: - 封面色彩图与栅格

/// 封面缩略图，编码 sRGB、非预乘 RGBA。
nonisolated struct 沉浸封面色彩图: Sendable {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    /// 双线性取预乘颜色，`x`、`y` 为 0...1 的源图坐标。
    func premultiplied(atX x: Double, y: Double) -> SIMD4<Float> {
        let fx = min(max(x * Double(width) - 0.5, 0), Double(width - 1))
        let fy = min(max(y * Double(height) - 0.5, 0), Double(height - 1))
        let x0 = Int(fx)
        let y0 = Int(fy)
        let x1 = min(x0 + 1, width - 1)
        let y1 = min(y0 + 1, height - 1)
        let tx = Float(fx - Double(x0))
        let ty = Float(fy - Double(y0))
        let top = pixel(x0, y0) * (1 - tx) + pixel(x1, y0) * tx
        let bottom = pixel(x0, y1) * (1 - tx) + pixel(x1, y1) * tx
        return top * (1 - ty) + bottom * ty
    }

    private func pixel(_ x: Int, _ y: Int) -> SIMD4<Float> {
        let index = (y * width + x) * 4
        let alpha = Float(rgba[index + 3]) / 255
        return SIMD4(
            Float(rgba[index]) / 255 * alpha,
            Float(rgba[index + 1]) / 255 * alpha,
            Float(rgba[index + 2]) / 255 * alpha,
            alpha
        )
    }
}

/// 以点为单位定位的预乘 RGBA 栅格，用于模拟视图里的模糊层。
nonisolated struct 沉浸取样栅格: Sendable {
    let width: Int
    let height: Int
    let origin: CGPoint
    let pointsPerPixel: CGFloat
    var pixels: [SIMD4<Float>]

    init(
        bounds: CGRect,
        pointsPerPixel: CGFloat,
        content: (CGPoint) -> SIMD4<Float>
    ) {
        let width = max(1, Int((bounds.width / pointsPerPixel).rounded(.up)))
        let height = max(1, Int((bounds.height / pointsPerPixel).rounded(.up)))
        self.width = width
        self.height = height
        self.origin = bounds.origin
        self.pointsPerPixel = pointsPerPixel
        var pixels = [SIMD4<Float>](repeating: .zero, count: width * height)
        for row in 0..<height {
            for column in 0..<width {
                pixels[row * width + column] = content(CGPoint(
                    x: bounds.minX + (CGFloat(column) + 0.5) * pointsPerPixel,
                    y: bounds.minY + (CGFloat(row) + 0.5) * pointsPerPixel
                ))
            }
        }
        self.pixels = pixels
    }

    /// 一个轴上的双线性插值位置。越界的一侧权重为 0（等同透明），索引夹到有效范围内以便直接读取。
    struct 轴采样 {
        let i0: Int
        let i1: Int
        let w0: Float
        let w1: Float
    }

    func 横轴(_ x: CGFloat) -> 轴采样 {
        Self.轴(Double((x - origin.x) / pointsPerPixel) - 0.5, count: width)
    }

    func 纵轴(_ y: CGFloat) -> 轴采样 {
        Self.轴(Double((y - origin.y) / pointsPerPixel) - 0.5, count: height)
    }

    private static func 轴(_ position: Double, count: Int) -> 轴采样 {
        let index = Int(position.rounded(.down))
        let fraction = Float(position - Double(index))
        let next = index + 1
        return 轴采样(
            i0: min(max(index, 0), count - 1),
            i1: min(max(next, 0), count - 1),
            w0: index >= 0 && index < count ? 1 - fraction : 0,
            w1: next >= 0 && next < count ? fraction : 0
        )
    }

    /// 栅格外视为透明，与视图里 `.clipped()` 之后再模糊一致。
    func sample(at point: CGPoint) -> SIMD4<Float> {
        sample(横轴(point.x), 纵轴(point.y))
    }

    @inline(__always)
    func sample(_ x: 轴采样, _ y: 轴采样) -> SIMD4<Float> {
        let row0 = y.i0 * width
        let row1 = y.i1 * width
        let top = pixels[row0 + x.i0] * x.w0 + pixels[row0 + x.i1] * x.w1
        let bottom = pixels[row1 + x.i0] * x.w0 + pixels[row1 + x.i1] * x.w1
        return top * y.w0 + bottom * y.w1
    }

    /// 三次盒式模糊近似高斯，边界外按透明处理。
    mutating func gaussianBlur(sigmaPoints: Double) {
        let sigma = sigmaPoints / Double(pointsPerPixel)
        guard sigma > 0.3 else { return }
        let idealWidth = (12 * sigma * sigma / 3 + 1).squareRoot()
        let radius = max(1, Int(((idealWidth - 1) / 2).rounded()))
        for _ in 0..<3 {
            boxBlur(radius: radius, horizontal: true)
            boxBlur(radius: radius, horizontal: false)
        }
    }

    mutating func saturate(_ amount: Float) {
        for index in pixels.indices {
            let pixel = pixels[index]
            let luma = pixel.x * 0.2126 + pixel.y * 0.7152 + pixel.z * 0.0722
            let gray = SIMD3<Float>(repeating: luma)
            let color = gray + (SIMD3(pixel.x, pixel.y, pixel.z) - gray) * amount
            let clamped = simd_clamp(color, .zero, SIMD3(repeating: pixel.w))
            pixels[index] = SIMD4(clamped, pixel.w)
        }
    }

    private mutating func boxBlur(radius: Int, horizontal: Bool) {
        let lineCount = horizontal ? height : width
        let lineLength = horizontal ? width : height
        let scale = 1 / Float(radius * 2 + 1)
        var line = [SIMD4<Float>](repeating: .zero, count: lineLength)
        var prefix = [SIMD4<Float>](repeating: .zero, count: lineLength + 1)
        for lineIndex in 0..<lineCount {
            for position in 0..<lineLength {
                line[position] = horizontal
                    ? pixels[lineIndex * width + position]
                    : pixels[position * width + lineIndex]
                prefix[position + 1] = prefix[position] + line[position]
            }
            for position in 0..<lineLength {
                let lower = max(position - radius, 0)
                let upper = min(position + radius + 1, lineLength)
                let blurred = (prefix[upper] - prefix[lower]) * scale
                if horizontal {
                    pixels[lineIndex * width + position] = blurred
                } else {
                    pixels[position * width + lineIndex] = blurred
                }
            }
        }
    }
}

// MARK: - 合成模拟

/// 按视图的实际层级在编码空间里合成文字背后的颜色：
/// 系统背景 → 模糊底图 → 系统背景覆盖 → 封面三层（清晰/中度/重度）× 渐隐 → 透明玻璃。
nonisolated struct 沉浸封面合成模型: Sendable {
    /// 决定栅格内容的参数；只有区域位置变化时可以复用同一个模型，免去重建模糊栅格。
    struct 键: Equatable, Sendable {
        let url: URL
        let background: 沉浸详情背景色调
        let gradient: 沉浸封面渐变方案
        let imageSize: CGSize
        let viewportSize: CGSize?
        let contentOffsetY: CGFloat

        init(_ request: 沉浸封面文字取样请求) {
            url = request.url
            background = request.background
            gradient = request.gradient
            imageSize = request.geometry.imageSize
            viewportSize = request.geometry.viewportSize
            contentOffsetY = request.geometry.contentOffsetY
        }
    }

    private struct 行遮罩 {
        let sharp: Float
        let medium: Float
        let heavy: Float
        let fade: Float
    }

    let background: 沉浸详情背景色调
    let gradient: 沉浸封面渐变方案
    let imageSize: CGSize
    private let sharp: 沉浸取样栅格
    private let medium: 沉浸取样栅格
    private let heavy: 沉浸取样栅格
    private let backdrop: 沉浸取样栅格

    init?(
        map: 沉浸封面色彩图,
        background: 沉浸详情背景色调,
        gradient: 沉浸封面渐变方案,
        geometry: 沉浸封面文字取样几何
    ) {
        let imageSize = geometry.imageSize
        guard imageSize.width > 1, imageSize.height > 1,
              map.width > 0, map.height > 0 else {
            return nil
        }
        self.background = background
        self.gradient = gradient
        self.imageSize = imageSize

        let sourceAspect = CGFloat(map.width) / CGFloat(map.height)
        let contentOffsetY = geometry.contentOffsetY

        // 封面：按图层宽高比填充、顶部对齐、水平居中，栅格精度不低于源图。
        let fitsHeight = sourceAspect > imageSize.width / imageSize.height
        let sourcePixelsPerPoint = fitsHeight
            ? CGFloat(map.height) / imageSize.height
            : CGFloat(map.width) / imageSize.width
        let heroPointsPerPixel = min(
            1 / max(sourcePixelsPerPoint, 0.0001),
            imageSize.width / 64
        )
        let heroBounds = CGRect(origin: .zero, size: imageSize)
        let sharp = 沉浸取样栅格(
            bounds: heroBounds,
            pointsPerPixel: heroPointsPerPixel
        ) { point in
            Self.heroPixel(
                map: map,
                at: CGPoint(x: point.x, y: point.y - contentOffsetY),
                imageSize: imageSize,
                fitsHeight: fitsHeight,
                sourceAspect: sourceAspect
            )
        }
        var medium = sharp
        medium.gaussianBlur(
            sigmaPoints: Double(gradient.mediumBlurRadius)
                * 沉浸取样校准常量.模糊半径换算标准差
        )
        var heavy = sharp
        heavy.gaussianBlur(
            sigmaPoints: Double(gradient.heavyBlurRadius)
                * 沉浸取样校准常量.模糊半径换算标准差
        )
        self.sharp = sharp
        self.medium = medium
        self.heavy = heavy

        // 模糊底图：填满视口、居中，再以视口中心放大，然后模糊、增饱和。
        let viewport = geometry.viewportSize.flatMap {
            $0.width > 1 && $0.height > 1 ? $0 : nil
        } ?? CGSize(
            width: imageSize.width,
            height: max(imageSize.height, imageSize.width * 2.16)
        )
        let scale = 沉浸封面背景层参数.缩放
        let viewportAspect = viewport.width / viewport.height
        let fillSize = sourceAspect > viewportAspect
            ? CGSize(width: viewport.height * sourceAspect, height: viewport.height)
            : CGSize(width: viewport.width, height: viewport.width / sourceAspect)
        let center = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        let scaledFrame = CGRect(
            x: center.x - fillSize.width * scale / 2,
            y: center.y - fillSize.height * scale / 2,
            width: fillSize.width * scale,
            height: fillSize.height * scale
        )
        let backdropSigma = Double(沉浸封面背景层参数.模糊半径)
            * 沉浸取样校准常量.模糊半径换算标准差
        let viewportBounds = CGRect(origin: .zero, size: viewport)
            .insetBy(dx: -backdropSigma * 2.5, dy: -backdropSigma * 2.5)
            .intersection(scaledFrame)
        var backdrop = 沉浸取样栅格(
            bounds: viewportBounds.isNull ? .init(origin: .zero, size: viewport) : viewportBounds,
            pointsPerPixel: max(viewport.width / 48, 4)
        ) { point in
            guard scaledFrame.contains(point) else { return .zero }
            return map.premultiplied(
                atX: Double((point.x - scaledFrame.minX) / scaledFrame.width),
                y: Double((point.y - scaledFrame.minY) / scaledFrame.height)
            )
        }
        backdrop.gaussianBlur(sigmaPoints: backdropSigma)
        backdrop.saturate(Float(沉浸封面背景层参数.饱和度))
        self.backdrop = backdrop
    }

    private static func heroPixel(
        map: 沉浸封面色彩图,
        at point: CGPoint,
        imageSize: CGSize,
        fitsHeight: Bool,
        sourceAspect: CGFloat
    ) -> SIMD4<Float> {
        guard point.x >= 0, point.y >= 0,
              point.x <= imageSize.width, point.y <= imageSize.height else {
            return .zero
        }
        var sourceX = point.x / imageSize.width
        var sourceY = point.y / imageSize.height
        let renderedAspect = imageSize.width / imageSize.height
        if fitsHeight {
            let visibleWidth = renderedAspect / sourceAspect
            sourceX = (1 - visibleWidth) / 2 + sourceX * visibleWidth
        } else {
            let visibleHeight = sourceAspect / renderedAspect
            sourceY *= visibleHeight
        }
        guard (0...1).contains(sourceX), (0...1).contains(sourceY) else {
            return .zero
        }
        return map.premultiplied(atX: Double(sourceX), y: Double(sourceY))
    }

    private func masks(atY y: CGFloat) -> 行遮罩 {
        let location = y / imageSize.height
        return 行遮罩(
            sharp: Float(gradient.sharp.不透明度(at: location)),
            medium: Float(gradient.medium.不透明度(at: location)),
            heavy: Float(gradient.heavy.不透明度(at: location)),
            fade: Float(gradient.fade.不透明度(at: location))
        )
    }

    /// 图层坐标（点）处文字背后的编码 RGB。
    func composite(at point: CGPoint) -> SIMD3<Float> {
        composite(
            heroX: sharp.横轴(point.x),
            heroY: sharp.纵轴(point.y),
            backdropX: backdrop.横轴(point.x),
            backdropY: backdrop.纵轴(point.y),
            masks: masks(atY: point.y)
        )
    }

    /// 三层封面栅格尺寸相同，共用同一组插值位置。
    @inline(__always)
    private func composite(
        heroX: 沉浸取样栅格.轴采样,
        heroY: 沉浸取样栅格.轴采样,
        backdropX: 沉浸取样栅格.轴采样,
        backdropY: 沉浸取样栅格.轴采样,
        masks: 行遮罩
    ) -> SIMD3<Float> {
        let base = SIMD3<Float>(repeating: background.encoded)
        var color = base

        let backdropPixel = backdrop.sample(backdropX, backdropY)
            * Float(沉浸封面背景层参数.不透明度)
        color = SIMD3(backdropPixel.x, backdropPixel.y, backdropPixel.z)
            + color * (1 - backdropPixel.w)

        let overlay = Float(沉浸封面背景层参数.系统背景覆盖不透明度)
        color = color * (1 - overlay) + base * overlay

        let sharpPixel = masks.sharp > 0 ? sharp.sample(heroX, heroY) * masks.sharp : .zero
        let mediumPixel = masks.medium > 0 ? medium.sample(heroX, heroY) * masks.medium : .zero
        let heavyPixel = masks.heavy > 0 ? heavy.sample(heroX, heroY) * masks.heavy : .zero
        var hero = sharpPixel
        hero = mediumPixel + hero * (1 - mediumPixel.w)
        hero = heavyPixel + hero * (1 - heavyPixel.w)
        hero *= masks.fade
        color = SIMD3(hero.x, hero.y, hero.z) + color * (1 - hero.w)
        return simd_clamp(color, .zero, SIMD3(repeating: 1))
    }

    func statistics(
        in region: CGRect,
        surface: 沉浸取样表面 = .透明玻璃
    ) -> 沉浸取样亮度统计? {
        guard !region.isEmpty, region.width.isFinite, region.height.isFinite else {
            return nil
        }
        let columns = max(4, min(48, Int((region.width / 4).rounded(.up))))
        let rows = max(4, min(48, Int((region.height / 4).rounded(.up))))
        let lift = 沉浸取样校准常量.表面提亮(surface, background: background)
        let liftTarget = SIMD3<Float>(repeating: lift >= 0 ? 1 : 0)
        // 每列的插值位置对所有行相同，先算好。
        let xs = (0..<columns).map {
            region.minX + (CGFloat($0) + 0.5) / CGFloat(columns) * region.width
        }
        let heroXs = xs.map(sharp.横轴)
        let backdropXs = xs.map(backdrop.横轴)
        var luminances: [Double] = []
        luminances.reserveCapacity(columns * rows)
        for row in 0..<rows {
            if Task.isCancelled { return nil }
            let y = region.minY + (CGFloat(row) + 0.5) / CGFloat(rows) * region.height
            let rowMasks = masks(atY: y)
            let heroY = sharp.纵轴(y)
            let backdropY = backdrop.纵轴(y)
            for column in 0..<columns {
                var color = composite(
                    heroX: heroXs[column],
                    heroY: heroY,
                    backdropX: backdropXs[column],
                    backdropY: backdropY,
                    masks: rowMasks
                )
                if lift != 0 {
                    color += (liftTarget - color) * abs(lift)
                }
                luminances.append(Self.luminance(color))
            }
        }
        return 沉浸取样亮度统计(luminances: luminances)
    }

    /// 编码值到线性值的查找表，避免每个样本三次 `pow`。
    private static let 线性查找表: [Float] = (0...4095).map {
        Float(沉浸文字配色判定.线性(Double($0) / 4095))
    }

    static func luminance(_ encoded: SIMD3<Float>) -> Double {
        func linear(_ value: Float) -> Float {
            线性查找表[Int(min(max(value, 0), 1) * 4095 + 0.5)]
        }
        return Double(
            0.2126 * linear(encoded.x)
                + 0.7152 * linear(encoded.y)
                + 0.0722 * linear(encoded.z)
        )
    }
}

// MARK: - 取样区域

nonisolated enum 沉浸封面取样区域 {
    struct 定义 {
        let key: String
        let group: String
        /// 相对封面图层的归一化区域，仅在页面没有上报该元素位置时使用。
        let fallback: CGRect
        var surface: 沉浸取样表面 = .透明玻璃
        /// 同名的元素必须使用同一种颜色（例如标题下方的几项信息）。
        var unified: String? = nil
    }

    static func 定义列表(
        for layout: 沉浸封面文字分析布局,
        itemCounts: [String: Int]
    ) -> [定义] {
        switch layout {
        case .visualNovel:
            return [
                .init(key: "metadata", group: "metadata", fallback: .init(x: 0.04, y: 0.31, width: 0.92, height: 0.25)),
                .init(key: "metadata.title", group: "metadata", fallback: .init(x: 0.04, y: 0.31, width: 0.92, height: 0.11)),
                .init(key: "metadata.rating", group: "metadata", fallback: .init(x: 0.04, y: 0.42, width: 0.44, height: 0.08), unified: "metadata.stats"),
                .init(key: "metadata.length", group: "metadata", fallback: .init(x: 0.04, y: 0.50, width: 0.44, height: 0.09), unified: "metadata.stats"),
                .init(key: "metadata.release", group: "metadata", fallback: .init(x: 0.52, y: 0.42, width: 0.44, height: 0.08), unified: "metadata.stats"),
                .init(key: "metadata.status", group: "metadata", fallback: .init(x: 0.52, y: 0.50, width: 0.44, height: 0.09), unified: "metadata.stats"),
                .init(key: "description", group: "description", fallback: .init(x: 0.02, y: 0.51, width: 0.96, height: 0.26)),
                .init(key: "description.text", group: "description", fallback: .init(x: 0.02, y: 0.51, width: 0.82, height: 0.26)),
                .init(key: "tags", group: "tags", fallback: .init(x: 0, y: 0.57, width: 1, height: 0.41))
            ] + 胶囊定义(
                group: "tags",
                startY: 0.57,
                count: itemCounts["tags"] ?? 28,
                surface: .提亮材质
            )
        case .character:
            let metadataCells: [(String, CGFloat, CGFloat)] = [
                ("age", 0, 0.41), ("birthday", 0.25, 0.41),
                ("gender", 0.50, 0.41), ("bloodType", 0.75, 0.41),
                ("height", 0, 0.51), ("weight", 0.25, 0.51),
                ("bust", 0.50, 0.51), ("waist", 0.75, 0.51),
                ("hips", 0, 0.61), ("cup", 0.25, 0.61)
            ]
            return [
                .init(key: "metadata", group: "metadata", fallback: .init(x: 0.04, y: 0.31, width: 0.92, height: 0.25)),
                .init(key: "metadata.title", group: "metadata", fallback: .init(x: 0.04, y: 0.31, width: 0.92, height: 0.10))
            ] + metadataCells.map { name, x, y in
                .init(key: "metadata.\(name)", group: "metadata", fallback: .init(x: x, y: y, width: 0.25, height: 0.10), unified: "metadata.stats")
            } + [
                .init(key: "description", group: "description", fallback: .init(x: 0.02, y: 0.52, width: 0.96, height: 0.24)),
                .init(key: "description.text", group: "description", fallback: .init(x: 0.02, y: 0.52, width: 0.82, height: 0.24)),
                .init(key: "traits", group: "traits", fallback: .init(x: 0, y: 0.5, width: 1, height: 0.48))
            ] + 胶囊定义(group: "traits", startY: 0.50, count: itemCounts["traits"] ?? 28)
        }
    }

    private static func 胶囊定义(
        group: String,
        startY: CGFloat,
        count: Int,
        surface: 沉浸取样表面 = .透明玻璃
    ) -> [定义] {
        (0..<max(count, 0)).map { index in
            let rowHeight: CGFloat = 0.058
            return .init(
                key: "\(group).item.\(index)",
                group: group,
                fallback: .init(
                    x: CGFloat(index % 4) * 0.25,
                    y: min(0.98, startY + CGFloat(index / 4) * rowHeight),
                    width: 0.25,
                    height: rowHeight + 0.035
                ),
                surface: surface
            )
        }
    }
}

// MARK: - 缓存与任务

nonisolated final class 沉浸封面文字分析缓存: @unchecked Sendable {
    static let shared = 沉浸封面文字分析缓存()
    private static let 最大缓存数 = 240

    private let lock = NSLock()
    private var maps: [String: 沉浸封面色彩图] = [:]
    private var mapOrder: [String] = []
    private var preparationTasks: [String: Task<沉浸封面色彩图?, Never>] = [:]
    private var models: [(key: 沉浸封面合成模型.键, model: 沉浸封面合成模型)] = []

    nonisolated func containsMap(for url: URL) -> Bool {
        lock.withLock { maps[url.absoluteString] != nil }
    }

    nonisolated func textSamplesAsync(
        for request: 沉浸封面文字取样请求
    ) async -> [String: 沉浸玻璃文字取样结果] {
        let map = lock.withLock { maps[request.url.absoluteString] }
        guard let map else { return [:] }

        let samplingTask = Task.detached(priority: .userInitiated) { [self] in
            let key = 沉浸封面合成模型.键(request)
            let cached = lock.withLock {
                models.first { $0.key == key }?.model
            }
            guard let model = cached ?? 沉浸封面合成模型(
                map: map,
                background: request.background,
                gradient: request.gradient,
                geometry: request.geometry
            ) else {
                return [String: 沉浸玻璃文字取样结果]()
            }
            if cached == nil, !Task.isCancelled {
                lock.withLock {
                    models.removeAll { $0.key == key }
                    models.insert((key, model), at: 0)
                    if models.count > 4 { models.removeLast() }
                }
            }
            return await Self.parallelTextSamples(model: model, request: request)
        }
        return await withTaskCancellationHandler {
            await samplingTask.value
        } onCancel: {
            samplingTask.cancel()
        }
    }

    nonisolated static func textSamples(
        map: 沉浸封面色彩图,
        request: 沉浸封面文字取样请求
    ) -> [String: 沉浸玻璃文字取样结果] {
        guard !Task.isCancelled,
              let model = 沉浸封面合成模型(
                map: map,
                background: request.background,
                gradient: request.gradient,
                geometry: request.geometry
              ) else {
            return [:]
        }
        return textSamples(model: model, request: request)
    }

    private struct 区域任务: Sendable {
        let key: String
        let group: String
        let region: CGRect
        let surface: 沉浸取样表面
        let unified: String?
    }

    private nonisolated static func 区域任务列表(
        for request: 沉浸封面文字取样请求
    ) -> [区域任务] {
        let imageSize = request.geometry.imageSize
        return 沉浸封面取样区域.定义列表(
            for: request.layout,
            itemCounts: request.itemCounts
        ).map { definition in
            区域任务(
                key: definition.key,
                group: definition.group,
                region: request.geometry.regions[definition.key] ?? CGRect(
                    x: definition.fallback.minX * imageSize.width,
                    y: definition.fallback.minY * imageSize.height,
                    width: definition.fallback.width * imageSize.width,
                    height: definition.fallback.height * imageSize.height
                ),
                surface: definition.surface,
                unified: definition.unified
            )
        }
    }

    /// 各区域互不依赖，并行计算后再统一协调；结果与逐个计算完全相同。
    nonisolated static func parallelTextSamples(
        model: 沉浸封面合成模型,
        request: 沉浸封面文字取样请求
    ) async -> [String: 沉浸玻璃文字取样结果] {
        let jobs = 区域任务列表(for: request)
        let statistics = await withTaskGroup(
            of: (Int, 沉浸取样亮度统计?).self
        ) { group in
            for (index, job) in jobs.enumerated() {
                group.addTask {
                    (index, model.statistics(in: job.region, surface: job.surface))
                }
            }
            var collected = [沉浸取样亮度统计?](repeating: nil, count: jobs.count)
            for await (index, stats) in group {
                collected[index] = stats
            }
            return collected
        }
        guard !Task.isCancelled else { return [:] }
        return 协调(jobs: jobs, statistics: statistics, background: request.background)
    }

    private nonisolated static func 协调(
        jobs: [区域任务],
        statistics: [沉浸取样亮度统计?],
        background: 沉浸详情背景色调
    ) -> [String: 沉浸玻璃文字取样结果] {
        var metrics: [String: 沉浸取样亮度统计] = [:]
        var groups: [String: String] = [:]
        var surfaces: [String: 沉浸取样表面] = [:]
        var unified: [String: String] = [:]
        for (job, stats) in zip(jobs, statistics) {
            guard let stats else { continue }
            metrics[job.key] = stats
            groups[job.key] = job.group
            surfaces[job.key] = job.surface
            unified[job.key] = job.unified
        }
        return 沉浸文字配色判定.协调(
            统计: metrics,
            分组: groups,
            表面: surfaces,
            统一: unified,
            背景: background
        )
    }

    nonisolated static func textSamples(
        model: 沉浸封面合成模型,
        request: 沉浸封面文字取样请求
    ) -> [String: 沉浸玻璃文字取样结果] {
        guard !Task.isCancelled else { return [:] }
        let jobs = 区域任务列表(for: request)
        var statistics: [沉浸取样亮度统计?] = []
        for job in jobs {
            if Task.isCancelled { return [:] }
            statistics.append(model.statistics(in: job.region, surface: job.surface))
        }
        return 协调(jobs: jobs, statistics: statistics, background: request.background)
    }

    nonisolated func prepare(data: Data, for url: URL) async {
        let key = url.absoluteString
        let task: Task<沉浸封面色彩图?, Never>? = lock.withLock {
            if maps[key] != nil { return nil }
            if let existing = preparationTasks[key] { return existing }
            // 详情页文字颜色要等它才能确定，用较高优先级。
            let task = Task.detached(priority: .userInitiated) {
                Self.makeColorMap(from: data)
            }
            preparationTasks[key] = task
            return task
        }
        guard let task else { return }
        let map = await task.value

        lock.withLock {
            preparationTasks.removeValue(forKey: key)
            guard maps[key] == nil, let map else { return }
            maps[key] = map
            mapOrder.append(key)
            if mapOrder.count > Self.最大缓存数 {
                maps.removeValue(forKey: mapOrder.removeFirst())
            }
        }
    }

    nonisolated static func makeColorMap(from data: Data) -> 沉浸封面色彩图? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 96
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return makeColorMap(from: image)
    }

    nonisolated static func makeColorMap(from image: CGImage) -> 沉浸封面色彩图? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes in
            guard let address = bytes.baseAddress,
                  let context = CGContext(
                    data: address,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }

        // 还原为非预乘，便于之后按需双线性插值。
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for channel in 0..<3 {
                pixels[index + channel] = UInt8(
                    min(255, (Int(pixels[index + channel]) * 255 + alpha / 2) / alpha)
                )
            }
        }
        return 沉浸封面色彩图(width: width, height: height, rgba: pixels)
    }
}

@MainActor
final class 沉浸封面文字取样任务协调器 {
    private var task: Task<Void, Never>?
    private var generation = 0
    private var currentRequest: 沉浸封面文字取样请求?
    private(set) var latestGeometry: 沉浸封面文字取样几何?
    /// 最近的计算结果（含预先算好的另一种外观），命中时在同一帧内直接应用。
    private var recentResults: [(request: 沉浸封面文字取样请求, samples: [String: 沉浸玻璃文字取样结果])] = []
    private var prewarmTask: Task<Void, Never>?
    let 校准名称: String

    init(校准名称: String) {
        self.校准名称 = 校准名称
    }

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
        if let cached = recentResults.first(where: { $0.request == request }) {
            task = nil
            deliver(cached.samples, for: request, apply: apply)
            return
        }
        task = Task {
            let computed = await 沉浸封面文字分析缓存.shared
                .textSamplesAsync(for: request)
            guard !Task.isCancelled,
                  generation == submittedGeneration,
                  currentRequest == request else {
                return
            }
            guard !computed.isEmpty else {
                currentRequest = nil
                return
            }
            remember(computed, for: request)
            deliver(computed, for: request, apply: apply)
            prewarm(request.另一外观)
        }
    }

    private func deliver(
        _ computed: [String: 沉浸玻璃文字取样结果],
        for request: 沉浸封面文字取样请求,
        apply: @MainActor (沉浸封面文字取样请求, [String: 沉浸玻璃文字取样结果]) -> Void
    ) {
        #if DEBUG
        let samples = 沉浸取样校准器.shared.校准用结果(computed)
        #else
        let samples = computed
        #endif
        apply(request, samples)
        #if DEBUG
        沉浸取样校准器.shared.安排校准(名称: 校准名称, samples: samples)
        #endif
    }

    private func remember(
        _ samples: [String: 沉浸玻璃文字取样结果],
        for request: 沉浸封面文字取样请求
    ) {
        recentResults.removeAll { $0.request == request }
        recentResults.insert((request, samples), at: 0)
        if recentResults.count > 8 { recentResults.removeLast() }
    }

    private func prewarm(_ request: 沉浸封面文字取样请求) {
        guard !recentResults.contains(where: { $0.request == request }) else { return }
        prewarmTask?.cancel()
        prewarmTask = Task(priority: .utility) {
            let samples = await 沉浸封面文字分析缓存.shared.textSamplesAsync(for: request)
            guard !Task.isCancelled, !samples.isEmpty else { return }
            remember(samples, for: request)
        }
    }

    func cancel() {
        generation += 1
        currentRequest = nil
        task?.cancel()
        task = nil
        prewarmTask?.cancel()
        prewarmTask = nil
    }
}
