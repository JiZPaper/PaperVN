import Foundation
import KiriKiri

/// 电脑版的 Ren'Py 游戏没有网页入口。这里把 Ren'Py 官方的 WebAssembly 运行库当页面，
/// 把游戏的 game 文件夹挂进它的虚拟文件系统：文件只在读到时才通过同步请求按块取，不用像官方网页版那样把整个游戏读进内存。
/// 运行库里的 game.zip 只有 SDK 的 main.py 和 renpy 文件夹（官方打包时也是这样放，.py 换成 .pyc），不含游戏内容。
nonisolated final class RenPy原生读取器: 网页游戏资源读取器, @unchecked Sendable {
    private let 运行库: URL
    private let 游戏目录: URL
    private let 文件表: Data
    private let 页面: Data
    private static let 游戏前缀 = "__papervn/game/"
    private static let 块前缀 = "__papervn/chunk/"

    enum 错误: LocalizedError {
        case 缺少game文件夹
        var errorDescription: String? { String(localized: "找不到“game”文件夹。") }
    }

    init(游戏根目录 root: URL) throws {
        运行库 = 视觉小说运行资源.RenPy运行库
        let manager = FileManager.default
        guard let name = try manager.contentsOfDirectory(atPath: root.path).first(where: { $0.lowercased() == "game" }) else {
            throw 错误.缺少game文件夹
        }
        游戏目录 = root.appending(path: name, directoryHint: .isDirectory)

        // 文件清单。saves、cache 是电脑上运行时产生的，不带进去
        var list: [[String: Any]] = []
        let base = 游戏目录.standardizedFileURL.path
        if let walker = manager.enumerator(at: 游戏目录, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            for case let url as URL in walker {
                var relative = url.standardizedFileURL.path
                guard relative.hasPrefix(base) else { continue }
                relative.removeFirst(base.count)
                while relative.hasPrefix("/") { relative.removeFirst() }
                let lower = relative.lowercased()
                if lower == "saves" || lower == "cache" {
                    walker.skipDescendants()
                    continue
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
                list.append(["p": relative, "s": size])
            }
        }
        文件表 = try JSONSerialization.data(withJSONObject: list)

        // 在官方脚本前插入挂载脚本
        var html = try String(contentsOf: 运行库.appending(path: "index.html"), encoding: .utf8)
        let marker = "<script src=\"renpy-pre.js\"></script>"
        guard html.contains(marker) else { throw 错误.缺少game文件夹 }
        // 官方页面左上角的菜单是导入、导出存档用的，App 里用不了
        html = html.replacingOccurrences(of: marker, with: "<style>#ContextContainer{display:none!important}</style>\n  <script>\(Self.挂载脚本)</script>\n  \(marker)")
        页面 = Data(html.utf8)
    }

    private func 游戏文件(_ path: String) -> URL? {
        var relative = String(path.dropFirst(Self.游戏前缀.count))
        relative = relative.removingPercentEncoding ?? relative
        guard !relative.split(separator: "/").contains("..") else { return nil }
        return 游戏目录.appending(path: relative)
    }

    /// `__papervn/chunk/起点/长度/相对路径`：Base64 编码的一段文件。
    /// 主线程上的同步 XHR 不能要二进制，WebKit 也不认 x-user-defined，只能走文本。
    private func 解析块(_ path: String) -> (url: URL, start: UInt64, length: UInt64)? {
        guard path.hasPrefix(Self.块前缀) else { return nil }
        let parts = path.dropFirst(Self.块前缀.count).split(separator: "/", maxSplits: 2).map(String.init)
        guard parts.count == 3, let start = UInt64(parts[0]), let length = UInt64(parts[1]),
              let url = 游戏文件(Self.游戏前缀 + parts[2]) else { return nil }
        return (url, start, length)
    }

    func 大小(_ path: String) -> UInt64? {
        switch path {
        case "index.html": return UInt64(页面.count)
        case "__papervn/files.json": return UInt64(文件表.count)
        default: break
        }
        if let chunk = 解析块(path) {
            guard let size = try? chunk.url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
            let total = UInt64(size), available = chunk.start < total ? min(chunk.length, total - chunk.start) : 0
            return (available + 2) / 3 * 4
        }
        let url = path.hasPrefix(Self.游戏前缀) ? 游戏文件(path) : 运行库.appending(path: path)
        guard let url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        return UInt64(size)
    }

    func 读取(_ path: String, 范围 range: Range<UInt64>?) throws -> Data {
        func slice(_ data: Data) -> Data {
            guard let range else { return data }
            return data.subdata(in: Int(range.lowerBound)..<min(Int(range.upperBound), data.count))
        }
        switch path {
        case "index.html": return slice(页面)
        case "__papervn/files.json": return slice(文件表)
        default: break
        }
        if let chunk = 解析块(path) {
            let handle = try FileHandle(forReadingFrom: chunk.url)
            defer { try? handle.close() }
            try handle.seek(toOffset: chunk.start)
            let data = try handle.read(upToCount: Int(chunk.length)) ?? Data()
            return slice(data.base64EncodedData())
        }
        guard let url = path.hasPrefix(Self.游戏前缀) ? 游戏文件(path) : 运行库.appending(path: path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if let range {
            try handle.seek(toOffset: range.lowerBound)
            return try handle.read(upToCount: Int(range.upperBound - range.lowerBound)) ?? Data()
        }
        return try handle.readToEnd() ?? Data()
    }

    /// 在 preRun 里把 game 文件夹挂到虚拟文件系统的 /game。
    /// Emscripten 自带的懒加载文件只能用在 Worker 里，主线程要自己写：同步请求按块取 Base64。
    private static let 挂载脚本 = #"""
    window.Module = window.Module || {};
    Module.preRun = Module.preRun || [];
    (function () {
      var CHUNK = 256 * 1024, MAX_CHUNKS = 128, cache = new Map();
      function readChunk(url, index, size) {
        var key = url + '#' + index, data = cache.get(key);
        if (data) { cache.delete(key); cache.set(key, data); return data; }
        var start = index * CHUNK, end = Math.min(start + CHUNK, size) - 1;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', '__papervn/chunk/' + start + '/' + (end - start + 1) + '/' + url, false);
        xhr.send(null);
        var text = atob(xhr.responseText), n = text.length;
        data = new Uint8Array(n);
        for (var i = 0; i < n; i++) data[i] = text.charCodeAt(i);
        cache.set(key, data);
        if (cache.size > MAX_CHUNKS) cache.delete(cache.keys().next().value);
        return data;
      }
      function addFile(path, size) {
        var slash = path.lastIndexOf('/');
        var dir = '/game' + (slash >= 0 ? '/' + path.substring(0, slash) : '');
        FS.createPath('/', dir.substring(1), true, true);
        var node = FS.createFile(dir, path.substring(slash + 1), {}, true, false);
        var url = path.split('/').map(encodeURIComponent).join('/');
        node.contents = null;
        Object.defineProperty(node, 'usedBytes', { get: function () { return size; } });
        var ops = Object.assign({}, node.stream_ops);
        ops.read = function (stream, buffer, offset, length, position) {
          if (position >= size) return 0;
          var total = Math.min(length, size - position), done = 0;
          while (done < total) {
            var at = position + done, index = Math.floor(at / CHUNK);
            var chunk = readChunk(url, index, size), inner = at - index * CHUNK;
            var count = Math.min(total - done, chunk.length - inner);
            if (count <= 0) break;
            buffer.set(chunk.subarray(inner, inner + count), offset + done);
            done += count;
          }
          return done;
        };
        ops.write = function () { throw new FS.ErrnoError(63); };
        ops.mmap = function (stream, length, position, prot, flags) {
          var ptr = _malloc(length);
          ops.read(stream, HEAP8, ptr, length, position);
          return { ptr: ptr, allocated: true };
        };
        node.stream_ops = ops;
      }
      Module.preRun.push(function () {
        Module.addRunDependency('papervnMount');
        fetch('__papervn/files.json').then(function (r) { return r.json(); }).then(function (list) {
          list.forEach(function (f) { addFile(f.p, f.s); });
          Module.removeRunDependency('papervnMount');
        });
      });
    })();
    """#
}
