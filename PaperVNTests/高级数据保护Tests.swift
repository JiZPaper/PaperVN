import Foundation
import Testing
@testable import PaperVN

/// 高级数据保护：恢复密钥的格式与输入容错、资料库密钥的包装、密文绑定账户与资料库所有者。
@Suite
struct 高级数据保护Tests {
    @Test func 恢复密钥是28个不易看错的字符() {
        let key = 高级数据保护.生成恢复密钥()
        #expect(key.count == 28)
        #expect(key.allSatisfy { 高级数据保护.恢复密钥字符.contains($0) })
        #expect(高级数据保护.格式化(key).split(separator: "-").map(\.count) == [4, 4, 4, 4, 4, 4, 4])
    }

    @Test func 输入忽略大小写与连字符并纠正看错的字符() {
        let key = "0123456789ABCDEFGHJKMNPQRSTV"
        #expect(高级数据保护.规范化(高级数据保护.格式化(key).lowercased()) == key)
        #expect(高级数据保护.规范化("O1I3 4567 89AB CDEF GHJK MNPQ RSTV") == "0113456789ABCDEFGHJKMNPQRSTV")
        #expect(高级数据保护.规范化("0123") == nil)
        #expect(高级数据保护.规范化("U123456789ABCDEFGHJKMNPQRSTV") == nil)
    }

    @Test func 用恢复密钥取回资料库密钥() throws {
        let recoveryKey = 高级数据保护.生成恢复密钥()
        let key = 高级数据保护.生成密钥()
        let settings = try 高级数据保护.包装(key, 恢复密钥: recoveryKey, 账户ID: "pa1")
        #expect(try 高级数据保护.解包(settings, 恢复密钥: recoveryKey, 账户ID: "pa1") == key)
        #expect(throws: 高级数据保护.错误.恢复密钥不正确) {
            try 高级数据保护.解包(settings, 恢复密钥: 高级数据保护.生成恢复密钥(), 账户ID: "pa1")
        }
        // 服务器把设置挪到其他账户也解不开
        #expect(throws: 高级数据保护.错误.恢复密钥不正确) {
            try 高级数据保护.解包(settings, 恢复密钥: recoveryKey, 账户ID: "pa2")
        }
    }

    @Test func 密文只能在同一账户与资料库下解开() throws {
        let key = 高级数据保护.生成密钥()
        let plaintext = Data("资料库".utf8)
        let sealed = try 高级数据保护.加密(plaintext, 密钥: key, 账户ID: "pa1", 所有者: "pa-1")
        #expect(高级数据保护.是密文(sealed))
        #expect(高级数据保护.密钥ID(sealed) == key.keyID)
        #expect(try 高级数据保护.解密(sealed, 密钥: key, 账户ID: "pa1", 所有者: "pa-1") == plaintext)
        #expect(throws: (any Error).self) { try 高级数据保护.解密(sealed, 密钥: key, 账户ID: "pa1", 所有者: "pa-2") }
        #expect(throws: (any Error).self) { try 高级数据保护.解密(sealed, 密钥: 高级数据保护.生成密钥(), 账户ID: "pa1", 所有者: "pa-1") }
        #expect(!高级数据保护.是密文(Data([0x78, 0x9c])))
    }
}
