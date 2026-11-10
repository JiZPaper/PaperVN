import Combine
import CoreSpotlight
import CryptoKit
import Foundation
import ImageIO
import NaturalLanguage
import UniformTypeIdentifiers

/// 把资料库里的作品写入 Spotlight，点按结果时打开作品详情。
///
/// 系统搜索只匹配标题，不看关键词和其他名称（iOS 26.5 实测），所以作品的其他语言名称各写一条，都打开同一部作品。
/// 中日文标题不分词，只输入标题的一部分搜不到，西文可以按单词搜到。所以中日文名称里的词也各写一条：
/// 标题是词本身，最后一行显示词所在的完整名称。不能设置 displayName，否则系统不再用 title 匹配（iOS 26.5）。
///
/// 资料库是事实来源，每次变化后和上次写入的内容比较，只更新有变化的作品。Spotlight 在 App 之外显示，
/// 也就没有逐张点按解除模糊的机会：资料库里受限制的封面不写入；紧急回避与家长控制生效时清空全部索引。
@MainActor
final class Spotlight索引 {
    static let shared = Spotlight索引()
    nonisolated static let 启用键 = "spotlightLibraryEnabled"

    /// 一次写入的条目数。同一部作品的条目相邻并共用封面，同时下载的封面比这少得多。
    private static let 每批数量 = 32
    private nonisolated static let 每个名称词语上限 = 12
    private nonisolated static let 缩略图边长 = 180
    /// 分隔作品编号和其他语言的名称。
    private nonisolated static let 名称分隔符: Character = "\u{1F}"

    private var 已启动 = false
    private var 观察者: Set<AnyCancellable> = []
    private var 同步任务: Task<Void, Never>?
    private var 打开任务: Task<Void, Never>?

    private init() {}

