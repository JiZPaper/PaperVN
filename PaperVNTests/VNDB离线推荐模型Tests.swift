import Foundation
import Testing
import zlib

@testable import PaperVN

@MainActor
@Suite
struct VNDB离线推荐模型Tests {
    @Test
    func 重新生成模型会改变模型标识() {
        let first = model(generatedAt: Date(timeIntervalSince1970: 1_000))
        let rebuilt = model(generatedAt: Date(timeIntervalSince1970: 2_000))

        #expect(first.模型标识 != rebuilt.模型标识)
    }

    @Test
    func 低秩折入会优先相似作品并排除资料库作品() {
        let model = model(itemFactors: [
            .init(visualNovelID: "v1", values: [1, 0]),
            .init(visualNovelID: "v2", values: [0.9, 0.1]),
            .init(visualNovelID: "v3", values: [0, 1]),
            .init(visualNovelID: "v4", values: [0.1, 0.9]),
            .init(visualNovelID: "v5", values: [0.95, 0.05]),
            .init(visualNovelID: "v6", values: [0.05, 0.95])
        ])

        let scores = VNDB离线低秩推荐算法.推荐分数(
            model: model,
            library: [
                item("v1", vote: 100),
                item("v2", vote: 90),
                item("v3", vote: 40),
                item("v4", vote: 50)
            ],
            excludedIDs: ["v1", "v2", "v3", "v4"]
        )

        #expect((scores["v5"] ?? 0) > 0.5)
        #expect((scores["v5"] ?? 0) > (scores["v6"] ?? 0))
        #expect(scores["v1"] == nil)
    }

    @Test
    func 旧版构建器的模型不产生协同分() {
        var legacy = model(itemFactors: [
            .init(visualNovelID: "v1", values: [1, 0]),
            .init(visualNovelID: "v2", values: [0.9, 0.1])
        ])
        legacy.collaborative = nil

        let scores = VNDB离线低秩推荐算法.推荐分数(
            model: legacy,
            library: [item("v1", vote: 100)],
            excludedIDs: ["v1"]
        )

        #expect(scores.isEmpty)
    }

    @Test
    func 证据少的作品仍有协同分但会自然收缩() {
        let model = model(itemFactors: [
            .init(visualNovelID: "v1", values: [1, 0]),
            .init(visualNovelID: "v2", values: [0, 1]),
            .init(visualNovelID: "v3", values: [0.8, 0]),
            .init(visualNovelID: "v4", values: [0.1, 0])
        ])

        let scores = VNDB离线低秩推荐算法.推荐分数(
            model: model,
            library: [item("v1", vote: 100), item("v2", vote: 40)],
            excludedIDs: ["v1", "v2"]
        )

        #expect((scores["v4"] ?? 0) > 0)
        #expect((scores["v3"] ?? 0) > (scores["v4"] ?? 0))
    }

    @Test
    func 折入前会减去作品偏置() {
        let library = [item("v1", vote: 90), item("v2", vote: 50)]
        let liked = Float(tanh(20.0 / 15.0) * 0.75)
        let personal = model(itemFactors: [
            .init(visualNovelID: "v1", values: [1, 0], bias: 0),
            .init(visualNovelID: "v2", values: [0, 1], bias: 0),
            .init(visualNovelID: "v3", values: [1, 0])
        ])
        let consensus = model(itemFactors: [
            .init(visualNovelID: "v1", values: [1, 0], bias: liked),
            .init(visualNovelID: "v2", values: [0, 1], bias: -liked),
            .init(visualNovelID: "v3", values: [1, 0])
        ])

        let personalScores = VNDB离线低秩推荐算法.推荐分数(
            model: personal,
            library: library,
            excludedIDs: ["v1", "v2"]
        )
        let consensusScores = VNDB离线低秩推荐算法.推荐分数(
            model: consensus,
            library: library,
            excludedIDs: ["v1", "v2"]
        )

        #expect((personalScores["v3"] ?? 0) > 0.5)
        #expect((consensusScores["v3"] ?? 0) < 0.01)
    }

