import AuthenticationServices
import Combine
import Foundation
import SwiftUI

/// AniList 使用 OAuth 2.0 隐式授权：只需要 Client ID，令牌直接附在回调地址里，有效期一年。
/// 在 AniList 开发者设置里注册应用时，Redirect URL 填 `papervn://oauth/anilist`。
enum AniListOAuth配置 {
    static let callbackScheme = "papervn"
    static let redirectURI = "papervn://oauth/anilist"
    static let endpoint = URL(string: "https://graphql.anilist.co")!

    static var clientID: String { 平台账户工具.infoValue("AniListClientID", environment: "ANILIST_CLIENT_ID") }
    static var isConfigured: Bool { !clientID.isEmpty }
}

struct AniList用户资料: Codable, Equatable {
    let id: Int
    let name: String
    let avatar: String?
}

private struct AniList凭据: Codable {
    var accessToken: String
    var expiresAt: Date
    var profile: AniList用户资料
}

/// AniList 账户：登录，以及资料库（动画、漫画、轻小说列表）的读写。
@MainActor
final class AniList账户: ObservableObject {
    @Published private(set) var profile: AniList用户资料?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let credentialStore = 钥匙串凭据存储<AniList凭据>(service: "com.jizpaper.PaperVN.anilist-oauth")
    private var credentials: AniList凭据?
    private var pendingState: String?
    private var webAuthenticationTask: Task<Void, Never>?