    /// 资料库的所有者确定之后调用。恢复登录期间所有者暂时为空，这时不能当成已退出登录而清空索引。
    func 资料库所有者已确定() {
        guard !已启动 else { return }
        已启动 = true
        let library = 本地资料库.shared
        let settings = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            // 通知可能从后台线程发出，而下面的闭包只能在主线程运行
            .receive(on: RunLoop.main)
            .map { _ in Self.设置快照() }
            .removeDuplicates()
            .dropFirst()
            .map { _ in () }
        library.$修订号.map { _ in () }
            .merge(with: library.$已载入.map { _ in () })
            .merge(with: 家长控制中心.shared.$hasActiveParentalControls.map { _ in () })
            .merge(with: settings)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] in self?.安排同步() }
            .store(in: &观察者)
    }

    /// 前一次同步还没结束时先让它停下，同一时间只有一次同步在写入。
    func 安排同步() {
        guard 已启动 else { return }
        let previous = 同步任务
        previous?.cancel()
        同步任务 = Task { [weak self] in
            await previous?.value
            await self?.同步()
        }
    }

    /// 点按 Spotlight 结果。冷启动时资料库还没读完，视觉小说的编号就是路由，其他作品等读完再打开。
    func 打开(标识符: String, router: PaperVNURLRouter) {
        打开任务?.cancel()
        开屏弹窗状态.shared.正在打开作品 = true
        let 标识符 = Self.条目ID(标识符: 标识符)
        if let route = Self.视觉小说路由(标识符: 标识符) {
            router.打开(route)
            return
        }
        打开任务 = Task {
            let library = 本地资料库.shared
            for await loaded in library.$已载入.values where loaded {
                break
            }
            guard !Task.isCancelled,
                  let entry = library.条目.first(where: { $0.id == 标识符 }),
                  let route = entry.Spotlight路由(标题: Self.显示标题(entry))
            else { return }
            router.打开(route)
        }
    }

    // MARK: - 同步

    private func 同步() async {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let library = 本地资料库.shared
        guard Self.允许写入, let owner = library.所有者 else {
            await 清空()
            return
        }
        guard library.已载入, !library.载入失败 else { return }

        var record = Self.读取记录()
        if record.所有者 != owner {
            try? await CSSearchableIndex.default().deleteAllSearchableItems()
            record = .init(所有者: owner)
        }

        let items = library.条目.flatMap(Self.索引内容)
        let currentIDs = Set(items.map(\.id))
        let removed = record.指纹.keys.filter { !currentIDs.contains($0) }
        if !removed.isEmpty {
            try? await CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: removed)
            for id in removed { record.指纹[id] = nil }
        }
        Self.保存记录(record)

        let changed = items.filter { record.指纹[$0.id] != $0.指纹 }
        var start = 0
        while start < changed.count, !Task.isCancelled {
            let batch = Array(changed[start..<min(start + Self.每批数量, changed.count)])
            start += batch.count
            let thumbnails = await Self.读取缩略图(batch)
            let searchable = batch.map { $0.可搜索项(缩略图: $0.封面.flatMap { thumbnails[$0] }) }
            do {
                try await CSSearchableIndex.default().indexSearchableItems(searchable)
            } catch {
                break
            }
            // 封面没读到的作品不记录，下次同步时再试
            for item in batch where item.封面.map({ thumbnails[$0] != nil }) ?? true {
                record.指纹[item.id] = item.指纹
            }
            // 条目很多时每批都保存太频繁
            if start % (Self.每批数量 * 10) == 0 { Self.保存记录(record) }
        }
        Self.保存记录(record)
    }

    private func 清空() async {
        guard FileManager.default.fileExists(atPath: Self.记录地址.path()) else { return }
        try? await CSSearchableIndex.default().deleteAllSearchableItems()
        try? FileManager.default.removeItem(at: Self.记录地址)
    }

    private static var 允许写入: Bool {
        (UserDefaults.standard.object(forKey: 启用键) as? Bool ?? true)
            && !紧急回避设置.会话正在进行()
            && !家长控制中心.shared.hasActiveParentalControls
    }

    /// 影响写入内容的设置。其他设置变化时不需要重新比较。
    private static func 设置快照() -> [String] {
        let defaults = UserDefaults.standard
        return [
            启用键, 紧急回避设置.会话进行中键, "preferredTitleLang", "fallbackTitleLang", "allowUnofficialTitles",
            "contentFilterEnabled", "sexualThreshold", "violenceThreshold", "filterMode",
        ].map { String(describing: defaults.object(forKey: $0)) }
    }

    // MARK: - 内容

    private static func 显示标题(_ entry: 本地资料库条目) -> String {
        let defaults = UserDefaults.standard
        return entry.显示标题(
            偏好: defaults.string(forKey: "preferredTitleLang").flatMap(标题语言.init) ?? .original,
            回退: defaults.string(forKey: "fallbackTitleLang").flatMap(标题语言.init) ?? .original,
            允许非官方: defaults.bool(forKey: "allowUnofficialTitles")
        ).text
    }

    /// 视觉小说的封面和资料库的行一样按内容限制判断，受限制时不写入。其他作品没有内容分级，资料库里也直接显示。
    private static func 封面地址(_ entry: 本地资料库条目) -> URL? {
        guard entry.类型 == .visualNovel else { return entry.封面地址.flatMap(URL.init(string:)) }
        guard let image = entry.vndb?.vn.image else { return nil }
        let defaults = UserDefaults.standard
        let restricted = 内容安全限制判定.图片需要限制(
            sexual: image.sexual,
            violence: image.violence,
            enabled: defaults.bool(forKey: "contentFilterEnabled"),
            sexualThreshold: defaults.object(forKey: "sexualThreshold") as? Double ?? 0.8,
            violenceThreshold: defaults.object(forKey: "violenceThreshold") as? Double ?? 1,
            mode: defaults.string(forKey: "filterMode").flatMap(内容过滤模式.init) ?? .both
        )
        return restricted ? nil : (image.thumbnail ?? image.url).flatMap(URL.init(string:))
    }

    private static func 索引内容(_ entry: 本地资料库条目) -> [索引项] {
        let title = 显示标题(entry)
        // 打不开详情的作品不写入，否则点按结果之后什么也不会发生
        guard entry.Spotlight路由(标题: title) != nil else { return [] }
        var description = [entry.类型.localizedTitle]
        if let status = entry.状态 { description.append(status.localizedTitle(for: entry.类型)) }
        let cover = 封面地址(entry)
        func item(id: String, 标题: String, 主标题: String?) -> 索引项 {
            索引项(id: id, 标题: 标题, 主标题: 主标题, 描述: description.joined(separator: " · "), 类型: entry.类型, 封面: cover)
        }
        let others = 其他名称(entry, 主标题: title)
        let names = [title] + others
        var seen = Set(names.map { $0.lowercased() })
        var words: [索引项] = []
        for name in names {
            for word in 假名词语(name) where seen.insert(word.lowercased()).inserted {
                words.append(item(
                    id: "\(entry.id)\(名称分隔符)词\(名称分隔符)\(word)",
                    标题: word,
                    主标题: name
                ))
            }
        }
        return [item(id: entry.id, 标题: title, 主标题: nil)]
            + others.map { item(id: "\(entry.id)\(名称分隔符)\($0)", 标题: $0, 主标题: title) }
            + words
    }

    /// 日文名称里可能被搜索的词。分词器会把人名拆开（フリー/レン），所以相邻的几个词也合起来写入。
    /// 只写入含假名的词：主屏幕搜索找不到短的纯汉字标题（葬送、芙莉莲），写了也白占空间；西文本来就按词匹配。
    /// 虚词不放在开头和结尾，一个字的不写入。短的优先，每个名称有上限，否则长标题的条目太多。
    nonisolated static func 假名词语(_ name: String) -> [String] {
        func 是假名(_ scalar: Unicode.Scalar) -> Bool {
            (0x3040...0x30FF).contains(scalar.value)
        }
        guard name.unicodeScalars.contains(where: 是假名) else { return [] }
        let 虚词: Set<String> = ["の", "と", "は", "が", "を", "に", "で", "へ", "も", "や"]
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = name
        tokenizer.setLanguage(.japanese)
        var tokens: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: name.startIndex..<name.endIndex) { range, _ in
            tokens.append(range)
            return true
        }
        var words: [String] = []
        for length in 1...3 {
            guard tokens.count >= length else { break }
            for start in 0...(tokens.count - length) {
                let first = tokens[start], last = tokens[start + length - 1]
                let word = String(name[first.lowerBound..<last.upperBound])
                guard word.count > 1, word != name, word.unicodeScalars.contains(where: 是假名),
                      !虚词.contains(String(name[first])), !虚词.contains(String(name[last])),
                      !words.contains(word)
                else { continue }
                words.append(word)
            }
        }
        return Array(words.prefix(每个名称词语上限))
    }

    /// 大小写不同的算同一个名称。
    private static func 其他名称(_ entry: 本地资料库条目, 主标题: String) -> [String] {
        var seen = [主标题.lowercased()]
        return (entry.全部标题 + (entry.显示用多语言标题 ?? []).map(\.title)).filter { name in
            let key = name.lowercased()
            guard !name.isEmpty, !seen.contains(key) else { return false }
            seen.append(key)
            return true
        }
    }

    /// 其他语言名称的条目，标识符里带着名称。
    nonisolated static func 条目ID(标识符: String) -> String {
        标识符.split(separator: 名称分隔符, maxSplits: 1).first.map(String.init) ?? 标识符
    }

    private static func 视觉小说路由(标识符: String) -> PaperVNURLRoute? {
        let prefix = 本地资料库条目.视觉小说ID("")
        guard 标识符.hasPrefix(prefix) else { return nil }
        return .visualNovel(String(标识符.dropFirst(prefix.count)))
    }

    private nonisolated static func 读取缩略图(_ items: [索引项]) async -> [URL: Data] {
        await withTaskGroup(of: (URL, Data?).self) { group in
            for url in Set(items.compactMap(\.封面)) {
                group.addTask { (url, await 缩略图(url)) }
            }
            var result: [URL: Data] = [:]
            for await (url, data) in group {
                result[url] = data
            }
            return result
        }
    }

    /// 封面原图可能很大，缩小后再交给系统。
    private nonisolated static func 缩略图(_ url: URL) async -> Data? {
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 缩略图边长,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    // MARK: - 写入记录

    /// 上次写入的所有者和每部作品的内容指纹。文件丢失时只是全部重新写入一次。
    private nonisolated struct 写入记录: Codable {
        var 所有者: String?
        var 指纹: [String: String] = [:]
    }

    private nonisolated static var 记录地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "Spotlight索引", directoryHint: .isDirectory)
            .appending(path: "记录.json")
    }

    private static func 读取记录() -> 写入记录 {
        guard let data = try? Data(contentsOf: 记录地址),
              let record = try? JSONDecoder().decode(写入记录.self, from: data)
        else { return .init() }
        return record
    }

    private static func 保存记录(_ record: 写入记录) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(
            at: 记录地址.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: 记录地址, options: .atomic)
    }
}

