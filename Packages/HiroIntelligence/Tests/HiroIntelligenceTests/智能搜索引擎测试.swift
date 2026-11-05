import Foundation
import Testing
@testable import HiroIntelligence

/// 用 App 里预装的模型测试；也可以用环境变量 HIRO_INTELLIGENCE_MODEL 指定其他模型文件。
private let 模型URL: URL? = {
    if let 路径 = ProcessInfo.processInfo.environment["HIRO_INTELLIGENCE_MODEL"] {
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

    @Test func 同音错字() async throws {
        // 中文输入法打出的同音字（们/门）靠读音索引找回
        let 结果 = try await 引擎.搜索("命运石之们")
        let 前五 = 结果.命中.prefix(5).map(\.编号)
        #expect(前五.contains("v2002"))
    }

    /// 和生成模型时 Python 算出的结果比较（HIRO_INTELLIGENCE_PARITY 指定样例文件）。
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HIRO_INTELLIGENCE_PARITY"] != nil))
    func 与生成模型时一致() async throws {
        struct 样例: Decodable {
            struct 结果: Decodable {
                let id: String
                let probability: Float
            }
            let query: String
            let results: [结果]
            let null: Float
        }
        let 路径 = ProcessInfo.processInfo.environment["HIRO_INTELLIGENCE_PARITY"]!
        let 样例们 = try JSONDecoder().decode([样例].self, from: Data(contentsOf: URL(fileURLWithPath: 路径)))
        for 例 in 样例们 {
            let 结果 = try await 引擎.搜索(例.query, 数量: 400)
            #expect(abs(结果.空概率 - 例.null) < 2e-3, "\(例.query) 空概率")
            for 预期 in 例.results {
                // 会社、制作人员在 App 里还要乘类型权重，只比较概率，不比较名次
                let 命中 = 结果.命中.first { $0.编号 == 预期.id }
                #expect(命中 != nil, "\(例.query) 缺少 \(预期.id)")
                if let 命中 {
                    #expect(abs(命中.概率 - 预期.probability) < 2e-3, "\(例.query) \(预期.id) \(命中.概率) ≠ \(预期.probability)")
                }
            }
        }
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
