import Foundation

/// 偏好分析模型和智能搜索模型共用的大文件下载：带进度、读取 ETag、只读取文件开头比较版本。
final class 模型文件下载代理: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    private let invalidResponseError: any Error
    private var continuation: CheckedContinuation<(URL, String?), Error>?
    private var didFinish = false

    init(
        progress: @escaping @Sendable (Double) -> Void,
        invalidResponseError: any Error,
        continuation: CheckedContinuation<(URL, String?), Error>
    ) {
        self.progress = progress
        self.invalidResponseError = invalidResponseError
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
            continuation?.resume(throwing: invalidResponseError)
            continuation = nil
            session.finishTasksAndInvalidate()
            return
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperVNModel-\(UUID().uuidString).download")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume(
                returning: (destination, 模型文件下载器.校验值(response))
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

enum 模型文件下载器 {
    static func download(
        from url: URL,
        invalidResponseError: any Error,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> (URL, String?) {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = 模型文件下载代理(
                progress: progress,
                invalidResponseError: invalidResponseError,
                continuation: continuation
            )
            let session = URLSession(
                configuration: .ephemeral,
                delegate: delegate,
                delegateQueue: nil
            )
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }

    /// 用 HEAD 请求读取服务器文件的校验值和大小。
    static func 服务器文件信息(of url: URL) async -> (validator: String?, bytes: Int64?)? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        guard let (_, response) = try? await session.data(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return nil
        }
        let bytes = response.expectedContentLength > 0
            ? response.expectedContentLength
            : response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
        return (校验值(response), bytes)
    }

    /// 用范围请求只读取服务器文件的开头。
    static func 读取文件开头(of url: URL, 字节数: Int) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(字节数 - 1)", forHTTPHeaderField: "Range")
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        guard let (bytes, response) = try? await session.bytes(for: request),
              let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            return nil
        }
        var head = Data()
        do {
            for try await byte in bytes {
                head.append(byte)
                if head.count >= 字节数 { break }
            }
        } catch {
            return nil
        }
        return head
    }

    nonisolated static func 校验值(_ response: HTTPURLResponse) -> String? {
        response.value(forHTTPHeaderField: "ETag")
            ?? response.value(forHTTPHeaderField: "Last-Modified")
    }
}
