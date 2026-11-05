import Combine
import SwiftUI

// MARK: - 结果结构

/// 一部作品及挂在它下面的内容：同系列的其他作品叠在一起，搜到的角色挂在所属作品下面。
struct 综合作品组: Identifiable, Hashable {
    var 作品: 视觉小说搜索结果
    var 同系列: [视觉小说搜索结果] = []
    var 角色: [角色搜索结果] = []

    var id: String { 作品.id }

    var 全部作品编号: [String] {
        [作品.id] + 同系列.map(\.id)
    }
}

/// 一部动画及同一系列的其他各季：搜索页把它们叠在一起，和视觉小说的系列一样。
struct 动画漫画组: Identifiable, Hashable {
    var 作品: 作品搜索结果
    var 同系列: [作品搜索结果] = []

    var id: String { 作品.id }
}

enum 综合搜索条目: Identifiable, Hashable {
    case 作品(综合作品组)
    /// 找不到所属作品（或所属作品被筛选掉）的角色
    case 角色(角色搜索结果)
    case 制作人员(探索制作人员)
    case 会社(探索会社)
    /// 动画、漫画或轻小说（动画的其他各季叠在下面）
    case 动画漫画(动画漫画组)

    var id: String {
        switch self {
        case let .作品(组): return 组.id
        case let .角色(item): return item.id
        case let .制作人员(item): return item.id
        case let .会社(item): return item.id
        case let .动画漫画(组): return 组.id
        }
    }

    /// 这个条目对应的智能搜索结果编号是否包含 `编号`。
    func 包含(_ 编号: String) -> Bool {
        switch self {
        case let .作品(组):
            return 组.全部作品编号.contains(编号) || 组.角色.contains { $0.id == 编号 }
        case let .动画漫画(组):
            return 组.id == 编号 || 组.同系列.contains { $0.id == 编号 }
        default:
            return id == 编号
        }
    }
}

