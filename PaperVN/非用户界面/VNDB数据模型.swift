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

struct 搜索扩展筛选条件: Codable, Hashable, Identifiable {
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

struct 搜索扩展筛选规则组: Codable, Hashable, Identifiable {
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

struct 搜索扩展筛选: Codable, Hashable {
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
            return 平台符号.计划中
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
            of: "\\[/?[a-zA-Z]+[^\\]]*\\]",
            with: "",
            options: .regularExpression
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
            of: "\\[/?[a-zA-Z]+[^\\]]*\\]",
            with: "",
            options: .regularExpression
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

struct 探索多语言标题: Codable, Hashable, Sendable {
    let lang: String
    let title: String
    let latin: String?
    let official: Bool?
    let main: Bool?
}

struct 探索图片: Codable, Hashable, Sendable {
    let id: String?
    let url: String?
    let thumbnail: String?
    let dims: [Int]?
    let sexual: Double?
    let violence: Double?
}

struct 探索外链: Codable, Hashable, Sendable {
    let url: String
    let label: String
    let name: String?
    let id: 探索外链标识?
}

enum 探索外链标识: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .integer(try container.decode(Int.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        }
    }
}

struct 探索标签关联: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let rating: Double
    let spoiler: Int
    let lie: Bool?
    let category: String?
}

struct 探索会社摘要: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let lang: String?
    let type: String?
}

struct 探索视觉小说关系: Codable, Hashable, Sendable {
    let id: String
    let relation: String
    let relationOfficial: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, relation
        case relationOfficial = "relation_official"
    }
}

struct 探索视觉小说: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let alttitle: String?
    let titles: [探索多语言标题]?
    let aliases: [String]?
    let released: String?
    let languages: [String]?
    let platforms: [String]?
    let image: 探索图片?
    let length: Int?
    let lengthMinutes: Int?
    let rating: Double?
    let voteCount: Int?
    let tags: [探索标签关联]?
    let developers: [探索会社摘要]?
    let relations: [探索视觉小说关系]?

    private enum CodingKeys: String, CodingKey {
        case id, title, alttitle, titles, aliases, released, languages, platforms
        case image, length, rating, tags, developers, relations
        case lengthMinutes = "length_minutes"
        case voteCount = "votecount"
    }

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

struct 探索发行语言: Codable, Hashable, Sendable {
    let lang: String
    let title: String?
    let latin: String?
    let mtl: Bool?
    let main: Bool?
}

struct 探索发行介质: Codable, Hashable, Sendable {
    let medium: String
    let quantity: Int

    private enum CodingKeys: String, CodingKey {
        case medium
        case quantity = "qty"
    }
}

struct 探索发行作品: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let titles: [探索多语言标题]?
    let image: 探索图片?
    let releaseType: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, titles, image
        case releaseType = "rtype"
    }

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

struct 探索发行会社: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let developer: Bool?
    let publisher: Bool?
}

struct 探索发行图片: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let url: String?
    let thumbnail: String?
    let dims: [Int]?
    let sexual: Double?
    let violence: Double?
    let type: String?
    let visualNovelID: String?
    let languages: [String]?
    let photo: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, url, thumbnail, dims, sexual, violence, type, languages, photo
        case visualNovelID = "vn"
    }
}

enum 探索发行分辨率: Codable, Hashable, Sendable {
    case dimensions([Int])
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([Int].self) {
            self = .dimensions(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .dimensions(value): try container.encode(value)
        case let .text(value): try container.encode(value)
        }
    }
}

struct 探索发行版本: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let alttitle: String?
    let releaseType: String?
    let languages: [探索发行语言]?
    let platforms: [String]?
    let media: [探索发行介质]?
    let visualNovels: [探索发行作品]?
    let producers: [探索发行会社]?
    let images: [探索发行图片]?
    let released: String?
    let minimumAge: Int?
    let patch: Bool?
    let freeware: Bool?
    let uncensored: Bool?
    let official: Bool?
    let hasAdultContent: Bool?
    let resolution: 探索发行分辨率?
    let engine: String?
    let voiced: Int?
    let notes: String?
    let gtin: String?
    let catalog: String?
    let externalLinks: [探索外链]?

    private enum CodingKeys: String, CodingKey {
        case id, title, alttitle, languages, platforms, media, producers, images
        case releaseType = "rtype"
        case released, patch, freeware, uncensored, official, resolution
        case engine, voiced, notes, gtin, catalog
        case visualNovels = "vns"
        case minimumAge = "minage"
        case hasAdultContent = "has_ero"
        case externalLinks = "extlinks"
    }
}

struct 探索角色作品: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let titles: [探索多语言标题]?
    let image: 探索图片?
    let spoiler: Int?
    let role: String?
}

struct 探索角色特征关联: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let groupName: String
    let spoiler: Int?
    let lie: Bool?
    let sexual: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, spoiler, lie, sexual
        case groupName = "group_name"
    }
}

struct 探索角色: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let aliases: [String]?
    let description: String?
    let image: 探索图片?
    let bloodType: String?
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
    let visualNovels: [探索角色作品]?
    let traits: [探索角色特征关联]?

    private enum CodingKeys: String, CodingKey {
        case id, name, original, aliases, description, image, height, weight
        case bust, waist, hips, cup, age, birthday, sex, gender, traits
        case bloodType = "blood_type"
        case visualNovels = "vns"
    }

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

struct VNDB探索统计: Codable, Hashable, Sendable {
    let visualNovels: Int
    let releases: Int
    let characters: Int
    let staff: Int
    let producers: Int
    let tags: Int
    let traits: Int

    private enum CodingKeys: String, CodingKey {
        case releases, staff, producers, tags, traits
        case visualNovels = "vn"
        case characters = "chars"
    }
}

struct VNDB探索枚举选项: Codable, Hashable, Identifiable, Sendable {
    let code: String
    let name: String

    var id: String { code }
}

struct VNDB探索目录: Codable, Hashable, Sendable {
    let languages: [VNDB探索枚举选项]
    let platforms: [VNDB探索枚举选项]
    let staffRoles: [VNDB探索枚举选项]
    let media: [VNDB探索枚举选项]
    let releaseTypes: [VNDB探索枚举选项]
}

enum 探索推荐理由: Codable, Hashable, Sendable {
    case sharedTag(String)
    case sameProducer(String)
    case preferredLanguage(String)
    case preferredPlatform(String)
    case preferredLength(Int)
    case preferredCharacterTrait(String)
    case typeAndCharacter(tags: [String], character: String?, traits: [String])
    case mainlyType(tags: [String])
    case similarUsers
    case highlyRated

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

enum 探索推荐置信度: String, Codable, Hashable, Sendable {
    case high
    case medium
    case exploratory

    var text: String {
        switch self {
        case .high: return String(localized: "高度符合你的偏好")
        case .medium: return String(localized: "可能符合你的偏好")
        case .exploratory: return String(localized: "尝试拓展你的兴趣")
        }
    }
}

struct 探索推荐证据: Codable, Hashable, Sendable {
    let gameTags: [String]
    let characterID: String?
    let characterName: String?
    let characterTraits: [String]
    let gameScore: Double
    let characterScore: Double?
    let collaborativeScore: Double?
    let confidence: 探索推荐置信度
    let isExploration: Bool
    let hasCharacterData: Bool?

    private enum CodingKeys: String, CodingKey {
        case gameTags, characterID, characterName, characterTraits
        case gameScore, characterScore, collaborativeScore, confidence
        case isExploration, hasCharacterData
    }

    var hasCharacterEvidence: Bool {
        characterScore != nil && !characterTraits.isEmpty
    }
}

struct 探索推荐: Codable, Hashable, Identifiable, Sendable {
    let visualNovel: 探索视觉小说
    let score: Double
    let reason: 探索推荐理由
    let evidence: 探索推荐证据?

    nonisolated init(
        visualNovel: 探索视觉小说,
        score: Double,
        reason: 探索推荐理由,
        evidence: 探索推荐证据? = nil
    ) {
        self.visualNovel = visualNovel
        self.score = score
        self.reason = reason
        self.evidence = evidence
    }

    var id: String { visualNovel.id }
}

struct VNDB偏好标签书架: Codable, Hashable, Identifiable, Sendable {
    let tagID: String
    let name: String
    let items: [探索视觉小说]

    var id: String { tagID }
}

struct 探索用户列表标签: Codable, Hashable, Sendable {
    let id: Int
    let label: String
}

struct 探索用户列表视觉小说: Codable, Hashable, Sendable {
    let title: String
    let titles: [探索多语言标题]?
    let image: 探索图片?
    let rating: Double?
    let voteCount: Int?
    let released: String?
    let languages: [String]?
    let platforms: [String]?
    let length: Int?
    let lengthMinutes: Int?
    let tags: [探索标签关联]?
    let developers: [探索会社摘要]?
    let relations: [探索视觉小说关系]?

    private enum CodingKeys: String, CodingKey {
        case title, titles, image, rating, released, languages, platforms, length, tags, developers, relations
        case voteCount = "votecount"
        case lengthMinutes = "length_minutes"
    }

    nonisolated func asVisualNovel(id: String) -> 探索视觉小说 {
        探索视觉小说(
            id: id,
            title: title,
            alttitle: nil,
            titles: titles,
            aliases: nil,
            released: released,
            languages: languages,
            platforms: platforms,
            image: image,
            length: length,
            lengthMinutes: lengthMinutes,
            rating: rating,
            voteCount: voteCount,
            tags: tags,
            developers: developers,
            relations: relations
        )
    }
}

struct 探索用户列表项目: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let added: Int?
    let voted: Int?
    let lastModified: Int?
    let vote: Int?
    let started: String?
    let finished: String?
    let labels: [探索用户列表标签]?
    let vn: 探索用户列表视觉小说

