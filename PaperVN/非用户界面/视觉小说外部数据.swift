import Combine
import Foundation
import SwiftUI

enum 评分数据来源: String, CaseIterable, Identifiable {
    static let 设置键 = "visualNovelRatingSource"

    case combined
    case vndb
    case bangumi

    var id: Self { self }

    var title: String {
        switch self {
        case .combined: return String(localized: "综合")
        case .vndb: return "VNDB"
        case .bangumi: return String(localized: "Bangumi番组计划")
        }
    }

    static var current: Self {
        guard let rawValue = UserDefaults.standard.string(forKey: 设置键),
              let value = Self(rawValue: rawValue) else { return .combined }
        return value
    }
}

enum 评论数据来源: String, CaseIterable, Identifiable {
    static let 设置键 = "visualNovelCommentSource"

    case combined
    case bangumi
    case steam

    var id: Self { self }

    var title: String {
        switch self {
        case .combined: return String(localized: "综合")
        case .bangumi: return String(localized: "Bangumi番组计划")
        case .steam: return "Steam"
        }
    }

    static var current: Self {
        guard let rawValue = UserDefaults.standard.string(forKey: 设置键),
              let value = Self(rawValue: rawValue) else { return .combined }
        return value
    }
}

enum Steam评论语言: String, CaseIterable, Identifiable, Codable, Sendable {
    static let 设置键 = "steamReviewLanguages"

    case japanese
    case simplifiedChinese = "schinese"
    case traditionalChinese = "tchinese"
    case korean = "koreana"
    case english

    var id: Self { self }

    var title: String {
        switch self {
        case .japanese: return String(localized: "日语")
        case .simplifiedChinese: return String(localized: "简体中文")
        case .traditionalChinese: return String(localized: "繁体中文")
        case .korean: return String(localized: "韩语")
        case .english: return String(localized: "英语")
        }
    }

    static var selected: Set<Self> {
        guard UserDefaults.standard.object(forKey: 设置键) != nil else {
            return Set(allCases)
        }
        let values = UserDefaults.standard.string(forKey: 设置键)?
            .split(separator: ",")
            .compactMap { Self(rawValue: String($0)) } ?? []
        return Set(values)
    }

    static func save(_ values: Set<Self>) {
        let ordered = allCases.filter(values.contains).map(\.rawValue)
        UserDefaults.standard.set(ordered.joined(separator: ","), forKey: 设置键)
    }
}

struct 视觉小说外部ID: Hashable, Sendable {
    let bangumiIDs: [Int]
    let steamIDs: [Int]

    var cacheIdentity: String {
        let bangumi = bangumiIDs.sorted().map(String.init).joined(separator: ",")
        let steam = steamIDs.sorted().map(String.init).joined(separator: ",")
        return "bangumi:\(bangumi)|steam:\(steam)"
    }
}

private struct 视觉小说外部ID文件: Decodable {
    struct 条目: Decodable {
        let steam: String
        let bangumi: String
        let vndb: String
    }

    let entries: [条目]
}

final class 视觉小说外部ID目录: @unchecked Sendable {
    static let shared = 视觉小说外部ID目录()
    private let values: [String: 视觉小说外部ID]

    private init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "vndb_id_connector", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(视觉小说外部ID文件.self, from: data) else {
            values = [:]
            return
        }

        var bangumi: [String: [Int]] = [:]
        var steam: [String: [Int]] = [:]
        for entry in file.entries {
            let vndbID = entry.vndb
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !vndbID.isEmpty else { continue }
            if let id = Int(entry.bangumi), id > 0,
               !bangumi[vndbID, default: []].contains(id) {
                bangumi[vndbID, default: []].append(id)
            }
            if let id = Int(entry.steam), id > 0,
               !steam[vndbID, default: []].contains(id) {
                steam[vndbID, default: []].append(id)
            }
        }
        let keys = Set(bangumi.keys).union(steam.keys)
        values = Dictionary(uniqueKeysWithValues: keys.map { key in
            (key, 视觉小说外部ID(bangumiIDs: bangumi[key] ?? [], steamIDs: steam[key] ?? []))
        })
    }

    func ids(for vndbID: String) -> 视觉小说外部ID {
        let normalizedID = vndbID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return values[normalizedID]
            ?? 视觉小说外部ID(bangumiIDs: [], steamIDs: [])
    }
}

