import Foundation
import zlib

/// YU-RIS 的 .ypf 封包。文件名不区分大小写，路径分隔符统一成 /。
nonisolated final class YURIS封包: @unchecked Sendable {
    struct 条目 {
        let 压缩: Bool
        let 原始大小: Int
        let 封包大小: Int
        let 偏移: UInt64
    }

    let 地址: URL
    let 版本: Int
    private(set) var 条目表: [String: 条目] = [:]
    /// 解密后的文件名原始字节
    private(set) var 原名: [String: [UInt8]] = [:]
    private let handle: FileHandle
    private let lock = NSLock()

    private static let 名称长度对换: [UInt8: UInt8] = {
        let pairs: [(UInt8, UInt8)] = [(3, 72), (6, 53), (9, 11), (12, 16), (13, 19), (17, 25), (21, 27), (28, 30), (32, 35), (38, 41), (44, 47), (46, 50)]
        var map: [UInt8: UInt8] = [:]
        for (a, b) in pairs { map[a] = b; map[b] = a }
        return map
    }()

    init?(地址: URL) {
        guard let handle = try? FileHandle(forReadingFrom: 地址),
              let head = try? handle.read(upToCount: 32), head.count == 32,
              head.prefix(4) == Data([0x59, 0x50, 0x46, 0x00]) else { return nil }
        self.地址 = 地址
        self.handle = handle
        版本 = Int(head.读UInt32(4))
        let count = Int(head.读UInt32(8))
        guard count > 0, count < 1_000_000 else { return nil }
        // 目录紧跟文件头，最长的条目也不到 300 字节
        guard let directory = try? handle.read(upToCount: min(count * 320, 64 * 1024 * 1024)),
              let size = try? handle.seekToEnd() else { return nil }
        // 0.477 起偏移是 8 字节。商业版的版本号不一定可信，对不上就试另一种
        let preferred = 版本 >= 477
        guard let entries = Self.读目录(directory, 个数: count, 文件大小: size, 宽偏移: preferred)
                ?? Self.读目录(directory, 个数: count, 文件大小: size, 宽偏移: !preferred) else { return nil }
        // 文件名默认按字节异或 0xFF，商业版可能换值：扩展名前的点能帮忙确认
        var mask: UInt8 = 0xFF
        if !entries.contains(where: { $0.名称.map { $0 ^ 0xFF }.suffix(4).first == 0x2E }) {
            for candidate in 0...255 where entries.allSatisfy({ $0.名称.count < 4 || $0.名称.suffix(4).first! ^ UInt8(candidate) == 0x2E }) {
                mask = UInt8(candidate)
                break
            }
        }
        for entry in entries {
            let name = entry.名称.map { $0 ^ mask }
            let text = YURIS文本.解码文件名(name).replacingOccurrences(of: "\\", with: "/").lowercased()
            条目表[text] = entry.条目
            原名[text] = name
        }
    }

    private static func 读目录(_ directory: Data, 个数 count: Int, 文件大小 fileSize: UInt64, 宽偏移 wide: Bool) -> [(名称: [UInt8], 条目: 条目)]? {
        let bytes = [UInt8](directory)
        var p = 0
        var result: [(名称: [UInt8], 条目: 条目)] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard p + 5 <= bytes.count else { return nil }
            p += 4
            var length = bytes[p] ^ 0xFF
            p += 1
            length = 名称长度对换[length] ?? length
            guard p + Int(length) + (wide ? 22 : 18) <= bytes.count else { return nil }
            let name = Array(bytes[p..<(p + Int(length))])
            p += Int(length)
            guard bytes[p + 1] <= 1 else { return nil }
            let compressed = bytes[p + 1] != 0
            p += 2
            let size = Int(directory.读UInt32(p)); p += 4
            let packed = Int(directory.读UInt32(p)); p += 4
            let offset: UInt64
            if wide { offset = directory.读UInt64(p); p += 8 } else { offset = UInt64(directory.读UInt32(p)); p += 4 }
            p += 4
            guard offset + UInt64(packed) <= fileSize else { return nil }
            result.append((name, 条目(压缩: compressed, 原始大小: size, 封包大小: packed, 偏移: offset)))
        }
        return result
    }

    func 添加别名(_ alias: String, 原名 name: String) {
        条目表[alias] = 条目表[name]
    }

    func 读取(_ name: String) -> Data? {
        guard let entry = 条目表[name] else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard (try? handle.seek(toOffset: entry.偏移)) != nil,
              let raw = try? handle.read(upToCount: entry.封包大小) else { return nil }
        return entry.压缩 ? Self.解压(raw, 大小: entry.原始大小) : raw
    }

    static func 解压(_ data: Data, 大小: Int) -> Data? {
        var output = Data(count: 大小)
        var length = uLong(大小)
        let status = output.withUnsafeMutableBytes { out in
            data.withUnsafeBytes { input in
                uncompress(out.bindMemory(to: Bytef.self).baseAddress, &length, input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count))
            }
        }
        return status == Z_OK ? output : nil
    }
}

