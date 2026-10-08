import Foundation
import Combine
import OSLog
@preconcurrency import BackgroundTasks
import UIKit
import CryptoKit

nonisolated enum NextMoe内容设置 {
    static let 设置键 = "nextMoeContentEnabled"

    static func 用户IP国家代码() async -> String? {
        guard let url = URL(string: "https://ipapi.co/country/") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let countryCode = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !countryCode.isEmpty else {
                return nil
            }
            return countryCode.uppercased()
        } catch {
            return nil
        }
    }

    static var 已启用: Bool {
        UserDefaults.standard.bool(forKey: 设置键)
    }
}

nonisolated enum 缓存策略: String, CaseIterable, Identifiable, Sendable {
    case less
    case balanced
    case more

    static let 设置键 = "cacheStrategy"

    var id: Self { self }

    var title: String {
        switch self {
        case .less:
            return String(localized: "更少")
        case .balanced:
            return String(localized: "平衡")
        case .more:
            // 与通用的“更多”按钮区分，部分语言需要不同译法
            return String(localized: "缓存策略.更多", defaultValue: "更多")
        }
    }

    var sliderPosition: Double {
        switch self {
        case .less: return 0
        case .balanced: return 1
        case .more: return 2
        }
    }

    init(sliderPosition: Double) {
        switch Int(sliderPosition.rounded()) {
        case 0: self = .less
        case 1: self = .balanced
        default: self = .more
        }
    }

    var maximumCacheBytes: Int64? {
        switch self {
        case .less: return 100 * 1_024 * 1_024
        case .balanced: return 300 * 1_024 * 1_024
        case .more: return nil
        }
    }

    var visualNovelDetailLifetime: TimeInterval {
        switch self {
        case .less: return 60
        case .balanced: return 24 * 60 * 60
        case .more: return 48 * 60 * 60
        }
    }

    var characterDetailLifetime: TimeInterval {
        switch self {
        case .less: return 60
        case .balanced, .more: return 48 * 60 * 60
        }
    }

    var releaseLifetime: TimeInterval {
        switch self {
        case .less: return 60
        case .balanced: return 24 * 60 * 60
        case .more: return 48 * 60 * 60
        }
    }

    var searchLifetime: TimeInterval {
        switch self {
        case .less: return 0
        case .balanced: return 60 * 60
        case .more: return 48 * 60 * 60
        }
    }

    var exploreFeedLifetime: TimeInterval {
        switch self {
        case .less: return 10 * 60
        case .balanced: return 30 * 60
        case .more: return 48 * 60 * 60
        }
    }

    static var 当前: Self {
        guard let rawValue = UserDefaults.standard.string(forKey: 设置键),
              let value = Self(rawValue: rawValue) else {
            return .balanced
        }
        return value
    }

    static func 应用URLCache配置() {
        let strategy = 当前
        let memoryCapacity: Int
        let diskCapacity: Int
        switch strategy {
        case .less:
            memoryCapacity = 50 * 1_024 * 1_024
            diskCapacity = 100 * 1_024 * 1_024
        case .balanced:
            memoryCapacity = 100 * 1_024 * 1_024
            diskCapacity = 300 * 1_024 * 1_024
        case .more:
            memoryCapacity = 500 * 1_024 * 1_024
            diskCapacity = 1_000 * 1_024 * 1_024
        }

        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "paperVNImageCache"
        )
    }
}

nonisolated private func normalizedVNDBLanguageCode(_ code: String) -> String {
    switch code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "zh", "zh-cn", "zh_cn", "zh-hans", "zh_hans":
        return "zh-Hans"
    case "zh-tw", "zh_tw", "zh-hant", "zh_hant":
        return "zh-Hant"
    default:
        return code
    }
}

nonisolated enum PaperVNConnect网络设置 {
    static let connect基础地址 = "https://papervn.jizpaper.com/connect"

    private struct 上游映射: Sendable {
        let 直连基础地址: String
        let 转发基础地址: String
    }

    private static let 上游映射表 = [
        上游映射(
            直连基础地址: "https://api.vndb.org/kana",
            转发基础地址: "\(connect基础地址)/vndb"
        ),
        上游映射(
            直连基础地址: "https://api.bgm.tv",
            转发基础地址: "\(connect基础地址)/bangumi"
        ),
        上游映射(
            直连基础地址: "https://next.bgm.tv",
            转发基础地址: "\(connect基础地址)/bangumi"
        ),
        上游映射(
            直连基础地址: "https://store.steampowered.com",
            转发基础地址: "\(connect基础地址)/steam"
        )
    ]

    static func 请求应回退(statusCode: Int) -> Bool {
        statusCode == 403
            || statusCode == 404
            || statusCode == 408
            || statusCode == 429
            || (500...599).contains(statusCode)
    }

    static func 图片请求地址(for url: URL) -> URL {
        guard PaperVNConnect自动策略.自动转发已启用,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "t.vndb.org",
              var components = URLComponents(
                  string: "\(connect基础地址)/image"
              ) else {
            return url
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString)
        ]
        return components.url ?? url
    }

    static func 发送图片请求(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let candidates = 图片请求候选(for: request)
        var lastError: Error?

        for (index, candidate) in candidates.enumerated() {
            do {
                let (data, response) = try await session.data(for: candidate)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if index < candidates.count - 1,
                   !(200...299).contains(httpResponse.statusCode) {
                    continue
                }
                return (data, httpResponse)
            } catch {
                guard index < candidates.count - 1 else { throw error }
                lastError = error
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    private static func 图片请求候选(
        for request: URLRequest
    ) -> [URLRequest] {
        guard let url = request.url,
              let originalURL = 原始VNDB图片地址(from: url) else {
            return [request]
        }

        if url == originalURL {
            let forwardedURL = 图片请求地址(for: originalURL)
            guard forwardedURL != originalURL else { return [request] }
            var forwardedRequest = request
            forwardedRequest.url = forwardedURL
            return [forwardedRequest, request]
        }

        var directRequest = request
        directRequest.url = originalURL
        return [request, directRequest]
    }

    private static func 原始VNDB图片地址(from url: URL) -> URL? {
        if url.scheme?.lowercased() == "https",
           url.host?.lowercased() == "t.vndb.org" {
            return url
        }

        guard url.host?.lowercased() == URL(
            string: connect基础地址
        )?.host?.lowercased(),
        url.path == "/connect/image",
        let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ),
        let value = components.queryItems?.first(where: {
            $0.name == "url"
        })?.value,
        let originalURL = URL(string: value),
        originalURL.scheme?.lowercased() == "https",
        originalURL.host?.lowercased() == "t.vndb.org" else {
            return nil
        }
        return originalURL
    }

    static func 发送请求(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> (Data, HTTPURLResponse) {
        let candidates = try 请求候选(for: request)
        var lastError: Error?

        for (index, candidateRequest) in candidates.enumerated() {
            do {
                let (data, response) = try await session.data(
                    for: candidateRequest
                )
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if index < candidates.count - 1,
                   请求应回退(statusCode: httpResponse.statusCode) {
                    continue
                }
                return (data, httpResponse)
            } catch {
                guard index < candidates.count - 1 else { throw error }
                lastError = error
            }
        }

        throw lastError ?? URLError(.cannotConnectToHost)
    }

    static func 请求候选(
        for request: URLRequest,
        自动转发已启用: Bool = PaperVNConnect自动策略.自动转发已启用
    ) throws -> [URLRequest] {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        guard 自动转发已启用,
              let mapping = 上游映射表.first(where: {
                  地址(url.absoluteString, belongsTo: $0.直连基础地址)
              }) else {
            return [request]
        }

        let absoluteString = url.absoluteString
        let suffix = absoluteString.dropFirst(mapping.直连基础地址.count)
        guard let replacementURL = URL(
            string: mapping.转发基础地址 + suffix
        ) else {
            throw URLError(.badURL)
        }
        var forwardedRequest = request
        forwardedRequest.url = replacementURL
        forwardedRequest.timeoutInterval = min(request.timeoutInterval, 8)
        return [forwardedRequest, request]
    }

    private static func 地址(_ address: String, belongsTo baseURL: String) -> Bool {
        address == baseURL
            || address.hasPrefix(baseURL + "/")
            || address.hasPrefix(baseURL + "?")
    }
}

enum VNDB服务错误: LocalizedError, Equatable {
    case token无效
    case 缺少资料库写入权限
    case NextMoe令牌无效
    case NextMoe权限不足
    case NextMoe请求过于频繁
    case NextMoe服务暂时不可用
    case NextMoe请求失败(statusCode: Int, message: String)
    case 无效搜索关键词
    case 请求过于频繁
    case 服务暂时不可用
    case 请求失败(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .token无效:
            return String(localized: "VNDB Token无效或已过期，请重新登录。")
        case .缺少资料库写入权限:
            return String(
                localized: "当前VNDB Token没有资料库写入权限，请在VNDB上重新创建Token并启用listwrite权限。"
            )
        case .NextMoe令牌无效:
            return String(localized: "鲲Galgame登录已失效，请重新登录。")
        case .NextMoe权限不足:
            return String(localized: "鲲Galgame登录缺少NextMoe内容权限，请重新登录以授权。")
        case .NextMoe请求过于频繁:
            return String(localized: "NextMoe请求过于频繁，请稍后再试。")
        case .NextMoe服务暂时不可用:
            return String(localized: "NextMoe服务暂时不可用，请稍后再试。")
        case let .NextMoe请求失败(_, message):
            return String(localized: "NextMoe请求失败：\(message)")
        case .无效搜索关键词:
            return String(localized: "请键入搜索内容。")
        case .请求过于频繁:
            return String(localized: "请求过于频繁，请稍后再试。")
        case .服务暂时不可用:
            return String(localized: "VNDB服务暂时不可用，请稍后再试。")
        case let .请求失败(_, message):
            return String(localized: "VNDB请求失败：\(message)")
        }
    }
}

nonisolated private struct VNDB视觉小说详情响应: Decodable, Sendable {
    let results: [视觉小说详细信息]
}

nonisolated private struct VNDB视觉小说详情缓存条目: Codable, Sendable {
    let savedAt: Date
    let value: 视觉小说详细信息
}

nonisolated struct VNDB视觉小说活动元数据: Codable, Hashable, Sendable {
    let id: String
    let title: String
    let titles: [用户多语言标题]?
    let aliases: [String]?
    let va: [声优关系]?

    struct 声优: Codable, Hashable, Sendable {
        let name: String?
        let original: String?
    }

    struct 声优关系: Codable, Hashable, Sendable {
        let staff: 声优
    }
}

nonisolated private struct VNDB视觉小说活动元数据响应: Decodable, Sendable {
    let results: [VNDB视觉小说活动元数据]
}

nonisolated struct VNDB用户资料库活动项目: Codable, Hashable, Sendable {
    let id: String
    let vn: 作品

    struct 作品: Codable, Hashable, Sendable {
        let title: String
        let titles: [用户多语言标题]?
    }
}

nonisolated private struct VNDB用户资料库活动响应: Decodable, Sendable {
    let results: [VNDB用户资料库活动项目]
    let more: Bool
}

nonisolated private struct NextMoe列表<Item: Decodable & Sendable>: Decodable, Sendable {
    let items: [Item]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

nonisolated private struct NextMoe本地化文本: Decodable, Sendable {
    let value: String
}

nonisolated private struct NextMoe图片: Decodable, Sendable {
    let url: String
    let width: Int?
    let height: Int?
    let sexual: String?
    let violence: String?
}

nonisolated private struct NextMoe标题: Decodable, Sendable {
    let lang: String
    let title: String
    let latin: String?
    let titleKind: String

    private enum CodingKeys: String, CodingKey {
        case lang, title, latin
        case titleKind = "title_kind"
    }
}

nonisolated private struct NextMoeRef: Decodable, Sendable {
    let source: String
    let externalID: String

    private enum CodingKeys: String, CodingKey {
        case source
        case externalID = "external_id"
    }
}

nonisolated private struct NextMoeIntro: Decodable, Sendable {
    let lang: String
    let value: String
}

nonisolated private struct NextMoeRating: Decodable, Sendable {
    let source: String
    let score: Double
    let voteCount: Int

    private enum CodingKeys: String, CodingKey {
        case source, score
        case voteCount = "vote_count"
    }
}

nonisolated private struct NextMoe标签: Decodable, Sendable {
    let id: String?
    let displayName: String
    let isSexual: Bool
    let spoiler: String
    let tagKind: String?

    private enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name"
        case isSexual = "is_sexual"
        case spoiler
        case tagKind = "tag_kind"
    }
}

nonisolated private struct NextMoe公司: Decodable, Sendable {
    let id: String
    let displayName: String
    let attributionRole: String

    private enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name"
        case attributionRole = "attribution_role"
    }
}

nonisolated private struct NextMoe平台: Decodable, Sendable {
    let platform: String
}

nonisolated private struct NextMoe链接: Decodable, Sendable {
    let source: String
    let url: String
}

nonisolated private struct NextMoe截图: Decodable, Sendable {
    let url: String
    let hash: String
    let width: Int?
    let height: Int?
    let sexual: String?
    let violence: String?
}

nonisolated private struct NextMoe发行版本: Decodable, Sendable {
    let id: String
    let workID: String?
    let title: String?
    let date: String?
    let lang: String
    let platform: String
    let platforms: [String]
    let releaseKind: String
    let refs: [NextMoeRef]

    private enum CodingKeys: String, CodingKey {
        case id, title, date, lang, platform, platforms, refs
        case workID = "work_id"
        case releaseKind = "release_kind"
    }
}

nonisolated private struct NextMoe声优: Decodable, Sendable {
    let id: String
    let displayName: String
    let latin: String?

    private enum CodingKeys: String, CodingKey {
        case id, latin
        case displayName = "display_name"
    }
}

nonisolated private struct NextMoe角色: Decodable, Sendable {
    let id: String
    let displayName: String
    let latin: String?
    let localized: [String: NextMoe本地化文本]
    let image: NextMoe图片?
    let rosterRole: String?
    let voices: [NextMoe声优]?
    let aliases: [NextMoe实体名称]?
    let intros: [NextMoeIntro]?
    let traits: [NextMoe特征]?
    let refs: [NextMoeRef]?
    let heightCM: Int?
    let weightKG: Int?
    let bloodType: String?
    let measurements: NextMoe三围?
    let gender: String?
    let birthday: String?

    private enum CodingKeys: String, CodingKey {
        case id, image, localized, voices, aliases, intros, traits, refs, latin
        case displayName = "display_name"
        case rosterRole = "roster_role"
        case heightCM = "height_cm"
        case weightKG = "weight_kg"
        case bloodType = "blood_type"
        case measurements
        case gender, birthday
    }
}

nonisolated private struct NextMoe角色摘要: Decodable, Sendable {
    let id: String
    let displayName: String
    let latin: String?
    let localized: [String: NextMoe本地化文本]
    let image: NextMoe图片?
    let figure: NextMoe图片?
    let rosterRole: String
    let spoiler: String
    let voices: [NextMoe声优]

    private enum CodingKeys: String, CodingKey {
        case id, latin, localized, image, figure, voices, spoiler
        case displayName = "display_name"
        case rosterRole = "roster_role"
    }
}

nonisolated private struct NextMoe实体名称: Decodable, Sendable {
    let value: String
}

nonisolated private struct NextMoe特征: Decodable, Sendable {
    let id: String
    let displayName: String
    let group: String?
    let spoiler: String
    let isSexual: Bool
    let isLie: Bool

    private enum CodingKeys: String, CodingKey {
        case id, group, spoiler
        case displayName = "display_name"
        case isSexual = "is_sexual"
        case isLie = "is_lie"
    }
}

nonisolated private struct NextMoe三围: Decodable, Sendable {
    let bustCM: Int?
    let waistCM: Int?
    let hipCM: Int?
    let cup: String?

    private enum CodingKeys: String, CodingKey {
        case cup
        case bustCM = "bust_cm"
        case waistCM = "waist_cm"
        case hipCM = "hip_cm"
    }
}

nonisolated private struct NextMoe关系: Decodable, Sendable {
    let relationType: String
    let work: NextMoe作品

    private enum CodingKeys: String, CodingKey {
        case work
        case relationType = "relation_type"
    }
}

nonisolated private struct NextMoe出演: Decodable, Sendable {
    let work: NextMoe作品
    let rosterRole: String
    let spoiler: String
    let voices: [NextMoe声优]

    private enum CodingKeys: String, CodingKey {
        case work, spoiler, voices
        case rosterRole = "roster_role"
    }
}

nonisolated private struct NextMoe署名: Decodable, Sendable {
    let id: String
    let displayName: String
    let latin: String?
    let characterID: String?

    private enum CodingKeys: String, CodingKey {
        case id, latin
        case displayName = "display_name"
        case characterID = "character_id"
    }
}

nonisolated private struct NextMoe署名分组: Decodable, Sendable {
    let roleKey: String
    let credits: [NextMoe署名]

    private enum CodingKeys: String, CodingKey {
        case credits
        case roleKey = "role_key"
    }
}

nonisolated private struct NextMoe作品: Decodable, Sendable {
    let id: String
    let displayName: String
    let latin: String?
    let localized: [String: NextMoe本地化文本]
    let olang: String
    let releaseDate: String?
    let releaseStatus: String
    let cover: NextMoe图片?
    let titles: [NextMoe标题]?
    let refs: [NextMoeRef]?
    let intros: [NextMoeIntro]?
    let ratings: [NextMoeRating]?
    let tags: [NextMoe标签]?
    let companies: [NextMoe公司]?
    let platforms: [NextMoe平台]?
    let screenshots: [NextMoe截图]?
    let releases: [NextMoe发行版本]?
    let characters: [NextMoe角色摘要]?
    let relations: [NextMoe关系]?
    let credits: [NextMoe署名分组]?
    let links: [NextMoe链接]?

    private enum CodingKeys: String, CodingKey {
        case id, latin, localized, olang, cover, titles, refs, intros
        case ratings, tags, companies, platforms, screenshots, releases
        case characters, relations, credits, links
        case displayName = "display_name"
        case releaseDate = "release_date"
        case releaseStatus = "release_status"
    }
}

@MainActor
final class VNDB服务: ObservableObject, VNDB搜索服务协议 {
    static let shared = VNDB服务()

    @Published var isLoading = false
    @Published var errorMessage: String?

    private let baseURL: String
    private let session: URLSession
    private let userListFields = """
    id,vote,started,finished,notes,labels{id,label},\
    releases{list_status,id,title,alttitle,released,languages{lang,title,latin,mtl,main},platforms},\
    vn{title,titles{lang,title,latin,official,main},image{url,thumbnail,dims,sexual,violence},rating,votecount,released}
    """

    private static let searchReleaseFields = """
    title,alttitle,languages{lang,title,latin,mtl,main},platforms,media{medium,qty},\
    vns{rtype,id,title,titles{lang,title,latin,official,main},image{id,url,thumbnail,dims,sexual,violence}},\
    producers{developer,publisher,id,name,original},images{id,url,thumbnail,dims,sexual,violence,type,vn,languages,photo},\
    released,minage,patch,freeware,uncensored,official,has_ero,resolution,engine,voiced,notes,gtin,catalog,\
    extlinks{url,label,name,id}
    """
    private static let searchStaffFields = "name,original,aid,ismain,lang,gender,description,extlinks{url,label,name,id},aliases{aid,name,latin,ismain}"
    private static let searchProducerFields = "name,original,aliases,lang,type,description,extlinks{url,label,name,id}"
    private var searchCacheLifetime: TimeInterval {
        缓存策略.当前.searchLifetime
    }

