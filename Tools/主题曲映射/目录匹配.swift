// 目录匹配：检索没找到的歌曲，直接翻歌手的全部专辑和这部作品的专辑，逐首按读音比较。
// 只在生成映射时用：请求多，读音用 macOS 的日文分词算出来（很多歌在 Apple Music 上没有罗马字名）。
import Foundation

/// 采集到的原始数据存到训练数据（不进仓库），下次运行直接复用。环境变量 PAPERVN_TRAINING_DATA 可以改位置。
enum 主题曲训练数据 {
    static let 目录: URL = {
        let root = ProcessInfo.processInfo.environment["PAPERVN_TRAINING_DATA"]
            ?? URL(fileURLWithPath: ProcessInfo.processInfo.environment["PAPERVN_APP_ROOT"] ?? FileManager.default.currentDirectoryPath)
                .deletingLastPathComponent().appending(path: "训练数据").path
        let url = URL(fileURLWithPath: root).appending(path: "主题曲匹配", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// 追加一行到 JSONL 文件。
    static func 追加(_ line: Data, 到 name: String) {
        let url = 目录.appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line + Data("\n".utf8))
    }
}

struct 目录曲目: Codable {
    let id: Int
    let 歌名: String
    let 歌手: String
    let 专辑: String
    let 英文歌名: String
    let 英文歌手: String
    let 封面: String?
}

enum 目录结果级别 { case 确信, 待确认, 建议 }

struct 目录结果 {
    let 曲目: 目录曲目
    let 级别: 目录结果级别
    let 歌名分: Double
    let 歌手分: Double
}

/// 要找的歌曲。
struct 目录歌曲 {
    let 标题: String
    let 原标题: String?
    /// 歌手的所有写法（罗马字、日文、括号里的声优）。
    let 歌手: [String]
    /// 歌名本身带的版本说明（有时才接受同样带版本说明的曲目）。
    let 全名: String
}

final class 目录匹配 {
    private let 令牌: String
    private var 上次请求 = Date.distantPast
    private var 歌手缓存: [String: [目录曲目]] = [:]
    private var 作品缓存: [String: [目录曲目]] = [:]

    private struct 缓存行: Codable {
        let 类型: String
        let 键: String
        let 曲目: [目录曲目]
    }
    private static let 缓存文件 = "AppleMusic目录.jsonl"

    init(令牌: String) {
        self.令牌 = 令牌
        // 之前读过的歌手和作品专辑不用再请求
        guard let text = try? String(contentsOf: 主题曲训练数据.目录.appending(path: Self.缓存文件), encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        for line in text.split(separator: "\n") {
            guard let row = try? decoder.decode(缓存行.self, from: Data(line.utf8)) else { continue }
            if row.类型 == "歌手" { 歌手缓存[row.键] = row.曲目 } else { 作品缓存[row.键] = row.曲目 }
        }
    }

    private func 存储(类型: String, 键: String, 曲目: [目录曲目]) {
        if let data = try? JSONEncoder().encode(缓存行(类型: 类型, 键: 键, 曲目: 曲目)) { 主题曲训练数据.追加(data, 到: Self.缓存文件) }
    }

    private func 请求(_ path: String, _ query: [String: String] = [:]) async -> [String: Any] {
        var components = URLComponents(string: "https://api.music.apple.com/v1/catalog/\(path)")!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        for attempt in 0..<4 {
            let wait = 0.55 - Date().timeIntervalSince(上次请求)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            上次请求 = Date()
            var request = URLRequest(url: components.url!, timeoutInterval: 25)
            request.setValue("Bearer \(令牌)", forHTTPHeaderField: "Authorization")
            if let (data, response) = try? await URLSession.shared.data(for: request) {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:] }
                if status == 429 {
                    try? await Task.sleep(for: .seconds(15 * Double(attempt + 1)))
                    continue
                }
                return [:]
            }
            try? await Task.sleep(for: .seconds(3))
        }
        return [:]
    }

    // MARK: 读音

