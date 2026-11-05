import Foundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Combine

private enum 反馈类型: Int, CaseIterable, Codable, Identifiable, Sendable {
    case suggestion = 1
    case bugReport = 2
    case question = 3

    var id: Int { rawValue }

    var localizedTitle: String {
        switch self {
        case .suggestion: String(localized: "建议")
        case .bugReport: String(localized: "错误报告")
        case .question: String(localized: "提问")
        }
    }
}

private enum 反馈来源: Int, Codable, Sendable {
    case app = 1
    case testFlight = 2
    case qq = 3
    case discord = 4
    case telegram = 5
    case email = 6
    case other = 7
    /// 在 Paper账户网页（account.jizpaper.com）上提交的反馈。
    case web = 8

    var localizedTitle: String {
        switch self {
        case .app: String(localized: "App内")
        case .testFlight: String(localized: "TestFlight")
        case .qq: String(localized: "QQ")
        case .discord: String(localized: "Discord")
        case .telegram: String(localized: "Telegram")
        case .email: String(localized: "电子邮件")
        case .other: String(localized: "其他")
        case .web: String(localized: "网页")
        }
    }
}

private struct 反馈工作流状态: Decodable, Sendable {
    let workflow: [Int]
    let closed: [Int]?
    private let isClosedValue: Bool

    private enum CodingKeys: String, CodingKey {
        case workflow
        case closed
        case isClosed = "isClosed"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflow = try container.decodeIfPresent([Int].self, forKey: .workflow) ?? [0, 0]
        closed = try container.decodeIfPresent([Int].self, forKey: .closed)
        isClosedValue = try container.decodeIfPresent(Bool.self, forKey: .isClosed) ?? false
    }

    var isClosed: Bool {
        isClosedValue || closed == [0, 2] || workflow == [0, 2]
    }

    var notificationKey: String {
        [
            workflow.map(String.init).joined(separator: ","),
            closed?.map(String.init).joined(separator: ",") ?? "",
            String(isClosedValue),
        ]
        .joined(separator: "|")
    }

    func localizedStatuses(for type: 反馈类型?) -> [String] {
        var statuses = [
            isClosed
                ? String(localized: "已关闭")
                : String(localized: "未结"),
        ]

        if let workflowStatus = localizedWorkflowStatus(for: type) {
            statuses.append(workflowStatus)
        }
        return statuses
    }

    func localizedSummary(for type: 反馈类型?) -> String {
        localizedStatuses(for: type).joined(separator: " · ")
    }

    private func localizedWorkflowStatus(for type: 反馈类型?) -> String? {
        guard !(isClosed && workflow == [0, 2]) else { return nil }

        switch type {
        case .suggestion:
            switch workflow {
            case [1, 1]:
                return String(localized: "已查看")
            case [1, 2]:
                return String(localized: "已计划 – 在将来的更新中提供")
            case [1, 3]:
                return String(localized: "已完成 – 当前版本已实现预期效果")
            case [1, 4]:
                return String(localized: "无计划")
            default:
                switch workflow.last {
                case 1:
                    return String(localized: "已查看")
                case 3:
                    return String(localized: "已计划 – 在将来的更新中提供")
                case 4:
                    return String(localized: "已完成 – 当前版本已实现预期效果")
                case 5:
                    return String(localized: "无计划")
                default:
                    return nil
                }
            }

        case .bugReport:
            switch workflow {
            case [2, 1]:
                return String(localized: "已查看")
            case [2, 2]:
                return String(localized: "正在调查")
            case [2, 3]:
                return String(localized: "已确定潜在修复方案 – 在将来的更新中提供")
            case [2, 4]:
                return String(localized: "调查已完成 – 需要由Apple进行更改")
            case [2, 5]:
                return String(localized: "调查已完成 – 与设计相符")
            case [2, 6]:
                return String(localized: "调查已完成 – 无法根据当前信息诊断问题")
            default:
                switch workflow.last {
                case 1:
                    return String(localized: "已查看")
                case 3:
                    return String(localized: "正在调查")
                case 4:
                    return String(localized: "已确定潜在修复方案 – 在将来的更新中提供")
                case 5:
                    return String(localized: "调查已完成 – 需要由Apple进行更改")
                case 6:
                    return String(localized: "调查已完成 – 与设计相符")
                case 7:
                    return String(localized: "调查已完成 – 无法根据当前信息诊断问题")
                default:
                    return nil
                }
            }

        case .question, nil:
            guard workflow.last == 1 else { return nil }
            return String(localized: "已查看")
        }
    }
}

private struct 反馈审核状态: Codable, Sendable {
    let state: String
    let ignoredReason: 反馈忽略原因?
}

private struct 反馈忽略原因: Codable, Sendable {
    let code: Int
    let message: String?
}

private struct 反馈提交者: Codable, Sendable {
    let vndbID: String?
    let vndbUsername: String?
    /// Paper Account 的昵称；旧版用VNDB登录提交的反馈只有 vndbUsername。
    let nickname: String?

    var 显示名称: String? { nickname ?? vndbUsername }
}

private struct 反馈时间: Codable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// 和数据维护的提交混排时按它排序。
    var date: Date? { preciseDate ?? dateOnly }

    var dayText: String {
        guard let date = dateOnly else { return datePart }
        return date.formatted(.dateTime.year().month().day())
    }

    var detailText: String {
        if let date = preciseDate {
            return date.formatted(.dateTime.year().month().day().hour().minute())
        }
        guard let timePart else { return dayText }
        return "\(dayText) \(timePart)"
    }

    private var datePart: String {
        String(rawValue.split(separator: "T", maxSplits: 1).first ?? "")
    }

    private var timePart: String? {
        guard let separator = rawValue.firstIndex(of: "T") else { return nil }
        let value = String(rawValue[rawValue.index(after: separator)...])
        let timezoneStart = value.firstIndex { $0 == "Z" || $0 == "+" || $0 == "-" }
        let time = timezoneStart.map { String(value[..<$0]) } ?? value
        return time.isEmpty ? nil : time
    }

    private var dateOnly: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: datePart)
    }

    private var preciseDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: rawValue) ?? {
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: rawValue)
        }()
    }
}

private struct 反馈附件: Codable, Identifiable, Sendable {
    let id: String
    let filename: String
    let mimeType: String
    let byteCount: Int
    let downloadURL: URL?
}

