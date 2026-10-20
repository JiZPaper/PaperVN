import AuthenticationServices
import Combine
import Foundation
import Security
import SwiftUI

enum BangumiOAuth配置 {
    static let callbackScheme = "papervn"
    static let redirectURI = "papervn://oauth/bangumi"

    static var clientID: String {
        configuredValue(environment: "BANGUMI_OAUTH_CLIENT_ID", plist: "BangumiOAuthClientID")
    }

    /// 换取和刷新令牌要用到 client_secret，由 PaperVN Sync 服务端代办，secret 不放在 App 里。
    static let tokenURL = URL(string: "https://papervn.jizpaper.com/api/sync/oauth/bangumi/token")!

    static var isConfigured: Bool { !clientID.isEmpty }

    private static func configuredValue(environment: String, plist: String) -> String {
        if let value = ProcessInfo.processInfo.environment[environment]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return (Bundle.main.object(forInfoDictionaryKey: plist) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct Bangumi用户资料: Codable, Equatable, Sendable {
    struct 头像: Codable, Equatable, Sendable {
        let large: String
        let medium: String
        let small: String
    }

    let id: Int
    let username: String
    let nickname: String
    let userGroup: Int
    let avatar: 头像
    let sign: String

    var displayName: String { nickname.isEmpty ? username : nickname }
}

private struct BangumiOAuth令牌: Decodable, Sendable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String
    let userID: Int?
}

private struct BangumiOAuth凭据: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    var profile: Bangumi用户资料?
}

private struct BangumiOAuth错误响应: Decodable {
    let error: String?
    let errorDescription: String?
    let message: String?
    let title: String?
    let description: String?
}

private enum Bangumi账户错误: LocalizedError {
    case notConfigured
    case invalidAuthorizationURL
    case failedToPresentLogin
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case invalidResponse
    case missingMapping
    case insufficientScope
    case keychain(OSStatus)
    case service(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "尚未配置Bangumi番组计划OAuth应用。")
        case .invalidAuthorizationURL:
            return String(localized: "无法创建Bangumi番组计划登录地址。")
        case .failedToPresentLogin:
            return String(localized: "无法打开Bangumi番组计划登录页。")
        case .invalidCallback:
            return String(localized: "Bangumi番组计划返回了无效的登录结果。")
        case .stateMismatch:
            return String(localized: "登录验证失败，请再试一次。")
        case .missingAuthorizationCode:
            return String(localized: "登录结果中缺少授权码。")
        case .invalidResponse:
            return String(localized: "返回的内容无效。")
        case .missingMapping:
            return String(localized: "没有找到该视觉小说对应的Bangumi番组计划条目。")
        case .insufficientScope:
            return String(localized: "Bangumi番组计划登录缺少发布权限，请退出账户后重新登录。")
        case .keychain:
            return String(localized: "无法访问系统钥匙串。")
        case let .service(_, message):
            return message
        }
    }

    var isUnavailableCollection: Bool {
        guard case let .service(statusCode, _) = self else { return false }
        return statusCode == 400 || statusCode == 404
    }

    var isTransient: Bool {
        guard case let .service(statusCode, _) = self else { return false }
        return statusCode == 429 || (500..<600).contains(statusCode)
    }
}

private struct BangumiOAuth凭据存储 {
    private let service = "com.jizpaper.PaperVN.bangumi-oauth"
    private let account = "session"

