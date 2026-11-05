import Accelerate
import CoreGraphics
import CoreText
import Foundation
import ImageIO

/// 位图：内存顺序 A R G B，预乘透明度。行宽固定为 宽 × 4。
nonisolated final class YURIS图像: @unchecked Sendable {
    let 宽: Int
    let 高: Int
    let 像素: UnsafeMutablePointer<UInt8>

    static let 色彩空间 = CGColorSpaceCreateDeviceRGB()
    static let 位图信息 = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

    /// 新位图，内容为全透明
    init(宽: Int, 高: Int) {
        self.宽 = max(1, 宽)
        self.高 = max(1, 高)
        let size = self.宽 * self.高 * 4
        像素 = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        像素.initialize(repeating: 0, count: size)
    }

    deinit { 像素.deallocate() }

    var 字节数: Int { 宽 * 高 * 4 }

    func 复制() -> YURIS图像 {
        let copy = YURIS图像(宽: 宽, 高: 高)
        memcpy(copy.像素, 像素, 字节数)
        return copy
    }

    func 填充(a: UInt8, r: UInt8, g: UInt8, b: UInt8) {
        let pattern = UInt32(a) | UInt32(r) << 8 | UInt32(g) << 16 | UInt32(b) << 24
        像素.withMemoryRebound(to: UInt32.self, capacity: 宽 * 高) { pointer in
            for i in 0..<(宽 * 高) { pointer[i] = pattern }
        }
    }

    func 缓冲区() -> vImage_Buffer {
        vImage_Buffer(data: 像素, height: vImagePixelCount(高), width: vImagePixelCount(宽), rowBytes: 宽 * 4)
    }

    func 上下文() -> CGContext? {
        CGContext(data: 像素, width: 宽, height: 高, bitsPerComponent: 8, bytesPerRow: 宽 * 4,
                  space: Self.色彩空间, bitmapInfo: Self.位图信息)
    }

    func 转CGImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes: 像素, count: 字节数) as CFData) else { return nil }
        return CGImage(width: 宽, height: 高, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 宽 * 4,
                       space: Self.色彩空间, bitmapInfo: CGBitmapInfo(rawValue: Self.位图信息),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func 解码(_ data: Data) -> YURIS图像? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let result = YURIS图像(宽: image.width, 高: image.height)
        guard let context = result.上下文() else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return result
    }

    @inline(__always)
    func 取像素(_ x: Int, _ y: Int) -> (a: UInt8, r: UInt8, g: UInt8, b: UInt8) {
        guard x >= 0, y >= 0, x < 宽, y < 高 else { return (0, 0, 0, 0) }
        let p = 像素 + (y * 宽 + x) * 4
        return (p[0], p[1], p[2], p[3])
    }

    /// 从另一张位图裁出一块（越界部分透明）
    func 裁剪(x: Int, y: Int, 宽 w: Int, 高 h: Int) -> YURIS图像 {
        let result = YURIS图像(宽: w, 高: h)
        let x0 = max(0, x), y0 = max(0, y)
        let x1 = min(宽, x + w), y1 = min(高, y + h)
        guard x1 > x0, y1 > y0 else { return result }
        for row in y0..<y1 {
            memcpy(result.像素 + ((row - y) * result.宽 + (x0 - x)) * 4, 像素 + (row * 宽 + x0) * 4, (x1 - x0) * 4)
        }
        return result
    }

    /// 缩放（vImage，Lanczos）
    func 缩放(宽 w: Int, 高 h: Int) -> YURIS图像 {
        let result = YURIS图像(宽: w, 高: h)
        if w == 宽, h == 高 {
            memcpy(result.像素, 像素, 字节数)
            return result
        }
        var source = 缓冲区(), target = result.缓冲区()
        vImageScale_ARGB8888(&source, &target, nil, vImage_Flags(kvImageEdgeExtend))
        return result
    }

    /// 最近邻缩放
    func 最近邻缩放(宽 w: Int, 高 h: Int) -> YURIS图像 {
        let result = YURIS图像(宽: w, 高: h)
        if w == 宽, h == 高 {
            memcpy(result.像素, 像素, 字节数)
            return result
        }
        let sw = 宽, sh = 高, rw = result.宽, rh = result.高
        像素.withMemoryRebound(to: UInt32.self, capacity: sw * sh) { from in
            result.像素.withMemoryRebound(to: UInt32.self, capacity: rw * rh) { to in
                for y in 0..<rh {
                    let sy = y * sh / rh
                    let row = from + sy * sw
                    let out = to + y * rw
                    for x in 0..<rw { out[x] = row[x * sw / rw] }
                }
            }
        }
        return result
    }

    /// 从小数坐标的源矩形缩放，用于慢速缩放镜头（整数坐标会抖）
    func 小数缩放(x: Double, y: Double, x2: Double, y2: Double, 宽 w: Double, 高 h: Double) -> YURIS图像 {
        // 脚本给坐标加了很小的偏移（0.02）防止取整误差，实际没有缩放时直接裁剪，省下绝大部分开销
        let roundedX = x.rounded(), roundedY = y.rounded()
        if abs(x - roundedX) < 0.05, abs(y - roundedY) < 0.05,
           abs((x2 - x) - w) < 0.05, abs((y2 - y) - h) < 0.05 {
            return 裁剪(x: Int(roundedX), y: Int(roundedY), 宽: Int(w.rounded()), 高: Int(h.rounded()))
        }
        let result = YURIS图像(宽: Int(w.rounded(.up)), 高: Int(h.rounded(.up)))
        guard let context = result.上下文(), let image = 转CGImage() else { return result }
        let sourceWidth = max(0.0001, x2 - x), sourceHeight = max(0.0001, y2 - y)
        let scaleX = w / sourceWidth, scaleY = h / sourceHeight
        context.interpolationQuality = .medium
        context.setBlendMode(.copy)
        // 上下文原点在左下
        let rect = CGRect(x: -x * scaleX,
                          y: Double(result.高) - h + (y + sourceHeight - Double(高)) * scaleY,
                          width: Double(宽) * scaleX, height: Double(高) * scaleY)
        context.draw(image, in: rect)
        return result
    }
}

