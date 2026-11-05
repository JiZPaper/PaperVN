import Accelerate
import Foundation

/// 召回之后的精排：每类按召回分数取前 `候选数` 部，再用一个小型神经网络按更多特征重新排序。
/// 特征和网络由构建脚本写进模型文件（`reranker`、`itemStats`），特征名或维数对不上时不使用精排。
nonisolated struct 作品推荐精排: Sendable {
    /// 与构建脚本的 精排特征名 一致。
    static let 特征名 = ["scoreZ", "rank", "collaborativeZ", "related", "popularity", "popularityRank", "quality", "ratingCount",
                      "year", "yearMissing", "yearOffset", "librarySize", "typeCount", "typeShare", "meanRating", "ratedShare",
                      "vectorNorm", "anime", "manga", "lightNovel", "visualNovel"]

    nonisolated struct 层: Sendable {
        let 输入: Int
        let 输出: Int
        /// 输入 × 输出（转置后的权重，方便矩阵乘法）。
        let 权重: [Float]
        let 偏置: [Float]
    }

    let 候选数: Int
    /// 最终分数 = 精排分 + 召回权重 × 召回分数（标准化后）；只用精排会偏向热门和当季新番。
    let 召回权重: Float
    let 均值: [Float]
    let 标准差: [Float]
    let 层们: [层]
    // 每部作品的统计
    let 热度: [Float]
    let 热度分位: [Float]
    let 评分质量: [Float]
    let 评分人数: [Float]
    /// 0 表示不知道。
    let 年份: [Float]
    let 向量长度: [Float]

    nonisolated struct 文件: Decodable {
        struct 层文件: Decodable {
            let inputs: Int
            let outputs: Int
            /// [输出][输入] 行优先。
            let weights: [Float]
            let biases: [Float]
        }

        let candidates: Int
        let recallWeight: Float?
        let features: [String]
        let mean: [Float]
        let std: [Float]
        let layers: [层文件]
    }

    nonisolated struct 统计文件: Decodable {
        let popularity: [Float]
        let popularityRank: [Float]
        let quality: [Float]
        let ratingCount: [Float]
        let year: [Float]
    }

    init?(文件 file: 文件?, 统计 stats: 统计文件?, 向量 vectors: [Float], count: Int, k: Int) {
        guard let file, let stats, file.candidates > 0, file.features == Self.特征名,
              file.mean.count == Self.特征名.count, file.std.count == Self.特征名.count,
              file.layers.first?.inputs == Self.特征名.count, file.layers.last?.outputs == 1,
              [stats.popularity, stats.popularityRank, stats.quality, stats.ratingCount, stats.year].allSatisfy({ $0.count == count })
        else { return nil }
        var layers: [层] = []
        var inputs = Self.特征名.count
        for layer in file.layers {
            guard layer.inputs == inputs, layer.weights.count == layer.inputs * layer.outputs,
                  layer.biases.count == layer.outputs else { return nil }
            var transposed = [Float](repeating: 0, count: layer.weights.count)
            for o in 0..<layer.outputs {
                for i in 0..<layer.inputs {
                    transposed[i * layer.outputs + o] = layer.weights[o * layer.inputs + i]
                }
            }
            layers.append(层(输入: layer.inputs, 输出: layer.outputs, 权重: transposed, 偏置: layer.biases))
            inputs = layer.outputs
        }
        候选数 = file.candidates
        召回权重 = file.recallWeight ?? 0
        均值 = file.mean
        标准差 = file.std.map { $0 < 1e-6 ? 1 : $0 }
        层们 = layers
        热度 = stats.popularity
        热度分位 = stats.popularityRank
        评分质量 = stats.quality
        评分人数 = stats.ratingCount
        年份 = stats.year
        var norms = [Float](repeating: 0, count: count)
        for i in 0..<count {
            var sum: Float = 0
            for j in 0..<k { sum += vectors[i * k + j] * vectors[i * k + j] }
            norms[i] = sum.squareRoot()
        }
        向量长度 = norms
    }

    /// 资料库整体的特征，每类共用。
    nonisolated struct 资料库概况 {
        let 部数: Int
        let 各类部数: [作品类型: Int]
        let 平均评分: Float
        let 有分比例: Float
        /// 资料库作品年份的中位数。
        let 年份中位数: Float?
    }

    func 概况(_ rows: [Int], 评分 ratings: [Int?], 类型 typeOf: (Int) -> 作品类型?) -> 资料库概况 {
        var counts: [作品类型: Int] = [:]
        for row in rows {
            if let type = typeOf(row) { counts[type, default: 0] += 1 }
        }
        let rated = ratings.compactMap { $0 }.filter { $0 > 0 }
        let years = rows.map { 年份[$0] }.filter { $0 > 0 }.sorted()
        var median: Float?
        if !years.isEmpty {
            median = years.count % 2 == 1 ? years[years.count / 2] : (years[years.count / 2 - 1] + years[years.count / 2]) / 2
        }
        let n = max(rows.count, 1)
        return 资料库概况(
            部数: rows.count,
            各类部数: counts,
            平均评分: rated.isEmpty ? 0 : Float(Double(rated.reduce(0, +)) / Double(rated.count) / 100),
            有分比例: Float(rated.count) / Float(n),
            年份中位数: median
        )
    }

    /// `候选`：这一类全部可推荐、不在资料库系列里的作品（含成人作品），已按召回分数从高到低排好。
    /// 返回前 `候选数` 部重新排序后的下标与精排分数；候选不多于 `候选数` 部时返回 nil（不精排）。
    func 重新排序(
        候选 sorted: [Int],
        类型 type: 作品类型,
        分数 scores: [Float],
        协同分数 collaborative: [Float],
        社区加成 related: [Float]?,
        资料库 library: 资料库概况
    ) -> [(index: Int, score: Float)]? {
        guard sorted.count > 候选数 else { return nil }
        func 均值与标准差(_ values: [Float]) -> (Float, Float) {
            var sum = 0.0, squares = 0.0
            for i in sorted {
                let value = Double(values[i])
                sum += value; squares += value * value
            }
            let mean = sum / Double(sorted.count)
            let std = (max(squares / Double(sorted.count) - mean * mean, 0)).squareRoot()
            return (Float(mean), std > 0 ? Float(std) : 1)
        }
        let (μ, σ) = 均值与标准差(scores)
        let (μ协, σ协) = 均值与标准差(collaborative)
        let top = Array(sorted.prefix(候选数))
        let d = Self.特征名.count
        let n = Float(max(library.部数, 1))
        let typeCount = Float(library.各类部数[type] ?? 0)
        let common: [Float] = [
            log1p(Float(library.部数)), log1p(typeCount), typeCount / n, library.平均评分, library.有分比例,
        ]
        let oneHot: [Float] = [作品类型.anime, .manga, .lightNovel, .visualNovel].map { $0 == type ? 1 : 0 }
        var features = [Float](repeating: 0, count: top.count * d)
        for (position, i) in top.enumerated() {
            let year = 年份[i]
            let offset: Float = if year > 0, let median = library.年份中位数 { year - median } else { 0 }
            let row: [Float] = [
                (scores[i] - μ) / σ, log1p(Float(position)), (collaborative[i] - μ协) / σ协, related?[i] ?? 0,
                热度[i], 热度分位[i], 评分质量[i], 评分人数[i],
                year, year > 0 ? 0 : 1, offset,
            ] + common + [向量长度[i]] + oneHot
            for j in 0..<d {
                features[position * d + j] = (row[j] - 均值[j]) / 标准差[j]
            }
        }
        var output = 前向(features, rows: top.count)
        if 召回权重 != 0 {
            for (position, i) in top.enumerated() { output[position] += 召回权重 * ((scores[i] - μ) / σ) }
        }
        return zip(top, output).enumerated()
            .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
            .map { (index: $0.element.0, score: $0.element.1) }
    }

    /// 多层感知机：除最后一层外接 ReLU。`input` 是 rows × 特征数，行优先。
    private func 前向(_ input: [Float], rows: Int) -> [Float] {
        var current = input
        for (number, layer) in 层们.enumerated() {
            var next = [Float](repeating: 0, count: rows * layer.输出)
            vDSP_mmul(current, 1, layer.权重, 1, &next, 1, vDSP_Length(rows), vDSP_Length(layer.输出), vDSP_Length(layer.输入))
            let last = number == 层们.count - 1
            for r in 0..<rows {
                for o in 0..<layer.输出 {
                    let value = next[r * layer.输出 + o] + layer.偏置[o]
                    next[r * layer.输出 + o] = last ? value : max(value, 0)
                }
            }
            current = next
        }
        return current
    }
}
