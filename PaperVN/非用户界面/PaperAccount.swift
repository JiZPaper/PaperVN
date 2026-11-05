import AuthenticationServices
import Combine
import CryptoKit
import DeviceCheck
import Foundation

/// Paper Account：PaperVN 自己的账户，用 Sign in with Apple 登录，不设密码。
/// 反馈、贡献翻译、Today 推荐用它识别用户；资料库会自动备份到它，删除 App 后重新登录即可恢复。
/// 服务器在 deploy/vps/papervn-account.mjs，接口与字段名两边保持一致。
enum PaperAccount配置 {
    static let 地址 = URL(string: "https://account.jizpaper.com/")!
    static let 自动备份键 = "paperAccountAutomaticBackup"
    static let 高级数据保护键 = "paperAccountAdvancedDataProtection"
}

nonisolated struct PaperAccount资料: Codable, Equatable, Sendable {
    let id: String
    var nickname: String?
    let createdAt: String
}

nonisolated struct 云端备份版本: Codable, Identifiable, Hashable, Sendable {
    let version: Int
    let createdAt: Date
    /// 端对端加密的版本没有作品数与原因，它们在密文里。
    let entryCount: Int?
    let reason: String?
    let size: Int
    let encrypted: Bool?

    var id: Int { version }
}

nonisolated struct 云端资料库: Codable, Identifiable, Hashable, Sendable {
    let owner: String
    let versions: [云端备份版本]

    var id: String { owner }
}

nonisolated struct VNDB迁移结果: Codable, Sendable {
    let feedback: Int?
    let todayRecommendations: Int?
    let translations: Int?
}

enum PaperAccount错误: LocalizedError {
    case 未登录
    case 服务(code: String, message: String)
    case 无效响应
    case 需要恢复密钥

    var errorDescription: String? {
        switch self {
        case .未登录: String(localized: "请先登录Paper账户。")
        case .需要恢复密钥: String(localized: "此账户已打开高级数据保护。输入恢复密钥以在此设备上访问Paper Cloud数据。")
        case let .服务(_, message): message
        case .无效响应: String(localized: "Paper账户暂时不可用。")
        }
    }

    var code: String? {
        if case let .服务(code, _) = self { return code }
        return nil
    }
}

private nonisolated struct PaperAccount凭据: Codable {
    var accessToken: String
    var accessTokenExpiresAt: Date
    var refreshToken: String
    var account: PaperAccount资料
}

private nonisolated struct 令牌响应: Decodable {
    let account: PaperAccount资料
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let created: Bool?
}

private nonisolated struct 错误响应: Decodable {
    struct 内容: Decodable {
        let code: String
        let message: String
        let currentVersion: Int?
    }
    let error: 内容
}

@MainActor
final class PaperAccount账户: ObservableObject {
    static let shared = PaperAccount账户()

    @Published private(set) var 资料: PaperAccount资料?
    @Published private(set) var 云端资料库: [云端资料库] = []
    @Published private(set) var 正在备份 = false
    @Published private(set) var 上次备份时间: Date?
    @Published private(set) var 备份错误: String?
    @Published private(set) var 正在登录 = false
    /// 登录前预先取得的挑战。Sign in with Apple 按钮的 nonce 必须同步给出，所以提前准备好。
    @Published private(set) var 登录挑战: String?
    /// 服务器上的高级数据保护设置，没有开启时为 nil。缓存在本机，打开页面时不用等网络。
    @Published private(set) var 高级数据保护设置: 高级数据保护.云端设置?

    var isLoggedIn: Bool { 资料 != nil }
    var 已开启高级数据保护: Bool { 高级数据保护设置 != nil }

    /// 已开启高级数据保护，但此设备的钥匙串里没有对应的资料库密钥（不是受信任设备）。
    var 需要恢复密钥: Bool {
        guard let settings = 高级数据保护设置, let accountID = 资料?.id else { return false }
        return 资料库密钥存储.读取(账户ID: accountID)?.keyID != settings.keyID
    }

    /// Today 推荐页面沿用 VNDB账户 的形式：用户ID 是账户 ID（服务器以令牌为准，不信任它），用户名是昵称。
    var Today账户: VNDB账户? {
        资料.map { VNDB账户(userID: $0.id, username: $0.nickname ?? String(localized: "未设置昵称"), 已登录: true) }
    }

