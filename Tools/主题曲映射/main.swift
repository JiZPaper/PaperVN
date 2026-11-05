// 生成 PaperVN/Resources/PaperVNThemeSongMap.json：按作品映射里的热度顺序读取 MAL 的主题曲和 AnisongDB 的插入曲，
// 用 App 里同一份匹配代码（PaperVN/非用户界面/资料库/动画主题曲.swift）在 Apple Music 日本商店里匹配。
// 由 Tools/生成主题曲映射.sh 编译运行，用法见那里。
//
// iTunes 接口每分钟只接受大约 20 次请求，一部作品通常要“歌曲数＋1”次。进度存在 Tools/主题曲映射/进度/，
// 中断后再运行会接着做；有请求失败（限流、网络）的作品不记结果，下次重试，不会把没检索到的歌曲记成“没有”。
import CryptoKit
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let 仓库 = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PAPERVN_APP_ROOT"] ?? FileManager.default.currentDirectoryPath)
let 进度URL = ProcessInfo.processInfo.environment["THEME_SONG_PROGRESS"].map(URL.init(fileURLWithPath:))
    ?? 仓库.appending(path: "Tools/主题曲映射/进度/进度.json")
let 校正URL = 仓库.appending(path: "Tools/主题曲映射人工校正.json")
let 作品映射URL = 仓库.appending(path: "PaperVN/Resources/PaperVNWorkMap.json")
var 输出URL = 仓库.appending(path: "PaperVN/Resources/PaperVNThemeSongMap.json")

// MARK: 参数

var 作品数 = 1500
var 指定作品: [Int] = []
var 季度: [String] = []
var 只写文件 = false
/// 不管进度里的检查时间和规则版本，重新匹配指定的作品（只改了个别规则、不想全部重跑时用）。
var 强制重查 = false
/// 只重查上次没找到的歌曲，找到的保留（规则只是放宽、不会让找到的变错时用，省掉大部分请求）。
var 只查未找到 = false
var 重新检查天数 = 60.0
var 未找到重查天数 = 14.0
var 时限分钟: Double?

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--top":
        let value = arguments.next() ?? ""
        作品数 = value == "all" ? Int.max : Int(value) ?? 作品数
    case "--ids": 指定作品 = (arguments.next() ?? "").split(separator: ",").compactMap { Int($0) }
    case "--season": 季度.append(arguments.next() ?? "")
    case "--write-only": 只写文件 = true
    case "--force": 强制重查 = true
    case "--misses-only": 强制重查 = true; 只查未找到 = true
    case "--recheck-days": 重新检查天数 = Double(arguments.next() ?? "") ?? 重新检查天数
    case "--miss-recheck-days": 未找到重查天数 = Double(arguments.next() ?? "") ?? 未找到重查天数
    case "--minutes": 时限分钟 = Double(arguments.next() ?? "")
    case "--output": 输出URL = URL(fileURLWithPath: arguments.next() ?? 输出URL.path)
    default:
        print("不认识的参数：\(argument)")
        exit(64)
    }
}

// MARK: 进度

/// 每部作品的结果：主题曲编号 → [曲目编号, 歌手编号, 歌名, 歌手, 封面]，0 表示没有。
struct 进度: Codable {
    struct 作品: Codable {
        var 检查时间: Date
        var 主题曲: [String: 值]
        /// 匹配时的规则版本（AppleMusic主题曲匹配.规则版本），规则改了就重查。
        var 规则版本: Int?
        /// AnisongDB 的插入曲（编号 → 结果），按 AnisongDB 的顺序；nil 表示还没读取。
        var 插入曲: [插入曲条目]?
        /// 作品的日文名（没有时是 MAL 的标题），写进未匹配清单。
        var 作品名: String?
        /// 没找到的歌曲的信息（键和“主题曲”相同，插入曲是负数），写进未匹配清单给后台人工匹配。
        var 未找到: [String: 歌曲信息]?
        /// 匹配到了但歌名、歌手不是几乎一致的歌曲（键和“主题曲”相同），写进清单给后台人工确认。
        var 低确信: [String: 低确信信息]?
        /// 所有匹配到的歌曲都打过分了；旧版本的进度没有，写文件时补上。
        var 已评确信: Bool?
        /// Bangumi 上关联的音乐条目（关系、名称），有没找到的歌曲时才读取；检索和后台人工匹配时用。
        var Bangumi音乐: [Bangumi音乐条目]?
        /// 没算找到但歌名对得上的候选，不进映射，只在后台建议人工确认。
        var 建议: [String: 建议信息]?
        /// 已经翻过歌手和作品的专辑（目录匹配）。
        var 目录已查: Bool?
    }
    struct 建议信息: Codable {
        let 值: 值
        let 歌名分: Double
        let 歌手分: Double
        let 专辑: String
    }
    struct Bangumi音乐条目: Codable {
        let 关系: String
        let 名称: String
    }
    struct 低确信信息: Codable {
        var 信息: 歌曲信息
        var 歌名分: Double
        var 歌手分: Double
        var 专辑: String
    }
    struct 歌曲信息: Codable {
        var 种类: String
        var 序号: String?
        var 标题: String
        var 原标题: String?
        var 歌手: String
        var 歌手原名: String?
        /// 匹配时用罗马字查到的歌手日文名（MAL 只有罗马字时）。
        var 歌手日文名: String?
        var 话数: String?
        /// MAL 的原文。
        var 原文: String?
    }
    struct 插入曲条目: Codable {
        let 编号: Int
        let 歌名: String
        let 歌手: String
        let 值: 值
    }
    enum 值: Codable, Equatable {
        case 歌曲(trackId: Int, artistId: Int?, 歌名: String, 歌手: String, 封面: String?)
        case 无

        init(from decoder: Decoder) throws {
            if let number = try? decoder.singleValueContainer().decode(Int.self), number == 0 {
                self = .无
                return
            }
            var container = try decoder.unkeyedContainer()
            let trackId = try container.decode(Int.self)
            let artistId = try container.decodeNil() ? nil : try container.decode(Int.self)
            self = .歌曲(
                trackId: trackId, artistId: artistId, 歌名: try container.decode(String.self),
                歌手: try container.decode(String.self), 封面: try container.decodeIfPresent(String.self)
            )
        }

        func encode(to encoder: Encoder) throws {
            switch self {
            case .无:
                var container = encoder.singleValueContainer()
                try container.encode(0)
            case let .歌曲(trackId, artistId, title, artist, artwork):
                var container = encoder.unkeyedContainer()
                try container.encode(trackId)
                if let artistId { try container.encode(artistId) } else { try container.encodeNil() }
                try container.encode(title)
                try container.encode(artist)
                if let artwork { try container.encode(artwork) }
            }
        }

        init(_ item: AppleMusic主题曲匹配.候选?) {
            guard let item else {
                self = .无
                return
            }
            self = .歌曲(trackId: item.trackId, artistId: item.artistId, 歌名: item.曲名, 歌手: item.歌手, 封面: item.封面?.absoluteString)
        }
    }
    var 作品: [String: 作品] = [:]
    /// 人工校正里的曲目编号查到的日本商店信息。
    var 校正曲目: [String: 值] = [:]
}