private struct 反馈消息: Codable, Identifiable, Sendable {
    let id: String
    let author: String
    let vndbID: String?
    let createdAt: 反馈时间
    let description: String
    let attachments: [反馈附件]

    var isDeveloper: Bool { author == "developer" }
}

private struct 反馈项目: Decodable, Identifiable, Sendable {
    let id: String
    let title: String
    let type: Int
    let source: Int
    let createdAt: 反馈时间
    let submitter: 反馈提交者
    let review: 反馈审核状态
    let status: 反馈工作流状态
    let messages: [反馈消息]
    let updatedAt: 反馈时间?
    /// 服务器按请求中的 Paper Account 判断是否是当前用户提交的。
    let ownedByCurrentUser: Bool?

    var feedbackType: 反馈类型? { 反馈类型(rawValue: type) }
    var feedbackSource: 反馈来源? { 反馈来源(rawValue: source) }
    var isPublished: Bool { review.state == "published" }
    var isIgnored: Bool { review.state == "ignored" }

    var developerReplyKey: String {
        messages
            .filter(\.isDeveloper)
            .map {
                "\($0.id)|\($0.createdAt.rawValue)|\($0.description)"
            }
            .joined(separator: "\n")
    }
}

private struct 反馈上传附件: Identifiable, Sendable {
    let id = UUID()
    let filename: String
    let mimeType: String
    let data: Data
}

private struct 反馈附件请求: Encodable {
    let filename: String
    let mimeType: String
    let data: Data
}

private struct 新建反馈请求: Encodable {
    let title: String
    let contact: String?
    let type: Int
    let description: String
    let source: Int
    let attachments: [反馈附件请求]
    let client: [String: String]
    /// 只有错误报告带诊断信息，只有提交者本人和开发者能看到。
    var diagnostics: 诊断报告? = nil
}

private struct 添加反馈信息请求: Encodable {
    let description: String
    let attachments: [反馈附件请求]
}

private struct 反馈列表响应: Decodable {
    let feedback: [反馈项目]
}

private struct 新建反馈资格: Decodable {
    let canCreate: Bool
    let unreviewedCount: Int
}

private struct 反馈错误响应: Decodable {
    struct APIError: Decodable {
        let code: String
        let message: String
    }

    let error: APIError
}

private enum 反馈服务错误: LocalizedError {
    case invalidResponse
    case unavailable
    case server(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "反馈服务返回了无效响应。")
        case .unavailable:
            String(localized: "服务器当前不可用，请稍后再试。")
        case let .server(_, message):
            message
        }
    }

    var code: String? {
        guard case let .server(code, _) = self else { return nil }
        return code
    }
}

private struct PaperVN反馈服务 {
    private let baseURL = URL(string: "https://papervn.jizpaper.com/feedback/")!

    func publicFeedback(token: String?) async throws -> [反馈项目] {
        let response: 反馈列表响应 = try await request(
            path: "/feedback?scope=public",
            method: "GET",
            token: token,
            body: Optional<EmptyRequest>.none
        )
        return response.feedback
    }

    func ownFeedback(token: String?) async throws -> [反馈项目] {
        let response: 反馈列表响应 = try await request(
            path: "/feedback?scope=mine",
            method: "GET",
            token: token,
            body: Optional<EmptyRequest>.none
        )
        return response.feedback
    }

    func eligibility(token: String?) async throws -> 新建反馈资格 {
        try await request(
            path: "/eligibility",
            method: "GET",
            token: token,
            body: Optional<EmptyRequest>.none
        )
    }

    func create(token: String?, requestBody: 新建反馈请求) async throws -> 反馈项目 {
        try await request(
            path: "/feedback",
            method: "POST",
            token: token,
            body: requestBody
        )
    }

    func addInformation(
        token: String?,
        id: String,
        requestBody: 添加反馈信息请求
    ) async throws -> 反馈项目 {
        try await request(
            path: "/feedback/\(id)/reply",
            method: "POST",
            token: token,
            body: requestBody
        )
    }

    func close(token: String?, id: String) async throws -> 反馈项目 {
        try await request(
            path: "/feedback/\(id)/close",
            method: "POST",
            token: token,
            body: EmptyRequest()
        )
    }

    func attachmentURL(for attachment: 反馈附件) -> URL? {
        guard let url = attachment.downloadURL,
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private func request<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        token: String?,
        body: Body?
    ) async throws -> Response {
        guard let url = endpointURL(path: path) else {
            throw 反馈服务错误.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        敏感内容网页设置.添加设备身份(to: &request)
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw 反馈服务错误.unavailable
        }
        guard let response = response as? HTTPURLResponse else {
            throw 反馈服务错误.unavailable
        }
        guard (200...299).contains(response.statusCode) else {
            if let error = try? JSONDecoder().decode(反馈错误响应.self, from: data) {
                throw 反馈服务错误.server(
                    code: error.error.code,
                    message: error.error.message
                )
            }
            throw 反馈服务错误.invalidResponse
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw 反馈服务错误.invalidResponse
        }
    }

    private func endpointURL(path: String) -> URL? {
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let route = parts.first, !route.isEmpty,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }

        var queryItems = [URLQueryItem(name: "route", value: String(route))]
        if parts.count == 2,
           let requestQuery = URLComponents(string: "?\(parts[1])")?.queryItems {
            queryItems.append(contentsOf: requestQuery)
        }
        components.queryItems = queryItems
        return components.url
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private struct EmptyRequest: Encodable {}
}

@MainActor
@Observable
private final class PaperVN反馈状态 {
    let service = PaperVN反馈服务()
    var publicFeedback: [反馈项目] = []
    var submittedFeedback: [反馈项目] = []
    var isLoading = false
    var errorMessage: String?