/// 图层或图层集（文件夹）
nonisolated final class YURIS图层 {
    let 名称: [UInt8]
    weak var 父: YURIS图层?
    let 是集合: Bool
    var 子: [[UInt8]: YURIS图层] = [:]
    var 排序好的子: [YURIS图层]?
    nonisolated(unsafe) private static var 下一个序号 = 0
    let 创建序号: Int

    var 图像: YURIS图像?
    var 启用 = true
    var 透明度 = 256
    var x = 0, y = 0
    var z: Int64 = 0 {
        didSet { if z != oldValue { 父?.排序好的子 = nil } }
    }
    var 集合宽 = 0, 集合高 = 0
    var 模式 = 0
    var 过渡进度 = 256
    var 过渡图层: [UInt8] = []
    var 过渡精度 = 0
    var 蒙版图层: [UInt8] = []
    var 整数属性: [Int64] = [0, 0]

    init(名称: [UInt8], 父: YURIS图层?, 是集合: Bool) {
        self.名称 = 名称
        self.父 = 父
        self.是集合 = 是集合
        Self.下一个序号 += 1
        创建序号 = Self.下一个序号
    }

    var 宽: Int { 是集合 ? 集合宽 : (图像?.宽 ?? 0) }
    var 高: Int { 是集合 ? 集合高 : (图像?.高 ?? 0) }

    /// 屏幕坐标（到 W0 为止）
    var 绝对位置: (x: Int, y: Int) {
        var ax = x, ay = y
        var node = 父
        while let current = node, current.父 != nil {
            ax += current.x
            ay += current.y
            node = current.父
        }
        return (ax, ay)
    }

    func 排序子() -> [YURIS图层] {
        if let sorted = 排序好的子 { return sorted }
        let sorted = 子.values.sorted { $0.z != $1.z ? $0.z < $1.z : $0.创建序号 < $1.创建序号 }
        排序好的子 = sorted
        return sorted
    }
}