/// 合并设备端智能搜索和 VNDB 搜索的结果。
///
/// 按相关程度排序时按智能搜索的顺序：它找到的条目在前（按可能性从高到低），VNDB 返回、
/// 智能搜索没找到的条目接在后面（作品、角色、会社、制作人员各自保持 VNDB 的顺序）。
/// 有资料库时，开头有把握的结果之后的部分参考偏好重新排（见 `按偏好调整`）。
/// 其他排序方式只用 VNDB 的作品顺序，角色、会社和制作人员排在作品后面。
///
/// 同系列的作品叠进排在最前面的那部作品；角色挂在所属作品下面，所属作品不在结果里时补上作品。
nonisolated enum 综合搜索合并 {
    struct 输入 {
        var 智能搜索命中: [智能搜索命中] = []
        var 作品: [String: 视觉小说搜索结果] = [:]
        var 角色: [String: 角色搜索结果] = [:]
        var 制作人员: [String: 探索制作人员] = [:]
        var 会社: [String: 探索会社] = [:]
        var VNDB作品顺序: [String] = []
        var VNDB角色顺序: [String] = []
        var VNDB制作人员顺序: [String] = []
        var VNDB会社顺序: [String] = []
        /// 动画、漫画与轻小说（智能搜索模型找到的和各平台搜到的）
        var 动画漫画: [String: 作品搜索结果] = [:]
        /// 各平台按关键词搜到的动画、漫画与轻小说的顺序
        var 在线作品顺序: [String] = []
        /// 作品编号 → 系列编号
        var 作品系列: [String: String] = [:]
        /// 角色编号 → 所属作品编号
        var 角色所属: [String: String] = [:]
        var 按相关程度 = true
        /// 搜索词。只输入了系列名（“lovelive”“fate”）时，这个系列的各部正作按播出顺序排
        var 查询 = ""
        /// 作品编号 → 资料库的偏好分数（每类标准化），见 `作品推荐中心.偏好分数`。没有资料库时为空
        var 偏好: [String: Float] = [:]
        /// 动画编号 → 企划（同一系列的各部作品、外传与改编，见 `作品推荐中心.企划`）
        var 企划: [String: Int32] = [:]
        /// 第一个结果所属企划里没被搜到的正作，和这个企划的其他作品排在一起
        var 企划补充: [String] = []
    }

    private enum 类型 {
        case 作品, 角色, 制作人员, 会社, 动画漫画
    }

    static func 合并(_ 输入: 输入) -> [综合搜索条目] {
        var 顺序: [(类型, String)] = []
        var 已排 = Set<String>()
        func 加入(_ 类型: 类型, _ 编号: String) {
            if 已排.insert(编号).inserted { 顺序.append((类型, 编号)) }
        }
        if 输入.按相关程度 {
            for 命中 in 按偏好调整(输入.智能搜索命中, 输入: 输入) {
                switch 命中.类型 {
                case .视觉小说 where 输入.作品[命中.编号] != nil: 加入(.作品, 命中.编号)
                case .角色 where 输入.角色[命中.编号] != nil: 加入(.角色, 命中.编号)
                case .制作人员 where 输入.制作人员[命中.编号] != nil: 加入(.制作人员, 命中.编号)
                case .会社 where 输入.会社[命中.编号] != nil: 加入(.会社, 命中.编号)
                case .动画 where 输入.动画漫画[命中.编号] != nil,
                     .漫画 where 输入.动画漫画[命中.编号] != nil,
                     .轻小说 where 输入.动画漫画[命中.编号] != nil: 加入(.动画漫画, 命中.编号)
                default: break
                }
            }
            输入.企划补充.filter { 输入.动画漫画[$0] != nil }.forEach { 加入(.动画漫画, $0) }
        }
        if 输入.按相关程度 {
            //智能搜索模型没找到的：VNDB 搜到的视觉小说和各平台搜到的动画、漫画、轻小说交替排列，不分类别
            let 在线 = 输入.在线作品顺序.filter { 输入.动画漫画[$0] != nil }
            for i in 0..<max(输入.VNDB作品顺序.count, 在线.count) {
                if i < 输入.VNDB作品顺序.count { 加入(.作品, 输入.VNDB作品顺序[i]) }
                if i < 在线.count { 加入(.动画漫画, 在线[i]) }
            }
        } else {
            输入.VNDB作品顺序.forEach { 加入(.作品, $0) }
            // 其他排序方式是按视觉小说的字段排的，动画、漫画、轻小说接在视觉小说后面
            输入.在线作品顺序.filter { 输入.动画漫画[$0] != nil }.forEach { 加入(.动画漫画, $0) }
        }
        输入.VNDB角色顺序.forEach { 加入(.角色, $0) }
        输入.VNDB会社顺序.forEach { 加入(.会社, $0) }
        输入.VNDB制作人员顺序.forEach { 加入(.制作人员, $0) }

        var 条目: [综合搜索条目] = []
        // 作品编号 / 系列编号 → 作品组在 条目 中的位置
        var 作品位置: [String: Int] = [:]
        var 系列位置: [String: Int] = [:]

        func 放入作品(_ 作品: 视觉小说搜索结果) -> Int {
            if let 位置 = 作品位置[作品.id] { return 位置 }
            if let 系列 = 输入.作品系列[作品.id], let 位置 = 系列位置[系列],
               case var .作品(组) = 条目[位置] {
                组.同系列.append(作品)
                条目[位置] = .作品(组)
                作品位置[作品.id] = 位置
                return 位置
            }
            条目.append(.作品(综合作品组(作品: 作品)))
            let 位置 = 条目.count - 1
            作品位置[作品.id] = 位置
            if let 系列 = 输入.作品系列[作品.id] {
                系列位置[系列] = 位置
            }
            return 位置
        }

        var 动画系列位置: [String: Int] = [:]
        var 待定角色: [角色搜索结果] = []
        for (类型, 编号) in 顺序 {
            switch 类型 {
            case .作品:
                if let 作品 = 输入.作品[编号] { _ = 放入作品(作品) }
            case .角色:
                guard let 角色 = 输入.角色[编号] else { continue }
                let 所属 = 输入.角色所属[编号] ?? 角色.主要作品编号
                if let 所属, let 作品 = 输入.作品[所属] {
                    // 非相关程度排序时不为角色补作品，避免打乱按字段排好的作品顺序
                    if !输入.按相关程度, 作品位置[所属] == nil {
                        待定角色.append(角色)
                        continue
                    }
                    let 位置 = 放入作品(作品)
                    if case var .作品(组) = 条目[位置] {
                        组.角色.append(角色)
                        条目[位置] = .作品(组)
                    }
                } else if 输入.按相关程度 {
                    条目.append(.角色(角色))
                } else {
                    待定角色.append(角色)
                }
            case .制作人员:
                if let item = 输入.制作人员[编号] { 条目.append(.制作人员(item)) }
            case .会社:
                if let item = 输入.会社[编号] { 条目.append(.会社(item)) }
            case .动画漫画:
                guard let item = 输入.动画漫画[编号] else { continue }
                // 同一系列的动画（各季、续篇）叠进排在最前面的那部
                let 系列 = item.类型 == .anime ? 作品映射.系列(item.作品键, 类型: .anime) : nil
                if let 系列, let 位置 = 动画系列位置[系列], case var .动画漫画(组) = 条目[位置] {
                    组.同系列.append(item)
                    条目[位置] = .动画漫画(组)
                } else {
                    条目.append(.动画漫画(动画漫画组(作品: item)))
                    if let 系列 { 动画系列位置[系列] = 条目.count - 1 }
                }
            }
        }
        // 叠在下面的同系列动画按播出顺序排（年份，同年按编号），不按搜索的可能性
        for (位置, 项) in 条目.enumerated() {
            guard case var .动画漫画(组) = 项, 组.同系列.count > 1 else { continue }
            组.同系列.sort { ($0.年份 ?? .max, $0.malID) < ($1.年份 ?? .max, $1.malID) }
            条目[位置] = .动画漫画(组)
        }
        if 输入.按相关程度 { 按企划整理(&条目, 输入: 输入) }
        if !待定角色.isEmpty {
            // 非相关程度排序：角色紧跟在作品之后，再是会社和制作人员
            let 首个非作品 = 条目.firstIndex {
                if case .作品 = $0 { return false }
                return true
            } ?? 条目.count
            条目.insert(contentsOf: 待定角色.map { .角色($0) }, at: 首个非作品)
        }
        return 条目
    }
}