    private let 凭据存储 = 钥匙串凭据存储<PaperAccount凭据>(service: "com.jizpaper.PaperVN.paper-account")
    private var 凭据: PaperAccount凭据?
    private var 刷新任务: Task<PaperAccount凭据, Error>?
    private var 备份任务: Task<Void, Never>?
    private var 同步任务: Task<Void, Never>?
    private var 待备份原因: 资料库更改原因?
    private let 设备验证 = PaperAccount设备验证()

    private init() {
        凭据 = try? 凭据存储.read()
        资料 = 凭据?.account
        上次备份时间 = UserDefaults.standard.object(forKey: "paperAccountLastBackup") as? Date
        高级数据保护设置 = UserDefaults.standard.data(forKey: PaperAccount配置.高级数据保护键)
            .flatMap { try? JSONDecoder().decode(高级数据保护.云端设置.self, from: $0) }
    }

    /// Paper Cloud 开关：开启后资料库与最近更改自动上传，并与其他设备同步。
    var 自动备份: Bool {
        get { UserDefaults.standard.object(forKey: PaperAccount配置.自动备份键) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: PaperAccount配置.自动备份键)
            if newValue { Task { await 同步资料库() } }
        }
    }

    // MARK: 登录

    /// 准备 Sign in with Apple 的 nonce。挑战 5 分钟内有效，按钮出现时和每次登录失败后重新获取。
    func 准备登录() async {
        登录挑战 = try? await 获取挑战()
    }

    /// Sign in with Apple 请求的 nonce：挑战的 SHA256。服务器用同样的方法核对。
    static func nonce(_ challenge: String) -> String {
        SHA256.hash(data: Data(challenge.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Sign in with Apple 完成后调用。首次登录即创建账户；登录后自动迁移以前用VNDB提交的内容，并备份资料库。
    func 登录(credential: ASAuthorizationAppleIDCredential, vndbToken: String) async throws {
        guard let challenge = 登录挑战,
              let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw PaperAccount错误.无效响应
        }
        登录挑战 = nil
        正在登录 = true
        defer { 正在登录 = false }

        let name = credential.fullName.map {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
        }
        var body: [String: Any] = [
            "identityToken": identityToken,
            "challenge": challenge,
        ]
        if let code = credential.authorizationCode.flatMap({ String(data: $0, encoding: .utf8) }) {
            body["authorizationCode"] = code
        }
        if let name, !name.isEmpty { body["nickname"] = String(name.prefix(30)) }

        let keyID = await 设备验证.可用密钥(获取挑战: { try await self.获取挑战() }, 登记: { try await self.登记设备($0, $1, $2) })
        if let keyID { body["keyID"] = keyID }
        let data = try JSONSerialization.data(withJSONObject: body)
        let response: 令牌响应
        do {
            response = try await 发送(令牌响应.self, 路径: "sign-in", 方法: "POST", 内容: data, 断言密钥: keyID)
        } catch let error as PaperAccount错误 where error.code?.hasPrefix("app_attest") == true && keyID != nil {
            // 服务器不认识这个密钥，或者这次没能生成断言：废弃密钥，这次不带设备验证登录，下次登录时重新登记
            await 设备验证.废弃()
            body["keyID"] = nil
            response = try await 发送(令牌响应.self, 路径: "sign-in", 方法: "POST", 内容: try JSONSerialization.data(withJSONObject: body))
        }
        保存凭据(PaperAccount凭据(
            accessToken: response.accessToken,
            accessTokenExpiresAt: response.accessTokenExpiresAt,
            refreshToken: response.refreshToken,
            account: response.account
        ))
        if !vndbToken.isEmpty { await 迁移VNDB(token: vndbToken) }
        await 关联设备()
        await 刷新云端资料库()
        // 登录后资料库改属 Paper Account（由 资料库身份 搬过去），随后同步
    }

    func 退出登录() async {
        if let refreshToken = 凭据?.refreshToken,
           let data = try? JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken]) {
            _ = try? await 发送(空响应.self, 路径: "sign-out", 方法: "POST", 内容: data)
        }
        清除本机凭据()
    }

    private func 清除本机凭据() {
        凭据存储.delete()
        凭据 = nil
        资料 = nil
        云端资料库 = []
        备份任务?.cancel()
        UserDefaults.standard.removeObject(forKey: "paperAccountLastBackup")
        上次备份时间 = nil
        更新高级数据保护设置(nil)
        游玩路径中心.shared.清除()
    }

    func 修改昵称(_ nickname: String) async throws {
        let value = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try JSONSerialization.data(withJSONObject: ["nickname": value.isEmpty ? NSNull() as Any : value as Any])
        struct 响应: Decodable { let account: PaperAccount资料 }
        let response = try await 发送(响应.self, 路径: "me", 方法: "PATCH", 内容: data, 需要登录: true)
        if var credentials = 凭据 {
            credentials.account = response.account
            保存凭据(credentials)
        }
    }

    /// 注销：用 Sign in with Apple 重新验证后，服务器删除此账户在 PaperVN 服务器上的全部数据。
    func 注销(credential: ASAuthorizationAppleIDCredential, challenge: String) async throws {
        guard let identityToken = credential.identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw PaperAccount错误.无效响应
        }
        let data = try JSONSerialization.data(withJSONObject: ["identityToken": identityToken, "challenge": challenge])
        let keyID = await 设备验证.已登记密钥()
        _ = try await 发送(空响应.self, 路径: "me", 方法: "DELETE", 内容: data, 需要登录: true, 断言密钥: keyID)
        if let accountID = 资料?.id { 资料库密钥存储.删除(账户ID: accountID) }
        清除本机凭据()
        UserDefaults.standard.removeObject(forKey: "paperAccountMigratedVNDB")
    }

    // MARK: 迁移

    /// 把以前用VNDB登录时提交的反馈、Today推荐与翻译转到 Paper Account。VNDB Token 只用来让服务器验证身份，不会保存。
    @discardableResult
    func 迁移VNDB(token: String) async -> VNDB迁移结果? {
        guard isLoggedIn, !token.isEmpty, let accountID = 资料?.id else { return nil }
        // 同一个账户与同一个VNDB Token只迁移一次
        let marker = "\(accountID):\(Self.nonce(token).prefix(16))"
        guard UserDefaults.standard.string(forKey: "paperAccountMigratedVNDB") != marker else { return nil }
        struct 响应: Decodable {
            let account: PaperAccount资料
            let migrated: VNDB迁移结果
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["vndbToken": token]),
              let response = try? await 发送(响应.self, 路径: "migrations/vndb", 方法: "POST", 内容: data, 需要登录: true) else { return nil }
        UserDefaults.standard.set(marker, forKey: "paperAccountMigratedVNDB")
        if var credentials = 凭据 {
            credentials.account = response.account
            保存凭据(credentials)
        }
        return response.migrated
    }

    // MARK: 高级数据保护

    private func 更新高级数据保护设置(_ settings: 高级数据保护.云端设置?) {
        if 高级数据保护设置 != settings { 高级数据保护设置 = settings }
        if let settings, let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: PaperAccount配置.高级数据保护键)
        } else {
            UserDefaults.standard.removeObject(forKey: PaperAccount配置.高级数据保护键)
        }
    }

    /// 用刚确认过的恢复密钥开启高级数据保护：生成新的资料库密钥存进 iCloud 钥匙串，再把用恢复密钥加密的一份交给服务器，
    /// 随后的同步上传密文，服务器删掉以前的版本。
    func 开启高级数据保护(恢复密钥 recoveryKey: String) async throws {
        guard let accountID = 资料?.id else { throw PaperAccount错误.未登录 }
        let key = 高级数据保护.生成密钥()
        let settings = try 高级数据保护.包装(key, 恢复密钥: recoveryKey, 账户ID: accountID)
        // 先存进钥匙串：服务器设置成功而本机没有密钥的话，这台设备就解不开自己的资料库了
        try 资料库密钥存储.存储(key, 账户ID: accountID)
        try await 更改高级数据保护(settings)
        await 同步资料库()
    }

    /// 关闭后随后的同步上传普通的快照，服务器删掉密文版本。不需要资料库密钥，没有受信任设备时也能关闭。
    /// 钥匙串里的密钥留着：还没换成普通版本之前，其他设备可能还要用它解开云端的密文；再次开启时会换一把新的。
    func 关闭高级数据保护() async throws {
        guard isLoggedIn else { throw PaperAccount错误.未登录 }
        try await 更改高级数据保护(nil)
        await 同步资料库()
    }

    /// 在不是受信任设备的设备上用恢复密钥取回资料库密钥。
    func 输入恢复密钥(_ recoveryKey: String) async throws {
        guard let accountID = 资料?.id else { throw PaperAccount错误.未登录 }
        try await 刷新云端资料库(抛出错误: true)
        guard let settings = 高级数据保护设置 else { return }
        let key = try 高级数据保护.解包(settings, 恢复密钥: recoveryKey, 账户ID: accountID)
        try 资料库密钥存储.存储(key, 账户ID: accountID)
        objectWillChange.send()
        await 同步资料库()
    }

    private func 更改高级数据保护(_ settings: 高级数据保护.云端设置?) async throws {
        struct 响应: Decodable { let advancedDataProtection: 高级数据保护.云端设置? }
        let body = try settings.map { try JSONEncoder().encode($0) }
        let response = try await 发送(
            响应.self, 路径: "advanced-data-protection", 方法: settings == nil ? "DELETE" : "PUT", 内容: body,
            需要登录: true, 断言密钥: await 设备验证.已登记密钥()
        )
        更新高级数据保护设置(response.advancedDataProtection)
    }

    /// 当前用来加解密的资料库密钥。开启了高级数据保护而此设备没有对应的密钥时抛出 需要恢复密钥。
    private func 当前资料库密钥() throws -> 高级数据保护.资料库密钥? {
        guard let settings = 高级数据保护设置 else { return nil }
        guard let accountID = 资料?.id, let key = 资料库密钥存储.读取(账户ID: accountID), key.keyID == settings.keyID else {
            throw PaperAccount错误.需要恢复密钥
        }
        return key
    }

    // MARK: 云端备份

    func 刷新云端资料库() async {
        try? await 刷新云端资料库(抛出错误: false)
    }

    private func 刷新云端资料库(抛出错误: Bool) async throws {
        guard isLoggedIn else { return }
        struct 响应: Decodable {
            let libraries: [云端资料库]
            let advancedDataProtection: 高级数据保护.云端设置?
        }
        do {
            let response = try await 发送(响应.self, 路径: "libraries", 方法: "GET", 需要登录: true)
            云端资料库 = response.libraries
            更新高级数据保护设置(response.advancedDataProtection)
        } catch {
            if 抛出错误 { throw error }
        }
    }

    /// 资料库每次有更改后调用：30秒内的多次更改合成一次同步，云端每个资料库保留最近10份。
    func 安排备份(原因 reason: 资料库更改原因?, 延迟: Duration = .seconds(30)) {
        guard isLoggedIn, 自动备份 else { return }
        // 合并云端的更改本身不需要再触发一次同步
        if reason == .云端同步 { return }
        if let reason { 待备份原因 = reason }
        备份任务?.cancel()
        备份任务 = Task { [weak self] in
            try? await Task.sleep(for: 延迟)
            guard !Task.isCancelled, let self else { return }
            await self.同步资料库()
        }
    }

    /// 与 Paper Account 同步资料库：先取回其他设备的更改与本机三方合并，再把结果上传。
    /// 资料库属于 Paper Account 时（只登录了 Paper Account 也可以），这就是资料库唯一的同步来源。
    func 同步资料库() async {
        guard isLoggedIn, 自动备份 else { return }
        if let 同步任务 {
            await 同步任务.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.执行同步()
                self.备份错误 = nil
            } catch {
                self.备份错误 = error.localizedDescription
            }
        }
        同步任务 = task
        await task.value
        同步任务 = nil
    }

    /// “立即同步”按钮：出错时把错误交给页面显示。
    func 立即备份() async throws {
        await 同步资料库()
        if let 备份错误 { throw PaperAccount错误.服务(code: "sync_failed", message: 备份错误) }
    }

    private func 执行同步() async throws {
        await 本地资料库.shared.等待载入()
        guard isLoggedIn, let owner = 本地资料库.shared.所有者, 本地资料库.shared.可写入,
              owner.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else { return }
        正在备份 = true
        defer { 正在备份 = false }
        资料库更改记录.shared.立即写入()

        // 其他设备同时在上传时，取回对方的版本重新合并，最多重试三次
        for _ in 0..<3 {
            guard 本地资料库.shared.所有者 == owner else { return }
            try await 刷新云端资料库(抛出错误: true)
            let libraryKey = try 当前资料库密钥()
            var state = PaperAccount资料库同步状态.读取(owner) ?? PaperAccount资料库同步状态()
            if let latest = 云端资料库.first(where: { $0.owner == owner })?.versions.last?.version, latest != state.版本 {
                let remote = try await 下载(owner: owner, 版本: latest)
                guard 本地资料库.shared.所有者 == owner else { return }
                let local = 本地资料库.shared.条目
                let merged = Self.合并(基准: state.版本 == nil ? nil : state.条目, 本机: local, 云端: remote.entries)
                await 资料库更改记录.shared.合并云端(
                    merged, 同步状态: local.isEmpty ? remote.sync : nil,
                    云端更改: remote.changes, 基准更改ID: Set(state.更改ID ?? [])
                )
                state = PaperAccount资料库同步状态(
                    版本: latest, 条目: remote.entries, 更改ID: remote.changes?.map(\.id),
                    密钥ID: 云端资料库.first(where: { $0.owner == owner })?.versions.last?.encrypted == true ? libraryKey?.keyID : nil
                )
                state.保存(owner)
            }

            let current = 本地资料库.shared.条目
            let changes = 资料库更改记录.shared.全部更改
            let unchanged = state.版本 != nil && 资料库差异项.比较(之前: state.条目, 之后: current).isEmpty
                && Set(state.条目.map(\.id)) == Set(current.map(\.id))
                && state.更改ID == changes.map(\.id)
                // 开启或关闭高级数据保护后，云端还是另一种加密方式的版本，要重新上传
                && state.密钥ID == libraryKey?.keyID
            if unchanged { return }

            let reason = 待备份原因
            let snapshot = 资料库快照(
                owner: owner, createdAt: .now, reason: reason?.标题, appVersion: 资料库快照.当前App版本,
                entries: current, sync: 同步状态存储.读取(owner: owner), changes: changes
            )
            let json = try 资料库快照.编码器().encode(snapshot)
            guard let compressed = try? (json as NSData).compressed(using: .zlib) as Data,
                  let accountID = 资料?.id else { throw PaperAccount错误.无效响应 }
            let body = try libraryKey.map { try 高级数据保护.加密(compressed, 密钥: $0, 账户ID: accountID, 所有者: owner) } ?? compressed
            do {
                let version = try await 上传(body, owner: owner, 版本: state.版本.map(String.init) ?? "*", 密钥ID: libraryKey?.keyID)
                待备份原因 = nil
                PaperAccount资料库同步状态(版本: version, 条目: current, 更改ID: changes.map(\.id), 密钥ID: libraryKey?.keyID).保存(owner)
                上次备份时间 = .now
                UserDefaults.standard.set(上次备份时间, forKey: "paperAccountLastBackup")
                return
            } catch let error as PaperAccount错误 where ["version_conflict", "advanced_data_protection_enabled", "advanced_data_protection_key_changed"].contains(error.code) {
                // 其他设备刚开启或关闭了高级数据保护：下一轮重新取得设置
                continue
            }
        }
    }

    /// 三方合并：只有一边改过的作品取改过的一边；两边都改过时取修改时间较新的。
    /// 第一次同步没有基准时取并集，不会因此删除任何作品。
    static func 合并(基准 base: [本地资料库条目]?, 本机 local: [本地资料库条目], 云端 remote: [本地资料库条目]) -> [本地资料库条目] {
        func index(_ entries: [本地资料库条目]) -> [String: 本地资料库条目] {
            Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        func same(_ a: 本地资料库条目?, _ b: 本地资料库条目?) -> Bool {
            switch (a, b) {
            case (nil, nil): true
            case let (a?, b?): 资料库差异项.用户记录相同(a, b)
            default: false
            }
        }
        let b = base.map(index)
        let l = index(local)
        let r = index(remote)
        var result: [本地资料库条目] = []
        for key in Set(l.keys).union(r.keys).union(b?.keys ?? [:].keys) {
            let mine = l[key], theirs = r[key]
            let chosen: 本地资料库条目?
            if same(mine, theirs) {
                chosen = mine ?? theirs
            } else if let b {
                if same(mine, b[key]) {
                    chosen = theirs
                } else if same(theirs, b[key]) {
                    chosen = mine
                } else if let mine, let theirs {
                    chosen = (theirs.修改时间 ?? .distantPast) > (mine.修改时间 ?? .distantPast) ? theirs : mine
                } else {
                    // 一边删除、一边修改：保留修改
                    chosen = mine ?? theirs
                }
            } else if let mine, let theirs {
                chosen = (theirs.修改时间 ?? .distantPast) > (mine.修改时间 ?? .distantPast) ? theirs : mine
            } else {
                chosen = mine ?? theirs
            }
            if let chosen { result.append(chosen) }
        }
        return result
    }

    @discardableResult
    private func 上传(_ body: Data, owner: String, 版本: String, 密钥ID keyID: String?) async throws -> Int {
        struct 响应: Decodable {
            let owner: String
            let versions: [云端备份版本]
        }
        let response = try await 发送(
            响应.self, 路径: "libraries/\(owner)", 方法: "PUT", 内容: body,
            内容类型: "application/octet-stream", 需要登录: true,
            断言密钥: await 设备验证.已登记密钥(),
            额外头: ["If-Match": 版本].merging(keyID.map { ["X-PaperVN-Library-Key": $0] } ?? [:]) { $1 }
        )
        云端资料库.removeAll { $0.owner == owner }
        云端资料库.insert(PaperVN.云端资料库(owner: response.owner, versions: response.versions), at: 0)
        return response.versions.last?.version ?? 0
    }

    func 下载(owner: String, 版本 version: Int) async throws -> 资料库快照 {
        var data = try await 原始请求(
            路径: "libraries/\(owner)/versions/\(version)", 方法: "GET", 需要登录: true,
            额外头: ["X-PaperVN-Accepts-Encrypted": "1"]
        )
        if 高级数据保护.是密文(data) {
            guard let accountID = 资料?.id, let key = 资料库密钥存储.读取(账户ID: accountID),
                  key.keyID == 高级数据保护.密钥ID(data) else { throw PaperAccount错误.需要恢复密钥 }
            data = try 高级数据保护.解密(data, 密钥: key, 账户ID: accountID, 所有者: owner)
        }
        guard let json = try? (data as NSData).decompressed(using: .zlib) as Data,
              let snapshot = try? 资料库快照.解码器().decode(资料库快照.self, from: json) else {
            throw PaperAccount错误.无效响应
        }
        return snapshot
    }

    /// 第三方 App 传入的游玩路径和已授权的 App。
    func 读取游玩路径() async throws -> 游玩路径内容 {
        try await 发送(游玩路径内容.self, 路径: "play-history", 方法: "GET", 需要登录: true)
    }

    /// 在 PaperVN 中运行视觉小说的时间。服务器按作品和起止时间去重，重发不会重复。
    func 上传游玩路径(_ sessions: [(vn: String, startedAt: Date, endedAt: Date)]) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let body = try JSONSerialization.data(withJSONObject: [
            "sessions": sessions.map {
                ["vn": $0.vn, "startedAt": formatter.string(from: $0.startedAt), "endedAt": formatter.string(from: $0.endedAt)]
            },
        ])
        _ = try await 发送(空响应.self, 路径: "play-history", 方法: "POST", 内容: body, 需要登录: true)
    }

    func 移除已授权App(_ id: String) async throws -> [已授权App] {
        struct 响应: Decodable { let apps: [已授权App] }
        return try await 发送(响应.self, 路径: "connected-apps/\(id)", 方法: "DELETE", 需要登录: true).apps
    }

    func 删除云端备份() async throws {
        _ = try await 发送(空响应.self, 路径: "libraries", 方法: "DELETE", 需要登录: true)
        云端资料库 = []
    }

    // MARK: 访问令牌

    /// 反馈、翻译和数据维护不登录也能用：已登录时返回令牌，未登录时返回 nil。
    func 可选访问令牌() async throws -> String? {
        isLoggedIn ? try await 访问令牌() : nil
    }

    /// 把这台设备关联到已登录的账户（解除限制的设置和设备上的内容）。
    func 关联设备() async {
        guard let id = 资料?.id, let token = try? await 访问令牌() else { return }
        await 敏感内容网页设置.关联Paper账户(accountID: id, token: token)
    }

    /// 其他服务（反馈、Today 推荐、翻译）使用的访问令牌，快过期时自动刷新。
    func 访问令牌() async throws -> String {
        guard var credentials = 凭据 else { throw PaperAccount错误.未登录 }
        if credentials.accessTokenExpiresAt.timeIntervalSinceNow < 60 {
            credentials = try await 刷新()
        }
        return credentials.accessToken
    }

    private func 刷新() async throws -> PaperAccount凭据 {
        if let 刷新任务 { return try await 刷新任务.value }
        guard let refreshToken = 凭据?.refreshToken else { throw PaperAccount错误.未登录 }
        let task = Task { [weak self] () throws -> PaperAccount凭据 in
            guard let self else { throw PaperAccount错误.未登录 }
            let data = try JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])
            do {
                let response = try await self.发送(
                    令牌响应.self, 路径: "refresh", 方法: "POST", 内容: data,
                    断言密钥: await self.设备验证.已登记密钥()
                )
                let credentials = PaperAccount凭据(
                    accessToken: response.accessToken,
                    accessTokenExpiresAt: response.accessTokenExpiresAt,
                    refreshToken: response.refreshToken,
                    account: response.account
                )
                self.保存凭据(credentials)
                return credentials
            } catch let error as PaperAccount错误 where ["session_expired", "account_not_found"].contains(error.code)
                        || error.code?.hasPrefix("app_attest") == true {
                self.清除本机凭据()
                throw error
            }
        }
        刷新任务 = task
        defer { 刷新任务 = nil }
        return try await task.value
    }

    private func 保存凭据(_ credentials: PaperAccount凭据) {
        try? 凭据存储.save(credentials)
        凭据 = credentials
        if 资料 != credentials.account { 资料 = credentials.account }
    }

    // MARK: 设备验证

    private func 获取挑战() async throws -> String {
        struct 响应: Decodable { let challenge: String }
        return try await 发送(响应.self, 路径: "challenge", 方法: "POST").challenge
    }

    private func 登记设备(_ keyID: String, _ attestation: Data, _ challenge: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "keyID": keyID,
            "attestation": attestation.base64EncodedString(),
            "challenge": challenge,
        ])
        _ = try await 发送(空响应.self, 路径: "attestations", 方法: "POST", 内容: data)
    }

    /// 注销时重新验证用的挑战。
    func 新挑战() async throws -> String { try await 获取挑战() }

    // MARK: 请求

    private struct 空响应: Decodable {}

    private func 发送<T: Decodable>(
        _ type: T.Type,
        路径 path: String,
        方法 method: String,
        内容 body: Data? = nil,
        内容类型 contentType: String = "application/json",
        需要登录: Bool = false,
        断言密钥: String? = nil,
        额外头: [String: String] = [:]
    ) async throws -> T {
        let data = try await 原始请求(
            路径: path, 方法: method, 内容: body, 内容类型: contentType,
            需要登录: 需要登录, 断言密钥: 断言密钥, 额外头: 额外头
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
        }
        if T.self == 空响应.self, let empty = 空响应() as? T { return empty }
        guard let value = try? decoder.decode(T.self, from: data) else { throw PaperAccount错误.无效响应 }
        return value
    }

    private func 原始请求(
        路径 path: String,
        方法 method: String,
        内容 body: Data? = nil,
        内容类型 contentType: String = "application/json",
        需要登录: Bool = false,
        断言密钥: String? = nil,
        额外头: [String: String] = [:],
        已重试: Bool = false
    ) async throws -> Data {
        let url = PaperAccount配置.地址.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        for (key, value) in 额外头 { request.setValue(value, forHTTPHeaderField: key) }
        if 需要登录 {
            request.setValue("Bearer \(try await 访问令牌())", forHTTPHeaderField: "Authorization")
        }
        if let keyID = 断言密钥,
           let assertion = await 设备验证.断言(密钥: keyID, 方法: method, 路径: url.path(), 内容: body ?? Data()) {
            request.setValue(keyID, forHTTPHeaderField: "X-PaperVN-Key-ID")
            request.setValue(assertion.断言, forHTTPHeaderField: "X-PaperVN-Assertion")
            request.setValue(assertion.时间, forHTTPHeaderField: "X-PaperVN-Timestamp")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PaperAccount错误.无效响应 }
        if (200..<300).contains(http.statusCode) { return data }
        let error = (try? JSONDecoder().decode(错误响应.self, from: data))
            .map { PaperAccount错误.服务(code: $0.error.code, message: $0.error.message) } ?? .无效响应
        // 访问令牌刚好过期：刷新后重试一次
        if 需要登录, !已重试, http.statusCode == 401, ["account_token_expired", "account_token_invalid"].contains(error.code) {
            _ = try await 刷新()
            return try await 原始请求(
                路径: path, 方法: method, 内容: body, 内容类型: contentType,
                需要登录: true, 断言密钥: 断言密钥, 额外头: 额外头, 已重试: true
            )
        }
        if http.statusCode == 401, error.code == "account_not_found" { 清除本机凭据() }
        // 设备密钥失效（例如恢复了其他设备的备份）：废弃后不带设备验证重试一次
        if !已重试, 断言密钥 != nil, path != "refresh", path != "sign-in", error.code?.hasPrefix("app_attest") == true {
            await 设备验证.废弃()
            return try await 原始请求(
                路径: path, 方法: method, 内容: body, 内容类型: contentType,
                需要登录: 需要登录, 断言密钥: nil, 额外头: 额外头, 已重试: true
            )
        }
        throw error
    }
}

