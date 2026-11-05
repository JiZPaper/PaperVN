import Foundation
import Testing

@testable import PaperVN

@MainActor
@Suite
struct 作品推荐模型Tests {
    /// 和构建脚本相同的文件格式：魔数、标识、原文长度、raw DEFLATE 压缩的 JSON。
    private func 模型(_ json: String) throws -> 作品推荐模型 {
        let raw = Data(json.utf8)
        let compressed = try (raw as NSData).compressed(using: .zlib) as Data
        var data = Data("PVWR".utf8)
        let id = Data("20261021-test".utf8)
        func append(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(id.count))
        data.append(id)
        append(UInt32(raw.count))
        data.append(compressed)
        return try 作品推荐模型(data: data)
    }

    /// 二维向量：a1、a2、a4、m5、n6、a7、v4 都在 (1, 0) 方向，a3 在 (0, 1) 方向。a2、a4 同一系列，a7 是成人作品。
    private var 示例: String {
        let keys = ["a1", "a2", "a3", "a4", "m5", "n6", "a7", "v4"]
        let vectors: [[Int8]] = [[127, 0], [127, 12], [0, 127], [114, 0], [127, 6], [120, 0], [127, 0], [127, 3]]
        let bytes = Data(vectors.flatMap { $0 }.map { UInt8(bitPattern: $0) })
        let keyList = keys.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"formatVersion":2,"generatedAt":"2026-10-22T00:00:00Z",
         "parameters":{"factors":2,"regularization":0.1,"alpha":10,"ratingBoost":1,"wishWeight":0.3,"relatedWeight":0},
         "keys":[\(keyList)],
         "series":[0,1,2,1,3,4,5,6],
         "adult":[0,0,0,0,0,0,1,0],
         "recommendable":[1,1,1,1,1,1,1,0],
         "scales":[\(Array(repeating: "0.007874", count: keys.count).joined(separator: ","))],
         "factors":"\(bytes.base64EncodedString())",
         "related":[[],[],[],[],[],[],[],[]]}
        """
    }

    /// 格式 3：视觉小说与其他类型在同一个模型里，另外带每部作品的相似作品。
    private func 合并示例(相似作品权重: Double) -> String {
        let vectors: [[Int8]] = [[127, 0], [127, 0], [100, 60]]
        let bytes = Data(vectors.flatMap { $0 }.map { UInt8(bitPattern: $0) })
        return """
        {"formatVersion":3,"generatedAt":"2026-10-22T00:00:00Z",
         "parameters":{"factors":2,"regularization":0.1,"alpha":2,"alphaVN":8,"ratingBoost":1,"wishWeight":0.3,
                       "neighborWeight":\(相似作品权重),"relatedWeight":0},
         "keys":["a1","v2","v3"],
         "series":[0,1,2],
         "adult":[0,0,0],
         "recommendable":[1,1,1],
         "scales":[0.007874,0.007874,0.007874],
         "factors":"\(bytes.base64EncodedString())",
         "related":[[],[],[]],
         "neighbors":[[2,1.0],[],[]]}
        """
    }

    @Test
    func 合并模型推荐视觉小说并加上相似作品() throws {
        let liked = 作品推荐反馈(候选编号: ["a1"], 评分: nil, 状态: .completed)
        let plain = try 模型(合并示例(相似作品权重: 0))
            .推荐(资料库: [liked], 类型: [.visualNovel], 包含成人内容: false, 数量: 10)
        #expect(plain.map(\.编号) == ["v2", "v3"])
        #expect(plain.allSatisfy { $0.类型 == .visualNovel })
        let boosted = try 模型(合并示例(相似作品权重: 5))
            .推荐(资料库: [liked], 类型: [.visualNovel], 包含成人内容: false, 数量: 10)
        #expect(boosted.map(\.编号) == ["v3", "v2"])
    }

    /// a2 是续作（系列入口 a3，不可推荐）；a1 在资料库里。
    private func 入口示例(入口成人: Bool, 用户正则: String = "") -> String {
        let vectors: [[Int8]] = [[127, 0], [127, 20], [127, 10]]
        let bytes = Data(vectors.flatMap { $0 }.map { UInt8(bitPattern: $0) })
        return """
        {"formatVersion":3,"generatedAt":"2026-11-03T00:00:00Z",
         "parameters":{"factors":2,"regularization":0.1,"alpha":2,"alphaManga":6,"ratingBoost":1,"wishWeight":0.3,
                       "relatedWeight":0\(用户正则)},
         "keys":["a1","a2","a3"],
         "series":[0,1,1],
         "adult":[0,0,\(入口成人 ? 1 : 0)],
         "recommendable":[1,1,0],
         "scales":[0.007874,0.007874,0.007874],
         "factors":"\(bytes.base64EncodedString())",
         "related":[[],[],[]],
         "entries":[1,2]}
        """
    }

    @Test
    func 推荐续作时显示系列入口() throws {
        let liked = 作品推荐反馈(候选编号: ["a1"], 评分: nil, 状态: .completed)
        let model = try 模型(入口示例(入口成人: false))
        let result = model.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 10)
        #expect(result.map(\.编号) == ["a3"])
        // 入口是成人作品而不允许成人内容时，显示原来的作品
        let adult = try 模型(入口示例(入口成人: true))
        #expect(adult.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 10).map(\.编号) == ["a2"])
        #expect(adult.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: true, 数量: 10).map(\.编号) == ["a3"])
        // 资料库里已有这个系列的作品时不推荐
        let watched = 作品推荐反馈(候选编号: ["a3"], 评分: nil, 状态: .completed)
        #expect(model.推荐(资料库: [liked, watched], 类型: [.anime], 包含成人内容: false, 数量: 10).isEmpty)
    }

    @Test
    func 资料库很小时加大正则() throws {
        let liked = 作品推荐反馈(候选编号: ["a1"], 评分: nil, 状态: .completed)
        let plain = try #require(try 模型(入口示例(入口成人: false))
            .推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 1).first)
        let adjusted = try #require(try 模型(入口示例(入口成人: false, 用户正则: #","userRegPower":1.5,"userRegRef":30"#))
            .推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 1).first)
        #expect(adjusted.分数 < plain.分数)
    }

    /// 精排示例：召回分数 a2 > a3 > a4，精排只看热度（越冷门越靠前），前 2 部重新排序。
    private func 精排示例(召回权重: Double = 0, 特征名: String = #""scoreZ","rank","collaborativeZ","related","popularity","popularityRank","quality","ratingCount","year","yearMissing","yearOffset","librarySize","typeCount","typeShare","meanRating","ratedShare","vectorNorm","anime","manga","lightNovel","visualNovel""#) -> String {
        let vectors: [[Int8]] = [[127, 0], [127, 0], [120, 0], [110, 0]]
        let bytes = Data(vectors.flatMap { $0 }.map { UInt8(bitPattern: $0) })
        var weights = Array(repeating: "0", count: 21)
        weights[4] = "-1"
        let zeros = Array(repeating: "0", count: 21).joined(separator: ",")
        let ones = Array(repeating: "1", count: 21).joined(separator: ",")
        return """
        {"formatVersion":3,"generatedAt":"2026-11-03T00:00:00Z",
         "parameters":{"factors":2,"regularization":0.1,"alpha":2,"ratingBoost":1,"wishWeight":0.3,"relatedWeight":0},
         "keys":["a1","a2","a3","a4"],
         "series":[0,1,2,3],
         "adult":[0,0,0,0],
         "recommendable":[1,1,1,1],
         "scales":[0.007874,0.007874,0.007874,0.007874],
         "factors":"\(bytes.base64EncodedString())",
         "related":[[],[],[],[]],
         "reranker":{"candidates":2,"recallWeight":\(召回权重),"features":[\(特征名)],"mean":[\(zeros)],"std":[\(ones)],
                     "layers":[{"inputs":21,"outputs":1,"weights":[\(weights.joined(separator: ","))],"biases":[0]}]},
         "itemStats":{"popularity":[1,5,1,0],"popularityRank":[0,0,0,0],"quality":[0,0,0,0],"ratingCount":[0,0,0,0],
                      "year":[2000,2001,0,2003]}}
        """
    }

    @Test
    func 精排按特征重新排序召回前几名() throws {
        let liked = 作品推荐反馈(候选编号: ["a1"], 评分: nil, 状态: .completed)
        let model = try 模型(精排示例())
        #expect(model.精排 != nil)
        #expect(model.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 10).map(\.编号) == ["a3", "a2"])
        // 混入的召回分数足够大时，召回的顺序占上风
        let blended = try 模型(精排示例(召回权重: 100))
        #expect(blended.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 10).map(\.编号) == ["a2", "a3"])
        // 特征对不上（新版构建脚本加了特征）时不精排，按召回分数排序
        let other = try 模型(精排示例(特征名: Array(repeating: #""x""#, count: 21).joined(separator: ",")))
        #expect(other.精排 == nil)
        #expect(other.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 10).map(\.编号) == ["a2", "a3", "a4"])
    }

    @Test
    func 取消的推荐不返回空结果也不改缓存() async throws {
        var entry = 本地资料库条目(id: "vn:v4", 类型: .visualNovel, 平台ID: [:], 标题: "v4", 加入时间: nil)
        entry.状态 = .completed
        本地资料库.shared.预览载入([entry])
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PaperVNWorkRecommendations.json")
        let before = try? Data(contentsOf: url)
        let task = Task {
            try await 作品推荐中心.shared.推荐(类型: Set(作品类型.allCases), 包含成人内容: false)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect((try? Data(contentsOf: url)) == before)
    }

    @Test
    func 只读文件开头就能取得模型标识() {
        var data = Data("PVWR".utf8)
        let id = Data("20261022-abc".utf8)
        withUnsafeBytes(of: UInt32(id.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(id)
        #expect(作品推荐模型.标识(头: data) == "20261022-abc")
        #expect(作品推荐模型.标识(头: data.prefix(10)) == nil)
        #expect(作品推荐模型.标识(头: Data("PVSS".utf8) + data.dropFirst(4)) == nil)
        #expect(推荐模型存储.日期("20261022-abc") == "20261022")
    }

    @Test
    func 旧版内存限制关闭的为你推荐恢复默认() throws {
        let defaults = try #require(UserDefaults(suiteName: "作品推荐模型Tests.\(UUID().uuidString)"))
        defaults.set(false, forKey: 为你推荐设置.启用键)
        为你推荐设置.移除设备限制(defaults: defaults, 物理内存: 3 * 1_024 * 1_024 * 1_024)
        #expect(defaults.object(forKey: 为你推荐设置.启用键) == nil)

        let other = try #require(UserDefaults(suiteName: "作品推荐模型Tests.\(UUID().uuidString)"))
        other.set(false, forKey: 为你推荐设置.启用键)
        为你推荐设置.移除设备限制(defaults: other, 物理内存: 8 * 1_024 * 1_024 * 1_024)
        #expect(other.bool(forKey: 为你推荐设置.启用键) == false)
    }

    @Test
    func 按喜欢的作品推荐相似作品并排除同一系列() throws {
        let model = try 模型(示例)
        let liked = 作品推荐反馈(候选编号: ["a1"], 评分: nil, 状态: .completed)
        let result = model.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: false, 数量: 10)
        // a2、a4 属于同一系列，只推荐分数高的一部；机战作品 a3 排在后面；资料库里的 a1 和成人作品 a7 不推荐
        #expect(result.map(\.编号) == ["a2", "a3"] || result.map(\.编号) == ["a4", "a3"])
        #expect(result.allSatisfy { $0.类型 == .anime })
    }

    @Test
    func 相关推荐只推荐同一类型并排除同一系列() throws {
        let model = try 模型(示例)
        let result = model.相关推荐(作品: ["a1"], 资料库: [], 类型: .anime, 包含成人内容: false, 数量: 10)
        // a2、a4 同一系列只推荐一部；方向不同的 a3 排在后面；这部作品所在的系列和成人作品 a7 不推荐；不推荐漫画 m5
        let anime = result.map(\.编号)
        #expect(anime == ["a2", "a3"] || anime == ["a4", "a3"])
        #expect(model.相关推荐(作品: ["a999"], 资料库: [], 类型: .anime, 包含成人内容: true, 数量: 10).isEmpty)
    }

    @Test
    func 相关推荐排除资料库里的系列() throws {
        let model = try 模型(示例)
        let library = [作品推荐反馈(候选编号: ["a4"], 评分: nil, 状态: .completed)]
        let result = model.相关推荐(作品: ["a1"], 资料库: library, 类型: .anime, 包含成人内容: false, 数量: 10)
        #expect(result.map(\.编号) == ["a3"])
    }

    @Test
    func 相关推荐加上社区推荐() throws {
        let model = try 模型(示例.replacingOccurrences(of: #""related":[[],"#, with: #""related":[[2,1.0],"#))
        let result = model.相关推荐(作品: ["a1"], 资料库: [], 类型: .anime, 包含成人内容: false, 数量: 10)
        #expect(result.first?.编号 == "a3")
    }

    @Test
    func 资料库里的视觉小说也能推荐其他类型() throws {
        let model = try 模型(示例)
        let liked = 作品推荐反馈(候选编号: ["v4"], 评分: nil, 状态: .completed)
        let result = model.推荐(资料库: [liked], 类型: [.manga, .lightNovel], 包含成人内容: false, 数量: 10)
        #expect(Set(result.map(\.编号)) == ["m5", "n6"])
    }

    @Test
    func 资料库为空时不推荐() throws {
        let model = try 模型(示例)
        #expect(model.推荐(资料库: [], 类型: [.anime], 包含成人内容: true, 数量: 10).isEmpty)
        let unknown = 作品推荐反馈(候选编号: ["a999"], 评分: nil, 状态: .completed)
        #expect(model.推荐(资料库: [unknown], 类型: [.anime], 包含成人内容: true, 数量: 10).isEmpty)
    }

    @Test
    func 成人作品只在允许时推荐() throws {
        let model = try 模型(示例)
        let liked = 作品推荐反馈(候选编号: ["a1"], 评分: nil, 状态: .completed)
        let result = model.推荐(资料库: [liked], 类型: [.anime], 包含成人内容: true, 数量: 10)
        #expect(result.contains { $0.编号 == "a7" })
    }

    @Test
    func 低分作品让相似作品排到后面() throws {
        let model = try 模型(示例)
        // 评分足够多时按个人中位数判断：给 a1 打低分（明显不喜欢）时，和 a1 相近的作品分数比给 a1 打高分时低
        func 分数(a1评分: Int) -> Double? {
            let feedback = [
                作品推荐反馈(候选编号: ["a1"], 评分: a1评分, 状态: .completed),
                作品推荐反馈(候选编号: ["a3"], 评分: 90, 状态: .completed),
                作品推荐反馈(候选编号: ["x1"], 评分: 80, 状态: .completed),
                作品推荐反馈(候选编号: ["x2"], 评分: 80, 状态: .completed),
                作品推荐反馈(候选编号: ["x3"], 评分: 70, 状态: .completed),
            ]
            return model.推荐(资料库: feedback, 类型: [.manga], 包含成人内容: false, 数量: 10).first?.分数
        }
        let 不喜欢 = try #require(分数(a1评分: 20))
        let 喜欢 = try #require(分数(a1评分: 100))
        #expect(不喜欢 < 喜欢)
    }

    @Test
    func 资料库编号换成模型编号() {
        #expect(作品推荐模型.候选编号(条目ID: "mal-anime:5114", 类型: .anime, malID: 5114) == ["a5114"])
        #expect(作品推荐模型.候选编号(条目ID: "mal-manga:2", 类型: .lightNovel, malID: 2) == ["n2", "m2"])
        #expect(作品推荐模型.候选编号(条目ID: "aniList-anime:21", 类型: .anime, malID: nil) == ["a\(0x8000_0015)"])
        #expect(作品推荐模型.候选编号(条目ID: "vn:v17", 类型: .visualNovel, malID: nil) == ["v17"])
    }

    @Test
    func 几种类型按资料库数量交替排列() {
        func work(_ id: String, _ type: 作品类型) -> 为你推荐条目 {
            .作品(作品推荐项(作品: 作品搜索结果(id: id, 类型: type, malID: 1, 标题: id, 多语言标题: []), 分数: 1))
        }
        let anime = (1...6).map { work("a\($0)", .anime) }
        let manga = (1...6).map { work("m\($0)", .manga) }
        let mixed = 为你推荐条目.交替([.anime: anime, .manga: manga], 资料库数量: [.anime: 16, .manga: 4])
        #expect(mixed.count == 12)
        // 动画的权重是漫画的两倍（数量的平方根），前 6 条里动画多于漫画
        #expect(mixed.prefix(6).filter { $0.类型 == .anime }.count == 4)
        // 每一类内部保持原来的顺序
        #expect(mixed.filter { $0.类型 == .manga }.map(\.id) == manga.map(\.id))
    }

    @Test
    func Today的动画故事放在单独的字段里() throws {
        let data = Data(#"""
        {"schemaVersion":2,"date":"2026-10-21",
         "stories":[{"id":"2026-10-21-v4","visualNovelID":"v4","accessibilityTitle":"CLANNAD","eyebrow":"推荐视觉小说","description":"标题"}],
         "workStories":[{"id":"2026-10-21-a5114","workID":"a5114","accessibilityTitle":"鋼の錬金術師","eyebrow":"推荐动画","description":"标题",
                         "related":[{"type":"manga","id":"m25","title":"鋼の錬金術師"}]}]}
        """#.utf8)
        let feed = try Today内容解码器.decode(data, localeIdentifier: "zh-Hans")
        #expect(feed.stories.map(\.id) == ["2026-10-21-v4", "2026-10-21-a5114"])
        let work = try #require(feed.stories.last)
        #expect(work.作品类型 == .anime)
        #expect(work.visualNovelID.isEmpty)
        #expect(work.主作品ID == "a5114")
        #expect(work.related.first?.type == .manga)
        #expect(feed.stories.first?.作品类型 == .visualNovel)
    }
}
