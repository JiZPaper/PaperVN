import AVKit
import Combine
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import Observation
import SwiftUI

private extension CodingUserInfoKey {
    nonisolated static let todayLocaleIdentifier = CodingUserInfoKey(
        rawValue: "com.jizpaper.PaperVN.Today.localeIdentifier"
    )!

    nonisolated static let todayContentBaseURL = CodingUserInfoKey(
        rawValue: "com.jizpaper.PaperVN.Today.contentBaseURL"
    )!
}

nonisolated struct Today清单: Decodable, Sendable {
    let schemaVersion: Int
    let currentFeed: String
}

private nonisolated struct Today数据响应: Sendable {
    let data: Data
    let serverDate: Date?
}

private nonisolated struct Today缓存记录: Codable, Sendable {
    let sourceBaseURL: URL
    let feedPath: String
    let feedData: Data?
}

nonisolated struct Today内容: Decodable, Sendable {
    let schemaVersion: Int
    let date: String
    let stories: [Today故事]

    var contentFingerprint: String {
        stories.map { story in
            let related = story.related.map { item in
                [
                    item.type.rawValue,
                    item.id,
                    item.title,
                    item.original ?? ""
                ].joined(separator: "\u{1F}")
            }.joined(separator: "\u{1E}")

            return [
                story.id,
                story.groupID ?? "",
                story.visualNovelID,
                story.accessibilityTitle,
                story.eyebrow,
                story.description,
                story.releaseDate ?? "",
                story.image?.path ?? "",
                story.image?.contentBaseURL.absoluteString ?? "",
                String(story.image?.width ?? 0),
                String(story.image?.height ?? 0),
                story.video?.source ?? "",
                story.video?.contentBaseURL.absoluteString ?? "",
                story.introduction?.contentFingerprint ?? "",
                related
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1D}")
    }
}

private nonisolated struct Today本地化文本: Decodable, Sendable {
    let fallback: String
    let translations: [String: String]
    let preferredLanguageIdentifier: String?

    init(from decoder: Decoder) throws {
        preferredLanguageIdentifier = decoder.userInfo[
            .todayLocaleIdentifier
        ] as? String

        if let value = try? decoder.singleValueContainer().decode(String.self) {
            guard !value.isEmpty else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Today文本不能为空。")
                )
            }
            fallback = value
            translations = [:]
            return
        }

        let container = try decoder.container(keyedBy: 动态键.self)
        var values: [String: String] = [:]
        for key in container.allKeys where key.stringValue != "translations" {
            if let value = try container.decodeIfPresent(String.self, forKey: key),
               Self.isUsable(value) {
                values[key.stringValue] = value
            }
        }
        if let nested = try container.decodeIfPresent(
            [String: String].self,
            forKey: 动态键(stringValue: "translations")!
        ) {
            values.merge(nested.filter { Self.isUsable($0.value) }) { _, new in new }
        }

        let defaultValue = values.removeValue(forKey: "default")
            ?? values["zh-Hans"]
            ?? values["zh_Hans"]
            ?? values.values.first
        guard let defaultValue, !defaultValue.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Today文本缺少可用内容。")
            )
        }
        fallback = defaultValue
        translations = values
    }

    var resolved: String {
        let normalizedTranslations = translations.reduce(into: [String: String]()) {
            result,
            entry in
            result[Self.normalize(entry.key)] = entry.value
        }

        for identifier in preferredLanguageIdentifiers {
            let normalizedIdentifier = Self.normalize(identifier)
            if let exact = normalizedTranslations[normalizedIdentifier] {
                return exact
            }

            let language = normalizedIdentifier.split(separator: "-").first.map(String.init)
            if language == "zh" {
                let preferredChinese = normalizedIdentifier.contains("hant")
                    || normalizedIdentifier.contains("tw")
                    || normalizedIdentifier.contains("hk")
                    ? "zh-hant"
                    : "zh-hans"
                if let chinese = normalizedTranslations[preferredChinese] {
                    return chinese
                }

                if let genericChinese = normalizedTranslations["zh"] {
                    return genericChinese
                }
                return fallback
            }

            if let language,
               let matching = normalizedTranslations.first(where: {
                   $0.key == language || $0.key.hasPrefix(language + "-")
               })?.value {
                return matching
            }
        }

        return fallback
    }

    private var preferredLanguageIdentifiers: [String] {
        [
            preferredLanguageIdentifier,
            Locale.preferredLanguages.first,
            Locale.current.identifier,
            Bundle.main.preferredLocalizations.first
        ]
        .compactMap { $0 }
    }

    private static func normalize(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
    }

    private static func isUsable(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private struct 动态键: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

nonisolated enum Today内容解码器 {
    static func decode(
        _ data: Data,
        localeIdentifier: String,
        contentBaseURL: URL = Today内容源.mirror.baseURL
    ) throws -> Today内容 {
        let decoder = JSONDecoder()
        decoder.userInfo[.todayLocaleIdentifier] = localeIdentifier
        decoder.userInfo[.todayContentBaseURL] = contentBaseURL
        return try decoder.decode(Today内容.self, from: data)
    }
}

nonisolated struct Today故事: Decodable, Identifiable, Sendable {
    let id: String
    let groupID: String?
    let visualNovelID: String
    let accessibilityTitle: String
    let eyebrow: String
    let description: String
    let releaseDate: String?
    let image: Today图片?
    let video: Today视频?
    let introduction: Today介绍内容?
    let related: [Today关联内容]

    private enum CodingKeys: String, CodingKey {
        case id
        case groupID
        case visualNovelID
        case accessibilityTitle
        case eyebrow
        case description
        case releaseDate
        case image
        case video
        case introduction
        case related
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
        visualNovelID = try container.decode(String.self, forKey: .visualNovelID)
        accessibilityTitle = try container
            .decode(Today本地化文本.self, forKey: .accessibilityTitle)
            .resolved
        eyebrow = try container.decode(Today本地化文本.self, forKey: .eyebrow).resolved
        description = try container.decode(Today本地化文本.self, forKey: .description).resolved
        releaseDate = try container.decodeIfPresent(
            Today本地化文本.self,
            forKey: .releaseDate
        )?.resolved
        image = try container.decodeIfPresent(Today图片.self, forKey: .image)
        video = try container.decodeIfPresent(Today视频.self, forKey: .video)
        introduction = try container.decodeIfPresent(
            Today介绍内容.self,
            forKey: .introduction
        )
        related = try container.decodeIfPresent(
            [Today关联内容].self,
            forKey: .related
        ) ?? []
    }

    var displayedRelatedItemCount: Int {
        related.count + (
            related.contains {
                $0.type == .visualNovel && $0.id == visualNovelID
            } ? 0 : 1
        )
    }
}

nonisolated struct Today介绍内容: Decodable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let blocks: [Today介绍段落]
    let related: [Today关联内容]
    let author: String?

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case blocks
        case related
        case author
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        author = try container.decodeIfPresent(String.self, forKey: .author)

        guard schemaVersion == Self.supportedSchemaVersion else {
            blocks = []
            related = []
            return
        }

        blocks = try container.decodeIfPresent(
            [Today介绍段落].self,
            forKey: .blocks
        ) ?? []
        related = try container.decodeIfPresent(
            [Today关联内容].self,
            forKey: .related
        ) ?? []
    }

    var isSupported: Bool {
        schemaVersion == Self.supportedSchemaVersion && !blocks.isEmpty
    }

    var contentFingerprint: String {
        let blockContent = blocks.map { block in
            block.style.rawValue + "\u{1F}" + block.markdown
        }.joined(separator: "\u{1E}")
        let relatedContent = related.map { item in
            [
                item.type.rawValue,
                item.id,
                item.title,
                item.original ?? ""
            ].joined(separator: "\u{1F}")
        }.joined(separator: "\u{1E}")
        return [
            String(schemaVersion),
            author ?? "",
            blockContent,
            relatedContent
        ].joined(separator: "\u{1D}")
    }
}

nonisolated enum Today介绍段落样式: String, Decodable, Sendable {
    case primary
    case secondary
}

nonisolated struct Today介绍段落: Decodable, Sendable {
    let style: Today介绍段落样式
    let markdown: String

    private enum CodingKeys: String, CodingKey {
        case style
        case markdown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decodeIfPresent(
            Today介绍段落样式.self,
            forKey: .style
        ) ?? .primary
        markdown = try container.decode(
            Today本地化文本.self,
            forKey: .markdown
        ).resolved
    }
}

nonisolated struct Today图片: Decodable, Sendable {
    let path: String
    let width: Int
    let height: Int
    let contentBaseURL: URL

    var aspectRatio: CGFloat {
        CGFloat(width) / CGFloat(height)
    }

    var url: URL? {
        Today内容源.resolvedURL(for: path, relativeTo: contentBaseURL)
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case width
        case height
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        contentBaseURL = decoder.userInfo[.todayContentBaseURL] as? URL
            ?? Today内容源.mirror.baseURL
    }
}

nonisolated struct Today视频: Decodable, Sendable {
    let source: String
    let contentBaseURL: URL

    private enum CodingKeys: String, CodingKey {
        case url
        case path
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .url)
            ?? container.decode(String.self, forKey: .path)
        contentBaseURL = decoder.userInfo[.todayContentBaseURL] as? URL
            ?? Today内容源.mirror.baseURL
    }

    var url: URL? {
        Today内容源.resolvedURL(for: source, relativeTo: contentBaseURL)
    }
}

nonisolated enum Today关联类型: String, Decodable, Sendable {
    case visualNovel
    case character
}

nonisolated struct Today关联内容: Decodable, Identifiable, Sendable {
    let type: Today关联类型
    let id: String
    let title: String
    let original: String?

    init(
        type: Today关联类型,
        id: String,
        title: String,
        original: String?
    ) {
        self.type = type
        self.id = id
        self.title = title
        self.original = original
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case title
        case original
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Today关联类型.self, forKey: .type)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(Today本地化文本.self, forKey: .title).resolved
        original = try container.decodeIfPresent(String.self, forKey: .original)
    }
}

nonisolated enum Today内容源 {
    static let connect = Today内容来源(
        string: "https://papervn.jizpaper.com/connect/today/"
    )
    static let mirror = Today内容来源(
        string: "https://papervn.jizpaper.com/today/"
    )
    static let repositoryBaseURL = mirror.baseURL
    static let manifestURL = mirror.manifestURL

    static func feedPath(for date: String) -> String {
        "feeds/\(date).json"
    }

    static func resolvedURL(for path: String, relativeTo baseURL: URL) -> URL? {
        guard !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    static func preferredSources(
        connectEnabled: Bool = PaperVNConnect自动策略.自动转发已启用
    ) -> [Today内容来源] {
        connectEnabled ? [connect] : [mirror]
    }
}

nonisolated struct Today内容来源: Sendable, Equatable {
    let baseURL: URL
    let manifestURL: URL
    let cachePrefix: String

    init(string: String) {
        baseURL = URL(string: string)!
        manifestURL = baseURL.appending(path: "manifest.json")
        cachePrefix = Self.cachePrefix(for: baseURL)
    }

    private static func cachePrefix(for baseURL: URL) -> String {
        let host = baseURL.host ?? "today"
        let path = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let normalizedPath = path.isEmpty ? "root" : path.replacingOccurrences(of: "/", with: "-")
        return host + "-" + normalizedPath
    }
}

private nonisolated enum Today日期工具 {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    static func isValidFeedDate(_ value: String) -> Bool {
        value.range(
            of: #"^\d{4}-\d{2}-\d{2}$"#,
            options: .regularExpression
        ) != nil
    }

    static func string(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    static func date(from value: String) -> Date? {
        guard isValidFeedDate(value) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(
            calendar: calendar,
            year: Int(value.prefix(4)),
            month: Int(value.dropFirst(5).prefix(2)),
            day: Int(value.suffix(2))
        )
        return calendar.date(from: components)
    }
}

enum Today服务错误: LocalizedError, Sendable {
    case invalidResponse
    case unsupportedSchema
    case invalidContent
    case noContentForDate

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "Today服务返回了无效响应。")
        case .unsupportedSchema:
            String(localized: "更新到最新版本以查看此页面。")
        case .invalidContent:
            String(localized: "Today内容暂时不可用。")
        case .noContentForDate:
            String(localized: "今天还没有准备Today内容。")
        }
    }
}

private actor Today名称服务 {
    static let shared = Today名称服务()

    private let endpoint = URL(string: "https://api.vndb.org/kana")!
    private let session = URLSession.shared
    private let decoder = JSONDecoder()

    private struct 作品响应: Decodable {
        let results: [作品名称]
    }

    private struct 作品名称: Decodable {
        let title: String
        let titles: [用户多语言标题]?
        let image: 作品图片?
    }

    private struct 作品图片: Decodable {
        let url: String?
        let dims: [Int]?
    }

    private struct 角色响应: Decodable {
        let results: [角色名称]
    }

    private struct 角色名称: Decodable {
        let name: String
        let original: String?
    }

    func fetchVisualNovelName(id: String) async throws -> Today视觉小说名称 {
        let response: 作品响应 = try await fetch(
            endpoint: "vn",
            id: id,
            fields: "title,titles{lang,title,latin,official,main},image{url,dims}"
        )
        guard let result = response.results.first else {
            throw Today服务错误.invalidContent
        }
        return Today视觉小说名称(
            id: id,
            title: result.title,
            titles: result.titles,
            imageURL: result.image?.url.flatMap(URL.init(string:)),
            imageDimensions: result.image?.dims
        )
    }

    func fetchCharacterName(id: String) async throws -> Today角色名称 {
        let response: 角色响应 = try await fetch(
            endpoint: "character",
            id: id,
            fields: "name,original"
        )
        guard let result = response.results.first else {
            throw Today服务错误.invalidContent
        }
        return Today角色名称(
            id: id,
            name: result.name,
            original: result.original
        )
    }

    private func fetch<Response: Decodable>(
        endpoint: String,
        id: String,
        fields: String
    ) async throws -> Response {
        let url = self.endpoint.appendingPathComponent(endpoint)
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "filters": ["id", "=", id],
                "fields": fields,
                "results": 1
            ]
        )

        let (data, response) = try await PaperVNConnect网络设置.发送请求(
            request,
            session: session
        )
        guard (200...299).contains(response.statusCode),
              !data.isEmpty else {
            throw Today服务错误.invalidResponse
        }
        return try decoder.decode(Response.self, from: data)
    }
}

