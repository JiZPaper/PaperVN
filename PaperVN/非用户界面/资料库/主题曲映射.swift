import CryptoKit
import Foundation

/// 主题曲与 Apple Music 歌曲的对应表（PaperVNThemeSongMap.json）。由 `Tools/生成主题曲映射.sh` 预先匹配生成，
/// App 安装包里预装一份，之后静默下载更新。键是 MAL 的主题曲编号，值是日本商店里的歌曲；
/// 值为 0 表示生成时确认 Apple Music 里没有这首歌。表里没有的主题曲（新番、冷门作品）才在 App 里现场匹配。
///
/// 插入曲来自 AnisongDB，只收录找到了 Apple Music 歌曲的：`inserts` 按作品（MAL ID）列出插入曲的键，
/// 键是 AnisongDB 歌曲编号的相反数，和 `songs` 里的键对应。
///
/// 文件格式：`{"version": "20261031-…", "format": 1, "songs": {"16132": [曲目编号, 歌手编号, "歌名", "歌手", "封面地址"], "21189": 0, "-11014": […]},
/// "inserts": {"9253": [-11014]}}`
nonisolated enum 主题曲映射 {
    enum 条目: Sendable {
        case 歌曲(AppleMusic主题曲匹配.候选)
        /// 生成映射时确认 Apple Music 里没有。
        case 无
    }

    private struct 文件: Decodable {
        let version: String
        let songs: [String: 值]
        let inserts: [String: [Int]]?

        enum 值: Decodable {
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
                    trackId: trackId, artistId: artistId,
                    歌名: try container.decode(String.self), 歌手: try container.decode(String.self),
                    封面: try container.decodeIfPresent(String.self)
                )
            }
        }
    }

    /// 管理后台人工匹配的结果（`/library-matches/theme-song-overrides`）：优先于映射，也能纠正自动配错的歌。
    /// song 的写法和映射里相同，0 表示确认 Apple Music 里没有。
    struct 人工显示信息: Decodable, Sendable {
        let title: String
        let artist: String
        let album: String?
        let episodes: String?
    }

    private struct 人工匹配文件: Decodable {
        struct 项: Decodable {
            let key: String
            let malID: Int
            let kind: String
            let song: 文件.值
            /// 数据维护添加的歌曲：MAL 和映射里都没有，按 `kind` 加到作品的主题曲里。
            let added: Bool?
            /// Apple Music 里没有时用户填写、经审核的歌曲信息，显示在详情页。
            let display: 人工显示信息?
        }
        let items: [项]
    }

    private struct 表: Sendable {
        let 版本: String?
        let 条目: [Int: 条目]
        var 插入曲: [Int: [Int]] = [:]
    }

    private static let 锁 = NSLock()
    nonisolated(unsafe) private static var 已载入: 表?
    /// 第一项是主题曲编号 → 条目，第二项是作品（MAL ID）→ 人工匹配的插入曲。
    nonisolated(unsafe) private static var 已载入的人工匹配: (条目: [Int: 条目], 插入曲: [Int: [Int]])?

    /// 数据维护添加的歌曲的种类（片头曲、片尾曲也可能是用户添加的）。
    nonisolated(unsafe) private static var 已载入的添加种类: [Int: 动画主题曲.种类] = [:]
    nonisolated(unsafe) private static var 已载入的显示信息: [Int: 人工显示信息] = [:]

    /// 用户填写的、不在 Apple Music 里的歌曲信息。
    static func 显示信息(_ 主题曲编号: Int) -> 人工显示信息? {
        _ = 人工匹配
        return 锁.withLock { 已载入的显示信息[主题曲编号] }
    }

    private static var 人工匹配: (条目: [Int: 条目], 插入曲: [Int: [Int]]) {
        锁.lock()
        defer { 锁.unlock() }
        if let 已载入的人工匹配 { return 已载入的人工匹配 }
        let loaded = 载入人工匹配((try? Data(contentsOf: 主题曲映射存储.人工匹配URL)) ?? Data())
        已载入的人工匹配 = loaded
        return loaded
    }

    private static var 数据: 表 {
        锁.lock()
        defer { 锁.unlock() }
        if let 已载入 { return 已载入 }
        let loaded = 载入(主题曲映射存储.当前URL)
        已载入 = loaded
        return loaded
    }

    private static func 载入(_ url: URL?) -> 表 {
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(文件.self, from: data) else { return 表(版本: nil, 条目: [:]) }
        var entries: [Int: 条目] = [:]
        entries.reserveCapacity(file.songs.count)
        for (key, value) in file.songs {
            guard let id = Int(key) else { continue }
            entries[id] = 转换(value)
        }
        var inserts: [Int: [Int]] = [:]
        for (key, ids) in file.inserts ?? [:] {
            if let malID = Int(key) { inserts[malID] = ids }
        }
        return 表(版本: file.version, 条目: entries, 插入曲: inserts)
    }

    private static func 转换(_ value: 文件.值) -> 条目 {
        switch value {
        case .无:
            .无
        case let .歌曲(trackId, artistId, title, artist, artwork):
            .歌曲(.init(
                trackId: trackId, artistId: artistId, 曲名: title, 歌手: artist, 专辑: "", 发行日期: "", 可播放: true,
                封面: artwork.flatMap(URL.init(string:)),
                链接: URL(string: "https://music.apple.com/jp/song/\(trackId)")
            ))
        }
    }

    private static func 载入人工匹配(_ data: Data) -> (条目: [Int: 条目], 插入曲: [Int: [Int]]) {
        guard let file = try? JSONDecoder().decode(人工匹配文件.self, from: data) else { return ([:], [:]) }
        var entries: [Int: 条目] = [:]
        var inserts: [Int: [Int]] = [:]
        var 添加种类: [Int: 动画主题曲.种类] = [:]
        var 显示信息: [Int: 人工显示信息] = [:]
        for item in file.items {
            guard let id = Int(item.key) else { continue }
            entries[id] = 转换(item.song)
            if item.kind == "in" || item.added == true { inserts[item.malID, default: []].append(id) }
            if item.added == true, let kind = 动画主题曲.种类(rawValue: item.kind) { 添加种类[id] = kind }
            if let display = item.display { 显示信息[id] = display }
        }
        已载入的添加种类 = 添加种类
        已载入的显示信息 = 显示信息
        return (entries, inserts)
    }

    /// nil 表示映射里没有这首主题曲，需要现场匹配。后台人工匹配的优先。
    static func 查找(_ 主题曲编号: Int) -> 条目? { 人工匹配.条目[主题曲编号] ?? 数据.条目[主题曲编号] }

    static var 版本: String? { 数据.版本 }

    /// 这部作品在映射里的插入曲（都在 Apple Music 里找到了），按 AnisongDB 的顺序，后面是后台人工匹配的。名称先用日本商店的写法，界面显示的也是它。
    static func 插入曲(malID: Int) -> [动画主题曲] {
        let listed = 数据.插入曲[malID] ?? []
        let manual = (人工匹配.插入曲[malID] ?? []).filter { !listed.contains($0) }
        return (listed + manual).compactMap { key in
            if let display = 显示信息(key) {
                let kind = 锁.withLock { 已载入的添加种类[key] } ?? .插入曲
                return 动画主题曲(插入曲编号: -key, 标题: display.title, 歌手: display.artist, 别名: [], 种类: kind, 话数: display.episodes)
            }
            guard case .歌曲(let item)? = 查找(key) else { return nil }
            return 动画主题曲(插入曲编号: -key, 标题: item.曲名, 歌手: item.歌手, 别名: [], 种类: 锁.withLock { 已载入的添加种类[key] } ?? .插入曲)
        }
    }

    /// 映射里已有的结果，交给 `AppleMusic主题曲匹配`：有歌曲的给歌曲，确认没有的给 nil，不在映射里的不放进来。
    static func 已知结果(_ 歌曲: [动画主题曲]) -> [Int: AppleMusic主题曲匹配.候选?] {
        var known: [Int: AppleMusic主题曲匹配.候选?] = [:]
        for song in 歌曲 {
            switch 查找(song.id) {
            case .歌曲(let item)?: known[song.id] = .some(item)
            case .无?: known[song.id] = .some(nil)
            case nil: break
            }
        }
        return known
    }

    /// 下载了新的映射之后换用。
    static func 重新载入() async {
        let loaded = await Task.detached(priority: .utility) { 载入(主题曲映射存储.当前URL) }.value
        锁.withLock { 已载入 = loaded }
    }

    /// 读取到新的人工匹配之后换用。内容不完整时返回 false，继续用上次的。
    static func 换用人工匹配(_ data: Data) -> Bool {
        guard (try? JSONDecoder().decode(人工匹配文件.self, from: data)) != nil else { return false }
        let loaded = 载入人工匹配(data)
        锁.withLock { 已载入的人工匹配 = loaded }
        return true
    }

    /// 下载的映射能完整读取时返回它的版本。
    static func 验证(_ data: Data) throws -> String {
        let file = try JSONDecoder().decode(文件.self, from: data)
        guard !file.songs.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        return file.version
    }
}