nonisolated extension 综合搜索合并 {
    /// 智能搜索的概率不低于这个值的开头几个结果是有把握的（“命运石之门”“冰菓”），位置不变。
    static let 有把握概率: Float = 0.15
    /// 其余结果按 log(概率) + 偏好权重 × 偏好分数 排：偏好差一个标准差相当于概率差 e^0.5 ≈ 1.6 倍。
    /// 偏好分数限制在 ±偏好上限 以内（热门作品的分数常常超过 10），最多相当于概率差 e^2 ≈ 7 倍，
    /// 只在可能性相近的结果之间起作用。
    static let 偏好权重: Float = 0.5
    static let 偏好上限: Float = 2

    /// 开头有把握的结果不动；其余结果（“Fate”“高达”这类搜索词的大部分结果）参考资料库的偏好重新排。
    /// 同一组（同一系列的作品、角色和所属作品）一起移动，组内保持原来的先后，叠放和系列内的排序规则不变。
    static func 按偏好调整(_ 命中: [智能搜索命中], 输入: 输入) -> [智能搜索命中] {
        guard !输入.偏好.isEmpty else { return 命中 }
        let 开头 = 命中.prefix { $0.概率 >= 有把握概率 }.count
        guard 命中.count - 开头 > 1 else { return 命中 }
        func 作品编号(_ 项: 智能搜索命中) -> String {
            guard 项.类型 == .角色 else { return 项.编号 }
            return 输入.角色所属[项.编号] ?? 输入.角色[项.编号]?.主要作品编号 ?? 项.编号
        }
        func 组(_ 项: 智能搜索命中) -> String {
            let 编号 = 作品编号(项)
            if let 系列 = 输入.作品系列[编号] { return "v:\(系列)" }
            if let item = 输入.动画漫画[编号], item.类型 == .anime,
               let 系列 = 作品映射.系列(item.作品键, 类型: .anime) { return "a:\(系列)" }
            return 编号
        }
        func 分数(_ 项: 智能搜索命中) -> Float {
            let 偏好 = min(max(输入.偏好[作品编号(项)] ?? 0, -偏好上限), 偏好上限)
            return log(max(项.概率 * 智能搜索引擎.类型权重(项.类型), 1e-6)) + 偏好权重 * 偏好
        }
        var 组顺序: [String] = []
        var 成员: [String: [智能搜索命中]] = [:]
        var 最高: [String: Float] = [:]
        for 项 in 命中[开头...] {
            let 键 = 组(项)
            if 成员[键] == nil { 组顺序.append(键) }
            成员[键, default: []].append(项)
            最高[键] = max(最高[键] ?? -.infinity, 分数(项))
        }
        let 排好 = 组顺序.enumerated().sorted { a, b in
            let (分a, 分b) = (最高[a.element] ?? 0, 最高[b.element] ?? 0)
            return 分a != 分b ? 分a > 分b : a.offset < b.offset
        }
        return Array(命中[..<开头]) + 排好.flatMap { 成员[$0.element] ?? [] }
    }

    /// 搜索词明确指的是哪一部（“lovelive sunshine”）的可能性：第一部的概率不低于这个值、搜索词又不只是系列名时，它留在最前面。
    static let 点名概率: Float = 0.5

    /// 排在最前面的动画所属的企划（“ll”“偶像大师”“Fate”）：这个企划的动画连在一起，放在第一部的位置，
    /// 各部正作按播出顺序（每组取最早的年份，同年按编号），单独的 OVA、剧场版、特别篇接在后面（保持原来的先后）。
    /// 企划来自推荐模型；不在模型里的作品，标题以搜索词为开头完整词的（“lovelive”对上 LoveLive! 各部）也算同一企划。
    /// 只排动画：漫画、轻小说和改编动画混在一起按年份排会把动画挤到后面。
    static func 按企划整理(_ 条目: inout [综合搜索条目], 输入: 输入) {
        let 查询键 = 名称键(输入.查询)
        func 动画组(_ 项: 综合搜索条目) -> 动画漫画组? {
            guard case let .动画漫画(组) = 项, 组.作品.类型 == .anime else { return nil }
            return 组
        }
        func 企划(_ 组: 动画漫画组) -> Int32? {
            ([组.作品] + 组.同系列).lazy.compactMap { 输入.企划[$0.id] }.first
        }
        func 标题对上(_ 组: 动画漫画组) -> Bool {
            查询键.count >= 3 && ([组.作品] + 组.同系列).contains { 标题开头是(查询键, $0) }
        }
        guard let 首 = 条目.firstIndex(where: { 动画组($0) != nil }), let 首组 = 动画组(条目[首]) else { return }
        let 目标 = 企划(首组)
        var 成员: [(序号: Int, 组: 动画漫画组)] = []
        for (序号, 项) in 条目.enumerated() {
            guard let 组 = 动画组(项) else { continue }
            if (目标 != nil && 企划(组) == 目标) || (标题对上(组) && 标题对上(首组)) {
                成员.append((序号, 组))
            }
        }
        guard 成员.count >= 2 else { return }
        // 搜索词只是系列名（几部正作的标题都以它开头）时不算指明了哪一部
        let 只是系列名 = 成员.filter { 是正作($0.组) && 标题对上($0.组) }.count >= 2
        let 首编号 = Set(([首组.作品] + 首组.同系列).map(\.id))
        let 首概率 = 输入.智能搜索命中.filter { 首编号.contains($0.编号) }.map(\.概率).max() ?? 0
        let 点名 = !只是系列名 && 首概率 >= 点名概率
        func 顺序(_ 组: 动画漫画组) -> (Int, Int) {
            ([组.作品] + 组.同系列).map { ($0.年份 ?? .max, $0.malID) }.min { $0 < $1 } ?? (.max, .max)
        }
        let 其余 = 点名 ? Array(成员.dropFirst()) : 成员
        let 正作 = 其余.enumerated().filter { 是正作($0.element.组) }.sorted {
            let (a, b) = (顺序($0.element.组), 顺序($1.element.组))
            return (a.0, a.1, $0.offset) < (b.0, b.1, $1.offset)
        }.map(\.element.组)
        let 其他 = 其余.filter { !是正作($0.组) }.map(\.组)
        let 排好 = (点名 ? [成员[0].组] : []) + 正作 + 其他
        let 位置 = Set(成员.map(\.序号))
        var 结果: [综合搜索条目] = []
        for (序号, 项) in 条目.enumerated() {
            if 序号 == 成员[0].序号 {
                结果 += 排好.map { .动画漫画($0) }
            } else if !位置.contains(序号) {
                结果.append(项)
            }
        }
        条目 = 结果
    }

    /// 系列的正作：叠着好几季的，或者单独一部 TV、网络动画。单独的 OVA、剧场版、特别篇、演唱会不算
    static func 是正作(_ 组: 动画漫画组) -> Bool {
        if !组.同系列.isEmpty { return true }
        guard let 格式 = 组.作品.格式?.uppercased() else { return true }
        return 格式.hasPrefix("TV") || 格式 == "ONA" || 格式 == "WEB"
    }

    /// 某个标题以搜索词为开头的完整词：标题在空格或标点处切开的各个开头部分，规范化后和搜索词相同。
    static func 标题开头是(_ 查询键: String, _ 作品: 作品搜索结果) -> Bool {
        let 标题们 = [作品.标题] + 作品.多语言标题.flatMap { [$0.title, $0.latin].compactMap { $0 } }
        return 标题们.contains { 标题 in
            let 文本 = 作品多语言标题.校正(标题)
            var 开头 = ""
            for 字 in 文本 {
                if !字.isLetter && !字.isNumber, 名称键(开头) == 查询键 { return true }
                开头.append(字)
            }
            return 名称键(文本) == 查询键
        }
    }

    /// 和智能搜索模型相同的规范化（不含变音映射）：小写、片假名转平假名、只留字母和数字。
    private static func 名称键(_ 文本: String) -> String {
        var 结果 = String.UnicodeScalarView()
        结果.append(contentsOf: 智能搜索名称索引.规范化(文本, 变音映射: [:]))
        return String(结果)
    }
}

