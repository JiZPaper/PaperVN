import CoreGraphics
import Foundation
import ImageIO

/// NScripter 的资源：arc.nsa、arc1.nsa…（ONScripter 的 .ns2）和 arc.sar 中的文件，找不到时读文件夹里的文件。
/// 查找顺序和 ONScripter 一样：先封包，后文件夹；路径不区分大小写，`\` 和 `/` 等同。
nonisolated final class NScripter资源: @unchecked Sendable {
    private struct 条目 {
        let 档案: Int
        let 偏移: UInt64
        let 长度: UInt32
        let 原始长度: UInt32
        let 压缩: UInt8
    }

    private let 根目录: URL
    private var 档案: [FileHandle] = []
    private var 条目表: [String: 条目] = [:]
    private var 文件夹索引: [String: String] = [:]
    private let 锁 = NSLock()
    let 文件名编码: String.Encoding

    init(根目录 root: URL, 编码 encoding: String.Encoding) {
        根目录 = root
        文件名编码 = encoding

        // 文件夹里的文件（补丁常常直接放文件）
        let rootPath = root.standardizedFileURL.path
        if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let file as URL in enumerator {
                let full = file.standardizedFileURL.path
                guard full.hasPrefix(rootPath) else { continue }
                var relative = String(full.dropFirst(rootPath.count))
                while relative.hasPrefix("/") { relative.removeFirst() }
                文件夹索引[Self.规范(relative)] = relative
            }
        }

        // ONScripter 的顺序：arc.sar、arc.nsa、arc1.nsa…arc9.nsa、00.ns2…；先读到的优先
        var archives: [(URL, Bool)] = []
        let sar = root.appending(path: "arc.sar")
        if let name = 文件夹索引["arc.sar"] { archives.append((root.appending(path: name), false)) } else if FileManager.default.fileExists(atPath: sar.path) { archives.append((sar, false)) }
        for index in 0...9 {
            let name = index == 0 ? "arc.nsa" : "arc\(index).nsa"
            if let actual = 文件夹索引[name] { archives.append((root.appending(path: actual), true)) }
        }
        for index in 0...99 {
            let name = String(format: "%02d.ns2", index)
            if let actual = 文件夹索引[name] { archives.append((root.appending(path: actual), true)) }
        }
        for (url, isNSA) in archives {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let archiveIndex = 档案.count
            档案.append(handle)
            let isNS2 = url.pathExtension.lowercased() == "ns2"
            for (name, entry) in (isNS2 ? Self.读取NS2目录(handle, archiveIndex) : Self.读取目录(handle, archiveIndex, nsa: isNSA, encoding: encoding)) {
                if 条目表[name] == nil { 条目表[name] = entry }
            }
        }
    }

    deinit {
        for handle in 档案 { try? handle.close() }
    }

    static func 规范(_ path: String) -> String {
        var value = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        while value.hasPrefix("./") { value.removeFirst(2) }
        while value.hasPrefix("/") { value.removeFirst() }
        return value
    }

    func 存在(_ path: String) -> Bool {
        let key = Self.规范(path)
        return 条目表[key] != nil || 文件夹索引[key] != nil
    }

    func 读取(_ path: String) -> Data? {
        let key = Self.规范(path)
        if let entry = 条目表[key] {
            return 读取条目(entry, 路径: key)
        }
        if let relative = 文件夹索引[key] {
            return try? Data(contentsOf: 根目录.appending(path: relative), options: .mappedIfSafe)
        }
        return nil
    }

    /// 文件夹里的文件地址（字体要直接注册文件）。
    func 文件夹地址(_ path: String) -> URL? {
        文件夹索引[Self.规范(path)].map { 根目录.appending(path: $0) }
    }

    var 文件夹文件: [String] { Array(文件夹索引.keys) }

    /// 封包和文件夹里的全部文件（规范化后的路径）。
    var 全部文件: Set<String> { Set(条目表.keys).union(文件夹索引.keys) }

    /// 解压后的大小，用来挑小文件做检查。
    func 大小(_ path: String) -> Int? {
        let key = Self.规范(path)
        if let entry = 条目表[key] { return Int(entry.原始长度 > 0 ? entry.原始长度 : entry.长度) }
        guard let relative = 文件夹索引[key] else { return nil }
        let values = try? 根目录.appending(path: relative).resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }

    private func 读取条目(_ entry: 条目, 路径 path: String) -> Data? {
        let raw: Data? = {
            锁.lock()
            defer { 锁.unlock() }
            let handle = 档案[entry.档案]
            guard (try? handle.seek(toOffset: entry.偏移)) != nil else { return nil }
            return try? handle.read(upToCount: Int(entry.长度))
        }()
        guard let raw else { return nil }
        switch entry.压缩 {
        case 1: return NScripter解码.SPB(raw)
        case 2: return NScripter解码.LZSS(raw, 原始长度: Int(entry.原始长度))
        default: return raw
        }
    }

    // MARK: 目录

    /// .sar：文件数(2)、数据起点(4)，每项：文件名\0、偏移(4)、长度(4)，均为大端。
    /// .nsa：同上，但每项在文件名后多一个压缩类型(1)，长度后多一个原始长度(4)。
    private static func 读取目录(_ handle: FileHandle, _ archive: Int, nsa: Bool, encoding: String.Encoding) -> [String: 条目] {
        guard let head = try? handle.read(upToCount: 6), head.count == 6 else { return [:] }
        let count = Int(head.大端16(0))
        let base = UInt64(head.大端32(2))
        guard base > 6, base < 64 * 1024 * 1024,
              let directory = try? handle.read(upToCount: Int(base) - 6) else { return [:] }
        var result: [String: 条目] = [:]
        var cursor = directory.startIndex
        for _ in 0..<count {
            guard let end = directory[cursor...].firstIndex(of: 0) else { break }
            let nameData = directory[cursor..<end]
            cursor = end + 1
            var compression: UInt8 = 0
            if nsa {
                guard cursor < directory.endIndex else { break }
                compression = directory[cursor]
                cursor += 1
            }
            guard cursor + (nsa ? 12 : 8) <= directory.endIndex else { break }
            let offset = UInt64(directory.大端32(cursor - directory.startIndex))
            let length = directory.大端32(cursor - directory.startIndex + 4)
            var original = length
            cursor += 8
            if nsa {
                original = directory.大端32(cursor - directory.startIndex)
                cursor += 4
            }
            guard let name = String(data: Data(nameData), encoding: encoding)
                    ?? String(data: Data(nameData), encoding: .shiftJIS) else { continue }
            // 扩展名是 .nbz 的是 bzip2，系统没有解码器，读不了
            result[规范(name)] = 条目(档案: archive, 偏移: base + offset, 长度: length, 原始长度: original, 压缩: compression)
        }
        return result
    }

    /// .ns2（ONScripter-jh）：数据起点(4，小端)，每项："文件名"(带引号)、长度(4，小端)，数据依次排列。
    private static func 读取NS2目录(_ handle: FileHandle, _ archive: Int) -> [String: 条目] {
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return [:] }
        let base = UInt64(head.小端32(0))
        guard base > 4, base < 64 * 1024 * 1024, let directory = try? handle.read(upToCount: Int(base) - 4) else { return [:] }
        var result: [String: 条目] = [:]
        var cursor = directory.startIndex
        var offset = base
        while cursor < directory.endIndex, directory[cursor] == UInt8(ascii: "\"") {
            guard let end = directory[(cursor + 1)...].firstIndex(of: UInt8(ascii: "\"")), end + 5 <= directory.endIndex else { break }
            let nameData = directory[(cursor + 1)..<end]
            let length = directory.小端32(end + 1 - directory.startIndex)
            cursor = end + 5
            if let name = String(data: Data(nameData), encoding: .utf8) ?? String(data: Data(nameData), encoding: .shiftJIS) {
                result[规范(name)] = 条目(档案: archive, 偏移: offset, 长度: length, 原始长度: length, 压缩: 0)
            }
            offset += UInt64(length)
        }
        return result
    }
}

