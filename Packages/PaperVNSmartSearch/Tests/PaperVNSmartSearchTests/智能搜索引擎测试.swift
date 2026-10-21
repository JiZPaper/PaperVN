import Foundation
import Testing
@testable import PaperVNSmartSearch

/// 用 App 里预装的模型测试；也可以用环境变量 PAPERVN_SMART_SEARCH_MODEL 指定其他模型文件。
private let 模型URL: URL? = {
    if let 路径 = ProcessInfo.processInfo.environment["PAPERVN_SMART_SEARCH_MODEL"] {
        return URL(fileURLWithPath: 路径)
    }
    let 预装 = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("../../../../PaperVN/Resources/PaperVNSmartSearch.pvss")
        .standardizedFileURL
    return FileManager.default.fileExists(atPath: 预装.path) ? 预装 : nil
}()

@Suite(.enabled(if: 模型URL != nil, "找不到模型文件"))
struct 智能搜索引擎测试 {
    let 引擎 = 智能搜索引擎(模型URL: 模型URL!)

    @Test func 读取头信息() async throws {
        let 头 = try await 引擎.头信息()
        #expect(智能搜索模型文件.支持的格式版本.contains(UInt32(头.formatVersion)))
        #expect(智能搜索模型文件.读取标识(模型URL!) == 头.modelIdentifier)
        #expect(头.visualNovelCount > 0)
    }

    @Test func 搜索作品() async throws {
        let 结果 = try await 引擎.搜索("Ever17")
        let 第一 = try #require(结果.命中.first)
        #expect(第一.编号 == "v17")
        #expect(第一.类型 == .视觉小说)
        #expect(第一.名称匹配)
    }

    @Test func 空输入() async throws {
        let 结果 = try await 引擎.搜索("")
        #expect(结果.命中.isEmpty)
        #expect(结果.空概率 == 1)
    }

    @Test func 无效文件() throws {
        let 临时 = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pvss")
        try Data("not a model".utf8).write(to: 临时)
        defer { try? FileManager.default.removeItem(at: 临时) }
        #expect(throws: 智能搜索模型错误.self) { try 智能搜索模型文件(url: 临时) }
        #expect(智能搜索模型文件.读取标识(临时) == nil)
    }
}
