import Foundation
import ZIPFoundation

nonisolated enum VNDB简介翻译模式: String, CaseIterable, Identifiable, Sendable {
    case automaticOnDevice
    case openSourceFetch
    case openSourceOffline

    static let 设置键 = "preferredDescriptionTranslationMode"

    var id: Self { self }

    var title: String {
        switch self {
        case .automaticOnDevice:
            String(localized: "设备端模型")
        case .openSourceFetch:
            String(localized: "开源项目（获取）")
        case .openSourceOffline:
            String(localized: "开源项目（离线）")
        }
    }

    /// 设备端模型依赖 iOS 18 的端侧翻译，更早系统不提供。
    static var 可用模式: [Self] {
        if #available(iOS 18.0, *) {
            return allCases
        }
        return allCases.filter { $0 != .automaticOnDevice }
    }

    static var current: Self {
        guard let value = UserDefaults.standard.string(forKey: 设置键),
              let mode = Self(rawValue: value),
              可用模式.contains(mode) else {
            return UserDefaults.standard.bool(
                forKey: VNDB简介人工翻译.完整下载设置键
            ) ? .openSourceOffline : .openSourceFetch
        }
        return mode
    }
}

nonisolated enum VNDB简介条目类型: String, Codable, Sendable {
    case visualNovel = "visual_novel"
    case character

    var directoryName: String {
        switch self {
        case .visualNovel: "visual-novels"
        case .character: "characters"
        }
    }
}

nonisolated private struct VNDB简介翻译文件: Decodable, Sendable {
    let schemaVersion: Int
    let id: String
    let type: VNDB简介条目类型
    let language: String
    let translation: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case id
        case type
        case language
        case translation
    }
}

nonisolated enum VNDB简介翻译数据源: String, CaseIterable, Sendable {
    case github
    case paperVN

    private static let repositoryOwner = "JiZPaper"
    private static let repositoryName = "VNDB-Description-Translations"
    private static let branchName = "main"
    private static let mirrorBaseURL = "https://papervn.jizpaper.com/translations"

    var archiveURL: URL? {
        switch self {
        case .github:
            URL(string: "https://codeload.github.com/\(Self.repositoryOwner)/\(Self.repositoryName)/zip/refs/heads/\(Self.branchName)")
        case .paperVN:
            URL(string: "\(Self.mirrorBaseURL)/vndb-descriptions.zip")
        }
    }

    func entryURL(relativePath: String) -> URL? {
        switch self {
        case .github:
            URL(string: "https://raw.githubusercontent.com/\(Self.repositoryOwner)/\(Self.repositoryName)/\(Self.branchName)/\(relativePath)")
        case .paperVN:
            URL(string: "\(Self.mirrorBaseURL)/vndb-descriptions/\(relativePath)")
        }
    }

    var revisionURL: URL? {
        switch self {
        case .github:
            URL(string: "https://api.github.com/repos/\(Self.repositoryOwner)/\(Self.repositoryName)/branches/\(Self.branchName)")
        case .paperVN:
            URL(string: "\(Self.mirrorBaseURL)/vndb-descriptions.json")
        }
    }

    var 预估压缩包大小字节数: Int64 {
        switch self {
        case .github: 94_709_226
        case .paperVN: 18_382_602
        }
    }

    static func 优先顺序(
        prefersPaperVN: Bool = 应优先使用PaperVN服务器
    ) -> [Self] {
        prefersPaperVN ? [.paperVN, .github] : [.github, .paperVN]
    }

    static var 应优先使用PaperVN服务器: Bool {
        PaperVNConnect自动策略.当前设备具有中国大陆特征
            || PaperVNConnect自动策略.自动转发已启用
    }
}

nonisolated enum VNDB简介译文缓存结果: Sendable, Equatable {
    case notLoaded
    case missing
    case translation(String)

    var translation: String? {
        guard case .translation(let value) = self else { return nil }
        return value
    }

    var isResolved: Bool {
        self != .notLoaded
    }
}

