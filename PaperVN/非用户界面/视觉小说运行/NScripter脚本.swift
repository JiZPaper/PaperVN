import Foundation

/// NScripter 的脚本：0.txt～99.txt（也可能是 00.txt～99.txt）按编号连接，或者是 nscript.dat、onscript.nt、pscript.dat（每字节异或 0x84）、
/// nscr_sec.dat（循环异或 5 字节）、nscript.___（密钥表在 EXE 里）、onscript.nt2、onscript.nt3。
/// 日文原版是 Shift-JIS（CP932），中文汉化版多是 GBK，按内容判断。
nonisolated struct NScripter脚本: Sendable {
    let 行: [String]
    /// 小写的标签名（不含 *）→ 所在行
    let 标签: [String: Int]
    let 屏幕宽: Int
    let 屏幕高: Int
    let 编码: String.Encoding

    static let CP932 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
    ))
    static let GBK = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
    ))

    static func 载入(_ root: URL) throws -> NScripter脚本 {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let names = Dictionary(files.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        var data = Data()
        for index in 0...99 {
            for name in index < 10 ? ["\(index).txt", "0\(index).txt"] : ["\(index).txt"] {
                guard let actual = names[name], let part = try? Data(contentsOf: root.appending(path: actual)) else { continue }
                data.append(part)
                data.append(0x0a)
            }
        }
        if data.isEmpty {
            for name in ["nscript.dat", "pscript.dat"] {
                guard let actual = names[name], var raw = try? Data(contentsOf: root.appending(path: actual)) else { continue }
                for i in raw.indices { raw[i] ^= 0x84 }
                data = raw
                break
            }
        }
        if data.isEmpty, let actual = names["nscr_sec.dat"], var raw = try? Data(contentsOf: root.appending(path: actual)) {
            let key: [UInt8] = [0x79, 0x57, 0x0D, 0x80, 0x04]
            for (offset, i) in raw.indices.enumerated() { raw[i] ^= key[offset % key.count] }
            data = raw
        }
        if data.isEmpty, let actual = names["nscript.___"], let raw = try? Data(contentsOf: root.appending(path: actual)) {
            data = 解密EXE密钥脚本(raw, root: root, 文件: files) ?? Data()
        }
        if data.isEmpty, let actual = names["onscript.nt"], let raw = try? Data(contentsOf: root.appending(path: actual)) {
            data = 解密NT(raw)
        }
        if data.isEmpty, let actual = names["onscript.nt2"], let raw = try? Data(contentsOf: root.appending(path: actual)) {
            data = Data(raw.map { ($0 ^ 0x85) &- 1 })
        }
        if data.isEmpty, let actual = names["onscript.nt3"], let raw = try? Data(contentsOf: root.appending(path: actual)) {
            data = 解密NT3(raw) ?? Data()
        }
        guard !data.isEmpty else {
            throw 视觉小说运行错误.无法读取(String(localized: "此视觉小说的脚本已加密，PaperVN无法读取。"))
        }

        let encoding = 判断编码(data)
        guard let text = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .shiftJIS)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw 视觉小说运行错误.无法读取(String(localized: "无法读取此视觉小说的脚本。"))
        }
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        if lines.last?.isEmpty == true { lines.removeLast() }

        var labels: [String: Int] = [:]
        for (index, line) in lines.enumerated() {
            let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
            guard trimmed.first == "*" else { continue }
            let name = trimmed.dropFirst().prefix { !$0.isWhitespace && $0 != ";" && $0 != ":" }.lowercased()
            if labels[name] == nil { labels[name] = index }
        }

        // 第一行的 ;mode800、;mode400、;$V2000G200S1280,720 指定画面大小
        var size = (640, 480)
        if let first = lines.first?.lowercased() {
            if first.hasPrefix(";mode800") { size = (800, 600) }
            else if first.hasPrefix(";mode400") { size = (400, 300) }
            else if first.hasPrefix(";mode320") { size = (320, 240) }
            else if first.hasPrefix(";mode1024") { size = (1024, 768) }
            else if first.hasPrefix(";mode1280") { size = (1280, 720) }
            else if first.hasPrefix(";$"), let s = first.firstIndex(of: "s") {
                let numbers = first[first.index(after: s)...].split(whereSeparator: { !$0.isNumber }).prefix(2).compactMap { Int($0) }
                if numbers.count == 2, numbers[0] > 0, numbers[1] > 0 { size = (numbers[0], numbers[1]) }
            }
        }
        return NScripter脚本(行: lines, 标签: labels, 屏幕宽: size.0, 屏幕高: size.1, 编码: encoding)
    }

    /// nscript.___：每个字节先查表再异或 0x84。256 字节的表存在游戏的 EXE 里，是第一段 256 个字节互不相同的数据
    /// （那一段的第 i 个字节解成 i）。文件夹里可能有多个 EXE，解出来像脚本的才算对。
    private static func 解密EXE密钥脚本(_ raw: Data, root: URL, 文件 files: [String]) -> Data? {
        for name in files where (name as NSString).pathExtension.lowercased() == "exe" {
            guard let exe = try? Data(contentsOf: root.appending(path: name), options: .mappedIfSafe),
                  let table = 查找密钥表(exe) else { continue }
            let plain = Data(raw.map { table[Int($0)] ^ 0x84 })
            if plain.contains(0x2A), plain.prefix(4096).contains(where: { $0 == 0x0A || $0 == 0x0D }) { return plain }
        }
        return nil
    }

    static func 查找密钥表(_ exe: Data) -> [UInt8]? {
        var last = [Int](repeating: -1, count: 256)
        var start = 0
        return exe.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8]? in
            for i in 0..<bytes.count {
                let value = Int(bytes[i])
                if last[value] >= start { start = last[value] + 1 }
                last[value] = i
                if i - start + 1 == 256 {
                    var table = [UInt8](repeating: 0, count: 256)
                    for offset in 0..<256 { table[Int(bytes[start + offset])] = UInt8(offset) }
                    return table
                }
            }
            return nil
        }
    }

    /// onscript.nt：先 (b ^ 0x85) - 1，再把 GBK 字符按打乱表还原。旧的简单异或也试一下。
    static func 解密NT(_ raw: Data) -> Data {
        var bytes = raw.map { ($0 ^ 0x85) &- 1 }
        还原双字节(&bytes)
        let result = Data(bytes)
        if 像脚本(result) { return result }
        let plain = Data(raw.map { $0 ^ 0x84 })
        return 像脚本(plain) ? plain : result
    }

    /// onscript.nt3 有三种：短文件单字节异或；滚动密钥加打乱表；还有一种前 0x91C 字节无用、接着 4 字节初始密钥、
    /// 从 0x920 开始的（密钥随解密滚动，用到“还剩多少字节”）。解出来像脚本的才算对。
    static func 解密NT3(_ raw: Data) -> Data? {
        if raw.prefix(2) != Data("PK".utf8) {
            if raw.count < 4000 {
                let plain = Data(raw.map { $0 ^ 0x98 })
                if 像脚本(plain) { return plain }
            } else {
                let key = NScripterNT表.滚动密钥
                var bytes = [UInt8](raw)
                for i in bytes.indices { bytes[i] = (bytes[i] ^ key[i % key.count]) &- 1 }
                还原双字节(&bytes)
                let plain = Data(bytes)
                if 像脚本(plain) { return plain }
            }
        }
        guard raw.count > 0x920 else { return nil }
        let bytes = [UInt8](raw)
        var key = UInt32(bytes[0x91C]) | UInt32(bytes[0x91D]) << 8 | UInt32(bytes[0x91E]) << 16 | UInt32(bytes[0x91F]) << 24
        let size = bytes.count - 0x920
        var output = [UInt8](repeating: 0, count: size)
        for index in 0..<size {
            let value = bytes[0x920 + index]
            key ^= UInt32(value)
            key &+= UInt32(value) &* UInt32(truncatingIfNeeded: size - index) &+ 0x5D58_8B65
            output[index] = value ^ UInt8(truncatingIfNeeded: key)
        }
        let plain = Data(output)
        return 像脚本(plain) ? plain : nil
    }

    /// 解密方式试错时的判断：有换行、有行首的 *，控制字符很少
    static func 像脚本(_ data: Data) -> Bool {
        let sample = data.prefix(1 << 20)
        var control = 0, newlines = 0, label = false, lineStart = true
        for byte in sample {
            if byte == 0x0A || byte == 0x0D {
                newlines += 1
                lineStart = true
                continue
            }
            if byte < 0x20, byte != 0x09 { control += 1 }
            if lineStart, byte == 0x2A { label = true }
            if byte != 0x20, byte != 0x09 { lineStart = false }
        }
        return newlines > 0 && label && control * 100 < sample.count
    }

    private static let 打乱表: (表: [UInt16], 无效: Set<Int>) = {
        let raw = Data(base64Encoded: NScripterNT表.打乱表Base64) ?? Data()
        let table = raw.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self)) }
        var invalid = Set<Int>()
        // 对应的字符不是有效的 GBK 时，这一项不算数
        for (index, value) in table.enumerated() {
            let code = value &+ 0x8140
            let bytes = [UInt8(code & 0xFF), UInt8(code >> 8)]
            guard let text = String(bytes: bytes, encoding: GBK), text.utf16.count == 1, text != "?" else {
                invalid.insert(index)
                continue
            }
        }
        return (table, invalid)
    }()

    private static func 特殊还原(_ bytes: inout [UInt8], _ i: Int) -> Bool {
        let key = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
        guard let value = NScripterNT表.特殊映射[key] else { return false }
        bytes[i] = UInt8(value >> 8)
        bytes[i + 1] = UInt8(value & 0xFF)
        return true
    }

    private static func 还原双字节(_ bytes: inout [UInt8]) {
        let (table, invalid) = 打乱表
        var i = 0
        while i < bytes.count - 1 {
            if bytes[i] > 0x81, bytes[i] != 0xFF {
                let index = (Int(bytes[i]) << 8 | Int(bytes[i + 1])) - 0x8140
                if index < 0 || index >= table.count || invalid.contains(index) {
                    if 特殊还原(&bytes, i) { i += 1 }
                } else {
                    let value = table[index] &+ 0x8140
                    bytes[i + 1] = UInt8(value >> 8)
                    bytes[i] = UInt8(value & 0xFF)
                    i += 1
                }
            } else if 特殊还原(&bytes, i) {
                i += 1
            }
            i += 1
        }
    }

    /// 用 CP932 解码后，日文里平假名、片假名占非 ASCII 字符的比例很高；中文用 CP932 解出来几乎没有全角假名。
    private static func 判断编码(_ data: Data) -> String.Encoding {
        let sample = data.prefix(400_000)
        func kanaRatio(_ encoding: String.Encoding) -> Double? {
            // 截断处可能切开一个双字节字符，往前退到换行
            let cut = sample.lastIndex(of: 0x0a).map { sample[..<$0] } ?? sample
            guard let text = String(data: Data(cut), encoding: encoding) else { return nil }
            var kana = 0
            var nonASCII = 0
            for scalar in text.unicodeScalars where scalar.value > 0x7f {
                nonASCII += 1
                if (0x3041...0x30ff).contains(scalar.value) { kana += 1 }
            }
            return nonASCII == 0 ? 1 : Double(kana) / Double(nonASCII)
        }
        if let ratio = kanaRatio(CP932), ratio > 0.12 { return CP932 }
        if kanaRatio(GBK) != nil { return GBK }
        return CP932
    }
}