actor Today服务 {
    static let shared = Today服务()
    private static let inMemoryCacheLifetime: TimeInterval = 60

    private let session: URLSession
    private let cacheDirectory: URL
    private let decoder = JSONDecoder()
    private var cachedFeeds: [String: (feed: Today内容, loadedAt: Date)] = [:]

    init(
        session: URLSession = .shared,
        cacheDirectory: URL? = nil
    ) {
        self.session = session

        let cachesRoot = cacheDirectory ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        self.cacheDirectory = cacheDirectory == nil
            ? cachesRoot.appendingPathComponent(
                "PaperVNToday",
                isDirectory: true
            )
            : cachesRoot

        try? FileManager.default.createDirectory(
            at: self.cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func cachedFeed(
        localeIdentifier: String,
        previewDate: String? = nil,
        now: Date = Date()
    ) -> Today内容? {
        let effectivePreviewDate = validPreviewDate(previewDate)
        let cacheKey = requestCacheKey(
            localeIdentifier: localeIdentifier,
            previewDate: effectivePreviewDate,
            now: now
        )
        if let cached = cachedFeeds[cacheKey] {
            removeExpiredFeedCaches(
                currentDate: cached.feed.date
            )
            return cached.feed
        }

        if let record = loadSuccessfulCacheRecord(
            previewDate: effectivePreviewDate
        ),
           let source = Today内容源.preferredSources().first(where: { $0.baseURL == record.sourceBaseURL }),
           let cached = loadCachedFeed(
               at: record.feedPath,
               data: record.feedData,
               expectedDate: effectivePreviewDate,
               localeIdentifier: localeIdentifier,
               source: source
           ) {
            cachedFeeds[cacheKey] = (cached.feed, now)
            removeExpiredFeedCaches(currentDate: cached.feed.date)
            return cached.feed
        }

        for source in Today内容源.preferredSources() {
            guard let manifestData = cachedData(
                cacheName: cacheName(for: "manifest.json", in: source)
            ),
                let manifest = try? decoder.decode(
                    Today清单.self,
                    from: manifestData
                ),
                manifest.schemaVersion == 1
            else { continue }

            let feedPath = effectivePreviewDate.map(Today内容源.feedPath(for:))
                ?? manifest.currentFeed
            guard let cached = loadCachedFeed(
                at: feedPath,
                expectedDate: effectivePreviewDate,
                localeIdentifier: localeIdentifier,
                source: source
            ) else { continue }

            saveSuccessfulCacheRecord(
                source: source,
                feedPath: feedPath,
                feedData: cached.data,
                previewDate: effectivePreviewDate
            )
            cachedFeeds[cacheKey] = (cached.feed, now)
            removeExpiredFeedCaches(currentDate: cached.feed.date)
            return cached.feed
        }

        return nil
    }

    func load(
        localeIdentifier: String,
        previewDate: String? = nil,
        forceRefresh: Bool = false
    ) async throws -> Today内容 {
        let effectivePreviewDate = validPreviewDate(previewDate)
        let cacheKey = requestCacheKey(
            localeIdentifier: localeIdentifier,
            previewDate: effectivePreviewDate,
            now: Date()
        )
        if !forceRefresh,
           let cached = cachedFeeds[cacheKey],
           Date().timeIntervalSince(cached.loadedAt)
                < Self.inMemoryCacheLifetime {
            return cached.feed
        }
        let sources = Today内容源.preferredSources()
        var lastError: Error?

        for (index, source) in sources.enumerated() {
            do {
                let feed = try await load(
                    from: source,
                    localeIdentifier: localeIdentifier,
                    previewDate: effectivePreviewDate,
                    forceRefresh: forceRefresh,
                    allowCachedFallback: index == sources.count - 1
                )
                cachedFeeds[cacheKey] = (feed, Date())
                removeExpiredFeedCaches(
                    currentDate: feed.date
                )
                return feed
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }

        throw lastError ?? Today服务错误.invalidResponse
    }

    private func load(
        from source: Today内容来源,
        localeIdentifier: String,
        previewDate: String?,
        forceRefresh: Bool,
        allowCachedFallback: Bool
    ) async throws -> Today内容 {
        let manifestResponse = try await data(
            from: source.manifestURL,
            cacheName: cacheName(for: "manifest.json", in: source),
            forceRefresh: true,
            allowCachedFallback: allowCachedFallback
        )
        let manifest = try decoder.decode(
            Today清单.self,
            from: manifestResponse.data
        )
        guard manifest.schemaVersion == 1 else {
            throw Today服务错误.unsupportedSchema
        }

        if let previewDate,
           Today日期工具.isValidFeedDate(previewDate) {
            return try await loadFeed(
                at: Today内容源.feedPath(for: previewDate),
                expectedDate: previewDate,
                localeIdentifier: localeIdentifier,
                forceRefresh: forceRefresh,
                contentBaseURL: source.baseURL,
                allowCachedFallback: allowCachedFallback,
                source: source,
                previewDate: previewDate
            )
        }

        if let serverDate = manifestResponse.serverDate {
            let date = Today日期工具.string(from: serverDate)
            let feedPath = Today内容源.feedPath(for: date)
            return try await loadFeed(
                at: feedPath,
                expectedDate: date,
                localeIdentifier: localeIdentifier,
                forceRefresh: forceRefresh,
                contentBaseURL: source.baseURL,
                allowCachedFallback: allowCachedFallback,
                source: source,
                previewDate: nil
            )
        }

        return try await loadFeed(
            at: manifest.currentFeed,
            expectedDate: nil,
            localeIdentifier: localeIdentifier,
            forceRefresh: forceRefresh,
            contentBaseURL: source.baseURL,
            allowCachedFallback: allowCachedFallback,
            source: source,
            previewDate: nil
        )
    }

    private func loadFeed(
        at path: String,
        expectedDate: String?,
        localeIdentifier: String,
        forceRefresh: Bool,
        contentBaseURL: URL,
        allowCachedFallback: Bool,
        source: Today内容来源,
        previewDate: String?
    ) async throws -> Today内容 {
        let feedURL = try repositoryURL(for: path, baseURL: contentBaseURL)
        let feedResponse = try await data(
            from: feedURL,
            cacheName: cacheName(for: path, in: source),
            forceRefresh: forceRefresh,
            allowCachedFallback: allowCachedFallback
        )
        let feed = try Today内容解码器.decode(
            feedResponse.data,
            localeIdentifier: localeIdentifier,
            contentBaseURL: contentBaseURL
        )
        try validate(feed, expectedDate: expectedDate)
        saveSuccessfulCacheRecord(
            source: source,
            feedPath: path,
            feedData: feedResponse.data,
            previewDate: previewDate
        )
        return feed
    }

    private func data(
        from url: URL,
        cacheName: String,
        forceRefresh: Bool,
        allowCachedFallback: Bool
    ) async throws -> Today数据响应 {
        let cachedURL = cacheDirectory.appendingPathComponent(cacheName)
        let requestURL: URL
        if forceRefresh,
           var components = URLComponents(
               url: url,
               resolvingAgainstBaseURL: false
           ) {
            var queryItems = components.queryItems ?? []
            queryItems.append(
                URLQueryItem(
                    name: "_papervn_refresh",
                    value: UUID().uuidString
                )
            )
            components.queryItems = queryItems
            requestURL = components.url ?? url
        } else {
            requestURL = url
        }
        var request = URLRequest(
            url: requestURL,
            cachePolicy: forceRefresh
                ? .reloadIgnoringLocalAndRemoteCacheData
                : .useProtocolCachePolicy,
            timeoutInterval: 20
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if forceRefresh {
            request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
            request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        }

        do {
            let (data, response) = try await PaperVNConnect网络设置.发送请求(
                request,
                session: session
            )
            if response.statusCode == 404 {
                throw Today服务错误.noContentForDate
            }
            guard (200...299).contains(response.statusCode), !data.isEmpty else {
                throw Today服务错误.invalidResponse
            }
            try? data.write(to: cachedURL, options: .atomic)
            return Today数据响应(
                data: data,
                serverDate: serverDate(from: response)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch Today服务错误.noContentForDate {
            throw Today服务错误.noContentForDate
        } catch {
            if allowCachedFallback,
               let cachedData = try? Data(contentsOf: cachedURL),
               !cachedData.isEmpty {
                return Today数据响应(data: cachedData, serverDate: nil)
            }
            throw error
        }
    }

    private func serverDate(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Date") else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }

    private func repositoryURL(for path: String, baseURL: URL) throws -> URL {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains(".."),
              let url = URL(
                string: path,
                relativeTo: baseURL
              )?.absoluteURL,
              url.host == baseURL.host else {
            throw Today服务错误.invalidContent
        }
        return url
    }

    private func cacheName(for path: String, in source: Today内容来源) -> String {
        source.cachePrefix + "-" + path.replacingOccurrences(of: "/", with: "-")
    }

    private func requestCacheKey(
        localeIdentifier: String,
        previewDate: String?,
        now: Date
    ) -> String {
        localeIdentifier + "|"
            + (previewDate ?? Today日期工具.string(from: now))
    }

    private func validPreviewDate(_ previewDate: String?) -> String? {
        guard let previewDate,
              Today日期工具.isValidFeedDate(previewDate) else { return nil }
        return previewDate
    }

    private func loadCachedFeed(
        at path: String,
        data preferredData: Data? = nil,
        expectedDate: String?,
        localeIdentifier: String,
        source: Today内容来源
    ) -> (feed: Today内容, data: Data)? {
        guard (try? repositoryURL(for: path, baseURL: source.baseURL)) != nil,
              let data = preferredData ?? cachedData(
                  cacheName: cacheName(for: path, in: source)
              ),
              !data.isEmpty,
              let feed = try? Today内容解码器.decode(
                  data,
                  localeIdentifier: localeIdentifier,
                  contentBaseURL: source.baseURL
              ),
              (try? validate(feed, expectedDate: expectedDate)) != nil else {
            return nil
        }
        return (feed, data)
    }

    private func removeExpiredFeedCaches(currentDate: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let calendar = Calendar(identifier: .gregorian)
        guard let current = calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: Int(currentDate.prefix(4)),
                month: Int(currentDate.dropFirst(5).prefix(2)),
                day: Int(currentDate.suffix(2))
            )
        ) else {
            return
        }
        let daysToKeep = 缓存策略.当前 == .more ? 2 : 1
        let cutoff = calendar.date(
            byAdding: .day,
            value: -(daysToKeep - 1),
            to: current
        ) ?? current
        for file in files {
            let name = file.lastPathComponent
            guard let dateString = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression),
                  let date = Today日期工具.date(from: String(name[dateString])) else {
                continue
            }
            if date < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func cachedData(cacheName: String) -> Data? {
        let url = cacheDirectory.appendingPathComponent(cacheName)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return nil
        }
        return data
    }

    private func loadSuccessfulCacheRecord(
        previewDate: String?
    ) -> Today缓存记录? {
        guard let data = cachedData(
            cacheName: successfulCacheRecordName(previewDate: previewDate)
        ) else { return nil }
        return try? decoder.decode(Today缓存记录.self, from: data)
    }

    private func saveSuccessfulCacheRecord(
        source: Today内容来源,
        feedPath: String,
        feedData: Data,
        previewDate: String?
    ) {
        let record = Today缓存记录(
            sourceBaseURL: source.baseURL,
            feedPath: feedPath,
            feedData: feedData
        )
        guard let data = try? JSONEncoder().encode(record) else { return }
        let url = cacheDirectory.appendingPathComponent(
            successfulCacheRecordName(previewDate: previewDate)
        )
        try? data.write(to: url, options: .atomic)
    }

    private func successfulCacheRecordName(previewDate: String?) -> String {
        guard let previewDate else { return "last-successful-feed.json" }
        return "last-successful-feed-\(previewDate).json"
    }

    private func validate(
        _ feed: Today内容,
        expectedDate: String?
    ) throws {
        guard (1...2).contains(feed.schemaVersion) else {
            throw Today服务错误.unsupportedSchema
        }
        guard !feed.date.isEmpty,
              expectedDate == nil || feed.date == expectedDate else {
            throw Today服务错误.noContentForDate
        }
        guard !feed.stories.isEmpty,
              feed.stories.allSatisfy({ story in
                  !story.id.isEmpty
                      && !story.visualNovelID.isEmpty
                      && !story.accessibilityTitle.isEmpty
                      && (story.image == nil || (
                          !story.image!.path.isEmpty
                              && story.image!.width > 0
                              && story.image!.height > 0
                      ))
                      && (story.video == nil || story.video!.url != nil)
              }) else {
            throw Today服务错误.noContentForDate
        }
    }
}

@MainActor
final class Today视图模型: ObservableObject {
    private static let unavailableRetryInterval: TimeInterval = 15 * 60

    @Published private(set) var feed: Today内容?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isTodayUnavailable = false
    @Published private(set) var isUnsupportedContent = false

    private let service: Today服务
    private var prefetchTask: Task<Void, Never>?
    private var unavailableIdentity: String?
    private var unavailableRetryAfter: Date?
    private var loadedIdentity: String?

    init(service: Today服务 = .shared) {
        self.service = service
    }

    func load(
        localeIdentifier: String,
        previewDate: String? = nil,
        connectEnabled: Bool = PaperVNConnect自动策略.自动转发已启用,
        forceRefresh: Bool = false,
        now: Date = Date()
    ) async {
        guard !isLoading else { return }
        let identity = Self.requestIdentity(
            localeIdentifier: localeIdentifier,
            previewDate: previewDate,
            connectEnabled: connectEnabled,
            now: now
        )
        if !forceRefresh,
           unavailableIdentity == identity,
           let unavailableRetryAfter,
           now < unavailableRetryAfter {
            return
        }

        if let loadedIdentity, loadedIdentity != identity {
            feed = nil
            errorMessage = nil
            isTodayUnavailable = false
            isUnsupportedContent = false
        }
        isLoading = true
        errorMessage = nil
        isTodayUnavailable = false
        isUnsupportedContent = false
        defer { isLoading = false }

        if feed == nil,
           let cachedFeed = await service.cachedFeed(
               localeIdentifier: localeIdentifier,
               previewDate: previewDate,
               now: now
           ) {
            apply(cachedFeed, identity: identity)
        }

        do {
            let loadedFeed = try await service.load(
                localeIdentifier: localeIdentifier,
                previewDate: previewDate,
                forceRefresh: true
            )
            apply(loadedFeed, identity: identity)
        } catch is CancellationError {
            return
        } catch Today服务错误.noContentForDate {
            guard feed == nil else { return }
            feed = nil
            loadedIdentity = identity
            isTodayUnavailable = true
            isUnsupportedContent = false
            errorMessage = nil
            unavailableIdentity = identity
            unavailableRetryAfter = now.addingTimeInterval(
                Self.unavailableRetryInterval
            )
        } catch Today服务错误.unsupportedSchema {
            guard feed == nil else { return }
            feed = nil
            loadedIdentity = identity
            isTodayUnavailable = false
            isUnsupportedContent = true
            errorMessage = nil
        } catch {
            if feed == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func apply(_ loadedFeed: Today内容, identity: String) {
        let feedChanged = feed?.date != loadedFeed.date
            || feed?.contentFingerprint != loadedFeed.contentFingerprint
        if feedChanged || feed == nil {
            feed = loadedFeed
        }
        loadedIdentity = identity
        isTodayUnavailable = false
        isUnsupportedContent = false
        unavailableIdentity = nil
        unavailableRetryAfter = nil

        guard feedChanged else { return }
        prefetchTask?.cancel()
        prefetchTask = Task.detached(priority: .utility) { [loadedFeed] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await Today图片加载器.shared.prefetch(
                stories: Array(loadedFeed.stories.dropFirst(2))
            )
        }
    }

    func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    private static func requestIdentity(
        localeIdentifier: String,
        previewDate: String?,
        connectEnabled: Bool,
        now: Date
    ) -> String {
        localeIdentifier + "|"
            + String(connectEnabled) + "|"
            + (previewDate ?? Today日期工具.string(from: now))
    }
}

private struct Today视觉小说名称: Sendable {
    let id: String
    let title: String
    let titles: [用户多语言标题]?
    let imageURL: URL?
    let imageDimensions: [Int]?
}

private struct Today角色名称: Sendable {
    let id: String
    let name: String
    let original: String?
}

@MainActor
private final class Today关联名称视图模型: ObservableObject {
    @Published private(set) var visualNovelNames: [
        String: Today视觉小说名称
    ] = [:]
    @Published private(set) var characterNames: [
        String: Today角色名称
    ] = [:]

    private var loadingVisualNovelIDs: Set<String> = []
    private var loadingCharacterIDs: Set<String> = []

    func load(stories: [Today故事]) async {
        let visualNovelIDs = Set(
            stories.flatMap { story in
                [story.visualNovelID]
                    + story.related.compactMap { item in
                        item.type == .visualNovel ? item.id : nil
                    }
            }
        )
        let characterIDs = Set(
            stories.flatMap { story in
                story.related.compactMap { item in
                    item.type == .character ? item.id : nil
                }
            }
        )

        let pendingVisualNovelIDs = visualNovelIDs
            .subtracting(visualNovelNames.keys)
            .subtracting(loadingVisualNovelIDs)
        let pendingCharacterIDs = characterIDs
            .subtracting(characterNames.keys)
            .subtracting(loadingCharacterIDs)

        loadingVisualNovelIDs.formUnion(pendingVisualNovelIDs)
        loadingCharacterIDs.formUnion(pendingCharacterIDs)
        defer {
            loadingVisualNovelIDs.subtract(pendingVisualNovelIDs)
            loadingCharacterIDs.subtract(pendingCharacterIDs)
        }

        var loadedVisualNovelNames: [String: Today视觉小说名称] = [:]
        for id in pendingVisualNovelIDs {
            guard !Task.isCancelled else { break }
            do {
                let name = try await Today名称服务.shared
                    .fetchVisualNovelName(id: id)
                loadedVisualNovelNames[id] = name
            } catch {
            }
        }
        if !loadedVisualNovelNames.isEmpty {
            visualNovelNames.merge(loadedVisualNovelNames) { _, new in new }
        }

        var loadedCharacterNames: [String: Today角色名称] = [:]
        for id in pendingCharacterIDs {
            guard !Task.isCancelled else { break }
            do {
                let name = try await Today名称服务.shared
                    .fetchCharacterName(id: id)
                loadedCharacterNames[id] = name
            } catch {
            }
        }
        if !loadedCharacterNames.isEmpty {
            characterNames.merge(loadedCharacterNames) { _, new in new }
        }
    }
}

private extension View {
    @ViewBuilder
    func Today横向书架适配() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.平台横向书架()
        } else {
            self
                .padding(.horizontal, -20)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollClipDisabled()
        }
    }
}

@MainActor
@Observable
private final class Today页眉滚动状态 {
    var opacity: CGFloat = 1
}

private nonisolated struct TodayDuo显示几何: Equatable, Sendable {
    var viewportSize = CGSize.zero
    var safeAreaTop: CGFloat = 0
    var hasDivision = false
    var activeDivisionFrame: CGRect?
    var hasCornerCameraOcclusion = false
}

private nonisolated enum Today故事书架布局: Equatable, Sendable {
    case compact
    case wide
    case duoPortrait
    case duoPortraitFolded(shelfHeight: CGFloat)

    var usesWideCardStyle: Bool {
        switch self {
        case .compact:
            false
        case .wide, .duoPortrait, .duoPortraitFolded:
            true
        }
    }

    var foldedShelfHeight: CGFloat? {
        guard case .duoPortraitFolded(let shelfHeight) = self else {
            return nil
        }
        return shelfHeight
    }
}

private struct Today页眉容器<Content: View>: View {
    let state: Today页眉滚动状态
    let maxWidth: CGFloat
    let content: Content

    init(
        state: Today页眉滚动状态,
        maxWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.state = state
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .opacity(state.opacity)
            .allowsHitTesting(state.opacity > 0.05)
    }
}

struct Today页面: View {
    private static let isRunningForPreviews =
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    @Namespace private var namespace
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var todayModel = Today视图模型()
    @StateObject private var systemStatusModel = 系统状态视图模型()
    @StateObject private var relatedNameModel = Today关联名称视图模型()
    @StateObject private var recommendationModel = Today推荐视图模型()
    @StateObject private var quoteModel = Today语录视图模型()
    @StateObject private var eventModel = PaperVN活动视图模型()
    @State private var todayRecommendationState = PaperVNToday推荐状态()

    @AppStorage(为你推荐偏好分析设置.启用键)
    private var recommendationPreferenceAnalysisEnabled = true
    @AppStorage(PaperVNConnect自动策略.自动转发状态键)
    private var connectEnabled = false
    @AppStorage(活动地区偏好.设置键)
    private var activityRegionSelection = 活动地区偏好.默认值
    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage("todayPreviewDateOverride")
    private var todayPreviewDateOverride = ""
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var immersiveDetailAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }

    @State private var displayConfig = Today显示配置.load()
    @State private var quoteCharacterDestination: 探索语录角色?
    @State private var quoteVisualNovelDestination: 探索语录作品?
    @State private var selectedIntroductionStory: Today故事?
    @State private var selectedStoryDetailID: String?
    @State private var isTodayVisible = false
    @State private var todayHeaderScrollState = Today页眉滚动状态()
    @State private var loadedAuxiliaryContentIdentity: String?
    @State private var duoDisplayGeometry = TodayDuo显示几何()
    @State private var 显示Today推荐页面 = false

    private var contentIdentity: String {
        auth.token + "|" + auth.userID + "|"
            + String(recommendationPreferenceAnalysisEnabled) + "|"
            + String(connectEnabled) + "|"
            + activityRegionSelection + "|"
            + locale.identifier + "|" + todayPreviewDateOverride
    }

    private var relatedGlassPrimaryColor: Color {
        switch immersiveDetailAppearance {
        case .clear, .reduced:
            .white
        case .standard:
            colorScheme == .dark ? .white : .black
        }
    }

    private var activePreviewDate: String? {
        let date = todayPreviewDateOverride.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return Today日期工具.isValidFeedDate(date) ? date : nil
    }

    private var tomorrowFeedDate: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Today日期工具.timeZone
        let tomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: Date()
        ) ?? Date()
        return Today日期工具.string(from: tomorrow)
    }

    private var usesWideTodayLayout: Bool {
        horizontalSizeClass == .regular
            && (
                UIDevice.current.userInterfaceIdiom == .pad
                    || duoDisplayGeometry.hasDivision
            )
    }

    private var usesDuoInnerPortraitLayout: Bool {
        duoDisplayGeometry.hasDivision
            && duoDisplayGeometry.viewportSize.height
                > duoDisplayGeometry.viewportSize.width
    }

    private var usesFoldedDuoInnerPortraitLayout: Bool {
        guard usesDuoInnerPortraitLayout,
              let division = duoDisplayGeometry.activeDivisionFrame else {
            return false
        }
        return division.width > division.height
            && division.minY > 0
            && division.maxY < duoDisplayGeometry.viewportSize.height
    }

    private var usesFoldedDuoInnerLandscapeLayout: Bool {
        let size = duoDisplayGeometry.viewportSize
        guard duoDisplayGeometry.hasDivision,
              size.width > size.height,
              let division = duoDisplayGeometry.activeDivisionFrame else {
            return false
        }
        return division.height > division.width
            && division.minX > 0
            && division.maxX < size.width
    }

    private var usesDuoLandscapeNavigationTitle: Bool {
        let size = duoDisplayGeometry.viewportSize
        guard UIDevice.current.userInterfaceIdiom == .phone,
              size.width > size.height else {
            return false
        }
        return duoDisplayGeometry.hasDivision
            || duoDisplayGeometry.hasCornerCameraOcclusion
    }

    private var contentMaxWidth: CGFloat {
        usesWideTodayLayout ? .infinity : 680
    }

    @ViewBuilder
    private var todayScrollContent: some View {
        VStack(
            alignment: .leading,
            spacing: usesWideTodayLayout ? 22 : 26
        ) {
            if let document = systemStatusModel.document,
               document.summary(at: Date()) != nil {
                系统状态卡片(
                    document: document,
                    now: Date()
                )
            }

            Today推荐横幅(显示推荐页面: $显示Today推荐页面)

            todayStories

            if displayConfig.showEvents && todayHasResolved {
                PaperVN活动栏目(
                    events: eventModel.events,
                    isLoading: eventModel.isLoading,
                    hasLoaded: eventModel.hasLoaded,
                    errorMessage: eventModel.errorMessage,
                    cardScene: .today,
                    title: eventModel.isPersonalized
                        ? String(localized: "与你相关的活动")
                        : nil,
                    usesTwoColumnFoldLayout:
                        usesFoldedDuoInnerLandscapeLayout,
                    hidesWhenEmpty: true,
                    onRetry: {
                        Task {
                            await loadRecentDatedEvents(
                                forceRefresh: true
                            )
                        }
                    }
                )
            }

            if todayHasResolved && showsRecommendations {
                Today推荐列表(
                    items: Self.isRunningForPreviews
                        ? []
                        : recommendationModel.recommendations,
                    isLoading: Self.isRunningForPreviews
                        ? false
                        : recommendationModel.isLoading,
                    hasLoaded: Self.isRunningForPreviews
                        || recommendationModel.hasLoaded,
                    errorMessage: Self.isRunningForPreviews
                        ? nil
                        : recommendationModel.errorMessage,
                    usesWideLayout: usesWideTodayLayout,
                    onRetry: {
                        Task {
                            await loadCachedRecommendations()
                        }
                    }
                )
            }

            if todayHasResolved && displayConfig.showQuotes {
                Today语录栏目(
                    quote: quoteModel.quote,
                    isLoading: quoteModel.isLoading,
                    errorMessage: quoteModel.errorMessage,
                    onReload: {
                        Task { await quoteModel.load(forceRefresh: true) }
                    },
                    onSelectCharacter: { quoteCharacterDestination = $0 },
                    onSelectVisualNovel: { quoteVisualNovelDestination = $0 },
                    usesTodayContainerStyle: true,
                    usesWideLayout: usesWideTodayLayout,
                    usesEqualWidthColumns: usesFoldedDuoInnerLandscapeLayout
                )
            }
        }
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    var body: some View {
        ScrollView(.vertical) {
            todayScrollContent
        }
        .background(Color.平台分组背景.ignoresSafeArea())
        .scrollIndicators(.automatic)
        .平台柔和滚动边缘(for: .top)
        .modifier(TodayDuoGeometryModifier(geometry: $duoDisplayGeometry))
        .平台滚动几何变化(for: CGFloat.self) { geometry in
            let offset = max(
                0,
                geometry.contentOffset.y + geometry.contentInsets.top
            )
            let fadeStart: CGFloat = 8
            let fadeDistance: CGFloat = 52
            return min(
                1,
                max(0, 1 - (offset - fadeStart) / fadeDistance)
            )
        } action: { _, opacity in
            todayHeaderScrollState.opacity = opacity
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !usesDuoLandscapeNavigationTitle {
                Today页眉容器(
                    state: todayHeaderScrollState,
                    maxWidth: contentMaxWidth
                ) {
                    todayHeader
                }
            }
        }
        .sheet(item: $selectedIntroductionStory) { story in
            let imageURL = storyImageURL(for: story)
            Today介绍页面(
                story: story,
                imageURL: imageURL,
                description: storyDescription(for: story)
            )
            .平台近全屏弹窗(dragIndicator: .visible)
            .平台缩放转场(
                sourceID: introductionTransitionID(for: story),
                in: namespace
            )
        }
        .sheet(isPresented: $显示Today推荐页面) {
            Today推荐页面(vndbAccount: auth.vndb账户)
                .presentationDetents([.fraction(0.98)])
                .presentationBackgroundInteraction(.enabled)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .navigationDestination(item: $quoteCharacterDestination) { character in
            角色详情(
                characterID: character.id,
                auth: auth,
                initialName: character.name,
                initialOriginal: character.original,
                initialImage: character.image.map {
                    角色图片(
                        url: $0.url,
                        dims: $0.dims,
                        sexual: $0.sexual,
                        violence: $0.violence
                    )
                }
            )
        }
        .navigationDestination(item: $quoteVisualNovelDestination) { vn in
            视觉小说详情(
                vnID: vn.id,
                auth: auth,
                initialTitle: vn.title,
                initialTitles: vn.titles?.map {
                    用户多语言标题(
                        lang: $0.lang,
                        title: $0.title,
                        latin: $0.latin,
                        official: $0.official ?? false,
                        main: $0.main ?? false
                    )
                },
                initialImageURL: vn.image?.url,
                initialImageSexual: vn.image?.sexual,
                initialImageViolence: vn.image?.violence,
                initialImageDimensions: vn.image?.dims
            )
        }
        .navigationDestination(item: $selectedStoryDetailID) { storyID in
            if let story = todayModel.feed?.stories.first(where: {
                $0.id == storyID
            }) {
                storyVisualNovelDestination(story)
                    .平台缩放转场(
                        sourceID: storyDetailTransitionID(for: story),
                        in: namespace
                    )
            } else {
                平台内容不可用视图(
                    "Today不可用",
                    systemImage: "doc.text.image"
                )
            }
        }
        .task(id: contentIdentity) {
            await todayModel.load(
                localeIdentifier: locale.identifier,
                previewDate: activePreviewDate,
                connectEnabled: connectEnabled,
                forceRefresh: false
            )
            if 缓存策略.当前 == .more,
               let feed = todayModel.feed {
                VNDB服务.shared.prefetchVisualNovelGraph(
                    vnIDs: feed.stories.map(\.visualNovelID)
                )
            }
            guard loadedAuxiliaryContentIdentity != contentIdentity else {
                return
            }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }

            async let quoteLoad: Void = quoteModel.load()
            async let recommendationLoad: Void = loadCachedRecommendations()
            if Self.isRunningForPreviews {
                _ = await (quoteLoad, recommendationLoad)
            } else {
                async let eventLoad: Void = loadRecentDatedEvents()
                _ = await (quoteLoad, recommendationLoad, eventLoad)
            }
            if 缓存策略.当前 == .more {
                let storyIDs = todayModel.feed?.stories.map(\.visualNovelID) ?? []
                VNDB服务.shared.prefetchVisualNovelGraph(
                vnIDs: storyIDs + recommendationModel.recommendations.map(\.id)
                )
            }
            loadedAuxiliaryContentIdentity = contentIdentity
        }
        .task {
            guard !Self.isRunningForPreviews else { return }
            await systemStatusModel.load()
        }
        .task(id: todayModel.feed?.contentFingerprint) {
            await loadRelatedNamesIfAvailable()
        }
        .onChange(of: recommendationPreferenceAnalysisEnabled) { _, enabled in
            if !enabled {
                推荐后台分析中心.shared.停止分析()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            let shouldReloadToday = phase == ScenePhase.active && isTodayVisible
            guard shouldReloadToday else { return }
            Task {
                await todayModel.load(
                    localeIdentifier: locale.identifier,
                    previewDate: activePreviewDate,
                    connectEnabled: connectEnabled
                )
            }
        }
        .onAppear {
            isTodayVisible = true
            推荐后台分析中心.shared.设置Today分析暂停(true)
        }
        .onDisappear {
            isTodayVisible = false
            todayModel.cancelPrefetch()
        }
        .navigationTitle("Today")
        .平台柔和滚动边缘(for: .top)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(
            usesDuoLandscapeNavigationTitle ? .automatic : .hidden,
            for: .navigationBar
        )
        .toolbar {
            #if DEBUG
            if usesDuoLandscapeNavigationTitle {
                ToolbarItem(placement: .topBarTrailing) {
                    todayDatePreviewMenu
                }
            }
            #endif
        }
        .statusBarHidden(false)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .paperVNRecommendationsDidUpdate
            )
        ) { notification in
            guard let updatedUserID = notification.object as? String,
                  updatedUserID.caseInsensitiveCompare(auth.userID)
                    == .orderedSame,
                  !isTodayVisible else { return }
            Task {
                await recommendationModel.reloadCachedRecommendations(
                    userID: auth.userID
                )
            }
        }
    }

    private var todayHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Today")
                .font(.largeTitle.weight(.bold))
                .fixedSize()
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 12)

            #if DEBUG
            todayDatePreviewMenu
            .font(.title3.weight(.semibold))
            .液态玻璃按钮(in: Circle())
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .frame(width: 52, height: 52)
            #endif

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if DEBUG
    private var todayDatePreviewMenu: some View {
        Menu {
            Button {
                todayPreviewDateOverride = ""
            } label: {
                Label("使用联网日期", systemImage: "network")
            }

            Button {
                todayPreviewDateOverride = tomorrowFeedDate
            } label: {
                Label("预览明天", systemImage: "calendar.badge.clock")
            }
        } label: {
            Image(
                systemName: activePreviewDate == nil
                    ? "calendar.badge.clock"
                    : "calendar.badge.checkmark"
            )
        }
        .accessibilityLabel(
            activePreviewDate == nil ? "Today日期预览" : "正在预览Today日期"
        )
    }
    #endif

    @ViewBuilder
    private var todayStories: some View {
        if let feed = todayModel.feed {
            let groups = storyGroups(from: feed.stories)
            let shelfLayout = storyShelfLayout

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    switch shelfLayout {
                    case .duoPortraitFolded:
                        ForEach(feed.stories) { story in
                            storyUnit(
                                story,
                                isGrouped: false,
                                cardAspectRatio: Today布局.iPadCardAspectRatio
                            )
                            .containerRelativeFrame(
                                .horizontal,
                                count: 2,
                                span: 1,
                                spacing: 20
                            )
                        }
                    case .duoPortrait:
                        ForEach(feed.stories) { story in
                            storyUnit(
                                story,
                                isGrouped: false,
                                cardAspectRatio: Today布局.iPadCardAspectRatio
                            )
                            .containerRelativeFrame(
                                .horizontal,
                                count: 4,
                                span: 3,
                                spacing: 20
                            )
                        }
                    case .wide:
                        ForEach(feed.stories) { story in
                            storyUnit(
                                story,
                                isGrouped: false,
                                cardAspectRatio: Today布局.iPadCardAspectRatio
                            )
                            .containerRelativeFrame(
                                .horizontal,
                                count: 2,
                                span: 1,
                                spacing: 20
                            )
                        }
                    case .compact:
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, stories in
                            if stories.count > 1 {
                                groupedStoryUnit(stories)
                            } else if let story = stories.first {
                                storyUnit(story, isGrouped: false)
                            }
                        }
                        .containerRelativeFrame(
                            .horizontal,
                            count: 1,
                            span: 1,
                            spacing: 20
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .frame(
                height: shelfLayout.foldedShelfHeight,
                alignment: .top
            )
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(
                .viewAligned(limitBehavior: .平台逐个)
            )
            .Today横向书架适配()
        } else if todayModel.isTodayUnavailable {
            平台内容不可用视图 {
                Label("Today不可用", systemImage: "doc.text.image")
            } description: {
                Text("开发者太懒了还没有准备今天的Today内容～")
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(
                Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
        } else if todayModel.isUnsupportedContent {
            平台内容不可用视图 {
                Label("Today不可用", systemImage: "doc.text.image")
            } description: {
                Text("更新到最新版本以查看此页面。")
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(
                Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
        } else if let errorMessage = todayModel.errorMessage {
            平台内容不可用视图 {
                Label("Today不可用", systemImage: "wifi.exclamationmark")
            } description: {
                Text(verbatim: errorMessage)
            } actions: {
                Button("重试") {
                    Task {
                        await todayModel.load(
                            localeIdentifier: locale.identifier,
                            previewDate: activePreviewDate,
                            connectEnabled: connectEnabled,
                            forceRefresh: true
                        )
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(
                Color.secondary.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在载入…")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
                .accessibilityElement(children: .combine)
                Today故事加载骨架列表(layout: loadingStoryShelfLayout)
            }
        }
    }

    private var storyShelfLayout: Today故事书架布局 {
        if usesFoldedDuoInnerPortraitLayout {
            return foldedDuoPortraitShelfLayout()
        }
        if usesDuoInnerPortraitLayout {
            return .duoPortrait
        }
        return usesWideTodayLayout ? .wide : .compact
    }

    private var loadingStoryShelfLayout: Today故事书架布局 {
        if usesFoldedDuoInnerPortraitLayout {
            return foldedDuoPortraitShelfLayout()
        }
        if usesDuoInnerPortraitLayout {
            return .duoPortrait
        }
        return usesWideTodayLayout ? .wide : .compact
    }

    private func foldedDuoPortraitShelfLayout() -> Today故事书架布局 {
        guard let division = duoDisplayGeometry.activeDivisionFrame else {
            return .duoPortrait
        }
        let availableHeight = max(
            division.minY
                - duoDisplayGeometry.safeAreaTop
                - Today布局.duoPortraitHeaderAndContentInset
                - Today布局.duoFoldClearance,
            Today布局.duoMinimumFoldedShelfHeight
        )
        return .duoPortraitFolded(
            shelfHeight: availableHeight
        )
    }

    @ViewBuilder
    private func groupedStoryUnit(_ stories: [Today故事]) -> some View {
        let usesIPadStyle = usesWideTodayLayout
        let containerPadding = usesIPadStyle
            ? Today布局.iPadGroupedContainerPadding
            : Today布局.groupedContainerPadding
        let containerCornerRadius = usesIPadStyle
            ? Today布局.iPadGroupedContainerCornerRadius
            : Today布局.groupedContainerCornerRadius

        Group {
            if usesIPadStyle {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(stories) { story in
                        storyUnit(
                            story,
                            isGrouped: true,
                            cardAspectRatio: Today布局.iPadCardAspectRatio
                        )
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                LazyVStack(spacing: Today布局.groupedContainerPadding) {
                    ForEach(stories) { story in
                        storyUnit(story, isGrouped: true)
                    }
                }
            }
        }
        .padding(containerPadding)
        .background(
            Color.secondary.opacity(0.14),
            in: RoundedRectangle(
                cornerRadius: containerCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: containerCornerRadius,
                style: .continuous
            )
            .stroke(
                Color.primary.opacity(0.10),
                lineWidth: 0.5
            )
        }
    }

    private func storyGroups(from stories: [Today故事]) -> [[Today故事]] {
        var groups: [[Today故事]] = []

        for story in stories {
            guard let groupID = story.groupID?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), !groupID.isEmpty else {
                groups.append([story])
                continue
            }

            if let lastGroupID = groups.last?.first?.groupID?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ), lastGroupID == groupID {
                groups[groups.count - 1].append(story)
            } else {
                groups.append([story])
            }
        }

        return groups
    }

    @ViewBuilder
    private func storyUnit(
        _ story: Today故事,
        isGrouped: Bool,
        cardAspectRatio: CGFloat = Today布局.cardAspectRatio
    ) -> some View {
        let relatedItems = relatedItems(for: story)
        let imageURL = storyImageURL(for: story)
        let hasIntroduction = story.introduction != nil
        let transitionID = hasIntroduction
            ? introductionTransitionID(for: story)
            : storyDetailTransitionID(for: story)
        let openStory: (() -> Void) = {
            if hasIntroduction {
                selectedIntroductionStory = story
            } else {
                selectedStoryDetailID = story.id
            }
        }
        let accessibilityHint = hasIntroduction ? "查看Today介绍" : "查看详情"
        let cornerRadius = usesWideTodayLayout
            ? (isGrouped
                ? Today布局.iPadGroupedCardCornerRadius
                : Today布局.iPadStoryCornerRadius)
            : (isGrouped
                ? Today布局.groupedCardCornerRadius
                : Today布局.storyCornerRadius)
        let relatedContentHeight = Today布局.relatedContentHeight(
            itemCount: relatedItems.count
        )
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Today故事卡片(
                    story: story,
                    description: storyDescription(for: story),
                    attachedToRelatedContent: true,
                    cardAspectRatio: cardAspectRatio,
                    cornerRadius: cornerRadius,
                    transitionSourceID: transitionID,
                    transitionNamespace: namespace,
                    onOpen: openStory,
                    openAccessibilityHint: accessibilityHint
                )

                Color.clear
                    .frame(
                        height: relatedContentHeight
                            + Today布局.relatedGlassInset
                    )
            }

            relatedLinks(
                for: story,
                items: relatedItems,
                cornerRadius: cornerRadius
            )
        }
        .background {
            let coverBackground = Today故事封面背景(
                url: imageURL,
                relatedItemCount: relatedItems.count,
                cardAspectRatio: story.video == nil
                    ? cardAspectRatio
                    : Today布局.videoCardAspectRatio,
                bottomContentHeight: relatedContentHeight
                    + Today布局.relatedGlassInset
            )

            if story.video == nil {
                coverBackground
                    .平台匹配转场源(
                        id: transitionID,
                        in: namespace
                    )
            } else {
                coverBackground
            }
        }
        .平台卡片容器(
            background: isGrouped
                ? Color.平台系统背景
                : Color.secondary.opacity(0.07),
            stroke: Color.primary.opacity(0.08),
            cornerRadius: cornerRadius,
            lightModeShadowOpacity: 0,
            shadowRadius: 18,
            shadowY: 0
        )
    }

    private var showsRecommendations: Bool {
        recommendationPreferenceAnalysisEnabled
            && 为你推荐偏好分析设置.此设备支持
            && !auth.token.isEmpty
            && !auth.userID.isEmpty
    }

    private var todayHasResolved: Bool {
        todayModel.feed != nil
            || todayModel.isTodayUnavailable
            || todayModel.isUnsupportedContent
            || todayModel.errorMessage != nil
    }

    private func loadCachedRecommendations() async {
        guard showsRecommendations,
              !Self.isRunningForPreviews else {
            return
        }
        await recommendationModel.loadCachedRecommendations(
            userID: auth.userID
        )
    }

    private func loadRecentDatedEvents(
        forceRefresh: Bool = false
    ) async {
        await eventModel.loadForLibrary(
            token: auth.token,
            userID: auth.userID,
            forceRefresh: forceRefresh
        )
    }

    private func loadRelatedNamesIfAvailable() async {
        guard let feed = todayModel.feed else { return }
        await relatedNameModel.load(stories: feed.stories)
    }

    private func storyImageURL(for story: Today故事) -> URL? {
        story.image?.url
            ?? relatedNameModel.visualNovelNames[story.visualNovelID]?.imageURL
    }

    private func introductionTransitionID(for story: Today故事) -> String {
        "today.introduction.\(story.id)"
    }

    private func storyDetailTransitionID(for story: Today故事) -> String {
        "today.detail.\(story.id)"
    }

    private func storyDescription(for story: Today故事) -> AttributedString {
        let baseDescription = AttributedString(story.description)
        guard let character = story.related.first(where: { $0.type == .character }) else {
            return baseDescription
        }

        let matchedName = [character.title, character.original]
            .compactMap { $0 }
            .first { !$0.isEmpty && story.description.contains($0) }
        guard let matchedName,
              let range = story.description.range(of: matchedName) else {
            return baseDescription
        }

        let metadata = relatedNameModel.characterNames[character.id]
        let displayedCharacterName = 人物名称工具.显示名称(
            name: metadata?.name ?? character.title,
            original: metadata?.original ?? character.original,
            偏好: staffNameLang
        )
        func surroundingText(_ text: String) -> AttributedString {
            var result = AttributedString(text)
            result.font = .system(.title3, weight: .bold)
            return result
        }

        var result = surroundingText(String(story.description[..<range.lowerBound]))
        result.append(
            标题工具.生成富文本(
                文本: displayedCharacterName,
                isJapanese: staffNameLang == .original,
                基础大小: staffNameLang == .original
                    ? Today字体.birthdayJapaneseSize
                    : 20,
                是粗体: true,
                日文字体名称: "HiraginoSans-W6",
                系统字体粗细: .bold,
                语言来源已知: false,
                空格视为日语: true
            )
        )
        result.append(surroundingText(String(story.description[range.upperBound...])))
        return result
    }

    @ViewBuilder
    private func relatedLinks(
        for story: Today故事,
        items relatedItems: [Today关联内容],
        cornerRadius: CGFloat
    ) -> some View {
        let contentHeight = Today布局.relatedContentHeight(
            itemCount: relatedItems.count
        )
        let glassRowHeight = Today布局.relatedGlassRowHeight(
            itemCount: relatedItems.count
        )
        VStack(spacing: 0) {
            ForEach(Array(relatedItems.enumerated()), id: \.element.id) {
                index,
                item in
                HStack(spacing: 12) {
                    Image(systemName: relatedIcon(for: item.type))
                        .font(.headline)
                        .foregroundStyle(relatedGlassPrimaryColor.opacity(0.9))
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(relatedLabel(for: item.type))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(relatedGlassPrimaryColor.opacity(0.78))

                        relatedName(for: item)
                            .foregroundStyle(relatedGlassPrimaryColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    NavigationLink {
                        relatedDestination(item, story: story)
                    } label: {
                        Text("查看")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(relatedGlassPrimaryColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(
                                relatedGlassPrimaryColor.opacity(0.18),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .stroke(
                                        relatedGlassPrimaryColor.opacity(0.24),
                                        lineWidth: 0.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .frame(height: glassRowHeight)

                if index < relatedItems.count - 1 {
                    Rectangle()
                        .fill(relatedGlassPrimaryColor.opacity(0.22))
                        .frame(height: Today布局.relatedDividerHeight)
                        .padding(.leading, 52)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: contentHeight)
        .沉浸详情玻璃(
            immersiveDetailAppearance,
            in: RoundedRectangle(
                cornerRadius: max(
                    cornerRadius - Today布局.relatedGlassInset,
                    0
                ),
                style: .continuous
            )
        )
        .padding(.horizontal, Today布局.relatedGlassInset)
        .padding(.bottom, Today布局.relatedGlassInset)
    }

    private func relatedItems(for story: Today故事) -> [Today关联内容] {
        if story.related.contains(where: {
            $0.type == .visualNovel && $0.id == story.visualNovelID
        }) {
            return story.related
        }

        return [
            Today关联内容(
                type: .visualNovel,
                id: story.visualNovelID,
                title: story.accessibilityTitle,
                original: nil
            )
        ] + story.related
    }

    @ViewBuilder
    private func relatedName(for item: Today关联内容) -> some View {
        switch item.type {
        case .visualNovel:
            let metadata = relatedNameModel.visualNovelNames[item.id]
            let title = 标题工具.获取主标题(
                titles: metadata?.titles,
                defaultTitle: metadata?.title ?? item.title,
                偏好: preferredTitleLang,
                回退: fallbackTitleLang,
                允许非官方: allowUnofficialTitles
            )
            多语言列表文本(
                title,
                层级: .主标题,
                日文字体名称: "HiraginoSans-W6",
                系统字体粗细: .bold,
                语言来源已知: title.languageCode != nil
            )
        case .character:
            let metadata = relatedNameModel.characterNames[item.id]
            let name = 人物名称工具.显示名称(
                name: metadata?.name ?? item.title,
                original: metadata?.original ?? item.original,
                偏好: staffNameLang
            )
            多语言列表文本(
                文本: name,
                isJapanese: staffNameLang == .original,
                层级: .主标题,
                日文字体名称: "HiraginoSans-W6",
                系统字体粗细: .bold,
                语言来源已知: false,
                空格视为日语: true
            )
        }
    }

    @ViewBuilder
    private func relatedDestination(
        _ item: Today关联内容,
        story: Today故事
    ) -> some View {
        switch item.type {
        case .visualNovel:
            let metadata = relatedNameModel.visualNovelNames[item.id]
            视觉小说详情(
                vnID: item.id,
                auth: auth,
                initialTitle: metadata?.title ?? item.title,
                initialTitles: metadata?.titles,
                initialImageURL: metadata?.imageURL?.absoluteString
                    ?? storyImageURL(for: story)?.absoluteString,
                initialImageDimensions: metadata?.imageDimensions
            )
        case .character:
            let metadata = relatedNameModel.characterNames[item.id]
            角色详情(
                characterID: item.id,
                auth: auth,
                initialName: metadata?.name ?? item.title,
                initialOriginal: metadata?.original ?? item.original,
                initialImage: nil
            )
        }
    }

    private func relatedIcon(for type: Today关联类型) -> String {
        switch type {
        case .visualNovel: "books.vertical"
        case .character: "person.crop.rectangle.stack"
        }
    }

    private func relatedLabel(
        for type: Today关联类型
    ) -> LocalizedStringKey {
        switch type {
        case .visualNovel: "相关作品"
        case .character: "相关角色"
        }
    }

    private func storyVisualNovelDestination(
        _ story: Today故事
    ) -> some View {
        let metadata = relatedNameModel.visualNovelNames[story.visualNovelID]
        return 视觉小说详情(
            vnID: story.visualNovelID,
            auth: auth,
            initialTitle: metadata?.title ?? story.accessibilityTitle,
            initialTitles: metadata?.titles,
            initialImageURL: metadata?.imageURL?.absoluteString
                ?? storyImageURL(for: story)?.absoluteString,
            initialImageDimensions: metadata?.imageDimensions
        )
    }
}

private struct Today故事加载骨架列表: View {
    let layout: Today故事书架布局

    var body: some View {
        switch layout {
        case .duoPortraitFolded(let shelfHeight):
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(
                        Array([1, 2, 1, 1].enumerated()),
                        id: \.offset
                    ) { _, relatedItemCount in
                        Today故事加载骨架卡片(
                            relatedItemCount: relatedItemCount,
                            cardAspectRatio: Today布局.iPadCardAspectRatio,
                            cornerRadius: Today布局.iPadStoryCornerRadius
                        )
                        .containerRelativeFrame(
                            .horizontal,
                            count: 2,
                            span: 1,
                            spacing: 20
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .frame(height: shelfHeight, alignment: .top)
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(
                .viewAligned(limitBehavior: .平台逐个)
            )
            .Today横向书架适配()
        case .duoPortrait:
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(
                        Array([1, 2, 1, 1].enumerated()),
                        id: \.offset
                    ) { _, relatedItemCount in
                        Today故事加载骨架卡片(
                            relatedItemCount: relatedItemCount,
                            cardAspectRatio: Today布局.iPadCardAspectRatio,
                            cornerRadius: Today布局.iPadStoryCornerRadius
                        )
                        .containerRelativeFrame(
                            .horizontal,
                            count: 4,
                            span: 3,
                            spacing: 20
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(
                .viewAligned(limitBehavior: .平台逐个)
            )
            .Today横向书架适配()
        case .wide:
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    ForEach(
                        Array([1, 2, 1, 1].enumerated()),
                        id: \.offset
                    ) { _, relatedItemCount in
                        Today故事加载骨架卡片(
                            relatedItemCount: relatedItemCount,
                            cardAspectRatio: Today布局.iPadCardAspectRatio,
                            cornerRadius: Today布局.iPadStoryCornerRadius
                        )
                        .containerRelativeFrame(
                            .horizontal,
                            count: 2,
                            span: 1,
                            spacing: 20
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(
                .viewAligned(limitBehavior: .平台逐个)
            )
            .Today横向书架适配()
        case .compact:
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 20) {
                    Today故事加载骨架卡片(relatedItemCount: 1)
                        .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 20)
                    Today故事加载骨架卡片(relatedItemCount: 2)
                        .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 20)
                    groupedSkeleton
                        .containerRelativeFrame(.horizontal, count: 1, span: 1, spacing: 20)
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .平台逐个))
            .Today横向书架适配()
        }
    }

    private var singleColumnSkeleton: some View {
        VStack(spacing: 26) {
            Today故事加载骨架卡片(relatedItemCount: 1)
            Today故事加载骨架卡片(relatedItemCount: 2)
            groupedSkeleton
        }
    }

    @ViewBuilder
    private var groupedSkeleton: some View {
        let containerPadding = layout.usesWideCardStyle
            ? Today布局.iPadGroupedContainerPadding
            : Today布局.groupedContainerPadding
        let containerCornerRadius = layout.usesWideCardStyle
            ? Today布局.iPadGroupedContainerCornerRadius
            : Today布局.groupedContainerCornerRadius

        Group {
            if layout.usesWideCardStyle {
                HStack(alignment: .top, spacing: 20) {
                    groupedSkeletonCard
                    groupedSkeletonCard
                }
            } else {
                verticalGroupedSkeletonContent
            }
        }
        .padding(containerPadding)
        .background(
            Color.secondary.opacity(0.14),
            in: RoundedRectangle(
                cornerRadius: containerCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: containerCornerRadius,
                style: .continuous
            )
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var groupedSkeletonCard: some View {
        Today故事加载骨架卡片(
            relatedItemCount: 1,
            isGrouped: true,
            cardAspectRatio: layout.usesWideCardStyle
                ? Today布局.iPadCardAspectRatio
                : Today布局.cardAspectRatio,
            cornerRadius: layout.usesWideCardStyle
                ? Today布局.iPadGroupedCardCornerRadius
                : Today布局.groupedCardCornerRadius
        )
        .frame(maxWidth: .infinity)
    }

    private var verticalGroupedSkeletonContent: some View {
        VStack(spacing: Today布局.groupedContainerPadding) {
            groupedSkeletonCard
            groupedSkeletonCard
        }
    }
}

private struct Today故事加载骨架卡片: View {
    let relatedItemCount: Int
    var isGrouped = false
    var cardAspectRatio: CGFloat = Today布局.cardAspectRatio
    var cornerRadius: CGFloat = Today布局.storyCornerRadius

    var body: some View {
        let relatedContentHeight = Today布局.relatedContentHeight(
            itemCount: relatedItemCount
        )
        let relatedGlassRowHeight = Today布局.relatedGlassRowHeight(
            itemCount: relatedItemCount
        )

        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.secondary.opacity(0.12)

                VStack(alignment: .leading, spacing: 0) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.24))
                        .frame(width: 88, height: 14)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.24))
                            .frame(maxWidth: 250)
                            .frame(height: 19)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.20))
                            .frame(maxWidth: 180)
                            .frame(height: 19)
                    }
                }
                .padding(18)
            }
            .aspectRatio(cardAspectRatio, contentMode: .fit)

            ZStack(alignment: .bottom) {
                Color.secondary.opacity(0.12)

                VStack(spacing: 0) {
                    ForEach(0..<relatedItemCount, id: \.self) { index in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(height: Today布局.relatedDividerHeight)
                                .padding(.leading, 52)
                        }

                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.secondary.opacity(0.28))
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(
                                    cornerRadius: 4,
                                    style: .continuous
                                )
                                .fill(Color.secondary.opacity(0.28))
                                .frame(width: 60, height: 11)
                                RoundedRectangle(
                                    cornerRadius: 4,
                                    style: .continuous
                                )
                                .fill(Color.secondary.opacity(0.34))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: 15)
                            }

                            Spacer(minLength: 8)

                            RoundedRectangle(
                                cornerRadius: 12,
                                style: .continuous
                            )
                            .fill(Color.secondary.opacity(0.24))
                            .frame(width: 52, height: 30)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: relatedGlassRowHeight)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: relatedContentHeight)
                .background(
                    Color.secondary.opacity(0.10),
                    in: RoundedRectangle(
                        cornerRadius: max(
                            cornerRadius - Today布局.relatedGlassInset,
                            0
                        ),
                        style: .continuous
                    )
                )
                .padding(.horizontal, Today布局.relatedGlassInset)
                .padding(.bottom, Today布局.relatedGlassInset)
            }
            .frame(maxWidth: .infinity)
            .frame(height: relatedContentHeight + Today布局.relatedGlassInset)
        }
        .平台卡片容器(
            background: isGrouped
                ? Color.平台系统背景
                : Color.secondary.opacity(0.07),
            stroke: Color.primary.opacity(0.08),
            cornerRadius: cornerRadius,
            lightModeShadowOpacity: 0,
            shadowRadius: 18,
            shadowY: 0
        )
    }
}

private struct Today介绍页面: View {
    let story: Today故事
    let imageURL: URL?
    let description: AttributedString

    @Environment(\.dismiss) private var dismiss
    @State private var 投稿作者: String?

    init(
        story: Today故事,
        imageURL: URL?,
        description: AttributedString
    ) {
        self.story = story
        self.imageURL = imageURL
        self.description = description
    }

    var body: some View {
        NavigationStack {
            Group {
                if let introduction = story.introduction,
                   introduction.isSupported {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            Today介绍封面(
                                url: imageURL,
                                visualNovelID: story.visualNovelID,
                                eyebrow: story.eyebrow,
                                description: description,
                                releaseDate: story.releaseDate
                            )

                            Today介绍Markdown内容(
                                blocks: introduction.blocks,
                                author: introduction.author ?? 投稿作者
                            )
                            .frame(maxWidth: 680, alignment: .leading)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 24)
                            .padding(.top, 24)
                            .padding(.bottom, 36)
                        }
                    }
                    .coordinateSpace(name: "TodayIntroductionScroll")
                    .background(Color.平台系统背景)
                    .ignoresSafeArea(edges: .top)
                } else {
                    平台内容不可用视图 {
                        Label("Today不可用", systemImage: "doc.text.image")
                    } description: {
                        Text("更新到最新版本以查看此页面。")
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .平台柔和滚动边缘(for: .top)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .statusBarHidden(false)
        .task(id: story.id) {
            guard story.introduction?.author == nil else { return }
            let date = String(story.id.prefix(10))
            guard date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return }
            投稿作者 = try? await PaperVNToday推荐服务()
                .获取公开推荐(vnID: story.visualNovelID, displayDate: date)?.nickname
        }
    }
}

private struct Today介绍封面: View {
    let url: URL?
    let visualNovelID: String
    let eyebrow: String
    let description: AttributedString
    let releaseDate: String?

    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            let pullDistance = max(
                proxy.frame(in: .named("TodayIntroductionScroll")).minY,
                0
            )

            ZStack(alignment: .top) {
                if pullDistance > 0 {
                    Today介绍封面顶部模糊延展(
                        image: image,
                        width: proxy.size.width,
                        height: pullDistance + 64
                    )
                }

                ZStack {
                    Color.secondary.opacity(0.12)

                    if let image {
                        let cover = Image(decorative: image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: proxy.size.width, height: proxy.size.height)

                        ZStack {
                            cover

                            cover
                                .scaleEffect(1.10)
                                .blur(radius: 28)
                                .mask {
                                    LinearGradient(
                                        stops: [
                                            .init(color: .clear, location: 0.32),
                                            .init(color: .black.opacity(0.30), location: 0.58),
                                            .init(color: .black, location: 1)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                            }
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.56),
                                    .init(color: .black.opacity(0.42), location: 0.82),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                    }

                    LinearGradient(
                        colors: [.black.opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .allowsHitTesting(false)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: eyebrow)
                            .font(.subheadline.weight(.bold))

                        Spacer(minLength: 0)

                        Text(description)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let releaseDate {
                            Text(verbatim: releaseDate)
                                .font(.subheadline.weight(.semibold))
                                .opacity(0.88)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .padding(24)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(y: pullDistance)
            }
            .frame(
                width: proxy.size.width,
                height: proxy.size.height + pullDistance,
                alignment: .top
            )
            .offset(y: -pullDistance)
        }
        .frame(height: Today布局.introductionCoverHeight)
        .task(id: "\(url?.absoluteString ?? "")#\(visualNovelID)") {
            image = nil
            var imageURL = url
            if imageURL == nil {
                imageURL = try? await Today名称服务.shared
                    .fetchVisualNovelName(id: visualNovelID)
                    .imageURL
            }
            guard let imageURL else { return }
            do {
                let loadedImage = try await Today图片加载器.shared.image(
                    from: imageURL,
                    maximumPixelSize: 1_800
                )
                guard !Task.isCancelled else { return }
                image = loadedImage
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}

private struct Today介绍封面顶部模糊延展: View {
    let image: CGImage?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)

            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: Today布局.introductionCoverHeight)
                    .scaleEffect(1.10)
                    .blur(radius: 30)
                    .frame(
                        width: width,
                        height: height,
                        alignment: .top
                    )
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct Today介绍Markdown内容: View {
    let blocks: [Today介绍段落]
    var author: String? = nil
    @Environment(\.locale) private var locale

    private var attributedText: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var result = AttributedString()

        for block in blocks {
            var fragment = (
                try? AttributedString(
                    markdown: Today标准化Markdown换行(block.markdown),
                    options: options
                )
            ) ?? AttributedString(block.markdown)

            fragment.font = .body
            for run in fragment.runs {
                guard let intent = run.inlinePresentationIntent else {
                    continue
                }

                if intent.contains(.stronglyEmphasized),
                   intent.contains(.emphasized) {
                    fragment[run.range].font = .body.bold().italic()
                } else if intent.contains(.stronglyEmphasized) {
                    fragment[run.range].font = .body.bold()
                } else if intent.contains(.emphasized) {
                    fragment[run.range].font = .body.italic()
                }

                if intent.contains(.strikethrough) {
                    fragment[run.range].strikethroughStyle = Text.LineStyle(
                        pattern: .solid
                    )
                }
            }
            fragment.foregroundColor = block.style == .secondary
                ? .secondary
                : .primary
            result.append(fragment)
        }

        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines),
           !author.isEmpty {
            var credit = AttributedString("\n\n")
            credit.append(AttributedString(String(localized: "作者：\(author)", locale: locale)))
            credit.font = .body
            credit.foregroundColor = .secondary
            result.append(credit)
        }

        return result
    }

    var body: some View {
        Text(attributedText)
            .font(.body)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func Today标准化Markdown换行(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\\r\\n", with: "\n")
        .replacingOccurrences(of: "\\n", with: "\n")
        .replacingOccurrences(of: "/n", with: "\n")
}

private nonisolated enum Today布局 {
    static let cardAspectRatio: CGFloat = 1.00
    static let iPadCardAspectRatio: CGFloat = 4.0 / 3.0
    static let videoCardAspectRatio: CGFloat = 16.0 / 9.0
    static let duoPortraitHeaderAndContentInset: CGFloat = 86
    static let duoFoldClearance: CGFloat = 12
    static let duoMinimumFoldedShelfHeight: CGFloat = 220
    static let introductionCoverHeight: CGFloat = 440
    static let storyCornerRadius: CGFloat = 26
    static let iPadStoryCornerRadius: CGFloat = 28
    static let groupedContainerCornerRadius: CGFloat = 32
    static let iPadGroupedContainerCornerRadius: CGFloat = 24
    static let groupedContainerPadding: CGFloat = 16
    static let iPadGroupedContainerPadding: CGFloat = 12
    static let groupedCardCornerRadius: CGFloat = 16
    static let iPadGroupedCardCornerRadius: CGFloat = 12
    static let relatedRowHeight: CGFloat = 66
    static let storyImageMaximumPixelSize = 1_600
    static let storyImageBlurRadius = 48.0
    static let relatedRowHeightRatio: CGFloat = 0.12
    static let relatedGlassInset: CGFloat = 8
    static let relatedDividerHeight: CGFloat = 0.5

    static func relatedContentHeight(itemCount: Int) -> CGFloat {
        let dividerCount = max(itemCount - 1, 0)
        return relatedRowHeight * CGFloat(itemCount)
            + relatedDividerHeight * CGFloat(dividerCount)
    }

    static func relatedGlassRowHeight(itemCount: Int) -> CGFloat {
        let count = max(itemCount, 1)
        let dividerHeight = relatedDividerHeight * CGFloat(count - 1)
        return max(
            (
                relatedContentHeight(itemCount: count)
                    - dividerHeight
            ) / CGFloat(count),
            44
        )
    }

}

private enum Today字体 {
    static let birthdayJapaneseSize: CGFloat = 19
}

private struct Today故事卡片: View {
    let story: Today故事
    let description: AttributedString
    var attachedToRelatedContent = false
    let cardAspectRatio: CGFloat
    let cornerRadius: CGFloat
    let transitionSourceID: String
    let transitionNamespace: Namespace.ID
    let onOpen: (() -> Void)?
    let openAccessibilityHint: String

    var body: some View {
        let cardContent = Group {
            if let videoURL = story.video?.url {
                Today故事视频(
                    url: videoURL,
                    eyebrow: story.eyebrow,
                    description: description,
                    releaseDate: story.releaseDate,
                    accessibilityTitle: story.accessibilityTitle,
                    transitionSourceID: transitionSourceID,
                    transitionNamespace: transitionNamespace,
                    onOpen: onOpen,
                    openAccessibilityHint: openAccessibilityHint
                )
            } else if let onOpen {
                Button(action: onOpen) {
                    Today故事图片(
                        eyebrow: story.eyebrow,
                        description: description,
                        releaseDate: story.releaseDate
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                )
                .accessibilityLabel(story.accessibilityTitle)
                .accessibilityHint(Text(verbatim: openAccessibilityHint))
            } else {
                Today故事图片(
                    eyebrow: story.eyebrow,
                    description: description,
                    releaseDate: story.releaseDate
                )
            }
        }

        let attachedCardContent = Group {
            if attachedToRelatedContent {
                cardContent
            } else {
                cardContent
                    .clipShape(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
            }
        }
        Group {
            if story.video == nil {
                attachedCardContent.aspectRatio(
                    cardAspectRatio,
                    contentMode: .fit
                )
            } else {
                attachedCardContent
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

private nonisolated final class Today视频播放状态: @unchecked Sendable {
    static let shared = Today视频播放状态()

    private let lock = NSLock()
    private var positions: [String: Double] = [:]
    private var mutedValues: [String: Bool] = [:]

    func position(for key: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return positions[key] ?? 0
    }

    func setPosition(_ position: Double, for key: String) {
        guard position.isFinite, position >= 0 else { return }
        lock.lock()
        positions[key] = position
        lock.unlock()
    }

    func isMuted(for key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return mutedValues[key] ?? true
    }

    func setMuted(_ isMuted: Bool, for key: String) {
        lock.lock()
        mutedValues[key] = isMuted
        lock.unlock()
    }
}

@MainActor
private final class Today视频音频会话 {
    static let shared = Today视频音频会话()

    private var activePlayers: [String: Bool] = [:]

    func update(playerKey: String, isMuted: Bool) {
        activePlayers[playerKey] = isMuted
        configureSession()
    }

    func remove(playerKey: String) {
        activePlayers.removeValue(forKey: playerKey)
        if activePlayers.isEmpty {
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        } else {
            configureSession()
        }
    }

    private func configureSession() {
        let hasAudiblePlayer = activePlayers.values.contains(false)
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = hasAudiblePlayer
            ? .playback
            : .ambient

        try? session.setCategory(
            category,
            mode: .moviePlayback,
            options: [.mixWithOthers]
        )
    }
}

private actor Today视频缓存 {
    static let shared = Today视频缓存()

    private let fileManager = FileManager.default
    private let rootDirectory: URL
    private var downloadTasks: [String: Task<Void, Never>] = [:]
    private var lastCleanupDay: String?

    init() {
        let cachesDirectory = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        rootDirectory = cachesDirectory.appendingPathComponent(
            "PaperVNTodayVideos-v1",
            isDirectory: true
        )
        try? fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
    }

    func cleanupExpired() {
        let currentDay = Today日期工具.string(from: Date())
        guard lastCleanupDay != currentDay else { return }
        lastCleanupDay = currentDay
        guard let entries = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for entry in entries {
            guard entry.lastPathComponent != currentDay else { continue }
            try? fileManager.removeItem(at: entry)
        }
    }

    func playableURL(for remoteURL: URL) -> URL {
        cleanupExpired()

        let day = Today日期工具.string(from: Date())
        let targetURL = cacheTarget(for: remoteURL, day: day)

        return fileManager.fileExists(atPath: targetURL.path)
            ? targetURL
            : remoteURL
    }

    func cacheInBackground(_ remoteURL: URL) {
        cleanupExpired()

        let day = Today日期工具.string(from: Date())
        let directory = rootDirectory.appendingPathComponent(
            day,
            isDirectory: true
        )
        let targetURL = cacheTarget(for: remoteURL, day: day)
        let taskKey = "\(day)#\(remoteURL.absoluteString)"

        guard !fileManager.fileExists(atPath: targetURL.path),
              downloadTasks[taskKey] == nil else { return }

        let task = Task<Void, Never>(priority: .utility) { [self] in
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                let (temporaryURL, response) = try await URLSession.shared.download(
                    from: remoteURL
                )
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw Today服务错误.invalidResponse
                }
                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.moveItem(at: temporaryURL, to: targetURL)
            } catch {
            }
            downloadTasks[taskKey] = nil
        }
        downloadTasks[taskKey] = task
    }

    private func cacheTarget(for remoteURL: URL, day: String) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let extensionName = remoteURL.pathExtension.isEmpty
            ? "mp4"
            : remoteURL.pathExtension
        return rootDirectory
            .appendingPathComponent(day, isDirectory: true)
            .appendingPathComponent(
                "\(digest).\(extensionName)",
                isDirectory: false
            )
    }
}

private struct Today故事视频: View {
    let url: URL
    let eyebrow: String
    let description: AttributedString
    let releaseDate: String?
    let accessibilityTitle: String
    let transitionSourceID: String
    let transitionNamespace: Namespace.ID
    let onOpen: (() -> Void)?
    let openAccessibilityHint: String

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var timeObserver: Any?
    @State private var isMuted = true

    private let playbackState = Today视频播放状态.shared
    private let audioSession = Today视频音频会话.shared

    private var playbackKey: String {
        url.absoluteString
    }

    private var audioSessionKey: String {
        transitionSourceID + "#" + playbackKey
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                if let onOpen {
                    Button(action: onOpen) {
                        videoContent(size: proxy.size)
                    }
                    .buttonStyle(.plain)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .accessibilityLabel(accessibilityTitle)
                    .accessibilityHint(Text(verbatim: openAccessibilityHint))
                    .平台匹配转场源(
                        id: transitionSourceID,
                        in: transitionNamespace
                    )
                } else {
                    videoContent(size: proxy.size)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }

                Button {
                    let nextValue = !isMuted
                    isMuted = nextValue
                    playbackState.setMuted(nextValue, for: playbackKey)
                    audioSession.update(
                        playerKey: audioSessionKey,
                        isMuted: nextValue
                    )
                    player?.isMuted = nextValue
                } label: {
                    Image(
                        systemName: isMuted
                            ? "speaker.slash.fill"
                            : "speaker.wave.2.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                }
                .液态玻璃按钮(in: Circle())
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .frame(width: 44, height: 44)
                .accessibilityLabel(isMuted ? "解除静音" : "开启静音")
                .padding(12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(Today布局.videoCardAspectRatio, contentMode: .fit)
        .task(id: url) {
            guard player == nil else { return }

            let playableURL = await Today视频缓存.shared.playableURL(for: url)
            guard !Task.isCancelled, player == nil else { return }

            let queuePlayer = AVQueuePlayer()
            let item = AVPlayerItem(url: playableURL)
            let playerLooper = AVPlayerLooper(
                player: queuePlayer,
                templateItem: item
            )
            let muted = playbackState.isMuted(for: playbackKey)
            let savedPosition = playbackState.position(for: playbackKey)

            audioSession.update(playerKey: audioSessionKey, isMuted: muted)
            queuePlayer.isMuted = muted
            queuePlayer.actionAtItemEnd = .none
            isMuted = muted
            player = queuePlayer
            looper = playerLooper

            installTimeObserver(on: queuePlayer)

            if savedPosition > 0 {
                await queuePlayer.seek(
                    to: CMTime(seconds: savedPosition, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
            queuePlayer.play()

            if !playableURL.isFileURL {
                await Today视频缓存.shared.cacheInBackground(url)
            }
        }
        .onAppear {
            if let player {
                installTimeObserver(on: player)
                player.play()
            }
        }
        .onDisappear {
            saveAndPause()
            audioSession.remove(playerKey: audioSessionKey)
            if let timeObserver,
               let player {
                player.removeTimeObserver(timeObserver)
                self.timeObserver = nil
            }
        }
    }

    @ViewBuilder
    private func videoContent(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                } else {
                    Color.secondary.opacity(0.12)
                        .frame(width: size.width, height: size.height)
                }
            }
            .background(Color.secondary.opacity(0.12))

            LinearGradient(
                colors: [.black.opacity(0.34), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 112)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                Text(description)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let releaseDate {
                    Text(verbatim: releaseDate)
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.88)
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
            .allowsHitTesting(false)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .bottomLeading
            )
            .padding(18)

            Text(verbatim: eyebrow)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 1)
                .padding(18)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private func installTimeObserver(on player: AVQueuePlayer) {
        guard timeObserver == nil else { return }
        let state = playbackState
        let key = playbackKey
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 2),
            queue: .main
        ) { time in
            guard time.isNumeric else { return }
            state.setPosition(time.seconds, for: key)
        }
    }

    private func saveAndPause() {
        guard let player else { return }
        let time = player.currentTime()
        if time.isNumeric {
            playbackState.setPosition(time.seconds, for: playbackKey)
        }
        player.pause()
    }
}

private struct Today故事封面背景: View {
    let url: URL?
    let relatedItemCount: Int
    let cardAspectRatio: CGFloat
    let bottomContentHeight: CGFloat

    @State private var image: CGImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.secondary.opacity(0.12)

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: proxy.size.height
                        )
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.36),
                        .init(color: .black.opacity(0.18), location: 0.58),
                        .init(color: .black.opacity(0.38), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(
                id: "\(url?.absoluteString ?? "")#related=\(relatedItemCount)#width=\(Int(proxy.size.width.rounded()))"
            ) {
                guard let url, proxy.size.width > 0 else { return }
                do {
                    let images = try await Today图片加载器.shared.storyImages(
                        from: url,
                        relatedItemCount: relatedItemCount,
                        cardAspectRatio: cardAspectRatio,
                        relatedHeightRatio: bottomContentHeight
                            / proxy.size.width
                    )
                    guard !Task.isCancelled else { return }
                    image = images.full
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}

private struct Today故事图片: View {
    let eyebrow: String
    let description: AttributedString
    let releaseDate: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [.black.opacity(0.18), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * 0.30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: eyebrow)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.28), radius: 3, y: 1)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(description)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if let releaseDate {
                            Text(verbatim: releaseDate)
                                .font(.subheadline.weight(.semibold))
                                .opacity(0.88)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: .leading
                )
                .padding(18)
            }
            .clipped()
        }
    }
}

private struct Today推荐列表: View {
    let items: [探索推荐]
    let isLoading: Bool
    let hasLoaded: Bool
    let errorMessage: String?
    let usesWideLayout: Bool
    let onRetry: () -> Void

    @EnvironmentObject private var auth: 用户登录
    @AppStorage("contentFilterEnabled")
    private var contentFilterEnabled = false
    @AppStorage("sexualThreshold")
    private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold")
    private var violenceThreshold: Double = 1
    @AppStorage("filterMode")
    private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var contentRestrictionMethod: 内容限制方式 = .blurred
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()
    @State private var revealedCoverIDs: Set<String> = []

    private var visibleItems: [探索推荐] {
        Array(items.prefix(12))
    }

    private let containerCornerRadius: CGFloat = 28

    private var rowContentInset: CGFloat {
        usesWideLayout ? 12 : 14
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("为你推荐")
                    .font(.title2.weight(.bold))

                if isLoading && !items.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Group {
                if visibleItems.isEmpty {
                    emptyContent
                } else {
                    VStack(spacing: 0) {
                        ForEach(
                            Array(visibleItems.enumerated()),
                            id: \.element.id
                        ) { index, recommendation in
                            recommendationLink(
                                recommendation,
                                isCoverRevealed: revealedCoverIDs.contains(
                                    recommendation.id
                                ),
                                usesCompactDisclosure: true
                            )

                            if index < visibleItems.count - 1 {
                                Divider()
                                    .padding(.leading, 90)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .平台卡片容器(
                        background: Color.平台次级分组背景,
                        stroke: .clear,
                        cornerRadius: containerCornerRadius,
                        lightModeShadowOpacity: 0,
                        shadowRadius: 10,
                        shadowY: 0
                    )
                }
            }
        }
        .accessibilityIdentifier("today.recommendations")
        .overlay(alignment: .bottom) {
            模糊解除提示(
                isPresented: blurRevealConfirmation.isPromptVisible
            )
            .padding(.bottom, 18)
        }
        .onDisappear {
            blurRevealConfirmation.cancel()
            revealedCoverIDs.removeAll()
        }
    }

    private func recommendationLink(
        _ recommendation: 探索推荐,
        isCoverRevealed: Bool,
        usesCompactDisclosure: Bool = false
    ) -> some View {
        let item = recommendation.visualNovel

        return NavigationLink {
            视觉小说详情(
                vnID: item.id,
                auth: auth,
                initialTitle: item.title,
                initialTitles: item.详情多语言标题,
                initialImageURL: item.image?.url,
                initialImageSexual: item.image?.sexual,
                initialImageViolence: item.image?.violence,
                initialImageDimensions: item.image?.dims,
                isFromRecommendation: true
            )
        } label: {
            Today推荐行(
                item: item,
                isRestricted: imageIsRestricted(for: item)
                    && !isCoverRevealed,
                restrictionMethod: contentRestrictionMethod,
                revealCover: {
                    blurRevealConfirmation.request(id: "today-cover-\(item.id)") {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            let _ = revealedCoverIDs.insert(item.id)
                        }
                    }
                },
                canRevealCover: imageCanBeRevealed(for: item),
                usesCompactDisclosure: usesCompactDisclosure
            )
            .padding(rowContentInset)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func imageCanBeRevealed(for item: 探索视觉小说) -> Bool {
        内容安全限制判定.图片允许手动解除模糊(
            sexual: item.image?.sexual,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            mode: filterMode
        )
    }

    private func imageIsRestricted(for item: 探索视觉小说) -> Bool {
        内容安全限制判定.图片需要限制(
            sexual: item.image?.sexual,
            violence: item.image?.violence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
    }

    @ViewBuilder
    private var emptyContent: some View {
        if let errorMessage {
            探索加载失败提示(
                message: errorMessage,
                retry: onRetry
            )
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(18)
            .background(
                Color.平台次级分组背景,
                in: RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)
            )
        } else if !hasLoaded || isLoading {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text("正在准备推荐…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                Color.平台次级分组背景,
                in: RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)
            )
        } else {
            平台内容不可用视图(
                "暂无推荐",
                systemImage: "sparkles.rectangle.stack"
            )
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                Color.平台次级分组背景,
                in: RoundedRectangle(cornerRadius: containerCornerRadius, style: .continuous)
            )
        }
    }
}

private struct Today推荐行: View {
    let item: 探索视觉小说
    let isRestricted: Bool
    let restrictionMethod: 内容限制方式
    let revealCover: () -> Void
    let canRevealCover: Bool
    var usesCompactDisclosure = false

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var coverCornerRadius: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad
            && horizontalSizeClass == .regular ? 10 : 16
    }

    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false

    private var displayedTitle: 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: item.详情多语言标题,
            defaultTitle: item.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Today异步图片(
                    url: URL(string: item.image?.url ?? item.image?.thumbnail ?? ""),
                    maximumPixelSize: 1_200
                )
                .frame(width: 72, height: 100)
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: coverCornerRadius,
                        style: .continuous
                    )
                )
                .应用不安全内容限制(
                    isRestricted,
                    method: restrictionMethod,
                    blurRadius: 16
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: coverCornerRadius,
                        style: .continuous
                    )
                )

                if isRestricted && canRevealCover {
                    Color.clear
                        .contentShape(
                            RoundedRectangle(
                                cornerRadius: coverCornerRadius,
                                style: .continuous
                            )
                        )
                        .onTapGesture(perform: revealCover)
                        .accessibilityLabel("轻触两次以解除模糊")
                }
            }
            .frame(width: 72, height: 100)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: coverCornerRadius,
                    style: .continuous
                )
            )

            VStack(alignment: .leading, spacing: 4) {
                多语言列表文本(
                    displayedTitle,
                    层级: .主标题,
                    日文字体名称: "HiraginoSans-W5",
                    系统字体粗细: displayedTitle.languageCode
                        == 标题语言.chinese.langCode ? .medium : nil,
                    语言来源已知: displayedTitle.languageCode != nil
                )
                    .lineLimit(2)

                if let developer = item.developers?.first?.name {
                    Text(verbatim: developer)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    视觉小说统一评分标签(
                        vndbID: item.id,
                        vndbRating: item.rating,
                        vndbVoteCount: item.voteCount
                    )
                    if let released = item.released {
                        探索元数据(systemImage: "calendar", text: released)
                    }
                }
            }

            Spacer(minLength: 0)
            if usesCompactDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
            } else {
                Text("查看")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.1), in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }
}

private struct Today异步图片: View {
    let url: URL?
    var maximumPixelSize = 1_200

    var body: some View {
        Today加载图片(url: url, maximumPixelSize: maximumPixelSize) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        .clipped()
    }
}

private nonisolated final class Today故事图片资源: @unchecked Sendable {
    let full: CGImage

    init(full: CGImage) {
        self.full = full
    }

    var memoryCost: Int {
        full.bytesPerRow * full.height
    }
}

private actor Today图片加载器 {
    static let shared = Today图片加载器()

    private let cache = NSCache<NSString, CGImage>()
    private let storyCache = NSCache<NSString, Today故事图片资源>()
    private let diskCacheDirectory: URL
    private let maximumConcurrentLoads = 2
    private let maximumConcurrentStoryRenders = 1
    private var activeLoadCount = 0
    private var activeStoryRenderCount = 0
    private var imageTasks: [String: Task<CGImage, Error>] = [:]
    private var dataTasks: [URL: Task<Data, Error>] = [:]
    private var storyTasks: [String: Task<Today故事图片资源, Error>] = [:]
    private var lastDiskCleanupDay: String?

    init() {
        let cachesRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        diskCacheDirectory = cachesRoot.appendingPathComponent(
            "PaperVNTodayImages-v1",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(
            at: diskCacheDirectory,
            withIntermediateDirectories: true
        )
        cache.countLimit = 48
        cache.totalCostLimit = 64 * 1_024 * 1_024
        storyCache.countLimit = 6
        storyCache.totalCostLimit = 96 * 1_024 * 1_024
    }

    func prefetch(stories: [Today故事]) async {
        for story in stories {
            guard !Task.isCancelled else { return }
            guard let url = story.image?.url else { continue }
            do {
                _ = try await storyImages(
                    from: url,
                    relatedItemCount: story.displayedRelatedItemCount
                )
            } catch is CancellationError {
                return
            } catch {
                continue
            }
        }
    }

    func storyImages(
        from url: URL,
        relatedItemCount: Int,
        cardAspectRatio: CGFloat = Today布局.cardAspectRatio,
        relatedHeightRatio: CGFloat? = nil
    ) async throws -> Today故事图片资源 {
        let itemCount = max(1, relatedItemCount)
        let resolvedRelatedHeightRatio = max(
            relatedHeightRatio
                ?? Today布局.relatedRowHeightRatio * CGFloat(itemCount),
            0
        )
        let key = "\(url.absoluteString)#cardRatio=\(cardAspectRatio)#relatedRatio=\(resolvedRelatedHeightRatio)"
        let cacheKey = key as NSString
        if let cached = storyCache.object(forKey: cacheKey) {
            return cached
        }
        if let task = storyTasks[key] {
            return try await task.value
        }

        let task = Task<Today故事图片资源, Error>(priority: .utility) { [self] in
            try await renderStoryImages(
                from: url,
                cardAspectRatio: cardAspectRatio,
                relatedHeightRatio: resolvedRelatedHeightRatio
            )
        }
        storyTasks[key] = task
        defer { storyTasks[key] = nil }

        let images = try await task.value
        storyCache.setObject(
            images,
            forKey: cacheKey,
            cost: images.memoryCost
        )
        return images
    }

    func image(from url: URL, maximumPixelSize: Int) async throws -> CGImage {
        let key = "\(url.absoluteString)#\(maximumPixelSize)"
        let cacheKey = key as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }
        if let task = imageTasks[key] {
            return try await task.value
        }

        let task = Task<CGImage, Error>(priority: .utility) { [self] in
            try await loadImage(from: url, maximumPixelSize: maximumPixelSize)
        }
        imageTasks[key] = task
        defer { imageTasks[key] = nil }

        let image = try await task.value
        cache.setObject(
            image,
            forKey: cacheKey,
            cost: image.bytesPerRow * image.height
        )
        return image
    }

    private func loadImage(
        from url: URL,
        maximumPixelSize: Int
    ) async throws -> CGImage {
        let data = try await imageData(from: url)

        let image = try await Task.detached(priority: .utility) {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(
                data as CFData,
                sourceOptions
            ) else {
                throw Today服务错误.invalidContent
            }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions
            ) else {
                throw Today服务错误.invalidContent
            }
            return image
        }.value
        return image
    }

    private func renderStoryImages(
        from url: URL,
        cardAspectRatio: CGFloat,
        relatedHeightRatio: CGFloat
    ) async throws -> Today故事图片资源 {
        let data = try await imageData(from: url)
        try await acquireStoryRenderSlot()
        defer { releaseStoryRenderSlot() }

        let maximumPixelSize = Today布局.storyImageMaximumPixelSize
        let blurRadius = Today布局.storyImageBlurRadius

        return try await Task.detached(priority: .utility) {
            let sourceOptions = [
                kCGImageSourceShouldCache: false
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(
                data as CFData,
                sourceOptions
            ) else {
                throw Today服务错误.invalidContent
            }
            let thumbnailOptions = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
            ] as CFDictionary
            guard let decodedImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                thumbnailOptions
            ) else {
                throw Today服务错误.invalidContent
            }

            let sourceImage = CIImage(cgImage: decodedImage)
            let outputWidth = CGFloat(decodedImage.width)
            let cardHeight = floor(outputWidth / cardAspectRatio)
            let relatedHeight = max(
                1,
                floor(
                    outputWidth * relatedHeightRatio
                )
            )
            let extent = CGRect(
                x: 0,
                y: 0,
                width: outputWidth,
                height: cardHeight + relatedHeight
            )
            let scale = max(
                extent.width / sourceImage.extent.width,
                extent.height / sourceImage.extent.height
            )
            let scaledImage = sourceImage.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
            let baseImage = scaledImage
                .transformed(
                    by: CGAffineTransform(
                        translationX: extent.midX - scaledImage.extent.midX,
                        y: extent.midY - scaledImage.extent.midY
                    )
                )
                .cropped(to: extent)
            let blurredImage = baseImage
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: blurRadius]
                )
                .cropped(to: extent)
            let context = CIContext(options: [
                .useSoftwareRenderer: true,
                .cacheIntermediates: false
            ])
            guard let renderedBlurredImage = context.createCGImage(
                blurredImage,
                from: extent
            ) else {
                throw Today服务错误.invalidContent
            }

            guard let gradientMask = CIFilter(
                name: "CISmoothLinearGradient",
                parameters: [
                    "inputPoint0": CIVector(
                        x: extent.midX,
                        y: extent.minY
                    ),
                    "inputColor0": CIColor(
                        red: 1,
                        green: 1,
                        blue: 1,
                        alpha: 1
                    ),
                    "inputPoint1": CIVector(
                        x: extent.midX,
                        y: relatedHeight + cardHeight * 0.58
                    ),
                    "inputColor1": CIColor(
                        red: 0,
                        green: 0,
                        blue: 0,
                        alpha: 0
                    )
                ]
            )?.outputImage?.cropped(to: extent) else {
                throw Today服务错误.invalidContent
            }
            let renderedBlurredCIImage = CIImage(cgImage: renderedBlurredImage)
            let fullImage = renderedBlurredCIImage.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: baseImage,
                    kCIInputMaskImageKey: gradientMask
                ]
            )
            guard let renderedFullImage = context.createCGImage(
                fullImage,
                from: extent
            ) else {
                throw Today服务错误.invalidContent
            }

            return Today故事图片资源(
                full: renderedFullImage
            )
        }.value
    }

    private func imageData(from url: URL) async throws -> Data {
        if let task = dataTasks[url] {
            return try await task.value
        }

        let task = Task<Data, Error>(priority: .utility) { [self] in
            try await loadData(from: url)
        }
        dataTasks[url] = task
        defer { dataTasks[url] = nil }
        return try await task.value
    }

    private func loadData(from url: URL) async throws -> Data {
        cleanupExpiredDiskImages()
        let cachedURL = diskURL(for: url)
        if let cachedData = try? Data(contentsOf: cachedURL),
           !cachedData.isEmpty {
            return cachedData
        }

        try await acquireLoadSlot()
        defer { releaseLoadSlot() }

        var request = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy,
            timeoutInterval: 30
        )
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (downloadedData, response) = try await PaperVNConnect网络设置
            .发送图片请求(
                request,
                session: .shared
            )
        guard (200...299).contains(response.statusCode),
              !downloadedData.isEmpty else {
            throw Today服务错误.invalidResponse
        }
        persistData(downloadedData, to: cachedURL)
        return downloadedData
    }

    private func cleanupExpiredDiskImages() {
        let currentDay = Today日期工具.string(from: Date())
        guard lastDiskCleanupDay != currentDay else { return }
        lastDiskCleanupDay = currentDay
        let daysToKeep = 缓存策略.当前 == .more ? 2 : 1
        let cutoff = Date().addingTimeInterval(
            -TimeInterval(daysToKeep) * 24 * 60 * 60
        )
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: diskCacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        for file in files {
            let modified = (try? file.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? nil
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func acquireLoadSlot() async throws {
        while activeLoadCount >= maximumConcurrentLoads {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        activeLoadCount += 1
    }

    private func releaseLoadSlot() {
        activeLoadCount = max(0, activeLoadCount - 1)
    }

    private func acquireStoryRenderSlot() async throws {
        while activeStoryRenderCount >= maximumConcurrentStoryRenders {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        activeStoryRenderCount += 1
    }

    private func releaseStoryRenderSlot() {
        activeStoryRenderCount = max(0, activeStoryRenderCount - 1)
    }

    private func diskURL(for url: URL) -> URL {
        let safeKey = url.absoluteString.replacingOccurrences(
            of: "[^A-Za-z0-9._-]",
            with: "_",
            options: .regularExpression
        )
        return diskCacheDirectory
            .appendingPathComponent(safeKey)
            .appendingPathExtension("image")
    }

    private func persistData(_ data: Data, to url: URL) {
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

}

private struct Today加载图片<Content: View>: View {
    let url: URL?
    let maximumPixelSize: Int
    @ViewBuilder let content: (Image) -> Content

    @State private var image: CGImage?
    var body: some View {
        Group {
            if let image {
                content(Image(decorative: image, scale: 1))
            } else {
                Color.secondary.opacity(0.12)
            }
        }
        .task(id: url) {
            guard image == nil else { return }
            guard let url else {
                return
            }
            do {
                image = try await Today图片加载器.shared.image(
                    from: url,
                    maximumPixelSize: maximumPixelSize
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }
}

private struct TodayDuoGeometryModifier: ViewModifier {
    @Binding var geometry: TodayDuo显示几何

    func body(content: Content) -> some View {
        #if compiler(>=6.5)
        if #available(iOS 27.1, *) {
            content
                .onGeometryChange(for: TodayDuo显示几何.self) { proxy in
                    let divisions = proxy.reservedRegions(
                        kind: .division,
                        options: [.includeInactive]
                    )
                    let occlusions = proxy.reservedRegions(
                        kind: .occlusion,
                        options: [.includeInactive]
                    )
                    let size = proxy.size
                    let hasCornerCameraOcclusion = occlusions.contains { region in
                        let midX = region.frame.midX
                        return midX < size.width / 3
                            || midX > size.width * 2 / 3
                    }
                    return TodayDuo显示几何(
                        viewportSize: size,
                        safeAreaTop: proxy.safeAreaInsets.top,
                        hasDivision: !divisions.isEmpty,
                        activeDivisionFrame: divisions.first(where: \.isActive)?.frame,
                        hasCornerCameraOcclusion: hasCornerCameraOcclusion
                    )
                } action: { newGeometry in
                    geometry = newGeometry
                }
        } else {
            content
                .onGeometryChange(for: TodayDuo显示几何.self) { proxy in
                    TodayDuo显示几何(viewportSize: proxy.size)
                } action: { newGeometry in
                    geometry = newGeometry
                }
        }
        #else
        content
            .onGeometryChange(for: TodayDuo显示几何.self) { proxy in
                TodayDuo显示几何(viewportSize: proxy.size)
            } action: { newGeometry in
                geometry = newGeometry
            }
        #endif
    }
}

private struct Today显示设置: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var config: Today显示配置

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("最近活动", isOn: $config.showEvents)
                    Toggle("随机语录", isOn: $config.showQuotes)
                } header: {
                    Text("显示模块")
                } footer: {
                    Text("选择要在Today页面中显示的内容模块")
                }
            }
            .navigationTitle("Today显示设置")
            .平台柔和滚动边缘(for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        config.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

nonisolated enum Today推荐语言: String, Codable, CaseIterable, Identifiable, Sendable {
    case 简体中文 = "zh-Hans"
    case 繁体中文 = "zh-Hant"
    case 日语 = "ja"
    case 韩语 = "ko"
    case 英语 = "en"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .简体中文: "简体中文"
        case .繁体中文: "繁體中文"
        case .日语: "日本語"
        case .韩语: "한국어"
        case .英语: "English"
        }
    }

    static func 当前语言(_ locale: Locale) -> Self {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if identifier.hasPrefix("zh") {
            return identifier.contains("hant") || identifier.contains("tw")
                || identifier.contains("hk") || identifier.contains("mo") ? .繁体中文 : .简体中文
        }
        return allCases.first { identifier.hasPrefix($0.rawValue) } ?? .英语
    }
}

nonisolated struct Today推荐多语言内容: Codable, Sendable {
    var description: [String: String]
    var introduction: [String: String]

    func 标题(locale: Locale, fallback: String) -> String {
        Self.文本(description, locale: locale, fallback: fallback)
    }

    func 正文(locale: Locale, fallback: String) -> String {
        Self.文本(introduction, locale: locale, fallback: fallback)
    }

    private static func 文本(_ values: [String: String], locale: Locale, fallback: String) -> String {
        let language = Today推荐语言.当前语言(locale)
        return values[language.rawValue] ?? values["default"] ?? fallback
    }
}

private struct Today推荐正文: View {
    let description: String
    let author: String?
    @Environment(\.locale) private var locale

    private var text: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var result = (
            try? AttributedString(
                markdown: Today标准化Markdown换行(description),
                options: options
            )
        ) ?? AttributedString(description)

        result.font = .body
        for run in result.runs {
            guard let intent = run.inlinePresentationIntent else { continue }

            if intent.contains(.stronglyEmphasized),
               intent.contains(.emphasized) {
                result[run.range].font = .body.bold().italic()
            } else if intent.contains(.stronglyEmphasized) {
                result[run.range].font = .body.bold()
            } else if intent.contains(.emphasized) {
                result[run.range].font = .body.italic()
            }

            if intent.contains(.strikethrough) {
                result[run.range].strikethroughStyle = Text.LineStyle(
                    pattern: .solid
                )
            }
        }
        result.foregroundColor = .primary

        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            var credit = AttributedString("\n\n" + String(localized: "作者：\(author)", locale: locale))
            credit.font = .body
            credit.foregroundColor = .secondary
            result.append(credit)
        }
        return result
    }

    var body: some View {
        Text(text)
        .font(.body)
        .lineSpacing(5)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

fileprivate enum Today推荐状态: String, Codable, Sendable {
    case pending = "pending"
    case approved = "approved"
    case rejected = "rejected"
    case canceled = "canceled"
}

fileprivate struct Today推荐项目: Decodable, Identifiable, Sendable {
    let submissionNumber: Int
    let vndbID: String
    let vndbUsername: String?
    let nickname: String?
    let vnID: String
    let vnTitle: String
    let description: String
    let title: String?
    let defaultLanguage: String?
    let submissionTranslations: Today推荐多语言内容?
    let visualNovelImage: String?
    let submittedAt: String
    let status: Today推荐状态
    let displayDate: String?
    let reviewNote: String?

    var id: Int { submissionNumber }

    var displayID: String { "T\(submissionNumber)" }

    var displayName: String {
        vndbUsername ?? "匿名"
    }

    func localizedTitle(locale: Locale) -> String {
        submissionTranslations?.标题(locale: locale, fallback: title ?? vnTitle) ?? title ?? vnTitle
    }

    func localizedDescription(locale: Locale) -> String {
        submissionTranslations?.正文(locale: locale, fallback: description) ?? description
    }

    var statusText: String {
        switch status {
        case .pending: return "已提交"
        case .approved:
            guard let displayDate,
                  !displayDate.isEmpty,
                  displayDate <= Today日期工具.string(from: Date()) else {
                return "已通过"
            }
            return "已展示"
        case .rejected: return "已拒绝"
        case .canceled: return "已取消"
        }
    }

    var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        case .canceled: return .secondary
        }
    }
}

private struct Today公开推荐内容: Decodable, Sendable {
    let vnID: String
    let vnTitle: String
    let nickname: String?
    let description: String
    let title: String?
    let translations: Today推荐多语言内容?
    let displayDate: String?

    func localizedDescription(locale: Locale) -> String {
        translations?.正文(locale: locale, fallback: description) ?? description
    }
}

private func 标准化视觉小说ID(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    let suffix = trimmed.drop { character in
        character == "v" || character == "V"
    }
    return "v\(suffix)"
}

private struct Today提交资格: Decodable, Sendable {
    let available: Bool
    let canSubmit: Bool
    let dailyCount: Int?
    let dailyLimit: Int
    let error: Today提交资格错误?
    let warning: Today提交资格错误?

    var isAllowed: Bool {
        available && canSubmit
    }
}

private struct Today提交资格错误: Decodable, Sendable {
    let type: String
    let message: String
}

private struct PaperVNToday推荐服务 {
    private let baseURL = URL(string: "https://papervn.jizpaper.com/api/")!

    enum ServiceError: LocalizedError {
        case rateLimitExceeded
        case duplicateOwn
        case duplicatePending(message: String)
        case duplicateRejected(message: String)
        case duplicateByOthers(message: String)
        case unauthorized
        case invalidData
        case unavailable
        case server(code: String, message: String)

        var errorDescription: String? {
            switch self {
            case .rateLimitExceeded: return "每个VNDB ID每日最多提交5个推荐。"
            case .duplicateOwn: return "7天内不可重复推荐相同视觉小说。"
            case .duplicatePending(let message): return message
            case .duplicateRejected(let message): return message
            case .duplicateByOthers(let message): return message
            case .unauthorized: return "需要登录 VNDB 账号才能提交推荐。"
            case .invalidData: return "提交的数据格式不正确。"
            case .unavailable: return "服务器当前不可用，请稍后重试。"
            case .server(_, let message): return message
            }
        }

        var alertTitle: String {
            switch self {
            case .rateLimitExceeded: return "已达到每日提交限额"
            case .duplicateOwn: return "无法重复推荐"
            case .duplicatePending: return "合并重复推荐"
            case .duplicateRejected: return "被拒绝的重复推荐"
            case .duplicateByOthers: return "无法重复推荐"
            case .unauthorized: return "需要登录"
            case .invalidData: return "数据错误"
            case .unavailable: return "加载失败"
            case .server: return "服务器错误"
            }
        }

        var alertMessage: String {
            errorDescription ?? ""
        }
    }

    func 获取我的推荐(vndbID: String) async throws -> [Today推荐项目] {
        struct RecommendationsResponse: Decodable {
            let recommendations: [Today推荐项目]
        }

        let response: RecommendationsResponse = try await request(
            path: "/today/recommendations?vndbID=\(vndbID)",
            method: "GET",
            body: Optional<EmptyRequest>.none
        )
        return response.recommendations
    }

    func 获取公开推荐(vnID: String, displayDate: String? = nil) async throws -> Today公开推荐内容? {
        struct PublicRecommendationResponse: Decodable {
            let recommendation: Today公开推荐内容?
        }

        var path = "/today/public-recommendation?vnID=\(标准化视觉小说ID(vnID))"
        if let displayDate { path += "&displayDate=\(displayDate)" }
        let response: PublicRecommendationResponse = try await request(
            path: path,
            method: "GET",
            body: Optional<EmptyRequest>.none
        )
        return response.recommendation
    }

    func 检查提交资格(vndbID: String, vnID: String? = nil) async throws -> Today提交资格 {
        var path = "/today/submission-status?vndbID=\(vndbID)"
        if let vnID {
            path += "&vnID=\(标准化视觉小说ID(vnID))"
        }

        let eligibility: Today提交资格 = try await request(
            path: path,
            method: "GET",
            body: Optional<EmptyRequest>.none
        )

        guard eligibility.available else {
            throw ServiceError.unavailable
        }
        guard eligibility.canSubmit else {
            throw Self.serviceError(for: eligibility.error)
        }
        return eligibility
    }

    func 检查是否需要同意隐私政策(vndbID: String) async throws -> Bool {
        struct ConsentResponse: Decodable {
            let needsConsent: Bool
        }

        let response: ConsentResponse = try await request(
            path: "/today/needs-privacy-consent?vndbID=\(vndbID)",
            method: "GET",
            body: Optional<EmptyRequest>.none
        )
        return response.needsConsent
    }

    func 记录隐私政策同意(vndbID: String) async throws {
        struct ConsentRequest: Encodable {
            let vndbID: String
        }

        struct ConsentResponse: Decodable {
            let consented: Bool
        }

        let _: ConsentResponse = try await request(
            path: "/today/privacy-consent",
            method: "POST",
            body: ConsentRequest(vndbID: vndbID)
        )
    }

    func 提交推荐(
        vndbID: String,
        vndbUsername: String?,
        vnID: String,
        vnTitle: String,
        description: String,
        title: String,
        defaultLanguage: String,
        translations: Today推荐多语言内容
    ) async throws -> Today提交资格错误? {
        struct SubmissionRequest: Encodable {
            let vndbID: String
            let vndbUsername: String?
            let vnID: String
            let vnTitle: String
            let description: String
            let title: String
            let defaultLanguage: String
            let translations: Today推荐多语言内容
        }

        struct SubmissionResponse: Decodable {
            let warning: Today提交资格错误?
        }

        let submission = SubmissionRequest(
            vndbID: vndbID,
            vndbUsername: vndbUsername,
            vnID: vnID,
            vnTitle: vnTitle,
            description: description,
            title: title,
            defaultLanguage: defaultLanguage,
            translations: translations
        )

        let response: SubmissionResponse = try await request(
            path: "/today/submit",
            method: "POST",
            body: submission
        )
        return response.warning
    }

    func 编辑推荐(
        vndbID: String,
        submissionNumber: Int,
        defaultLanguage: String,
        translations: Today推荐多语言内容
    ) async throws {
        struct EditRequest: Encodable {
            let vndbID: String
            let defaultLanguage: String
            let translations: Today推荐多语言内容
        }
        let _: Today推荐项目 = try await request(
            path: "/today/recommendations/SUB\(submissionNumber)",
            method: "PUT",
            body: EditRequest(vndbID: vndbID, defaultLanguage: defaultLanguage, translations: translations)
        )
    }

    func 取消推荐(
        vndbID: String,
        submissionNumber: Int,
        从服务器删除: Bool
    ) async throws {
        struct MutationRequest: Encodable {
            let vndbID: String
        }

        struct 删除响应: Decodable {
            let deleted: Bool
        }

        let id = "SUB\(submissionNumber)"
        let path = 从服务器删除
            ? "/today/recommendations/\(id)"
            : "/today/recommendations/\(id)/cancel"
        let body = MutationRequest(vndbID: vndbID)

        if 从服务器删除 {
            let _: 删除响应 = try await request(
                path: path,
                method: "DELETE",
                body: body
            )
        } else {
            let _: Today推荐项目 = try await request(
                path: path,
                method: "POST",
                body: body
            )
        }
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        guard let url = endpointURL(path: path) else {
            throw ServiceError.invalidData
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ServiceError.unavailable
        }
        guard let response = response as? HTTPURLResponse else {
            throw ServiceError.unavailable
        }
        guard (200...299).contains(response.statusCode) else {
            if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                if let type = error.type {
                    switch type.uppercased() {
                    case "RATE_LIMIT_EXCEEDED", "RATE_LIMIT":
                        throw ServiceError.rateLimitExceeded
                    case "DUPLICATE_OWN":
                        throw ServiceError.duplicateOwn
                    case "DUPLICATE_PENDING":
                        throw ServiceError.duplicatePending(message: error.error)
                    case "DUPLICATE_REJECTED":
                        throw ServiceError.duplicateRejected(message: error.error)
                    case "DUPLICATE_BY_OTHERS":
                        throw ServiceError.duplicateByOthers(message: error.error)
                    default:
                        throw ServiceError.server(code: type, message: error.error)
                    }
                }
                throw ServiceError.server(code: "UNKNOWN", message: error.error)
            }
            if response.statusCode == 401 {
                throw ServiceError.unauthorized
            }
            throw ServiceError.unavailable
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw ServiceError.invalidData
        }
    }

    private func endpointURL(path: String) -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }

        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            components.queryItems = URLComponents(string: "?\(parts[1])")?.queryItems
        }
        return components.url
    }

    private static func serviceError(for error: Today提交资格错误?) -> ServiceError {
        guard let error else { return .unavailable }
        switch error.type.uppercased() {
        case "RATE_LIMIT_EXCEEDED", "RATE_LIMIT":
            return .rateLimitExceeded
        case "DUPLICATE_OWN":
            return .duplicateOwn
        case "DUPLICATE_PENDING":
            return .duplicatePending(message: error.message)
        case "DUPLICATE_REJECTED":
            return .duplicateRejected(message: error.message)
        case "DUPLICATE_BY_OTHERS", "DUPLICATE":
            return .duplicateByOthers(message: error.message)
        default:
            return .server(code: error.type, message: error.message)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private struct EmptyRequest: Encodable {}

    private struct ErrorResponse: Decodable {
        let error: String
        let type: String?

        private struct NestedError: Decodable {
            let code: String?
            let message: String?
        }

        private enum CodingKeys: String, CodingKey {
            case error
            case type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let responseType = try container.decodeIfPresent(String.self, forKey: .type)

            if let message = try? container.decode(String.self, forKey: .error) {
                type = responseType
                error = message
                return
            }

            let nested = try container.decode(NestedError.self, forKey: .error)
            type = responseType ?? nested.code
            error = nested.message ?? "服务器返回了错误。"
        }
    }
}

@MainActor
@Observable
fileprivate final class PaperVNToday推荐状态 {
    var 推荐列表: [Today推荐项目] = []
    var 正在加载 = false
    var 错误信息: String?
    private var 推荐列表加载成功 = false
    var 提交资格: Today提交资格?
    var 提交资格错误: String?
    var 正在检查提交资格 = false

    var 可以新建推荐: Bool {
        !正在加载
            && !正在检查提交资格
            && 错误信息 == nil
            && (提交资格?.isAllowed == true)
    }

    func 加载推荐列表(vndbID: String) async {
        正在加载 = true
        错误信息 = nil
        提交资格 = nil
        提交资格错误 = nil

        do {
            let service = PaperVNToday推荐服务()
            推荐列表 = try await service.获取我的推荐(vndbID: vndbID)
            推荐列表加载成功 = true
        } catch {
            推荐列表加载成功 = false
            错误信息 = error.localizedDescription
            推荐列表 = []
        }

        正在加载 = false
        await 刷新提交资格(vndbID: vndbID)
    }

    func 刷新提交资格(vndbID: String) async {
        正在检查提交资格 = true
        defer { 正在检查提交资格 = false }

        do {
            let service = PaperVNToday推荐服务()
            提交资格 = try await service.检查提交资格(vndbID: vndbID)
            提交资格错误 = nil
            if 推荐列表加载成功 {
                错误信息 = nil
            }
        } catch {
            提交资格 = nil
            提交资格错误 = error.localizedDescription
        }
    }
}

private struct Today推荐横幅: View {
    @Binding var 显示推荐页面: Bool

    var body: some View {
        Button {
            显示推荐页面 = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.tint)

                Text("用更多的视觉小说把Today填满吧～")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .平台卡片容器(
                background: Color.平台次级分组背景,
                stroke: .clear,
                cornerRadius: 28,
                lightModeShadowOpacity: 0,
                shadowRadius: 0,
                shadowY: 0
            )
        }
        .buttonStyle(.plain)
    }
}

