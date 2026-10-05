import SwiftUI
import UIKit

enum 简介翻译条目名称 {
    static func 原语言标题(
        titles: [用户多语言标题]?,
        defaultTitle: String
    ) -> String {
        标题工具.获取主标题(
            titles: titles,
            defaultTitle: defaultTitle,
            偏好: .original,
            回退: .original,
            允许非官方: true
        ).text
    }

    static func 偏好标题(
        titles: [用户多语言标题]?,
        defaultTitle: String
    ) -> 标题工具.标题结果 {
        let defaults = UserDefaults.standard
        return 标题工具.获取主标题(
            titles: titles,
            defaultTitle: defaultTitle,
            偏好: 标题语言(
                rawValue: defaults.string(forKey: "preferredTitleLang") ?? ""
            ) ?? .original,
            回退: 标题语言(
                rawValue: defaults.string(forKey: "fallbackTitleLang") ?? ""
            ) ?? .original,
            允许非官方: defaults.bool(forKey: "allowUnofficialTitles")
        )
    }

    /// 人名按原名显示时使用日文字体，与角色详情的规则一致。
    static func 偏好人名(name: String, original: String?) -> 标题工具.标题结果 {
        let 偏好 = 制作人员语言(
            rawValue: UserDefaults.standard.string(forKey: "staffNameLang") ?? ""
        ) ?? .romaji
        return 标题工具.标题结果(
            text: 人物名称工具.显示名称(name: name, original: original, 偏好: 偏好),
            isJapanese: 偏好 == .original
        )
    }

    static func 显示名称(for record: VNDB简介翻译投稿记录) -> 标题工具.标题结果 {
        let romanized = record.romanizedName ?? record.originalLanguageName
        switch record.type {
        case .visualNovel:
            return 偏好标题(
                titles: record.titles?.map(用户多语言标题.init),
                defaultTitle: romanized
            )
        case .character:
            return 偏好人名(name: romanized, original: record.name)
        }
    }
}

extension 用户多语言标题 {
    init(_ title: VNDB简介翻译标题) {
        self.init(
            lang: title.lang,
            title: title.title,
            latin: title.latin,
            official: title.official,
            main: title.main
        )
    }
}

extension VNDB简介翻译标题 {
    init(_ title: 用户多语言标题) {
        self.init(
            lang: title.lang,
            title: title.title,
            latin: title.latin,
            official: title.official,
            main: title.main
        )
    }
}

struct 简介翻译参与按钮: View {
    enum 样式 {
        case icon(tint: Color)
        case labeled
    }

    @ObservedObject var auth: 用户登录
    let entry: VNDB简介翻译条目
    let targetLanguage: 简介翻译语言
    let knownHasTranslation: Bool?
    let resolvesIndependently: Bool
    var style: 样式 = .icon(tint: .secondary)

    @State private var resolvedHasTranslation: Bool?
    @State private var showsSubmission = false
    @State private var isPreparingSubmission = false
    @State private var submissionRecords: [VNDB简介翻译投稿记录]?
    @State private var showsFeedback = false
    @State private var didSubmitFeedback = false
    @State private var showsFeedbackConfirmation = false

    private var hasTranslation: Bool? {
        resolvesIndependently ? resolvedHasTranslation : knownHasTranslation
    }

    private var lookupKey: String {
        "\(entry.type.rawValue)|\(entry.id)|\(targetLanguage.rawValue)|\(resolvesIndependently)"
    }