func 读取进度() -> 进度 {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let data = try? Data(contentsOf: 进度URL) else { return 进度() }
    return (try? decoder.decode(进度.self, from: data)) ?? 进度()
}

func 存储(_ value: 进度) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try? FileManager.default.createDirectory(at: 进度URL.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? encoder.encode(value) { try? data.write(to: 进度URL, options: .atomic) }
}

// MARK: MAL

/// 环境变量优先，否则读 Config/PaperVN.private.xcconfig（不进仓库）。
func 私有配置(_ name: String) -> String {
    if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty { return value }
    let config = (try? String(contentsOf: 仓库.appending(path: "Config/PaperVN.private.xcconfig"), encoding: .utf8)) ?? ""
    for line in config.split(separator: "\n") where line.hasPrefix(name + " ") || line.hasPrefix(name + "=") {
        return line.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }
    return ""
}

let clientID = 私有配置("MAL_CLIENT_ID")
guard 只写文件 || !clientID.isEmpty else {
    print("没有 MAL_CLIENT_ID：在 Config/PaperVN.private.xcconfig 里填写，或者设置同名环境变量")
    exit(1)
}

struct MAL作品: Decodable {
    struct 主题曲: Decodable { let id: Int; let text: String }
    struct 别名: Decodable { let en: String?; let ja: String? }
    let id: Int
    let title: String
    let alternative_titles: 别名?
    let opening_themes: [主题曲]?
    let ending_themes: [主题曲]?
}

func MAL请求(_ path: String) async -> Data? {
    for attempt in 0..<4 {
        var request = URLRequest(url: URL(string: "https://api.myanimelist.net/v2/\(path)")!, timeoutInterval: 20)
        request.setValue(clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        request.setValue("PaperVN", forHTTPHeaderField: "User-Agent")
        if let (data, response) = try? await URLSession.shared.data(for: request) {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                // 作品的主题曲文本存到训练数据
                if path.hasPrefix("anime/"), !path.hasPrefix("anime/season"), let body = String(data: data, encoding: .utf8) {
                    主题曲训练数据.追加(Data("{\"path\":\"\(path)\",\"body\":\(body)}".utf8), 到: "MAL主题曲.jsonl")
                }
                return data
            }
            if status == 404 { return nil }
        }
        try? await Task.sleep(for: .seconds(Double(attempt + 1) * 5))
    }
    return nil
}

func 季度作品(_ value: String) async -> [Int] {
    struct 列表: Decodable { struct 项: Decodable { struct 节点: Decodable { let id: Int }; let node: 节点 }; let data: [项] }
    guard let data = await MAL请求("anime/season/\(value)?limit=200&sort=anime_num_list_users"),
          let list = try? JSONDecoder().decode(列表.self, from: data) else { return [] }
    return list.data.map(\.node.id)
}

// MARK: 匹配

var progress = 读取进度()
/// Apple Music API 的开发者令牌（ES256 签名的 JWT）：密钥是开发者账户里建的 MusicKit 密钥（Media Services），
/// Key ID 与密钥路径写在 APPLE_MUSIC_KEY_ID、APPLE_MUSIC_KEY_PATH，Team ID 读 Xcode 项目。没有配置时返回 nil。
func AppleMusic开发者令牌() -> String? {
    let keyID = 私有配置("APPLE_MUSIC_KEY_ID")
    let path = NSString(string: 私有配置("APPLE_MUSIC_KEY_PATH")).expandingTildeInPath
    let project = (try? String(contentsOf: 仓库.appending(path: "PaperVN.xcodeproj/project.pbxproj"), encoding: .utf8)) ?? ""
    guard !keyID.isEmpty, let pem = try? String(contentsOfFile: path, encoding: .utf8),
          let key = try? P256.Signing.PrivateKey(pemRepresentation: pem),
          let team = project.firstMatch(of: #/DEVELOPMENT_TEAM = ([A-Z0-9]+);/#)?.1 else { return nil }
    func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let now = Int(Date().timeIntervalSince1970)
    guard let header = try? JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID]),
          let payload = try? JSONSerialization.data(withJSONObject: ["iss": String(team), "iat": now, "exp": now + 7 * 86_400]) else { return nil }
    let signingInput = "\(base64URL(header)).\(base64URL(payload))"
    guard let signature = try? key.signature(for: Data(signingInput.utf8)) else { return nil }
    return "\(signingInput).\(base64URL(signature.rawRepresentation))"
}

let 令牌 = 只写文件 ? nil : AppleMusic开发者令牌()
// 有 Apple Music API 的令牌时用它（上限高得多；同时发出几十个请求会触发突发限流，所以每 0.5 秒一次，遇到 429 退避）；
// 否则用 iTunes 接口，它在每分钟 20 次时仍会间歇返回 403，放慢到每分钟 12 次
let 匹配器 = 令牌 == nil
    ? AppleMusic主题曲匹配(每分钟请求上限: 12, 限流重试次数: 8, 限流等待秒数: 30, 打印失败: true)
    : AppleMusic主题曲匹配(每分钟请求上限: 120, 最小间隔: 0.5, 限流重试次数: 8, 限流等待秒数: 30, 开发者令牌: 令牌, 打印失败: true)
if !只写文件 { print(令牌 == nil ? "使用 iTunes 接口（没有配置 Apple Music API 密钥）" : "使用 Apple Music API") }
let 开始时间 = Date()

/// 限流时等一会儿重试整批；一直失败就返回 nil，下次运行再做。
func 匹配(_ songs: [动画主题曲], 作品标题: [String], 名称: String, malID: Int) async -> [Int: AppleMusic主题曲匹配.候选]? {
    for attempt in 0..<3 {
        let failures = await 匹配器.请求失败次数
        let found = await 匹配器.日本商店匹配(songs, 作品标题: 作品标题, 原名线索: { await Bangumi检索词(malID) })
        if await 匹配器.请求失败次数 == failures { return found }
        print("  \(名称) 有请求失败，\(attempt < 2 ? "稍后重试" : "跳过")")
        try? await Task.sleep(for: .seconds(Double(attempt + 1) * 90))
    }
    return nil
}

// MARK: Bangumi

/// 作品映射里 MAL ID → Bangumi ID。
let Bangumi编号: [Int: Int] = {
    enum 值: Decodable {
        case int(Int), other
        init(from decoder: Decoder) throws {
            self = (try? decoder.singleValueContainer().decode(Int.self)).map(值.int) ?? .other
        }
    }
    struct 映射: Decodable { struct 动画: Decodable { let works: [[值]] }; let anime: 动画 }
    guard let data = try? Data(contentsOf: 作品映射URL), let map = try? JSONDecoder().decode(映射.self, from: data) else { return [:] }
    var ids: [Int: Int] = [:]
    for row in map.anime.works where row.count > 4 {
        if case .int(let mal) = row[1], case .int(let bangumi) = row[4], ids[mal] == nil { ids[mal] = bangumi }
    }
    return ids
}()

