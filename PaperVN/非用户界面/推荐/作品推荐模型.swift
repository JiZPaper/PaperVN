import Foundation

/// “为你推荐”的动画、漫画与轻小说模型（`PaperVNWorkRecommendation.pvwr`，预装在 App 里）。
///
/// 每部作品是一个稀疏向量（已归一化），资料库里的视觉小说也有向量，可以用来推荐其他类型。
///
/// 文件：“PVWR”、UInt32 标识长度、标识（UTF-8）、UInt32 原文长度、raw DEFLATE 压缩的 JSON。
/// 作品编号与 Hiro智能一致（见 `作品搜索结果.编号`），视觉小说用 VNDB ID。
nonisolated struct 作品推荐模型: Sendable {
    nonisolated struct 模型参数: Codable, Hashable, Sendable {
        let personWeight: Double
        let qualityWeight: Double
        let popularityWeight: Double
        /// 评分太少、算不出个人尺度时用的尺度（10–100 分制）。
        let ratingScale: Double
    }

    /// 稀疏向量：第 i 个向量的特征是 `特征[偏移[i]..<偏移[i+1]]`，值已经 L2 归一化。
    nonisolated struct 向量组: Sendable {
        let 偏移: [Int32]
        let 特征: [Int32]
        let 值: [Float]

        init(_ vectors: [[Int]]) {
            var offsets: [Int32] = [0]
            var features: [Int32] = []
            var values: [Float] = []
            offsets.reserveCapacity(vectors.count + 1)
            features.reserveCapacity(vectors.count * 24)
            values.reserveCapacity(vectors.count * 24)
            for vector in vectors {
                // [特征, 量化值, 特征, 量化值, …]；量化后不再严格归一化，载入时重新归一化
                var squared: Float = 0
                var index = 1
                while index < vector.count {
                    let value = Float(vector[index])
                    squared += value * value
                    index += 2
                }
                let length = squared > 0 ? squared.squareRoot() : 1
                index = 0
                while index + 1 < vector.count {
                    features.append(Int32(vector[index]))
                    values.append(Float(vector[index + 1]) / length)
                    index += 2
                }
                offsets.append(Int32(features.count))
            }
            偏移 = offsets
            特征 = features
            值 = values
        }

        func 范围(_ index: Int) -> Range<Int> {
            Int(偏移[index])..<Int(偏移[index + 1])
        }
    }

    let 标识: String
    let 参数: 模型参数
    let 特征数: Int
    let 作品键: [String]
    let 作品下标: [String: Int]
    let 作品系列: [Int32]
    let 质量: [Float]
    let 热度: [Float]
    let 成人: [Bool]
    let 可推荐: [Bool]
    let 作品向量: 向量组
    let 视觉小说下标: [String: Int]
    let 视觉小说系列: [Int32]
    let 视觉小说向量: 向量组
}

nonisolated enum 作品推荐模型错误: Error {
    case 文件无效
    case 版本不受支持
}

