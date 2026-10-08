import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import PaperVN

@Suite
struct 沉浸封面文字取样Tests {
    private typealias 判定 = 沉浸文字配色判定

    private func 纯色图(_ gray: UInt8, width: Int = 8, height: Int = 8) -> 沉浸封面色彩图 {
        沉浸封面色彩图(
            width: width,
            height: height,
            rgba: Array(repeating: [gray, gray, gray, 255], count: width * height)
                .flatMap { $0 }
        )
    }

    private func 均匀统计(_ luminance: Double) -> 沉浸取样亮度统计 {
        沉浸取样亮度统计(p10: luminance, p50: luminance, p90: luminance, 样本数: 64)
    }

    // MARK: 模糊系数

    @Test
    @MainActor
    func SwiftUI模糊标准差约为半径的0点77倍() throws {
        for radius in [20.0, 40.0] {
            let view = ZStack {
                Color.black
                HStack(spacing: 0) {
                    Color.white
                    Color.black
                }
                .blur(radius: radius)
            }
            .frame(width: 400, height: 400)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try #require(renderer.cgImage)
            var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: sRGB,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let row = image.height / 2
            let profile = (0..<image.width).map {
                Double(pixels[(row * image.width + $0) * 4]) / 255
            }
            let x75 = try #require((100..<300).first { profile[$0] <= 0.75 })
            let x25 = try #require((100..<300).first { profile[$0] <= 0.25 })
            // 高斯边缘 25%–75% 的宽度为 1.349σ。
            let ratio = Double(x25 - x75) / 1.349 / radius
            #expect(abs(ratio - 沉浸取样校准常量.模糊半径换算标准差) < 0.08)
        }
    }

    // MARK: 合成

