import Combine
import Foundation

nonisolated enum パーパル卡片类型: String, Codable, Hashable, Sendable {
    case visualNovel = "VN"
    case character = "CHAR"
}

nonisolated struct パーパル卡片引用: Codable, Hashable, Identifiable, Sendable {
    let 类型: パーパル卡片类型
    let vndbID: String?
    let 名称: String

    var id: String {
        "\(类型.rawValue)|\(vndbID ?? "-")|\(名称)"
    }
}

nonisolated struct パーパル网络引用: Codable, Hashable, Identifiable, Sendable {
    let 编号: String
    let 地址: URL

    var id: String {
        地址.absoluteString
    }

    var 网站名称: String {
        let 主机 = 地址.host?.trimmingCharacters(in: .whitespacesAndNewlines)
        let 名称 = 主机?.isEmpty == false ? 主机! : 地址.absoluteString
        let 无前缀 = 名称.lowercased().hasPrefix("www.")
            ? String(名称.dropFirst(4))
            : 名称
        return Self.截断(无前缀, 上限: パーパル额度.来源名称字数上限)
    }

    var 图标地址: URL? {
        guard let 方案 = 地址.scheme,
              let 主机 = 地址.host,
              !主机.isEmpty else {
            return nil
        }
        var 组件 = URLComponents()
        组件.scheme = 方案
        组件.host = 主机
        组件.port = 地址.port
        组件.path = "/favicon.ico"
        return 组件.url
    }

    var 显示文本: String {
        网站名称
    }

    var 行内标记: String {
        "[\(编号)]"
    }

    private static func 截断(_ 文本: String, 上限: Int) -> String {
        guard 上限 > 0, 文本.count > 上限 else { return 文本 }
        guard 上限 > 1 else { return String(文本.prefix(上限)) }
        return String(文本.prefix(上限 - 1)) + "…"
    }
}

nonisolated enum パーパル消息角色: String, Codable, Hashable, Sendable {
    case user
    case assistant
}

nonisolated struct パーパル回答版本: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var 文本: String
    var 卡片: [パーパル卡片引用]
    var 引用: [パーパル网络引用]
    var 时间: Date
    var 思考过程: String?

    init(
        id: UUID = UUID(),
        文本: String,
        卡片: [パーパル卡片引用] = [],
        引用: [パーパル网络引用] = [],
        时间: Date = Date(),
        思考过程: String? = nil
    ) {
        self.id = id
        self.文本 = 文本
        self.卡片 = 卡片
        self.引用 = 引用
        self.时间 = 时间
        self.思考过程 = 思考过程
    }
}