struct Today推荐页面: View {
    private static let 新建推荐转场ID = "today.recommendation.new"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Namespace private var transitionNamespace
    @State private var state = PaperVNToday推荐状态()
    @State private var 显示新建页面 = false
    @State private var 待编辑推荐: Today推荐项目?
    @State private var 待取消推荐: Today推荐项目?
    @State private var 显示取消推荐提示 = false
    @State private var 显示取消错误 = false
    @State private var 取消错误信息: String?
    let vndbAccount: VNDB账户?

    var body: some View {
        NavigationStack {
            Group {
                if let account = vndbAccount {
                    推荐列表视图(vndbAccount: account)
                } else {
                    未登录视图()
                }
            }
            .navigationTitle("推荐视觉小说")
            .平台柔和滚动边缘(for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }

                if vndbAccount != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                guard let account = vndbAccount else { return }
                                await state.刷新提交资格(vndbID: account.用户ID)
                                if state.可以新建推荐 {
                                    显示新建页面 = true
                                }
                            }
                        } label: {
                            if state.正在检查提交资格 {
                                ProgressView()
                            } else {
                                Image(systemName: "square.and.pencil")
                            }
                        }
                        .disabled(!state.可以新建推荐)
                        .accessibilityLabel("新建推荐")
                        .平台匹配转场源(
                            id: Self.新建推荐转场ID,
                            in: transitionNamespace
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $显示新建页面) {
            if let account = vndbAccount {
                Today推荐编辑页面(vndbAccount: account, state: state)
                    .presentationDetents([.fraction(0.98)])
                    .平台缩放转场(
                        sourceID: Self.新建推荐转场ID,
                        in: transitionNamespace
                    )
            }
        }
        .sheet(item: $待编辑推荐) { 推荐 in
            if let account = vndbAccount {
                Today推荐编辑页面(vndbAccount: account, state: state, 推荐: 推荐)
                    .presentationDetents([.fraction(0.98)])
            }
        }
        .alert("确定要取消推荐吗？", isPresented: $显示取消推荐提示) {
            Button("保持", role: .cancel) {
                待取消推荐 = nil
            }
            Button("取消推荐", role: .destructive) {
                执行取消推荐(从服务器删除: false)
            }
            Button("取消推荐并从服务器中删除", role: .destructive) {
                执行取消推荐(从服务器删除: true)
            }
        } message: {
            Text("取消推荐的视觉小说不增加今日推荐计数。如果你遇到了情有可原的情况，请使用“取消推荐并从服务器中删除”。")
        }
        .alert("无法取消推荐", isPresented: $显示取消错误) {
            Button("好") {
                显示取消错误 = false
                取消错误信息 = nil
            }
        } message: {
            Text(取消错误信息 ?? "服务器当前不可用，请稍后重试。")
        }
    }

    private func 请求取消推荐(_ 推荐: Today推荐项目) {
        guard 推荐.status == .pending else { return }
        待取消推荐 = 推荐
        显示取消推荐提示 = true
    }

    private func 执行取消推荐(从服务器删除: Bool) {
        guard let 推荐 = 待取消推荐,
              let account = vndbAccount else {
            return
        }
        待取消推荐 = nil

        Task {
            do {
                try await PaperVNToday推荐服务().取消推荐(
                    vndbID: account.用户ID,
                    submissionNumber: 推荐.submissionNumber,
                    从服务器删除: 从服务器删除
                )
                await state.加载推荐列表(vndbID: account.用户ID)
            } catch {
                取消错误信息 = error.localizedDescription
                显示取消错误 = true
            }
        }
    }

    @ViewBuilder
    private func 推荐列表视图(vndbAccount: VNDB账户) -> some View {
        List {
            if state.正在加载 {
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        Today推荐列表加载占位行()
                    }
                    .accessibilityHidden(true)
                } header: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入…")
                    }
                    .textCase(nil)
                    .accessibilityElement(children: .combine)
                }
            } else if let 错误 = state.错误信息 {
                Section {
                    平台内容不可用视图(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(错误)
                    )
                }
            } else if state.推荐列表.isEmpty {
                Section {
                    平台内容不可用视图(
                        "暂无已提交推荐",
                        systemImage: "square.and.pencil"
                    )
                }
            } else {
                Section {
                    ForEach(state.推荐列表) { 推荐 in
                        Button {
                            待编辑推荐 = 推荐
                        } label: {
                            推荐行视图(推荐: 推荐)
                        }
                            .buttonStyle(.plain)
                            .accessibilityHint("轻点编辑推荐")
                            .contextMenu {
                                if 推荐.status == .pending {
                                    Button(role: .destructive) {
                                        请求取消推荐(推荐)
                                    } label: {
                                        Label("取消推荐", systemImage: "pencil.slash")
                                    }
                                }
                            }
                            .swipeActions(
                                edge: .trailing,
                                allowsFullSwipe: true
                            ) {
                                if 推荐.status == .pending {
                                    Button {
                                        请求取消推荐(推荐)
                                    } label: {
                                        Label("取消推荐", systemImage: "pencil.slash")
                                    }
                                    .tint(.red)
                                }
                            }
                    }
                }
            }
        }
        .平台分组列表样式()
        .task {
            await state.加载推荐列表(vndbID: vndbAccount.用户ID)
        }
    }

    private func 推荐行视图(推荐: Today推荐项目) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: 推荐.localizedTitle(locale: locale))
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Text(verbatim: formatDate(推荐.submittedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            Text(verbatim: 推荐.localizedDescription(locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                HStack(spacing: 6) {
                    Text(verbatim: 推荐.displayID)

                    if let nickname = 推荐.nickname?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ), !nickname.isEmpty {
                        Text(verbatim: "·")
                        Text(verbatim: nickname)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                Text(verbatim: 推荐.statusText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func 未登录视图() -> some View {
        ContentUnavailableView {
            Label("需要登录", systemImage: "person.crop.circle.badge.exclamationmark")
        } description: {
            Text("登录 VNDB 账号后即可推荐视觉小说")
        }
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: dateString) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: dateString)
        }()

        guard let date else {
            return dateString
        }

        return date.formatted(
            .dateTime
                .year()
                .month()
                .day()
                .locale(locale)
        )
    }
}

private struct Today推荐列表加载占位行: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(
                cornerRadius: 列表封面布局.圆角(
                    horizontalSizeClass: horizontalSizeClass
                ),
                style: .continuous
            )
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)

            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 184, height: 16)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(width: 132, height: 12)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 156, height: 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
    }
}