    func read() throws -> BangumiOAuth凭据? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw Bangumi账户错误.keychain(status)
        }
        return try JSONDecoder().decode(BangumiOAuth凭据.self, from: data)
    }

    func save(_ credentials: BangumiOAuth凭据) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw Bangumi账户错误.keychain(updateStatus)
        }
        var newItem = query
        values.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Bangumi账户错误.keychain(addStatus)
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class Bangumi账户: NSObject, ObservableObject {

    private actor 访问令牌中心 {
        func 有效访问令牌() async -> String? {
            await Bangumi账户.读取并刷新访问令牌()
        }
    }

    private static let 访问令牌中心实例 = 访问令牌中心()

    @Published private(set) var profile: Bangumi用户资料?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isRestoringSession = true
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    /// 视觉小说推送的进度单独放在一个对象里：它每推送一部作品就变一次，
    /// 如果作为账户本身的 @Published 属性，所有观察账户的页面（资料库、探索、搜索、详情等）都会跟着重绘。
    let 同步进度 = Bangumi同步进度()

    private(set) var isSynchronizing: Bool {
        get { 同步进度.isSynchronizing }
        set { 同步进度.isSynchronizing = newValue }
    }
    /// 资料库同步进度：已处理的作品数与预计总数（总数来自本地资料库，未载入时为空）。
    private(set) var 已同步数: Int {
        get { 同步进度.已同步数 }
        set { 同步进度.已同步数 = newValue }
    }
    private(set) var 待同步总数: Int? {
        get { 同步进度.待同步总数 }
        set { 同步进度.待同步总数 = newValue }
    }
    var synchronizationErrorMessage: String? {
        get { 同步进度.synchronizationErrorMessage }
        set { 同步进度.synchronizationErrorMessage = newValue }
    }

    private let credentialStore = BangumiOAuth凭据存储()
    private var credentials: BangumiOAuth凭据?
    private var webAuthenticationTask: Task<Void, Never>?
    private var pendingState: String?
    private var librarySynchronizationTask: Task<Void, Never>?
    private var librarySynchronizationID: UUID?
    /// 最近一次读到的 Bangumi 游戏收藏，决定视觉小说推送到哪些条目。
    private var 已收藏游戏: Set<Int> = []

    init(previewing: Bool = false) {
        super.init()
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        guard !previewing && !isPreview else {
            isRestoringSession = false
            return
        }
        do {
            credentials = try credentialStore.read()
            profile = credentials?.profile
            isLoggedIn = profile != nil
            guard credentials != nil else {
                isRestoringSession = false
                return
            }
            Task { [weak self] in await self?.restoreSession() }
        } catch {
            isRestoringSession = false
            errorMessage = error.localizedDescription
        }
    }

    func login(using authenticator: WebAuthenticationSession) {
        guard !isAuthenticating else { return }
        do {
            guard BangumiOAuth配置.isConfigured else { throw Bangumi账户错误.notConfigured }
            let state = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            var components = URLComponents(string: "https://bgm.tv/oauth/authorize")
            components?.queryItems = [
                URLQueryItem(name: "client_id", value: BangumiOAuth配置.clientID),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "redirect_uri", value: BangumiOAuth配置.redirectURI),
                URLQueryItem(name: "state", value: state)
            ]
            guard let authorizationURL = components?.url else {
                throw Bangumi账户错误.invalidAuthorizationURL
            }
            pendingState = state
            isAuthenticating = true
            errorMessage = nil
            webAuthenticationTask = Task { [weak self] in
                do {
                    let callbackURL = try await authenticator.authenticate(
                        using: authorizationURL,
                        callback: .customScheme(BangumiOAuth配置.callbackScheme),
                        preferredBrowserSession: .shared,
                        additionalHeaderFields: [:]
                    )
                    self?.webAuthenticationTask = nil
                    await self?.handleCallback(callbackURL)
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.webAuthenticationTask = nil
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        self?.finishAuthentication()
                    } else {
                        self?.finishAuthentication(error: error.localizedDescription)
                    }
                }
            }
        } catch {
            finishAuthentication(error: error.localizedDescription)
        }
    }

    func logout() {
        cancelLibrarySynchronization()
        webAuthenticationTask?.cancel()
        webAuthenticationTask = nil
        pendingState = nil
        credentialStore.delete()
        credentials = nil
        profile = nil
        isLoggedIn = false
        isRestoringSession = false
        errorMessage = nil
        synchronizationErrorMessage = nil
    }

    func synchronize(vndbID: String, status: 用户列表筛选, rating: Int?, comment: String? = nil) async throws {
        // 同步方式设为“无”时，视觉小说也不推送到 Bangumi
        guard PaperVNSync中心.已启用, 资料库平台.bangumi.同步方向 != .无 else { return }
        guard let accessToken = try await validAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        let ids = Bangumi推送目标(vndbID: vndbID)
        guard !ids.isEmpty else { return }
        var payload: [String: Any] = ["type": collectionType(for: status)]
        if let rating { payload["rate"] = min(max(rating, 0), 10) }
        if let comment { payload["comment"] = comment }
        let body = try JSONSerialization.data(withJSONObject: payload)
        var firstUnavailableError: Bangumi账户错误?
        var didSynchronize = false
        for id in ids {
            try Task.checkCancellation()
            do {
                _ = try await Self.request(
                    url: URL(string: "https://api.bgm.tv/v0/users/-/collections/\(id)")!,
                    method: "POST",
                    accessToken: accessToken,
                    body: body,
                    allowsEmptyData: true
                )
                didSynchronize = true
            } catch let error as Bangumi账户错误 where error.isUnavailableCollection {
                firstUnavailableError = firstUnavailableError ?? error
            }
        }
        if !didSynchronize, let firstUnavailableError {
            throw firstUnavailableError
        }
    }

    /// 一部视觉小说在 Bangumi 上常有多个条目（不同发行版本），VNDB 只算一部。
    /// 只推送到主条目，以及用户已经收藏的其他版本；不会把每个版本都加入 Bangumi 收藏。
    /// 被几部作品共用的条目（VNDB 把原版和重制版分成两部、Bangumi 只有一个条目）只由其中一部写入，免得互相覆盖。
    private func Bangumi推送目标(vndbID: String) -> [Int] {
        let ids = 视觉小说外部ID目录.shared.ids(for: vndbID).bangumiIDs
            .filter { 作品映射.视觉小说可以写入($0, vndbID: vndbID) }
        guard ids.count > 1 else { return ids }
        let main = 作品映射.视觉小说Bangumi主条目(vndbID).flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]
        return [main] + ids.filter { $0 != main && 已收藏游戏.contains($0) }
    }

    func startLibrarySynchronization(vndbToken: String, userID: String) {
        guard !isSynchronizing,
              isLoggedIn,
              PaperVNSync中心.已启用,
              资料库平台.bangumi.同步方向 != .无 else { return }

        let synchronizationID = UUID()
        librarySynchronizationID = synchronizationID
        isSynchronizing = true
        synchronizationErrorMessage = nil
        已同步数 = 0
        let 本地资料库 = 本地资料库.shared
        待同步总数 = 本地资料库.已载入
            ? 本地资料库.条目.filter { $0.类型 == .visualNovel && $0.状态 != nil }.count
            : nil
        librarySynchronizationTask = Task { [weak self] in
            await self?.performLibrarySynchronization(
                vndbToken: vndbToken,
                userID: userID,
                synchronizationID: synchronizationID
            )
        }
    }

    func cancelLibrarySynchronization() {
        librarySynchronizationID = nil
        librarySynchronizationTask?.cancel()
        librarySynchronizationTask = nil
        isSynchronizing = false
        synchronizationErrorMessage = nil
    }

    private func performLibrarySynchronization(
        vndbToken: String,
        userID: String,
        synchronizationID: UUID
    ) async {
        defer {
            if librarySynchronizationID == synchronizationID {
                librarySynchronizationID = nil
                librarySynchronizationTask = nil
                isSynchronizing = false
            }
        }

        do {
            // 先读出 Bangumi 上已有的游戏收藏，只写入不一致的作品：
            // 重新写入一致的收藏没有意义，还会刷新 Bangumi 上的更改时间
            let existing = try await 读取游戏收藏()
            已收藏游戏 = Set(existing.keys)
            var page = 1
            var hasMore = true
            var 写入成功数 = 0
            var 首个写入失败: Error?
            while hasMore {
                try Task.checkCancellation()
                let response = try await VNDB服务.shared.fetchUserList(
                    token: vndbToken,
                    userID: userID,
                    filter: .all,
                    page: page,
                    forceRefresh: page == 1
                )
                for item in response.results {
                    try Task.checkCancellation()
                    guard let status = item.primaryStatus else { continue }
                    let rating = item.vote.map { $0 / 10 }
                    let ids = Bangumi推送目标(vndbID: item.id)
                    let needsWrite = ids.contains { id in
                        guard let current = existing[id] else { return true }
                        if current.type != collectionType(for: status) { return true }
                        if let rating, rating != current.rate { return true }
                        if let notes = item.notes, notes != (current.comment ?? "") { return true }
                        return false
                    }
                    guard needsWrite else {
                        已同步数 += 1
                        continue
                    }
                    do {
                        try await synchronize(
                            vndbID: item.id,
                            status: status,
                            rating: rating,
                            comment: item.notes
                        )
                        写入成功数 += 1
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        首个写入失败 = 首个写入失败 ?? error
                    }
                    已同步数 += 1
                    await Self.暂停写入节奏()
                }
                hasMore = response.more
                page += 1
            }
            if 写入成功数 == 0, let 首个写入失败 {
                // 全部写入都失败才算同步失败
                throw 首个写入失败
            }
            synchronizationErrorMessage = nil
            PaperVNSync中心.记录同步完成(.bangumi)
        } catch {
            if Task.isCancelled
                || !PaperVNSync中心.已启用 {
                synchronizationErrorMessage = nil
            } else {
                synchronizationErrorMessage = error.localizedDescription
            }
        }
    }

    func publishComment(vndbID: String, text: String, rating: Int?) async throws {
        guard let accessToken = try await validAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        let ids = 视觉小说外部ID目录.shared.ids(for: vndbID).bangumiIDs
        guard !ids.isEmpty else { throw Bangumi账户错误.missingMapping }
        var payload: [String: Any] = ["comment": text]
        if let rating { payload["rate"] = min(max(rating, 0), 10) }
        let body = try JSONSerialization.data(withJSONObject: payload)
        for id in ids {
            _ = try await Self.request(
                url: URL(string: "https://api.bgm.tv/v0/users/-/collections/\(id)")!,
                method: "POST",
                accessToken: accessToken,
                body: body,
                allowsEmptyData: true
            )
        }
    }

    private func restoreSession() async {
        defer { isRestoringSession = false }
        do {
            guard let accessToken = try await validAccessToken() else { return }
            let profile = try await Self.fetchProfile(accessToken: accessToken)
            self.profile = profile
            self.isLoggedIn = true
            if var credentials {
                credentials.profile = profile
                try save(credentials)
            }
            errorMessage = nil
        } catch {
            if case let Bangumi账户错误.service(statusCode, _) = error,
               statusCode == 401 || statusCode == 403 {
                logout()
                errorMessage = String(localized: "Bangumi番组计划登录已失效，请重新登录。")
            } else {
                isLoggedIn = profile != nil
                if profile == nil {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleCallback(_ url: URL) async {
        do {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw Bangumi账户错误.invalidCallback
            }
            let queryItems = components.queryItems ?? []
            func value(named name: String) throws -> String? {
                let matches = queryItems.filter { $0.name == name }
                guard matches.count <= 1 else {
                    throw Bangumi账户错误.invalidCallback
                }
                return matches.first?.value
            }
            guard try value(named: "state") == pendingState else {
                throw Bangumi账户错误.stateMismatch
            }
            if let oauthError = try value(named: "error") {
                throw Bangumi账户错误.service(
                    400,
                    try value(named: "error_description") ?? oauthError
                )
            }
            guard let code = try value(named: "code"), !code.isEmpty else {
                throw Bangumi账户错误.missingAuthorizationCode
            }
            let token = try await Self.requestToken(grantType: "authorization_code", code: code)
            var newCredentials = BangumiOAuth凭据(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                profile: nil
            )
            newCredentials.profile = try await Self.fetchProfile(accessToken: token.accessToken)
            try save(newCredentials)
            profile = newCredentials.profile
            isLoggedIn = true
            finishAuthentication()
        } catch {
            finishAuthentication(error: error.localizedDescription)
        }
    }

    static func 有效访问令牌() async -> String? {
        await 访问令牌中心实例.有效访问令牌()
    }

    static var 当前访问令牌: String? {
        guard let credentials = (try? BangumiOAuth凭据存储().read()) ?? nil,
              credentials.expiresAt > Date() else { return nil }
        return credentials.accessToken
    }

    private static func 读取并刷新访问令牌() async -> String? {
        let store = BangumiOAuth凭据存储()
        guard var credentials = (try? store.read()) ?? nil else { return nil }
        guard credentials.expiresAt <= Date().addingTimeInterval(60) else {
            return credentials.accessToken
        }

        do {
            let token = try await requestToken(
                grantType: "refresh_token",
                refreshToken: credentials.refreshToken
            )
            credentials = BangumiOAuth凭据(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                profile: credentials.profile
            )
            try store.save(credentials)
            return credentials.accessToken
        } catch {
            return nil
        }
    }

    func validAccessToken() async throws -> String? {
        guard var credentials else { return nil }
        if credentials.expiresAt <= Date().addingTimeInterval(60) {
            let token = try await Self.requestToken(grantType: "refresh_token", refreshToken: credentials.refreshToken)
            credentials = BangumiOAuth凭据(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
                profile: credentials.profile
            )
            try save(credentials)
        }
        return credentials.accessToken
    }

    private func save(_ credentials: BangumiOAuth凭据) throws {
        try credentialStore.save(credentials)
        self.credentials = credentials
    }

    private func finishAuthentication(error: String? = nil) {
        pendingState = nil
        isAuthenticating = false
        errorMessage = error
    }

    private func collectionType(for status: 用户列表筛选) -> Int {
        switch status {
        case .planning: 1
        case .finished: 2
        case .playing: 3
        case .stalled: 4
        case .dropped: 5
        case .all: 1
        }
    }

    private static func requestToken(grantType: String, code: String? = nil, refreshToken: String? = nil) async throws -> BangumiOAuth令牌 {
        var values = ["grant_type": grantType]
        if let code { values["code"] = code }
        if let refreshToken { values["refresh_token"] = refreshToken }
        var urlRequest = URLRequest(url: BangumiOAuth配置.tokenURL, timeoutInterval: 20)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: values)
        let data = try await self.request(urlRequest)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let token = try? decoder.decode(BangumiOAuth令牌.self, from: data) else {
            throw Bangumi账户错误.invalidResponse
        }
        return token
    }

    private static func fetchProfile(accessToken: String) async throws -> Bangumi用户资料 {
        var urlRequest = URLRequest(url: URL(string: "https://api.bgm.tv/v0/me")!)
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await self.request(urlRequest)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Bangumi用户资料.self, from: data)
    }

    private static func request(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await PaperVNConnect网络设置.发送请求(
            configured(request),
            session: .shared
        )
        guard (200..<300).contains(http.statusCode) else {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let error = try? decoder.decode(BangumiOAuth错误响应.self, from: data)
            let message = error?.message
                ?? error?.description
                ?? error?.errorDescription
                ?? error?.error
                ?? error?.title
                ?? String(localized: "请求失败。")
            if http.statusCode == 403,
               message.localizedCaseInsensitiveCompare("insufficient token scope") == .orderedSame {
                throw Bangumi账户错误.insufficientScope
            }
            throw Bangumi账户错误.service(http.statusCode, message)
        }
        return data
    }

    private static func request(url: URL, method: String, accessToken: String, body: Data, allowsEmptyData: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data = try await 退避重试请求(request)
        if !allowsEmptyData && data.isEmpty { throw Bangumi账户错误.invalidResponse }
        return data
    }

    private static func 退避重试请求(_ request: URLRequest) async throws -> Data {
        let 退避时长: [Duration] = [.seconds(1), .seconds(3)]
        var 已重试 = 0
        while true {
            do {
                return try await self.request(request)
            } catch let error as Bangumi账户错误
                where error.isTransient && 已重试 < 退避时长.count {
                try await Task.sleep(for: 退避时长[已重试])
                已重试 += 1
            } catch let error as URLError
                where Self.可重试的网络错误.contains(error.code) && 已重试 < 退避时长.count {
                // 开启 Connect 时偶尔会遇到 TLS 握手失败、连接中断，稍等后重新尝试（会再走一遍转发和直连）
                try await Task.sleep(for: 退避时长[已重试])
                已重试 += 1
            }
        }
    }

    private static let 可重试的网络错误: Set<URLError.Code> = [
        .secureConnectionFailed, .networkConnectionLost, .timedOut, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet,
    ]

    private static func 暂停写入节奏() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    private static func configured(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("JiZPaper/PaperVN/1.6.0 (iOS; https://github.com/JiZPaper/PaperVN)", forHTTPHeaderField: "User-Agent")
        return request
    }

}