nonisolated private final class VNDB简介译文缓存: @unchecked Sendable {
    static let shared = VNDB简介译文缓存()

    private let lock = NSLock()
    private var values: [String: VNDB简介译文缓存结果] = [:]
    private let diskRoot: URL = {
        FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!
            .appending(path: "PaperVN", directoryHint: .isDirectory)
            .appending(
                path: "VNDBDescriptionTranslations",
                directoryHint: .isDirectory
            )
    }()

    func result(
        for key: String,
        allowDisk: Bool
    ) -> VNDB简介译文缓存结果 {
        lock.lock()
        if let value = values[key] {
            lock.unlock()
            return value
        }
        lock.unlock()

        let fileURL = fileURL(for: key)
        guard allowDisk,
              let data = try? Data(contentsOf: fileURL) else {
            return .notLoaded
        }

        let result: VNDB简介译文缓存结果
        if data.isEmpty {
            result = .missing
        } else if let value = String(data: data, encoding: .utf8),
                  !value.isEmpty {
            result = .translation(value)
        } else {
            return .notLoaded
        }

        let modifiedAt = (try? fileURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ))?.contentModificationDate ?? .distantPast
        let lifetime: TimeInterval = result == .missing
            ? 12 * 60 * 60
            : 7 * 24 * 60 * 60
        guard Date().timeIntervalSince(modifiedAt) < lifetime else {
            return .notLoaded
        }

        lock.lock()
        values[key] = result
        lock.unlock()
        return result
    }

    func insert(
        _ result: VNDB简介译文缓存结果,
        for key: String,
        persist: Bool
    ) {
        lock.lock()
        values[key] = result
        lock.unlock()

        guard persist else { return }
        let fileURL = fileURL(for: key)
        try? FileManager.default.createDirectory(
            at: diskRoot,
            withIntermediateDirectories: true
        )
        let data: Data
        switch result {
        case .translation(let value):
            data = Data(value.utf8)
        case .missing:
            data = Data()
        case .notLoaded:
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    func removeAllFromMemory() {
        lock.lock()
        values.removeAll()
        lock.unlock()
    }

    func removeAll() {
        removeAllFromMemory()
        try? FileManager.default.removeItem(at: diskRoot)
    }

    var diskSizeInBytes: Int64 {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: diskRoot,
            includingPropertiesForKeys: Array(resourceKeys)
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? 0
            )
        }
        return total
    }

    private func fileURL(for key: String) -> URL {
        let fileName = Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return diskRoot.appending(
            path: "\(fileName).txt",
            directoryHint: .notDirectory
        )
    }
}

nonisolated struct VNDB简介翻译版本: Sendable, Equatable {
    let revision: String
    let committedAt: Date?
    let archiveBytes: Int64

    var archiveSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: archiveBytes)
    }
}

nonisolated private struct VNDB简介翻译镜像清单: Decodable, Sendable {
    let revision: String
    let committedAt: Date?
    let archiveBytes: Int64
    let githubArchiveBytes: Int64?
}

nonisolated private struct VNDB简介翻译GitHub分支: Decodable, Sendable {
    struct Commit: Decodable, Sendable {
        struct Details: Decodable, Sendable {
            struct Signature: Decodable, Sendable {
                let date: Date?
            }

            let committer: Signature?
        }

        let sha: String
        let commit: Details?
    }

    let commit: Commit
}

private actor VNDB简介翻译镜像清单缓存 {
    static let shared = VNDB简介翻译镜像清单缓存()

    private var cached: (manifest: VNDB简介翻译镜像清单?, fetchedAt: Date)?
    private var inFlight: Task<VNDB简介翻译镜像清单?, Never>?

    func manifest(maxAge: TimeInterval) async -> VNDB简介翻译镜像清单? {
        if let cached {
            let lifetime = cached.manifest == nil ? min(maxAge, 60) : maxAge
            if Date().timeIntervalSince(cached.fetchedAt) < lifetime {
                return cached.manifest
            }
        }
        if let inFlight {
            return await inFlight.value
        }

        let task = Task { await VNDB简介人工翻译.获取镜像清单() }
        inFlight = task
        let manifest = await task.value
        inFlight = nil
        cached = (manifest, Date())
        return manifest
    }
}

nonisolated enum VNDB简介翻译下载阶段: Int, Sendable {
    case connecting
    case downloading
    case extracting

    var localizedTitle: String {
        localizedTitle(source: .github)
    }

    func localizedTitle(source: VNDB简介翻译数据源) -> String {
        switch self {
        case .connecting:
            source == .github
                ? String(localized: "正在连接GitHub…")
                : String(localized: "正在连接PaperVN服务器…")
        case .downloading:
            String(localized: "正在下载…")
        case .extracting:
            String(localized: "正在解压…")
        }
    }
}

