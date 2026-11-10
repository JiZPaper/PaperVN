import Foundation
import Observation

nonisolated enum 为你推荐设置 {
    /// 沿用旧版“偏好分析”开关的键，用户关闭过的保持关闭。
    static let 启用键 = "recommendationPreferenceAnalysisEnabled"
    private static let 设备限制迁移键 = "PaperVN.didRemoveRecommendationMemoryLimit"
    private static let 旧版数据清除键 = "PaperVN.didRemovePreferenceAnalysisData"

    static var 已启用: Bool {
        UserDefaults.standard.object(forKey: 启用键) as? Bool ?? true
    }

    /// 旧版在内存不足 4 GB 的设备上自动关闭了“为你推荐”，现在所有设备都支持，恢复成默认开启。
    static func 移除设备限制(
        defaults: UserDefaults = .standard,
        物理内存: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) {
        guard !defaults.bool(forKey: 设备限制迁移键) else { return }
        if 物理内存 < 4 * 1_024 * 1_024 * 1_024 {
            defaults.removeObject(forKey: 启用键)
        }
        defaults.set(true, forKey: 设备限制迁移键)
    }

    /// 删除旧版偏好分析下载的模型、计算缓存和进度记录。
    static func 清除旧版数据(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: 旧版数据清除键) else { return }
        let fileManager = FileManager.default
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fileManager.removeItem(at: support.appendingPathComponent("PaperVNRecommendationModel", isDirectory: true))
            // 探索页面的标签与特征目录也存在这里，只删除推荐结果和资料库快照
            let analysis = support.appendingPathComponent("PaperVNRecommendationAnalysis", isDirectory: true)
            let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PaperVNExplore", isDirectory: true)
            for directory in [analysis, caches] {
                for file in (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
                where file.hasPrefix("recommendations_")
                    || file.hasPrefix("recommendation_library_")
                    || file.hasPrefix("recommendation_tag_shelves_") {
                    try? fileManager.removeItem(at: directory.appendingPathComponent(file))
                }
            }
        }
        for key in defaults.dictionaryRepresentation().keys where
            key.hasPrefix("recommendationPreferenceAnalysis") && key != 启用键
            || key.hasPrefix("pendingRecommendationPreferenceAnalysis")
            || key == "recommendationModelServerValidator"
            || key == "ignoredRecommendationModelVersion" {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: 旧版数据清除键)
    }
}

nonisolated enum 推荐模型存储 {
    static let 文件名 = "\(作品推荐模型.资源名).\(作品推荐模型.扩展名)"
    static let 下载地址 = URL(
        string: "https://r2-papervn.jizpaper.com/Resources/\(作品推荐模型.资源名).\(作品推荐模型.扩展名)"
    )!

    static var 目录: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent(作品推荐模型.资源名, isDirectory: true)
    }

    /// 下载的模型更新。
    static var 下载URL: URL {
        目录.appendingPathComponent(文件名)
    }

    /// App 安装包里预装的模型。
    static var 内置URL: URL? {
        Bundle.main.url(forResource: 作品推荐模型.资源名, withExtension: 作品推荐模型.扩展名)
    }

    /// 当前使用的模型：下载的更新和内置的不是同一版、且不比内置的旧时用下载的，否则用内置的。
    static var 当前URL: URL? {
        let 内置 = 内置URL.flatMap { url in 作品推荐模型.标识(of: url).map { (url, $0) } }
        guard let 下载 = 作品推荐模型.标识(of: 下载URL) else { return 内置?.0 }
        guard let 内置 else { return 下载URL }
        return 下载 == 内置.1 || 日期(下载) < 日期(内置.1) ? 内置.0 : 下载URL
    }

    /// 下载的更新存在并且正在使用。
    static var 已下载更新: Bool {
        当前URL == 下载URL
    }

    /// 下载的文件不再使用时删除：App 更新后内置的模型和它一样新或更新。
    static func 清理过期的下载() {
        guard FileManager.default.fileExists(atPath: 下载URL.path), !已下载更新 else { return }
        try? 删除()
    }

    /// 模型标识开头是构建日期，用来比较新旧；同一天构建的视为一样新。
    static func 日期(_ 标识: String) -> Substring {
        标识.prefix { $0 != "-" }
    }

    static var 已下载文件大小: Int64 {
        guard let values = try? 下载URL.resourceValues(
            forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        ), values.isRegularFile == true else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    static func 创建目录() throws {
        var directory = 目录
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try directory.setResourceValues(resourceValues)
    }

    static func 删除() throws {
        if FileManager.default.fileExists(atPath: 目录.path) {
            try FileManager.default.removeItem(at: 目录)
        }
    }
}

/// 服务器上比本地新的推荐模型。
nonisolated struct 推荐模型更新: Sendable, Equatable {
    let modelIdentifier: String
    let bytes: Int64?

    var sizeText: String? {
        bytes.map(推荐模型下载状态.文件大小文本)
    }
}

