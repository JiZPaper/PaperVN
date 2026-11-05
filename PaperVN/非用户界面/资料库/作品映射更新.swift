import CryptoKit
import Foundation

/// 作品映射文件放在哪里：App 安装包里预装一份，App 内静默下载的更新放在 Application Support。
nonisolated enum 作品映射存储 {
    static let 文件名 = "PaperVNWorkMap.json"

    static var 目录: URL {
        URL.applicationSupportDirectory.appending(path: "PaperVNWorkMap", directoryHint: .isDirectory)
    }

    /// 下载的更新。
    static var 下载URL: URL { 目录.appending(path: 文件名) }

    /// App 安装包里预装的映射。
    static var 内置URL: URL? { Bundle.main.url(forResource: "PaperVNWorkMap", withExtension: "json") }

    /// 当前使用的映射：下载的更新和内置的不是同一份、且不比内置的旧时用下载的，否则用内置的。
    static var 当前URL: URL? {
        guard let 下载 = 版本(of: 下载URL) else { return 内置URL }
        guard let 内置URL, let 内置 = 版本(of: 内置URL) else { return 下载URL }
        return 比内置的新(下载, 内置: 内置) ? 下载URL : 内置URL
    }

    static var 正在使用下载的更新: Bool { 当前URL == 下载URL }

    /// 版本是“构建日期-内容摘要”：摘要相同是同一份；不同时日期更晚（或同一天）的算新。
    static func 比内置的新(_ version: String, 内置: String) -> Bool {
        摘要(version) != 摘要(内置) && 日期(version) >= 日期(内置)
    }

    static func 日期(_ version: String) -> Substring { version.prefix { $0 != "-" } }

    static func 摘要(_ version: String) -> Substring {
        guard let dash = version.firstIndex(of: "-") else { return Substring(version) }
        return version[version.index(after: dash)...]
    }

    /// 只读文件开头的 "version"（生成映射时放在最前面），不用解析整个文件。
    static func 版本(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 256),
              let text = String(data: head, encoding: .utf8),
              let match = text.firstMatch(of: /"version"\s*:\s*"([^"]+)"/) else { return nil }
        return String(match.1)
    }

    /// App 更新后内置的映射和下载的一样新或更新时，删掉不再使用的下载文件。
    static func 清理过期的下载() {
        guard FileManager.default.fileExists(atPath: 下载URL.path), !正在使用下载的更新 else { return }
        try? FileManager.default.removeItem(at: 下载URL)
    }

    static func 创建目录() throws {
        var directory = 目录
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
}

/// 服务器上的映射更新清单（`https://papervn.jizpaper.com/workmap/manifest.json`，由 `deploy/vps/deploy-workmap.sh` 发布）。
nonisolated struct 作品映射清单: Codable, Equatable, Sendable {
    /// 映射文件的结构版本。只接受这个版本的 App 认识的结构，结构改了的新映射留给新版 App。
    let format: Int
    let version: String
    /// 数据文件名，带版本，内容不会再变。
    let file: String
    /// 压缩后的大小。
    let bytes: Int64
    /// 解压后 JSON 的 SHA-256。
    let sha256: String
}

