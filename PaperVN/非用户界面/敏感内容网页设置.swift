import CryptoKit
import Foundation
import Security

/// 设备的安全限制特例只能由用户在PaperVN网站上登记（App Store审核指南1.2），App只读取结果。
/// App在钥匙串中保存只属于此设备的密钥，设备码由密钥哈希得出：网站只接触设备码，
/// 读取结果则需要密钥，所以知道设备码也无法冒充这台设备。
enum 敏感内容网页设置 {
    static let 已开启键 = "contentSafetyDeviceExceptionEnabled"

    private static let endpoint = URL(
        string: "https://papervn.jizpaper.com/api/content-preferences/device"
    )!
    /// 旧版本通过App内隐藏入口写入的本地解锁标记，已废弃。
    private static let 旧版本地解锁键 = "contentSafetyAdvancedControlsUnlocked"
    private static let 设备码字母表 = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    private nonisolated struct 响应: Decodable {
        nonisolated struct 偏好: Decodable {
            let sensitiveContent: Bool
        }

        let preferences: 偏好
    }

    static func 已开启(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: 已开启键)
    }

    /// 在“账户与设置 > 账户”中显示。钥匙串不可用时为nil。
    static var 设备码: String? {
        设备密钥存储.读取或创建().map(设备码(密钥:))
    }

    /// 与服务器一致：SHA-256前80位，Crockford Base32，四位一组。
    static func 设备码(密钥: Data) -> String {
        let digest = Array(SHA256.hash(data: 密钥).prefix(10))
        var bits = 0
        var value = 0
        var code = ""
        for byte in digest {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                code.append(设备码字母表[(value >> (bits - 5)) & 31])
                bits -= 5
            }
            value &= (1 << bits) - 1
        }
        return stride(from: 0, to: code.count, by: 4).map { start in
            let lower = code.index(code.startIndex, offsetBy: start)
            return String(code[lower..<code.index(lower, offsetBy: 4)])
        }
        .joined(separator: "-")
    }

    static func 移除旧版本地解锁(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: 旧版本地解锁键)
    }

    /// 从服务器读取网站上的登记结果。网络错误时保留上次结果。
    static func 同步(
        defaults: UserDefaults = .standard,
        session: URLSession = .shared
    ) async {
        移除旧版本地解锁(defaults: defaults)
        guard let 密钥 = 设备密钥存储.读取或创建() else { return }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Device \(密钥.map { String(format: "%02x", $0) }.joined())",
            forHTTPHeaderField: "Authorization"
        )

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let value = try? JSONDecoder().decode(响应.self, from: data)
        else { return }
        保存(已开启: value.preferences.sensitiveContent, defaults: defaults)
    }

    static func 保存(
        已开启: Bool,
        defaults: UserDefaults = .standard
    ) {
        if 已开启 {
            defaults.set(true, forKey: 已开启键)
        } else {
            defaults.removeObject(forKey: 已开启键)
        }
        强制内容安全策略.应用到用户设置(defaults)
    }
}

/// 设备密钥只保存在此设备的钥匙串中，不随备份迁移到其他设备。
private enum 设备密钥存储 {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.jizpaper.PaperVN",
        kSecAttrAccount as String: "contentSafetyDeviceSecret",
    ]
    private static var 缓存: Data?

    static func 读取或创建() -> Data? {
        if let 缓存 { return 缓存 }

        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data, data.count == 32 {
            缓存 = data
            return data
        }
        guard status == errSecItemNotFound else { return nil }

        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        let data = Data(bytes)
        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess else { return nil }
        缓存 = data
        return data
    }
}
