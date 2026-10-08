import Foundation
import Combine
import SwiftUI

nonisolated enum 系统状态服务类型: String, Codable, CaseIterable, Sendable {
    case today = "paperVNToday"
    case activity = "paperVNActivity"
    case connect = "paperVNConnect"
    case feedback = "paperVNFeedback"

    var defaultName: String {
        switch self {
        case .today: return String(localized: "PaperVN Today")
        case .activity: return String(localized: "PaperVN活动")
        case .connect: return String(localized: "PaperVN Connect")
        case .feedback: return String(localized: "PaperVN反馈")
        }
    }
}

nonisolated struct 系统状态本地化文本: Codable, Sendable, Equatable {
    let fallback: String
    let translations: [String: String]

    init(_ value: String) {
        fallback = value
        translations = [:]
    }

    init(fallback: String, translations: [String: String] = [:]) {
        self.fallback = fallback
        self.translations = translations
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            fallback = value
            translations = [:]
            return
        }

        let container = try decoder.container(keyedBy: 动态键.self)
        var values: [String: String] = [:]
        for key in container.allKeys where key.stringValue != "translations" {
            if let value = try container.decodeIfPresent(String.self, forKey: key),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                values[key.stringValue] = value
            }
        }
        if let nested = try container.decodeIfPresent(
            [String: String].self,
            forKey: 动态键(stringValue: "translations")!
        ) {
            values.merge(nested) { _, new in new }
        }

        guard let fallback = values.removeValue(forKey: "default")
                ?? values["zh-Hans"]
                ?? values["zh_Hans"]
                ?? values.values.first else {
            self.fallback = ""
            translations = [:]
            return
        }
        self.fallback = fallback
        translations = values
    }

    func encode(to encoder: Encoder) throws {
        if translations.isEmpty {
            var container = encoder.singleValueContainer()
            try container.encode(fallback)
            return
        }
        var container = encoder.container(keyedBy: 动态键.self)
        try container.encode(fallback, forKey: 动态键(stringValue: "default")!)
        for (key, value) in translations {
            try container.encode(value, forKey: 动态键(stringValue: key)!)
        }
    }

    func resolved(localeIdentifier: String = Locale.current.identifier) -> String {
        let normalized = Self.normalize(localeIdentifier)
        let normalizedTranslations = translations.reduce(into: [String: String]()) {
            $0[Self.normalize($1.key)] = $1.value
        }
        if let exact = normalizedTranslations[normalized] {
            return exact
        }
        let language = normalized.split(separator: "-").first.map(String.init)
        if language == "zh" {
            let key = normalized.contains("hant")
                || normalized.contains("tw")
                || normalized.contains("hk")
                ? "zh-hant"
                : "zh-hans"
            return normalizedTranslations[key]
                ?? normalizedTranslations["zh"]
                ?? fallback
        }
        if let language,
           let matching = normalizedTranslations.first(where: {
               $0.key == language || $0.key.hasPrefix(language + "-")
           })?.value {
            return matching
        }
        return fallback
    }

    private static func normalize(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private struct 动态键: CodingKey {
        let stringValue: String
        let intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

nonisolated enum 系统状态状态: String, Codable, Sendable {
    case available
    case issue
    case outage

    var title: String {
        switch self {
        case .available: return String(localized: "可用")
        case .issue: return String(localized: "问题")
        case .outage: return String(localized: "中断")
        }
    }

    var icon: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .issue: return "exclamationmark.triangle.fill"
        case .outage: return "xmark.octagon.fill"
        }
    }
}

nonisolated enum 系统状态影响范围: String, Codable, Sendable {
    case none
    case partial
    case all

    var title: String? {
        switch self {
        case .none: return nil
        case .partial: return String(localized: "部分用户受到影响")
        case .all: return String(localized: "所有用户受到影响")
        }
    }
}

nonisolated enum 系统状态时间精度: String, Codable, Sendable {
    case date
    case datetime
}