private struct Today视觉小说搜索结果: Identifiable, Sendable {
    let id: String
    let title: String
    let displayTitle: String
    var displayIsJapanese = false
    var displayLanguageCode: String? = nil
    let imageURL: String?
}

@MainActor
@Observable
private final class 视觉小说搜索视图模型 {
    enum Today页面状态 {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    var 搜索文本 = ""
    var 结果列表: [Today视觉小说搜索结果] = []
    var 页面状态: Today页面状态 = .loading
    var 当前页 = 1
    var 总结果数 = 0
    var 正在加载更多 = false

    private var 搜索结果提交门: Task<Void, Never>?

    func 搜索(文本: String) {
        搜索结果提交门?.cancel()

        搜索结果提交门 = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await 执行搜索(文本: 文本, 页码: 1)
        }
    }

    func 加载默认列表() {
        搜索结果提交门?.cancel()
        搜索结果提交门 = Task {
            await 执行搜索(文本: "", 页码: 1)
        }
    }

    func 加载更多页面() {
        guard !正在加载更多,
              case .loaded = 页面状态,
              结果列表.count < 总结果数 else {
            return
        }

        正在加载更多 = true
        Task {
            await 执行搜索(文本: 搜索文本, 页码: 当前页 + 1, 追加: true)
        }
    }