    init(previewing: Bool = false) {
        guard !previewing else { return }
        do {
            credentials = try credentialStore.read()
            if let credentials, credentials.expiresAt <= .now {
                // 令牌过期后需要重新登录
                credentialStore.delete()
                self.credentials = nil
            }
            profile = credentials?.profile
            isLoggedIn = credentials != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 登录

    func login(using authenticator: WebAuthenticationSession) {
        guard !isAuthenticating else { return }
        guard AniListOAuth配置.isConfigured else {
            errorMessage = 平台账户错误.notConfigured("AniList").localizedDescription
            return
        }
        let state = 平台账户工具.randomString(length: 32)
        var components = URLComponents(string: "https://anilist.co/api/v2/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AniListOAuth配置.clientID),
            URLQueryItem(name: "response_type", value: "token"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { return }
        pendingState = state
        isAuthenticating = true
        errorMessage = nil
        webAuthenticationTask = Task { [weak self] in
            do {
                let callbackURL = try await authenticator.authenticate(
                    using: url,
                    callback: .customScheme(AniListOAuth配置.callbackScheme),
                    preferredBrowserSession: .shared,
                    additionalHeaderFields: [:]
                )
                await self?.handleCallback(callbackURL)
            } catch {
                guard !Task.isCancelled else { return }
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    self?.finishAuthentication()
                } else {
                    self?.finishAuthentication(error: error.localizedDescription)
                }
            }
        }
    }

    func logout() {
        webAuthenticationTask?.cancel()
        credentialStore.delete()
        credentials = nil
        profile = nil
        isLoggedIn = false
        isAuthenticating = false
        errorMessage = nil
    }

    private func handleCallback(_ url: URL) async {
        do {
            // 隐式授权的令牌在 # 后面
            var components = URLComponents()
            components.query = url.fragment ?? URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
            let items = components.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if let error = value("error") {
                throw 平台账户错误.service("AniList", value("error_description") ?? error)
            }
            // AniList 不一定原样带回 state；带回时必须一致
            if let state = value("state"), state != pendingState {
                throw 平台账户错误.loginIncomplete("AniList")
            }
            guard let token = value("access_token"), !token.isEmpty else {
                throw 平台账户错误.loginIncomplete("AniList")
            }
            let expiresIn = value("expires_in").flatMap(TimeInterval.init) ?? 31_536_000
            let profile = try await Self.viewer(accessToken: token)
            let newCredentials = AniList凭据(
                accessToken: token,
                expiresAt: Date().addingTimeInterval(expiresIn),
                profile: profile
            )
            try credentialStore.save(newCredentials)
            credentials = newCredentials
            self.profile = profile
            isLoggedIn = true
            finishAuthentication()
        } catch {
            finishAuthentication(error: error.localizedDescription)
        }
    }

    private func finishAuthentication(error: String? = nil) {
        pendingState = nil
        webAuthenticationTask = nil
        isAuthenticating = false
        errorMessage = error
    }

    private func accessToken() throws -> String {
        guard let credentials, credentials.expiresAt > .now else { throw 平台账户错误.notLoggedIn("AniList") }
        return credentials.accessToken
    }

    private static func viewer(accessToken: String) async throws -> AniList用户资料 {
        struct 响应: Decodable {
            struct 数据: Decodable {
                struct 用户: Decodable {
                    struct 头像: Decodable { let medium: String? }
                    let id: Int
                    let name: String
                    let avatar: 头像?
                }
                let Viewer: 用户
            }
            let data: 数据
        }
        let data = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: accessToken,
            query: "query { Viewer { id name avatar { medium } } }"
        )
        guard let viewer = try? JSONDecoder().decode(响应.self, from: data).data.Viewer else {
            throw 平台账户错误.invalidResponse("AniList")
        }
        return AniList用户资料(id: viewer.id, name: viewer.name, avatar: viewer.avatar?.medium)
    }

    // MARK: 资料库

    /// 读取动画与漫画（包括轻小说）列表。
    func 读取资料库() async throws -> [平台资料库记录] {
        async let anime = fetchList(type: "ANIME")
        async let manga = fetchList(type: "MANGA")
        return try await anime + manga
    }

    private func fetchList(type: String) async throws -> [平台资料库记录] {
        let token = try accessToken()
        guard let userID = profile?.id else { throw 平台账户错误.notLoggedIn("AniList") }
        let query = """
        query ($userId: Int, $type: MediaType, $chunk: Int) {
          MediaListCollection(userId: $userId, type: $type, chunk: $chunk, perChunk: 500) {
            hasNextChunk
            lists { entries {
              status score(format: POINT_100) progress updatedAt
              startedAt { year month day } completedAt { year month day }
              media {
                id idMal format episodes chapters averageScore countryOfOrigin
                title { romaji native english }
                coverImage { large }
                startDate { year month day }
              }
            } }
          }
        }
        """
        var results: [平台资料库记录] = []
        var chunk = 1
        while true {
            try Task.checkCancellation()
            let data = try await 平台账户工具.graphQL(
                endpoint: AniListOAuth配置.endpoint,
                platform: "AniList",
                accessToken: token,
                query: query,
                variables: ["userId": userID, "type": type, "chunk": chunk]
            )
            guard let page = try? JSONDecoder().decode(AniList列表响应.self, from: data).data.MediaListCollection else {
                throw 平台账户错误.invalidResponse("AniList")
            }
            results += page.lists.flatMap(\.entries).compactMap { $0.记录(type: type) }
            guard page.hasNextChunk == true else { break }
            chunk += 1
        }
        return results
    }

    /// 新增或修改一条记录。
    /// `清除空值` 为真时（在 App 里编辑），没有评分、进度表示清除；否则不改动 AniList 上的值。
    func 保存(
        mediaID: Int,
        快照 value: 同步快照,
        日期: (start: String?, finish: String?)? = nil,
        清除空值: Bool = false
    ) async throws {
        var variables: [String: Any] = [
            "mediaId": mediaID,
            "status": Self.statusValue(value.状态),
        ]
        if let score = value.评分 ?? (清除空值 ? 0 : nil) { variables["scoreRaw"] = score }
        if let progress = value.进度 { variables["progress"] = progress }
        if let 日期 {
            // 各部分为 null 表示清除日期
            variables["startedAt"] = Self.模糊日期(日期.start)
            variables["completedAt"] = Self.模糊日期(日期.finish)
        }
        _ = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: try accessToken(),
            query: """
            mutation ($mediaId: Int, $status: MediaListStatus, $scoreRaw: Int, $progress: Int,
                      $startedAt: FuzzyDateInput, $completedAt: FuzzyDateInput) {
              SaveMediaListEntry(mediaId: $mediaId, status: $status, scoreRaw: $scoreRaw, progress: $progress,
                                 startedAt: $startedAt, completedAt: $completedAt) { id }
            }
            """,
            variables: variables
        )
    }

    /// 删除一条记录。AniList 按列表条目 ID 删除，所以先查出条目 ID。
    func 删除(mediaID: Int) async throws {
        let token = try accessToken()
        guard let userID = profile?.id else { throw 平台账户错误.notLoggedIn("AniList") }
        struct 响应: Decodable {
            struct 数据: Decodable { struct 条目: Decodable { let id: Int }; let MediaList: 条目? }
            let data: 数据?
        }
        let entryID: Int
        do {
            let data = try await 平台账户工具.graphQL(
                endpoint: AniListOAuth配置.endpoint,
                platform: "AniList",
                accessToken: token,
                query: "query ($userId: Int, $mediaId: Int) { MediaList(userId: $userId, mediaId: $mediaId) { id } }",
                variables: ["userId": userID, "mediaId": mediaID]
            )
            guard let id = try? JSONDecoder().decode(响应.self, from: data).data?.MediaList?.id else { return }
            entryID = id
        } catch 平台账户错误.service(_, let message) where message?.localizedCaseInsensitiveContains("not found") == true {
            // 已经不在列表里
            return
        }
        _ = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: token,
            query: "mutation ($id: Int) { DeleteMediaListEntry(id: $id) { deleted } }",
            variables: ["id": entryID]
        )
    }

