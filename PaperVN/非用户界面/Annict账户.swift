import AuthenticationServices
import Combine
import Foundation
import SwiftUI

/// Annict 使用 OAuth 2.0 授权码方式。换取令牌需要 client secret，所以和 Bangumi 一样由 PaperVN Sync 服务器代办。
/// 在 Annict 注册应用时，Redirect URI 填 `papervn://oauth/annict`，权限选择读取和写入。令牌不会过期。
enum AnnictOAuth配置 {
    static let callbackScheme = "papervn"
    static let redirectURI = "papervn://oauth/annict"
    static let endpoint = URL(string: "https://api.annict.com/graphql")!
    static let tokenURL = URL(string: "https://papervn.jizpaper.com/api/sync/oauth/annict/token")!

    static var clientID: String { 平台账户工具.infoValue("AnnictClientID", environment: "ANNICT_CLIENT_ID") }
    static var isConfigured: Bool { !clientID.isEmpty }
}

struct Annict用户资料: Codable, Equatable {
    let annictId: Int
    let username: String
    let name: String
    let avatarUrl: String?
}

private struct Annict凭据: Codable {
    var accessToken: String
    var profile: Annict用户资料
}

/// Annict 账户：登录，以及动画观看状态的读写。Annict 只有动画，也不同步评分与进度。
@MainActor
final class Annict账户: ObservableObject {
    @Published private(set) var profile: Annict用户资料?
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isAuthenticating = false
    @Published var errorMessage: String?