// MARK: - 智能搜索结果的详情

/// 设备端智能搜索：输入停顿后在设备上做名称模糊匹配，再用 VNDB 编号批量取详情（带上当前筛选条件，
/// 这样筛选对智能搜索找到的条目同样生效）。查询文本不会离开设备。
@MainActor
final class 智能搜索视图模型: ObservableObject {
    struct 筛选条件: Equatable {
        var 作品 = 视觉小说搜索筛选()
        var 角色 = 搜索扩展筛选()
        var 制作人员 = 搜索扩展筛选()
        var 会社 = 搜索扩展筛选()
    }

    @Published private(set) var 结果集: 智能搜索结果集 = .空
    @Published private(set) var 作品: [String: 视觉小说搜索结果] = [:]
    @Published private(set) var 角色: [String: 角色搜索结果] = [:]
    @Published private(set) var 制作人员: [String: 探索制作人员] = [:]
    @Published private(set) var 会社: [String: 探索会社] = [:]
    /// 作品编号 → 系列编号，用于把同系列作品叠在一起；包括 VNDB 搜索返回的作品。
    @Published private(set) var 作品系列: [String: String] = [:]
    /// 当前查询的智能搜索结果还没取回。搜索页等它完成再显示，避免结果出来后重新排列。
    @Published private(set) var 正在搜索 = false
    @Published private(set) var 正在补充所属作品 = false
    /// 已经请求过的角色所属作品（被筛选掉的作品不会返回，不能靠结果判断是否请求过）
    @Published private(set) var 已请求所属作品 = Set<String>()
    /// 动画、漫画与轻小说：智能搜索模型找到的和各平台搜到的，编号是“a”“m”“n”加 MAL ID。
    @Published private(set) var 动画漫画: [String: 作品搜索结果] = [:]
    /// 各平台按关键词搜到的动画、漫画与轻小说，按相关程度排好（智能搜索模型没找到的接在后面）。
    @Published private(set) var 在线作品顺序: [String] = []
    /// 各平台的搜索还没回来。
    @Published private(set) var 正在搜索作品 = false
    /// 智能搜索结果里的作品 → 资料库的偏好分数（按相关程度排序时参考）。
    @Published private(set) var 偏好: [String: Float] = [:]
    /// 动画 → 企划，以及第一个结果所属企划里没被搜到的正作（见 `综合搜索合并.按企划整理`）。
    @Published private(set) var 企划: [String: Int32] = [:]
    @Published private(set) var 企划补充: [String] = []
    private var 作品任务: Task<Void, Never>?
    private var 当前作品查询 = ""