    /// 按 MAL ID 查找 AniList 作品 ID，每次最多 50 个。
    func 查找(malIDs: [Int], 类型 type: 作品类型) async throws -> [Int: Int] {
        var result: [Int: Int] = [:]
        struct 响应: Decodable {
            struct 数据: Decodable {
                struct 页: Decodable { struct 作品: Decodable { let id: Int; let idMal: Int? }; let media: [作品] }
                let Page: 页
            }
            let data: 数据
        }
        for start in stride(from: 0, to: malIDs.count, by: 50) {
            let ids = Array(malIDs[start..<min(start + 50, malIDs.count)])
            let data = try await 平台账户工具.graphQL(
                endpoint: AniListOAuth配置.endpoint,
                platform: "AniList",
                accessToken: try? accessToken(),
                query: """
                query ($ids: [Int], $type: MediaType) {
                  Page(perPage: 50) { media(idMal_in: $ids, type: $type) { id idMal } }
                }
                """,
                variables: ["ids": ids, "type": type == .anime ? "ANIME" : "MANGA"]
            )
            guard let page = try? JSONDecoder().decode(响应.self, from: data).data.Page else {
                throw 平台账户错误.invalidResponse("AniList")
            }
            for media in page.media {
                if let malID = media.idMal { result[malID] = media.id }
            }
        }
        return result
    }

    private static func 模糊日期(_ value: String?) -> [String: Any] {
        let parts = (value ?? "").split(separator: "-").map { Int($0) }
        func part(_ index: Int) -> Any { index < parts.count ? (parts[index] as Any? ?? NSNull()) : NSNull() }
        return ["year": part(0), "month": part(1), "day": part(2)]
    }

    private static func statusValue(_ status: 资料库状态) -> String {
        switch status {
        case .inProgress: "CURRENT"
        case .completed: "COMPLETED"
        case .onHold: "PAUSED"
        case .dropped: "DROPPED"
        case .planning: "PLANNING"
        }
    }

    fileprivate static func status(from value: String?) -> 资料库状态? {
        switch value {
        case "CURRENT", "REPEATING": .inProgress
        case "COMPLETED": .completed
        case "PAUSED": .onHold
        case "DROPPED": .dropped
        case "PLANNING": .planning
        default: nil
        }
    }
}

private struct AniList列表响应: Decodable {
    struct 数据: Decodable { let MediaListCollection: 集合? }
    struct 集合: Decodable {
        let hasNextChunk: Bool?
        let lists: [列表]
    }
    struct 列表: Decodable { let entries: [条目] }
    struct 日期: Decodable { let year: Int?; let month: Int?; let day: Int? }
    struct 条目: Decodable {
        struct 作品: Decodable {
            struct 标题: Decodable { let romaji: String?; let native: String?; let english: String? }
            struct 封面: Decodable { let large: String? }
            let id: Int
            let idMal: Int?
            let format: String?
            let episodes: Int?
            let chapters: Int?
            let averageScore: Int?
            let countryOfOrigin: String?
            let title: 标题?
            let coverImage: 封面?
            let startDate: 日期?
        }
        let status: String?
        let score: Double?
        let progress: Int?
        let updatedAt: Int?
        let startedAt: 日期?
        let completedAt: 日期?
        let media: 作品

