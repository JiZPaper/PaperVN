import Foundation
import Observation

nonisolated enum 智能搜索设置 {
    static let 启用键 = "smartSearchEnabled"

    static var 已启用: Bool {
        UserDefaults.standard.object(forKey: 启用键) as? Bool ?? true
    }
}

/// 服务器上比本地新的智能搜索模型。
nonisolated struct 智能搜索模型更新: Sendable, Equatable {
    let modelIdentifier: String
    let bytes: Int64?

    var sizeText: String? {
        bytes.map(推荐模型下载状态.文件大小文本)
    }
}

@MainActor
@Observable
final class 智能搜索模型下载状态 {
    static let shared = 智能搜索模型下载状态()

    private(set) var isDownloading = false
    /// 下载完成后校验并安装文件的阶段。
    private(set) var isInstalling = false
    private(set) var progress = 0.0
    private(set) var downloadError: String?
    /// 有可以使用的模型。App 内置了模型，正常情况下总是 true。
    private(set) var isModelAvailable = false
    /// 下载了比内置更新的模型。
    private(set) var hasDownloadedUpdate = false
    /// 下载的更新占用的空间（内置的模型属于 App 本身，不算在内）。
    private(set) var downloadedSize: Int64 = 0
    /// 服务器上模型文件的大小，用于下载和更新提示。
    private(set) var serverFileSize: Int64?
    var availableUpdate: 智能搜索模型更新?
    var updateError: String?

    private static let 服务器文件校验值键 = "smartSearchModelServerValidator"
    private static let 忽略版本设置键 = "ignoredSmartSearchModelVersion"
    private var isCheckingForUpdate = false
    private var lastUpdateCheck: Date?

    var progressPercent: Int {
        min(max(Int(progress * 100), 0), 100)
    }

    var serverFileSizeText: String? {
        serverFileSize.map(推荐模型下载状态.文件大小文本)
    }

    private init() {
        refresh()
    }

    func refresh() {
        智能搜索模型存储.清理过期的下载()
        isModelAvailable = 智能搜索模型存储.已安装
        hasDownloadedUpdate = 智能搜索模型存储.已下载更新
        downloadedSize = hasDownloadedUpdate ? 智能搜索模型存储.已下载文件大小 : 0
    }

    func refreshServerFileSize() async {
        if let bytes = await 模型文件下载器.服务器文件信息(
            of: 智能搜索模型存储.下载地址
        )?.bytes {
            serverFileSize = bytes
        }
    }

    /// 服务器上的模型与本地不同时提示更新。先比较 ETag，没有记录时只读取服务器文件开头的版本标识。
    func checkForUpdate() async {
        refresh()
        guard isModelAvailable,
              !isDownloading,
              !isCheckingForUpdate,
              availableUpdate == nil,
              智能搜索设置.已启用 else {
            return
        }
        if let lastUpdateCheck,
           Date().timeIntervalSince(lastUpdateCheck) < 30 * 60 {
            return
        }
        isCheckingForUpdate = true
        lastUpdateCheck = Date()
        defer { isCheckingForUpdate = false }

        let url = 智能搜索模型存储.下载地址
        guard let info = await 模型文件下载器.服务器文件信息(of: url) else { return }
        if let bytes = info.bytes {
            serverFileSize = bytes
        }
        if let validator = info.validator,
           validator == UserDefaults.standard.string(forKey: Self.服务器文件校验值键) {
            return
        }
        guard let head = await 模型文件下载器.读取文件开头(of: url, 字节数: 65_536),
              let remote = try? 智能搜索模型文件.读取头(head).modelIdentifier else {
            return
        }
        if remote == Self.本地模型标识() {
            if let validator = info.validator {
                UserDefaults.standard.set(validator, forKey: Self.服务器文件校验值键)
            }
            return
        }
        guard remote != UserDefaults.standard.string(forKey: Self.忽略版本设置键),
              !isDownloading else {
            return
        }
        availableUpdate = 智能搜索模型更新(modelIdentifier: remote, bytes: info.bytes)
    }

    func ignore(_ update: 智能搜索模型更新) {
        UserDefaults.standard.set(update.modelIdentifier, forKey: Self.忽略版本设置键)
        availableUpdate = nil
    }

    func installUpdate() async {
        availableUpdate = nil
        await downloadReportingErrors()
    }

    /// 从提示里开始的下载失败时用提示框告知，而不是只在设置里显示。
    func downloadReportingErrors() async {
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
        defer {
            isDownloading = false
            isInstalling = false
        }

        do {
            let (temporaryURL, validator) = try await 模型文件下载器.download(
                from: 智能搜索模型存储.下载地址,
                invalidResponseError: 智能搜索模型错误.服务器响应无效,
                progress: { [weak self] fraction in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.progress = max(self.progress, fraction)
                    }
                }
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            progress = 1
            isInstalling = true
            await 智能搜索引擎.shared.卸载()
            try await Self.安装(temporaryURL)
            if let validator {
                UserDefaults.standard.set(validator, forKey: Self.服务器文件校验值键)
            }
            availableUpdate = nil
            refresh()
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
    func deleteModel() async throws {
        await 智能搜索引擎.shared.卸载()
        try 智能搜索模型存储.删除()
        refresh()
    }

    private static func 本地模型标识() -> String? {
        智能搜索模型存储.当前URL.flatMap(智能搜索模型存储.读取标识)
    }

    /// 先完整验证下载的文件能被读取，再替换已下载的文件。
    private nonisolated static func 安装(_ 下载文件: URL) async throws {
        do {
            let 文件 = try 智能搜索模型文件(url: 下载文件)
            _ = try 智能搜索名称索引(文件: 文件)
            _ = try 智能搜索排序器(数据: 文件.数据段("ranker"))
        }
        let 文件管理 = FileManager.default
        try 智能搜索模型存储.创建目录()
        if 文件管理.fileExists(atPath: 智能搜索模型存储.下载URL.path) {
            try 文件管理.removeItem(at: 智能搜索模型存储.下载URL)
        }
        try 文件管理.moveItem(at: 下载文件, to: 智能搜索模型存储.下载URL)
    }
}
