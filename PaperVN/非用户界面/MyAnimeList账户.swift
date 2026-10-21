import AuthenticationServices
import Combine
import Foundation
import Security
import SwiftUI

/// MyAnimeList 使用 OAuth 2.0 PKCE。App 在 MAL 注册为 iOS 类型时没有 client secret，
/// 所以只需要 Client ID，不会有泄露问题。
nonisolated enum MyAnimeListOAuth配置 {
    static let callbackScheme = "papervn"
    static let redirectURI = "papervn://oauth/mal"

    static var clientID: String {
        if let value = ProcessInfo.processInfo.environment["MAL_CLIENT_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return (Bundle.main.object(forInfoDictionaryKey: "MALClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isConfigured: Bool { !clientID.isEmpty }
}

struct MyAnimeList用户资料: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let picture: String?
    let joinedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, picture
        case joinedAt = "joined_at"
    }
}

private struct MyAnimeListOAuth令牌: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

private struct MyAnimeListOAuth凭据: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var profile: MyAnimeList用户资料?
}

enum MyAnimeList错误: LocalizedError {
    case notConfigured
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case notLoggedIn
    case service(Int, String?)
    case invalidResponse
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            String(localized: "需要先在App配置中设置MALClientID。")
        case .invalidCallback, .stateMismatch, .missingAuthorizationCode:
            String(localized: "登录未完成，请重试。")
        case .notLoggedIn:
            String(localized: "请重新登录。")
        case let .service(status, message):
            message ?? String(localized: "请求失败（\(status)）。")
        case .invalidResponse:
            String(localized: "返回的内容无效。")
        case let .keychain(status):
            String(localized: "无法读取登录凭据（\(status)）。")
        }
    }
}

private struct MyAnimeListOAuth凭据存储 {
    private let service = "com.jizpaper.PaperVN.mal-oauth"
    private let account = "session"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> MyAnimeListOAuth凭据? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw MyAnimeList错误.keychain(status)
        }
        return try JSONDecoder().decode(MyAnimeListOAuth凭据.self, from: data)
    }

    func save(_ credentials: MyAnimeListOAuth凭据) throws {
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(credentials),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw MyAnimeList错误.keychain(updateStatus) }
        var newItem = query
        values.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw MyAnimeList错误.keychain(addStatus) }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// MyAnimeList 账户：登录、令牌刷新，以及资料库（动画、漫画列表）的读写。
@MainActor
final class MyAnimeList账户: ObservableObject {
    @Published private(set) var profile: MyAnimeList用户资料?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let credentialStore = MyAnimeListOAuth凭据存储()
    private var credentials: MyAnimeListOAuth凭据?
    private var pendingState: String?
    private var pendingVerifier: String?
    private var webAuthenticationTask: Task<Void, Never>?

