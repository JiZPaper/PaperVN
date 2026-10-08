import Combine
import Foundation
import SwiftUI

enum 偏好数据iCloud同步设置 {
    static let 启用键 = "PaperVN.preferenceICloudSyncEnabled"

    static func 读取(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: 启用键) != nil else {
            defaults.set(true, forKey: 启用键)
            return true
        }
        return defaults.bool(forKey: 启用键)
    }
}

extension Notification.Name {
    static let paperVNPreferenceICloudSyncSettingDidChange = Notification.Name(
        "PaperVN.preferenceICloudSyncSettingDidChange"
    )
}

struct 标签: Codable {
    let id: String
    let name: String
    let category: String?
    let vote: Int?
    let spoilerlevel: Int?
}

enum 搜索设置偏好 {
    static let 独立搜索Tab设置键 = "independentSearchTabEnabled"

    static let 独立搜索Tab默认值 = false
}

enum 搜索范围: String, CaseIterable, Identifiable, Hashable {
    case visualNovel
    case character
    case release
    case staff
    case producer

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .visualNovel:
            return String(localized: "视觉小说")
        case .character:
            return String(localized: "角色")
        case .release:
            return String(localized: "发行版本")
        case .staff:
            return String(localized: "制作人员")
        case .producer:
            return String(localized: "开发与发行商")
        }
    }

    var systemImage: String {
        switch self {
        case .visualNovel: return "books.vertical"
        case .character: return "person.crop.rectangle.stack"
        case .release: return "shippingbox"
        case .staff: return "person.text.rectangle"
        case .producer: return "building.2"
        }
    }
}

enum 视觉小说搜索排序: String, CaseIterable, Identifiable, Hashable {
    case relevance
    case title
    case rating
    case voteCount
    case released

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .relevance: return String(localized: "按相关程度")
        case .title: return String(localized: "按标题")
        case .rating: return String(localized: "按平均评分")
        case .voteCount: return String(localized: "按评分人数")
        case .released: return String(localized: "按发行日期")
        }
    }

    var symbolName: String {
        switch self {
        case .relevance: return "magnifyingglass"
        case .title: return "textformat"
        case .rating: return "chart.bar.xaxis"
        case .voteCount: return "person.2"
        case .released: return "calendar"
        }
    }

    var apiSort: String {
        switch self {
        case .relevance: return "searchrank"
        case .title: return "title"
        case .rating: return "rating"
        case .voteCount: return "votecount"
        case .released: return "released"
        }
    }

    var defaultIsDescending: Bool {
        switch self {
        case .relevance, .title: return false
        case .rating, .voteCount, .released: return true
        }
    }

    static func available(hasSearchText: Bool) -> [Self] {
        hasSearchText ? allCases : allCases.filter { $0 != .relevance }
    }
}

enum 搜索扩展排序: String, CaseIterable, Identifiable, Hashable {
    case relevance
    case title
    case name
    case released
    case added = "id"

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .relevance: return String(localized: "按相关程度")
        case .title: return String(localized: "按标题")
        case .name: return String(localized: "按名称")
        case .released: return String(localized: "按发行日期")
        case .added: return String(localized: "按新增日期")
        }
    }

    var symbolName: String {
        switch self {
        case .relevance: return "magnifyingglass"
        case .title: return "textformat"
        case .name: return "person.text.rectangle"
        case .released: return "calendar"
        case .added: return "calendar"
        }
    }

    var defaultIsDescending: Bool {
        switch self {
        case .relevance, .title, .name: return false
        case .released, .added: return true
        }
    }

    static func available(
        for scope: 搜索范围,
        hasSearchText: Bool = false
    ) -> [Self] {
        let base: [Self] = switch scope {
        case .release: [.title, .released]
        case .character, .staff, .producer: [.name, .added]
        case .visualNovel: []
        }
        return hasSearchText ? [.relevance] + base : base
    }

    func apiSort(for scope: 搜索范围) -> String {
        switch self {
        case .relevance: return "searchrank"
        case .title: return "title"
        case .name: return "name"
        case .released: return "released"
        case .added: return "id"
        }
    }
}

enum 搜索扩展筛选字段: String, CaseIterable, Codable, Hashable, Identifiable {
    case birthday
    case role
    case trait
    case releaseTime
    case releaseAttribute
    case language
    case platform
    case type

    var id: Self { self }

    func localizedTitle(for scope: 搜索范围) -> String {
        switch self {
        case .birthday: return String(localized: "生日月份")
        case .role:
            return scope == .character
                ? String(localized: "类型")
                : String(localized: "职位")
        case .trait: return String(localized: "特征")
        case .releaseTime: return String(localized: "发行时间")
        case .releaseAttribute: return String(localized: "版本属性")
        case .language: return String(localized: "语言")
        case .platform: return String(localized: "平台")
        case .type: return String(localized: "类型")
        }
    }

    var systemImage: String {
        switch self {
        case .birthday: return "calendar"
        case .role: return "person.text.rectangle"
        case .trait: return "person.crop.circle.badge.questionmark"
        case .releaseTime: return "calendar"
        case .releaseAttribute: return "checkmark.seal"
        case .language: return "character.bubble"
        case .platform: return "rectangle.3.group"
        case .type: return "building.2"
        }
    }