    var body: some View {
        content
            .opacity(hasTranslation == nil ? 0 : 1)
            .disabled(hasTranslation == nil)
            .accessibilityHidden(hasTranslation == nil)
            .animation(.easeInOut(duration: 0.2), value: hasTranslation)
            .task(id: lookupKey) {
                guard resolvesIndependently else { return }
                resolvedHasTranslation = nil
                let result = await VNDB简介人工翻译.项目译文状态(
                    for: entry.id,
                    type: entry.type,
                    language: targetLanguage
                )
                guard !Task.isCancelled else { return }
                switch result {
                case .translation: resolvedHasTranslation = true
                case .missing: resolvedHasTranslation = false
                case .notLoaded: resolvedHasTranslation = nil
                }
            }
            .sheet(isPresented: $showsSubmission) {
                简介翻译投稿页面(
                    entry: entry,
                    fallbackLanguage: targetLanguage,
                    records: submissionRecords
                )
                .environmentObject(auth)
            }
            .sheet(isPresented: $showsFeedback, onDismiss: {
                guard didSubmitFeedback else { return }
                didSubmitFeedback = false
                showsFeedbackConfirmation = true
            }) {
                快速反馈页面(
                    title: String(
                        localized: "简介翻译问题：\(entry.displayName)"
                    ),
                    description: feedbackTemplate,
                    clientInfo: [
                        "translationEntry": entry.id,
                        "translationType": entry.type.rawValue,
                        "translationLanguage": targetLanguage.rawValue
                    ],
                    onSubmitted: { didSubmitFeedback = true }
                )
                .environmentObject(auth)
                .平台近全屏弹窗()
            }
            .alert("反馈已提交", isPresented: $showsFeedbackConfirmation) {
                Button("好") {}
            } message: {
                Text("我们将在查看后展示你的反馈。请勿重复提交相同反馈。")
            }
    }

