import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking // 主题曲映射生成器的 Linux 版
#endif

/// 动画的片头曲、片尾曲和插入曲。片头曲、片尾曲来自 MyAnimeList 的 opening_themes、ending_themes，
/// 文本形如 `#1: "Yuusha (勇者)" by YOASOBI (eps 1-16)`：引号里是罗马字（或英文）标题，括号里是日文原名。
/// 插入曲来自 AnisongDB（只有罗马字），只在生成主题曲映射时读取，App 里只显示映射里找到了 Apple Music 歌曲的插入曲。
nonisolated struct 动画主题曲: Identifiable, Hashable, Sendable {
    enum 种类: String, Codable, Sendable {
        case 片头曲 = "op"
        case 片尾曲 = "ed"
        case 插入曲 = "in"
    }

    /// 片头曲、片尾曲是 MAL 的主题曲编号；插入曲是 AnisongDB 歌曲编号的相反数，不会和 MAL 的编号重复。
    let id: Int
    let 种类: 种类
    /// MAL 的序号，例如“1”“S1”；只有一首时没有。
    let 序号: String?
    /// 罗马字或英文标题。
    let 标题: String
    /// 日文原名；标题本身就是英文（或 MAL 没写原名）时没有。
    let 原标题: String?
    /// 歌手的罗马字名（不含括号里的原名、角色声优）。
    let 歌手: String
    /// 歌手的日文原名。
    let 歌手原名: String?
    /// 括号里的其他名字：角色歌的角色与声优、组合成员。只用来匹配 Apple Music。
    let 歌手别名: [String]
    /// MAL 原文的话数范围，例如“1-16”“1-14, 16-28”。
    let 话数: String?
    /// MAL 指定的版本，例如“Acoustic Ver.”“Wind Orchestra Ver.”；匹配时候选必须是这个版本。
    var 版本说明: String? = nil

    /// AnisongDB 的插入曲：歌名、歌手都是罗马字，`别名` 是歌手的其他写法与组合成员。
    init(插入曲编号: Int, 标题: String, 歌手: String, 别名: [String], 种类: 种类 = .插入曲, 话数: String? = nil) {
        id = -插入曲编号
        self.种类 = 种类
        序号 = nil
        self.标题 = 标题
        原标题 = nil
        self.歌手 = 歌手
        歌手原名 = nil
        歌手别名 = 别名
        self.话数 = 话数
    }

    /// 解析 MAL 的主题曲文本，格式不认识时返回 nil。
    init?(malID id: Int, 种类: 种类, 文本: String) {
        // 去掉异体字选择符：不用正则，这种写法在 Linux 的 Foundation 上会把整段文字清空
        let 去选择符 = String(String.UnicodeScalarView(文本.unicodeScalars.filter { !(0xFE00...0xFE0F).contains($0.value) }))
        var text = 去选择符.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var 序号: String?
        // “#5 cont. 1:”“cont 2.”：一首歌的歌手太多时分成几行，后面几行只有歌手，不是歌曲
        if let prefix = text.firstMatch(of: #/^(?:#?\w{0,4}:?\s*)?cont\.?\s*\d*\s*[.:]?\s*/#.ignoresCase()) {
            let rest = String(text[prefix.range.upperBound...])
            // cont. "Gold Ship (CV: …)"：引号里也只是歌手
            guard rest.contains("\""), rest.firstMatch(of: #/^"[^"]*\(CV/#) == nil else { return nil }
            if let number = text.firstMatch(of: #/^#?(\w{1,4})\s+cont/#.ignoresCase()) { 序号 = String(number.1) }
            text = rest
        }
        // 只有成员名单的行：“[Miho Nishizumi (Mai Fuchigami), …]”“Hosoya), Aiichirou Nitori (Kouki Miyata)”
        if !text.contains("\""), text.hasPrefix("[") || text.firstMatch(of: #/^[^(]*\)/#) != nil { return nil }
        // “#1:”“#S1:”“R3:”（重播期间的主题曲）这类序号；有时冒号后面还多一个冒号
        if let prefix = text.firstMatch(of: #/^#?([A-Za-z]{0,2}\d{0,3}[A-Za-z]?)(?:[ ]{0,2}\([^)]{0,12}\))?[ ]{0,2}:(?:[ ]{0,2}:)?[ ]{0,3}/#) {
            let value = String(prefix.1)
            if !value.isEmpty { 序号 = value }
            text = String(text[prefix.range.upperBound...])
        } else if let prefix = text.firstMatch(of: #/^#?([A-Za-z]{0,2}\d{1,3}[A-Za-z]?)\s*[.;]?\s*(?=")/#) {
            // “#1 "LUCKY"”“1. "Marionette"”“4; "…"”
            序号 = String(prefix.1)
            text = String(text[prefix.range.upperBound...])
        }
        while text.hasPrefix("\"\"") { text.removeFirst() }

        var 标题部分: String
        var 歌手部分: String
        if text.hasPrefix("\""), let parts = Self.拆开引号(text) {
            (标题部分, 歌手部分) = parts
        } else if let by = text.range(of: #"\s+by\s+"#, options: [.regularExpression, .caseInsensitive]) {
            标题部分 = String(text[..<by.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\", "))
            歌手部分 = String(text[by.upperBound...])
        } else {
            // 没有歌手
            标题部分 = text.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            歌手部分 = ""
        }
        if 标题部分.hasSuffix("''") { 标题部分.removeLast(2) }
        // “Suberidai" / "Slide”：同一首歌的两种写法，取第一个
        if let other = 标题部分.range(of: #""\s*[/&]\s*"?"#, options: .regularExpression) { 标题部分 = String(标题部分[..<other.lowerBound]) }
        歌手部分 = 歌手部分.trimmingCharacters(in: CharacterSet(charactersIn: "\", "))
        if 歌手部分.hasSuffix(").") { 歌手部分.removeLast() }

        // 末尾的话数：(eps 1-16)、(ep 22)、(eps Special Broadcast: 1-4)
        var 话数: String?
        if let (head, last) = Self.拆出末尾括号(歌手部分), last.range(of: Self.话数格式, options: [.regularExpression, .caseInsensitive]) != nil {
            话数 = last.replacingOccurrences(of: Self.话数格式 + #"\.?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            歌手部分 = head
        } else if let (head, last) = Self.拆出末尾括号(标题部分), 歌手部分.isEmpty,
                  last.range(of: Self.话数格式, options: [.regularExpression, .caseInsensitive]) != nil {
            话数 = last.replacingOccurrences(of: Self.话数格式 + #"\.?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            标题部分 = head
        }

        // 标题：“Yuusha (勇者)”拆成罗马字和日文；整个标题就是日文时两者相同
        var 标题 = 标题部分.trimmingCharacters(in: .whitespaces)
        var 原标题: String?
        // 末尾的版本说明：“Kore ga… (これが私の生きる道) (Wind Orchestra Ver.)”“Fly Me to the Moon -4 Beat Version-”
        var 版本说明: String?
        // “We go! (ウィーゴー！) Special ver.”：版本说明在日文名后面
        if let middle = 标题.firstMatch(of: #/^(.+\([^()]+\))\s+([^()]+)$/#), Self.拆出末尾括号(String(middle.1)).map({ 主题曲文本.含日文($0.1) }) == true {
            标题 = String(middle.1)
            版本说明 = String(middle.2)
        }
        if 版本说明 != nil {
            // 上面已经拆出来了
        } else if let (head, last) = Self.拆出末尾括号(标题), !head.isEmpty, !主题曲文本.含日文(last), Self.是版本说明(last) {
            标题 = head
            版本说明 = last
        } else if let dash = 标题.firstMatch(of: #/\s+-\s*([^-]+?)\s*-$/#), Self.是版本说明(String(dash.1)) {
            版本说明 = String(dash.1)
            标题 = String(标题[..<dash.range.lowerBound])
        }
        if let (head, last) = Self.拆出末尾括号(标题), 主题曲文本.含日文(last), !主题曲文本.含日文(head) {
            标题 = head
            // “残酷な天使のテーゼ, A Cruel Angel's Thesis”“天使と悪魔; ANGEL & DEVIL”：日文名后面跟着英文译名，只取日文那段
            原标题 = last.components(separatedBy: CharacterSet(charactersIn: ";；"))
                .flatMap { $0.components(separatedBy: ", ") }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: 主题曲文本.含日文) ?? last
        } else if let (head, last) = Self.拆出末尾括号(标题), !head.isEmpty, 主题曲文本.罗马字键(head) == 主题曲文本.罗马字键(last) {
            // “A to Z ~One Piece Edition~ (A to Z〜ONE PIECE Edition〜)”：括号里只是全角写法
            标题 = head
        } else if 主题曲文本.含日文(标题) {
            原标题 = 标题
        }

        // 歌手：“Yorushika (ヨルシカ)”“Houkago Tea Time (Yui Hirasawa (Aki Toyosaki), ...)”
        var 歌手 = 歌手部分.trimmingCharacters(in: .whitespaces)
        var 歌手原名: String?
        var 别名: [String] = []
        // 方括号里的成员名单：“XX:me (Kiss Me; キス・ミー) [Zero Two (Haruka Tomatsu), …]”
        if 歌手.hasSuffix("]"), let open = 歌手.lastIndex(of: "[") {
            别名 += Self.括号内名字(String(歌手[歌手.index(after: open)..<歌手.index(before: 歌手.endIndex)]))
            歌手 = 歌手[..<open].trimmingCharacters(in: .whitespaces)
        }
        while let (head, last) = Self.拆出末尾括号(歌手), !head.isEmpty {
            歌手 = head
            // “(Kiss Me; キス・ミー)”：英文名和日文名并列时取日文那段
            let japanese = last.components(separatedBy: CharacterSet(charactersIn: ";；")).map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: 主题曲文本.含日文)
            if let japanese, !japanese.contains(","), !japanese.contains("、"), 歌手原名 == nil, !主题曲文本.含日文(head) {
                歌手原名 = japanese
            } else {
                别名.append(contentsOf: Self.括号内名字(last))
            }
        }
        if 主题曲文本.含日文(歌手), 歌手原名 == nil { 歌手原名 = 歌手 }

        guard !标题.isEmpty else { return nil }
        self.版本说明 = 版本说明
        self.id = id
        self.种类 = 种类
        self.序号 = 序号
        self.标题 = 标题
        self.原标题 = 原标题
        self.歌手 = 歌手
        self.歌手原名 = 歌手原名
        self.歌手别名 = 别名
        // “2-3, 5-9; BD/DVD: eps 1-13”：只显示电视版的话数
        self.话数 = 话数.map { $0.replacingOccurrences(of: #"\s*[;,]\s*BD/DVD.*$"#, with: "", options: .regularExpression) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private nonisolated static let 话数格式 = #"^(?:TV:\s*)?(?:eps?|episodes?)\b"#

    /// 拆开带引号的“歌名 + 歌手”。歌名里可能还有引号（"All "the thing"s i am"），所以找第一个后面跟着“by”的引号；
    /// 引号和 by 之间的括号属于歌名（"Doro no Kusa" (泥の草) by …）。写法不认识时返回 nil。
    private nonisolated static func 拆开引号(_ text: String) -> (标题: String, 歌手: String)? {
        let body = text.dropFirst()
        if let match = body.firstMatch(of: #/"[,\s]*((?:\([^"]*\)|[A-Za-z ]{0,20}?)?)"?\s*(?:composed\s+|performed\s+)?\bbyi?\b\s*/#.ignoresCase()),
           !match.1.contains("\"") {
            return ("\(body[..<match.range.lowerBound]) \(match.1)".trimmingCharacters(in: .whitespaces), String(body[match.range.upperBound...]))
        }
        if let match = body.firstMatch(of: #/"?\s*byi?\s+/#.ignoresCase()), body[..<match.range.lowerBound].hasSuffix(")") {
            // "Kigeki (喜劇)"by …
            return (String(body[..<match.range.lowerBound]), String(body[match.range.upperBound...]))
        }
        guard let close = body.lastIndex(of: "\"") else { return nil }
        var title = String(body[..<close])
        var rest = String(body[body.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        // "Kasabuta by Hidenori Chiwata" (Episode 150)
        if rest.isEmpty || rest.hasPrefix("("), let by = title.range(of: " by ") {
            return (String(title[..<by.lowerBound]), "\(title[by.upperBound...]) \(rest)".trimmingCharacters(in: .whitespaces))
        }
        // 后面的括号是话数时留给调用方；其余括号属于歌名
        var episode = ""
        while let open = rest.first, open == "(", let end = rest.firstIndex(of: ")") {
            let group = String(rest[rest.index(after: rest.startIndex)..<end])
            if group.range(of: 话数格式, options: [.regularExpression, .caseInsensitive]) != nil {
                episode = " (\(group))"
            } else {
                title += " (\(group))"
            }
            rest = String(rest[rest.index(after: end)...]).trimmingCharacters(in: .whitespaces)
        }
        // "Making of a Cyborg" Kenji Kawai、"Hihamukage" (日蝕む翳) - Toshio Masuda
        if rest.hasPrefix("- ") { rest.removeFirst(2) }
        return (title, rest + episode)
    }

    /// “Acoustic Ver.”“TV Limited”“Rei #5 Version”这类说明版本的文字。
    nonisolated static func 是版本说明(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(?:ver\.?|version|edit|mix|remix|arrange|acoustic|size|limited|instrumental|off[- ]vocal)\b"#,
                   options: .regularExpression) != nil
    }

    /// 拆出末尾成对的括号：“A (B (C))”返回 (“A”, “B (C)”)。
    private nonisolated static func 拆出末尾括号(_ text: String) -> (String, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")") else { return nil }
        var depth = 0
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            index = trimmed.index(before: index)
            switch trimmed[index] {
            case ")": depth += 1
            case "(":
                depth -= 1
                if depth == 0 {
                    let head = trimmed[..<index].trimmingCharacters(in: .whitespaces)
                    let inner = trimmed[trimmed.index(after: index)..<trimmed.index(before: trimmed.endIndex)]
                    return (head, inner.trimmingCharacters(in: .whitespaces))
                }
            default: break
            }
        }
        return nil
    }

    /// “Yui Hirasawa (Aki Toyosaki), Mio Akiyama (CV: Youko Hikasa)”拆成每个名字。
    private nonisolated static func 括号内名字(_ text: String) -> [String] {
        var names: [String] = []
        var current = ""
        var depth = 0
        func flush() {
            let value = current
                .replacingOccurrences(of: #"^(?:CV|cv|Vo|vo)\s*[:.：]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^(?:and|&)\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { names.append(value) }
            current = ""
        }
        for character in text {
            switch character {
            case "(":
                if depth == 0 { flush() }
                depth += 1
            case ")":
                depth -= 1
                if depth == 0 { flush() }
            case "," where depth <= 1, "、" where depth <= 1:
                flush()
            default:
                current.append(character)
            }
        }
        flush()
        return names
    }
}

/// 匹配到的 Apple Music 歌曲。链接是日本商店里的地址，打开后进入“音乐”App。
/// 标题、歌手取自日本的商店，是原语言的写法（其他商店可能换成罗马字，例如“Sukimaswitch”）。
nonisolated struct AppleMusic歌曲: Codable, Hashable, Sendable {
    let id: Int
    let 标题: String
    let 歌手: String
    let 专辑: String
    let 封面: URL?
    let 链接: URL
}

nonisolated enum AppleMusic匹配结果: Codable, Hashable, Sendable {
    case 已找到(AppleMusic歌曲)
    case 未找到
}

// MARK: - 文本处理

nonisolated enum 主题曲文本 {
    /// 把日语罗马字转成平假名：Apple Music 日本商店不认罗马字，但能按读音检索汉字歌名（そうくうのほのお → 蒼空の炎）。
    /// 英文单词转不出来时返回 nil，不要拿去检索。独立的 wa、e、o 按助词写成は、へ、を。
    nonisolated static func 平假名读音(_ romaji: String) -> String? {
        let digraphs: [String: String] = [
            "kya": "きゃ", "kyu": "きゅ", "kyo": "きょ", "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ",
            "nya": "にゃ", "nyu": "にゅ", "nyo": "にょ", "hya": "ひゃ", "hyu": "ひゅ", "hyo": "ひょ", "mya": "みゃ", "myu": "みゅ", "myo": "みょ",
            "rya": "りゃ", "ryu": "りゅ", "ryo": "りょ", "gya": "ぎゃ", "gyu": "ぎゅ", "gyo": "ぎょ", "bya": "びゃ", "byu": "びゅ", "byo": "びょ",
            "pya": "ぴゃ", "pyu": "ぴゅ", "pyo": "ぴょ", "jya": "じゃ", "jyu": "じゅ", "jyo": "じょ", "shi": "し", "chi": "ち", "tsu": "つ",
        ]
        let pairs: [String: String] = [
            "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ", "sa": "さ", "si": "し", "su": "す", "se": "せ", "so": "そ",
            "ta": "た", "ti": "ち", "tu": "つ", "te": "て", "to": "と", "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
            "ha": "は", "hi": "ひ", "fu": "ふ", "hu": "ふ", "he": "へ", "ho": "ほ", "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
            "ya": "や", "yu": "ゆ", "yo": "よ", "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ", "wa": "わ", "wo": "を",
            "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご", "za": "ざ", "ji": "じ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
            "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど", "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
            "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ", "ja": "じゃ", "ju": "じゅ", "jo": "じょ",
        ]
        let vowels: [Character: String] = ["a": "あ", "i": "い", "u": "う", "e": "え", "o": "お"]
        let particles = ["wa": "は", "e": "へ", "o": "を", "wo": "を"]
        var result: [String] = []
        let words = romaji.lowercased().replacingOccurrences(of: "ō", with: "ou").replacingOccurrences(of: "ū", with: "uu")
            .split { !($0.isLetter && $0.isASCII) }
        guard !words.isEmpty else { return nil }
        for (index, word) in words.enumerated() {
            if index > 0, let particle = particles[String(word)] { result.append(particle); continue }
            let letters = Array(word)
            var i = 0
            var kana = ""
            while i < letters.count {
                if i + 3 <= letters.count, let value = digraphs[String(letters[i..<i + 3])] { kana += value; i += 3; continue }
                if i + 2 <= letters.count, let value = pairs[String(letters[i..<i + 2])] { kana += value; i += 2; continue }
                if let value = vowels[letters[i]] { kana += value; i += 1; continue }
                if letters[i] == "n" { kana += "ん"; i += 1; continue }
                // 促音：kk、tt、tch
                if i + 1 < letters.count, letters[i] == letters[i + 1] || (letters[i] == "t" && letters[i + 1] == "c") { kana += "っ"; i += 1; continue }
                return nil
            }
            result.append(kana)
        }
        return result.joined(separator: " ")
    }


    static func 含日文(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF66...0xFF9F: true
            default: false
            }
        }
    }

    /// 比较日文用：全角半角统一、小写、片假名转平假名，只留文字和数字。
    static func 日文键(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping.lowercased()
        // 简体统一成繁体：MAL 写“无别”，Apple 写“無別”
        let traditional = folded.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? folded
        let hiragana = traditional.applyingTransform(.hiraganaToKatakana, reverse: true) ?? traditional
        return String(String.UnicodeScalarView(hiragana.unicodeScalars.filter {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == "ー"
        }))
    }

    /// 有汉字、没有假名（中文歌名）。
    static func 只有汉字(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        let hasHan = scalars.contains { (0x3400...0x4DBF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
        let hasKana = scalars.contains { (0x3040...0x30FF).contains($0.value) || (0x31F0...0x31FF).contains($0.value) }
        return hasHan && !hasKana
    }

    /// 日文转成罗马字（汉字按日语读音），其他文字原样保留。
    static func 转写(_ text: String) -> String {
        guard 含日文(text) else { return text }
        #if canImport(Darwin)
        let string = text as NSString
        let tokenizer = CFStringTokenizerCreate(
            nil, text as CFString, CFRange(location: 0, length: string.length),
            kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
        )
        var parts: [String] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = string.substring(with: NSRange(location: range.location, length: range.length))
            if 含日文(token),
               let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                parts.append(latin)
            } else {
                parts.append(token)
            }
        }
        return parts.joined(separator: " ")
        #else
        return 日文读音桥.共用.分词(text).map { $0.罗马字 ?? $0.原文 }.joined(separator: " ")
        #endif
    }

    /// 罗马字的分词：去掉附加符号、小写，按非字母数字切开。
    static func 罗马字词(_ text: String) -> [String] {
        let folded = 转写(text).precomposedStringWithCompatibilityMapping
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map(罗马字规范)
    }

    static func 罗马字键(_ text: String) -> String {
        罗马字规范(罗马字词(text).joined())
    }

    /// 抹平罗马字拼法差异：Hepburn 与训令式、长音写法（ou、oo、ō）、促音与拨音，也让 l/r、v/b 视作相同。
    static func 罗马字规范(_ word: String) -> String {
        // “Ohtsuki”“Ohno”的 oh 是长音
        var value = word.lowercased().replacingOccurrences(of: "oh(?![aeiou])", with: "o", options: .regularExpression)
        for (from, to) in [("sh", "s"), ("ch", "t"), ("ts", "t"), ("dz", "z"), ("j", "z"), ("f", "h"),
                           ("l", "r"), ("v", "b"), ("mb", "nb"), ("mp", "np"), ("wo", "o"), ("du", "zu"), ("di", "zi")] {
            value = value.replacingOccurrences(of: from, with: to)
        }
        // 连续相同的字母合成一个（长音、促音、nn）
        var collapsed = ""
        for character in value where collapsed.last != character {
            collapsed.append(character)
        }
        return collapsed
            .replacingOccurrences(of: "ou", with: "o")
            .replacingOccurrences(of: "ei", with: "e")
            .replacingOccurrences(of: "y", with: "i")
    }

    /// 编辑距离换算的相似度，0…1。
    static func 相似度(_ a: String, _ b: String) -> Double {
        if a == b { return a.isEmpty ? 0 : 1 }
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }
}

// MARK: - Apple Music 匹配

/// 在 Apple Music 里找主题曲。日本的商店收录最全、标题和歌手用日文，先在那里检索和打分：
/// 歌名必须对上（日文原名、罗马字两种写法都比较），歌手也必须对上——歌手名用 Apple 自己的罗马字写法
/// （同一位歌手的编号在各商店通用，在美国商店查询编号就能拿到“Kenshi Yonezu”这样的写法）和转写后的读音比较，
/// 这样翻唱、八音盒、卡拉OK版本都会被排除。伴奏、现场、混音版本扣分，专辑名里有作品名的加分。
/// 不核对用户所在的地区：App 不知道用户订阅哪个地区的 Apple Music，链接交给“音乐”App 处理。
actor AppleMusic主题曲匹配 {
    static let shared = AppleMusic主题曲匹配()

    /// 改了匹配规则后加一，让旧的缓存失效。
    static let 规则版本 = 8

    private nonisolated struct 缓存文件: Codable {
        let 版本: Int
        let 保存时间: Date
        /// 匹配时映射里已有的结果，映射更新后对不上就重新匹配。
        let 已知: String
        let 结果: [Int: AppleMusic匹配结果]
    }

    private var 内存缓存: [String: 缓存文件] = [:]
    private var 罗马字歌手名: [Int: String] = [:]
    private var 罗马字曲名: [Int: String] = [:]
    /// Apple Music API 的检索结果不带歌手编号，按曲目查询后记在这里。
    private var 曲目歌手: [Int: [Int]] = [:]
    /// 用罗马字检索到的候选（名称是罗马字），选中后要换成日本商店原语言的名称。
    private var 罗马字候选: Set<Int> = []
    private let session: URLSession
    private let 每分钟请求上限: Int
    /// 两次请求之间至少隔这么久，避免一次发出大量请求触发突发限流。
    private let 最小间隔: TimeInterval
    private let 限流重试次数: Int
    private let 限流等待秒数: Double
    /// 有开发者令牌时用 Apple Music API（只用于生成主题曲映射），否则用不需要令牌的 iTunes 接口。
    private let 开发者令牌: String?
    /// 现场版、重录版、改编版也算找到（降分）。只用于统计放宽后能多找到多少，App 和映射都不用。
    private let 允许替代版本: Bool
    /// 生成主题曲映射时打印失败的请求，方便排查。
    private let 打印失败: Bool

    /// App 里每页只有几次请求，用默认值；批量生成主题曲映射时调低频率、限流时多等几次。
    init(
        session: URLSession = .shared, 每分钟请求上限: Int = 20, 最小间隔: TimeInterval = 0,
        限流重试次数: Int = 3, 限流等待秒数: Double = 5,
        开发者令牌: String? = nil, 打印失败: Bool = false, 允许替代版本: Bool = false
    ) {
        self.允许替代版本 = 允许替代版本
        self.session = session
        self.每分钟请求上限 = 每分钟请求上限
        self.最小间隔 = 最小间隔
        self.限流重试次数 = 限流重试次数
        self.限流等待秒数 = 限流等待秒数
        self.开发者令牌 = 开发者令牌
        self.打印失败 = 打印失败
    }

    /// - Parameters:
    ///   - 作品键: 缓存用，例如 MAL ID。
    ///   - 作品标题: 作品的日文、罗马字、英文标题，用来认出专辑名里的作品名。
    ///   - 已知: 预先匹配好的日本商店歌曲（主题曲映射），值为 nil 表示确认没有。这些歌曲不再检索。
    func 匹配(
        _ 歌曲: [动画主题曲], 作品键: String, 作品标题: [String], 已知: [Int: 候选?] = [:]
    ) async -> [Int: AppleMusic匹配结果] {
        // 映射里的结果变了（映射更新）时缓存作废
        let knownDigest = 已知.keys.sorted().map { "\($0):\(已知[$0]??.trackId ?? 0)" }.joined(separator: ",")
        let cacheKey = 作品键
        if let cached = 读取缓存(cacheKey), Set(cached.结果.keys) == Set(歌曲.map(\.id)), cached.已知 == knownDigest {
            return cached.结果
        }

        let failuresBefore = 请求失败次数
        var 结果: [Int: AppleMusic匹配结果] = [:]
        var 日本结果 = 已知.compactMapValues { $0 }
        let 未收录 = 歌曲.filter { 已知[$0.id] == nil }
        if !未收录.isEmpty {
            日本结果.merge(await 日本商店匹配(未收录, 作品标题: 作品标题)) { a, _ in a }
        }

        for song in 歌曲 {
            结果[song.id] = 日本结果[song.id].map { .已找到($0.歌曲()) } ?? .未找到
        }

        // 有请求失败（网络出错、限流、离开页面）时不缓存，免得把没检索到的歌曲记成“未找到”
        if !结果.isEmpty, 请求失败次数 == failuresBefore, !Task.isCancelled {
            存入缓存(cacheKey, 缓存文件(版本: Self.规则版本, 保存时间: .now, 已知: knownDigest, 结果: 结果))
        }
        return 结果
    }

    // MARK: 候选与打分

    nonisolated struct 候选: Sendable {
        let trackId: Int
        let artistId: Int?
        let 曲名: String
        let 歌手: String
        let 专辑: String
        let 发行日期: String
        let 可播放: Bool
        let 封面: URL?
        let 链接: URL?

        func 歌曲() -> AppleMusic歌曲 {
            AppleMusic歌曲(
                id: trackId, 标题: 曲名, 歌手: 歌手, 专辑: 专辑, 封面: 封面,
                链接: 链接 ?? URL(string: "https://music.apple.com/song/\(trackId)")!
            )
        }
    }

    nonisolated struct 评分: Sendable {
        let 歌名: Double
        let 歌手: Double
        let 总分: Double
        let 排除: Bool
        /// 专辑名里有作品名。
        var 专辑相符 = false
        /// Apple 按读音检索时排在前面。
        var 读音命中 = false

        /// 达到门槛：歌名、歌手都对得上；或者歌名完全一致、专辑名里有作品名时，歌手的罗马字写法差一些也接受
        /// （MAL 把佐伯ユウスケ写成“YouthK Saeki”）。
        var 可接受: Bool {
            !排除 && 歌名 >= 0.85 && (歌手 >= 0.72 || (歌名 >= 0.97 && 专辑相符 && 歌手 >= 0.5) || (读音命中 && 专辑相符))
        }

        /// 歌名、歌手都几乎一致。达到门槛但不到这一步的，生成映射时列到管理后台人工确认。
        var 几乎一致: Bool { 歌名 >= 0.97 && 歌手 >= 0.85 }

        /// 不需要人工确认。罗马字和日文比较时歌名分数上限是 0.95，歌手又一致时算确信。
        var 确信: Bool { 歌名 >= 0.95 && 歌手 >= 0.85 }
    }

    /// 歌曲 → 按读音检索时排在前面的曲目。
    private var 读音命中: [Int: Set<Int>] = [:]

    /// 歌名里的假名按顺序都出现在读音里（蒼空の炎 / そうくうのほのお），没有假名的歌名（汉字）不能用它排除。
    /// 片假名按平假名比较。全是假名时要和读音一样。
    private nonisolated static func 假名对得上(_ title: String, 读音 reading: String) -> Bool {
        let hiragana = (title.applyingTransform(.hiraganaToKatakana, reverse: true) ?? title)
        let kana = hiragana.filter { ("\u{3041}"..."\u{3096}").contains($0) }
        guard 主题曲文本.含日文(title) else { return false }
        let target = reading.filter { $0 != " " }
        var rest = Substring(target)
        for character in kana {
            guard let index = rest.firstIndex(of: character) else { return false }
            rest = rest[rest.index(after: index)...]
        }
        return true
    }

    /// 最后一轮没找到、但歌名对得上的歌曲和最好的候选。
    private var 建议结果: [Int: (候选, 评分)] = [:]

    /// 取走这段时间的建议，生成映射时用。
    func 取走建议() -> [Int: (候选, 评分)] {
        defer { 建议结果 = [:] }
        return 建议结果
    }

    /// 请求失败（网络出错、限流、取消）的累计次数。生成主题曲映射时用它判断结果能不能记下。
    private(set) var 请求失败次数 = 0

    private struct 检索进度 {
        var 候选: [Int: [Int: 候选]] = [:]
        var 已找到: [Int: 候选] = [:]
        var 未找到: [动画主题曲]
    }

    /// 分几轮检索，每轮只为还没找到的歌曲发请求：先只用歌名，再加上歌手，最后用罗马字在美国商店检索。
    /// 每轮检索完，歌名对得上的候选的歌手一起查一次罗马字名，再打分。歌名、歌手都几乎一致时就不再检索。
    /// `原名线索` 是其他来源（Bangumi）列出的这部作品的音乐名称：只用来检索，结果照样按歌名、歌手打分，
    /// 所以线索写错、和这首歌无关都不会配错。
    func 日本商店匹配(_ 歌曲: [动画主题曲], 作品标题: [String], 原名线索: () async -> [String] = { [] }) async -> [Int: 候选] {
        var progress = 检索进度(未找到: 歌曲)

        await 检索各首(&progress) { [($0.原标题 ?? $0.标题, "jp", 50)] }
        await 结算(&progress, 作品标题: 作品标题, 最后一轮: false)

        await 检索各首(&progress) { song in
            guard !song.歌手.isEmpty else { return [] }
            let title = song.原标题 ?? song.标题
            var terms = [("\(title) \(song.歌手原名 ?? song.歌手)", "jp", 25)]
            if song.歌手原名 != nil { terms.append(("\(title) \(song.歌手)", "jp", 25)) }
            return terms
        }
        await 结算(&progress, 作品标题: 作品标题, 最后一轮: false)

        // 只有罗马字的歌名（“Shiroi Yuki”）在日本商店检索不到：先用罗马字找到歌手，再用歌手的日文名检索，
        // 把歌名的读音（白い雪 → shiroi yuki）和 MAL 的罗马字比较。只在生成映射时做（请求较多）
        if 开发者令牌 != nil {
            var names: [Int: [String]] = [:]
            for song in progress.未找到 where !song.歌手.isEmpty {
                names[song.id] = await 日文歌手名(song.歌手原名 == nil ? song.歌手 : nil)
            }
            await 检索各首(&progress) { song in (names[song.id] ?? []).prefix(2).map { ($0, "jp", 100) } }
            await 结算(&progress, 作品标题: 作品标题, 最后一轮: false)
        }

        // 只有罗马字的歌名：转成假名按读音检索。太长时只用前面一段，日本商店整句对不上时检索不到
        if 开发者令牌 != nil {
            for song in progress.未找到 where song.原标题 == nil {
                guard let reading = 主题曲文本.平假名读音(song.标题) else { continue }
                let words = reading.split(separator: " ").map(String.init)
                var terms = [reading]
                if words.joined().count > 12 { terms.append(words.prefix(3).joined()) }
                for (index, term) in terms.enumerated() {
                    let items = await 检索(term, 地区: "jp", 数量: 25)
                    for (rank, item) in items.enumerated() {
                        if progress.候选[song.id, default: [:]][item.trackId] == nil { progress.候选[song.id, default: [:]][item.trackId] = item }
                        // Apple 按读音排在前面、歌名里的假名也对得上：很多歌没有罗马字名，这是能确认读音的唯一依据
                        if index == 0, rank < 5, Self.假名对得上(item.曲名, 读音: reading) { 读音命中[song.id, default: []].insert(item.trackId) }
                    }
                }
            }
            await 结算(&progress, 作品标题: 作品标题, 最后一轮: false)
        }

        // 只有罗马字时日本商店检索不到：用线索里的日文名检索，每个名称只查一次，结果给所有还没找到的歌曲比较读音
        if progress.未找到.contains(where: { $0.原标题 == nil }) {
            for term in await 原名线索() {
                let items = await 检索(term, 地区: "jp", 数量: 25)
                for song in progress.未找到 {
                    for item in items where progress.候选[song.id, default: [:]][item.trackId] == nil {
                        progress.候选[song.id, default: [:]][item.trackId] = item
                    }
                }
            }
            await 结算(&progress, 作品标题: 作品标题, 最后一轮: false)
        }

        // 中国动画的歌（歌名是汉字、没有假名）常常只在中国内地、台湾的商店里，日本商店检索不到
        if 开发者令牌 != nil {
            await 检索各首(&progress) { song in
                guard let title = song.原标题, 主题曲文本.只有汉字(title) else { return [] }
                let term = "\(title) \(song.歌手原名 ?? "")".trimmingCharacters(in: .whitespaces)
                return [(term, "cn", 25), (term, "tw", 25)]
            }
            await 结算(&progress, 作品标题: 作品标题, 最后一轮: false)
        }

        // 只有罗马字标题时，用 Apple 的罗马字曲名再比较（例如“Skyclad No Kansokusha”）；Apple Music API 在结算时已经补上
        if 开发者令牌 == nil {
            let romanizable = progress.未找到.filter { $0.原标题 == nil }.flatMap { song in
                (progress.候选[song.id] ?? [:]).values.filter { 歌手分数($0, song: song) >= 0.72 }.map(\.trackId)
            }
            await 补充罗马字曲名(romanizable)
        }
        // 用罗马字检索（美国商店，或 Apple Music API 的英文名称），和 MAL 的写法最接近
        await 检索各首(&progress) { song in song.歌手.isEmpty ? [] : [("\(song.标题) \(song.歌手)", Self.罗马字地区, 25)] }
        // 美国商店检索到的曲目可能日本商店没有，选中后才发现就白白丢了这首歌，先去掉
        let foreign = Set(progress.未找到.flatMap { (progress.候选[$0.id] ?? [:]).keys }).intersection(罗马字候选)
        if !foreign.isEmpty, let available = try? await 查询曲目(Array(foreign), 地区: "jp") {
            for song in progress.未找到 {
                for id in foreign where available[id] == nil { progress.候选[song.id]?[id] = nil }
            }
        }
        await 结算(&progress, 作品标题: 作品标题, 最后一轮: true)
        return await 换成原语言名称(progress.已找到)
    }

    private var 日文歌手名缓存: [String: [String]] = [:]

    /// 匹配时查到过的日文歌手名（写进未匹配清单，后台人工匹配时用来检索）。
    func 查过的日文歌手名(_ romaji: String) -> String? {
        日文歌手名缓存[romaji]?.first
    }

    /// 罗马字的歌手名在美国商店里对应的歌手，在日本商店的名称（例如 Mai Kuraki → 倉木麻衣）。
    private func 日文歌手名(_ romaji: String?) async -> [String] {
        guard let romaji, !romaji.isEmpty else { return [] }
        if let cached = 日文歌手名缓存[romaji] { return cached }
        var result: [String] = []
        // 美国商店的歌手检索不容错：MAL 的“Kumiko Oosugi”要写成 Apple 的“Kumiko Osugi”才找得到，依次试长音和姓名顺序的几种写法
        for term in Self.罗马字写法(romaji) where result.isEmpty {
            var components = URLComponents(string: "https://api.music.apple.com/v1/catalog/us/search")!
            components.queryItems = [
                URLQueryItem(name: "term", value: term), URLQueryItem(name: "types", value: "artists"), URLQueryItem(name: "limit", value: "5"),
            ]
            guard let url = components.url, let data = await 请求(url),
                  let decoded = try? JSONDecoder().decode(AppleMusic结果.self, from: data) else { continue }
            let ids = (decoded.results?.artists?.data ?? []).filter { artist in
                Self.名字相似度(romaji, artist.attributes?.name ?? "") >= 0.85
            }.map(\.id)
            if !ids.isEmpty,
               let data = await 请求(URL(string: "https://api.music.apple.com/v1/catalog/jp/artists?ids=\(ids.joined(separator: ","))")!),
               let artists = try? JSONDecoder().decode(AppleMusic结果.self, from: data) {
                result = artists.data.compactMap { $0.attributes?.name }.filter { !$0.isEmpty }
            }
        }
        日文歌手名缓存[romaji] = result
        return result
    }

    /// 罗马字名字的几种写法：原样、长音缩写（Oosugi → Osugi、Itou → Ito）、姓名顺序颠倒。
    private nonisolated static func 罗马字写法(_ name: String) -> [String] {
        let shortened = name
            .replacingOccurrences(of: "(?i)oo", with: "o", options: .regularExpression)
            .replacingOccurrences(of: "(?i)ou(?=[^aeiou]|$)", with: "o", options: .regularExpression)
            .replacingOccurrences(of: "(?i)uu", with: "u", options: .regularExpression)
        var variants: [String] = []
        for value in [name, shortened] {
            let words = value.split(separator: " ")
            variants.append(value)
            if words.count == 2 { variants.append("\(words[1]) \(words[0])") }
        }
        var seen = Set<String>()
        return variants.filter { seen.insert($0.lowercased()).inserted }
    }

    /// 检索时用这个“地区”表示用罗马字检索。
    private static let 罗马字地区 = "romaji"

    /// 用罗马字检索到的结果名称是罗马字，到日本商店取回原语言的名称；日本商店里没有的不要。
    private func 换成原语言名称(_ found: [Int: 候选]) async -> [Int: 候选] {
        let romanized = found.values.map(\.trackId).filter(罗马字候选.contains)
        guard !romanized.isEmpty else { return found }
        let japanese = (try? await 查询曲目(romanized, 地区: "jp")) ?? [:]
        return found.compactMapValues { item in
            罗马字候选.contains(item.trackId) ? japanese[item.trackId] : item
        }
    }

    private func 检索各首(_ progress: inout 检索进度, _ query: (动画主题曲) -> [(String, String, Int)]) async {
        let jobs = progress.未找到.flatMap { song in query(song).map { (song.id, $0.0, $0.1, $0.2) } }
        var results: [(Int, String, [候选])] = []
        await withTaskGroup(of: (Int, String, [候选]).self) { group in
            for (id, term, store, limit) in jobs {
                group.addTask { (id, store, await self.检索(term, 地区: store, 数量: limit)) }
            }
            for await result in group { results.append(result) }
        }
        for (id, store, items) in results {
            for item in items where progress.候选[id, default: [:]][item.trackId] == nil {
                progress.候选[id, default: [:]][item.trackId] = item
                // 罗马字检索的歌名、歌手是 Apple 的罗马字写法
                if store == Self.罗马字地区 {
                    罗马字候选.insert(item.trackId)
                    罗马字曲名[item.trackId] = item.曲名
                    if let artistId = item.artistId { 罗马字歌手名[artistId] = item.歌手 }
                }
            }
        }
    }

    /// 打分前补上歌名对得上的候选的罗马字歌手名，再记下几乎一致的结果；最后一轮记下所有达到门槛的结果。
    private func 结算(_ progress: inout 检索进度, 作品标题: [String], 最后一轮: Bool) async {
        if 开发者令牌 != nil {
            // Apple Music API 按曲目一次查出罗马字的歌名、歌手和歌手编号
            await 补充罗马字名称(progress.未找到.flatMap { (progress.候选[$0.id] ?? [:]).keys })
        } else {
            let artistIds = progress.未找到.flatMap { song in
                (progress.候选[song.id] ?? [:]).values.filter { 歌名分数($0, song: song) >= 0.85 }.compactMap(\.artistId)
            }
            await 补充罗马字歌手名(artistIds)
        }
        var remaining: [动画主题曲] = []
        for song in progress.未找到 {
            let best = 优先完整版((progress.候选[song.id] ?? [:]).values
                .map { ($0, 打分($0, song: song, 作品标题: 作品标题)) }
                .filter { $0.1.可接受 })
            // 暂时只找到短版本时继续检索，后面几轮可能找到完整版
            if let (item, score) = best, 最后一轮 || (score.几乎一致 && !Self.是短版本(item.曲名)) {
                progress.已找到[song.id] = item
            } else if !最后一轮 {
                remaining.append(song)
            } else if 开发者令牌 != nil {
                // 歌名对得上、歌手对不上（MAL 写了别名或罗马字读音不同）：不算找到，生成映射时列到后台建议人工确认
                建议结果[song.id] = 优先完整版((progress.候选[song.id] ?? [:]).values
                    .map { ($0, 打分($0, song: song, 作品标题: 作品标题)) }
                    .filter { !$0.1.排除 && ($0.1.歌名 >= 0.95 || $0.1.读音命中) })
            }
        }
        progress.未找到 = remaining
    }

    /// 选分数最高的候选；选中短版本时，歌名、歌手同样对得上的完整版优先，没有完整版才用短版本。
    private nonisolated func 优先完整版(_ candidates: [(候选, 评分)]) -> (候选, 评分)? {
        guard let best = candidates.max(by: { 更好($1, than: $0) }) else { return nil }
        guard Self.是短版本(best.0.曲名) else { return best }
        return candidates
            .filter { Self.是完整版($0.0.曲名, 短版本: best.0.曲名) && $0.1.歌名 >= best.1.歌名 - 0.02 && $0.1.歌手 >= best.1.歌手 - 0.02 }
            .max { 更好($1, than: $0) } ?? best
    }

    /// 去掉括号和尺寸说明后和短版本同名，本身又不带其他版本说明（feat. 除外）：
    /// “departure! second version (TVサイズ)”的完整版不是“departure! (VS Edition)”，“ブックマーク ア・ヘッド (ショートサイズ)”的不是“(Type-11)”。
    nonisolated static func 是完整版(_ title: String, 短版本 short: String) -> Bool {
        func key(_ text: String) -> String {
            String(text.precomposedStringWithCompatibilityMapping.lowercased().filter { $0.isLetter || $0.isNumber })
        }
        let bracket = #"[\(\[（【〔][^\)\]）】〕]*[\)\]）】〕]"#
        let marker = #"[\s_~-]*(?<![a-z])(?:t\.?v\.?|anime|game|movie|ova|short)[\s_-]*(?:size|ver(?![a-z])\.?|version|edit)(?![a-z])\.?[\s_~-]*"#
        let shortBase = short.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: bracket, with: "", options: .regularExpression)
            .replacingOccurrences(of: marker, with: "", options: [.regularExpression, .caseInsensitive])
        let full = title.precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: #"\s*[\(\[（【〔]\s*(?:feat|ft)\b[^\)\]）】〕]*[\)\]）】〕]"#, with: "", options: [.regularExpression, .caseInsensitive])
        guard !是短版本(title), !key(shortBase).isEmpty else { return false }
        return key(full) == key(shortBase)
    }

    /// 两边列的是同一组歌手：顺序、空格、“&”和逗号的写法可以不同，多一位少一位都算不同的演唱组合。
    nonisolated static func 是同歌手(_ a: String, _ b: String) -> Bool {
        func names(_ text: String) -> Set<String> {
            Set(text.precomposedStringWithCompatibilityMapping.lowercased()
                .components(separatedBy: CharacterSet(charactersIn: ",、&/×"))
                .map { String($0.filter { $0.isLetter || $0.isNumber }) }.filter { !$0.isEmpty })
        }
        return names(a) == names(b)
    }

    /// “TV Size”“Game Version”“アニメサイズ”“Movie edit”“Short Ver.”这类为动画、游戏剪短的版本。
    nonisolated static func 是短版本(_ title: String) -> Bool {
        let text = title.precomposedStringWithCompatibilityMapping
        let patterns = [
            #"(?<![a-z])(?:t\.?v\.?|anime|game|movie|ova|op|ed|short)[\s_-]*(?:size|ver(?![a-z])|version|edit)(?![a-z])"#,
            #"(?<![a-z])short(?:\s+radio)?\s+edit(?![a-z])|(?<![a-z])radio\s+edit(?![a-z])|(?<![a-z])edit\s+ver(?![a-z])"#,
            #"[\(\[（【-]\s*short\s*[\)\]）】-]|[\(\[（【-][^\)\]）】]*(?<![a-z])size(?![a-z])"#,
            #"(?:テレビ|アニメ|ゲーム|ショート|ムービー|tv|movie|ova|game)\s*(?:サイズ|バージョン|ヴァージョン)|サイズ\s*[\)\]）】]"#,
        ]
        return patterns.contains { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    /// 分数接近（0.02 以内）时选发行早的：原版单曲通常比合辑、精选集早。
    private nonisolated func 更好(_ a: (候选, 评分), than b: (候选, 评分)) -> Bool {
        if abs(a.1.总分 - b.1.总分) > 0.02 { return a.1.总分 > b.1.总分 }
        if a.0.发行日期 != b.0.发行日期, !a.0.发行日期.isEmpty, !b.0.发行日期.isEmpty { return a.0.发行日期 < b.0.发行日期 }
        return a.1.总分 > b.1.总分
    }

    func 打分(_ item: 候选, song: 动画主题曲, 作品标题: [String]) -> 评分 {
        // 读音命中算 0.9：够得上门槛，但不算“确信”，会列到后台待确认
        let hit = 读音命中[song.id]?.contains(item.trackId) == true
        let titleScore = max(歌名分数(item, song: song), hit ? 0.9 : 0)
        let artistScore = 歌手分数(item, song: song)
        let version = 版本(item, song: song, 作品标题: 作品标题, 歌手分数: artistScore)
        var total = titleScore * 0.55 + artistScore * 0.35 - version.扣分
        // MAL 分开列出同一首歌的几个版本（“Fly Me to the Moon (Yoko Takahashi Version)”和“(… Acid Bossa Version)”）：
        // 去掉版本说明后歌名一样，再按包括版本说明的完整歌名细分
        total += 0.05 * 完整歌名相似度(item, song: song)
        // 专辑名里有作品名只在歌手对不上时帮忙区分；歌手一致时不加分，否则角色歌专辑、精选集会盖过原版单曲
        let albumMatches = 专辑含作品名(item.专辑, 作品标题: 作品标题)
        if artistScore < 0.85, albumMatches { total += 0.08 }
        if !item.可播放 { total -= 0.3 }
        return 评分(歌名: titleScore, 歌手: artistScore, 总分: total, 排除: version.排除, 专辑相符: albumMatches, 读音命中: hit)
    }

    private func 歌名分数(_ item: 候选, song: 动画主题曲) -> Double {
        // 破折号里的版本说明，Apple 常写在歌名里不加括号：“departure! second version”
        let withVersion = song.版本说明.map { "\(song.标题) \($0)" }
        let mine = [song.原标题, song.标题, withVersion].compactMap { $0 }.flatMap(Self.歌名写法)
        var theirs = Self.歌名写法(item.曲名)
        if let romanized = 罗马字曲名[item.trackId] { theirs += Self.歌名写法(romanized) }
        var best = 0.0
        for a in mine {
            for b in theirs {
                if 主题曲文本.含日文(a), 主题曲文本.含日文(b) {
                    // 都是日文时只按日文比较：转成罗马字后长音会被抹平，“リフレーン”和“リフレイン”会变得一样
                    best = max(best, 主题曲文本.相似度(主题曲文本.日文键(a), 主题曲文本.日文键(b)))
                    continue
                }
                let x = 主题曲文本.罗马字键(a), y = 主题曲文本.罗马字键(b)
                // 转写的读音不一定对（晴る→hareru），只在双方都不是靠转写得到时给满分
                let transliterated = 主题曲文本.含日文(a) != 主题曲文本.含日文(b)
                best = max(best, 主题曲文本.相似度(x, y) * (transliterated ? 0.95 : 1))
            }
        }
        return best
    }

    /// 显示用的歌名：去掉“ - TV Size”和括号里的版本说明，保留原语言的写法。
    nonisolated static func 显示歌名(_ title: String) -> String {
        let cleaned = 去掉版本说明(title)
        return cleaned.isEmpty ? title : cleaned
    }

    private nonisolated static func 去掉版本说明(_ title: String) -> String {
        var base = title
        if let dash = base.range(of: " - ", options: .backwards),
           base[dash.upperBound...].range(of: #"(?i)size|ver|version|from|edit|mix|サイズ|remaster"#, options: .regularExpression) != nil {
            base = String(base[..<dash.lowerBound])
        }
        return base.replacingOccurrences(
            of: #"\s*[\(\[（【〔][^\)\]）】〕]*(?:ver|version|size|サイズ|edit|tv|anime|アニメ|short|remaster)[^\)\]）】〕]*[\)\]）】〕]"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespaces)
    }

    private func 完整歌名相似度(_ item: 候选, song: 动画主题曲) -> Double {
        var theirs = [item.曲名]
        if let romanized = 罗马字曲名[item.trackId], !romanized.isEmpty { theirs.append(romanized) }
        var best = 0.0
        for a in [song.原标题, song.标题].compactMap({ $0 }) {
            for b in theirs where 主题曲文本.含日文(a) == 主题曲文本.含日文(b) {
                best = max(best, 主题曲文本.相似度(主题曲文本.罗马字键(a), 主题曲文本.罗马字键(b)))
            }
        }
        return best
    }

    /// 去掉版本说明后的歌名，以及去掉所有括号的歌名。
    private nonisolated static func 歌名写法(_ title: String) -> [String] {
        var base = title
        // “紅蓮華 - From THE FIRST TAKE”“Lemon - TV Size”
        if let dash = base.range(of: " - ", options: .backwards) { base = String(base[..<dash.lowerBound]) }
        let stripped = base.replacingOccurrences(of: #"\s*[\(\[（【〔][^\)\]）】〕]*[\)\]）】〕]"#, with: "", options: .regularExpression)
        // 没有括号的客串歌手：“君ノカケラ feat 宮本笑里”
        let withoutFeat = base.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|ft\.|featuring)\s.*$"#, with: "", options: .regularExpression)
        let cleaned = base.replacingOccurrences(
            of: #"\s*[\(\[（【〔][^\)\]）】〕]*(?:ver|version|size|サイズ|feat|ft\.|from|edit|mix|inst|vocal|karaoke|カラオケ|tv|anime|アニメ|op|ed|オープニング|エンディング|主題歌|テーマ|theme|short|full|remaster)[^\)\]）】〕]*[\)\]）】〕]"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        return Array(Set([title, base, cleaned, stripped, withoutFeat].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }))
    }

    func 歌手分数(_ item: 候选, song: 动画主题曲) -> Double {
        let mine = Self.歌手名字(song.歌手) + (song.歌手原名.map(Self.歌手名字) ?? []) + song.歌手别名
        var theirs = Self.歌手名字(item.歌手)
        for artistId in item.artistId.map({ [$0] }) ?? 曲目歌手[item.trackId] ?? [] {
            if let romanized = 罗马字歌手名[artistId] { theirs += Self.歌手名字(romanized) }
        }
        // “永久のキズナ feat. Another Infinity”：客串歌手有时写在歌名里
        for title in [item.曲名, 罗马字曲名[item.trackId] ?? ""] {
            if let feat = title.range(of: #"(?i)\b(?:feat\.?|ft\.|featuring|starring)\s*"#, options: .regularExpression) {
                theirs += Self.歌手名字(String(title[feat.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " )]）】")))
            }
        }
        guard !mine.isEmpty else { return 0 }
        var best = 0.0
        for a in mine {
            for b in theirs { best = max(best, Self.名字相似度(a, b)) }
        }
        // 团体名对不上、只靠括号里的成员名单对上时（“Project Yamato 2199 (Eir Aoi, …, Isao Sasaki, …)”
        // 配到“ささきいさお & ロイヤル・ナイツ”的旧版）：Apple 列出的每一位歌手都要在成员名单里
        if song.歌手别名.count >= 3 {
            let main = Self.歌手名字(song.歌手) + (song.歌手原名.map(Self.歌手名字) ?? [])
            let mainBest = main.flatMap { a in theirs.map { Self.名字相似度(a, $0) } }.max() ?? 0
            let performers = Self.个人歌手(item.歌手).isEmpty ? [item.歌手] : Self.个人歌手(item.歌手)
            let allListed = performers.allSatisfy { name in song.歌手别名.contains { Self.名字相似度($0, name) >= 0.8 } }
            if mainBest < 0.85, !allListed { best = min(best, 0.7) }
        }
        // 双方都列出几位歌手时，MAL 列的每一位都要对上：角色歌常有同一首歌的不同演唱组合，只对上一位会配错版本
        let listed = Self.个人歌手(song.歌手)
        if listed.count >= 2, Self.个人歌手(item.歌手).count >= 2 {
            let covered = listed.allSatisfy { name in theirs.contains { Self.名字相似度(name, $0) >= 0.8 } }
            if !covered { best = min(best, 0.7) }
        }
        return best
    }

    /// 拆开后的各位歌手（不含整体写法），用来判断是不是同一组演唱者。
    private nonisolated static func 个人歌手(_ text: String) -> [String] {
        Array(Set(歌手名字(text).filter { $0 != text && 主题曲文本.罗马字键($0).count >= 2 }))
    }

    /// 整体与拆开后的每个名字：“ALI ft. AKLO”“Roselia & ITO KANAKO”“ファンタズム(FES cv.榊原ゆい)”。
    private nonisolated static func 歌手名字(_ text: String) -> [String] {
        let separators = #"\s+(?:ft\.?|feat\.?|featuring|with|and|x|×|&|vs\.?)\s+|[,，、/／&＆×・\[\]［］\(\)（）]|\s(?:cv|CV|Cv)[.:：]?\s*|(?:cv|CV)[.:：]"#
        let parts = text.replacingOccurrences(of: separators, with: "\u{1F}", options: .regularExpression)
            .components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return Array(Set([text] + parts))
    }

    /// 名字比较：日文直接比较；罗马字不分姓名顺序。较长的一方包含较短的一方（按词，或 6 个字母以上）时也算对上。
    nonisolated static func 名字相似度(_ a: String, _ b: String) -> Double {
        var best = 0.0
        if 主题曲文本.含日文(a), 主题曲文本.含日文(b) {
            let x = 主题曲文本.日文键(a), y = 主题曲文本.日文键(b)
            best = max(best, 主题曲文本.相似度(x, y))
            let (short, long) = x.count <= y.count ? (x, y) : (y, x)
            if short.count >= 2, long.contains(short) { best = max(best, 0.92) }
        }
        let wa = 主题曲文本.罗马字词(a), wb = 主题曲文本.罗马字词(b)
        guard !wa.isEmpty, !wb.isEmpty else { return best }
        let ka = wa.joined(), kb = wb.joined(), kaReversed = wa.reversed().joined()
        // 1–2 个字母的名字只接受完全相同
        if min(ka.count, kb.count) <= 2 { return max(best, ka == kb ? 1 : 0) }
        let transliterated = 主题曲文本.含日文(a) != 主题曲文本.含日文(b)
        let factor = transliterated ? 0.97 : 1
        best = max(best, 主题曲文本.相似度(ka, kb) * factor, 主题曲文本.相似度(kaReversed, kb) * factor)
        for words in [wa, Array(wa.reversed())] {
            let (short, long) = words.count <= wb.count ? (words, wb) : (wb, words)
            let shortKey = short.joined(), longKey = long.joined()
            if 包含连续词(long, short) || (shortKey.count >= 6 && longKey.contains(shortKey)) {
                best = max(best, 0.9)
            }
        }
        return best
    }

    private nonisolated static func 包含连续词(_ long: [String], _ short: [String]) -> Bool {
        guard !short.isEmpty, short.count <= long.count, short.joined().count >= 3 else { return false }
        for start in 0...(long.count - short.count) where Array(long[start..<start + short.count]) == short {
            return true
        }
        return false
    }

    /// 伴奏、翻唱、八音盒等直接排除；TV 尺寸、现场、混音等扣分（MAL 标题本身带这些词时不算）。
    private func 版本(_ item: 候选, song: 动画主题曲, 作品标题: [String] = [], 歌手分数 knownArtistScore: Double? = nil) -> (排除: Bool, 扣分: Double) {
        // 先去掉作品名：“プリティーリズム・レインボーライブ”“ラブライブ!”里的“ライブ”不是现场版
        func 去掉作品名(_ text: String) -> String {
            var value = text.precomposedStringWithCompatibilityMapping.lowercased()
            for title in 作品标题 where title.count >= 2 {
                value = value.replacingOccurrences(of: title.precomposedStringWithCompatibilityMapping.lowercased(), with: " ")
            }
            return value
        }
        let name = 去掉作品名(item.曲名)
        let album = 去掉作品名(item.专辑)
        let original = "\(song.标题) \(song.原标题 ?? "") \(song.版本说明 ?? "")".lowercased()
        func has(_ keywords: [String], in text: String) -> Bool {
            keywords.contains { text.contains($0) && !original.contains($0) }
        }
        /// 拉丁字母的关键词按整词找（“live”不能匹配“Alive”）。
        func hasWord(_ words: [String], in text: String) -> Bool {
            words.contains { word in
                text.range(of: "(?<![a-z])\(NSRegularExpression.escapedPattern(for: word))(?![a-z])", options: .regularExpression) != nil
                    && original.range(of: "(?<![a-z])\(NSRegularExpression.escapedPattern(for: word))(?![a-z])", options: .regularExpression) == nil
            }
        }
        let excluded = ["instrumental", "inst.", "(inst", "inst)", "off vocal", "off-vocal", "offvocal", "karaoke", "カラオケ",
                        "backing track", "without vocal", "less vocal", "vocal less", "no vocal", "ボーカルなし", "インスト",
                        "cover", "カバー", "covered by", "オルゴール", "music box", "8bit", "8-bit", "english ver",
                        "english version", "eng ver", "lofi", "lo-fi", "nightcore", "piano ver", "ピアノ", "acoustic ver",
                        // 中文的伴奏、纯音乐、改编版本、现场、翻唱
                        "伴奏", "纯音乐", "純音樂", "钢琴", "鋼琴", "吉他版", "轻松版", "輕鬆版", "抒情版", "现场", "現場", "翻唱", "dj版",
                        "小提琴", "大提琴", "二胡", "古筝", "古箏", "笛子", "弦乐", "弦樂", "交响", "交響", "八音盒"]
        if has(excluded, in: name) { return (true, 0) }
        // 伴奏、现场、混音是另一段录音，不能算作主题曲（MAL 标题本身带这些词时除外）
        /// 另一段录音的同一首歌（现场、重录、改编）：通常排除，统计放宽效果时降分保留。
        let 替代版本: (排除: Bool, 扣分: Double) = 允许替代版本 ? (false, 0.3) : (true, 0)
        if hasWord(["inst"], in: name) { return (true, 0) }
        if hasWord(["remix", "rmx", "live"], in: name) || has(["ライブ", "ライヴ", "リミックス"], in: name) { return 替代版本 }
        if hasWord(["live", "concert"], in: album) || has(["ライブ", "ライヴ", "コンサート"], in: album) { return 替代版本 }
        // MAL 指定了版本（“Acoustic Ver.”）时，候选的歌名里要有这个版本的关键词
        // MAL 写“TV Size”时仍然要完整版，不要求候选带这个说明
        if let wanted = song.版本说明, !Self.是短版本(wanted) {
            let generic = Set(["ver", "version", "edit", "the", "of", "a"].map(主题曲文本.罗马字规范))
            let keywords = 主题曲文本.罗马字词(wanted).filter { $0.count >= 2 && !generic.contains($0) }
            let words = Set(主题曲文本.罗马字词(item.曲名) + 主题曲文本.罗马字词(罗马字曲名[item.trackId] ?? ""))
            if !keywords.isEmpty, !keywords.contains(where: words.contains) { return 替代版本 }
        }
        // 重录、自翻唱不是动画里的那段录音：“2005 ver.”“2009VERSION”“2205 OP Ver.”“第5期 ver.”“セルフカバー”
        if name.range(of: #"(?:19|2\d)\d\d[^)\]）】]{0,12}?(?:ver|version|ヴァージョン|バージョン)|第\d+期"#, options: .regularExpression) != nil,
           original.range(of: #"(?:19|2\d)\d\d|第\d+期"#, options: .regularExpression) == nil {
            return 替代版本
        }
        if has(["self cover", "self-cover", "セルフカバー", "re-recording", "re-recorded", "新録", "再録"], in: name) { return 替代版本 }
        // 编曲不同的版本（“Acid Bossa Version”“Jungle Version”）：MAL 没写这种编曲时不算
        if hasWord(["acid", "bossa", "jungle", "techno", "jazz", "swing", "eurobeat", "trance", "house", "dance mix", "club mix",
                    "reggae", "hip hop", "r&b", "4 beat", "lo-fi", "chill", "bossa nova", "samba"], in: name) { return 替代版本 }
        // 吹奏乐团、管弦乐团的翻奏（MAL 列的本来就是乐团时除外）
        let artist = item.歌手.precomposedStringWithCompatibilityMapping.lowercased()
        let originalArtist = "\(song.歌手) \(song.歌手原名 ?? "") \(song.歌手别名.joined(separator: " ")) \(song.版本说明 ?? "")".lowercased()
        let ensembles = ["orchestra", "オーケストラ", "吹奏楽", "ブラスバンド", "philharmonic", "フィルハーモニー", "wind ensemble"]
        if ensembles.contains(where: artist.contains), !ensembles.contains(where: originalArtist.contains) { return (true, 0) }
        if has(["ブラバン", "brass band", "吹奏楽"], in: name + " " + album) { return (true, 0) }
        // 卡拉OK、八音盒、翻唱合集：歌手对不上时才排除（角色翻唱的“Cover song collection”、
        // “エンディングテーマ集 ～ある日のカラオケボックス～”里是 MAL 列的歌手本人）
        if (knownArtistScore ?? 歌手分数(item, song: song)) < 0.85,
           has(["karaoke", "カラオケ", "オルゴール", "music box", "8bit", "cover", "カバー", "lofi", "piano"], in: album) {
            return (true, 0)
        }
        var penalty = 0.0
        if has(["mix", "rmx", "dub", "symphonic", "orchestra", "オーケストラ", "acoustic", "アコースティック",
                "unplugged", "arrange", "アレンジ", "self cover", "セルフカバー", "re-recording", "rearrange", "-ballade", "ballad ver"], in: name) {
            penalty += 0.2
        }
        if has(["the first take"], in: name) { penalty += 0.12 }
        // 重制版音质没问题，但同一首有原版时选原版
        if has(["remaster", "リマスター"], in: name) { penalty += 0.03 }
        if has(["tv size", "tvsize", "tvサイズ", "tv ver", "tv-size", "tv edit", "tv version", "short ver", "short version", "anime size",
                "アニメサイズ", "anime ver", "op ver", "ed ver", "size)", "サイズ)", "movie ver", "game ver"], in: name) {
            penalty += 0.06
        } else if has(["ver.", "version", "ver)", "バージョン", "ヴァージョン", "版)", "版]", "版）", "版】"], in: name) {
            penalty += 0.08
        }
        return (false, penalty)
    }

    private nonisolated func 专辑含作品名(_ album: String, 作品标题: [String]) -> Bool {
        let japaneseAlbum = 主题曲文本.日文键(album)
        let latinAlbum = 主题曲文本.罗马字词(album).joined()
        return 作品标题.contains { title in
            if 主题曲文本.含日文(title) {
                let key = 主题曲文本.日文键(title)
                return key.count >= 2 && japaneseAlbum.contains(key)
            }
            let key = 主题曲文本.罗马字词(title).joined()
            return key.count >= 5 && latinAlbum.contains(key)
        }
    }

    // MARK: iTunes 接口

    private nonisolated struct iTunes结果: Decodable {
        struct 项目: Decodable {
            let wrapperType: String?
            let kind: String?
            let trackId: Int?
            let artistId: Int?
            let trackName: String?
            let artistName: String?
            let collectionName: String?
            let releaseDate: String?
            let isStreamable: Bool?
            let artworkUrl100: String?
            let trackViewUrl: String?
        }
        let results: [项目]
    }

    private func 检索(_ term: String, 地区: String, 数量: Int) async -> [候选] {
        if 开发者令牌 != nil {
            // Apple Music API 每页最多 25 首。罗马字检索用美国商店：日本商店的检索不认罗马字（加 l=en-US 也一样），
            // 美国商店的名称本身就是 Apple 的罗马字写法，曲目编号各商店通用，选中后再换回日本商店的名称
            let romaji = 地区 == Self.罗马字地区
            var items: [候选] = []
            for offset in stride(from: 0, to: 数量, by: 25) {
                var components = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(romaji ? "us" : 地区)/search")!
                components.queryItems = [
                    URLQueryItem(name: "term", value: term),
                    URLQueryItem(name: "types", value: "songs"),
                    URLQueryItem(name: "limit", value: String(min(25, 数量 - offset))),
                    URLQueryItem(name: "offset", value: String(offset)),
                ]
                guard let url = components.url, let data = await 请求(url) else { break }
                let page = Self.解析AppleMusic(data, 检索结果: true)
                items += page
                if page.count < 25 { break }
            }
            return items
        }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "country", value: 地区 == Self.罗马字地区 ? "us" : 地区),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(数量)),
        ]
        guard let url = components.url, let data = await 请求(url) else { return [] }
        return Self.解析(data)
    }

    func 查询曲目(_ ids: [Int], 地区: String) async throws -> [Int: 候选] {
        var found: [Int: 候选] = [:]
        if 开发者令牌 != nil {
            for chunk in stride(from: 0, to: ids.count, by: 300).map({ Array(ids[$0..<min($0 + 300, ids.count)]) }) where !chunk.isEmpty {
                // 带上歌手关系：检索结果没有歌手编号
                let url = URL(string: "https://api.music.apple.com/v1/catalog/\(地区)/songs?ids=\(chunk.map(String.init).joined(separator: ","))&include=artists")!
                guard let data = await 请求(url) else { continue }
                for item in Self.解析AppleMusic(data, 检索结果: false) { found[item.trackId] = item }
            }
            return found
        }
        for chunk in stride(from: 0, to: ids.count, by: 50).map({ Array(ids[$0..<min($0 + 50, ids.count)]) }) where !chunk.isEmpty {
            let url = URL(string: "https://itunes.apple.com/lookup?id=\(chunk.map(String.init).joined(separator: ","))&country=\(地区)&entity=song")!
            guard let data = await 请求(url) else { continue }
            for item in Self.解析(data) { found[item.trackId] = item }
        }
        return found
    }

    private func 补充罗马字歌手名(_ ids: [Int]) async {
        let missing = Array(Set(ids).subtracting(罗马字歌手名.keys))
        guard !missing.isEmpty else { return }
        for chunk in stride(from: 0, to: missing.count, by: 50).map({ Array(missing[$0..<min($0 + 50, missing.count)]) }) {
            let url = URL(string: "https://itunes.apple.com/lookup?id=\(chunk.map(String.init).joined(separator: ","))&country=us")!
            guard let data = await 请求(url),
                  let decoded = try? JSONDecoder().decode(iTunes结果.self, from: data) else { continue }
            for id in chunk { 罗马字歌手名[id] = "" }
            for item in decoded.results where item.wrapperType == "artist" {
                if let id = item.artistId, let name = item.artistName { 罗马字歌手名[id] = name }
            }
        }
    }

    private func 补充罗马字曲名(_ ids: [Int]) async {
        let missing = Array(Set(ids).subtracting(罗马字曲名.keys).prefix(50))
        guard !missing.isEmpty, let found = try? await 查询曲目(missing, 地区: "us") else { return }
        for id in missing { 罗马字曲名[id] = found[id]?.曲名 ?? "" }
        for item in found.values {
            if let artistId = item.artistId, 罗马字歌手名[artistId]?.isEmpty != false { 罗马字歌手名[artistId] = item.歌手 }
        }
    }

    /// Apple Music API：按曲目查询日本商店的英文名称（Apple 的罗马字写法）和歌手。
    func 补充罗马字名称(_ trackIds: [Int]) async {
        let missing = Array(Set(trackIds).subtracting(罗马字曲名.keys))
        for chunk in stride(from: 0, to: missing.count, by: 300).map({ Array(missing[$0..<min($0 + 300, missing.count)]) }) where !chunk.isEmpty {
            let url = URL(string: "https://api.music.apple.com/v1/catalog/jp/songs?ids=\(chunk.map(String.init).joined(separator: ","))&l=en-US&include=artists")!
            guard let data = await 请求(url),
                  let decoded = try? JSONDecoder().decode(AppleMusic结果.self, from: data) else { continue }
            for id in chunk { 罗马字曲名[id] = "" }
            for song in decoded.data {
                guard let id = Int(song.id) else { continue }
                罗马字曲名[id] = song.attributes?.name ?? ""
                let artists = song.relationships?.artists?.data ?? []
                曲目歌手[id] = artists.compactMap { Int($0.id) }
                for artist in artists {
                    if let artistId = Int(artist.id), let name = artist.attributes?.name { 罗马字歌手名[artistId] = name }
                }
            }
        }
    }

    private nonisolated struct AppleMusic结果: Decodable {
        struct 项目: Decodable {
            struct 属性: Decodable {
                struct 封面: Decodable { let url: String? }
                struct 播放参数: Decodable { let id: String? }
                let name: String?
                let artistName: String?
                let albumName: String?
                let releaseDate: String?
                let artwork: 封面?
                let url: String?
                let playParams: 播放参数?
            }
            struct 关系: Decodable {
                struct 歌手: Decodable {
                    struct 数据: Decodable { struct 属性: Decodable { let name: String? }; let id: String; let attributes: 属性? }
                    let data: [数据]?
                }
                let artists: 歌手?
            }
            let id: String
            let attributes: 属性?
            let relationships: 关系?
        }
        struct 检索结果: Decodable { struct 列表: Decodable { let data: [项目]? }; let songs: 列表?; let artists: 列表? }
        let data: [项目]
        let results: 检索结果?

        enum CodingKeys: String, CodingKey { case data, results }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            data = try container.decodeIfPresent([项目].self, forKey: .data) ?? []
            results = try container.decodeIfPresent(检索结果.self, forKey: .results)
        }
    }

    private nonisolated static func 解析AppleMusic(_ data: Data, 检索结果: Bool) -> [候选] {
        guard let decoded = try? JSONDecoder().decode(AppleMusic结果.self, from: data) else { return [] }
        let items = 检索结果 ? decoded.results?.songs?.data ?? [] : decoded.data
        return items.compactMap { item in
            guard let id = Int(item.id), let attributes = item.attributes,
                  let name = attributes.name, let artist = attributes.artistName else { return nil }
            return 候选(
                trackId: id, artistId: item.relationships?.artists?.data?.first.flatMap { Int($0.id) },
                曲名: name, 歌手: artist, 专辑: attributes.albumName ?? "", 发行日期: attributes.releaseDate ?? "",
                // 没有 playParams 表示 Apple Music 里不能播放（只能在 iTunes Store 购买）
                可播放: attributes.playParams != nil,
                封面: attributes.artwork?.url.flatMap { URL(string: $0.replacingOccurrences(of: "{w}x{h}", with: "600x600")) },
                链接: attributes.url.flatMap(URL.init(string:))
            )
        }
    }

    private nonisolated static func 解析(_ data: Data) -> [候选] {
        guard let decoded = try? JSONDecoder().decode(iTunes结果.self, from: data) else { return [] }
        return decoded.results.compactMap { item in
            guard item.wrapperType == "track", item.kind == "song", let id = item.trackId,
                  let name = item.trackName, let artist = item.artistName else { return nil }
            // 封面换成 600 像素
            let artwork = item.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) }
            var link = item.trackViewUrl.flatMap { URLComponents(string: $0) }
            let songQuery = link?.queryItems?.filter { $0.name == "i" }
            link?.queryItems = songQuery
            return 候选(
                trackId: id, artistId: item.artistId, 曲名: name, 歌手: artist, 专辑: item.collectionName ?? "",
                发行日期: item.releaseDate ?? "", 可播放: item.isStreamable ?? true, 封面: artwork, 链接: link?.url
            )
        }
    }

    /// iTunes 接口每分钟大约只接受 20 次请求，超过时等到窗口空出来。
    private var 请求时间: [Date] = []
    /// 被限流后所有请求都暂停到这个时间，不让并发的请求继续撞上去。
    private var 暂停到 = Date.distantPast

    private func 等待请求名额() async {
        while true {
            if 暂停到 > .now {
                try? await Task.sleep(for: .seconds(暂停到.timeIntervalSinceNow))
                if Task.isCancelled { return }
                continue
            }
            let now = Date()
            请求时间.removeAll { now.timeIntervalSince($0) >= 60 }
            if let last = 请求时间.last, now.timeIntervalSince(last) < 最小间隔 {
                try? await Task.sleep(for: .seconds(最小间隔 - now.timeIntervalSince(last)))
                if Task.isCancelled { return }
                continue
            }
            if 请求时间.count < 每分钟请求上限 {
                请求时间.append(now)
                return
            }
            let wait = 60 - now.timeIntervalSince(请求时间[0]) + 0.1
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
        }
    }

    private func 请求(_ url: URL) async -> Data? {
        for attempt in 0..<限流重试次数 {
            await 等待请求名额()
            if Task.isCancelled { break }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.setValue("PaperVN", forHTTPHeaderField: "User-Agent")
            if let 开发者令牌, url.host == "api.music.apple.com" {
                request.setValue("Bearer \(开发者令牌)", forHTTPHeaderField: "Authorization")
            }
            do {
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                if status == 200 { return data }
                if 打印失败 { print("  请求失败 \(status)：\(url.absoluteString.removingPercentEncoding ?? url.absoluteString)") }
                // 403、429 是限流，稍等再试（Apple Music API 会给出 Retry-After）
                guard [403, 429, 500, 502, 503].contains(status), attempt < 限流重试次数 - 1 else { break }
                if [403, 429].contains(status) {
                    let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    暂停到 = max(暂停到, Date(timeIntervalSinceNow: retryAfter ?? Double(attempt + 1) * 限流等待秒数))
                    continue
                }
            } catch {
                if 打印失败 { print("  请求出错 \(error.localizedDescription)：\(url.absoluteString.removingPercentEncoding ?? url.absoluteString)") }
                guard attempt < 限流重试次数 - 1 else { break }
            }
            try? await Task.sleep(for: .seconds(Double(attempt + 1) * 限流等待秒数))
        }
        请求失败次数 += 1
        return nil
    }

    // MARK: 缓存

    private nonisolated static var 缓存目录: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppleMusic主题曲", isDirectory: true)
    }

    private func 读取缓存(_ key: String) -> 缓存文件? {
        if let cached = 内存缓存[key], 有效(cached) { return cached }
        let url = Self.缓存目录.appendingPathComponent("\(key).json")
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder().decode(缓存文件.self, from: data), 有效(cached) else { return nil }
        内存缓存[key] = cached
        return cached
    }

    /// 找到的保留 30 天；有没找到的歌曲时 3 天后重新检索（新歌可能刚上架）。
    private func 有效(_ file: 缓存文件) -> Bool {
        guard file.版本 == Self.规则版本 else { return false }
        let complete = file.结果.values.allSatisfy { if case .已找到 = $0 { true } else { false } }
        return Date().timeIntervalSince(file.保存时间) < (complete ? 30 : 3) * 86_400
    }

    private func 存入缓存(_ key: String, _ file: 缓存文件) {
        内存缓存[key] = file
        try? FileManager.default.createDirectory(at: Self.缓存目录, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: Self.缓存目录.appendingPathComponent("\(key).json"), options: .atomic)
        }
    }
}