        func 记录(type: String) -> 平台资料库记录? {
            guard let status = AniList账户.status(from: status) else { return nil }
            let kind: 作品类型 = type == "ANIME" ? .anime : (media.format == "NOVEL" ? .lightNovel : .manga)
            let total = kind == .anime ? media.episodes : media.chapters
            func text(_ date: 日期?) -> String? {
                平台账户工具.日期文本(year: date?.year, month: date?.month, day: date?.day)
            }
            return 平台资料库记录(
                平台: .aniList,
                平台ID: String(media.id),
                类型: kind,
                malID: media.idMal,
                标题: media.title?.romaji ?? media.title?.native ?? String(media.id),
                日文标题: media.title?.native,
                封面地址: media.coverImage?.large,
                快照: 同步快照(状态: status, 评分: score.map { Int($0.rounded()) }, 进度: progress),
                总数: (total ?? 0) > 0 ? total : nil,
                平均评分: media.averageScore.map(Double.init),
                发行日期: text(media.startDate),
                开始日期: text(startedAt),
                完成日期: text(completedAt),
                修改时间: updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                多语言标题: 作品多语言标题.生成(
                    原名: media.title?.native,
                    原名语言: 作品多语言标题.语言(国家: media.countryOfOrigin),
                    罗马字: media.title?.romaji,
                    英文: media.title?.english
                )
            )
        }
    }
    let data: 数据
}

extension AniList账户 {
    /// 手动匹配时搜索作品；输入作品编号或作品页面的链接时直接读取这部作品。
    func 搜索候选(类型 type: 作品类型, 关键词 query: String) async throws -> [匹配候选] {
        struct 响应: Decodable {
            struct 数据: Decodable { struct 页: Decodable { let media: [作品] }; let Page: 页 }
            struct 作品: Decodable {
                struct 标题: Decodable { let native: String?; let romaji: String?; let english: String? }
                struct 日期: Decodable { let year: Int? }
                struct 封面: Decodable { let medium: String? }
                let id: Int
                let title: 标题
                let startDate: 日期?
                let coverImage: 封面?
                let format: String?
                let countryOfOrigin: String?
            }
            let data: 数据
        }
        let kind = type == .anime ? "anime" : "manga"
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let id = 匹配候选编号(text, 链接: "anilist.co/\(kind)/")
        let data = try await 平台账户工具.graphQL(
            endpoint: AniListOAuth配置.endpoint,
            platform: "AniList",
            accessToken: try? accessToken(),
            query: """
            query ($search: String, $id: Int, $type: MediaType) {
              Page(perPage: 20) {
                media(search: $search, id: $id, type: $type) {
                  id title { native romaji english } startDate { year } coverImage { medium } format countryOfOrigin
                }
              }
            }
            """,
            variables: id.map { ["id": $0, "type": kind.uppercased()] } ?? ["search": text, "type": kind.uppercased()]
        )
        guard let media = try? JSONDecoder().decode(响应.self, from: data).data.Page.media else {
            throw 平台账户错误.invalidResponse("AniList")
        }
        return media.map { item in
            let native = item.title.native.flatMap { $0.isEmpty ? nil : $0 }
            let romaji = item.title.romaji.flatMap { $0.isEmpty ? nil : $0 }
            let main = native ?? romaji ?? item.title.english ?? String(item.id)
            let mainLanguage = native != nil ? 作品多语言标题.语言(国家: item.countryOfOrigin) : romaji != nil ? "ja-Latn" : "en"
            let other = native != nil ? (romaji ?? item.title.english) : (romaji != nil ? item.title.english : nil)
            return 匹配候选(
                id: String(item.id), 标题: main, 标题语言: mainLanguage,
                其他标题: other, 其他标题语言: other == romaji ? "ja-Latn" : "en",
                年份: item.startDate?.year,
                封面: item.coverImage?.medium.flatMap(URL.init(string:)),
                种类: item.format?.replacingOccurrences(of: "_", with: " ")
            )
        }
    }
}
