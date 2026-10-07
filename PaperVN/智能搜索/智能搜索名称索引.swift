import Foundation

/// 作品标题、别名和角色名的模糊匹配，与 `Tools/智能搜索模型/名称.py` 逐条对应。
nonisolated struct 智能搜索名称索引: @unchecked Sendable {
    nonisolated struct 匹配特征: Sendable {
        var f: Float = 0
        var 查询覆盖: Float = 0
        var 名称覆盖: Float = 0
        var 完全一致 = false
        var 前缀 = false
        var 包含 = false
        /// 查询长度占 F 值最高的那个名字长度的比例。
        var 长度比: Float = 0
    }

    nonisolated struct 查询: Sendable {
        let 规范文本: [Unicode.Scalar]
        let 查询权重: Float
        /// 每个名称与查询重合的 IDF 权重；没有命中的名称为 0。
        let 重合: [Float]
        let 命中名称: [Int32]
    }

    private static let 未知片段: UInt64 = (1 << 21) - 1
    private static let 长音替换: [([Unicode.Scalar], [Unicode.Scalar])] = [
        (["o", "u"], ["o"]), (["o", "o"], ["o"]), (["u", "u"], ["u"]),
        (["a", "a"], ["a"]), (["i", "i"], ["i"]), (["e", "e"], ["e"]),
    ]

    private let 变音映射: [Unicode.Scalar: [Unicode.Scalar]]
    private let 名称字节: UnsafeRawBufferPointer
    private let 名称偏移: UnsafeBufferPointer<UInt32>
    private let 名称所属: UnsafeBufferPointer<UInt32>
    private let 名称权重: UnsafeBufferPointer<Float>
    private let 文档名称起点: UnsafeBufferPointer<UInt32>
    private let 片段键: UnsafeBufferPointer<UInt64>
    private let 片段起点: UnsafeBufferPointer<UInt32>
    private let 倒排: UnsafeBufferPointer<UInt32>
    private let idf: UnsafeBufferPointer<Float>
    private let 最大idf: Float
    /// 查询里的汉字不超过这个数时才加单字片段（与 `名称.查询单字最多汉字数` 一致）。
    private let 查询单字最多汉字数: Int

    var 名称数量: Int { 名称权重.count }

    init(文件: 智能搜索模型文件) throws {
        let 映射 = try JSONSerialization.jsonObject(
            with: try 文件.数据段("latinFold")
        ) as? [String: String] ?? [:]
        var 变音映射: [Unicode.Scalar: [Unicode.Scalar]] = [:]
        for (键, 值) in 映射 {
            if let 字 = 键.unicodeScalars.first, 键.unicodeScalars.count == 1 {
                变音映射[字] = Array(值.unicodeScalars)
            }
        }
        self.变音映射 = 变音映射
        名称字节 = try 文件.原始段("names/strings")
        名称偏移 = try 文件.数组段("names/offsets", 类型: UInt32.self)
        名称所属 = try 文件.数组段("names/docs", 类型: UInt32.self)
        名称权重 = try 文件.数组段("names/weights", 类型: Float.self)
        文档名称起点 = try 文件.数组段("names/docStarts", 类型: UInt32.self)
        片段键 = try 文件.数组段("grams/keys", 类型: UInt64.self)
        片段起点 = try 文件.数组段("grams/starts", 类型: UInt32.self)
        倒排 = try 文件.数组段("grams/postings", 类型: UInt32.self)
        idf = try 文件.数组段("grams/idf", 类型: Float.self)
        最大idf = Float(文件.头.maxIDF)
        查询单字最多汉字数 = 文件.头.queryUnigramMaxHan
        guard 名称偏移.count == 名称权重.count + 1,
              名称所属.count == 名称权重.count,
              片段起点.count == 片段键.count + 1,
              idf.count == 片段键.count else {
            throw 智能搜索模型错误.缺少数据("names")
        }
    }

    // MARK: 规范化

    func 规范化(_ 文本: String) -> [Unicode.Scalar] {
        Self.规范化(文本, 变音映射: 变音映射)
    }

    static func 规范化(
        _ 文本: String,
        变音映射: [Unicode.Scalar: [Unicode.Scalar]]
    ) -> [Unicode.Scalar] {
        var 结果: [Unicode.Scalar] = []
        for 标量 in 文本.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
            for var 字 in 变音映射[标量] ?? [标量] {
                if (0x30A1...0x30F6).contains(字.value) {
                    字 = Unicode.Scalar(字.value - 0x60)!
                } else if 字 == "ー" {
                    continue
                }
                switch 字.properties.generalCategory {
                case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                     .modifierLetter, .otherLetter,
                     .decimalNumber, .letterNumber, .otherNumber:
                    结果.append(字)
                default:
                    continue
                }
            }
        }
        结果 = 折叠oh(结果)
        for (旧, 新) in 长音替换 {
            结果 = 替换(结果, 旧, 新)
        }
        return 结果
    }

    /// 等价于正则 `oh(?![aeiou])` → `o`。
    private static func 折叠oh(_ 字: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var 结果: [Unicode.Scalar] = []
        结果.reserveCapacity(字.count)
        var i = 0
        while i < 字.count {
            if 字[i] == "o", i + 1 < 字.count, 字[i + 1] == "h",
               i + 2 == 字.count || !"aeiou".unicodeScalars.contains(字[i + 2]) {
                结果.append("o")
                i += 2
            } else {
                结果.append(字[i])
                i += 1
            }
        }
        return 结果
    }

    private static func 替换(
        _ 字: [Unicode.Scalar],
        _ 旧: [Unicode.Scalar],
        _ 新: [Unicode.Scalar]
    ) -> [Unicode.Scalar] {
        var 结果: [Unicode.Scalar] = []
        结果.reserveCapacity(字.count)
        var i = 0
        while i < 字.count {
            if i + 旧.count <= 字.count, Array(字[i..<(i + 旧.count)]) == 旧 {
                结果.append(contentsOf: 新)
                i += 旧.count
            } else {
                结果.append(字[i])
                i += 1
            }
        }
        return 结果
    }


    private static func 是汉字(_ 字: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(字.value)
    }

    private static func 片段(_ 字: [Unicode.Scalar], 含单字: Bool = true) -> [UInt64] {
        guard !字.isEmpty else { return [] }
        guard 字.count > 1 else {
            return [UInt64(字[0].value) << 21 | 未知片段]
        }
        var 已有 = Set<UInt64>()
        var 结果: [UInt64] = []
        for i in 0..<(字.count - 1) {
            let 键 = UInt64(字[i].value) << 21 | UInt64(字[i + 1].value)
            if 已有.insert(键).inserted { 结果.append(键) }
        }
        // 汉字另外加上单字片段，让错一个字或调换两个字的中文名仍能匹配（与 `名称.片段键` 一致）。
        guard 含单字 else { return 结果 }
        for 单字 in 字 where 是汉字(单字) {
            let 键 = UInt64(单字.value) << 21 | 未知片段
            if 已有.insert(键).inserted { 结果.append(键) }
        }
        return 结果
    }

    // MARK: 检索

    func 准备查询(_ 文本: String) -> 查询 {
        let 规范 = 规范化(文本)
        var 查询权重: Float = 0
        var 重合 = [Float](repeating: 0, count: 名称数量)
        var 命中: [Int32] = []
        let 含单字 = 规范.filter(Self.是汉字).count <= 查询单字最多汉字数
        for 键 in Self.片段(规范, 含单字: 含单字) {
            guard let 位置 = 查找片段(键) else {
                查询权重 += 最大idf
                continue
            }
            let 权重 = idf[位置]
            查询权重 += 权重
            for k in Int(片段起点[位置])..<Int(片段起点[位置 + 1]) {
                let 名称 = Int(倒排[k])
                if 重合[名称] == 0 { 命中.append(Int32(名称)) }
                重合[名称] += 权重
            }
        }
        return 查询(规范文本: 规范, 查询权重: 查询权重, 重合: 重合, 命中名称: 命中.sorted())
    }

    private func 查找片段(_ 键: UInt64) -> Int? {
        var 低 = 0
        var 高 = 片段键.count
        while 低 < 高 {
            let 中 = (低 + 高) / 2
            if 片段键[中] < 键 { 低 = 中 + 1 } else { 高 = 中 }
        }
        return 低 < 片段键.count && 片段键[低] == 键 ? 低 : nil
    }

    /// 候选文档：先按名称 F 值取前 `名称数量` 个不同文档；再在“查询的所有片段都出现在名字里”的名字中
    /// 按热度补上 `覆盖数量` 个，否则只输开头几个字时，长标题的热门作品会被一堆短名字挤出候选。
    /// 与 `模糊.特征计算.候选` 一致。
    func 候选文档(_ 查询: 查询, 名称数量: Int, 覆盖数量: Int, 先验: UnsafeBufferPointer<Float>) -> [Int] {
        guard 查询.查询权重 > 0 else { return [] }
        let 排序后 = 查询.命中名称.map { 名称 -> (Int32, Float) in
            let i = Int(名称)
            return (名称, 2 * 查询.重合[i] / (查询.查询权重 + 名称权重[i]))
        }
        .enumerated()
        .sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }
        var 结果: [Int] = []
        var 已有 = Set<Int>()
        for (_, (名称, _)) in 排序后 {
            let 文档 = Int(名称所属[Int(名称)])
            if 已有.insert(文档).inserted {
                结果.append(文档)
                if 结果.count >= 名称数量 { break }
            }
        }
        // 全覆盖的名字（命中名称已按下标升序），按文档去重后按热度从高到低
        var 覆盖文档 = Set<Int>()
        for 名称 in 查询.命中名称 where 查询.重合[Int(名称)] >= 查询.查询权重 - 1e-4 {
            覆盖文档.insert(Int(名称所属[Int(名称)]))
        }
        let 热门 = 覆盖文档.sorted { 先验[$0] != 先验[$1] ? 先验[$0] > 先验[$1] : $0 < $1 }
        var 加入 = 0
        for 文档 in 热门 where 已有.insert(文档).inserted {
            结果.append(文档)
            加入 += 1
            if 加入 >= 覆盖数量 { break }
        }
        return 结果
    }

    func 特征(_ 查询: 查询, 文档: Int) -> 匹配特征 {
        let 起 = Int(文档名称起点[文档])
        let 止 = Int(文档名称起点[文档 + 1])
        guard 止 > 起, 查询.查询权重 > 0 else { return 匹配特征() }
        var 最佳 = 起
        var 最佳f: Float = -1
        for i in 起..<止 {
            let f = 2 * 查询.重合[i] / (查询.查询权重 + 名称权重[i])
            if f > 最佳f {
                最佳f = f
                最佳 = i
            }
        }
        var 结果 = 匹配特征(
            f: 最佳f,
            查询覆盖: 查询.重合[最佳] / 查询.查询权重,
            名称覆盖: 查询.重合[最佳] / max(名称权重[最佳], 1e-6),
            长度比: min(1, Float(查询.规范文本.count) / Float(max(名称(最佳).count, 1)))
        )
        let q = 查询.规范文本
        for i in 起..<止 {
            let 名 = 名称(i)
            if 名 == q { 结果.完全一致 = true }
            if q.count >= 2, 名.starts(with: q) { 结果.前缀 = true }
            if (q.count >= 2 && Self.包含(名, q)) || (名.count >= 3 && Self.包含(q, 名)) {
                结果.包含 = true
            }
        }
        return 结果
    }

    private func 名称(_ i: Int) -> [Unicode.Scalar] {
        let 起 = Int(名称偏移[i])
        let 止 = Int(名称偏移[i + 1])
        let 字节 = UnsafeRawBufferPointer(rebasing: 名称字节[起..<止])
        return Array(String(decoding: 字节, as: UTF8.self).unicodeScalars)
    }

    private static func 包含(_ 全文: [Unicode.Scalar], _ 片段: [Unicode.Scalar]) -> Bool {
        guard !片段.isEmpty, 片段.count <= 全文.count else { return 片段.isEmpty }
        for 起点 in 0...(全文.count - 片段.count) where 全文[起点] == 片段[0] {
            if 全文[起点..<(起点 + 片段.count)].elementsEqual(片段) { return true }
        }
        return false
    }
}