/// 一部游戏的全部资源：封包加散放文件。后读入的封包覆盖先读入的（update*.ypf 是补丁）。
nonisolated final class YURIS资源库: @unchecked Sendable {
    let 根目录: URL
    private(set) var 封包: [YURIS封包] = []
    private var 索引: [String: YURIS封包] = [:]
    private var 散放文件: [String: URL] = [:]

    init(根目录: URL) {
        self.根目录 = 根目录
        let manager = FileManager.default
        if let walker = manager.enumerator(at: 根目录, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            var packs: [URL] = []
            for case let url as URL in walker {
                let depth = url.pathComponents.count - 根目录.pathComponents.count
                if depth > 2 { walker.skipDescendants(); continue }
                if url.pathExtension.lowercased() == "ypf" { packs.append(url) }
            }
            for url in packs.sorted(by: { $0.path < $1.path }) {
                guard let pack = YURIS封包(地址: url) else { continue }
                封包.append(pack)
                for name in pack.条目表.keys { 索引[name] = pack }
            }
        }
    }

    /// 文字不是日文编码时，脚本里的文件名也会按那种编码解出来。把封包里的日文文件名换一种解法多登记一份。
    func 添加别名() {
        for pack in 封包 {
            for (name, raw) in pack.原名 {
                let alias = YURIS文本.解码(raw).replacingOccurrences(of: "\\", with: "/").lowercased()
                if alias != name, 索引[alias] == nil {
                    索引[alias] = pack
                    pack.添加别名(alias, 原名: name)
                }
            }
        }
    }

    private func 规范(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    func 存在(_ name: String) -> Bool {
        let key = 规范(name)
        return 索引[key] != nil || 散放地址(key) != nil
    }

    /// 所有名称（调试和按前缀枚举用）
    var 全部名称: [String] { Array(索引.keys) }

    private func 散放地址(_ key: String) -> URL? {
        if let known = 散放文件[key] { return known }
        var current = 根目录
        for part in key.split(separator: "/") {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: current.path),
                  let match = items.first(where: { $0.lowercased() == part }) else { return nil }
            current.append(path: match)
        }
        散放文件[key] = current
        return current
    }

    /// 封包里的文件名（小写），启动前用来判断要不要下载资源
    var 封包文件名: [String] { Array(索引.keys) }

    /// 不在封包里的文件（swf 只能这样放）
    func 散放文件地址(_ name: String) -> URL? {
        散放地址(规范(name))
    }

    func 读取(_ name: String) -> Data? {
        let key = 规范(name)
        if let pack = 索引[key], let data = pack.读取(key) { return data }
        if let url = 散放地址(key) { return try? Data(contentsOf: url, options: .mappedIfSafe) }
        return nil
    }
}