/// “为你推荐”模型内置在 App 里，服务器上有更新的版本时提示下载，和智能搜索模型一样。
@MainActor
@Observable
final class 推荐模型下载状态 {
    static let shared = 推荐模型下载状态()

    private(set) var isDownloading = false
    private(set) var progress = 0.0
    private(set) var downloadError: String?
    /// 下载了比内置更新的模型。
    private(set) var hasDownloadedUpdate = false
    /// 下载的更新占用的空间（内置的模型属于 App 本身，不算在内）。
    private(set) var downloadedSize: Int64 = 0
    var availableUpdate: 推荐模型更新?
    var updateError: String?

    private static let 服务器文件校验值键 = "workRecommendationModelServerValidator"
    private static let 忽略版本设置键 = "ignoredWorkRecommendationModelVersion"
    private var isCheckingForUpdate = false
    private var lastUpdateCheck: Date?

    var progressPercent: Int {
        min(max(Int(progress * 100), 0), 100)
    }

    nonisolated static func 文件大小文本(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private init() {
        refresh()
    }

    func refresh() {
        推荐模型存储.清理过期的下载()
        hasDownloadedUpdate = 推荐模型存储.已下载更新
        downloadedSize = hasDownloadedUpdate ? 推荐模型存储.已下载文件大小 : 0
    }

    /// 服务器上的模型比正在用的新时提示更新。先比较 ETag，没有记录时只读取服务器文件开头的版本标识。
    func checkForUpdate() async {
        refresh()
        guard !isDownloading,
              !isCheckingForUpdate,
              availableUpdate == nil,
              为你推荐设置.已启用 else {
            return
        }
        if let lastUpdateCheck,
           Date().timeIntervalSince(lastUpdateCheck) < 30 * 60 {
            return
        }
        isCheckingForUpdate = true
        lastUpdateCheck = Date()
        defer { isCheckingForUpdate = false }

        let url = 推荐模型存储.下载地址
        guard let info = await 模型文件下载器.服务器文件信息(of: url) else { return }
        if let validator = info.validator,
           validator == UserDefaults.standard.string(forKey: Self.服务器文件校验值键) {
            return
        }
        guard let head = await 模型文件下载器.读取文件开头(of: url, 字节数: 264),
              let remote = 作品推荐模型.标识(头: head) else {
            return
        }
        // App 内置的模型可能比服务器上的新（标识开头是构建日期）
        let local = 推荐模型存储.当前URL.flatMap(作品推荐模型.标识(of:))
        if remote == local || (local.map { 推荐模型存储.日期(remote) <= 推荐模型存储.日期($0) } ?? false) {
            if let validator = info.validator {
                UserDefaults.standard.set(validator, forKey: Self.服务器文件校验值键)
            }
            return
        }
        guard remote != UserDefaults.standard.string(forKey: Self.忽略版本设置键),
              !isDownloading else {
            return
        }
        availableUpdate = 推荐模型更新(modelIdentifier: remote, bytes: info.bytes)
    }

    func ignore(_ update: 推荐模型更新) {
        UserDefaults.standard.set(update.modelIdentifier, forKey: Self.忽略版本设置键)
        availableUpdate = nil
    }

    func installUpdate() async {
        availableUpdate = nil
        await download()
        if let downloadError {
            updateError = downloadError
        }
    }

    func download() async {
        guard !isDownloading else { return }

        isDownloading = true
        progress = 0
        downloadError = nil
        defer { isDownloading = false }

        do {
            let (temporaryURL, validator) = try await 模型文件下载器.download(
                from: 推荐模型存储.下载地址,
                invalidResponseError: 作品推荐模型错误.服务器响应无效,
                progress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.progress = max(self.progress, fraction)
                    }
                }
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            progress = 1
            try await Self.安装(temporaryURL)
            if let validator {
                UserDefaults.standard.set(validator, forKey: Self.服务器文件校验值键)
            }
            availableUpdate = nil
            refresh()
            作品推荐中心.shared.模型文件已变更()
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            downloadError = error.localizedDescription
            refresh()
        }
    }

    /// 删除下载的更新，恢复使用 App 内置的模型。
    func deleteModel() throws {
        try 推荐模型存储.删除()
        refresh()
        作品推荐中心.shared.模型文件已变更()
    }

    /// 先完整验证下载的文件能被读取，再替换已下载的文件。
    private nonisolated static func 安装(_ 下载文件: URL) async throws {
        _ = try 作品推荐模型(url: 下载文件)
        let fileManager = FileManager.default
        try 推荐模型存储.创建目录()
        if fileManager.fileExists(atPath: 推荐模型存储.下载URL.path) {
            try fileManager.removeItem(at: 推荐模型存储.下载URL)
        }
        try fileManager.moveItem(at: 下载文件, to: 推荐模型存储.下载URL)
    }
}