    private enum CodingKeys: String, CodingKey {
        case id, added, voted, vote, started, finished, labels, vn
        case lastModified = "lastmod"
    }
}

struct 探索用户列表响应: Codable, Sendable {
    let results: [探索用户列表项目]
    let more: Bool
    let count: Int?

    private enum CodingKeys: String, CodingKey {
        case results, more, count
    }

    init(
        results: [探索用户列表项目],
        more: Bool,
        count: Int? = nil
    ) {
        self.results = results
        self.more = more
        self.count = count
    }
}

struct VNDB兴趣原型: Codable, Hashable, Sendable {
    var tagWeights: [String: Double]
    var traitWeights: [String: Double]
    var confidence: Double
}

struct VNDB游戏兴趣原型: Codable, Hashable, Sendable {
    var tagWeights: [String: Double]
    var confidence: Double
    var share: Double
}

struct VNDB角色兴趣原型: Codable, Hashable, Sendable {
    var traitWeights: [String: Double]
    var confidence: Double
    var share: Double
}

struct VNDB偏好校准样本: Hashable, Sendable {
    let visualNovel: 探索视觉小说
    let signal: Double
}

struct VNDB本地推荐画像V2: Codable, Hashable, Sendable {
    var prototypes: [VNDB兴趣原型] = []
    var gamePrototypes: [VNDB游戏兴趣原型] = []
    var characterPrototypes: [VNDB角色兴趣原型] = []
    var tagWeights: [String: Double] = [:]
    var tagNames: [String: String] = [:]
    var tagPairWeights: [String: Double] = [:]
    var traitWeights: [String: Double] = [:]
    var traitNames: [String: String] = [:]
    var traitGroups: [String: String] = [:]
    var traitGroupWeights: [String: Double] = [:]
    var producerWeights: [String: Double] = [:]
    var producerNames: [String: String] = [:]
    var languageWeights: [String: Double] = [:]
    var platformWeights: [String: Double] = [:]
    var lengthWeights: [Int: Double] = [:]
    var releaseEraWeights: [Int: Double] = [:]
    var historicalPresentationAcceptance: [Int: Double] = [:]
    var historicalPresentationEvidence: [Int: Double] = [:]
    var audienceAcceptance: [String: Double] = [:]
    var audienceEvidence: [String: Double] = [:]
    var itemFeedback: [String: Double] = [:]
    var seedIDs: Set<String> = []
    var positiveSeedIDs: Set<String> = []
    var tagIDF: [String: Double] = [:]
    var tagSpecificity: [String: Double] = [:]
    var ignoredTagIDs: Set<String> = []
    var traitIDF: [String: Double] = [:]

    nonisolated var hasPositiveSignal: Bool {
        !positiveSeedIDs.isEmpty && (!gamePrototypes.isEmpty || !prototypes.isEmpty)
    }

    nonisolated var hasReliableCharacterSignal: Bool {
        !characterPrototypes.isEmpty
    }
}

struct VNDB候选角色证据: Hashable, Sendable {
    let characterID: String
    let characterName: String
    let traitID: String
    let traitName: String
    let groupName: String
    let role: String
    var hasImage: Bool = true
    var reliability: Double = 1
    var canExplain: Bool = true

    nonisolated init(
        characterID: String,
        characterName: String,
        traitID: String,
        traitName: String,
        groupName: String,
        role: String,
        hasImage: Bool = true,
        reliability: Double = 1,
        canExplain: Bool = true
    ) {
        self.characterID = characterID
        self.characterName = characterName
        self.traitID = traitID
        self.traitName = traitName
        self.groupName = groupName
        self.role = role
        self.hasImage = hasImage
        self.reliability = reliability
        self.canExplain = canExplain
    }
}