    private func 执行搜索(文本: String, 页码: Int, 追加: Bool = false) async {
        if !追加 {
            页面状态 = .loading
            结果列表 = []
            当前页 = 1
            总结果数 = 0
            正在加载更多 = false
        }

        do {
            struct SearchRequest: Encodable {
                enum Filter: Encodable {
                    case all
                    case search(String)

                    func encode(to encoder: Encoder) throws {
                        var container = encoder.singleValueContainer()
                        switch self {
                        case .all:
                            try container.encode([String]())
                        case let .search(query):
                            try container.encode(["search", "=", query])
                        }
                    }
                }

                let filters: Filter
                let fields: String
                let sort: String
                let reverse: Bool
                let results: Int
                let page: Int
                let count: Bool
            }

            let query = 文本.trimmingCharacters(in: .whitespacesAndNewlines)
            let fields = "id, title, image.url, titles.lang, titles.title, titles.latin, titles.official, titles.main"
            let hasQuery = !query.isEmpty

            let request = SearchRequest(
                filters: hasQuery ? .search(query) : .all,
                fields: fields,
                sort: hasQuery ? "searchrank" : "released",
                reverse: !hasQuery,
                results: 25,
                page: 页码,
                count: true
            )

            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(request)

            var urlRequest = URLRequest(url: URL(string: "https://api.vndb.org/kana/vn")!)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = jsonData

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                if !追加 {
                    页面状态 = .failed("搜索失败")
                }
                正在加载更多 = false
                return
            }

            struct VNDBResponse: Decodable {
                let results: [VNDBVisualNovel]
                let count: Int?
            }

            struct VNDBVisualNovel: Decodable {
                let id: String
                let title: String
                let titles: [用户多语言标题]?
                let image: VNDBImage?
            }

            struct VNDBImage: Decodable {
                let url: String?
            }

            let decoder = JSONDecoder()
            let vndbResponse = try decoder.decode(VNDBResponse.self, from: data)

            let 新结果 = vndbResponse.results.map { vn in
                let 显示标题 = 简介翻译条目名称.偏好标题(
                    titles: vn.titles,
                    defaultTitle: vn.title
                )
                return Today视觉小说搜索结果(
                    id: 标准化视觉小说ID(vn.id),
                    title: 简介翻译条目名称.原语言标题(
                        titles: vn.titles,
                        defaultTitle: vn.title
                    ),
                    displayTitle: 显示标题.text,
                    displayIsJapanese: 显示标题.isJapanese,
                    displayLanguageCode: 显示标题.languageCode,
                    imageURL: vn.image?.url
                )
            }

            if 追加 {
                结果列表.append(contentsOf: 新结果)
                当前页 = 页码
            } else {
                结果列表 = 新结果
                当前页 = 页码
                总结果数 = vndbResponse.count ?? 新结果.count

                if 新结果.isEmpty {
                    页面状态 = .empty
                } else {
                    页面状态 = .loaded
                }
            }

            正在加载更多 = false

        } catch {
            if !追加 {
                页面状态 = .failed(error.localizedDescription)
            }
            正在加载更多 = false
        }
    }
}

