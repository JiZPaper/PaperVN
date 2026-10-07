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

    var localizedTitle: String {
        switch self {
        case .app: String(localized: "App内")
        case .testFlight: String(localized: "TestFlight")
        case .qq: String(localized: "QQ")
        case .discord: String(localized: "Discord")
        case .telegram: String(localized: "Telegram")
        case .email: String(localized: "电子邮件")
        case .other: String(localized: "其他")
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
    private let baseURL = URL(string: "https://papervn.jizpaper.com/api/feedback/")!

    func publicFeedback() async throws -> [反馈项目] {
        let response: 反馈列表响应 = try await request(
            path: "/feedback?scope=public",
            method: "GET",
            token: nil,
            body: Optional<EmptyRequest>.none
        )
        return response.feedback
    }

    func ownFeedback(token: String) async throws -> [反馈项目] {
        let response: 反馈列表响应 = try await request(
            path: "/feedback?scope=mine",
            method: "GET",
            token: token,
            body: Optional<EmptyRequest>.none
        )
        return response.feedback
    }

    func eligibility(token: String) async throws -> 新建反馈资格 {
        try await request(
            path: "/eligibility",
            method: "GET",
            token: token,
            body: Optional<EmptyRequest>.none
        )
    }

    func create(token: String, requestBody: 新建反馈请求) async throws -> 反馈项目 {
        try await request(
            path: "/feedback",
            method: "POST",
            token: token,
            body: requestBody
        )
    }

    func addInformation(
        token: String,
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

    func close(token: String, id: String) async throws -> 反馈项目 {
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
            publicFeedback = try await service.publicFeedback()
            if let token, !token.isEmpty {
                submittedFeedback = try await service.ownFeedback(token: token)
            } else {
                submittedFeedback = []
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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

private func 反馈更新提示(
    for feedback: [反馈项目],
    userID: String
) -> [反馈提示] {
    guard !userID.isEmpty else { return [] }

    let previousSnapshots = 反馈更新提醒记录.load(for: userID)
    var currentSnapshots: [String: 反馈更新快照] = [:]
    var updates: [反馈提示] = []

    for item in feedback {
        let current = 反馈更新快照(
            statusKey: item.status.notificationKey,
            developerReplyKey: item.developerReplyKey
        )
        currentSnapshots[item.id] = current

        guard let previous = previousSnapshots[item.id] else { continue }
        if previous.developerReplyKey != current.developerReplyKey,
           !current.developerReplyKey.isEmpty {
            updates.append(
                反馈提示(
                    title: String(
                        format: String(localized: "反馈“%@”的状态更新"),
                        item.title
                    ),
                    message: String(localized: "开发者对你的反馈做出了回复。")
                )
            )
        } else if previous.statusKey != current.statusKey {
            updates.append(
                反馈提示(
                    title: String(
                        format: String(localized: "反馈“%@”的状态更新"),
                        item.title
                    ),
                    message: String(
                        format: String(localized: "开发者已将你的反馈标记为“%@”。"),
                        item.status.localizedSummary(for: item.feedbackType)
                    )
                )
            )
        }
    }

    反馈更新提醒记录.save(currentSnapshots, for: userID)
    return updates
}

@MainActor
final class 反馈更新提醒中心: ObservableObject {
    @Published var alert: 反馈提示?

    private let service = PaperVN反馈服务()
    private var pendingAlerts: [反馈提示] = []
    private var isRefreshing = false

    func refresh(token: String?, userID: String) async {
        guard let token, !token.isEmpty, !userID.isEmpty, !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let feedback = try? await service.ownFeedback(token: token) else {
            return
        }
        pendingAlerts.append(contentsOf: 反馈更新提示(for: feedback, userID: userID))
        showNextAlertIfNeeded()
    }

    func dismissCurrentAlert() {
        alert = nil
        guard !pendingAlerts.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.showNextAlertIfNeeded()
        }
    }

    private func showNextAlertIfNeeded() {
        guard alert == nil, !pendingAlerts.isEmpty else { return }
        alert = pendingAlerts.removeFirst()
    }
}

struct 反馈页面: View {
    @EnvironmentObject private var auth: 用户登录
    private let showsCloseButton: Bool
    private let closeAction: () -> Void
    @State private var state = PaperVN反馈状态()
    @State private var selectedTab = 0
    @State private var isComposerPresented = false
    @State private var alert: 反馈提示?
    @State private var isCheckingEligibility = false
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
                Button(action: prepareComposer) {
                    if isCheckingEligibility {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bubble.and.pencil")
                    }
                }
                .matchedTransitionSource(
                    id: "FeedbackComposerSheet",
                    in: composerNamespace
                )
                .accessibilityLabel("新建反馈")
                .disabled(isCheckingEligibility)
            }

            if showsCloseButton {
                ToolbarItem(placement: .平台前导操作) {
                    Button(action: closeAction) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .task(id: auth.token + auth.userID) {
            await reloadFeedback()
        }
        .refreshable {
            await reloadFeedback()
        }
        .sheet(isPresented: $isComposerPresented) {
            NavigationStack {
                新建反馈页面(service: state.service) {
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

    @ViewBuilder
    private var allFeedbackSection: some View {
        Section {
            if state.isLoading && state.publicFeedback.isEmpty {
                ForEach(0..<5, id: \.self) { index in
                    反馈列表占位行(index: index)
                }
            } else if state.publicFeedback.isEmpty {
                平台内容不可用视图(
                    "无反馈",
                    systemImage: "exclamationmark.bubble"
                )
            } else {
                ForEach(state.publicFeedback) { feedback in
                    NavigationLink {
                        反馈详情页面(
                            feedback: feedback,
                            service: state.service,
                            isOwnedByCurrentUser: feedback.submitter.vndbID == auth.userID
                        )
                    } label: {
                        反馈列表行(feedback: feedback)
                    }
                }
            }
        } header: {
            if state.isLoading && state.publicFeedback.isEmpty {
                反馈加载区标题()
            }
        }
    }

    @ViewBuilder
    private var submittedFeedbackSection: some View {
        Section {
            if !auth.isLoggedIn {
                平台内容不可用视图(
                    "需要登录",
                    systemImage: "person.crop.circle",
                    description: Text("需要登录VNDB账户以查看已提交反馈。")
                )
            } else if state.isLoading && state.submittedFeedback.isEmpty {
                ForEach(0..<5, id: \.self) { index in
                    反馈列表占位行(index: index)
                }
            } else if state.submittedFeedback.isEmpty {
                平台内容不可用视图(
                    "无已提交反馈",
                    systemImage: "exclamationmark.bubble"
                )
            } else {
                ForEach(state.submittedFeedback) { feedback in
                    submittedRow(feedback)
                }
            }
        } header: {
            if auth.isLoggedIn && state.isLoading && state.submittedFeedback.isEmpty {
                反馈加载区标题()
            }
        }
    }

    @ViewBuilder
    private func submittedRow(_ feedback: 反馈项目) -> some View {
        NavigationLink {
            反馈详情页面(
                feedback: feedback,
                service: state.service,
                isOwnedByCurrentUser: true
            )
        } label: {
            反馈列表行(feedback: feedback, emphasizesTitle: true)
        }
    }

    private func prepareComposer() {
        guard auth.isLoggedIn, !auth.token.isEmpty else {
            alert = 反馈提示(
                title: String(localized: "需要登录"),
                message: String(localized: "需要登录VNDB账户以提交反馈。")
            )
            return
        }
        isCheckingEligibility = true
        Task {
            defer { isCheckingEligibility = false }
            do {
                let eligibility = try await state.service.eligibility(token: auth.token)
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

    private func reloadFeedback() async {
        await state.reload(token: auth.isLoggedIn ? auth.token : nil)
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
            Text("正在载入…")
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

private struct 反馈列表占位行: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("正在载入…")
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
    let feedback: 反馈项目
    var emphasizesTitle = true

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

                Text(
                    verbatim: feedback.status.localizedSummary(
                        for: feedback.feedbackType
                    )
                )
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.dismiss) private var dismiss

    let title: String
    let description: String
    var clientInfo: [String: String] = [:]
    var onSubmitted: () -> Void = {}

    var body: some View {
        NavigationStack {
            if auth.isLoggedIn, !auth.token.isEmpty {
                新建反馈页面(
                    service: PaperVN反馈服务(),
                    initialTitle: title,
                    initialType: .bugReport,
                    initialDescription: description,
                    extraClientInfo: clientInfo
                ) {
                    onSubmitted()
                }
            } else {
                平台内容不可用视图(
                    "需要登录",
                    systemImage: "person.crop.circle",
                    description: Text("需要登录VNDB账户以提交反馈。")
                )
                .navigationTitle("新建反馈")
                .平台柔和滚动边缘(for: .top)
                .平台内联导航标题()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("取消")
                    }
                }
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
        onSubmitted: @escaping () async -> Void
    ) {
        self.service = service
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
                LabeledContent("用户名", value: auth.username)
                LabeledContent("VNDB ID", value: auth.userID)
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("取消")
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                    }
                    .液态玻璃醒目按钮(in: Circle())
                    .buttonBorderShape(.circle)
                    .tint(.blue)
                    .accessibilityLabel("提交")
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                let request = 新建反馈请求(
                    title: title,
                    contact: contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : contact,
                    type: type.rawValue,
                    description: description,
                    source: 反馈来源.app.rawValue,
                    attachments: attachments.map(attachmentRequest),
                    client: clientInfo
                )
                _ = try await service.create(token: auth.token, requestBody: request)
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
                                submitterName: feedback.submitter.vndbUsername,
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
        .navigationTitle(feedback.id)
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if isOwnedByCurrentUser, !feedback.status.isClosed {
                ToolbarItem(placement: .平台主操作) {
                    Menu {
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
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .tint(.primary)
                    .accessibilityLabel("更多操作")
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
            Text("关闭后无法重新开启，也无法再添加更多信息。")
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
                feedback = try await service.close(token: auth.token, id: feedback.id)
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
        guard let username = feedback.submitter.vndbUsername?.trimmingCharacters(
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
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("取消")
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSubmitting {
                    ProgressView()
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                    }
                    .accessibilityLabel("提交")
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
                    token: auth.token,
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