    func reload(token: String?) async {
        isLoading = true
        defer { isLoading = false }

        do {
            publicFeedback = try await service.publicFeedback(token: token)
            submittedFeedback = try await service.ownFeedback(token: token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 反馈列表的类型筛选：反馈的三种类型和数据维护的各个种类。
private enum 反馈列表筛选: Hashable {
    case 反馈(反馈类型)
    case 数据维护(数据维护种类)
}

/// 反馈和数据维护的提交在同一个列表中按时间排列。
private enum 反馈列表项: Identifiable {
    case 反馈(反馈项目)
    case 数据维护(数据维护提交)

    var id: String {
        switch self {
        case let .反馈(item): item.id
        case let .数据维护(item): item.id
        }
    }

    var date: Date {
        switch self {
        case let .反馈(item): item.createdAt.date ?? .distantPast
        case let .数据维护(item): item.createdAt
        }
    }

    func 符合(_ filter: 反馈列表筛选?) -> Bool {
        switch (filter, self) {
        case (nil, _): true
        case let (.反馈(type)?, .反馈(item)): item.feedbackType == type
        case let (.数据维护(kind)?, .数据维护(item)): item.kind == kind
        default: false
        }
    }

    static func 合并(_ feedback: [反馈项目], _ maintenance: [数据维护提交]) -> [反馈列表项] {
        (feedback.map(Self.反馈) + maintenance.map(Self.数据维护))
            .sorted { $0.date > $1.date }
    }
}

struct 反馈提示: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct 反馈更新快照: Codable {
    let statusKey: String
    let developerReplyKey: String
}

private enum 反馈更新提醒记录 {
    static func load(for userID: String) -> [String: 反馈更新快照] {
        guard let data = UserDefaults.standard.data(
            forKey: "PaperVN.feedbackUpdateSnapshots.\(userID)"
        ), let snapshots = try? JSONDecoder().decode(
            [String: 反馈更新快照].self,
            from: data
        ) else {
            return [:]
        }
        return snapshots
    }

    static func save(_ snapshots: [String: 反馈更新快照], for userID: String) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(
            data,
            forKey: "PaperVN.feedbackUpdateSnapshots.\(userID)"
        )
    }
}

/// 记录当前账户的反馈有哪些未查看的更新（开发者回复或状态变化），显示在“反馈”按钮和反馈列表上。
/// 第一次见到的反馈只记下快照；打开反馈详情后才算已查看。
@MainActor
final class 反馈更新提醒中心: ObservableObject {
    enum 更新种类 {
        case 回复
        case 状态
    }

    static let shared = 反馈更新提醒中心()

    /// 反馈ID -> 未查看的更新
    @Published private(set) var 更新: [String: 更新种类] = [:]

    private let service = PaperVN反馈服务()
    private var isRefreshing = false
    private var userID = ""
    private var 已查看快照: [String: 反馈更新快照] = [:]

    private init() {
        #if DEBUG
        if Self.调试预览 {
            userID = "preview"
            更新 = ["FB-1042": .回复, "FB-1038": .状态]
        }
        #endif
    }

    /// 显示在按钮上的提示；没有更新时为 nil。
    var 提示: String? {
        guard let 种类 = 更新.values.first else { return nil }
        guard 更新.count == 1 else {
            return String(localized: "\(更新.count)个反馈有更新")
        }
        return Self.提示(种类)
    }

    static func 提示(_ 种类: 更新种类) -> String {
        switch 种类 {
        case .回复: String(localized: "有新回复")
        case .状态: String(localized: "状态已更新")
        }
    }

    func refresh(token: String?, userID: String) async {
        guard let token, !token.isEmpty, !userID.isEmpty, !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let feedback = try? await service.ownFeedback(token: token) else {
            return
        }
        接收(feedback, userID: userID)
    }

    fileprivate func 接收(_ feedback: [反馈项目], userID: String) {
        guard !userID.isEmpty else { return }
        #if DEBUG
        guard !Self.调试预览 else { return }
        #endif
        self.userID = userID

        let previous = 反馈更新提醒记录.load(for: userID)
        var snapshots: [String: 反馈更新快照] = [:]
        var updates: [String: 更新种类] = [:]

        for item in feedback {
            let current = Self.快照(item)
            guard let acknowledged = previous[item.id] else {
                snapshots[item.id] = current
                continue
            }
            snapshots[item.id] = acknowledged
            if acknowledged.developerReplyKey != current.developerReplyKey,
               !current.developerReplyKey.isEmpty {
                updates[item.id] = .回复
            } else if acknowledged.statusKey != current.statusKey {
                updates[item.id] = .状态
            }
        }

        已查看快照 = snapshots
        更新 = updates
        反馈更新提醒记录.save(snapshots, for: userID)
    }

    fileprivate func 标记已查看(_ feedback: 反馈项目) {
        更新[feedback.id] = nil
        guard !userID.isEmpty else { return }
        已查看快照[feedback.id] = Self.快照(feedback)
        反馈更新提醒记录.save(已查看快照, for: userID)
    }

    /// 退出 Paper Account 后不再显示上一个账户的更新。
    func 清除() {
        #if DEBUG
        guard !Self.调试预览 else { return }
        #endif
        userID = ""
        已查看快照 = [:]
        更新 = [:]
    }

    private static func 快照(_ item: 反馈项目) -> 反馈更新快照 {
        反馈更新快照(
            statusKey: item.status.notificationKey,
            developerReplyKey: item.developerReplyKey
        )
    }

    #if DEBUG
    /// 调试用：带 `-FeedbackUpdateSample` 启动参数时显示示例更新和示例反馈（不需要登录）。
    static var 调试预览: Bool {
        ProcessInfo.processInfo.arguments.contains("-FeedbackUpdateSample")
    }

    fileprivate static var 示例反馈: [反馈项目] {
        func 项目(_ id: String, _ title: String, type: Int, workflow: [Int]) -> String {
            """
            {"id":"\(id)","title":"\(title)","type":\(type),"source":1,"createdAt":"2026-10-28",\
            "submitter":{},"review":{"state":"published"},"status":{"workflow":\(workflow)},"messages":[]}
            """
        }
        let json = "[" + [
            项目("FB-1042", "同步后资料库顺序改变", type: 2, workflow: [2, 2]),
            项目("FB-1038", "希望Today支持隐藏已读作品", type: 1, workflow: [1, 2]),
            项目("FB-1021", "搜索结果中的角色名显示不完整", type: 2, workflow: [2, 1]),
        ].joined(separator: ",") + "]"
        return (try? JSONDecoder().decode([反馈项目].self, from: Data(json.utf8))) ?? []
    }
    #endif
}

struct 反馈页面: View {
    @ObservedObject private var paperAccount = PaperAccount账户.shared
    @ObservedObject private var updates = 反馈更新提醒中心.shared
    private let showsCloseButton: Bool
    private let closeAction: () -> Void
    @State private var state = PaperVN反馈状态()
    @State private var selectedTab = 0
    @State private var filter: 反馈列表筛选?
    @State private var publicMaintenance: [数据维护提交] = []
    @State private var submittedMaintenance: [数据维护提交] = []
    @State private var blockedAuthors = 数据维护屏蔽.全部
    @State private var isComposerPresented = false
    @State private var alert: 反馈提示?
    @State private var isCheckingEligibility = false
    /// 点按“新建反馈”时就开始收集诊断信息，选择“错误报告”时已经收集了一部分
    @State private var diagnostics = PaperVN诊断程序()
    @Namespace private var composerNamespace

    init(
        showsCloseButton: Bool = false,
        closeAction: @escaping () -> Void = {}
    ) {
        self.showsCloseButton = showsCloseButton
        self.closeAction = closeAction
    }

    var body: some View {
        平台滚动页面 {
            Picker("反馈范围", selection: $selectedTab) {
                Text("所有反馈").tag(0)
                Text("已提交").tag(1)
            }
            .pickerStyle(.segmented)
            .listRowInsets(
                EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if selectedTab == 0 {
                allFeedbackSection
            } else {
                submittedFeedbackSection
            }
        }
        .平台分组列表样式()
        .contentMargins(.top, 8, for: .scrollContent)
        .navigationTitle("反馈")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .平台主操作) {
                filterMenu
            }

            ToolbarItem(placement: .平台主操作) {
                Button(action: prepareComposer) {
                    if isCheckingEligibility {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        工具栏圆形图标标签("新建反馈", systemImage: "bubble.and.pencil")
                    }
                }
                .matchedTransitionSource(
                    id: "FeedbackComposerSheet",
                    in: composerNamespace
                )
                .accessibilityLabel("新建反馈")
                .disabled(isCheckingEligibility)
            }
            .平台可见优先级(.高)
            .平台优先纵向栏()

            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: closeAction) {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
        }
        .onAppear {
            // 有更新时直接显示已提交的反馈，更新都在这里
            if !updates.更新.isEmpty {
                selectedTab = 1
            }
        }
        .task(id: paperAccount.资料?.id ?? "") {
            await reloadFeedback()
        }
        .refreshable {
            await reloadFeedback()
        }
        .sheet(isPresented: $isComposerPresented) {
            NavigationStack {
                新建反馈页面(service: state.service, diagnostics: diagnostics) {
                    await reloadFeedback()
                }
            }
            .平台近全屏弹窗()
            .navigationTransition(.zoom(
                sourceID: "FeedbackComposerSheet",
                in: composerNamespace
            ))
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private var publicItems: [反馈列表项] {
        反馈列表项.合并(
            state.publicFeedback,
            publicMaintenance.filter { !blockedAuthors.contains($0.authorID) }
        )
        .filter { $0.符合(filter) }
    }

    private var submittedItems: [反馈列表项] {
        反馈列表项.合并(state.submittedFeedback, submittedMaintenance)
            .filter { $0.符合(filter) }
    }

    private var filterMenu: some View {
        Menu {
            Picker("类型", selection: $filter) {
                Text("全部").tag(反馈列表筛选?.none)
                ForEach(反馈类型.allCases) { type in
                    Text(verbatim: type.localizedTitle).tag(反馈列表筛选?.some(.反馈(type)))
                }
            }
            // 菜单中的 Picker 不显示分组标题，这里用 Toggle 放进 Section，勾号和上面的 Picker 一样
            Section("数据维护") {
                ForEach(数据维护种类.allCases) { kind in
                    Toggle(kind.名称, isOn: Binding(
                        get: { filter == .数据维护(kind) },
                        set: { filter = $0 ? .数据维护(kind) : nil }
                    ))
                }
            }
            if !blockedAuthors.isEmpty {
                Button("取消屏蔽所有用户", systemImage: "person.crop.circle.badge.checkmark") {
                    数据维护屏蔽.清除()
                    blockedAuthors = []
                }
            }
        } label: {
            Image(systemName: filter == nil
                  ? "line.3.horizontal.decrease"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("筛选")
    }

    @ViewBuilder
    private var allFeedbackSection: some View {
        Section {
            if state.isLoading && publicItems.isEmpty {
                ForEach(0..<5, id: \.self) { index in
                    反馈列表占位行(index: index)
                }
            } else if publicItems.isEmpty {
                平台内容不可用视图(
                    "无反馈",
                    systemImage: "exclamationmark.bubble"
                )
            } else {
                ForEach(publicItems) { item in
                    row(item, isSubmitted: false)
                }
            }
        } header: {
            if state.isLoading && publicItems.isEmpty {
                反馈加载区标题()
            }
        } footer: {
            maintenanceFooter
        }
    }

    @ViewBuilder
    private var submittedFeedbackSection: some View {
        Section {
            if state.isLoading && submittedItems.isEmpty {
                ForEach(0..<5, id: \.self) { index in
                    反馈列表占位行(index: index)
                }
            } else if submittedItems.isEmpty {
                平台内容不可用视图(
                    "无已提交反馈",
                    systemImage: "exclamationmark.bubble"
                )
            } else {
                ForEach(submittedItems) { item in
                    row(item, isSubmitted: true)
                }
            }
        } header: {
            if state.isLoading && submittedItems.isEmpty {
                反馈加载区标题()
            }
        } footer: {
            maintenanceFooter
        }
    }

    /// 数据维护不在这里新建，提示从作品详情提交。
    @ViewBuilder
    private var maintenanceFooter: some View {
        if case .数据维护? = filter {
            Text("可以在作品详情中报告简介翻译错误、音乐匹配错误或添加音乐。提交和回复将在审核后公开。")
        }
    }

    @ViewBuilder
    private func row(_ item: 反馈列表项, isSubmitted: Bool) -> some View {
        switch item {
        case let .反馈(feedback):
            NavigationLink {
                反馈详情页面(
                    feedback: feedback,
                    service: state.service,
                    isOwnedByCurrentUser: isSubmitted || (feedback.ownedByCurrentUser ?? false)
                )
            } label: {
                反馈列表行(feedback: feedback)
            }
        case let .数据维护(maintenance):
            NavigationLink {
                数据维护详情页面(初始内容: maintenance) {
                    blockedAuthors = 数据维护屏蔽.全部
                    await reloadMaintenance()
                }
            } label: {
                数据维护列表行(item: maintenance)
            }
        }
    }

    private func prepareComposer() {
        // 每次新建反馈重新收集，不用上一次的结果
        diagnostics = PaperVN诊断程序()
        diagnostics.开始()
        isCheckingEligibility = true
        Task {
            defer { isCheckingEligibility = false }
            do {
                let eligibility = try await state.service.eligibility(token: try await paperAccount.可选访问令牌())
                guard eligibility.canCreate else {
                    alert = rateLimitAlert(count: eligibility.unreviewedCount)
                    return
                }
                isComposerPresented = true
            } catch let error as 反馈服务错误 {
                switch error {
                case .unavailable, .invalidResponse:
                    alert = 反馈提示(
                        title: String(localized: "无法连接服务器"),
                        message: String(localized: "服务器当前不可用，请稍后再试。")
                    )
                case let .server(_, message):
                    alert = 反馈提示(
                        title: String(localized: "无法新建反馈"),
                        message: message
                    )
                }
            } catch {
                alert = 反馈提示(
                    title: String(localized: "无法连接服务器"),
                    message: String(localized: "服务器当前不可用，请稍后再试。")
                )
            }
        }
    }

    private var 显示示例反馈: Bool {
        #if DEBUG
        反馈更新提醒中心.调试预览
        #else
        false
        #endif
    }

    private func reloadFeedback() async {
        #if DEBUG
        if 反馈更新提醒中心.调试预览 {
            state.submittedFeedback = 反馈更新提醒中心.示例反馈
            publicMaintenance = 数据维护提交.示例.filter { $0.status != "pending" }
            submittedMaintenance = 数据维护提交.示例.filter(\.isOwn)
            return
        }
        #endif
        let token = try? await paperAccount.可选访问令牌()
        async let maintenance: Void = reloadMaintenance()
        await state.reload(token: token)
        await maintenance
        if let accountID = paperAccount.资料?.id, state.errorMessage == nil {
            updates.接收(state.submittedFeedback, userID: accountID)
        }
    }

    /// 数据维护用设备码识别，和反馈分开加载；失败时保留上次的结果。
    private func reloadMaintenance() async {
        let service = 数据维护服务()
        async let all = service.列表(scope: "public")
        async let mine = service.列表(scope: "mine")
        if let all = try? await all { publicMaintenance = all }
        if let mine = try? await mine { submittedMaintenance = mine }
    }

    private func rateLimitAlert(count: Int) -> 反馈提示 {
        反馈提示(
            title: String(localized: "速率限制"),
            message: String(
                localized: "你已有\(count)个未结反馈。为了防止滥用，在我们查看你的问题之前，你将无法提交反馈。"
            )
        )
    }
}

private struct 反馈加载区标题: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在加载…")
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

private struct 反馈列表占位行: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("正在加载…")
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text("正在调查")
                .font(.caption)
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .padding(.vertical, 3)
    }
}

private struct 反馈列表行: View {
    @ObservedObject private var updates = 反馈更新提醒中心.shared

    let feedback: 反馈项目
    var emphasizesTitle = true

    private var 更新种类: 反馈更新提醒中心.更新种类? {
        updates.更新[feedback.id]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: feedback.title)
                    .font(emphasizesTitle ? .body.weight(.semibold) : .body)
                    .lineLimit(2)

                Spacer(minLength: 0)

                Text(verbatim: feedback.createdAt.dayText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(1)
            }

            HStack(spacing: 12) {
                Text(verbatim: feedback.id)

                Spacer(minLength: 0)

                if 更新种类 != nil {
                    Circle()
                        .fill(.tint)
                        .frame(width: 7, height: 7)
                        .padding(.trailing, -6)
                        .accessibilityHidden(true)
                }

                if 更新种类 == .回复 {
                    Text(verbatim: 反馈更新提醒中心.提示(.回复))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                } else {
                    Text(
                        verbatim: feedback.status.localizedSummary(
                            for: feedback.feedbackType
                        )
                    )
                        .foregroundStyle(更新种类 == .状态 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityValue(更新种类.map(反馈更新提醒中心.提示) ?? "")
    }
}

private struct 已提交反馈提示行: View {
    let feedback: 反馈项目

    private var title: String {
        feedback.isIgnored
            ? String(localized: "已忽略反馈")
            : String(localized: "已提交反馈")
    }

    private var description: String {
        guard feedback.isIgnored else {
            return String(localized: "我们将在查看后展示你的反馈。请勿重复提交相同反馈。")
        }
        if feedback.review.ignoredReason?.code == 1 {
            return String(localized: "你最近提交的一个反馈因滥用已被忽略。")
        }
        let reason = feedback.review.ignoredReason?.message?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let reason, !reason.isEmpty else {
            return String(localized: "你最近提交的一个反馈已被忽略。")
        }
        return String(localized: "你最近提交的一个反馈已被忽略，原因是：“\(reason)”。")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: title)
                .font(.headline.weight(.semibold))
            Text(verbatim: description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct 快速反馈页面: View {
    @ObservedObject private var paperAccount = PaperAccount账户.shared
    @Environment(\.dismiss) private var dismiss

    let title: String
    let description: String
    var clientInfo: [String: String] = [:]
    var onSubmitted: () -> Void = {}
    /// 和页面同生命周期：界面重新计算时不能换成新的、没在运行的诊断程序
    @State private var diagnostics = PaperVN诊断程序()

    /// 调试用：带 `-FeedbackDiagnosticsSample` 启动参数时不登录也能打开（提交会失败）。
    static var 调试预览: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-FeedbackDiagnosticsSample")
        #else
        false
        #endif
    }

    var body: some View {
        NavigationStack {
            新建反馈页面(
                service: PaperVN反馈服务(),
                initialTitle: title,
                initialType: .bugReport,
                initialDescription: description,
                extraClientInfo: clientInfo,
                diagnostics: diagnostics
            ) {
                onSubmitted()
            }
        }
    }
}

private struct 新建反馈页面: View {
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.dismiss) private var dismiss

    let service: PaperVN反馈服务
    let extraClientInfo: [String: String]
    let onSubmitted: () async -> Void
    let diagnostics: PaperVN诊断程序

    @State private var title: String
    @State private var contact = ""
    @State private var type: 反馈类型
    @State private var description: String

    init(
        service: PaperVN反馈服务,
        initialTitle: String = "",
        initialType: 反馈类型 = .suggestion,
        initialDescription: String = "",
        extraClientInfo: [String: String] = [:],
        diagnostics: PaperVN诊断程序,
        onSubmitted: @escaping () async -> Void
    ) {
        self.service = service
        self.diagnostics = diagnostics
        self.extraClientInfo = extraClientInfo
        self.onSubmitted = onSubmitted
        _title = State(initialValue: initialTitle)
        _type = State(initialValue: initialType)
        _description = State(initialValue: initialDescription)
    }
    @State private var attachments: [反馈上传附件] = []
    @State private var isPhotoPickerPresented = false
    @State private var isSubmitting = false
    @State private var alert: 反馈提示?

    var body: some View {
        Form {
            Section {
                TextField("标题", text: $title)
            }

            Section {
                if PaperAccount账户.shared.isLoggedIn {
                    LabeledContent("Paper账户", value: PaperAccount账户.shared.资料?.nickname ?? String(localized: "未设置昵称"))
                } else {
                    LabeledContent("提交者", value: String(localized: "匿名"))
                }
                TextField("联系方式（可选）", text: $contact, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                Picker("类型", selection: $type) {
                    ForEach(反馈类型.allCases) { type in
                        Text(verbatim: type.localizedTitle).tag(type)
                    }
                }
            }

            Section("描述") {
                TextEditor(text: $description)
                    .frame(minHeight: 150)
            }

            反馈附件选择区(
                attachments: $attachments,
                maximumCount: 5,
                onChoosePhotos: { isPhotoPickerPresented = true }
            )

            if type == .bugReport {
                反馈诊断区(diagnostics: diagnostics)
            }
        }
        .反馈照片选择器(
            isPresented: $isPhotoPickerPresented,
            attachments: $attachments,
            maximumCount: 5,
            alert: $alert
        )
        .navigationTitle("新建反馈")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        // 从其他页面直接打开（快速反馈）时这里才开始收集；已经开始的不会重复
        .onAppear { diagnostics.开始() }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Label("取消", systemImage: "xmark")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Button(action: submit) {
                        Label("提交", systemImage: "arrow.up")
                    }
                    .液态玻璃醒目按钮(in: Circle())
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            // 错误报告要等诊断信息收集完
                            || (type == .bugReport && !diagnostics.已完成)
                    )
                }
            }
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func submit() {
        guard !isSubmitting, type != .bugReport || diagnostics.已完成 else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let request = 新建反馈请求(
                    title: title,
                    contact: contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : contact,
                    type: type.rawValue,
                    description: description,
                    source: 反馈来源.app.rawValue,
                    attachments: attachments.map(attachmentRequest),
                    client: clientInfo,
                    diagnostics: type == .bugReport ? diagnostics.报告 : nil
                )
                _ = try await service.create(token: try await PaperAccount账户.shared.可选访问令牌(), requestBody: request)
                await onSubmitted()
                dismiss()
            } catch let error as 反馈服务错误 where error.code == "rate_limited" {
                alert = 反馈提示(
                    title: String(localized: "速率限制"),
                    message: error.localizedDescription
                )
            } catch {
                alert = 反馈提示(
                    title: String(localized: "无法提交"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private var clientInfo: [String: String] {
        [
            "appVersion": Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "",
            "build": Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "",
            "platform": platformName,
        ].merging(extraClientInfo) { current, _ in current }
    }

    private var platformName: String {
        "iOS"
    }
}

private struct 反馈详情页面: View {
    @EnvironmentObject private var auth: 用户登录

    let service: PaperVN反馈服务
    let isOwnedByCurrentUser: Bool
    @State private var feedback: 反馈项目
    @State private var isReplyPresented = false
    @State private var isCloseConfirmationPresented = false
    @State private var alert: 反馈提示?

    init(
        feedback: 反馈项目,
        service: PaperVN反馈服务,
        isOwnedByCurrentUser: Bool
    ) {
        self.service = service
        self.isOwnedByCurrentUser = isOwnedByCurrentUser
        _feedback = State(initialValue: feedback)
    }

    private var attachmentCount: Int {
        feedback.messages.reduce(0) { $0 + $1.attachments.count }
    }

    private var submissionMessage: 反馈消息? {
        feedback.messages.first(where: { !$0.isDeveloper }) ?? feedback.messages.first
    }

    private var additionalMessages: [反馈消息] {
        guard let submissionMessage else { return feedback.messages }
        return feedback.messages.filter { $0.id != submissionMessage.id }
    }

    private var showsSubmissionNotice: Bool {
        isOwnedByCurrentUser && (!feedback.isPublished || feedback.isIgnored)
    }

    @ViewBuilder
    private var feedbackActions: some View {
        Button {
            isReplyPresented = true
        } label: {
            Label("添加更多信息", systemImage: "text.bubble")
        }

        Button {
            isCloseConfirmationPresented = true
        } label: {
            Label("关闭反馈", systemImage: "checkmark.bubble")
        }
    }

    var body: some View {
        平台滚动页面 {
            if showsSubmissionNotice {
                Section {
                    已提交反馈提示行(feedback: feedback)
                } footer: {
                    Color.clear
                        .frame(height: 14)
                        .accessibilityHidden(true)
                }
            }

            Group {
                if let submissionMessage {
                    Section {
                        反馈提交详情内容(
                            feedback: feedback,
                            message: submissionMessage,
                            service: service
                        )
                    }
                }

                if !additionalMessages.isEmpty {
                    Section {
                        ForEach(additionalMessages) { message in
                            反馈消息行(
                                message: message,
                                submitterName: feedback.submitter.显示名称,
                                service: service
                            )
                        }
                    }
                }
            }
        }
        .平台分组列表样式()
        .listSectionSpacing(12)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            反馈状态底部栏(
                status: feedback.status,
                feedbackType: feedback.feedbackType
            )
        }
        .task(id: feedback.status.notificationKey + feedback.developerReplyKey) {
            if isOwnedByCurrentUser {
                反馈更新提醒中心.shared.标记已查看(feedback)
            }
        }
        .navigationTitle(feedback.id)
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if isOwnedByCurrentUser, !feedback.status.isClosed {
                // iOS 27 起放进系统溢出菜单，iPhone Duo 纵向栏与其他页面的“…”保持一致
                if #available(iOS 27.0, *) {
                    ToolbarOverflowMenu {
                        feedbackActions
                    }
                } else {
                    ToolbarItem(placement: .平台主操作) {
                        Menu {
                            feedbackActions
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .tint(.primary)
                        .accessibilityLabel("更多操作")
                    }
                }
            }
        }
        .sheet(isPresented: $isReplyPresented) {
            NavigationStack {
                添加反馈信息页面(
                    service: service,
                    feedbackID: feedback.id,
                    maximumAttachmentCount: max(0, 5 - attachmentCount)
                ) { updatedFeedback in
                    feedback = updatedFeedback
                }
            }
            .平台近全屏弹窗()
        }
        .confirmationDialog(
            "要关闭反馈吗？",
            isPresented: $isCloseConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("关闭反馈", action: closeFeedback)
            Button("取消", role: .cancel) {}
        } message: {
            Text("此反馈将无法重新打开，也无法再添加更多信息。")
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func closeFeedback() {
        Task {
            do {
                feedback = try await service.close(token: try await PaperAccount账户.shared.可选访问令牌(), id: feedback.id)
            } catch {
                alert = 反馈提示(
                    title: String(localized: "无法关闭反馈"),
                    message: error.localizedDescription
                )
            }
        }
    }
}

private struct 反馈状态底部栏: View {
    let status: 反馈工作流状态
    let feedbackType: 反馈类型?

    private var systemImage: String {
        status.isClosed ? "checkmark.circle.fill" : "clock.fill"
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.regularMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.54), location: 0.42),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: 24)
                .blur(radius: 5)

            Label {
                Text(verbatim: status.localizedSummary(for: feedbackType))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .液态玻璃(
                .regular,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct 反馈提交详情内容: View {
    let feedback: 反馈项目
    let message: 反馈消息
    let service: PaperVN反馈服务

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                avatar
                    .frame(width: 36, height: 36)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: authorName)
                        .font(.body.weight(.semibold))
                    Text(verbatim: message.createdAt.detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .offset(y: -6)

            Text(verbatim: feedback.title)
                .font(.title3.weight(.semibold))

            Divider()

            Text(verbatim: message.description)
                .textSelection(.enabled)

            if !message.attachments.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(message.attachments) { attachment in
                        反馈附件下载行(
                            attachment: attachment,
                            service: service
                        )
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var avatar: some View {
        if message.isDeveloper {
            Image("PaperVNAppIcon")
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private var authorName: String {
        guard let username = feedback.submitter.显示名称?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !username.isEmpty else {
            return String(localized: "匿名")
        }
        return username
    }
}

private struct 反馈消息行: View {
    let message: 反馈消息
    let submitterName: String?
    let service: PaperVN反馈服务

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
                .frame(width: 36, height: 36)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: message.isDeveloper ? String(localized: "PaperVN反馈") : authorName)
                    .font(.body.weight(.semibold))
                Text(verbatim: message.createdAt.detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: message.description)
                    .textSelection(.enabled)
                if !message.attachments.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(message.attachments) { attachment in
                            反馈附件下载行(
                                attachment: attachment,
                                service: service
                            )
                        }
                    }
                }
            }
        }
        .offset(y: -6)
        .padding(.top, 6)
        .padding(.bottom, -6)
    }

    @ViewBuilder
    private var avatar: some View {
        if message.isDeveloper {
            Image("PaperVNAppIcon")
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }

    private var authorName: String {
        guard let username = submitterName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !username.isEmpty else {
            return String(localized: "匿名")
        }
        return username
    }
}

private struct 反馈附件下载行: View {
    @Environment(\.openURL) private var openURL

    let attachment: 反馈附件
    let service: PaperVN反馈服务

    var body: some View {
        if let url = service.attachmentURL(for: attachment) {
            Button {
                openURL(url)
            } label: {
                attachmentRow
            }
            .buttonStyle(.plain)
            .accessibilityHint("下载附件")
        } else {
            attachmentRow
        }
    }

    private var attachmentRow: some View {
        HStack(alignment: .center, spacing: 8) {
            attachmentLabel

            Image(systemName: "chevron.right")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var attachmentLabel: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "document")
                .foregroundStyle(.tint)
                .frame(width: 17)

            Text(verbatim: attachment.filename)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
        }
        .font(.body)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

private struct 添加反馈信息页面: View {
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.dismiss) private var dismiss

    let service: PaperVN反馈服务
    let feedbackID: String
    let maximumAttachmentCount: Int
    let onSubmitted: (反馈项目) -> Void

    @State private var description = ""
    @State private var attachments: [反馈上传附件] = []
    @State private var isPhotoPickerPresented = false
    @State private var isSubmitting = false
    @State private var alert: 反馈提示?

    var body: some View {
        Form {
            Section("更多信息") {
                TextEditor(text: $description)
                    .frame(minHeight: 170)
            }
            反馈附件选择区(
                attachments: $attachments,
                maximumCount: maximumAttachmentCount,
                onChoosePhotos: { isPhotoPickerPresented = true }
            )
        }
        .反馈照片选择器(
            isPresented: $isPhotoPickerPresented,
            attachments: $attachments,
            maximumCount: maximumAttachmentCount,
            alert: $alert
        )
        .navigationTitle("添加更多信息")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Label("取消", systemImage: "xmark")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Button(action: submit) {
                        Label("提交", systemImage: "arrow.up")
                    }
                    .disabled(
                        description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
        .alert(item: $alert) { alert in
            Alert(
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            do {
                let updatedFeedback = try await service.addInformation(
                    token: try await PaperAccount账户.shared.可选访问令牌(),
                    id: feedbackID,
                    requestBody: 添加反馈信息请求(
                        description: description,
                        attachments: attachments.map(attachmentRequest)
                    )
                )
                onSubmitted(updatedFeedback)
                dismiss()
            } catch {
                alert = 反馈提示(
                    title: String(localized: "无法提交"),
                    message: error.localizedDescription
                )
            }
        }
    }
}

private struct 反馈附件选择区: View {
    @Binding var attachments: [反馈上传附件]
    let maximumCount: Int
    let onChoosePhotos: () -> Void

    @State private var isImporterPresented = false
    @State private var alert: 反馈提示?

    var body: some View {
        Section(content: {
            ForEach(attachments) { attachment in
                HStack {
                    Label {
                        Text(verbatim: attachment.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "paperclip")
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("移除附件")
                }
            }

            Menu {
                Button {
                    presentPhotoPicker()
                } label: {
                    Label("照片或视频", systemImage: "photo.on.rectangle")
                }

                Button {
                    presentFileImporter()
                } label: {
                    Label("文件", systemImage: "folder")
                }
            } label: {
                Label("添加附件", systemImage: "paperclip")
            }
            .disabled(attachments.count >= maximumCount)
        }, header: {
            Text("附件")
        }, footer: {
            Text("最多5个附件，每个附件不超过5 MB。")
        })
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .alert(item: $alert) { alert in
            Alert(
                title: Text(verbatim: alert.title),
                message: Text(verbatim: alert.message),
                dismissButton: .default(Text("好"))
            )
        }
    }

    private func presentFileImporter() {
        Task { @MainActor in
            await Task.yield()
            isImporterPresented = true
        }
    }

    private func presentPhotoPicker() {
        Task { @MainActor in
            await Task.yield()
            onChoosePhotos()
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result else { return }
        let remainingCount = max(0, maximumCount - attachments.count)
        guard remainingCount > 0 else { return }

        for url in urls.prefix(remainingCount) {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                appendAttachment(
                    filename: url.lastPathComponent,
                    mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
                    data: data
                )
            } catch {
                alert = 反馈提示(
                    title: String(localized: "无法读取附件"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func appendAttachment(filename: String, mimeType: String, data: Data) {
        guard data.count <= 5 * 1024 * 1024 else {
            alert = 反馈提示(
                title: String(localized: "附件大小限制"),
                message: String(localized: "附件大小不可超过5 MB。如果你确实需要上传，请在描述中附上网盘链接。")
            )
            return
        }
        attachments.append(
            反馈上传附件(
                filename: filename,
                mimeType: mimeType,
                data: data
            )
        )
    }
}

private struct 反馈照片选择器Modifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var attachments: [反馈上传附件]
    let maximumCount: Int
    @Binding var alert: 反馈提示?

    @State private var selectedItems: [PhotosPickerItem] = []

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $isPresented,
                selection: $selectedItems,
                maxSelectionCount: max(1, maximumCount - attachments.count),
                selectionBehavior: .ordered,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current
            )
            .onChange(of: selectedItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                selectedItems = []
                Task { @MainActor in
                    await importMedia(newItems)
                }
            }
    }

    @MainActor
    private func importMedia(_ items: [PhotosPickerItem]) async {
        let remainingCount = max(0, maximumCount - attachments.count)
        guard remainingCount > 0 else { return }

        for item in items.prefix(remainingCount) {
            guard let contentType = item.supportedContentTypes.first(where: {
                $0.conforms(to: .image) || $0.conforms(to: .movie)
            }) else {
                alert = 反馈提示(
                    title: String(localized: "无法读取附件"),
                    message: 反馈服务错误.invalidResponse.localizedDescription
                )
                continue
            }

            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw CocoaError(.fileReadUnknown)
                }
                guard data.count <= 5 * 1024 * 1024 else {
                    alert = 反馈提示(
                        title: String(localized: "附件大小限制"),
                        message: String(localized: "附件大小不可超过5 MB。如果你确实需要上传，请在描述中附上网盘链接。")
                    )
                    continue
                }
                guard attachments.count < maximumCount else { return }

                attachments.append(
                    反馈上传附件(
                        filename: mediaFilename(for: contentType),
                        mimeType: contentType.preferredMIMEType
                            ?? (contentType.conforms(to: .movie)
                                ? "video/quicktime"
                                : "image/jpeg"),
                        data: data
                    )
                )
            } catch {
                alert = 反馈提示(
                    title: String(localized: "无法读取附件"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func mediaFilename(for contentType: UTType) -> String {
        let isVideo = contentType.conforms(to: .movie)
        let filenameExtension = contentType.preferredFilenameExtension
            ?? (isVideo ? "mov" : "jpg")
        return "\(isVideo ? "video" : "photo")-\(UUID().uuidString).\(filenameExtension)"
    }
}

private extension View {
    func 反馈照片选择器(
        isPresented: Binding<Bool>,
        attachments: Binding<[反馈上传附件]>,
        maximumCount: Int,
        alert: Binding<反馈提示?>
    ) -> some View {
        modifier(
            反馈照片选择器Modifier(
                isPresented: isPresented,
                attachments: attachments,
                maximumCount: maximumCount,
                alert: alert
            )
        )
    }
}

private func attachmentRequest(_ attachment: 反馈上传附件) -> 反馈附件请求 {
    反馈附件请求(
        filename: attachment.filename,
        mimeType: attachment.mimeType,
        data: attachment.data
    )
}

/// 新建错误报告时的诊断信息：收集中显示进度，收集完可以查看将要提交的全部内容。
private struct 反馈诊断区: View {
    let diagnostics: PaperVN诊断程序

    var body: some View {
        Section {
            if let report = diagnostics.报告 {
                NavigationLink {
                    诊断信息页面(report: report)
                } label: {
                    Label("诊断信息", systemImage: "stethoscope")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("正在收集诊断信息…", systemImage: "stethoscope")
                    ProgressView(value: diagnostics.进度)
                        .animation(.default, value: diagnostics.进度)
                }
                .padding(.vertical, 4)
            }
        } footer: {
            Text("错误报告将收集诊断信息以帮助我们找到问题。")
        }
    }
}

/// 将要随错误报告提交的诊断信息，逐项列出。
struct 诊断信息页面: View {
    let report: 诊断报告

    var body: some View {
        List {
            ForEach(report.sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        LabeledContent {
                            // 值太长换到标题下面时，文字框也要靠右，不只是各行之间靠右
                            Text(verbatim: item.value)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .textSelection(.enabled)
                        } label: {
                            HStack(spacing: 6) {
                                if let status = item.status, status != .正常 {
                                    Image(systemName: status == .错误 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(status == .错误 ? .red : .orange)
                                        .accessibilityLabel(status == .错误 ? Text("错误") : Text("注意"))
                                }
                                Text(verbatim: item.title)
                            }
                        }
                    }
                }
            }
            if let date = report.收集时间 {
                Section {
                    LabeledContent("收集时间") {
                        Text(date, format: .dateTime)
                    }
                }
            }
        }
        .navigationTitle("诊断信息")
        .平台内联导航标题()
    }
}