nonisolated extension 作品推荐模型 {
    static let 当前格式版本 = 1
    static let 资源名 = "PaperVNWorkRecommendation"
    static let 扩展名 = "pvwr"

    private struct 文件: Decodable {
        struct 作品: Decodable {
            let keys: [String]
            let series: [Int32]
            let quality: [Float]
            let popularity: [Float]
            let adult: [UInt8]
            let recommendable: [UInt8]
            let vectors: [[Int]]
        }
        struct 视觉小说: Decodable {
            let ids: [String]
            let series: [Int32]
            let vectors: [[Int]]
        }
        let formatVersion: Int
        let parameters: 模型参数
        let featureCount: Int
        let works: 作品
        let visualNovels: 视觉小说
    }

    /// 只读出标识，不解压。
    static func 标识(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 8), header.count == 8,
              header.prefix(4) == Data("PVWR".utf8) else { return nil }
        let length = Int(读取UInt32(header, at: 4))
        guard length > 0, length < 256, let id = try? handle.read(upToCount: length), id.count == length else { return nil }
        return String(data: id, encoding: .utf8)
    }

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try self.init(data: data)
    }

    init(data: Data) throws {
        guard data.count > 12, data.prefix(4) == Data("PVWR".utf8) else { throw 作品推荐模型错误.文件无效 }
        let idLength = Int(Self.读取UInt32(data, at: 4))
        let idEnd = 8 + idLength
        guard idEnd + 4 <= data.count,
              let id = String(data: data.subdata(in: 8..<idEnd), encoding: .utf8) else {
            throw 作品推荐模型错误.文件无效
        }
        let rawLength = Int(Self.读取UInt32(data, at: idEnd))
        let compressed = data.subdata(in: (idEnd + 4)..<data.count)
        // NSData 的 .zlib 是不带头的 raw DEFLATE，与构建脚本一致
        guard let json = try? (compressed as NSData).decompressed(using: .zlib) as Data,
              json.count == rawLength else {
            throw 作品推荐模型错误.文件无效
        }
        let file = try JSONDecoder().decode(文件.self, from: json)
        guard file.formatVersion == Self.当前格式版本 else { throw 作品推荐模型错误.版本不受支持 }
        let works = file.works
        let count = works.keys.count
        guard works.series.count == count, works.quality.count == count, works.popularity.count == count,
              works.adult.count == count, works.recommendable.count == count, works.vectors.count == count,
              file.visualNovels.series.count == file.visualNovels.ids.count,
              file.visualNovels.vectors.count == file.visualNovels.ids.count else {
            throw 作品推荐模型错误.文件无效
        }
        标识 = id
        参数 = file.parameters
        特征数 = file.featureCount
        作品键 = works.keys
        作品下标 = Dictionary(works.keys.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        作品系列 = works.series
        质量 = works.quality
        热度 = works.popularity
        成人 = works.adult.map { $0 != 0 }
        可推荐 = works.recommendable.map { $0 != 0 }
        作品向量 = 向量组(works.vectors)
        视觉小说下标 = Dictionary(
            file.visualNovels.ids.enumerated().map { ($1.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        视觉小说系列 = file.visualNovels.series
        视觉小说向量 = 向量组(file.visualNovels.vectors)
    }

    private static func 读取UInt32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start]) | UInt32(data[start + 1]) << 8
            | UInt32(data[start + 2]) << 16 | UInt32(data[start + 3]) << 24
    }
}

/// 资料库里的一部作品对推荐的意义。
nonisolated struct 作品推荐反馈: Hashable, Sendable {
    /// 模型里的编号（“a5114”“v17”）；同一部作品可能对应几个候选编号，取模型里有的第一个。
    let 候选编号: [String]
    /// 10–100。
    let 评分: Int?
    let 状态: 资料库状态?
}

nonisolated struct 作品推荐分数: Hashable, Sendable {
    let 编号: String
    let 类型: 作品类型
    let 分数: Double
}

