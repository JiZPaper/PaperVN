import Foundation
import zlib
#if os(iOS)
import os
#endif

nonisolated enum VNDB离线推荐模型存储 {
    static let 文件名 = "VNDBRecommendationModel.json.gz"
    static let 下载地址 = URL(
        string: "https://r2-papervn.jizpaper.com/Resources/VNDBRecommendationModel.json.gz"
    )!

    static var 文件URL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("PaperVNRecommendationModel", isDirectory: true)
            .appendingPathComponent(文件名)
    }

    static var 已下载文件大小: Int64 {
        guard let values = try? 文件URL.resourceValues(
            forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        ), values.isRegularFile == true else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    static func 创建目录() throws {
        var directory = 文件URL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try directory.setResourceValues(resourceValues)
    }

    static func 删除() throws {
        if FileManager.default.fileExists(atPath: 文件URL.path) {
            try FileManager.default.removeItem(at: 文件URL)
        }
    }
}

nonisolated struct VNDB离线角色: Codable, Sendable {
    let id: String
    let name: String
    let image: 探索图片?
    let visualNovels: [探索角色作品]
    let traits: [探索角色特征关联]

    var asExploreCharacter: 探索角色 {
        探索角色(
            id: id,
            name: name,
            original: nil,
            aliases: nil,
            description: nil,
            image: image,
            bloodType: nil,
            height: nil,
            weight: nil,
            bust: nil,
            waist: nil,
            hips: nil,
            cup: nil,
            age: nil,
            birthday: nil,
            sex: nil,
            gender: nil,
            visualNovels: visualNovels,
            traits: traits
        )
    }
}

nonisolated struct VNDB离线低秩向量: Codable, Hashable, Sendable {
    let visualNovelID: String
    let values: [Float]
    /// 大众评分普遍高于各自中位数的程度；旧版模型没有。
    var bias: Float?
}

/// 新版构建器写进模型清单的参数，取值来自留出用户评估。
/// 旧版模型没有这一项，它们的低秩向量未经训练，不能使用。
nonisolated struct VNDB离线协同参数: Codable, Hashable, Sendable {
    let version: Int
    let userRegularization: Double
    let interceptRegularization: Double
    /// 作品偏置在协同分里的权重：0 只看个性化项，1 是完整预测。
    let biasWeight: Double
    /// 典型用户前 0.1% 的作品对应协同分 0.72。
    let scoreScale: Double
}

nonisolated struct VNDB离线推荐模型清单: Codable, Sendable {
    let formatVersion: Int
    let generatedAt: Date
    let factorCount: Int
    var collaborative: VNDB离线协同参数?

    var 模型标识: String {
        [
            String(formatVersion),
            String(Int(generatedAt.timeIntervalSince1970)),
            String(factorCount)
        ].joined(separator: "|")
    }
}

nonisolated struct VNDB离线推荐模型: Codable, Sendable {
    static let 当前格式版本 = 2

    let formatVersion: Int
    let generatedAt: Date
    let factorCount: Int
    let visualNovels: [探索视觉小说]
    let characters: [VNDB离线角色]
    let itemFactors: [VNDB离线低秩向量]
    let tagFrequencies: [String: Int]
    let traitFrequencies: [String: Int]
    let visualNovelCount: Int
    let characterCount: Int
    var collaborative: VNDB离线协同参数?

    var 模型标识: String {
        VNDB离线推荐模型清单(
            formatVersion: formatVersion,
            generatedAt: generatedAt,
            factorCount: factorCount
        ).模型标识
    }
}

nonisolated enum VNDB离线推荐模型错误: LocalizedError {
    case invalidGzip
    case unsupportedVersion
    case invalidServerResponse
    /// 可用内存不够完成本次计算；释放后稍等即可重试。
    case insufficientMemory

    var errorDescription: String? {
        switch self {
        case .invalidGzip:
            String(localized: "下载的偏好分析模型文件无效。")
        case .unsupportedVersion:
            String(localized: "下载的偏好分析模型版本不受支持。")
        case .invalidServerResponse:
            String(localized: "服务器没有返回有效的偏好分析模型文件。")
        case .insufficientMemory:
            String(localized: "可用内存不足，暂时无法完成偏好分析。")
        }
    }
}