nonisolated struct パーパル消息: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var 角色: パーパル消息角色
    var 文本: String
    var 卡片: [パーパル卡片引用]
    var 引用: [パーパル网络引用]
    var 时间: Date
    var 思考过程: String?
    var 回答版本: [パーパル回答版本]
    var 当前回答索引: Int

    init(
        id: UUID = UUID(),
        角色: パーパル消息角色,
        文本: String,
        卡片: [パーパル卡片引用] = [],
        引用: [パーパル网络引用] = [],
        时间: Date = Date(),
        思考过程: String? = nil,
        回答版本: [パーパル回答版本] = [],
        当前回答索引: Int = 0
    ) {
        self.id = id
        self.角色 = 角色
        self.文本 = 文本
        self.卡片 = 卡片
        self.引用 = 引用
        self.时间 = 时间
        self.思考过程 = 思考过程
        self.回答版本 = 回答版本
        self.当前回答索引 = 当前回答索引
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        角色 = try container.decode(パーパル消息角色.self, forKey: .角色)
        let 解码文本 = try container.decode(String.self, forKey: .文本)
        卡片 = try container.decodeIfPresent([パーパル卡片引用].self, forKey: .卡片)
            ?? []
        引用 = try container.decodeIfPresent([パーパル网络引用].self, forKey: .引用)
            ?? []
        文本 = Self.迁移旧引用标记(解码文本, 引用: 引用)
        时间 = try container.decode(Date.self, forKey: .时间)
        思考过程 = try container.decodeIfPresent(String.self, forKey: .思考过程)

        let 解码版本 = try container.decodeIfPresent(
            [パーパル回答版本].self,
            forKey: .回答版本
        ) ?? []
        let 已保存版本 = 解码版本.map { 版本 -> パーパル回答版本 in
            var 迁移后版本 = 版本
            迁移后版本.文本 = Self.迁移旧引用标记(
                版本.文本,
                引用: 版本.引用
            )
            return 迁移后版本
        }
        if 角色 == .assistant, 已保存版本.isEmpty,
           !文本.isEmpty || !卡片.isEmpty || !引用.isEmpty || 思考过程 != nil {
            回答版本 = [
                パーパル回答版本(
                    id: id,
                    文本: 文本,
                    卡片: 卡片,
                    引用: 引用,
                    时间: 时间,
                    思考过程: 思考过程
                )
            ]
        } else {
            回答版本 = 已保存版本
        }
        let 保存的索引 = try container.decodeIfPresent(
            Int.self,
            forKey: .当前回答索引
        ) ?? max(回答版本.count - 1, 0)
        当前回答索引 = 回答版本.isEmpty
            ? 0
            : min(max(保存的索引, 0), 回答版本.count - 1)
    }

    private static func 迁移旧引用标记(
        _ 文本: String,
        引用: [パーパル网络引用]
    ) -> String {
        guard !文本.isEmpty, !引用.isEmpty else { return 文本 }

        var 结果 = 文本
        let 上标数字: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"
        ]

        for 来源 in 引用 {
            let 编号 = 来源.编号
            let 上标编号 = String(编号.map { 上标数字[$0] ?? $0 })
            let 替换 = "[\(编号)]"
            结果 = 结果
                .replacingOccurrences(of: "⁽\(上标编号)⁾", with: 替换)
                .replacingOccurrences(of: "(\(编号))", with: 替换)
                .replacingOccurrences(of: "（\(编号)）", with: 替换)
        }
        return 结果
    }

    var 回答总数: Int { 回答版本.count }

    var 可以切换回答: Bool {
        角色 == .assistant && 回答版本.count > 1
    }

    mutating func 收录当前回答() {
        guard 角色 == .assistant,
              !文本.isEmpty || !卡片.isEmpty || !引用.isEmpty || 思考过程 != nil
        else { return }

        回答版本.append(
            パーパル回答版本(
                文本: 文本,
                卡片: 卡片,
                引用: 引用,
                时间: 时间,
                思考过程: 思考过程
            )
        )
        当前回答索引 = 回答版本.count - 1
    }

    mutating func 恢复当前回答() {
        guard 角色 == .assistant,
              回答版本.indices.contains(当前回答索引) else { return }
        let 版本 = 回答版本[当前回答索引]
        文本 = 版本.文本
        卡片 = 版本.卡片
        引用 = 版本.引用
        时间 = 版本.时间
        思考过程 = 版本.思考过程
    }
}

nonisolated struct パーパル会话: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var 消息: [パーパル消息]
    var 标题: String?
    var 创建时间: Date
    var 更新时间: Date
    var 已删除: Bool

    init(
        id: UUID = UUID(),
        消息: [パーパル消息] = [],
        标题: String? = nil,
        创建时间: Date = Date(),
        更新时间: Date = Date(),
        已删除: Bool = false
    ) {
        self.id = id
        self.消息 = 消息
        self.标题 = 标题
        self.创建时间 = 创建时间
        self.更新时间 = 更新时间
        self.已删除 = 已删除
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        消息 = try container.decode([パーパル消息].self, forKey: .消息)
        标题 = try container.decodeIfPresent(String.self, forKey: .标题)
        创建时间 = try container.decode(Date.self, forKey: .创建时间)
        更新时间 = try container.decode(Date.self, forKey: .更新时间)
        已删除 = try container.decodeIfPresent(Bool.self, forKey: .已删除)
            ?? false
    }

    var 用户消息数: Int {
        消息.reduce(into: 0) { $0 += $1.角色 == .user ? 1 : 0 }
    }

    var 剩余消息数: Int {
        max(パーパル额度.单会话用户消息上限 - 用户消息数, 0)
    }

    var 已用尽额度: Bool {
        剩余消息数 == 0
    }

    var 显示标题: String {
        let 整理后 = (标题 ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return 整理后.isEmpty ? String(localized: "新对话") : 整理后
    }
}