    var requiresSearch: Bool {
        switch self {
        case .trait, .language, .platform: return true
        case .birthday, .role, .releaseTime, .releaseAttribute, .type: return false
        }
    }

    static func available(for scope: 搜索范围) -> [Self] {
        switch scope {
        case .character: return [.birthday, .role, .trait]
        case .release: return [.language, .platform, .releaseTime, .releaseAttribute]
        case .staff: return [.role]
        case .producer: return [.type]
        case .visualNovel: return []
        }
    }
}

nonisolated struct 搜索扩展筛选条件: Codable, Hashable, Identifiable {
    let id: UUID
    var field: 搜索扩展筛选字段
    var stringValues: Set<String>

    init(
        id: UUID = UUID(),
        field: 搜索扩展筛选字段,
        stringValues: Set<String> = []
    ) {
        self.id = id
        self.field = field
        self.stringValues = stringValues
    }

    var normalizedStringValues: [String] {
        Set(
            stringValues.compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        ).sorted()
    }

    var isConfigured: Bool {
        !normalizedStringValues.isEmpty
    }
}

nonisolated struct 搜索扩展筛选规则组: Codable, Hashable, Identifiable {
    let id: UUID
    var matchMode: 视觉小说筛选匹配方式
    var isExcluded: Bool
    var conditions: [搜索扩展筛选条件]

    init(
        id: UUID = UUID(),
        matchMode: 视觉小说筛选匹配方式 = .all,
        isExcluded: Bool = false,
        conditions: [搜索扩展筛选条件] = []
    ) {
        self.id = id
        self.matchMode = matchMode
        self.isExcluded = isExcluded
        self.conditions = conditions
    }

    var configuredConditions: [搜索扩展筛选条件] {
        conditions.filter(\.isConfigured)
    }

    var isConfigured: Bool {
        !configuredConditions.isEmpty
    }
}

nonisolated struct 搜索扩展筛选: Codable, Hashable {
    var rules: [搜索扩展筛选规则组]

    private enum CodingKeys: String, CodingKey {
        case rules
        case values
    }

    init(rules: [搜索扩展筛选规则组] = []) {
        self.rules = rules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rules = try container.decodeIfPresent(
            [搜索扩展筛选规则组].self,
            forKey: .rules
        ) {
            self.init(rules: rules)
        } else if let values = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .values
        ) {
            self.init(values: values)
        } else {
            self.init()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rules, forKey: .rules)
    }

    init(values: Set<String>) {
        var conditionsByField: [搜索扩展筛选字段: Set<String>] = [:]
        for value in values {
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let field: 搜索扩展筛选字段?
            let normalizedValue: String
            switch parts[0] {
            case "recent", "upcoming":
                field = .releaseTime
                normalizedValue = parts[0]
            case "freeware", "official":
                field = .releaseAttribute
                normalizedValue = parts[0]
            default:
                field = Self.field(for: parts[0])
                normalizedValue = parts[1]
            }
            guard let field else { continue }
            conditionsByField[field, default: []].insert(normalizedValue)
        }
        let conditions = conditionsByField
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { 搜索扩展筛选条件(field: $0.key, stringValues: $0.value) }
        rules = conditions.isEmpty ? [] : [搜索扩展筛选规则组(conditions: conditions)]
    }

    var configuredRules: [搜索扩展筛选规则组] {
        rules.filter(\.isConfigured)
    }

    var isEmpty: Bool {
        configuredRules.isEmpty
    }

    var activeFilterCount: Int {
        configuredRules.reduce(0) { $0 + $1.configuredConditions.count }
    }

    var values: Set<String> {
        get {
            Set(
                configuredRules.flatMap { rule in
                    rule.configuredConditions.flatMap { condition in
                        condition.normalizedStringValues.map {
                            "\(condition.field.rawValue):\($0)"
                        }
                    }
                }
            )
        }
        set {
            self = Self(values: newValue)
        }
    }

    func contains(_ value: String) -> Bool {
        values.contains(value)
    }

    private static func field(for rawValue: String) -> 搜索扩展筛选字段? {
        if let field = 搜索扩展筛选字段(rawValue: rawValue) {
            return field
        }
        switch rawValue {
        case "birthday": return .birthday
        case "role": return .role
        case "trait": return .trait
        case "recent", "upcoming": return .releaseTime
        case "freeware", "official": return .releaseAttribute
        case "language": return .language
        case "platform": return .platform
        case "type": return .type
        default: return nil
        }
    }
}

struct 搜索分页响应<Item: Codable>: Codable {
    let results: [Item]
    let more: Bool
}

struct 视觉小说搜索标签: Codable, Hashable {
    let category: String?

    var isAdultContent: Bool {
        category == "ero"
    }
}

struct 视觉小说搜索结果: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let alttitle: String?
    let titles: [用户多语言标题]?
    let aliases: [String]?
    let released: String?
    let languages: [String]?
    let platforms: [String]?
    let image: 视觉小说图片?
    let length: Int?
    let length_minutes: Int?
    let rating: Double?
    let votecount: Int?
    let tags: [视觉小说搜索标签]?
    let developers: [视觉小说开发商]?
}

