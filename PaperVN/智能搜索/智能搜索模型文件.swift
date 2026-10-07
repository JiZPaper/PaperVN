import Foundation

nonisolated enum 智能搜索模型存储 {
    static let 文件名 = "PaperVNSmartSearch.pvss"
    static let 下载地址 = URL(
        string: "https://r2-papervn.jizpaper.com/Resources/PaperVNSmartSearch.pvss"
    )!

    static var 目录: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
            .appendingPathComponent("PaperVNSmartSearch", isDirectory: true)
    }

    /// 下载的模型更新。
    static var 下载URL: URL {
        目录.appendingPathComponent(文件名)
    }

    /// App 安装包里预装的模型。
    static var 内置URL: URL? {
        Bundle.main.url(forResource: "PaperVNSmartSearch", withExtension: "pvss")
    }

    /// 当前使用的模型：下载的更新和内置的不是同一版、且不比内置的旧时用下载的，否则用内置的。
    static var 当前URL: URL? {
        let 内置 = 内置URL.flatMap { url in 读取标识(url).map { (url, $0) } }
        guard let 下载 = 读取标识(下载URL) else { return 内置?.0 }
        guard let 内置 else { return 下载URL }
        return 下载 == 内置.1 || 日期(下载) < 日期(内置.1) ? 内置.0 : 下载URL
    }

    /// 有可以使用的模型（内置的或下载的）。
    static var 已安装: Bool {
        当前URL != nil
    }

    /// 下载的更新存在并且正在使用。
    static var 已下载更新: Bool {
        当前URL == 下载URL
    }

    /// 下载的文件不再使用时删除：App 更新后内置的模型和它一样新或更新，或者是旧格式的文件。
    static func 清理过期的下载() {
        guard FileManager.default.fileExists(atPath: 下载URL.path), !已下载更新 else { return }
        try? 删除()
    }

    /// 读取模型标识（如 "20261007-1c066ae53088"）；不是当前格式的文件返回 nil。
    static func 读取标识(_ url: URL) -> String? {
        guard let 句柄 = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? 句柄.close() }
        guard let 开头 = try? 句柄.read(upToCount: 65_536) else { return nil }
        return try? 智能搜索模型文件.读取头(开头).modelIdentifier
    }

    /// 模型标识开头是构建日期，用来比较新旧；同一天构建的视为一样新。
    private static func 日期(_ 标识: String) -> Substring {
        标识.prefix { $0 != "-" }
    }

    static var 已下载文件大小: Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: 目录,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey]
            ), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    static func 创建目录() throws {
        var directory = 目录
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
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

nonisolated enum 智能搜索模型错误: LocalizedError {
    case 文件无效
    case 缺少数据(String)
    case 服务器响应无效

    var errorDescription: String? {
        switch self {
        case .文件无效, .缺少数据:
            return String(localized: "Hiro智能模型文件已损坏，请重新下载。")
        case .服务器响应无效:
            return String(localized: "无法从服务器下载Hiro智能模型。")
        }
    }
}

/// 以只读方式映射整个文件；索引数据直接从映射内存读取，不复制进内存。
nonisolated final class 只读映射文件: @unchecked Sendable {
    let 起点: UnsafeRawPointer
    let 长度: Int

    init(url: URL) throws {
        let 描述符 = open(url.path, O_RDONLY)
        guard 描述符 >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        defer { close(描述符) }
        var 状态 = stat()
        guard fstat(描述符, &状态) == 0, 状态.st_size > 0 else {
            throw 智能搜索模型错误.文件无效
        }
        长度 = Int(状态.st_size)
        let 地址 = mmap(nil, 长度, PROT_READ, MAP_PRIVATE, 描述符, 0)
        guard let 地址, 地址 != MAP_FAILED else {
            throw 智能搜索模型错误.文件无效
        }
        起点 = UnsafeRawPointer(地址)
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: 起点), 长度)
    }
}


/// `Tools/智能搜索模型/模糊.py` 生成的模型文件：
/// "PVSS" | 格式版本 UInt32 | 头长度 UInt32 | 头 JSON | 各段数据（16 字节对齐，小端序）。
nonisolated struct 智能搜索模型文件: @unchecked Sendable {
    /// 2：纯名称模糊匹配（名称索引 + 排序器），不再包含查询编码器。
    static let 支持的格式版本: UInt32 = 2

    nonisolated struct 段: Decodable, Sendable {
        let offset: Int
        let length: Int
    }

    nonisolated struct 头信息: Decodable, Sendable {
        let formatVersion: Int
        let modelIdentifier: String
        let visualNovelCount: Int
        let characterCount: Int
        let producerCount: Int
        let staffCount: Int
        let nameCount: Int
        let gramCount: Int
        let maxIDF: Double
        let nameCandidateCount: Int
        let coverageCandidateCount: Int
        let queryUnigramMaxHan: Int
        let sections: [String: 段]
    }

    let 头: 头信息
    let 文件: 只读映射文件

    init(url: URL) throws {
        let 文件 = try 只读映射文件(url: url)
        let 头数据 = Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: 文件.起点),
            count: min(文件.长度, 65_536),
            deallocator: .none
        )
        头 = try Self.读取头(头数据)
        self.文件 = 文件
    }

    static func 读取格式版本(_ 数据: Data) throws -> UInt32 {
        guard 数据.count >= 12,
              数据.prefix(4) == Data("PVSS".utf8) else {
            throw 智能搜索模型错误.文件无效
        }
        return 数据.读取UInt32小端(偏移: 4)
    }

    /// 只需要文件开头（不超过 64 KB）就能读出头信息，用于比较服务器上的版本。
    static func 读取头(_ 数据: Data) throws -> 头信息 {
        let 版本 = try 读取格式版本(数据)
        let 头长度 = Int(数据.读取UInt32小端(偏移: 8))
        guard 版本 == 支持的格式版本, 数据.count >= 12 + 头长度 else {
            throw 智能搜索模型错误.文件无效
        }
        let 起点 = 数据.startIndex + 12
        return try JSONDecoder().decode(
            头信息.self,
            from: 数据[起点..<(起点 + 头长度)]
        )
    }

    func 原始段(_ 名称: String) throws -> UnsafeRawBufferPointer {
        guard let 段 = 头.sections[名称],
              段.offset >= 0,
              段.offset + 段.length <= 文件.长度 else {
            throw 智能搜索模型错误.缺少数据(名称)
        }
        return UnsafeRawBufferPointer(start: 文件.起点 + 段.offset, count: 段.length)
    }

    func 数组段<元素>(_ 名称: String, 类型: 元素.Type) throws -> UnsafeBufferPointer<元素> {
        let 原始 = try 原始段(名称)
        guard 原始.count % MemoryLayout<元素>.stride == 0 else {
            throw 智能搜索模型错误.缺少数据(名称)
        }
        return 原始.bindMemory(to: 元素.self)
    }

    func 数据段(_ 名称: String) throws -> Data {
        Data(try 原始段(名称))
    }
}

private extension Data {
    nonisolated func 读取UInt32小端(偏移: Int) -> UInt32 {
        let 起点 = startIndex + 偏移
        var 值: UInt32 = 0
        for (位置, 字节) in self[起点..<(起点 + 4)].enumerated() {
            值 |= UInt32(字节) << (8 * UInt32(位置))
        }
        return 值
    }
}
