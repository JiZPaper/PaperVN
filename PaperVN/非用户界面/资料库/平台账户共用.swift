import Foundation
import Security

/// 把平台账户的登录凭据以 JSON 存进钥匙串，只在本机、首次解锁后可读。
nonisolated struct 钥匙串凭据存储<Value: Codable> {
    let service: String
    private let account = "session"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> Value? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw 平台账户错误.keychain(status)
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        let values: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(value),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw 平台账户错误.keychain(updateStatus) }
        var newItem = query
        values.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw 平台账户错误.keychain(addStatus) }
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// AniList、Annict 等平台账户共用的错误。
enum 平台账户错误: LocalizedError {
    case notConfigured(String)
    case loginIncomplete(String)
    case notLoggedIn(String)
    case service(String, String?)
    case invalidResponse(String)
    case rateLimited(String, TimeInterval)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .notConfigured(platform):
            String(localized: "需要先在App配置中设置\(platform)的Client ID。")
        case .loginIncomplete:
            String(localized: "登录未完成，请重试。")
        case .notLoggedIn:
            String(localized: "请重新登录。")
        case let .service(_, message):
            message ?? String(localized: "请求失败。")
        case .invalidResponse:
            String(localized: "返回的内容无效。")
        case .rateLimited:
            String(localized: "请求过于频繁，请稍后再试。")
        case let .keychain(status):
            String(localized: "无法读取登录凭据（\(status)）。")
        }
    }
}

enum 平台账户工具 {
    static func randomString(length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { characters[Int($0) % characters.count] })
    }

    nonisolated static func infoValue(_ key: String, environment: String) -> String {
        if let value = ProcessInfo.processInfo.environment[environment]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// GraphQL 请求；返回 data 字段的原始 JSON。errors 里的第一条作为错误抛出。
    static func graphQL(
        endpoint: URL,
        platform: String,
        accessToken: String?,
        query: String,
        variables: [String: Any] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        struct 响应: Decodable {
            struct 错误: Decodable { let message: String?; let status: Int? }
            let errors: [错误]?
        }
        let errors = (try? JSONDecoder().decode(响应.self, from: data))?.errors ?? []
        guard (200...299).contains(status), errors.isEmpty else {
            if status == 401 { throw 平台账户错误.notLoggedIn(platform) }
            if status == 429 {
                let retryAfter = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap(TimeInterval.init) ?? 60
                throw 平台账户错误.rateLimited(platform, retryAfter)
            }
            throw 平台账户错误.service(platform, errors.first?.message)
        }
        return data
    }

    /// “2019-05-31”这类日期；年月日缺失的部分省略。
    static func 日期文本(year: Int?, month: Int?, day: Int?) -> String? {
        guard let year else { return nil }
        guard let month else { return String(format: "%04d", year) }
        guard let day else { return String(format: "%04d-%02d", year, month) }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
