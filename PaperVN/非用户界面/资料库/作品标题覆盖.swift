import Foundation
import Observation

/// 管理后台“作品标题”里手动设置的标题：平台上的写法不标准、各平台之间不一致时，指定作品在 App 里某种语言显示的名字。
/// 启动和回到前台时静默读取（按 ETag，没有变化时不下载内容），读取失败时继续使用上次的。
///
/// 后台用任一平台上的 ID 指定作品，这里按作品映射找到资料库里的编号（“mal-anime:5114”“vn:v17”）。
/// 填写的语言替换平台上的标题，没填的语言照常使用平台上的标题。
@MainActor
@Observable
final class 作品标题覆盖 {
    static let shared = 作品标题覆盖()

    private static let 地址 = URL(string: "https://papervn.jizpaper.com/library-matches/title-overrides")!
    /// 回到前台时最多每 30 分钟读取一次。
    private static let 检查间隔: TimeInterval = 30 * 60

    nonisolated struct 条目: Codable, Sendable {
        let type: String
        let platform: String
        let platformID: String
        /// original（原名）、latin（原名的罗马字）或语言代码 → 标题。
        let titles: [String: String]
    }

    private struct 缓存: Codable {
        var etag: String?
        var items: [条目]
    }

    private var 缓存内容: 缓存
    /// 分组（anime、manga、visualNovel）+ 平台 + ID → 标题。
    @ObservationIgnored private var 平台索引: [String: [String: String]] = [:]
    /// 资料库编号 → 标题。作品映射换成新版本后重建。
    @ObservationIgnored private var 编号索引: [String: [String: String]] = [:]
    @ObservationIgnored private var 编号索引的映射版本: String?
    @ObservationIgnored private var 上次检查: Date?

    private init() {
        缓存内容 = (try? Data(contentsOf: Self.缓存地址)).flatMap { try? JSONDecoder().decode(缓存.self, from: $0) }
            ?? 缓存(etag: nil, items: [])
        重建平台索引()
    }

    /// 正在使用的版本（服务器的 ETag，例如“"to-12"”），诊断时用。
    var 版本: String? { 缓存内容.etag }

    func 检查更新(忽略间隔: Bool = false) async {
        if !忽略间隔, let 上次检查, Date.now.timeIntervalSince(上次检查) < Self.检查间隔 { return }
        上次检查 = .now
        var request = URLRequest(url: Self.地址, timeoutInterval: 10)
        if let etag = 缓存内容.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        struct 响应: Decodable { let items: [条目] }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let value = try? JSONDecoder().decode(响应.self, from: data) else { return }
        // 换掉缓存内容时，读取过标题的界面会重新显示
        缓存内容 = 缓存(etag: http.value(forHTTPHeaderField: "ETag"), items: value.items)
        重建平台索引()
        if let data = try? JSONEncoder().encode(缓存内容) {
            try? FileManager.default.createDirectory(at: Self.缓存地址.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.缓存地址, options: .atomic)
        }
    }

    /// 按后台的设置替换作品的标题。`作品键` 是资料库里的编号（视觉小说是“vn:v17”）。
    func 应用(_ titles: [用户多语言标题]?, 作品键: String, 类型: 作品类型) -> [用户多语言标题]? {
        guard !缓存内容.items.isEmpty, let override = 查找(作品键: 作品键, 类型: 类型) else { return titles }
        return Self.替换(titles ?? [], 覆盖: override)
    }

    /// 后台为这部作品设置的标题，语言 → 标题。
    func 查找(作品键 key: String, 类型 type: 作品类型) -> [String: String]? {
        guard !缓存内容.items.isEmpty else { return nil }
        let group = Self.分组(type)
        if type == .visualNovel {
            return 平台索引[Self.索引键(group, "vndb", String(key.dropFirst("vn:".count)))]
        }
        if 编号索引的映射版本 != 作品映射.版本 { 重建编号索引() }
        if let value = 编号索引[key] { return value }
        // 映射里没有的作品：编号本身带着平台 ID（“mal-anime:5114”“aniList-manga:101444”）
        for platform in [资料库平台.myAnimeList, .aniList, .bangumi, .annict] {
            if let id = Self.编号里的平台ID(key, platform) ?? 作品映射.平台ID(key, 平台: platform, 类型: type),
               let value = 平台索引[Self.索引键(group, platform.rawValue, id)] {
                return value
            }
        }
        return nil
    }