nonisolated enum VNDB离线推荐模型加载器 {
    /// 边解压边解析，不把解压后的近 400 MB JSON 整份放进内存。
    ///
    /// - Parameters:
    ///   - includeCharacters: 为 false 时跳过角色数据，约省一半内存；
    ///     资料库角色改从网络下载，角色证据只覆盖资料库里的作品。
    ///   - check: 每解析一批数据调用一次，抛出错误即中止加载并释放已解析的部分。
    static func load(
        url: URL = VNDB离线推荐模型存储.文件URL,
        includeCharacters: Bool = true,
        check: () throws -> Void = {}
    ) throws -> VNDB离线推荐模型? {
        _ = try loadManifest(url)
        var reader = try 流式JSON读取器(url: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var header = Data("{".utf8)
        var visualNovels: [探索视觉小说]?
        var characters: [VNDB离线角色] = []
        var itemFactors: [VNDB离线低秩向量]?
        try reader.expect(0x7B)
        while true {
            reader.skipWhitespace()
            guard let next = try reader.peek() else {
                throw VNDB离线推荐模型错误.invalidGzip
            }
            if next == 0x7D { break }
            if next == 0x2C {
                _ = try reader.next()
                continue
            }
            var keyData = Data()
            try reader.readValue(into: &keyData)
            let key = String(decoding: keyData.dropFirst().dropLast(), as: UTF8.self)
            reader.skipWhitespace()
            try reader.expect(0x3A)
            reader.skipWhitespace()
            switch key {
            case "visualNovels":
                visualNovels = try reader.readArray(
                    decoding: 作品批.self, decoder: decoder, check: check
                )
            case "characters" where includeCharacters:
                characters = try reader.readArray(
                    decoding: 角色批.self, decoder: decoder, check: check
                )
            case "characters":
                try reader.skipValue()
            case "itemFactors":
                itemFactors = try reader.readArray(
                    decoding: 低秩向量批.self, decoder: decoder, check: check
                )
            default:
                if header.count > 1 { header.append(0x2C) }
                header.append(keyData)
                header.append(0x3A)
                try reader.readValue(into: &header)
            }
            try check()
        }
        header.append(0x7D)

        guard let visualNovels, let itemFactors else {
            throw VNDB离线推荐模型错误.invalidGzip
        }
        let manifest = try decoder.decode(VNDB离线推荐模型头.self, from: header)
        guard manifest.formatVersion == VNDB离线推荐模型.当前格式版本 else {
            throw VNDB离线推荐模型错误.unsupportedVersion
        }
        return VNDB离线推荐模型(
            formatVersion: manifest.formatVersion,
            generatedAt: manifest.generatedAt,
            factorCount: manifest.factorCount,
            visualNovels: visualNovels,
            characters: characters,
            itemFactors: itemFactors,
            tagFrequencies: manifest.tagFrequencies,
            traitFrequencies: manifest.traitFrequencies,
            visualNovelCount: manifest.visualNovelCount,
            characterCount: manifest.characterCount,
            collaborative: manifest.collaborative
        )
    }

    static func 模型标识(url: URL = VNDB离线推荐模型存储.文件URL) -> String? {
        清单(url: url)?.模型标识
    }

    static func 清单(url: URL = VNDB离线推荐模型存储.文件URL) -> VNDB离线推荐模型清单? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? loadManifest(url)
    }

    private static func loadManifest(_ url: URL) throws -> VNDB离线推荐模型清单 {
        guard let file = gzopen(url.path(percentEncoded: false), "rb") else {
            throw VNDB离线推荐模型错误.invalidGzip
        }
        defer { gzclose(file) }

        let marker = Data(",\"visualNovels\":[".utf8)
        var prefix = Data()
        var buffer = [UInt8](repeating: 0, count: 4 * 1_024)
        while prefix.count < 64 * 1_024 {
            let count = gzread(file, &buffer, UInt32(buffer.count))
            guard count >= 0 else {
                throw VNDB离线推荐模型错误.invalidGzip
            }
            guard count > 0 else { break }
            prefix.append(buffer, count: Int(count))
            if let range = prefix.range(of: marker) {
                var manifestData = Data(prefix[..<range.lowerBound])
                manifestData.append(0x7D)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let manifest = try decoder.decode(
                    VNDB离线推荐模型清单.self,
                    from: manifestData
                )
                guard manifest.formatVersion
                        == VNDB离线推荐模型.当前格式版本 else {
                    throw VNDB离线推荐模型错误.unsupportedVersion
                }
                return manifest
            }
        }
        throw VNDB离线推荐模型错误.invalidGzip
    }

}

