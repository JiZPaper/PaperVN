import SwiftUI

private struct 资料库编辑草稿: Equatable {
    var status: 用户列表筛选
    var rating: Int
    var releaseID: String?
    var started: Date?
    var finished: Date?
}

struct 资料库编辑页面: View {
    let vnID: String
    let title: 标题工具.标题结果
    let token: String
    let currentItem: 用户列表项目?
    let releases: [视觉小说发行版本]
    let mode: 资料库编辑模式
    let loadsReleasesOnAppear: Bool
    let initialReleaseID: String?
    let onSaved: @MainActor () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var bangumiAccount: Bangumi账户

    @AppStorage("autoFillStartDate") private var autoFillStartDate = true
    @AppStorage("autoFillFinishDate") private var autoFillFinishDate = true

    @State private var draft: 资料库编辑草稿
    @State private var originalDraft: 资料库编辑草稿
    @State private var showDiscardAlert = false
    @State private var showDateCorrectionAlert = false
    @State private var hasHandledDateCorrection = false
    @State private var hasManuallyModifiedDate = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var automaticallyFilledStarted = false
    @State private var automaticallyFilledFinished = false
    @State private var loadedReleases: [视觉小说发行版本]
    @State private var isLoadingReleases = false
    @State private var releaseLoadError: String?

    init(
        vnID: String,
        title: 标题工具.标题结果,
        token: String,
        currentItem: 用户列表项目?,
        releases: [视觉小说发行版本],
        mode: 资料库编辑模式 = .full,
        loadsReleasesOnAppear: Bool = false,
        initialReleaseID: String? = nil,
        onSaved: @escaping @MainActor () async -> Void
    ) {
        self.vnID = vnID
        self.title = title
        self.token = token
        self.currentItem = currentItem
        self.releases = releases
        self.mode = mode
        self.loadsReleasesOnAppear = loadsReleasesOnAppear
        self.initialReleaseID = initialReleaseID
        self.onSaved = onSaved

        let initial = 资料库编辑草稿(
            status: currentItem?.primaryStatus ?? .planning,
            rating: (currentItem?.vote ?? 0) / 10,
            releaseID: currentItem?.releases?.first?.id ?? initialReleaseID,
            started: Self.date(from: currentItem?.started),
            finished: Self.date(from: currentItem?.finished)
        )
        _draft = State(initialValue: initial)
        _originalDraft = State(initialValue: initial)
        _loadedReleases = State(initialValue: releases)
    }

    private var hasChanges: Bool {
        currentItem == nil || draft != originalDraft
    }