nonisolated struct 系统状态服务: Codable, Identifiable, Sendable, Equatable {
    let id: 系统状态服务类型
    let name: 系统状态本地化文本?
    let status: 系统状态状态
    let impact: 系统状态影响范围
    let description: 系统状态本地化文本?
    let startAt: String?
    let endAt: String?
    let timePrecision: 系统状态时间精度?

    func displayName(localeIdentifier: String = Locale.current.identifier) -> String {
        name?.resolved(localeIdentifier: localeIdentifier) ?? id.defaultName
    }

    func cleanedDescription(localeIdentifier: String = Locale.current.identifier) -> String? {
        guard let description else { return nil }
        let value = description.resolved(localeIdentifier: localeIdentifier)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    init(
        id: 系统状态服务类型,
        name: String? = nil,
        status: 系统状态状态,
        impact: 系统状态影响范围 = .none,
        description: String? = nil,
        startAt: String? = nil,
        endAt: String? = nil,
        timePrecision: 系统状态时间精度? = nil
    ) {
        self.id = id
        self.name = name.map(系统状态本地化文本.init)
        self.status = status
        self.impact = impact
        self.description = description.map(系统状态本地化文本.init)
        self.startAt = startAt
        self.endAt = endAt
        self.timePrecision = timePrecision
    }
}

nonisolated struct 系统状态文档: Codable, Sendable, Equatable {
    let schemaVersion: Int
    let updatedAt: String?
    let services: [系统状态服务]

    init(
        schemaVersion: Int = 1,
        updatedAt: String? = nil,
        services: [系统状态服务]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.services = services
    }

    var servicesInKnownOrder: [系统状态服务] {
        let order = 系统状态服务类型.allCases
        return services.sorted { left, right in
            let leftIndex = order.firstIndex(of: left.id) ?? order.count
            let rightIndex = order.firstIndex(of: right.id) ?? order.count
            return leftIndex < rightIndex
        }
    }

    func activeServices(at now: Date = Date()) -> [系统状态服务] {
        servicesInKnownOrder.filter { $0.isVisible(at: now) }
    }

    func plannedServices(at now: Date = Date()) -> [系统状态服务] {
        activeServices(at: now).filter { $0.isPlanned(at: now) }
    }

    func currentServices(at now: Date = Date()) -> [系统状态服务] {
        activeServices(at: now).filter { !$0.isPlanned(at: now) }
    }

    var hasServiceData: Bool {
        !services.isEmpty
    }

    func summary(at now: Date = Date()) -> String? {
        let current = currentServices(at: now)
        let planned = plannedServices(at: now)
        let currentSummary = Self.summary(
            services: current,
            prefix: "当前有"
        )
        let plannedSummary = Self.summary(
            services: planned,
            prefix: "计划有"
        )

        switch (currentSummary, plannedSummary) {
        case let (current?, planned?):
            return current + String(localized: "；") + planned
        case let (current?, nil):
            return current
        case let (nil, planned?):
            return planned
        case (nil, nil):
            return nil
        }
    }

    private static func summary(
        services: [系统状态服务],
        prefix: String
    ) -> String? {
        let outageCount = services.filter { $0.status == .outage }.count
        let issueCount = services.filter { $0.status == .issue }.count
        var parts: [String] = []
        if outageCount > 0 {
            parts.append(
                prefix == "当前有"
                    ? String(localized: "当前有\(outageCount)个服务中断")
                    : String(localized: "计划有\(outageCount)个服务中断")
            )
        }
        if issueCount > 0 {
            parts.append(
                prefix == "当前有"
                    ? String(localized: "当前有\(issueCount)个服务出现问题")
                    : String(localized: "计划有\(issueCount)个服务出现问题")
            )
        }
        return parts.isEmpty ? nil : parts.joined(separator: String(localized: "，"))
    }
}

private extension 系统状态服务 {
    nonisolated var resolvedTimePrecision: 系统状态时间精度 {
        if let timePrecision {
            return timePrecision
        }
        if [startAt, endAt].compactMap({ $0 }).contains(where: { $0.contains("T") }) {
            return .datetime
        }
        return .date
    }

    nonisolated func isVisible(at now: Date) -> Bool {
        guard status != .available else { return false }
        guard let start = 系统状态日期工具.parse(startAt, precision: resolvedTimePrecision) else {
            return endAt == nil
        }
        if now < start {
            if status == .outage,
               let visibilityStart = 系统状态日期工具.dateBySubtractingDays(
                   3,
                   from: start,
                   precision: resolvedTimePrecision
               ) {
                return now >= visibilityStart
            }
            return false
        }
        guard let end = 系统状态日期工具.parse(endAt, precision: resolvedTimePrecision) else {
            return true
        }
        return now <= 系统状态日期工具.endOfDisplayDate(end, precision: resolvedTimePrecision)
    }

    nonisolated func isPlanned(at now: Date) -> Bool {
        guard let start = 系统状态日期工具.parse(startAt, precision: resolvedTimePrecision) else {
            return false
        }
        return start > now
    }

    nonisolated func timeDescription(at now: Date = Date()) -> String? {
        guard status != .available else { return nil }
        guard let start = 系统状态日期工具.parse(startAt, precision: resolvedTimePrecision) else {
            return nil
        }
        let end = 系统状态日期工具.parse(endAt, precision: resolvedTimePrecision)
        return 系统状态日期工具.rangeDescription(
            start: start,
            end: end,
            precision: resolvedTimePrecision,
            now: now
        )
    }
}

nonisolated enum 系统状态日期工具 {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }()

    static func parse(
        _ value: String?,
        precision: 系统状态时间精度
    ) -> Date? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        if precision == .date {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: value)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func endOfDisplayDate(
        _ date: Date,
        precision: 系统状态时间精度
    ) -> Date {
        guard precision == .date else { return date }
        return calendar.date(byAdding: .day, value: 1, to: date)?.addingTimeInterval(-0.001)
            ?? date
    }

    static func dateBySubtractingDays(
        _ days: Int,
        from date: Date,
        precision: 系统状态时间精度
    ) -> Date? {
        if precision == .date {
            return calendar.date(byAdding: .day, value: -days, to: date)
        }
        return date.addingTimeInterval(TimeInterval(-days) * 24 * 60 * 60)
    }

    static func rangeDescription(
        start: Date,
        end: Date?,
        precision: 系统状态时间精度,
        now: Date
    ) -> String {
        let startText = format(start, precision: precision, now: now)
        let endText: String
        if let end {
            endText = format(end, precision: precision, now: now)
        } else {
            endText = String(localized: "现在")
        }
        return String(format: String(localized: "%@ — %@"), startText, endText)
    }

    private static func format(
        _ date: Date,
        precision: 系统状态时间精度,
        now: Date
    ) -> String {
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        if precision == .date {
            return date.formatted(style.year().month().day())
        }

        let dayDifference = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day

        let dayText: String
        if calendar.isDate(date, inSameDayAs: now) {
            dayText = String(localized: "今天")
        } else if dayDifference == 1 {
            dayText = String(localized: "昨天")
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            dayText = date.formatted(style.month().day())
        } else {
            dayText = date.formatted(style.year().month().day())
        }

        return "\(dayText) \(date.formatted(style.hour().minute()))"
    }
}

