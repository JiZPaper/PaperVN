import Foundation

public nonisolated enum 智能搜索模型错误: LocalizedError {
    case 文件无效
    case 缺少数据(String)

    public var errorDescription: String? {
        switch self {
        case .文件无效:
            return "Hiro智能模型文件无效或格式版本不受支持。"
        case let .缺少数据(名称):
            return "Hiro智能模型文件缺少数据：\(名称)。"
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

/// Hiro智能的模型文件：
/// "PVSS" | 格式版本 UInt32 | 头长度 UInt32 | 头 JSON | 各段数据（16 字节对齐，小端序）。
public nonisolated struct 智能搜索模型文件: @unchecked Sendable {
    /// 2：纯名称模糊匹配（名称索引 + 排序器），不再包含查询编码器。
    /// 3：加入动画、漫画、轻小说条目（排在制作人员之后，编号是 MAL ID）。
    public static let 支持的格式版本: ClosedRange<UInt32> = 2...3

    public nonisolated struct 段: Decodable, Sendable {
        public let offset: Int
        public let length: Int
    }

    public nonisolated struct 头信息: Decodable, Sendable {
        public let formatVersion: Int
        public let modelIdentifier: String
        public let visualNovelCount: Int
        public let characterCount: Int
        public let producerCount: Int
        public let staffCount: Int
        /// 格式 2 的文件没有这三项。
        public let animeCount: Int?
        public let mangaCount: Int?
        public let lightNovelCount: Int?
        public let nameCount: Int
        public let gramCount: Int
        public let maxIDF: Double
        public let nameCandidateCount: Int
        public let coverageCandidateCount: Int
        public let queryUnigramMaxHan: Int
        public let sections: [String: 段]
    }

    public let 头: 头信息
    let 文件: 只读映射文件

    public init(url: URL) throws {
        let 文件 = try 只读映射文件(url: url)
        let 头数据 = Data(
            bytesNoCopy: UnsafeMutableRawPointer(mutating: 文件.起点),
            count: min(文件.长度, 65_536),
            deallocator: .none
        )
        头 = try Self.读取头(头数据)
        self.文件 = 文件
    }

    public static func 读取格式版本(_ 数据: Data) throws -> UInt32 {
        guard 数据.count >= 12,
              数据.prefix(4) == Data("PVSS".utf8) else {
            throw 智能搜索模型错误.文件无效
        }
        return 数据.读取UInt32小端(偏移: 4)
    }

    /// 只需要文件开头（不超过 64 KB）就能读出头信息，用于比较服务器上的版本。
    public static func 读取头(_ 数据: Data) throws -> 头信息 {
        let 版本 = try 读取格式版本(数据)
        let 头长度 = Int(数据.读取UInt32小端(偏移: 8))
        guard 支持的格式版本.contains(版本), 数据.count >= 12 + 头长度 else {
            throw 智能搜索模型错误.文件无效
        }
        let 起点 = 数据.startIndex + 12
        return try JSONDecoder().decode(
            头信息.self,
            from: 数据[起点..<(起点 + 头长度)]
        )
    }

    /// 读取模型标识（如 "20261007-1c066ae53088"），开头是构建日期；不是支持的格式时返回 nil。
    public static func 读取标识(_ url: URL) -> String? {
        guard let 句柄 = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? 句柄.close() }
        guard let 开头 = try? 句柄.read(upToCount: 65_536) else { return nil }
        return try? 读取头(开头).modelIdentifier
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
