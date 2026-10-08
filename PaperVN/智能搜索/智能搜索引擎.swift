import Foundation

nonisolated enum 智能搜索条目类型: Sendable, Hashable {
    case 视觉小说
    case 角色
    case 会社
    case 制作人员
}

nonisolated struct 智能搜索命中: Sendable, Hashable {
    let 类型: 智能搜索条目类型
    /// VNDB 编号，如 "v2002"、"c6487"、"p98"、"s216"。
    let 编号: String
    let 概率: Float
    /// 查询和这个条目的某个名字（标题、别名、梗、角色名）明显对得上。
    let 名称匹配: Bool
    /// 作品所属系列：同系列作品的这个值相同（取组里编号最小的作品），不属于任何系列时为空。
    let 系列: String?
    /// 角色的主要出场作品。
    let 所属作品: String?
}

nonisolated struct 智能搜索结果集: Sendable {
    /// 按可能性从高到低。
    let 命中: [智能搜索命中]
    /// “输入不像任何一个名字”的概率。
    let 空概率: Float

    static let 空 = 智能搜索结果集(命中: [], 空概率: 1)
}

/// 在设备上完成名称模糊匹配：名称片段索引召回候选 → 排序器综合名称匹配和热度打分。
/// 查询文本不会离开设备。
actor 智能搜索引擎 {
    static let shared = 智能搜索引擎()

    private final class 已加载模型: @unchecked Sendable {
        let 文件: 智能搜索模型文件
        let 名称索引: 智能搜索名称索引
        let 排序器: 智能搜索排序器
        let 编号: UnsafeBufferPointer<UInt32>
        let 先验: UnsafeBufferPointer<Float>
        let 系列: UnsafeBufferPointer<UInt32>
        let 所属作品: UnsafeBufferPointer<UInt32>

        var 作品数: Int { 文件.头.visualNovelCount }
        var 角色数: Int { 文件.头.characterCount }
        var 会社数: Int { 文件.头.producerCount }

        init(文件: 智能搜索模型文件) throws {
            self.文件 = 文件
            名称索引 = try 智能搜索名称索引(文件: 文件)
            排序器 = try 智能搜索排序器(数据: 文件.数据段("ranker"))
            编号 = try 文件.数组段("docs/ids", 类型: UInt32.self)
            先验 = try 文件.数组段("docs/priors", 类型: Float.self)
            系列 = try 文件.数组段("docs/series", 类型: UInt32.self)
            所属作品 = try 文件.数组段("docs/parents", 类型: UInt32.self)
            let 头 = 文件.头
            let 数量 = 头.visualNovelCount + 头.characterCount + 头.producerCount + 头.staffCount
            guard 编号.count == 数量,
                  先验.count == 数量,
                  系列.count == 头.visualNovelCount,
                  所属作品.count == 头.characterCount else {
                throw 智能搜索模型错误.缺少数据("docs")
            }
        }

        func 类型(_ 文档: Int) -> 智能搜索条目类型 {
            if 文档 < 作品数 { return .视觉小说 }
            if 文档 < 作品数 + 角色数 { return .角色 }
            if 文档 < 作品数 + 角色数 + 会社数 { return .会社 }
            return .制作人员
        }
    }

    private var 当前: 已加载模型?

    /// 模型文件被替换或删除后调用，下次搜索时重新加载。
    func 卸载() {
        当前 = nil
    }

    func 预热() {
        _ = try? 加载()
    }

    private func 加载() throws -> 已加载模型 {
        if let 当前 { return 当前 }
        guard let url = 智能搜索模型存储.当前URL else { throw 智能搜索模型错误.文件无效 }
        let 模型 = try 已加载模型(文件: try 智能搜索模型文件(url: url))
        当前 = 模型
        return 模型
    }

    /// 查询作品所属的系列（作品编号 → 系列编号），只返回属于某个系列的作品。
    /// 用于把 VNDB 返回、智能搜索没找到的作品也叠进同系列。作品按编号升序存放，二分查找。
    func 作品系列(_ 作品编号: [String]) -> [String: String] {
        guard let 模型 = try? 加载() else { return [:] }
        var 结果: [String: String] = [:]
        for 编号 in 作品编号 {
            guard 编号.hasPrefix("v"), let 数字 = UInt32(编号.dropFirst()) else { continue }
            var 低 = 0
            var 高 = 模型.作品数
            while 低 < 高 {
                let 中 = (低 + 高) / 2
                if 模型.编号[中] < 数字 { 低 = 中 + 1 } else { 高 = 中 }
            }
            guard 低 < 模型.作品数, 模型.编号[低] == 数字 else { continue }
            let 系列 = 模型.系列[低]
            if 系列 != 0 { 结果[编号] = "v\(系列)" }
        }
        return 结果
    }

    func 搜索(_ 文本: String, 数量: Int = 60) throws -> 智能搜索结果集 {
        let 模型 = try 加载()
        let 查询 = 模型.名称索引.准备查询(文本)
        let 头 = 模型.文件.头
        let 候选 = 模型.名称索引.候选文档(
            查询,
            名称数量: 头.nameCandidateCount,
            覆盖数量: 头.coverageCandidateCount,
            先验: 模型.先验
        )
        guard !候选.isEmpty else { return .空 }
        try Task.checkCancellation()

        let 名称特征 = 候选.map { 模型.名称索引.特征(查询, 文档: $0) }
        let 最高名称分 = 名称特征.map(\.f).max() ?? 0
        let 最高先验 = 候选.map { 模型.先验[$0] }.max() ?? 0
        let 查询长度 = Float(min(查询.规范文本.count, 32)) / 32
        let 中日文: Float = 文本.unicodeScalars.contains(where: Self.是中日文) ? 1 : 0

        let 特征 = 候选.indices.map { i -> [Float] in
            let 名称 = 名称特征[i]
            let 文档 = 候选[i]
            let 类型 = 模型.类型(文档)
            return [
                名称.f,
                名称.查询覆盖,
                名称.名称覆盖,
                名称.完全一致 ? 1 : 0,
                名称.前缀 ? 1 : 0,
                名称.包含 ? 1 : 0,
                名称.f - 最高名称分,
                模型.先验[文档],
                模型.先验[文档] - 最高先验,
                类型 == .角色 ? 1 : 0,
                类型 == .会社 ? 1 : 0,
                类型 == .制作人员 ? 1 : 0,
                名称.长度比,
                查询长度,
                中日文,
            ]
        }
        let 空特征: [Float] = [
            最高名称分,
            名称特征.contains(where: \.完全一致) ? 1 : 0,
            名称特征.contains(where: \.前缀) ? 1 : 0,
            查询长度,
            中日文,
        ]
        let (排序结果, 空概率) = 模型.排序器.排序(候选特征: 特征, 空特征: 空特征)
        // 用户多半是在找作品或角色：会社和制作人员只有明显更像时才排到它们前面
        let 排序后 = 排序结果.enumerated().sorted { a, b in
            let 分a = a.element.概率 * Self.类型权重(模型.类型(候选[a.element.下标]))
            let 分b = b.element.概率 * Self.类型权重(模型.类型(候选[b.element.下标]))
            return 分a != 分b ? 分a > 分b : a.offset < b.offset
        }.map(\.element)
        let 命中 = 排序后.prefix(数量).map { 结果 in
            let 文档 = 候选[结果.下标]
            let 类型 = 模型.类型(文档)
            let 名称 = 名称特征[结果.下标]
            let 前缀: String
            var 系列: String?
            var 所属作品: String?
            switch 类型 {
            case .视觉小说:
                前缀 = "v"
                let 值 = 模型.系列[文档]
                系列 = 值 == 0 ? nil : "v\(值)"
            case .角色:
                前缀 = "c"
                let 值 = 模型.所属作品[文档 - 模型.作品数]
                所属作品 = 值 == 0 ? nil : "v\(值)"
            case .会社:
                前缀 = "p"
            case .制作人员:
                前缀 = "s"
            }
            return 智能搜索命中(
                类型: 类型,
                编号: 前缀 + String(模型.编号[文档]),
                概率: 结果.概率,
                名称匹配: 名称.完全一致 || 名称.f >= 0.5,
                系列: 系列,
                所属作品: 所属作品
            )
        }
        return 智能搜索结果集(命中: Array(命中), 空概率: 空概率)
    }

    private static func 类型权重(_ 类型: 智能搜索条目类型) -> Float {
        switch 类型 {
        case .视觉小说, .角色: return 1
        case .会社, .制作人员: return 0.3
        }
    }

    private static func 是中日文(_ 字: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(字.value)
            || (0x3400...0x9FFF).contains(字.value)
            || (0xAC00...0xD7A3).contains(字.value)
    }
}