    @ViewBuilder
    private var content: some View {
        let translated = hasTranslation == true
        switch style {
        case .icon(let tint):
            Button(action: open) {
                if isPreparingSubmission {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(
                        systemName: translated
                            ? "exclamationmark.bubble"
                            : "character.bubble"
                    )
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(tint)
            .accessibilityLabel(translated ? "反馈翻译问题" : "提交翻译")
        case .labeled:
            Button(action: open) {
                Label(
                    translated ? "反馈翻译问题" : "提交翻译",
                    systemImage: translated
                        ? "exclamationmark.bubble"
                        : "character.bubble"
                )
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .disabled(isPreparingSubmission)
        }
    }

    private var feedbackTemplate: String {
        [
            String(localized: "条目：\(entry.displayName)（\(entry.id)）"),
            String(localized: "语言：\(targetLanguage.title)"),
            "",
            String(localized: "问题："),
            ""
        ].joined(separator: "\n")
    }

    private func open() {
        if hasTranslation == true {
            showsFeedback = true
            return
        }
        guard !isPreparingSubmission else { return }
        guard auth.isLoggedIn, !auth.token.isEmpty else {
            submissionRecords = []
            showsSubmission = true
            return
        }
        isPreparingSubmission = true
        Task {
            let records = try? await VNDB简介翻译投稿服务()
                .mySubmissions(token: auth.token)
            submissionRecords = records?.filter {
                $0.entryID == entry.id
                    && $0.type == entry.type
                    && $0.status != .withdrawn
            }
            isPreparingSubmission = false
            showsSubmission = true
        }
    }
}

struct 简介翻译投稿页面: View {
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.dismiss) private var dismiss

    let entry: VNDB简介翻译条目
    private let existing: VNDB简介翻译投稿记录?
    private let onSubmitted: () async -> Void

    @State private var language: 简介翻译投稿语言
    @State private var translation: String
    @State private var note: String
    @State private var hasExistingTranslation = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var submittedResult: VNDB简介翻译投稿结果?
    @State private var entryRecords: [VNDB简介翻译投稿记录]?
    @State private var showsDiscardConfirmation = false
    @State private var isScrolledToTop = true

    init(
        entry: VNDB简介翻译条目,
        fallbackLanguage: 简介翻译语言,
        records: [VNDB简介翻译投稿记录]? = nil
    ) {
        self.entry = entry
        existing = nil
        onSubmitted = {}
        let defaultLanguage = 简介翻译投稿语言.默认语言(fallback: fallbackLanguage)
        let initialRecord = Self.initialRecord(
            in: records,
            preferredLanguage: defaultLanguage
        )
        _language = State(
            initialValue: initialRecord?.投稿语言 ?? defaultLanguage
        )
        _translation = State(initialValue: initialRecord?.translation ?? "")
        _note = State(initialValue: initialRecord?.note ?? "")
        _entryRecords = State(initialValue: records)
    }

    init(
        existing: VNDB简介翻译投稿记录,
        displayName: 标题工具.标题结果,
        onSubmitted: @escaping () async -> Void = {}
    ) {
        entry = existing.entry(
            displayName: displayName.text,
            displayIsJapanese: displayName.isJapanese,
            displayLanguageCode: displayName.languageCode
        )
        self.existing = existing
        self.onSubmitted = onSubmitted
        _language = State(
            initialValue: existing.投稿语言 ?? .simplifiedChinese
        )
        _translation = State(initialValue: existing.translation)
        _note = State(initialValue: existing.note ?? "")
    }

    private var isReadOnly: Bool {
        guard let editingRecord else { return false }
        return !editingRecord.isEditable || editingRecord.投稿语言 == nil
    }

    private static func initialRecord(
        in records: [VNDB简介翻译投稿记录]?,
        preferredLanguage: 简介翻译投稿语言
    ) -> VNDB简介翻译投稿记录? {
        records?.first { $0.language == preferredLanguage.rawValue }
            ?? records?.first
    }

    private func record(for language: 简介翻译投稿语言) -> VNDB简介翻译投稿记录? {
        entryRecords?.first { $0.language == language.rawValue }
    }

    private var editingRecord: VNDB简介翻译投稿记录? {
        existing ?? record(for: language)
    }

    private var navigationTitle: LocalizedStringKey {
        guard let editingRecord else { return "提交翻译" }
        return editingRecord.status == .accepted ? "翻译详情" : "编辑翻译"
    }

    private var trimmedTranslation: String {
        translation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        editingRecord == nil || hasUnsavedChanges
    }

    private var hasUnsavedChanges: Bool {
        guard !isReadOnly else { return false }
        let baseline = editingRecord?.translation
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTranslation != baseline
            || trimmedNote != (editingRecord?.note ?? "")
    }

    private var canSubmit: Bool {
        auth.isLoggedIn
            && !auth.token.isEmpty
            && !isReadOnly
            && !trimmedTranslation.isEmpty
            && trimmedTranslation.count <= VNDB简介翻译投稿服务.译文最大长度
            && hasChanges
            && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                if let editingRecord {
                    statusSection(editingRecord)
                } else {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("贡献翻译", systemImage: "character.bubble")
                                .font(.headline)
                            Text("你的译文将在通过后加入VNDB-Description-Translations项目并在PaperVN App中使用。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    LabeledContent("条目") {
                        多语言列表文本(
                            文本: entry.displayName,
                            isJapanese: entry.displayIsJapanese,
                            语言代码: entry.displayLanguageCode,
                            层级: .主标题,
                            日文字体名称: "HiraginoSans-W4",
                            系统字体粗细: .regular
                        )
                        .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("VNDB ID") {
                        Text(verbatim: entry.id)
                    }
                    if let existing {
                        LabeledContent("语言", value: existing.languageTitle)
                    } else {
                        Picker("语言", selection: $language) {
                            ForEach(简介翻译投稿语言.allCases) { option in
                                Text(verbatim: option.title).tag(option)
                            }
                        }
                    }
                } footer: {
                    if hasExistingTranslation, existing == nil {
                        Text("条目已有当前语言的译文，你的译文仍被提交以供审核。")
                    }
                }

                if !entry.displaySource.isEmpty {
                    Section("原文") {
                        简介原文展开文本(text: entry.displaySource)
                    }
                }

                Section {
                    if isReadOnly {
                        Text(verbatim: translation)
                            .textSelection(.enabled)
                    } else {
                        TextEditor(text: $translation)
                            .frame(minHeight: 200)
                            .accessibilityLabel("译文")
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("译文")
                        Spacer(minLength: 12)
                        if !isReadOnly {
                            translationCharacterCount
                        }
                    }
                } footer: {
                    if !isReadOnly {
                        Text("请勿直接提交机器翻译的结果。")
                    }
                }

                if !isReadOnly {
                    Section {
                        TextField("备注（选填）", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                    }

                    Section {
                        if auth.isLoggedIn {
                            LabeledContent("译者", value: auth.username)
                        } else {
                            Text("需要登录VNDB账户以提交翻译。")
                                .foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("")
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: requestDismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(isReadOnly ? "关闭" : "取消")
                    .disabled(isSubmitting)
                    .confirmationDialog(
                        "确定要放弃编辑吗？",
                        isPresented: $showsDiscardConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("继续编辑", role: .cancel) {}
                        Button("放弃编辑", role: .destructive) {
                            dismiss()
                        }
                    } message: {
                        Text("尚未提交的译文将会丢失。")
                    }
                }
                if !isReadOnly {
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
                            .disabled(!canSubmit)
                        }
                    }
                }
            }
            .平台滚动几何变化(for: Bool.self) { geometry in
                geometry.contentOffset.y <= -geometry.contentInsets.top + 1
            } action: { _, isAtTop in
                isScrolledToTop = isAtTop
            }
            .interactiveDismissDisabled(hasUnsavedChanges || isSubmitting)
            .task {
                await loadEntryRecordsIfNeeded()
            }
            .task(id: language) {
                await loadExistingTranslationState()
            }
            .onChange(of: language) { oldLanguage, newLanguage in
                switchRecord(from: oldLanguage, to: newLanguage)
            }
            .alert(
                "提交失败",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(verbatim: errorMessage ?? "")
            }
            .alert(
                "已提交翻译",
                isPresented: Binding(
                    get: { submittedResult != nil },
                    set: { if !$0 { submittedResult = nil } }
                ),
                presenting: submittedResult
            ) { _ in
                Button("好") { dismiss() }
            } message: { result in
                if result.updated {
                    Text("已更新你之前提交的译文，我们会重新审核。")
                } else {
                    Text("谢谢！你的翻译已提交以供审核。")
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard hasUnsavedChanges,
                          !isSubmitting,
                          isScrolledToTop,
                          value.translation.height > 90,
                          abs(value.translation.height)
                            > abs(value.translation.width) else {
                        return
                    }
                    showsDiscardConfirmation = true
                }
        )
        .平台近全屏弹窗()
    }

    private func requestDismiss() {
        if hasUnsavedChanges {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func loadEntryRecordsIfNeeded() async {
        guard existing == nil,
              entryRecords == nil,
              auth.isLoggedIn,
              !auth.token.isEmpty,
              let submissions = try? await VNDB简介翻译投稿服务()
                .mySubmissions(token: auth.token),
              !Task.isCancelled else {
            return
        }
        entryRecords = submissions.filter {
            $0.entryID == entry.id
                && $0.type == entry.type
                && $0.status != .withdrawn
        }
        guard trimmedTranslation.isEmpty,
              let initial = Self.initialRecord(
                in: entryRecords,
                preferredLanguage: language
              ) else {
            return
        }
        if let initialLanguage = initial.投稿语言, initialLanguage != language {
            language = initialLanguage
        }
        translation = initial.translation
        note = initial.note ?? ""
    }

    private func switchRecord(
        from oldLanguage: 简介翻译投稿语言,
        to newLanguage: 简介翻译投稿语言
    ) {
        guard existing == nil else { return }
        let previous = record(for: oldLanguage)
        let isUntouched = trimmedTranslation.isEmpty
            || trimmedTranslation == previous?.translation
                .trimmingCharacters(in: .whitespacesAndNewlines)
        guard isUntouched else { return }
        let next = record(for: newLanguage)
        translation = next?.translation ?? ""
        note = next?.note ?? ""
    }

    private var translationCharacterCount: some View {
        let count = trimmedTranslation.count
        let limit = VNDB简介翻译投稿服务.译文最大长度
        return Text(verbatim: "\(count.formatted())/\(limit.formatted())")
            .monospacedDigit()
            .foregroundStyle(count > limit ? Color.red : Color.secondary)
            .contentTransition(.numericText(value: Double(count)))
            .animation(.snappy(duration: 0.25), value: count)
    }

    @ViewBuilder
    private func statusSection(_ existing: VNDB简介翻译投稿记录) -> some View {
        Section {
            LabeledContent("状态", value: existing.statusText)
            if let date = existing.submittedDate {
                LabeledContent("提交时间") {
                    Text(date, format: .dateTime.year().month().day())
                }
            }
            if existing.status == .rejected,
               let reviewNote = existing.reviewNote?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !reviewNote.isEmpty {
                LabeledContent("拒绝原因") {
                    Text(verbatim: reviewNote)
                        .multilineTextAlignment(.trailing)
                }
            }
        } footer: {
            switch existing.status {
            case .pending:
                Text("修改后再次提交会更新这条正在审核的翻译。")
            case .rejected:
                Text("修改后再次提交会重新审核。")
            case .accepted:
                Text("这条翻译已加入开源项目。")
            case .withdrawn:
                Text("这条翻译已撤回。")
            }
        }
    }

    private func loadExistingTranslationState() async {
        hasExistingTranslation = false
        guard existing == nil else { return }
        let result = await VNDB简介人工翻译.项目译文状态(
            for: entry.id,
            type: entry.type,
            language: language.简介语言
        )
        guard !Task.isCancelled else { return }
        hasExistingTranslation = result.translation != nil
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSubmitting = false }
            do {
                submittedResult = try await VNDB简介翻译投稿服务().submit(
                    token: auth.token,
                    entry: entry,
                    language: language,
                    translation: trimmedTranslation,
                    note: trimmedNote.isEmpty ? nil : trimmedNote
                )
                await onSubmitted()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct 简介翻译贡献页面: View {
    @ObservedObject var auth: 用户登录
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    @State private var submissions: [VNDB简介翻译投稿记录] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSubmission: VNDB简介翻译投稿记录?
    @State private var pendingWithdrawal: VNDB简介翻译投稿记录?
    @State private var showsWithdrawalConfirmation = false
    @State private var withdrawalError: String?

    private var canLoad: Bool {
        auth.isLoggedIn && !auth.token.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if canLoad {
                    submissionList
                } else {
                    ContentUnavailableView {
                        Label(
                            "需要登录",
                            systemImage: "person.crop.circle.badge.exclamationmark"
                        )
                    } description: {
                        Text("登录VNDB账户后即可贡献翻译")
                    }
                }
            }
            .navigationTitle("贡献翻译")
            .平台柔和滚动边缘(for: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .sheet(item: $selectedSubmission) { submission in
            简介翻译投稿页面(
                existing: submission,
                displayName: 简介翻译条目名称.显示名称(for: submission)
            ) {
                await reload()
            }
            .environmentObject(auth)
        }
        .alert("确定要撤回翻译吗？", isPresented: $showsWithdrawalConfirmation) {
            Button("保持", role: .cancel) {
                pendingWithdrawal = nil
            }
            Button("撤回翻译", role: .destructive) {
                withdraw()
            }
        } message: {
            Text("撤回后无法重新提交以供审核。")
        }
        .alert(
            "无法撤回翻译",
            isPresented: Binding(
                get: { withdrawalError != nil },
                set: { if !$0 { withdrawalError = nil } }
            )
        ) {
            Button("好") { withdrawalError = nil }
        } message: {
            Text(verbatim: withdrawalError ?? "")
        }
    }

    private var submissionList: some View {
        List {
            if isLoading && submissions.isEmpty {
                Section {
                    ForEach(0..<3, id: \.self) { _ in
                        placeholderRow
                    }
                    .accessibilityHidden(true)
                } header: {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在载入…")
                    }
                    .textCase(nil)
                    .accessibilityElement(children: .combine)
                }
            } else if let errorMessage {
                Section {
                    平台内容不可用视图(
                        "加载失败",
                        systemImage: "exclamationmark.triangle",
                        description: Text(verbatim: errorMessage)
                    )
                }
            } else if submissions.isEmpty {
                Section {
                    平台内容不可用视图(
                        "暂无已提交翻译",
                        systemImage: "character.bubble"
                    )
                } footer: {
                    contributionHint
                }
            } else {
                Section {
                    ForEach(submissions) { submission in
                        submissionRow(submission)
                        .contextMenu {
                            contextMenuActions(for: submission)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if submission.status == .pending {
                                Button {
                                    requestWithdrawal(submission)
                                } label: {
                                    Label("撤回翻译", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.red)
                            }
                        }
                    }
                } footer: {
                    contributionHint
                }
            }
        }
        .平台分组列表样式()
        .task(id: auth.token) {
            await reload()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private func submissionRow(_ submission: VNDB简介翻译投稿记录) -> some View {
        if submission.status == .withdrawn {
            row(submission)
                .accessibilityElement(children: .combine)
        } else {
            Button {
                selectedSubmission = submission
            } label: {
                row(submission)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                submission.isEditable ? "轻点修改翻译" : "轻点查看翻译"
            )
        }
    }

    @ViewBuilder
    private func contextMenuActions(
        for submission: VNDB简介翻译投稿记录
    ) -> some View {
        if submission.isEditable {
            Button {
                selectedSubmission = submission
            } label: {
                Label("编辑翻译", systemImage: "pencil")
            }
        } else if submission.status == .accepted {
            Button {
                selectedSubmission = submission
            } label: {
                Label("查看翻译", systemImage: "doc.text")
            }
        }

        Button {
            UIPasteboard.general.string = submission.translation
        } label: {
            Label("拷贝译文", systemImage: "doc.on.doc")
        }

        if let url = URL(string: "https://vndb.org/\(submission.entryID)") {
            Button {
                openURL(url)
            } label: {
                Label("在VNDB中查看", systemImage: "safari")
            }
        }

        if submission.status == .pending {
            Divider()
            Button(role: .destructive) {
                requestWithdrawal(submission)
            } label: {
                Label("撤回翻译", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var contributionHint: some View {
        Text("")
    }

    private func row(_ submission: VNDB简介翻译投稿记录) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                多语言列表文本(
                    简介翻译条目名称.显示名称(for: submission),
                    层级: .主标题,
                    系统字体粗细: .semibold
                )
                .lineLimit(2)

                Spacer(minLength: 0)

                if let date = submission.submittedDate {
                    Text(
                        date.formatted(
                            .dateTime.year().month().day().locale(locale)
                        )
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                }
            }

            Text(verbatim: submission.translation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack {
                HStack(spacing: 6) {
                    Text(verbatim: submission.entryID)
                    Text(verbatim: "·")
                    Text(verbatim: submission.languageTitle)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(verbatim: submission.statusText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var placeholderRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "Placeholder Title")
                .font(.body.weight(.semibold))
            Text(verbatim: String(repeating: "Placeholder ", count: 12))
                .font(.subheadline)
                .lineLimit(2)
            Text(verbatim: "v00000 · Placeholder")
                .font(.caption)
        }
        .redacted(reason: .placeholder)
        .padding(.vertical, 4)
    }

    private func reload() async {
        guard canLoad else {
            submissions = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            submissions = try await VNDB简介翻译投稿服务().mySubmissions(
                token: auth.token
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestWithdrawal(_ submission: VNDB简介翻译投稿记录) {
        guard submission.status == .pending else { return }
        pendingWithdrawal = submission
        showsWithdrawalConfirmation = true
    }

    private func withdraw() {
        guard let submission = pendingWithdrawal else { return }
        pendingWithdrawal = nil
        Task {
            do {
                try await VNDB简介翻译投稿服务().withdraw(
                    token: auth.token,
                    id: submission.id
                )
                await reload()
            } catch {
                withdrawalError = error.localizedDescription
            }
        }
    }
}

private struct 简介原文展开文本: View {
    let text: String

    @State private var 已展开 = false
    @State private var 完整高度: CGFloat = 0
    @State private var 收起高度: CGFloat = 0

    private var 展开动画: Animation {
        .smooth(duration: 0.34, extraBounce: 0)
    }

    private var 应显示更多按钮: Bool {
        收起高度 > 0 && 完整高度 > 收起高度 + 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            正文
                .lineLimit(已展开 ? nil : 6)
                .textSelection(.enabled)
                .background(alignment: .topLeading) {
                    正文
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            完整高度 = height
                        }
                }
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    if !已展开 {
                        收起高度 = height
                    }
                }

            if 应显示更多按钮 {
                Button {
                    withAnimation(展开动画) {
                        已展开.toggle()
                    }
                } label: {
                    Text(已展开 ? "收起" : "更多")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .accessibilityLabel(已展开 ? "收起原文" : "展开原文")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var 正文: some View {
        Text(verbatim: text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