nonisolated private final class VNDB简介翻译下载代理:
    NSObject,
    URLSessionDownloadDelegate,
    @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void
    private let responseHandler: @Sendable () -> Void
    private let delegateQueue: OperationQueue
    private var continuation: CheckedContinuation<URL, any Error>?
    private var downloadedFileURL: URL?
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var hasReceivedResponse = false
    private var lastReportedFraction = -1.0

    init(
        progressHandler: @escaping @Sendable (Double) -> Void,
        responseHandler: @escaping @Sendable () -> Void
    ) {
        self.progressHandler = progressHandler
        self.responseHandler = responseHandler
        delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        super.init()
    }

    func download(for request: URLRequest) async throws -> URL {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                configuration.timeoutIntervalForRequest = 180
                configuration.timeoutIntervalForResource = 600
                configuration.waitsForConnectivity = true
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: delegateQueue
                )
                self.session = session
                let task = session.downloadTask(with: request)
                downloadTask = task
                task.resume()
            }
        } onCancel: {
            self.downloadTask?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if !hasReceivedResponse {
            hasReceivedResponse = true
            responseHandler()
        }
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(
            Double(totalBytesWritten) / Double(totalBytesExpectedToWrite),
            1
        )
        guard fraction >= 1 || fraction - lastReportedFraction >= 0.005 else {
            return
        }
        lastReportedFraction = fraction
        progressHandler(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let response = downloadTask.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return
        }

        do {
            let destinationURL = FileManager.default.temporaryDirectory.appending(
                path: "\(UUID().uuidString).zip",
                directoryHint: .notDirectory
            )
            try FileManager.default.moveItem(at: location, to: destinationURL)
            downloadedFileURL = destinationURL
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        defer {
            continuation = nil
            downloadTask = nil
            self.session?.finishTasksAndInvalidate()
            self.session = nil
        }

        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
            return
        }
        guard let response = task.response as? HTTPURLResponse else {
            continuation.resume(
                throwing: VNDB简介翻译下载错误.invalidServerResponse()
            )
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            continuation.resume(
                throwing: VNDB简介翻译下载错误.httpStatus(response.statusCode)
            )
            return
        }
        guard let downloadedFileURL else {
            continuation.resume(
                throwing: VNDB简介翻译下载错误.invalidServerResponse()
            )
            return
        }
        continuation.resume(returning: downloadedFileURL)
    }
}