/// 读取 Bangumi 关联的音乐条目，存进进度。读取失败时返回 nil，下次再试。
func Bangumi音乐(_ malID: Int) async -> [进度.Bangumi音乐条目]? {
    if let known = progress.作品[String(malID)]?.Bangumi音乐 { return known }
    if let known = Bangumi读取结果[malID] { return known }
    guard let bangumi = Bangumi编号[malID] else { return [] }
    struct 关联: Decodable { let type: Int; let relation: String; let name: String }
    var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/subjects/\(bangumi)/subjects")!, timeoutInterval: 20)
    request.setValue("jizpaper/PaperVN", forHTTPHeaderField: "User-Agent")
    for attempt in 0..<3 {
        try? await Task.sleep(for: .seconds(0.4))
        if let (data, response) = try? await URLSession.shared.data(for: request) {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { Bangumi读取结果[malID] = []; return [] }
            if status == 200, let list = try? JSONDecoder().decode([关联].self, from: data) {
                if let body = String(data: data, encoding: .utf8) {
                    主题曲训练数据.追加(Data("{\"malID\":\(malID),\"bangumi\":\(bangumi),\"body\":\(body)}".utf8), 到: "Bangumi音乐.jsonl")
                }
                let result = list.filter { $0.type == 3 && $0.relation != "广播剧" }.map { 进度.Bangumi音乐条目(关系: $0.relation, 名称: $0.name) }
                Bangumi读取结果[malID] = result
                return result
            }
        }
        try? await Task.sleep(for: .seconds(Double(attempt + 1) * 5))
    }
    return nil
}
var Bangumi读取结果: [Int: [进度.Bangumi音乐条目]] = [:]

