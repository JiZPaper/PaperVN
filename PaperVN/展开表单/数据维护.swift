import SwiftUI

// “数据维护”：简介翻译错误、贡献翻译、音乐匹配错误、添加音乐。显示在“反馈”的列表中，和反馈一起筛选。
// 所有人都能看已公开的提交，也能投票和回复；提交和回复都要审核后才公开。不需要登录，未登录时显示“匿名”，用设备码识别。

// MARK: - 数据

enum 数据维护种类: String, Codable, CaseIterable, Identifiable, Sendable {
    case 简介翻译错误 = "translationError"
    case 贡献翻译 = "translation"
    case 音乐匹配错误 = "musicMismatch"
    case 添加音乐 = "musicAddition"

    var id: String { rawValue }

    var 名称: String {
        switch self {
        case .简介翻译错误: String(localized: "简介翻译错误")
        case .贡献翻译: String(localized: "贡献翻译")
        case .音乐匹配错误: String(localized: "音乐匹配错误")
        case .添加音乐: String(localized: "添加音乐")
        }
    }

    var 图标: String {
        switch self {
        case .简介翻译错误: "exclamationmark.bubble"
        case .贡献翻译: "character.bubble"
        case .音乐匹配错误: "music.note"
        case .添加音乐: "plus"
        }
    }
}

struct 数据维护回复: Codable, Identifiable, Sendable {
    let id: String
    let author: String?
    let authorID: String
    let official: Bool
    let text: String
    let state: String
    let isOwn: Bool
    let createdAt: Date
}

struct 数据维护提交: Codable, Identifiable, Sendable {
    let id: String
    let kind: 数据维护种类
    let status: String
    let author: String?
    let authorID: String
    let isOwn: Bool
    let support: Int
    let oppose: Int
    let myVote: Int
    let replyCount: Int
    let createdAt: Date
    let work: String?
    let title: String?
    let artist: String?
    let note: String?
    let source: String?
    let suggestion: String?
    let reviewNote: String?
    let language: String?
    let songKind: String?
    let track: String?
    let notInAppleMusic: Bool?
    let trackInfo: 数据维护草稿.歌曲信息?
    let display: 数据维护草稿.显示信息?
    let replies: [数据维护回复]?

    var 状态名称: String {
        switch status {
        case "pending": String(localized: "等待审核")
        case "discussion": String(localized: "已展示")
        case "accepted": String(localized: "已采纳")
        case "rejected": String(localized: "已拒绝")
        case "withdrawn": String(localized: "已撤回")
        default: status
        }
    }

    var 标题: String { title ?? work ?? id }
    var 署名: String { author ?? String(localized: "匿名") }
}