nonisolated enum VNDB简介人工翻译 {
    static let 完整下载设置键 = "downloadCompleteDescriptionTranslations"
    static let resourceDirectoryName = "VNDB-Description-Translations"
    static var 完整翻译文件大小字节数: Int64 {
        (VNDB简介翻译数据源.优先顺序().first ?? .github).预估压缩包大小字节数
    }

    static var 完整翻译文件大小文本: String {
        ByteCountFormatter.string(
            fromByteCount: 完整翻译文件大小字节数,
            countStyle: .file
        )
    }

    private static let repositoryName = "VNDB-Description-Translations"
    private static let branchName = "main"
    private static let supportedLanguageDirectories: Set<String> = [
        "zh-Hans", "zh-Hant", "ja", "ko"
    ]

    static var 已有完整下载: Bool {
        FileManager.default.fileExists(atPath: 完整下载标记URL.path)
    }

    static var 完整下载日期: Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: 完整下载标记URL.path
        ) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    static var 已下载文件大小字节数: Int64 {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: 完整下载根目录.path) else {
            return 0
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: 完整下载根目录,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                continue
            }
            total += Int64(
                values.totalFileAllocatedSize
                    ?? values.fileAllocatedSize
                    ?? 0
            )
        }
        return total
    }

    static func 删除完整翻译文件() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: 完整下载根目录.path) {
            try fileManager.removeItem(at: 完整下载根目录)
        }
        UserDefaults.standard.removeObject(forKey: 完整下载设置键)
        VNDB简介译文缓存.shared.removeAllFromMemory()
    }

    static var 译文缓存大小字节数: Int64 {
        VNDB简介译文缓存.shared.diskSizeInBytes
    }

    static func 清除译文缓存() {
        VNDB简介译文缓存.shared.removeAll()
    }

    static func 译文(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言,
        mode: VNDB简介翻译模式? = nil
    ) async -> String? {
        await 译文结果(
            for: id,
            type: type,
            language: language,
            mode: mode
        ).translation
    }

    static func 项目译文状态(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言
    ) async -> VNDB简介译文缓存结果 {
        let currentMode = VNDB简介翻译模式.current
        let mode: VNDB简介翻译模式
        if currentMode != .automaticOnDevice {
            mode = currentMode
        } else {
            mode = 已有完整下载 ? .openSourceOffline : .openSourceFetch
        }
        return await 译文结果(
            for: id,
            type: type,
            language: language,
            mode: mode
        )
    }

    static func 译文结果(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言,
        mode: VNDB简介翻译模式? = nil
    ) async -> VNDB简介译文缓存结果 {
        let resolvedMode = mode ?? VNDB简介翻译模式.current
        let cacheKey = translationCacheKey(
            for: id,
            type: type,
            language: language,
            mode: resolvedMode
        )
        let cachedResult = VNDB简介译文缓存.shared.result(
            for: cacheKey,
            allowDisk: resolvedMode == .openSourceFetch
        )
        if cachedResult.isResolved, resolvedMode != .openSourceFetch {
            return cachedResult
        }

        let result: VNDB简介译文缓存结果
        switch resolvedMode {
        case .automaticOnDevice:
            return .missing
        case .openSourceOffline:
            guard 已有完整下载 else { return .missing }
            let translationsRoot = 完整下载根目录
            let translation = await Task.detached(priority: .userInitiated) {
                读取本地译文(
                    for: id,
                    type: type,
                    language: language,
                    translationsRoot: translationsRoot
                )
            }.value
            result = translation.map(VNDB简介译文缓存结果.translation)
                ?? .missing
        case .openSourceFetch:
            result = await 远程译文(
                for: id,
                type: type,
                language: language
            )
            guard result.isResolved else { return cachedResult }
        }

        if result.isResolved {
            VNDB简介译文缓存.shared.insert(
                result,
                for: cacheKey,
                persist: resolvedMode == .openSourceFetch
            )
        }
        return result
    }

    private static func 远程译文(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言
    ) async -> VNDB简介译文缓存结果 {
        guard let relativePath = relativeTranslationPath(
            for: id,
            type: type,
            language: language
        ) else {
            return .missing
        }

        let sources = VNDB简介翻译数据源.优先顺序()
        for (index, source) in sources.enumerated() {
            guard !Task.isCancelled else { return .notLoaded }
            guard let url = source.entryURL(relativePath: relativePath) else {
                continue
            }

            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = index == sources.count - 1 ? 20 : 8
            request.setValue(
                "application/vnd.github.raw+json",
                forHTTPHeaderField: "Accept"
            )

            do {
                let (data, response) = try await URLSession.shared.data(
                    for: request
                )
                guard let httpResponse = response as? HTTPURLResponse else {
                    continue
                }
                if httpResponse.statusCode == 404 {
                    if source == .paperVN,
                       await VNDB简介翻译镜像清单缓存.shared.manifest(
                           maxAge: 10 * 60
                       ) == nil {
                        continue
                    }
                    return .missing
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    continue
                }
                return decodeTranslation(
                    from: data,
                    expectedID: id,
                    type: type,
                    language: language
                ).map(VNDB简介译文缓存结果.translation) ?? .missing
            } catch {
                continue
            }
        }
        return .notLoaded
    }

    static func 译文缓存结果(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言,
        mode: VNDB简介翻译模式? = nil
    ) -> VNDB简介译文缓存结果 {
        let resolvedMode = mode ?? VNDB简介翻译模式.current
        guard resolvedMode != .automaticOnDevice else { return .missing }

        let cacheKey = translationCacheKey(
            for: id,
            type: type,
            language: language,
            mode: resolvedMode
        )
        let cachedResult = VNDB简介译文缓存.shared.result(
            for: cacheKey,
            allowDisk: resolvedMode == .openSourceFetch
        )
        if cachedResult.isResolved {
            return cachedResult
        }

        guard resolvedMode == .openSourceOffline,
              已有完整下载 else {
            return .notLoaded
        }
        let translation = 读取本地译文(
            for: id,
            type: type,
            language: language,
            translationsRoot: 完整下载根目录
        )
        let result = translation.map(VNDB简介译文缓存结果.translation)
            ?? .missing
        VNDB简介译文缓存.shared.insert(
            result,
            for: cacheKey,
            persist: false
        )
        return result
    }

    static func 下载完整翻译文件(
        progress: @escaping @Sendable (Double) async -> Void = { _ in },
        stage: @escaping @Sendable (VNDB简介翻译下载阶段) async -> Void = { _ in },
        source: @escaping @Sendable (VNDB简介翻译数据源) async -> Void = { _ in }
    ) async throws {
        var temporaryURL: URL?
        var lastError: (any Error)?
        for candidate in VNDB简介翻译数据源.优先顺序() {
            try Task.checkCancellation()
            await source(candidate)
            do {
                temporaryURL = try await 下载压缩包(
                    from: candidate,
                    progress: progress,
                    stage: stage
                )
                break
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        guard let temporaryURL else {
            throw lastError ?? VNDB简介翻译下载错误.invalidArchiveURL
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let destinationRoot = 完整下载根目录
        let supportDirectory = applicationSupportDirectory
        await stage(.extracting)
        await progress(0.9)
        let extractionTask = Task.detached(priority: .userInitiated) {
            try installArchive(
                from: temporaryURL,
                applicationSupportDirectory: supportDirectory,
                destinationRoot: destinationRoot
            ) { fraction in
                Task { await progress(0.9 + fraction * 0.1) }
            }
        }
        try await withTaskCancellationHandler {
            try await extractionTask.value
        } onCancel: {
            extractionTask.cancel()
        }
        VNDB简介译文缓存.shared.removeAllFromMemory()
        await progress(1)
    }

    static var 已安装版本号: String? {
        guard let data = try? Data(contentsOf: 完整下载版本URL),
              let revision = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !revision.isEmpty else {
            return nil
        }
        return revision
    }

    static func 检查完整翻译文件更新() async -> VNDB简介翻译版本? {
        guard 已有完整下载,
              let latest = await 最新版本() else {
            return nil
        }
        return 需要更新(
            to: latest,
            installedRevision: 已安装版本号,
            downloadedAt: 完整下载日期
        ) ? latest : nil
    }

    static func 需要更新(
        to latest: VNDB简介翻译版本,
        installedRevision: String?,
        downloadedAt: Date?
    ) -> Bool {
        if let installedRevision {
            return latest.revision.caseInsensitiveCompare(installedRevision)
                != .orderedSame
        }
        guard let committedAt = latest.committedAt,
              let downloadedAt else {
            return false
        }
        return committedAt > downloadedAt
    }

    private static func 最新版本() async -> VNDB简介翻译版本? {
        let preferredSource = VNDB简介翻译数据源.优先顺序().first ?? .github
        let manifest = await VNDB简介翻译镜像清单缓存.shared.manifest(maxAge: 60)
        if preferredSource == .paperVN, let manifest {
            return VNDB简介翻译版本(
                revision: manifest.revision,
                committedAt: manifest.committedAt,
                archiveBytes: manifest.archiveBytes
            )
        }

        let githubArchiveBytes = { (revision: String) -> Int64 in
            guard let manifest, manifest.revision == revision else {
                return VNDB简介翻译数据源.github.预估压缩包大小字节数
            }
            return manifest.githubArchiveBytes
                ?? VNDB简介翻译数据源.github.预估压缩包大小字节数
        }
        if let branch = await 获取GitHub最新提交() {
            return VNDB简介翻译版本(
                revision: branch.commit.sha,
                committedAt: branch.commit.commit?.committer?.date,
                archiveBytes: githubArchiveBytes(branch.commit.sha)
            )
        }
        guard let manifest else { return nil }
        return VNDB简介翻译版本(
            revision: manifest.revision,
            committedAt: manifest.committedAt,
            archiveBytes: githubArchiveBytes(manifest.revision)
        )
    }

    fileprivate static func 获取镜像清单() async -> VNDB简介翻译镜像清单? {
        guard let url = VNDB简介翻译数据源.paperVN.revisionURL else {
            return nil
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        return await 获取版本信息(request, as: VNDB简介翻译镜像清单.self)
    }

    private static func 获取GitHub最新提交() async -> VNDB简介翻译GitHub分支? {
        guard let url = VNDB简介翻译数据源.github.revisionURL else {
            return nil
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue("PaperVN", forHTTPHeaderField: "User-Agent")
        return await 获取版本信息(request, as: VNDB简介翻译GitHub分支.self)
    }

    private static func 获取版本信息<Value: Decodable>(
        _ request: URLRequest,
        as type: Value.Type
    ) async -> Value? {
        guard let (data, response) = try? await URLSession.shared.data(
                  for: request
              ),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func 压缩包版本号(at archiveURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: archiveURL) else {
            return nil
        }
        defer { try? handle.close() }

        let endOfCentralDirectorySize = 22
        guard let fileSize = try? handle.seekToEnd(),
              fileSize >= UInt64(endOfCentralDirectorySize) else {
            return nil
        }
        let tailLength = min(
            fileSize,
            UInt64(endOfCentralDirectorySize + Int(UInt16.max))
        )
        guard (try? handle.seek(toOffset: fileSize - tailLength)) != nil,
              let tail = try? handle.readToEnd() else {
            return nil
        }

        let bytes = [UInt8](tail)
        for index in stride(
            from: bytes.count - endOfCentralDirectorySize,
            through: 0,
            by: -1
        ) {
            guard bytes[index] == 0x50,
                  bytes[index + 1] == 0x4B,
                  bytes[index + 2] == 0x05,
                  bytes[index + 3] == 0x06 else {
                continue
            }
            let commentLength = Int(bytes[index + 20])
                | Int(bytes[index + 21]) << 8
            let commentStart = index + endOfCentralDirectorySize
            guard commentStart + commentLength == bytes.count else {
                continue
            }
            let comment = String(decoding: bytes[commentStart...], as: UTF8.self)
            let isRevision = (40...64).contains(comment.count)
                && comment.allSatisfy(\.isHexDigit)
            return isRevision ? comment.lowercased() : nil
        }
        return nil
    }

    private static func 下载压缩包(
        from source: VNDB简介翻译数据源,
        progress: @escaping @Sendable (Double) async -> Void,
        stage: @escaping @Sendable (VNDB简介翻译下载阶段) async -> Void
    ) async throws -> URL {
        guard let archiveURL = source.archiveURL else {
            throw VNDB简介翻译下载错误.invalidArchiveURL
        }

        var request = URLRequest(url: archiveURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 180
        request.setValue("application/zip", forHTTPHeaderField: "Accept")
        request.setValue("PaperVN", forHTTPHeaderField: "User-Agent")

        await stage(.connecting)
        await progress(0)
        let delegate = VNDB简介翻译下载代理(
            progressHandler: { fraction in
                Task { await progress(fraction * 0.9) }
            },
            responseHandler: {
                Task { await stage(.downloading) }
            }
        )
        do {
            return try await delegate.download(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as URLError {
            throw VNDB简介翻译下载错误.network(
                source: source,
                code: error.code.rawValue,
                description: error.localizedDescription
            )
        } catch let error as VNDB简介翻译下载错误 {
            throw error.attributed(to: source)
        }
    }

    static func 译文(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言,
        translationsRoot: URL
    ) -> String? {
        读取本地译文(
            for: id,
            type: type,
            language: language,
            translationsRoot: translationsRoot
        )
    }

    private static func translationCacheKey(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言,
        mode: VNDB简介翻译模式
    ) -> String {
        "\(mode.rawValue)|\(type.rawValue)|\(language.rawValue)|\(id)"
    }

    static func bucketName(for id: String) -> String? {
        guard id.count > 1,
              let number = Int(id.dropFirst()),
              number >= 0 else {
            return nil
        }
        return String(format: "%03d", number / 1_000)
    }

    static func cleanDescription(_ description: String) -> String {
        var text = description
        text = text.replacingOccurrences(
            of: "\\[/?[a-zA-Z]+[^\\]]*\\]",
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var applicationSupportDirectory: URL {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return root.appending(path: "PaperVN", directoryHint: .isDirectory)
    }

    private static var 完整下载根目录: URL {
        applicationSupportDirectory.appending(
            path: resourceDirectoryName,
            directoryHint: .isDirectory
        )
    }

    private static var 完整下载标记URL: URL {
        完整下载根目录.appending(
            path: ".papervn-download-complete",
            directoryHint: .notDirectory
        )
    }

    private static var 完整下载版本URL: URL {
        完整下载根目录.appending(
            path: ".papervn-revision",
            directoryHint: .notDirectory
        )
    }

    static func relativeTranslationPath(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言
    ) -> String? {
        guard let bucket = bucketName(for: id) else { return nil }
        return "\(language.rawValue)/\(type.directoryName)/\(bucket)/\(id).json"
    }

    private static func decodeTranslation(
        from data: Data,
        expectedID: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言
    ) -> String? {
        guard let file = try? JSONDecoder().decode(
            VNDB简介翻译文件.self,
            from: data
        ),
        file.schemaVersion == 1,
        file.id == expectedID,
        file.type == type,
        file.language == language.rawValue else {
            return nil
        }

        let translation = cleanDescription(file.translation)
        return translation.isEmpty ? nil : translation
    }

    private static func 读取本地译文(
        for id: String,
        type: VNDB简介条目类型,
        language: 简介翻译语言,
        translationsRoot: URL
    ) -> String? {
        guard let bucket = bucketName(for: id) else { return nil }

        let fileURL = translationsRoot
            .appending(path: language.rawValue, directoryHint: .isDirectory)
            .appending(path: type.directoryName, directoryHint: .isDirectory)
            .appending(path: bucket, directoryHint: .isDirectory)
            .appending(path: "\(id).json", directoryHint: .notDirectory)

        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return decodeTranslation(
            from: data,
            expectedID: id,
            type: type,
            language: language
        )
    }

    private static func installArchive(
        from archiveURL: URL,
        applicationSupportDirectory: URL,
        destinationRoot: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )

        let stagingDirectory = applicationSupportDirectory.appending(
            path: ".\(resourceDirectoryName)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? fileManager.removeItem(at: stagingDirectory) }
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        let archive = try Archive(url: archiveURL, accessMode: .read)
        let expectedRootPrefix = "\(repositoryName)-\(branchName)/"
        let entries = archive.compactMap { entry -> Entry? in
            guard entry.type == .file,
                  entry.path.hasPrefix(expectedRootPrefix) else {
                return nil
            }

            let relativePath = String(entry.path.dropFirst(expectedRootPrefix.count))
            let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
            guard components.count >= 2,
                  let language = components.first.map(String.init),
                  supportedLanguageDirectories.contains(language),
                  components.allSatisfy({ component in
                      !component.isEmpty && component != "." && component != ".."
                  }),
                  relativePath.hasSuffix(".json") || relativePath.hasSuffix(".gitkeep") else {
                return nil
            }
            return entry
        }
        let totalEntryCount = entries.count
        var extractedEntryCount = 0

        for entry in entries {
            try Task.checkCancellation()
            let relativePath = String(entry.path.dropFirst(expectedRootPrefix.count))
            let destinationURL = stagingDirectory.appending(
                path: relativePath,
                directoryHint: .notDirectory
            )
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = try archive.extract(entry, to: destinationURL)
            extractedEntryCount += 1
            if extractedEntryCount.isMultiple(of: 100)
                || extractedEntryCount == totalEntryCount {
                progress(
                    Double(extractedEntryCount)
                        / Double(max(totalEntryCount, 1))
                )
            }
        }

        guard extractedEntryCount > 0 else {
            throw VNDB简介翻译下载错误.noTranslationDirectory
        }

        let markerURL = stagingDirectory.appending(
            path: ".papervn-download-complete",
            directoryHint: .notDirectory
        )
        try Data("\(Date().timeIntervalSince1970)".utf8).write(
            to: markerURL,
            options: .atomic
        )
        if let revision = 压缩包版本号(at: archiveURL) {
            try Data(revision.utf8).write(
                to: stagingDirectory.appending(
                    path: ".papervn-revision",
                    directoryHint: .notDirectory
                ),
                options: .atomic
            )
        }

        if fileManager.fileExists(atPath: destinationRoot.path) {
            _ = try fileManager.replaceItemAt(
                destinationRoot,
                withItemAt: stagingDirectory,
                backupItemName: nil,
                options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(
                at: stagingDirectory,
                to: destinationRoot
            )
        }
    }
}

private enum VNDB简介翻译下载错误: LocalizedError {
    case invalidArchiveURL
    case invalidServerResponse(source: VNDB简介翻译数据源 = .github)
    case httpStatus(Int, source: VNDB简介翻译数据源 = .github)
    case network(source: VNDB简介翻译数据源, code: Int, description: String)
    case noTranslationDirectory

    func attributed(to source: VNDB简介翻译数据源) -> Self {
        switch self {
        case .invalidServerResponse:
            .invalidServerResponse(source: source)
        case .httpStatus(let statusCode, _):
            .httpStatus(statusCode, source: source)
        case .network(_, let code, let description):
            .network(source: source, code: code, description: description)
        case .invalidArchiveURL, .noTranslationDirectory:
            self
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidArchiveURL:
            String(localized: "无法创建简介翻译下载地址。")
        case .invalidServerResponse(let source):
            source == .github
                ? String(localized: "GitHub没有返回有效的简介翻译文件。")
                : String(localized: "PaperVN服务器没有返回有效的简介翻译文件。")
        case .httpStatus(let statusCode, let source):
            String(
                format: source == .github
                    ? String(localized: "GitHub返回了HTTP错误（%d）。")
                    : String(localized: "PaperVN服务器返回了HTTP错误（%d）。"),
                statusCode
            )
        case .network(let source, let code, let description):
            String(
                format: source == .github
                    ? String(localized: "连接GitHub时发生网络错误（%d）：%@")
                    : String(localized: "连接PaperVN服务器时发生网络错误（%d）：%@"),
                code,
                description
            )
        case .noTranslationDirectory:
            String(localized: "下载的文件中没有可用的简介翻译目录。")
        }
    }
}

nonisolated struct VNDB简介翻译标题: Codable, Hashable, Sendable {
    let lang: String
    let title: String
    let latin: String?
    let official: Bool
    let main: Bool
}

nonisolated struct VNDB简介翻译条目: Hashable, Sendable {
    let id: String
    let type: VNDB简介条目类型
    let name: String
    let romanizedName: String
    let titles: [VNDB简介翻译标题]?
    let displayName: String
    let originalName: String?
    let source: String
    let displaySource: String
    /// 显示名称的字体规则，与 `标题工具.标题结果` 一致。
    var displayIsJapanese = false
    var displayLanguageCode: String? = nil
}

nonisolated enum 简介翻译投稿语言: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplifiedChinese: String(localized: "简体中文")
        case .traditionalChinese: String(localized: "繁体中文")
        case .japanese: String(localized: "日语")
        case .korean: String(localized: "韩语")
        }
    }

    var 简介语言: 简介翻译语言 {
        switch self {
        case .simplifiedChinese: .simplifiedChinese
        case .traditionalChinese: .traditionalChinese
        case .japanese: .japanese
        case .korean: .korean
        }
    }

    static func 默认语言(
        interfaceLanguage: String? = Bundle.main.preferredLocalizations.first,
        fallback: 简介翻译语言
    ) -> Self {
        if let interfaceLanguage {
            let language = Locale.Language(identifier: interfaceLanguage)
            if language.languageCode?.identifier == "zh" {
                let script = language.script?.identifier
                let region = language.region?.identifier
                let isTraditional = script == "Hant"
                    || (script == nil && ["TW", "HK", "MO"].contains(region ?? ""))
                return isTraditional ? .traditionalChinese : .simplifiedChinese
            }
            if let code = language.languageCode?.identifier,
               let value = Self(rawValue: code) {
                return value
            }
        }
        return Self(rawValue: fallback.rawValue) ?? .simplifiedChinese
    }
}

nonisolated struct VNDB简介翻译投稿记录: Decodable, Identifiable, Hashable, Sendable {
    enum 状态: String, Decodable, Sendable {
        case pending
        case accepted
        case rejected
        case withdrawn
    }

    let id: String
    let entryID: String
    let type: VNDB简介条目类型
    let language: String
    let status: 状态
    let name: String?
    let romanizedName: String?
    let titles: [VNDB简介翻译标题]?
    let originalName: String?
    let source: String?
    let translation: String
    let note: String?
    let reviewNote: String?
    let submittedAt: String
    let updatedAt: String?

    var 投稿语言: 简介翻译投稿语言? {
        简介翻译投稿语言(rawValue: language)
    }

    var languageTitle: String {
        投稿语言?.title
            ?? Locale.current.localizedString(forIdentifier: language)
            ?? language
    }

    var statusText: String {
        switch status {
        case .pending: String(localized: "已提交")
        case .accepted: String(localized: "已采纳")
        case .rejected: String(localized: "已拒绝")
        case .withdrawn: String(localized: "已撤回")
        }
    }

    var isEditable: Bool {
        status == .pending || status == .rejected
    }

    var originalLanguageName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? entryID : trimmed
    }

    func entry(
        displayName: String,
        displayIsJapanese: Bool = false,
        displayLanguageCode: String? = nil
    ) -> VNDB简介翻译条目 {
        let source = source ?? ""
        return VNDB简介翻译条目(
            id: entryID,
            type: type,
            name: originalLanguageName,
            romanizedName: romanizedName ?? originalLanguageName,
            titles: titles,
            displayName: displayName,
            originalName: originalName,
            source: source,
            displaySource: VNDB简介人工翻译.cleanDescription(source),
            displayIsJapanese: displayIsJapanese,
            displayLanguageCode: displayLanguageCode
        )
    }

    var submittedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: submittedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: submittedAt)
    }
}

nonisolated struct VNDB简介翻译投稿结果: Decodable, Sendable {
    let submission: VNDB简介翻译投稿记录
    let updated: Bool
}

nonisolated enum VNDB简介翻译投稿错误: LocalizedError {
    case unavailable
    case invalidResponse
    case server(code: String, message: String)

    var code: String? {
        guard case let .server(code, _) = self else { return nil }
        return code
    }

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "服务器当前不可用，请稍后重试。")
        case .invalidResponse:
            String(localized: "翻译投稿服务返回了无效响应。")
        case let .server(code, message):
            switch code {
            case "authentication_required", "authentication_invalid":
                String(localized: "VNDB登录已失效，请重新登录。")
            case "authentication_unavailable":
                String(localized: "暂时无法验证VNDB登录状态。")
            case "invalid_translation":
                String(localized: "译文不能为空，且不能超过20000个字符。")
            case "translation_already_accepted":
                String(localized: "你提交的这条译文已被采纳。如有问题，请通过反馈告诉我们。")
            default:
                message
            }
        }
    }
}

nonisolated struct VNDB简介翻译投稿服务: Sendable {
    static let 译文最大长度 = 20_000
    private static let endpoint = URL(
        string: "https://papervn.jizpaper.com/api/translations/submissions"
    )!

    private struct 请求: Encodable {
        let id: String
        let type: String
        let language: String
        let translation: String
        let note: String?
        let name: String
        let romanizedName: String
        let titles: [VNDB简介翻译标题]?
        let originalName: String?
        let source: String
        let client: [String: String]
    }

    private struct 错误响应: Decodable {
        struct APIError: Decodable {
            let code: String
            let message: String
        }

        let error: APIError
    }

    private struct 列表响应: Decodable {
        let submissions: [VNDB简介翻译投稿记录]
    }

    private struct 单条响应: Decodable {
        let submission: VNDB简介翻译投稿记录
    }

    private struct 空请求: Encodable {}

    func submit(
        token: String,
        entry: VNDB简介翻译条目,
        language: 简介翻译投稿语言,
        translation: String,
        note: String?
    ) async throws -> VNDB简介翻译投稿结果 {
        try await request(
            url: Self.endpoint,
            method: "POST",
            token: token,
            body: 请求(
                id: entry.id,
                type: entry.type.rawValue,
                language: language.rawValue,
                translation: translation,
                note: note,
                name: entry.name,
                romanizedName: entry.romanizedName,
                titles: entry.titles,
                originalName: entry.originalName,
                source: entry.source,
                client: [
                    "appVersion": Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String ?? "",
                    "build": Bundle.main.object(
                        forInfoDictionaryKey: "CFBundleVersion"
                    ) as? String ?? "",
                    "interfaceLanguage":
                        Bundle.main.preferredLocalizations.first ?? "",
                    "platform": "iOS"
                ]
            )
        )
    }

    func mySubmissions(token: String) async throws -> [VNDB简介翻译投稿记录] {
        let response: 列表响应 = try await request(
            url: Self.endpoint,
            method: "GET",
            token: token,
            body: Optional<空请求>.none
        )
        return response.submissions
    }

    func withdraw(token: String, id: String) async throws {
        let _: 单条响应 = try await request(
            url: Self.endpoint.appending(path: id).appending(path: "withdraw"),
            method: "POST",
            token: token,
            body: 空请求()
        )
    }

    private func request<Response: Decodable, Body: Encodable>(
        url: URL,
        method: String,
        token: String,
        body: Body?
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue(
                "application/json; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw VNDB简介翻译投稿错误.unavailable
        }
        guard let response = response as? HTTPURLResponse else {
            throw VNDB简介翻译投稿错误.unavailable
        }
        guard (200...299).contains(response.statusCode) else {
            if let error = try? JSONDecoder().decode(错误响应.self, from: data) {
                throw VNDB简介翻译投稿错误.server(
                    code: error.error.code,
                    message: error.error.message
                )
            }
            throw VNDB简介翻译投稿错误.unavailable
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw VNDB简介翻译投稿错误.invalidResponse
        }
    }
}