/// Bangumi 视觉小说推送的进度，只有同步任务页面和账户页面需要观察。
@MainActor
final class Bangumi同步进度: ObservableObject {
    @Published var isSynchronizing = false
    @Published var 已同步数 = 0
    @Published var 待同步总数: Int?
    @Published var synchronizationErrorMessage: String?
}

// MARK: - 动画、漫画与轻小说

extension Bangumi账户 {
    private struct 收藏页: Decodable {
        struct 收藏: Decodable {
            struct 条目: Decodable {
                struct 图片: Decodable { let large: String?; let common: String? }
                struct 标签: Decodable { let name: String }
                let id: Int
                let name: String
                let nameCn: String?
                let date: String?
                let images: 图片?
                let eps: Int?
                let volumes: Int?
                let score: Double?
                let tags: [标签]?
            }
            let subjectId: Int
            let subjectType: Int
            let rate: Int
            let type: Int
            let comment: String?
            let epStatus: Int
            let updatedAt: String?
            let subject: 条目?
        }
        let data: [收藏]
        let total: Int
    }

    /// 读取游戏收藏（视觉小说）的状态、评分与吐槽，用来跳过已经一致的作品。
    fileprivate func 读取游戏收藏() async throws -> [Int: (type: Int, rate: Int, comment: String?)] {
        guard let accessToken = try await validAccessToken(), let username = profile?.username else {
            throw URLError(.userAuthenticationRequired)
        }
        var result: [Int: (type: Int, rate: Int, comment: String?)] = [:]
        var offset = 0
        while true {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://api.bgm.tv/v0/users/\(username)/collections")!
            components.queryItems = [
                URLQueryItem(name: "subject_type", value: "4"),
                URLQueryItem(name: "limit", value: "50"),
                URLQueryItem(name: "offset", value: String(offset)),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let data = try await Self.退避重试请求(request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let page = try? decoder.decode(收藏页.self, from: data) else {
                throw Bangumi账户错误.invalidResponse
            }
            for item in page.data {
                result[item.subjectId] = (item.type, item.rate, item.comment)
            }
            offset += page.data.count
            guard !page.data.isEmpty, offset < page.total else { break }
        }
        return result
    }

    /// 读取动画与书籍（漫画、轻小说）收藏。
    func 读取动画漫画资料库() async throws -> [平台资料库记录] {
        guard let accessToken = try await validAccessToken(), let username = profile?.username else {
            throw URLError(.userAuthenticationRequired)
        }
        var results: [平台资料库记录] = []
        for subjectType in [2, 1] {
            var offset = 0
            while true {
                try Task.checkCancellation()
                var components = URLComponents(string: "https://api.bgm.tv/v0/users/\(username)/collections")!
                components.queryItems = [
                    URLQueryItem(name: "subject_type", value: String(subjectType)),
                    URLQueryItem(name: "limit", value: "50"),
                    URLQueryItem(name: "offset", value: String(offset)),
                ]
                var request = URLRequest(url: components.url!)
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                let data = try await Self.退避重试请求(request)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                guard let page = try? decoder.decode(收藏页.self, from: data) else {
                    throw Bangumi账户错误.invalidResponse
                }
                results += page.data.compactMap(Self.记录)
                offset += page.data.count
                guard !page.data.isEmpty, offset < page.total else { break }
                await Self.暂停写入节奏()
            }
        }
        return results
    }

    private static func 记录(_ item: 收藏页.收藏) -> 平台资料库记录? {
        let status: 资料库状态
        switch item.type {
        case 1: status = .planning
        case 2: status = .completed
        case 3: status = .inProgress
        case 4: status = .onHold
        case 5: status = .dropped
        default: return nil
        }
        let subject = item.subject
        let type: 作品类型
        if item.subjectType == 2 {
            type = .anime
        } else {
            // 精简条目里没有“漫画／小说”分类，用标签区分
            let tags = subject?.tags?.map(\.name) ?? []
            type = tags.contains { $0.contains("小说") || $0 == "轻小说" || $0 == "ライトノベル" } ? .lightNovel : .manga
        }
        let name = subject?.name ?? String(item.subjectId)
        let chineseName = subject?.nameCn?.isEmpty == false ? subject?.nameCn : nil
        let total = subject?.eps
        let image = subject?.images?.large ?? subject?.images?.common
        return 平台资料库记录(
            平台: .bangumi,
            平台ID: String(item.subjectId),
            类型: type,
            malID: 作品映射.malID(.bangumi, 平台ID: String(item.subjectId), 类型: type),
            标题: chineseName ?? name,
            日文标题: name,
            封面地址: image?.isEmpty == false ? image : nil,
            快照: 同步快照(状态: status, 评分: item.rate * 10, 进度: item.epStatus),
            总数: (total ?? 0) > 0 ? total : nil,
            平均评分: subject?.score.flatMap { $0 > 0 ? $0 * 10 : nil },
            发行日期: subject?.date,
            开始日期: nil,
            完成日期: nil,
            修改时间: item.updatedAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            // Bangumi 的 name_cn 是简体中文；name 是原名，Bangumi 没有标明语言
            多语言标题: 作品多语言标题.生成(原名: name, 罗马字: nil, 中文: chineseName)
        )
    }

    /// 新增或修改收藏。书籍的进度随收藏一起修改；动画的进度要逐集标记为看过。
    /// `清除空值` 为真时（在 App 里编辑），没有评分、进度表示清除；否则不改动 Bangumi 上的值。
    func 保存收藏(subjectID: Int, 类型 type: 作品类型, 快照 value: 同步快照, 清除空值: Bool = false) async throws {
        guard let accessToken = try await validAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        let collectionType: Int = switch value.状态 {
        case .planning: 1
        case .completed: 2
        case .inProgress: 3
        case .onHold: 4
        case .dropped: 5
        }
        var payload: [String: Any] = [
            "type": collectionType,

        ]
        if let score = value.评分 ?? (清除空值 ? 0 : nil) {
            payload["rate"] = min(max(Int((Double(score) / 10).rounded()), 0), 10)
        }
        let progress = value.进度
        if type != .anime, let progress { payload["ep_status"] = progress }
        _ = try await Self.request(
            url: URL(string: "https://api.bgm.tv/v0/users/-/collections/\(subjectID)")!,
            method: "POST",
            accessToken: accessToken,
            body: try JSONSerialization.data(withJSONObject: payload),
            allowsEmptyData: true
        )
        if type == .anime {
            // 看过的作品不逐集标记：Bangumi 的“看过”本身就表示看完了
            if let progress, value.状态 != .completed {
                try await 设置看过的集数(subjectID: subjectID, count: progress, accessToken: accessToken)
            }
        }
        await Self.暂停写入节奏()
    }

    /// 前 count 集标记为看过，其余正片取消标记。
    private func 设置看过的集数(subjectID: Int, count: Int, accessToken: String) async throws {
        struct 章节页: Decodable {
            struct 章节: Decodable { let id: Int; let sort: Double }
            let data: [章节]
        }
        var components = URLComponents(string: "https://api.bgm.tv/v0/episodes")!
        components.queryItems = [
            URLQueryItem(name: "subject_id", value: String(subjectID)),
            URLQueryItem(name: "type", value: "0"),
            URLQueryItem(name: "limit", value: "1000"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let data = try await Self.退避重试请求(request)
        guard let episodes = try? JSONDecoder().decode(章节页.self, from: data).data.sorted(by: { $0.sort < $1.sort }),
              !episodes.isEmpty else { return }
        let watched = episodes.prefix(count).map(\.id)
        let rest = episodes.dropFirst(count).map(\.id)
        for (ids, type) in [(watched, 2), (Array(rest), 0)] where !ids.isEmpty {
            _ = try await Self.request(
                url: URL(string: "https://api.bgm.tv/v0/users/-/collections/\(subjectID)/episodes")!,
                method: "PATCH",
                accessToken: accessToken,
                body: try JSONSerialization.data(withJSONObject: ["episode_id": ids, "type": type]),
                allowsEmptyData: true
            )
        }
    }
}

extension Bangumi账户 {
    /// 手动匹配时搜索条目；输入条目编号或条目页面的链接时直接读取这个条目。
    func 搜索候选(类型 type: 作品类型, 关键词 query: String) async throws -> [匹配候选] {
        struct 条目: Decodable {
            struct 图片: Decodable { let common: String?; let medium: String? }
            let id: Int
            let name: String
            let nameCn: String?
            let date: String?
            let images: 图片?
            let platform: String?
            var 候选: 匹配候选 {
                匹配候选(
                    id: String(id), 标题: name,
                    其他标题: nameCn.flatMap { $0.isEmpty || $0 == name ? nil : $0 }, 其他标题语言: "zh-Hans",
                    其他标题为官方: false,
                    年份: date.flatMap { Int($0.prefix(4)) },
                    封面: (images?.medium ?? images?.common).flatMap(URL.init(string:)),
                    种类: platform.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
        }
        struct 结果: Decodable { let data: [条目] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let accessToken = try? await validAccessToken()
        func 请求(_ url: URL, body: Data? = nil) async throws -> Data {
            var request = URLRequest(url: url, timeoutInterval: 15)
            if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
            if let body {
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            return try await Self.退避重试请求(request)
        }
        if let id = 匹配候选编号(query, 链接: "/subject/") {
            let data = try await 请求(URL(string: "https://api.bgm.tv/v0/subjects/\(id)")!)
            guard let item = try? decoder.decode(条目.self, from: data) else { throw Bangumi账户错误.invalidResponse }
            return [item.候选]
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let body = try JSONSerialization.data(withJSONObject: [
            "keyword": text,
            "filter": ["type": [type == .anime ? 2 : 1], "nsfw": true],
        ])
        let data = try await 请求(URL(string: "https://api.bgm.tv/v0/search/subjects?limit=20")!, body: body)
        guard let result = try? decoder.decode(结果.self, from: data) else { throw Bangumi账户错误.invalidResponse }
        return result.data.map(\.候选)
    }
}
