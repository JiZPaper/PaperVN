import Foundation

/// 综合名称匹配和热度给候选打分的小型网络，权重由 `Tools/智能搜索模型/模糊.py` 训练。
/// 除候选外还有一个“没有合适结果”选项：它的概率高说明输入不像任何一个名字。
nonisolated struct 智能搜索排序器: Sendable {
    static let 特征名 = [
        "f", "p", "r", "exact", "prefix", "contains", "f_gap", "prior", "prior_gap",
        "is_char", "is_producer", "is_staff", "len_ratio", "query_len", "query_cjk",
    ]
    static let 空特征名 = ["f_max", "exact_any", "prefix_any", "query_len", "query_cjk"]

    private nonisolated struct 层: Sendable {
        let 权重: [[Float]]
        let 偏置: [Float]
    }

    private nonisolated struct 文件格式: Decodable {
        nonisolated struct 线性层: Decodable {
            let weight: [[Float]]
            let bias: [Float]
        }

        nonisolated struct 空选项: Decodable {
            let weight: [Float]
            let bias: Float
        }

        let features: [String]
        let nullFeatures: [String]
        let layers: [线性层]
        let null: 空选项
    }

    private let 层列表: [层]
    private let 空权重: [Float]
    private let 空偏置: Float

    init(数据: Data) throws {
        let 格式 = try JSONDecoder().decode(文件格式.self, from: 数据)
        guard 格式.features == Self.特征名,
              格式.nullFeatures == Self.空特征名,
              格式.null.weight.count == Self.空特征名.count,
              格式.layers.first?.weight.first?.count == Self.特征名.count,
              格式.layers.last?.weight.count == 1 else {
            throw 智能搜索模型错误.缺少数据("ranker")
        }
        层列表 = 格式.layers.map { 层(权重: $0.weight, 偏置: $0.bias) }
        空权重 = 格式.null.weight
        空偏置 = 格式.null.bias
    }

    func 分数(_ 特征: [Float]) -> Float {
        var 输入 = 特征
        for (序号, 层) in 层列表.enumerated() {
            var 输出 = 层.偏置
            for 行 in 0..<输出.count {
                var 和 = 输出[行]
                let 权重行 = 层.权重[行]
                for 列 in 0..<输入.count {
                    和 += 权重行[列] * 输入[列]
                }
                输出[行] = 序号 < 层列表.count - 1 ? max(和, 0) : 和
            }
            输入 = 输出
        }
        return 输入[0]
    }

    func 空分数(_ 特征: [Float]) -> Float {
        zip(空权重, 特征).reduce(空偏置) { $0 + $1.0 * $1.1 }
    }

    /// 返回全部候选按概率从高到低的下标和概率，以及“没有合适结果”的概率。
    func 排序(候选特征: [[Float]], 空特征: [Float]) -> (结果: [(下标: Int, 概率: Float)], 空概率: Float) {
        guard !候选特征.isEmpty else { return ([], 1) }
        let 分 = 候选特征.map(分数) + [空分数(空特征)]
        let 最大 = 分.max() ?? 0
        let 指数 = 分.map { exp($0 - 最大) }
        let 总和 = 指数.reduce(0, +)
        let 概率 = 指数.map { $0 / 总和 }
        let 结果 = 概率.dropLast()
            .enumerated()
            .sorted { $0.element != $1.element ? $0.element > $1.element : $0.offset < $1.offset }
            .map { (下标: $0.offset, 概率: $0.element) }
        return (结果, 概率[概率.count - 1])
    }
}