/// 作品映射的 App 内静默更新：启动和回到前台时检查清单（最多每 6 小时一次），有新版本就用后台下载会话下载，
/// 用户退出 App 也不要紧——系统会继续下载；被强行退出时保存续传数据，下次检查时接着下载。
/// 下载完先解压、核对摘要、确认能完整读取，再替换已下载的映射文件；没有同步正在进行时马上换用，
/// 否则等下一次同步开始时再换（同步过程中作品的编号不能变）。整个过程不显示任何界面。
nonisolated final class 作品映射更新: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = 作品映射更新()
    static let 会话标识 = "com.jizpaper.PaperVN.workmap"
    static let 支持的结构版本 = 1
    static var 清单地址: URL {
        #if DEBUG
        // 调试用：-WorkMapManifestURL <地址> 改用本机的测试清单，并且每次启动都检查
        if let value = UserDefaults.standard.string(forKey: "WorkMapManifestURL"), let url = URL(string: value) { return url }
        #endif
        return URL(string: "https://papervn.jizpaper.com/workmap/manifest.json")!
    }
    private static let 检查间隔: TimeInterval = 6 * 60 * 60

    private enum 设置键 {
        static let 上次检查 = "workMapUpdate.lastCheck"
        static let 正在下载 = "workMapUpdate.pendingManifest"
        static let 上次结果 = "workMapUpdate.lastResult"
        static let 上次更新 = "workMapUpdate.lastInstalled"
    }

    private let 锁 = NSLock()
    private var 后台会话: URLSession?
    /// 系统在后台唤醒 App 交付下载事件时给的完成回调。
    private var 后台事件完成: (() -> Void)?

    private var 续传数据URL: URL { 作品映射存储.目录.appending(path: "download.resume") }
    private var 暂存URL: URL { 作品映射存储.目录.appending(path: "download.deflate") }

    /// 后台下载会话。启动时就要建好，系统才能把 App 不在时完成或中断的下载交给它。
    var 会话: URLSession {
        锁.lock()
        defer { 锁.unlock() }
        if let 后台会话 { return 后台会话 }
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.会话标识)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.allowsConstrainedNetworkAccess = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        后台会话 = session
        return session
    }

    /// App 启动时调用：删掉过期的下载，建好后台会话接收之前没交付的下载事件。
    func 启动() {
        作品映射存储.清理过期的下载()
        _ = 会话
    }

    /// 系统在后台唤醒 App 交付下载事件（SwiftUI 的 `.backgroundTask(.urlSession)`）：建好会话，等事件交付完再返回。
    /// 系统一直不通知交付完时最多等 25 秒，免得一直占着后台时间。
    func 处理后台事件() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = 只执行一次 { continuation.resume() }
            锁.lock()
            后台事件完成 = once.run
            锁.unlock()
            _ = 会话
            DispatchQueue.global().asyncAfter(deadline: .now() + 25, execute: once.run)
        }
    }

    private final class 只执行一次: @unchecked Sendable {
        private let 锁 = NSLock()
        private var action: (() -> Void)?
        init(_ action: @escaping () -> Void) { self.action = action }
        func run() {
            锁.lock()
            let action = action
            self.action = nil
            锁.unlock()
            action?()
        }
    }

    // MARK: 检查

    /// 检查服务器上的清单，有新版本时开始（或接着）下载。`忽略间隔` 只用于测试与诊断。
    func 检查更新(忽略间隔: Bool = false) async {
        let defaults = UserDefaults.standard
        var 忽略间隔 = 忽略间隔
        #if DEBUG
        if defaults.string(forKey: "WorkMapManifestURL") != nil { 忽略间隔 = true }
        #endif
        if !忽略间隔, let last = defaults.object(forKey: 设置键.上次检查) as? Date,
           Date().timeIntervalSince(last) < Self.检查间隔 {
            return
        }
        defaults.set(Date(), forKey: 设置键.上次检查)
        guard let manifest = await 读取清单() else {
            记录结果(.无法读取清单)
            return
        }
        guard manifest.format == Self.支持的结构版本 else {
            记录结果(.需要更新App, 版本: manifest.version)
            return
        }
        let current = 作品映射存储.当前URL.flatMap(作品映射存储.版本(of:))
        if let current, !作品映射存储.比内置的新(manifest.version, 内置: current) {
            记录结果(.已是最新)
            return
        }
        await 下载(manifest)
    }

    private func 读取清单() async -> 作品映射清单? {
        var request = URLRequest(url: Self.清单地址, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let manifest = try? JSONDecoder().decode(作品映射清单.self, from: data),
              manifest.file.wholeMatch(of: /PaperVNWorkMap-[A-Za-z0-9-]+\.json\.deflate/) != nil,
              manifest.sha256.wholeMatch(of: /[0-9a-f]{64}/) != nil else { return nil }
        return manifest
    }

    private func 下载(_ manifest: 作品映射清单) async {
        // 已经在下载这个版本（App 只是被挂起了）：不重复开始
        let tasks = await 会话.allTasks
        if tasks.contains(where: { $0.taskDescription == manifest.version && $0.state == .running }) { return }
        for task in tasks { task.cancel() }

        let defaults = UserDefaults.standard
        let pending = defaults.data(forKey: 设置键.正在下载).flatMap { try? JSONDecoder().decode(作品映射清单.self, from: $0) }
        let task: URLSessionDownloadTask
        if pending == manifest, let resume = try? Data(contentsOf: 续传数据URL) {
            task = 会话.downloadTask(withResumeData: resume)
        } else {
            try? FileManager.default.removeItem(at: 续传数据URL)
            task = 会话.downloadTask(with: Self.清单地址.deletingLastPathComponent().appending(path: manifest.file))
        }
        defaults.set(try? JSONEncoder().encode(manifest), forKey: 设置键.正在下载)
        task.taskDescription = manifest.version
        task.countOfBytesClientExpectsToReceive = manifest.bytes
        task.resume()
        记录结果(.正在下载, 版本: manifest.version)
    }

    // MARK: 下载完成

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // 回调返回后系统就会删掉临时文件，必须在这里同步移走
        let defaults = UserDefaults.standard
        guard let manifest = defaults.data(forKey: 设置键.正在下载).flatMap({ try? JSONDecoder().decode(作品映射清单.self, from: $0) }),
              downloadTask.taskDescription == manifest.version,
              let response = downloadTask.response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            记录结果(.文件无效)
            return
        }
        do {
            try 作品映射存储.创建目录()
            try? FileManager.default.removeItem(at: 暂存URL)
            try FileManager.default.moveItem(at: location, to: 暂存URL)
            try 安装(manifest)
            defaults.removeObject(forKey: 设置键.正在下载)
            try? FileManager.default.removeItem(at: 续传数据URL)
            defaults.set(Date(), forKey: 设置键.上次更新)
            记录结果(.已更新, 版本: manifest.version)
            Task { @MainActor in await PaperVNSync中心.shared.作品映射已更新() }
        } catch {
            // 文件坏了：丢掉，下次检查时重新下载
            defaults.removeObject(forKey: 设置键.正在下载)
            try? FileManager.default.removeItem(at: 续传数据URL)
            记录结果(.无法安装, 版本: manifest.version, 详情: error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: 暂存URL)
    }

    /// 解压、核对摘要、确认能完整读取，再替换已下载的映射文件。
    private func 安装(_ manifest: 作品映射清单) throws {
        let compressed = try Data(contentsOf: 暂存URL)
        let data = try (compressed as NSData).decompressed(using: .zlib) as Data
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.sha256 else { throw CocoaError(.fileReadCorruptFile) }
        guard try 作品映射.验证(data) == manifest.version else { throw CocoaError(.fileReadCorruptFile) }
        try data.write(to: 作品映射存储.下载URL, options: .atomic)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        // 被取消（包括用户强行退出 App）或网络中断：留下续传数据，下次检查时接着下载
        if let resume = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? 作品映射存储.创建目录()
            try? resume.write(to: 续传数据URL, options: .atomic)
            记录结果(.下载中断)
        } else if (error as? URLError)?.code != .cancelled {
            记录结果(.下载失败, 详情: error.localizedDescription)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        锁.lock()
        let completion = 后台事件完成
        后台事件完成 = nil
        锁.unlock()
        completion?()
    }

    // MARK: 诊断

    /// 上一次检查或下载的结果。存代码而不是文字，诊断时按当时的语言显示。
    enum 结果: String, Sendable {
        case 无法读取清单, 需要更新App, 已是最新, 正在下载, 文件无效, 已更新, 无法安装, 下载中断, 下载失败
    }

    private func 记录结果(_ result: 结果, 版本 version: String? = nil, 详情 detail: String? = nil) {
        var value = ["code": result.rawValue]
        value["version"] = version
        value["detail"] = detail
        UserDefaults.standard.set(value, forKey: 设置键.上次结果)
    }

    private static func 结果说明(_ value: [String: String]?) -> String? {
        guard let value, let code = value["code"].flatMap(结果.init(rawValue:)) else { return nil }
        let version = value["version"] ?? "—"
        let detail = value["detail"] ?? "—"
        return switch code {
        case .无法读取清单: String(localized: "无法读取清单")
        case .需要更新App: String(localized: "需要更新App才能使用版本\(version)")
        case .已是最新: String(localized: "已是最新")
        case .正在下载: String(localized: "正在下载版本\(version)")
        case .文件无效: String(localized: "下载的文件无效")
        case .已更新: String(localized: "已更新到版本\(version)")
        case .无法安装: String(localized: "无法安装版本\(version)：\(detail)")
        case .下载中断: String(localized: "下载中断，下次继续")
        case .下载失败: String(localized: "下载失败：\(detail)")
        }
    }

    struct 状态: Sendable {
        let 正在使用的版本: String?
        let 使用下载的更新: Bool
        let 内置版本: String?
        let 上次检查: Date?
        let 上次更新: Date?
        let 上次结果: String?
        let 正在下载的版本: String?
    }

    var 状态: 状态 {
        let defaults = UserDefaults.standard
        return .init(
            正在使用的版本: 作品映射.版本,
            使用下载的更新: 作品映射存储.正在使用下载的更新,
            内置版本: 作品映射存储.内置URL.flatMap(作品映射存储.版本(of:)),
            上次检查: defaults.object(forKey: 设置键.上次检查) as? Date,
            上次更新: defaults.object(forKey: 设置键.上次更新) as? Date,
            上次结果: Self.结果说明(defaults.dictionary(forKey: 设置键.上次结果) as? [String: String]),
            正在下载的版本: defaults.data(forKey: 设置键.正在下载)
                .flatMap { try? JSONDecoder().decode(作品映射清单.self, from: $0) }?.version
        )
    }
}