private struct 视觉小说搜索页面: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var 选中的视觉小说: Today视觉小说搜索结果?
    @State private var viewModel = 视觉小说搜索视图模型()

    var body: some View {
        NavigationStack {
            List {
                switch viewModel.页面状态 {
                case .idle:
                    Section {
                        平台内容不可用视图(
                            "选择视觉小说",
                            systemImage: "magnifyingglass",
                            description: Text("在上方输入关键词开始搜索")
                        )
                    }

                case .loading:
                    Section {
                        ForEach(0..<5, id: \.self) { _ in
                            Today视觉小说搜索加载占位行()
                        }
                        .accessibilityHidden(true)
                    } header: {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在载入…")
                        }
                        .textCase(nil)
                        .accessibilityElement(children: .combine)
                    }

                case .empty:
                    EmptyView()

                case .failed(let message):
                    Section {
                        平台内容不可用视图(
                            "搜索失败",
                            systemImage: "exclamationmark.triangle",
                            description: Text(message)
                        )
                    }

                case .loaded:
                    Section {
                        ForEach(
                            Array(viewModel.结果列表.enumerated()),
                            id: \.element.id
                        ) { index, 视觉小说 in
                            Button {
                                选中的视觉小说 = 视觉小说
                                dismiss()
                            } label: {
                                视觉小说搜索行(视觉小说: 视觉小说)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                guard viewModel.结果列表.count > 0,
                                      index >= max(
                                        viewModel.结果列表.count
                                            - 平台列表分页.预取余量,
                                        0
                                      ) else { return }
                                if viewModel.结果列表.count < viewModel.总结果数 {
                                    viewModel.加载更多页面()
                                }
                            }
                        }
                    }

                    if viewModel.正在加载更多 {
                        Section {
                            ForEach(0..<2, id: \.self) { _ in
                                Today视觉小说搜索加载占位行()
                            }
                            .accessibilityHidden(true)
                        } header: {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在载入…")
                            }
                            .textCase(nil)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            .平台分组列表样式()
            .overlay {
                switch viewModel.页面状态 {
                case .empty:
                    ContentUnavailableView.search
                default:
                    EmptyView()
                }
            }
            .navigationTitle("选择视觉小说")
            .平台柔和滚动边缘(for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.搜索文本, prompt: "搜索视觉小说")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .onChange(of: viewModel.搜索文本) { _, 新值 in
                viewModel.搜索(文本: 新值)
            }
            .task {
                viewModel.加载默认列表()
            }
        }
    }
}

private struct Today推荐视觉小说封面: View {
    let imageURL: String?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var cornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        Group {
            CachedAsyncImage(
                url: imageURL.flatMap(URL.init(string:)),
                contentMode: .fill
            )
        }
        .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
        .clipped()
        .background(Color.secondary.opacity(0.1))
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}

private struct Today视觉小说搜索加载占位行: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(
                cornerRadius: 列表封面布局.圆角(
                    horizontalSizeClass: horizontalSizeClass
                ),
                style: .continuous
            )
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                搜索页占位线(width: 184, height: 16, opacity: 0.14)
                搜索页占位线(width: 132, height: 12)
                搜索页占位线(width: 156, height: 10, opacity: 0.08)
                搜索页占位线(width: 104, height: 10, opacity: 0.08)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
        .allowsHitTesting(false)
    }
}