nonisolated enum パーパル额度 {
    static let 单会话用户消息上限 = 50
    static let 请求历史上限 = 24
    static let 标题字数上限 = 40
    static let 来源名称字数上限 = 32
    static let 记忆字数上限 = 2000
}

nonisolated enum パーパル偏好 {
    static let 称呼键 = "paperVNAssistantHonorific"
    static let 默认称呼 = "ご主人様"
    static let 记忆功能键 = "paperVNAssistantMemoryEnabledV1"

    static func 读取称呼(defaults: UserDefaults = .standard) -> String {
        let 值 = (defaults.string(forKey: 称呼键) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return 值.isEmpty ? 默认称呼 : 值
    }

    static func 读取记忆功能(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: 记忆功能键) != nil else {
            defaults.set(true, forKey: 记忆功能键)
            return true
        }
        return defaults.bool(forKey: 记忆功能键)
    }
}

@MainActor
final class パーパル记忆中心: ObservableObject {
    static let shared = パーパル记忆中心()

    private static let 本地摘要键 = "paperVNAssistantMemorySummaryV2"
    private static let 本地清除时间键 = "paperVNAssistantMemoryClearedAtV1"
    private static let 云端摘要键 = "paperVNAssistantMemorySummaryV2"
    private static let 云端清除时间键 = "paperVNAssistantMemoryClearedAtV1"
    static let iCloud同步键 = "paperVNAssistantMemoryICloudSyncEnabledV1"

    nonisolated private struct 摘要值: Codable, Equatable, Sendable {
        let 文本: String
        let 更新时间: Date
    }

    @Published private(set) var 当前摘要: String?
    @Published private(set) var iCloud同步已启用: Bool
    @Published private(set) var 已启用: Bool