nonisolated enum VNDB本地推荐算法V2 {
    static func 建立画像(
        library: [探索用户列表项目],
        characters: [探索角色],
        globalTagFrequencies: [String: Int] = [:],
        globalTraitFrequencies: [String: Int] = [:],
        globalVisualNovelCount: Int? = nil,
        globalCharacterCount: Int? = nil,
        calibrationSamples: [VNDB偏好校准样本] = []
    ) -> VNDB本地推荐画像V2 {
        var profile = VNDB本地推荐画像V2()
        profile.seedIDs = Set(library.map(\.id))
        profile.seedIDs.formUnion(calibrationSamples.map { $0.visualNovel.id })

        let votes = library.compactMap(\.vote).sorted()
        let medianVote: Double? = if votes.isEmpty {
            nil
        } else if votes.count.isMultiple(of: 2) {
            Double(votes[votes.count / 2 - 1] + votes[votes.count / 2]) / 2
        } else {
            Double(votes[votes.count / 2])
        }
        let medianAbsoluteDeviation: Double? = medianVote.map { median in
            let deviations = votes.map { abs(Double($0) - median) }.sorted()
            guard !deviations.isEmpty else { return 10 }
            if deviations.count.isMultiple(of: 2) {
                return (
                    deviations[deviations.count / 2 - 1]
                        + deviations[deviations.count / 2]
                ) / 2
            }
            return deviations[deviations.count / 2]
        }
        let voteScale = max(10, 1.4826 * (medianAbsoluteDeviation ?? 10))
        for item in library {
            let signal = feedback(
                for: item,
                medianVote: medianVote,
                voteScale: voteScale,
                hasReliableVoteDistribution: votes.count >= 5
            )
            profile.itemFeedback[item.id] = signal
            if signal > 0.08 { profile.positiveSeedIDs.insert(item.id) }
        }
        let positiveCalibrationCount = calibrationSamples.count { $0.signal > 0.08 }
        let negativeCalibrationCount = calibrationSamples.count { $0.signal < -0.08 }
        for sample in calibrationSamples {
            let id = sample.visualNovel.id
            let directionCount = sample.signal > 0.08
                ? positiveCalibrationCount
                : (sample.signal < -0.08 ? negativeCalibrationCount : 0)
            let calibrationScale = directionCount > 0
                ? min(0.55, 0.15 + 0.08 * Double(directionCount - 1))
                : 0.10
            let calibratedSignal = sample.signal * calibrationScale
            let signal: Double
            if let librarySignal = profile.itemFeedback[id] {
                signal = min(1, max(-1, librarySignal + 0.35 * calibratedSignal))
            } else {
                signal = calibratedSignal
            }
            profile.itemFeedback[id] = signal
            if signal > 0.08 { profile.positiveSeedIDs.insert(id) }
        }

        let libraryIDs = Set(library.map(\.id))
        let seriesScales = 系列证据缩放(
            library,
            feedback: profile.itemFeedback
        )
        profile.positiveSeedIDs.subtract(libraryIDs)
        for item in library {
            profile.itemFeedback[item.id] = (profile.itemFeedback[item.id] ?? 0)
                * (seriesScales[item.id] ?? 1)
            if (profile.itemFeedback[item.id] ?? 0) > 0.08 {
                profile.positiveSeedIDs.insert(item.id)
            }
        }

        let historicalCutoffs = [1999, 2004, 2009, 2014]
        var historicalPositive: [Int: Double] = [:]
        var historicalNegative: [Int: Double] = [:]
        var audiencePositive: [String: Double] = [:]
        var audienceNegative: [String: Double] = [:]
        for item in library {
            let signal = profile.itemFeedback[item.id] ?? 0
            if let year = releaseYear(item.vn.released) {
                let experience = historicalExperienceConfidence(item)
                if experience > 0 {
                    let distinctiveness = historicalWorkDistinctiveness(
                        voteCount: item.vn.voteCount
                    )
                    for cutoff in historicalCutoffs where year <= cutoff {
                        historicalPositive[cutoff, default: 0] += max(0, signal)
                            * experience * distinctiveness
                        historicalNegative[cutoff, default: 0] += abs(min(0, signal))
                            * experience * (0.75 + 0.25 * distinctiveness)
                    }
                }
            }

            let audienceExperience = audienceExperienceConfidence(item)
            guard audienceExperience > 0 else { continue }
            let boundaryKeys = Set(
                (item.vn.tags ?? []).compactMap(audienceBoundaryKey)
            )
            for key in boundaryKeys {
                audiencePositive[key, default: 0] += max(0, signal)
                    * audienceExperience
                audienceNegative[key, default: 0] += abs(min(0, signal))
                    * audienceExperience
            }
        }
        for cutoff in historicalCutoffs {
            let positive = historicalPositive[cutoff] ?? 0
            let negative = historicalNegative[cutoff] ?? 0
            let evidence = positive + negative
            profile.historicalPresentationEvidence[cutoff] = evidence
            profile.historicalPresentationAcceptance[cutoff] = min(
                1,
                max(0, (positive - 0.85 * negative) / (0.80 + evidence))
            )
        }
        for key in Set(audiencePositive.keys).union(audienceNegative.keys) {
            let positive = audiencePositive[key] ?? 0
            let negative = audienceNegative[key] ?? 0
            let evidence = positive + negative
            profile.audienceEvidence[key] = evidence
            profile.audienceAcceptance[key] = min(
                1,
                max(0, (positive - negative) / (0.45 + evidence))
            )
        }

        let profileItems: [(id: String, vn: 探索视觉小说, signal: Double)] =
            library.map { item in
                (
                    item.id,
                    item.vn.asVisualNovel(id: item.id),
                    profile.itemFeedback[item.id] ?? 0
                )
            } + calibrationSamples.map { sample in
                (
                    sample.visualNovel.id,
                    sample.visualNovel,
                    profile.itemFeedback[sample.visualNovel.id] ?? sample.signal
                )
            }
        let uniqueProfileItems = Dictionary(
            profileItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, second in
                abs(second.signal) > abs(first.signal) ? second : first
            }
        ).values

        let documentCount = max(1, uniqueProfileItems.count)
        var tagDocumentFrequency: [String: Int] = [:]
        var visualPresentationTagIDs: Set<String> = []
        for item in uniqueProfileItems {
            let tags = item.vn.tags ?? []
            profile.ignoredTagIDs.formUnion(
                tags.filter { !recommendationEligibleTag($0) }.map(\.id)
            )
            let eligibleTags = tags.filter(recommendationEligibleTag)
            visualPresentationTagIDs.formUnion(
                eligibleTags.filter(isVisualPresentationTag).map(\.id)
            )
            let ids = Set(eligibleTags.map(\.id))
            for id in ids { tagDocumentFrequency[id, default: 0] += 1 }
        }
        for (id, localFrequency) in tagDocumentFrequency {
            let globalFrequency = globalTagFrequencies[id]
            let hasGlobalFrequency = globalFrequency != nil
                && globalVisualNovelCount != nil
            let corpusCount = hasGlobalFrequency
                ? max(documentCount, globalVisualNovelCount ?? documentCount)
                : documentCount
            let frequency = hasGlobalFrequency
                ? (globalFrequency ?? localFrequency)
                : localFrequency
            profile.tagIDF[id] = min(
                4,
                log((Double(corpusCount) + 1) / (Double(frequency) + 1)) + 1
            )
            let specificity = tagSpecificity(
                globalFrequency: globalFrequency,
                globalDocumentCount: globalVisualNovelCount
            )
            profile.tagSpecificity[id] = specificity
            let globalRatio = tagGlobalRatio(
                frequency: globalFrequency,
                documentCount: globalVisualNovelCount
            )
            if (globalRatio ?? 0) >= 0.30
                && !visualPresentationTagIDs.contains(id) {
                profile.ignoredTagIDs.insert(id)
            }
        }
        if let globalVisualNovelCount {
            for (id, frequency) in globalTagFrequencies where profile.tagIDF[id] == nil {
                profile.tagIDF[id] = min(
                    4,
                    log(
                        (Double(globalVisualNovelCount) + 1)
                            / (Double(frequency) + 1)
                    ) + 1
                )
                let ratio = Double(frequency) / Double(max(1, globalVisualNovelCount))
                profile.tagSpecificity[id] = frequencySpecificity(ratio)
                if ratio >= 0.30 { profile.ignoredTagIDs.insert(id) }
            }
        }

        let relevantCharacters = characters.filter { character in
            (character.visualNovels ?? []).contains {
                profile.seedIDs.contains($0.id)
            }
        }
        let characterCount = max(1, relevantCharacters.count)
        var traitDocumentFrequency: [String: Int] = [:]
        for character in relevantCharacters {
            let ids = Set((character.traits ?? []).filter {
                $0.lie != true
            }.map(\.id))
            for id in ids { traitDocumentFrequency[id, default: 0] += 1 }
        }
        let traitCorpusCount = max(
            characterCount,
            globalCharacterCount ?? characterCount
        )
        for (id, localFrequency) in traitDocumentFrequency {
            let frequency = globalTraitFrequencies[id] ?? localFrequency
            profile.traitIDF[id] = log(
                (Double(traitCorpusCount) + 1) / (Double(frequency) + 1)
            ) + 1
        }
        for (id, frequency) in globalTraitFrequencies where profile.traitIDF[id] == nil {
            profile.traitIDF[id] = log(
                (Double(traitCorpusCount) + 1) / (Double(frequency) + 1)
            ) + 1
        }

        var itemTraits: [String: [String: Double]] = [:]
        var traitExposure: [String: Double] = [:]
        var traitGroupExposure: [String: Double] = [:]
        var positiveTraitDocuments: [String: Set<String>] = [:]
        var negativeTraitDocuments: [String: Set<String>] = [:]
        var characterCountsByVisualNovel: [String: Int] = [:]
        for character in relevantCharacters {
            for relation in character.visualNovels ?? []
            where profile.seedIDs.contains(relation.id) {
                characterCountsByVisualNovel[relation.id, default: 0] += 1
            }
        }
        for character in relevantCharacters {
            let validTraits = (character.traits ?? []).filter {
                $0.lie != true
            }
            guard !validTraits.isEmpty else { continue }
            var grouped: [String: [探索角色特征关联]] = [:]
            for trait in validTraits {
                grouped[trait.groupName, default: []].append(trait)
                profile.traitGroups[trait.id] = trait.groupName
            }
            var characterVector: [String: Double] = [:]
            for traits in grouped.values {
                let groupScale = 1 / sqrt(Double(max(1, traits.count)))
                for trait in traits {
                    characterVector[trait.id] = (profile.traitIDF[trait.id] ?? 1)
                        * groupScale
                        * spoilerReliability(trait.spoiler)
                    if trait.spoiler == 0 {
                        profile.traitNames[trait.id] = trait.name
                    }
                }
            }
            characterVector = normalized(characterVector)

            for relation in character.visualNovels ?? [] {
                guard let signal = profile.itemFeedback[relation.id], signal != 0 else {
                    continue
                }
                let role = roleWeight(relation.role)
                    * spoilerReliability(relation.spoiler)
                let characterCountScale = 1 / sqrt(Double(
                    max(1, characterCountsByVisualNovel[relation.id] ?? 0)
                ))
                for (traitID, traitValue) in characterVector {
                    let evidence = role * traitValue * characterCountScale
                    let value = signal * evidence
                    profile.traitWeights[traitID, default: 0] += value
                    traitExposure[traitID, default: 0] += abs(signal) * evidence
                    if signal > 0.08 {
                        positiveTraitDocuments[traitID, default: []].insert(relation.id)
                    } else if signal < -0.08 {
                        negativeTraitDocuments[traitID, default: []].insert(relation.id)
                    }
                    itemTraits[relation.id, default: [:]][traitID, default: 0] += evidence
                }
                for groupName in grouped.keys {
                    profile.traitGroupWeights[groupName, default: 0] += signal * role * characterCountScale
                    traitGroupExposure[groupName, default: 0] += abs(signal) * role * characterCountScale
                }
            }
        }

        for traitID in profile.traitWeights.keys {
            let shrunk = (profile.traitWeights[traitID] ?? 0)
                / (1.5 + (traitExposure[traitID] ?? 0))
            let repeated = 独立证据作品数(
                positiveTraitDocuments[traitID],
                seriesScales: seriesScales
            ) >= 2 || 独立证据作品数(
                negativeTraitDocuments[traitID],
                seriesScales: seriesScales
            ) >= 2
            profile.traitWeights[traitID] = repeated ? shrunk : shrunk * 0.65
        }
        for groupName in profile.traitGroupWeights.keys {
            profile.traitGroupWeights[groupName] = (profile.traitGroupWeights[groupName] ?? 0)
                / (1.5 + (traitGroupExposure[groupName] ?? 0))
        }

        var tagExposure: [String: Double] = [:]
        var pairExposure: [String: Double] = [:]
        var releaseEraExposure: [Int: Double] = [:]
        var rawPrototypes: [VNDB兴趣原型] = []
        for item in uniqueProfileItems {
            let signal = item.signal
            guard signal != 0 else { continue }
            var tagVector: [String: Double] = [:]
            let validTags = (item.vn.tags ?? []).filter {
                recommendationEligibleTag($0)
                    && !profile.ignoredTagIDs.contains($0.id)
            }
            let categoryCounts = Dictionary(
                grouping: validTags,
                by: { $0.category ?? "unknown" }
            ).mapValues(\.count)
            for tag in validTags {
                let idf = profile.tagIDF[tag.id] ?? 1
                let categoryScale = 1 / sqrt(Double(
                    max(1, categoryCounts[tag.category ?? "unknown"] ?? 1)
                ))
                let strength = pow(max(0, min(3, tag.rating)) / 3, 1.5)
                    * idf
                    * (profile.tagSpecificity[tag.id] ?? 1)
                    * categoryScale
                    * spoilerReliability(tag.spoiler)
                tagVector[tag.id, default: 0] += strength
                profile.tagWeights[tag.id, default: 0] += signal * strength
                tagExposure[tag.id, default: 0] += abs(signal) * strength
                if tag.spoiler == 0 {
                    profile.tagNames[tag.id] = tag.name
                }
            }

            let pairTags = tagVector.sorted { lhs, rhs in
                if abs(lhs.value - rhs.value) > 0.000_001 {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }.prefix(10).map { ($0.key, $0.value) }
            if pairTags.count >= 2 {
                for lhs in 0..<(pairTags.count - 1) {
                    for rhs in (lhs + 1)..<pairTags.count {
                        let key = pairKey(pairTags[lhs].0, pairTags[rhs].0)
                        let strength = sqrt(pairTags[lhs].1 * pairTags[rhs].1)
                        profile.tagPairWeights[key, default: 0] += signal * strength
                        pairExposure[key, default: 0] += abs(signal) * strength
                    }
                }
            }

            for producer in item.vn.developers ?? [] {
                profile.producerWeights[producer.id, default: 0] += signal
                profile.producerNames[producer.id] = producer.name
            }
            for language in item.vn.languages ?? [] {
                profile.languageWeights[language, default: 0] += signal
            }
            for platform in item.vn.platforms ?? [] {
                profile.platformWeights[platform, default: 0] += signal
            }
            if let length = item.vn.length {
                profile.lengthWeights[length, default: 0] += signal
            }
            if let era = releaseEra(item.vn.released) {
                profile.releaseEraWeights[era, default: 0] += signal
                releaseEraExposure[era, default: 0] += abs(signal)
            }

            guard signal > 0.08 else { continue }
            let traitVector = itemTraits[item.id] ?? [:]
            guard !tagVector.isEmpty || !traitVector.isEmpty else { continue }
            rawPrototypes.append(
                VNDB兴趣原型(
                    tagWeights: normalized(tagVector),
                    traitWeights: normalized(traitVector),
                    confidence: min(1.5, max(0.1, signal))
                )
            )
        }

        for tagID in profile.tagWeights.keys {
            profile.tagWeights[tagID] = (profile.tagWeights[tagID] ?? 0)
                / (1.75 + (tagExposure[tagID] ?? 0))
        }
        let shrunkPairs = profile.tagPairWeights.map { key, value in
            (
                key,
                value / (1.5 + (pairExposure[key] ?? 0))
            )
        }.sorted { abs($0.1) > abs($1.1) }.prefix(80)
        profile.tagPairWeights = Dictionary(uniqueKeysWithValues: shrunkPairs)
        for era in profile.releaseEraWeights.keys {
            profile.releaseEraWeights[era] = (profile.releaseEraWeights[era] ?? 0)
                / (1.5 + (releaseEraExposure[era] ?? 0))
        }
        profile.prototypes = mergedPrototypes(rawPrototypes, limit: 6)

        let gameClusters = mergedPrototypes(
            rawPrototypes.compactMap { prototype in
                guard !prototype.tagWeights.isEmpty else { return nil }
                return VNDB兴趣原型(
                    tagWeights: prototype.tagWeights,
                    traitWeights: [:],
                    confidence: prototype.confidence
                )
            },
            limit: 6
        )
        let gameConfidenceTotal = max(
            0.000_001,
            gameClusters.reduce(0) { $0 + $1.confidence }
        )
        profile.gamePrototypes = gameClusters.map { prototype in
            VNDB游戏兴趣原型(
                tagWeights: prototype.tagWeights,
                confidence: prototype.confidence,
                share: prototype.confidence / gameConfidenceTotal
            )
        }

        let reliableTraitIDs = Set(positiveTraitDocuments.compactMap { traitID, documents in
            独立证据作品数(
                documents,
                seriesScales: seriesScales
            ) >= 2 && (profile.traitWeights[traitID] ?? 0) > 0
                ? traitID
                : nil
        })
        let characterClusters = mergedPrototypes(
            rawPrototypes.compactMap { prototype in
                let reliableTraits = prototype.traitWeights.filter {
                    reliableTraitIDs.contains($0.key)
                }
                guard !reliableTraits.isEmpty else { return nil }
                return VNDB兴趣原型(
                    tagWeights: [:],
                    traitWeights: normalized(reliableTraits),
                    confidence: min(1, prototype.confidence * 0.90)
                )
            },
            limit: 6
        )
        let characterConfidenceTotal = max(
            0.000_001,
            characterClusters.reduce(0) { $0 + $1.confidence }
        )
        profile.characterPrototypes = characterClusters.map { prototype in
            VNDB角色兴趣原型(
                traitWeights: prototype.traitWeights,
                confidence: prototype.confidence,
                share: prototype.confidence / characterConfidenceTotal
            )
        }
        return profile
    }

    private static func 系列证据缩放(
        _ library: [探索用户列表项目],
        feedback: [String: Double]
    ) -> [String: Double] {
        let ids = Set(library.map(\.id))
        guard ids.count > 1 else { return [:] }
        let seriesRelations: Set<String> = [
            "seq", "preq", "side", "par", "ser", "set", "alt"
        ]
        let relatedIDs = Set(library.lazy.flatMap { item in
            (item.vn.relations ?? []).compactMap { relation in
                relation.relationOfficial == true
                    && seriesRelations.contains(relation.relation)
                    ? relation.id
                    : nil
            }
        })
        let allIDs = ids.union(relatedIDs)
        var parent = Dictionary(uniqueKeysWithValues: allIDs.map { ($0, $0) })

        func root(of id: String) -> String {
            var value = id
            while let next = parent[value], next != value {
                value = next
            }
            return value
        }

        func union(_ lhs: String, _ rhs: String) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            guard lhsRoot != rhsRoot else { return }
            if lhsRoot < rhsRoot {
                parent[rhsRoot] = lhsRoot
            } else {
                parent[lhsRoot] = rhsRoot
            }
        }

        for item in library {
            for relation in item.vn.relations ?? []
            where relation.relationOfficial == true
                && seriesRelations.contains(relation.relation) {
                union(item.id, relation.id)
            }
        }

        let groups = Dictionary(grouping: ids, by: { root(of: $0) })
        var result: [String: Double] = [:]
        for group in groups.values where group.count > 1 {
            let positive = group.filter { (feedback[$0] ?? 0) > 0 }
            let negative = group.filter { (feedback[$0] ?? 0) < 0 }
            for sameDirectionGroup in [positive, negative]
            where sameDirectionGroup.count > 1 {
                let ordered = sameDirectionGroup.sorted { lhs, rhs in
                    let lhsMagnitude = abs(feedback[lhs] ?? 0)
                    let rhsMagnitude = abs(feedback[rhs] ?? 0)
                    if abs(lhsMagnitude - rhsMagnitude) > 0.000_001 {
                        return lhsMagnitude > rhsMagnitude
                    }
                    return lhs.localizedStandardCompare(rhs) == .orderedAscending
                }
                guard let representative = ordered.first else { continue }
                result[representative] = 1

                let additionalCount = Double(ordered.count - 1)
                let additionalEvidence = 0.75
                    * (1 - exp(-0.70 * additionalCount))
                let additionalScale = additionalEvidence / additionalCount
                for id in ordered.dropFirst() {
                    result[id] = additionalScale
                }
            }
        }
        return result
    }

    private static func 独立证据作品数(
        _ ids: Set<String>?,
        seriesScales: [String: Double]
    ) -> Int {
        ids?.count { (seriesScales[$0] ?? 1) >= 0.999 } ?? 0
    }

    static func 偏好标签书架(
        candidates: [探索视觉小说],
        profile: VNDB本地推荐画像V2,
        excludedIDs: Set<String>,
        charactersByVisualNovel: [String: [VNDB候选角色证据]]? = nil,
        maximumShelves: Int = 4,
        minimumItems: Int = 4
    ) -> [VNDB偏好标签书架] {
        guard maximumShelves > 0, minimumItems > 0 else { return [] }

        let preferredTags = profile.tagWeights.compactMap { tagID, weight
            -> (id: String, name: String, weight: Double)? in
            guard weight > 0.08,
                  let name = profile.tagNames[tagID],
                  !name.isEmpty else { return nil }
            return (tagID, name, weight)
        }.sorted { lhs, rhs in
            if abs(lhs.weight - rhs.weight) > 0.000_001 {
                return lhs.weight > rhs.weight
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }

        var shelves: [VNDB偏好标签书架] = []
        var usedNames: Set<String> = []
        for preferredTag in preferredTags {
            guard usedNames.insert(preferredTag.name).inserted else { continue }
            let items = candidates.compactMap { candidate
                -> (item: 探索视觉小说, relevance: Double)? in
                guard !excludedIDs.contains(candidate.id),
                      !profile.seedIDs.contains(candidate.id),
                      (candidate.tags ?? []).count(where: { $0.lie != true }) >= 5,
                      !包含禁止的3D表现(candidate.tags ?? []) else { return nil }
                if let charactersByVisualNovel {
                    guard 推荐作品准入(
                        candidate,
                        characterEvidence: charactersByVisualNovel[candidate.id] ?? []
                    ) else { return nil }
                }
                let relation = (candidate.tags ?? []).first {
                    $0.id == preferredTag.id
                        && $0.lie != true
                        && $0.spoiler == 0
                }
                guard let relation else { return nil }
                let tagStrength = max(0, min(3, relation.rating)) / 3
                let voteConfidence = min(
                    1,
                    log10(Double(max(1, candidate.voteCount ?? 1))) / 4
                )
                let quality = max(0, ((candidate.rating ?? 50) - 50) / 50)
                return (
                    candidate,
                    0.80 * tagStrength + 0.20 * quality * voteConfidence
                )
            }.sorted { lhs, rhs in
                if abs(lhs.relevance - rhs.relevance) > 0.000_001 {
                    return lhs.relevance > rhs.relevance
                }
                return lhs.item.id.localizedStandardCompare(rhs.item.id)
                    == .orderedAscending
            }.map(\.item)

            guard items.count >= minimumItems else { continue }
            shelves.append(
                VNDB偏好标签书架(
                    tagID: preferredTag.id,
                    name: preferredTag.name,
                    items: items
                )
            )
            if shelves.count == maximumShelves { break }
        }
        return shelves
    }

    static func 角色证据按作品分组(
        _ characters: [探索角色]
    ) -> [String: [VNDB候选角色证据]] {
        var result: [String: [VNDB候选角色证据]] = [:]
        for character in characters {
            let traits = (character.traits ?? []).filter {
                $0.lie != true
            }
            for relation in character.visualNovels ?? [] {
                for trait in traits {
                    result[relation.id, default: []].append(
                        VNDB候选角色证据(
                            characterID: character.id,
                            characterName: character.name,
                            traitID: trait.id,
                            traitName: trait.name,
                            groupName: trait.groupName,
                            role: relation.role ?? "appears",
                            hasImage: character.image?.url
                                .map { !$0.isEmpty } == true,
                            reliability: spoilerReliability(relation.spoiler)
                                * spoilerReliability(trait.spoiler),
                            canExplain: relation.spoiler == 0
                                && trait.spoiler == 0
                        )
                    )
                }
            }
        }
        return result
    }

    static func 排序候选(
        _ candidates: [探索视觉小说],
        charactersByVisualNovel: [String: [VNDB候选角色证据]],
        profile: VNDB本地推荐画像V2,
        excludedIDs: Set<String>,
        limit: Int,
        minimumExplorationCount: Int = 8,
        collaborativeScores: [String: Double] = [:]
    ) -> [探索推荐] {
        guard limit > 0, profile.hasPositiveSignal else { return [] }
        let unique = Dictionary(
            candidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var scored = unique.values.compactMap { candidate -> Scored? in
            guard !excludedIDs.contains(candidate.id),
                  !profile.seedIDs.contains(candidate.id) else { return nil }
            let characterEvidence = charactersByVisualNovel[candidate.id] ?? []
            guard 推荐作品准入(candidate, characterEvidence: characterEvidence) else {
                return nil
            }
            return evaluate(
                candidate,
                characterEvidence: characterEvidence,
                profile: profile,
                collaborativeScore: collaborativeScores[candidate.id] ?? 0
            )
        }.filter { value in
            value.total > (value.isTypeFallback ? 0.04 : 0.08)
        }
        let seriesKeys = 系列分组(scored.map(\.vn))
        for index in scored.indices {
            scored[index].seriesKey = seriesKeys[scored[index].vn.id]
        }

        var selected: [Scored] = []
        var interestCounts: [Int: Int] = [:]
        var seriesCounts: [String: Int] = [:]
        let reliableCandidateCount = scored.count { !$0.hasSparseEvidence }
        let shouldLimitSparseEvidence = reliableCandidateCount >= min(limit, 12)
        let maximumSparseEvidence = max(2, min(5, limit / 10))
        while selected.count < limit, !scored.isEmpty {
            let sparseSelected = selected.filter(\.hasSparseEvidence).count
            let evidenceEligibleIndices = scored.indices.filter { index in
                !shouldLimitSparseEvidence
                    || !scored[index].hasSparseEvidence
                    || sparseSelected < maximumSparseEvidence
            }
            let seriesEligibleIndices = evidenceEligibleIndices.filter { index in
                guard let seriesKey = scored[index].seriesKey else { return true }
                return (seriesCounts[seriesKey] ?? 0) < 2
            }
            let eligibleIndices = seriesEligibleIndices.isEmpty
                ? evidenceEligibleIndices
                : seriesEligibleIndices
            guard !eligibleIndices.isEmpty else { break }
            let bestIndex = eligibleIndices.max { lhs, rhs in
                let lhsScore = mmrScore(
                    scored[lhs],
                    selected: selected,
                    interestCounts: interestCounts
                )
                let rhsScore = mmrScore(
                    scored[rhs],
                    selected: selected,
                    interestCounts: interestCounts
                )
                if abs(lhsScore - rhsScore) < 0.000_001 {
                    return scored[lhs].vn.id > scored[rhs].vn.id
                }
                return lhsScore < rhsScore
            }!
            let choice = scored.remove(at: bestIndex)
            selected.append(choice)
            interestCounts[choice.interestIndex, default: 0] += 1
            if let seriesKey = choice.seriesKey {
                seriesCounts[seriesKey, default: 0] += 1
            }
        }

        let requestedExplorationCount = min(
            max(0, minimumExplorationCount),
            max(0, selected.count - 1)
        )
        let naturalExploration = selected.filter(\.isTypeFallback).count
        let additionalExploration = max(
            0,
            requestedExplorationCount - naturalExploration
        )
        let additionalExplorationIDs = Set(
            selected.filter { !$0.isTypeFallback }
                .sorted { lhs, rhs in
                    if abs(lhs.total - rhs.total) > 0.000_001 {
                        return lhs.total < rhs.total
                    }
                    return lhs.vn.id.localizedStandardCompare(rhs.vn.id)
                        == .orderedAscending
                }
                .prefix(additionalExploration)
                .map { $0.vn.id }
        )

        return selected.map { value in
            let tagNames = value.strongestTagIDs.compactMap { profile.tagNames[$0] }
            let traitNames = value.strongestTraitIDs.compactMap { profile.traitNames[$0] }
            let isExploration = value.isTypeFallback
                || additionalExplorationIDs.contains(value.vn.id)
            let confidence: 探索推荐置信度 = if isExploration {
                .exploratory
            } else if value.total >= 0.55 && (value.character ?? 0) >= 0.35 {
                .high
            } else {
                .medium
            }
            return 探索推荐(
                visualNovel: value.vn,
                score: value.total,
                reason: reason(for: value, profile: profile),
                evidence: 探索推荐证据(
                    gameTags: tagNames,
                    characterID: value.characterID,
                    characterName: value.characterName,
                    characterTraits: traitNames,
                    gameScore: value.game,
                    characterScore: value.character,
                    collaborativeScore: value.collaborative > 0
                        ? value.collaborative
                        : nil,
                    confidence: confidence,
                    isExploration: isExploration,
                    hasCharacterData: true
                )
            )
        }
    }

    private struct Scored {
        let vn: 探索视觉小说
        let total: Double
        let game: Double
        let character: Double?
        let collaborative: Double
        let metadata: Double
        let interestIndex: Int
        let strongestTagIDs: [String]
        let strongestTraitIDs: [String]
        let characterID: String?
        let characterName: String?
        let hasImportantCharacterMatch: Bool
        let isTypeFallback: Bool
        let hasSparseEvidence: Bool
        var seriesKey: String?
    }

    private static func evaluate(
        _ vn: 探索视觉小说,
        characterEvidence: [VNDB候选角色证据],
        profile: VNDB本地推荐画像V2,
        collaborativeScore: Double
    ) -> Scored? {
        var tags: [String: Double] = [:]
        var matchedTags: [(String, Double)] = []
        var tagInformationMass = 0.0
        var matchedTagInformationMass = 0.0
        var nonTechnicalTagInformationMass = 0.0
        var nonTechnicalSpecificTagCount = 0
        var visualPresentationPreferenceMatch = 0.0
        let strongestPositiveTagWeight = max(
            0.000_001,
            profile.tagWeights.values.filter { $0 > 0 }.max() ?? 0
        )
        let validTags = (vn.tags ?? []).filter {
            recommendationEligibleTag($0)
                && !profile.ignoredTagIDs.contains($0.id)
        }
        let tagCategories = Dictionary(
            validTags.map { ($0.id, $0.category ?? "unknown") },
            uniquingKeysWith: { first, _ in first }
        )
        let categoryCounts = Dictionary(
            grouping: validTags,
            by: { $0.category ?? "unknown" }
        ).mapValues(\.count)
        for tag in validTags {
            let categoryScale = 1 / sqrt(Double(
                max(1, categoryCounts[tag.category ?? "unknown"] ?? 1)
            ))
            let ratingStrength = pow(max(0, min(3, tag.rating)) / 3, 1.5)
            let specificity = profile.tagSpecificity[tag.id] ?? 1
            let reliability = spoilerReliability(tag.spoiler)
            let value = ratingStrength
                * (profile.tagIDF[tag.id] ?? 1)
                * specificity
                * categoryScale
                * reliability
            tags[tag.id, default: 0] += value
            tagInformationMass += ratingStrength * specificity * reliability
            if tag.category != "tech" {
                let information = ratingStrength * specificity * reliability
                nonTechnicalTagInformationMass += information
                if information >= 0.40 {
                    nonTechnicalSpecificTagCount += 1
                }
            }
            let preference = max(0, profile.tagWeights[tag.id] ?? 0)
            if preference > 0, isVisualPresentationTag(tag) {
                visualPresentationPreferenceMatch = max(
                    visualPresentationPreferenceMatch,
                    min(1, preference / strongestPositiveTagWeight)
                )
            }
            if preference > 0, tag.spoiler == 0 {
                matchedTags.append((tag.id, value * preference))
                let relativePreference = min(
                    1,
                    preference / strongestPositiveTagWeight
                )
                matchedTagInformationMass += ratingStrength
                    * specificity
                    * reliability
                    * relativePreference
            }
        }
        tags = normalized(tags)
        let strongestTagIDs = matchedTags.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)

        let pairTags = tags.sorted { $0.value > $1.value }
            .prefix(10).map { ($0.key, $0.value) }
        var positivePairScore = 0.0
        var negativePairPenalty = 0.0
        if pairTags.count >= 2 {
            for lhs in 0..<(pairTags.count - 1) {
                for rhs in (lhs + 1)..<pairTags.count {
                    let weight = profile.tagPairWeights[
                        pairKey(pairTags[lhs].0, pairTags[rhs].0)
                    ] ?? 0
                    let strength = sqrt(pairTags[lhs].1 * pairTags[rhs].1)
                    positivePairScore += max(0, weight) * strength
                    negativePairPenalty += abs(min(0, weight)) * strength
                }
            }
        }
        positivePairScore = clampPositive(positivePairScore)

        var characters: [(
            id: String,
            name: String,
            role: String,
            traits: [String: Double],
            explainableTraitIDs: Set<String>
        )] = []
        let maximumTraitGroupMagnitude = profile.traitGroupWeights.values
            .map { abs($0) }.max() ?? 0
        for group in Dictionary(grouping: characterEvidence, by: \.characterID).values {
            guard let first = group.first else { continue }
            let role = group.max { roleWeight($0.role) < roleWeight($1.role) }?.role ?? first.role
            var traitsByGroup: [String: [(String, Double)]] = [:]
            var explainableTraitIDs: Set<String> = []
            for evidence in group {
                let idf = profile.traitIDF[evidence.traitID] ?? 1
                traitsByGroup[evidence.groupName, default: []].append((
                    evidence.traitID,
                    idf * evidence.reliability
                ))
                if evidence.canExplain {
                    explainableTraitIDs.insert(evidence.traitID)
                }
            }
            var vector: [String: Double] = [:]
            for (groupName, traits) in traitsByGroup {
                let groupScale = 1 / sqrt(Double(max(1, traits.count)))
                let groupSalience = maximumTraitGroupMagnitude > 0
                    ? min(
                        1,
                        abs(profile.traitGroupWeights[groupName] ?? 0)
                            / maximumTraitGroupMagnitude
                    )
                    : 0
                for (traitID, idf) in traits {
                    vector[traitID, default: 0] += idf
                        * groupScale
                        * (1 + 0.35 * groupSalience)
                }
            }
            characters.append((
                first.characterID,
                first.characterName,
                role,
                normalized(vector),
                explainableTraitIDs
            ))
        }

        var bestIndex = 0
        var bestGame = -1.0
        for (index, prototype) in profile.gamePrototypes.enumerated() {
            let game = max(0, cosine(tags, prototype.tagWeights))
            if game > bestGame {
                bestIndex = index
                bestGame = game
            }
        }
        if profile.gamePrototypes.isEmpty {
            for (index, prototype) in profile.prototypes.enumerated() {
                let game = max(0, cosine(tags, prototype.tagWeights))
                if game > bestGame {
                    bestIndex = index
                    bestGame = game
                }
            }
        }
        let matchedTagCount = Set(matchedTags.map(\.0)).count
        let tagCountConfidence = min(1, Double(validTags.count) / 8)
        let tagInformationConfidence = min(1, tagInformationMass / 4)
        let matchedTagConfidence = min(1, Double(matchedTagCount) / 3)
        let matchedTagInformationConfidence = min(
            1,
            matchedTagInformationMass / 1.75
        )
        let tagEvidenceConfidence = pow(
            tagCountConfidence
                * tagInformationConfidence
                * matchedTagConfidence
                * matchedTagInformationConfidence,
            0.25
        )
        let preferenceSupportConfidence = matchedTagConfidence
        bestGame = clampPositive(
            0.82 * max(0, bestGame) + 0.18 * positivePairScore
        ) * tagEvidenceConfidence * preferenceSupportConfidence

        var rankedCharacters: [(
            id: String,
            name: String,
            role: String,
            score: Double,
            matchedTraits: [String],
            allTraits: [String: Double]
        )] = []
        let positiveTraitWeights = profile.traitWeights.filter { $0.value > 0 }
        let positiveTraitVector = normalized(positiveTraitWeights)
        let strongestPositiveTrait = positiveTraitWeights.values.max() ?? 0
        let positiveTraitMass = positiveTraitWeights.values.reduce(0, +)
        let directTraitConfidence = min(
            1,
            2 * strongestPositiveTrait + 0.25 * positiveTraitMass
        )
        for character in characters {
            var prototypeMatch = 0.0
            for prototype in profile.characterPrototypes {
                prototypeMatch = max(
                    prototypeMatch,
                    cosine(character.traits, prototype.traitWeights)
                )
            }
            let directTraitMatch = max(
                0,
                cosine(character.traits, positiveTraitVector)
            ) * directTraitConfidence
            let preferenceMatch = max(prototypeMatch, directTraitMatch)
            let matchedTraits = character.traits.compactMap { traitID, weight -> (String, Double)? in
                let preference = max(0, profile.traitWeights[traitID] ?? 0)
                return preference > 0 && character.explainableTraitIDs.contains(traitID)
                    ? (traitID, weight * preference)
                    : nil
            }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
            rankedCharacters.append((
                character.id,
                character.name,
                character.role,
                max(0, preferenceMatch) * roleWeight(character.role),
                matchedTraits,
                character.traits
            ))
        }
        rankedCharacters.sort { $0.score > $1.score }
        let bestCharacter = rankedCharacters.first
        let secondCharacterScore = rankedCharacters.dropFirst().first?.score ?? 0
        let characterScore: Double? = bestCharacter.map {
            min(1, 0.8 * $0.score + 0.2 * secondCharacterScore)
        }
        let hasImportantCharacterMatch = bestCharacter.map {
            ($0.role == "main" || $0.role == "primary") && $0.score >= 0.20
        } ?? false
        guard hasUsablePrimaryCharacterEvidence(characterEvidence) else {
            return nil
        }
        let technicalTagCount = validTags.count { $0.category == "tech" }
        let nonTechnicalTagCount = validTags.count - technicalTagCount
        let isTechnicalOnlySparseCandidate = technicalTagCount >= 3
            && technicalTagCount >= max(3, nonTechnicalTagCount)
            && (nonTechnicalSpecificTagCount < 3
                || nonTechnicalTagInformationMass < 1.50)
        guard !isTechnicalOnlySparseCandidate else { return nil }

        let audienceBoundaries = Set(
            (vn.tags ?? []).compactMap(audienceBoundaryKey)
        )
        for boundary in audienceBoundaries {
            let evidence = profile.audienceEvidence[boundary] ?? 0
            let acceptance = profile.audienceAcceptance[boundary] ?? 0
            guard evidence >= 0.18, acceptance >= 0.18 else { return nil }
        }

        let historicalPresentation = historicalPresentationAssessment(
            vn,
            profile: profile,
            visualPresentationPreferenceMatch: visualPresentationPreferenceMatch
        )
        let lacksPreferredCharacterEvidence = profile.hasReliableCharacterSignal
            && !hasImportantCharacterMatch
        let hasStrongTagEvidence = validTags.count >= 4
            && tagInformationMass >= 1.75
            && matchedTagCount >= 2
            && matchedTagInformationMass >= 1
            && bestGame >= 0.22
        let negativeTagPenalty = abs(tags.reduce(0.0) {
            $0 + min(0, profile.tagWeights[$1.key] ?? 0) * $1.value
        })
        let negativeContentTagPenalty = tags.reduce(0.0) { partial, tag in
            guard tagCategories[tag.key] == "cont"
                    || tagCategories[tag.key] == "ero" else { return partial }
            return partial
                + abs(min(0, profile.tagWeights[tag.key] ?? 0)) * tag.value
        }
        let negativePrimaryTraitPenalty = characters.reduce(0.0) { result, character in
            guard character.role == "main" || character.role == "primary" else {
                return result
            }
            let penalty = abs(character.traits.reduce(0.0) {
                $0 + min(0, profile.traitWeights[$1.key] ?? 0) * $1.value
            }) * roleWeight(character.role)
            return max(result, penalty)
        }
        let negativePairEvidence = min(1, negativePairPenalty)
        guard negativeContentTagPenalty < 0.10,
              negativeTagPenalty < 0.32,
              negativePrimaryTraitPenalty < 0.12 else { return nil }

        let aversionEvidence = min(
            1,
            negativeTagPenalty
                + 0.75 * negativePrimaryTraitPenalty
                + 0.45 * negativePairEvidence
        )
        let collaborative = clampPositive(collaborativeScore)
            * max(0.05, 1 - 2.5 * aversionEvidence)
        let voteCount = max(0, vn.voteCount ?? 0)
        let hasReliableCollaborativeEvidence = collaborative >= 0.72
            && validTags.count >= 5
            && tagInformationMass >= 2
            && voteCount >= 25
            && (vn.rating ?? 0) >= 58
            && historicalPresentation.allowsCollaborativeFallback
        let passesJointGate = bestGame >= 0.18
            && (characterScore ?? 0) >= 0.20
            && hasImportantCharacterMatch
        guard hasImportantCharacterMatch
                || hasStrongTagEvidence
                || hasReliableCollaborativeEvidence else { return nil }
        let hasPositiveGameOverlap = bestGame > 0 && !strongestTagIDs.isEmpty
        let hasPositiveCharacterOverlap = hasImportantCharacterMatch
        let hasDirectPreferenceEvidence = hasPositiveGameOverlap
            || hasPositiveCharacterOverlap
        let isTypeFallback = !passesJointGate && hasDirectPreferenceEvidence
        let isCollaborativeFallback = !passesJointGate
            && !isTypeFallback
            && hasReliableCollaborativeEvidence
        let core: Double
        if passesJointGate, let characterScore {
            let joint = pow(bestGame, 0.45) * pow(characterScore, 0.55)
            core = 0.88 * joint + 0.12 * collaborative
        } else if isTypeFallback {
            let gameFallbackWeight = profile.hasReliableCharacterSignal
                ? 0.48
                : 0.60
            core = max(
                bestGame * gameFallbackWeight,
                (characterScore ?? 0) * 0.72,
                collaborative * 0.42
            )
        } else if isCollaborativeFallback {
            core = collaborative * 0.55
        } else {
            core = 0
        }

        let producer = maxMatch(
            (vn.developers ?? []).map(\.id),
            weights: profile.producerWeights
        )
        let language = maxMatch(vn.languages ?? [], weights: profile.languageWeights)
        let platform = maxMatch(vn.platforms ?? [], weights: profile.platformWeights)
        let length = vn.length.map { profile.lengthWeights[$0] ?? 0 } ?? 0
        let releaseEra = releaseEra(vn.released).map {
            clampPositive(profile.releaseEraWeights[$0] ?? 0)
        } ?? 0
        let metadata = clampPositive(
            0.12 * producer
                + 0.28 * language
                + 0.28 * platform
                + 0.12 * length
                + 0.20 * releaseEra
        )
        let voteConfidence = min(1, log10(Double(max(1, vn.voteCount ?? 1))) / 4)
        let quality = clampPositive(((vn.rating ?? 50) - 50) / 50) * voteConfidence
        let evidenceConfidence = min(
            1,
            log1p(Double(voteCount)) / log(101)
        )
        let ratingQuality: Double
        if let rating = vn.rating, voteCount >= 3 {
            ratingQuality = min(1, max(-1, (rating - 60) / 25))
        } else {
            ratingQuality = -0.20
        }
        let sparseEvidencePenalty: Double = switch voteCount {
        case 0...2: 0.16
        case 3...9: 0.09
        case 10...24: 0.04
        default: 0
        }
        let lowRatingPenalty = max(0, -ratingQuality) * (0.12 + 0.08 * evidenceConfidence)
        var total = max(
            0,
            core * (0.90 + 0.10 * quality)
                + 0.04 * metadata
                + 0.06 * collaborative * evidenceConfidence
                - 0.75 * min(
                    1,
                    negativeTagPenalty
                        + 0.75 * negativePrimaryTraitPenalty
                        + 0.45 * negativePairEvidence
                )
                - sparseEvidencePenalty
                - lowRatingPenalty
                - historicalPresentation.penalty
                - (isTypeFallback ? 0.02 : 0)
        )
        if lacksPreferredCharacterEvidence {
            total = min(total, 0.42)
        }
        return Scored(
            vn: vn,
            total: total,
            game: max(0, bestGame),
            character: characterScore,
            collaborative: collaborative,
            metadata: metadata,
            interestIndex: bestIndex,
            strongestTagIDs: strongestTagIDs,
            strongestTraitIDs: bestCharacter?.matchedTraits ?? [],
            characterID: bestCharacter?.id,
            characterName: bestCharacter?.name,
            hasImportantCharacterMatch: hasImportantCharacterMatch,
            isTypeFallback: isTypeFallback,
            hasSparseEvidence: voteCount < 10
                || vn.rating == nil
                || lacksPreferredCharacterEvidence
                || validTags.count < 4
                || tagInformationMass < 1.75,
            seriesKey: nil
        )
    }

    private static func reason(
        for value: Scored,
        profile: VNDB本地推荐画像V2
    ) -> 探索推荐理由 {
        let tags = value.strongestTagIDs.compactMap { profile.tagNames[$0] }
        let traits = value.strongestTraitIDs.compactMap { profile.traitNames[$0] }
        if value.collaborative > 0.15,
           value.collaborative >= max(value.game, value.character ?? 0) {
            return .similarUsers
        }
        if value.hasImportantCharacterMatch, !tags.isEmpty, !traits.isEmpty {
            return .typeAndCharacter(
                tags: tags,
                character: value.characterName,
                traits: traits
            )
        }
        if value.isTypeFallback,
           !value.hasImportantCharacterMatch,
           !tags.isEmpty {
            return .mainlyType(tags: tags)
        }
        if let tag = tags.first { return .sharedTag(tag) }
        if let trait = traits.first { return .preferredCharacterTrait(trait) }
        return .highlyRated
    }

    private static func feedback(
        for item: 探索用户列表项目,
        medianVote: Double?,
        voteScale: Double,
        hasReliableVoteDistribution: Bool
    ) -> Double {
        let statusSignal = 状态信号(item)
        if let vote = item.vote {
            let center = hasReliableVoteDistribution
                ? (medianVote ?? 70)
                : 70
            let scale = hasReliableVoteDistribution ? voteScale : 15
            let confidence = hasReliableVoteDistribution ? 1.0 : 0.75
            let ratingSignal = tanh((Double(vote) - center) / scale)
                * confidence
            return min(1, max(-1, 0.90 * ratingSignal + 0.10 * statusSignal))
        }
        return statusSignal
    }

    /// 没有评分时，资料库状态代表的偏好信号；协同过滤折入也使用它。
    static func 状态信号(_ item: 探索用户列表项目) -> Double {
        let statusIDs = Set((item.labels ?? []).map(\.id))
        return if statusIDs.contains(4) {
            -0.45
        } else if statusIDs.contains(3) {
            -0.08
        } else if statusIDs.contains(5) {
            0.30
        } else if statusIDs.contains(2) || item.finished != nil {
            0.20
        } else if statusIDs.contains(1) || item.started != nil {
            0.12
        } else {
            0
        }
    }

    private static func recommendationEligibleTag(
        _ tag: 探索标签关联
    ) -> Bool {
        tag.lie != true
    }

    static func 推荐作品准入(
        _ vn: 探索视觉小说,
        characterEvidence: [VNDB候选角色证据]
    ) -> Bool {
        let tagCount = (vn.tags ?? []).count { $0.lie != true }
        guard tagCount >= 5,
              !包含禁止的3D表现(vn.tags ?? []),
              hasUsablePrimaryCharacterEvidence(characterEvidence) else {
            return false
        }
        return true
    }

    private static func 包含禁止的3D表现(
        _ tags: [探索标签关联]
    ) -> Bool {
        let blockedIDs: Set<String> = ["g2693", "g3723"]
        return tags.contains { tag in
            guard tag.lie != true else { return false }
            if blockedIDs.contains(tag.id) { return true }
            let name = tag.name.lowercased()
            return name == "pre-rendered 3d graphics"
                || name == "realistic-looking 3d"
                || name == "预渲染3d图像"
                || name == "预渲染3d图形"
                || name == "写实风格3d"
        }
    }

    private static func hasUsablePrimaryCharacterEvidence(
        _ evidence: [VNDB候选角色证据]
    ) -> Bool {
        evidence.contains {
            ($0.role == "main" || $0.role == "primary")
                && $0.hasImage
                && $0.reliability > 0
                && !$0.traitID.isEmpty
        }
    }

    private static func audienceBoundaryKey(
        _ tag: 探索标签关联
    ) -> String? {
        guard tag.lie != true else { return nil }
        switch tag.id {
        case "g542", "g3432": return "otome"
        case "g98", "g2002", "g2846": return "male-male-romance"
        case "g97", "g1986", "g2300": return "female-female-romance"
        default:
            let name = tag.name.lowercased()
            if name.contains("otome game") { return "otome" }
            if name.contains("boy x boy romance")
                || name.contains("yaoi game") { return "male-male-romance" }
            if name.contains("girl x girl romance")
                || name.contains("yuri game") { return "female-female-romance" }
            return nil
        }
    }

    private static func historicalExperienceConfidence(
        _ item: 探索用户列表项目
    ) -> Double {
        let statusIDs = Set((item.labels ?? []).map(\.id))
        if item.vote != nil || item.finished != nil || statusIDs.contains(2) {
            return 1
        }
        if item.started != nil || statusIDs.contains(1) { return 0.75 }
        if statusIDs.contains(4) { return 1 }
        if statusIDs.contains(3) { return 0.55 }
        return 0
    }

    private static func audienceExperienceConfidence(
        _ item: 探索用户列表项目
    ) -> Double {
        let statusIDs = Set((item.labels ?? []).map(\.id))
        if statusIDs.contains(5) { return 0.75 }
        return historicalExperienceConfidence(item)
    }

    private static func historicalWorkDistinctiveness(
        voteCount: Int?
    ) -> Double {
        guard let voteCount, voteCount > 0 else { return 0.12 }
        switch voteCount {
        case ...50: return 1
        case ...150: return 0.85
        case ...500: return 0.55
        case ...1_500: return 0.30
        default: return 0.12
        }
    }

    private static func historicalPresentationAssessment(
        _ vn: 探索视觉小说,
        profile: VNDB本地推荐画像V2,
        visualPresentationPreferenceMatch: Double
    ) -> (penalty: Double, allowsCollaborativeFallback: Bool) {
        guard let year = releaseYear(vn.released) else { return (0.03, true) }
        let tier: (cutoff: Int, maximumPenalty: Double)? = switch year {
        case ...1999: (1999, 0.34)
        case ...2004: (2004, 0.28)
        case ...2009: (2009, 0.20)
        case ...2014: (2014, 0.08)
        default: nil
        }
        guard let tier else { return (0, true) }
        let evidence = profile.historicalPresentationEvidence[tier.cutoff] ?? 0
        let acceptance = profile.historicalPresentationAcceptance[tier.cutoff] ?? 0
        let evidenceConfidence = min(1, evidence / 1.20)
        let demonstratedAcceptance = acceptance * evidenceConfidence
        let compatibility = max(
            demonstratedAcceptance,
            0.75 * visualPresentationPreferenceMatch
        )
        let penalty = tier.maximumPenalty * (1 - min(1, compatibility))
        let allowsCollaborativeFallback = year >= 2010
            || compatibility >= 0.22
            || (evidence >= 0.55 && acceptance >= 0.20)
        return (penalty, allowsCollaborativeFallback)
    }

    private static func isVisualPresentationTag(
        _ tag: 探索标签关联
    ) -> Bool {
        guard tag.category == "tech" else { return false }
        let name = tag.name.lowercased()
        return name.contains("graphic")
            || name.contains("photograph")
            || name.contains("photos only")
            || name.contains("pixel art")
            || name.contains("3d")
            || name.contains("2d")
            || ((name.contains("animated") || name.contains("animation"))
                && (name.contains("sprite")
                    || name.contains("graphic")
                    || name.contains("cg")))
            || name.contains("visual style")
            || name.contains("art style")
            || name.contains("illustration")
            || (name.contains("background") && !name.contains("music"))
            || name.contains(" cgs")
            || name.hasPrefix("cgs")
            || name == "no character sprites"
            || name == "lots of character sprites"
            || name == "stock sprites"
            || name == "super deformed sprites"
            || name == "minimalist sprites"
    }

    private static func tagSpecificity(
        globalFrequency: Int?,
        globalDocumentCount: Int?
    ) -> Double {
        var result = 1.0
        if let ratio = tagGlobalRatio(
            frequency: globalFrequency,
            documentCount: globalDocumentCount
        ) {
            result = min(result, frequencySpecificity(ratio, commonFrom: 0.02))
        }
        return result
    }

    private static func tagGlobalRatio(
        frequency: Int?,
        documentCount: Int?
    ) -> Double? {
        guard let frequency, let documentCount, documentCount > 0 else {
            return nil
        }
        return Double(frequency) / Double(documentCount)
    }

    private static func frequencySpecificity(
        _ ratio: Double,
        commonFrom: Double = 0.02
    ) -> Double {
        let upperBound = 0.30
        guard ratio > commonFrom else { return 1 }
        let progress = min(
            1,
            (ratio - commonFrom) / max(0.01, upperBound - commonFrom)
        )
        return max(0.08, 1 - 0.92 * progress)
    }

    private static func spoilerReliability(_ spoiler: Int?) -> Double {
        switch spoiler ?? 0 {
        case 1: 0.90
        case 2...: 0.80
        default: 1
        }
    }

    private static func pairKey(_ lhs: String, _ rhs: String) -> String {
        lhs < rhs ? "\(lhs)|\(rhs)" : "\(rhs)|\(lhs)"
    }

    private static func releaseEra(_ released: String?) -> Int? {
        guard let year = releaseYear(released) else { return nil }
        return year - year % 5
    }

    private static func releaseYear(_ released: String?) -> Int? {
        guard let released,
              released.count >= 4,
              let year = Int(released.prefix(4)),
              year >= 1970,
              year <= 2100 else { return nil }
        return year
    }

    private static func roleWeight(_ role: String?) -> Double {
        switch role {
        case "main": return 1
        case "primary": return 0.85
        case "side": return 0.45
        default: return 0.20
        }
    }

    private static func mergedPrototypes(
        _ source: [VNDB兴趣原型],
        limit: Int
    ) -> [VNDB兴趣原型] {
        var values = source
        let mergeThreshold = 0.42
        while values.count > 1 {
            var pair = (0, 1)
            var similarity = -Double.infinity
            for lhs in values.indices {
                for rhs in values.indices where rhs > lhs {
                    let value = 0.75 * cosine(
                        values[lhs].tagWeights,
                        values[rhs].tagWeights
                    ) + 0.25 * cosine(
                        values[lhs].traitWeights,
                        values[rhs].traitWeights
                    )
                    if value > similarity {
                        similarity = value
                        pair = (lhs, rhs)
                    }
                }
            }
            guard values.count > limit || similarity >= mergeThreshold else { break }
            let rhs = values.remove(at: pair.1)
            let lhs = values.remove(at: pair.0)
            values.append(merge(lhs, rhs))
        }
        return values.sorted { $0.confidence > $1.confidence }
    }

    private static func merge(
        _ lhs: VNDB兴趣原型,
        _ rhs: VNDB兴趣原型
    ) -> VNDB兴趣原型 {
        let total = lhs.confidence + rhs.confidence
        var tags = lhs.tagWeights.mapValues { $0 * lhs.confidence }
        for (key, value) in rhs.tagWeights {
            tags[key, default: 0] += value * rhs.confidence
        }
        var traits = lhs.traitWeights.mapValues { $0 * lhs.confidence }
        for (key, value) in rhs.traitWeights {
            traits[key, default: 0] += value * rhs.confidence
        }
        return VNDB兴趣原型(
            tagWeights: normalized(tags.mapValues { $0 / total }),
            traitWeights: normalized(traits.mapValues { $0 / total }),
            confidence: min(3, total)
        )
    }

    private static func mmrScore(
        _ candidate: Scored,
        selected: [Scored],
        interestCounts: [Int: Int]
    ) -> Double {
        let similarity = selected.map { item in
            candidateSimilarity(candidate.vn, item.vn)
        }.max() ?? 0
        let sameSeriesCount = candidate.seriesKey.map { seriesKey in
            selected.count { $0.seriesKey == seriesKey }
        } ?? 0
        let quotaPenalty = Double(interestCounts[candidate.interestIndex] ?? 0) * 0.02
        return candidate.total
            - 0.08 * similarity
            - 0.18 * Double(sameSeriesCount)
            - quotaPenalty
    }

    private static func 系列分组(
        _ candidates: [探索视觉小说]
    ) -> [String: String] {
        let candidateIDs = Set(candidates.map(\.id))
        let seriesRelations: Set<String> = [
            "seq", "preq", "side", "par", "ser", "set", "alt"
        ]
        let relatedIDs = Set(candidates.lazy.flatMap { candidate in
            (candidate.relations ?? []).compactMap { relation in
                relation.relationOfficial == true
                    && seriesRelations.contains(relation.relation)
                    ? relation.id
                    : nil
            }
        })
        let allIDs = candidateIDs.union(relatedIDs)
        guard !allIDs.isEmpty else { return [:] }
        var parent = Dictionary(uniqueKeysWithValues: allIDs.map { ($0, $0) })

        func root(of id: String) -> String {
            var value = id
            while let next = parent[value], next != value {
                value = next
            }
            return value
        }

        func union(_ lhs: String, _ rhs: String) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            guard lhsRoot != rhsRoot else { return }
            if lhsRoot < rhsRoot {
                parent[rhsRoot] = lhsRoot
            } else {
                parent[lhsRoot] = rhsRoot
            }
        }

        for candidate in candidates {
            for relation in candidate.relations ?? []
            where relation.relationOfficial == true
                && seriesRelations.contains(relation.relation) {
                union(candidate.id, relation.id)
            }
        }

        let fallbackBuckets = Dictionary(grouping: candidates) { candidate in
            guard let titleKey = 系列标题键(candidate) else { return "" }
            let developerKey = (candidate.developers ?? []).map(\.id)
                .sorted().joined(separator: ",")
            guard !developerKey.isEmpty else { return "" }
            return "\(developerKey)|\(titleKey)"
        }
        for (key, bucket) in fallbackBuckets where !key.isEmpty && bucket.count > 1 {
            let ordered = bucket.sorted {
                $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
            for index in ordered.indices where index > 0 {
                let comparisonStart = max(0, index - 16)
                for earlierIndex in comparisonStart..<index
                where candidateSimilarity(
                    ordered[index],
                    ordered[earlierIndex]
                ) >= 0.78 {
                    union(ordered[index].id, ordered[earlierIndex].id)
                    break
                }
            }
        }
        return Dictionary(uniqueKeysWithValues: candidateIDs.map {
            ($0, root(of: $0))
        })
    }

    private static func 系列标题键(_ vn: 探索视觉小说) -> String? {
        let ignoredWords: Set<String> = [
            "the", "a", "an", "episode", "ep", "chapter", "chap",
            "volume", "vol", "part", "side", "route", "season",
            "edition", "version", "ver", "remake", "st", "nd", "rd", "th"
        ]
        for title in [vn.title, vn.alttitle].compactMap({ $0 }) {
            let folded = title.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            let tokens = folded.components(
                separatedBy: CharacterSet.letters.inverted
            ).filter { !$0.isEmpty && !ignoredWords.contains($0) }
            guard let first = tokens.first else { continue }
            let hasNonASCII = first.unicodeScalars.contains { !$0.isASCII }
            if (hasNonASCII && first.count >= 2) || first.count >= 5 {
                return first
            }
        }
        return nil
    }

    private static func candidateSimilarity(
        _ lhs: 探索视觉小说,
        _ rhs: 探索视觉小说
    ) -> Double {
        let lhsTags = Set((lhs.tags ?? []).filter { $0.lie != true }.map(\.id))
        let rhsTags = Set((rhs.tags ?? []).filter { $0.lie != true }.map(\.id))
        let union = lhsTags.union(rhsTags)
        let tagSimilarity = union.isEmpty
            ? 0
            : Double(lhsTags.intersection(rhsTags).count) / Double(union.count)
        let lhsProducers = Set((lhs.developers ?? []).map(\.id))
        let producerMatch = lhsProducers.isDisjoint(with: Set((rhs.developers ?? []).map(\.id)))
            ? 0.0
            : 1.0
        return 0.82 * tagSimilarity + 0.18 * producerMatch
    }

    private static func normalized(_ source: [String: Double]) -> [String: Double] {
        let norm = sqrt(source.values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return [:] }
        return source.mapValues { $0 / norm }
    }

    private static func cosine(
        _ lhs: [String: Double],
        _ rhs: [String: Double]
    ) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let smaller = lhs.count <= rhs.count ? lhs : rhs
        let larger = lhs.count <= rhs.count ? rhs : lhs
        return smaller.reduce(0) { $0 + $1.value * (larger[$1.key] ?? 0) }
    }

    private static func maxMatch(
        _ keys: [String],
        weights: [String: Double]
    ) -> Double {
        clampPositive(keys.map { weights[$0] ?? 0 }.max() ?? 0)
    }

    private static func clampPositive(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