    private var availableReleases: [视觉小说发行版本] {
        loadsReleasesOnAppear ? loadedReleases : releases
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode == .full || mode == .status {
                    statusSection
                }

                if mode == .full {
                    releaseSection
                }

                if mode == .full || mode == .rating {
                    ratingSection
                }

                if mode == .full {
                    datesSection
                }
            }
            .onChange(of: draft.status) { _, status in
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

                ToolbarItem(placement: .平台前导操作) {
                    Button {
                        requestDismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                    .disabled(isSaving)
                    .confirmationDialog(
                        "要放弃更改吗？",
                        isPresented: $showDiscardAlert,
                        titleVisibility: .visible
                    ) {
                        Button("存储更改") {
                            Task {
                                await save()
                            }
                        }

                        Button("放弃更改", role: .destructive) {
                            dismiss()
                        }
                    } message: {
                        Text("尚未存储的状态、评分或日期将会丢失。")
                    }
                }

                ToolbarItem(placement: .平台主操作) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.regular)
                                .tint(.gray)
                                .frame(width: 22, height: 22)
                        } else {
                            Image(systemName: "checkmark")
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
        .task(id: vnID) {
            await loadReleasesIfNeeded()
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    guard hasChanges,
                          !isSaving,
                          value.translation.height > 90,
                          abs(value.translation.height)
                            > abs(value.translation.width) else {
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
            Button("好") {
                saveError = nil
            }
        } message: {
            Text(verbatim: saveError ?? "")
        }
        .alert(
            "这是补标吗？",
            isPresented: $showDateCorrectionAlert
        ) {
            Button("修改日期") {
                hasHandledDateCorrection = true
            }

            Button("留空日期") {
                hasHandledDateCorrection = true
                if automaticallyFilledStarted {
                    draft.started = nil
                }
                if automaticallyFilledFinished {
                    draft.finished = nil
                }
                automaticallyFilledStarted = false
                automaticallyFilledFinished = false
                Task {
                    await saveChanges()
                }
            }

            Button("无需操作", role: .cancel) {
                hasHandledDateCorrection = true
            }
        } message: {
            Text(verbatim: dateCorrectionAlertMessage)
        }
    }

    private var dateCorrectionAlertMessage: String {
        String(
            format: String(
                localized: "你似乎已经玩过“%@”。自动填充的游玩日期可能不准确。"
            ),
            title.text
        )
    }

    private var editorNavigationTitle: AttributedString {
        标题工具.生成格式化标题富文本(
            格式: String(localized: "编辑“%@”"),
            标题: title,
            基础大小: 17,
            是粗体: true
        )
    }

    private var statusSection: some View {
        Section {
            Picker("状态", selection: $draft.status) {
                ForEach(用户列表筛选.editableStatuses) { status in
                    Label(status.localizedTitle, systemImage: status.symbolName)
                        .tag(status)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("状态")
        }
    }

    private var releaseSection: some View {
        Section {
            Picker("游玩版本", selection: $draft.releaseID) {
                Text("未指定版本")
                    .tag(Optional<String>.none)

                if let selectedRelease = currentItem?.releases?.first(
                    where: { release in
                        release.id == draft.releaseID
                            && !availableReleases.contains { $0.id == release.id }
                    }
                ) {
                    Text(verbatim: selectedRelease.title)
                        .tag(Optional(selectedRelease.id))
                }

                ForEach(availableReleases) { release in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: release.title)
                        if !release.displaySubtitle.isEmpty {
                            Text(verbatim: release.displaySubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(Optional(release.id))
                }
            }
            .平台导航链接选择样式()
            .disabled(isLoadingReleases)

            if isLoadingReleases {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在载入可选版本…")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else if let releaseLoadError {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        releaseLoadError,
                        systemImage: "wifi.exclamationmark"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Button {
                        Task {
                            await loadReleasesIfNeeded(forceReload: true)
                        }
                    } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            Text("游玩版本")
        } footer: {
            if !isLoadingReleases,
               releaseLoadError == nil,
               availableReleases.isEmpty {
                Text("没有可选的发行版本。")
            }
        }
    }

    private var ratingSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("评分", systemImage: "star")
                    Spacer()
                    Text(verbatim: draft.rating == 0 ? String(localized: "无") : "\(draft.rating)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(
                            draft.rating == 0
                                ? Color.secondary
                                : Color.blue
                        )
                }

                HStack(spacing: 4) {
                    ForEach(0...10, id: \.self) { value in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                value == draft.rating
                                    ? Color.blue
                                    : Color.secondary.opacity(0.12)
                            )
                            .overlay {
                                Text(verbatim: value == 0 ? "–" : "\(value)")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(
                                        value == draft.rating
                                            ? Color.white
                                            : Color.secondary
                                    )
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
                                        updateRating(
                                            at: value.location.x,
                                            width: proxy.size.width
                                        )
                                    }
                            )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("我的评分")
                .accessibilityValue(
                    draft.rating == 0
                        ? String(localized: "无")
                        : "\(draft.rating)"
                )
                .sensoryFeedback(.selection, trigger: draft.rating)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        draft.rating = min(draft.rating + 1, 10)
                    case .decrement:
                        draft.rating = max(draft.rating - 1, 0)
                    @unknown default:
                        break
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("评分")
        } footer: {
        }
    }

    private var datesSection: some View {
        Section {
            optionalDateRow(
                title: "开始日期",
                systemImage: "calendar.badge.clock",
                date: Binding(
                    get: { draft.started },
                    set: {
                        draft.started = $0
                        automaticallyFilledStarted = false
                        hasManuallyModifiedDate = true
                    }
                )
            )

            optionalDateRow(
                title: "结束日期",
                systemImage: "calendar.badge.checkmark",
                date: Binding(
                    get: { draft.finished },
                    set: {
                        draft.finished = $0
                        automaticallyFilledFinished = false
                        hasManuallyModifiedDate = true
                    }
                )
            )
        } header: {
            Text("游玩日期")
        }
    }

    private func optionalDateRow(
        title: LocalizedStringKey,
        systemImage: String,
        date: Binding<Date?>
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
            Spacer(minLength: 8)

            if let currentDate = date.wrappedValue {
                DatePicker(
                    title,
                    selection: Binding(
                        get: { currentDate },
                        set: { date.wrappedValue = $0 }
                    ),
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
                .foregroundStyle(.blue)
            }
        }
        .frame(height: 34)
    }

    private func updateRating(at location: CGFloat, width: CGFloat) {
        guard width > 0 else { return }
        let normalized = min(max(location / width, 0), 0.999_999)
        draft.rating = min(Int(normalized * 11), 10)
    }

    private func applyAutomaticDates(for status: 用户列表筛选) {
        let today = Calendar.current.startOfDay(for: Date())

        if autoFillStartDate,
           (status == .playing || status == .finished),
           draft.started == nil {
            draft.started = today
            automaticallyFilledStarted = true
        }

        if autoFillFinishDate,
           status == .finished,
           draft.finished == nil {
            draft.finished = today
            automaticallyFilledFinished = true
        }
    }

    private var shouldAskDateCorrection: Bool {
        guard !hasHandledDateCorrection,
              !hasManuallyModifiedDate,
              mode == .full,
              originalDraft.status == .planning,
              draft.status == .finished || draft.status == .dropped else {
            return false
        }

        let recordedAddedDate = 资料库加入时间记录.date(
            userID: auth.userID,
            vnID: vnID
        )
        let serverAddedDate = currentItem?.added.map { rawValue in
            let timestamp = rawValue > 10_000_000_000
                ? TimeInterval(rawValue) / 1_000
                : TimeInterval(rawValue)
            return Date(timeIntervalSince1970: timestamp)
        }
        guard let addedDate = recordedAddedDate ?? serverAddedDate else {
            return autoFillStartDate || autoFillFinishDate
        }
        let age = Date().timeIntervalSince(addedDate)
        return (0...60 * 60 ~= age)
            && (autoFillStartDate || autoFillFinishDate)
    }

    private func requestDismiss() {
        if hasChanges {
            showDiscardAlert = true
        } else {
            dismiss()
        }
    }

    @MainActor
    private func loadReleasesIfNeeded(forceReload: Bool = false) async {
        guard mode == .full, loadsReleasesOnAppear else { return }
        guard forceReload || loadedReleases.isEmpty else { return }
        guard !isLoadingReleases else { return }

        isLoadingReleases = true
        releaseLoadError = nil
        defer { isLoadingReleases = false }

        do {
            loadedReleases = try await VNDB服务.shared.fetchVNReleases(
                vnID: vnID
            )
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .timedOut {
                releaseLoadError = String(
                    localized: "载入发行版本超时，请检查网络后再试。"
                )
            } else {
                releaseLoadError = String(
                    localized: "无法载入发行版本：\(error.localizedDescription)"
                )
            }
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        guard !token.isEmpty else {
            saveError = String(localized: "请先登录VNDB账户。")
            return
        }

        if !hasChanges {
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

        do {
            switch mode {
            case .rating:
                try await VNDB服务.shared.updateUserVote(
                    token: token,
                    vnID: vnID,
                    vote: draft.rating == 0 ? nil : draft.rating * 10
                )

            case .status:
                try await VNDB服务.shared.updateUserStatus(
                    token: token,
                    vnID: vnID,
                    status: draft.status,
                    existingLabels: currentItem?.labels ?? []
                )

            case .full:
                try await VNDB服务.shared.updateUserListEntry(
                    token: token,
                    vnID: vnID,
                    status: currentItem != nil && draft.status == originalDraft.status
                        ? nil
                        : draft.status,
                    vote: draft.rating == 0 ? nil : draft.rating * 10,
                    updateVote: draft.rating != originalDraft.rating,
                    started: Self.string(from: draft.started),
                    updateStarted: draft.started != originalDraft.started,
                    finished: Self.string(from: draft.finished),
                    updateFinished: draft.finished != originalDraft.finished,
                    existingLabels: currentItem?.labels ?? []
                )

                if draft.releaseID != originalDraft.releaseID {
                    try await VNDB服务.shared.updateReleaseSelection(
                        token: token,
                        existingReleaseIDs: currentItem?.releases?.map(\.id) ?? [],
                        selectedReleaseID: draft.releaseID
                    )
                }
            }

            if UserDefaults.standard.bool(forKey: Bangumi账户.同步设置键),
               bangumiAccount.isLoggedIn {
                try await bangumiAccount.synchronize(
                    vndbID: vnID,
                    status: draft.status,
                    rating: draft.rating == 0 ? nil : draft.rating,
                    comment: currentItem?.notes
                )
            }

            originalDraft = draft
            await onSaved()
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = error.localizedDescription
        }
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        return dateFormatter.date(from: value)
    }

    private static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        return String(
            format: "%04d-%02d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            year,
            month,
            day
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
