import Foundation
import Observation

/// 服务器上比本地新的偏好分析模型。
nonisolated struct 推荐模型更新: Sendable, Equatable {
    /// 服务器模型清单的标识，忽略时按它记录。
    let modelIdentifier: String
    let bytes: Int64?

    var sizeText: String? {
        bytes.map(推荐模型下载状态.文件大小文本)
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
    /// 服务器上模型文件的大小，用于下载和更新提示。
    private(set) var serverFileSize: Int64?
    var availableUpdate: 推荐模型更新?
    var updateError: String?

    private static let 服务器文件校验值键 = "recommendationModelServerValidator"
    private static let 忽略版本设置键 = "ignoredRecommendationModelVersion"
    private var isCheckingForUpdate = false
    private var lastUpdateCheck: Date?

    var progressPercent: Int {
        min(max(Int(progress * 100), 0), 100)
    }

    var serverFileSizeText: String? {
        serverFileSize.map(Self.文件大小文本)
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
        let manifest = VNDB离线推荐模型加载器.清单()
        hasDownloadedModel = manifest != nil
        needsUpdate = manifest.map { $0.collaborative == nil } ?? false
        downloadedSize = hasDownloadedModel
            ? VNDB离线推荐模型存储.已下载文件大小
            : 0
    }

    func refreshServerFileSize() async {
        if let bytes = await 模型文件下载器.服务器文件信息(
            of: VNDB离线推荐模型存储.下载地址
        )?.bytes {
            serverFileSize = bytes
        }
    }

    /// 服务器上的模型与本地不同时提示更新，包括旧版构建器生成的模型。
    /// 先比较 ETag；没有记录过 ETag 时只读取服务器文件开头的模型清单，不下载完整模型。
    func checkForUpdate() async {
        refresh()
        guard hasDownloadedModel,
              !isDownloading,
              !isCheckingForUpdate,
              availableUpdate == nil,
              为你推荐偏好分析设置.已启用 else {
            return
        }
        if let lastUpdateCheck,
           Date().timeIntervalSince(lastUpdateCheck) < 30 * 60 {
            return
        }
        isCheckingForUpdate = true
        lastUpdateCheck = Date()
        defer { isCheckingForUpdate = false }

        let url = VNDB离线推荐模型存储.下载地址
        guard let info = await 模型文件下载器.服务器文件信息(of: url) else { return }
        if let bytes = info.bytes {
            serverFileSize = bytes
        }
        if let validator = info.validator,
           validator == UserDefaults.standard.string(forKey: Self.服务器文件校验值键) {
            return
        }
        guard let remote = await 模型文件下载器.服务器模型标识(of: url) else { return }
        if remote == VNDB离线推荐模型加载器.模型标识() {
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
        UserDefaults.standard.set(
            update.modelIdentifier,
            forKey: Self.忽略版本设置键
        )
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
            try VNDB离线推荐模型存储.创建目录()
            let stagingURL = VNDB离线推荐模型存储.文件URL
                .deletingLastPathComponent()
                .appendingPathComponent(
                    ".\(VNDB离线推荐模型存储.文件名).\(UUID().uuidString).download"
                )
            defer { try? FileManager.default.removeItem(at: stagingURL) }

            let (temporaryURL, validator) = try await 模型文件下载器.download(
                from: VNDB离线推荐模型存储.下载地址,
                invalidResponseError: VNDB离线推荐模型错误.invalidServerResponse,
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
            availableUpdate = nil
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
            downloadError = error.localizedDescription
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

private extension 模型文件下载器 {
    /// 只读取服务器文件开头 64 KB 解析模型清单，不下载完整模型。
    static func 服务器模型标识(of url: URL) async -> String? {
        guard let head = await 读取文件开头(of: url, 字节数: 65_536) else { return nil }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperVNModelHead-\(UUID().uuidString).gz")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? head.write(to: file)) != nil else { return nil }
        return VNDB离线推荐模型加载器.模型标识(url: file)
    }
}