/// App Attest：证明请求来自 App Store 上正版的 PaperVN，阻止脚本批量注册与刷接口。
/// 不支持的设备（例如模拟器）照常登录，只是服务器对这类请求的限制更严格。
actor PaperAccount设备验证 {
    private let 密钥键 = "paperAccountAppAttestKeyID"
    private let 已登记键 = "paperAccountAppAttestRegistered"

    /// 已经在服务器上登记过的密钥；没有时返回 nil。
    func 已登记密钥() -> String? {
        guard UserDefaults.standard.bool(forKey: 已登记键) else { return nil }
        return UserDefaults.standard.string(forKey: 密钥键)
    }

    /// 返回已登记的密钥；还没有时生成并登记。不支持或失败时返回 nil。
    func 可用密钥(
        获取挑战: @Sendable () async throws -> String,
        登记: @Sendable (String, Data, String) async throws -> Void
    ) async -> String? {
        if let key = 已登记密钥() { return key }
        let service = DCAppAttestService.shared
        guard service.isSupported else { return nil }
        do {
            let keyID = try await service.generateKey()
            let challenge = try await 获取挑战()
            let attestation = try await service.attestKey(keyID, clientDataHash: Data(SHA256.hash(data: Data(challenge.utf8))))
            try await 登记(keyID, attestation, challenge)
            UserDefaults.standard.set(keyID, forKey: 密钥键)
            UserDefaults.standard.set(true, forKey: 已登记键)
            return keyID
        } catch {
            return nil
        }
    }

    func 废弃() {
        UserDefaults.standard.removeObject(forKey: 密钥键)
        UserDefaults.standard.removeObject(forKey: 已登记键)
    }

    /// 对请求生成断言。覆盖的内容与服务器的 `assertionClientData` 一致：方法、路径、时间与请求体的 SHA256。
    func 断言(密钥 keyID: String, 方法 method: String, 路径 path: String, 内容 body: Data) async -> (断言: String, 时间: String)? {
        let timestamp = String(Int(Date.now.timeIntervalSince1970 * 1000))
        let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let clientData = Data("\(method)\n\(path)\n\(timestamp)\n\(bodyHash)".utf8)
        guard let assertion = try? await DCAppAttestService.shared.generateAssertion(
            keyID, clientDataHash: Data(SHA256.hash(data: clientData))
        ) else { return nil }
        return (assertion.base64EncodedString(), timestamp)
    }
}

/// 上一次与 Paper Account 同步时云端的版本与内容，作为下一次三方合并的基准。
nonisolated struct PaperAccount资料库同步状态: Codable {
    var 版本: Int?
    var 条目: [本地资料库条目] = []
    /// 当时云端的最近更改，三方合并最近更改用。
    var 更改ID: [UUID]?
    /// 当时云端版本用的高级数据保护密钥，普通版本为 nil。
    var 密钥ID: String?

    static func 文件地址(_ owner: String) -> URL {
        let safeOwner = owner.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? owner
        return URL.applicationSupportDirectory
            .appending(path: "Paper Account同步", directoryHint: .isDirectory)
            .appending(path: "\(safeOwner).json")
    }

    static func 读取(_ owner: String) -> Self? {
        guard let data = try? Data(contentsOf: 文件地址(owner)) else { return nil }
        return try? 资料库快照.解码器().decode(Self.self, from: data)
    }

    func 保存(_ owner: String) {
        let url = Self.文件地址(owner)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? 资料库快照.编码器().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