/// 数组元素按批解码。包一层合成的 Decodable，App 默认主 actor 隔离下也能在后台解码。
private nonisolated protocol 模型数据批: Decodable {
    associatedtype Element
    var items: [Element] { get }
}

private nonisolated struct 作品批: 模型数据批 {
    let items: [探索视觉小说]
}

private nonisolated struct 角色批: 模型数据批 {
    let items: [VNDB离线角色]
}

private nonisolated struct 低秩向量批: 模型数据批 {
    let items: [VNDB离线低秩向量]
}

/// 模型里除三个大数组以外的字段。
private nonisolated struct VNDB离线推荐模型头: Decodable {
    let formatVersion: Int
    let generatedAt: Date
    let factorCount: Int
    let tagFrequencies: [String: Int]
    let traitFrequencies: [String: Int]
    let visualNovelCount: Int
    let characterCount: Int
    let collaborative: VNDB离线协同参数?
}

/// 只认识模型文件用到的 JSON 结构：按字节扫描值的边界，数组元素攒成小批交给 JSONDecoder。
private nonisolated struct 流式JSON读取器: ~Copyable {
    private let file: gzFile
    private var buffer = [UInt8](repeating: 0, count: 256 * 1_024)
    private var position = 0
    private var available = 0

    init(url: URL) throws {
        guard let file = gzopen(url.path(percentEncoded: false), "rb") else {
            throw VNDB离线推荐模型错误.invalidGzip
        }
        self.file = file
    }

    deinit {
        gzclose(file)
    }

    mutating func peek() throws -> UInt8? {
        if position == available {
            let file = file
            let count = buffer.withUnsafeMutableBytes { bytes in
                gzread(file, bytes.baseAddress, UInt32(bytes.count))
            }
            guard count >= 0 else { throw VNDB离线推荐模型错误.invalidGzip }
            position = 0
            available = Int(count)
            guard count > 0 else { return nil }
        }
        return buffer[position]
    }

    mutating func next() throws -> UInt8 {
        guard let byte = try peek() else {
            throw VNDB离线推荐模型错误.invalidGzip
        }
        position += 1
        return byte
    }

    mutating func skipWhitespace() {
        while let byte = try? peek(),
              byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 {
            position += 1
        }
    }

    mutating func expect(_ expected: UInt8) throws {
        skipWhitespace()
        guard try next() == expected else {
            throw VNDB离线推荐模型错误.invalidGzip
        }
    }

    mutating func skipValue() throws {
        var discarded: Data?
        try scanValue(into: &discarded)
    }

    mutating func readValue(into output: inout Data) throws {
        var target: Data? = output
        output = Data()
        try scanValue(into: &target)
        output = target ?? Data()
    }

    /// 读一个 JSON 数组；每 256 个元素解码一次，只在内存里留一小段原文。
    mutating func readArray<Batch: 模型数据批>(
        decoding _: Batch.Type,
        decoder: JSONDecoder,
        check: () throws -> Void
    ) throws -> [Batch.Element] {
        let prefix = Data(#"{"items":["#.utf8)
        try expect(0x5B)
        var result: [Batch.Element] = []
        var batch = prefix
        var batchCount = 0
        func flush() throws {
            guard batchCount > 0 else { return }
            batch.append(contentsOf: [0x5D, 0x7D])
            result.append(contentsOf: try decoder.decode(Batch.self, from: batch).items)
            batch = prefix
            batchCount = 0
            try check()
        }
        while true {
            skipWhitespace()
            switch try peek() {
            case nil:
                throw VNDB离线推荐模型错误.invalidGzip
            case 0x5D:
                position += 1
                try flush()
                return result
            case 0x2C:
                position += 1
            default:
                if batchCount > 0 { batch.append(0x2C) }
                var target: Data? = batch
                batch = Data()
                try scanValue(into: &target)
                batch = target ?? Data()
                batchCount += 1
                if batchCount == 256 { try flush() }
            }
        }
    }

    /// 扫过一个完整的值；output 为 nil 时只跳过。
    private mutating func scanValue(into output: inout Data?) throws {
        skipWhitespace()
        var depth = 0
        var inString = false
        var escaped = false
        repeat {
            let byte = try next()
            output?.append(byte)
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }
            switch byte {
            case 0x22:
                inString = true
            case 0x7B, 0x5B:
                depth += 1
            case 0x7D, 0x5D:
                depth -= 1
            default:
                // 数字、true、false、null：读到分隔符为止。
                if depth == 0 {
                    while let next = try peek(),
                          next != 0x2C, next != 0x7D, next != 0x5D,
                          next != 0x20, next != 0x0A, next != 0x0D, next != 0x09 {
                        output?.append(next)
                        position += 1
                    }
                }
            }
        } while inString || depth > 0
    }
}