nonisolated enum YURIS文本 {
    private static let shiftJIS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)))
    private static let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
    enum 文字编码类型: Sendable { case 日文, gbk, utf8 }
    /// 游戏文字的编码。汉化版常把 WORD 换成 GBK，商业版有的用 UTF-8。读脚本时判断
    nonisolated(unsafe) static var 文字编码: 文字编码类型 = .日文

    static func 解码(_ data: Data) -> String {
        switch 文字编码 {
        case .gbk: if let text = String(data: data, encoding: gbk) { return text }
        case .utf8: if let text = String(data: data, encoding: .utf8) { return text }
        case .日文: break
        }
        return String(data: data, encoding: shiftJIS) ?? String(decoding: data, as: UTF8.self)
    }

    static func 解码(_ bytes: [UInt8]) -> String {
        解码(Data(bytes))
    }

    /// 封包里的文件名总是日文编码
    static func 解码文件名(_ bytes: [UInt8]) -> String {
        String(data: Data(bytes), encoding: shiftJIS) ?? String(decoding: bytes, as: UTF8.self)
    }

    static func 编码(_ text: String) -> [UInt8] {
        switch 文字编码 {
        case .gbk: if let data = text.data(using: gbk) { return [UInt8](data) }
        case .utf8: return Array(text.utf8)
        case .日文: break
        }
        if let data = text.data(using: shiftJIS) { return [UInt8](data) }
        return Array(text.utf8)
    }

    @inline(__always)
    static func 是首字节(_ c: UInt8) -> Bool {
        switch 文字编码 {
        case .日文: return (c >= 0x81 && c <= 0x9F) || (c >= 0xE0 && c <= 0xFC)
        case .gbk: return c >= 0x81 && c <= 0xFE
        case .utf8: return c >= 0xC0
        }
    }

    /// 从这个首字节开始的字符占几个字节
    @inline(__always)
    static func 字符长度(_ c: UInt8) -> Int {
        guard 是首字节(c) else { return 1 }
        if 文字编码 == .utf8 { return c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : 2 }
        return 2
    }

    /// E-ris 的控制字符（0xEF 接 0xF0～0xF3）不是合法的 UTF-8，要按两个字节算
    @inline(__always)
    static func 字符长度(_ bytes: [UInt8], _ i: Int) -> Int {
        if 文字编码 == .utf8, bytes[i] == 0xEF, i + 1 < bytes.count, bytes[i + 1] >= 0xF0 { return 2 }
        return 字符长度(bytes[i])
    }

    /// 看一段文字的字节判断编码
    static func 判断编码(_ sample: [UInt8]) -> 文字编码类型 {
        guard sample.contains(where: { $0 >= 0x80 }) else { return .日文 }
        if let text = String(data: Data(sample), encoding: .utf8), text.unicodeScalars.contains(where: { $0.value >= 0x80 }) {
            return .utf8
        }
        // 日文的平假名、片假名在 CP932 里是 0x82 0x9F-0xF1 和 0x83 0x40-0x96
        var double = 0, kana = 0, invalid = 0
        var i = 0
        while i < sample.count {
            let c = sample[i]
            if c < 0x80 || (c >= 0xA1 && c <= 0xDF) {
                i += 1
                continue
            }
            guard (c >= 0x81 && c <= 0x9F) || (c >= 0xE0 && c <= 0xFC), i + 1 < sample.count else {
                invalid += 1
                i += 1
                continue
            }
            let d = sample[i + 1]
            if (d >= 0x40 && d <= 0x7E) || (d >= 0x80 && d <= 0xFC) {
                double += 1
                if (c == 0x82 && d >= 0x9F && d <= 0xF1) || (c == 0x83 && d >= 0x40 && d <= 0x96) { kana += 1 }
                i += 2
            } else {
                invalid += 1
                i += 1
            }
        }
        if double > 0, kana * 5 >= double, invalid * 20 <= double { return .日文 }
        return String(data: Data(sample), encoding: gbk) != nil ? .gbk : .日文
    }

    /// 字符数（双字节算一个）
    static func 字符数(_ bytes: [UInt8]) -> Int {
        var count = 0, i = 0
        while i < bytes.count {
            i += 字符长度(bytes, i)
            count += 1
        }
        return count
    }

    /// 按字符取子串。位置从 1 开始。
    static func 子串(_ bytes: [UInt8], 位置: Int, 长度: Int) -> [UInt8] {
        guard 长度 > 0, 位置 >= 1 else { return [] }
        var i = 0, index = 1
        while i < bytes.count, index < 位置 {
            i += 字符长度(bytes, i)
            index += 1
        }
        guard i < bytes.count else { return [] }
        let start = i
        var taken = 0
        while i < bytes.count, taken < 长度 {
            i += 字符长度(bytes, i)
            taken += 1
        }
        return Array(bytes[start..<min(i, bytes.count)])
    }

    /// 每个字符一个标记：半角 1，全角 2（$_TEXT_FLAG）
    static func 字符标记(_ bytes: [UInt8]) -> [UInt8] {
        var flags: [UInt8] = []
        flags.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            if 是首字节(bytes[i]) {
                flags.append(0x32)
                i += 字符长度(bytes, i)
            } else {
                flags.append(0x31)
                i += 1
            }
        }
        return flags
    }
}

extension Data {
    nonisolated func 读UInt16(_ at: Int) -> UInt16 {
        let i = startIndex + at
        return UInt16(self[i]) | UInt16(self[i + 1]) << 8
    }
    nonisolated func 读UInt32(_ at: Int) -> UInt32 {
        let i = startIndex + at
        return UInt32(self[i]) | UInt32(self[i + 1]) << 8 | UInt32(self[i + 2]) << 16 | UInt32(self[i + 3]) << 24
    }
    nonisolated func 读UInt64(_ at: Int) -> UInt64 {
        UInt64(读UInt32(at)) | UInt64(读UInt32(at + 4)) << 32
    }
}