nonisolated struct YURIS字体状态 {
    var 名称 = "ＭＳ ゴシック"
    var 颜色: Int64 = 0xFFFFFF
    var 颜色2: Int64 = 0xFFFFFF
    var 宽 = 24
    var 高 = 24
    var 粗体 = false
    var 抗锯齿 = true
    var 绘制模式 = 0
    var 渐变 = 0
    var 旋转 = 0
    /// BNO=1 的渐变色（按钮文字用）
    var 备用颜色: Int64 = 0xFFFFFF
    var 备用颜色2: Int64 = 0xFFFFFF
}

nonisolated final class YURIS画面: @unchecked Sendable {
    let 根: YURIS图层
    let 资源: YURIS资源库
    private(set) var 主集合: YURIS图层
    var 宽: Int
    var 高: Int
    var 脏 = true
    private var 文件缓存: [String: YURIS图像] = [:]
    private var 缓存字节 = 0
    private var 缓存顺序: [String] = []
    private static let 缓存上限 = 192 * 1024 * 1024
    private var 画布: YURIS图像
    private var 名称缓存: [[UInt8]: [[UInt8]]] = [:]
    /// 字体缓存
    private var 字体缓存: [String: CTFont] = [:]
    /// MOVIE 播放期间只显示影片，其他图层都看不到
    var 影片模式 = false
    /// 取帧之后到下一次取帧之前有效
    var 影片帧: 视觉小说影片.帧?
    /// 没有指定大小时和窗口一样大
    var 影片区域: (x: Int, y: Int, 宽: Int?, 高: Int?) = (0, 0, nil, nil)
    private var 影片缩放缓冲: YURIS图像?

    init(资源: YURIS资源库, 宽: Int, 高: Int) {
        self.资源 = 资源
        self.宽 = 宽
        self.高 = 高
        根 = YURIS图层(名称: [], 父: nil, 是集合: true)
        for number in 0...3 {
            let set = YURIS图层(名称: Array("W\(number)".utf8), 父: 根, 是集合: true)
            根.子[set.名称] = set
        }
        主集合 = 根.子[Array("W0".utf8)]!
        主集合.集合宽 = 宽
        主集合.集合高 = 高
        画布 = YURIS图像(宽: 宽, 高: 高)
    }

    // MARK: - 路径

    /// `:/W0/ABC/` → 根 → W0 → ABC。返回 (路径片段, 是否集合, 是否绝对)
    private func 解析路径(_ id: [UInt8]) -> (parts: [[UInt8]], isSet: Bool, absolute: Bool) {
        var bytes = id[...]
        var absolute = false
        if bytes.first == 0x3A { // :
            absolute = true
            bytes = bytes.dropFirst()
            if bytes.first == 0x2F { bytes = bytes.dropFirst() }
        }
        let isSet = bytes.last == 0x2F
        var parts: [[UInt8]] = []
        var current: [UInt8] = []
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let c = bytes[i]
            if YURIS文本.是首字节(c), i + 1 < bytes.endIndex {
                let end = min(bytes.endIndex, i + YURIS文本.字符长度(c))
                current.append(contentsOf: bytes[i..<end])
                i = end
                continue
            }
            if c == 0x2F || c == 0x5C {
                if !current.isEmpty { parts.append(current); current = [] }
            } else {
                current.append(c >= 0x61 && c <= 0x7A ? c - 0x20 : c)
            }
            i += 1
        }
        if !current.isEmpty { parts.append(current) }
        return (parts, isSet, absolute)
    }

    func 查找(_ id: [UInt8]) -> YURIS图层? {
        let (parts, _, absolute) = 解析路径(id)
        var node: YURIS图层 = absolute ? 根 : 主集合
        for part in parts {
            if part == [0x2E] { continue }
            if part == [0x2E, 0x2E] { node = node.父 ?? node; continue }
            guard let next = node.子[part] else { return nil }
            node = next
        }
        return node
    }

    /// 查找，不存在就逐级创建
    func 查找或新建(_ id: [UInt8]) -> YURIS图层 {
        let (parts, isSet, absolute) = 解析路径(id)
        var node: YURIS图层 = absolute ? 根 : 主集合
        for (index, part) in parts.enumerated() {
            if part == [0x2E] { continue }
            if part == [0x2E, 0x2E] { node = node.父 ?? node; continue }
            if let next = node.子[part] {
                node = next
            } else {
                let last = index == parts.count - 1
                let next = YURIS图层(名称: part, 父: node, 是集合: !last || isSet)
                node.子[part] = next
                node.排序好的子 = nil
                node = next
            }
        }
        return node
    }

    func 删除(_ id: [UInt8]) {
        guard let layer = 查找(id), let parent = layer.父 else { return }
        parent.子[layer.名称] = nil
        parent.排序好的子 = nil
        脏 = true
    }

    /// 把图层换到另一个 ID 上（SWAP）
    func 交换(_ a: YURIS图层, _ b: YURIS图层, 含属性: Bool) {
        swap(&a.图像, &b.图像)
        if 含属性 {
            swap(&a.启用, &b.启用)
            swap(&a.透明度, &b.透明度)
            swap(&a.x, &b.x)
            swap(&a.y, &b.y)
            let z = a.z; a.z = b.z; b.z = z
            swap(&a.模式, &b.模式)
            swap(&a.过渡进度, &b.过渡进度)
            swap(&a.过渡图层, &b.过渡图层)
            swap(&a.过渡精度, &b.过渡精度)
        }
        脏 = true
    }

    // MARK: - 文件

    private static let 图片扩展名 = ["png", "bmp", "jpg", "jpeg", "gif"]

    func 图片路径(_ file: String) -> String? {
        let name = file.replacingOccurrences(of: "\\", with: "/")
        if 资源.存在(name) { return name }
        for ext in Self.图片扩展名 where 资源.存在("\(name).\(ext)") {
            return "\(name).\(ext)"
        }
        return nil
    }

    /// 解码后的图片（共享，不要直接改）
    func 读图片(_ file: String) -> YURIS图像? {
        guard let path = 图片路径(file) else { return nil }
        let key = path.lowercased()
        if let cached = 文件缓存[key] { return cached }
        guard let data = 资源.读取(path), let image = YURIS图像.解码(data) else { return nil }
        文件缓存[key] = image
        缓存顺序.append(key)
        缓存字节 += image.字节数
        while 缓存字节 > Self.缓存上限, !缓存顺序.isEmpty {
            let oldest = 缓存顺序.removeFirst()
            if let removed = 文件缓存.removeValue(forKey: oldest) { 缓存字节 -= removed.字节数 }
        }
        return image
    }

    func 清空缓存() {
        文件缓存 = [:]
        缓存顺序 = []
        缓存字节 = 0
    }

    // MARK: - 合成

    /// 合成主画面。没有变化时返回 nil
    func 合成帧() -> YURIS图像? {
        guard 脏 else { return nil }
        脏 = false
        let w = 主集合.集合宽 > 0 ? 主集合.集合宽 : 宽
        let h = 主集合.集合高 > 0 ? 主集合.集合高 : 高
        if 画布.宽 != w || 画布.高 != h {
            画布 = YURIS图像(宽: w, 高: h)
        }
        画布.填充(a: 255, r: 0, g: 0, b: 0)
        if 影片模式 {
            绘制影片()
            return 画布
        }
        合成子层(主集合, 到: 画布, ox: 0, oy: 0, 裁剪: (0, 0, w, h))
        return 画布
    }

    private func 绘制影片() {
        guard let frame = 影片帧 else { return }
        let w = max(1, 影片区域.宽 ?? 画布.宽), h = max(1, 影片区域.高 ?? 画布.高)
        var source = frame.像素
        if w != frame.宽 || h != frame.高 {
            if 影片缩放缓冲?.宽 != w || 影片缩放缓冲?.高 != h { 影片缩放缓冲 = YURIS图像(宽: w, 高: h) }
            guard let scaled = 影片缩放缓冲 else { return }
            var from = vImage_Buffer(data: frame.像素, height: vImagePixelCount(frame.高), width: vImagePixelCount(frame.宽), rowBytes: frame.宽 * 4)
            var to = scaled.缓冲区()
            vImageScale_ARGB8888(&from, &to, nil, vImage_Flags(kvImageNoFlags))
            source = scaled.像素
        }
        // 超出画布的部分裁掉
        let left = max(0, 影片区域.x), top = max(0, 影片区域.y)
        let right = min(画布.宽, 影片区域.x + w), bottom = min(画布.高, 影片区域.y + h)
        guard right > left, bottom > top else { return }
        for row in top..<bottom {
            memcpy(画布.像素 + (row * 画布.宽 + left) * 4,
                   source + ((row - 影片区域.y) * w + (left - 影片区域.x)) * 4,
                   (right - left) * 4)
        }
    }

    /// 把图层集合成为一张新位图（截屏、COPY）
    func 渲染集合(_ set: YURIS图层) -> YURIS图像 {
        let w = max(1, set.集合宽 > 0 ? set.集合宽 : 宽)
        let h = max(1, set.集合高 > 0 ? set.集合高 : 高)
        let result = YURIS图像(宽: w, 高: h)
        // 截主画面时底色是黑的，跟窗口看到的一致
        if set === 主集合 { result.填充(a: 255, r: 0, g: 0, b: 0) }
        合成子层(set, 到: result, ox: 0, oy: 0, 裁剪: (0, 0, w, h))
        return result
    }

    private func 合成子层(_ set: YURIS图层, 到 dest: YURIS图像, ox: Int, oy: Int, 裁剪 clip: (Int, Int, Int, Int)) {
        for child in set.排序子() {
            guard child.启用, child.透明度 > 0 else { continue }
            if child.是集合 {
                if child.透明度 >= 256, child.模式 == 0, child.过渡图层.isEmpty {
                    // 不透明的集合可以直接画进父层
                    var newClip = clip
                    let cx = ox + child.x, cy = oy + child.y
                    if child.集合宽 > 0, child.集合高 > 0 {
                        newClip = (max(clip.0, cx), max(clip.1, cy), min(clip.2, cx + child.集合宽), min(clip.3, cy + child.集合高))
                    }
                    if newClip.2 > newClip.0, newClip.3 > newClip.1 {
                        合成子层(child, 到: dest, ox: cx, oy: cy, 裁剪: newClip)
                    }
                } else {
                    let offscreen = 渲染集合(child)
                    贴图(child, 图像: offscreen, 到: dest, ox: ox, oy: oy, 裁剪: clip)
                }
            } else if let image = child.图像 {
                贴图(child, 图像: image, 到: dest, ox: ox, oy: oy, 裁剪: clip)
            }
        }
    }

    private func 贴图(_ layer: YURIS图层, 图像 image: YURIS图像, 到 dest: YURIS图像, ox: Int, oy: Int, 裁剪 clip: (Int, Int, Int, Int)) {
        let dx = ox + layer.x, dy = oy + layer.y
        let x0 = max(clip.0, dx), y0 = max(clip.1, dy)
        let x1 = min(clip.2, dx + image.宽), y1 = min(clip.3, dy + image.高)
        guard x1 > x0, y1 > y0 else { return }
        // 过渡（规则图）
        if !layer.过渡图层.isEmpty, let rule = 查找(layer.过渡图层)?.图像 {
            绘制过渡(image, 规则: rule, 进度: layer.过渡进度, 精度: layer.过渡精度, 透明度: layer.透明度, 模式: layer.模式,
                 到: dest, dx: dx, dy: dy, 范围: (x0, y0, x1, y1))
            return
        }
        Self.混合(image, 到: dest, dx: dx, dy: dy, 范围: (x0, y0, x1, y1), 透明度: layer.透明度, 模式: layer.模式)
    }

    static func 混合(_ image: YURIS图像, 到 dest: YURIS图像, dx: Int, dy: Int, 范围 r: (Int, Int, Int, Int), 透明度 alpha: Int, 模式 mode: Int) {
        let w = r.2 - r.0, h = r.3 - r.1
        guard w > 0, h > 0 else { return }
        if mode == 0 {
            var top = vImage_Buffer(data: image.像素 + ((r.1 - dy) * image.宽 + (r.0 - dx)) * 4,
                                    height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: image.宽 * 4)
            var bottom = vImage_Buffer(data: dest.像素 + (r.1 * dest.宽 + r.0) * 4,
                                       height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: dest.宽 * 4)
            var out = bottom
            if alpha >= 256 {
                vImagePremultipliedAlphaBlend_ARGB8888(&top, &bottom, &out, vImage_Flags(kvImageDoNotTile))
            } else {
                vImagePremultipliedConstAlphaBlend_ARGB8888(&top, Pixel_8(max(0, alpha * 255 / 256)), &bottom, &out, vImage_Flags(kvImageDoNotTile))
            }
            return
        }
        // 其他描画模式走逐像素
        for y in 0..<h {
            var s = image.像素 + ((r.1 - dy + y) * image.宽 + (r.0 - dx)) * 4
            var d = dest.像素 + ((r.1 + y) * dest.宽 + r.0) * 4
            for _ in 0..<w {
                混合像素(s, d, alpha, mode)
                s += 4
                d += 4
            }
        }
    }

    @inline(__always)
    private static func 混合像素(_ s: UnsafeMutablePointer<UInt8>, _ d: UnsafeMutablePointer<UInt8>, _ layerAlpha: Int, _ mode: Int) {
        let sa = Int(s[0]) * layerAlpha / 256
        guard sa > 0 else { return }
        let da = Int(d[0])
        // 先还原成不预乘的颜色来算模式
        let sourceAlpha = max(1, Int(s[0]))
        for channel in 1...3 {
            let cs = min(255, Int(s[channel]) * 255 / sourceAlpha)
            let cb = da > 0 ? min(255, Int(d[channel]) * 255 / da) : 0
            let blended = 模式颜色(cb, cs, mode)
            // 标准公式：结果 = cs 贡献 + cb 贡献 + 混合贡献，都按预乘
            let result = (cs * sa * (255 - da) + Int(d[channel]) * (255 - sa) * 255 + blended * sa * da) / (255 * 255)
            d[channel] = UInt8(max(0, min(255, result)))
        }
        d[0] = UInt8(min(255, sa + da - sa * da / 255))
    }

    @inline(__always)
    private static func 模式颜色(_ b: Int, _ s: Int, _ mode: Int) -> Int {
        switch mode {
        case 1: return min(255, b + s)
        case 2: return max(0, b - s)
        case 3: return b * s / 255
        case 4: return s == 0 ? 255 : min(255, b * 255 / s)
        case 5: return 255 - (255 - b) * (255 - s) / 255
        case 6: return max(b, s)
        case 7: return min(b, s)
        case 8: return abs(b - s)
        case 9: return b + s - 2 * b * s / 255
        case 10: return b < 128 ? 2 * b * s / 255 : 255 - 2 * (255 - b) * (255 - s) / 255
        case 11: return s >= 255 ? 255 : min(255, b * 255 / (255 - s))
        case 12: return s == 0 ? 0 : 255 - min(255, (255 - b) * 255 / s)
        case 13: return max(0, b + s - 255)
        case 14: return s < 128 ? 2 * b * s / 255 : 255 - 2 * (255 - b) * (255 - s) / 255
        case 15:
            let fb = Double(b) / 255, fs = Double(s) / 255
            let value = fs < 0.5 ? fb - (1 - 2 * fs) * fb * (1 - fb) : fb + (2 * fs - 1) * ((fb <= 0.25 ? ((16 * fb - 12) * fb + 4) * fb : fb.squareRoot()) - fb)
            return Int(value * 255)
        case 16:
            if s < 128 { return s == 0 ? 0 : max(0, 255 - (255 - b) * 255 / (2 * s)) }
            return s >= 255 ? 255 : min(255, b * 255 / (2 * (255 - s)))
        case 17: return max(0, min(255, b + 2 * s - 255))
        case 18: return s < 128 ? min(b, 2 * s) : max(b, 2 * s - 255)
        default: return s
        }
    }

    private func 绘制过渡(_ image: YURIS图像, 规则 rule: YURIS图像, 进度 progress: Int, 精度 softness: Int, 透明度 alpha: Int, 模式 mode: Int,
                      到 dest: YURIS图像, dx: Int, dy: Int, 范围 r: (Int, Int, Int, Int)) {
        if progress >= 256 {
            Self.混合(image, 到: dest, dx: dx, dy: dy, 范围: r, 透明度: alpha, 模式: mode)
            return
        }
        guard progress > 0 else { return }
        let soft = max(1, softness)
        let threshold = progress * (255 + soft) / 256
        let w = r.2 - r.0, h = r.3 - r.1
        // 规则图和图层大小不同时按比例对应
        let scaleX = rule.宽 == image.宽, scaleY = rule.高 == image.高
        for y in 0..<h {
            let iy = r.1 - dy + y
            let ry = scaleY ? iy : iy * rule.高 / image.高
            var s = image.像素 + (iy * image.宽 + (r.0 - dx)) * 4
            var d = dest.像素 + ((r.1 + y) * dest.宽 + r.0) * 4
            let ruleRow = rule.像素 + ry * rule.宽 * 4
            for x in 0..<w {
                let ix = r.0 - dx + x
                let rx = scaleX ? ix : ix * rule.宽 / image.宽
                // 规则图是灰度，取绿色通道
                let v = Int(ruleRow[rx * 4 + 2])
                let factor = max(0, min(255, (threshold - v) * 255 / soft))
                if factor > 0 {
                    let a = Int(s[0]) * factor * alpha / (255 * 256)
                    if a > 0 {
                        if mode == 0 {
                            let inv = 255 - a
                            let scale = factor * alpha / 256
                            d[0] = UInt8(min(255, a + Int(d[0]) * inv / 255))
                            d[1] = UInt8(min(255, Int(s[1]) * scale / 255 + Int(d[1]) * inv / 255))
                            d[2] = UInt8(min(255, Int(s[2]) * scale / 255 + Int(d[2]) * inv / 255))
                            d[3] = UInt8(min(255, Int(s[3]) * scale / 255 + Int(d[3]) * inv / 255))
                        } else {
                            Self.混合像素(s, d, factor * alpha / 255, mode)
                        }
                    }
                }
                s += 4
                d += 4
            }
        }
    }

    /// 输出给界面：转成 BGRA（CoreAnimation 不用再转一次）
    static func 输出CGImage(_ image: YURIS图像) -> CGImage? {
        let size = image.字节数
        guard let bytes = malloc(size) else { return nil }
        var source = image.缓冲区()
        var target = vImage_Buffer(data: bytes, height: vImagePixelCount(image.高), width: vImagePixelCount(image.宽), rowBytes: image.宽 * 4)
        var map: [UInt8] = [3, 2, 1, 0]
        vImagePermuteChannels_ARGB8888(&source, &target, &map, vImage_Flags(kvImageDoNotTile))
        guard let provider = CGDataProvider(dataInfo: nil, data: bytes, size: size, releaseData: { _, data, _ in free(UnsafeMutableRawPointer(mutating: data)) }) else {
            free(bytes)
            return nil
        }
        return CGImage(width: image.宽, height: image.高, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: image.宽 * 4,
                       space: YURIS图像.色彩空间,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: - 文字

    private static func 系统字体名(_ name: String, 粗体: Bool) -> String {
        let serif = name.contains("明朝") || name.lowercased().contains("mincho") || name.contains("Serif")
        if serif { return 粗体 ? "HiraMinProN-W6" : "HiraMinProN-W3" }
        return 粗体 ? "HiraginoSans-W6" : "HiraginoSans-W3"
    }

    private func 字体(_ state: YURIS字体状态, 大小 size: Int) -> CTFont {
        let key = "\(Self.系统字体名(state.名称, 粗体: state.粗体))#\(size)"
        if let cached = 字体缓存[key] { return cached }
        let font = CTFontCreateWithName(Self.系统字体名(state.名称, 粗体: state.粗体) as CFString, CGFloat(size), nil)
        字体缓存[key] = font
        return font
    }

    /// 把文字画进位图。x、y 是左上角；全角字符占 宽，半角占 宽/2。
    func 绘制文字(_ text: [UInt8], 字体 state: YURIS字体状态, 到 image: YURIS图像, x: Int, y: Int, 描边: Int) {
        guard !text.isEmpty, let context = image.上下文() else { return }
        let font = 字体(state, 大小: state.高)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let baseline = CGFloat(state.高) * ascent / max(1, ascent + descent)
        context.setShouldAntialias(state.抗锯齿)
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        // 位图坐标上下翻转
        context.textMatrix = .identity
        let horizontal = CGFloat(state.宽) / CGFloat(max(1, state.高))
        var pen = x
        var i = 0
        func rgb(_ value: Int64) -> CGColor {
            CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        while i < text.count {
            let wide = YURIS文本.是首字节(text[i])
            let end = min(text.count, i + YURIS文本.字符长度(text[i]))
            let character = YURIS文本.解码(Array(text[i..<end]))
            i = end
            let advance = wide ? state.宽 : state.宽 / 2
            defer { pen += advance }
            if character == " " || character.isEmpty { continue }
            let cellTop = image.高 - y - state.高
            if state.绘制模式 == 0, 描边 == 0 {
                context.clear(CGRect(x: pen, y: cellTop, width: advance, height: state.高))
            }
            var characters = Array(character.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            let attributes: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: rgb(state.颜色)]
            let attributed = CFAttributedStringCreate(nil, character as CFString, attributes as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attributed)
            _ = characters.withUnsafeMutableBufferPointer { CTFontGetGlyphsForCharacters(font, $0.baseAddress!, &glyphs, $0.count) }
            context.saveGState()
            // 让字形在单元格里水平居中（比例字体不会偏）
            let bounds = CTLineGetTypographicBounds(line, nil, nil, nil)
            let offset = (CGFloat(advance) - CGFloat(bounds) * horizontal) / 2
            context.translateBy(x: CGFloat(pen) + offset, y: CGFloat(image.高 - y) - baseline)
            context.scaleBy(x: horizontal, y: 1)
            context.textPosition = .zero
            if 描边 > 0 {
                context.setTextDrawingMode(.fillStroke)
                context.setLineJoin(.round)
                context.setLineWidth(CGFloat(描边 == 11 ? 1 : 描边) * 2)
                context.setStrokeColor(rgb(state.颜色))
                context.setFillColor(rgb(state.颜色))
                CTFontDrawGlyphs(font, glyphs, [.zero], glyphs.count, context)
            } else if state.颜色 != state.颜色2, state.颜色2 >= 0 {
                context.setTextDrawingMode(.clip)
                CTFontDrawGlyphs(font, glyphs, [.zero], glyphs.count, context)
                if let gradient = CGGradient(colorsSpace: YURIS图像.色彩空间, colors: [rgb(state.颜色), rgb(state.颜色2)] as CFArray, locations: [0, 1]) {
                    let top = CGPoint(x: 0, y: baseline), bottom = CGPoint(x: 0, y: baseline - CGFloat(state.高))
                    context.drawLinearGradient(gradient, start: top, end: bottom, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
            } else {
                context.setTextDrawingMode(.fill)
                context.setFillColor(rgb(state.颜色))
                CTFontDrawGlyphs(font, glyphs, [.zero], glyphs.count, context)
            }
            context.restoreGState()
        }
        脏 = true
    }
}
