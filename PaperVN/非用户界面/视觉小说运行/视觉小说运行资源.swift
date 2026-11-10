import CryptoKit
import Foundation
import Observation
import ZIPFoundation

/// 运行部分引擎才需要的资源。不放进 App，运行时才下载，不玩这些游戏的人不用占这份空间。
/// 引擎的原生代码不能下载，仍在 App 里。
nonisolated enum 视觉小说运行资源包: String, CaseIterable, Sendable {
    case kirikiri
    case 字体
    case midi音色
    case flash
    case renpy

    var 显示名称: String {
        switch self {
        case .kirikiri: String(localized: "KiriKiri支持内容")
        case .字体: String(localized: "运行资源.字体")
        case .midi音色: String(localized: "MIDI音色")
        case .flash: String(localized: "Flash支持内容")
        case .renpy: String(localized: "Ren'Py支持内容")
        }
    }
}

nonisolated struct 视觉小说资源包信息: Sendable {
    let 文件名: String
    let 下载大小: Int64
    let 解压大小: Int64
    let 校验值: String
}

nonisolated enum 视觉小说运行资源 {
    enum 错误: LocalizedError {
        case 文件已损坏
        case 服务器错误
        case 空间不足(需要: Int64)

        var errorDescription: String? {
            switch self {
            case .文件已损坏: String(localized: "下载的文件已损坏。")
            case .服务器错误: String(localized: "无法下载资源")
            case .空间不足(let bytes):
                String(localized: "需要\(推荐模型下载状态.文件大小文本(bytes))可用空间才能下载资源。")
            }
        }
    }

    private static var 地址前缀: URL {
        #if DEBUG
        // 测试用：资源包还没上传时指向本地服务器
        if let override = UserDefaults.standard.string(forKey: "VisualNovelRuntimeBaseURL"),
           let url = URL(string: override) {
            return url
        }
        #endif
        return URL(string: "https://r2-papervn.jizpaper.com/Resources/VisualNovelRuntime/")!
    }

    static func 下载地址(_ pack: 视觉小说运行资源包) -> URL {
        地址前缀.appending(path: pack.信息.文件名)
    }

    static var 根目录: URL {
        URL.applicationSupportDirectory.appending(path: "VisualNovelRuntime", directoryHint: .isDirectory)
    }

    private static var 下载中目录: URL { 根目录.appending(path: ".downloading", directoryHint: .isDirectory) }
    private static var 安装中目录: URL { 根目录.appending(path: ".installing", directoryHint: .isDirectory) }

    /// 文件名带校验值，资源更新后是新文件夹，旧的在下次下载时清掉
    private static func 文件夹名(_ pack: 视觉小说运行资源包) -> String {
        (pack.信息.文件名 as NSString).deletingPathExtension
    }

    static func 目录(_ pack: 视觉小说运行资源包) -> URL {
        根目录.appending(path: 文件夹名(pack), directoryHint: .isDirectory)
    }

    static func 已安装(_ pack: 视觉小说运行资源包) -> Bool {
        FileManager.default.fileExists(atPath: 目录(pack).path)
    }

    static func 缺少(_ packs: [视觉小说运行资源包]) -> [视觉小说运行资源包] {
        packs.filter { !已安装($0) }
    }

    static func 部分文件(_ pack: 视觉小说运行资源包) -> URL {
        下载中目录.appending(path: pack.信息.文件名 + ".part")
    }

    // MARK: - 各引擎用到的位置

    static var 字体文件: URL { 目录(.字体).appending(path: "NotoSansCJK-Regular.ttc") }
    static var MIDI音色库: URL { 目录(.midi音色).appending(path: "GeneralUser-GS.sf2") }
    static var Ruffle目录: URL { 目录(.flash) }
    static var RenPy运行库: URL { 目录(.renpy) }

    /// krkr2 固定在资源根目录下的 res 文件夹里找资源，也在那里按文件名找默认字体。
    /// 字体是单独的包，这里放一个链接，用相对路径：App 更新后容器的绝对路径会变。
    static func 准备KiriKiri目录() -> String {
        let folder = 目录(.kirikiri).appending(path: "res", directoryHint: .isDirectory)
        let link = folder.appending(path: "NotoSansCJK-Regular.ttc").path
        try? FileManager.default.removeItem(atPath: link)
        try? FileManager.default.createSymbolicLink(
            atPath: link, withDestinationPath: "../../\(文件夹名(.字体))/NotoSansCJK-Regular.ttc"
        )
        return folder.path
    }

    // MARK: - 储存空间

    static var 已占用大小: Int64 {
        guard let walker = FileManager.default.enumerator(
            at: 根目录, includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    static func 全部删除() throws {
        guard FileManager.default.fileExists(atPath: 根目录.path) else { return }
        try FileManager.default.removeItem(at: 根目录)
    }

    // MARK: - 安装

    /// 下载和安装时临时要用的空间：压缩包和解压后的文件会同时存在
    static func 检查空间(_ packs: [视觉小说运行资源包]) throws {
        let need = packs.reduce(Int64(0)) { sum, pack in
            let partial = (try? 部分文件(pack).resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }.map(Int64.init) ?? 0
            return sum + pack.信息.下载大小 - partial + pack.信息.解压大小
        }
        let parent = FileManager.default.fileExists(atPath: 根目录.path) ? 根目录 : URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        guard let available = try? parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return }
        if available < need { throw 错误.空间不足(需要: need) }
    }

    static func 准备目录() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: 下载中目录, withIntermediateDirectories: true)
        // 可以重新下载，不进 iCloud 备份
        var root = 根目录
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        // 清掉 App 更新后不再用的旧版本
        let current = Set(视觉小说运行资源包.allCases.map(文件夹名))
        let currentParts = Set(视觉小说运行资源包.allCases.map { $0.信息.文件名 + ".part" })
        for name in (try? manager.contentsOfDirectory(atPath: root.path)) ?? []
        where !name.hasPrefix(".") && !current.contains(name) {
            try? manager.removeItem(at: root.appending(path: name))
        }
        for name in (try? manager.contentsOfDirectory(atPath: 下载中目录.path)) ?? [] where !currentParts.contains(name) {
            try? manager.removeItem(at: 下载中目录.appending(path: name))
        }
        try? manager.removeItem(at: 安装中目录)
    }

    /// 校验并解压。先解压到临时文件夹再整个移过去，文件夹存在就等于安装完整
    static func 安装(_ pack: 视觉小说运行资源包) throws {
        let manager = FileManager.default
        let archive = 部分文件(pack)
        guard try 校验值(archive) == pack.信息.校验值 else {
            try? manager.removeItem(at: archive)
            throw 错误.文件已损坏
        }
        let temporary = 安装中目录.appending(path: 文件夹名(pack), directoryHint: .isDirectory)
        try? manager.removeItem(at: temporary)
        try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: 安装中目录) }
        do {
            try manager.unzipItem(at: archive, to: temporary)
        } catch {
            try? manager.removeItem(at: archive)
            throw 错误.文件已损坏
        }
        try manager.moveItem(at: temporary, to: 目录(pack))
        try? manager.removeItem(at: archive)
    }

    private static func 校验值(_ file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// 把数据追加到部分文件，下载中断后从断点继续
private nonisolated final class 视觉小说资源下载代理: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let 文件: URL
    private let 进度: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var handle: FileHandle?
    private var 已下载: Int64

    init(文件: URL, 已下载: Int64, 进度: @escaping @Sendable (Int64) -> Void, continuation: CheckedContinuation<Void, Error>) {
        self.文件 = 文件
        self.已下载 = 已下载
        self.进度 = 进度
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 || status == 206 else {
            结束(视觉小说运行资源.错误.服务器错误)
            completionHandler(.cancel)
            return
        }
        // 200 表示服务器没理会范围请求，从头写
        if status == 200 {
            已下载 = 0
            try? FileManager.default.removeItem(at: 文件)
        }
        if !FileManager.default.fileExists(atPath: 文件.path) {
            FileManager.default.createFile(atPath: 文件.path, contents: nil)
        }
        do {
            let opened = try FileHandle(forWritingTo: 文件)
            try opened.seekToEnd()
            handle = opened
            completionHandler(.allow)
        } catch {
            结束(error)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            try handle?.write(contentsOf: data)
            已下载 += Int64(data.count)
            进度(已下载)
        } catch {
            结束(error)
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        结束(error)
    }

    private func 结束(_ error: Error?) {
        try? handle?.close()
        handle = nil
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

@MainActor
@Observable
final class 视觉小说运行资源下载 {
    enum 阶段 {
        case 下载
        case 安装
    }

    private(set) var 当前阶段 = 阶段.下载
    private(set) var 进度 = 0.0

    func 下载(_ packs: [视觉小说运行资源包]) async throws {
        let total = packs.reduce(Int64(0)) { $0 + $1.信息.下载大小 }
        var finished: Int64 = 0
        当前阶段 = .下载
        进度 = 0
        try await Task.detached { try 视觉小说运行资源.检查空间(packs) }.value
        try await Task.detached { try 视觉小说运行资源.准备目录() }.value
        for pack in packs {
            try await 下载文件(pack, 已完成: finished, 总大小: total)
            finished += pack.信息.下载大小
        }
        当前阶段 = .安装
        try await Task.detached(priority: .userInitiated) {
            for pack in packs { try 视觉小说运行资源.安装(pack) }
        }.value
    }

    private func 下载文件(_ pack: 视觉小说运行资源包, 已完成 finished: Int64, 总大小 total: Int64) async throws {
        let file = 视觉小说运行资源.部分文件(pack)
        let existing = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        进度 = Double(finished + existing) / Double(max(total, 1))
        // 上次已经下载完（比如解压时被打断）
        if existing == pack.信息.下载大小 { return }
        if existing > pack.信息.下载大小 { try? FileManager.default.removeItem(at: file) }
        let start = existing > pack.信息.下载大小 ? 0 : existing

        var request = URLRequest(url: 视觉小说运行资源.下载地址(pack), cachePolicy: .reloadIgnoringLocalCacheData)
        if start > 0 { request.setValue("bytes=\(start)-", forHTTPHeaderField: "Range") }

        let progress: @Sendable (Int64) -> Void = { [weak self] received in
            let value = Double(finished + received) / Double(max(total, 1))
            Task { @MainActor [weak self] in self?.进度 = value }
        }
        nonisolated(unsafe) var running: URLSessionDataTask?
        let lock = NSLock()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let delegate = 视觉小说资源下载代理(文件: file, 已下载: start, 进度: progress, continuation: continuation)
                let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                let task = session.dataTask(with: request)
                lock.withLock { running = task }
                task.resume()
                session.finishTasksAndInvalidate()
            }
        } onCancel: {
            lock.withLock { running?.cancel() }
        }
    }
}