    private let credentialStore = 钥匙串凭据存储<Annict凭据>(service: "com.jizpaper.PaperVN.annict-oauth")
    private var credentials: Annict凭据?
    private var pendingState: String?
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
        guard AnnictOAuth配置.isConfigured else {
            errorMessage = 平台账户错误.notConfigured("Annict").localizedDescription
            return
        }
        let state = 平台账户工具.randomString(length: 32)
        var components = URLComponents(string: "https://annict.com/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AnnictOAuth配置.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AnnictOAuth配置.redirectURI),
            URLQueryItem(name: "scope", value: "read write"),
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
                    callback: .customScheme(AnnictOAuth配置.callbackScheme),
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
            if let error = value("error") {
                throw 平台账户错误.service("Annict", value("error_description") ?? error)
            }
            if let state = value("state"), state != pendingState {
                throw 平台账户错误.loginIncomplete("Annict")
            }
            guard let code = value("code"), !code.isEmpty else {
                throw 平台账户错误.loginIncomplete("Annict")
            }
            let token = try await Self.exchange(code: code)
            let profile = try await Self.viewer(accessToken: token)
            let newCredentials = Annict凭据(accessToken: token, profile: profile)
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

    private static func exchange(code: String) async throws -> String {
        var request = URLRequest(url: AnnictOAuth配置.tokenURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["grant_type": "authorization_code", "code": code])
        let (data, response) = try await URLSession.shared.data(for: request)
        struct 令牌: Decodable {
            struct 服务器错误: Decodable { let message: String? }
            let access_token: String?
            let error: String?
            let error_description: String?
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let token = try? JSONDecoder().decode(令牌.self, from: data)
        guard (200...299).contains(status), let accessToken = token?.access_token else {
            struct 包装: Decodable { struct 内容: Decodable { let message: String? }; let error: 内容? }
            let message = (try? JSONDecoder().decode(包装.self, from: data))?.error?.message
                ?? token?.error_description ?? token?.error
            throw 平台账户错误.service("Annict", message)
        }
        return accessToken
    }

    private static func viewer(accessToken: String) async throws -> Annict用户资料 {
        struct 响应: Decodable {
            struct 数据: Decodable { let viewer: Annict用户资料 }
            let data: 数据
        }
        let data = try await 平台账户工具.graphQL(
            endpoint: AnnictOAuth配置.endpoint,
            platform: "Annict",
            accessToken: accessToken,
            query: "query { viewer { annictId username name avatarUrl } }"
        )
        guard let viewer = try? JSONDecoder().decode(响应.self, from: data).data.viewer else {
            throw 平台账户错误.invalidResponse("Annict")
        }
        return viewer
    }

    private func accessToken() throws -> String {
        guard let credentials else { throw 平台账户错误.notLoggedIn("Annict") }
        return credentials.accessToken
    }

    // MARK: 资料库

    func 读取资料库() async throws -> [平台资料库记录] {
        let token = try accessToken()
        let query = """
        query ($after: String) {
          viewer {
            libraryEntries(first: 100, after: $after, states: [WANNA_WATCH, WATCHING, WATCHED, ON_HOLD, STOP_WATCHING]) {
              pageInfo { hasNextPage endCursor }
              nodes {
                status { state }
                work {
                  id annictId malAnimeId title titleEn titleRo episodesCount noEpisodes seasonYear
                  image { recommendedImageUrl }
                }
              }
            }
          }
        }
        """
        var results: [平台资料库记录] = []
        var cursor: String?
        while true {
            try Task.checkCancellation()
            var variables: [String: Any] = [:]
            if let cursor { variables["after"] = cursor }
            let data = try await 平台账户工具.graphQL(
                endpoint: AnnictOAuth配置.endpoint,
                platform: "Annict",
                accessToken: token,
                query: query,
                variables: variables
            )
            guard let page = try? JSONDecoder().decode(Annict列表响应.self, from: data).data.viewer.libraryEntries else {
                throw 平台账户错误.invalidResponse("Annict")
            }
            results += page.nodes.compactMap(\.记录)
            guard page.pageInfo.hasNextPage, let next = page.pageInfo.endCursor else { break }
            cursor = next
        }
        return results
    }

    /// 修改观看状态。删除就是把状态改为“未选择”。
    func 设置状态(workID: String, 状态 status: 资料库状态?) async throws {
        _ = try await 平台账户工具.graphQL(
            endpoint: AnnictOAuth配置.endpoint,
            platform: "Annict",
            accessToken: try accessToken(),
            query: """
            mutation ($workId: ID!, $state: StatusState!) {
              updateStatus(input: { workId: $workId, state: $state }) { work { id } }
            }
            """,
            variables: ["workId": workID, "state": status.map(Self.stateValue) ?? "NO_STATE"]
        )
    }

    private static func stateValue(_ status: 资料库状态) -> String {
        switch status {
        case .inProgress: "WATCHING"
        case .completed: "WATCHED"
        case .onHold: "ON_HOLD"
        case .dropped: "STOP_WATCHING"
        case .planning: "WANNA_WATCH"
        }
    }

    fileprivate static func status(from value: String?) -> 资料库状态? {
        switch value {
        case "WATCHING": .inProgress
        case "WATCHED": .completed
        case "ON_HOLD": .onHold
        case "STOP_WATCHING": .dropped
        case "WANNA_WATCH": .planning
        default: nil
        }
    }
}

private struct Annict列表响应: Decodable {
    struct 数据: Decodable { let viewer: 用户 }
    struct 用户: Decodable { let libraryEntries: 连接 }
    struct 连接: Decodable {
        struct 分页: Decodable { let hasNextPage: Bool; let endCursor: String? }
        let pageInfo: 分页
        let nodes: [条目]
    }
    struct 条目: Decodable {
        struct 状态: Decodable { let state: String }
        struct 作品: Decodable {
            struct 图片: Decodable { let recommendedImageUrl: String? }
            let id: String
            let annictId: Int
            let malAnimeId: String?
            let title: String
            let titleEn: String?
            let titleRo: String?
            let episodesCount: Int
            let noEpisodes: Bool
            let seasonYear: Int?
            let image: 图片?
        }
        let status: 状态?
        let work: 作品

        var 记录: 平台资料库记录? {
            guard let status = Annict账户.status(from: status?.state) else { return nil }
            let image = work.image?.recommendedImageUrl
            return 平台资料库记录(
                平台: .annict,
                平台ID: work.id,
                类型: .anime,
                malID: work.malAnimeId.flatMap { Int($0) },
                标题: work.title,
                日文标题: work.title,
                封面地址: image?.isEmpty == false ? image : nil,
                快照: 同步快照(状态: status, 评分: nil, 进度: nil),
                总数: work.noEpisodes || work.episodesCount == 0 ? nil : work.episodesCount,
                平均评分: nil,
                发行日期: work.seasonYear.map { String($0) },
                开始日期: nil,
                完成日期: nil,
                修改时间: nil,
                多语言标题: 作品多语言标题.生成(原名: work.title, 原名语言: "ja", 罗马字: work.titleRo, 英文: work.titleEn)
            )
        }
    }
    let data: 数据
}

extension Annict账户 {
    /// 手动匹配时搜索作品；输入作品编号或作品页面的链接时直接读取这部作品。
    func 搜索候选(关键词 query: String) async throws -> [匹配候选] {
        struct 响应: Decodable {
            struct 数据: Decodable { struct 结果: Decodable { let nodes: [作品] }; let searchWorks: 结果 }
            struct 作品: Decodable {
                struct 图片: Decodable { let recommendedImageUrl: String? }
                let id: String
                let title: String
                let titleEn: String?
                let seasonYear: Int?
                let media: String?
                let image: 图片?
            }
            let data: 数据
        }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let id = 匹配候选编号(text, 链接: "annict.com/works/")
        let data = try await 平台账户工具.graphQL(
            endpoint: AnnictOAuth配置.endpoint,
            platform: "Annict",
            accessToken: try accessToken(),
            query: id == nil
                ? "query ($titles: [String!]) { searchWorks(titles: $titles, first: 20) { nodes { id title titleEn seasonYear media image { recommendedImageUrl } } } }"
                : "query ($ids: [Int!]) { searchWorks(annictIds: $ids, first: 1) { nodes { id title titleEn seasonYear media image { recommendedImageUrl } } } }",
            variables: id.map { ["ids": [$0]] } ?? ["titles": [text]]
        )
        guard let works = try? JSONDecoder().decode(响应.self, from: data).data.searchWorks.nodes else {
            throw 平台账户错误.invalidResponse("Annict")
        }
        return works.map { work in
            匹配候选(
                id: work.id, 标题: work.title, 标题语言: "ja",
                其他标题: work.titleEn.flatMap { $0.isEmpty ? nil : $0 }, 其他标题语言: "en",
                年份: work.seasonYear,
                封面: work.image?.recommendedImageUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                种类: work.media
            )
        }
    }
}

#if DEBUG
extension Annict账户 {
    /// 预览用：已登录的账户，不读写钥匙串。
    static func 预览已登录(_ profile: Annict用户资料) -> Annict账户 {
        let account = Annict账户(previewing: true)
        account.profile = profile
        account.isLoggedIn = true
        return account
    }
}
#endif