    private var detailCacheLifetime: TimeInterval {
        缓存策略.当前.visualNovelDetailLifetime
    }
    private let eventMetadataCacheLifetime: TimeInterval = 12 * 60 * 60
    private let eventLibraryCacheLifetime: TimeInterval = 10 * 60
    private var releaseCacheLifetime: TimeInterval {
        缓存策略.当前.releaseLifetime
    }
    private let userCacheLifetime: TimeInterval = 10 * 60
    private let schemaCacheLifetime: TimeInterval = 30 * 24 * 60 * 60

    private struct 缓存条目<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    private var visualNovelMemoryCache:
        [String: 缓存条目<视觉小说详细信息>] = [:]
    private var eventMetadataMemoryCache:
        [String: 缓存条目<VNDB视觉小说活动元数据>] = [:]
    private var eventLibraryMemoryCache:
        [String: 缓存条目<[VNDB用户资料库活动项目]>] = [:]
    private var characterMemoryCache:
        [String: 缓存条目<角色详细信息>] = [:]
    private var releaseMemoryCache:
        [String: 缓存条目<[视觉小说发行版本]>] = [:]
    private var userListMemoryCache:
        [String: 缓存条目<用户列表响应>] = [:]
    private var userItemMemoryCache:
        [String: 缓存条目<用户列表项目?>] = [:]
    private var schemaMemoryCache: 缓存条目<VNDB搜索筛选目录>?
    private var validatedListWriteTokens: Set<String> = []
    private var recentPrefetchTask: Task<Void, Never>?
    private var prefetchedRecentVNIDs: Set<String> = []
    private var diskWriteTasks: [UUID: Task<Void, Never>] = [:]
    private var cacheWritesEnabled = true
    private var lastSearchCacheCleanupAt: Date?
    private let cacheDirectory: URL

    private convenience init() {
        self.init(session: .shared)
    }

    init(
        session: URLSession,
        baseURL: String = "https://api.vndb.org/kana",
        cacheDirectory: URL? = nil
    ) {
        self.session = session
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let root = cacheDirectory ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
        self.cacheDirectory = cacheDirectory == nil
            ? root.appendingPathComponent("PaperVNContentCache", isDirectory: true)
            : root
        try? FileManager.default.createDirectory(
            at: self.cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func cacheSizeInBytes() -> Int64 {
        Int64(URLCache.shared.currentDiskUsage)
            + diskUsage(of: cacheDirectory)
    }

    func clearCache() async {
        cacheWritesEnabled = false
        recentPrefetchTask?.cancel()
        recentPrefetchTask = nil
        let pendingWrites = Array(diskWriteTasks.values)
        diskWriteTasks.removeAll()
        for task in pendingWrites {
            task.cancel()
            await task.value
        }
        cacheWritesEnabled = false
        prefetchedRecentVNIDs.removeAll()
        visualNovelMemoryCache.removeAll()
        eventMetadataMemoryCache.removeAll()
        eventLibraryMemoryCache.removeAll()
        characterMemoryCache.removeAll()
        releaseMemoryCache.removeAll()
        userListMemoryCache.removeAll()
        userItemMemoryCache.removeAll()
        schemaMemoryCache = nil
        let oldURLCache = URLCache.shared
        oldURLCache.removeAllCachedResponses()
        oldURLCache.memoryCapacity = 0
        oldURLCache.diskCapacity = 0
        缓存策略.应用URLCache配置()

        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func clearTransientDetailCache() async {
        let pendingWrites = Array(diskWriteTasks.values)
        diskWriteTasks.removeAll()
        for task in pendingWrites {
            task.cancel()
            await task.value
        }

        visualNovelMemoryCache.removeAll()
        characterMemoryCache.removeAll()
        releaseMemoryCache.removeAll()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        let transientPrefixes = [
            "vn_detail_v2_",
            "character_detail_",
            "vn_releases_"
        ]
        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            guard transientPrefixes.contains(where: name.hasPrefix) else {
                continue
            }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func diskUsage(of directory: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize ?? values.fileSize ?? 0
            )
        }
        return total
    }

    func fetchUserList(
        token: String,
        userID: String,
        filter: 用户列表筛选,
        sort: 用户列表排序 = .lastModified,
        isDescending: Bool = true,
        page: Int = 1,
        forceRefresh: Bool = false
    ) async throws -> 用户列表响应 {
        guard !token.isEmpty, !userID.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let cacheKey = userListCacheKey(
            userID: userID,
            filter: filter,
            sort: sort,
            isDescending: isDescending,
            page: page
        )
        if !forceRefresh,
           let cached = userListCacheEntry(for: cacheKey),
           isFresh(cached.savedAt, lifetime: userCacheLifetime) {
            return cached.value
        }

        let url = URL(string: "\(baseURL)/ulist")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = [
            "user": userID,
            "fields": userListFields,
            "sort": sort.apiSort,
            "reverse": isDescending,
            "results": 50,
            "page": page
        ]
        if let labelID = filter.labelID {
            body["filters"] = ["label", "=", labelID]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request, accepting: [200])
        let response = try JSONDecoder().decode(
            用户列表响应.self,
            from: data
        )
        saveUserListCache(response, key: cacheKey)
        return response
    }

    func fetchAllUserList(
        token: String,
        userID: String,
        filter: 用户列表筛选 = .all,
        sort: 用户列表排序 = .lastModified,
        isDescending: Bool = true,
        forceRefresh: Bool = false
    ) async throws -> [用户列表项目] {
        var page = 1
        var values: [用户列表项目] = []
        repeat {
            try Task.checkCancellation()
            let response = try await fetchUserList(
                token: token,
                userID: userID,
                filter: filter,
                sort: sort,
                isDescending: isDescending,
                page: page,
                forceRefresh: forceRefresh
            )
            values.append(contentsOf: response.results)
            guard response.more else { break }
            page += 1
        } while page <= 1000
        return 排序用户列表(
            values,
            sort: sort,
            isDescending: isDescending
        )
    }

    func fetchUserLibraryEventMetadata(
        token: String,
        userID: String,
        forceRefresh: Bool = false
    ) async throws -> [VNDB用户资料库活动项目] {
        guard !token.isEmpty, !userID.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let cacheKey = "user_event_library_v1_\(userID)"
        if !forceRefresh,
           let cached = eventLibraryMemoryCache[cacheKey],
           isFresh(cached.savedAt, lifetime: eventLibraryCacheLifetime) {
            return cached.value
        }
        if !forceRefresh,
           let cached: 缓存条目<[VNDB用户资料库活动项目]> = loadDiskCache(
               key: cacheKey
           ),
           isFresh(cached.savedAt, lifetime: eventLibraryCacheLifetime) {
            eventLibraryMemoryCache[cacheKey] = cached
            return cached.value
        }

        let fields = "id,vn{title,titles{lang,title,latin,official,main}}"
        var page = 1
        var values: [VNDB用户资料库活动项目] = []
        repeat {
            try Task.checkCancellation()
            var request = URLRequest(url: URL(string: "\(baseURL)/ulist")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "user": userID,
                "fields": fields,
                "sort": 用户列表排序.lastModified.rawValue,
                "reverse": true,
                "results": 100,
                "page": page,
                "count": false
            ])

            let data = try await perform(request, accepting: [200])
            let response = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder().decode(
                    VNDB用户资料库活动响应.self,
                    from: data
                )
            }.value
            values.append(contentsOf: response.results)
            guard response.more else { break }
            page += 1
        } while page <= 1000

        let entry = 缓存条目(savedAt: Date(), value: values)
        eventLibraryMemoryCache[cacheKey] = entry
        saveDiskCache(entry, key: cacheKey)
        return values
    }

    func loadCachedList(
        filter: 用户列表筛选,
        userID: String,
        sort: 用户列表排序 = .lastModified,
        isDescending: Bool = true
    ) -> [用户列表项目]? {
        var page = 1
        var values: [用户列表项目] = []

        repeat {
            guard let cached = userListCacheEntry(
                for: userListCacheKey(
                    userID: userID,
                    filter: filter,
                    sort: sort,
                    isDescending: isDescending,
                    page: page
                )
            ) else {
                return nil
            }

            values.append(contentsOf: cached.value.results)
            guard cached.value.more else {
                return 排序用户列表(
                    values,
                    sort: sort,
                    isDescending: isDescending
                )
            }
            page += 1
        } while page <= 1000

        return nil
    }

    private func 排序用户列表(
        _ items: [用户列表项目],
        sort: 用户列表排序,
        isDescending: Bool
    ) -> [用户列表项目] {
        guard sort == .averageRating else { return items }
        return items.sorted { lhs, rhs in
            switch (lhs.vn.rating, rhs.vn.rating) {
            case let (lhsRating?, rhsRating?) where lhsRating != rhsRating:
                return isDescending ? lhsRating > rhsRating : lhsRating < rhsRating
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                let titleOrder = lhs.vn.title.localizedStandardCompare(rhs.vn.title)
                if titleOrder != .orderedSame {
                    return isDescending
                        ? titleOrder == .orderedDescending
                        : titleOrder == .orderedAscending
                }
                return isDescending ? lhs.id > rhs.id : lhs.id < rhs.id
            }
        }
    }

    func prefetchRecentlyChanged(
        _ items: [用户列表项目],
        limit: Int = 4
    ) {
        guard 缓存策略.当前 != .less else { return }
        let effectiveLimit = 缓存策略.当前 == .more ? items.count : limit
        let candidates = items.prefix(effectiveLimit).filter {
            !prefetchedRecentVNIDs.contains($0.id)
        }
        guard !candidates.isEmpty else { return }

        prefetchedRecentVNIDs.formUnion(candidates.map(\.id))
        recentPrefetchTask?.cancel()
        recentPrefetchTask = Task(priority: .background) { [weak self] in
            guard let self else { return }

            for item in candidates {
                guard !Task.isCancelled else { return }

                do {
                    async let detailRequest = fetchVNDetail(vnID: item.id)
                    async let releaseRequest = fetchVNReleases(vnID: item.id)
                    let detail = try await detailRequest
                    _ = try? await releaseRequest
                    await warmImageCache(for: detail, fallback: item)
                } catch is CancellationError {
                    return
                } catch {
                    prefetchedRecentVNIDs.remove(item.id)
                }

                await Task.yield()
            }
        }
    }

