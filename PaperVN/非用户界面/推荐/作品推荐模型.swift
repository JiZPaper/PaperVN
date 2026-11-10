import Foundation

/// “为你推荐”的动画、漫画与轻小说模型（`PaperVNWorkRecommendation.pvwr`，预装在 App 里）。
///
/// 每部作品（含视觉小说）有一个低维向量；App 按资料库解出用户的向量，和作品向量的内积就是推荐分数。
/// 资料库里的视觉小说也会用来推荐其他类型。
///
/// 文件：“PVWR”、UInt32 标识长度、标识（UTF-8）、UInt32 原文长度、raw DEFLATE 压缩的 JSON。
/// 作品编号与智能搜索模型一致（见 `作品搜索结果.编号`），视觉小说用 VNDB ID。
nonisolated struct 作品推荐模型: Sendable {
    nonisolated struct 模型参数: Codable, Hashable, Sendable {
        let factors: Int
        let regularization: Double
        let alpha: Double
        /// 视觉小说、漫画、轻小说的置信度强度；没有时和动画一样用 alpha。
        let alphaVN: Double?
        let alphaManga: Double?
        let alphaNovel: Double?
        let ratingBoost: Double
        let wishWeight: Double
        /// 相似作品的权重；没有时不使用。
        let neighborWeight: Double?
        let relatedWeight: Double
        /// 资料库少于 userRegRef 部时加大正则：λ × (userRegRef / 部数)^userRegPower。没有时不调整。
        let userRegPower: Double?
        let userRegRef: Double?
    }

    let 标识: String
    let 参数: 模型参数
    let 维数: Int
    let 编号: [String]
    let 下标: [String: Int]
    let 系列: [Int32]
    let 成人: [Bool]
    let 可推荐: [Bool]
    /// 条目数 × 维数，行优先。
    let 向量: [Float]
    /// 向量ᵀ向量（维数 × 维数），解用户向量时用。
    let 格拉姆: [Double]
    /// 第 i 部作品的相关作品是 `相关下标[相关偏移[i]..<相关偏移[i+1]]`，权重之和不超过 1。
    let 相关偏移: [Int32]
    let 相关下标: [Int32]
    let 相关权重: [Float]
    /// 第 i 部作品最相似的作品，格式同上。
    let 相似偏移: [Int32]
    let 相似下标: [Int32]
    let 相似权重: [Float]
    /// 推荐的作品是续作时显示的系列入口（正篇最早的一部），键和值都是下标。
    let 入口: [Int32: Int32]
    /// 召回之后的精排；模型里没有时按召回分数排序。
    let 精排: 作品推荐精排?
}

nonisolated enum 作品推荐模型错误: LocalizedError {
    case 文件无效
    case 版本不受支持
    case 服务器响应无效
    case 无法读取作品信息

    var errorDescription: String? {
        switch self {
        case .文件无效:
            String(localized: "“为你推荐”模型文件已损坏，请重新下载。")
        case .版本不受支持:
            String(localized: "此版本的PaperVN无法使用这个“为你推荐”模型，请更新App。")
        case .服务器响应无效:
            String(localized: "无法从服务器下载“为你推荐”模型。")
        case .无法读取作品信息:
            String(localized: "无法连接服务器")
        }
    }
}

