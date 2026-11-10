// 生成器在 Linux（VPS 每日任务）上的日文读音：macOS 的 CFStringTokenizer 在 Linux 上没有，
// 改用常驻的 MeCab 进程（apt：mecab mecab-ipadic-utf8）取读音，再把假名转成黑本式罗马字。
// 假名转罗马字是纯 Swift，macOS 上也能编译，用来和 CFStringTokenizer 对比一致率。
import Foundation

nonisolated enum 假名罗马字 {
    private static let 双字: [String: String] = [
        "きゃ": "kya", "きゅ": "kyu", "きょ": "kyo", "ぎゃ": "gya", "ぎゅ": "gyu", "ぎょ": "gyo",
        "しゃ": "sha", "しゅ": "shu", "しょ": "sho", "しぇ": "she", "じゃ": "ja", "じゅ": "ju", "じょ": "jo", "じぇ": "je",
        "ちゃ": "cha", "ちゅ": "chu", "ちょ": "cho", "ちぇ": "che", "ぢゃ": "ja", "ぢゅ": "ju", "ぢょ": "jo",
        "にゃ": "nya", "にゅ": "nyu", "にょ": "nyo", "ひゃ": "hya", "ひゅ": "hyu", "ひょ": "hyo",
        "びゃ": "bya", "びゅ": "byu", "びょ": "byo", "ぴゃ": "pya", "ぴゅ": "pyu", "ぴょ": "pyo",
        "みゃ": "mya", "みゅ": "myu", "みょ": "myo", "りゃ": "rya", "りゅ": "ryu", "りょ": "ryo",
        "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
        "てぃ": "ti", "でぃ": "di", "とぅ": "tu", "どぅ": "du", "でゅ": "dyu", "てゅ": "tyu",
        "うぃ": "wi", "うぇ": "we", "うぉ": "wo", "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo",
        "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso", "いぇ": "ye",
        "くぁ": "kwa", "くぃ": "kwi", "くぇ": "kwe", "くぉ": "kwo", "ぐぁ": "gwa",
    ]
    private static let 单字: [Character: String] = [
        "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
        "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko", "が": "ga", "ぎ": "gi", "ぐ": "gu", "げ": "ge", "ご": "go",
        "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so", "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze", "ぞ": "zo",
        "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to", "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
        "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
        "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho", "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
        "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
        "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo", "や": "ya", "ゆ": "yu", "よ": "yo",
        "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro", "わ": "wa", "ゐ": "i", "ゑ": "e", "を": "o", "ん": "n", "ゔ": "vu",
        "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o", "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "ゎ": "wa",
    ]

    /// 片假名转平假名只按码位平移，不依赖 ICU。
    static func 平假名(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value), let shifted = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(shifted)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    static func 转换(_ kana: String) -> String {
        let characters = Array(平假名(kana))
        var output = ""
        var 促音 = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "っ" {
                促音 = true
                index += 1
                continue
            }
            if character == "ー" {
                if let vowel = output.last(where: { "aiueo".contains($0) }) { output.append(vowel) }
                index += 1
                continue
            }
            var syllable: String?
            if index + 1 < characters.count, let pair = 双字[String(characters[index...index + 1])] {
                syllable = pair
                index += 2
            } else if let single = 单字[character] {
                syllable = single
                index += 1
            }
            guard let syllable else {
                output.append(character)
                促音 = false
                index += 1
                continue
            }
            if 促音, let first = syllable.first { output.append(first == "c" ? "t" : first) }
            促音 = false
            output += syllable
        }
        return output
    }
}

#if !canImport(Darwin)
/// 常驻的 MeCab 进程。生成器顺序调用，加锁只是为了满足跨隔离访问；结果带缓存。
nonisolated final class 日文读音桥: @unchecked Sendable {
    static let 共用 = 日文读音桥()
    private let lock = NSLock()
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var 缓存: [String: [(原文: String, 罗马字: String?)]] = [:]

    private init() {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mecab")
        process.arguments = ["-F", "%m\t%f[7]\n", "-E", "EOS\n", "-U", "%m\t*\n", "-d", "/var/lib/mecab/dic/ipadic-utf8"]
        process.standardInput = input
        process.standardOutput = output
        do {
            try process.run()
        } catch {
            fatalError("无法启动 MeCab：\(error)")
        }
    }

    private func 读一行() -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }

    /// 分词：日文词带罗马字，其他词（英文、符号）罗马字为 nil。
    func 分词(_ text: String) -> [(原文: String, 罗马字: String?)] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = 缓存[text] { return cached }
        let line = text.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\t", with: " ")
        input.fileHandleForWriting.write(Data((line + "\n").utf8))
        var tokens: [(原文: String, 罗马字: String?)] = []
        while let row = 读一行(), row != "EOS" {
            let fields = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard let surface = fields.first, !surface.isEmpty else { continue }
            let reading = fields.count > 1 && fields[1] != "*" && !fields[1].isEmpty ? fields[1] : surface
            tokens.append((surface, 主题曲文本.含日文(surface) ? 假名罗马字.转换(reading) : nil))
        }
        缓存[text] = tokens
        return tokens
    }
}
#endif

#if !canImport(CryptoKit)
/// 只用来算映射的版本号；Linux 上没有 CryptoKit，接口和 CryptoKit 的 SHA256.hash(data:) 相同（结果是字节序列）。
nonisolated enum SHA256 {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hash(data: Data) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var bytes = [UInt8](data)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xFF)) }
        func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
        var w = [UInt32](repeating: 0, count: 64)
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            for i in 0..<16 {
                let p = chunk + i * 4
                w[i] = UInt32(bytes[p]) << 24 | UInt32(bytes[p + 1]) << 16 | UInt32(bytes[p + 2]) << 8 | UInt32(bytes[p + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var v = h
            for i in 0..<64 {
                let s1 = rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25)
                let ch = (v[4] & v[5]) ^ (~v[4] & v[6])
                let t1 = v[7] &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22)
                let maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2])
                let t2 = s0 &+ maj
                v = [t1 &+ t2, v[0], v[1], v[2], v[3] &+ t1, v[4], v[5], v[6]]
            }
            for i in 0..<8 { h[i] = h[i] &+ v[i] }
        }
        return h.flatMap { value in [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) } }
    }
}
#endif