struct 统一视觉小说评分: Codable, Hashable, Sendable {
    let score: Double
    let voteCount: Int?
    var shortText: String { String(format: "%.2f", score) }
    var detailedText: String {
        guard let voteCount else { return shortText }
        return "\(shortText)（\(voteCount.formatted())人评分）"
    }
}

enum 视觉小说评论来源: String, Codable, Sendable {
    case bangumi
    case steam
    var title: String {
        self == .bangumi ? String(localized: "Bangumi番组计划") : "Steam"
    }
}

struct 视觉小说评论: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let source: 视觉小说评论来源
    let username: String
    let avatarURL: String?
    let text: String
    let rating: Int?
    let isRecommended: Bool?
    let dateText: String?
    let timestamp: Int?
    let language: String?

    var commentLanguageCode: String? {
        switch source {
        case .bangumi:
            return "zh-Hans"
        case .steam:
            let 标记 = language?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: "-")
                .lowercased()
            switch 标记 {
            case "schinese", "simplified chinese", "zh", "zh-cn", "zh-hans":
                return "zh-Hans"
            case "tchinese", "traditional chinese", "zh-tw", "zh-hant":
                return "zh-Hant"
            case "japanese", "ja", "ja-jp":
                return "ja"
            case "koreana", "korean", "ko", "ko-kr":
                return "ko"
            case "english", "en", "en-us", "en-gb":
                return "en"
            default: return nil
            }
        }
    }
}

@MainActor
final class 视觉小说外部数据服务: ObservableObject {
    static let shared = 视觉小说外部数据服务()

    private struct 缓存条目<Value: Codable>: Codable {
        let savedAt: Date
        let value: Value
    }

    private struct Bangumi条目: Decodable {
        struct 评分: Decodable { let total: Int; let score: Double }
        let rating: 评分?
    }

    private struct Steam评论响应: Decodable {
        struct 评论: Decodable {
            struct 作者: Decodable {
                let steamid: String
                let personaname: String?
                let avatar: String?
            }
            let recommendationid: String
            let author: 作者
            let language: String
            let review: String
            let timestamp_created: Int
            let voted_up: Bool
        }
        let success: Int
        let reviews: [评论]
    }

    private struct 评论请求: Sendable {
        let url: URL
        let bangumiID: Int?
        let steamAppID: Int?
        var accessToken: String?
    }

    private struct 评论响应: Sendable {
        let request: 评论请求
        let data: Data
    }

    private struct 评论响应批次: Sendable {
        let responses: [评论响应]
        let failedRequestCount: Int
    }

    private enum 评论请求结果: Sendable {
        case response(评论响应)
        case failure
        case deadline
    }

    private struct 进行中的评论请求 {
        let id: UUID
        let task: Task<[视觉小说评论], Error>
    }

    private struct Bangumi评论响应: Decodable {
        struct 评论: Decodable {
            struct 用户: Decodable {
                struct 头像: Decodable {
                    let medium: String?
                }

                let id: Int
                let nickname: String?
                let username: String?
                let avatar: 头像?
            }

            let id: Int
            let user: 用户?
            let rate: Int?
            let comment: String?
            let updatedAt: Int?
        }

        let data: [评论]
    }

    private let session: URLSession
    private let cacheDirectory: URL
    private let cacheLifetime: TimeInterval = 12 * 60 * 60
    private let commentRetryDelays: [Duration] = [
        .seconds(1),
        .seconds(3),
        .seconds(7)
    ]
    private var bangumiRatings: [String: 统一视觉小说评分] = [:]
    private var commentCache: [String: [视觉小说评论]] = [:]
    private var pendingCommentRequests: [String: 进行中的评论请求] = [:]