    init(previewing: Bool = false) {
        guard !previewing else { return }
        do {
            credentials = try credentialStore.read()
            profile = credentials?.profile
            isLoggedIn = credentials != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: 登录

    func login(using authenticator: WebAuthenticationSession) {
        guard !isAuthenticating else { return }
        guard MyAnimeListOAuth配置.isConfigured else {
            errorMessage = MyAnimeList错误.notConfigured.localizedDescription
            return
        }
        let state = Self.randomString(length: 32)
        // MAL 只支持 plain 方式的 PKCE：code_challenge 与 code_verifier 相同
        let verifier = Self.randomString(length: 96)
        var components = URLComponents(string: "https://myanimelist.net/v1/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: MyAnimeListOAuth配置.clientID),
            URLQueryItem(name: "redirect_uri", value: MyAnimeListOAuth配置.redirectURI),
            URLQueryItem(name: "code_challenge", value: verifier),
            URLQueryItem(name: "code_challenge_method", value: "plain"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else { return }
        pendingState = state
        pendingVerifier = verifier
        isAuthenticating = true
        errorMessage = nil
        webAuthenticationTask = Task { [weak self] in
            do {
                let callbackURL = try await authenticator.authenticate(
                    using: url,
                    callback: .customScheme(MyAnimeListOAuth配置.callbackScheme),
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
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            guard value("state") == pendingState, let verifier = pendingVerifier else {
                throw MyAnimeList错误.stateMismatch
            }
            if let error = value("error") {
                throw MyAnimeList错误.service(400, value("message") ?? value("hint") ?? error)
            }
            guard let code = value("code"), !code.isEmpty else {
                throw MyAnimeList错误.missingAuthorizationCode
            }
            let token = try await Self.requestToken([
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": MyAnimeListOAuth配置.redirectURI,
            ])
            var newCredentials = MyAnimeListOAuth凭据(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                profile: nil
            )
            newCredentials.profile = try await Self.get(
                "users/@me",
                query: [URLQueryItem(name: "fields", value: "joined_at")],
                accessToken: token.accessToken,
                as: MyAnimeList用户资料.self
            )
            try credentialStore.save(newCredentials)
            credentials = newCredentials
            profile = newCredentials.profile
            isLoggedIn = true
            finishAuthentication()
        } catch {
            finishAuthentication(error: error.localizedDescription)
        }
    }

    private func finishAuthentication(error: String? = nil) {
        pendingState = nil
        pendingVerifier = nil
        webAuthenticationTask = nil
        isAuthenticating = false
        errorMessage = error
    }

    /// 有效的访问令牌；快过期时先刷新。
    func validAccessToken() async throws -> String {
        guard var credentials else { throw MyAnimeList错误.notLoggedIn }
        guard credentials.expiresAt <= Date().addingTimeInterval(60) else {
            return credentials.accessToken
        }
        let token = try await Self.requestToken([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
        ])
        credentials.accessToken = token.accessToken
        credentials.refreshToken = token.refreshToken
        credentials.expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
        try credentialStore.save(credentials)
        self.credentials = credentials
        return credentials.accessToken
    }

    // MARK: 资料库

    /// 读取用户的动画列表。
    func animeList() async throws -> [MyAnimeList列表项] {
        try await fetchList(
            path: "users/@me/animelist",
            fields: "list_status,num_episodes,mean,num_scoring_users,start_date,media_type,alternative_titles,main_picture",
            kind: .anime
        )
    }

    /// 读取用户的漫画列表（包括轻小说）。
    func mangaList() async throws -> [MyAnimeList列表项] {
        try await fetchList(
            path: "users/@me/mangalist",
            fields: "list_status,num_chapters,num_volumes,mean,num_scoring_users,start_date,media_type,alternative_titles,main_picture",
            kind: .manga
        )
    }

    private func fetchList(path: String, fields: String, kind: MyAnimeList列表项.种类) async throws -> [MyAnimeList列表项] {
        let accessToken = try await validAccessToken()
        var results: [MyAnimeList列表项] = []
        var offset = 0
        while true {
            try Task.checkCancellation()
            let page = try await Self.get(
                path,
                query: [
                    URLQueryItem(name: "fields", value: fields),
                    URLQueryItem(name: "limit", value: "1000"),
                    URLQueryItem(name: "offset", value: String(offset)),
                    URLQueryItem(name: "nsfw", value: "true"),
                ],
                accessToken: accessToken,
                as: MyAnimeList列表页.self
            )
            results += page.data.map { MyAnimeList列表项(kind: kind, raw: $0) }
            guard page.paging?.next != nil, !page.data.isEmpty else { break }
            offset += page.data.count
        }
        return results
    }

    /// 修改一条记录的状态、评分与进度。
    func updateListStatus(
        kind: MyAnimeList列表项.种类,
        id: Int,
        status: 资料库状态,
        score: Int?,
        progress: Int?,
        dates: (start: String?, finish: String?)? = nil
    ) async throws {
        let accessToken = try await validAccessToken()
        var values = ["status": kind.statusValue(status)]
        // MAL 只有 0–10 的整数评分，按四舍五入换算；没有传评分时不改动 MAL 上的评分
        if let score {
            values["score"] = String(min(max(Int((Double(score) / 10).rounded()), 0), 10))
        }
        if let progress {
            values[kind == .anime ? "num_watched_episodes" : "num_chapters_read"] = String(progress)
        }
        if let dates {
            // 空字符串表示清除日期
            values["start_date"] = dates.start ?? ""
            values["finish_date"] = dates.finish ?? ""
        }
        var request = URLRequest(url: URL(string: "https://api.myanimelist.net/v2/\(kind.rawValue)/\(id)/my_list_status")!)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(values)
        _ = try await Self.perform(request)
    }

    func deleteListItem(kind: MyAnimeList列表项.种类, id: Int) async throws {
        let accessToken = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://api.myanimelist.net/v2/\(kind.rawValue)/\(id)/my_list_status")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await Self.perform(request)
    }

    // MARK: 网络

    private static func requestToken(_ values: [String: String]) async throws -> MyAnimeListOAuth令牌 {
        var values = values
        values["client_id"] = MyAnimeListOAuth配置.clientID
        var request = URLRequest(url: URL(string: "https://myanimelist.net/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(values)
        let data = try await perform(request)
        guard let token = try? JSONDecoder().decode(MyAnimeListOAuth令牌.self, from: data) else {
            throw MyAnimeList错误.invalidResponse
        }
        return token
    }

    private static func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem],
        accessToken: String?,
        as type: T.Type
    ) async throws -> T {
        var components = URLComponents(string: "https://api.myanimelist.net/v2/\(path)")!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            // 没有登录时用 Client ID 读取公开数据（搜索）
            request.setValue(MyAnimeListOAuth配置.clientID, forHTTPHeaderField: "X-MAL-CLIENT-ID")
        }
        let data = try await perform(request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MyAnimeList错误.invalidResponse
        }
    }

    private static func perform(_ request: URLRequest) async throws -> Data {
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            struct 错误内容: Decodable { let error: String?; let message: String? }
            let body = try? JSONDecoder().decode(错误内容.self, from: data)
            throw MyAnimeList错误.service(status, body?.message ?? body?.error)
        }
        return data
    }

    private static func formBody(_ values: [String: String]) -> Data? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return values
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private static func randomString(length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }
}

// MARK: - 列表数据

private struct MyAnimeList列表页: Decodable {
    struct 项: Decodable {
        let node: 作品
        let listStatus: 状态?

        enum CodingKeys: String, CodingKey {
            case node
            case listStatus = "list_status"
        }
    }

    struct 作品: Decodable {
        struct 图片: Decodable { let medium: String?; let large: String? }
        struct 别名: Decodable { let en: String?; let ja: String? }

        let id: Int
        let title: String
        let mainPicture: 图片?
        let alternativeTitles: 别名?
        let mean: Double?
        let startDate: String?
        let mediaType: String?
        let numEpisodes: Int?
        let numChapters: Int?
        let numVolumes: Int?

        enum CodingKeys: String, CodingKey {
            case id, title, mean
            case mainPicture = "main_picture"
            case alternativeTitles = "alternative_titles"
            case startDate = "start_date"
            case mediaType = "media_type"
            case numEpisodes = "num_episodes"
            case numChapters = "num_chapters"
            case numVolumes = "num_volumes"
        }
    }

    struct 状态: Decodable {
        let status: String?
        let score: Int?
        let numEpisodesWatched: Int?
        let numChaptersRead: Int?
        let startDate: String?
        let finishDate: String?
        let updatedAt: String?

        enum CodingKeys: String, CodingKey {
            case status, score
            case numEpisodesWatched = "num_episodes_watched"
            case numChaptersRead = "num_chapters_read"
            case startDate = "start_date"
            case finishDate = "finish_date"
            case updatedAt = "updated_at"
        }
    }

    struct 分页: Decodable { let next: String? }

    let data: [项]
    let paging: 分页?
}

/// MAL 列表里的一条记录，已经整理成本地资料库需要的字段。
struct MyAnimeList列表项: Sendable {
    enum 种类: String, Sendable {
        case anime
        case manga

        func statusValue(_ status: 资料库状态) -> String {
            switch (self, status) {
            case (.anime, .inProgress): "watching"
            case (.manga, .inProgress): "reading"
            case (_, .completed): "completed"
            case (_, .onHold): "on_hold"
            case (_, .dropped): "dropped"
            case (.anime, .planning): "plan_to_watch"
            case (.manga, .planning): "plan_to_read"
            }
        }

        static func status(from value: String?) -> 资料库状态? {
            switch value {
            case "watching", "reading": .inProgress
            case "completed": .completed
            case "on_hold": .onHold
            case "dropped": .dropped
            case "plan_to_watch", "plan_to_read": .planning
            default: nil
            }
        }
    }

    let kind: 种类
    let id: Int
    let 类型: 作品类型
    let 标题: String
    let 日文标题: String?
    let 英文标题: String?
    let 封面地址: String?
    let 状态: 资料库状态?
    /// 0–10，0表示没有评分。
    let 评分: Int
    let 进度: Int
    let 总数: Int?
    let 平均评分: Double?
    let 发行日期: String?
    let 开始日期: String?
    let 完成日期: String?
    let 修改时间: Date?

    fileprivate init(kind: 种类, raw: MyAnimeList列表页.项) {
        self.kind = kind
        id = raw.node.id
        switch kind {
        case .anime:
            类型 = .anime
        case .manga:
            // MAL 把轻小说也放在漫画列表里，用 media_type 区分
            类型 = ["light_novel", "novel"].contains(raw.node.mediaType ?? "") ? .lightNovel : .manga
        }
        标题 = raw.node.title
        日文标题 = raw.node.alternativeTitles?.ja
        英文标题 = raw.node.alternativeTitles?.en
        封面地址 = raw.node.mainPicture?.large ?? raw.node.mainPicture?.medium
        状态 = 种类.status(from: raw.listStatus?.status)
        评分 = raw.listStatus?.score ?? 0
        进度 = kind == .anime
            ? raw.listStatus?.numEpisodesWatched ?? 0
            : raw.listStatus?.numChaptersRead ?? 0
        let total = kind == .anime ? raw.node.numEpisodes : raw.node.numChapters
        总数 = (total ?? 0) > 0 ? total : nil
        平均评分 = raw.node.mean
        发行日期 = raw.node.startDate
        开始日期 = raw.listStatus?.startDate
        完成日期 = raw.listStatus?.finishDate
        修改时间 = raw.listStatus?.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
    }
}

extension MyAnimeList列表项 {
    /// 整理成 PaperVN Sync 统一的平台记录。没有状态的记录不参与同步。
    var 平台记录: 平台资料库记录? {
        guard let 状态 else { return nil }
        return 平台资料库记录(
            平台: .myAnimeList,
            平台ID: String(id),
            类型: 类型,
            malID: id,
            标题: 标题,
            日文标题: 日文标题,
            封面地址: 封面地址,
            快照: 同步快照(状态: 状态, 评分: 评分 * 10, 进度: 进度),
            总数: 总数,
            平均评分: 平均评分.map { $0 * 10 },
            发行日期: 发行日期,
            开始日期: 开始日期,
            完成日期: 完成日期,
            修改时间: 修改时间,
            // MAL 的 title 是罗马字，alternative_titles.ja 是原名：韩国、中国作品也放在这里，语言按作品映射（AniList 的出品国家）改正
            多语言标题: 作品多语言标题.生成(原名: 日文标题, 原名语言: 作品映射.原名语言(类型, malID: id) ?? "ja", 罗马字: 标题, 英文: 英文标题)
        )
    }
}

extension MyAnimeList账户 {
    /// 手动匹配时搜索作品；输入作品编号或作品页面的链接时直接读取这部作品。
    func 搜索候选(类型 type: 作品类型, 关键词 query: String) async throws -> [匹配候选] {
        struct 作品: Decodable {
            struct 别名: Decodable { let en: String?; let ja: String? }
            struct 图片: Decodable { let medium: String? }
            let id: Int
            let title: String
            let alternativeTitles: 别名?
            let startDate: String?
            let mediaType: String?
            let mainPicture: 图片?
            enum CodingKeys: String, CodingKey {
                case id, title
                case alternativeTitles = "alternative_titles"
                case startDate = "start_date"
                case mediaType = "media_type"
                case mainPicture = "main_picture"
            }
            var 候选: 匹配候选 {
                // MAL 的 title 是罗马字，ja 字段是原名
                let native = alternativeTitles?.ja.flatMap { $0.isEmpty || $0 == title ? nil : $0 }
                return 匹配候选(
                    id: String(id),
                    标题: native ?? title, 标题语言: native == nil ? "ja-Latn" : "ja",
                    其他标题: native == nil ? nil : title, 其他标题语言: "ja-Latn",
                    年份: startDate.flatMap { Int($0.prefix(4)) },
                    封面: mainPicture?.medium.flatMap(URL.init(string:)),
                    种类: mediaType.map { $0.replacingOccurrences(of: "_", with: " ").uppercased() }
                )
            }
        }
        struct 结果: Decodable { struct 项: Decodable { let node: 作品 }; let data: [项] }
        let kind = type == .anime ? "anime" : "manga"
        let fields = URLQueryItem(name: "fields", value: "alternative_titles,start_date,media_type,main_picture")
        // 搜索页没有登录 MAL 时也能搜索
        let accessToken = isLoggedIn ? try await validAccessToken() : nil
        guard accessToken != nil || MyAnimeListOAuth配置.isConfigured else { throw 平台账户错误.notLoggedIn("MyAnimeList") }
        if let id = 匹配候选编号(query, 链接: "myanimelist.net/\(kind)/") {
            let work = try await Self.get("\(kind)/\(id)", query: [fields], accessToken: accessToken, as: 作品.self)
            return [work.候选]
        }
        let text = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(64))
        guard text.count >= 3 else { return [] }
        let found = try await Self.get(kind, query: [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "limit", value: "20"),
            fields,
            URLQueryItem(name: "nsfw", value: "true"),
        ], accessToken: accessToken, as: 结果.self)
        return found.data.map(\.node.候选)
    }
}

#if DEBUG
extension MyAnimeList账户 {
    /// 预览用：已登录的账户，不读写钥匙串。
    static func 预览已登录(_ profile: MyAnimeList用户资料) -> MyAnimeList账户 {
        let account = MyAnimeList账户(previewing: true)
        account.profile = profile
        account.isLoggedIn = true
        return account
    }
}
#endif