    private let defaults: UserDefaults
    private let 云端: NSUbiquitousKeyValueStore
    private var 摘要更新时间: Date?
    private var 清除时间: Date?
    private var 云端观察者: NSObjectProtocol?
    private let 编码器: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let 解码器: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(
        defaults: UserDefaults = .standard,
        云端: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.云端 = 云端
        self.当前摘要 = nil
        self.摘要更新时间 = nil
        self.云端观察者 = nil
        self.已启用 = パーパル偏好.读取记忆功能(defaults: defaults)
        self.iCloud同步已启用 = Self.读取iCloud同步(defaults: defaults)
        self.清除时间 = defaults.object(forKey: Self.本地清除时间键) as? Date

        if let 数据 = defaults.data(forKey: Self.本地摘要键),
           let 值 = try? 解码器.decode(摘要值.self, from: 数据) {
            当前摘要 = Self.整理摘要(值.文本)
            摘要更新时间 = 值.更新时间
        } else if let 旧摘要 = Self.读取旧记忆摘要(
            defaults: defaults,
            decoder: 解码器
        ) {
            当前摘要 = 旧摘要
            摘要更新时间 = Date()
            保存本地摘要()
            defaults.removeObject(forKey: "paperVNAssistantMemoriesV1")
        }

        云端观察者 = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: 云端,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.合并云端摘要()
            }
        }

        if iCloud同步已启用 {
            合并云端摘要()
        }
    }

    func 设置已启用(_ 启用: Bool) {
        已启用 = 启用
        defaults.set(启用, forKey: パーパル偏好.记忆功能键)
        if 启用, iCloud同步已启用 {
            合并云端摘要()
            上传云端摘要()
        }
    }

    func 设置iCloud同步(_ 启用: Bool) {
        guard 已启用 else { return }
        iCloud同步已启用 = 启用
        defaults.set(启用, forKey: Self.iCloud同步键)
        guard 启用 else { return }
        合并云端摘要()
        上传云端摘要()
    }

    func 更新摘要(_ 文本: String) {
        guard 已启用 else { return }
        let 整理后 = Self.整理摘要(文本)
        当前摘要 = 整理后
        摘要更新时间 = Date()
        保存本地摘要()
        if iCloud同步已启用 {
            上传云端摘要()
        }
    }

    func 删除全部() {
        当前摘要 = nil
        摘要更新时间 = nil
        let 时间 = Date()
        清除时间 = 时间
        defaults.removeObject(forKey: Self.本地摘要键)
        defaults.set(时间, forKey: Self.本地清除时间键)
        guard iCloud同步已启用 else { return }
        云端.removeObject(forKey: Self.云端摘要键)
        云端.set(时间, forKey: Self.云端清除时间键)
        云端.synchronize()
    }

    private func 保存本地摘要() {
        guard let 当前摘要,
              let 摘要更新时间,
              let 数据 = try? 编码器.encode(
                  摘要值(文本: 当前摘要, 更新时间: 摘要更新时间)
              ) else {
            defaults.removeObject(forKey: Self.本地摘要键)
            return
        }
        defaults.set(数据, forKey: Self.本地摘要键)
    }

    private func 上传云端摘要() {
        guard 已启用, iCloud同步已启用 else { return }
        guard let 当前摘要,
              let 摘要更新时间,
              let 数据 = try? 编码器.encode(
                  摘要值(文本: 当前摘要, 更新时间: 摘要更新时间)
              ) else {
            云端.removeObject(forKey: Self.云端摘要键)
            if let 清除时间 {
                云端.set(清除时间, forKey: Self.云端清除时间键)
            }
            云端.synchronize()
            return
        }
        云端.set(数据, forKey: Self.云端摘要键)
        if let 清除时间 {
            云端.set(清除时间, forKey: Self.云端清除时间键)
        }
        云端.synchronize()
    }

    private func 合并云端摘要() {
        guard 已启用, iCloud同步已启用 else { return }
        云端.synchronize()

        let 云端清除时间 = 云端.object(forKey: Self.云端清除时间键) as? Date
        let 有效清除时间 = [清除时间, 云端清除时间].compactMap { $0 }.max()
        if 有效清除时间 != 清除时间 {
            清除时间 = 有效清除时间
            if let 有效清除时间 {
                defaults.set(有效清除时间, forKey: Self.本地清除时间键)
            }
        }

        let 云端值 = 云端.data(forKey: Self.云端摘要键).flatMap {
            try? 解码器.decode(摘要值.self, from: $0)
        }
        let 有效云端值: 摘要值?
        if let 云端值,
           let 有效清除时间,
           云端值.更新时间 <= 有效清除时间 {
            有效云端值 = nil
        } else {
            有效云端值 = 云端值
        }

        if let 云端值 = 有效云端值,
           摘要更新时间 == nil || 云端值.更新时间 > 摘要更新时间! {
            当前摘要 = Self.整理摘要(云端值.文本)
            摘要更新时间 = 云端值.更新时间
            保存本地摘要()
            return
        }

        if let 摘要更新时间,
           let 有效清除时间,
           摘要更新时间 <= 有效清除时间 {
            当前摘要 = nil
            self.摘要更新时间 = nil
            defaults.removeObject(forKey: Self.本地摘要键)
            return
        }

        if 有效云端值 == nil, 当前摘要 != nil {
            上传云端摘要()
        }
    }

    private static func 读取iCloud同步(defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: Self.iCloud同步键) != nil else {
            defaults.set(true, forKey: Self.iCloud同步键)
            return true
        }
        return defaults.bool(forKey: Self.iCloud同步键)
    }

    private static func 读取旧记忆摘要(
        defaults: UserDefaults,
        decoder: JSONDecoder
    ) -> String? {
        struct 旧记忆: Codable {
            let 文本: String
        }
        guard let 数据 = defaults.data(forKey: "paperVNAssistantMemoriesV1"),
              let 旧记忆 = try? decoder.decode([旧记忆].self, from: 数据) else {
            return nil
        }
        return 整理摘要(旧记忆.map(\.文本).joined(separator: "\n"))
    }

    private static func 整理摘要(_ 文本: String) -> String? {
        let 整理后 = 文本
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !整理后.isEmpty else { return nil }
        return String(整理后.prefix(パーパル额度.记忆字数上限))
    }
}