#if DEBUG
extension 数据维护提交 {
    /// 调试用：和示例反馈一起在 `-FeedbackUpdateSample` 下显示。
    static var 示例: [数据维护提交] {
        let json = """
        [{"id":"DM3","kind":"musicMismatch","status":"discussion","author":null,"authorID":"a1","isOwn":false,"support":3,"oppose":1,"myVote":0,"replyCount":2,"createdAt":"2026-10-29T08:00:00Z","work":"葬送のフリーレン","title":"勇者","artist":"YOASOBI","note":"片尾曲匹配到了同名的另一首歌。"},
        {"id":"TR5","kind":"translation","status":"discussion","author":null,"authorID":"me","isOwn":true,"support":1,"oppose":0,"myVote":0,"replyCount":0,"createdAt":"2026-10-28T08:00:00Z","work":"サクラノ詩","language":"zh-Hans","source":"Summary","suggestion":"简介译文"},
        {"id":"DM1","kind":"translationError","status":"pending","author":null,"authorID":"me","isOwn":true,"support":0,"oppose":0,"myVote":0,"replyCount":0,"createdAt":"2026-10-27T08:00:00Z","work":"白昼夢の青写真","note":"第二段人名译错了。"}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([数据维护提交].self, from: Data(json.utf8))) ?? []
    }
}
#endif

/// 提交时填写的内容，字段名和服务器相同。
struct 数据维护草稿: Encodable {
    /// 选中的 Apple Music 歌曲。
    struct 歌曲信息: Codable, Sendable {
        var title: String?
        var artist: String?
        var album: String?
        var artwork: String?
    }
    /// Apple Music 里没有时填写的内容，审核后显示在作品详情。
    struct 显示信息: Codable, Sendable {
        var title: String
        var artist: String
        var album: String?
        var episodes: String?
    }

    var kind: String
    var note: String?
    var work: String?
    // 音乐
    var malID: Int?
    var songKind: String?
    var songKey: String?
    var title: String?
    var artist: String?
    var track: String?
    var currentTrackID: Int?
    var notInAppleMusic: Bool?
    var trackInfo: 歌曲信息?
    var display: 显示信息?
    // 简介翻译
    var entryType: String?
    var entryID: String?
    var language: String?
    var suggestion: String?
    var client: [String: String] = 数据维护服务.设备信息
}

struct 数据维护音乐结果: Decodable, Identifiable, Sendable {
    let trackId: Int
    let title: String
    let artist: String
    let album: String?
    let artwork: String?

    var id: Int { trackId }
}

struct 数据维护服务错误: LocalizedError {
    let errorDescription: String?
}

struct 数据维护服务 {
    private static let baseURL = URL(string: "https://papervn.jizpaper.com/data-maintenance/items")!

    /// 只有机型、系统、版本和语言，方便排查问题；注册 Paper 账户时内容按设备码迁移。
    static var 设备信息: [String: String] {
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return [
            "model": model,
            "system": UIDevice.current.systemVersion,
            "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "language": Locale.preferredLanguages.first ?? "",
        ]
    }

    private struct 列表响应: Decodable { let items: [数据维护提交] }
    private struct 单条响应: Decodable { let item: 数据维护提交 }
    private struct 错误响应: Decodable {
        struct 内容: Decodable { let message: String }
        let error: 内容
    }

    func 列表(scope: String) async throws -> [数据维护提交] {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "scope", value: scope)]
        let data = try await 发送(components.url!, method: "GET", body: Optional<数据维护草稿>.none)
        return try Self.decoder.decode(列表响应.self, from: data).items
    }

    func 搜索音乐(_ term: String) async throws -> [数据维护音乐结果] {
        struct 响应: Decodable { let results: [数据维护音乐结果] }
        var components = URLComponents(url: Self.baseURL.deletingLastPathComponent().appending(path: "music-search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "term", value: term)]
        let data = try await 发送(components.url!, method: "GET", body: Optional<数据维护草稿>.none)
        return try Self.decoder.decode(响应.self, from: data).results
    }

    func 详情(_ id: String) async throws -> 数据维护提交 {
        try await 单条(Self.baseURL.appending(path: id), method: "GET", body: Optional<数据维护草稿>.none)
    }

    func 提交(_ draft: 数据维护草稿) async throws {
        _ = try await 发送(Self.baseURL, method: "POST", body: draft)
    }

    func 投票(_ id: String, value: Int) async throws -> 数据维护提交 {
        try await 单条(Self.baseURL.appending(path: "\(id)/vote"), method: "POST", body: ["value": value])
    }

    func 回复(_ id: String, text: String) async throws -> 数据维护提交 {
        try await 单条(Self.baseURL.appending(path: "\(id)/replies"), method: "POST", body: ["text": text])
    }

    func 撤回(_ id: String) async throws -> 数据维护提交 {
        try await 单条(Self.baseURL.appending(path: "\(id)/withdraw"), method: "POST", body: [String: String]())
    }

    func 举报(_ id: String, replyID: String?) async throws {
        var body: [String: String] = [:]
        if let replyID { body["replyID"] = replyID }
        _ = try await 发送(Self.baseURL.appending(path: "\(id)/report"), method: "POST", body: body)
    }

    private func 单条<Body: Encodable>(_ url: URL, method: String, body: Body?) async throws -> 数据维护提交 {
        try Self.decoder.decode(单条响应.self, from: try await 发送(url, method: method, body: body)).item
    }

    private func 发送<Body: Encodable>(_ url: URL, method: String, body: Body?) async throws -> Data {
        guard method == "GET" || 敏感内容网页设置.设备身份可用 else {
            throw 数据维护服务错误(errorDescription: String(localized: "此设备的钥匙串不可用，无法提交。"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try await PaperAccount账户.shared.可选访问令牌() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        敏感内容网页设置.添加设备身份(to: &request)
        if let body {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(错误响应.self, from: data))?.error.message
            throw 数据维护服务错误(errorDescription: message ?? String(localized: "服务器当前不可用，请稍后再试。"))
        }
        return data
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) ?? .distantPast
        }
        return decoder
    }()
}

/// 用户在本机屏蔽的发布者，他们的提交和回复不再显示。
enum 数据维护屏蔽 {
    static let 键 = "dataMaintenance.blockedAuthors"

    static var 全部: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: 键) ?? [])
    }

    static func 添加(_ authorID: String) {
        UserDefaults.standard.set(Array(全部.union([authorID])), forKey: 键)
    }

    static func 清除() {
        UserDefaults.standard.removeObject(forKey: 键)
    }
}

// MARK: - 列表

/// 和反馈列表行同一排版：第一行标题和日期，第二行类型和状态。
struct 数据维护列表行: View {
    let item: 数据维护提交

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: item.标题)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 0)

                Text(item.createdAt, format: .dateTime.year().month().day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }

            HStack(spacing: 12) {
                Text(item.kind.名称)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(verbatim: item.状态名称)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 详情

struct 数据维护详情页面: View {
    let 初始内容: 数据维护提交
    let 更改后: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var item: 数据维护提交?
    @State private var 回复内容 = ""
    @State private var 正在发送 = false
    @State private var 提示: 反馈提示?
    @State private var 确认撤回 = false
    @State private var 屏蔽 = 数据维护屏蔽.全部
    @State private var 编辑中的翻译: VNDB简介翻译投稿记录?
    @EnvironmentObject private var auth: 用户登录

    private let service = 数据维护服务()
    private var 当前: 数据维护提交 { item ?? 初始内容 }
    /// 贡献的翻译在审核前和被拒绝后都能修改，和提交时一样在翻译页面中编辑。
    private var 可编辑翻译: Bool {
        当前.isOwn && 当前.kind == .贡献翻译 && ["pending", "discussion", "rejected"].contains(当前.status)
    }
    private var 已公开: Bool { 当前.status != "pending" && 当前.status != "withdrawn" }

    var body: some View {
        List {
            Section {
                LabeledContent("类型", value: 当前.kind.名称)
                LabeledContent("状态", value: 当前.状态名称)
                LabeledContent("提交者", value: 当前.署名)
                if let work = 当前.work, work != 当前.标题 { LabeledContent("作品", value: work) }
                if let artist = 当前.artist { LabeledContent("歌手", value: artist) }
                if 当前.notInAppleMusic == true { Text("Apple Music中没有这首歌") }
                if let info = 当前.trackInfo, let title = info.title {
                    LabeledContent("选择的歌曲", value: [title, info.artist].compactMap { $0 }.joined(separator: " / "))
                }
                if let display = 当前.display {
                    LabeledContent("歌名", value: display.title)
                    LabeledContent("歌手", value: display.artist)
                    if let album = display.album { LabeledContent("专辑", value: album) }
                    if let episodes = display.episodes { LabeledContent("话数", value: episodes) }
                }
                if let track = 当前.track, let url = Int(track).flatMap({ URL(string: "https://music.apple.com/jp/song/\($0)") }) ?? URL(string: track), url.scheme == "https" {
                    Link("在Apple Music中打开", destination: url)
                }
            } header: {
                Text(verbatim: 当前.标题)
                    .textCase(nil)
            }

            if let note = 当前.note { Section("说明") { Text(verbatim: note).textSelection(.enabled) } }
            if let source = 当前.source { Section("原文") { Text(verbatim: source).textSelection(.enabled) } }
            if let suggestion = 当前.suggestion { Section("译文") { Text(verbatim: suggestion).textSelection(.enabled) } }
            if let reviewNote = 当前.reviewNote { Section("审核备注") { Text(verbatim: reviewNote) } }

            if 已公开 {
                Section {
                    HStack(spacing: 12) {
                        投票按钮("支持", count: 当前.support, systemImage: "hand.thumbsup", selected: 当前.myVote == 1, value: 1)
                        投票按钮("反对", count: 当前.oppose, systemImage: "hand.thumbsdown", selected: 当前.myVote == -1, value: -1)
                    }
                    // 按钮本身就是容器，不再套一层分组背景
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    let replies = (当前.replies ?? []).filter { !屏蔽.contains($0.authorID) }
                    if replies.isEmpty {
                        Text("无回复").foregroundStyle(.secondary)
                    }
                    ForEach(replies) { reply in
                        回复行(reply)
                    }
                    TextField("回复", text: $回复内容, axis: .vertical)
                        .lineLimit(1...5)
                    Button("发送回复", action: 发送回复)
                        .disabled(正在发送 || 回复内容.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("回复")
                } footer: {
                    Text("回复将在审核后显示。")
                }
            } else if 当前.status == "pending" {
                Section {
                } footer: {
                    Text("这项提交将在审核后公开。")
                }
            }
        }
        .平台分组列表样式()
        .仅顶部可下拉关闭()
        .navigationTitle(当前.kind.名称)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .平台主操作) {
                Menu {
                    if 当前.isOwn {
                        if 可编辑翻译 {
                            Button("编辑翻译", systemImage: "pencil", action: 打开翻译)
                        }
                        if 当前.status == "pending" || 当前.status == "discussion" {
                            Button("撤回", systemImage: "arrow.uturn.backward", role: .destructive) { 确认撤回 = true }
                        }
                    } else {
                        Button("举报", systemImage: "exclamationmark.bubble") { 举报(replyID: nil) }
                        Button("屏蔽此用户", systemImage: "person.crop.circle.badge.xmark", role: .destructive) {
                            屏蔽用户(当前.authorID)
                            dismiss()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多")
            }
        }
        .task {
            if let loaded = try? await service.详情(初始内容.id) { item = loaded }
        }
        .sheet(item: $编辑中的翻译) { record in
            简介翻译投稿页面(
                existing: record,
                displayName: 简介翻译条目名称.显示名称(for: record)
            ) {
                if let loaded = try? await service.详情(初始内容.id) { item = loaded }
                await 更改后()
            }
            .environmentObject(auth)
        }
        .alert("要撤回这项提交吗？", isPresented: $确认撤回) {
            Button("保持", role: .cancel) {}
            Button("撤回", role: .destructive, action: 撤回)
        }
        .alert(item: $提示) { value in
            Alert(title: Text(verbatim: value.title), message: Text(verbatim: value.message), dismissButton: .default(Text("好")))
        }
    }

    private func 投票按钮(_ title: LocalizedStringResource, count: Int, systemImage: String, selected: Bool, value: Int) -> some View {
        Button {
            运行 { item = try await service.投票(当前.id, value: selected ? 0 : value) }
        } label: {
            Label {
                Text(verbatim: "\(String(localized: title)) \(count)")
                    .monospacedDigit()
            } icon: {
                Image(systemName: selected ? "\(systemImage).fill" : systemImage)
            }
            .frame(maxWidth: .infinity)
            // 玻璃按钮的符号不跟随 tint，图标和文字直接设同一种颜色
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .controlSize(.large)
        // 选中后整个按钮用强调色填充
        .modifier(Senkou按钮样式(突出: selected))
    }

    private func 回复行(_ reply: 数据维护回复) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: reply.author ?? String(localized: "匿名"))
                    .font(.subheadline.weight(.semibold))
                if reply.state == "pending" {
                    Text("等待审核")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(reply.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(verbatim: reply.text)
                .textSelection(.enabled)
        }
        .contextMenu {
            if !reply.isOwn && !reply.official {
                Button("举报", systemImage: "exclamationmark.bubble") { 举报(replyID: reply.id) }
                Button("屏蔽此用户", systemImage: "person.crop.circle.badge.xmark", role: .destructive) { 屏蔽用户(reply.authorID) }
            }
        }
    }

    private func 打开翻译() {
        运行 {
            let token = try? await PaperAccount账户.shared.可选访问令牌()
            let records = try await VNDB简介翻译投稿服务().mySubmissions(token: token)
            guard let record = records.first(where: { $0.id == 当前.id }) else {
                throw 数据维护服务错误(errorDescription: String(localized: "提交不存在。"))
            }
            编辑中的翻译 = record
        }
    }

    private func 发送回复() {
        let text = 回复内容.trimmingCharacters(in: .whitespacesAndNewlines)
        正在发送 = true
        运行 {
            defer { 正在发送 = false }
            item = try await service.回复(当前.id, text: text)
            回复内容 = ""
            await 更改后()
        }
    }

    private func 撤回() {
        运行 {
            item = try await service.撤回(当前.id)
            await 更改后()
            dismiss()
        }
    }

    private func 举报(replyID: String?) {
        运行 {
            try await service.举报(当前.id, replyID: replyID)
            提示 = 反馈提示(title: String(localized: "已举报"), message: String(localized: "我们将尽快查看。"))
        }
    }

    private func 屏蔽用户(_ authorID: String) {
        数据维护屏蔽.添加(authorID)
        屏蔽 = 数据维护屏蔽.全部
        Task { await 更改后() }
    }

    private func 运行(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                正在发送 = false
                提示 = 反馈提示(title: String(localized: "无法完成操作"), message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 提交

/// 从作品详情打开：报告音乐匹配错误、添加音乐、报告简介翻译错误。
struct 数据维护提交页面: View {
    enum 提交内容 {
        case 音乐匹配错误(malID: Int, 作品: String, 歌曲键: Int, 种类: 动画主题曲.种类, 歌名: String, 歌手: String, 当前曲目: Int?)
        case 添加音乐(malID: Int, 作品: String)
        case 简介翻译错误(条目: VNDB简介翻译条目, 语言: 简介翻译语言)
    }

    let 内容: 提交内容

    @ObservedObject private var paperAccount = PaperAccount账户.shared
    @Environment(\.dismiss) private var dismiss
    @State private var 歌名 = ""
    @State private var 歌手 = ""
    @State private var 种类 = 动画主题曲.种类.片头曲
    @State private var 选中歌曲: 数据维护音乐结果?
    @State private var 专辑 = ""
    @State private var 话数 = ""
    @State private var 没有这首歌 = false
    @State private var 说明 = ""
    @State private var 建议译文 = ""
    @State private var 正在提交 = false
    @State private var 提示: 反馈提示?
    @State private var 已提交 = false

    private var 标题: LocalizedStringKey {
        switch 内容 {
        case .音乐匹配错误: "报告音乐匹配错误"
        case .添加音乐: "添加音乐"
        case .简介翻译错误: "报告简介翻译错误"
        }
    }

    private var 可以提交: Bool {
        func filled(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        switch 内容 {
        case .音乐匹配错误, .添加音乐: return 选中歌曲 != nil || (没有这首歌 && filled(歌名) && filled(歌手))
        case .简介翻译错误: return filled(说明)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                switch 内容 {
                case let .音乐匹配错误(_, 作品, _, _, 歌名, 歌手, _):
                    Section {
                        LabeledContent("作品", value: 作品)
                        LabeledContent("当前歌名", value: 歌名)
                        LabeledContent("当前歌手", value: 歌手)
                    }
                    音乐选择区(检索词: 歌名)
                    Section("说明（可选）") { TextEditor(text: $说明).frame(minHeight: 80) }
                case let .添加音乐(_, 作品):
                    Section {
                        LabeledContent("作品", value: 作品)
                        Picker("类型", selection: $种类) {
                            Text("片头曲").tag(动画主题曲.种类.片头曲)
                            Text("片尾曲").tag(动画主题曲.种类.片尾曲)
                            Text("插入曲").tag(动画主题曲.种类.插入曲)
                        }
                    }
                    音乐选择区(检索词: 作品)
                    Section("说明（可选）") { TextEditor(text: $说明).frame(minHeight: 80) }
                case let .简介翻译错误(条目, 语言):
                    Section {
                        LabeledContent("条目", value: 条目.displayName)
                        LabeledContent("语言", value: 语言.title)
                    }
                    Section("问题") { TextEditor(text: $说明).frame(minHeight: 120) }
                    Section("建议的译文（可选）") { TextEditor(text: $建议译文).frame(minHeight: 120) }
                }

                Section {
                    LabeledContent(
                        "提交者",
                        value: paperAccount.isLoggedIn
                            ? paperAccount.资料?.nickname ?? String(localized: "未设置昵称")
                            : String(localized: "匿名")
                    )
                } footer: {
                    Text("这项提交将在审核后公开，所有用户都能查看、投票和回复。")
                }
            }
            .navigationTitle(标题)
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .平台前导关闭操作) {
                    Button {
                        dismiss()
                    } label: {
                        Label("取消", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if 正在提交 {
                        ProgressView()
                    } else {
                        Button(action: 提交) {
                            Label("提交", systemImage: "arrow.up")
                        }
                        .液态玻璃醒目按钮(in: Circle())
                        .buttonBorderShape(.circle)
                        .tint(.blue)
                        .disabled(!可以提交)
                    }
                }
            }
            .alert(item: $提示) { value in
                Alert(title: Text(verbatim: value.title), message: Text(verbatim: value.message), dismissButton: .default(Text("好")))
            }
            .alert("已提交", isPresented: $已提交) {
                Button("好") { dismiss() }
            } message: {
                Text("这项提交将在审核后公开。请勿重复提交相同内容。")
            }
        }
    }

    /// 在 Apple Music 中选择；没有这首歌时填写详细信息，审核后显示在作品详情。
    @ViewBuilder
    private func 音乐选择区(检索词: String) -> some View {
        Section {
            NavigationLink {
                数据维护选歌页面(初始检索词: 检索词, 选中: $选中歌曲, 不在AppleMusic中: $没有这首歌)
            } label: {
                if let 选中歌曲 {
                    数据维护音乐行(歌曲: 选中歌曲)
                } else if 没有这首歌 {
                    Text("不在Apple Music中")
                } else {
                    Text("在Apple Music中选择")
                }
            }
        }
        if 没有这首歌 {
            Section {
                TextField("歌名", text: $歌名)
                TextField("歌手", text: $歌手)
                TextField("专辑（可选）", text: $专辑)
                TextField("话数（可选），例如1-12", text: $话数)
            } header: {
                Text("歌曲信息")
            } footer: {
                Text("请使用歌曲的原语言写法。审核通过后，这些信息会显示在作品详情中。")
            }
        }
    }

    private func 提交() {
        func optional(_ text: String) -> String? {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        func 填写音乐(_ draft: inout 数据维护草稿) {
            draft.notInAppleMusic = 没有这首歌
            if 没有这首歌 {
                draft.display = .init(title: optional(歌名) ?? "", artist: optional(歌手) ?? "", album: optional(专辑), episodes: optional(话数))
            } else if let 选中歌曲 {
                draft.track = String(选中歌曲.trackId)
                draft.trackInfo = .init(title: 选中歌曲.title, artist: 选中歌曲.artist, album: 选中歌曲.album, artwork: 选中歌曲.artwork)
            }
        }
        var draft: 数据维护草稿
        switch 内容 {
        case let .音乐匹配错误(malID, 作品, 歌曲键, 种类, 当前歌名, 当前歌手, 当前曲目):
            draft = 数据维护草稿(kind: 数据维护种类.音乐匹配错误.rawValue, note: optional(说明), work: 作品)
            draft.malID = malID
            draft.songKind = 种类.rawValue
            draft.songKey = String(歌曲键)
            draft.title = 当前歌名
            draft.artist = optional(当前歌手)
            draft.currentTrackID = 当前曲目
            填写音乐(&draft)
        case let .添加音乐(malID, 作品):
            draft = 数据维护草稿(kind: 数据维护种类.添加音乐.rawValue, note: optional(说明), work: 作品)
            draft.malID = malID
            draft.songKind = 种类.rawValue
            填写音乐(&draft)
        case let .简介翻译错误(条目, 语言):
            draft = 数据维护草稿(kind: 数据维护种类.简介翻译错误.rawValue, note: optional(说明), work: 条目.displayName)
            draft.entryType = 条目.type.rawValue
            draft.entryID = 条目.id
            draft.language = 语言.rawValue
            draft.suggestion = optional(建议译文)
        }
        正在提交 = true
        Task {
            defer { 正在提交 = false }
            do {
                try await 数据维护服务().提交(draft)
                已提交 = true
            } catch {
                提示 = 反馈提示(title: String(localized: "无法提交"), message: error.localizedDescription)
            }
        }
    }
}

// MARK: - 选歌

private struct 数据维护音乐行: View {
    let 歌曲: 数据维护音乐结果

    var body: some View {
        HStack(spacing: 12) {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            ZStack {
                shape.fill(Color.secondary.opacity(0.12))
                if let artwork = 歌曲.artwork.flatMap(URL.init(string:)) {
                    CachedAsyncImage(url: artwork, contentMode: .fill)
                } else {
                    Image(systemName: "music.note").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(shape)
            VStack(alignment: .leading, spacing: 2) {
                多语言列表文本(文本: 歌曲.title, isJapanese: true, 层级: .主标题, 语言来源已知: false)
                    .lineLimit(1)
                多语言列表文本(
                    文本: [歌曲.artist, 歌曲.album].compactMap { $0 }.joined(separator: " · "),
                    isJapanese: true, 层级: .下属标题, 日文字体名称: "HiraginoSans-W4",
                    系统字体粗细: .regular, 语言来源已知: false, 空格视为日语: true
                )
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }
}

private struct 数据维护选歌页面: View {
    let 初始检索词: String
    @Binding var 选中: 数据维护音乐结果?
    @Binding var 不在AppleMusic中: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var 检索词 = ""
    @State private var 结果: [数据维护音乐结果] = []
    @State private var 正在检索 = false
    @State private var 错误: String?

    var body: some View {
        List {
            // 始终在最上面：检索不到时也能选
            Section {
                Button {
                    选中 = nil
                    不在AppleMusic中 = true
                    dismiss()
                } label: {
                    HStack {
                        Text("不在Apple Music中")
                            .foregroundStyle(.primary)
                        Spacer()
                        if 不在AppleMusic中 {
                            Image(systemName: "checkmark")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if 正在检索 && 结果.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            } else if let 错误 {
                平台内容不可用视图("无法加载", systemImage: "exclamationmark.triangle", description: Text(verbatim: 错误))
            } else if 结果.isEmpty {
                平台内容不可用视图("无结果", systemImage: "music.note")
            }
            ForEach(结果) { song in
                Button {
                    选中 = song
                    不在AppleMusic中 = false
                    dismiss()
                } label: {
                    数据维护音乐行(歌曲: song)
                }
                .buttonStyle(.plain)
            }
        }
        .平台分组列表样式()
        .navigationTitle("在Apple Music中选择")
        .平台内联导航标题()
        .searchable(text: $检索词, prompt: "歌名或歌手")
        .onAppear { if 检索词.isEmpty { 检索词 = 初始检索词 } }
        .task(id: 检索词) {
            let term = 检索词.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { 结果 = []; return }
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            正在检索 = true
            defer { 正在检索 = false }
            do {
                let found = try await 数据维护服务().搜索音乐(term)
                guard !Task.isCancelled else { return }
                结果 = found
                错误 = nil
            } catch {
                guard !Task.isCancelled else { return }
                错误 = error.localizedDescription
            }
        }
    }
}