private func 搜索页占位线(
    width: CGFloat,
    height: CGFloat,
    opacity: Double = 0.1
) -> some View {
    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        .fill(Color.secondary.opacity(opacity))
        .frame(width: width, height: height)
}

private struct 视觉小说搜索行: View {
    let 视觉小说: Today视觉小说搜索结果

    var body: some View {
        HStack(spacing: 12) {
            Today推荐视觉小说封面(imageURL: 视觉小说.imageURL)

            VStack(alignment: .leading, spacing: 4) {
                多语言列表文本(
                    文本: 视觉小说.displayTitle,
                    isJapanese: 视觉小说.displayIsJapanese,
                    语言代码: 视觉小说.displayLanguageCode,
                    层级: .主标题,
                    系统字体粗细: .semibold
                )
                .foregroundStyle(.primary)

                Text(视觉小说.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct Today推荐编辑页面: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let vndbAccount: VNDB账户
    let state: PaperVNToday推荐状态
    var 推荐: Today推荐项目? = nil

    @State private var 选中的视觉小说: Today视觉小说搜索结果?
    @State private var 填写语言: Today推荐语言 = .简体中文
    @State private var 默认语言: Today推荐语言 = .简体中文
    @State private var 标题: [Today推荐语言: String] = [:]
    @State private var 描述: [Today推荐语言: String] = [:]
    @State private var 已初始化 = false
    @State private var 显示搜索页面 = false
    @State private var 正在提交 = false
    @State private var 显示错误 = false
    @State private var 错误: PaperVNToday推荐服务.ServiceError?
    @State private var 显示隐私政策 = false
    @State private var 正在检查隐私政策 = false

    var 可以提交: Bool {
        guard 已初始化, 选中的视觉小说 != nil, !已填写语言.isEmpty else { return false }
        return 已填写语言.allSatisfy {
            !已整理标题($0).isEmpty && !已整理描述($0).isEmpty
        }
    }

    private var 已填写语言: [Today推荐语言] {
        Today推荐语言.allCases.filter {
            !已整理标题($0).isEmpty || !已整理描述($0).isEmpty
        }
    }

    private var 提交默认语言: Today推荐语言 {
        if 已填写语言.contains(默认语言) { return 默认语言 }
        if 已填写语言.contains(填写语言) { return 填写语言 }
        return 已填写语言.first ?? 默认语言
    }

    private var 提交内容: Today推荐多语言内容 {
        var titles: [String: String] = [:]
        var descriptions: [String: String] = [:]
        for language in 已填写语言 {
            titles[language.rawValue] = 已整理标题(language)
            descriptions[language.rawValue] = 已整理描述(language)
        }
        titles["default"] = 已整理标题(提交默认语言)
        descriptions["default"] = 已整理描述(提交默认语言)
        return Today推荐多语言内容(description: titles, introduction: descriptions)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("用户名") {
                        Text(vndbAccount.用户名)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("VNDB ID") {
                        Text(vndbAccount.用户ID)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if let vn = 选中的视觉小说 {
                        Button {
                            guard 推荐 == nil else { return }
                            显示搜索页面 = true
                        } label: {
                            HStack {
                                Today推荐视觉小说封面(imageURL: vn.imageURL)

                                VStack(alignment: .leading, spacing: 4) {
                                    多语言列表文本(
                                        文本: vn.displayTitle,
                                        isJapanese: vn.displayIsJapanese,
                                        语言代码: vn.displayLanguageCode,
                                        层级: .主标题,
                                        系统字体粗细: .semibold
                                    )
                                    Text(vn.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if 推荐 == nil {
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .disabled(推荐 != nil)
                    } else {
                        Button {
                            显示搜索页面 = true
                        } label: {
                            Label("选择视觉小说", systemImage: 搜索范围.visualNovel.systemImage)
                                .foregroundStyle(.primary)
                        }
                        .contentShape(Rectangle())
                    }
                } header: {
                    Text("视觉小说")
                }

                Section {
                    TextField("", text: Binding(
                        get: { 标题[填写语言] ?? "" },
                        set: { 标题[填写语言] = $0 }
                    ), axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("标题")
                }

                Section {
                    TextField("介绍视觉小说或你想说的话…", text: Binding(
                        get: { 描述[填写语言] ?? "" },
                        set: { 描述[填写语言] = $0 }
                    ), axis: .vertical)
                        .lineLimit(5...10)
                } header: {
                    Text("描述")
                } footer: {
                    Text("")
                }

                if !已整理描述(填写语言).isEmpty {
                    Section {
                        Today推荐正文(
                            description: 已整理描述(填写语言),
                            author: 推荐?.nickname ?? vndbAccount.用户名
                        )
                    } header: {
                        Text("预览")
                    }
                }

                if let 推荐, 推荐.status != .canceled {
                    Section {
                        Text("修改后的推荐将重新等待审核。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(正在提交 || 正在检查隐私政策)
            .navigationTitle(推荐 == nil ? "新建推荐" : "编辑推荐")
            .平台柔和滚动边缘(for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("取消")
                    .disabled(正在提交 || 正在检查隐私政策)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        ForEach(Today推荐语言.allCases) { language in
                            Button {
                                填写语言 = language
                            } label: {
                                HStack {
                                    Text(verbatim: language.name)
                                    if 填写语言 == language {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "globe")
                    }
                    .accessibilityLabel("填写语言")
                    .accessibilityHint("可选择任意语言填写，也可填写多种语言")
                    .disabled(正在提交 || 正在检查隐私政策)

                    if 正在提交 || 正在检查隐私政策 {
                        ProgressView()
                    } else {
                        Button {
                            if 推荐 == nil {
                                提交推荐()
                            } else {
                                执行编辑()
                            }
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .液态玻璃醒目按钮(in: Circle())
                        .buttonBorderShape(.circle)
                        .tint(.blue)
                        .disabled(!可以提交)
                        .accessibilityLabel(推荐 == nil ? "提交推荐" : "保存推荐")
                    }
                }
            }
        }
        .interactiveDismissDisabled(正在提交 || 正在检查隐私政策)
        .task {
            初始化草稿()
        }
        .sheet(isPresented: $显示搜索页面) {
            视觉小说搜索页面(选中的视觉小说: $选中的视觉小说)
                .presentationDetents([.fraction(0.98)])
        }
        .alert(错误?.alertTitle ?? "错误", isPresented: $显示错误) {
            Button("好") {
                显示错误 = false
                错误 = nil
            }
        } message: {
            if let error = 错误 {
                Text(error.alertMessage)
            }
        }
        .alert("需要同意新增的隐私政策与服务条款", isPresented: $显示隐私政策) {
            Button("同意") {
                显示隐私政策 = false
                记录同意并提交()
            }
            Button("取消", role: .cancel) {
                显示隐私政策 = false
                正在提交 = false
            }
        } message: {
            Text("用于提交的VNDB ID将被记录以防止滥用行为。用户提交的视觉小说、标题、描述与用户名在通过后将向所有用户展示，开发者可能出于PaperVN的需要对内容进行适当修改。\n\n每个VNDB ID每日最多提交5个推荐，7天内不可重复推荐相同视觉小说。")
        }
    }

    private func 已整理标题(_ language: Today推荐语言) -> String {
        (标题[language] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func 已整理描述(_ language: Today推荐语言) -> String {
        (描述[language] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func 初始化草稿() {
        guard !已初始化 else { return }
        let interfaceLanguage = Today推荐语言.当前语言(locale)
        默认语言 = 推荐?.defaultLanguage.flatMap(Today推荐语言.init(rawValue:)) ?? interfaceLanguage
        填写语言 = interfaceLanguage
        if let 推荐 {
            let cachedDetail = VNDB服务.shared.loadCachedVNDetail(vnID: 推荐.vnID)
            // 没有缓存详情时 titles 为空，标题工具会按文字内容判断是否使用日文字体。
            let 显示标题 = 简介翻译条目名称.偏好标题(
                titles: cachedDetail?.titles,
                defaultTitle: cachedDetail?.title ?? 推荐.vnTitle
            )
            选中的视觉小说 = Today视觉小说搜索结果(
                id: 推荐.vnID,
                title: 推荐.vnTitle,
                displayTitle: 显示标题.text,
                displayIsJapanese: 显示标题.isJapanese,
                displayLanguageCode: 显示标题.languageCode,
                imageURL: 推荐.visualNovelImage
            )
            if let translations = 推荐.submissionTranslations {
                for language in Today推荐语言.allCases {
                    标题[language] = translations.description[language.rawValue]
                    描述[language] = translations.introduction[language.rawValue]
                }
                if 已填写语言.isEmpty {
                    标题[默认语言] = translations.description["default"] ?? 推荐.title ?? 推荐.vnTitle
                    描述[默认语言] = translations.introduction["default"] ?? 推荐.description
                }
            } else {
                标题[默认语言] = 推荐.title ?? 推荐.vnTitle
                描述[默认语言] = 推荐.description
            }
            if !已填写语言.contains(填写语言) {
                填写语言 = 已填写语言.contains(默认语言) ? 默认语言 : 已填写语言.first ?? 默认语言
            }
        }
        已初始化 = true
    }

    private func 执行编辑() {
        guard 可以提交, let 推荐 else { return }
        正在提交 = true
        let content = 提交内容
        let language = 提交默认语言.rawValue
        Task {
            do {
                try await PaperVNToday推荐服务().编辑推荐(
                    vndbID: vndbAccount.用户ID,
                    submissionNumber: 推荐.submissionNumber,
                    defaultLanguage: language,
                    translations: content
                )
                await state.加载推荐列表(vndbID: vndbAccount.用户ID)
                正在提交 = false
                dismiss()
            } catch let error as PaperVNToday推荐服务.ServiceError {
                正在提交 = false
                错误 = error
                显示错误 = true
            } catch {
                正在提交 = false
                错误 = .invalidData
                显示错误 = true
            }
        }
    }

    private func 记录同意并提交() {
        Task { @MainActor in
            do {
                let service = PaperVNToday推荐服务()
                try await service.记录隐私政策同意(vndbID: vndbAccount.用户ID)
                执行提交()
            } catch let serviceError as PaperVNToday推荐服务.ServiceError {
                正在提交 = false
                错误 = serviceError
                显示错误 = true
            } catch {
                正在提交 = false
                错误 = .invalidData
                显示错误 = true
            }
        }
    }

    private func 提交推荐() {
        guard 可以提交, 选中的视觉小说 != nil else { return }
        正在提交 = true
        正在检查隐私政策 = true

        Task {
            do {
                let service = PaperVNToday推荐服务()
                guard let vn = 选中的视觉小说 else {
                    正在检查隐私政策 = false
                    正在提交 = false
                    return
                }

                _ = try await service.检查提交资格(
                    vndbID: vndbAccount.用户ID,
                    vnID: vn.id
                )

                let needsConsent = try await service.检查是否需要同意隐私政策(vndbID: vndbAccount.用户ID)
                正在检查隐私政策 = false

                if needsConsent {
                    显示隐私政策 = true
                } else {
                    执行提交()
                }
            } catch let serviceError as PaperVNToday推荐服务.ServiceError {
                正在检查隐私政策 = false
                正在提交 = false
                错误 = serviceError
                显示错误 = true
            } catch {
                正在检查隐私政策 = false
                正在提交 = false
                错误 = .invalidData
                显示错误 = true
            }
        }
    }

    private func 执行提交() {
        guard let vn = 选中的视觉小说 else { return }

        Task {
            do {
                let service = PaperVNToday推荐服务()
                let warning = try await service.提交推荐(
                    vndbID: vndbAccount.用户ID,
                    vndbUsername: vndbAccount.用户名,
                    vnID: vn.id,
                    vnTitle: vn.title,
                    description: 已整理描述(提交默认语言),
                    title: 已整理标题(提交默认语言),
                    defaultLanguage: 提交默认语言.rawValue,
                    translations: 提交内容
                )

                await state.加载推荐列表(vndbID: vndbAccount.用户ID)
                正在提交 = false
                if let warning {
                    错误 = .duplicateRejected(message: warning.message)
                    显示错误 = true
                } else {
                    dismiss()
                }
            } catch let error as PaperVNToday推荐服务.ServiceError {
                正在提交 = false
                错误 = error
                显示错误 = true
            } catch {
                正在提交 = false
                错误 = .invalidData
                显示错误 = true
            }
        }
    }
}

#Preview {
    NavigationStack {
        Today页面()
    }
    .environmentObject(用户登录(previewing: true))
    .environmentObject(Bangumi账户(previewing: true))
}

struct Today显示配置: Codable, Equatable {
    var showEvents = true
    var showQuotes = true

    private static let localStorageKey = "todayDisplayConfiguration"
    private static let cloudStorageKey = "todayDisplayConfiguration"
    private static let iCloudSyncSettingKey = 偏好数据iCloud同步设置.启用键

    static let 设置键 = localStorageKey

    static func load() -> Today显示配置 {
        let defaults = UserDefaults.standard
        let cloudStore = NSUbiquitousKeyValueStore.default
        let iCloudEnabled = defaults.bool(forKey: iCloudSyncSettingKey)

        if iCloudEnabled,
           let cloudData = cloudStore.data(forKey: cloudStorageKey),
           let cloudConfig = try? JSONDecoder().decode(Today显示配置.self, from: cloudData) {
            return cloudConfig
        }

        guard let localData = defaults.data(forKey: localStorageKey),
              let localConfig = try? JSONDecoder().decode(Today显示配置.self, from: localData) else {
            return Today显示配置()
        }
        return localConfig
    }

    func save() {
        let defaults = UserDefaults.standard
        let cloudStore = NSUbiquitousKeyValueStore.default
        let iCloudEnabled = defaults.bool(forKey: Self.iCloudSyncSettingKey)

        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.localStorageKey)

            if iCloudEnabled {
                cloudStore.set(data, forKey: Self.cloudStorageKey)
                cloudStore.synchronize()
            }
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showEvents = try container.decodeIfPresent(Bool.self, forKey: .showEvents) ?? true
        showQuotes = try container.decodeIfPresent(Bool.self, forKey: .showQuotes) ?? true
    }

    init(showEvents: Bool = true, showQuotes: Bool = true) {
        self.showEvents = showEvents
        self.showQuotes = showQuotes
    }

    private enum CodingKeys: String, CodingKey {
        case showEvents, showQuotes
    }
}
