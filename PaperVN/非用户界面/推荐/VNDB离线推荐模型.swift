import Foundation
import Observation
import zlib

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

@MainActor
@Observable
final class 推荐模型下载状态 {
    static let shared = 推荐模型下载状态()

    private(set) var isDownloading = false
    private(set) var progress = 0.0
    private(set) var downloadError: String?
    private(set) var hasDownloadedModel = false
    /// 已下载的模型来自旧版构建器，低秩向量未经训练，不能用于协同过滤。
    private(set) var needsUpdate = false
    private(set) var downloadedSize: Int64 = 0

    private static let 服务器文件校验值键 = "recommendationModelServerValidator"
    private var lastUpdateCheck: Date?

    var progressPercent: Int {
        min(max(Int(progress * 100), 0), 100)
    }

    private init() {
        refresh()
    }

    func refresh() {
        let manifest = VNDB离线推荐模型加载器.清单()
        hasDownloadedModel = manifest != nil
        needsUpdate = manifest.map { $0.collaborative == nil } ?? false
        downloadedSize = hasDownloadedModel
            ? VNDB离线推荐模型存储.已下载文件大小
            : 0
    }

    /// 旧版模型在非昂贵网络下静默更新；服务器文件与上次下载相同时不重复下载。
    func updateIfOutdated() async {
        refresh()
        guard needsUpdate,
              !isDownloading,
              为你推荐偏好分析设置.已启用 else {
            return
        }
        if let lastUpdateCheck,
           Date().timeIntervalSince(lastUpdateCheck) < 30 * 60 {
            return
        }
        lastUpdateCheck = Date()

        guard let validator = await 推荐模型下载器.服务器文件校验值(
            of: VNDB离线推荐模型存储.下载地址
        ),
              validator != UserDefaults.standard.string(
                forKey: Self.服务器文件校验值键
              ) else {
            return
        }
        await download(automatic: true)
    }

    func download(automatic: Bool = false) async {
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0
        if !automatic {
            downloadError = nil
        }
        defer { isDownloading = false }

        do {
            try VNDB离线推荐模型存储.创建目录()
            let stagingURL = VNDB离线推荐模型存储.文件URL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(VNDB离线推荐模型存储.文件名).\(UUID().uuidString).download"
                )
            defer { try? FileManager.default.removeItem(at: stagingURL) }

            let (temporaryURL, validator) = try await 推荐模型下载器.download(
                from: VNDB离线推荐模型存储.下载地址,
                allowsExpensiveNetworkAccess: !automatic,
                progress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.progress = max(self.progress, fraction)
                    }
                }
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try FileManager.default.moveItem(at: temporaryURL, to: stagingURL)
            guard VNDB离线推荐模型加载器.模型标识(url: stagingURL) != nil else {
                throw VNDB离线推荐模型错误.invalidGzip
            }

            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: VNDB离线推荐模型存储.文件URL.path) {
                try fileManager.removeItem(at: VNDB离线推荐模型存储.文件URL)
            }
            try fileManager.moveItem(
                at: stagingURL,
                to: VNDB离线推荐模型存储.文件URL
            )
            if let validator {
                UserDefaults.standard.set(validator, forKey: Self.服务器文件校验值键)
            }
            progress = 1
            refresh()
            await VNDB离线推荐计算中心.shared.模型文件已变更()
            VNDB探索服务.shared.刷新推荐模型标识()
            推荐后台分析中心.shared.启动需要的分析()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if !automatic {
                downloadError = error.localizedDescription
            }
            refresh()
        }
    }

    func deleteModel() throws {
        try VNDB离线推荐模型存储.删除()
        refresh()
        Task {
            await VNDB离线推荐计算中心.shared.模型文件已变更()
        }
        VNDB探索服务.shared.刷新推荐模型标识()
    }
}