    /// 同一企划最多补多少部（作品聚合搜索.详情 一次最多读 50 部）。
    private static let 企划补充上限 = 40
    private let 防抖纳秒: UInt64
    @Published private(set) var 已查系列 = Set<String>()
    @Published private(set) var 正在查系列 = 0
    private var 补充作品任务: Task<Void, Never>?
    private var 任务: Task<Void, Never>?
    private var 当前查询 = ""
    private var 当前筛选 = 筛选条件()

    init(防抖纳秒: UInt64 = 250_000_000) {
        self.防抖纳秒 = 防抖纳秒
    }

    deinit {
        任务?.cancel()
        作品任务?.cancel()
    }

    func 更新(关键词: String, 可用: Bool, 筛选: 筛选条件) {
        let 查询 = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        更新在线作品(查询)
        guard 可用, Self.值得搜索(查询) else {
            任务?.cancel()
            当前查询 = ""
            正在搜索 = false
            if !结果集.命中.isEmpty { 清空() }
            return
        }
        guard 查询 != 当前查询 || 筛选 != 当前筛选 else { return }
        搜索(查询, 筛选: 筛选, 重试: true)
    }

    /// `重试`：读取模型失败时是否过一会儿自动再搜一次（只重试一次）。
    private func 搜索(_ 查询: String, 筛选: 筛选条件, 重试: Bool) {
        if 筛选 != 当前筛选 {
            角色所属作品 = [:]
            已请求所属作品 = []
        }
        正在搜索 = true
        当前查询 = 查询
        当前筛选 = 筛选
        任务?.cancel()
        任务 = Task { [weak self, 防抖纳秒] in
            do {
                try await Task.sleep(nanoseconds: 防抖纳秒)
                let 结果 = try await 智能搜索引擎.shared.搜索(查询)
                try Task.checkCancellation()
                guard let self else { return }
                // 第一个结果有把握是某部动画时（“ll”对上 LoveLive!），补上同一企划里没被搜到的作品
                let 已搜到 = Set(结果.命中.map(\.编号))
                var 补充: [String] = []
                if let 首 = 结果.命中.first, 首.类型 == .动画, 首.概率 >= 综合搜索合并.有把握概率 {
                    补充 = await 作品推荐中心.shared.同企划作品(编号: 首.编号, 数量: Self.企划补充上限)
                        .filter { !已搜到.contains($0) }
                }
                async let 作品详情 = 作品聚合搜索.shared.详情(
                    结果.命中.filter { [.动画, .漫画, .轻小说].contains($0.类型) }.map(\.编号) + 补充
                )
                async let 企划 = 作品推荐中心.shared.企划(
                    编号: 结果.命中.filter { $0.类型 == .动画 }.map(\.编号) + 补充
                )
                // 和结果一起取回，结果出来以后不再重新排列
                async let 偏好 = 作品推荐中心.shared.偏好分数(
                    编号: 结果.命中.compactMap { [.视觉小说, .动画, .漫画, .轻小说].contains($0.类型) ? $0.编号 : $0.所属作品 }
                )
                let 详情 = try await Self.获取详情(结果, 筛选: 筛选)
                let 动画漫画详情 = await 作品详情
                let 偏好分数 = await 偏好
                let 企划表 = await 企划
                try Task.checkCancellation()
                guard 查询 == self.当前查询, 筛选 == self.当前筛选 else { return }
                self.作品 = 详情.作品.merging(self.角色所属作品) { 新, _ in 新 }
                self.角色 = 详情.角色
                self.制作人员 = 详情.制作人员
                self.会社 = 详情.会社
                //智能搜索模型读到的标题更完整（AniList 的各语言标题），覆盖各平台搜索结果里的。
                // AniList 标明是音乐（MV）的不显示，和 PaperVN Sync 不导入的条目一致
                self.动画漫画.merge(动画漫画详情.filter { 作品搜索结果.可导入(格式: $0.value.格式) != false || $0.value.aniListID == nil }) { _, 新 in 新 }
                self.偏好 = 偏好分数
                self.企划 = 企划表
                // 只补正作（TV、网络动画）；OVA、剧场版、音乐等不补
                self.企划补充 = 补充.filter {
                    guard let item = 动画漫画详情[$0], 作品搜索结果.可导入(格式: item.格式) != false else { return false }
                    return 综合搜索合并.是正作(动画漫画组(作品: item))
                }
                self.结果集 = 结果
                self.正在搜索 = false
                self.补充作品系列(结果.命中.filter { $0.类型 == .视觉小说 }.map(\.编号))
            } catch is CancellationError {
                return
            } catch {
                guard let self, 查询 == self.当前查询 else { return }
                self.清空()
                self.正在搜索 = false
                // 读取模型失败（例如模型文件刚被更新替换）：不记住这个查询，再次提交或输入时会重新搜索；
                // 另外过一秒自动重试一次。否则这次的结果只剩各平台的搜索结果，而且不会再变
                self.当前查询 = ""
                guard 重试 else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.当前查询.isEmpty, !Task.isCancelled else { return }
                self.搜索(查询, 筛选: 筛选, 重试: false)
            }
        }
    }

