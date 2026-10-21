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

    /// a1、a2、a4、m5、n6 的向量相近，a3 和它们不同。
    private let 示例 = """
    {"formatVersion":1,"generatedAt":"2026-10-21T00:00:00Z",
     "parameters":{"personWeight":1,"qualityWeight":0.1,"popularityWeight":0.2,"ratingScale":15},
     "featureCount":5,
     "works":{
       "keys":["a1","a2","a3","a4","m5","n6","a7"],
       "series":[0,1,2,1,3,4,5],
       "quality":[0.5,0.5,0.5,0.5,0.5,0.5,0.9],
       "popularity":[0.5,0.5,0.5,0.5,0.5,0.5,0.5],
       "adult":[0,0,0,0,0,0,1],
       "year":[2000,2001,2002,2003,2004,2005,2006],
       "recommendable":[1,1,1,1,1,1,1],
       "vectors":[[0,200,1,200],[0,200,1,180,4,100],[2,200,3,200],[0,150,1,200],[0,200,1,150],[0,180,1,200],[0,255]]
     },
     "visualNovels":{"ids":["v4"],"series":[6],"vectors":[[0,255,1,100]]}
    }
    """

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
        // 评分足够多时按个人中位数判断：a1 是这位用户打分最低的作品
        let feedback = [
            作品推荐反馈(候选编号: ["a1"], 评分: 20, 状态: .completed),
            作品推荐反馈(候选编号: ["a3"], 评分: 90, 状态: .completed),
            作品推荐反馈(候选编号: ["x1"], 评分: 80, 状态: .completed),
            作品推荐反馈(候选编号: ["x2"], 评分: 80, 状态: .completed),
            作品推荐反馈(候选编号: ["x3"], 评分: 70, 状态: .completed),
        ]
        let result = model.推荐(资料库: feedback, 类型: [.anime, .manga, .lightNovel], 包含成人内容: false, 数量: 10)
        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.分数 < 0.5 })
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