nonisolated extension 作品推荐模型 {
    static let 支持的格式版本 = 2...3
    static let 资源名 = "PaperVNWorkRecommendation"
    static let 扩展名 = "pvwr"

    private struct 文件: Decodable {
        let formatVersion: Int
        let parameters: 模型参数
        let keys: [String]
        let series: [Int32]
        let adult: [UInt8]
        let recommendable: [UInt8]
        let scales: [Float]
        let factors: String
        /// 向量ᵀ向量（维数 × 维数，行优先），由构建脚本算好；没有时载入后自己算。
        let gram: [Double]?
        /// 每部作品：[下标, 权重, 下标, 权重, …]
        let related: [[Double]]
        /// 每部作品最相似的作品，格式同 related（格式 3 起）。
        let neighbors: [[Double]]?
        /// [推荐的下标, 入口下标, …]；没有时直接显示推荐的作品。
        let entries: [Int32]?
        let reranker: 作品推荐精排.文件?
        let itemStats: 作品推荐精排.统计文件?
    }

    /// 只读出标识，不解压。
    static func 标识(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 264)).flatMap(标识(头:))
    }

    /// 从文件开头（至少 8 字节加标识长度）读取模型标识，用于只下载文件开头比较版本。
    static func 标识(头 header: Data) -> String? {
        guard header.count >= 8, header.prefix(4) == Data("PVWR".utf8) else { return nil }
        let length = Int(读取UInt32(header, at: 4))
        guard length > 0, length < 256, header.count >= 8 + length else { return nil }
        let start = header.startIndex + 8
        return String(data: header[start..<start + length], encoding: .utf8)
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
        guard Self.支持的格式版本.contains(file.formatVersion) else { throw 作品推荐模型错误.版本不受支持 }
        let count = file.keys.count
        let k = file.parameters.factors
        guard k > 0, file.series.count == count, file.adult.count == count, file.recommendable.count == count,
              file.scales.count == count, file.related.count == count,
              let bytes = Data(base64Encoded: file.factors), bytes.count == count * k else {
            throw 作品推荐模型错误.文件无效
        }
        var vectors = [Float](repeating: 0, count: count * k)
        bytes.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: Int8.self)
            for i in 0..<count {
                let scale = file.scales[i]
                for j in 0..<k {
                    vectors[i * k + j] = Float(values[i * k + j]) * scale
                }
            }
        }
        var gram = file.gram ?? []
        if gram.count != k * k {
            gram = Self.计算格拉姆(vectors, count: count, k: k)
        }
        let related = Self.展开(file.related, count: count)
        let similar = Self.展开(file.neighbors ?? Array(repeating: [], count: count), count: count)
        标识 = id
        参数 = file.parameters
        维数 = k
        编号 = file.keys
        下标 = Dictionary(file.keys.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        系列 = file.series
        成人 = file.adult.map { $0 != 0 }
        可推荐 = file.recommendable.map { $0 != 0 }
        向量 = vectors
        格拉姆 = gram
        相关偏移 = related.offsets
        相关下标 = related.indices
        相关权重 = related.weights
        相似偏移 = similar.offsets
        相似下标 = similar.indices
        相似权重 = similar.weights
        var entries: [Int32: Int32] = [:]
        if let pairs = file.entries {
            for index in stride(from: 0, to: pairs.count - 1, by: 2)
            where (0..<Int32(count)).contains(pairs[index]) && (0..<Int32(count)).contains(pairs[index + 1]) {
                entries[pairs[index]] = pairs[index + 1]
            }
        }
        入口 = entries
        精排 = 作品推荐精排(文件: file.reranker, 统计: file.itemStats, 向量: vectors, count: count, k: k)
    }

    /// [[下标, 权重, …]] → 偏移、下标、权重三个平铺数组。
    private static func 展开(_ rows: [[Double]], count: Int) -> (offsets: [Int32], indices: [Int32], weights: [Float]) {
        var offsets: [Int32] = [0]
        var indices: [Int32] = []
        var weights: [Float] = []
        for row in rows {
            var index = 0
            while index + 1 < row.count {
                let neighbor = Int(row[index])
                if neighbor >= 0, neighbor < count {
                    indices.append(Int32(neighbor))
                    weights.append(Float(row[index + 1]))
                }
                index += 2
            }
            offsets.append(Int32(indices.count))
        }
        while offsets.count < count + 1 { offsets.append(Int32(indices.count)) }
        return (offsets, indices, weights)
    }

    private static func 计算格拉姆(_ vectors: [Float], count: Int, k: Int) -> [Double] {
        var gram = [Double](repeating: 0, count: k * k)
        for i in 0..<count {
            let base = i * k
            for a in 0..<k {
                let va = Double(vectors[base + a])
                guard va != 0 else { continue }
                for b in a..<k {
                    gram[a * k + b] += va * Double(vectors[base + b])
                }
            }
        }
        for a in 0..<k {
            for b in 0..<a {
                gram[a * k + b] = gram[b * k + a]
            }
        }
        return gram
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

    /// 资料库状态 → 模型使用的类型编号（1 计划 2 已完成 3 进行中 4 搁置 5 抛弃）。
    static func 收藏类型(_ status: 资料库状态?) -> Int {
        switch status {
        case .planning: 1
        case .completed: 2
        case .inProgress: 3
        case .onHold: 4
        case .dropped: 5
        case nil: 0
        }
    }

    static func 状态信号(_ type: Int) -> Double {
        switch type {
        case 1: 0.05
        case 2: 0.20
        case 3: 0.12
        case 4: -0.08
        case 5: -0.45
        default: 0
        }
    }

    private static func 中位数(_ sorted: [Double]) -> Double {
        let count = sorted.count
        return count % 2 == 1 ? sorted[count / 2] : (sorted[count / 2 - 1] + sorted[count / 2]) / 2
    }

    /// 每条资料库记录的偏好（1 选过 / 0 不喜欢）与置信度。
    /// 评分按用户自己的中位数和尺度换成信号；没有评分也没有状态的记录不参与。
    func 偏好与置信(_ items: [(评分: Int?, 类型: Int, 作品类型: 作品类型?)]) -> [(偏好: Double, 置信: Double)?] {
        let ratings = items.compactMap(\.评分).map(Double.init).sorted()
        var center = 70.0, scale = 15.0
        if ratings.count >= 5 {
            center = Self.中位数(ratings)
            scale = max(10, 1.4826 * Self.中位数(ratings.map { abs($0 - center) }.sorted()))
        }
        return items.map { item in
            // 有评分但没有状态时当作看过
            let type = item.类型 == 0 && item.评分 != nil ? 2 : item.类型
            guard type != 0 else { return nil }
            let status = Self.状态信号(type)
            let signal = item.评分.map { 0.9 * tanh((Double($0) - center) / scale) + 0.1 * status } ?? status
            let disliked = type == 5 || (item.评分 != nil && signal < -0.3)
            let typeWeight: Double = switch type {
            case 1: 参数.wishWeight
            case 3: 0.8
            case 4: 0.5
            default: 1.0
            }
            let strength = disliked ? 1 + abs(signal) : typeWeight * (1 + 参数.ratingBoost * max(signal, 0))
            let alpha = switch item.作品类型 {
            case .visualNovel: 参数.alphaVN ?? 参数.alpha
            case .manga: 参数.alphaManga ?? 参数.alpha
            case .lightNovel: 参数.alphaNovel ?? 参数.alpha
            default: 参数.alpha
            }
            return (disliked ? 0 : 1, 1 + alpha * strength)
        }
    }

    /// 资料库解出的推荐分数（召回阶段）。
    private struct 资料库召回 {
        let rows: [Int]
        let 评分: [Int?]
        let librarySeries: Set<Int32>
        /// 协同分数加上相似作品与社区推荐的加成。
        let scores: [Float]
        let collaborative: [Float]
        /// 0–1 的社区推荐加成（精排的特征）；没有时为 nil。
        let related: [Float]?
    }

    /// 资料库没有任何一部作品在模型里、或者没有一条可用的记录时返回 nil。
    private func 召回(资料库 feedback: [作品推荐反馈]) -> 资料库召回? {
        let k = 维数
        var rows: [Int] = []
        var raw: [(评分: Int?, 类型: Int, 作品类型: 作品类型?)] = []
        var librarySeries: Set<Int32> = []
        for item in feedback {
            guard let index = item.候选编号.lazy.compactMap({ 下标[$0.lowercased()] }).first else { continue }
            rows.append(index)
            raw.append((item.评分, Self.收藏类型(item.状态), Self.类型(of: 编号[index])))
            librarySeries.insert(系列[index])
        }
        let weights = 偏好与置信(raw)
        let used = weights.count(where: { $0 != nil })
        guard used > 0 else { return nil }
        // A = YᵀY + Σ (c−1) y yᵀ + λI，b = Σ c·p·y；资料库很小时加大 λ，不被少数作品带偏
        var regularization = 参数.regularization
        if let power = 参数.userRegPower, let reference = 参数.userRegRef, power > 0 {
            regularization *= pow(max(1, reference / Double(used)), power)
        }
        var A = 格拉姆
        for i in 0..<k { A[i * k + i] += regularization }
        var b = [Double](repeating: 0, count: k)
        var liked = [Int: Double]()
        for (row, weight) in zip(rows, weights) {
            guard let weight else { continue }
            let base = row * k
            let extra = weight.置信 - 1
            for a in 0..<k {
                let va = Double(向量[base + a])
                b[a] += weight.置信 * weight.偏好 * va
                guard va != 0 else { continue }
                for c in a..<k {
                    A[a * k + c] += extra * va * Double(向量[base + c])
                }
            }
            liked[row, default: 0] += weight.偏好 * extra
        }
        for a in 0..<k {
            for c in 0..<a { A[a * k + c] = A[c * k + a] }
        }
        guard let user = Self.解正定方程组(A, b, size: k) else { return nil }
        let userVector = user.map(Float.init)

        let count = 编号.count
        var scores = [Float](repeating: 0, count: count)
        var absoluteSum: Float = 0
        for i in 0..<count {
            var dot: Float = 0
            let base = i * k
            for a in 0..<k { dot += 向量[base + a] * userVector[a] }
            scores[i] = dot
            absoluteSum += abs(dot)
        }
        // 相似作品与作品间社区推荐的加成，都缩放到和协同分相当的量级；返回 0–1 的加成（精排的特征）
        let collaborative = scores
        let scale = absoluteSum / Float(count)
        @discardableResult
        func 加成(_ weight: Double?, _ offsets: [Int32], _ indices: [Int32], _ weights: [Float]) -> [Float]? {
            guard let weight, weight > 0, !liked.isEmpty else { return nil }
            var bonus = [Float](repeating: 0, count: count)
            for (row, value) in liked where value > 0 {
                for position in Int(offsets[row])..<Int(offsets[row + 1]) {
                    bonus[Int(indices[position])] += Float(value) * weights[position]
                }
            }
            guard let maximum = bonus.max(), maximum > 0 else { return nil }
            let factor = Float(weight) * scale / maximum
            for i in 0..<count where bonus[i] > 0 { scores[i] += factor * bonus[i] }
            return bonus.map { $0 / maximum }
        }
        加成(参数.neighborWeight, 相似偏移, 相似下标, 相似权重)
        let related = 加成(参数.relatedWeight, 相关偏移, 相关下标, 相关权重)
        return 资料库召回(rows: rows, 评分: raw.map(\.评分), librarySeries: librarySeries,
                      scores: scores, collaborative: collaborative, related: related)
    }

    /// 按资料库推荐作品。资料库里已有的作品和它们所在的系列不推荐，每个系列最多一部；
    /// 推荐的作品是续作时换成系列入口显示，分数不变。资料库没有任何一部作品在模型里时返回空。
    func 推荐(
        资料库 feedback: [作品推荐反馈],
        类型 types: Set<作品类型>,
        包含成人内容: Bool,
        数量 limit: Int
    ) -> [作品推荐分数] {
        guard let recall = 召回(资料库: feedback) else { return [] }
        let count = 编号.count
        let scores = recall.scores
        let libraryRows = Set(recall.rows)
        let librarySeries = recall.librarySeries
        if let 精排 {
            return 精排推荐(精排, rows: recall.rows, 评分: recall.评分, libraryRows: libraryRows, librarySeries: librarySeries,
                         scores: scores, collaborative: recall.collaborative, related: recall.related, types: types,
                         包含成人内容: 包含成人内容, limit: limit)
        }
        var candidates: [(index: Int, type: 作品类型, score: Float)] = []
        candidates.reserveCapacity(8_192)
        for i in 0..<count where 可推荐[i] {
            guard let type = Self.类型(of: 编号[i]), types.contains(type),
                  包含成人内容 || !成人[i],
                  !libraryRows.contains(i),
                  !librarySeries.contains(系列[i]) else { continue }
            candidates.append((i, type, scores[i]))
        }
        candidates.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return 选出(candidates, 包含成人内容: 包含成人内容, limit: limit)
    }

    /// 按分数顺序选出：每个系列最多一部，续作换成系列入口显示。
    private func 选出(
        _ ranked: [(index: Int, type: 作品类型, score: Float)],
        包含成人内容: Bool,
        limit: Int
    ) -> [作品推荐分数] {
        var usedSeries: Set<Int32> = []
        var result: [作品推荐分数] = []
        for entry in ranked where 包含成人内容 || !成人[entry.index] {
            guard usedSeries.insert(系列[entry.index]).inserted else { continue }
            var shown = entry.index
            if let start = 入口[Int32(entry.index)].map(Int.init), 包含成人内容 || !成人[start] {
                shown = start
            }
            result.append(作品推荐分数(编号: 编号[shown], 类型: entry.type, 分数: Double(entry.score)))
            if result.count >= limit { break }
        }
        return result
    }

    /// 每部作品对这个资料库的推荐分数（协同分数加社区推荐加成），每类在可推荐作品上分别标准化，按 `编号` 的顺序。
    /// 搜索按相关程度排序时用它调整没有把握的结果。资料库没有任何一部作品在模型里时返回 nil。
    func 偏好分数(资料库 feedback: [作品推荐反馈]) -> [Float]? {
        guard let recall = 召回(资料库: feedback) else { return nil }
        let kinds = 编号.map(Self.类型(of:))
        return 按类型标准化(recall.scores, kinds: kinds)
    }

    /// 每类在可推荐作品上分别减去平均值、除以标准差。
    private func 按类型标准化(_ values: [Float], kinds: [作品类型?]) -> [Float] {
        var result = [Float](repeating: 0, count: values.count)
        for type in 作品类型.allCases {
            var sum: Double = 0, squares: Double = 0, n = 0
            for i in values.indices where 可推荐[i] && kinds[i] == type {
                let value = Double(values[i])
                sum += value; squares += value * value; n += 1
            }
            guard n > 0 else { continue }
            let mean = sum / Double(n)
            let deviation = (squares / Double(n) - mean * mean).squareRoot()
            let factor = 1 / Float(deviation > 1e-9 ? deviation : 1)
            for i in values.indices where kinds[i] == type {
                result[i] = (values[i] - Float(mean)) * factor
            }
        }
        return result
    }

    /// 作品所属的企划（同一系列的各部作品、外传与改编，见构建脚本的系列划分）：编号 → 系列号，不在模型里的不包含。
    func 企划(_ keys: [String]) -> [String: Int32] {
        var result: [String: Int32] = [:]
        for key in keys {
            if let index = 下标[key.lowercased()] { result[key] = 系列[index] }
        }
        return result
    }

    /// 和这部作品同一企划、同一类型的其他作品编号（按编号顺序）。
    func 同企划作品(_ key: String) -> [String] {
        guard let index = 下标[key.lowercased()], let type = Self.类型(of: 编号[index]) else { return [] }
        return 编号.indices.filter { $0 != index && 系列[$0] == 系列[index] && Self.类型(of: 编号[$0]) == type }.map { 编号[$0] }
    }

    /// 详情页“相关”的推荐参数：每类分别标准化后相加。
    private enum 相关推荐参数 {
        /// 和这部作品的向量内积除以候选作品向量长度的这个次方：0 偏向热门、千篇一律，1 偏向冷门、和这部作品关系弱。
        static let 向量长度指数: Float = 0.5
        static let 热度权重: Float = 0.5
        /// 这部作品的社区推荐（按最大值归一化到 0–1）。
        static let 社区权重: Float = 4
        /// 有资料库时，先按和这部作品的相似程度取前这么多部，再在里面按资料库的推荐分数（标准化后限制在 ±资料库上限）
        /// 乘资料库权重微调顺序。直接相加时用户偏好的作品会出现在每部作品的“相关”里。
        static let 资料库候选数 = 40
        static let 资料库权重: Float = 1
        static let 资料库上限: Float = 2
    }

    /// 以一部作品推荐同一类型的其他作品（详情页的“相关”）：和这部作品的向量相似度、热度与社区推荐；
    /// 有资料库时只在最像的前几部里参考资料库调整顺序，并排除资料库里已有的系列。
    /// `作品`是这部作品的候选编号，不在模型里时返回空。每个系列最多一部，不含这部作品所在的系列。
    func 相关推荐(
        作品 candidates: [String],
        资料库 feedback: [作品推荐反馈],
        类型 type: 作品类型,
        包含成人内容: Bool,
        数量 limit: Int
    ) -> [作品推荐分数] {
        guard let seed = candidates.lazy.compactMap({ 下标[$0.lowercased()] }).first else { return [] }
        let k = 维数
        let count = 编号.count
        let kinds = 编号.map(Self.类型(of:))
        let seedBase = seed * k
        var similarity = [Float](repeating: 0, count: count)
        for i in 0..<count where kinds[i] == type {
            let base = i * k
            var dot: Float = 0, norm: Float = 0
            for a in 0..<k {
                let value = 向量[base + a]
                dot += value * 向量[seedBase + a]
                norm += value * value
            }
            similarity[i] = dot / pow(norm.squareRoot() + 1e-9, 相关推荐参数.向量长度指数)
        }

        var total = [Float](repeating: 0, count: count)
        func 加上标准化(_ values: [Float], 权重 weight: Float) {
            for (i, value) in 按类型标准化(values, kinds: kinds).enumerated() { total[i] += weight * value }
        }
        加上标准化(similarity, 权重: 1)
        if let popularity = 精排?.热度 {
            加上标准化(popularity, 权重: 相关推荐参数.热度权重)
        }
        let start = Int(相关偏移[seed]), end = Int(相关偏移[seed + 1])
        if let maximum = 相关权重[start..<end].max(), maximum > 0 {
            for position in start..<end {
                total[Int(相关下标[position])] += 相关推荐参数.社区权重 * 相关权重[position] / maximum
            }
        }
        var libraryRows: Set<Int> = []
        var librarySeries: Set<Int32> = []
        let recall = 召回(资料库: feedback)
        if let recall {
            libraryRows = Set(recall.rows)
            librarySeries = recall.librarySeries
        }

        var pool: [(index: Int, type: 作品类型, score: Float)] = []
        for i in 0..<count where 可推荐[i] && kinds[i] == type {
            guard 系列[i] != 系列[seed], !libraryRows.contains(i), !librarySeries.contains(系列[i]) else { continue }
            pool.append((i, type, total[i]))
        }
        pool.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        // 有资料库时只在和这部作品最像的前几部里按偏好微调顺序，偏好不能把不像的作品拉进来
        if let recall {
            let preference = 按类型标准化(recall.scores, kinds: kinds)
            let limitValue = 相关推荐参数.资料库上限
            pool = Array(pool.prefix(相关推荐参数.资料库候选数)).map {
                ($0.index, $0.type, $0.score + 相关推荐参数.资料库权重 * min(max(preference[$0.index], -limitValue), limitValue))
            }
            pool.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        }
        return 选出(pool, 包含成人内容: 包含成人内容, limit: limit)
    }

    /// 每类分别取召回前 `精排.候选数` 部重新排序；精排的统计（平均值、名次）包含成人作品，选出结果时再按设置排除。
    private func 精排推荐(
        _ 精排: 作品推荐精排,
        rows: [Int],
        评分 ratings: [Int?],
        libraryRows: Set<Int>,
        librarySeries: Set<Int32>,
        scores: [Float],
        collaborative: [Float],
        related: [Float]?,
        types: Set<作品类型>,
        包含成人内容: Bool,
        limit: Int
    ) -> [作品推荐分数] {
        let library = 精排.概况(rows, 评分: ratings) { Self.类型(of: 编号[$0]) }
        var pools: [作品类型: [Int]] = [:]
        for i in 0..<编号.count where 可推荐[i] {
            guard let type = Self.类型(of: 编号[i]), types.contains(type),
                  !libraryRows.contains(i), !librarySeries.contains(系列[i]) else { continue }
            pools[type, default: []].append(i)
        }
        var ranked: [(index: Int, type: 作品类型, score: Float)] = []
        for type in [作品类型.anime, .manga, .lightNovel, .visualNovel] {
            guard var pool = pools[type] else { continue }
            pool.sort { scores[$0] != scores[$1] ? scores[$0] > scores[$1] : $0 < $1 }
            if let order = 精排.重新排序(候选: pool, 类型: type, 分数: scores, 协同分数: collaborative,
                                     社区加成: related, 资料库: library) {
                ranked += order.map { ($0.index, type, $0.score) }
            } else {
                ranked += pool.map { ($0, type, scores[$0]) }
            }
        }
        ranked.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return 选出(ranked, 包含成人内容: 包含成人内容, limit: limit)
    }

    /// Cholesky 分解解对称正定方程组。
    private static func 解正定方程组(_ matrix: [Double], _ vector: [Double], size n: Int) -> [Double]? {
        var L = [Double](repeating: 0, count: n * n)
        for i in 0..<n {
            for j in 0...i {
                var sum = matrix[i * n + j]
                for p in 0..<j { sum -= L[i * n + p] * L[j * n + p] }
                if i == j {
                    guard sum > 0 else { return nil }
                    L[i * n + i] = sum.squareRoot()
                } else {
                    L[i * n + j] = sum / L[j * n + j]
                }
            }
        }
        var y = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var sum = vector[i]
            for p in 0..<i { sum -= L[i * n + p] * y[p] }
            y[i] = sum / L[i * n + i]
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var sum = y[i]
            for p in (i + 1)..<n { sum -= L[p * n + i] * x[p] }
            x[i] = sum / L[i * n + i]
        }
        return x
    }

    static func 类型(of key: String) -> 作品类型? {
        switch key.first {
        case "a": .anime
        case "m": .manga
        case "n": .lightNovel
        case "v": .visualNovel
        default: nil
        }
    }
}
