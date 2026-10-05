import AuthenticationServices
import Combine
import Foundation
import Security
import UIKit

enum BangumiOAuth配置 {
    static let callbackScheme = "papervn"
    static let redirectURI = "papervn://oauth/bangumi"

    static var clientID: String {
        configuredValue(environment: "BANGUMI_OAUTH_CLIENT_ID", plist: "BangumiOAuthClientID")
    }

    static var clientSecret: String {
        configuredValue(environment: "BANGUMI_OAUTH_CLIENT_SECRET", plist: "BangumiOAuthClientSecret")
    }

    static var isConfigured: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

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
            return String(localized: "登录验证失败，请重试。")
        case .missingAuthorizationCode:
            return String(localized: "登录结果中缺少授权码。")
        case .invalidResponse:
            return String(localized: "Bangumi番组计划返回了无法识别的响应。")
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
    static let 同步设置键 = "bangumiCollectionSyncEnabled"

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
    @Published private(set) var isSynchronizing = false
    @Published var errorMessage: String?
    @Published var synchronizationErrorMessage: String?

    private let credentialStore = BangumiOAuth凭据存储()
    private var credentials: BangumiOAuth凭据?
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private var pendingState: String?
    private var librarySynchronizationTask: Task<Void, Never>?
    private var librarySynchronizationID: UUID?

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

    func login() {
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
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                平台自定义Scheme: BangumiOAuth配置.callbackScheme
            ) { [weak self] callbackURL, error in
                let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                Task { @MainActor [weak self] in
                    self?.webAuthenticationSession = nil
                    if cancelled {
                        self?.finishAuthentication()
                    } else if let callbackURL {
                        await self?.handleCallback(callbackURL)
                    } else {
                        self?.finishAuthentication(error: error?.localizedDescription ?? Bangumi账户错误.invalidCallback.localizedDescription)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webAuthenticationSession = session
            guard session.start() else { throw Bangumi账户错误.failedToPresentLogin }
        } catch {
            finishAuthentication(error: error.localizedDescription)
        }
    }

    func logout() {
        cancelLibrarySynchronization()
        webAuthenticationSession?.cancel()
        webAuthenticationSession = nil
        pendingState = nil
        credentialStore.delete()
        credentials = nil
        profile = nil
        isLoggedIn = false
        isRestoringSession = false
        errorMessage = nil
        synchronizationErrorMessage = nil
        UserDefaults.standard.set(false, forKey: Self.同步设置键)
    }

    func synchronize(vndbID: String, status: 用户列表筛选, rating: Int?, comment: String? = nil) async throws {
        guard UserDefaults.standard.bool(forKey: Self.同步设置键) else { return }
        guard let accessToken = try await validAccessToken() else {
            throw URLError(.userAuthenticationRequired)
        }
        let ids = 视觉小说外部ID目录.shared.ids(for: vndbID).bangumiIDs
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

    func startLibrarySynchronization(vndbToken: String, userID: String) {
        guard !isSynchronizing,
              isLoggedIn,
              UserDefaults.standard.bool(forKey: Self.同步设置键) else { return }

        let synchronizationID = UUID()
        librarySynchronizationID = synchronizationID
        isSynchronizing = true
        synchronizationErrorMessage = nil
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
                    do {
                        try await synchronize(
                            vndbID: item.id,
                            status: status,
                            rating: item.vote.map { $0 / 10 },
                            comment: item.notes
                        )
                        写入成功数 += 1
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        首个写入失败 = 首个写入失败 ?? error
                    }
                    await Self.暂停写入节奏()
                }
                hasMore = response.more
                page += 1
            }
            if 写入成功数 == 0, let 首个写入失败 {
                throw 首个写入失败
            }
            synchronizationErrorMessage = nil
        } catch {
            if Task.isCancelled
                || !UserDefaults.standard.bool(forKey: Self.同步设置键) {
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

    private func validAccessToken() async throws -> String? {
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
        var values = [
            "grant_type": grantType,
            "client_id": BangumiOAuth配置.clientID,
            "client_secret": BangumiOAuth配置.clientSecret,
            "redirect_uri": BangumiOAuth配置.redirectURI
        ]
        if let code { values["code"] = code }
        if let refreshToken { values["refresh_token"] = refreshToken }
        var urlRequest = URLRequest(url: URL(string: "https://bgm.tv/oauth/access_token")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = values
            .map { "\(formEncoded($0.key))=\(formEncoded($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)
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
                ?? String(localized: "Bangumi番组计划请求失败。")
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
            }
        }
    }

    private static func 暂停写入节奏() async {
        try? await Task.sleep(for: .milliseconds(200))
    }

    private static func configured(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("JiZPaper/PaperVN/1.6.0 (iOS; https://github.com/JiZPaper/PaperVN)", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func formEncoded(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

extension Bangumi账户: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else {
            preconditionFailure("Bangumi番组计划登录需要可用的展示窗口。")
        }
        return window
    }
}