@MainActor
final class パーパル数据中心: ObservableObject {
    static let shared = パーパル数据中心()

    private static let 本地会话键 = "paperVNAssistantConversationsV1"
    private static let 会话保留条数 = 200

    @Published private(set) var 会话列表: [パーパル会话] = []

    private let defaults: UserDefaults
    private let 编码器: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let 解码器: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    init(
        defaults: UserDefaults = .standard,
        云端: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults

        if let 数据 = defaults.data(forKey: Self.本地会话键),
           let 值 = try? 解码器.decode([パーパル会话].self, from: 数据) {
            会话列表 = 值
        }

    }

    var 可见会话: [パーパル会话] {
        会话列表
            .filter { !$0.消息.isEmpty }
            .sorted { $0.更新时间 > $1.更新时间 }
    }

    func 保存会话(_ 会话: パーパル会话) {
        var 更新后 = 会话
        更新后.更新时间 = Date()
        if let index = 会话列表.firstIndex(where: { $0.id == 会话.id }) {
            会话列表[index] = 更新后
        } else {
            会话列表.append(更新后)
        }
        if 会话列表.count > Self.会话保留条数 {
            会话列表 = Array(
                会话列表
                    .sorted { $0.更新时间 > $1.更新时间 }
                    .prefix(Self.会话保留条数)
            )
        }
        写入本地会话()
    }

    func 删除会话(id: UUID) {
        会话列表.removeAll { $0.id == id }
        写入本地会话()
    }

    func 删除全部会话() {
        会话列表 = []
        写入本地会话()
    }

    private func 写入本地会话() {
        if let 数据 = try? 编码器.encode(会话列表) {
            defaults.set(数据, forKey: Self.本地会话键)
        }
    }
}