struct 角色搜索结果: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let original: String?
    let aliases: [String]?
    let image: 角色图片?
    /// 出场作品；综合搜索用它把角色挂在作品下面。旧缓存里没有这个字段。
    var vns: [角色搜索所属作品]? = nil

    /// 主要出场作品：主角、主要角色优先。
    nonisolated var 主要作品编号: String? {
        let 顺序 = ["main": 0, "primary": 1, "side": 2, "appears": 3]
        return vns?
            .min { (顺序[$0.role ?? ""] ?? 4) < (顺序[$1.role ?? ""] ?? 4) }?
            .id
    }
}

struct 角色搜索所属作品: Codable, Hashable {
    let id: String
    let role: String?
}

@MainActor
protocol VNDB搜索服务协议: AnyObject {
    func 搜索视觉小说(
        关键词: String,
        筛选: 视觉小说搜索筛选,
        排序: 视觉小说搜索排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<视觉小说搜索结果>

    func 搜索角色(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<角色搜索结果>

    func 搜索发行版本(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索发行版本>

    func 搜索制作人员(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索制作人员>

    func 搜索会社(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索会社>

    func 搜索角色(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<角色搜索结果>

    func 搜索发行版本(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索发行版本>

    func 搜索制作人员(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索制作人员>

    func 搜索会社(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索会社>
}

extension VNDB搜索服务协议 {
    func 搜索发行版本(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索发行版本> {
        throw VNDB服务错误.无效搜索关键词
    }

    func 搜索制作人员(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索制作人员> {
        throw VNDB服务错误.无效搜索关键词
    }

    func 搜索会社(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索会社> {
        throw VNDB服务错误.无效搜索关键词
    }

    func 搜索角色(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<角色搜索结果> {
        try await 搜索角色(关键词: 关键词, 页码: 页码, 每页: 每页)
    }

    func 搜索发行版本(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索发行版本> {
        try await 搜索发行版本(关键词: 关键词, 页码: 页码, 每页: 每页)
    }

    func 搜索制作人员(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索制作人员> {
        try await 搜索制作人员(关键词: 关键词, 页码: 页码, 每页: 每页)
    }

    func 搜索会社(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<探索会社> {
        try await 搜索会社(关键词: 关键词, 页码: 页码, 每页: 每页)
    }
}

enum 用户列表筛选: String, CaseIterable, Identifiable {
    case all
    case playing
    case finished
    case stalled
    case dropped
    case planning

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .all: return String(localized: "全部")
        case .playing: return String(localized: "游玩中")
        case .finished: return String(localized: "已游玩")
        case .stalled: return String(localized: "搁置")
        case .dropped: return String(localized: "抛弃")
        case .planning: return String(localized: "计划游玩")
        }
    }

    var localizedString: String {
        switch self {
        case .all: return String(localized: "全部")
        case .playing: return String(localized: "游玩中")
        case .finished: return String(localized: "已游玩")
        case .stalled: return String(localized: "搁置")
        case .dropped: return String(localized: "抛弃")
        case .planning: return String(localized: "计划游玩")
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "square.stack"
        case .playing: return "play"
        case .finished: return "checkmark.circle"
        case .stalled: return "stop.circle"
        case .dropped: return "play.slash"
        case .planning:
            return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        }
    }

    var labelID: Int? {
        switch self {
        case .all: return nil
        case .playing: return 1
        case .finished: return 2
        case .stalled: return 3
        case .dropped: return 4
        case .planning: return 5
        }
    }

    static var editableStatuses: [用户列表筛选] {
        [.playing, .finished, .stalled, .dropped, .planning]
    }
}

enum 用户列表排序: String, CaseIterable, Identifiable, Hashable {
    case lastModified = "lastmod"
    case title
    case rating = "vote"
    case averageRating = "rating"
    case releaseDate = "released"

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .lastModified: return String(localized: "按最近更改")
        case .title: return String(localized: "按标题")
        case .rating: return String(localized: "按评分")
        case .averageRating: return String(localized: "按平均评分")
        case .releaseDate: return String(localized: "按发行日期")
        }
    }

    var symbolName: String {
        switch self {
        case .lastModified: return "clock.arrow.circlepath"
        case .title: return "textformat"
        case .rating: return "star"
        case .averageRating: return "chart.bar.xaxis"
        case .releaseDate: return "calendar"
        }
    }

    var defaultIsDescending: Bool {
        self != .title
    }

    var apiSort: String {
        switch self {
        case .averageRating:
            return Self.title.rawValue
        default:
            return rawValue
        }
    }
}

struct 用户列表响应: Codable {
    let results: [用户列表项目]
    let more: Bool
}

struct 用户多语言标题: Codable, Hashable, Sendable {
    let lang: String
    let title: String
    let latin: String?
    let official: Bool
    let main: Bool
}

struct 用户列表项目: Codable, Identifiable, Hashable {
    let id: String
    let added: Int?
    let vote: Int?
    let started: String?
    let finished: String?
    let notes: String?
    let labels: [用户列表标签]?
    let releases: [用户列表发行版本]?
    let vn: 用户列表详细信息

    struct 用户列表标签: Codable, Hashable {
        let id: Int
        let label: String
    }

    struct 用户列表详细信息: Codable, Hashable {
        let title: String
        let titles: [用户多语言标题]?
        let image: 用户列表图片?
        let rating: Double?
        let votecount: Int?
        let released: String?

        struct 用户列表图片: Codable, Hashable {
            let url: String?
            let thumbnail: String?
            let sexual: Double?
            let violence: Double?
            let dims: [Int]?
        }
    }

    struct 用户列表发行版本: Codable, Hashable, Identifiable {
        let id: String
        let title: String
        let alttitle: String?
        let released: String?
        let list_status: Int
        let languages: [视觉小说发行语言]?
        let platforms: [String]?
    }

    var primaryStatus: 用户列表筛选? {
        guard let id = labels?.first(where: { 1...5 ~= $0.id })?.id else { return nil }
        return 用户列表筛选.allCases.first(where: { $0.labelID == id })
    }

    var primaryLabel: String? {
        primaryStatus?.localizedString
    }
}

nonisolated enum 资料库加入时间记录 {
    private static let keyPrefix = "library.addedAt."

    static func record(userID: String, vnID: String, at date: Date = .now) {
        guard !userID.isEmpty, !vnID.isEmpty else { return }
        UserDefaults.standard.set(
            date.timeIntervalSince1970,
            forKey: key(userID: userID, vnID: vnID)
        )
    }

    static func date(userID: String, vnID: String) -> Date? {
        guard !userID.isEmpty, !vnID.isEmpty else { return nil }
        let value = UserDefaults.standard.double(
            forKey: key(userID: userID, vnID: vnID)
        )
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    private static func key(userID: String, vnID: String) -> String {
        "\(keyPrefix)\(userID).\(vnID)"
    }
}

struct 视觉小说发行关联: Codable, Hashable {
    let id: String
    let releaseType: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case releaseType = "rtype"
    }
}

struct 视觉小说发行版本: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let alttitle: String?
    let released: String?
    let languages: [视觉小说发行语言]?
    let platforms: [String]?
    let official: Bool?
    let visualNovels: [视觉小说发行关联]?

    private enum CodingKeys: String, CodingKey {
        case id, title, alttitle, released, languages, platforms, official
        case visualNovels = "vns"
    }

    var releaseType: String? {
        visualNovels?.first?.releaseType
    }

    var displaySubtitle: String {
        var components: [String] = []

        if let released, !released.isEmpty {
            components.append(released)
        }

        let languageNames = (languages ?? [])
            .map(\.lang)
            .map { VNDB显示工具.语言名称($0) }
        if !languageNames.isEmpty {
            components.append(
                ListFormatter.localizedString(byJoining: languageNames)
            )
        }

        let platformNames = (platforms ?? [])
            .map { VNDB显示工具.平台名称($0) }
        if !platformNames.isEmpty {
            components.append(
                ListFormatter.localizedString(byJoining: platformNames)
            )
        }

        return components.joined(separator: "·")
    }
}

struct 视觉小说发行语言: Codable, Hashable {
    let lang: String
    let title: String?
    let latin: String?
    let mtl: Bool?
    let main: Bool?
}

enum 资料库编辑模式: String, Identifiable {
    case full
    case status
    case rating

    var id: String { rawValue }

    var navigationTitle: String {
        switch self {
        case .full: return String(localized: "编辑资料库")
        case .status: return String(localized: "更改状态")
        case .rating: return String(localized: "评分")
        }
    }
}

enum 剧透标签模糊设置: Int, CaseIterable, Identifiable {
    case off = 0
    case minorAndMajor = 1
    case majorOnly = 2

    var id: Int { rawValue }

    var sliderPosition: Double {
        switch self {
        case .minorAndMajor: return 0
        case .majorOnly: return 1
        case .off: return 2
        }
    }

    init(sliderPosition: Double) {
        switch Int(sliderPosition.rounded()) {
        case 0: self = .minorAndMajor
        case 1: self = .majorOnly
        default: self = .off
        }
    }

    var localizedTitle: String {
        switch self {
        case .minorAndMajor:
            return String(localized: "模糊所有剧透元素")
        case .majorOnly:
            return String(localized: "模糊严重剧透")
        case .off:
            return String(localized: "禁用")
        }
    }

    func shouldBlur(spoilerLevel: Int) -> Bool {
        switch self {
        case .minorAndMajor:
            return spoilerLevel >= 1
        case .majorOnly:
            return spoilerLevel >= 2
        case .off:
            return false
        }
    }
}

struct 视觉小说详细信息: Codable, Hashable, @unchecked Sendable {
    let id: String
    let title: String
    let titles: [用户多语言标题]?
    let aliases: [String]?
    let olang: String?
    let devstatus: Int?
    let released: String?
    let languages: [String]?
    let platforms: [String]?
    let image: 视觉小说图片?
    let length: Int?
    let length_minutes: Int?
    let length_votes: Int?
    let description: String?
    let rating: Double?
    let votecount: Int?
    let tags: [视觉小说标签]?
    let developers: [视觉小说开发商]?
    let screenshots: [视觉小说截图]?
    let relations: [视觉小说相关]?
    let staff: [视觉小说制作人员]?
    let va: [视觉小说声优关系]?
    let extlinks: [视觉小说外链]?

    var displayDevStatus: String {
        switch devstatus {
        case 0: return String(localized: "已完结")
        case 1: return String(localized: "开发中")
        case 2: return String(localized: "已取消")
        default: return String(localized: "未知")
        }
    }

    var displayLength: String {
        if let minutes = length_minutes {
            let hours = minutes / 60
            let remainder = minutes % 60
            if hours > 0, remainder > 0 {
                return String(localized: "\(hours)小时\(remainder)分钟")
            }
            if hours > 0 {
                return String(localized: "\(hours)小时")
            }
            return String(localized: "\(remainder)分钟")
        }

        switch length {
        case 1: return String(localized: "超短篇")
        case 2: return String(localized: "短篇")
        case 3: return String(localized: "中篇")
        case 4: return String(localized: "长篇")
        case 5: return String(localized: "超长篇")
        default: return String(localized: "未知")
        }
    }

    var cleanDescription: String? {
        guard let description else { return nil }
        var text = description
        text = text.replacingOccurrences(
            of: "\\[/?(?:url|spoiler|quote|raw|code|b|i|u|s)(?:=[^\\]]*)?\\]",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var sortedTags: [视觉小说标签] {
        (tags ?? []).sorted { $0.rating > $1.rating }
    }
}

struct 视觉小说图片: Codable, Hashable {
    let id: String?
    let url: String?
    let thumbnail: String?
    let sexual: Double?
    let violence: Double?
    let dims: [Int]?
}

struct 视觉小说标签: Codable, Hashable {
    let id: String
    let name: String
    let rating: Double
    let spoiler: Int
    let lie: Bool?
    let category: String?

    var categoryTitle: String {
        switch category {
        case "ero": return String(localized: "色情")
        case "tech": return String(localized: "技术")
        default: return String(localized: "内容")
        }
    }

    var isMajorSpoiler: Bool {
        spoiler >= 2
    }

    var isAdultContent: Bool {
        category == "ero"
    }
}

struct 视觉小说开发商: Codable, Hashable {
    let id: String
    let name: String
    let original: String?
}

struct 视觉小说截图: Codable, Hashable, Identifiable {
    let id: String
    let url: String?
    let thumbnail: String?
    let sexual: Double?
    let violence: Double?
}

struct 视觉小说相关: Codable, Hashable {
    let id: String
    let title: String
    let titles: [用户多语言标题]?
    let relation: String
    let relation_official: Bool?
    let image: 视觉小说图片?

    var relationTitle: String {
        switch relation {
        case "seq": return String(localized: "续作")
        case "preq": return String(localized: "前作")
        case "set": return String(localized: "平行设定")
        case "alt": return String(localized: "其他版本")
        case "char": return String(localized: "相同角色")
        case "side": return String(localized: "外传")
        case "par": return String(localized: "系列")
        case "ser": return String(localized: "系列作品")
        case "fan": return String(localized: "同人")
        case "orig": return String(localized: "原作")
        default: return String(localized: "相关")
        }
    }
}

struct 视觉小说制作人员: Codable, Hashable {
    let eid: Int?
    let role: String
    let note: String?
    let id: String
    let name: String
    let original: String?

    var roleTitle: String {
        switch role {
        case "scenario":
            return String(
                localized: "staff_role.scenario",
                defaultValue: "Scenario",
                table: "VNDBStaffRoles"
            )
        case "chardesign":
            return String(
                localized: "staff_role.chardesign",
                defaultValue: "Character Design",
                table: "VNDBStaffRoles"
            )
        case "art":
            return String(
                localized: "staff_role.art",
                defaultValue: "Art",
                table: "VNDBStaffRoles"
            )
        case "music":
            return String(
                localized: "staff_role.music",
                defaultValue: "Music",
                table: "VNDBStaffRoles"
            )
        case "songs":
            return String(
                localized: "staff_role.songs",
                defaultValue: "Songs",
                table: "VNDBStaffRoles"
            )
        case "director":
            return String(
                localized: "staff_role.director",
                defaultValue: "Director",
                table: "VNDBStaffRoles"
            )
        case "staff":
            return String(
                localized: "staff_role.staff",
                defaultValue: "Staff",
                table: "VNDBStaffRoles"
            )
        default:
            return String(
                localized: "staff_role.other",
                defaultValue: "Other",
                table: "VNDBStaffRoles"
            )
        }
    }

    var roleSortOrder: Int {
        switch role {
        case "scenario": return 0
        case "chardesign": return 1
        case "art": return 2
        case "music": return 3
        case "songs": return 4
        case "director": return 5
        case "staff": return 6
        default: return 99
        }
    }

    var roleGroupKey: String {
        switch role {
        case "scenario", "chardesign", "art", "music", "songs", "director", "staff":
            return role
        default:
            return "__other__"
        }
    }
}

struct 人员基础信息: Codable, Hashable {
    let id: String
    let name: String
    let original: String?
}

struct 角色图片: Codable, Hashable {
    let url: String?
    let dims: [Int]?
    let sexual: Double?
    let violence: Double?
}

struct 视觉小说声优关系: Codable, Hashable {
    let note: String?
    let staff: 人员基础信息
    let character: 角色信息

    struct 角色信息: Codable, Hashable {
        let id: String
        let name: String
        let original: String?
        let aliases: [String]?
        let image: 角色图片?
    }
}

struct 视觉小说角色声优分组: Identifiable {
    let relationships: [视觉小说声优关系]

    var id: String { primary.character.id }
    var primary: 视觉小说声优关系 { relationships[0] }

    static func 合并(
        _ relationships: [视觉小说声优关系]
    ) -> [视觉小说角色声优分组] {
        var groups: [[视觉小说声优关系]] = []
        var groupByCharacterID: [String: Int] = [:]
        var groupByIdentity: [String: Int] = [:]

        for relationship in relationships {
            let character = relationship.character
            let identity = duplicateIdentity(for: character)
            let existingIndex = groupByCharacterID[character.id]
                ?? identity.flatMap { groupByIdentity[$0] }

            if let existingIndex {
                groups[existingIndex].append(relationship)
                groupByCharacterID[character.id] = existingIndex
                if let identity {
                    groupByIdentity[identity] = existingIndex
                }
            } else {
                let index = groups.endIndex
                groups.append([relationship])
                groupByCharacterID[character.id] = index
                if let identity {
                    groupByIdentity[identity] = index
                }
            }
        }

        return groups.compactMap { relationships in
            guard let preferredCharacterID = relationships
                .map(\.character.id)
                .min(by: characterIDPrecedes) else {
                return nil
            }
            let ordered = relationships.filter {
                $0.character.id == preferredCharacterID
            } + relationships.filter {
                $0.character.id != preferredCharacterID
            }
            return 视觉小说角色声优分组(relationships: ordered)
        }
    }

    private static func duplicateIdentity(
        for character: 视觉小说声优关系.角色信息
    ) -> String? {
        guard let imageURL = character.image?.url?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !imageURL.isEmpty else {
            return nil
        }
        let name = character.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return imageURL.lowercased() + "|" + name.lowercased()
    }

    private static func characterIDPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        let lhsNumber = Int(lhs.drop(while: { !$0.isNumber }))
        let rhsNumber = Int(rhs.drop(while: { !$0.isNumber }))
        switch (lhsNumber, rhsNumber) {
        case let (lhs?, rhs?): return lhs < rhs
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
}

struct 角色详细信息: Codable, Hashable {
    let id: String
    let name: String
    let original: String?
    let aliases: [String]?
    let description: String?
    let image: 角色图片?
    let blood_type: String?
    let height: Int?
    let weight: Int?
    let bust: Int?
    let waist: Int?
    let hips: Int?
    let cup: String?
    let age: Int?
    let birthday: [Int]?
    let sex: [String?]?
    let gender: [String?]?
    let vns: [角色视觉小说关系]?
    let traits: [角色特征]?

    var cleanDescription: String? {
        guard let description else { return nil }
        var text = description
        text = text.replacingOccurrences(
            of: "\\[/?(?:url|spoiler|quote|raw|code|b|i|u|s)(?:=[^\\]]*)?\\]",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "\\n", with: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct 角色视觉小说关系: Codable, Hashable {
    let id: String
    let title: String
    let titles: [用户多语言标题]?
    let image: 视觉小说图片?
    let spoiler: Int
    let role: String

    var roleTitle: String {
        switch role {
        case "main": return String(localized: "主角")
        case "primary": return String(localized: "主要角色")
        case "side": return String(localized: "次要角色")
        default: return String(localized: "登场")
        }
    }
}

struct 角色特征: Codable, Hashable {
    let id: String
    let name: String
    let group_name: String
    let spoiler: Int
    let lie: Bool?
    let sexual: Bool?
}

struct 视觉小说外链: Codable, Hashable {
    let url: String
    let label: String
    let name: String?

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return label
    }
}

enum 探索视觉小说来源: Hashable, Codable, Identifiable, Sendable {
    case popular
    case topRated
    case recent
    case upcoming
    case tag(id: String, name: String? = nil)
    case language(code: String, name: String? = nil)
    case platform(code: String, name: String? = nil)
    case length(Int)
    case releaseYear(Int)
    case producer(id: String, name: String? = nil)
    case staff(id: String, name: String? = nil)

    var id: String {
        switch self {
        case .popular: return "popular"
        case .topRated: return "top-rated"
        case .recent: return "recent"
        case .upcoming: return "upcoming"
        case let .tag(id, _): return "tag:\(id)"
        case let .language(code, _): return "language:\(code)"
        case let .platform(code, _): return "platform:\(code)"
        case let .length(value): return "length:\(value)"
        case let .releaseYear(year): return "release-year:\(year)"
        case let .producer(id, _): return "producer:\(id)"
        case let .staff(id, _): return "staff:\(id)"
        }
    }

    var localizedTitle: String {
        switch self {
        case .popular: return String(localized: "热门作品")
        case .topRated: return String(localized: "高分作品")
        case .recent: return String(localized: "最近发行")
        case .upcoming: return String(localized: "即将发行")
        case let .tag(_, name): return name ?? String(localized: "游戏标签")
        case let .language(code, name): return name ?? code.uppercased()
        case let .platform(code, name): return name ?? code
        case let .length(value): return String(localized: "篇幅\(value)")
        case let .releaseYear(year):
            return String(format: String(localized: "%lld年"), Int64(year))
        case let .producer(_, name): return name ?? String(localized: "制作会社")
        case let .staff(_, name): return name ?? String(localized: "制作人员")
        }
    }

    static let homeFeeds: [Self] = [.popular, .topRated, .recent, .upcoming]
}

enum 探索发行来源: Hashable, Codable, Identifiable, Sendable {
    case recent
    case upcoming
    case freeware
    case official
    case language(code: String, name: String? = nil)
    case platform(code: String, name: String? = nil)
    case visualNovel(id: String, title: String? = nil)
    case producer(id: String, name: String? = nil)

    var id: String {
        switch self {
        case .recent: return "recent"
        case .upcoming: return "upcoming"
        case .freeware: return "freeware"
        case .official: return "official"
        case let .language(code, _): return "language:\(code)"
        case let .platform(code, _): return "platform:\(code)"
        case let .visualNovel(id, _): return "vn:\(id)"
        case let .producer(id, _): return "producer:\(id)"
        }
    }
}

enum 探索角色来源: Hashable, Codable, Identifiable, Sendable {
    case recentlyAdded
    case trait(id: String, name: String? = nil)
    case role(String)
    case birthday(month: Int, day: Int? = nil)
    case visualNovel(id: String, title: String? = nil)

    var id: String {
        switch self {
        case .recentlyAdded: return "recently-added"
        case let .trait(id, _): return "trait:\(id)"
        case let .role(role): return "role:\(role)"
        case let .birthday(month, day): return "birthday:\(month):\(day ?? 0)"
        case let .visualNovel(id, _): return "vn:\(id)"
        }
    }
}

enum 探索制作人员来源: Hashable, Codable, Identifiable, Sendable {
    case recentlyAdded
    case language(code: String, name: String? = nil)
    case gender(String)
    case role(code: String, name: String? = nil)

    var id: String {
        switch self {
        case .recentlyAdded: return "recently-added"
        case let .language(code, _): return "language:\(code)"
        case let .gender(value): return "gender:\(value)"
        case let .role(code, _): return "role:\(code)"
        }
    }
}

enum 探索会社类型: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case company = "co"
    case individual = "in"
    case amateurGroup = "ng"

    var id: String { rawValue }
}

enum 探索会社来源: Hashable, Codable, Identifiable, Sendable {
    case recentlyAdded
    case language(code: String, name: String? = nil)
    case type(探索会社类型)

    var id: String {
        switch self {
        case .recentlyAdded: return "recently-added"
        case let .language(code, _): return "language:\(code)"
        case let .type(type): return "type:\(type.rawValue)"
        }
    }
}

enum 探索标签类别: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case content = "cont"
    case sexual = "ero"
    case technical = "tech"

    var id: String { rawValue }
}

enum 探索标签来源: Hashable, Codable, Identifiable, Sendable {
    case popular
    case category(探索标签类别)

    var id: String {
        switch self {
        case .popular: return "popular"
        case let .category(category): return "category:\(category.rawValue)"
        }
    }
}

enum 探索特征来源: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case popular

    var id: String { rawValue }
}

enum 探索源: Hashable, Codable, Identifiable, Sendable {
    case visualNovel(探索视觉小说来源)
    case release(探索发行来源)
    case character(探索角色来源)
    case staff(探索制作人员来源)
    case producer(探索会社来源)
    case tag(探索标签来源)
    case trait(探索特征来源)

    var id: String {
        switch self {
        case let .visualNovel(source): return "vn:\(source.id)"
        case let .release(source): return "release:\(source.id)"
        case let .character(source): return "character:\(source.id)"
        case let .staff(source): return "staff:\(source.id)"
        case let .producer(source): return "producer:\(source.id)"
        case let .tag(source): return "tag:\(source.id)"
        case let .trait(source): return "trait:\(source.id)"
        }
    }
}

enum 探索缓存状态: String, Codable, Hashable, Sendable {
    case network
    case fresh
    case stale
}

struct 探索页面<Item: Codable>: Codable {
    let results: [Item]
    let more: Bool
    let count: Int?
    let cacheState: 探索缓存状态

    init(
        results: [Item],
        more: Bool,
        count: Int? = nil,
        cacheState: 探索缓存状态 = .network
    ) {
        self.results = results
        self.more = more
        self.count = count
        self.cacheState = cacheState
    }

    private enum CodingKeys: String, CodingKey {
        case results, more, count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = try container.decode([Item].self, forKey: .results)
        more = try container.decodeIfPresent(Bool.self, forKey: .more) ?? false
        count = try container.decodeIfPresent(Int.self, forKey: .count)
        cacheState = .network
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(results, forKey: .results)
        try container.encode(more, forKey: .more)
        try container.encodeIfPresent(count, forKey: .count)
    }

    func markingCache(_ state: 探索缓存状态) -> Self {
        Self(results: results, more: more, count: count, cacheState: state)
    }
}

extension 探索视觉小说 {
    var 详情多语言标题: [用户多语言标题]? {
        titles?.map {
            用户多语言标题(
                lang: $0.lang,
                title: $0.title,
                latin: $0.latin,
                official: $0.official ?? false,
                main: $0.main ?? false
            )
        }
    }

    var 详情图片: 视觉小说图片? {
        image.map {
            视觉小说图片(
                id: $0.id,
                url: $0.url,
                thumbnail: $0.thumbnail,
                sexual: $0.sexual,
                violence: $0.violence,
                dims: $0.dims
            )
        }
    }
}

extension 探索发行作品 {
    var 详情多语言标题: [用户多语言标题]? {
        titles?.map {
            用户多语言标题(
                lang: $0.lang,
                title: $0.title,
                latin: $0.latin,
                official: $0.official ?? false,
                main: $0.main ?? false
            )
        }
    }
}

extension 探索角色 {
    var 详情图片: 角色图片? {
        image.map {
            角色图片(
                url: $0.url,
                dims: $0.dims,
                sexual: $0.sexual,
                violence: $0.violence
            )
        }
    }
}

struct 探索制作人员别名: Codable, Hashable, Sendable {
    let aliasID: Int
    let name: String
    let latin: String?
    let isMain: Bool?

    private enum CodingKeys: String, CodingKey {
        case name, latin
        case aliasID = "aid"
        case isMain = "ismain"
    }
}

struct 探索制作人员: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let aliasID: Int?
    let isMain: Bool?
    let name: String
    let original: String?
    let language: String?
    let gender: String?
    let description: String?
    let externalLinks: [探索外链]?
    let aliases: [探索制作人员别名]?

    private enum CodingKeys: String, CodingKey {
        case id, name, original, gender, description, aliases
        case aliasID = "aid"
        case isMain = "ismain"
        case language = "lang"
        case externalLinks = "extlinks"
    }
}

struct 探索会社: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let aliases: [String]?
    let language: String?
    let type: String?
    let description: String?
    let externalLinks: [探索外链]?

    private enum CodingKeys: String, CodingKey {
        case id, name, original, aliases, type, description
        case language = "lang"
        case externalLinks = "extlinks"
    }
}

struct 探索标签: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let aliases: [String]?
    let description: String?
    let category: String?
    let searchable: Bool?
    let applicable: Bool?
    let visualNovelCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, description, category, searchable, applicable
        case visualNovelCount = "vn_count"
    }
}

struct 探索特征: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let aliases: [String]?
    let description: String?
    let searchable: Bool?
    let applicable: Bool?
    let sexual: Bool?
    let groupID: String?
    let groupName: String?
    let characterCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, aliases, description, searchable, applicable, sexual
        case groupID = "group_id"
        case groupName = "group_name"
        case characterCount = "char_count"
    }
}

struct 探索语录作品: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let titles: [探索多语言标题]?
    let image: 探索图片?
}

struct 探索语录角色: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let image: 探索图片?
}

struct 探索语录: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let quote: String
    let score: Int?
    let visualNovel: 探索语录作品?
    let character: 探索语录角色?

    private enum CodingKeys: String, CodingKey {
        case id, quote, score, character
        case visualNovel = "vn"
    }
}

extension 探索推荐理由 {
    var text: String {
        switch self {
        case let .sharedTag(name):
            return String(localized: "符合你偏好的游戏标签“\(name)”")
        case let .sameProducer(name):
            return String(
                localized: "与你资料库中的作品来自同一开发与发行商“\(name)”"
            )
        case let .preferredLanguage(code):
            return String(
                localized: "支持你常用的语言：\(VNDB显示工具.语言名称(code))"
            )
        case let .preferredPlatform(code):
            return String(
                localized: "支持你常用的平台：\(VNDB显示工具.平台名称(code))"
            )
        case let .preferredLength(length):
            return String(localized: "与你偏好的游戏篇幅相近：\(length)")
        case let .preferredCharacterTrait(name):
            return String(localized: "包含你偏好的角色特征“\(name)”")
        case let .typeAndCharacter(tags, character, traits):
            let typeText = ListFormatter.localizedString(byJoining: tags.prefix(2).map { "“\($0)”" })
            let traitText = ListFormatter.localizedString(byJoining: traits.prefix(2).map { "“\($0)”" })
            if let character, !character.isEmpty {
                return String(localized: "符合你偏好的\(typeText)类型；主要角色“\(character)”具有\(traitText)等你经常偏好的特征。")
            }
            return String(localized: "符合你偏好的\(typeText)类型，并包含具有\(traitText)等偏好特征的主要角色。")
        case let .mainlyType(tags):
            let typeText = ListFormatter.localizedString(byJoining: tags.prefix(2).map { "“\($0)”" })
            return String(localized: "主要依据游戏类型推荐：本作符合你偏好的\(typeText)类型，角色资料不足。")
        case .similarUsers:
            return String(localized: "与你偏好相近的VNDB用户也喜欢这部作品。")
        case .highlyRated:
            return String(localized: "探索推荐：作品质量较可靠，但个性化证据有限。")
        }
    }
}
