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

enum 综合搜索条目: Identifiable, Hashable {
    case 作品(综合作品组)
    /// 找不到所属作品（或所属作品被筛选掉）的角色
    case 角色(角色搜索结果)
    case 制作人员(探索制作人员)
    case 会社(探索会社)

    var id: String {
        switch self {
        case let .作品(组): return 组.id
        case let .角色(item): return item.id
        case let .制作人员(item): return item.id
        case let .会社(item): return item.id
        }
    }

    /// 这个条目对应的智能搜索结果编号是否包含 `编号`。
    func 包含(_ 编号: String) -> Bool {
        switch self {
        case let .作品(组):
            return 组.全部作品编号.contains(编号) || 组.角色.contains { $0.id == 编号 }
        default:
            return id == 编号
        }
    }
}

/// 合并设备端智能搜索和 VNDB 搜索的结果。
///
/// 按相关程度排序时完全按智能搜索的顺序：它找到的条目在前（按可能性从高到低），VNDB 返回、
/// 智能搜索没找到的条目接在后面（作品、角色、会社、制作人员各自保持 VNDB 的顺序）。
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
        /// 作品编号 → 系列编号
        var 作品系列: [String: String] = [:]
        /// 角色编号 → 所属作品编号
        var 角色所属: [String: String] = [:]
        var 按相关程度 = true
    }

    private enum 类型 {
        case 作品, 角色, 制作人员, 会社
    }

    static func 合并(_ 输入: 输入) -> [综合搜索条目] {
        var 顺序: [(类型, String)] = []
        var 已排 = Set<String>()
        func 加入(_ 类型: 类型, _ 编号: String) {
            if 已排.insert(编号).inserted { 顺序.append((类型, 编号)) }
        }
        if 输入.按相关程度 {
            for 命中 in 输入.智能搜索命中 {
                switch 命中.类型 {
                case .视觉小说 where 输入.作品[命中.编号] != nil: 加入(.作品, 命中.编号)
                case .角色 where 输入.角色[命中.编号] != nil: 加入(.角色, 命中.编号)
                case .制作人员 where 输入.制作人员[命中.编号] != nil: 加入(.制作人员, 命中.编号)
                case .会社 where 输入.会社[命中.编号] != nil: 加入(.会社, 命中.编号)
                default: break
                }
            }
        }
        输入.VNDB作品顺序.forEach { 加入(.作品, $0) }
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
            }
        }
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
    }

    func 更新(关键词: String, 可用: Bool, 筛选: 筛选条件) {
        let 查询 = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        guard 可用, Self.值得搜索(查询) else {
            任务?.cancel()
            当前查询 = ""
            正在搜索 = false
            if !结果集.命中.isEmpty { 清空() }
            return
        }
        guard 查询 != 当前查询 || 筛选 != 当前筛选 else { return }
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
                let 详情 = try await Self.获取详情(结果, 筛选: 筛选)
                try Task.checkCancellation()
                guard 查询 == self.当前查询, 筛选 == self.当前筛选 else { return }
                self.作品 = 详情.作品.merging(self.角色所属作品) { 新, _ in 新 }
                self.角色 = 详情.角色
                self.制作人员 = 详情.制作人员
                self.会社 = 详情.会社
                self.结果集 = 结果
                self.正在搜索 = false
                self.补充作品系列(结果.命中.filter { $0.类型 == .视觉小说 }.map(\.编号))
            } catch is CancellationError {
                return
            } catch {
                guard let self, 查询 == self.当前查询 else { return }
                self.清空()
                self.正在搜索 = false
            }
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