nonisolated enum 系统状态服务源 {
    static let statusURL = URL(
        string: "https://papervn.jizpaper.com/status/status.json"
    )!
}

enum 系统状态服务错误: LocalizedError, Sendable {
    case invalidResponse
    case invalidContent
    case unsupportedSchema

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return String(localized: "系统状态服务返回了无效响应。")
        case .invalidContent: return String(localized: "系统状态内容格式无效。")
        case .unsupportedSchema: return String(localized: "系统状态内容版本过高。")
        }
    }
}

actor 系统状态网络服务 {
    static let shared = 系统状态网络服务()
    private static let memoryCacheLifetime: TimeInterval = 60

    private let session: URLSession
    private let cacheURL: URL
    private let decoder = JSONDecoder()
    private var memoryCache: (document: 系统状态文档, loadedAt: Date)?

    init(
        session: URLSession = .shared,
        cacheURL: URL? = nil
    ) {
        self.session = session
        self.cacheURL = cacheURL ?? FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("PaperVNStatus/status.json")
        try? FileManager.default.createDirectory(
            at: self.cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func load(forceRefresh: Bool = false) async throws -> 系统状态文档 {
        if !forceRefresh,
           let memoryCache,
           Date().timeIntervalSince(memoryCache.loadedAt) < Self.memoryCacheLifetime {
            return memoryCache.document
        }

        var requestURL = 系统状态服务源.statusURL
        if var components = URLComponents(
            url: requestURL,
            resolvingAgainstBaseURL: false
        ) {
            var queryItems = components.queryItems ?? []
            queryItems.append(
                URLQueryItem(
                    name: "_papervn_refresh",
                    value: UUID().uuidString
                )
            )
            components.queryItems = queryItems
            requestURL = components.url ?? requestURL
        }

        var request = URLRequest(url: requestURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode),
                  !data.isEmpty else {
                throw 系统状态服务错误.invalidResponse
            }
            let document = try decode(data)
            try? data.write(to: cacheURL, options: .atomic)
            memoryCache = (document, Date())
            return document
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let data = try? Data(contentsOf: cacheURL) else { throw error }
            let document = try decode(data)
            memoryCache = (document, Date())
            return document
        }
    }

    private func decode(_ data: Data) throws -> 系统状态文档 {
        let document = try decoder.decode(系统状态文档.self, from: data)
        guard document.schemaVersion == 1 else {
            throw 系统状态服务错误.unsupportedSchema
        }
        guard document.services.contains(where: { $0.id == .today }),
              document.services.contains(where: { $0.id == .activity }),
              document.services.contains(where: { $0.id == .connect }),
              document.services.contains(where: { $0.id == .feedback }) else {
            throw 系统状态服务错误.invalidContent
        }
        return document
    }
}

@MainActor
final class 系统状态视图模型: ObservableObject {
    @Published private(set) var document: 系统状态文档?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: 系统状态网络服务
    private let initialDocument: 系统状态文档?

    init(
        service: 系统状态网络服务 = .shared,
        initialDocument: 系统状态文档? = nil
    ) {
        self.service = service
        self.initialDocument = initialDocument
        self.document = initialDocument
    }

    func load(forceRefresh: Bool = false) async {
        if initialDocument != nil { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            document = try await service.load(forceRefresh: forceRefresh)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

}

struct 系统状态卡片: View {
    fileprivate static let previewServices: [系统状态服务] = [
        系统状态服务(
            id: .today,
            status: .available,
            impact: .none
        ),
        系统状态服务(
            id: .connect,
            status: .issue,
            impact: .partial,
            description: "部分用户可能无法同步账户信息。我们正在调查连接稳定性问题。",
            startAt: "2026-08-18T23:40:00+08:00",
            timePrecision: .datetime
        ),
        系统状态服务(
            id: .feedback,
            status: .outage,
            impact: .all,
            description: "反馈提交暂时不可用。",
            startAt: "2026-08-22",
            endAt: "2026-09-01",
            timePrecision: .date
        ),
        系统状态服务(
            id: .activity,
            status: .issue,
            impact: .partial,
            description: "中国大陆用户目前在使用此服务时可能遇到无法载入的问题。",
            startAt: "2026-08-22T09:00:00+08:00",
            timePrecision: .datetime
        )
    ]

    @Environment(\.locale) private var locale
    let document: 系统状态文档
    private let now: Date
    @State private var collapsedGroups: Set<String> = []

    init(document: 系统状态文档, now: Date = Date()) {
        self.document = document
        self.now = now
    }

    var body: some View {
        let currentIssues = services(status: .issue, planned: false)
        let currentOutages = services(status: .outage, planned: false)
        let plannedIssues = services(status: .issue, planned: true)
        let plannedOutages = services(status: .outage, planned: true)
        let groups = [
            (
                id: "currentIssues",
                title: String(localized: "当前有\(currentIssues.count)个服务出现问题"),
                services: currentIssues
            ),
            (
                id: "currentOutages",
                title: String(localized: "当前有\(currentOutages.count)个服务中断"),
                services: currentOutages
            ),
            (
                id: "plannedIssues",
                title: String(localized: "计划有\(plannedIssues.count)个服务出现问题"),
                services: plannedIssues
            ),
            (
                id: "plannedOutages",
                title: String(localized: "计划有\(plannedOutages.count)个服务中断"),
                services: plannedOutages
            )
        ].filter { !$0.services.isEmpty }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Divider()
                }
                statusGroup(
                    id: group.id,
                    title: group.title,
                    services: group.services
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .平台卡片容器(
            background: Color.平台次级分组背景,
            stroke: .clear,
            cornerRadius: 28,
            lightModeShadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0
        )
        .animation(.snappy, value: collapsedGroups)
        .accessibilityElement(children: .contain)
    }

    private func services(
        status: 系统状态状态,
        planned: Bool
    ) -> [系统状态服务] {
        document.activeServices(at: now).filter {
            $0.status == status && $0.isPlanned(at: now) == planned
        }
    }

    @ViewBuilder
    private func statusGroup(
        id: String,
        title: String,
        services: [系统状态服务]
    ) -> some View {
        if !services.isEmpty {
            let isCollapsed = collapsedGroups.contains(id)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: title)
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.snappy) {
                            if isCollapsed {
                                collapsedGroups.remove(id)
                            } else {
                                collapsedGroups.insert(id)
                            }
                        }
                    } label: {
                        Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                            .font(.body.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text(isCollapsed ? "展开分组" : "收起分组")
                    )
                }

                if !isCollapsed {
                    Divider()

                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(services.enumerated()), id: \.element.id) { index, service in
                            if index > 0 {
                                Divider()
                                    .padding(.vertical, 12)
                            }
                            serviceRow(service)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    @ViewBuilder
    private func serviceRow(_ service: 系统状态服务) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(for: service.status)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: service.displayName(localeIdentifier: locale.identifier))
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(verbatim: service.status.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            service.status == .outage ? .red : .yellow
                        )
                }

                if let time = service.timeDescription(at: now) {
                    Text(verbatim: time)
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(.secondary)
                }

                if let impact = service.impact.title {
                    Text(impact)
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(.secondary)
                }

                if let description = service.cleanedDescription(
                    localeIdentifier: locale.identifier
                ) {
                    Text(verbatim: description)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusIcon(for status: 系统状态状态) -> some View {
        switch status {
        case .issue:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.yellow)
                .frame(width: 14, height: 14)
                .rotationEffect(.degrees(45))
                .padding(5)
                .accessibilityHidden(true)
        case .outage:
            Image(systemName: "triangle.fill")
                .font(.body.weight(.bold))
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        case .available:
            EmptyView()
        }
    }
}

#Preview("系统状态卡片") {
    系统状态卡片(
        document: 系统状态文档(
            updatedAt: "2026-08-19T12:00:00+08:00",
            services: 系统状态卡片.previewServices
        ),
        now: Date()
    )
}
