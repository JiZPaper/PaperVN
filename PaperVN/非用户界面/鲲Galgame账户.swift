import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Network
import Security
import SwiftUI

nonisolated enum 鲲OAuth配置 {
    static let apiBaseURL = URL(
        string: "https://account.nextmoe.com/api/v1"
    )!
    static let callbackScheme = "http"
    static let callbackHost = "127.0.0.1"
    static let callbackPath = "/callback"
    static let baseScopes = "openid profile email"
    static let catalogScopes = "openid profile email catalog:read"

    static var clientID: String {
        let environmentValue = ProcessInfo.processInfo.environment[
            "KUN_OAUTH_CLIENT_ID"
        ]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty {
            return environmentValue
        }

        return (Bundle.main.object(
            forInfoDictionaryKey: "KUNOAuthClientID"
        ) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var isConfigured: Bool {
        !clientID.isEmpty
    }
}

struct 鲲用户资料: Codable, Equatable, Sendable {
    let id: Int
    let sub: String
    let name: String?
    let email: String?
    let picture: String?
    let roles: [String]
    let siteRoles: [String]?
    let updatedAt: Int?
    let avatarImageHash: String?
    let bio: String?
    let moemoepoint: Int?
    let status: Int?
    let createdAt: String?

    var displayName: String {
        guard let name, !name.isEmpty else {
            return String(localized: "鲲Galgame用户")
        }
        return name
    }

    fileprivate func merging(_ details: 鲲账户详细资料) -> Self {
        Self(
            id: id,
            sub: sub,
            name: details.name ?? name,
            email: details.email ?? email,
            picture: details.avatar ?? picture,
            roles: details.roles ?? roles,
            siteRoles: siteRoles,
            updatedAt: updatedAt,
            avatarImageHash: details.avatarImageHash,
            bio: details.bio,
            moemoepoint: details.moemoepoint,
            status: details.status,
            createdAt: details.createdAt
        )
    }
}

private struct 鲲账户详细资料: Decodable, Sendable {
    let uuid: String?
    let name: String?
    let email: String?
    let avatar: String?
    let avatarImageHash: String?
    let bio: String?
    let moemoepoint: Int?
    let status: Int?
    let roles: [String]?
    let createdAt: String?
}

private struct 鲲OAuth令牌: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String?
}

private struct 鲲OAuth凭据: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let scope: String?
    var profile: 鲲用户资料?

    var scopeTokens: Set<String> {
        Set(
            (scope ?? "")
                .split { $0 == " " || $0 == "," }
                .map(String.init)
        )
    }

    var hasCatalogAccess: Bool {
        scopeTokens.contains("catalog:read")
    }
}

private struct 鲲OAuth响应<Value: Decodable>: Decodable {
    let code: Int?
    let message: String?
    let data: Value?
}

private struct 鲲OAuth错误响应: Decodable {
    let code: Int?
    let message: String?
    let error: String?
    let errorDescription: String?
}

private struct 鲲OAuth令牌请求: Encodable {
    let grantType: String
    let clientID: String
    let code: String?
    let redirectURI: String?
    let codeVerifier: String?
    let refreshToken: String?
}

private struct 鲲OAuth撤销请求: Encodable {
    let token: String
}

private struct 鲲OAuth服务错误: LocalizedError, Sendable {
    let statusCode: Int
    let code: Int?
    let oauthError: String?
    let message: String

    var errorDescription: String? { message }

    var userFacingMessage: String {
        if code == 15006 || oauthError == "invalid_scope" {
            return String(
                localized: "鲲Galgame OAuth客户端尚未开放NextMoe内容权限，请稍后再试。"
            )
        }
        return message
    }

    var permanentlyInvalidatesSession: Bool {
        if [10002, 10003, 10014, 15001, 15005, 15008]
            .contains(code) {
            return true
        }
        return ["invalid_client", "invalid_grant", "unauthorized_client"]
            .contains(oauthError)
    }
}