    @Test
    func 作品偏置按权重计入协同分() {
        var model = model(itemFactors: [
            .init(visualNovelID: "v1", values: [1, 0], bias: 0),
            .init(visualNovelID: "v2", values: [0, 1], bias: 0),
            .init(visualNovelID: "v3", values: [0.5, 0], bias: 0.4),
            .init(visualNovelID: "v4", values: [0.5, 0], bias: -0.4)
        ])
        model.collaborative = VNDB离线协同参数(
            version: 1,
            userRegularization: 0.1,
            interceptRegularization: 0.01,
            biasWeight: 0.25,
            scoreScale: 1
        )

        let scores = VNDB离线低秩推荐算法.推荐分数(
            model: model,
            library: [item("v1", vote: 100), item("v2", vote: 40)],
            excludedIDs: ["v1", "v2"]
        )

        #expect((scores["v3"] ?? 0) > (scores["v4"] ?? 0))
        #expect((scores["v4"] ?? 0) > 0)
    }

    @Test
    func 模型清单会读取协同参数() throws {
        let url = try 写入模型头(
            #"{"formatVersion":2,"generatedAt":"2026-10-05T00:00:00Z","factorCount":48,"collaborative":{"version":1,"userRegularization":8,"interceptRegularization":0.01,"biasWeight":0.25,"scoreScale":0.15,"evaluation":{"rmse":0.49}},"visualNovels":[]}"#
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try #require(VNDB离线推荐模型加载器.清单(url: url))

        #expect(manifest.collaborative?.userRegularization == 8)
        #expect(manifest.collaborative?.biasWeight == 0.25)
        #expect(manifest.collaborative?.scoreScale == 0.15)
    }

    @Test
    func 旧版模型清单没有协同参数() throws {
        let url = try 写入模型头(
            #"{"formatVersion":2,"generatedAt":"2026-08-01T17:02:25Z","factorCount":48,"visualNovels":[]}"#
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try #require(VNDB离线推荐模型加载器.清单(url: url))

        #expect(manifest.collaborative == nil)
        #expect(manifest.模型标识 == "2|1785603745|48")
    }

    private func model(
        generatedAt: Date = .now,
        itemFactors: [VNDB离线低秩向量] = []
    ) -> VNDB离线推荐模型 {
        VNDB离线推荐模型(
            formatVersion: VNDB离线推荐模型.当前格式版本,
            generatedAt: generatedAt,
            factorCount: 2,
            visualNovels: [],
            characters: [],
            itemFactors: itemFactors,
            tagFrequencies: [:],
            traitFrequencies: [:],
            visualNovelCount: itemFactors.count,
            characterCount: 0,
            collaborative: VNDB离线协同参数(
                version: 1,
                userRegularization: 0.1,
                interceptRegularization: 0.01,
                biasWeight: 0,
                scoreScale: 0.5
            )
        )
    }

    private func item(_ id: String, vote: Int) -> 探索用户列表项目 {
        探索用户列表项目(
            id: id,
            added: nil,
            voted: nil,
            lastModified: nil,
            vote: vote,
            started: nil,
            finished: nil,
            labels: [探索用户列表标签(id: 7, label: "Voted")],
            vn: 探索用户列表视觉小说(
                title: id,
                titles: nil,
                image: nil,
                rating: nil,
                voteCount: nil,
                released: nil,
                languages: nil,
                platforms: nil,
                length: nil,
                lengthMinutes: nil,
                tags: nil,
                developers: nil,
                relations: nil
            )
        )
    }

    private func 写入模型头(_ header: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperVNModelManifest-\(UUID().uuidString).json.gz")
        guard let file = gzopen(url.path(percentEncoded: false), "wb") else {
            throw CocoaError(.fileWriteUnknown)
        }
        let bytes = Array(header.utf8)
        let written = bytes.withUnsafeBufferPointer {
            gzwrite(file, $0.baseAddress, UInt32($0.count))
        }
        gzclose(file)
        guard written == Int32(bytes.count) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }
}
