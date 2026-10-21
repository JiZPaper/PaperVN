import SwiftUI

private struct 作品编辑草稿: Equatable {
    var 状态: 资料库状态
    /// 0–10，0 表示没有评分。
    var 评分: Int
    var 进度: Int
    var 开始日期: Date?
    var 完成日期: Date?
}

/// 动画、漫画与轻小说的资料库编辑页面。排版和交互与视觉小说的 `资料库编辑页面` 一致：
/// 编辑完成后统一存储，关闭时有未存储的更改会先询问；状态改为观看中、已观看时按设置自动填写日期。
struct 作品资料库编辑页面: View {
    let entry: 本地资料库条目
    let title: 标题工具.标题结果

    @Environment(\.dismiss) private var dismiss
    @AppStorage("autoFillStartDate") private var autoFillStartDate = true
    @AppStorage("autoFillFinishDate") private var autoFillFinishDate = true

    @State private var draft: 作品编辑草稿
    @State private var originalDraft: 作品编辑草稿
    @State private var showDiscardAlert = false
    @State private var showDateCorrectionAlert = false
    @State private var hasHandledDateCorrection = false
    @State private var hasManuallyModifiedDate = false
    @State private var automaticallyFilledStarted = false
    @State private var automaticallyFilledFinished = false
    @State private var isSaving = false
    @State private var saveError: String?
    /// 手动输入进度，适合几百话的作品。
    @State private var showsProgressInput = false
    @State private var progressInput = ""

    init(entry: 本地资料库条目, title: 标题工具.标题结果) {
        self.entry = entry
        self.title = title
        let initial = 作品编辑草稿(
            状态: entry.状态 ?? .planning,
            评分: Int((Double(entry.评分 ?? 0) / 10).rounded()),
            进度: entry.进度 ?? 0,
            开始日期: Self.date(from: entry.开始日期),
            完成日期: Self.date(from: entry.完成日期)
        )
        _draft = State(initialValue: initial)
        _originalDraft = State(initialValue: initial)
    }