private enum 鲲OAuth本地错误: LocalizedError {
    case notConfigured
    case randomGenerationFailed
    case invalidAuthorizationURL
    case failedToPresentLogin
    case invalidCallback
    case stateMismatch
    case missingAuthorizationCode
    case invalidResponse
    case catalogScopeRequired
    case loopbackListenerFailed(String)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(
                localized: "尚未配置鲲Galgame OAuth客户端ID。"
            )
        case .randomGenerationFailed:
            return String(localized: "无法生成安全的登录参数。")
        case .invalidAuthorizationURL:
            return String(localized: "无法创建登录地址。")
        case .failedToPresentLogin:
            return String(localized: "无法打开鲲Galgame登录页。")
        case .invalidCallback:
            return String(localized: "鲲Galgame返回了无效的登录结果。")
        case .stateMismatch:
            return String(localized: "登录验证失败。")
        case .missingAuthorizationCode:
            return String(localized: "登录结果中缺少授权码。")
        case .invalidResponse:
            return String(localized: "鲲Galgame返回了无法识别的响应。")
        case .catalogScopeRequired:
            return String(
                localized: "鲲Galgame登录缺少NextMoe内容权限，请重新登录以授权。"
            )
        case let .loopbackListenerFailed(details):
            return String(
                localized: "无法启动鲲Galgame登录回调：\(details)"
            )
        case .keychain:
            return String(localized: "无法访问系统钥匙串。")
        }
    }
}

private struct 鲲OAuth凭据存储 {
    private let service = "com.jizpaper.PaperVN.kungal-oauth"
    private let account = "session"

    func read() throws -> 鲲OAuth凭据? {
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
            throw 鲲OAuth本地错误.keychain(status)
        }
        return try JSONDecoder().decode(鲲OAuth凭据.self, from: data)
    }

    func save(_ credentials: 鲲OAuth凭据) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let values: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            values as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw 鲲OAuth本地错误.keychain(updateStatus)
        }

        var newItem = query
        values.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw 鲲OAuth本地错误.keychain(addStatus)
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

private enum 鲲OAuthPKCE {
    static func makeVerifier() throws -> String {
        try randomURLSafeString(byteCount: 32)
    }

    static func makeState() throws -> String {
        try randomURLSafeString(byteCount: 32)
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        )
        guard status == errSecSuccess else {
            throw 鲲OAuth本地错误.randomGenerationFailed
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private nonisolated final class 鲲OAuthLoopback服务器: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(
        label: "com.jizpaper.PaperVN.kungal-oauth-loopback"
    )
    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<String, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var pendingCallback: URL?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(鲲OAuth配置.callbackHost),
            port: .any
        )
        parameters.acceptLocalOnly = true
        listener = try NWListener(using: parameters, on: .any)

        listener.stateUpdateHandler = { [weak self] state in
            self?.handle(state)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
    }

