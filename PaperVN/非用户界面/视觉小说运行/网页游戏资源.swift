import Compression
import Foundation
import UniformTypeIdentifiers

/// 网页游戏的资源读取：WebKit 通过自定义 URL scheme 请求文件，这里从文件夹、ZIP（package.nw 或附加在 exe 后的 ZIP）、
/// app.asar 中读出来。Windows 上做的游戏经常写错文件名大小写，找不到时按不区分大小写再找一次。
nonisolated final class 网页游戏资源: @unchecked Sendable {
    static let scheme = "papervn-game"

    private let 读取器: any 网页游戏资源读取器
    let 入口: String

    init(游戏文件夹 folder: URL, 包 package: 网页游戏包) throws {
        switch package {
        case .文件夹(let root, let entry):
            读取器 = 文件夹读取器(root.isEmpty ? folder : folder.appending(path: root, directoryHint: .isDirectory))
            入口 = entry
        case .zip(let file, let offset, let entry):
            读取器 = try ZIP读取器(folder.appending(path: file), 偏移: offset)
            入口 = entry
        case .asar(let file, let entry):
            读取器 = try ASAR读取器(folder.appending(path: file))
            入口 = entry
        }
    }

    /// 电脑版的 Ren'Py 游戏：页面和运行库来自 App，game 文件夹按需读取
    init(RenPy游戏根目录 root: URL) throws {
        读取器 = try RenPy原生读取器(游戏根目录: root)
        入口 = "index.html"
    }

    /// 游戏页面的地址。host 用作品 ID，不同作品的 localStorage（存档）互不影响。
    static func 入口URL(作品 vnID: String, 入口 entry: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = vnID.lowercased()
        components.path = "/" + entry
        return components.url!
    }

    /// 自定义 scheme 请求的回应。支持 Range（音频、视频会分段请求）。
    func 回应(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        guard let url = request.url else {
            return (HTTPURLResponse(url: URL(string: "\(Self.scheme)://invalid/")!, statusCode: 400, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
        }
        var path = url.path(percentEncoded: false)
        while path.hasPrefix("/") { path.removeFirst() }
        if path.isEmpty || path.hasSuffix("/") { path += "index.html" }

        guard let size = 读取器.大小(path) else {
            return (HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: Self.通用头)!, Data())
        }
        var headers = Self.通用头
        headers["Content-Type"] = Self.MIME类型(path)
        headers["Accept-Ranges"] = "bytes"

        if let range = request.value(forHTTPHeaderField: "Range").flatMap({ Self.解析范围($0, 大小: size) }) {
            let data = (try? 读取器.读取(path, 范围: range)) ?? Data()
            headers["Content-Range"] = "bytes \(range.lowerBound)-\(range.lowerBound + UInt64(data.count) - 1)/\(size)"
            headers["Content-Length"] = String(data.count)
            return (HTTPURLResponse(url: url, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: headers)!, data)
        }
        let data = (try? 读取器.读取(path, 范围: nil)) ?? Data()
        headers["Content-Length"] = String(data.count)
        return (HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!, data)
    }

    private static let 通用头: [String: String] = [
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-cache",
    ]

    private static func 解析范围(_ value: String, 大小 size: UInt64) -> Range<UInt64>? {
        guard size > 0, value.hasPrefix("bytes=") else { return nil }
        let parts = value.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = UInt64(parts[1]) {
            return (size - min(suffix, size))..<size
        }
        guard let start = UInt64(parts[0]), start < size else { return nil }
        let end = UInt64(parts[1]).map { min($0 + 1, size) } ?? size
        return end > start ? start..<end : nil
    }

    private static func MIME类型(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "ks", "txt", "tjs", "csv": return "text/plain; charset=utf-8"
        case "wasm": return "application/wasm"
        case "ogg", "oga": return "audio/ogg"
        case "m4a": return "audio/mp4"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        default:
            return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    // MARK: 识别

    /// 文件是 ZIP（或末尾附加了 ZIP 的 exe）且里面有网页入口时，返回包和引擎（认不出引擎时是 HTML5）。
    static func 识别ZIP包(_ file: URL, relative: String) -> (包: 网页游戏包, 引擎: 视觉小说引擎)? {
        guard let reader = try? ZIP读取器(file, 偏移: nil),
              let entry = 网页入口(reader) else { return nil }
        return (.zip(文件: relative, 偏移: reader.起点, 入口: entry), 网页引擎(reader.全部路径, 入口: entry) ?? .html5)
    }

    static func 识别ASAR包(_ file: URL, relative: String) -> (包: 网页游戏包, 引擎: 视觉小说引擎)? {
        guard let reader = try? ASAR读取器(file), let entry = 网页入口(reader) else { return nil }
        return (.asar(文件: relative, 入口: entry), 网页引擎(reader.全部路径, 入口: entry) ?? .html5)
    }

    /// 按包里的文件判断是哪个网页引擎。`paths` 是小写路径。
    static func 网页引擎(_ paths: Set<String>, 入口 entry: String) -> 视觉小说引擎? {
        let base = (entry as NSString).deletingLastPathComponent.lowercased()
        let prefix = base.isEmpty ? "" : base + "/"
        if paths.contains(prefix + "js/rmmz_core.js") { return .rpgMakerMZ }
        if paths.contains(prefix + "js/rpg_core.js") { return .rpgMakerMV }
        if paths.contains(where: { $0.hasPrefix(prefix + "tyrano/") }) { return .tyranoScript }
        if paths.contains(prefix + "renpy.wasm") || paths.contains(prefix + "game.zip") { return .renPyWeb }
        return nil
    }

    private static func 网页入口(_ reader: some 网页游戏资源读取器 & 可列出路径) -> String? {
        let paths = reader.全部路径
        // NW.js 的 package.json 里 main 就是入口页面
        if let data = try? reader.读取("package.json", 范围: nil),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let main = json["main"] as? String,
           main.lowercased().hasSuffix(".html") || main.lowercased().hasSuffix(".htm") {
            let entry = main.hasPrefix("./") ? String(main.dropFirst(2)) : main
            if paths.contains(entry.lowercased()) { return entry }
        }
        return ["index.html", "www/index.html", "app/index.html"].first { paths.contains($0) }
    }
}

// MARK: - 读取器

nonisolated protocol 网页游戏资源读取器: Sendable {
    /// 文件大小；没有这个文件时返回 nil。
    func 大小(_ path: String) -> UInt64?
    func 读取(_ path: String, 范围 range: Range<UInt64>?) throws -> Data
}

nonisolated protocol 可列出路径 {
    /// 小写的全部文件路径。
    var 全部路径: Set<String> { get }
}

nonisolated final class 简单锁<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

nonisolated enum 网页游戏资源错误: Error {
    case 格式无效
    case 找不到文件
}

/// 普通文件夹。找不到时用小写路径索引再找一次。
nonisolated final class 文件夹读取器: 网页游戏资源读取器, @unchecked Sendable {
    private let 根目录: URL
    private let 小写索引 = 简单锁<[String: String]?>(nil)

    init(_ root: URL) {
        根目录 = root
    }

    private func 实际路径(_ path: String) -> URL? {
        let direct = 根目录.appending(path: path)
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        let index = 小写索引.withLock { index -> [String: String] in
            if let index { return index }
            var built: [String: String] = [:]
            let rootPath = 根目录.standardizedFileURL.path
            if let enumerator = FileManager.default.enumerator(at: 根目录, includingPropertiesForKeys: nil) {
                for case let file as URL in enumerator {
                    let full = file.standardizedFileURL.path
                    guard full.hasPrefix(rootPath) else { continue }
                    var relative = String(full.dropFirst(rootPath.count))
                    while relative.hasPrefix("/") { relative.removeFirst() }
                    built[relative.lowercased()] = relative
                }
            }
            index = built
            return built
        }
        return index[path.lowercased()].map { 根目录.appending(path: $0) }
    }

    func 大小(_ path: String) -> UInt64? {
        guard let url = 实际路径(path), !url.是文件夹,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return UInt64(size)
    }

    func 读取(_ path: String, 范围 range: Range<UInt64>?) throws -> Data {
        guard let url = 实际路径(path) else { throw 网页游戏资源错误.找不到文件 }
        guard let range else { return try Data(contentsOf: url, options: .mappedIfSafe) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: range.lowerBound)
        return try handle.read(upToCount: Int(range.upperBound - range.lowerBound)) ?? Data()
    }
}

/// ZIP：只支持不压缩和 Deflate（NW.js 打包只会用到这两种）。自己解析中央目录，
/// 这样附加在 exe 后面、偏移没有修正过的 ZIP 也能读。
nonisolated final class ZIP读取器: 网页游戏资源读取器, 可列出路径, @unchecked Sendable {
    private struct 条目 {
        let 名称: String
        let 方法: UInt16
        let 压缩大小: UInt64
        let 原始大小: UInt64
        let 本地头偏移: UInt64
    }

    private let 文件: FileHandle
    private let 锁 = NSLock()
    private var 条目表: [String: 条目] = [:]
    private let 缓存 = 简单锁<(path: String, data: Data)?>(nil)
    /// ZIP 本体在文件里的起点（附加在 exe 后时不为 0）。
    let 起点: UInt64
    var 全部路径: Set<String> { Set(条目表.keys) }

    init(_ url: URL, 偏移: UInt64?) throws {
        文件 = try FileHandle(forReadingFrom: url)
        let fileSize = try 文件.seekToEnd()
        guard fileSize >= 22 else { throw 网页游戏资源错误.格式无效 }
        // 中央目录结束记录在末尾 22～65557 字节之间
        let tailLength = min(fileSize, 65_557)
        try 文件.seek(toOffset: fileSize - tailLength)
        let tail = try 文件.read(upToCount: Int(tailLength)) ?? Data()
        guard let eocd = Self.查找结束记录(tail) else { throw 网页游戏资源错误.格式无效 }
        let eocdOffset = fileSize - tailLength + UInt64(eocd)
        let directorySize = UInt64(tail.小端32(eocd + 12))
        let recordedDirectoryOffset = UInt64(tail.小端32(eocd + 16))
        guard eocdOffset >= directorySize else { throw 网页游戏资源错误.格式无效 }
        let directoryOffset = eocdOffset - directorySize
        guard directoryOffset >= recordedDirectoryOffset else { throw 网页游戏资源错误.格式无效 }
        起点 = 偏移 ?? (directoryOffset - recordedDirectoryOffset)

        try 文件.seek(toOffset: directoryOffset)
        let directory = try 文件.read(upToCount: Int(directorySize)) ?? Data()
        var cursor = 0
        while cursor + 46 <= directory.count, directory.小端32(cursor) == 0x0201_4b50 {
            let flags = directory.小端16(cursor + 8)
            let method = directory.小端16(cursor + 10)
            let compressed = UInt64(directory.小端32(cursor + 20))
            let original = UInt64(directory.小端32(cursor + 24))
            let nameLength = Int(directory.小端16(cursor + 28))
            let extraLength = Int(directory.小端16(cursor + 30))
            let commentLength = Int(directory.小端16(cursor + 32))
            let localOffset = UInt64(directory.小端32(cursor + 42))
            let nameData = directory.subdata(in: (cursor + 46)..<min(directory.count, cursor + 46 + nameLength))
            // 第 11 位表示 UTF-8；没有时多半是 Shift-JIS（日本的打包工具）
            let name = (flags & 0x800 != 0 ? String(data: nameData, encoding: .utf8) : nil)
                ?? String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .shiftJIS)
                ?? ""
            if !name.isEmpty, !name.hasSuffix("/") {
                条目表[name.lowercased()] = 条目(名称: name, 方法: method, 压缩大小: compressed, 原始大小: original, 本地头偏移: localOffset)
            }
            cursor += 46 + nameLength + extraLength + commentLength
        }
        guard !条目表.isEmpty else { throw 网页游戏资源错误.格式无效 }
    }

    deinit { try? 文件.close() }

    private static func 查找结束记录(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        var index = data.count - 22
        while index >= 0 {
            if data[data.startIndex + index] == 0x50, data.小端32(index) == 0x0605_4b50 { return index }
            index -= 1
        }
        return nil
    }

    func 大小(_ path: String) -> UInt64? {
        条目表[path.lowercased()]?.原始大小
    }

    func 读取(_ path: String, 范围 range: Range<UInt64>?) throws -> Data {
        let key = path.lowercased()
        guard let entry = 条目表[key] else { throw 网页游戏资源错误.找不到文件 }
        let full: Data
        if let cached = 缓存.withLock({ $0 }), cached.path == key {
            full = cached.data
        } else {
            let raw: Data = try {
                锁.lock()
                defer { 锁.unlock() }
                try 文件.seek(toOffset: 起点 + entry.本地头偏移)
                let header = try 文件.read(upToCount: 30) ?? Data()
                guard header.count == 30, header.小端32(0) == 0x0403_4b50 else { throw 网页游戏资源错误.格式无效 }
                let skip = UInt64(header.小端16(26)) + UInt64(header.小端16(28))
                try 文件.seek(toOffset: 起点 + entry.本地头偏移 + 30 + skip)
                return try 文件.read(upToCount: Int(entry.压缩大小)) ?? Data()
            }()
            switch entry.方法 {
            case 0: full = raw
            case 8: full = try 解压Deflate(raw, 原始大小: Int(entry.原始大小))
            default: throw 网页游戏资源错误.格式无效
            }
            // 音频、视频会分段请求同一个文件，留着最近的一个
            缓存.withLock { $0 = (key, full) }
        }
        guard let range else { return full }
        let lower = Int(min(range.lowerBound, UInt64(full.count)))
        let upper = Int(min(range.upperBound, UInt64(full.count)))
        return full.subdata(in: lower..<upper)
    }
}

/// Electron 的 asar：4 字节 + 4 字节头长度，然后是 Pickle 包着的 JSON 目录，文件内容不压缩地接在后面。
nonisolated final class ASAR读取器: 网页游戏资源读取器, 可列出路径, @unchecked Sendable {
    private struct 条目 {
        let 偏移: UInt64
        let 大小: UInt64
    }

    private let 文件: FileHandle
    private let 锁 = NSLock()
    private var 条目表: [String: 条目] = [:]
    private let 数据起点: UInt64
    var 全部路径: Set<String> { Set(条目表.keys) }

    init(_ url: URL) throws {
        文件 = try FileHandle(forReadingFrom: url)
        let prefix = try 文件.read(upToCount: 16) ?? Data()
        guard prefix.count == 16 else { throw 网页游戏资源错误.格式无效 }
        let headerSize = UInt64(prefix.小端32(4))
        let jsonLength = Int(prefix.小端32(12))
        let json = try 文件.read(upToCount: jsonLength) ?? Data()
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw 网页游戏资源错误.格式无效
        }
        数据起点 = 8 + headerSize
        func walk(_ node: [String: Any], _ prefix: String) {
            guard let files = node["files"] as? [String: Any] else { return }
            for (name, value) in files {
                guard let child = value as? [String: Any] else { continue }
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                if child["files"] != nil {
                    walk(child, path)
                } else if child["unpacked"] as? Bool != true,
                          let size = (child["size"] as? NSNumber)?.uint64Value,
                          let offset = UInt64(child["offset"] as? String ?? "") {
                    条目表[path.lowercased()] = 条目(偏移: offset, 大小: size)
                }
            }
        }
        walk(root, "")
        guard !条目表.isEmpty else { throw 网页游戏资源错误.格式无效 }
    }

    deinit { try? 文件.close() }

    func 大小(_ path: String) -> UInt64? {
        条目表[path.lowercased()]?.大小
    }

    func 读取(_ path: String, 范围 range: Range<UInt64>?) throws -> Data {
        guard let entry = 条目表[path.lowercased()] else { throw 网页游戏资源错误.找不到文件 }
        let range = range ?? 0..<entry.大小
        锁.lock()
        defer { 锁.unlock() }
        try 文件.seek(toOffset: 数据起点 + entry.偏移 + range.lowerBound)
        return try 文件.read(upToCount: Int(min(range.upperBound - range.lowerBound, entry.大小 - range.lowerBound))) ?? Data()
    }
}

/// 原始 Deflate（ZIP 里的方法 8）。Compression 框架的 ZLIB 就是不带头的 Deflate。
nonisolated func 解压Deflate(_ data: Data, 原始大小 size: Int) throws -> Data {
    guard size > 0 else { return Data() }
    var output = Data(count: size)
    let written = output.withUnsafeMutableBytes { destination in
        data.withUnsafeBytes { source in
            compression_decode_buffer(
                destination.bindMemory(to: UInt8.self).baseAddress!, size,
                source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                nil, COMPRESSION_ZLIB
            )
        }
    }
    guard written == size else { throw 网页游戏资源错误.格式无效 }
    return output
}

nonisolated extension Data {
    func 小端16(_ offset: Int) -> UInt16 {
        let base = startIndex + offset
        return UInt16(self[base]) | UInt16(self[base + 1]) << 8
    }

    func 小端32(_ offset: Int) -> UInt32 {
        let base = startIndex + offset
        return UInt32(self[base]) | UInt32(self[base + 1]) << 8 | UInt32(self[base + 2]) << 16 | UInt32(self[base + 3]) << 24
    }
}
