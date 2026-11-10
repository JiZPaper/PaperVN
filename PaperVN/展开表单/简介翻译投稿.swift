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
        case toolbar
    }

    @ObservedObject var auth: 用户登录
    @ObservedObject private var paperAccount = PaperAccount账户.shared
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
            .sheet(isPresented: $showsFeedback) {
                数据维护提交页面(内容: .简介翻译错误(条目: entry, 语言: targetLanguage))
                    .平台近全屏弹窗()
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
        case .toolbar:
            Button(action: open) {
                if isPreparingSubmission {
                    ProgressView()
                } else {
                    Image(
                        systemName: translated
                            ? "exclamationmark.bubble"
                            : "character.bubble"
                    )
                }
            }
            .accessibilityLabel(translated ? "反馈翻译问题" : "提交翻译")
        }
    }

    private func open() {
        if hasTranslation == true {
            showsFeedback = true
            return
        }
        guard !isPreparingSubmission else { return }
        isPreparingSubmission = true
        Task {
            let token = try? await paperAccount.可选访问令牌()
            let records = try? await VNDB简介翻译投稿服务()
                .mySubmissions(token: token)
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
    @ObservedObject private var paperAccount = PaperAccount账户.shared
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
        !isReadOnly
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
                        Text(verbatim: entry.displaySource)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        TextField("备注（可选）", text: $note, axis: .vertical)
                            .lineLimit(1...4)
                    }

                    Section {
                        LabeledContent(
                            "译者",
                            value: paperAccount.isLoggedIn
                                ? paperAccount.资料?.nickname ?? String(localized: "未设置昵称")
                                : String(localized: "匿名")
                        )
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
                        "要放弃编辑吗？",
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
                                Label("提交", systemImage: "arrow.up")
                            }
                            .液态玻璃醒目按钮(in: Circle())
                            .buttonBorderShape(.circle)
                            .tint(.blue)
                            .disabled(!canSubmit)
                        }
                    }
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
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
                "无法提交",
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
                    Text("谢谢！更新的翻译已提交以供审核。")
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
              let token = try? await paperAccount.可选访问令牌(),
              let submissions = try? await VNDB简介翻译投稿服务()
                .mySubmissions(token: token),
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
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(
                count > limit
                    ? AnyShapeStyle(Color.red)
                    : AnyShapeStyle(.tertiary)
            )
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
                Text("你的更改将重新提交以供审核。")
            case .rejected:
                Text("更改后可重新提交以供审核。")
            case .accepted:
                Text("翻译已通过。")
            case .withdrawn:
                Text("翻译已撤回。")
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
                    token: try await paperAccount.可选访问令牌(),
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
