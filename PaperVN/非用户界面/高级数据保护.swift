import CryptoKit
import Foundation
import Security

/// 高级数据保护：开启后资料库快照在上传前用资料库密钥加密，服务器只存密文。
/// 资料库密钥存在 iCloud 钥匙串里，登录同一 Apple 账户的设备自动取得，这些就是受信任设备；
/// 服务器另存一份用恢复密钥加密的资料库密钥，没有受信任设备时输入恢复密钥取回。
/// 格式与 deploy/vps/papervn-account.mjs、account.html 保持一致。
nonisolated enum 高级数据保护 {
    struct 资料库密钥: Codable, Equatable, Sendable {
        /// 8 字节，十六进制。写在每份密文的开头，换了密钥的设备一看就知道自己解不开。
        let keyID: String
        let key: Data
    }

    /// 服务器上的设置：用恢复密钥加密的资料库密钥。
    struct 云端设置: Codable, Equatable, Sendable {
        let keyID: String
        let salt: String
        let wrappedKey: String
    }

    enum 错误: LocalizedError {
        case 恢复密钥不正确
        case 数据无效

        var errorDescription: String? {
            switch self {
            case .恢复密钥不正确: String(localized: "恢复密钥不正确。")
            case .数据无效: String(localized: "Paper账户暂时不可用。")
            }
        }
    }

    static let 魔数 = Data("PVE1".utf8)
    /// Crockford Base32：去掉了容易看错的 I、L、O、U。28 个字符共 140 位。
    static let 恢复密钥字符 = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
    static let 恢复密钥长度 = 28

    static func 生成密钥() -> 资料库密钥 {
        资料库密钥(keyID: 随机字节(8).十六进制, key: 随机字节(32))
    }

    static func 生成恢复密钥() -> String {
        String(随机字节(恢复密钥长度).map { 恢复密钥字符[Int($0) % 恢复密钥字符.count] })
    }

    /// 每4个字符一组，用连字符隔开。
    static func 格式化(_ recoveryKey: String) -> String {
        stride(from: 0, to: recoveryKey.count, by: 4).map {
            let start = recoveryKey.index(recoveryKey.startIndex, offsetBy: $0)
            return String(recoveryKey[start..<(recoveryKey.index(start, offsetBy: 4, limitedBy: recoveryKey.endIndex) ?? recoveryKey.endIndex)])
        }.joined(separator: "-")
    }

    /// 输入的恢复密钥：忽略大小写、空格与连字符，把看错的 I、L 当作 1，O 当作 0。不是28个有效字符时返回 nil。
    static func 规范化(_ input: String) -> String? {
        let characters = input.uppercased().compactMap { character -> Character? in
            switch character {
            case "-", " ", "\n", "\t", "\u{2010}", "\u{2011}", "\u{2012}", "\u{2013}", "\u{2014}", "\u{2212}", "\u{3000}": nil
            case "I", "L": "1"
            case "O": "0"
            default: character
            }
        }
        guard characters.count == 恢复密钥长度, characters.allSatisfy(恢复密钥字符.contains) else { return nil }
        return String(characters)
    }

    static func 包装(_ key: 资料库密钥, 恢复密钥 recoveryKey: String, 账户ID accountID: String) throws -> 云端设置 {
        let salt = 随机字节(16)
        let sealed = try AES.GCM.seal(key.key, using: 包装密钥(recoveryKey, salt: salt), authenticating: 包装附加数据(accountID, key.keyID))
        guard let combined = sealed.combined else { throw 错误.数据无效 }
        return 云端设置(keyID: key.keyID, salt: salt.base64EncodedString(), wrappedKey: combined.base64EncodedString())
    }

    static func 解包(_ settings: 云端设置, 恢复密钥 recoveryKey: String, 账户ID accountID: String) throws -> 资料库密钥 {
        guard let salt = Data(base64Encoded: settings.salt), let wrapped = Data(base64Encoded: settings.wrappedKey) else { throw 错误.数据无效 }
        do {
            let box = try AES.GCM.SealedBox(combined: wrapped)
            let key = try AES.GCM.open(box, using: 包装密钥(recoveryKey, salt: salt), authenticating: 包装附加数据(accountID, settings.keyID))
            guard key.count == 32 else { throw 错误.数据无效 }
            return 资料库密钥(keyID: settings.keyID, key: key)
        } catch is CryptoKitError {
            throw 错误.恢复密钥不正确
        }
    }

    /// “PVE1” + 8 字节密钥 ID + AES-GCM 的 nonce、密文与 tag。附加数据绑定账户与资料库所有者，服务器无法把密文挪到别处。
    static func 加密(_ plaintext: Data, 密钥 key: 资料库密钥, 账户ID accountID: String, 所有者 owner: String) throws -> Data {
        guard let keyID = Data(十六进制: key.keyID) else { throw 错误.数据无效 }
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key.key), authenticating: 资料库附加数据(accountID, owner))
        guard let combined = sealed.combined else { throw 错误.数据无效 }
        return 魔数 + keyID + combined
    }

    static func 是密文(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(4) == 魔数
    }

    static func 密钥ID(_ data: Data) -> String? {
        guard 是密文(data), data.count >= 12 else { return nil }
        return data.subdata(in: data.startIndex + 4..<data.startIndex + 12).十六进制
    }

    static func 解密(_ data: Data, 密钥 key: 资料库密钥, 账户ID accountID: String, 所有者 owner: String) throws -> Data {
        guard 密钥ID(data) == key.keyID, data.count >= 4 + 8 + 12 + 16 else { throw 错误.数据无效 }
        let box = try AES.GCM.SealedBox(combined: data.subdata(in: data.startIndex + 12..<data.endIndex))
        return try AES.GCM.open(box, using: SymmetricKey(data: key.key), authenticating: 资料库附加数据(accountID, owner))
    }

    // 恢复密钥有140位，不需要慢速的口令派生，HKDF 就够了
    private static func 包装密钥(_ recoveryKey: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(recoveryKey.utf8)), salt: salt,
            info: Data("PaperVN advanced data protection recovery".utf8), outputByteCount: 32
        )
    }

    private static func 包装附加数据(_ accountID: String, _ keyID: String) -> Data {
        Data("PaperVN advanced data protection key\n\(accountID)\n\(keyID)".utf8)
    }

    private static func 资料库附加数据(_ accountID: String, _ owner: String) -> Data {
        Data("PaperVN library\n\(accountID)\n\(owner)".utf8)
    }

    private static func 随机字节(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

/// 资料库密钥放在 iCloud 钥匙串：同一 Apple 账户的设备同步取得，删除App后也还在。
nonisolated enum 资料库密钥存储 {
    private static let service = "com.jizpaper.PaperVN.advanced-data-protection"

    private static func query(_ accountID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    static func 读取(账户ID accountID: String) -> 高级数据保护.资料库密钥? {
        var query = query(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(高级数据保护.资料库密钥.self, from: data)
    }

    static func 存储(_ key: 高级数据保护.资料库密钥, 账户ID accountID: String) throws {
        删除(账户ID: accountID)
        var item = query(accountID)
        item[kSecAttrSynchronizable as String] = kCFBooleanTrue
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecValueData as String] = try JSONEncoder().encode(key)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw 平台账户错误.keychain(status) }
    }

    static func 删除(账户ID accountID: String) {
        SecItemDelete(query(accountID) as CFDictionary)
    }
}

private nonisolated extension Data {
    var 十六进制: String { map { String(format: "%02x", $0) }.joined() }

    init?(十六进制 text: String) {
        guard text.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