    /// 在各平台上搜索动画、漫画与轻小说。和智能搜索模型无关：没有模型或关闭智能搜索时也会搜索。
    private func 更新在线作品(_ 查询: String) {
        guard Self.值得搜索(查询) else {
            作品任务?.cancel()
            当前作品查询 = ""
            正在搜索作品 = false
            在线作品顺序 = []
            return
        }
        guard 查询 != 当前作品查询 else { return }
        当前作品查询 = 查询
        正在搜索作品 = true
        作品任务?.cancel()
        作品任务 = Task { [weak self, 防抖纳秒] in
            do {
                try await Task.sleep(nanoseconds: 防抖纳秒)
            } catch {
                return
            }
            let 结果 = await 作品聚合搜索.shared.在线搜索(查询)
            guard let self, !Task.isCancelled, 查询 == self.当前作品查询 else { return }
            for item in 结果 where self.动画漫画[item.id] == nil {
                self.动画漫画[item.id] = item
            }
            self.在线作品顺序 = 结果.map(\.id)
            self.正在搜索作品 = false
        }
    }

    /// 查询这些作品所属的系列（已经查过的不再查）。
    func 补充作品系列(_ 编号: [String]) {
        let 缺少 = 编号.filter { !已查系列.contains($0) }
        guard !缺少.isEmpty else { return }
        已查系列.formUnion(缺少)
        正在查系列 += 1
        Task {
            let 结果 = await 智能搜索引擎.shared.作品系列(缺少)
            作品系列.merge(结果) { 新, _ in 新 }
            正在查系列 -= 1
        }
    }