nonisolated enum VNDB离线低秩推荐算法 {
    /// 把资料库折入低秩空间，返回每部作品的协同分（0...1）。
    ///
    /// 与 Tools/构建VNDB离线推荐模型.py 的留出评估完全一致：评分先按用户自己的
    /// 中位数和尺度转成信号，减去作品偏置后做岭回归；协同分是个性化项 p·q
    /// 加上按留出召回率选出的少量作品偏置。没有票数门槛：证据少的作品向量
    /// 本身就短，分数会自然偏低。
    static func 推荐分数(
        model: VNDB离线推荐模型,
        library: [探索用户列表项目],
        excludedIDs: Set<String>
    ) -> [String: Double] {
        guard let parameters = model.collaborative,
              parameters.scoreScale > 0,
              model.factorCount > 0 else { return [:] }
        let dimension = model.factorCount
        let size = dimension + 1
        let factorByID = Dictionary(
            model.itemFactors.map { ($0.visualNovelID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var matrix = [Double](repeating: 0, count: size * size)
        var vector = [Double](repeating: 0, count: size)
        var observationCount = 0
        for observation in 协同观测(library) {
            guard let item = factorByID[observation.id],
                  item.values.count == dimension else { continue }
            let target = observation.signal
                - (observation.isRating ? Double(item.bias ?? 0) : 0)
            var features = item.values.map(Double.init)
            features.append(1)
            for row in 0..<size {
                let weighted = features[row] * observation.weight
                vector[row] += target * weighted
                for column in 0...row {
                    matrix[row * size + column] += weighted * features[column]
                }
            }
            observationCount += 1
        }
        guard observationCount > 0 else { return [:] }
        for index in 0..<dimension {
            matrix[index * size + index] += parameters.userRegularization
        }
        matrix[dimension * size + dimension] += parameters.interceptRegularization
        guard let solution = 解正定方程组(matrix, vector, size: size) else {
            return [:]
        }

        var result: [String: Double] = [:]
        for item in model.itemFactors
        where !excludedIDs.contains(item.visualNovelID)
            && item.values.count == dimension {
            var interaction = 0.0
            for index in 0..<dimension {
                interaction += solution[index] * Double(item.values[index])
            }
            let raw = interaction + parameters.biasWeight * Double(item.bias ?? 0)
            let score = min(1, raw / parameters.scoreScale)
            if score > 0 {
                result[item.visualNovelID] = score
            }
        }
        return result
    }

    private static func 协同观测(
        _ library: [探索用户列表项目]
    ) -> [(id: String, signal: Double, weight: Double, isRating: Bool)] {
        let rating = 评分信号参数(library.compactMap(\.vote))
        return library.compactMap { item in
            if let vote = item.vote {
                let signal = tanh((Double(vote) - rating.center) / rating.scale)
                    * rating.confidence
                return (item.id, signal, 1, true)
            }
            let signal = VNDB本地推荐算法V2.状态信号(item)
            guard signal != 0 else { return nil }
            return (item.id, signal, 0.5, false)
        }
    }

    /// 与构建器的 rating_signal_parameters 相同，训练目标和折入目标才在同一尺度上。
    static func 评分信号参数(
        _ votes: [Int]
    ) -> (center: Double, scale: Double, confidence: Double) {
        let ordered = votes.sorted().map(Double.init)
        guard ordered.count >= 5 else { return (70, 15, 0.75) }
        let median = 有序中位数(ordered)
        let deviation = 有序中位数(ordered.map { abs($0 - median) }.sorted())
        return (median, max(10, 1.4826 * deviation), 1)
    }

    private static func 有序中位数(_ values: [Double]) -> Double {
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }

    /// Cholesky 分解求解对称正定方程组，只读取下三角。
    private static func 解正定方程组(
        _ matrix: [Double],
        _ vector: [Double],
        size: Int
    ) -> [Double]? {
        var lower = [Double](repeating: 0, count: size * size)
        for column in 0..<size {
            var diagonal = matrix[column * size + column]
            for k in 0..<column {
                diagonal -= lower[column * size + k] * lower[column * size + k]
            }
            guard diagonal > 1e-12 else { return nil }
            let root = diagonal.squareRoot()
            lower[column * size + column] = root
            for row in (column + 1)..<size {
                var value = matrix[row * size + column]
                for k in 0..<column {
                    value -= lower[row * size + k] * lower[column * size + k]
                }
                lower[row * size + column] = value / root
            }
        }
        var forward = [Double](repeating: 0, count: size)
        for row in 0..<size {
            var value = vector[row]
            for k in 0..<row {
                value -= lower[row * size + k] * forward[k]
            }
            forward[row] = value / lower[row * size + row]
        }
        var solution = [Double](repeating: 0, count: size)
        for row in stride(from: size - 1, through: 0, by: -1) {
            var value = forward[row]
            for k in (row + 1)..<size {
                value -= lower[k * size + row] * solution[k]
            }
            solution[row] = value / lower[row * size + row]
        }
        return solution
    }
}

nonisolated struct VNDB离线推荐计算结果: Sendable {
    let recommendations: [探索推荐]
    let tagShelves: [VNDB偏好标签书架]
}

nonisolated struct VNDB离线推荐计算上下文: Sendable {
    let profile: VNDB本地推荐画像V2
    let collaborativeScores: [String: Double]
    let characterEvidence: VNDB角色证据索引
}

/// 按作品取角色证据。证据在用到时才生成：全部角色展开后有近 300 万条，
/// 一次性建好要占几百 MB，是偏好分析闪退的主要原因之一。
nonisolated struct VNDB角色证据索引: Sendable {
    private let characters: [VNDB离线角色]
    private let characterIndicesByVisualNovel: [String: [Int32]]

    init(_ characters: [VNDB离线角色]) {
        var indices: [String: [Int32]] = [:]
        for (index, character) in characters.enumerated()
        where character.traits.contains(where: { $0.lie != true }) {
            for visualNovelID in Set(character.visualNovels.map(\.id)) {
                indices[visualNovelID, default: []].append(Int32(index))
            }
        }
        self.characters = characters
        characterIndicesByVisualNovel = indices
    }

    var 作品数: Int { characterIndicesByVisualNovel.count }

    func 证据(_ visualNovelID: String) -> [VNDB候选角色证据] {
        guard let indices = characterIndicesByVisualNovel[visualNovelID] else {
            return []
        }
        var result: [VNDB候选角色证据] = []
        for index in indices {
            let character = characters[Int(index)]
            let traits = character.traits.filter { $0.lie != true }
            for relation in character.visualNovels where relation.id == visualNovelID {
                for trait in traits {
                    result.append(
                        VNDB候选角色证据(
                            characterID: character.id,
                            characterName: character.name,
                            traitID: trait.id,
                            traitName: trait.name,
                            groupName: trait.groupName,
                            role: relation.role ?? "appears",
                            reliability: Self.spoilerReliability(relation.spoiler)
                                * Self.spoilerReliability(trait.spoiler),
                            canExplain: relation.spoiler == 0
                                && trait.spoiler == 0
                        )
                    )
                }
            }
        }
        return result
    }

    private static func spoilerReliability(_ spoiler: Int?) -> Double {
        switch spoiler ?? 0 {
        case 1: 0.90
        case 2...: 0.80
        default: 1
        }
    }
}

/// 一次推荐计算的完整流程，不依赖 App 状态；Tools/推荐离线评估 使用同一套代码。
nonisolated enum VNDB离线推荐计算 {
    static func 准备(
        model: VNDB离线推荐模型,
        library: [探索用户列表项目],
        downloadedCharacters: [探索角色] = [],
        excludedIDs: Set<String>,
        characterEvidence: VNDB角色证据索引
    ) -> VNDB离线推荐计算上下文 {
        let libraryIDs = Set(library.map(\.id))
        var libraryCharacters = model.characters.compactMap { character in
            character.visualNovels.contains { libraryIDs.contains($0.id) }
                ? character.asExploreCharacter
                : nil
        }
        libraryCharacters.append(contentsOf: downloadedCharacters.filter { character in
            (character.visualNovels ?? []).contains { libraryIDs.contains($0.id) }
        })

        let profile = VNDB本地推荐算法V2.建立画像(
            library: library,
            characters: libraryCharacters,
            globalTagFrequencies: model.tagFrequencies,
            globalTraitFrequencies: model.traitFrequencies,
            globalVisualNovelCount: model.visualNovelCount,
            globalCharacterCount: model.characterCount
        )
        let collaborativeScores = VNDB离线低秩推荐算法.推荐分数(
            model: model,
            library: library,
            excludedIDs: excludedIDs
        )
        return VNDB离线推荐计算上下文(
            profile: profile,
            collaborativeScores: collaborativeScores,
            characterEvidence: characterEvidence
        )
    }

    static func 排序(
        model: VNDB离线推荐模型,
        context: VNDB离线推荐计算上下文,
        excludedIDs: Set<String>,
        limit: Int
    ) -> VNDB离线推荐计算结果 {
        let recommendations = VNDB本地推荐算法V2.排序候选(
            model.visualNovels,
            characterEvidence: context.characterEvidence.证据,
            profile: context.profile,
            excludedIDs: excludedIDs,
            limit: max(limit, 48),
            minimumExplorationCount: 0,
            collaborativeScores: context.collaborativeScores
        )
        let tagShelves = VNDB本地推荐算法V2.偏好标签书架(
            candidates: model.visualNovels,
            profile: context.profile,
            excludedIDs: excludedIDs
        )
        return VNDB离线推荐计算结果(
            recommendations: recommendations,
            tagShelves: tagShelves
        )
    }
}

/// 模型解析时峰值约 600 MB（不含角色约 250 MB），旧设备上很容易被系统因内存不足终止。这里的做法是：
/// 先看可用内存再决定加载方式，加载中内存不够就中止并抛出可重试的错误；
/// 上次计算中途被系统终止过，就改用不含角色数据的省内存方式。
actor VNDB离线推荐计算中心 {
    static let shared = VNDB离线推荐计算中心()

    /// 完整模型解析时的峰值，留出余量。
    private static let 完整加载所需内存: UInt64 = 900 * 1_024 * 1_024
    /// 跳过角色数据时的峰值，留出余量。
    private static let 省内存加载所需内存: UInt64 = 450 * 1_024 * 1_024
    /// 加载和计算过程中可用内存低于这个值就中止，宁可稍后重试也不要被系统终止。
    private static let 最低剩余内存: UInt64 = 150 * 1_024 * 1_024
    private static let 计算进行中键 = "VNDB离线推荐计算进行中"
    private static let 省内存模式键 = "VNDB离线推荐使用省内存模式"

    private var model: VNDB离线推荐模型?

    init() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.计算进行中键) {
            // 上次计算没有正常结束，多半是被系统因内存不足终止。
            defaults.set(true, forKey: Self.省内存模式键)
            defaults.set(false, forKey: Self.计算进行中键)
        }
    }

    /// 只读取文件开头的清单，不加载整个模型。
    func 有可用模型() -> Bool {
        VNDB离线推荐模型加载器.清单() != nil
    }

    func 模型文件已变更() {
        model = nil
        UserDefaults.standard.set(false, forKey: Self.省内存模式键)
    }

    /// 计算结束（成功或失败）后调用，归还模型占用的内存。
    func 结束计算() {
        model = nil
        UserDefaults.standard.set(false, forKey: Self.计算进行中键)
    }

    func 需要下载角色的作品ID(_ ids: Set<String>) async throws -> Set<String> {
        let model = try await 加载模型()
        let covered = Set(model.characters.lazy.flatMap { character in
            character.visualNovels.map(\.id)
        })
        return ids.subtracting(covered)
    }

    func 准备计算(
        library: [探索用户列表项目],
        downloadedCharacters: [探索角色],
        excludedIDs: Set<String>
    ) async throws -> VNDB离线推荐计算上下文 {
        let model = try await 加载模型()
        try Self.检查可用内存()
        let context = VNDB离线推荐计算.准备(
            model: model,
            library: library,
            downloadedCharacters: downloadedCharacters,
            excludedIDs: excludedIDs,
            characterEvidence: VNDB角色证据索引(model.characters)
        )
        try Self.检查可用内存()
        return context
    }

    func 排序(
        _ context: VNDB离线推荐计算上下文,
        excludedIDs: Set<String>,
        limit: Int
    ) async throws -> VNDB离线推荐计算结果 {
        let model = try await 加载模型()
        try Self.检查可用内存()
        return VNDB离线推荐计算.排序(
            model: model,
            context: context,
            excludedIDs: excludedIDs,
            limit: limit
        )
    }

    private func 加载模型() async throws -> VNDB离线推荐模型 {
        if let model { return model }
        let defaults = UserDefaults.standard
        var includeCharacters = !defaults.bool(forKey: Self.省内存模式键)
        if includeCharacters {
            // 内存一时不够就等一会儿（最多约半分钟），仍不够再改用省内存方式。
            var waited = 0
            while let available = Self.可用内存(),
                  available < Self.完整加载所需内存 {
                guard waited < 6 else {
                    includeCharacters = false
                    break
                }
                try await Task.sleep(for: .seconds(5))
                waited += 1
            }
        }
        if !includeCharacters,
           let available = Self.可用内存(),
           available < Self.省内存加载所需内存 {
            throw VNDB离线推荐模型错误.insufficientMemory
        }
        try Task.checkCancellation()

        defaults.set(true, forKey: Self.计算进行中键)
        let loaded = try VNDB离线推荐模型加载器.load(
            includeCharacters: includeCharacters,
            check: {
                try Task.checkCancellation()
                try Self.检查可用内存()
            }
        )
        guard let loaded else { throw VNDB离线推荐模型错误.invalidGzip }
        model = loaded
        return loaded
    }

    private static func 检查可用内存() throws {
        if let available = 可用内存(), available < 最低剩余内存 {
            throw VNDB离线推荐模型错误.insufficientMemory
        }
    }

    /// 只有 iOS 能查询；离线评估工具在 macOS 上运行，不做限制。
    private static func 可用内存() -> UInt64? {
        #if os(iOS)
        UInt64(os_proc_available_memory())
        #else
        nil
        #endif
    }
}