    func start() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                startContinuation = continuation
                lock.unlock()
                listener.start(queue: queue)
            }
        } onCancel: { [weak self] in
            self?.cancel()
        }
    }

    func waitForCallback() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let pendingCallback {
                    self.pendingCallback = nil
                    lock.unlock()
                    continuation.resume(returning: pendingCallback)
                } else {
                    callbackContinuation = continuation
                    lock.unlock()
                }
            }
        } onCancel: { [weak self] in
            self?.cancel()
        }
    }

    func cancel() {
        listener.cancel()

        lock.lock()
        let startContinuation = self.startContinuation
        self.startContinuation = nil
        let callbackContinuation = self.callbackContinuation
        self.callbackContinuation = nil
        self.pendingCallback = nil
        lock.unlock()

        startContinuation?.resume(throwing: CancellationError())
        callbackContinuation?.resume(throwing: CancellationError())
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port else {
                finishStart(
                    .failure(
                        鲲OAuth本地错误.loopbackListenerFailed(
                            "未能取得环回端口。"
                        )
                    )
                )
                return
            }
            finishStart(
                .success(
                    "http://\(鲲OAuth配置.callbackHost):\(port.rawValue)\(鲲OAuth配置.callbackPath)"
                )
            )
        case let .failed(error):
            finishStart(
                .failure(
                    鲲OAuth本地错误.loopbackListenerFailed(
                        error.localizedDescription
                    )
                )
            )
        case .waiting:
            break
        case .cancelled:
            finishStart(.failure(CancellationError()))
        case .setup:
            break
        @unknown default:
            finishStart(
                .failure(
                    鲲OAuth本地错误.loopbackListenerFailed(
                        "未知的环回监听状态。"
                    )
                )
            )
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let connection else { return }
            guard case .ready = state else {
                if case .failed = state {
                    connection.cancel()
                }
                return
            }

            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: 16 * 1024
            ) { [weak self, weak connection] data, _, _, _ in
                guard let connection else { return }
                guard let data,
                      let request = String(data: data, encoding: .utf8) else {
                    connection.cancel()
                    return
                }
                self?.handle(request, on: connection)
            }
        }
        connection.start(queue: queue)
    }

    private func handle(_ request: String, on connection: NWConnection) {
        let callbackURL: URL? = {
            guard let requestLine = request
                .components(separatedBy: "\r\n")
                .first else { return nil }
            let fields = requestLine.split(separator: " ")
            guard fields.count >= 2 else { return nil }
            return URL(
                string: "http://\(鲲OAuth配置.callbackHost):\(listener.port?.rawValue ?? 0)\(fields[1])"
            )
        }()

        let body = Data(
            "<html><meta charset=\"utf-8\"><body>登录完成。正在返回PaperVN…</body></html>"
                .utf8
        )
        let headers = Data(
            "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
                .utf8
        )
        connection.send(
            content: headers + body,
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )

        guard let callbackURL else { return }
        lock.lock()
        if let callbackContinuation {
            self.callbackContinuation = nil
            lock.unlock()
            callbackContinuation.resume(returning: callbackURL)
        } else {
            pendingCallback = callbackURL
            lock.unlock()
        }
        listener.cancel()
    }

    private func finishStart(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = startContinuation
        startContinuation = nil
        lock.unlock()
        guard let continuation else { return }

        switch result {
        case let .success(redirectURI):
            continuation.resume(returning: redirectURI)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

@MainActor
final class 鲲Galgame账户: NSObject, ObservableObject {
    private actor 目录访问令牌中心 {
        func token() async throws -> String {
            try await 鲲Galgame账户.读取并刷新NextMoe访问令牌()
        }
    }

    private static let 目录访问令牌中心实例 = 目录访问令牌中心()

    @Published private(set) var profile: 鲲用户资料?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isRestoringSession = true
    @Published private(set) var isAuthenticating = false
    @Published private(set) var isLoggingOut = false
    @Published var errorMessage: String?

    private let credentialStore = 鲲OAuth凭据存储()
    private var credentials: 鲲OAuth凭据?
    private var webAuthenticationTask: Task<Void, Never>?
    private var loopbackServer: 鲲OAuthLoopback服务器?
    private var pendingState: String?
    private var pendingCodeVerifier: String?
    private var pendingScopes: String?
    private var pendingRedirectURI: String?
    private var callbackTaskStarted = false

    private enum DefaultsKey {
        static let requiresFreshLogin = "kunOAuth.requiresFreshLogin"
    }

    init(previewing: Bool = false) {
        super.init()

        let isRunningForPreviews = ProcessInfo.processInfo.environment[
            "XCODE_RUNNING_FOR_PREVIEWS"
        ] == "1"
        guard !previewing && !isRunningForPreviews else {
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
            Task { [weak self] in
                await self?.restoreSession()
            }
        } catch {
            isRestoringSession = false
            errorMessage = error.localizedDescription
        }
    }

    var hasCatalogAccess: Bool {
        credentials?.hasCatalogAccess ?? false
    }

    func login(using authenticator: WebAuthenticationSession) {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            await self?.beginLogin(using: authenticator)
        }
    }

    private func beginLogin(
        using authenticator: WebAuthenticationSession
    ) async {
        do {
            guard 鲲OAuth配置.isConfigured else {
                throw 鲲OAuth本地错误.notConfigured
            }

            let verifier = try 鲲OAuthPKCE.makeVerifier()
            let state = try 鲲OAuthPKCE.makeState()
            let challenge = 鲲OAuthPKCE.challenge(for: verifier)

            let scopes = NextMoe内容设置.已启用
                ? 鲲OAuth配置.catalogScopes
                : 鲲OAuth配置.baseScopes

            let loopbackServer = try 鲲OAuthLoopback服务器()
            let redirectURI = try await loopbackServer.start()
            guard let authorizationURL = authorizationURL(
                state: state,
                challenge: challenge,
                scopes: scopes,
                redirectURI: redirectURI
            ) else {
                throw 鲲OAuth本地错误.invalidAuthorizationURL
            }

            pendingState = state
            pendingCodeVerifier = verifier
            pendingScopes = scopes
            pendingRedirectURI = redirectURI
            callbackTaskStarted = false
            self.loopbackServer = loopbackServer

            webAuthenticationTask = Task { [weak self] in
                do {
                    let callbackURL = try await authenticator.authenticate(
                        using: authorizationURL,
                        callback: .customScheme(鲲OAuth配置.callbackScheme),
                        preferredBrowserSession: .shared,
                        additionalHeaderFields: [:]
                    )
                    self?.webAuthenticationTask = nil
                    await self?.handleCallback(callbackURL)
                } catch {
                    // 回环服务器先收到回调或主动结束登录时会取消此任务，状态已由取消方处理。
                    guard !Task.isCancelled else { return }
                    self?.webAuthenticationTask = nil
                    if (error as? ASWebAuthenticationSessionError)?.code
                        == .canceledLogin {
                        self?.finishAuthentication()
                    } else {
                        self?.finishAuthentication(
                            error: error.localizedDescription
                        )
                    }
                }
            }

            Task { [weak self, loopbackServer] in
                guard let callbackURL = try? await loopbackServer.waitForCallback() else {
                    return
                }
                await self?.handleCallback(callbackURL)
            }
        } catch {
            let message = (error as? 鲲OAuth服务错误)?.userFacingMessage
                ?? error.localizedDescription
            finishAuthentication(error: message)
        }
    }

    func logout() {
        guard !isLoggingOut else { return }
        isLoggingOut = true
        let refreshToken = credentials?.refreshToken

        webAuthenticationTask?.cancel()
        webAuthenticationTask = nil
        loopbackServer?.cancel()
        loopbackServer = nil
        pendingState = nil
        pendingCodeVerifier = nil
        pendingScopes = nil
        pendingRedirectURI = nil
        callbackTaskStarted = false
        clearLocalSession()
        UserDefaults.standard.set(
            true,
            forKey: DefaultsKey.requiresFreshLogin
        )

        Task { [weak self] in
            if let refreshToken {
                try? await Self.revoke(refreshToken: refreshToken)
            }
            self?.isLoggingOut = false
        }
    }

    private func restoreSession() async {
        defer { isRestoringSession = false }
        guard var current = credentials else { return }

        do {
            if current.expiresAt <= Date().addingTimeInterval(30) {
                current = try await refresh(current)
            }

            do {
                current.profile = try await Self.fetchUserInfo(
                    accessToken: current.accessToken
                )
            } catch let error as 鲲OAuth服务错误
                where error.statusCode == 401 {
                current = try await refresh(current)
                current.profile = try await Self.fetchUserInfo(
                    accessToken: current.accessToken
                )
            }

            try save(current)
            profile = current.profile
            isLoggedIn = current.profile != nil
            errorMessage = nil
        } catch let error as 鲲OAuth服务错误
            where error.permanentlyInvalidatesSession {
            clearLocalSession()
            errorMessage = error.localizedDescription
        } catch {
            profile = current.profile
            isLoggedIn = current.profile != nil
            errorMessage = String(
                localized: "暂时无法验证鲲Galgame登录状态。"
            )
        }
    }

    private func handleCallback(_ url: URL) async {
        do {
            guard url.scheme?.lowercased() == 鲲OAuth配置.callbackScheme,
                  url.host?.lowercased() == 鲲OAuth配置.callbackHost,
                  url.path == 鲲OAuth配置.callbackPath,
                  let redirectURI = pendingRedirectURI,
                  let expectedRedirectURL = URL(string: redirectURI),
                  url.port == expectedRedirectURL.port,
                  let components = URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                  ) else {
                throw 鲲OAuth本地错误.invalidCallback
            }

            let queryItems = components.queryItems ?? []
            func queryValue(named name: String) throws -> String? {
                let matches = queryItems.filter { $0.name == name }
                guard matches.count <= 1 else {
                    throw 鲲OAuth本地错误.invalidCallback
                }
                return matches.first?.value
            }

            guard let expectedState = pendingState,
                  try queryValue(named: "state") == expectedState else {
                throw 鲲OAuth本地错误.stateMismatch
            }

            guard !callbackTaskStarted else { return }
            callbackTaskStarted = true

            if let oauthError = try queryValue(named: "error") {
                throw 鲲OAuth服务错误(
                    statusCode: 400,
                    code: nil,
                    oauthError: oauthError,
                    message: try queryValue(named: "error_description")
                        ?? String(localized: "鲲Galgame拒绝了登录请求。")
                )
            }
            guard let code = try queryValue(named: "code"), !code.isEmpty else {
                throw 鲲OAuth本地错误.missingAuthorizationCode
            }
            guard let verifier = pendingCodeVerifier else {
                throw 鲲OAuth本地错误.invalidCallback
            }

            let token = try await Self.exchangeCode(
                code,
                verifier: verifier,
                redirectURI: redirectURI
            )
            var newCredentials = 鲲OAuth凭据(
                accessToken: token.accessToken,
                refreshToken: token.refreshToken,
                expiresAt: Date().addingTimeInterval(
                    TimeInterval(token.expiresIn)
                ),
                scope: token.scope ?? pendingScopes ?? 鲲OAuth配置.baseScopes,
                profile: nil
            )
            try save(newCredentials)
            newCredentials.profile = try await Self.fetchUserInfo(
                accessToken: token.accessToken
            )
            try save(newCredentials)

            profile = newCredentials.profile
            isLoggedIn = newCredentials.profile != nil
            UserDefaults.standard.removeObject(
                forKey: DefaultsKey.requiresFreshLogin
            )
            finishAuthentication()
        } catch {
            let message = (error as? 鲲OAuth服务错误)?.userFacingMessage
                ?? error.localizedDescription
            finishAuthentication(error: message)
        }
    }

    private func authorizationURL(
        state: String,
        challenge: String,
        scopes: String,
        redirectURI: String
    ) -> URL? {
        var components = URLComponents(
            url: 鲲OAuth配置.apiBaseURL
                .appending(path: "oauth/authorize"),
            resolvingAgainstBaseURL: false
        )
        var queryItems = [
            URLQueryItem(name: "client_id", value: 鲲OAuth配置.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if UserDefaults.standard.bool(
            forKey: DefaultsKey.requiresFreshLogin
        ) {
            queryItems.append(URLQueryItem(name: "prompt", value: "login"))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func refresh(_ current: 鲲OAuth凭据) async throws
        -> 鲲OAuth凭据 {
        let token = try await Self.requestToken(
            鲲OAuth令牌请求(
                grantType: "refresh_token",
                clientID: 鲲OAuth配置.clientID,
                code: nil,
                redirectURI: nil,
                codeVerifier: nil,
                refreshToken: current.refreshToken
            )
        )
        let refreshed = 鲲OAuth凭据(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(
                TimeInterval(token.expiresIn)
            ),
            scope: token.scope ?? current.scope,
            profile: current.profile
        )
        try save(refreshed)
        return refreshed
    }

    private func save(_ newCredentials: 鲲OAuth凭据) throws {
        try credentialStore.save(newCredentials)
        credentials = newCredentials
    }

    private func clearLocalSession() {
        credentialStore.delete()
        credentials = nil
        profile = nil
        isLoggedIn = false
        isRestoringSession = false
        errorMessage = nil
    }

    private func finishAuthentication(error: String? = nil) {
        webAuthenticationTask?.cancel()
        webAuthenticationTask = nil
        loopbackServer?.cancel()
        loopbackServer = nil
        pendingState = nil
        pendingCodeVerifier = nil
        pendingScopes = nil
        pendingRedirectURI = nil
        callbackTaskStarted = false
        isAuthenticating = false
        errorMessage = error
    }

    private static func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: String
    ) async throws -> 鲲OAuth令牌 {
        try await requestToken(
            鲲OAuth令牌请求(
                grantType: "authorization_code",
                clientID: 鲲OAuth配置.clientID,
                code: code,
                redirectURI: redirectURI,
                codeVerifier: verifier,
                refreshToken: nil
            )
        )
    }

    static func 有效NextMoe访问令牌() async throws -> String {
        try await 目录访问令牌中心实例.token()
    }

    private static func 读取并刷新NextMoe访问令牌() async throws -> String {
        let store = 鲲OAuth凭据存储()
        guard var credentials = try store.read() else {
            throw 鲲OAuth本地错误.catalogScopeRequired
        }

        guard credentials.hasCatalogAccess else {
            throw 鲲OAuth本地错误.catalogScopeRequired
        }

        guard credentials.expiresAt <= Date().addingTimeInterval(60) else {
            return credentials.accessToken
        }

        let token = try await requestToken(
            鲲OAuth令牌请求(
                grantType: "refresh_token",
                clientID: 鲲OAuth配置.clientID,
                code: nil,
                redirectURI: nil,
                codeVerifier: nil,
                refreshToken: credentials.refreshToken
            )
        )
        credentials = 鲲OAuth凭据(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(token.expiresIn)),
            scope: token.scope ?? credentials.scope,
            profile: credentials.profile
        )
        try store.save(credentials)
        return credentials.accessToken
    }

    private static func requestToken(
        _ body: 鲲OAuth令牌请求
    ) async throws -> 鲲OAuth令牌 {
        try await request(
            path: "oauth/token",
            method: "POST",
            body: try encoded(body),
            response: 鲲OAuth令牌.self
        )
    }

    private static func fetchUserInfo(
        accessToken: String
    ) async throws -> 鲲用户资料 {
        var profile: 鲲用户资料 = try await request(
            path: "oauth/userinfo",
            method: "GET",
            authorization: "Bearer \(accessToken)",
            response: 鲲用户资料.self
        )
        let details: 鲲账户详细资料? = try? await request(
            path: "auth/me",
            method: "GET",
            authorization: "Bearer \(accessToken)",
            response: 鲲账户详细资料.self
        )
        if let details {
            profile = profile.merging(details)
        }
        return profile
    }

    private static func revoke(refreshToken: String) async throws {
        let _: EmptyResponse = try await request(
            path: "oauth/revoke",
            method: "POST",
            body: try encoded(
                鲲OAuth撤销请求(token: refreshToken)
            ),
            response: EmptyResponse.self,
            allowsEmptyData: true
        )
    }

    private struct EmptyResponse: Decodable {}

    private static func encoded<Body: Encodable>(
        _ body: Body
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(body)
    }

    private static func request<Response: Decodable>(
        path: String,
        method: String,
        body: Data? = nil,
        authorization: String? = nil,
        response: Response.Type,
        allowsEmptyData: Bool = false
    ) async throws -> Response {
        var request = URLRequest(
            url: 鲲OAuth配置.apiBaseURL.appending(path: path)
        )
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authorization {
            request.setValue(
                authorization,
                forHTTPHeaderField: "Authorization"
            )
        }
        if let body {
            request.httpBody = body
            request.setValue(
                "application/json",
                forHTTPHeaderField: "Content-Type"
            )
        }

        let (data, urlResponse) = try await URLSession.shared.data(
            for: request
        )
        guard let http = urlResponse as? HTTPURLResponse else {
            throw 鲲OAuth本地错误.invalidResponse
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard (200..<300).contains(http.statusCode) else {
            let wire = try? decoder.decode(鲲OAuth错误响应.self, from: data)
            throw 鲲OAuth服务错误(
                statusCode: http.statusCode,
                code: wire?.code,
                oauthError: wire?.error,
                message: wire?.message
                    ?? wire?.errorDescription
                    ?? String(localized: "鲲Galgame请求失败。")
            )
        }

        if allowsEmptyData, data.isEmpty {
            guard let empty = EmptyResponse() as? Response else {
                throw 鲲OAuth本地错误.invalidResponse
            }
            return empty
        }
        if let envelope = try? decoder.decode(
            鲲OAuth响应<Response>.self,
            from: data
        ) {
            if let code = envelope.code, code != 0 {
                throw 鲲OAuth服务错误(
                    statusCode: http.statusCode,
                    code: code,
                    oauthError: nil,
                    message: envelope.message
                        ?? String(localized: "鲲Galgame请求失败。")
                )
            }
            if let value = envelope.data {
                return value
            }
            if allowsEmptyData,
               let empty = EmptyResponse() as? Response {
                return empty
            }
        }
        if let value = try? decoder.decode(Response.self, from: data) {
            return value
        }
        throw 鲲OAuth本地错误.invalidResponse
    }
}