/// 版本规则和作品映射相同（“构建日期-内容摘要”），下载的更新放在 Application Support。
nonisolated enum 主题曲映射存储 {
    static let 文件名 = "PaperVNThemeSongMap.json"

    static var 目录: URL {
        URL.applicationSupportDirectory.appending(path: "PaperVNThemeSongMap", directoryHint: .isDirectory)
    }

    static var 下载URL: URL { 目录.appending(path: 文件名) }

    /// 后台人工匹配的缓存（和接口返回的内容相同）。
    static var 人工匹配URL: URL { 目录.appending(path: "PaperVNThemeSongOverrides.json") }

    static var 内置URL: URL? { Bundle.main.url(forResource: "PaperVNThemeSongMap", withExtension: "json") }

    static var 当前URL: URL? {
        guard let 下载 = 作品映射存储.版本(of: 下载URL) else { return 内置URL }
        guard let 内置URL, let 内置 = 作品映射存储.版本(of: 内置URL) else { return 下载URL }
        return 作品映射存储.比内置的新(下载, 内置: 内置) ? 下载URL : 内置URL
    }

    /// App 更新后内置的映射不比下载的旧时，删掉不再使用的下载文件。
    static func 清理过期的下载() {
        guard FileManager.default.fileExists(atPath: 下载URL.path), 当前URL != 下载URL else { return }
        try? FileManager.default.removeItem(at: 下载URL)
    }
}