    /// 填写的语言替换同语言的标题：原名的语言是这种语言时改原名的文字，否则去掉这种语言的其他标题，加上设置的标题。
    /// original 只改原名的文字（语言不变），latin 改原名的罗马字。设置的标题都算官方标题。
    nonisolated static func 替换(_ titles: [用户多语言标题], 覆盖 override: [String: String]) -> [用户多语言标题] {
        var result = titles
        func 改原名(title: String? = nil, latin: String? = nil) {
            if let index = result.firstIndex(where: \.main) {
                let main = result[index]
                result[index] = 用户多语言标题(
                    lang: main.lang, title: title ?? main.title, latin: latin ?? main.latin, official: true, main: true
                )
            } else if let text = title ?? latin {
                // 没有原名时补一个；只有罗马字时和 `作品多语言标题.生成` 一样不当作日文
                result.insert(用户多语言标题(
                    lang: title == nil ? "ja-Latn" : "und", title: text, latin: latin, official: true, main: true
                ), at: 0)
            }
        }
        for (lang, text) in override.sorted(by: { $0.key < $1.key }) where lang != "original" && lang != "latin" {
            result.removeAll { $0.lang == lang && !$0.main }
            if result.contains(where: { $0.main && $0.lang == lang }) {
                改原名(title: text)
            } else {
                result.append(用户多语言标题(lang: lang, title: text, latin: nil, official: true, main: false))
            }
        }
        if override["original"] != nil || override["latin"] != nil {
            改原名(title: override["original"], latin: override["latin"])
        }
        return result
    }

    // MARK: 索引

    private func 重建平台索引() {
        平台索引 = [:]
        for item in 缓存内容.items {
            guard let type = 作品类型(rawValue: item.type) else { continue }
            平台索引[Self.索引键(Self.分组(type), item.platform, item.platformID)] = item.titles
        }
        编号索引的映射版本 = nil
    }

    /// 后台填的 ID 按作品映射换成资料库里的编号。
    private func 重建编号索引() {
        编号索引 = [:]
        for item in 缓存内容.items {
            guard let type = 作品类型(rawValue: item.type), type != .visualNovel,
                  let platform = 资料库平台(rawValue: item.platform) else { continue }
            if let key = 作品映射.查找(platform, 平台ID: item.platformID, 类型: type)?.键 {
                编号索引[key] = item.titles
            }
        }
        编号索引的映射版本 = 作品映射.版本
    }

    private nonisolated static func 分组(_ type: 作品类型) -> String {
        switch type {
        case .anime: "anime"
        case .visualNovel: "visualNovel"
        default: "manga"
        }
    }

    private nonisolated static func 索引键(_ group: String, _ platform: String, _ id: String) -> String {
        "\(group)|\(platform)|\(id)"
    }

    /// “mal-anime:5114” → MAL 的 5114；“aniList-manga:101444” → AniList 的 101444。
    private nonisolated static func 编号里的平台ID(_ key: String, _ platform: 资料库平台) -> String? {
        let prefix = platform == .myAnimeList ? "mal-" : "\(platform.rawValue)-"
        guard key.hasPrefix(prefix), let colon = key.firstIndex(of: ":") else { return nil }
        return String(key[key.index(after: colon)...])
    }

    private static var 缓存地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "PaperVN Sync", directoryHint: .isDirectory)
            .appending(path: "作品标题.json")
    }
}

extension 本地资料库条目 {
    /// 按后台“作品标题”的设置替换过的标题，显示时用它。
    var 显示用多语言标题: [用户多语言标题]? {
        作品标题覆盖.shared.应用(多语言标题, 作品键: id, 类型: 类型)
    }
}

extension 用户列表项目 {
    /// 按后台“作品标题”的设置替换过的标题，显示时用它。
    var 显示用多语言标题: [用户多语言标题]? {
        作品标题覆盖.shared.应用(vn.titles, 作品键: 本地资料库条目.视觉小说ID(id), 类型: .visualNovel)
    }
}