// MARK: - 解码

nonisolated enum NScripter解码 {
    /// 按位读取，高位在前。
    private struct 位读取器 {
        let data: Data
        var index: Int
        var mask: UInt8 = 0
        var byte: UInt8 = 0

        init(_ data: Data, start: Int = 0) {
            self.data = data
            index = data.startIndex + start
        }

        mutating func 读(_ count: Int) -> Int {
            var result = 0
            for _ in 0..<count {
                if mask == 0 {
                    byte = index < data.endIndex ? data[index] : 0
                    index += 1
                    mask = 0x80
                }
                result <<= 1
                if byte & mask != 0 { result |= 1 }
                mask >>= 1
            }
            return result
        }
    }

    /// NScripter 的 LZSS：窗口 256（起点 256-17），偏移 8 位，长度 4 位（+2）。解出来通常是 BMP。
    static func LZSS(_ data: Data, 原始长度 length: Int) -> Data {
        var reader = 位读取器(data)
        var window = [UInt8](repeating: 0, count: 256)
        var r = 256 - 17
        var output = [UInt8]()
        output.reserveCapacity(length)
        while output.count < length {
            if reader.读(1) == 1 {
                let value = UInt8(reader.读(8))
                output.append(value)
                window[r] = value
                r = (r + 1) & 0xff
            } else {
                let position = reader.读(8)
                let count = reader.读(4) + 2
                for k in 0..<count {
                    guard output.count < length else { break }
                    let value = window[(position + k) & 0xff]
                    output.append(value)
                    window[r] = value
                    r = (r + 1) & 0xff
                }
            }
            if reader.index > data.endIndex + 1 { break }
        }
        return Data(output)
    }

    /// SPB：NScripter 专用的图片压缩。宽、高各 2 字节（大端），然后按 B、G、R 三个通道分别编码，
    /// 每个通道是蛇形扫描（偶数行从左到右，奇数行从右到左）的差分值。这里直接输出 BMP，和其他图片走同一条解码路线。
    static func SPB(_ data: Data) -> Data {
        guard data.count >= 4 else { return Data() }
        let width = Int(data.大端16(0))
        let height = Int(data.大端16(2))
        guard width > 0, height > 0, width * height < 64 * 1024 * 1024 else { return Data() }
        var reader = 位读取器(data, start: 4)
        let pixels = width * height
        let rowSize = (width * 3 + 3) & ~3
        var bmp = [UInt8](repeating: 0, count: 54 + rowSize * height)
        // BMP 头
        bmp[0] = 0x42; bmp[1] = 0x4d
        Self.写小端(&bmp, 2, UInt32(bmp.count))
        bmp[10] = 54; bmp[14] = 40
        Self.写小端(&bmp, 18, UInt32(width))
        Self.写小端(&bmp, 22, UInt32(height))
        bmp[26] = 1; bmp[28] = 24
        Self.写小端(&bmp, 34, UInt32(rowSize * height))

        var channel = [UInt8](repeating: 0, count: pixels + 4)
        for component in 0..<3 {
            var count = 0
            var c = UInt8(reader.读(8))
            channel[count] = c
            count += 1
            while count < pixels {
                let n = reader.读(3)
                if n == 0 {
                    for _ in 0..<4 { channel[count] = c; count += 1 }
                    continue
                }
                let m = n == 7 ? reader.读(1) + 1 : n + 2
                for _ in 0..<4 {
                    if m == 8 {
                        c = UInt8(reader.读(8))
                    } else {
                        let k = reader.读(m)
                        if k & 1 != 0 {
                            c = c &+ UInt8(truncatingIfNeeded: (k >> 1) + 1)
                        } else {
                            c = c &- UInt8(truncatingIfNeeded: k >> 1)
                        }
                    }
                    channel[count] = c
                    count += 1
                }
            }
            // 第 0 行是图片最上面一行，BMP 从下往上存
            var source = 0
            for y in 0..<height {
                let row = 54 + (height - 1 - y) * rowSize
                if y & 1 == 0 {
                    for x in 0..<width { bmp[row + x * 3 + component] = channel[source]; source += 1 }
                } else {
                    for x in stride(from: width - 1, through: 0, by: -1) { bmp[row + x * 3 + component] = channel[source]; source += 1 }
                }
            }
        }
        return Data(bmp)
    }

    private static func 写小端(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset] = UInt8(value & 0xff)
        buffer[offset + 1] = UInt8((value >> 8) & 0xff)
        buffer[offset + 2] = UInt8((value >> 16) & 0xff)
        buffer[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}

// MARK: - 图片

/// 处理过透明方式的图片。`格` 是横向排列的动画格或按钮状态，平时显示第 0 格。
nonisolated struct NScripter图像: @unchecked Sendable {
    let 格: [CGImage]
    var 宽: Int { 格.first?.width ?? 0 }
    var 高: Int { 格.first?.height ?? 0 }
}

nonisolated enum NScripter透明方式: Equatable {
    /// 左半是图，右半是遮罩（黑色不透明）
    case 遮罩
    /// 左上角像素的颜色透明
    case 左上
    /// 右上角像素的颜色透明
    case 右上
    /// 不透明
    case 不透明
    /// 指定颜色透明
    case 颜色(UInt8, UInt8, UInt8)
}

nonisolated enum NScripter图像解码 {
    /// 解析 `:a/3,100,0;image\foo.bmp` 这样的标签。没有写透明方式时用 `默认`。
    static func 解析标签(_ tag: String, 默认 defaultMode: NScripter透明方式) -> (文件: String, 方式: NScripter透明方式, 格数: Int) {
        guard tag.hasPrefix(":"), let semicolon = tag.firstIndex(of: ";") else {
            return (tag, defaultMode, 1)
        }
        let spec = tag[tag.index(after: tag.startIndex)..<semicolon]
        let file = String(tag[tag.index(after: semicolon)...])
        var mode = defaultMode
        var rest = Substring(spec)
        if let first = rest.first {
            switch first {
            case "a": mode = .遮罩; rest = rest.dropFirst()
            case "l": mode = .左上; rest = rest.dropFirst()
            case "r": mode = .右上; rest = rest.dropFirst()
            case "c": mode = .不透明; rest = rest.dropFirst()
            case "#":
                let hex = rest.dropFirst().prefix(6)
                if let value = UInt32(hex, radix: 16) {
                    mode = .颜色(UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff))
                }
                rest = rest.dropFirst(7)
            default: break
            }
        }
        var cells = 1
        if rest.first == "/" {
            let number = rest.dropFirst().prefix(while: \.isNumber)
            cells = max(1, Int(number) ?? 1)
        }
        return (file, mode, cells)
    }

    static func 解码(_ data: Data, 方式 mode: NScripter透明方式, 格数 cells: Int) -> NScripter图像? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space, bitmapInfo: info
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else { return nil }

        var outputWidth = width
        var output = pixels
        // 太窄的图片分不出图和遮罩，按不透明处理
        let mode = mode == .遮罩 && width / max(cells, 1) < 2 ? .不透明 : mode
        switch mode {
        case .不透明:
            break
        case .左上, .右上, .颜色:
            let key: (UInt8, UInt8, UInt8)
            switch mode {
            case .左上: key = (pixels[0], pixels[1], pixels[2])
            case .右上: key = (pixels[(width - 1) * 4], pixels[(width - 1) * 4 + 1], pixels[(width - 1) * 4 + 2])
            case .颜色(let r, let g, let b): key = (r, g, b)
            default: key = (0, 0, 0)
            }
            for i in stride(from: 0, to: output.count, by: 4)
            where output[i] == key.0 && output[i + 1] == key.1 && output[i + 2] == key.2 {
                output[i] = 0; output[i + 1] = 0; output[i + 2] = 0; output[i + 3] = 0
            }
        case .遮罩:
            // 每一格都是“图 | 遮罩”，多格时按格分别取
            let cellWidth = width / max(cells, 1)
            let half = cellWidth / 2
            outputWidth = half * cells
            output = [UInt8](repeating: 0, count: outputWidth * height * 4)
            for cell in 0..<cells {
                for y in 0..<height {
                    for x in 0..<half {
                        let colorIndex = (y * width + cell * cellWidth + x) * 4
                        let maskIndex = colorIndex + half * 4
                        let alpha = 255 - Int(pixels[maskIndex])
                        let target = (y * outputWidth + cell * half + x) * 4
                        output[target] = UInt8(Int(pixels[colorIndex]) * alpha / 255)
                        output[target + 1] = UInt8(Int(pixels[colorIndex + 1]) * alpha / 255)
                        output[target + 2] = UInt8(Int(pixels[colorIndex + 2]) * alpha / 255)
                        output[target + 3] = UInt8(alpha)
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(output) as CFData),
              let full = CGImage(
                width: outputWidth, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: outputWidth * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: info),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
              ) else { return nil }
        let cellWidth = outputWidth / max(cells, 1)
        guard cells > 1, cellWidth > 0 else { return NScripter图像(格: [full]) }
        let frames = (0..<cells).compactMap { full.cropping(to: CGRect(x: $0 * cellWidth, y: 0, width: cellWidth, height: height)) }
        return NScripter图像(格: frames.isEmpty ? [full] : frames)
    }
}

nonisolated extension Data {
    func 大端16(_ offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) << 8 | UInt16(self[base + 1])
    }

    func 大端32(_ offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) << 24 | UInt32(self[base + 1]) << 16 | UInt32(self[base + 2]) << 8 | UInt32(self[base + 3])
    }
}