    static func 读音(_ text: String) -> String {
        let string = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil, string, CFRangeMake(0, CFStringGetLength(string)), kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
        )
        var output = ""
        var token = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while !token.isEmpty {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                output += latin
            } else {
                let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                output += (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
            }
            token = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }
        return output
    }

    /// 比较用的写法：去掉符号，长音、助词、训令式和黑本式的差别都抹平。
    static func 键(_ text: String) -> String {
        var value = text.folding(options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive], locale: nil).lowercased()
        value = value.filter { $0.isLetter || $0.isNumber }
        for (a, b) in [
            ("ou", "o"), ("oo", "o"), ("uu", "u"), ("aa", "a"), ("ii", "i"), ("ee", "e"), ("wo", "o"), ("nn", "n"), ("dzu", "zu"), ("du", "zu"),
            ("ha", "wa"), ("he", "e"), ("si", "shi"), ("ti", "chi"), ("tu", "tsu"), ("hu", "fu"), ("zi", "ji"),
        ] {
            value = value.replacingOccurrences(of: a, with: b)
        }
        return value
    }

    static func 相似度(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        if x.isEmpty || y.isEmpty { return 0 }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    private static func 去版本(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*[\(（\[【].*?[\)）\]】]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+[-–~〜～].*$"#, with: "", options: .regularExpression)
    }

    private static func 符合(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let 排除歌名 = #"カラオケ|karaoke|instrumental|off.?vocal|オルゴール|music box|カバー|\bcover\b|tv.?size|\binst\b|\blive\b|ライブ|ライヴ|remix|リミックス|short ver|from "|\[from"#
    private static let 版本词 = #"\b(ver|version|mix|arrange)\b|バージョン|ヴァージョン|リミックス"#
    private static let 排除专辑 = #"カバー|\bcover|アレンジ|arrange|piano|ピアノ|オルゴール|music box|カラオケ|karaoke|instrumental|acoustic|ジャズ|\bjazz|lullaby|子守|α波|アニソン魂|tribute|トリビュート"#

    private static func 名字(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",、&()（）"))
            .flatMap { $0.components(separatedBy: " and ") }.flatMap { $0.components(separatedBy: "CV") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .:：・")) }.filter { !$0.isEmpty }
    }

    private static func 姓名顺序(_ name: String) -> [String] {
        let words = name.split(separator: " ").map(String.init)
        return words.count == 2 ? [name, "\(words[1]) \(words[0])"] : [name]
    }

    static func 歌手对得上(_ mine: String, _ theirs: String) -> Bool {
        let keys = 姓名顺序(mine).map(键)
        for part in 名字(theirs) + [theirs] {
            for candidate in [键(part), 键(读音(part))] where keys.contains(where: { 相似度(candidate, $0) >= 0.8 }) {
                return true
            }
        }
        return false
    }

    // MARK: 读取目录

    private func 曲目(专辑 ids: [String]) async -> [目录曲目] {
        var output: [目录曲目] = []
        for start in stride(from: 0, to: ids.count, by: 30) {
            let chunk = ids[start..<min(start + 30, ids.count)].joined(separator: ",")
            let japanese = await 请求("jp/albums", ["ids": chunk, "include": "tracks"])
            let english = await 请求("jp/albums", ["ids": chunk, "include": "tracks", "l": "en-US"])
            func 曲目数据(_ album: [String: Any]) -> [[String: Any]] {
                ((album["relationships"] as? [String: Any])?["tracks"] as? [String: Any])?["data"] as? [[String: Any]] ?? []
            }
            var names: [String: (String, String)] = [:]
            for album in english["data"] as? [[String: Any]] ?? [] {
                for track in 曲目数据(album) {
                    guard let id = track["id"] as? String, let attributes = track["attributes"] as? [String: Any] else { continue }
                    names[id] = ((attributes["name"] as? String) ?? "", (attributes["artistName"] as? String) ?? "")
                }
            }
            for album in japanese["data"] as? [[String: Any]] ?? [] {
                let attributes = album["attributes"] as? [String: Any]
                let albumName = (attributes?["name"] as? String) ?? ""
                let artwork = ((attributes?["artwork"] as? [String: Any])?["url"] as? String)?
                    .replacingOccurrences(of: "{w}", with: "600").replacingOccurrences(of: "{h}", with: "600")
                for track in 曲目数据(album) where track["type"] as? String == "songs" {
                    guard let idText = track["id"] as? String, let id = Int(idText), let trackAttributes = track["attributes"] as? [String: Any] else { continue }
                    output.append(.init(
                        id: id, 歌名: (trackAttributes["name"] as? String) ?? "", 歌手: (trackAttributes["artistName"] as? String) ?? "", 专辑: albumName,
                        英文歌名: names[idText]?.0 ?? "", 英文歌手: names[idText]?.1 ?? "", 封面: artwork
                    ))
                }
            }
        }
        return output
    }

    private func 歌手全部歌曲(_ name: String) async -> [目录曲目] {
        if let cached = 歌手缓存[name] { return cached }
        var terms: [(String, String)] = [("us", name), ("jp", name)]
        for order in Self.姓名顺序(name) {
            if let reading = 主题曲文本.平假名读音(order) { terms.append(("jp", reading.replacingOccurrences(of: " ", with: ""))) }
        }
        var artists = Set<String>()
        for (store, term) in terms {
            let result = await 请求("\(store)/search", ["term": term, "types": "artists", "limit": "10"])
            for artist in ((result["results"] as? [String: Any])?["artists"] as? [String: Any])?["data"] as? [[String: Any]] ?? [] {
                let artistName = ((artist["attributes"] as? [String: Any])?["name"] as? String) ?? ""
                if Self.歌手对得上(name, artistName), let id = artist["id"] as? String { artists.insert(id) }
            }
        }
        var albums: [String] = []
        for artist in artists.sorted().prefix(5) {
            var offset = 0
            while offset < 300 {
                let page = await 请求("jp/artists/\(artist)/albums", ["limit": "100", "offset": String(offset)])
                let data = page["data"] as? [[String: Any]] ?? []
                albums += data.compactMap { $0["id"] as? String }
                if data.count < 100 { break }
                offset += 100
            }
        }
        let tracks = await 曲目(专辑: Array(Set(albums)).sorted())
        歌手缓存[name] = tracks
        存储(类型: "歌手", 键: name, 曲目: tracks)
        return tracks
    }

    static func 作品短名(_ work: String) -> String {
        let base = work.replacingOccurrences(of: #"^(劇場総集編|総集編|劇場版|映画|TVアニメ)\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(
                of: #"\s*(第[0-9一二三四五六七八九十]+期|[0-9]+(st|nd|rd|th) Season|Season ?[0-9]+|\(.*\)|（.*）).*$"#, with: "", options: .regularExpression
            )
        return base.split(whereSeparator: { $0 == " " || $0 == "　" }).first.map(String.init) ?? base
    }

    private func 作品专辑(_ work: String, 音乐: [String]) async -> [目录曲目] {
        if let cached = 作品缓存[work] { return cached }
        let short = Self.作品短名(work)
        var albums: [String] = []
        for offset in [0, 25] {
            let result = await 请求("jp/search", ["term": short, "types": "albums", "limit": "25", "offset": String(offset)])
            for album in ((result["results"] as? [String: Any])?["albums"] as? [String: Any])?["data"] as? [[String: Any]] ?? [] {
                let name = ((album["attributes"] as? [String: Any])?["name"] as? String) ?? ""
                if name.contains(short), let id = album["id"] as? String { albums.append(id) }
            }
        }
        // Bangumi 列出的音乐条目名：单曲的专辑名里常常没有作品名
        for term in 音乐.prefix(6) {
            let result = await 请求("jp/search", ["term": term, "types": "albums", "limit": "10"])
            for album in ((result["results"] as? [String: Any])?["albums"] as? [String: Any])?["data"] as? [[String: Any]] ?? [] {
                let name = ((album["attributes"] as? [String: Any])?["name"] as? String) ?? ""
                if Self.相似度(Self.键(name), Self.键(term)) >= 0.8, let id = album["id"] as? String { albums.append(id) }
            }
        }
        let tracks = await 曲目(专辑: Array(Set(albums)).sorted())
        作品缓存[work] = tracks
        存储(类型: "作品", 键: work, 曲目: tracks)
        return tracks
    }

    /// 可能是这首短版本的完整版的曲目：翻 Apple 上这组歌手的全部专辑，再按歌名和歌手检索。结果由调用方比较歌名和歌手。
    func 完整版曲目(短版本 short: String, 歌手 artist: String) async -> [Int] {
        var ids: [Int] = []
        let names = artist.components(separatedBy: CharacterSet(charactersIn: ",、&/×"))
            .map { $0.replacingOccurrences(of: #"[\(（].*?[\)）]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for name in names.prefix(3) {
            ids += await 歌手全部歌曲(name).filter { AppleMusic主题曲匹配.是完整版($0.歌名, 短版本: short) }.map(\.id)
        }
        let title = AppleMusic主题曲匹配.显示歌名(short)
        for term in [title, "\(title) \(names.first ?? "")"] {
            let result = await 请求("jp/search", ["term": term, "types": "songs", "limit": "25"])
            for song in ((result["results"] as? [String: Any])?["songs"] as? [String: Any])?["data"] as? [[String: Any]] ?? [] {
                if let id = (song["id"] as? String).flatMap(Int.init) { ids.append(id) }
            }
        }
        return Array(Set(ids))
    }

    // MARK: 比较

    private func 最接近(_ song: 目录歌曲, _ tracks: [目录曲目], 门槛: Double) -> (目录曲目, Double)? {
        let wanted = Self.键(Self.去版本(song.原标题.map(Self.读音) ?? song.标题))
        let raw = Self.键(Self.去版本(song.原标题 ?? song.标题))
        var best: (目录曲目, Double)?
        for track in tracks {
            if Self.符合(Self.排除歌名, track.歌名) || AppleMusic主题曲匹配.是短版本(track.歌名) { continue }
            // 曲目带版本说明（Emotional Version、RIN Mix）而这首歌没有：是另一个版本
            if Self.符合(Self.版本词, track.歌名), !Self.符合(Self.版本词, song.全名) { continue }
            let plain = Self.去版本(track.歌名)
            let score = [Self.读音(plain), Self.去版本(track.英文歌名), plain].map { max(Self.相似度(Self.键($0), wanted), Self.相似度(Self.键($0), raw)) }.max() ?? 0
            if score >= 门槛, score > (best?.1 ?? 0) { best = (track, score) }
        }
        return best
    }

    /// 歌手对得上的优先；否则看作品的专辑；专辑名里有作品名才算依据，其余只给建议。
    func 查找(_ song: 目录歌曲, 作品: String?, 音乐: [String]) async -> 目录结果? {
        func 对上歌手(_ track: 目录曲目) -> Bool {
            song.歌手.contains { Self.歌手对得上($0, track.歌手) || Self.歌手对得上($0, track.英文歌手) }
        }
        var byArtist: (目录曲目, Double)?
        for name in song.歌手.prefix(5) {
            if let hit = 最接近(song, await 歌手全部歌曲(name), 门槛: 0.85), hit.1 > (byArtist?.1 ?? 0) { byArtist = hit }
        }
        if let (track, score) = byArtist, 对上歌手(track) {
            return .init(曲目: track, 级别: score >= 0.95 ? .确信 : .待确认, 歌名分: score, 歌手分: 1)
        }
        guard let 作品 else { return nil }
        let tracks = (await 作品专辑(作品, 音乐: 音乐)).filter { !Self.符合(Self.排除专辑, $0.专辑) }
        guard let (track, score) = 最接近(song, tracks, 门槛: 0.92) else { return nil }
        if 对上歌手(track) { return .init(曲目: track, 级别: score >= 0.95 ? .确信 : .待确认, 歌名分: score, 歌手分: 1) }
        // 歌手对不上：同名歌常是别人唱的版本，只有这部作品的原声集才算依据（原声集署名常是作曲家），其余只给建议
        let inSoundtrack = track.专辑.contains(Self.作品短名(作品)) && Self.符合(#"サウンドトラック|soundtrack|\bost\b|音楽集|劇伴"#, track.专辑)
        return .init(曲目: track, 级别: inSoundtrack ? .待确认 : .建议, 歌名分: score, 歌手分: 0)
    }
}