    /// 这些作品的系列还没查完（查完前搜索页先不显示结果，免得同系列作品先分开显示再叠到一起）。
    func 系列待补充(_ 编号: [String]) -> Bool {
        正在查系列 > 0 || 编号.contains { !已查系列.contains($0) }
    }

    /// VNDB 搜索返回的角色：取回所属作品，用于把角色挂在作品下面。
    private var 角色所属作品: [String: 视觉小说搜索结果] = [:]

    func 补充所属作品(_ 角色: [角色搜索结果], 筛选: 视觉小说搜索筛选) {
        let 编号 = Array(待补充所属作品编号(角色).prefix(100))
        guard !编号.isEmpty else { return }
        已请求所属作品.formUnion(编号)
        正在补充所属作品 = true
        补充作品任务 = Task { [weak self] in
            let 结果 = (try? await VNDB服务.shared.按编号获取视觉小说(编号, 筛选: 筛选)) ?? []
            guard let self else { return }
            for item in 结果 {
                self.角色所属作品[item.id] = item
                self.作品[item.id] = item
            }
            self.正在补充所属作品 = false
            // 系列在设备上查，很快；查完前作品先单独显示
            self.补充作品系列(结果.map(\.id))
        }
    }

    /// 这些角色还有所属作品没取回（取回前搜索页先不显示结果）。
    func 所属作品待补充(_ 角色: [角色搜索结果]) -> Bool {
        正在补充所属作品 || !待补充所属作品编号(角色).isEmpty
    }