nonisolated enum パーパル标记解析 {
    nonisolated struct 结果: Sendable, Equatable {
        var 显示文本: String
        var 卡片: [パーパル卡片引用]
        var 引用: [パーパル网络引用]
        var 标题: String?
        var 思考过程: String?
        var 记忆摘要: String?

        static let 空 = 结果(
            显示文本: "",
            卡片: [],
            引用: [],
            标题: nil,
            思考过程: nil,
            记忆摘要: nil
        )
    }

    static let 开始定界符 = "[["
    static let 结束定界符 = "]]"
    private static let 标题标签 = "TITLE"
    private static let 未知编号 = "-"

    static func 解析(_ 原文: String, 流式: Bool = false) -> 结果 {
        let (处理后文本, 思考过程) = 提取思考过程(原文, 流式: 流式)

        let 字符 = Array(处理后文本)
        var 显示 = ""
        var 卡片: [パーパル卡片引用] = []
        var 引用: [パーパル网络引用] = []
        var 标题: String?
        var 记忆摘要: String?
        var 已见卡片: Set<String> = []
        var 位置 = 0

        while 位置 < 字符.count {
            if let 网络引用 = 查找网络引用(字符, 从: 位置) {
                显示 += 网络引用.引用.行内标记
                if 已见卡片.insert(网络引用.引用.id).inserted {
                    引用.append(网络引用.引用)
                }
                位置 = 网络引用.下一位置
                continue
            }

            guard 字符[位置] == "[",
                  位置 + 1 < 字符.count,
                  字符[位置 + 1] == "[" else {
                显示.append(字符[位置])
                位置 += 1
                continue
            }

            guard let 结束 = 查找结束(字符, 从: 位置 + 2) else {
                if 流式 {
                    位置 = 字符.count
                } else {
                    显示.append(contentsOf: 字符[位置...])
                    位置 = 字符.count
                }
                break
            }

            let 载荷 = String(字符[(位置 + 2)..<结束])
            位置 = 结束 + 2

            switch 解析载荷(载荷) {
            case let .卡片(引用):
                显示 += 引用.名称
                if 已见卡片.insert(引用.id).inserted {
                    卡片.append(引用)
                }
            case let .标题(文本):
                标题 = 文本
            case let .记忆(文本):
                记忆摘要 = 文本
            case .无法识别:
                显示 += 开始定界符 + 载荷 + 结束定界符
            }
        }

        return 结果(
            显示文本: 规范化(显示),
            卡片: 卡片,
            引用: 引用,
            标题: 标题,
            思考过程: 思考过程,
            记忆摘要: 记忆摘要
        )
    }

    private static func 提取思考过程(_ 原文: String, 流式: Bool) -> (处理后文本: String, 思考过程: String?) {
        let 开始标签 = "<thinking>"
        let 结束标签 = "</thinking>"

        guard let 开始位置 = 原文.range(of: 开始标签) else {
            return (原文, nil)
        }

        let 搜索起点 = 开始位置.upperBound
        guard let 结束位置 = 原文.range(of: 结束标签, range: 搜索起点..<原文.endIndex) else {
            if 流式 {
                let 前部分 = 原文[..<开始位置.lowerBound]
                return (前部分.trimmingCharacters(in: .whitespacesAndNewlines), nil)
            } else {
                let 文本 = String(原文[..<开始位置.lowerBound])
                return (文本.trimmingCharacters(in: .whitespacesAndNewlines), nil)
            }
        }

        let 思考内容 = String(原文[搜索起点..<结束位置.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let 前部分 = 原文[..<开始位置.lowerBound]
        let 后部分 = 原文[结束位置.upperBound...]
        let 处理后 = (前部分 + 后部分).trimmingCharacters(in: .whitespacesAndNewlines)

        return (处理后, 思考内容.isEmpty ? nil : 思考内容)
    }

    static func 规范化(_ 文本: String) -> String {
        var 行 = 文本.components(separatedBy: .newlines).map {
            String($0.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        }
        var 压缩: [String] = []
        for 单行 in 行 {
            if 单行.isEmpty, 压缩.last?.isEmpty == true { continue }
            压缩.append(单行)
        }
        行 = 压缩
        while 行.first?.isEmpty == true { 行.removeFirst() }
        while 行.last?.isEmpty == true { 行.removeLast() }
        return 行.joined(separator: "\n")
    }

    private enum 载荷类型 {
        case 卡片(パーパル卡片引用)
        case 标题(String)
        case 记忆(String)
        case 无法识别
    }

    private static func 查找网络引用(
        _ 字符: [Character],
        从 起点: Int
    ) -> (引用: パーパル网络引用, 下一位置: Int)? {
        guard 起点 < 字符.count, 字符[起点] == "[" else { return nil }

        let 是双括号 = 起点 + 1 < 字符.count && 字符[起点 + 1] == "["
        let 标签起点 = 起点 + (是双括号 ? 2 : 1)
        guard 标签起点 < 字符.count else { return nil }

        let 结束符号: Character = "]"
        var 标签结束: Int?
        var 位置 = 标签起点
        while 位置 < 字符.count {
            if 字符[位置] == 结束符号 {
                if 是双括号 {
                    guard 位置 + 1 < 字符.count, 字符[位置 + 1] == "]" else {
                        return nil
                    }
                }
                标签结束 = 位置
                break
            }
            if 字符[位置].isNewline { return nil }
            位置 += 1
        }
        guard let 标签结束 else { return nil }

        let 标签 = String(字符[标签起点..<标签结束])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !标签.isEmpty, 标签.allSatisfy(\.isNumber) else { return nil }

        位置 = 标签结束 + (是双括号 ? 2 : 1)
        if 位置 < 字符.count, 字符[位置] == "\\" {
            位置 += 1
        }
        guard 位置 < 字符.count, 字符[位置] == "(" else { return nil }

        let 地址起点 = 位置 + 1
        位置 = 地址起点
        var 深度 = 1
        var 已转义 = false
        while 位置 < 字符.count {
            let 当前 = 字符[位置]
            if 已转义 {
                已转义 = false
            } else if 当前 == "\\" {
                已转义 = true
            } else if 当前 == "(" {
                深度 += 1
            } else if 当前 == ")" {
                深度 -= 1
                if 深度 == 0 { break }
            }
            位置 += 1
        }
        guard 位置 < 字符.count, 深度 == 0 else { return nil }

        let 地址文本 = String(字符[地址起点..<位置])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let 地址 = 规范化网络地址(地址文本) else { return nil }

        return (
            パーパル网络引用(编号: 标签, 地址: 地址),
            位置 + 1
        )
    }

    private static func 规范化网络地址(_ 原文: String) -> URL? {
        guard !原文.isEmpty, !原文.contains(where: { $0.isWhitespace }) else {
            return nil
        }
        guard let 地址 = URL(string: 原文),
              let 方案 = 地址.scheme?.lowercased(),
              方案 == "http" || 方案 == "https",
              地址.host?.isEmpty == false else {
            return nil
        }
        return 地址
    }

    private static func 查找结束(_ 字符: [Character], 从 起点: Int) -> Int? {
        var 位置 = 起点
        while 位置 + 1 < 字符.count {
            if 字符[位置] == "]", 字符[位置 + 1] == "]" { return 位置 }
            if 字符[位置].isNewline { return nil }
            位置 += 1
        }
        return nil
    }

    private static func 解析载荷(_ 载荷: String) -> 载荷类型 {
        let 分段 = 载荷.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let 标签 = 分段.first?.uppercased() else { return .无法识别 }

        if 标签 == 标题标签 {
            let 内容 = 分段.dropFirst()
                .joined(separator: "|")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !内容.isEmpty else { return .无法识别 }
            return .标题(String(内容.prefix(パーパル额度.标题字数上限)))
        }

        if 标签 == "MEMORY" {
            let 内容 = 分段.dropFirst()
                .joined(separator: "|")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !内容.isEmpty, !内容.contains(where: \.isNewline) else {
                return .无法识别
            }
            return .记忆(String(内容.prefix(パーパル额度.记忆字数上限)))
        }

        guard let 类型 = パーパル卡片类型(rawValue: 标签) else {
            return .无法识别
        }

        let 参数 = Array(分段.dropFirst())
        let 编号原文: String
        let 名称: String
        switch 参数.count {
        case 0:
            return .无法识别
        case 1:
            编号原文 = ""
            名称 = 参数[0]
        default:
            编号原文 = 参数[0]
            名称 = 参数.dropFirst().joined(separator: "|")
        }

        let 名称文本 = 名称.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !名称文本.isEmpty else { return .无法识别 }

        return .卡片(
            パーパル卡片引用(
                类型: 类型,
                vndbID: 规范化编号(编号原文, 类型: 类型),
                名称: 名称文本
            )
        )
    }

    private static func 规范化编号(
        _ 原文: String,
         类型: パーパル卡片类型
    ) -> String? {
        var 编号 = 原文.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !编号.isEmpty, 编号 != 未知编号, 编号 != "?" else { return nil }

        if let 末段 = 编号.split(separator: "/").last {
            编号 = String(末段)
        }
        编号 = 编号.trimmingCharacters(
            in: CharacterSet(charactersIn: "#、,.。")
        )

        let 前缀: Character = 类型 == .visualNovel ? "v" : "c"
        if 编号.first == 前缀, 编号.dropFirst().allSatisfy(\.isNumber),
           编号.count > 1 {
            return 编号
        }
        if !编号.isEmpty, 编号.allSatisfy(\.isNumber) {
            return "\(前缀)\(编号)"
        }
        return nil
    }
}