private nonisolated struct 索引项: Sendable {
    let id: String
    let 标题: String
    /// 其他语言名称的条目和词条才有：显示在结果的最后一行，看得出是哪部作品。
    let 主标题: String?
    let 描述: String
    let 类型: 作品类型
    let 封面: URL?

    var 指纹: String {
        // 第一项是写入格式的版本，改变写入的属性时加一，内容没变的作品也会重新写入
        let content = (["6", 标题, 主标题 ?? "", 描述, 封面?.absoluteString ?? ""]).joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func 可搜索项(缩略图: Data?) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        // 不要设置 displayName：设置之后系统搜索就匹配不到标题了（iOS 26.5）
        attributes.title = 标题
        attributes.alternateNames = 主标题.map { [$0] }
        attributes.contentDescription = 描述
        attributes.thumbnailData = 缩略图
        let item = CSSearchableItem(
            uniqueIdentifier: id,
            domainIdentifier: 类型.rawValue,
            attributeSet: attributes
        )
        // 默认 30 天后过期，而内容没变的作品不会重新写入
        item.expirationDate = .distantFuture
        return item
    }
}

extension 本地资料库条目 {
    /// 从 Spotlight 打开此作品的路由。
    func Spotlight路由(标题: String) -> PaperVNURLRoute? {
        if 类型 == .visualNovel {
            return 平台ID[.vndb].map(PaperVNURLRoute.visualNovel)
        }
        guard var target = 详情目标(标题: 标题) else { return nil }
        target.多语言标题 = 显示用多语言标题
        target.类型 = 类型
        return .work(target)
    }
}