    private var hasChanges: Bool { draft != originalDraft }
    private var 是动画: Bool { entry.类型 == .anime }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                progressSection
                ratingSection
                datesSection
            }
            .onChange(of: draft.状态) { _, status in
                applyAutomaticDates(for: status)
            }
            .navigationTitle("")
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(editorNavigationTitle)
                        .lineLimit(1)
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        requestDismiss()
                    } label: {
                        Label("关闭", systemImage: "xmark")
                    }
                    .disabled(isSaving)
                    .confirmationDialog(
                        "要放弃更改吗？",
                        isPresented: $showDiscardAlert,
                        titleVisibility: .visible
                    ) {
                        Button("存储更改") {
                            Task { await save() }
                        }
                        Button("放弃更改", role: .destructive) {
                            dismiss()
                        }
                    } message: {
                        Text("尚未存储的状态、进度、评分或日期将会丢失。")
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.gray)
                                .frame(width: 22, height: 22)
                        } else {
                            Label("存储更改", systemImage: "checkmark")
                        }
                    }
                    .液态玻璃醒目按钮(in: Circle())
                    .tint(.blue)
                    .accessibilityLabel("存储更改")
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard hasChanges,
                          !isSaving,
                          value.translation.height > 90,
                          abs(value.translation.height) > abs(value.translation.width) else {
                        return
                    }
                    showDiscardAlert = true
                }
        )
        .alert(
            "无法存储",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("好") { saveError = nil }
        } message: {
            Text(verbatim: saveError ?? "")
        }
        .alert(进度标题, isPresented: $showsProgressInput) {
            TextField(进度标题, text: $progressInput)
                .keyboardType(.numberPad)
            Button("取消", role: .cancel) {}
            Button("好") {
                guard let value = Int(progressInput.trimmingCharacters(in: .whitespaces)) else { return }
                withAnimation(.snappy) {
                    draft.进度 = min(max(value, 0), entry.总数 ?? 99_999)
                }
            }
        } message: {
            if let total = entry.总数 {
                Text("输入0到\(total)之间的数字。")
            }
        }
        .alert("这是补标吗？", isPresented: $showDateCorrectionAlert) {
            Button("修改日期") {
                hasHandledDateCorrection = true
            }
            Button("留空日期") {
                hasHandledDateCorrection = true
                if automaticallyFilledStarted { draft.开始日期 = nil }
                if automaticallyFilledFinished { draft.完成日期 = nil }
                automaticallyFilledStarted = false
                automaticallyFilledFinished = false
                Task { await saveChanges() }
            }
            Button("无需操作", role: .cancel) {
                hasHandledDateCorrection = true
            }
        } message: {
            Text(verbatim: dateCorrectionAlertMessage)
        }
    }

    private var editorNavigationTitle: AttributedString {
        标题工具.生成格式化标题富文本(
            格式: String(localized: "编辑“%@”"),
            标题: title,
            基础大小: 17,
            是粗体: true
        )
    }

    private var dateCorrectionAlertMessage: String {
        String(
            format: 是动画
                ? String(localized: "你似乎已经看过“%@”。自动填充的观看日期可能不准确。")
                : String(localized: "你似乎已经读过“%@”。自动填充的阅读日期可能不准确。"),
            title.text
        )
    }

    // MARK: 分组

    private var statusSection: some View {
        Section {
            Picker("状态", selection: $draft.状态) {
                ForEach(资料库状态.allCases) { status in
                    Label(status.localizedTitle(for: entry.类型), systemImage: status.用户列表筛选.symbolName)
                        .tag(status)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("状态")
        }
    }

    private var 进度标题: LocalizedStringKey { 是动画 ? "已观看话数" : "已阅读话数" }

    private var progressSection: some View {
        Section {
            // 绑定带动画，加减时数字使用系统的数字滚动效果
            Stepper(value: $draft.进度.animation(.snappy), in: 0...(entry.总数 ?? 99_999)) {
                HStack {
                    // Stepper 的标签不会套用强调色，图标要单独设为强调色，和上下的图标一致
                    Label {
                        Text(进度标题)
                    } icon: {
                        Image(systemName: 是动画 ? "play.rectangle" : "book")
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                    // 点按数字可以直接输入
                    Button {
                        progressInput = String(draft.进度)
                        showsProgressInput = true
                    } label: {
                        Text(verbatim: entry.总数.map { "\(draft.进度)/\($0)" } ?? "\(draft.进度)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(draft.进度 == 0 ? Color.secondary : Color.blue)
                            .contentTransition(.numericText(value: Double(draft.进度)))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint(Text("输入数字"))
                }
            }
            .sensoryFeedback(.selection, trigger: draft.进度)
        } header: {
            Text("进度")
        }
    }

    private var ratingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("评分", systemImage: "star")
                    Spacer()
                    Text(verbatim: draft.评分 == 0 ? String(localized: "无") : "\(draft.评分)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(draft.评分 == 0 ? Color.secondary : Color.blue)
                        .contentTransition(.numericText(value: Double(draft.评分)))
                }

                HStack(spacing: 4) {
                    ForEach(0...10, id: \.self) { value in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(value == draft.评分 ? Color.blue : Color.secondary.opacity(0.12))
                            .overlay {
                                Text(verbatim: value == 0 ? "–" : "\(value)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(value == draft.评分 ? Color.white : Color.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                }
                .contentShape(Rectangle())
                .overlay {
                    GeometryReader { proxy in
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateRating(at: value.location.x, width: proxy.size.width)
                                    }
                            )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("我的评分")
                .accessibilityValue(draft.评分 == 0 ? String(localized: "无") : "\(draft.评分)")
                .sensoryFeedback(.selection, trigger: draft.评分)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: withAnimation(.snappy) { draft.评分 = min(draft.评分 + 1, 10) }
                    case .decrement: withAnimation(.snappy) { draft.评分 = max(draft.评分 - 1, 0) }
                    @unknown default: break
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("评分")
        }
    }

    private var datesSection: some View {
        Section {
            optionalDateRow(
                title: "开始日期",
                systemImage: "calendar.badge.clock",
                date: Binding(
                    get: { draft.开始日期 },
                    set: {
                        draft.开始日期 = $0
                        automaticallyFilledStarted = false
                        hasManuallyModifiedDate = true
                    }
                )
            )
            optionalDateRow(
                title: "结束日期",
                systemImage: "calendar.badge.checkmark",
                date: Binding(
                    get: { draft.完成日期 },
                    set: {
                        draft.完成日期 = $0
                        automaticallyFilledFinished = false
                        hasManuallyModifiedDate = true
                    }
                )
            )
        } header: {
            Text(是动画 ? "观看日期" : "阅读日期")
        }
    }

    private func optionalDateRow(title: LocalizedStringKey, systemImage: String, date: Binding<Date?>) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)

            if let currentDate = date.wrappedValue {
                DatePicker(
                    title,
                    selection: Binding(get: { currentDate }, set: { date.wrappedValue = $0 }),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()

                Button {
                    date.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("清除日期")
            } else {
                Button("添加日期") {
                    date.wrappedValue = Calendar.current.startOfDay(for: Date())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.blue)
            }
        }
        .frame(height: 34)
    }

    // MARK: 行为

    private func updateRating(at location: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let normalized = min(max(location / width, 0), 0.999_999)
        let value = min(Int(normalized * 11), 10)
        guard value != draft.评分 else { return }
        withAnimation(.snappy) { draft.评分 = value }
    }

    private func applyAutomaticDates(for status: 资料库状态) {
        let today = Calendar.current.startOfDay(for: Date())
        if autoFillStartDate, status == .inProgress || status == .completed, draft.开始日期 == nil {
            draft.开始日期 = today
            automaticallyFilledStarted = true
        }
        if autoFillFinishDate, status == .completed, draft.完成日期 == nil {
            draft.完成日期 = today
            automaticallyFilledFinished = true
        }
        // 看完时进度补满
        if status == .completed, let total = entry.总数, draft.进度 < total {
            draft.进度 = total
        }
    }

    /// 刚加入资料库不久就从计划改成已看完或抛弃，多半是补标，自动填的日期可能不对。
    private var shouldAskDateCorrection: Bool {
        guard !hasHandledDateCorrection,
              !hasManuallyModifiedDate,
              automaticallyFilledStarted || automaticallyFilledFinished,
              originalDraft.状态 == .planning,
              draft.状态 == .completed || draft.状态 == .dropped else {
            return false
        }
        guard let added = entry.加入时间 else { return true }
        return Date().timeIntervalSince(added) <= 60 * 60
    }

    private func requestDismiss() {
        if hasChanges {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard hasChanges else {
            dismiss()
            return
        }
        if shouldAskDateCorrection {
            showDateCorrectionAlert = true
            return
        }
        await saveChanges()
    }

    @MainActor
    private func saveChanges() async {
        guard !isSaving else { return }
        isSaving = true
        saveError = nil
        var updated = 本地资料库.shared.条目.first { $0.id == entry.id } ?? entry
        updated.状态 = draft.状态
        updated.评分 = draft.评分 == 0 ? nil : draft.评分 * 10
        updated.进度 = draft.进度
        updated.开始日期 = Self.string(from: draft.开始日期)
        updated.完成日期 = Self.string(from: draft.完成日期)
        let datesChanged = draft.开始日期 != originalDraft.开始日期 || draft.完成日期 != originalDraft.完成日期
        do {
            try await PaperVNSync中心.shared.存储(updated, 推送日期: datesChanged)
            originalDraft = draft
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            // 本地已经存储，推送失败的平台会在下次同步时重试
            saveError = error.localizedDescription
            originalDraft = draft
        }
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return dateFormatter.date(from: String(value.prefix(10)))
    }

    static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        return dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}


/// 已登录的平台都无法同步这类作品时编辑资料库的提示。
struct 无法编辑资料库提示: ViewModifier {
    /// 不为 nil 时显示提示。
    @Binding var 限制: PaperVNSync中心.资料库编辑限制?

    func body(content: Content) -> some View {
        content.alert(
            "无法编辑资料库",
            isPresented: Binding(get: { 限制 != nil }, set: { if !$0 { 限制 = nil } })
        ) {
            Button("好") {}
        } message: {
            Text(verbatim: 说明)
        }
    }

    /// 新增平台时要检查这里的说明：Bangumi 是单独写的原因，其他平台按 `同步能力.支持的类型` 生成“不支持某类记录”。
    /// 新平台如果是因为别的原因不能同步（例如只能导入），要像 Bangumi 一样单独写一句。
    private var 说明: String {
        guard let 限制 else { return "" }
        let reasons = 限制.无法同步.map { platform -> String in
            if platform == .bangumi {
                return String(localized: "Bangumi番组计划不提供PaperVN所需“从资料库删除”功能对应的API。无法向Bangumi番组计划同步资料库。")
            }
            // 平台不支持记录哪些类型就写哪些，例如 Annict 是“漫画与轻小说”，VNDB 是“动画、漫画与轻小说”
            let types = 作品类型.allCases
                .filter { $0 != .visualNovel && !platform.同步能力.支持的类型.contains($0) }
                .map(\.localizedTitle)
            return String(localized: "\(platform.localizedTitle)不支持\(types.并列)记录。无法向\(platform.localizedTitle)同步资料库。")
        }
        let names = 限制.可登录.map(\.localizedTitle).顿号并列
        return (reasons + [String(localized: "请至少登录\(names)之一以编辑资料库。")]).joined()
    }
}

extension [String] {
    /// “动画、漫画与轻小说”的写法。系统列表格式在中文用“和”、在日语不加“と”，所以中文与日语用目录里的“%@与%@”，
    /// 其他语言交给系统（例如英语“A, B, and C”）。
    var 并列: String {
        guard Self.用中日写法 else { return formatted(.list(type: .and).locale(Self.界面语言)) }
        guard let last else { return "" }
        guard count > 1 else { return last }
        return String(localized: "\(dropLast().joined(separator: "、"))与\(last)")
    }

    /// “MyAnimeList、AniList”的写法，只用顿号不加“与”。系统列表格式在中文会加“和”，所以中文与日语直接用“、”，
    /// 其他语言交给系统（例如英语“A, B, and C”）。
    var 顿号并列: String {
        Self.用中日写法 ? joined(separator: "、") : formatted(.list(type: .and).locale(Self.界面语言))
    }

    /// App 实际显示的语言，而不是系统首选语言（两者可能不同，例如系统语言 App 不支持时）。
    private static var 界面语言: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "zh-Hans")
    }

    private static var 用中日写法: Bool {
        ["zh", "ja"].contains(界面语言.language.languageCode?.identifier)
    }
}

extension View {
    func 无法编辑资料库提示(_ 限制: Binding<PaperVNSync中心.资料库编辑限制?>) -> some View {
        modifier(PaperVN.无法编辑资料库提示(限制: 限制))
    }
}

#if DEBUG
// MARK: - 预览

#Preview("编辑资料库") {
    预览状态切换([
        .init("动画", 准备: { 本地资料库.shared.预览载入(预览数据.资料库条目) }) {
            作品资料库编辑页面(entry: 预览数据.我推的孩子.条目(.inProgress, 评分: 80, 进度: 7, 开始日期: "2023-04-12"), title: 预览数据.我推的孩子.标题结果)
        },
        .init("漫画", 准备: { 本地资料库.shared.预览载入(预览数据.资料库条目) }) {
            作品资料库编辑页面(entry: 预览数据.芙莉莲漫画.条目(.inProgress, 评分: 90, 进度: 128), title: 预览数据.芙莉莲漫画.标题结果)
        },
        .init("轻小说", 准备: { 本地资料库.shared.预览载入(预览数据.资料库条目) }) {
            作品资料库编辑页面(
                entry: 预览数据.狼与香辛料.条目(.completed, 评分: 90, 进度: 24, 开始日期: "2024-01-03", 完成日期: "2024-05-20"),
                title: 预览数据.狼与香辛料.标题结果
            )
        },
        // 一小时内加入的“计划观看”：改为“已观看”后存储会询问是否为补标
        .init("刚加入（试试补标提示）", 准备: { 本地资料库.shared.预览载入(预览数据.资料库条目) }) {
            作品资料库编辑页面(entry: 预览数据.刚加入的条目, title: 预览数据.芙莉莲第二季.标题结果)
        },
    ])
}

/// 打开时就显示“无法编辑资料库”提示；关闭后可以轻点按钮再显示。
private struct 无法编辑资料库提示预览: View {
    let 限制: PaperVNSync中心.资料库编辑限制
    @State private var 当前: PaperVNSync中心.资料库编辑限制?

    init(_ 限制: PaperVNSync中心.资料库编辑限制) {
        self.限制 = 限制
        _当前 = State(initialValue: 限制)
    }

    var body: some View {
        Button("显示提示") { 当前 = 限制 }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .无法编辑资料库提示($当前)
    }
}

#Preview("无法编辑资料库提示") {
    预览状态切换([
        .init("只登录了VNDB") {
            无法编辑资料库提示预览(.init(无法同步: [.vndb], 可登录: [.myAnimeList, .aniList]))
        },
        .init("只登录了Bangumi") {
            无法编辑资料库提示预览(.init(无法同步: [.bangumi], 可登录: [.myAnimeList, .aniList, .annict, .tmdb]))
        },
        .init("编辑漫画时只登录了Bangumi与Annict") {
            无法编辑资料库提示预览(.init(无法同步: [.bangumi, .annict], 可登录: [.myAnimeList, .aniList]))
        },
    ])
}
#endif