/// 音乐条目名称里可以检索的日文名：“ef／OPENING THEME「euphoric field」”取括号里的，“炎のさだめ / いつもあなたが”分开。
func Bangumi检索词(_ malID: Int) async -> [String] {
    guard let list = await Bangumi音乐(malID) else { return [] }
    let relations: Set<String> = ["片头曲", "片尾曲", "插入歌", "主题歌"]
    var seen = Set<String>()
    var terms: [String] = []
    for item in list where relations.contains(item.关系) {
        let quoted = item.名称.matches(of: #/[「『]([^」』]+)[」』]/#).map { String($0.1) }
        let parts = quoted.isEmpty ? item.名称.components(separatedBy: CharacterSet(charactersIn: "/／&＆")) : quoted
        for part in parts.map({ $0.trimmingCharacters(in: .whitespaces) }) where 主题曲文本.含日文(part) && seen.insert(part).inserted {
            // “Days-愛情と日常-”这样连着符号检索不到，换成空格
            terms.append(part.replacingOccurrences(of: #"[-‐–—~〜～]+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces))
        }
    }
    return Array(terms.prefix(8))
}

func 处理(_ malID: Int) async -> Bool {
    let changed = await 基础处理(malID)
    return await 目录补充(malID) || changed
}

let 目录器: 目录匹配? = AppleMusic开发者令牌().map(目录匹配.init(令牌:))

/// 检索没找到的歌曲，翻歌手和作品的专辑再找一遍。确信、待确认的写进结果，其余只留作建议。
func 目录补充(_ malID: Int) async -> Bool {
    let key = String(malID)
    guard let 目录器, let work = progress.作品[key], work.目录已查 != true else { return false }
    guard work.主题曲.values.contains(.无) || work.插入曲?.contains(where: { $0.值 == .无 }) == true else {
        progress.作品[key]?.目录已查 = true
        return false
    }
    let music = (await Bangumi音乐(malID) ?? []).filter { ["原声集", "角色歌", "片头曲", "片尾曲", "插入歌", "其他"].contains($0.关系) }.map(\.名称)
    记下Bangumi音乐(key, malID)
    let themeTracks = Set(work.主题曲.values.compactMap { value -> Int? in
        if case .歌曲(let id, _, _, _, _) = value { id } else { nil }
    })
    func 名字(_ info: 进度.歌曲信息?, 歌手: String) -> [String] {
        var names = 歌手.components(separatedBy: CharacterSet(charactersIn: ",、&")).flatMap { $0.components(separatedBy: " and ") }
            .map { $0.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        if let original = info?.歌手原名 { names.append(original) }
        if let japanese = info?.歌手日文名 { names.append(japanese) }
        if let text = info?.原文, let by = text.range(of: " by ", options: .caseInsensitive) {
            for match in text[by.upperBound...].matches(of: #/[\(（](?:CV[:：]?\s*)?([^()（）]+)[\)）]/#) {
                names += String(match.1).components(separatedBy: CharacterSet(charactersIn: ",、&")).map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        return Array(Set(names.filter { !$0.isEmpty && !$0.lowercased().hasPrefix("ep") })).sorted()
    }
    func 值(_ result: 目录结果) -> 进度.值 {
        .歌曲(trackId: result.曲目.id, artistId: nil, 歌名: result.曲目.歌名, 歌手: result.曲目.歌手, 封面: result.曲目.封面)
    }
    func 记录(_ id: String, _ result: 目录结果, 信息: 进度.歌曲信息) {
        if result.级别 != .确信, result.级别 != .建议 {
            var low = progress.作品[key]?.低确信 ?? [:]
            low[id] = .init(信息: 信息, 歌名分: result.歌名分, 歌手分: result.歌手分, 专辑: result.曲目.专辑)
            progress.作品[key]?.低确信 = low
        }
        print("    目录\(result.级别 == .确信 ? "确信" : result.级别 == .待确认 ? "待确认" : "建议")：\(信息.原标题 ?? 信息.标题) / \(信息.歌手) → \(result.曲目.歌名) / \(result.曲目.歌手) | \(result.曲目.专辑)")
    }
    for (id, value) in work.主题曲 where value == .无 {
        guard let info = work.未找到?[id] else { continue }
        let song = 目录歌曲(标题: info.标题, 原标题: info.原标题, 歌手: 名字(info, 歌手: info.歌手), 全名: info.原文 ?? info.标题)
        guard let result = await 目录器.查找(song, 作品: work.作品名, 音乐: music) else { continue }
        记录(id, result, 信息: info)
        if result.级别 == .建议 {
            progress.作品[key]?.建议?[id] = nil
            var suggestions = progress.作品[key]?.建议 ?? [:]
            suggestions[id] = .init(值: 值(result), 歌名分: result.歌名分, 歌手分: result.歌手分, 专辑: result.曲目.专辑)
            progress.作品[key]?.建议 = suggestions
        } else {
            progress.作品[key]?.主题曲[id] = 值(result)
            progress.作品[key]?.建议?[id] = nil
        }
    }
    var entries = work.插入曲 ?? []
    for (index, entry) in entries.enumerated() where entry.值 == .无 {
        let id = String(-entry.编号)
        let info = work.未找到?[id] ?? 进度.歌曲信息(种类: "in", 标题: entry.歌名, 歌手: entry.歌手)
        let song = 目录歌曲(标题: entry.歌名, 原标题: nil, 歌手: 名字(info, 歌手: entry.歌手), 全名: entry.歌名)
        guard let result = await 目录器.查找(song, 作品: work.作品名, 音乐: music), !themeTracks.contains(result.曲目.id) else { continue }
        记录(id, result, 信息: info)
        if result.级别 == .建议 {
            progress.作品[key]?.建议?[id] = nil
            var suggestions = progress.作品[key]?.建议 ?? [:]
            suggestions[id] = .init(值: 值(result), 歌名分: result.歌名分, 歌手分: result.歌手分, 专辑: result.曲目.专辑)
            progress.作品[key]?.建议 = suggestions
        } else {
            entries[index] = .init(编号: entry.编号, 歌名: entry.歌名, 歌手: entry.歌手, 值: 值(result))
            progress.作品[key]?.建议?[id] = nil
        }
    }
    if work.插入曲 != nil { progress.作品[key]?.插入曲 = entries }
    progress.作品[key]?.目录已查 = true
    return true
}

/// 已经配上短版本（TV Size、Game Version 等）的歌曲，单独再找一次完整版，找到就替换，其他歌曲不动；确实没有时保留短版本。
var 查过完整版: Set<String> = []
func 换成完整版() async {
    func 是短版本(_ value: 进度.值) -> Bool {
        if case let .歌曲(_, _, title, _, _) = value { AppleMusic主题曲匹配.是短版本(title) } else { false }
    }
    func 完整版(_ current: 进度.值?) async -> AppleMusic主题曲匹配.候选? {
        guard let 目录器, case let .歌曲(_, _, shortTitle, shortArtist, _)? = current else { return nil }
        let ids = await 目录器.完整版曲目(短版本: shortTitle, 歌手: shortArtist)
        let items = (try? await 匹配器.查询曲目(ids, 地区: "jp"))?.values ?? [:].values
        return items.filter {
            $0.可播放 && AppleMusic主题曲匹配.是完整版($0.曲名, 短版本: shortTitle) && AppleMusic主题曲匹配.是同歌手($0.歌手, shortArtist)
        }.min { ($0.发行日期, $0.trackId) < ($1.发行日期, $1.trackId) }
    }
    /// MAL 指定了别的版本（“~Acoustic&hidamarble version~”）：这首要的不是普通完整版，不自动替换。
    func 指定了版本(_ song: 动画主题曲) -> Bool {
        let text = "\(song.标题) \(song.版本说明 ?? "")"
        return !AppleMusic主题曲匹配.是短版本(text)
            && text.range(of: #"(?i)(?<![a-z])(?:ver|version|acoustic|mix|remix|arrange)(?![a-z])"#, options: .regularExpression) != nil
    }
    /// 确实只有短版本：保留，同时列到后台，人工确认或改配。
    func 列到后台(_ song: 动画主题曲, key: String, 专辑 album: String?) async {
        var low = progress.作品[key]?.低确信 ?? [:]
        low[String(song.id)] = .init(信息: await 未找到信息(song, 原文: nil), 歌名分: 1, 歌手分: 1, 专辑: album ?? "")
        progress.作品[key]?.低确信 = low
    }
    for (key, work) in progress.作品 {
        let shortThemes = work.主题曲.filter { 是短版本($0.value) && 查过完整版.insert("\(key)/\($0.key)").inserted }
        let shortInserts = (work.插入曲 ?? []).filter { 是短版本($0.值) && 查过完整版.insert("\(key)/\($0.编号)").inserted }
        guard !shortThemes.isEmpty || !shortInserts.isEmpty, let malID = Int(key),
              let data = await MAL请求("anime/\(malID)?fields=alternative_titles,opening_themes,ending_themes"),
              let anime = try? JSONDecoder().decode(MAL作品.self, from: data) else { continue }
        let songs = (anime.opening_themes ?? []).compactMap { 动画主题曲(malID: $0.id, 种类: .片头曲, 文本: $0.text) }
            + (anime.ending_themes ?? []).compactMap { 动画主题曲(malID: $0.id, 种类: .片尾曲, 文本: $0.text) }
        let titles = [anime.alternative_titles?.ja, anime.title, anime.alternative_titles?.en].compactMap { $0 }.filter { !$0.isEmpty }
        for song in songs where shortThemes[String(song.id)] != nil {
            guard !指定了版本(song), let item = await 完整版(shortThemes[String(song.id)]) else {
                await 列到后台(song, key: key, 专辑: nil)
                continue
            }
            progress.作品[key]?.主题曲[String(song.id)] = 进度.值(item)
            progress.作品[key]?.低确信?[String(song.id)] = nil
            print("    换成完整版：\(song.标题) → \(item.曲名) / \(item.歌手)")
        }
        if !shortInserts.isEmpty, let inserts = await 插入曲(malID, 片头片尾: songs) {
            for song in inserts where shortInserts.contains(where: { $0.编号 == -song.id }) {
                guard !指定了版本(song), let item = await 完整版(shortInserts.first { $0.编号 == -song.id }?.值) else {
                    await 列到后台(song, key: key, 专辑: nil)
                    continue
                }
                guard let index = progress.作品[key]?.插入曲?.firstIndex(where: { $0.编号 == -song.id }) else { continue }
                progress.作品[key]?.插入曲?[index] = .init(编号: -song.id, 歌名: song.标题, 歌手: song.歌手, 值: 进度.值(item))
                progress.作品[key]?.低确信?[String(song.id)] = nil
                print("    换成完整版：\(song.标题) → \(item.曲名) / \(item.歌手)")
            }
        }
        存储(progress)
    }
}

func 基础处理(_ malID: Int) async -> Bool {
    // 中断后再运行时，翻过目录的作品不用再查一遍
    if 只查未找到, progress.作品[String(malID)]?.目录已查 == true { return false }
    let key = String(malID)
    var needsThemes = true
    if !强制重查, let done = progress.作品[key], done.规则版本 ?? 1 == AppleMusic主题曲匹配.规则版本 {
        let age = Date().timeIntervalSince(done.检查时间) / 86_400
        let hasMiss = done.主题曲.values.contains(.无)
        if age < 重新检查天数, !(hasMiss && age >= 未找到重查天数) { needsThemes = false }
    }
    guard needsThemes || progress.作品[key]?.插入曲 == nil || 强制重查 else { return false }
    guard let data = await MAL请求("anime/\(malID)?fields=alternative_titles,opening_themes,ending_themes"),
          let anime = try? JSONDecoder().decode(MAL作品.self, from: data) else {
        print("  无法读取 MAL \(malID)")
        return false
    }
    let name = anime.alternative_titles?.ja.flatMap { $0.isEmpty ? nil : $0 } ?? anime.title
    let songs = (anime.opening_themes ?? []).compactMap { 动画主题曲(malID: $0.id, 种类: .片头曲, 文本: $0.text) }
        + (anime.ending_themes ?? []).compactMap { 动画主题曲(malID: $0.id, 种类: .片尾曲, 文本: $0.text) }
    let titles = [anime.alternative_titles?.ja, anime.title, anime.alternative_titles?.en].compactMap { $0 }.filter { !$0.isEmpty }

    if needsThemes {
        var themes: [String: 进度.值] = [:]
        var matched: [(动画主题曲, AppleMusic主题曲匹配.候选)] = []
        // 只查未找到时，上次找到的直接沿用
        let previous = 只查未找到 ? progress.作品[key]?.主题曲 ?? [:] : [:]
        let pending = songs.filter { previous[String($0.id)].map { $0 == .无 } ?? true }
        for song in songs where !pending.contains(where: { $0.id == song.id }) { themes[String(song.id)] = previous[String(song.id)] }
        if !pending.isEmpty {
            guard let found = await 匹配(pending, 作品标题: titles, 名称: "\(malID)", malID: malID) else { return false }
            for song in pending { themes[String(song.id)] = 进度.值(found[song.id]) }
            matched = pending.compactMap { song in found[song.id].map { (song, $0) } }
            print("\(name)（\(malID)）：\(found.count)/\(pending.count)\(只查未找到 ? "（重查上次没找到的）" : "")")
            for song in pending where found[song.id] == nil {
                print("    没有：\(song.原标题 ?? song.标题) / \(song.歌手原名 ?? song.歌手)")
            }
        }
        let previousMisses = progress.作品[key]?.未找到 ?? [:]
        let previousLow = 只查未找到 ? progress.作品[key]?.低确信 : nil
        let previousRated = 只查未找到 ? progress.作品[key]?.已评确信 : nil
        let previousSuggestions = progress.作品[key]?.建议
        // 只查未找到时，插入曲上次找到的也要留着
        let previousInsertEntries = 只查未找到 ? progress.作品[key]?.插入曲 : nil
        progress.作品[key] = .init(
            检查时间: .now, 主题曲: themes, 规则版本: AppleMusic主题曲匹配.规则版本, 插入曲: previousInsertEntries
        )
        let texts = Dictionary(((anime.opening_themes ?? []) + (anime.ending_themes ?? [])).map { (String($0.id), $0.text) }, uniquingKeysWith: { a, _ in a })
        var misses: [String: 进度.歌曲信息] = [:]
        for song in songs where themes[String(song.id)] == .无 {
            misses[String(song.id)] = await 未找到信息(song, 原文: texts[String(song.id)])
        }
        // 上次记下的插入曲信息留着，插入曲在下面重新记
        for (id, info) in previousMisses where info.种类 == "in" { misses[id] = info }
        progress.作品[key]?.未找到 = misses
        progress.作品[key]?.低确信 = previousLow
        progress.作品[key]?.已评确信 = previousRated
        await 记录确信度(key, matched, 作品标题: titles, 原文: texts, 匹配器: 匹配器)
        // 插入曲的建议在下面重新记
        progress.作品[key]?.建议 = (previousSuggestions ?? [:]).filter { (Int($0.key) ?? 0) < 0 }
        await 记下建议(key)
    }
    progress.作品[key]?.作品名 = name
    记下Bangumi音乐(key, malID)

    guard let inserts = await 插入曲(malID, 片头片尾: songs) else { return true }
    if inserts.isEmpty {
        progress.作品[key]?.插入曲 = []
        if needsThemes, !只查未找到 { progress.作品[key]?.已评确信 = true }
        return true
    }
    let previousInserts = 只查未找到 ? Dictionary((progress.作品[key]?.插入曲 ?? []).map { ($0.编号, $0) }, uniquingKeysWith: { a, _ in a }) : [:]
    let pendingInserts = inserts.filter { previousInserts[-$0.id].map { $0.值 == .无 } ?? true }
    guard let found = pendingInserts.isEmpty ? [:] : await 匹配(pendingInserts, 作品标题: titles, 名称: "\(malID) 插入曲", malID: malID) else { return true }
    // 插入曲只有罗马字，门槛比片头片尾严：歌名、歌手都要几乎一致；和片头片尾是同一首的不算
    let themeTracks = Set(progress.作品[key]?.主题曲.values.compactMap { value -> Int? in
        if case .歌曲(let id, _, _, _, _) = value { id } else { nil }
    } ?? [])
    var entries: [进度.插入曲条目] = []
    for song in inserts {
        if let kept = previousInserts[-song.id], kept.值 != .无, !pendingInserts.contains(where: { $0.id == song.id }) {
            entries.append(kept)
            continue
        }
        var item = found[song.id]
        if let candidate = item {
            let score = await 匹配器.打分(candidate, song: song, 作品标题: titles)
            let strict = score.歌名 >= 0.95 && score.歌手 >= 0.85
            if !(strict || (score.读音命中 && score.可接受)) || themeTracks.contains(candidate.trackId) { item = nil }
        }
        entries.append(.init(编号: -song.id, 歌名: song.标题, 歌手: song.歌手, 值: 进度.值(item)))
    }
    progress.作品[key]?.插入曲 = entries
    var misses = (progress.作品[key]?.未找到 ?? [:]).filter { $0.value.种类 != "in" }
    for song in inserts where entries.contains(where: { $0.编号 == -song.id && $0.值 == .无 }) {
        misses[String(song.id)] = await 未找到信息(song, 原文: nil)
    }
    progress.作品[key]?.未找到 = misses
    await 记录确信度(key, pendingInserts.compactMap { song in
        guard let item = found[song.id], entries.contains(where: { $0.编号 == -song.id && $0.值 != .无 }) else { return nil }
        return (song, item)
    }, 作品标题: titles, 原文: [:], 匹配器: 匹配器)
    await 记下建议(key)
    if needsThemes, !只查未找到 { progress.作品[key]?.已评确信 = true }
    记下Bangumi音乐(key, malID)
    print("  插入曲：\(entries.filter { $0.值 != .无 }.count)/\(entries.count)")
    for entry in entries {
        if case let .歌曲(_, _, title, artist, _) = entry.值 {
            print("    \(entry.歌名) / \(entry.歌手) → \(title) / \(artist)")
        }
    }
    return true
}

/// 给匹配到的歌曲打分，不是几乎一致的记下来。打分要用罗马字名称，先补上。
func 记录确信度(
    _ key: String, _ pairs: [(动画主题曲, AppleMusic主题曲匹配.候选)], 作品标题: [String], 原文: [String: String], 匹配器: AppleMusic主题曲匹配
) async {
    guard !pairs.isEmpty else { return }
    await 匹配器.补充罗马字名称(pairs.map(\.1.trackId))
    var low = progress.作品[key]?.低确信 ?? [:]
    for (song, item) in pairs {
        let score = await 匹配器.打分(item, song: song, 作品标题: 作品标题)
        if score.确信 {
            low[String(song.id)] = nil
        } else {
            low[String(song.id)] = .init(
                信息: await 未找到信息(song, 原文: 原文[String(song.id)]), 歌名分: score.歌名, 歌手分: score.歌手, 专辑: item.专辑
            )
        }
    }
    progress.作品[key]?.低确信 = low
}

func 记下建议(_ key: String) async {
    var suggestions = progress.作品[key]?.建议 ?? [:]
    for (id, (item, score)) in await 匹配器.取走建议() {
        suggestions[String(id)] = .init(值: 进度.值(item), 歌名分: score.歌名, 歌手分: score.歌手, 专辑: item.专辑)
    }
    progress.作品[key]?.建议 = suggestions
}

func 记下Bangumi音乐(_ key: String, _ malID: Int) {
    if let list = Bangumi读取结果[malID] { progress.作品[key]?.Bangumi音乐 = list }
}

func 未找到信息(_ song: 动画主题曲, 原文: String?) async -> 进度.歌曲信息 {
    .init(
        种类: song.种类.rawValue, 序号: song.序号, 标题: song.标题, 原标题: song.原标题, 歌手: song.歌手, 歌手原名: song.歌手原名,
        歌手日文名: song.歌手原名 == nil ? await 匹配器.查过的日文歌手名(song.歌手) : nil, 话数: song.话数, 原文: 原文
    )
}

// MARK: AnisongDB

struct AnisongDB歌曲: Decodable {
    struct 关联: Decodable { let myanimelist: Int? }
    struct 艺人: Decodable { let names: [String]?; let members: [艺人]? }
    let annSongId: Int
    let songType: String
    let songName: String
    let songArtist: String
    let isDub: Bool?
    let isRebroadcast: Bool?
    let linked_ids: 关联?
    let artists: [艺人]?
}

/// 批量读到的 AnisongDB 歌曲（MAL ID → 歌曲），没有歌曲的作品是空数组。
var AnisongDB缓存: [Int: [AnisongDB歌曲]] = [:]

/// 一次读几部作品的 AnisongDB 歌曲。长篇作品的数据很大，可能超时，多试几次；失败时返回 nil。
func 读取AnisongDB(_ malIDs: [Int]) async -> [AnisongDB歌曲]? {
    var request = URLRequest(url: URL(string: "https://anisongdb.com/api/mal_ids_request")!, timeoutInterval: 90)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("PaperVN", forHTTPHeaderField: "User-Agent")
    request.httpBody = try? JSONSerialization.data(withJSONObject: ["mal_ids": malIDs])
    for attempt in 0..<3 {
        try? await Task.sleep(for: .seconds(1 + Double(attempt) * 10))
        if let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let list = try? JSONDecoder().decode([AnisongDB歌曲].self, from: data) {
            主题曲训练数据.追加(data, 到: "AnisongDB.jsonl")
            return list
        }
    }
    return nil
}

/// 预先批量读取接下来几部作品的插入曲，省掉逐部请求的等待。失败的不放进缓存，处理时再单独读。
func 预取AnisongDB(_ malIDs: [Int]) async {
    let missing = malIDs.filter { AnisongDB缓存[$0] == nil }
    guard !missing.isEmpty, let list = await 读取AnisongDB(missing) else { return }
    for id in missing { AnisongDB缓存[id] = [] }
    for song in list {
        if let id = song.linked_ids?.myanimelist, AnisongDB缓存[id] != nil { AnisongDB缓存[id]?.append(song) }
    }
}

/// 这部作品在 AnisongDB 上的插入曲（不含配音版、重播版，也不含和片头片尾同名的）。读取失败时返回 nil。
func 插入曲(_ malID: Int, 片头片尾: [动画主题曲]) async -> [动画主题曲]? {
    var list = AnisongDB缓存.removeValue(forKey: malID)
    if list == nil { list = await 读取AnisongDB([malID]) }
    guard let list else {
        print("  无法读取 AnisongDB \(malID)")
        return nil
    }
    let themeKeys = Set(片头片尾.flatMap { [$0.标题, $0.原标题].compactMap { $0 } }.map(主题曲文本.罗马字键))
    var seen = Set<Int>()
    return list.compactMap { song in
        guard song.linked_ids?.myanimelist == malID, song.songType == "Insert Song",
              song.isDub != true, song.isRebroadcast != true, seen.insert(song.annSongId).inserted,
              !song.songName.isEmpty, !themeKeys.contains(主题曲文本.罗马字键(song.songName)) else { return nil }
        func names(_ artist: AnisongDB歌曲.艺人) -> [String] { (artist.names ?? []) + (artist.members ?? []).flatMap(names) }
        let aliases = Array(Set((song.artists ?? []).flatMap(names)))
        return 动画主题曲(插入曲编号: song.annSongId, 标题: song.songName, 歌手: song.songArtist, 别名: aliases)
    }
}

if !只写文件 {
    var ids: [Int] = []
    if 指定作品.isEmpty {
        struct 映射: Decodable { struct 动画: Decodable { let works: [[JSONValue]] }; let anime: 动画 }
        enum JSONValue: Decodable {
            case int(Int), other
            init(from decoder: Decoder) throws {
                self = (try? decoder.singleValueContainer().decode(Int.self)).map(JSONValue.int) ?? .other
            }
        }
        let map = try JSONDecoder().decode(映射.self, from: Data(contentsOf: 作品映射URL))
        // 作品映射按热度排序，第二列是 MAL ID
        ids = map.anime.works.compactMap { row in
            guard row.count > 1, case .int(let id) = row[1] else { return nil }
            return id
        }
        ids = Array(ids.prefix(作品数))
        for value in 季度 { ids += await 季度作品(value) }
    } else {
        ids = 指定作品
    }
    var seen = Set<Int>()
    ids = ids.filter { seen.insert($0).inserted }
    print("共 \(ids.count) 部作品，已有进度 \(progress.作品.count) 部")

    if 指定作品.isEmpty { await 换成完整版() }

    var changed = 0
    for (index, id) in ids.enumerated() {
        if index % 50 == 0 { await 预取AnisongDB(Array(ids[index..<min(index + 50, ids.count)])) }
        if let 时限分钟, Date().timeIntervalSince(开始时间) > 时限分钟 * 60 {
            print("到达时限，停在第 \(index) 部")
            break
        }
        if await 处理(id) {
            changed += 1
            if changed % 5 == 0 { 存储(progress) }
        }
    }
    存储(progress)
    if 指定作品.isEmpty { await 换成完整版() }
}

// MARK: 人工校正与写出

struct 校正文件: Decodable { let songs: [String: Int?] }
let corrections = (try? JSONDecoder().decode(校正文件.self, from: Data(contentsOf: 校正URL)))?.songs ?? [:]
let needLookup = corrections.values.compactMap { $0 }.filter { progress.校正曲目[String($0)] == nil }
if !needLookup.isEmpty, let found = try? await 匹配器.查询曲目(needLookup, 地区: "jp") {
    for id in needLookup {
        if let item = found[id] { progress.校正曲目[String(id)] = 进度.值(item) } else { print("校正里的曲目 \(id) 在日本商店查不到") }
    }
    存储(progress)
}

// Apple Music API 的检索结果不带歌手编号，写出前批量补上（App 在用户所在地区找同一位歌手的歌时要用）
if 令牌 != nil || 私有配置("APPLE_MUSIC_KEY_ID").isEmpty == false {
    let 补全器 = 令牌 == nil
        ? AppleMusic主题曲匹配(每分钟请求上限: 120, 最小间隔: 0.5, 限流重试次数: 8, 限流等待秒数: 30, 开发者令牌: AppleMusic开发者令牌(), 打印失败: true)
        : 匹配器
    var missing = Set<Int>()
    for work in progress.作品.values {
        for value in Array(work.主题曲.values) + (work.插入曲 ?? []).map(\.值) {
            if case let .歌曲(trackId, nil, _, _, _) = value { missing.insert(trackId) }
        }
    }
    if !missing.isEmpty, let found = try? await 补全器.查询曲目(Array(missing), 地区: "jp") {
        func 补全(_ value: 进度.值) -> 进度.值 {
            guard case let .歌曲(trackId, nil, title, artist, artwork) = value, let artistId = found[trackId]?.artistId else { return value }
            return .歌曲(trackId: trackId, artistId: artistId, 歌名: title, 歌手: artist, 封面: artwork)
        }
        for (key, work) in progress.作品 {
            progress.作品[key]?.主题曲 = work.主题曲.mapValues(补全)
            progress.作品[key]?.插入曲 = work.插入曲?.map { .init(编号: $0.编号, 歌名: $0.歌名, 歌手: $0.歌手, 值: 补全($0.值)) }
        }
        存储(progress)
        print("补上 \(found.values.filter { $0.artistId != nil }.count)/\(missing.count) 首歌曲的歌手编号")
    }
}

var songs: [String: 进度.值] = [:]
/// 作品（MAL ID）→ 找到了 Apple Music 歌曲的插入曲（键是插入曲编号的相反数，和 songs 里的键一致）。
var inserts: [String: [String]] = [:]
for (malID, work) in progress.作品 {
    for (id, value) in work.主题曲 { songs[id] = value }
    for entry in work.插入曲 ?? [] where entry.值 != .无 {
        songs[String(-entry.编号)] = entry.值
        inserts[malID, default: []].append(String(-entry.编号))
    }
}
for (id, track) in corrections {
    if let track {
        if let value = progress.校正曲目[String(track)] { songs[id] = value }
    } else {
        songs[id] = .无
    }
}

// 每行一首，方便比较两个版本的差别；"version" 放在最前面，App 只读文件开头就能知道版本
let encoder = JSONEncoder()
encoder.outputFormatting = [.withoutEscapingSlashes]
var lines: [String] = []
for id in songs.keys.sorted(by: { Int($0) ?? 0 < Int($1) ?? 0 }) {
    let value = String(data: try encoder.encode(songs[id]!), encoding: .utf8)!
    lines.append("\"\(id)\":\(value)")
}
let body = lines.joined(separator: ",\n")
let insertLines = inserts.keys.sorted { Int($0) ?? 0 < Int($1) ?? 0 }.map { key in
    "\"\(key)\":[\(inserts[key]!.joined(separator: ","))]"
}
let insertBody = insertLines.joined(separator: ",\n")
let digest = SHA256.hash(data: Data((body + insertBody).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
let formatter = DateFormatter()
formatter.dateFormat = "yyyyMMdd"
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
let version = "\(formatter.string(from: .now))-\(digest)"
let text = "{\"version\":\"\(version)\",\"format\":1,\"songs\":{\n\(body)\n},\"inserts\":{\n\(insertBody)\n}}\n"
try text.write(to: 输出URL, atomically: true, encoding: .utf8)

let hits = songs.values.filter { $0 != .无 }.count
print("已写出 \(输出URL.lastPathComponent)：版本 \(version)，\(progress.作品.count) 部作品，\(songs.count) 首歌曲（其中插入曲 \(inserts.values.map(\.count).reduce(0, +)) 首），\(hits) 首在 Apple Music 里")

// MARK: 未匹配清单

/// 没找到 Apple Music 歌曲的主题曲，按作品热度排序，由 deploy-themesongs.sh 上传到管理后台人工匹配。
/// 之前处理时没记下歌曲信息的作品（旧版本的进度）在这里补读 MAL。
struct 未匹配项: Encodable {
    let key: String
    let malID: Int
    let anime: String?
    let rank: Int?
    let kind: String
    let number: String?
    let title: String
    let originalTitle: String?
    let artist: String
    let originalArtist: String?
    let artistJapanese: String?
    let episodes: String?
    let text: String?
    /// 匹配到了但不是几乎一致时，自动匹配的结果，等人工确认。
    var autoMatch: 自动匹配结果? = nil
    /// Bangumi 上这部作品的音乐条目，后台人工匹配时轻点检索。
    var bangumiMusic: [Bangumi音乐项]? = nil
}

struct Bangumi音乐项: Encodable {
    let relation: String
    let name: String
}

struct 自动匹配结果: Encodable {
    let trackId: Int
    let artistId: Int?
    let title: String
    let artist: String
    let album: String
    let artwork: String?
    let titleScore: Double
    let artistScore: Double
    /// 只是建议，没有进映射。
    var suggested: Bool? = nil
}

func 作品热度排名() -> [Int: Int] {
    struct 映射: Decodable { struct 动画: Decodable { let works: [[值]] }; let anime: 动画 }
    enum 值: Decodable {
        case int(Int), other
        init(from decoder: Decoder) throws {
            self = (try? decoder.singleValueContainer().decode(Int.self)).map(值.int) ?? .other
        }
    }
    guard let data = try? Data(contentsOf: 作品映射URL), let map = try? JSONDecoder().decode(映射.self, from: data) else { return [:] }
    var ranks: [Int: Int] = [:]
    for (index, row) in map.anime.works.enumerated() where row.count > 1 {
        if case .int(let id) = row[1], ranks[id] == nil { ranks[id] = index + 1 }
    }
    return ranks
}

var backfilled = 0
for (key, work) in progress.作品 {
    let missing = work.主题曲.filter { $0.value == .无 && corrections[$0.key] == nil }.map(\.key)
    let needsInfo = missing.contains { work.未找到?[$0] == nil } || (work.作品名 == nil && (!missing.isEmpty || work.插入曲?.contains { $0.值 == .无 } == true))
    guard needsInfo, let malID = Int(key) else { continue }
    guard let data = await MAL请求("anime/\(malID)?fields=alternative_titles,opening_themes,ending_themes"),
          let anime = try? JSONDecoder().decode(MAL作品.self, from: data) else { continue }
    progress.作品[key]?.作品名 = anime.alternative_titles?.ja.flatMap { $0.isEmpty ? nil : $0 } ?? anime.title
    var misses = work.未找到 ?? [:]
    let themes = (anime.opening_themes ?? []).map { ($0, 动画主题曲.种类.片头曲) } + (anime.ending_themes ?? []).map { ($0, 动画主题曲.种类.片尾曲) }
    for (theme, kind) in themes where missing.contains(String(theme.id)) && misses[String(theme.id)] == nil {
        if let song = 动画主题曲(malID: theme.id, 种类: kind, 文本: theme.text) {
            misses[String(theme.id)] = await 未找到信息(song, 原文: theme.text)
        }
    }
    progress.作品[key]?.未找到 = misses
    backfilled += 1
}
if backfilled > 0 {
    存储(progress)
    print("补读了 \(backfilled) 部作品的主题曲信息")
}

// 之前处理时没打过分的作品，补上确信度（要读 MAL 的主题曲文本，再查曲目的专辑）
if 令牌 != nil || 私有配置("APPLE_MUSIC_KEY_ID").isEmpty == false {
    let 评分器 = 令牌 == nil
        ? AppleMusic主题曲匹配(每分钟请求上限: 120, 最小间隔: 0.5, 限流重试次数: 8, 限流等待秒数: 30, 开发者令牌: AppleMusic开发者令牌(), 打印失败: true)
        : 匹配器
    func 曲目编号(_ value: 进度.值) -> Int? {
        if case .歌曲(let id, _, _, _, _) = value { id } else { nil }
    }
    let pending = progress.作品.filter { $0.value.已评确信 != true }
    let trackIds = Array(Set(pending.values.flatMap { work in
        work.主题曲.values.compactMap(曲目编号) + (work.插入曲 ?? []).compactMap { 曲目编号($0.值) }
    }))
    if !trackIds.isEmpty, let details = try? await 评分器.查询曲目(trackIds, 地区: "jp") {
        var rated = 0
        for (key, work) in pending {
            guard let malID = Int(key),
                  let data = await MAL请求("anime/\(malID)?fields=alternative_titles,opening_themes,ending_themes"),
                  let anime = try? JSONDecoder().decode(MAL作品.self, from: data) else { continue }
            let titles = [anime.alternative_titles?.ja, anime.title, anime.alternative_titles?.en].compactMap { $0 }.filter { !$0.isEmpty }
            let themes = (anime.opening_themes ?? []).map { ($0, 动画主题曲.种类.片头曲) } + (anime.ending_themes ?? []).map { ($0, 动画主题曲.种类.片尾曲) }
            var pairs: [(动画主题曲, AppleMusic主题曲匹配.候选)] = []
            var texts: [String: String] = [:]
            for (theme, kind) in themes {
                guard let song = 动画主题曲(malID: theme.id, 种类: kind, 文本: theme.text),
                      let track = work.主题曲[String(theme.id)].flatMap(曲目编号), let item = details[track] else { continue }
                pairs.append((song, item))
                texts[String(theme.id)] = theme.text
            }
            for entry in work.插入曲 ?? [] {
                guard let track = 曲目编号(entry.值), let item = details[track] else { continue }
                pairs.append((动画主题曲(插入曲编号: entry.编号, 标题: entry.歌名, 歌手: entry.歌手, 别名: []), item))
            }
            await 记录确信度(key, pairs, 作品标题: titles, 原文: texts, 匹配器: 评分器)
            progress.作品[key]?.已评确信 = true
            rated += 1
            if rated % 50 == 0 { 存储(progress) }
        }
        存储(progress)
        print("补上了 \(rated) 部作品的确信度")
    }
}

let ranks = 作品热度排名()
var unmatched: [未匹配项] = []
for (key, work) in progress.作品 {
    guard let malID = Int(key) else { continue }
    var pending = work.主题曲.filter { $0.value == .无 }.map(\.key)
    pending += (work.插入曲 ?? []).filter { $0.值 == .无 }.map { String(-$0.编号) }
    for id in pending where corrections[id] == nil {
        // 插入曲的信息在进度的插入曲条目里也有（罗马字）
        let insert = work.插入曲?.first { String(-$0.编号) == id }
        guard let info = work.未找到?[id] ?? insert.map({ 进度.歌曲信息(种类: "in", 标题: $0.歌名, 歌手: $0.歌手) }) else { continue }
        unmatched.append(.init(
            key: id, malID: malID, anime: work.作品名, rank: ranks[malID], kind: info.种类, number: info.序号,
            title: info.标题, originalTitle: info.原标题, artist: info.歌手, originalArtist: info.歌手原名,
            artistJapanese: info.歌手日文名, episodes: info.话数, text: info.原文,
            autoMatch: work.建议?[id].flatMap { suggestion in
                guard case let .歌曲(trackId, artistId, title, artist, artwork) = suggestion.值 else { return nil }
                return .init(
                    trackId: trackId, artistId: artistId, title: title, artist: artist, album: suggestion.专辑, artwork: artwork,
                    titleScore: suggestion.歌名分, artistScore: suggestion.歌手分, suggested: true
                )
            }
        ))
    }
    for (id, low) in work.低确信 ?? [:] where corrections[id] == nil {
        let value = work.主题曲[id] ?? work.插入曲?.first { String(-$0.编号) == id }?.值
        guard case let .歌曲(trackId, artistId, title, artist, artwork)? = value else { continue }
        let info = low.信息
        unmatched.append(.init(
            key: id, malID: malID, anime: work.作品名, rank: ranks[malID], kind: info.种类, number: info.序号,
            title: info.标题, originalTitle: info.原标题, artist: info.歌手, originalArtist: info.歌手原名,
            artistJapanese: info.歌手日文名, episodes: info.话数, text: info.原文,
            autoMatch: .init(
                trackId: trackId, artistId: artistId, title: title, artist: artist, album: low.专辑, artwork: artwork,
                titleScore: low.歌名分, artistScore: low.歌手分
            )
        ))
    }
}
unmatched = unmatched.map { item in
    var item = item
    item.bangumiMusic = progress.作品[String(item.malID)]?.Bangumi音乐?.map { .init(relation: $0.关系, name: $0.名称) }
    return item
}
unmatched.sort { ($0.rank ?? .max, $0.key) < ($1.rank ?? .max, $1.key) }
struct 未匹配清单: Encodable { let version: String; let generatedAt: Date; let items: [未匹配项] }
let missesEncoder = JSONEncoder()
missesEncoder.dateEncodingStrategy = .iso8601
missesEncoder.outputFormatting = [.withoutEscapingSlashes]
let missesURL = 进度URL.deletingLastPathComponent().appending(path: "PaperVNThemeSongMisses.json")
try missesEncoder.encode(未匹配清单(version: version, generatedAt: .now, items: unmatched)).write(to: missesURL, options: .atomic)
let lowCount = unmatched.filter { $0.autoMatch != nil }.count
let suggestedCount = unmatched.filter { $0.autoMatch?.suggested == true }.count
print("已写出待人工处理清单：\(unmatched.count) 首（没匹配到 \(unmatched.count - lowCount) 首，其中插入曲 \(unmatched.filter { $0.kind == "in" && $0.autoMatch == nil }.count) 首；确信度不高 \(lowCount - suggestedCount) 首；只有建议 \(suggestedCount) 首）")
