import CryptoKit
import Foundation
import Testing
@testable import PaperVN

@Suite
@MainActor
struct 作品映射更新Tests {
    @Test func 版本比较按摘要和日期() {
        // 摘要相同是同一份，日期不同也不下载
        #expect(!作品映射存储.比内置的新("20261027-aaaaaaaaaaaa", 内置: "20261026-aaaaaaaaaaaa"))
        #expect(作品映射存储.比内置的新("20261027-bbbbbbbbbbbb", 内置: "20261026-aaaaaaaaaaaa"))
        #expect(作品映射存储.比内置的新("20261026-bbbbbbbbbbbb", 内置: "20261026-aaaaaaaaaaaa"))
        // 比内置的旧（App 更新后内置的更新）
        #expect(!作品映射存储.比内置的新("20261025-bbbbbbbbbbbb", 内置: "20261026-aaaaaaaaaaaa"))
        // 旧格式只有日期
        #expect(作品映射存储.比内置的新("20261027-bbbbbbbbbbbb", 内置: "2026-10-25") == ("20261027" >= "2026-10-25"))
    }

    @Test func 只读文件开头就能取得内置映射的版本() throws {
        let url = try #require(作品映射存储.内置URL)
        let version = try #require(作品映射存储.版本(of: url))
        #expect(version.wholeMatch(of: /\d{8}-[0-9a-f]{12}/) != nil)
        #expect(作品映射.版本 == version || 作品映射存储.正在使用下载的更新)
    }

    @Test func 下载的映射要能完整读取() throws {
        let url = try #require(作品映射存储.内置URL)
        let data = try Data(contentsOf: url)
        #expect(try 作品映射.验证(data) == 作品映射存储.版本(of: url))
        #expect(throws: (any Error).self) { try 作品映射.验证(Data("{\"version\":\"x\"}".utf8)) }
        #expect(throws: (any Error).self) { try 作品映射.验证(data.prefix(1000)) }
    }

    @Test func 原始DEFLATE可以解压() throws {
        // 发布工具用 zlib wbits=-15 压缩；这里用同样格式的样本确认 Foundation 能解开
        let sample = Data("{\"version\":\"20261026-000000000000\"}".utf8)
        let compressed = try (sample as NSData).compressed(using: .zlib) as Data
        #expect(try (compressed as NSData).decompressed(using: .zlib) as Data == sample)
    }
}

@Suite
@MainActor
struct PaperVN诊断Tests {
    @Test func 收集完包含各分组且不含令牌() async throws {
        let diagnostics = PaperVN诊断程序()
        diagnostics.开始()
        for _ in 0..<300 where !diagnostics.已完成 {
            try await Task.sleep(for: .milliseconds(100))
        }
        let report = try #require(diagnostics.报告)
        #expect(report.sections.map(\.id) == ["app", "device", "network", "sync", "library", "data"])
        #expect(diagnostics.进度 == 1)
        #expect(report.收集时间 != nil)
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        #expect(!json.localizedCaseInsensitiveContains("token\":"))
        #expect(report.sections.first { $0.id == "network" }?.items.contains { $0.id == "endpoint.papervn" } == true)
        #expect(report.sections.first { $0.id == "data" }?.items.first { $0.id == "workMap.version" }?.value.contains(作品映射.版本 ?? "?") == true)
    }
}