    private func 待补充所属作品编号(_ 角色: [角色搜索结果]) -> [String] {
        Set(角色.compactMap(\.主要作品编号))
            .subtracting(作品.keys)
            .subtracting(已请求所属作品)
            .sorted()
    }

    private func 清空() {
        结果集 = .空
        作品 = 角色所属作品
        角色 = [:]
        制作人员 = [:]
        会社 = [:]
    }

    /// 一个汉字、假名或韩文就可能是有意义的查询（如“猫”），拉丁字母至少两个。
    nonisolated static func 值得搜索(_ 查询: String) -> Bool {
        let 标量 = 查询.unicodeScalars.filter { !$0.properties.isWhitespace }
        if 标量.count >= 2 { return true }
        guard let 字 = 标量.first else { return false }
        return (0x3040...0x30FF).contains(字.value)
            || (0x3400...0x9FFF).contains(字.value)
            || (0xAC00...0xD7A3).contains(字.value)
    }

    private struct 详情结果 {
        var 作品: [String: 视觉小说搜索结果] = [:]
        var 角色: [String: 角色搜索结果] = [:]
        var 制作人员: [String: 探索制作人员] = [:]
        var 会社: [String: 探索会社] = [:]
    }

    private static func 获取详情(_ 结果: 智能搜索结果集, 筛选: 筛选条件) async throws -> 详情结果 {
        var 作品编号: [String] = []
        var 角色编号: [String] = []
        var 制作人员编号: [String] = []
        var 会社编号: [String] = []
        for 命中 in 结果.命中 {
            switch 命中.类型 {
            case .视觉小说: 作品编号.append(命中.编号)
            case .角色:
                角色编号.append(命中.编号)
                // 角色的所属作品也取回来，用于把角色挂在作品下面
                if let 所属 = 命中.所属作品 { 作品编号.append(所属) }
            case .制作人员: 制作人员编号.append(命中.编号)
            case .会社: 会社编号.append(命中.编号)
            case .动画, .漫画, .轻小说: break
            }
        }
        作品编号 = Array(NSOrderedSet(array: 作品编号)) as? [String] ?? 作品编号
        let 服务 = VNDB服务.shared
        async let 作品结果 = try? 服务.按编号获取视觉小说(Array(作品编号.prefix(100)), 筛选: 筛选.作品)
        async let 角色结果 = try? 服务.按编号获取角色(Array(角色编号.prefix(100)), 筛选: 筛选.角色)
        async let 制作人员结果 = try? 服务.按编号获取制作人员(Array(制作人员编号.prefix(100)), 筛选: 筛选.制作人员)
        async let 会社结果 = try? 服务.按编号获取会社(Array(会社编号.prefix(100)), 筛选: 筛选.会社)
        var 详情 = 详情结果()
        for item in await 作品结果 ?? [] { 详情.作品[item.id] = item }
        for item in await 角色结果 ?? [] { 详情.角色[item.id] = item }
        for item in await 制作人员结果 ?? [] { 详情.制作人员[item.id] = item }
        for item in await 会社结果 ?? [] { 详情.会社[item.id] = item }
        return 详情
    }
}
