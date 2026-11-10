import Foundation

/// 作品标题、别名和角色名的模糊匹配。规范化、片段和读音规则必须和生成模型时的完全一致，否则模型在 App 里会失效。
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
        /// 读音 F 值（各名字中最高的）。
        var 读音f: Float = 0
        /// 和各名字（以及名字开头同样长的部分）的编辑距离相似度，取最高的。
        var 编辑相似: Float = 0
        var 开头编辑相似: Float = 0
        /// F 值最高的那个名字的标记（第 0 位：补充的叫法；第 1 位：借来的角色名）。
        var 名字标记: UInt8 = 0
        /// F 值最高的那个名字含中日韩文字。
        var 名字中日文 = false
        /// F 值最高的那个名字里有数字。
        var 名字有数字 = false
        /// 某个名字包含查询里的全部数字。
        var 数字对上 = false
        /// 查询和 F 值最高的那个名字都有数字，但没有一个相同。
        var 数字冲突 = false
    }

    nonisolated struct 查询: Sendable {
        let 规范文本: [Unicode.Scalar]
        let 查询权重: Float
        /// 每个名称与查询重合的 IDF 权重；没有命中的名称为 0。
        let 重合: [Float]
        let 命中名称: [Int32]
        /// 查询里的数字（连续的 0～9）。
        let 数字: Set<[Unicode.Scalar]>
        /// 读音太短时不用读音，以下为空、0。
        let 读音权重: Float
        let 读音重合: [Float]
        let 读音命中名称: [Int32]
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
    private let 名称标记: UnsafeBufferPointer<UInt8>

    // 读音（见 `读音(_:)`）
    /// 键：一个字或两个字（第一个字 << 21 | 第二个字，一个字时第二个是 `未知片段`）；值：小写拉丁字母。
    private let 读音表: [UInt64: [UInt8]]
    private let 读音规则: [([UInt8], [UInt8])]
    private let 读音名称权重: UnsafeBufferPointer<Float>
    private let 读音片段键: UnsafeBufferPointer<UInt32>
    private let 读音片段起点: UnsafeBufferPointer<UInt32>
    private let 读音倒排: UnsafeBufferPointer<UInt32>
    private let 读音idf: UnsafeBufferPointer<Float>
    private let 读音最大idf: Float
    private let 读音最短查询: Int
    private static let 读音最长 = 40

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
        名称标记 = try 文件.数组段("names/flags", 类型: UInt8.self)

        struct 读音格式: Decodable {
            let map: [String: String]
            let rules: [[String]]
        }
        let 读音 = try JSONDecoder().decode(读音格式.self, from: try 文件.数据段("phonetic"))
        var 表: [UInt64: [UInt8]] = [:]
        for (键, 值) in 读音.map {
            let 字 = Array(键.unicodeScalars)
            guard (1...2).contains(字.count) else { continue }
            表[Self.读音键(字[0], 字.count == 2 ? 字[1] : nil)] = Array(值.utf8)
        }
        读音表 = 表
        读音规则 = 读音.rules.compactMap { $0.count == 2 ? (Array($0[0].utf8), Array($0[1].utf8)) : nil }
        读音名称权重 = try 文件.数组段("names/phoneticWeights", 类型: Float.self)
        读音片段键 = try 文件.数组段("phoneticGrams/keys", 类型: UInt32.self)
        读音片段起点 = try 文件.数组段("phoneticGrams/starts", 类型: UInt32.self)
        读音倒排 = try 文件.数组段("phoneticGrams/postings", 类型: UInt32.self)
        读音idf = try 文件.数组段("phoneticGrams/idf", 类型: Float.self)
        读音最大idf = Float(文件.头.phoneticMaxIDF)
        读音最短查询 = 文件.头.phoneticMinQueryLength
        guard 名称偏移.count == 名称权重.count + 1,
              名称所属.count == 名称权重.count,
              名称标记.count == 名称权重.count,
              读音名称权重.count == 名称权重.count,
              片段起点.count == 片段键.count + 1,
              idf.count == 片段键.count,
              读音片段起点.count == 读音片段键.count + 1,
              读音idf.count == 读音片段键.count else {
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

    static func 是中日文(_ 字: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(字.value)
            || (0x3400...0x9FFF).contains(字.value)
            || (0xAC00...0xD7A3).contains(字.value)
    }

    /// 连续的 0～9（规范化后全角数字已经变成半角）。
    static func 数字(_ 字: [Unicode.Scalar]) -> [[Unicode.Scalar]] {
        var 结果: [[Unicode.Scalar]] = []
        var 当前: [Unicode.Scalar] = []
        for 单字 in 字 {
            if ("0"..."9").contains(单字) {
                当前.append(单字)
            } else if !当前.isEmpty {
                结果.append(当前)
                当前 = []
            }
        }
        if !当前.isEmpty { 结果.append(当前) }
        return 结果
    }

    // MARK: 读音

    private static func 读音键(_ 第一: Unicode.Scalar, _ 第二: Unicode.Scalar?) -> UInt64 {
        UInt64(第一.value) << 21 | (第二.map { UInt64($0.value) } ?? 未知片段)
    }

    /// 规范化后的文本 → 读音（小写拉丁字母和数字），与 `名称.读音` 一致：
    /// 读音表里的键最长两个字、按最长匹配；汉字的拼音原样接上，假名和拉丁字母的部分套用读音规则；
    /// 表里没有的拉丁字母、数字原样保留，其他字符丢掉；只取前 40 个字。
    func 读音(_ 字: [Unicode.Scalar]) -> [UInt8] {
        var 结果: [UInt8] = []
        var 缓冲: [UInt8] = []
        func 冲刷() {
            guard !缓冲.isEmpty else { return }
            var 文本 = 缓冲
            for (旧, 新) in 读音规则 {
                文本 = Self.替换(文本, 旧, 新)
            }
            结果.append(contentsOf: 文本)
            缓冲.removeAll()
        }
        var i = 0
        while i < 字.count {
            if i + 1 < 字.count, let 音 = 读音表[Self.读音键(字[i], 字[i + 1])] {
                缓冲.append(contentsOf: 音)
                i += 2
                continue
            }
            let 单字 = 字[i]
            i += 1
            if let 音 = 读音表[Self.读音键(单字, nil)] {
                if Self.是汉字(单字) {
                    冲刷()
                    结果.append(contentsOf: 音)
                } else {
                    缓冲.append(contentsOf: 音)
                }
            } else if 单字.isASCII, 单字.properties.isAlphabetic || ("0"..."9").contains(单字) {
                缓冲.append(UInt8(单字.value))
            }
        }
        冲刷()
        return Array(结果.prefix(Self.读音最长))
    }

    private static func 替换(_ 字: [UInt8], _ 旧: [UInt8], _ 新: [UInt8]) -> [UInt8] {
        guard !旧.isEmpty, 字.count >= 旧.count else { return 字 }
        var 结果: [UInt8] = []
        结果.reserveCapacity(字.count)
        var i = 0
        while i < 字.count {
            if i + 旧.count <= 字.count, 字[i..<(i + 旧.count)].elementsEqual(旧) {
                结果.append(contentsOf: 新)
                i += 旧.count
            } else {
                结果.append(字[i])
                i += 1
            }
        }
        return 结果
    }

    /// 读音的三字片段；不到三个字时整段作为一个片段，空位补 0（与 `名称.读音片段键` 一致）。
    private static func 读音片段(_ 音: [UInt8]) -> [UInt32] {
        guard !音.isEmpty else { return [] }
        guard 音.count >= 3 else {
            let 补齐 = 音 + [UInt8](repeating: 0, count: 3 - 音.count)
            return [UInt32(补齐[0]) << 16 | UInt32(补齐[1]) << 8 | UInt32(补齐[2])]
        }
        var 已有 = Set<UInt32>()
        var 结果: [UInt32] = []
        for i in 0..<(音.count - 2) {
            let 键 = UInt32(音[i]) << 16 | UInt32(音[i + 1]) << 8 | UInt32(音[i + 2])
            if 已有.insert(键).inserted { 结果.append(键) }
        }
        return 结果
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
        var 读音权重: Float = 0
        var 读音重合: [Float] = []
        var 读音命中: [Int32] = []
        let 音 = 读音(规范)
        if 音.count >= 读音最短查询 {
            读音重合 = [Float](repeating: 0, count: 名称数量)
            for 键 in Self.读音片段(音) {
                guard let 位置 = 查找读音片段(键) else {
                    读音权重 += 读音最大idf
                    continue
                }
                let 权重 = 读音idf[位置]
                读音权重 += 权重
                for k in Int(读音片段起点[位置])..<Int(读音片段起点[位置 + 1]) {
                    let 名称 = Int(读音倒排[k])
                    if 读音重合[名称] == 0 { 读音命中.append(Int32(名称)) }
                    读音重合[名称] += 权重
                }
            }
        }
        return 查询(
            规范文本: 规范,
            查询权重: 查询权重,
            重合: 重合,
            命中名称: 命中.sorted(),
            数字: Set(Self.数字(规范)),
            读音权重: 读音权重,
            读音重合: 读音重合,
            读音命中名称: 读音命中.sorted()
        )
    }

    private func 查找读音片段(_ 键: UInt32) -> Int? {
        var 低 = 0
        var 高 = 读音片段键.count
        while 低 < 高 {
            let 中 = (低 + 高) / 2
            if 读音片段键[中] < 键 { 低 = 中 + 1 } else { 高 = 中 }
        }
        return 低 < 读音片段键.count && 读音片段键[低] == 键 ? 低 : nil
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
    /// 按热度补上 `覆盖数量` 个，否则只输开头几个字时，长标题的热门作品会被一堆短名字挤出候选；
    /// 最后按读音 F 值补上 `读音数量` 个（同音错字、假名和罗马字写法不同时原文片段对不上）。
    /// 与 `模糊.特征计算.候选` 一致。
    func 候选文档(
        _ 查询: 查询,
        名称数量: Int,
        覆盖数量: Int,
        读音数量: Int,
        先验: UnsafeBufferPointer<Float>
    ) -> [Int] {
        guard 查询.查询权重 > 0 else { return [] }
        var 结果: [Int] = []
        var 已有 = Set<Int>()
        加入前列文档(查询.命中名称, 需要: 名称数量, 已有: &已有, 结果: &结果) { i in
            2 * 查询.重合[i] / (查询.查询权重 + 名称权重[i])
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
        if !查询.读音重合.isEmpty {
            加入前列文档(查询.读音命中名称, 需要: 读音数量, 已有: &已有, 结果: &结果) { i in
                2 * 查询.读音重合[i] / (查询.读音权重 + 读音名称权重[i])
            }
        }
        return 结果
    }

    /// 按（分数从高到低，名称下标从小到大）取名字，依次加入还没有的文档，加够 `需要` 个为止。
    /// 命中的名字可能有几十万个（读音的三字片段很常见），只用堆挑出排在最前面的 m 个，不够再把 m 翻倍；
    /// 结果与全部排序相同。
    private func 加入前列文档(
        _ 命中: [Int32],
        需要: Int,
        已有: inout Set<Int>,
        结果: inout [Int],
        分数: (Int) -> Float
    ) {
        let n = 命中.count
        guard n > 0, 需要 > 0 else { return }
        let 分 = 命中.map { 分数(Int($0)) }
        // a 排在 b 前面（命中名称按下标升序，序号小即下标小）
        func 在前(_ a: Int, _ b: Int) -> Bool {
            分[a] != 分[b] ? 分[a] > 分[b] : a < b
        }
        var m = min(n, 需要 * 8)
        while true {
            var 前列: [Int]
            if m == n {
                前列 = Array(0..<n)
            } else {
                // 堆顶是已选里最靠后的
                var 堆: [Int] = []
                堆.reserveCapacity(m)
                for i in 0..<n {
                    if 堆.count < m {
                        堆.append(i)
                        var 子 = 堆.count - 1
                        while 子 > 0 {
                            let 父 = (子 - 1) / 2
                            guard 在前(堆[父], 堆[子]) else { break }
                            堆.swapAt(父, 子)
                            子 = 父
                        }
                    } else if 在前(i, 堆[0]) {
                        堆[0] = i
                        var 当前 = 0
                        while true {
                            let 左 = 2 * 当前 + 1, 右 = 左 + 1
                            var 最后 = 当前
                            if 左 < 堆.count, 在前(堆[最后], 堆[左]) { 最后 = 左 }
                            if 右 < 堆.count, 在前(堆[最后], 堆[右]) { 最后 = 右 }
                            if 最后 == 当前 { break }
                            堆.swapAt(当前, 最后)
                            当前 = 最后
                        }
                    }
                }
                前列 = 堆
            }
            前列.sort(by: 在前)
            var 加入: [Int] = []
            for i in 前列 {
                let 文档 = Int(名称所属[Int(命中[i])])
                if 已有.insert(文档).inserted {
                    加入.append(文档)
                    if 加入.count >= 需要 { break }
                }
            }
            if 加入.count >= 需要 || m == n {
                结果.append(contentsOf: 加入)
                return
            }
            已有.subtract(加入)
            m = min(n, m * 2)
        }
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
            结果.编辑相似 = max(结果.编辑相似, Self.编辑相似度(q, 名))
            结果.开头编辑相似 = max(结果.开头编辑相似, Self.编辑相似度(q, Array(名.prefix(q.count))))
            if !查询.读音重合.isEmpty {
                结果.读音f = max(结果.读音f, 2 * 查询.读音重合[i] / (查询.读音权重 + 读音名称权重[i]))
            }
            if !查询.数字.isEmpty, 查询.数字.isSubset(of: Set(Self.数字(名))) {
                结果.数字对上 = true
            }
        }
        let 最佳名 = 名称(最佳)
        let 最佳数字 = Set(Self.数字(最佳名))
        结果.名字标记 = 名称标记[最佳]
        结果.名字中日文 = 最佳名.contains(where: Self.是中日文)
        结果.名字有数字 = !最佳数字.isEmpty
        结果.数字冲突 = !查询.数字.isEmpty && !最佳数字.isEmpty && 查询.数字.isDisjoint(with: 最佳数字)
        return 结果
    }

    /// 1 − OSA 距离（相邻两字调换算一次）/ 较长的长度，与 rapidfuzz 的 `OSA.normalized_similarity` 一致。
    static func 编辑相似度(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Float {
        let 最长 = max(a.count, b.count)
        guard 最长 > 0 else { return 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var 前前 = [Int](repeating: 0, count: b.count + 1)
        var 前 = Array(0...b.count)
        var 当前 = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            当前[0] = i
            for j in 1...b.count {
                let 代价 = a[i - 1] == b[j - 1] ? 0 : 1
                var 值 = min(前[j] + 1, 当前[j - 1] + 1, 前[j - 1] + 代价)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    值 = min(值, 前前[j - 2] + 1)
                }
                当前[j] = 值
            }
            (前前, 前, 当前) = (前, 当前, 前前)
        }
        return Float(1 - Double(前[b.count]) / Double(最长))
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