nonisolated extension 作品推荐模型 {
    /// 资料库条目的编号（“mal-anime:5114”“aniList-manga:30002”“bangumi-anime:12”“vn:v17”）换成模型里的候选编号。
    static func 候选编号(条目ID id: String, 类型 type: 作品类型, malID: Int?) -> [String] {
        if type == .visualNovel {
            guard id.hasPrefix("vn:") else { return [id.lowercased()] }
            return [String(id.dropFirst(3)).lowercased()]
        }
        // 漫画和轻小说在 MAL 上是同一类（manga），平台对“轻小说”的判断不完全一致，两个前缀都试
        let prefixes: [String] = switch type {
        case .anime: ["a"]
        case .lightNovel: ["n", "m"]
        default: ["m", "n"]
        }
        var number: UInt32?
        if let malID, malID > 0 {
            number = UInt32(malID)
        } else if let colon = id.lastIndex(of: ":"), let value = UInt32(id[id.index(after: colon)...]) {
            if id.hasPrefix("aniList-") { number = 作品搜索结果.AniList标记 | value }
            else if id.hasPrefix("bangumi-") { number = 作品搜索结果.Bangumi标记 | value }
            else if id.hasPrefix("mal-") { number = value }
        }
        guard let number else { return [] }
        return prefixes.map { "\($0)\(number)" }
    }

    /// 资料库状态在没有评分时的信号，与视觉小说推荐一致。
    static func 状态信号(_ status: 资料库状态?) -> Double {
        switch status {
        case .completed: 0.20
        case .inProgress: 0.12
        case .planning: 0.05
        case .onHold: -0.08
        case .dropped: -0.45
        case nil: 0
        }
    }

    /// 评分的中心与尺度：中位数和 1.4826×MAD（至少 10）；评分少于 5 个时用 70 和模型参数里的尺度。
    func 评分中心与尺度(_ ratings: [Int]) -> (center: Double, scale: Double) {
        guard ratings.count >= 5 else { return (70, 参数.ratingScale) }
        let sorted = ratings.map(Double.init).sorted()
        let median = Self.中位数(sorted)
        let deviations = sorted.map { abs($0 - median) }.sorted()
        return (median, max(10, 1.4826 * deviations[deviations.count / 2]))
    }

    private static func 中位数(_ sorted: [Double]) -> Double {
        let count = sorted.count
        return count % 2 == 1 ? sorted[count / 2] : (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }

    /// 按资料库推荐作品。
    /// 资料库里已有的作品和它们所在的系列不推荐，每个系列最多一部。资料库没有任何可用的作品时返回空。
    func 推荐(
        资料库 feedback: [作品推荐反馈],
        类型 types: Set<作品类型>,
        包含成人内容: Bool,
        数量 limit: Int
    ) -> [作品推荐分数] {
        let center = 评分中心与尺度(feedback.compactMap(\.评分))
        var profile = [Float](repeating: 0, count: 特征数)
        var librarySeries: Set<Int32> = []
        var libraryWorks: Set<Int> = []
        var hasEvidence = false

        func add(_ vectors: 向量组, _ index: Int, weight: Float) {
            for position in vectors.范围(index) {
                let feature = Int(vectors.特征[position])
                guard feature < profile.count else { continue }
                profile[feature] += weight * vectors.值[position]
            }
        }

        for item in feedback {
            let weight: Double
            if let rating = item.评分 {
                weight = 0.9 * tanh((Double(rating) - center.center) / center.scale) + 0.1 * Self.状态信号(item.状态)
            } else {
                weight = Self.状态信号(item.状态)
            }
            for id in item.候选编号 {
                if let index = 作品下标[id] {
                    librarySeries.insert(作品系列[index])
                    libraryWorks.insert(index)
                    if weight != 0 { add(作品向量, index, weight: Float(weight)); hasEvidence = true }
                    break
                }
                if let index = 视觉小说下标[id] {
                    librarySeries.insert(视觉小说系列[index])
                    if weight != 0 { add(视觉小说向量, index, weight: Float(weight)); hasEvidence = true }
                    break
                }
            }
        }
        let length = profile.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard hasEvidence, length > 0 else { return [] }

        let qualityWeight = Float(参数.qualityWeight)
        let popularityWeight = Float(参数.popularityWeight)
        var scored: [(index: Int, type: 作品类型, score: Float)] = []
        scored.reserveCapacity(4_096)
        for index in 作品键.indices where 可推荐[index] {
            guard let type = Self.类型(of: 作品键[index]), types.contains(type),
                  包含成人内容 || !成人[index],
                  !libraryWorks.contains(index),
                  !librarySeries.contains(作品系列[index]) else { continue }
            var dot: Float = 0
            for position in 作品向量.范围(index) {
                let feature = Int(作品向量.特征[position])
                guard feature < profile.count else { continue }
                dot += profile[feature] * 作品向量.值[position]
            }
            scored.append((index, type, dot / length + qualityWeight * 质量[index] + popularityWeight * 热度[index]))
        }
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }

        var usedSeries: Set<Int32> = []
        var result: [作品推荐分数] = []
        for entry in scored {
            guard usedSeries.insert(作品系列[entry.index]).inserted else { continue }
            result.append(作品推荐分数(编号: 作品键[entry.index], 类型: entry.type, 分数: Double(entry.score)))
            if result.count >= limit { break }
        }
        return result
    }

    static func 类型(of key: String) -> 作品类型? {
        switch key.first {
        case "a": .anime
        case "m": .manga
        case "n": .lightNovel
        default: nil
        }
    }
}