    private init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.httpMaximumConnectionsPerHost = 12
            self.session = URLSession(configuration: configuration)
        }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = root.appendingPathComponent("PaperVNExternalContentCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func rating(vndbID: String, vndbRating: Double?, vndbVoteCount: Int?, forceRefresh: Bool = false) async -> 统一视觉小说评分? {
        let vndbValue = vndbRating.map { 统一视觉小说评分(score: $0 / 10, voteCount: vndbVoteCount) }
        switch 评分数据来源.current {
        case .vndb: return vndbValue
        case .bangumi: return await bangumiRating(vndbID: vndbID, forceRefresh: forceRefresh)
        case .combined:
            let bangumiValue = await bangumiRating(vndbID: vndbID, forceRefresh: forceRefresh)
            guard let vndbValue else { return bangumiValue }
            guard let bangumiValue else { return vndbValue }
            let weight = min(max(UserDefaults.standard.object(forKey: "combinedRatingVNDBWeight") as? Double ?? 0.5, 0.1), 0.9)
            return 统一视觉小说评分(score: vndbValue.score * weight + bangumiValue.score * (1 - weight), voteCount: (vndbValue.voteCount ?? 0) + (bangumiValue.voteCount ?? 0))
        }
    }

    func comments(vndbID: String, forceRefresh: Bool = false) async throws -> [视觉小说评论] {
        let source = 评论数据来源.current
        let selectedLanguages = Steam评论语言.selected
        let languages = selectedLanguages
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        let externalIDs = 视觉小说外部ID目录.shared.ids(for: vndbID)
        let mappingSignature = stableIdentifier(externalIDs.cacheIdentity)
        let key = "comments_v4_\(vndbID)_\(source.rawValue)_\(languages)_\(mappingSignature)"
        if !forceRefresh, let cached = commentCache[key] { return cached }
        if !forceRefresh, let cached: 缓存条目<[视觉小说评论]> = loadCache(key), Date().timeIntervalSince(cached.savedAt) < cacheLifetime {
            commentCache[key] = cached.value
            return cached.value
        }

        if !forceRefresh, let pending = pendingCommentRequests[key] {
            return try await pending.task.value
        }

        let requestID = UUID()
        let task = Task { [self] in
            try await fetchCommentsWithRetry(
                source: source,
                vndbID: vndbID,
                selectedLanguages: selectedLanguages,
                externalIDs: externalIDs
            )
        }
        pendingCommentRequests[key] = 进行中的评论请求(
            id: requestID,
            task: task
        )
        defer {
            if pendingCommentRequests[key]?.id == requestID {
                pendingCommentRequests[key] = nil
            }
        }

        let result = try await task.value
        commentCache[key] = result
        saveCache(缓存条目(savedAt: Date(), value: result), key: key)
        return result
    }

    private func fetchCommentsWithRetry(
        source: 评论数据来源,
        vndbID: String,
        selectedLanguages: Set<Steam评论语言>,
        externalIDs: 视觉小说外部ID
    ) async throws -> [视觉小说评论] {
        var retryIndex = 0
        while true {
            do {
                return try await fetchComments(
                    source: source,
                    vndbID: vndbID,
                    selectedLanguages: selectedLanguages,
                    externalIDs: externalIDs
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard retryIndex < commentRetryDelays.count,
                      Self.isRetryableCommentError(error) else {
                    throw error
                }
                try await Task.sleep(for: commentRetryDelays[retryIndex])
                retryIndex += 1
            }
        }
    }

    private static func isRetryableCommentError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .cannotLoadFromNetwork,
             .cannotConnectToHost,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .dnsLookupFailed,
             .resourceUnavailable,
             .badServerResponse,
             .cannotDecodeContentData:
            return true
        default:
            return false
        }
    }

    private func fetchComments(
        source: 评论数据来源,
        vndbID: String,
        selectedLanguages: Set<Steam评论语言>,
        externalIDs: 视觉小说外部ID
    ) async throws -> [视觉小说评论] {
        let values: [视觉小说评论]
        switch source {
        case .bangumi: values = try await bangumiComments(vndbID: vndbID)
        case .steam:
            values = try await steamComments(
                vndbID: vndbID,
                languages: selectedLanguages
            )
        case .combined:
            async let bangumi = try? bangumiComments(vndbID: vndbID)
            async let steam = try? steamComments(
                vndbID: vndbID,
                languages: selectedLanguages
            )
            let bangumiValues = await bangumi
            let steamValues = await steam
            try Task.checkCancellation()
            values = (bangumiValues ?? []) + (steamValues ?? [])
            let bangumiFailed = bangumiValues == nil
                && !externalIDs.bangumiIDs.isEmpty
            let steamFailed = steamValues == nil
                && !externalIDs.steamIDs.isEmpty
                && !selectedLanguages.isEmpty
            if values.isEmpty, bangumiFailed || steamFailed {
                throw URLError(.cannotLoadFromNetwork)
            }
        }
        return Array(
            values
                .sorted { ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }
                .prefix(60)
        )
    }

    func clearCache() {
        pendingCommentRequests.values.forEach { $0.task.cancel() }
        pendingCommentRequests.removeAll()
        bangumiRatings.removeAll(); commentCache.removeAll()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
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
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private func bangumiRating(vndbID: String, forceRefresh: Bool) async -> 统一视觉小说评分? {
        let key = "bangumi_rating_\(vndbID)"
        if !forceRefresh, let value = bangumiRatings[vndbID] { return value }
        if !forceRefresh, let cached: 缓存条目<统一视觉小说评分> = loadCache(key), Date().timeIntervalSince(cached.savedAt) < cacheLifetime {
            bangumiRatings[vndbID] = cached.value; return cached.value
        }
        let accessToken = await Bangumi账户.有效访问令牌()
        var values: [统一视觉小说评分] = []
        for id in 视觉小说外部ID目录.shared.ids(for: vndbID).bangumiIDs {
            guard let url = URL(string: "https://api.bgm.tv/v0/subjects/\(id)"),
                  let data = try? await request(url, accessToken: accessToken),
                  let item = try? JSONDecoder().decode(Bangumi条目.self, from: data),
                  let rating = item.rating,
                  rating.total > 0 else { continue }
            values.append(统一视觉小说评分(score: rating.score, voteCount: rating.total))
        }
        guard !values.isEmpty else { return nil }
        let votes = values.reduce(0) { $0 + ($1.voteCount ?? 0) }
        let score = values.reduce(0) { $0 + $1.score * Double($1.voteCount ?? 0) } / Double(max(votes, 1))
        let result = 统一视觉小说评分(score: score, voteCount: votes)
        bangumiRatings[vndbID] = result
        saveCache(缓存条目(savedAt: Date(), value: result), key: key)
        return result
    }

    private func bangumiComments(vndbID: String) async throws -> [视觉小说评论] {
        let ids = 视觉小说外部ID目录.shared.ids(for: vndbID).bangumiIDs
        guard !ids.isEmpty else { return [] }
        let 访问令牌 = await Bangumi账户.有效访问令牌()
        let requests = ids.compactMap { id -> 评论请求? in
            var components = URLComponents(
                string: "https://next.bgm.tv/p1/subjects/\(id)/comments"
            )
            components?.queryItems = [URLQueryItem(name: "limit", value: "30")]
            guard let url = components?.url else { return nil }
            return 评论请求(
                url: url,
                bangumiID: id,
                steamAppID: nil,
                accessToken: 访问令牌
            )
        }
        let batch = await Self.fetchCommentResponses(requests, using: session)
        try Task.checkCancellation()
        var result: [视觉小说评论] = []
        var decodedResponseCount = 0
        for responseValue in batch.responses {
            guard let id = responseValue.request.bangumiID,
                  let response = try? JSONDecoder().decode(
                      Bangumi评论响应.self,
                      from: responseValue.data
                  ) else { continue }
            decodedResponseCount += 1
            result.append(contentsOf: response.data.compactMap {
                转换Bangumi评论($0, subjectID: id)
            })
        }
        try Self.validateCommentBatch(
            batch,
            decodedResponseCount: decodedResponseCount,
            hasComments: !result.isEmpty
        )
        return result
    }

    private func steamComments(vndbID: String, languages: Set<Steam评论语言>) async throws -> [视觉小说评论] {
        let ids = 视觉小说外部ID目录.shared.ids(for: vndbID).steamIDs
        guard !ids.isEmpty, !languages.isEmpty else { return [] }
        let selectedLanguageCodes = Set(languages.map(\.rawValue))
        let requestLanguages: [String]
        if languages.count == Steam评论语言.allCases.count {
            requestLanguages = ["all"]
        } else {
            requestLanguages = Steam评论语言.allCases
                .filter(languages.contains)
                .map(\.rawValue)
        }
        var requests: [评论请求] = []
        for appID in ids {
            for language in requestLanguages {
                var components = URLComponents(string: "https://store.steampowered.com/appreviews/\(appID)")
                components?.queryItems = [
                    URLQueryItem(name: "json", value: "1"),
                    URLQueryItem(name: "language", value: language),
                    URLQueryItem(name: "purchase_type", value: "all"),
                    URLQueryItem(name: "filter", value: "recent"),
                    URLQueryItem(
                        name: "num_per_page",
                        value: language == "all" ? "100" : "20"
                    )
                ]
                guard let url = components?.url else { continue }
                requests.append(评论请求(url: url, bangumiID: nil, steamAppID: appID))
            }
        }
        let batch = await Self.fetchCommentResponses(requests, using: session)
        try Task.checkCancellation()
        var result: [视觉小说评论] = []
        var decodedResponseCount = 0
        for responseValue in batch.responses {
            guard let appID = responseValue.request.steamAppID,
                  let response = try? JSONDecoder().decode(
                    Steam评论响应.self,
                    from: responseValue.data
                  ),
                  response.success == 1 else { continue }
            decodedResponseCount += 1
            result.append(contentsOf: response.reviews.lazy.filter {
                selectedLanguageCodes.contains($0.language)
            }.map { review in
                视觉小说评论(id: "steam-\(appID)-\(review.recommendationid)", source: .steam, username: review.author.personaname ?? review.author.steamid, avatarURL: review.author.avatar.map { "https://avatars.fastly.steamstatic.com/\($0)_medium.jpg" }, text: review.review, rating: nil, isRecommended: review.voted_up, dateText: self.dateText(forUnixTimestamp: review.timestamp_created), timestamp: review.timestamp_created, language: review.language)
            })
        }
        try Self.validateCommentBatch(
            batch,
            decodedResponseCount: decodedResponseCount,
            hasComments: !result.isEmpty
        )
        return result
    }

    private func 转换Bangumi评论(
        _ 评论: Bangumi评论响应.评论,
        subjectID: Int
    ) -> 视觉小说评论? {
        let 正文 = (评论.comment ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !正文.isEmpty else { return nil }
        let 名称 = [评论.user?.nickname, 评论.user?.username]
            .compactMap { $0 }
            .first { !$0.isEmpty }
            ?? String(评论.user?.id ?? 评论.id)
        return 视觉小说评论(
            id: "bangumi-\(subjectID)-\(评论.id)",
            source: .bangumi,
            username: 名称,
            avatarURL: 评论.user?.avatar?.medium,
            text: 正文,
            rating: 评论.rate.flatMap { $0 > 0 ? $0 : nil },
            isRecommended: nil,
            dateText: 评论.updatedAt.map { dateText(forUnixTimestamp: $0) },
            timestamp: 评论.updatedAt,
            language: nil
        )
    }

    private func dateText(forUnixTimestamp timestamp: Int) -> String {
        Date(timeIntervalSince1970: TimeInterval(timestamp)).formatted(
            date: .abbreviated,
            time: .omitted
        )
    }

    private func stableIdentifier(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func request(
        _ url: URL,
        accessToken: String? = nil
    ) async throws -> Data {
        try await Self.request(
            url,
            using: session,
            accessToken: accessToken
        )
    }

    private nonisolated static func fetchCommentResponses(
        _ requests: [评论请求],
        using session: URLSession,
        maximumConcurrentRequestCount: Int = 12,
        deadline: Duration = .seconds(8)
    ) async -> 评论响应批次 {
        guard !requests.isEmpty else {
            return 评论响应批次(
                responses: [],
                failedRequestCount: 0
            )
        }
        let initialRequestCount = min(maximumConcurrentRequestCount, requests.count)
        return await withTaskGroup(
            of: 评论请求结果.self,
            returning: 评论响应批次.self
        ) { group in
            for request in requests.prefix(initialRequestCount) {
                group.addTask {
                    guard let data = try? await Self.request(
                        request.url,
                        using: session,
                        accessToken: request.accessToken
                    ) else { return .failure }
                    return .response(评论响应(request: request, data: data))
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: deadline)
                } catch {
                    return .deadline
                }
                return .deadline
            }

            var responses: [评论响应] = []
            var nextRequestIndex = initialRequestCount
            var completedRequestCount = 0
            while completedRequestCount < requests.count,
                  let result = await group.next() {
                switch result {
                case .response(let response):
                    responses.append(response)
                    completedRequestCount += 1
                case .failure:
                    completedRequestCount += 1
                case .deadline:
                    group.cancelAll()
                    return 评论响应批次(
                        responses: responses,
                        failedRequestCount: requests.count - responses.count
                    )
                }
                if nextRequestIndex < requests.count {
                    let nextRequest = requests[nextRequestIndex]
                    nextRequestIndex += 1
                    group.addTask {
                        guard let data = try? await Self.request(
                            nextRequest.url,
                            using: session,
                            accessToken: nextRequest.accessToken
                        ) else { return .failure }
                        return .response(
                            评论响应(
                                request: nextRequest,
                                data: data
                            )
                        )
                    }
                }
            }
            group.cancelAll()
            return 评论响应批次(
                responses: responses,
                failedRequestCount: requests.count - responses.count
            )
        }
    }

    private nonisolated static func validateCommentBatch(
        _ batch: 评论响应批次,
        decodedResponseCount: Int,
        hasComments: Bool
    ) throws {
        try Task.checkCancellation()
        guard !batch.responses.isEmpty else {
            throw URLError(.cannotLoadFromNetwork)
        }
        guard decodedResponseCount > 0 else {
            throw URLError(.cannotDecodeContentData)
        }
        if !hasComments, batch.failedRequestCount > 0 {
            throw URLError(.cannotLoadFromNetwork)
        }
    }

    private nonisolated static func request(
        _ url: URL,
        using session: URLSession,
        accessToken: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("JiZPaper/PaperVN/1.6.0 (https://github.com/JiZPaper/PaperVN)", forHTTPHeaderField: "User-Agent")
        if let accessToken {
            request.setValue(
                "Bearer \(accessToken)",
                forHTTPHeaderField: "Authorization"
            )
        }
        let (data, response) = try await PaperVNConnect网络设置.发送请求(
            request,
            session: session
        )
        guard (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func loadCache<Value: Codable>(_ key: String) -> 缓存条目<Value>? {
        guard let data = try? Data(contentsOf: cacheURL(key)) else { return nil }
        return try? JSONDecoder().decode(缓存条目<Value>.self, from: data)
    }

    private func saveCache<Value: Codable>(_ value: 缓存条目<Value>, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: cacheURL(key), options: .atomic)
        enforceCacheLimitIfNeeded()
    }

    private func enforceCacheLimitIfNeeded() {
        guard let maximum = 缓存策略.当前.maximumCacheBytes,
              maximum > 0 else { return }
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
        ) else { return }
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
        for file in files.sorted(by: { $0.date < $1.date }) {
            guard total > maximum else { break }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }

    private func cacheURL(_ key: String) -> URL {
        let safe = key.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        return cacheDirectory.appendingPathComponent(safe + ".json")
    }
}

struct 视觉小说统一评分标签: View {
    let vndbID: String
    let vndbRating: Double?
    let vndbVoteCount: Int?
    var includesVoteCount = false

    @AppStorage(评分数据来源.设置键)
    private var ratingSource = 评分数据来源.combined.rawValue
    @AppStorage("combinedRatingVNDBWeight")
    private var vndbWeight = 0.5
    @State private var rating: 统一视觉小说评分?

    init(
        vndbID: String,
        vndbRating: Double?,
        vndbVoteCount: Int?,
        includesVoteCount: Bool = false
    ) {
        self.vndbID = vndbID
        self.vndbRating = vndbRating
        self.vndbVoteCount = vndbVoteCount
        self.includesVoteCount = includesVoteCount
        let initial = 评分数据来源.current == .bangumi ? nil : vndbRating.map {
            统一视觉小说评分(score: $0 / 10, voteCount: vndbVoteCount)
        }
        _rating = State(initialValue: initial)
    }

    var body: some View {
        Group {
            if let rating {
                HStack(spacing: 2) {
                    Image(systemName: "chart.bar.xaxis")
                    Text(verbatim: includesVoteCount ? rating.detailedText : rating.shortText)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .task(id: "\(vndbID)|\(ratingSource)|\(vndbWeight)") {
            rating = await 视觉小说外部数据服务.shared.rating(
                vndbID: vndbID,
                vndbRating: vndbRating,
                vndbVoteCount: vndbVoteCount
            )
        }
    }
}
