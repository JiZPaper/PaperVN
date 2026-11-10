import Foundation

/// 资料库里的动画、漫画与轻小说只在 Bangumi 资料库里有记录时才带中文名，详情页却会读取 Bangumi 的中文名，
/// 两边显示的副标题不一样。中文名预装在作品映射里（`chineseTitles`），资料库从磁盘读出、同步写入之前都先补上，
/// 显示出来的就是最终的标题。只有映射里没有的 Bangumi 条目才向 Bangumi 读取，读到的结果存在磁盘上，同一个条目只读一次。
nonisolated enum Bangumi中文名补全 {
    /// 同时读取的条目数，避免 Bangumi 限流。
    private static let 并发数 = 4

    /// 用作品映射里预装的中文名补上，不联网。
    static func 预装(_ entries: inout [本地资料库条目]) {
        for index in entries.indices {
            let entry = entries[index]
            guard entry.类型 != .visualNovel, !有中文名(entry),
                  let name = 作品映射.中文名(entry.id, 类型: entry.类型) else { continue }
            entries[index] = 加上(name, to: entry)
        }
    }

    /// 同步写入资料库之前调用：先用预装的中文名，映射里没有的 Bangumi 条目再向 Bangumi 读取。
    /// 和详情页一样，中文名由用户编辑，视为非官方标题。
    static func 补全(_ library: inout [String: 本地资料库条目]) async {
        var entries = Array(library.values)
        预装(&entries)
        for entry in entries { library[entry.id] = entry }

        var cache = 读取缓存()
        var targets: [(key: String, bangumiID: Int)] = []
        for entry in entries where entry.类型 != .visualNovel && !有中文名(entry) {
            // 映射里收录的条目没有中文名就是 Bangumi 上没有，不必再读
            guard let value = entry.平台ID[.bangumi], let id = Int(value),
                  作品映射.查找(.bangumi, 平台ID: value, 类型: entry.类型) == nil else { continue }
            targets.append((entry.id, id))
        }
        let missing = Array(Set(targets.map(\.bangumiID)).filter { cache[String($0)] == nil })
        if !missing.isEmpty {
            await withTaskGroup(of: (Int, String?).self) { group in
                var iterator = missing.makeIterator()
                for _ in 0..<min(并发数, missing.count) {
                    if let id = iterator.next() { group.addTask { (id, await 读取中文名(id)) } }
                }
                for await (id, name) in group {
                    // 读取失败的不记下来，下次同步再读；条目没有中文名记为空字符串
                    if let name { cache[String(id)] = name }
                    if let next = iterator.next() { group.addTask { (next, await 读取中文名(next)) } }
                }
            }
            保存缓存(cache)
        }
        for (key, id) in targets {
            guard let name = cache[String(id)], !name.isEmpty, let entry = library[key] else { continue }
            library[key] = 加上(name, to: entry)
        }
    }

    private static func 有中文名(_ entry: 本地资料库条目) -> Bool {
        (entry.多语言标题 ?? []).contains { $0.lang == "zh-Hans" }
    }

    private static func 加上(_ name: String, to entry: 本地资料库条目) -> 本地资料库条目 {
        var entry = entry
        entry.多语言标题 = 作品多语言标题.合并([
            entry.多语言标题 ?? [],
            [用户多语言标题(lang: "zh-Hans", title: name, latin: nil, official: false, main: false)],
        ])
        return entry
    }

    /// 读取成功时返回中文名（没有中文名时为空字符串），失败时返回 nil。
    private static func 读取中文名(_ id: Int) async -> String? {
        struct 条目: Decodable {
            let nameCN: String?
            enum CodingKeys: String, CodingKey { case nameCN = "name_cn" }
        }
        var request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/subjects/\(id)")!, timeoutInterval: 15)
        request.setValue("jizpaper/PaperVN (https://papervn.jizpaper.com)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
        // 条目不存在或需要登录才能看到：当作没有中文名，不再重复读取
        if status == 404 { return "" }
        guard status == 200, let subject = try? JSONDecoder().decode(条目.self, from: data) else { return nil }
        return subject.nameCN?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func 读取缓存() -> [String: String] {
        guard let data = try? Data(contentsOf: 缓存地址),
              let value = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return value
    }

    private static func 保存缓存(_ cache: [String: String]) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: 缓存地址.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: 缓存地址, options: .atomic)
    }

    private static var 缓存地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "PaperVN Sync", directoryHint: .isDirectory)
            .appending(path: "Bangumi中文名.json")
    }
}