/// 主题曲映射的静默更新：启动和回到前台时检查清单（`https://papervn.jizpaper.com/themesongs/manifest.json`，
/// 由 `deploy/vps/deploy-themesongs.sh` 发布，最多每 6 小时一次），有新版本就下载、解压、核对摘要、确认能完整读取后换用。
/// 文件只有一两 MB，不需要后台下载会话；下载没完成时下次检查重新下载。不显示任何界面。
actor 主题曲映射更新 {
    static let shared = 主题曲映射更新()
    static let 支持的结构版本 = 1
    static var 清单地址: URL {
        #if DEBUG
        // 调试用：-ThemeSongMapManifestURL <地址> 改用本机的测试清单，并且每次启动都检查
        if let value = UserDefaults.standard.string(forKey: "ThemeSongMapManifestURL"), let url = URL(string: value) { return url }
        #endif
        return URL(string: "https://papervn.jizpaper.com/themesongs/manifest.json")!
    }
    private static let 检查间隔: TimeInterval = 6 * 60 * 60
    private static let 上次检查键 = "themeSongMapUpdate.lastCheck"

    private static var 人工匹配地址: URL {
        #if DEBUG
        // 调试用：-ThemeSongOverridesURL <地址> 改用本机的测试数据
        if let value = UserDefaults.standard.string(forKey: "ThemeSongOverridesURL"), let url = URL(string: value) { return url }
        #endif
        return URL(string: "https://papervn.jizpaper.com/library-matches/theme-song-overrides")!
    }
    /// 回到前台时最多每 30 分钟读取一次，和作品标题覆盖相同。
    private static let 人工匹配检查间隔: TimeInterval = 30 * 60
    private static let 人工匹配ETag键 = "themeSongOverrides.etag"

    private var 正在检查 = false
    private var 上次检查人工匹配: Date?

    func 检查更新() async {
        guard !正在检查 else { return }
        正在检查 = true
        defer { 正在检查 = false }
        await 检查人工匹配()
        主题曲映射存储.清理过期的下载()
        // 在这里（不在主线程）先读入映射，打开详情页时不用等
        _ = 主题曲映射.版本

        let defaults = UserDefaults.standard
        var ignoresInterval = false
        #if DEBUG
        ignoresInterval = defaults.string(forKey: "ThemeSongMapManifestURL") != nil
        #endif
        if !ignoresInterval, let last = defaults.object(forKey: Self.上次检查键) as? Date,
           Date().timeIntervalSince(last) < Self.检查间隔 {
            return
        }
        defaults.set(Date(), forKey: Self.上次检查键)

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: Self.清单地址, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let manifest = try? JSONDecoder().decode(作品映射清单.self, from: data),
              manifest.format == Self.支持的结构版本,
              manifest.file.wholeMatch(of: /PaperVNThemeSongMap-[A-Za-z0-9-]+\.json\.deflate/) != nil,
              manifest.sha256.wholeMatch(of: /[0-9a-f]{64}/) != nil else { return }
        if let current = 主题曲映射存储.当前URL.flatMap(作品映射存储.版本(of:)),
           !作品映射存储.比内置的新(manifest.version, 内置: current) {
            return
        }

        let fileURL = Self.清单地址.deletingLastPathComponent().appending(path: manifest.file)
        guard let (compressed, fileResponse) = try? await session.data(from: fileURL),
              (fileResponse as? HTTPURLResponse)?.statusCode == 200,
              let json = try? (compressed as NSData).decompressed(using: .zlib) as Data,
              SHA256.hash(data: json).map({ String(format: "%02x", $0) }).joined() == manifest.sha256,
              (try? 主题曲映射.验证(json)) == manifest.version else { return }
        do {
            var directory = 主题曲映射存储.目录
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try json.write(to: 主题曲映射存储.下载URL, options: .atomic)
        } catch {
            return
        }
        await 主题曲映射.重新载入()
    }

    /// 后台人工匹配的结果按 ETag 静默读取，没有变化时不下载内容，读取失败时继续使用上次的。
    private func 检查人工匹配() async {
        if let 上次检查人工匹配, Date().timeIntervalSince(上次检查人工匹配) < Self.人工匹配检查间隔 { return }
        上次检查人工匹配 = Date()
        let defaults = UserDefaults.standard
        var request = URLRequest(url: Self.人工匹配地址, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        if FileManager.default.fileExists(atPath: 主题曲映射存储.人工匹配URL.path),
           let etag = defaults.string(forKey: Self.人工匹配ETag键) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              主题曲映射.换用人工匹配(data) else { return }
        do {
            var directory = 主题曲映射存储.目录
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            try data.write(to: 主题曲映射存储.人工匹配URL, options: .atomic)
            defaults.set(http.value(forHTTPHeaderField: "ETag"), forKey: Self.人工匹配ETag键)
        } catch {
            return
        }
    }
}
