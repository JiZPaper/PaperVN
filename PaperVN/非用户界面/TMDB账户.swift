import AuthenticationServices
import Combine
import Foundation
import SwiftUI

/// TMDB（The Movie Database）。PaperVN 不内置 TMDB 的 API 令牌：用户在自己的 TMDB 账户里申请 API，
/// 把“API 读取访问令牌”填进 App（存进钥匙串）。登录使用 v4 的用户授权：用这个令牌申请请求令牌，
/// 用户在 TMDB 网站上批准后换成用户访问令牌，再转换成 v3 的会话，用来写入评分和想看列表。
nonisolated enum TMDB配置 {
    static let callbackScheme = "papervn"
    static let redirectURI = "papervn://oauth/tmdb"
    static let apiBase = URL(string: "https://api.themoviedb.org")!

    private static let 令牌存储 = 钥匙串凭据存储<String>(service: "com.jizpaper.PaperVN.tmdb-token")
    private static let 锁 = NSLock()
    nonisolated(unsafe) private static var 缓存: String??

    /// 用户填写的 API 读取访问令牌。
    static var readAccessToken: String {
        锁.lock(); defer { 锁.unlock() }
        if case let .some(value) = 缓存 { return value ?? "" }
        let value = (try? 令牌存储.read()) ?? nil
        缓存 = .some(value)
        return value ?? ""
    }

    static var isConfigured: Bool { !readAccessToken.isEmpty }

    static func 保存令牌(_ token: String?) throws {
        锁.lock(); defer { 锁.unlock() }
        let value = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value, !value.isEmpty {
            try 令牌存储.save(value)
            缓存 = .some(value)
        } else {
            令牌存储.delete()
            缓存 = .some(nil)
        }
    }

    /// TMDB 的界面语言代码，用来读取本地化的简介和标题。
    static var 语言: String {
        let language = Locale.preferredLanguages.first ?? "en"
        if language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW") || language.hasPrefix("zh-HK") { return "zh-TW" }
        if language.hasPrefix("zh") { return "zh-CN" }
        for code in ["ja", "ko", "de", "pl", "en"] where language.hasPrefix(code) {
            return ["ja": "ja-JP", "ko": "ko-KR", "de": "de-DE", "pl": "pl-PL", "en": "en-US"][code]!
        }
        return "en-US"
    }

    /// 发送 TMDB API 请求。开启 PaperVN Connect 时经由转发服务器，失败时改为直连。
    static func 请求(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        bearer: String? = nil
    ) async throws -> Data {
        var components = URLComponents(url: apiBase.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(bearer ?? readAccessToken)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json;charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await PaperVNConnect网络设置.发送请求(request, session: .shared)
        switch response.statusCode {
        case 200...299:
            return data
        case 401:
            throw 平台账户错误.notLoggedIn("TMDB")
        case 429:
            throw 平台账户错误.rateLimited("TMDB", 10)
        default:
            struct 错误: Decodable { let status_message: String? }
            throw 平台账户错误.service("TMDB", (try? JSONDecoder().decode(错误.self, from: data))?.status_message)
        }
    }
}

struct TMDB用户资料: Codable, Equatable {
    let id: Int
    let username: String
    let name: String?
    let avatar: String?
}

private struct TMDB凭据: Codable {
    /// v4 用户访问令牌，读取列表时使用。
    var accessToken: String
    /// v4 的账户 ID（字符串）。
    var accountObjectID: String
    /// v3 会话，写入评分和想看列表时使用。
    var sessionID: String
    var profile: TMDB用户资料
}

/// TMDB 账户。TMDB 没有“在看”“看过”这样的状态和进度，只同步“想看”（想看列表）与评分：
/// 想看列表里的作品是“计划观看”，只评过分的作品记为“看过”。没有评分、又不是“计划观看”的作品无法记录在 TMDB 上。
@MainActor
final class TMDB账户: ObservableObject {
    @Published private(set) var profile: TMDB用户资料?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let credentialStore = 钥匙串凭据存储<TMDB凭据>(service: "com.jizpaper.PaperVN.tmdb")
    private var credentials: TMDB凭据?
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

    /// 先保存用户填写的 API 读取访问令牌，再到 TMDB 网站上批准登录。
    func login(令牌 token: String, using authenticator: WebAuthenticationSession) {
        guard !isAuthenticating else { return }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isAuthenticating = true
        errorMessage = nil
        webAuthenticationTask = Task { [weak self] in
            do {
                try TMDB配置.保存令牌(trimmed)
                struct 请求令牌: Decodable { let request_token: String }
                let data = try await TMDB配置.请求("4/auth/request_token", method: "POST", body: ["redirect_to": TMDB配置.redirectURI])
                let requestToken = try JSONDecoder().decode(请求令牌.self, from: data).request_token
                var components = URLComponents(string: "https://www.themoviedb.org/auth/access")!
                components.queryItems = [URLQueryItem(name: "request_token", value: requestToken)]
                _ = try await authenticator.authenticate(
                    using: components.url!,
                    callback: .customScheme(TMDB配置.callbackScheme),
                    preferredBrowserSession: .shared,
                    additionalHeaderFields: [:]
                )
                try await self?.finishLogin(requestToken: requestToken)
            } catch {
                guard !Task.isCancelled else { return }
                // 没有登录成功时不留下令牌，免得一个无效的令牌一直被用来读取详情
                if self?.isLoggedIn != true { try? TMDB配置.保存令牌(nil) }
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    self?.finishAuthentication()
                } else if case .notLoggedIn = error as? 平台账户错误 {
                    self?.finishAuthentication(error: String(localized: "API读取访问令牌无效。"))
                } else {
                    self?.finishAuthentication(error: error.localizedDescription)
                }
            }
        }
    }

    func logout() {
        webAuthenticationTask?.cancel()
        if let token = credentials?.accessToken {
            Task { _ = try? await TMDB配置.请求("4/auth/access_token", method: "DELETE", body: ["access_token": token]) }
        }
        credentialStore.delete()
        try? TMDB配置.保存令牌(nil)
        credentials = nil
        profile = nil
        isLoggedIn = false
        isAuthenticating = false
        errorMessage = nil
    }

    private func finishLogin(requestToken: String) async throws {
        struct 访问令牌: Decodable { let access_token: String; let account_id: String }
        struct 会话: Decodable { let session_id: String }
        struct 账户: Decodable {
            struct 头像: Decodable { struct TMDB: Decodable { let avatar_path: String? }; let tmdb: TMDB? }
            let id: Int
            let username: String
            let name: String?
            let avatar: 头像?
        }
        let tokenData = try await TMDB配置.请求("4/auth/access_token", method: "POST", body: ["request_token": requestToken])
        guard let token = try? JSONDecoder().decode(访问令牌.self, from: tokenData) else { throw 平台账户错误.loginIncomplete("TMDB") }
        let sessionData = try await TMDB配置.请求("3/authentication/session/convert/4", method: "POST", body: ["access_token": token.access_token])
        guard let session = try? JSONDecoder().decode(会话.self, from: sessionData) else { throw 平台账户错误.loginIncomplete("TMDB") }
        let accountData = try await TMDB配置.请求("3/account", query: [URLQueryItem(name: "session_id", value: session.session_id)])
        guard let account = try? JSONDecoder().decode(账户.self, from: accountData) else { throw 平台账户错误.invalidResponse("TMDB") }
        let profile = TMDB用户资料(
            id: account.id,
            username: account.username,
            name: account.name.flatMap { $0.isEmpty ? nil : $0 },
            avatar: account.avatar?.tmdb?.avatar_path.map { "https://image.tmdb.org/t/p/w185\($0)" }
        )
        let newCredentials = TMDB凭据(accessToken: token.access_token, accountObjectID: token.account_id, sessionID: session.session_id, profile: profile)
        try credentialStore.save(newCredentials)
        credentials = newCredentials
        self.profile = profile
        isLoggedIn = true
        finishAuthentication()
    }

    private func finishAuthentication(error: String? = nil) {
        webAuthenticationTask = nil
        isAuthenticating = false
        errorMessage = error
    }

    private func 凭据() throws -> TMDB凭据 {
        guard let credentials else { throw 平台账户错误.notLoggedIn("TMDB") }
        return credentials
    }

    // MARK: 资料库

    private struct 列表页: Decodable {
        struct 条目: Decodable {
            struct 评分: Decodable { let value: Double?; let created_at: String? }
            let id: Int
            let name: String?
            let title: String?
            let original_name: String?
            let original_title: String?
            let original_language: String?
            let first_air_date: String?
            let release_date: String?
            let poster_path: String?
            let genre_ids: [Int]?
            let account_rating: 评分?
        }
        let results: [条目]
        let total_pages: Int?
    }

    /// 读取想看列表和评过分的作品，只保留动画：作品映射里有的，或分类是动画、原语言是日语、汉语或韩语的。
    func 读取资料库() async throws -> [平台资料库记录] {
        let credentials = try 凭据()
        var items: [String: (条目: 列表页.条目, 想看: Bool, 评分: Double?, 时间: String?)] = [:]
        for media in ["tv", "movie"] {
            for list in ["watchlist", "rated"] {
                var page = 1
                while true {
                    let data = try await TMDB配置.请求(
                        "4/account/\(credentials.accountObjectID)/\(media)/\(list)",
                        query: [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "language", value: "en-US")],
                        bearer: credentials.accessToken
                    )
                    guard let result = try? JSONDecoder().decode(列表页.self, from: data) else { throw 平台账户错误.invalidResponse("TMDB") }
                    for item in result.results {
                        let key = "\(media)/\(item.id)"
                        var value = items[key] ?? (item, false, nil, nil)
                        if list == "watchlist" { value.想看 = true }
                        if let rating = item.account_rating?.value { value.评分 = rating; value.时间 = item.account_rating?.created_at }
                        items[key] = value
                    }
                    guard page < (result.total_pages ?? 1) else { break }
                    page += 1
                }
            }
        }
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return items.compactMap { id, value -> 平台资料库记录? in
            let item = value.条目
            let mapped = 作品映射.查找(.tmdb, 平台ID: id, 类型: .anime) != nil
            let looksLikeAnime = item.genre_ids?.contains(16) == true && ["ja", "zh", "ko"].contains(item.original_language ?? "")
            guard mapped || looksLikeAnime else { return nil }
            let original = item.original_name ?? item.original_title
            let title = item.name ?? item.title ?? original ?? id
            let languages = ["ja": "ja", "ko": "ko", "zh": "zh-Hans"]
            return 平台资料库记录(
                平台: .tmdb,
                平台ID: id,
                类型: .anime,
                malID: nil,
                标题: title,
                日文标题: item.original_language == "ja" ? original : nil,
                封面地址: item.poster_path.map { "https://image.tmdb.org/t/p/w342\($0)" },
                快照: 同步快照(
                    状态: value.想看 ? .planning : .completed,
                    评分: value.评分.map { Int(($0 * 10).rounded()) },
                    进度: nil
                ),
                总数: nil,
                平均评分: nil,
                发行日期: item.first_air_date ?? item.release_date,
                开始日期: nil,
                完成日期: nil,
                修改时间: value.时间.flatMap { isoFormatter.date(from: $0) },
                多语言标题: 作品多语言标题.生成(
                    原名: original,
                    原名语言: item.original_language.flatMap { languages[$0] },
                    罗马字: nil,
                    英文: title == original ? nil : title
                )
            )
        }
    }

    /// 写入一部作品：“计划观看”加入想看列表，其他状态移出想看列表；有评分时写入评分。nil 表示从 TMDB 删除。
    func 写入(平台ID id: String, 快照 target: 同步快照?) async throws {
        let credentials = try 凭据()
        let parts = id.split(separator: "/")
        guard parts.count == 2, ["tv", "movie"].contains(parts[0]), let mediaID = Int(parts[1]) else {
            throw 平台账户错误.invalidResponse("TMDB")
        }
        let media = String(parts[0])
        let session = [URLQueryItem(name: "session_id", value: credentials.sessionID)]
        _ = try await TMDB配置.请求(
            "3/account/\(credentials.profile.id)/watchlist",
            method: "POST",
            query: session,
            body: ["media_type": media, "media_id": mediaID, "watchlist": target?.状态 == .planning]
        )
        if let score = target?.评分 {
            // TMDB 的评分是 0.5–10，以 0.5 为步长
            let value = max(0.5, min(10, (Double(score) / 5).rounded() * 0.5))
            _ = try await TMDB配置.请求("3/\(media)/\(mediaID)/rating", method: "POST", query: session, body: ["value": value])
        } else if target == nil {
            _ = try? await TMDB配置.请求("3/\(media)/\(mediaID)/rating", method: "DELETE", query: session)
        }
    }

    /// 手动匹配时搜索动画；输入“tv/123”“movie/123”或 TMDB 页面的链接时直接读取。
    func 搜索候选(关键词 query: String) async throws -> [匹配候选] {
        struct 结果: Decodable {
            struct 条目: Decodable {
                let id: Int
                let media_type: String?
                let name: String?
                let title: String?
                let original_name: String?
                let original_title: String?
                let original_language: String?
                let first_air_date: String?
                let release_date: String?
                let poster_path: String?
            }
            let results: [条目]
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        func 候选(_ item: 结果.条目, media: String) -> 匹配候选 {
            let original = item.original_name ?? item.original_title
            let local = item.name ?? item.title
            let languages = ["ja": "ja", "ko": "ko", "zh": "zh-Hans"]
            return 匹配候选(
                id: "\(media)/\(item.id)",
                标题: original ?? local ?? String(item.id),
                标题语言: item.original_language.flatMap { languages[$0] },
                其他标题: local == original ? nil : local,
                其他标题语言: nil,
                年份: (item.first_air_date ?? item.release_date).flatMap { Int($0.prefix(4)) },
                封面: item.poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") },
                种类: media == "tv" ? "TV" : "Movie"
            )
        }
        let language = [URLQueryItem(name: "language", value: TMDB配置.语言)]
        if let match = text.range(of: #"(tv|movie)/[0-9]+"#, options: .regularExpression) {
            let path = String(text[match])
            let data = try await TMDB配置.请求("3/\(path)", query: language)
            guard let item = try? JSONDecoder().decode(结果.条目.self, from: data) else { throw 平台账户错误.invalidResponse("TMDB") }
            return [候选(item, media: String(path.split(separator: "/")[0]))]
        }
        let data = try await TMDB配置.请求("3/search/multi", query: language + [URLQueryItem(name: "query", value: text)])
        guard let result = try? JSONDecoder().decode(结果.self, from: data) else { throw 平台账户错误.invalidResponse("TMDB") }
        return result.results.compactMap { item in
            guard let media = item.media_type, media == "tv" || media == "movie" else { return nil }
            return 候选(item, media: media)
        }
    }
}