private final class 推荐模型下载代理: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<(URL, String?), Error>?
    private var didFinish = false

    init(
        progress: @escaping @Sendable (Double) -> Void,
        continuation: CheckedContinuation<(URL, String?), Error>
    ) {
        self.progress = progress
        self.continuation = continuation
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(
            min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !didFinish else { return }
        didFinish = true
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            continuation?.resume(throwing: VNDB离线推荐模型错误.invalidServerResponse)
            continuation = nil
            session.finishTasksAndInvalidate()
            return
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperVNRecommendation-\(UUID().uuidString).gz")
        do {
            try FileManager.default.copyItem(at: location, to: destination)
            continuation?.resume(
                returning: (destination, 推荐模型下载器.校验值(response))
            )
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, !didFinish else { return }
        didFinish = true
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}

private enum 推荐模型下载器 {
    static func download(
        from url: URL,
        allowsExpensiveNetworkAccess: Bool,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, String?) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = 推荐模型下载代理(
                progress: progress,
                continuation: continuation
            )
            let session = URLSession(
                configuration: 会话配置(
                    allowsExpensiveNetworkAccess: allowsExpensiveNetworkAccess
                ),
                delegate: delegate,
                delegateQueue: nil
            )
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    /// 只在非昂贵网络下检查，避免用蜂窝流量做后台更新。
    static func 服务器文件校验值(of url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let session = URLSession(
            configuration: 会话配置(allowsExpensiveNetworkAccess: false)
        )
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return nil
        }
        return 校验值(response)
    }

    nonisolated static func 校验值(_ response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "ETag")
            ?? response.value(forHTTPHeaderField: "Last-Modified")
    }

    private static func 会话配置(
        allowsExpensiveNetworkAccess: Bool
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsExpensiveNetworkAccess = allowsExpensiveNetworkAccess
        configuration.allowsConstrainedNetworkAccess = allowsExpensiveNetworkAccess
        return configuration
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

    var errorDescription: String? {
        switch self {
        case .invalidGzip:
            String(localized: "下载的低秩模型文件无效。")
        case .unsupportedVersion:
            String(localized: "下载的低秩模型版本不受支持。")
        case .invalidServerResponse:
            String(localized: "服务器没有返回有效的低秩模型文件。")
        }
    }
}

nonisolated enum VNDB离线推荐模型加载器 {
    static func load(url: URL = VNDB离线推荐模型存储.文件URL) throws -> VNDB离线推荐模型? {
        let data = try gunzip(url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let model = try decoder.decode(VNDB离线推荐模型.self, from: data)
        guard model.formatVersion == VNDB离线推荐模型.当前格式版本 else {
            throw VNDB离线推荐模型错误.unsupportedVersion
        }
        return model
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

    private static func gunzip(_ url: URL) throws -> Data {
        guard let file = gzopen(url.path(percentEncoded: false), "rb") else {
            throw VNDB离线推荐模型错误.invalidGzip
        }
        defer { gzclose(file) }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 256 * 1_024)
        while true {
            let count = gzread(file, &buffer, UInt32(buffer.count))
            guard count >= 0 else {
                throw VNDB离线推荐模型错误.invalidGzip
            }
            guard count > 0 else { break }
            result.append(buffer, count: Int(count))
        }
        return result
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
    private static func 评分信号参数(
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
    let characterEvidence: [String: [VNDB候选角色证据]]
}

actor VNDB离线推荐计算中心 {
    static let shared = VNDB离线推荐计算中心()

    private var model: VNDB离线推荐模型?
    private var didAttemptLoading = false

    func 有可用模型() async -> Bool {
        await 加载模型() != nil
    }

    func 模型文件已变更() {
        model = nil
        didAttemptLoading = false
    }

    func 需要下载角色的作品ID(_ ids: Set<String>) async -> Set<String> {
        guard let model = await 加载模型() else { return ids }
        let covered = Set(model.characters.lazy.flatMap { character in
            character.visualNovels.map(\.id)
        })
        return ids.subtracting(covered)
    }

    func 准备计算(
        library: [探索用户列表项目],
        downloadedCharacters: [探索角色],
        excludedIDs: Set<String>
    ) async throws -> VNDB离线推荐计算上下文? {
        guard let model = await 加载模型() else { return nil }
        try Task.checkCancellation()

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
            globalCharacterCount: model.characterCount,
            calibrationSamples: []
        )
        try Task.checkCancellation()

        let collaborativeScores = VNDB离线低秩推荐算法.推荐分数(
            model: model,
            library: library,
            excludedIDs: excludedIDs
        )
        let characterEvidence = 角色证据按作品分组(model.characters)
        return VNDB离线推荐计算上下文(
            profile: profile,
            collaborativeScores: collaborativeScores,
            characterEvidence: characterEvidence
        )
    }

    func 排序(
        _ context: VNDB离线推荐计算上下文,
        excludedIDs: Set<String>,
        limit: Int
    ) async throws -> VNDB离线推荐计算结果? {
        guard let model = await 加载模型() else { return nil }
        try Task.checkCancellation()
        let recommendations = VNDB本地推荐算法V2.排序候选(
            model.visualNovels,
            charactersByVisualNovel: context.characterEvidence,
            profile: context.profile,
            excludedIDs: excludedIDs,
            limit: max(limit, 48),
            minimumExplorationCount: 0,
            collaborativeScores: context.collaborativeScores
        )
        let tagShelves = VNDB本地推荐算法V2.偏好标签书架(
            candidates: model.visualNovels,
            profile: context.profile,
            excludedIDs: excludedIDs,
            charactersByVisualNovel: context.characterEvidence
        )
        return VNDB离线推荐计算结果(
            recommendations: recommendations,
            tagShelves: tagShelves
        )
    }

    private func 加载模型() async -> VNDB离线推荐模型? {
        if let model { return model }
        guard !didAttemptLoading else { return nil }
        didAttemptLoading = true
        await Task.yield()
        let loaded = try? VNDB离线推荐模型加载器.load()
        model = loaded
        return loaded
    }

    private func 角色证据按作品分组(
        _ characters: [VNDB离线角色]
    ) -> [String: [VNDB候选角色证据]] {
        var result: [String: [VNDB候选角色证据]] = [:]
        for character in characters {
            let traits = character.traits.filter { $0.lie != true }
            guard !traits.isEmpty else { continue }
            for relation in character.visualNovels {
                for trait in traits {
                    result[relation.id, default: []].append(
                        VNDB候选角色证据(
                            characterID: character.id,
                            characterName: character.name,
                            traitID: trait.id,
                            traitName: trait.name,
                            groupName: trait.groupName,
                            role: relation.role ?? "appears",
                            hasImage: character.image?.url
                                .map { !$0.isEmpty } == true,
                            reliability: spoilerReliability(relation.spoiler)
                                * spoilerReliability(trait.spoiler),
                            canExplain: relation.spoiler == 0
                                && trait.spoiler == 0
                        )
                    )
                }
            }
        }
        return result
    }

    private func spoilerReliability(_ spoiler: Int?) -> Double {
        switch spoiler ?? 0 {
        case 1: 0.90
        case 2...: 0.80
        default: 1
        }
    }
}
