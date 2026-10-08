import SwiftUI
import UIKit
#if DEBUG
import os
#endif

/// 校准开关在启动时读取一次；未开启时下面的钩子不挂任何东西，不影响滚动性能。
nonisolated enum 沉浸取样校准开关 {
    #if DEBUG
    static let 已启用 = UserDefaults.standard.bool(forKey: "PaperVNImmersiveCalibration")
    static let 禁用着色 = 已启用
        && UserDefaults.standard.bool(forKey: "PaperVNImmersiveCalibrationNoTint")
    #else
    static let 已启用 = false
    static let 禁用着色 = false
    #endif
}

/// 校准期间隐藏沉浸详情文字，让截图只剩文字背后的背景和玻璃。
struct 沉浸取样校准隐藏Modifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if DEBUG
        if 沉浸取样校准开关.已启用 {
            content.opacity(沉浸取样校准器.shared.隐藏文字 ? 0 : 1)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

#if DEBUG
private struct 沉浸取样校准登记Modifier: ViewModifier {
    let 名称: String
    let keys: [String]

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            沉浸取样校准器.shared.登记(名称: 名称, keys: keys, frame: frame)
        }
    }
}
#endif

extension View {
    /// Debug 校准用：登记取样元素在窗口中的位置。未开启校准时为空操作。
    @ViewBuilder
    func 沉浸取样校准登记(_ 名称: String, keys: [String]) -> some View {
        #if DEBUG
        if 沉浸取样校准开关.已启用 {
            modifier(沉浸取样校准登记Modifier(名称: 名称, keys: keys))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

#if DEBUG
/// 把取样器的预测和屏幕上的真实背景对比，量化文字配色是否判错。
///
/// 用法：Scheme 的启动参数加 `-PaperVNImmersiveCalibration YES`，打开任意沉浸详情页；
/// 每次取样结果更新后约 1.5 秒自动截图（截图时隐藏文字），
/// 报告输出到控制台，并写入 App 容器的 Documents/沉浸取样校准/latest.txt。
@MainActor
@Observable
final class 沉浸取样校准器 {
    static let shared = 沉浸取样校准器()
    static let 启动参数键 = "PaperVNImmersiveCalibration"

    private(set) var 隐藏文字 = false
    @ObservationIgnored private var frames: [String: [String: CGRect]] = [:]
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var latest: (名称: String, samples: [String: 沉浸玻璃文字取样结果])?
    @ObservationIgnored private var updateCount = 0
    @ObservationIgnored private let logger = Logger(
        subsystem: "PaperVN",
        category: "沉浸取样校准"
    )

    static let 禁用着色参数键 = "PaperVNImmersiveCalibrationNoTint"

    var 已启用: Bool { 沉浸取样校准开关.已启用 }

    /// 加启动参数 `-PaperVNImmersiveCalibrationNoTint YES` 时去掉补偿着色，用来单独测量玻璃自身的提亮。
    var 禁用着色: Bool {
        沉浸取样校准开关.禁用着色
    }

    func 校准用结果(
        _ samples: [String: 沉浸玻璃文字取样结果]
    ) -> [String: 沉浸玻璃文字取样结果] {
        guard 禁用着色 else { return samples }
        return samples.mapValues {
            沉浸玻璃文字取样结果(
                usesDarkText: $0.usesDarkText,
                groupUsesDarkText: $0.groupUsesDarkText,
                needsContrastShadow: $0.needsContrastShadow,
                glassTint: nil,
                亮度统计: $0.亮度统计,
                表面: $0.表面
            )
        }
    }

    func 登记(名称: String, keys: [String], frame: CGRect) {
        guard 已启用 else { return }
        for key in keys {
            frames[名称, default: [:]][key] = frame
        }
    }

    /// 节流而非防抖：结果持续更新时也会在 1.5～4 秒内出报告，并记录期间更新次数，便于发现循环重取样。
    func 安排校准(名称: String, samples: [String: 沉浸玻璃文字取样结果]) {
        guard 已启用 else { return }
        latest = (名称, samples)
        updateCount += 1
        logger.debug("取样结果更新：\(名称, privacy: .public) \(samples.count) 项，已登记 \(self.frames[名称]?.count ?? 0) 项")
        guard pending == nil else { return }
        pending = Task {
            try? await Task.sleep(for: .seconds(1.5))
            var waited = 1.5
            var lastCount = updateCount
            while waited < 4 {
                try? await Task.sleep(for: .milliseconds(500))
                waited += 0.5
                if updateCount == lastCount { break }
                lastCount = updateCount
            }
            let updates = updateCount
            updateCount = 0
            pending = nil
            guard let latest else { return }
            await 校准(名称: latest.名称, samples: latest.samples, 更新次数: updates)
        }
    }

    private struct 行 {
        let key: String
        let predicted: 沉浸取样亮度统计
        let actual: 沉浸取样亮度统计
        let result: 沉浸玻璃文字取样结果
        let idealUsesDark: Bool
        let actualWorstContrast: Double
        let 判错: Bool
        let 对比不足: Bool
    }

    private func 校准(
        名称: String,
        samples: [String: 沉浸玻璃文字取样结果],
        更新次数: Int
    ) async {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else {
            return
        }

        隐藏文字 = true
        try? await Task.sleep(for: .milliseconds(350))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let snapshot = UIGraphicsImageRenderer(
            bounds: window.bounds,
            format: format
        ).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        隐藏文字 = false

        guard let cgImage = snapshot.cgImage,
              let screen = 沉浸封面文字分析缓存.makeColorMap(from: cgImage)
        else {
            return
        }

        let background: 沉浸详情背景色调 =
            window.traitCollection.userInterfaceStyle == .dark ? .dark : .light
        let registered = frames[名称] ?? [:]
        var rows: [行] = []
        for (key, result) in samples.sorted(by: { $0.key < $1.key }) {
            guard let frame = registered[key],
                  let actual = Self.统计(screen: screen, frame: frame) else {
                continue
            }
            let ideal = 沉浸文字配色判定.使用黑字(
                actual,
                背景: background,
                可着色: result.表面 == .透明玻璃
            )
            let worst = 沉浸文字配色判定.最差可读度(
                actual,
                usesDarkText: result.usesDarkText
            )
            let margin = 沉浸文字配色判定.黑字裕量(actual)
            rows.append(行(
                key: key,
                predicted: result.亮度统计,
                actual: actual,
                result: result,
                idealUsesDark: ideal,
                actualWorstContrast: worst,
                判错: ideal != result.usesDarkText
                    && abs(margin) > 沉浸文字配色判定.判错容差,
                对比不足: worst < 沉浸文字配色判定.着色触发可读度
            ))
        }
        guard !rows.isEmpty else { return }

        let report = Self.报告(
            名称: 名称,
            背景: background,
            更新次数: 更新次数,
            rows: rows
        )
        logger.notice("\(report, privacy: .public)")
        print(report)
        Self.写入(report: report, 名称: 名称)
    }

    private static func 统计(
        screen: 沉浸封面色彩图,
        frame: CGRect
    ) -> 沉浸取样亮度统计? {
        // 内缩避开玻璃边缘的高光。
        let region = frame
            .insetBy(dx: min(8, frame.width / 4), dy: min(6, frame.height / 4))
            .intersection(CGRect(x: 0, y: 0, width: screen.width, height: screen.height))
        guard !region.isNull, region.width >= 2, region.height >= 2 else {
            return nil
        }
        let columns = max(4, min(48, Int(region.width / 2)))
        let rows = max(4, min(48, Int(region.height / 2)))
        var luminances: [Double] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let x = min(screen.width - 1, Int(region.minX + (CGFloat(column) + 0.5) / CGFloat(columns) * region.width))
                let y = min(screen.height - 1, Int(region.minY + (CGFloat(row) + 0.5) / CGFloat(rows) * region.height))
                let index = (y * screen.width + x) * 4
                luminances.append(沉浸封面合成模型.luminance(SIMD3(
                    Float(screen.rgba[index]) / 255,
                    Float(screen.rgba[index + 1]) / 255,
                    Float(screen.rgba[index + 2]) / 255
                )))
            }
        }
        return 沉浸取样亮度统计(luminances: luminances)
    }

    private static func 报告(
        名称: String,
        背景: 沉浸详情背景色调,
        更新次数: Int,
        rows: [行]
    ) -> String {
        func f(_ value: Double) -> String { String(format: "%.3f", value) }
        func color(_ dark: Bool) -> String { dark ? "黑" : "白" }

        var lines = [
            "沉浸取样校准 · \(名称) · \(背景 == .dark ? "深色" : "浅色") · \(Date().formatted(date: .omitted, time: .standard)) · 期间更新 \(更新次数) 次"
                + (UserDefaults.standard.bool(forKey: 禁用着色参数键) ? " · 已禁用着色" : ""),
            "key | 表面 | 预测 p10/p50/p90 | 实际 p10/p50/p90 | 用色 | 着色 | 实际应用 | 实际最差Lc | 标记"
        ]
        for row in rows {
            let tint = row.result.glassTint.map {
                "\($0.明暗 == .black ? "黑" : "白")\(f($0.不透明度))"
            } ?? "-"
            var flags: [String] = []
            if row.判错 { flags.append("判错") }
            if row.对比不足 { flags.append("对比不足") }
            if row.result.needsContrastShadow { flags.append("阴影") }
            lines.append([
                row.key,
                row.result.表面.rawValue,
                "\(f(row.predicted.p10))/\(f(row.predicted.p50))/\(f(row.predicted.p90))",
                "\(f(row.actual.p10))/\(f(row.actual.p50))/\(f(row.actual.p90))",
                color(row.result.usesDarkText),
                tint,
                color(row.idealUsesDark),
                String(format: "%.0f", row.actualWorstContrast),
                flags.joined(separator: ",")
            ].joined(separator: " | "))
        }

        // 只用未着色的区域，按表面估计自身的提亮：编码空间里实际中位数相对预测向白（正）或黑（负）移动的比例。
        let untinted = rows.filter { $0.result.glassTint == nil }
        let meanError = untinted.isEmpty ? 0 : untinted.map {
            沉浸文字配色判定.编码($0.actual.p50) - 沉浸文字配色判定.编码($0.predicted.p50)
        }.reduce(0, +) / Double(untinted.count)
        var liftNotes: [String] = []
        for surface in 沉浸取样表面.allCases {
            let lifts = untinted.filter { $0.result.表面 == surface }.map { row -> Double in
                let predicted = 沉浸文字配色判定.编码(row.predicted.p50)
                let actual = 沉浸文字配色判定.编码(row.actual.p50)
                return actual >= predicted
                    ? (actual - predicted) / max(1 - predicted, 0.05)
                    : (actual - predicted) / max(predicted, 0.05)
            }.sorted()
            guard !lifts.isEmpty else { continue }
            liftNotes.append("\(surface.rawValue)额外提亮 \(f(lifts[lifts.count / 2]))（\(lifts.count) 项）")
        }
        lines.append(
            "合计 \(rows.count) 项，判错 \(rows.count(where: \.判错))，对比不足 \(rows.count(where: \.对比不足))；"
                + "未着色区域中位数编码误差均值 \(f(meanError))；"
                + (liftNotes.isEmpty ? "无未着色区域" : liftNotes.joined(separator: "，"))
        )
        return lines.joined(separator: "\n")
    }

    private static func 写入(report: String, 名称: String) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return
        }
        let directory = documents.appending(path: "沉浸取样校准", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = Data((report + "\n").utf8)
        try? data.write(to: directory.appending(path: "latest.txt"))
        let stamp = Int(Date().timeIntervalSince1970)
        try? data.write(to: directory.appending(path: "\(名称)-\(stamp).txt"))
    }
}
#endif