    func prefetchVisualNovelGraph(
        vnIDs: [String],
        maximumDepth: Int = 5
    ) {
        guard 缓存策略.当前 == .more else { return }
        let roots = Array(Set(vnIDs.filter { !$0.isEmpty }))
        guard !roots.isEmpty else { return }
        Task(priority: .background) { [weak self] in
            guard let self else { return }
            for id in roots {
                await prefetchVisualNovelGraphNode(
                    id: id,
                    depth: 0,
                    maximumDepth: maximumDepth,
                    visited: []
                )
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func prefetchVisualNovelGraphNode(
        id: String,
        depth: Int,
        maximumDepth: Int,
        visited: Set<String>
    ) async {
        guard !Task.isCancelled, !visited.contains(id) else { return }
        var visited = visited
        visited.insert(id)
        guard let detail = try? await fetchVNDetail(vnID: id) else { return }
        await warmImages(for: detail)
        for characterID in Set(detail.va?.map { $0.character.id } ?? []) {
            if let character = try? await fetchCharacterDetail(
                characterID: characterID
            ), depth < maximumDepth {
                for vn in character.vns ?? [] {
                    await prefetchVisualNovelGraphNode(
                        id: vn.id,
                        depth: depth + 1,
                        maximumDepth: maximumDepth,
                        visited: visited
                    )
                }
            }
        }
        guard depth < maximumDepth else { return }
        for relationID in detail.relations?.map(\.id) ?? [] {
            await prefetchVisualNovelGraphNode(
                id: relationID,
                depth: depth + 1,
                maximumDepth: maximumDepth,
                visited: visited
            )
        }
    }

    private func warmImages(for detail: 视觉小说详细信息) async {
        let urls = [detail.image?.url]
            .compactMap { $0 }
            + (detail.screenshots ?? []).compactMap { $0.url }
            + (detail.va ?? []).compactMap { $0.character.image?.url }
        for value in urls {
            guard !Task.isCancelled, let url = URL(string: value) else {
                return
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            _ = try? await PaperVNConnect网络设置.发送图片请求(
                request,
                session: .shared
            )
        }
    }

    func fetchUserListItem(
        token: String,
        userID: String,
        vnID: String,
        forceRefresh: Bool = false
    ) async throws -> 用户列表项目? {
        guard !token.isEmpty, !userID.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }

        let cacheKey = userItemCacheKey(userID: userID, vnID: vnID)
        if !forceRefresh,
           let cached = userItemCacheEntry(for: cacheKey),
           isFresh(cached.savedAt, lifetime: userCacheLifetime) {
            return cached.value
        }

        let url = URL(string: "\(baseURL)/ulist")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "user": userID,
                "filters": ["id", "=", vnID],
                "fields": userListFields,
                "results": 1
            ]
        )

        let data = try await perform(request, accepting: [200])
        let item = try JSONDecoder()
            .decode(用户列表响应.self, from: data)
            .results
            .first
        saveUserItemCache(item, key: cacheKey)
        return item
    }

    func loadCachedUserListItem(
        userID: String,
        vnID: String
    ) -> 用户列表项目? {
        userItemCacheEntry(
            for: userItemCacheKey(userID: userID, vnID: vnID)
        )?.value
    }

    func 搜索视觉小说(
        关键词: String,
        筛选: 视觉小说搜索筛选,
        排序: 视觉小说搜索排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<视觉小说搜索结果> {
        let query = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = """
        title,alttitle,titles{lang,title,latin,official,main},aliases,released,\
        languages,platforms,image{id,url,thumbnail,dims,sexual,violence},\
        length,length_minutes,rating,votecount,\
        tags{category},developers{id,name,original}
        """
        let filterObject: Any = query.isEmpty && 筛选.isEmpty
            ? []
            : 作品筛选条件(keyword: query, filters: 筛选)
        let effectiveSort = query.isEmpty && 排序 == .relevance
            ? 视觉小说搜索排序.rating
            : 排序
        let effectiveDescending = query.isEmpty && 排序 == .relevance
            ? effectiveSort.defaultIsDescending
            : 降序
        let body: [String: Any] = [
            "filters": filterObject,
            "fields": fields,
            "sort": effectiveSort.apiSort,
            "reverse": effectiveDescending,
            "results": min(max(每页, 1), 100),
            "page": max(页码, 1),
            "count": false
        ]

        let data = try await 执行搜索请求(
            endpoint: "vn",
            body: body,
            cacheKey: "vn_search_\(搜索缓存键(query: query, body: body))"
        )
        return try JSONDecoder().decode(
            搜索分页响应<视觉小说搜索结果>.self,
            from: data
        )
    }

    func 获取搜索筛选目录(
        forceRefresh: Bool = false
    ) async throws -> VNDB搜索筛选目录 {
        let cached = 搜索筛选目录缓存()
        if !forceRefresh,
           let cached,
           isFresh(cached.savedAt, lifetime: schemaCacheLifetime) {
            return VNDB搜索筛选目录.builtIn.merging(
                Self.规范化搜索筛选目录(cached.value)
            )
        }

        do {
            guard let url = URL(string: "\(baseURL)/schema") else {
                throw URLError(.badURL)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            let data = try await perform(request, accepting: [200])
            let catalog = try Self.解析搜索筛选目录(data)
            let merged = VNDB搜索筛选目录.builtIn.merging(catalog)
            let entry = 缓存条目(savedAt: Date(), value: merged)
            schemaMemoryCache = entry
            saveDiskCache(entry, key: "vndb_schema_filter_catalog")
            return merged
        } catch {
            if let cached {
                return VNDB搜索筛选目录.builtIn.merging(
                    Self.规范化搜索筛选目录(cached.value)
                )
            }
            throw error
        }
    }

    nonisolated static func 解析搜索筛选目录(
        _ data: Data
    ) throws -> VNDB搜索筛选目录 {
        guard let root = try JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Invalid VNDB schema")
            )
        }

        let enumerations = root["enums"] as? [String: Any] ?? root
        let languages = schemaOptions(
            from: enumerations,
            keys: ["language", "languages"]
        ) + schemaObjectOptions(
            from: root["languages"]
        )
        let platforms = schemaOptions(
            from: enumerations,
            keys: ["platform", "platforms"]
        ) + schemaObjectOptions(
            from: root["platforms"]
        )
        guard !platforms.isEmpty else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "Missing platform enumeration"
                )
            )
        }
        return VNDB搜索筛选目录(
            languages: deduplicatedSchemaOptions(
                languages,
                normalizeLanguageCodes: true
            ),
            platforms: deduplicatedSchemaOptions(platforms)
        )
    }

    nonisolated private static func 规范化搜索筛选目录(
        _ catalog: VNDB搜索筛选目录
    ) -> VNDB搜索筛选目录 {
        VNDB搜索筛选目录(
            languages: deduplicatedSchemaOptions(
                catalog.languages,
                normalizeLanguageCodes: true
            ),
            platforms: deduplicatedSchemaOptions(catalog.platforms)
        )
    }

    nonisolated private static func schemaObjectOptions(
        from raw: Any?
    ) -> [VNDB筛选选项] {
        guard let values = raw as? [String: Any] else { return [] }
        return values.map { code, value in
            let name: String
            if let value = value as? String {
                name = value
            } else if let value = value as? [String: Any] {
                name = value["name"] as? String
                    ?? value["label"] as? String
                    ?? value["title"] as? String
                    ?? code
            } else {
                name = code
            }
            return .init(code: code, name: name)
        }
    }

    nonisolated private static func deduplicatedSchemaOptions(
        _ options: [VNDB筛选选项],
        normalizeLanguageCodes: Bool = false
    ) -> [VNDB筛选选项] {
        var seen: Set<String> = []
        return options
            .compactMap { option in
                let code = normalizeLanguageCodes
                    ? normalizedVNDBLanguageCode(option.code)
                    : option.code
                guard !code.isEmpty, seen.insert(code).inserted else { return nil }
                return VNDB筛选选项(code: code, name: option.name)
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    nonisolated private static func schemaOptions(
        from enumerations: [String: Any],
        keys: [String]
    ) -> [VNDB筛选选项] {
        guard let raw = keys.compactMap({ enumerations[$0] }).first else {
            return []
        }

        var options: [VNDB筛选选项] = []
        if let values = raw as? [String: Any] {
            for (code, value) in values {
                let name: String
                if let value = value as? String {
                    name = value
                } else if let value = value as? [String: Any] {
                    name = value["name"] as? String
                        ?? value["label"] as? String
                        ?? value["title"] as? String
                        ?? code
                } else {
                    name = code
                }
                options.append(.init(code: code, name: name))
            }
        } else if let values = raw as? [Any] {
            for value in values {
                if let code = value as? String {
                    options.append(.init(code: code, name: code))
                    continue
                }
                guard let value = value as? [String: Any],
                      let code = value["code"] as? String
                        ?? value["id"] as? String
                        ?? value["value"] as? String else {
                    continue
                }
                let name = value["name"] as? String
                    ?? value["label"] as? String
                    ?? value["title"] as? String
                    ?? code
                options.append(.init(code: code, name: name))
            }
        }

        var seen: Set<String> = []
        return options
            .filter { !$0.code.isEmpty && seen.insert($0.code).inserted }
            .sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    func 搜索角色(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<角色搜索结果> {
        let query = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw VNDB服务错误.无效搜索关键词 }

        let body: [String: Any] = [
            "filters": ["search", "=", query],
            "fields": "name,original,aliases,image{url,sexual,violence},vns{id,role}",
            "sort": "searchrank",
            "reverse": false,
            "results": min(max(每页, 1), 100),
            "page": max(页码, 1),
            "count": false
        ]

        let data = try await 执行搜索请求(endpoint: "character", body: body)
        return try JSONDecoder().decode(
            搜索分页响应<角色搜索结果>.self,
            from: data
        )
    }

    /// 按编号批量获取视觉小说，字段与搜索结果相同，按传入顺序返回。
    func 按编号获取视觉小说(_ ids: [String]) async throws -> [视觉小说搜索结果] {
        guard !ids.isEmpty else { return [] }
        let fields = """
        title,alttitle,titles{lang,title,latin,official,main},aliases,released,\
        languages,platforms,image{id,url,thumbnail,dims,sexual,violence},\
        length,length_minutes,rating,votecount,\
        tags{category},developers{id,name,original}
        """
        let body: [String: Any] = [
            "filters": 编号筛选(ids),
            "fields": fields,
            "results": min(ids.count, 100),
        ]
        let data = try await 执行搜索请求(
            endpoint: "vn",
            body: body,
            cacheKey: "vn_search_\(搜索缓存键(query: "", body: body))"
        )
        let results = try JSONDecoder().decode(
            搜索分页响应<视觉小说搜索结果>.self,
            from: data
        ).results
        return 按编号排序(results, ids: ids, id: \.id)
    }

    /// 按编号批量获取角色，字段与搜索结果相同，按传入顺序返回。
    func 按编号获取角色(_ ids: [String]) async throws -> [角色搜索结果] {
        guard !ids.isEmpty else { return [] }
        let body: [String: Any] = [
            "filters": 编号筛选(ids),
            "fields": "name,original,aliases,image{url,sexual,violence},vns{id,role}",
            "results": min(ids.count, 100),
        ]
        let data = try await 执行搜索请求(
            endpoint: "character",
            body: body,
            cacheKey: "character_search_\(搜索缓存键(query: "", body: body))"
        )
        let results = try JSONDecoder().decode(
            搜索分页响应<角色搜索结果>.self,
            from: data
        ).results
        return 按编号排序(results, ids: ids, id: \.id)
    }

    /// 按编号批量获取并同时满足筛选条件，按传入顺序返回。设备端智能搜索找到、但 VNDB 搜索没返回的条目
    /// 用它补上详情；带上筛选条件，筛选在综合搜索里对这些条目同样生效。
    func 按编号获取视觉小说(_ ids: [String], 筛选: 视觉小说搜索筛选) async throws -> [视觉小说搜索结果] {
        guard !筛选.isEmpty else { return try await 按编号获取视觉小说(ids) }
        guard !ids.isEmpty else { return [] }
        let fields = """
        title,alttitle,titles{lang,title,latin,official,main},aliases,released,\
        languages,platforms,image{id,url,thumbnail,dims,sexual,violence},\
        length,length_minutes,rating,votecount,\
        tags{category},developers{id,name,original}
        """
        let body: [String: Any] = [
            "filters": 搜索条件组合(编号筛选(ids), with: 作品筛选条件(keyword: "", filters: 筛选)),
            "fields": fields,
            "results": min(ids.count, 100),
        ]
        let data = try await 执行搜索请求(
            endpoint: "vn",
            body: body,
            cacheKey: "vn_search_\(搜索缓存键(query: "", body: body))"
        )
        let results = try JSONDecoder().decode(搜索分页响应<视觉小说搜索结果>.self, from: data).results
        return 按编号排序(results, ids: ids, id: \.id)
    }

    func 按编号获取角色(_ ids: [String], 筛选: 搜索扩展筛选) async throws -> [角色搜索结果] {
        try await 按编号获取扩展对象(
            endpoint: "character",
            ids: ids,
            fields: "name,original,aliases,image{url,sexual,violence},vns{id,role}",
            筛选: 扩展筛选条件(筛选, scope: .character)
        )
    }

    func 按编号获取制作人员(_ ids: [String], 筛选: 搜索扩展筛选) async throws -> [探索制作人员] {
        try await 按编号获取扩展对象(
            endpoint: "staff",
            ids: ids,
            fields: VNDB服务.searchStaffFields,
            筛选: 搜索条件组合(["ismain", "=", 1], with: 扩展筛选条件(筛选, scope: .staff))
        )
    }

    func 按编号获取会社(_ ids: [String], 筛选: 搜索扩展筛选) async throws -> [探索会社] {
        try await 按编号获取扩展对象(
            endpoint: "producer",
            ids: ids,
            fields: VNDB服务.searchProducerFields,
            筛选: 扩展筛选条件(筛选, scope: .producer)
        )
    }

    private func 按编号获取扩展对象<Item: Codable & Identifiable>(
        endpoint: String,
        ids: [String],
        fields: String,
        筛选: Any
    ) async throws -> [Item] where Item.ID == String {
        guard !ids.isEmpty else { return [] }
        let body: [String: Any] = [
            "filters": 搜索条件组合(编号筛选(ids), with: 筛选),
            "fields": fields,
            "results": min(ids.count, 100),
        ]
        let data = try await 执行搜索请求(
            endpoint: endpoint,
            body: body,
            cacheKey: "\(endpoint)_ids_\(搜索缓存键(query: "", body: body))"
        )
        let results = try JSONDecoder().decode(搜索分页响应<Item>.self, from: data).results
        return 按编号排序(results, ids: ids, id: \.id)
    }

    /// 作品筛选条件；发行版本规则编成嵌套的 release 筛选（作品至少有一个发行版本满足）。
    private func 作品筛选条件(keyword: String, filters: 视觉小说搜索筛选) -> Any {
        let 作品条件 = VNDB视觉小说筛选编译器.filterObject(keyword: keyword, filters: filters)
        let 发行版本条件 = 扩展筛选条件(filters.发行版本规则, scope: .release)
        if let 空 = 发行版本条件 as? [Any], 空.isEmpty {
            return 作品条件
        }
        return 搜索条件组合(作品条件, with: ["release", "=", 发行版本条件])
    }

    private func 编号筛选(_ ids: [String]) -> [Any] {
        ids.count == 1
            ? ["id", "=", ids[0]]
            : ["or"] + ids.map { ["id", "=", $0] as [Any] }
    }

    private func 按编号排序<Item>(
        _ items: [Item],
        ids: [String],
        id: KeyPath<Item, String>
    ) -> [Item] {
        let order = Dictionary(
            ids.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return items.sorted {
            (order[$0[keyPath: id]] ?? .max) < (order[$1[keyPath: id]] ?? .max)
        }
    }

    func 搜索角色(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<角色搜索结果> {
        let body = 搜索扩展请求体(
            endpoint: "character",
            keyword: 关键词,
            filter: 扩展筛选条件(筛选, scope: .character),
            fields: "name,original,aliases,image{url,sexual,violence},vns{id,role}",
            sort: 排序.apiSort(for: .character),
            reverse: 降序,
            page: 页码,
            pageSize: 每页
        )
        let data = try await 执行搜索请求(
            endpoint: "character", body: body,
            cacheKey: "character_search_\(搜索缓存键(query: 关键词, body: body))"
        )
        return try JSONDecoder().decode(搜索分页响应<角色搜索结果>.self, from: data)
    }

    func 搜索发行版本(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索发行版本> {
        try await 搜索扩展对象(
            endpoint: "release",
            关键词: 关键词,
            fields: VNDB服务.searchReleaseFields,
            页码: 页码,
            每页: 每页
        )
    }

    func 搜索发行版本(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索发行版本> {
        try await 搜索扩展对象(
            endpoint: "release",
            关键词: 关键词,
            fields: VNDB服务.searchReleaseFields,
            附加筛选: 扩展筛选条件(筛选, scope: .release),
            排序: 排序.apiSort(for: .release),
            降序: 降序,
            页码: 页码,
            每页: 每页,
            允许空关键词: true
        )
    }

    func 搜索制作人员(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索制作人员> {
        try await 搜索扩展对象(
            endpoint: "staff",
            关键词: 关键词,
            fields: VNDB服务.searchStaffFields,
            附加筛选: ["ismain", "=", 1],
            页码: 页码,
            每页: 每页
        )
    }

    func 搜索制作人员(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索制作人员> {
        try await 搜索扩展对象(
            endpoint: "staff",
            关键词: 关键词,
            fields: VNDB服务.searchStaffFields,
            附加筛选: 搜索条件组合(
                ["ismain", "=", 1],
                with: 扩展筛选条件(筛选, scope: .staff)
            ),
            排序: 排序.apiSort(for: .staff),
            降序: 降序,
            页码: 页码,
            每页: 每页,
            允许空关键词: true
        )
    }

    func 搜索会社(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索会社> {
        try await 搜索扩展对象(
            endpoint: "producer",
            关键词: 关键词,
            fields: VNDB服务.searchProducerFields,
            页码: 页码,
            每页: 每页
        )
    }

    func 搜索会社(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索会社> {
        try await 搜索扩展对象(
            endpoint: "producer",
            关键词: 关键词,
            fields: VNDB服务.searchProducerFields,
            附加筛选: 扩展筛选条件(筛选, scope: .producer),
            排序: 排序.apiSort(for: .producer),
            降序: 降序,
            页码: 页码,
            每页: 每页,
            允许空关键词: true
        )
    }

    private func 扩展筛选条件(
        _ filters: 搜索扩展筛选,
        scope: 搜索范围
    ) -> Any {
        let expressions = filters.configuredRules.compactMap {
            扩展规则表达式($0, scope: scope)
        }
        switch expressions.count {
        case 0: return []
        case 1: return expressions[0]
        default:
            var result: [Any] = ["and"]
            result.append(contentsOf: expressions)
            return result
        }
    }

    private func 扩展规则表达式(
        _ rule: 搜索扩展筛选规则组,
        scope: 搜索范围
    ) -> [Any]? {
        let expressions = rule.configuredConditions.compactMap {
            扩展条件表达式($0, scope: scope, mode: rule.matchMode)
        }
        guard !expressions.isEmpty else { return nil }

        var expression: [Any]
        if expressions.count == 1 {
            expression = expressions[0]
        } else {
            expression = ["and"]
            expression.append(contentsOf: expressions)
        }
        return rule.isExcluded ? 反转扩展表达式(expression) : expression
    }

    private func 扩展条件表达式(
        _ condition: 搜索扩展筛选条件,
        scope: 搜索范围,
        mode: 视觉小说筛选匹配方式
    ) -> [Any]? {
        guard 扩展字段适用(condition.field, scope: scope) else { return nil }
        let leaves: [[Any]] = condition.normalizedStringValues.compactMap { value in
            switch condition.field {
            case .birthday:
                guard let month = Int(value), (1...12).contains(month) else {
                    return nil
                }
                return ["birthday", "=", [month, 0]]
            case .role:
                let allowedValues: Set<String>
                switch scope {
                case .character:
                    allowedValues = ["main", "primary", "side", "appears"]
                case .staff:
                    allowedValues = [
                        "scenario", "director", "chardesign", "art", "music",
                        "songs", "translator", "editor", "qa", "staff"
                    ]
                default:
                    return nil
                }
                guard allowedValues.contains(value) else { return nil }
                return ["role", "=", value]
            case .trait:
                return ["trait", "=", value]
            case .releaseTime:
                switch value {
                case "recent": return ["released", "<=", "today"]
                case "upcoming":
                    return [
                        "and",
                        ["released", ">", "today"],
                        ["released", "!=", "TBA"]
                    ]
                default: return nil
                }
            case .releaseAttribute:
                switch value {
                case "freeware": return ["freeware", "=", 1]
                case "official": return ["official", "=", 1]
                default: return nil
                }
            case .language:
                return ["lang", "=", value]
            case .platform:
                return ["platform", "=", value]
            case .type:
                return ["type", "=", value]
            }
        }
        guard !leaves.isEmpty else { return nil }
        if leaves.count == 1 { return leaves[0] }
        var expression: [Any] = [mode == .all ? "and" : "or"]
        expression.append(contentsOf: leaves)
        return expression
    }

    private func 扩展字段适用(
        _ field: 搜索扩展筛选字段,
        scope: 搜索范围
    ) -> Bool {
        switch (scope, field) {
        case (.character, .birthday), (.character, .role), (.character, .trait): return true
        case (.release, .releaseTime), (.release, .releaseAttribute),
             (.release, .language), (.release, .platform): return true
        case (.staff, .role): return true
        case (.producer, .type): return true
        default: return false
        }
    }

    private func 反转扩展表达式(_ expression: [Any]) -> [Any] {
        guard let operatorName = expression.first as? String else { return expression }
        if operatorName == "and" || operatorName == "or" {
            let invertedOperator = operatorName == "and" ? "or" : "and"
            var result: [Any] = [invertedOperator]
            result.append(contentsOf: expression.dropFirst().map { value in
                if let value = value as? [Any] {
                    return 反转扩展表达式(value) as Any
                }
                return value
            })
            return result
        }
        guard expression.count == 3,
              let comparison = expression[1] as? String else {
            return expression
        }
        let inverted: String
        switch comparison {
        case "=": inverted = "!="
        case "!=": inverted = "="
        case ">=": inverted = "<"
        case ">": inverted = "<="
        case "<=": inverted = ">"
        case "<": inverted = ">="
        default: inverted = comparison
        }
        return [expression[0], inverted, expression[2]]
    }

    private func 搜索扩展请求体(
        endpoint: String,
        keyword: String,
        filter: Any,
        fields: String,
        sort: String,
        reverse: Bool,
        page: Int,
        pageSize: Int
    ) -> [String: Any] {
        var filters: Any = filter
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            filters = 搜索条件组合(filter, with: ["search", "=", query])
        }
        let effectiveSort = query.isEmpty && sort == "searchrank" ? "id" : sort
        let effectiveReverse = query.isEmpty && sort == "searchrank" ? true : reverse
        return [
            "filters": filters,
            "fields": fields,
            "sort": effectiveSort,
            "reverse": effectiveReverse,
            "results": min(max(pageSize, 1), 100),
            "page": max(page, 1),
            "count": false
        ]
    }

    private func 搜索条件组合(_ lhs: Any, with rhs: Any) -> [Any] {
        if let lhs = lhs as? [Any], lhs.isEmpty {
            return rhs as? [Any] ?? [rhs]
        }
        if let rhs = rhs as? [Any], rhs.isEmpty {
            return lhs as? [Any] ?? [lhs]
        }
        return ["and", lhs, rhs]
    }

    private func 搜索扩展对象<Item: Codable>(
        endpoint: String,
        关键词: String,
        fields: String,
        附加筛选: Any? = nil,
        排序: String = "searchrank",
        降序: Bool = false,
        页码: Int,
        每页: Int,
        允许空关键词: Bool = false
    ) async throws -> 搜索分页响应<Item> {
        let query = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        guard 允许空关键词 || !query.isEmpty else {
            throw VNDB服务错误.无效搜索关键词
        }

        let searchFilter: Any? = query.isEmpty ? nil : ["search", "=", query]
        let filters: Any = if let 附加筛选, let searchFilter {
            搜索条件组合(searchFilter, with: 附加筛选)
        } else if let searchFilter {
            searchFilter
        } else if let 附加筛选 {
            附加筛选
        } else {
            []
        }
        let effectiveSort = query.isEmpty && 排序 == "searchrank" ? "id" : 排序
        let effectiveDescending = query.isEmpty && 排序 == "searchrank"
            ? true
            : 降序
        let body: [String: Any] = [
            "filters": filters,
            "fields": fields,
            "sort": effectiveSort,
            "reverse": effectiveDescending,
            "results": min(max(每页, 1), 100),
            "page": max(页码, 1),
            "count": false
        ]
        let data = try await 执行搜索请求(
            endpoint: endpoint,
            body: body,
            cacheKey: "\(endpoint)_search_\(搜索缓存键(query: query, body: body))"
        )
        return try JSONDecoder().decode(
            搜索分页响应<Item>.self,
            from: data
        )
    }

    private func 执行搜索请求(
        endpoint: String,
        body: [String: Any],
        cacheKey: String? = nil
    ) async throws -> Data {
        scheduleExpiredSearchCacheRemoval()
        if let cacheKey,
           searchCacheLifetime > 0,
           let cached: 缓存条目<Data> = loadDiskCache(key: cacheKey),
           isFresh(cached.savedAt, lifetime: searchCacheLifetime) {
            return cached.value
        }
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request, accepting: [200])
        if let cacheKey, searchCacheLifetime > 0 {
            saveDiskCache(
                缓存条目(savedAt: Date(), value: data),
                key: cacheKey
            )
        }
        return data
    }

    private func scheduleExpiredSearchCacheRemoval() {
        let now = Date()
        if let lastSearchCacheCleanupAt,
           now.timeIntervalSince(lastSearchCacheCleanupAt) < 5 * 60 {
            return
        }
        lastSearchCacheCleanupAt = now

        let directory = cacheDirectory
        let lifetime = searchCacheLifetime
        Task.detached(priority: .utility) {
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            for file in files {
                let name = file.deletingPathExtension().lastPathComponent
                guard name.contains("_search_") else { continue }
                if lifetime == 0 {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                guard let values = try? file.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ),
                let modifiedAt = values.contentModificationDate,
                now.timeIntervalSince(modifiedAt) > lifetime else {
                    continue
                }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func 搜索缓存键(query: String, body: [String: Any]) -> String {
        let bodyData = (try? JSONSerialization.data(
            withJSONObject: body,
            options: [.sortedKeys]
        )) ?? Data()
        let digest = SHA256.hash(data: Data(query.utf8) + bodyData)
            .map { String(format: "%02x", $0) }
            .joined()
        return digest
    }

    func fetchVNDetail(
        vnID: String,
        forceRefresh: Bool = false
    ) async throws -> 视觉小说详细信息 {
        if NextMoe内容设置.已启用 {
            do {
                return try await fetchNextMoeVNDetail(
                    vnID: vnID,
                    forceRefresh: forceRefresh
                )
            } catch {
                try Task.checkCancellation()
            }
        }
        let cacheKey = visualNovelCacheKey(vnID)
        if !forceRefresh,
           let cached = visualNovelCacheEntry(for: cacheKey),
           isFresh(cached.savedAt, lifetime: detailCacheLifetime) {
            return cached.value
        }
        try Task.checkCancellation()

        let url = URL(string: "\(baseURL)/vn")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fields = """
        title,titles{lang,title,latin,official,main},aliases,olang,devstatus,released,\
        languages,platforms,image{id,url,thumbnail,dims,sexual,violence},\
        length,length_minutes,length_votes,description,rating,votecount,\
        tags{id,name,rating,spoiler,lie,category},\
        developers{id,name,original},\
        screenshots{id,url,thumbnail,sexual,violence},\
        relations{relation,relation_official,id,title,titles{lang,title,latin,official,main},image{url,thumbnail,sexual,violence}},\
        staff{eid,role,note,id,name,original},\
        va{note,staff{id,name,original},character{id,name,original,aliases,image{url,sexual,violence}}},\
        extlinks{url,label,name}
        """
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "filters": ["id", "=", vnID],
                "fields": fields,
                "results": 1
            ]
        )

        let data = try await perform(request, accepting: [200])
        try Task.checkCancellation()
        let detail = try await Task.detached(priority: .userInitiated) {
            try JSONDecoder()
                .decode(VNDB视觉小说详情响应.self, from: data)
                .results
                .first
        }.value
        try Task.checkCancellation()
        guard let detail else {
            throw URLError(.resourceUnavailable)
        }
        saveVisualNovelCache(detail, key: cacheKey)
        return detail
    }

    func fetchVNEventMetadata(
        vnIDs: [String],
        forceRefresh: Bool = false
    ) async throws -> [VNDB视觉小说活动元数据] {
        let ids = Array(Set(vnIDs.filter { !$0.isEmpty }))
        guard !ids.isEmpty else { return [] }

        var values: [String: VNDB视觉小说活动元数据] = [:]
        var missingIDs: [String] = []
        for id in ids {
            let key = "vn_event_metadata_v1_\(id)"
            if !forceRefresh,
               let cached = eventMetadataMemoryCache[key],
               isFresh(cached.savedAt, lifetime: eventMetadataCacheLifetime) {
                values[id] = cached.value
            } else if !forceRefresh,
                      let cached: 缓存条目<VNDB视觉小说活动元数据> = loadDiskCache(
                          key: key
                      ),
                      isFresh(cached.savedAt, lifetime: eventMetadataCacheLifetime) {
                eventMetadataMemoryCache[key] = cached
                values[id] = cached.value
            } else {
                missingIDs.append(id)
            }
        }

        let fields = "id,title,titles{lang,title,latin,official,main},aliases,va{staff{name,original}}"
        var start = 0
        while start < missingIDs.count {
            try Task.checkCancellation()
            let end = min(start + 100, missingIDs.count)
            let chunk = Array(missingIDs[start..<end])
            var request = URLRequest(url: URL(string: "\(baseURL)/vn")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if forceRefresh {
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "filters": ["id", "in", chunk],
                "fields": fields,
                "results": chunk.count,
                "count": false
            ])

            let data = try await perform(request, accepting: [200])
            let details = try await Task.detached(priority: .userInitiated) {
                try JSONDecoder()
                    .decode(VNDB视觉小说活动元数据响应.self, from: data)
                    .results
            }.value
            for detail in details {
                values[detail.id] = detail
                let entry = 缓存条目(savedAt: Date(), value: detail)
                eventMetadataMemoryCache["vn_event_metadata_v1_\(detail.id)"] = entry
                saveDiskCache(entry, key: "vn_event_metadata_v1_\(detail.id)")
            }
            start = end
        }

        return ids.compactMap { values[$0] }
    }

    func loadCachedVNDetail(vnID: String) -> 视觉小说详细信息? {
        visualNovelCacheEntry(
            for: visualNovelCacheKey(vnID)
        )?.value
    }

    private func warmImageCache(
        for detail: 视觉小说详细信息,
        fallback item: 用户列表项目
    ) async {
        var urls: [String] = []

        if let cover = detail.image?.url ?? detail.image?.thumbnail
            ?? item.vn.image?.url ?? item.vn.image?.thumbnail {
            urls.append(cover)
        }
        urls.append(contentsOf: (detail.screenshots ?? []).prefix(2).compactMap {
            $0.url ?? $0.thumbnail
        })
        urls.append(contentsOf: (detail.va ?? []).prefix(2).compactMap {
            $0.character.image?.url
        })

        for urlString in urls {
            guard !Task.isCancelled, let url = URL(string: urlString) else {
                return
            }
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 20
            _ = try? await PaperVNConnect网络设置.发送图片请求(
                request,
                session: .shared
            )
        }
    }

    func fetchVNReleases(
        vnID: String,
        forceRefresh: Bool = false
    ) async throws -> [视觉小说发行版本] {
        if NextMoe内容设置.已启用 {
            do {
                return try await fetchNextMoeVNReleases(
                    vnID: vnID,
                    forceRefresh: forceRefresh
                )
            } catch {
                try Task.checkCancellation()
            }
        }
        let cacheKey = releaseCacheKey(vnID)
        if !forceRefresh,
           let cached = releaseCacheEntry(for: cacheKey),
           isFresh(cached.savedAt, lifetime: releaseCacheLifetime) {
            return cached.value
        }

        let url = URL(string: "\(baseURL)/release")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "filters": ["vn", "=", ["id", "=", vnID]],
                "fields": "title,alttitle,released,languages{lang,title,latin,mtl,main},platforms,official,vns{id,rtype}",
                "sort": "released",
                "reverse": true,
                "results": 100
            ]
        )

        struct 发行版本响应: Codable {
            let results: [视觉小说发行版本]
        }

        let data = try await perform(request, accepting: [200])
        let releases = try JSONDecoder()
            .decode(发行版本响应.self, from: data)
            .results
        saveReleaseCache(releases, key: cacheKey)
        return releases
    }

    func loadCachedVNReleases(vnID: String) -> [视觉小说发行版本]? {
        releaseCacheEntry(for: releaseCacheKey(vnID))?.value
    }

    private static let nextMoeBaseURL = URL(string: "https://api.nextmoe.dev/v2/catalog")!
    private static let nextMoeWorkIncludes = "titles,refs,intros,relations,credits,releases,ratings,tags,covers,screenshots,characters,companies,platforms,links"

    private func nextMoeVNDBReference(for vnID: String) -> String {
        "vndb:" + vnID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextMoeCharacterReference(for characterID: String) -> String {
        "vndb:" + characterID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nextMoeRequest(
        path: String,
        query: [URLQueryItem] = []
    ) async throws -> Data {
        var components = URLComponents(
            url: Self.nextMoeBaseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.setValue(
            "Bearer \(try await 鲲Galgame账户.有效NextMoe访问令牌())",
            forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await PaperVNConnect网络设置.发送请求(
            request,
            session: session
        )
        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            throw VNDB服务错误.NextMoe令牌无效
        case 403:
            throw VNDB服务错误.NextMoe权限不足
        case 429:
            throw VNDB服务错误.NextMoe请求过于频繁
        case 500, 502, 503, 504:
            throw VNDB服务错误.NextMoe服务暂时不可用
        default:
            let message = String(data: data, encoding: .utf8)
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw VNDB服务错误.NextMoe请求失败(
                statusCode: response.statusCode,
                message: message
            )
        }
    }

    private func nextMoeList(
        query: [URLQueryItem]
    ) async throws -> NextMoe列表<NextMoe作品> {
        try await nextMoeList(path: "works", query: query)
    }

    private func nextMoeList<Item: Decodable & Sendable>(
        path: String,
        query: [URLQueryItem]
    ) async throws -> NextMoe列表<Item> {
        let data = try await nextMoeRequest(path: path, query: query)
        return try JSONDecoder().decode(
            NextMoe列表<Item>.self,
            from: data
        )
    }

    private func fetchNextMoeVNDetail(
        vnID: String,
        forceRefresh: Bool
    ) async throws -> 视觉小说详细信息 {
        let key = "nextmoe_vn_detail_v1_\(vnID)"
        if !forceRefresh,
           let cached = visualNovelCacheEntry(for: key),
           isFresh(cached.savedAt, lifetime: detailCacheLifetime) {
            return cached.value
        }

        let list = try await nextMoeList(query: [
            URLQueryItem(name: "refs", value: nextMoeVNDBReference(for: vnID)),
            URLQueryItem(name: "include", value: "refs"),
            URLQueryItem(name: "nsfw", value: "true")
        ])
        guard let workID = list.items.first?.id else {
            throw URLError(.resourceUnavailable)
        }
        let data = try await nextMoeRequest(
            path: "works/\(workID)",
            query: [
                URLQueryItem(name: "include", value: Self.nextMoeWorkIncludes),
                URLQueryItem(name: "nsfw", value: "true")
            ]
        )
        let work = try JSONDecoder().decode(NextMoe作品.self, from: data)
        let detail = convertNextMoe(work, vndbID: vnID)
        saveVisualNovelCache(detail, key: key)
        return detail
    }

    private func convertNextMoe(
        _ work: NextMoe作品,
        vndbID: String
    ) -> 视觉小说详细信息 {
        let titles = work.titles?.map { title in
            用户多语言标题(
                lang: title.lang,
                title: title.title,
                latin: title.latin,
                official: title.titleKind == "official",
                main: title.titleKind == "official"
            )
        } ?? []
        let mainTitle = work.displayName
        let aliases = titles
            .filter { $0.title != mainTitle }
            .map(\.title)
        let platforms = work.platforms?.map(\.platform) ?? []
        let rating = work.ratings?.first(where: { $0.source == "vndb" })
        let tags = work.tags?.compactMap { tag -> 视觉小说标签? in
            guard let id = tag.id else { return nil }
            return 视觉小说标签(
                id: id,
                name: tag.displayName,
                rating: 1,
                spoiler: nextMoeSpoilerLevel(tag.spoiler),
                lie: false,
                category: tag.isSexual ? "ero" : tag.tagKind
            )
        }
        let developers = work.companies?.filter {
            $0.attributionRole == "developer" || $0.attributionRole == "circle"
        }.map {
            视觉小说开发商(id: $0.id, name: $0.displayName, original: nil)
        }
        let screenshots = work.screenshots?.enumerated().map { index, screenshot in
            视觉小说截图(
                id: screenshot.hash.isEmpty ? String(index) : screenshot.hash,
                url: screenshot.url,
                thumbnail: screenshot.url,
                sexual: nextMoeRisk(screenshot.sexual),
                violence: nextMoeRisk(screenshot.violence)
            )
        }
        let relations = work.relations?.compactMap { relation -> 视觉小说相关? in
            guard let relatedID = nextMoeVNDBID(from: relation.work.refs) else { return nil }
            return 视觉小说相关(
                id: relatedID,
                title: relation.work.displayName,
                titles: nextMoeTitles(relation.work.titles),
                relation: relation.relationType,
                relation_official: true,
                image: nextMoeImage(relation.work.cover)
            )
        }
        let staff = work.credits?.flatMap { group in
            group.credits.map {
                视觉小说制作人员(
                    eid: nil,
                    role: group.roleKey,
                    note: nil,
                    id: $0.id,
                    name: $0.displayName,
                    original: $0.latin
                )
            }
        }
        let va = work.characters?.flatMap { character in
            character.voices.map { voice in
                视觉小说声优关系(
                    note: nil,
                    staff: 人员基础信息(
                        id: voice.id,
                        name: voice.displayName,
                        original: voice.latin
                    ),
                    character: 视觉小说声优关系.角色信息(
                        id: character.id,
                        name: character.displayName,
                        original: character.latin,
                        aliases: nil,
                        image: character.image.map {
                            角色图片(
                                url: $0.url,
                                dims: [$0.width ?? 0, $0.height ?? 0],
                                sexual: nextMoeRisk($0.sexual),
                                violence: nextMoeRisk($0.violence)
                            )
                        }
                    )
                )
            }
        }
        let links = work.links?.map {
            视觉小说外链(url: $0.url, label: $0.source, name: $0.source)
        }
        let description = nextMoeDescription(work.intros)
        return 视觉小说详细信息(
            id: vndbID,
            title: mainTitle,
            titles: titles,
            aliases: aliases,
            olang: work.olang,
            devstatus: work.releaseStatus == "released" ? 0 : 1,
            released: work.releaseDate,
            languages: [work.olang],
            platforms: platforms,
            image: nextMoeImage(work.cover),
            length: nil,
            length_minutes: nil,
            length_votes: nil,
            description: description,
            rating: rating?.score,
            votecount: rating?.voteCount,
            tags: tags,
            developers: developers,
            screenshots: screenshots,
            relations: relations,
            staff: staff,
            va: va,
            extlinks: links
        )
    }

    private func fetchNextMoeVNReleases(
        vnID: String,
        forceRefresh: Bool
    ) async throws -> [视觉小说发行版本] {
        let key = "nextmoe_vn_releases_v1_\(vnID)"
        if !forceRefresh,
           let cached = releaseCacheEntry(for: key),
           isFresh(cached.savedAt, lifetime: releaseCacheLifetime) {
            return cached.value
        }
        let works = try await nextMoeList(query: [
            URLQueryItem(name: "refs", value: nextMoeVNDBReference(for: vnID)),
            URLQueryItem(name: "include", value: "refs"),
            URLQueryItem(name: "nsfw", value: "true")
        ])
        guard let work = works.items.first else {
            throw URLError(.resourceUnavailable)
        }
        var query = [URLQueryItem(name: "limit", value: "100")]
        query.append(URLQueryItem(name: "nsfw", value: "true"))
        let data = try await nextMoeRequest(
            path: "works/\(work.id)/releases",
            query: query
        )
        let list = try JSONDecoder().decode(
            NextMoe列表<NextMoe发行版本>.self,
            from: data
        )
        let releases = list.items.map { release in
            视觉小说发行版本(
                id: release.id,
                title: release.title ?? release.id,
                alttitle: nil,
                released: release.date,
                languages: release.lang.isEmpty ? nil : [
                    视觉小说发行语言(
                        lang: release.lang,
                        title: nil,
                        latin: nil,
                        mtl: nil,
                        main: true
                    )
                ],
                platforms: release.platforms.isEmpty
                    ? [release.platform]
                    : release.platforms,
                official: release.releaseKind == "default",
                visualNovels: [
                    视觉小说发行关联(id: vnID, releaseType: release.releaseKind)
                ]
            )
        }
        saveReleaseCache(releases, key: key)
        return releases
    }

    private func fetchNextMoeCharacterDetail(
        characterID: String,
        forceRefresh: Bool
    ) async throws -> 角色详细信息 {
        let key = "nextmoe_character_detail_v1_\(characterID)"
        if !forceRefresh,
           let cached = characterCacheEntry(for: key),
           isFresh(cached.savedAt, lifetime: 缓存策略.当前.characterDetailLifetime) {
            return cached.value
        }
        let normalizedID = characterID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let catalogID: String
        if normalizedID.hasPrefix("c") {
            let lookup: NextMoe列表<NextMoe角色> = try await nextMoeList(
                path: "characters",
                query: [
                    URLQueryItem(
                        name: "refs",
                        value: nextMoeCharacterReference(for: normalizedID)
                    ),
                    URLQueryItem(name: "include", value: "refs"),
                    URLQueryItem(name: "nsfw", value: "true")
                ]
            )
            guard let resolvedID = lookup.items.first?.id else {
                throw URLError(.resourceUnavailable)
            }
            catalogID = resolvedID
        } else {
            guard !normalizedID.isEmpty else {
                throw URLError(.resourceUnavailable)
            }
            catalogID = normalizedID
        }

        let data = try await nextMoeRequest(
            path: "characters/\(catalogID)",
            query: [
                URLQueryItem(name: "view", value: "full"),
                URLQueryItem(name: "include", value: "image,aliases,intros,traits,refs"),
                URLQueryItem(name: "nsfw", value: "true")
            ]
        )
        let character = try JSONDecoder().decode(NextMoe角色.self, from: data)
        let appearances: [NextMoe出演]
        if let appearancesData = try? await nextMoeRequest(
            path: "characters/\(catalogID)/appearances",
            query: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "nsfw", value: "true")
            ]
        ),
           let decoded = try? JSONDecoder().decode(
               NextMoe列表<NextMoe出演>.self,
               from: appearancesData
           ) {
            appearances = decoded.items
        } else {
            appearances = []
        }

        let value = convertNextMoeCharacter(
            character,
            vndbID: nextMoeCharacterVNDBID(from: character.refs) ?? characterID,
            appearances: appearances
        )
        saveCharacterCache(value, key: key)
        return value
    }

    private func convertNextMoeCharacter(
        _ character: NextMoe角色,
        vndbID: String,
        appearances: [NextMoe出演]
    ) -> 角色详细信息 {
        let description = nextMoeDescription(character.intros)
        let traits = character.traits?.map {
            角色特征(
                id: $0.id,
                name: $0.displayName,
                group_name: $0.group ?? "",
                spoiler: nextMoeSpoilerLevel($0.spoiler),
                lie: $0.isLie,
                sexual: $0.isSexual
            )
        }
        let birthday = character.birthday.flatMap { value -> [Int]? in
            let parts = value.split(separator: "-").compactMap { Int($0) }
            return parts.count == 2 ? [parts[0], parts[1]] : nil
        }
        let vns = appearances.compactMap { appearance -> 角色视觉小说关系? in
            guard let vnID = nextMoeVNDBID(from: appearance.work.refs) else {
                return nil
            }
            return 角色视觉小说关系(
                id: vnID,
                title: appearance.work.displayName,
                titles: nextMoeTitles(appearance.work.titles),
                image: nextMoeImage(appearance.work.cover),
                spoiler: nextMoeSpoilerLevel(appearance.spoiler),
                role: appearance.rosterRole
            )
        }
        return 角色详细信息(
            id: vndbID,
            name: character.displayName,
            original: character.latin,
            aliases: character.aliases?.map(\.value),
            description: description,
            image: character.image.map {
                角色图片(
                    url: $0.url,
                    dims: [$0.width ?? 0, $0.height ?? 0],
                    sexual: nextMoeRisk($0.sexual),
                    violence: nextMoeRisk($0.violence)
                )
            },
            blood_type: character.bloodType,
            height: character.heightCM,
            weight: character.weightKG,
            bust: character.measurements?.bustCM,
            waist: character.measurements?.waistCM,
            hips: character.measurements?.hipCM,
            cup: character.measurements?.cup,
            age: nil,
            birthday: birthday,
            sex: character.gender.map { [$0] },
            gender: character.gender.map { [$0] },
            vns: vns,
            traits: traits
        )
    }

    private func nextMoeTitles(_ titles: [NextMoe标题]?) -> [用户多语言标题]? {
        titles?.map {
            用户多语言标题(
                lang: $0.lang,
                title: $0.title,
                latin: $0.latin,
                official: $0.titleKind == "official",
                main: $0.titleKind == "official"
            )
        }
    }

    private func nextMoeImage(_ image: NextMoe图片?) -> 视觉小说图片? {
        guard let image else { return nil }
        return 视觉小说图片(
            id: nil,
            url: image.url,
            thumbnail: image.url,
            sexual: nextMoeRisk(image.sexual),
            violence: nextMoeRisk(image.violence),
            dims: [image.width ?? 0, image.height ?? 0]
        )
    }

    private func nextMoeVNDBID(from refs: [NextMoeRef]?) -> String? {
        guard let reference = refs?.first(where: { $0.source == "vndb" }) else {
            return nil
        }
        let externalID = reference.externalID
        return externalID.hasPrefix("v") ? externalID : "v\(externalID)"
    }

    private func nextMoeCharacterVNDBID(from refs: [NextMoeRef]?) -> String? {
        guard let reference = refs?.first(where: { $0.source == "vndb" }) else {
            return nil
        }
        let externalID = reference.externalID
        return externalID.hasPrefix("c") ? externalID : "c\(externalID)"
    }

    private func nextMoeDescription(_ intros: [NextMoeIntro]?) -> String? {
        let preferred = ["zh-Hans", "zh", "ja", "en"]
        return preferred.compactMap { lang in
            intros?.first(where: { $0.lang == lang })?.value
        }.first ?? intros?.first?.value
    }

    private func nextMoeSpoilerLevel(_ value: String) -> Int {
        switch value {
        case "major": return 2
        case "minor": return 1
        default: return 0
        }
    }

    private func nextMoeRisk(_ value: String?) -> Double? {
        switch value {
        case "explicit", "brutal": return 2
        case "suggestive", "violent": return 1
        case "safe", "tame": return 0
        default: return nil
        }
    }

    func fetchCharacterDetail(
        characterID: String,
        forceRefresh: Bool = false
    ) async throws -> 角色详细信息 {
        if NextMoe内容设置.已启用 {
            do {
                return try await fetchNextMoeCharacterDetail(
                    characterID: characterID,
                    forceRefresh: forceRefresh
                )
            } catch {
                try Task.checkCancellation()
            }
        }
        let cacheKey = characterCacheKey(characterID)
        if !forceRefresh,
           let cached = characterCacheEntry(for: cacheKey),
           isFresh(
               cached.savedAt,
               lifetime: 缓存策略.当前.characterDetailLifetime
           ) {
            return cached.value
        }

        let url = URL(string: "\(baseURL)/character")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if forceRefresh {
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let fields = """
        name,original,aliases,description,image{url,dims,sexual,violence},\
        blood_type,height,weight,bust,waist,hips,cup,age,birthday,sex,gender,\
        vns{spoiler,role,id,title,titles{lang,title,latin,official,main},image{id,url,thumbnail,sexual,violence,dims}},\
        traits{id,name,group_name,spoiler,lie,sexual}
        """
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "filters": ["id", "=", characterID],
                "fields": fields,
                "results": 1
            ]
        )

        struct 角色响应: Codable {
            let results: [角色详细信息]
        }

        let data = try await perform(request, accepting: [200])
        guard let character = try JSONDecoder()
            .decode(角色响应.self, from: data)
            .results
            .first else {
            throw URLError(.resourceUnavailable)
        }
        saveCharacterCache(character, key: cacheKey)
        return character
    }

    func loadCachedCharacterDetail(
        characterID: String
    ) -> 角色详细信息? {
        characterCacheEntry(
            for: characterCacheKey(characterID)
        )?.value
    }

    private struct Token权限信息: Decodable {
        let permissions: [String]
    }

    private func ensureListWritePermission(token: String) async throws {
        guard !token.isEmpty else {
            throw VNDB服务错误.token无效
        }
        guard !validatedListWriteTokens.contains(token) else { return }

        let url = URL(string: "\(baseURL)/authinfo")!
        var request = URLRequest(url: url)
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let data = try await perform(request, accepting: [200])
        let authInfo = try JSONDecoder().decode(Token权限信息.self, from: data)
        guard authInfo.permissions.contains("listwrite") else {
            throw VNDB服务错误.缺少资料库写入权限
        }
        validatedListWriteTokens.insert(token)
    }

    func updateUserListEntry(
        token: String,
        vnID: String,
        status: 用户列表筛选?,
        vote: Int?,
        updateVote: Bool,
        started: String?,
        updateStarted: Bool,
        finished: String?,
        updateFinished: Bool,
        existingLabels: [用户列表项目.用户列表标签]
    ) async throws {
        var values: [String: Any] = [:]

        if let statusID = status?.labelID {
            let retainedLabels = existingLabels
                .map(\.id)
                .filter { !(1...5).contains($0) && $0 != 0 && $0 != 7 }
            values["labels"] = Array(Set(retainedLabels + [statusID])).sorted()
        }
        if updateVote {
            values["vote"] = vote ?? NSNull()
        }
        if updateStarted {
            values["started"] = started ?? NSNull()
        }
        if updateFinished {
            values["finished"] = finished ?? NSNull()
        }

        guard !values.isEmpty else { return }
        try await patchUserList(token: token, vnID: vnID, values: values)
    }

    func updateUserStatus(
        token: String,
        vnID: String,
        status: 用户列表筛选,
        existingLabels: [用户列表项目.用户列表标签]
    ) async throws {
        guard let statusID = status.labelID else { return }

        let retainedLabels = existingLabels
            .map(\.id)
            .filter { !(1...5).contains($0) && $0 != 0 && $0 != 7 }
        let labels = Array(Set(retainedLabels + [statusID])).sorted()

        try await patchUserList(
            token: token,
            vnID: vnID,
            values: ["labels": labels]
        )
    }

    func updateUserVote(
        token: String,
        vnID: String,
        vote: Int?
    ) async throws {
        try await patchUserList(
            token: token,
            vnID: vnID,
            values: ["vote": vote ?? NSNull()]
        )
    }

    func deleteUserListEntry(
        token: String,
        vnID: String
    ) async throws {
        try await ensureListWritePermission(token: token)

        let url = URL(string: "\(baseURL)/ulist/\(vnID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request, accepting: [204])
        invalidateUserCaches()
        NotificationCenter.default.post(
            name: .paperVNLibraryDidChange,
            object: vnID
        )
    }

    func updateReleaseSelection(
        token: String,
        existingReleaseIDs: [String],
        selectedReleaseID: String?
    ) async throws {
        try await ensureListWritePermission(token: token)

        for releaseID in existingReleaseIDs where releaseID != selectedReleaseID {
            try await deleteRelease(token: token, releaseID: releaseID)
        }

        if let selectedReleaseID {
            let url = URL(string: "\(baseURL)/rlist/\(selectedReleaseID)")!
            var request = URLRequest(url: url)
            request.httpMethod = "PATCH"
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
            request.setValue(
                "Token \(token)",
                forHTTPHeaderField: "Authorization"
            )
            request.httpBody = try JSONSerialization.data(
                withJSONObject: ["status": 2]
            )
            _ = try await perform(request, accepting: [204])
        }

        invalidateUserCaches()
    }

    private func visualNovelCacheEntry(
        for key: String
    ) -> 缓存条目<视觉小说详细信息>? {
        if let cached = visualNovelMemoryCache[key] {
            guard isFresh(cached.savedAt, lifetime: detailCacheLifetime) else {
                visualNovelMemoryCache[key] = nil
                try? FileManager.default.removeItem(at: cacheFileURL(for: key))
                return nil
            }
            return cached
        }
        guard let cached: 缓存条目<视觉小说详细信息> = loadDiskCache(
            key: key
        ) else {
            return nil
        }
        guard isFresh(cached.savedAt, lifetime: detailCacheLifetime) else {
            try? FileManager.default.removeItem(at: cacheFileURL(for: key))
            return nil
        }
        visualNovelMemoryCache[key] = cached
        return cached
    }

    private func characterCacheEntry(
        for key: String
    ) -> 缓存条目<角色详细信息>? {
        if let cached = characterMemoryCache[key] {
            guard isFresh(
                cached.savedAt,
                lifetime: 缓存策略.当前.characterDetailLifetime
            ) else {
                characterMemoryCache[key] = nil
                try? FileManager.default.removeItem(at: cacheFileURL(for: key))
                return nil
            }
            return cached
        }
        guard let cached: 缓存条目<角色详细信息> = loadDiskCache(
            key: key
        ) else {
            return nil
        }
        guard isFresh(
            cached.savedAt,
            lifetime: 缓存策略.当前.characterDetailLifetime
        ) else {
            try? FileManager.default.removeItem(at: cacheFileURL(for: key))
            return nil
        }
        characterMemoryCache[key] = cached
        return cached
    }

    private func releaseCacheEntry(
        for key: String
    ) -> 缓存条目<[视觉小说发行版本]>? {
        if let cached = releaseMemoryCache[key] {
            guard isFresh(cached.savedAt, lifetime: releaseCacheLifetime) else {
                releaseMemoryCache[key] = nil
                try? FileManager.default.removeItem(at: cacheFileURL(for: key))
                return nil
            }
            return cached
        }
        guard let cached: 缓存条目<[视觉小说发行版本]> = loadDiskCache(
            key: key
        ) else {
            return nil
        }
        guard isFresh(cached.savedAt, lifetime: releaseCacheLifetime) else {
            try? FileManager.default.removeItem(at: cacheFileURL(for: key))
            return nil
        }
        releaseMemoryCache[key] = cached
        return cached
    }

    private func userListCacheEntry(
        for key: String
    ) -> 缓存条目<用户列表响应>? {
        if let cached = userListMemoryCache[key] {
            return cached
        }
        guard let cached: 缓存条目<用户列表响应> = loadDiskCache(
            key: key
        ) else {
            return nil
        }
        userListMemoryCache[key] = cached
        return cached
    }

    private func userItemCacheEntry(
        for key: String
    ) -> 缓存条目<用户列表项目?>? {
        if let cached = userItemMemoryCache[key] {
            return cached
        }
        guard let cached: 缓存条目<用户列表项目?> = loadDiskCache(
            key: key
        ) else {
            return nil
        }
        userItemMemoryCache[key] = cached
        return cached
    }

    private func 搜索筛选目录缓存() -> 缓存条目<VNDB搜索筛选目录>? {
        if let schemaMemoryCache {
            let normalized = 缓存条目(
                savedAt: schemaMemoryCache.savedAt,
                value: Self.规范化搜索筛选目录(schemaMemoryCache.value)
            )
            self.schemaMemoryCache = normalized
            return normalized
        }
        guard let cached: 缓存条目<VNDB搜索筛选目录> = loadDiskCache(
            key: "vndb_schema_filter_catalog"
        ) else {
            return nil
        }
        let normalized = 缓存条目(
            savedAt: cached.savedAt,
            value: Self.规范化搜索筛选目录(cached.value)
        )
        schemaMemoryCache = normalized
        return normalized
    }

    private func saveVisualNovelCache(
        _ value: 视觉小说详细信息,
        key: String
    ) {
        guard cacheWritesEnabled else { return }
        let savedAt = Date()
        let entry = 缓存条目(savedAt: savedAt, value: value)
        visualNovelMemoryCache[key] = entry

        let url = cacheFileURL(for: key)
        let diskEntry = VNDB视觉小说详情缓存条目(
            savedAt: savedAt,
            value: value
        )
        let taskID = UUID()
        let task = Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(diskEntry) else {
                return
            }
            guard !Task.isCancelled else { return }
            try? data.write(to: url, options: .atomic)
        }
        diskWriteTasks[taskID] = task
        Task { [weak self] in
            await task.value
            self?.enforceCacheLimitIfNeeded()
            self?.diskWriteTasks[taskID] = nil
        }
    }

    private func saveCharacterCache(
        _ value: 角色详细信息,
        key: String
    ) {
        let entry = 缓存条目(savedAt: Date(), value: value)
        characterMemoryCache[key] = entry
        saveDiskCache(entry, key: key)
    }

    private func saveReleaseCache(
        _ value: [视觉小说发行版本],
        key: String
    ) {
        let entry = 缓存条目(savedAt: Date(), value: value)
        releaseMemoryCache[key] = entry
        saveDiskCache(entry, key: key)
    }

    private func saveUserListCache(
        _ value: 用户列表响应,
        key: String
    ) {
        let entry = 缓存条目(savedAt: Date(), value: value)
        userListMemoryCache[key] = entry
        saveDiskCache(entry, key: key)
    }

    private func saveUserItemCache(
        _ value: 用户列表项目?,
        key: String
    ) {
        let entry = 缓存条目(savedAt: Date(), value: value)
        userItemMemoryCache[key] = entry
        saveDiskCache(entry, key: key)
    }

    private func loadDiskCache<Value: Codable>(
        key: String
    ) -> 缓存条目<Value>? {
        let url = cacheFileURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(
            缓存条目<Value>.self,
            from: data
        )
    }

    private func saveDiskCache<Value: Codable>(
        _ entry: 缓存条目<Value>,
        key: String
    ) {
        guard cacheWritesEnabled else { return }
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: cacheFileURL(for: key), options: .atomic)
        enforceCacheLimitIfNeeded()
    }

    private func enforceCacheLimitIfNeeded() {
        guard let maximum = 缓存策略.当前.maximumCacheBytes,
              maximum > 0 else {
            return
        }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var files: [(url: URL, size: Int64, modifiedAt: Date)] = []
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }
            let size = Int64(
                values.totalFileAllocatedSize ?? values.fileSize ?? 0
            )
            files.append((
                url: fileURL,
                size: size,
                modifiedAt: values.contentModificationDate ?? .distantPast
            ))
            total += size
        }

        guard total > maximum else { return }
        for file in files.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
            guard total > maximum else { break }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }

    private func cacheFileURL(for key: String) -> URL {
        let safeKey = key.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        return cacheDirectory
            .appendingPathComponent(safeKey)
            .appendingPathExtension("json")
    }

    private func isFresh(
        _ date: Date,
        lifetime: TimeInterval
    ) -> Bool {
        Date().timeIntervalSince(date) < lifetime
    }

    private func visualNovelCacheKey(_ vnID: String) -> String {
        "vn_detail_v2_\(vnID)"
    }

    private func characterCacheKey(_ characterID: String) -> String {
        "character_detail_\(characterID)"
    }

    private func releaseCacheKey(_ vnID: String) -> String {
        "vn_releases_\(vnID)"
    }

    private func userListCacheKey(
        userID: String,
        filter: 用户列表筛选,
        sort: 用户列表排序,
        isDescending: Bool,
        page: Int
    ) -> String {
        let direction = isDescending ? "descending" : "ascending"
        return "user_list_\(userID)_\(filter.rawValue)_\(sort.rawValue)_\(direction)_\(page)"
    }

    private func userItemCacheKey(
        userID: String,
        vnID: String
    ) -> String {
        "user_item_\(userID)_\(vnID)"
    }

    private func invalidateUserCaches() {
        userListMemoryCache.removeAll()
        userItemMemoryCache.removeAll()

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent
            if name.hasPrefix("user_list_")
                || name.hasPrefix("user_item_") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func patchUserList(
        token: String,
        vnID: String,
        values: [String: Any]
    ) async throws {
        try await ensureListWritePermission(token: token)

        let url = URL(string: "\(baseURL)/ulist/\(vnID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: values)
        _ = try await perform(request, accepting: [204])
        invalidateUserCaches()
        NotificationCenter.default.post(
            name: .paperVNLibraryDidChange,
            object: vnID
        )
    }

    private func deleteRelease(
        token: String,
        releaseID: String
    ) async throws {
        let url = URL(string: "\(baseURL)/rlist/\(releaseID)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        _ = try await perform(request, accepting: [204])
    }

    private func perform(
        _ request: URLRequest,
        accepting statusCodes: Set<Int>
    ) async throws -> Data {
        cacheWritesEnabled = true
        let (data, httpResponse) = try await PaperVNConnect网络设置.发送请求(
            request,
            session: session
        )

        if httpResponse.statusCode == 401 {
            throw VNDB服务错误.token无效
        }

        if httpResponse.statusCode == 403 {
            throw VNDB服务错误.缺少资料库写入权限
        }

        if httpResponse.statusCode == 429 {
            throw VNDB服务错误.请求过于频繁
        }

        if [500, 502, 503, 504].contains(httpResponse.statusCode) {
            throw VNDB服务错误.服务暂时不可用
        }

        guard statusCodes.contains(httpResponse.statusCode) else {
            let responseText = String(data: data, encoding: .utf8)
                ?? String(localized: "未知服务器错误")
            throw VNDB服务错误.请求失败(
                statusCode: httpResponse.statusCode,
                message: responseText
            )
        }

        return data
    }
}

enum VNDB探索服务错误: LocalizedError, Equatable, Sendable {
    case token无效
    case 请求过于频繁
    case 推荐请求预算不足
    case 服务暂时不可用
    case 无效响应
    case 请求失败(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .token无效:
            return String(localized: "VNDB Token无效或已过期，请重新登录。")
        case .请求过于频繁:
            return String(localized: "请求过于频繁，请稍后再试。")
        case .推荐请求预算不足:
            return String(localized: "推荐资料仍在准备中，请稍后再试。")
        case .服务暂时不可用:
            return String(localized: "VNDB服务暂时不可用，请稍后再试。")
        case .无效响应:
            return String(localized: "VNDB返回了无法识别的数据。")
        case let .请求失败(_, message):
            return String(localized: "VNDB请求失败：\(message)")
        }
    }
}

@MainActor
protocol VNDB探索服务协议: AnyObject {
    func 视觉小说(
        来源: 探索视觉小说来源,
        页码: Int,
        每页: Int,
        强制刷新: Bool
    ) async throws -> 探索页面<探索视觉小说>

    func 发行版本(
        来源: 探索发行来源,
        页码: Int,
        每页: Int,
        强制刷新: Bool
    ) async throws -> 探索页面<探索发行版本>

    func 发行详情(id: String, 强制刷新: Bool) async throws -> 探索发行版本?

    func 角色(
        来源: 探索角色来源,
        页码: Int,
        每页: Int,
        强制刷新: Bool
    ) async throws -> 探索页面<探索角色>

    func 角色详情(id: String, 强制刷新: Bool) async throws -> 探索角色?

    func 制作人员(
        来源: 探索制作人员来源,
        页码: Int,
        每页: Int,
        强制刷新: Bool
    ) async throws -> 探索页面<探索制作人员>

    func 会社(
        来源: 探索会社来源,
        页码: Int,
        每页: Int,
        强制刷新: Bool
    ) async throws -> 探索页面<探索会社>

    func 标签(
        来源: 探索标签来源,
        页码: Int,
        每页: Int,
        强制刷新: Bool
    ) async throws -> 探索页面<探索标签>

    func 所有标签(强制刷新: Bool) async throws -> [探索标签]
    func 已缓存标签目录() -> [探索标签]?

    func 特征(
        来源: 探索特征来源,
        页码: Int,
        每页: Int,
        强制刷新: Bool
    ) async throws -> 探索页面<探索特征>

    func 所有特征(强制刷新: Bool) async throws -> [探索特征]
    func 已缓存特征目录() -> [探索特征]?
    func 随机语录(强制刷新: Bool) async throws -> 探索语录?

    func 生成推荐(
        token: String,
        userID: String,
        排除ID: Set<String>,
        数量: Int,
        强制刷新: Bool
    ) async throws -> [探索推荐]

    func 已缓存推荐(userID: String, 排除ID: Set<String>) async -> [探索推荐]?
    func 清除缓存() async
}

@MainActor
final class VNDB探索服务: VNDB探索服务协议 {
    static let shared = VNDB探索服务()

    private struct 缓存条目<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    private struct 完整目录缓存<Item: Codable>: Codable {
        let items: [Item]
        let isComplete: Bool
    }

    private struct 完整目录页面<Item: Codable>: Codable {
        let results: [Item]
        let more: Bool
        let count: Int?
    }

    private struct 推荐资料库快照: Codable {
        let items: [探索用户列表项目]
        let newestLastModified: Int?
        let lastFullSyncAt: Date
    }

    private struct 推荐资料库角色快照: Codable {
        var coveredVisualNovelIDs: Set<String>
        var characters: [探索角色]
    }

    private final class 推荐请求预算 {
        private let limit: Int
        private let progressTotal: Int
        private let progress: ((Int, Int) -> Void)?
        private(set) var remaining: Int

        init(
            limit: Int,
            progressTotal: Int? = nil,
            progress: ((Int, Int) -> Void)? = nil
        ) {
            self.limit = max(0, limit)
            self.progressTotal = max(1, progressTotal ?? limit)
            self.progress = progress
            remaining = max(0, limit)
            progress?(0, self.progressTotal)
        }

        func consume(reserving minimumRemaining: Int = 0) -> Bool {
            guard remaining > max(0, minimumRemaining) else { return false }
            remaining -= 1
            let completed = limit - remaining
            progress?(
                completed,
                max(progressTotal, completed + 1)
            )
            return true
        }
    }

    private let session: URLSession
    private let baseURL: String
    private let cacheDirectory: URL
    private let recommendationDataDirectory: URL
    private let now: @Sendable () -> Date
    private let randomInteger: @Sendable (ClosedRange<Int>) -> Int
    private var memoryCache: [String: Data] = [:]
    private var recommendationModelIdentifier: String
    private var lastRequestStartedAt: ContinuousClock.Instant?
    private var rateLimitCooldownUntil: ContinuousClock.Instant?
    private var cacheWritesEnabled = true

    private var feedLifetime: TimeInterval {
        缓存策略.当前.exploreFeedLifetime
    }
    private let recommendationLifetime: TimeInterval = 24 * 60 * 60
    /// 推荐结果最多保留一周；展示顺序每天在界面层重新排列。
    private let recommendationRefreshLifetime: TimeInterval = 7 * 24 * 60 * 60
    private let recommendationMetadataLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let 推荐分析请求上限 = 100
    private let recommendationRequestLimit = Int.max
    private let dailyLifetime: TimeInterval = 24 * 60 * 60
    private let taxonomyLifetime: TimeInterval = 7 * 24 * 60 * 60

    init(
        session: URLSession = .shared,
        baseURL: String = "https://api.vndb.org/kana",
        cacheDirectory: URL? = nil,
        recommendationDataDirectory: URL? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        randomInteger: @escaping @Sendable (ClosedRange<Int>) -> Int = {
            Int.random(in: $0)
        }
    ) {
        self.session = session
        self.baseURL = baseURL.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        self.cacheDirectory = cacheDirectory
            ?? FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent("PaperVNExplore", isDirectory: true)
        self.recommendationDataDirectory = recommendationDataDirectory
            ?? FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
                .appendingPathComponent(
                    "PaperVNRecommendationAnalysis",
                    isDirectory: true
                )
        self.now = now
        self.randomInteger = randomInteger
        self.recommendationModelIdentifier =
            VNDB离线推荐模型加载器.模型标识() ?? "none"
        try? FileManager.default.createDirectory(
            at: self.cacheDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: self.recommendationDataDirectory,
            withIntermediateDirectories: true
        )
        if recommendationDataDirectory == nil {
            var directory = self.recommendationDataDirectory
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try? directory.setResourceValues(resourceValues)
        }
    }

    func 推荐模型标识() -> String {
        recommendationModelIdentifier
    }

    func 刷新推荐模型标识() {
        recommendationModelIdentifier =
            VNDB离线推荐模型加载器.模型标识() ?? "none"
    }

    func 视觉小说(
        来源: 探索视觉小说来源,
        页码: Int = 1,
        每页: Int = 12,
        强制刷新: Bool = false
    ) async throws -> 探索页面<探索视觉小说> {
        let page = max(1, 页码)
        let pageSize = min(100, max(1, 每页))
        let key = "vn_\(来源.id)_\(page)_\(pageSize)"
        let cached: 缓存条目<探索页面<探索视觉小说>>? = page == 1
            ? loadCache(key: key)
            : nil

        if !强制刷新, let cached,
           isFresh(cached.savedAt, lifetime: feedLifetime) {
            return cached.value.markingCache(.fresh)
        }

        do {
            let query = visualNovelQuery(for: 来源)
            let body: [String: Any] = [
                "filters": query.filters,
                "fields": Self.visualNovelFields,
                "sort": query.sort,
                "reverse": query.reverse,
                "results": pageSize,
                "page": page,
                "count": false
            ]
            let response: 探索页面<探索视觉小说> = try await post(
                endpoint: "vn",
                body: body
            )
            if page == 1 { saveCache(response, key: key) }
            if 缓存策略.当前 == .more {
                VNDB服务.shared.prefetchVisualNovelGraph(
                    vnIDs: response.results.map(\.id),
                    maximumDepth: 1
                )
            }
            return response
        } catch {
            if let cached { return cached.value.markingCache(.stale) }
            throw error
        }
    }

    func 发行版本(
        来源: 探索发行来源,
        页码: Int = 1,
        每页: Int = 24,
        强制刷新: Bool = false
    ) async throws -> 探索页面<探索发行版本> {
        let page = max(1, 页码)
        let pageSize = min(100, max(1, 每页))
        let key = "release_\(来源.id)_\(page)_\(pageSize)"
        let cached: 缓存条目<探索页面<探索发行版本>>? = page == 1
            ? loadCache(key: key)
            : nil
        if !强制刷新, let cached,
           isFresh(cached.savedAt, lifetime: feedLifetime) {
            return cached.value.markingCache(.fresh)
        }
        do {
            let query = releaseQuery(for: 来源)
            let response: 探索页面<探索发行版本> = try await post(
                endpoint: "release",
                body: queryBody(
                    filters: query.filters,
                    fields: Self.releaseFields,
                    sort: query.sort,
                    reverse: query.reverse,
                    page: page,
                    pageSize: pageSize
                )
            )
            if page == 1 { saveCache(response, key: key) }
            return response
        } catch {
            if let cached { return cached.value.markingCache(.stale) }
            throw error
        }
    }

    func 发行详情(id: String, 强制刷新: Bool = false) async throws -> 探索发行版本? {
        try await single(
            endpoint: "release",
            id: id,
            fields: Self.releaseFields,
            key: "release_detail_\(id)",
            lifetime: dailyLifetime,
            force: 强制刷新
        )
    }

    func 角色(
        来源: 探索角色来源,
        页码: Int = 1,
        每页: Int = 24,
        强制刷新: Bool = false
    ) async throws -> 探索页面<探索角色> {
        let query = characterQuery(for: 来源)
        return try await paged(
            endpoint: "character",
            key: "character_\(来源.id)",
            filters: query.filters,
            fields: Self.characterFields,
            sort: "id",
            reverse: query.reverse,
            page: 页码,
            pageSize: 每页,
            lifetime: feedLifetime,
            force: 强制刷新
        )
    }

    func 角色详情(id: String, 强制刷新: Bool = false) async throws -> 探索角色? {
        try await single(
            endpoint: "character",
            id: id,
            fields: Self.characterFields,
            key: "character_detail_\(id)",
            lifetime: dailyLifetime,
            force: 强制刷新
        )
    }

    func 制作人员(
        来源: 探索制作人员来源,
        页码: Int = 1,
        每页: Int = 24,
        强制刷新: Bool = false
    ) async throws -> 探索页面<探索制作人员> {
        let sourceFilters = staffFilters(for: 来源)
        return try await paged(
            endpoint: "staff",
            key: "staff_\(来源.id)",
            filters: combine(["ismain", "=", 1], with: sourceFilters),
            fields: Self.staffFields,
            sort: "id",
            reverse: true,
            page: 页码,
            pageSize: 每页,
            lifetime: feedLifetime,
            force: 强制刷新
        )
    }

    func 会社(
        来源: 探索会社来源,
        页码: Int = 1,
        每页: Int = 24,
        强制刷新: Bool = false
    ) async throws -> 探索页面<探索会社> {
        return try await paged(
            endpoint: "producer",
            key: "producer_\(来源.id)",
            filters: producerFilters(for: 来源),
            fields: Self.producerFields,
            sort: "id",
            reverse: true,
            page: 页码,
            pageSize: 每页,
            lifetime: feedLifetime,
            force: 强制刷新
        )
    }

    func 标签(
        来源: 探索标签来源,
        页码: Int = 1,
        每页: Int = 40,
        强制刷新: Bool = false
    ) async throws -> 探索页面<探索标签> {
        if !强制刷新,
           let cachedPage = 完整标签缓存页面(
               来源: 来源,
               页码: 页码,
               每页: 每页
           ) {
            return cachedPage
        }

        let filters: Any = switch 来源 {
        case .popular: []
        case let .category(category): ["category", "=", category.rawValue]
        }
        return try await paged(
            endpoint: "tag",
            key: "tag_\(来源.id)",
            filters: filters,
            fields: Self.tagFields,
            sort: "vn_count",
            reverse: true,
            page: 页码,
            pageSize: 每页,
            lifetime: taxonomyLifetime,
            force: 强制刷新
        )
    }

    func 所有标签(强制刷新: Bool = false) async throws -> [探索标签] {
        let key = "tag_catalog_all"
        let cached = 完整标签缓存()
        if !强制刷新, let cached {
            return cached.value.items
        }

        do {
            let items: [探索标签] = try await 获取完整目录(
                endpoint: "tag",
                fields: Self.tagFields,
                pageCacheKeyPrefix: "recommendation_tag_catalog_v1",
                强制刷新: 强制刷新
            )
            saveCache(
                完整目录缓存(items: items, isComplete: true),
                key: key
            )
            return items
        } catch {
            if let cached { return cached.value.items }
            throw error
        }
    }

    func 已缓存标签目录() -> [探索标签]? {
        完整标签缓存()?.value.items
    }

    func 特征(
        来源: 探索特征来源 = .popular,
        页码: Int = 1,
        每页: Int = 40,
        强制刷新: Bool = false
    ) async throws -> 探索页面<探索特征> {
        try await paged(
            endpoint: "trait",
            key: "trait_\(来源.id)",
            filters: [],
            fields: Self.traitFields,
            sort: "char_count",
            reverse: true,
            page: 页码,
            pageSize: 每页,
            lifetime: taxonomyLifetime,
            force: 强制刷新
        )
    }

    func 所有特征(强制刷新: Bool = false) async throws -> [探索特征] {
        let key = "trait_catalog_all"
        let cached = 完整特征缓存()
        if !强制刷新, let cached {
            return cached.value.items
        }

        do {
            let items: [探索特征] = try await 获取完整目录(
                endpoint: "trait",
                fields: Self.traitCatalogFields,
                pageCacheKeyPrefix: "recommendation_trait_catalog_v1",
                强制刷新: 强制刷新
            )
            saveCache(
                完整目录缓存(items: items, isComplete: true),
                key: key
            )
            return items
        } catch {
            if let cached { return cached.value.items }
            throw error
        }
    }

    func 已缓存特征目录() -> [探索特征]? {
        完整特征缓存()?.value.items
    }

    private func 完整标签缓存()
        -> 缓存条目<完整目录缓存<探索标签>>? {
        let cached: 缓存条目<完整目录缓存<探索标签>>? = loadCache(
            key: "tag_catalog_all"
        )
        guard let cached, cached.value.isComplete, !cached.value.items.isEmpty else {
            return nil
        }
        return cached
    }

    private func 完整特征缓存()
        -> 缓存条目<完整目录缓存<探索特征>>? {
        let cached: 缓存条目<完整目录缓存<探索特征>>? = loadCache(
            key: "trait_catalog_all"
        )
        guard let cached, cached.value.isComplete, !cached.value.items.isEmpty else {
            return nil
        }
        return cached
    }

    private func 完整标签缓存页面(
        来源: 探索标签来源,
        页码: Int,
        每页: Int
    ) -> 探索页面<探索标签>? {
        guard let cached = 完整标签缓存(),
              isFresh(cached.savedAt, lifetime: taxonomyLifetime) else {
            return nil
        }

        let filtered: [探索标签]
        switch 来源 {
        case .popular:
            filtered = cached.value.items
        case let .category(category):
            filtered = cached.value.items.filter {
                $0.category == category.rawValue
            }
        }

        let sorted = filtered.sorted { lhs, rhs in
            let lhsCount = lhs.visualNovelCount ?? Int.min
            let rhsCount = rhs.visualNovelCount ?? Int.min
            if lhsCount != rhsCount { return lhsCount > rhsCount }

            let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }

        let normalizedPage = max(1, 页码)
        let normalizedSize = min(100, max(1, 每页))
        let start = (normalizedPage - 1) * normalizedSize
        let end = min(sorted.count, start + normalizedSize)
        let results = start < sorted.count ? Array(sorted[start..<end]) : []
        let cacheState: 探索缓存状态 = isFresh(
            cached.savedAt,
            lifetime: taxonomyLifetime
        ) ? .fresh : .stale

        return 探索页面(
            results: results,
            more: end < sorted.count,
            count: sorted.count,
            cacheState: cacheState
        )
    }

    private func 获取完整目录<Item: Codable & Identifiable>(
        endpoint: String,
        fields: String,
        pageCacheKeyPrefix: String,
        强制刷新: Bool = false
    ) async throws -> [Item] where Item.ID == String {
        var pageNumber = 1
        var items: [Item] = []
        var seen: Set<String> = []
        var hasMore = true
        var expectedCount: Int?

        while hasMore {
            try Task.checkCancellation()
            let pageKey = "\(pageCacheKeyPrefix)_page_\(pageNumber)"
            let cachedPage: 缓存条目<完整目录页面<Item>>? = loadCache(
                key: pageKey
            )
            let page: 完整目录页面<Item>
            if !强制刷新,
               let cachedPage {
                page = cachedPage.value
            } else {
                page = try await post(
                    endpoint: endpoint,
                    body: [
                        "filters": [],
                        "fields": fields,
                        "sort": "id",
                        "reverse": false,
                        "results": 100,
                        "page": pageNumber,
                        "count": pageNumber == 1
                    ]
                )
                saveCache(page, key: pageKey)
            }
            if pageNumber == 1 {
                expectedCount = page.count
            }
            items.append(contentsOf: page.results.filter {
                seen.insert($0.id).inserted
            })
            hasMore = page.more
            pageNumber += 1
        }

        guard !hasMore,
              !items.isEmpty,
              expectedCount.map({ $0 == items.count }) ?? true else {
            throw VNDB探索服务错误.无效响应
        }
        return items
    }

    func 随机语录(强制刷新: Bool = false) async throws -> 探索语录? {
        let key = "random_quote"
        let cached: 缓存条目<探索语录>? = loadCache(key: key)
        if !强制刷新, let cached,
           isFresh(cached.savedAt, lifetime: dailyLifetime) {
            return cached.value
        }
        do {
            let response: 探索页面<探索语录> = try await post(
                endpoint: "quote",
                body: [
                    "filters": ["random", "=", 1],
                    "fields": Self.quoteFields,
                    "results": 1
                ]
            )
            if let quote = response.results.first {
                saveCache(quote, key: key)
                return quote
            }
            return cached?.value
        } catch {
            if let cached { return cached.value }
            throw error
        }
    }

    func 生成推荐(
        token: String,
        userID: String,
        排除ID: Set<String> = [],
        数量: Int = 12,
        强制刷新: Bool = false
    ) async throws -> [探索推荐] {
        try await 生成推荐(
            token: token,
            userID: userID,
            排除ID: 排除ID,
            数量: 数量,
            强制刷新: 强制刷新,
            进度: nil
        )
    }

    func 生成推荐(
        token: String,
        userID: String,
        排除ID: Set<String>,
        数量: Int,
        强制刷新: Bool,
        进度: ((Int, Int) -> Void)?
    ) async throws -> [探索推荐] {
        guard !token.isEmpty, !userID.isEmpty else { return [] }
        guard await VNDB离线推荐计算中心.shared.有可用模型() else {
            throw VNDB探索服务错误.推荐请求预算不足
        }
        let allExcludedIDs = 排除ID
        let progressTotal = 100
        var reportedProgress = 0
        func reportProgress(_ completed: Int) {
            let value = min(progressTotal, max(reportedProgress, completed))
            guard value > reportedProgress || completed == 0 else { return }
            reportedProgress = value
            进度?(value, progressTotal)
        }
        reportProgress(0)
        let limit = min(60, max(1, 数量))
        let calibrationSignature = "none"
        let modelCacheIdentity = safeFilename(for: 推荐模型标识())
        let recommendationKey = "recommendations_v19_\(userID)_\(modelCacheIdentity)_\(calibrationSignature)"
        let latestRecommendationKey = "recommendations_v19_latest_\(userID)_\(modelCacheIdentity)"
        let tagShelvesKey = "recommendation_tag_shelves_v9_\(userID)_\(modelCacheIdentity)_\(calibrationSignature)"
        let latestTagShelvesKey = "recommendation_tag_shelves_v9_latest_\(userID)_\(modelCacheIdentity)"
        let cached: 缓存条目<[探索推荐]>? = loadCache(key: recommendationKey)
        if !强制刷新, let cached,
           isFresh(cached.savedAt, lifetime: recommendationRefreshLifetime) {
            saveCache(cached.value, key: latestRecommendationKey)
            let libraryIDs = Set(
                (try? await allUserList(
                    token: token,
                    userID: userID,
                    budget: 推荐请求预算(
                        limit: recommendationRequestLimit,
                        progressTotal: progressTotal,
                        progress: { _, _ in reportProgress(12) }
                    ),
                    forceRefresh: false
                ))?.map(\.id) ?? []
            )
            return cached.value.filter {
                !allExcludedIDs.contains($0.id)
                    && !libraryIDs.contains($0.id)
            }
            .prefix(limit).map { $0 }
        }

        do {
            reportProgress(3)
            let budget = 推荐请求预算(
                limit: recommendationRequestLimit,
                progressTotal: progressTotal,
                progress: { _, _ in
                    reportProgress(min(24, reportedProgress + 1))
                }
            )
            let library = try await allUserList(
                token: token,
                userID: userID,
                budget: budget,
                forceRefresh: 强制刷新
            )
            reportProgress(24)
            let libraryIDs = Set(library.map(\.id))
            let excluded = allExcludedIDs.union(libraryIDs)
            guard await VNDB离线推荐计算中心.shared.有可用模型() else {
                throw VNDB探索服务错误.推荐请求预算不足
            }
            reportProgress(38)
            let libraryCharacters: [探索角色]
            let characterSnapshotKey =
                "recommendation_library_characters_v3_\(userID)"
            let savedCharacters: 推荐资料库角色快照 = loadCache(
                key: characterSnapshotKey
            )?.value ?? 推荐资料库角色快照(
                coveredVisualNovelIDs: [],
                characters: []
            )
            var charactersByID = Dictionary(
                savedCharacters.characters.map { ($0.id, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
            var coveredVisualNovelIDs = savedCharacters.coveredVisualNovelIDs
            let modelMissingVisualNovelIDs = await VNDB离线推荐计算中心.shared
                .需要下载角色的作品ID(libraryIDs)
            let missingVisualNovelIDs = modelMissingVisualNovelIDs
                .subtracting(coveredVisualNovelIDs)
            if !missingVisualNovelIDs.isEmpty {
                let downloadedCharacters = try await recommendationCharacters(
                    visualNovelIDs: Array(missingVisualNovelIDs),
                    budget: budget
                )
                for character in downloadedCharacters {
                    charactersByID[character.id] = character
                }
                coveredVisualNovelIDs.formUnion(missingVisualNovelIDs)
            }
            let updatedSnapshot = 推荐资料库角色快照(
                coveredVisualNovelIDs: coveredVisualNovelIDs,
                characters: Array(charactersByID.values)
            )
            saveCache(updatedSnapshot, key: characterSnapshotKey)
            libraryCharacters = charactersByID.values.filter { character in
                (character.visualNovels ?? []).contains {
                    libraryIDs.contains($0.id)
                }
            }

            if let context = try await VNDB离线推荐计算中心.shared.准备计算(
                   library: library,
                   downloadedCharacters: libraryCharacters,
                   excludedIDs: excluded
               ) {
                reportProgress(68)
                guard let result = try await VNDB离线推荐计算中心.shared.排序(
                    context,
                    excludedIDs: excluded,
                    limit: limit
                ) else {
                    throw VNDB探索服务错误.推荐请求预算不足
                }
                reportProgress(94)
                guard !result.recommendations.isEmpty else {
                    throw VNDB探索服务错误.推荐请求预算不足
                }
                saveCache(result.recommendations, key: recommendationKey)
                saveCache(result.recommendations, key: latestRecommendationKey)
                saveCache(result.tagShelves, key: tagShelvesKey)
                saveCache(result.tagShelves, key: latestTagShelvesKey)
                reportProgress(100)
                return Array(result.recommendations.prefix(limit))
            }

            throw VNDB探索服务错误.推荐请求预算不足
        } catch {
            throw error
        }
    }

    func 已缓存推荐(
        userID: String,
        排除ID: Set<String> = []
    ) -> [探索推荐]? {
        let excludedIDs = 排除ID
        let modelCacheIdentity = safeFilename(for: 推荐模型标识())
        let latestKey = "recommendations_v19_latest_\(userID)_\(modelCacheIdentity)"
        let current: 缓存条目<[探索推荐]>? = loadCache(
            key: "recommendations_v19_\(userID)_\(modelCacheIdentity)_\(preferenceCalibrationSignature())"
        )
        let latest: 缓存条目<[探索推荐]>? = loadCache(
            key: latestKey
        )
        if let current { saveCache(current.value, key: latestKey) }
        return (current ?? latest).map {
            $0.value.filter { !excludedIDs.contains($0.id) }
        }
    }

    func 推荐缓存是否新鲜(userID: String) -> Bool {
        let current: 缓存条目<[探索推荐]>? = loadCache(
            key: "recommendations_v19_\(userID)_\(safeFilename(for: 推荐模型标识()))_\(preferenceCalibrationSignature())"
        )
        guard let current, !current.value.isEmpty else { return false }
        return isFresh(current.savedAt, lifetime: recommendationRefreshLifetime)
    }

    func 推荐缓存生成日期(userID: String) -> Date? {
        let current: 缓存条目<[探索推荐]>? = loadCache(
            key: "recommendations_v19_\(userID)_\(safeFilename(for: 推荐模型标识()))_\(preferenceCalibrationSignature())"
        )
        guard let current, !current.value.isEmpty else { return nil }
        return current.savedAt
    }

    func cacheSizeInBytes() -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize ?? values.fileSize ?? 0
            )
        }
        return total
    }

    func 清除缓存() async {
        cacheWritesEnabled = false
        memoryCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    private func allUserList(
        token: String,
        userID: String,
        budget: 推荐请求预算,
        forceRefresh: Bool = false
    ) async throws -> [探索用户列表项目] {
        let key = "recommendation_library_snapshot_v2_\(userID)"
        let current: 缓存条目<推荐资料库快照>? = loadCache(key: key)
        let snapshot = current?.value
        let snapshotSavedAt = current?.savedAt
        if !forceRefresh, let snapshot, let snapshotSavedAt,
           isFresh(snapshotSavedAt, lifetime: recommendationLifetime) {
            return snapshot.items
        }

        let fullSyncLifetime: TimeInterval = 30 * 24 * 60 * 60
        let needsFullSync = forceRefresh || snapshot == nil
            || now().timeIntervalSince(snapshot?.lastFullSyncAt ?? .distantPast)
                >= fullSyncLifetime
        let watermark = snapshot?.newestLastModified
        let overlapWatermark = watermark.map { max(0, $0 - 1) }
        var valuesByID = needsFullSync
            ? [:]
            : Dictionary(
                (snapshot?.items ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { _, updated in updated }
            )
        var page = 1
        var hasMore = true
        while hasMore {
            try Task.checkCancellation()
            guard budget.consume() else {
                throw VNDB探索服务错误.推荐请求预算不足
            }
            let response: 探索用户列表响应 = try await post(
                endpoint: "ulist",
                body: [
                    "user": userID,
                    "filters": [],
                    "fields": Self.userListFields,
                    "sort": "lastmod",
                    "reverse": true,
                    "results": 100,
                    "page": page,
                    "count": false
                ],
                token: token
            )
            let changedItems = if needsFullSync {
                response.results
            } else if let overlapWatermark {
                response.results.filter {
                    ($0.lastModified ?? 0) >= overlapWatermark
                }
            } else {
                response.results
            }
            for item in changedItems { valuesByID[item.id] = item }
            hasMore = response.more
            if !needsFullSync, let overlapWatermark,
               response.results.contains(where: {
                   ($0.lastModified ?? 0) < overlapWatermark
               }) {
                hasMore = false
            }
            page += 1
        }
        let values = valuesByID.values.sorted {
            if ($0.lastModified ?? 0) != ($1.lastModified ?? 0) {
                return ($0.lastModified ?? 0) > ($1.lastModified ?? 0)
            }
            return $0.id.localizedStandardCompare($1.id) == .orderedAscending
        }
        let savedSnapshot = 推荐资料库快照(
            items: values,
            newestLastModified: values.compactMap(\.lastModified).max(),
            lastFullSyncAt: needsFullSync
                ? now()
                : (snapshot?.lastFullSyncAt ?? now())
        )
        saveCache(savedSnapshot, key: key)
        return values
    }

    private func recommendationCharacters(
        visualNovelIDs: [String],
        budget: 推荐请求预算
    ) async throws -> [探索角色] {
        let ids = Array(Set(visualNovelIDs)).sorted()
        guard !ids.isEmpty else { return [] }
        var values: [探索角色] = []
        var seen: Set<String> = []
        let batches = stride(from: 0, to: ids.count, by: 20).map {
            Array(ids[$0..<min($0 + 20, ids.count)])
        }
        for batch in batches {
            try Task.checkCancellation()
            let predicates: [Any] = batch.map {
                ["vn", "=", ["id", "=", $0]] as [Any]
            }
            let visualNovelFilter: Any = predicates.count == 1
                ? predicates[0]
                : ["or"] + predicates
            let filter: Any = [
                "and",
                visualNovelFilter,
                [
                    "or",
                    ["role", "=", "main"],
                    ["role", "=", "primary"]
                ]
            ]
            var page = 1
            var hasMore = true
            while hasMore {
                try Task.checkCancellation()
                let key = "recommendation_library_characters_v3_\(batch.joined(separator: "_"))_page_\(page)"
                let cached: 缓存条目<探索页面<探索角色>>? = loadCache(
                    key: key
                )
                let response: 探索页面<探索角色>
                if let cached,
                   isFresh(cached.savedAt, lifetime: recommendationMetadataLifetime) {
                    response = cached.value
                } else {
                    guard budget.consume() else {
                        throw VNDB探索服务错误.推荐请求预算不足
                    }
                    do {
                        response = try await post(
                            endpoint: "character",
                            body: [
                                "filters": filter,
                                "fields": Self.characterRecommendationFields,
                                "sort": "id",
                                "reverse": false,
                                "results": 100,
                                "page": page,
                                "count": false
                            ]
                        )
                        saveCache(response, key: key)
                    } catch {
                        guard let cached else { throw error }
                        response = cached.value
                    }
                }
                values.append(contentsOf: response.results.filter {
                    seen.insert($0.id).inserted
                })
                hasMore = response.more
                page += 1
            }
        }
        return values
    }

    private func paged<Item: Codable>(
        endpoint: String,
        key: String,
        filters: Any,
        fields: String,
        sort: String,
        reverse: Bool,
        page: Int,
        pageSize: Int,
        lifetime: TimeInterval,
        force: Bool
    ) async throws -> 探索页面<Item> {
        let normalizedPage = max(1, page)
        let normalizedSize = min(100, max(1, pageSize))
        let cacheKey = "\(key)_\(normalizedPage)_\(normalizedSize)"
        let cached: 缓存条目<探索页面<Item>>? = normalizedPage == 1
            ? loadCache(key: cacheKey)
            : nil
        if !force, let cached, isFresh(cached.savedAt, lifetime: lifetime) {
            return cached.value.markingCache(.fresh)
        }
        do {
            let response: 探索页面<Item> = try await post(
                endpoint: endpoint,
                body: queryBody(
                    filters: filters,
                    fields: fields,
                    sort: sort,
                    reverse: reverse,
                    page: normalizedPage,
                    pageSize: normalizedSize
                )
            )
            if normalizedPage == 1 { saveCache(response, key: cacheKey) }
            return response
        } catch {
            if let cached { return cached.value.markingCache(.stale) }
            throw error
        }
    }

    private func single<Item: Codable>(
        endpoint: String,
        id: String,
        extraFilter: Any? = nil,
        fields: String,
        key: String,
        lifetime: TimeInterval,
        force: Bool
    ) async throws -> Item? {
        let cached: 缓存条目<Item>? = loadCache(key: key)
        if !force, let cached, isFresh(cached.savedAt, lifetime: lifetime) {
            return cached.value
        }
        let idFilter: [Any] = ["id", "=", id]
        let filters = extraFilter.map { combine(idFilter, with: $0) } ?? idFilter
        do {
            let page: 探索页面<Item> = try await post(
                endpoint: endpoint,
                body: [
                    "filters": filters,
                    "fields": fields,
                    "results": 1
                ]
            )
            if let item = page.results.first { saveCache(item, key: key) }
            return page.results.first ?? cached?.value
        } catch {
            if let cached { return cached.value }
            throw error
        }
    }

    private func post<Value: Decodable>(
        endpoint: String,
        body: [String: Any],
        token: String? = nil
    ) async throws -> Value {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, !token.isEmpty {
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func get<Value: Decodable>(endpoint: String) async throws -> Value {
        let data = try await getData(endpoint: endpoint)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    private func getData(endpoint: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }
        return try await perform(URLRequest(url: url))
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        cacheWritesEnabled = true
        let throttleBackoffs = [60, 120, 180]
        var throttleAttempt = 0
        while true {
            try await waitForRequestSlot()
            let (data, response) = try await PaperVNConnect网络设置.发送请求(
                request,
                session: session
            )
            switch response.statusCode {
            case 200...299:
                return data
            case 401:
                throw VNDB探索服务错误.token无效
            case 429:
                guard throttleAttempt < throttleBackoffs.count else {
                    throw VNDB探索服务错误.请求过于频繁
                }
                scheduleRateLimitCooldown(
                    response: response,
                    fallbackSeconds: throttleBackoffs[throttleAttempt]
                )
                throttleAttempt += 1
            case 500, 502, 503, 504:
                throw VNDB探索服务错误.服务暂时不可用
            default:
                let message = String(
                    data: data,
                    encoding: .utf8
                )?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw VNDB探索服务错误.请求失败(
                    statusCode: response.statusCode,
                    message: message?.isEmpty == false
                        ? message!
                        : HTTPURLResponse.localizedString(
                            forStatusCode: response.statusCode
                        )
                )
            }
        }
    }

    private func waitForRequestSlot() async throws {
        let clock = ContinuousClock()
        while true {
            let current = clock.now
            var scheduled = current
            if let lastRequestStartedAt {
                scheduled = max(
                    scheduled,
                    lastRequestStartedAt.advanced(by: .seconds(3))
                )
            }
            if let rateLimitCooldownUntil {
                scheduled = max(scheduled, rateLimitCooldownUntil)
            }

            lastRequestStartedAt = scheduled
            if current < scheduled {
                try await Task.sleep(until: scheduled, clock: clock)
            }

            let resumedAt = clock.now
            if let rateLimitCooldownUntil, rateLimitCooldownUntil > resumedAt {
                continue
            }
            if rateLimitCooldownUntil != nil {
                self.rateLimitCooldownUntil = nil
            }
            return
        }
    }

    private func scheduleRateLimitCooldown(
        response: HTTPURLResponse,
        fallbackSeconds: Int
    ) {
        let headerSeconds = response.value(
            forHTTPHeaderField: "Retry-After"
        ).flatMap(Int.init)
        let seconds = min(
            300,
            max(fallbackSeconds, headerSeconds ?? 0)
        )
        let clock = ContinuousClock()
        let proposed = clock.now.advanced(by: .seconds(seconds))
        rateLimitCooldownUntil = max(
            rateLimitCooldownUntil ?? proposed,
            proposed
        )
    }

    private func visualNovelQuery(
        for source: 探索视觉小说来源
    ) -> (filters: Any, sort: String, reverse: Bool) {
        let commonFinished: [Any] = [
            "and",
            ["released", "<=", "today"],
            ["devstatus", "!=", 2]
        ]
        switch source {
        case .popular:
            return (commonFinished, "votecount", true)
        case .topRated:
            return (combine(commonFinished, with: ["votecount", ">=", 50]), "rating", true)
        case .recent:
            return (commonFinished, "released", true)
        case .upcoming:
            return (
                ["and", ["released", ">", "today"], ["released", "!=", "TBA"], ["devstatus", "!=", 2]],
                "released",
                false
            )
        case let .tag(id, _):
            return (["tag", "=", id], "votecount", true)
        case let .language(code, _):
            return (["lang", "=", code], "votecount", true)
        case let .platform(code, _):
            return (["platform", "=", code], "votecount", true)
        case let .length(value):
            return (["length", "=", min(5, max(1, value))], "votecount", true)
        case let .releaseYear(year):
            return (
                ["and", ["released", ">=", "\(year)-01-01"], ["released", "<", "\(year + 1)-01-01"]],
                "released",
                true
            )
        case let .producer(id, _):
            return (["developer", "=", ["id", "=", id]], "votecount", true)
        case let .staff(id, _):
            return (["staff", "=", ["id", "=", id]], "votecount", true)
        }
    }

    private func releaseQuery(
        for source: 探索发行来源
    ) -> (filters: Any, sort: String, reverse: Bool) {
        switch source {
        case .recent:
            return (["released", "<=", "today"], "released", true)
        case .upcoming:
            return (["and", ["released", ">", "today"], ["released", "!=", "TBA"]], "released", false)
        case .freeware:
            return (["freeware", "=", 1], "released", true)
        case .official:
            return (["official", "=", 1], "released", true)
        case let .language(code, _):
            return (["lang", "=", code], "released", true)
        case let .platform(code, _):
            return (["platform", "=", code], "released", true)
        case let .visualNovel(id, _):
            return (["vn", "=", ["id", "=", id]], "released", true)
        case let .producer(id, _):
            return (["producer", "=", ["id", "=", id]], "released", true)
        }
    }

    private func characterQuery(
        for source: 探索角色来源
    ) -> (filters: Any, reverse: Bool) {
        switch source {
        case .recentlyAdded:
            return ([], true)
        case let .trait(id, _):
            return (["trait", "=", id], true)
        case let .role(role):
            return (["role", "=", role], true)
        case let .birthday(month, day):
            return (["birthday", "=", [month, day ?? 0]], true)
        case let .visualNovel(id, _):
            return (["vn", "=", ["id", "=", id]], true)
        }
    }

    private func staffFilters(for source: 探索制作人员来源) -> Any {
        switch source {
        case .recentlyAdded: return []
        case let .language(code, _): return ["lang", "=", code]
        case let .gender(value): return ["gender", "=", value]
        case let .role(code, _): return ["role", "=", code]
        }
    }

    private func producerFilters(for source: 探索会社来源) -> Any {
        switch source {
        case .recentlyAdded: return []
        case let .language(code, _): return ["lang", "=", code]
        case let .type(type): return ["type", "=", type.rawValue]
        }
    }

    private func queryBody(
        filters: Any,
        fields: String,
        sort: String,
        reverse: Bool,
        page: Int,
        pageSize: Int
    ) -> [String: Any] {
        [
            "filters": filters,
            "fields": fields,
            "sort": sort,
            "reverse": reverse,
            "results": min(100, max(1, pageSize)),
            "page": max(1, page),
            "count": false
        ]
    }

    private func combine(_ lhs: Any, with rhs: Any) -> [Any] {
        if let lhs = lhs as? [Any], lhs.isEmpty { return rhs as? [Any] ?? [rhs] }
        if let rhs = rhs as? [Any], rhs.isEmpty { return lhs as? [Any] ?? [lhs] }
        return ["and", lhs, rhs]
    }

    private func preferenceCalibrationSignature() -> String {
        "none"
    }

    private func loadCache<Value: Codable>(
        key: String
    ) -> 缓存条目<Value>? {
        let decoder = JSONDecoder()
        if let data = memoryCache[key],
           let value = try? decoder.decode(缓存条目<Value>.self, from: data) {
            return value
        }
        let data: Data?
        if let stored = try? Data(contentsOf: dataURL(for: key)) {
            data = stored
        } else if isPersistentRecommendationData(key),
                  let legacy = try? Data(contentsOf: cacheURL(for: key)) {
            data = legacy
            if cacheWritesEnabled {
                try? legacy.write(to: dataURL(for: key), options: .atomic)
            }
        } else {
            data = nil
        }
        guard let data,
              let value = try? decoder.decode(缓存条目<Value>.self, from: data) else {
            return nil
        }
        if shouldRetainCacheInMemory(key) {
            memoryCache[key] = data
        }
        return value
    }

    private func saveCache<Value: Codable>(_ value: Value, key: String) {
        guard cacheWritesEnabled else { return }
        let entry = 缓存条目(savedAt: now(), value: value)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        if shouldRetainCacheInMemory(key) {
            memoryCache[key] = data
        } else {
            memoryCache[key] = nil
        }
        try? data.write(to: dataURL(for: key), options: .atomic)
        enforceCacheLimitIfNeeded()
    }

    private func enforceCacheLimitIfNeeded() {
        guard let maximum = 缓存策略.当前.maximumCacheBytes,
              maximum > 0 else {
            return
        }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        var files: [(url: URL, size: Int64, date: Date)] = []
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            let size = Int64(
                values.totalFileAllocatedSize ?? values.fileSize ?? 0
            )
            files.append((
                url: url,
                size: size,
                date: values.contentModificationDate ?? .distantPast
            ))
            total += size
        }
        let protectedPrefixes = [
            "tag_catalog_all",
            "trait_catalog_all",
            "recommendation_tag_catalog_v1_page_",
            "recommendation_trait_catalog_v1_page_"
        ]
        for file in files.sorted(by: { $0.date < $1.date }) {
            let name = file.url.deletingPathExtension().lastPathComponent
            if protectedPrefixes.contains(where: name.hasPrefix) {
                continue
            }
            guard total > maximum else { break }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }

    private func isFresh(_ date: Date, lifetime: TimeInterval) -> Bool {
        now().timeIntervalSince(date) < lifetime
    }

    private func cacheURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(safeFilename(for: key) + ".json")
    }

    private func dataURL(for key: String) -> URL {
        let directory = isPersistentRecommendationData(key)
            ? recommendationDataDirectory
            : cacheDirectory
        return directory.appendingPathComponent(safeFilename(for: key) + ".json")
    }

    private func safeFilename(for key: String) -> String {
        let safe = key.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "_"
        }
        return String(safe)
    }

    private func isPersistentRecommendationData(_ key: String) -> Bool {
        key.hasPrefix("recommendation_")
            || key.hasPrefix("recommendations_")
            || key == "tag_catalog_all"
            || key == "trait_catalog_all"
            || key == "stats"
    }

    private func shouldRetainCacheInMemory(_ key: String) -> Bool {
        !(isPersistentRecommendationData(key) && key.contains("_page_"))
    }

    private static let visualNovelFields = """
    title,alttitle,titles{lang,title,latin,official,main},aliases,released,languages,platforms,\
    image{id,url,thumbnail,dims,sexual,violence},length,length_minutes,rating,votecount,\
    tags{id,name,rating,spoiler,lie,category},developers{id,name,original,lang,type},\
    relations{id,relation,relation_official}
    """

    private static let releaseFields = """
    title,alttitle,languages{lang,title,latin,mtl,main},platforms,media{medium,qty},\
    vns{rtype,id,title,titles{lang,title,latin,official,main},image{id,url,thumbnail,dims,sexual,violence}},\
    producers{developer,publisher,id,name,original},\
    images{id,url,thumbnail,dims,sexual,violence,type,vn,languages,photo},\
    released,minage,patch,freeware,uncensored,official,has_ero,resolution,engine,voiced,notes,gtin,catalog,\
    extlinks{url,label,name,id}
    """

    private static let characterFields = """
    name,original,aliases,description,image{id,url,dims,sexual,violence},blood_type,height,weight,bust,waist,hips,cup,age,birthday,sex,gender,\
    vns{spoiler,role,id,title,titles{lang,title,latin,official,main},image{id,url,thumbnail,dims,sexual,violence}},\
    traits{spoiler,lie,id,name,group_name,sexual}
    """
    private static let characterRecommendationFields = """
    name,image{id,url,dims,sexual,violence},vns{spoiler,role,id,title},traits{spoiler,lie,id,name,group_name,sexual}
    """

    private static let staffFields = "name,original,aid,ismain,lang,gender,description,extlinks{url,label,name,id},aliases{aid,name,latin,ismain}"
    private static let producerFields = "name,original,aliases,lang,type,description,extlinks{url,label,name,id}"
    private static let tagFields = "name,aliases,description,category,searchable,applicable,vn_count"
    private static let traitFields = "name,aliases,description,searchable,applicable,sexual,group_id,group_name,char_count"
    private static let traitCatalogFields = "name,sexual,group_id,group_name,char_count"
    private static let quoteFields = "quote,score,vn{id,title,titles{lang,title,latin,official,main},image{id,url,thumbnail,dims,sexual,violence}},character{id,name,original,image{id,url,dims,sexual,violence}}"
    private static let userListFields = """
    added,voted,lastmod,vote,started,finished,labels{id,label},vn{title,titles{lang,title,latin,official,main},\
    image{url,thumbnail,dims,sexual,violence},languages,platforms,length,rating,votecount,\
    tags{id,name,rating,spoiler,lie,category},developers{id,name},\
    relations{id,relation,relation_official}}
    """
}

enum 为你推荐偏好分析设置 {
    static let 启用键 = "recommendationPreferenceAnalysisEnabled"
    static let 最低物理内存字节: UInt64 = 4 * 1_024 * 1_024 * 1_024
    static let 当前分析代次 = 15
    private static let 完成代次键前缀 =
        "recommendationPreferenceAnalysisCompletedGeneration."
    private static let 完成模型键前缀 =
        "recommendationPreferenceAnalysisCompletedModel."

    static var 此设备支持: Bool {
        是否支持(物理内存: ProcessInfo.processInfo.physicalMemory)
    }

    static var 已启用: Bool {
        启用状态()
    }

    static func 是否支持(物理内存: UInt64) -> Bool {
        物理内存 >= 最低物理内存字节
    }

    static func 启用状态(
        defaults: UserDefaults = .standard,
        物理内存: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Bool {
        guard 是否支持(物理内存: 物理内存) else { return false }
        guard defaults.object(forKey: 启用键) != nil else { return true }
        return defaults.bool(forKey: 启用键)
    }

    static func 应用设备限制(
        defaults: UserDefaults = .standard,
        物理内存: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        guard !是否支持(物理内存: 物理内存) else { return }
        defaults.set(false, forKey: 启用键)
    }

    static func 已完成分析(
        userID: String,
        代次: Int = 当前分析代次,
        模型标识: String? = nil,
        defaults: UserDefaults = .standard
    ) -> Bool {
        guard defaults.integer(forKey: 完成代次键(userID: userID)) >= 代次 else {
            return false
        }
        guard let 模型标识 else {
            return true
        }
        return defaults.string(forKey: 完成模型键(userID: userID)) == 模型标识
    }

    static func 标记分析完成(
        userID: String,
        代次: Int = 当前分析代次,
        模型标识: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        let key = 完成代次键(userID: userID)
        defaults.set(max(defaults.integer(forKey: key), 代次), forKey: key)
        if let 模型标识 {
            defaults.set(模型标识, forKey: 完成模型键(userID: userID))
        }
    }

    private static func 完成代次键(userID: String) -> String {
        完成代次键前缀 + userID.lowercased()
    }

    private static func 完成模型键(userID: String) -> String {
        完成模型键前缀 + userID.lowercased()
    }
}

@MainActor
final class 推荐后台分析中心: ObservableObject {
    static let shared = 推荐后台分析中心()

    @Published private(set) var isAnalyzing = false
    @Published private(set) var analysisProgress = 0.0

    private static let logger = Logger(
        subsystem: "com.jizpaper.PaperVN",
        category: "PreferenceAnalysis"
    )

    private static var 正在运行预览: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static var 可以提交持续处理任务: Bool {
        UIApplication.shared.applicationState == .active
    }

    static let 后台任务通配标识 =
        "com.jizpaper.PaperVN.preference-analysis.*"
    private static let 后台任务标识前缀 =
        "com.jizpaper.PaperVN.preference-analysis."

    private struct 分析描述: Codable, Equatable {
        let identifier: String
        let userID: String
        let forceRefresh: Bool
        let createdAt: Date
        let analysisGeneration: Int?
        let modelIdentifier: String?
    }

    private struct 运行中分析 {
        let descriptor: 分析描述
        let task: Task<[探索推荐], Error>
    }

    private let service = VNDB探索服务.shared
    private let defaults = UserDefaults.standard
    private let pendingDescriptorKey = "pendingRecommendationPreferenceAnalysis"
    private var activeAnalysis: 运行中分析?
    private var libraryChangeRefreshTask: Task<Void, Never>?
    private var changeObservers: [NSObjectProtocol] = []
    private var isPausedForToday = false
    private var completedRequestCount = 0
    private var totalRequestCount = VNDB探索服务.推荐分析请求上限

    private var didRegisterBackgroundTask = false
    private var continuedTasks: [String: BGTask] = [:]

    private init() {
        guard !Self.正在运行预览 else { return }

        for name in [Notification.Name.paperVNLibraryDidChange] {
            changeObservers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.安排资料变更重算()
                    }
                }
            )
        }
    }

    private func 安排资料变更重算() {
        guard 为你推荐偏好分析设置.已启用 else { return }
        libraryChangeRefreshTask?.cancel()
        libraryChangeRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled,
                  let self,
                  let credentials = 读取VNDB已保存凭据() else { return }
            self.停止分析()
            _ = try? await self.执行分析(
                token: credentials.token,
                userID: credentials.userID,
                forceRefresh: true
            )
        }
    }

    private func 当前模型标识() -> String {
        service.推荐模型标识()
    }

    func 注册后台任务() {
        guard !Self.正在运行预览, !didRegisterBackgroundTask else {
            return
        }
        guard #available(iOS 26.0, *) else { return }
        didRegisterBackgroundTask = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.后台任务通配标识,
            using: .main
        ) { task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                推荐后台分析中心.shared.接收后台任务(task)
            }
        }
        if !didRegisterBackgroundTask {
            Self.logger.error(
                "Preference analysis background task registration failed"
            )
        }
    }

    func 启动需要的分析() {
        guard !isPausedForToday,
              !Self.正在运行预览,
              为你推荐偏好分析设置.已启用,
              VNDB离线推荐模型加载器.模型标识() != nil,
              let credentials = 读取VNDB已保存凭据() else {
            return
        }
        guard Self.可以提交持续处理任务 else { return }
        let modelIdentifier = 当前模型标识()
        let hasPendingAnalysis = 待处理分析描述().map {
            $0.userID == credentials.userID
                && $0.analysisGeneration
                    == 为你推荐偏好分析设置.当前分析代次
                && $0.modelIdentifier == modelIdentifier
        } ?? false
        let needsCurrentGeneration = !为你推荐偏好分析设置.已完成分析(
            userID: credentials.userID,
            模型标识: modelIdentifier
        )
        let hasStaleRecommendations = !service.推荐缓存是否新鲜(
            userID: credentials.userID
        )
        guard hasPendingAnalysis
                || needsCurrentGeneration
                || hasStaleRecommendations else {
            偏好分析实时活动中心.shared.结束(
                success: true,
                immediately: true
            )
            return
        }
        if activeAnalysis?.descriptor.userID == credentials.userID {
            if let descriptor = 待处理分析描述(),
               descriptor.userID == credentials.userID,
               continuedTasks[descriptor.identifier] == nil {
                提交后台活动(for: descriptor)
            }
            return
        }

        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.分析(
                token: credentials.token,
                userID: credentials.userID,
                forceRefresh: false
            )
        }
    }

    func 设置Today分析暂停(_ isPaused: Bool) {
        guard !Self.正在运行预览 else { return }
        guard isPausedForToday != isPaused else { return }
        isPausedForToday = isPaused
        if isPaused {
            停止分析()
        } else {
            启动需要的分析()
        }
    }

    func 分析(
        token: String,
        userID: String,
        forceRefresh: Bool
    ) async throws -> [探索推荐] {
        try await 执行分析(
            token: token,
            userID: userID,
            forceRefresh: forceRefresh
        )
    }

    private func 执行分析(
        token: String,
        userID: String,
        forceRefresh: Bool
    ) async throws -> [探索推荐] {
        guard 为你推荐偏好分析设置.已启用 else { return [] }
        guard !Self.正在运行预览 else { return [] }
        guard await VNDB离线推荐计算中心.shared.有可用模型() else {
            return []
        }

        let needsCurrentGeneration = !为你推荐偏好分析设置.已完成分析(
            userID: userID,
            模型标识: 当前模型标识()
        )
        let effectiveForceRefresh = forceRefresh || needsCurrentGeneration

        if let activeAnalysis, activeAnalysis.descriptor.userID == userID {
            return try await activeAnalysis.task.value
        }
        if activeAnalysis != nil {
            停止分析()
        }

        if !effectiveForceRefresh,
           service.推荐缓存是否新鲜(userID: userID) {
            if let pending = 待处理分析描述(), pending.userID == userID {
                取消后台活动(pending.identifier)
                清除待处理分析描述()
            }
            return try await service.生成推荐(
                token: token,
                userID: userID,
                排除ID: [],
                数量: 48,
                强制刷新: false
            )
        }

        let descriptor: 分析描述
        if let pending = 待处理分析描述(),
           pending.userID == userID,
           pending.analysisGeneration == 为你推荐偏好分析设置.当前分析代次,
           pending.modelIdentifier == 当前模型标识(),
           !effectiveForceRefresh || pending.forceRefresh {
            descriptor = pending
        } else {
            if let pending = 待处理分析描述() {
                取消后台活动(pending.identifier)
            }
            descriptor = 分析描述(
                identifier: 新分析标识(),
                userID: userID,
                forceRefresh: effectiveForceRefresh,
                createdAt: Date(),
                analysisGeneration: 为你推荐偏好分析设置.当前分析代次,
                modelIdentifier: 当前模型标识()
            )
        }
        let task = 启动分析(
            descriptor: descriptor,
            token: token,
            submitBackgroundActivity: true
        )
        return try await task.value
    }

    func 停止分析() {
        activeAnalysis?.task.cancel()
        activeAnalysis = nil
        isAnalyzing = false
        analysisProgress = 0

        guard !Self.正在运行预览 else { return }

        偏好分析实时活动中心.shared.结束(
            success: false,
            immediately: true
        )

        if let descriptor = 待处理分析描述() {
            取消后台活动(descriptor.identifier)
        }
        清除待处理分析描述()

        for task in continuedTasks.values {
            task.setTaskCompleted(success: false)
        }
        continuedTasks.removeAll()
    }

    private func 启动分析(
        descriptor: 分析描述,
        token: String,
        submitBackgroundActivity: Bool
    ) -> Task<[探索推荐], Error> {
        completedRequestCount = 0
        totalRequestCount = VNDB探索服务.推荐分析请求上限
        isAnalyzing = true
        analysisProgress = 0

        let progress: (Int, Int) -> Void = { [weak self] completed, total in
            self?.更新进度(completed: completed, total: total)
        }
        let recommendationService = service
        let work = Task {
            try await recommendationService.生成推荐(
                token: token,
                userID: descriptor.userID,
                排除ID: [],
                数量: 48,
                强制刷新: descriptor.forceRefresh,
                进度: progress
            )
        }
        activeAnalysis = 运行中分析(descriptor: descriptor, task: work)

        偏好分析实时活动中心.shared.开始(
            totalRequestCount: totalRequestCount
        )

        if submitBackgroundActivity {
            保存待处理分析描述(descriptor)
            提交后台活动(for: descriptor)
        }

        Task { [weak self] in
            do {
                _ = try await work.value
                let generatedAt = self?.service.推荐缓存生成日期(
                    userID: descriptor.userID
                )
                let generatedFreshRecommendations = generatedAt.map {
                    $0 >= descriptor.createdAt.addingTimeInterval(-1)
                } ?? false
                self?.完成分析(
                    descriptor: descriptor,
                    success: generatedFreshRecommendations
                )
            } catch {
                self?.完成分析(descriptor: descriptor, success: false)
            }
        }
        return work
    }

    private func 更新进度(completed: Int, total: Int) {
        completedRequestCount = max(completedRequestCount, completed)
        totalRequestCount = max(1, total)
        analysisProgress = min(
            Double(completedRequestCount) / Double(totalRequestCount),
            1
        )

        偏好分析实时活动中心.shared.更新(
            completed: completedRequestCount,
            total: totalRequestCount
        )
        for task in continuedTasks.values {
            guard #available(iOS 26.0, *),
                  let task = task as? BGContinuedProcessingTask else {
                continue
            }
            task.progress.totalUnitCount = Int64(totalRequestCount)
            task.progress.completedUnitCount = Int64(
                min(completedRequestCount, totalRequestCount)
            )
        }
    }

    private func 完成分析(descriptor: 分析描述, success: Bool) {
        guard activeAnalysis?.descriptor == descriptor else { return }
        activeAnalysis = nil

        if success, 待处理分析描述() == descriptor {
            清除待处理分析描述()
        }
        if success,
           descriptor.analysisGeneration
            == 为你推荐偏好分析设置.当前分析代次 {
            为你推荐偏好分析设置.标记分析完成(
                userID: descriptor.userID,
                模型标识: descriptor.modelIdentifier ?? 当前模型标识()
            )
        }
        if success {
            NotificationCenter.default.post(
                name: .paperVNRecommendationsDidUpdate,
                object: descriptor.userID
            )
        }

        if success {
            更新进度(
                completed: totalRequestCount,
                total: totalRequestCount
            )
        }

        偏好分析实时活动中心.shared.结束(success: success)
        取消后台活动(descriptor.identifier)
        let completedTaskIDs = continuedTasks.values.compactMap { task in
            task.identifier == descriptor.identifier ? task.identifier : nil
        }
        for identifier in completedTaskIDs {
            guard let task = continuedTasks.removeValue(forKey: identifier) else {
                continue
            }
            task.setTaskCompleted(success: success)
        }

        if !success, 为你推荐偏好分析设置.已启用 {
            重新排队分析(descriptor)
        }

        isAnalyzing = false
    }

    private func 保存待处理分析描述(_ descriptor: 分析描述) {
        guard let data = try? JSONEncoder().encode(descriptor) else { return }
        defaults.set(data, forKey: pendingDescriptorKey)
    }

    private func 待处理分析描述() -> 分析描述? {
        guard let data = defaults.data(forKey: pendingDescriptorKey),
              let descriptor = try? JSONDecoder().decode(
                分析描述.self,
                from: data
              ) else {
            return nil
        }
        return descriptor
    }

    private func 清除待处理分析描述() {
        defaults.removeObject(forKey: pendingDescriptorKey)
    }

    private func 新分析标识() -> String {
        Self.后台任务标识前缀 + UUID().uuidString.lowercased()
    }

    private func 提交后台活动(for descriptor: 分析描述) {
        guard #available(iOS 26.0, *),
              didRegisterBackgroundTask,
              !Self.正在运行预览,
              Self.可以提交持续处理任务 else {
            return
        }
        let request = BGContinuedProcessingTaskRequest(
            identifier: descriptor.identifier,
            title: String(localized: "分析偏好"),
            subtitle: String(
                localized: "PaperVN需要一些时间分析你的偏好。"
            )
        )
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            Self.logger.info(
                "Preference analysis background task submitted: \(descriptor.identifier, privacy: .public)"
            )
        } catch {
            Self.logger.error(
                "Preference analysis background task submission failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func 取消后台活动(_ identifier: String) {
        guard didRegisterBackgroundTask else { return }
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: identifier
        )
    }

    @available(iOS 26.0, *)
    private func 接收后台任务(_ task: BGContinuedProcessingTask) {
        Self.logger.info(
            "Preference analysis background task started: \(task.identifier, privacy: .public)"
        )
        guard 为你推荐偏好分析设置.已启用,
              let descriptor = 待处理分析描述(),
              descriptor.identifier == task.identifier else {
            task.setTaskCompleted(success: false)
            return
        }

        continuedTasks[task.identifier] = task
        task.progress.totalUnitCount = Int64(totalRequestCount)
        task.progress.completedUnitCount = Int64(
            min(completedRequestCount, totalRequestCount)
        )
        task.updateTitle(
            String(localized: "分析偏好"),
            subtitle: String(
                localized: "PaperVN需要一些时间分析你的偏好。"
            )
        )
        task.expirationHandler = { [weak task] in
            Task { @MainActor in
                guard let task else { return }
                推荐后台分析中心.shared.后台任务到期(task)
            }
        }

        if let activeAnalysis,
           activeAnalysis.descriptor == descriptor {
            return
        }

        guard let credentials = 读取VNDB已保存凭据(),
              credentials.userID == descriptor.userID else {
            continuedTasks[task.identifier] = nil
            task.setTaskCompleted(success: false)
            重新排队分析(descriptor)
            return
        }
        _ = 启动分析(
            descriptor: descriptor,
            token: credentials.token,
            submitBackgroundActivity: false
        )
    }

    @available(iOS 26.0, *)
    private func 后台任务到期(_ task: BGContinuedProcessingTask) {
        continuedTasks[task.identifier] = nil
        guard activeAnalysis?.descriptor.identifier == task.identifier else {
            task.setTaskCompleted(success: false)
            return
        }
        let descriptor = activeAnalysis!.descriptor
        activeAnalysis?.task.cancel()
        activeAnalysis = nil
        isAnalyzing = false
        task.setTaskCompleted(success: false)
        重新排队分析(descriptor)
    }

    private func 重新排队分析(_ descriptor: 分析描述) {
        guard 为你推荐偏好分析设置.已启用 else { return }
        let retryDescriptor = 分析描述(
            identifier: 新分析标识(),
            userID: descriptor.userID,
            forceRefresh: descriptor.forceRefresh,
            createdAt: descriptor.createdAt,
            analysisGeneration: descriptor.analysisGeneration,
            modelIdentifier: descriptor.modelIdentifier
        )
        保存待处理分析描述(retryDescriptor)
        提交后台活动(for: retryDescriptor)
    }
}

nonisolated enum PaperVNConnect自动策略 {
    static let 自动转发状态键 = "vndbRequestForwardingEnabled"
    private static let 首次区域默认已应用键 =
        "paperVNConnectDidApplyInitialRegionDefault"
    private static let 旧自动状态键 =
        "paperVNConnectAutomaticallyEnabled"

    static var 自动转发已启用: Bool {
        UserDefaults.standard.bool(forKey: 自动转发状态键)
    }

    static func 准备初始状态(
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: 首次区域默认已应用键) else {
            return
        }

        defaults.set(
            当前设备具有中国大陆特征,
            forKey: 自动转发状态键
        )
        defaults.removeObject(forKey: 旧自动状态键)
        defaults.set(true, forKey: 首次区域默认已应用键)
    }

    static var 当前设备具有中国大陆特征: Bool {
        具有中国大陆特征(
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier,
            preferredLanguageIdentifiers:
                Bundle.main.preferredLocalizations
                + Locale.preferredLanguages
                + [
                    Locale.autoupdatingCurrent.identifier,
                    Locale.current.identifier
                ],
            regionIdentifiers: [
                Locale.autoupdatingCurrent.region?.identifier,
                Locale.current.region?.identifier
            ].compactMap { $0 }
        )
    }

    static func 具有中国大陆特征(
        timeZoneIdentifier: String,
        preferredLanguageIdentifiers: [String],
        regionIdentifiers: [String]
    ) -> Bool {
        let mainlandTimeZones = [
            "Asia/Shanghai",
            "Asia/Chongqing",
            "Asia/Harbin",
            "Asia/Urumqi",
            "Asia/Kashgar",
            "PRC"
        ]
        if mainlandTimeZones.contains(timeZoneIdentifier) {
            return true
        }
        if regionIdentifiers.contains(where: { $0.uppercased() == "CN" }) {
            return true
        }

        return preferredLanguageIdentifiers.contains { identifier in
            let language = Locale.Language(identifier: identifier)
            guard language.languageCode?.identifier.lowercased() == "zh" else {
                return false
            }
            if language.script?.identifier == "Hant" {
                return false
            }
            if let region = language.region?.identifier.uppercased(),
               ["TW", "HK", "MO"].contains(region) {
                return false
            }
            return language.script?.identifier == "Hans"
                || language.region?.identifier.uppercased() == "CN"
                || language.script == nil
        }
    }
}