    @Test
    func 在编码空间按层级合成() throws {
        let opaqueOnly = 沉浸封面渐变方案(
            sharp: [.init(1, at: 0)],
            mediumBlurRadius: 16,
            medium: [.init(0, at: 0)],
            heavyBlurRadius: 36,
            heavy: [.init(0, at: 0)],
            fade: [.init(0.5, at: 0)]
        )
        let model = try #require(沉浸封面合成模型(
            map: 纯色图(0),
            background: .light,
            gradient: opaqueOnly,
            geometry: 沉浸封面文字取样几何(
                imageSize: CGSize(width: 400, height: 500),
                regions: [:],
                viewportSize: CGSize(width: 400, height: 870)
            )
        ))
        // 白底 → 黑色底图 0.56 → 白色覆盖 0.2 → 黑色封面 × 渐隐 0.5，全部在编码值上混合。
        let expected: Float = ((1 - 0.56) * 0.8 + 0.2) * 0.5
        let color = model.composite(at: CGPoint(x: 200, y: 250))
        #expect(abs(color.x - expected) < 0.01)
        // 编码 0.276 对应相对亮度约 0.062；按线性亮度混合会得到 0.276，误判为浅色背景。
        #expect(沉浸封面合成模型.luminance(color) < 0.08)
    }

    @Test
    func 封面内容偏移后底部露出背景() throws {
        let model = try #require(沉浸封面合成模型(
            map: 纯色图(0, width: 8, height: 4),
            background: .light,
            gradient: 沉浸封面渐变方案(
                sharp: [.init(1, at: 0)],
                mediumBlurRadius: 1,
                medium: [.init(0, at: 0)],
                heavyBlurRadius: 1,
                heavy: [.init(0, at: 0)],
                fade: [.init(1, at: 0)]
            ),
            geometry: 沉浸封面文字取样几何(
                imageSize: CGSize(width: 400, height: 200),
                regions: [:],
                viewportSize: CGSize(width: 400, height: 870),
                contentOffsetY: -60
            )
        ))
        #expect(model.composite(at: CGPoint(x: 200, y: 100)).x < 0.05)
        #expect(model.composite(at: CGPoint(x: 200, y: 195)).x > 0.4)
    }

    // MARK: 判定

    @Test
    func 按APCA可读度选择文字颜色() {
        #expect(判定.使用黑字(均匀统计(0.6)))
        #expect(!判定.使用黑字(均匀统计(0.05)))
        // 中间调彩色背景上白字更合适（WCAG 2 会选黑字）。
        #expect(!判定.使用黑字(均匀统计(0.25)))
        // 背景一半很亮一半很暗时，最差处决定结果，不能只看平均值。
        let mixed = 沉浸取样亮度统计(p10: 0.01, p50: 0.25, p90: 0.9, 样本数: 64)
        #expect(判定.最差可读度(mixed, usesDarkText: true) < 判定.最低可读度)
        #expect(判定.最差可读度(mixed, usesDarkText: false) < 判定.最低可读度)
    }

    @Test
    func 同一画面总是得到同样的颜色() {
        // 不受之前取样的影响：下拉后松手，回到原位的颜色与下拉前一致。
        let rest = 均匀统计(0.3)
        let before = 判定.使用黑字(rest)
        _ = 判定.使用黑字(均匀统计(0.6))
        #expect(判定.使用黑字(rest) == before)
    }

    @Test
    func 只有十分难以看清时才补偿着色() {
        // 白字在 0.3 上仍清楚，保持透明。
        #expect(判定.补偿着色(均匀统计(0.3), usesDarkText: false) == 0)
        let bright = 均匀统计(0.6)
        let tint = 判定.补偿着色(bright, usesDarkText: false)
        #expect(tint > 0)
        #expect(tint <= 判定.最大补偿着色)
        #expect(判定.最差可读度(bright, usesDarkText: false, tint: tint)
            > 判定.最差可读度(bright, usesDarkText: false))
        #expect(判定.补偿着色(均匀统计(0.02), usesDarkText: false) == 0)
        #expect(判定.补偿着色(均匀统计(0.8), usesDarkText: true) == 0)
    }

    @Test
    func 组内少数元素在组色不可读时保留自己的颜色() {
        let metrics: [String: 沉浸取样亮度统计] = [
            "tags": 均匀统计(0.6),
            "tags.item.0": 均匀统计(0.7),
            "tags.item.1": 均匀统计(0.65),
            "tags.item.2": 均匀统计(0.75),
            "tags.item.3": 均匀统计(0.3),
            "tags.item.4": 均匀统计(0.005)
        ]
        let groups = Dictionary(uniqueKeysWithValues: metrics.keys.map { ($0, "tags") })
        let results = 判定.协调(统计: metrics, 分组: groups)
        #expect(results["tags"]?.usesDarkText == true)
        // 0.3 处单看白字略优，但黑字也清楚，跟随组色。
        #expect(results["tags.item.3"]?.usesDarkText == true)
        // 近黑处黑字不可读，改用白字。
        #expect(results["tags.item.4"]?.usesDarkText == false)
    }

    @Test
    func 文字颜色不随深浅模式翻转() throws {
        let groups = ["metadata": "metadata"]
        for luminance in stride(from: 0.0, through: 1.0, by: 0.05) {
            let metrics = ["metadata": 均匀统计(luminance)]
            let light = try #require(判定.协调(统计: metrics, 分组: groups, 背景: .light)["metadata"])
            let dark = try #require(判定.协调(统计: metrics, 分组: groups, 背景: .dark)["metadata"])
            #expect(light.usesDarkText == dark.usesDarkText)
        }
        // 用户截图（初恋＊シンドローム）标题处实测：两种模式都用白字，玻璃透明。
        let title = ["metadata": 沉浸取样亮度统计(p10: 0.14, p50: 0.30, p90: 0.37, 样本数: 64)]
        for background in [沉浸详情背景色调.light, .dark] {
            let result = try #require(判定.协调(统计: title, 分组: groups, 背景: background)["metadata"])
            #expect(!result.usesDarkText)
            #expect(result.glassTint == nil)
        }
    }

    @Test
    func 难以看清时浅色黑字提亮深色白字压暗() throws {
        let groups = ["metadata": "metadata"]
        let hard = ["metadata": 沉浸取样亮度统计(p10: 0.06, p50: 0.2, p90: 0.6, 样本数: 64)]
        let light = try #require(判定.协调(统计: hard, 分组: groups, 背景: .light)["metadata"])
        #expect(light.usesDarkText)
        #expect(light.glassTint?.明暗 == .white)
        let dark = try #require(判定.协调(统计: hard, 分组: groups, 背景: .dark)["metadata"])
        #expect(!dark.usesDarkText)
        #expect(dark.glassTint?.明暗 == .black)

        // 偏好的组合补偿后仍看不清时，退回画面本身更好的颜色。
        let darker = ["metadata": 沉浸取样亮度统计(p10: 0.03, p50: 0.2, p90: 0.6, 样本数: 64)]
        let fallback = try #require(判定.协调(统计: darker, 分组: groups, 背景: .light)["metadata"])
        #expect(!fallback.usesDarkText)
        #expect(fallback.glassTint?.明暗 == .black)
    }

    @Test
    func 标题下方的几项信息统一颜色() throws {
        // 发行日期单看偏暗、其余偏亮：四项统一取让最难看清那一项更清楚的颜色。
        let metrics: [String: 沉浸取样亮度统计] = [
            "metadata": 均匀统计(0.5),
            "metadata.title": 均匀统计(0.5),
            "metadata.rating": 均匀统计(0.55),
            "metadata.length": 均匀统计(0.6),
            "metadata.release": 均匀统计(0.3),
            "metadata.status": 均匀统计(0.5)
        ]
        let groups = Dictionary(uniqueKeysWithValues: metrics.keys.map { ($0, "metadata") })
        let unified = Dictionary(uniqueKeysWithValues: ["rating", "length", "release", "status"].map {
            ("metadata.\($0)", "metadata.stats")
        })
        for background in [沉浸详情背景色调.light, .dark] {
            let results = 判定.协调(统计: metrics, 分组: groups, 统一: unified, 背景: background)
            let colors = Set(unified.keys.compactMap { results[$0]?.usesDarkText })
            #expect(colors == [true])
        }
    }

    @Test
    func 深色模式透明玻璃自身提亮() {
        // 真机截图拟合：浅色模式不改变背景，深色模式明显提亮。
        #expect(沉浸取样校准常量.表面提亮(.透明玻璃, background: .light) == 0)
        #expect(沉浸取样校准常量.表面提亮(.透明玻璃, background: .dark) > 0.15)
    }

    // MARK: 渐变方案

    @Test
    func 渐变插值与LinearGradient一致() {
        let fade = 沉浸封面渐变方案.紧凑标准.fade
        #expect(fade.不透明度(at: 0.2) == 1)
        #expect(abs(fade.不透明度(at: 0.64) - 0.74) < 0.0001)
        #expect(fade.不透明度(at: 0.99) == 0)
        let regular = 沉浸封面渐变方案.常规(transitionStart: 0.5)
        #expect(regular.fade.不透明度(at: 0.5) == 1)
        #expect(abs(regular.sharp.不透明度(at: 0.5) - 0.76) < 0.0001)
    }

    // MARK: 端到端

    @Test
    func 纯白封面浅色模式用黑字并显出玻璃() throws {
        let request = 沉浸封面文字取样请求(
            url: try #require(URL(string: "https://example.com/white.jpg")),
            layout: .visualNovel,
            background: .light,
            gradient: .紧凑延伸,
            itemCounts: ["tags": 2],
            geometry: 沉浸封面文字取样几何(
                imageSize: CGSize(width: 402, height: 600),
                regions: ["metadata.title": CGRect(x: 16, y: 220, width: 370, height: 40)],
                viewportSize: CGSize(width: 402, height: 874)
            )
        )
        let results = 沉浸封面文字分析缓存.textSamples(
            map: 纯色图(255),
            request: request
        )
        let title = try #require(results["metadata.title"])
        #expect(title.usesDarkText)
        #expect(title.glassTint == .init(明暗: .white, 不透明度: 1))
        #expect(!title.needsContrastShadow)
    }

    @Test
    func 纯黑封面深色模式用白字() throws {
        let request = 沉浸封面文字取样请求(
            url: try #require(URL(string: "https://example.com/black.jpg")),
            layout: .character,
            background: .dark,
            gradient: .紧凑标准,
            itemCounts: ["traits": 3],
            geometry: 沉浸封面文字取样几何(
                imageSize: CGSize(width: 402, height: 400),
                regions: [:]
            )
        )
        let results = 沉浸封面文字分析缓存.textSamples(
            map: 纯色图(0),
            request: request
        )
        #expect(!results.isEmpty)
        #expect(results.values.allSatisfy { !$0.usesDarkText })
    }
}
