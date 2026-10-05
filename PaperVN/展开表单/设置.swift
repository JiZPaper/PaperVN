@preconcurrency import DeclaredAgeRange
import Observation
import SwiftUI

@MainActor
@Observable
final class 简介翻译下载状态 {
    static let shared = 简介翻译下载状态()

    var isDownloading = false
    var progress = 0.0
    var stage: VNDB简介翻译下载阶段 = .connecting
    var source: VNDB简介翻译数据源 = VNDB简介翻译数据源.优先顺序().first ?? .github
    var downloadError: String?
    var downloadedAt = VNDB简介人工翻译.完整下载日期
    var availableUpdate: VNDB简介翻译版本?
    var updateError: String?
    private var downloadGeneration = UUID()
    private var isCheckingForUpdate = false
    private var lastUpdateCheck: Date?

    private static let 忽略版本设置键 = "ignoredDescriptionTranslationRevision"

    var statusText: String { stage.localizedTitle(source: source) }

    var progressPercent: Int {
        min(max(Int(progress * 100), 0), 100)
    }

    private init() {}

    func download() async {
        guard !isDownloading else { return }
        downloadError = await runDownload()
    }

    func checkForUpdate() async {
        guard !isCheckingForUpdate,
              !isDownloading,
              availableUpdate == nil,
              VNDB简介人工翻译.已有完整下载,
              VNDB简介翻译模式.current != .openSourceFetch else {
            return
        }
        if let lastUpdateCheck,
           Date().timeIntervalSince(lastUpdateCheck) < 30 * 60 {
            return
        }

        isCheckingForUpdate = true
        lastUpdateCheck = Date()
        defer { isCheckingForUpdate = false }

        guard let update = await VNDB简介人工翻译.检查完整翻译文件更新(),
              update.revision != UserDefaults.standard.string(
                forKey: Self.忽略版本设置键
              ),
              !isDownloading else {
            return
        }
        availableUpdate = update
    }

    func ignore(_ update: VNDB简介翻译版本) {
        UserDefaults.standard.set(
            update.revision,
            forKey: Self.忽略版本设置键
        )
        availableUpdate = nil
    }

    func installUpdate() async {
        availableUpdate = nil
        guard !isDownloading else { return }
        updateError = await runDownload()
    }

    private func runDownload() async -> String? {
        isDownloading = true
        progress = 0
        stage = .connecting
        downloadError = nil
        updateError = nil
        let generation = UUID()
        downloadGeneration = generation

        return await performDownload(generation: generation)
    }

    private func performDownload(generation: UUID) async -> String? {
        defer {
            if downloadGeneration == generation {
                isDownloading = false
            }
        }

        do {
            try await VNDB简介人工翻译.下载完整翻译文件(
                progress: { fraction in
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.downloadGeneration == generation else { return }
                        self.progress = max(self.progress, fraction)
                    }
                },
                stage: { stage in
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.downloadGeneration == generation,
                              stage.rawValue >= self.stage.rawValue else { return }
                        self.stage = stage
                    }
                },
                source: { source in
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.downloadGeneration == generation else { return }
                        self.source = source
                        self.stage = .connecting
                        self.progress = 0
                    }
                }
            )
            guard downloadGeneration == generation else { return nil }
            downloadedAt = VNDB简介人工翻译.完整下载日期 ?? Date()
            UserDefaults.standard.set(
                true,
                forKey: VNDB简介人工翻译.完整下载设置键
            )
            return nil
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            guard downloadGeneration == generation else { return nil }
            return error.localizedDescription
        }
    }
}

private struct 简介翻译更新提示修饰器: ViewModifier {
    @State private var downloadState = 简介翻译下载状态.shared

    private var showsUpdatePrompt: Binding<Bool> {
        Binding(
            get: { downloadState.availableUpdate != nil },
            set: { if !$0 { downloadState.availableUpdate = nil } }
        )
    }

    private var showsUpdateError: Binding<Bool> {
        Binding(
            get: { downloadState.updateError != nil },
            set: { if !$0 { downloadState.updateError = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(
                "更新翻译文件",
                isPresented: showsUpdatePrompt,
                presenting: downloadState.availableUpdate
            ) { update in
                Button("忽略", role: .cancel) {
                    downloadState.ignore(update)
                }
                Button("更新") {
                    Task { await downloadState.installUpdate() }
                }
            } message: { update in
                Text("检测到翻译文件有较新版本（文件大小 \(update.archiveSizeText)）")
            }
            .alert("无法下载简介翻译", isPresented: showsUpdateError) {
                Button("好") { downloadState.updateError = nil }
            } message: {
                Text(verbatim: downloadState.updateError ?? "")
            }
    }
}

extension View {
    func 简介翻译更新提示() -> some View {
        modifier(简介翻译更新提示修饰器())
    }
}

private struct 简介翻译下载设置区: View {
    @AppStorage(VNDB简介翻译模式.设置键)
    private var mode: VNDB简介翻译模式 = .openSourceFetch
    @State private var downloadState = 简介翻译下载状态.shared
    @State private var pendingMode: VNDB简介翻译模式?
    @State private var showsOfflineDownloadConfirmation = false

    private var showsErrorAlert: Binding<Bool> {
        Binding(
            get: { downloadState.downloadError != nil },
            set: { if !$0 { downloadState.downloadError = nil } }
        )
    }

    var body: some View {
        Group {
            Picker(
                "偏好翻译模式",
                selection: Binding(
                    get: {
                        VNDB简介翻译模式.可用模式.contains(mode)
                            ? mode
                            : VNDB简介翻译模式.current
                    },
                    set: { select($0) }
                )
            ) {
                ForEach(VNDB简介翻译模式.可用模式) { option in
                    Text(verbatim: option.title).tag(option)
                }
            }
            .disabled(downloadState.isDownloading)

            if downloadState.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: downloadState.progress)
                    HStack {
                        Text(verbatim: downloadState.statusText)
                        Spacer()
                        Text(verbatim: "\(downloadState.progressPercent)%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if mode == .openSourceOffline {
                Button {
                    Task { await downloadState.download() }
                } label: {
                    HStack {
                        Text(
                            downloadState.downloadedAt == nil
                                ? "下载翻译文件"
                                : "检查更新"
                        )
                        Spacer()
                        if let downloadedAt = downloadState.downloadedAt {
                            Text(downloadedAt, format: .dateTime)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .alert(
            "下载翻译文件",
            isPresented: $showsOfflineDownloadConfirmation
        ) {
            Button("取消", role: .cancel) {
                pendingMode = nil
            }
            Button("下载") {
                mode = pendingMode ?? .openSourceOffline
                pendingMode = nil
                Task { await downloadState.download() }
            }
        } message: {
            Text(
                "“开源项目（离线）”模式需要下载完整翻译文件（约\(VNDB简介人工翻译.完整翻译文件大小文本)）"
            )
        }
        .alert("无法下载简介翻译", isPresented: showsErrorAlert) {
            Button("好") { downloadState.downloadError = nil }
        } message: {
            Text(verbatim: downloadState.downloadError ?? "")
        }
    }

    private func select(_ newMode: VNDB简介翻译模式) {
        guard newMode == .openSourceOffline,
              !VNDB简介人工翻译.已有完整下载 else {
            mode = newMode
            return
        }
        pendingMode = newMode
        showsOfflineDownloadConfirmation = true
    }
}

private struct Steam评论语言选择页面: View {
    @Binding var selection: Set<Steam评论语言>
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    var body: some View {
        List {
            ForEach(Steam评论语言.allCases) { language in
                Button {
                    if selection.contains(language) {
                        selection.remove(language)
                    } else {
                        selection.insert(language)
                    }
                } label: {
                    HStack {
                        Text(language.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selection.contains(language) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("显示语言")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }
}

private struct 活动地区操作菜单: View {
    let regionIDs: Set<String>
    @Binding var selection: Set<String>

    var body: some View {
        Menu {
            Button {
                selection.formUnion(regionIDs)
            } label: {
                Label("全选", systemImage: "checkmark.circle")
            }

            Button {
                selection.subtract(regionIDs)
            } label: {
                Label("取消全选", systemImage: "circle")
            }

            Button {
                selection.formSymmetricDifference(regionIDs)
            } label: {
                Label("反选", systemImage: "arrow.triangle.2.circlepath")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("地区选择操作")
    }
}

private struct 活动国家地区选择页面: View {
    let country: 活动地区国家
    @Binding var selection: Set<String>
    @State private var searchText = ""

    private var visibleRegions: [活动地区项目] {
        guard !searchText.isEmpty else { return country.regions }
        return country.regions.filter { region in
            region.searchNames.contains { name in
                name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        List {
            ForEach(visibleRegions) { region in
                Button {
                    if selection.contains(region.identifier) {
                        selection.remove(region.identifier)
                    } else {
                        selection.insert(region.identifier)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: region.localizedName(locale: .autoupdatingCurrent))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        if selection.contains(region.identifier) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .平台柔和滚动边缘(for: .top)
        .searchable(text: $searchText, prompt: "搜索地区")
        .navigationTitle(Text(verbatim: country.localizedName))
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                活动地区操作菜单(
                    regionIDs: country.regionIDs,
                    selection: $selection
                )
            }
        }
    }
}

private struct 活动地区选择页面: View {
    @Binding var selection: Set<String>
    @State private var searchText = ""

    private var visibleCountries: [活动地区国家] {
        guard !searchText.isEmpty else { return 活动地区目录.countries }
        return 活动地区目录.countries.filter { country in
            country.searchNames.contains { name in
                name.localizedCaseInsensitiveContains(searchText)
            }
            || country.regions.contains { region in
                region.searchNames.contains {
                    $0.localizedCaseInsensitiveContains(searchText)
                }
            }
        }
    }

    var body: some View {
        List {
            ForEach(visibleCountries) { country in
                NavigationLink {
                    活动国家地区选择页面(
                        country: country,
                        selection: $selection
                    )
                } label: {
                    HStack(spacing: 12) {
                        Text(verbatim: country.localizedName)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        countrySelectionIndicator(for: country)
                    }
                }
            }
        }
        .平台柔和滚动边缘(for: .top)
        .searchable(text: $searchText, prompt: "搜索国家或地区")
        .navigationTitle("偏好地区")
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                活动地区操作菜单(
                    regionIDs: 活动地区目录.allRegionIDs,
                    selection: $selection
                )
            }
        }
    }

    @ViewBuilder
    private func countrySelectionIndicator(
        for country: 活动地区国家
    ) -> some View {
        let selectedCount = country.regionIDs.intersection(selection).count
        if selectedCount == country.regionIDs.count {
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
        } else if selectedCount > 0 {
            Image(systemName: "minus")
                .foregroundStyle(.secondary)
        }
    }
}

private struct 家长控制状态设置区: View {
    @EnvironmentObject private var parentalControls: 家长控制中心

    private var showsErrorAlert: Binding<Bool> {
        Binding(
            get: { parentalControls.lastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    parentalControls.clearError()
                }
            }
        )
    }

    var body: some View {
        Section {
            LabeledContent(
                "保护状态",
                value: parentalControls.statusSummary
            )

            if #available(iOS 26.0, *) {
                共享年龄范围设置行()
            }

            LabeledContent("家长控制") {
                if parentalControls.isRequestingFamilyAuthorization {
                    ProgressView()
                        .controlSize(.small)
                } else if parentalControls.canRequestFamilyAuthorization,
                          !parentalControls.familyAuthorizationStatus.isApproved {
                    Button("授权") {
                        Task {
                            await parentalControls
                                .requestFamilyAuthorizationForChild()
                        }
                    }
                } else {
                    Text(
                        verbatim: parentalControls
                            .familyAuthorizationStatus
                            .localizedTitle
                    )
                    .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("家长控制或年龄范围控制将覆盖当前用户设置。按照家长要求或共享年龄范围隐藏不安全的内容，并限制不受信任的外部链接。")
        }
        .task {
            parentalControls.refresh()
        }
        .alert(
            "无法更新家长控制",
            isPresented: showsErrorAlert
        ) {
            Button("好") {
                parentalControls.clearError()
            }
        } message: {
            if let message = parentalControls.lastErrorMessage {
                Text(verbatim: message)
            }
        }
    }

}

@available(iOS 26.0, *)
private struct 共享年龄范围设置行: View {
    @EnvironmentObject private var parentalControls: 家长控制中心
    @Environment(\.requestAgeRange) private var requestAgeRange
    @State private var isRequestingAgeRange = false

    var body: some View {
        LabeledContent("共享年龄范围") {
            if isRequestingAgeRange {
                ProgressView()
                    .controlSize(.small)
            } else if parentalControls.ageLevel == .unknown {
                Button("共享") {
                    Task {
                        await requestAndApplyAgeRange()
                    }
                }
            } else {
                Text(verbatim: sharedAgeRangeDescription)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func requestAndApplyAgeRange() async {
        guard !isRequestingAgeRange else { return }
        isRequestingAgeRange = true
        parentalControls.clearError()
        defer { isRequestingAgeRange = false }

        do {
            let response = try await requestAgeRange(ageGates: 13, 16, 18)
            parentalControls.applyDeclaredAgeRangeResponse(response)
        } catch {
            parentalControls.recordAgeRangeRequestError(error)
        }
    }

    private var sharedAgeRangeDescription: String {
        guard let declaration = parentalControls.ageDeclarationDescription else {
            return parentalControls.ageLevel.localizedTitle
        }
        return "\(parentalControls.ageLevel.localizedTitle)（\(declaration)）"
    }
}

private struct Today模块显示设置区: View {
    @State private var config = Today显示配置.load()
    @AppStorage(为你推荐偏好分析设置.启用键)
    private var isRecommendationEnabled = true
    @State private var downloadState = 推荐模型下载状态.shared
    @State private var showsModelDownloadPrompt = false

    var body: some View {
        Section {
            Toggle("最近活动", isOn: $config.showEvents)
            Toggle("随机语录", isOn: $config.showQuotes)
            Toggle(
                "为你推荐",
                isOn: Binding(
                    get: {
                        为你推荐偏好分析设置.此设备支持 && isRecommendationEnabled
                    },
                    set: { updateRecommendationEnabledState($0) }
                )
            )
            .disabled(!为你推荐偏好分析设置.此设备支持)

            if downloadState.isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: downloadState.progress)
                    HStack {
                        Text("下载低秩模型")
                        Spacer()
                        Text(verbatim: "\(downloadState.progressPercent)%")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else if isRecommendationEnabled,
                      !downloadState.hasDownloadedModel,
                      let error = downloadState.downloadError {
                Button("重新下载模型") {
                    Task { await downloadState.download() }
                }
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isRecommendationEnabled, downloadState.needsUpdate {
                Button("重新下载模型") {
                    Task { await downloadState.download() }
                }
            }
        } header: {
            Text("显示模块")
        } footer: {
            if 为你推荐偏好分析设置.此设备支持 {
                Text("")
            } else {
                Text("“为你推荐”功能需要至少4GB内存的设备。")
            }
        }
        .task { downloadState.refresh() }
        .alert(
            "下载偏好分析所需模型",
            isPresented: $showsModelDownloadPrompt
        ) {
            Button("禁用\"为你推荐\"") {
                isRecommendationEnabled = false
                推荐后台分析中心.shared.停止分析()
            }
            Button("下载（40.5 MB）") {
                Task { await downloadState.download() }
            }
        } message: {
            Text("从此版本开始，偏好分析所需的模型不再包含在PaperVN App中，偏好分析将用于Today页面的\"为你推荐\"部分。")
        }
        .onChange(of: config) { _, newValue in
            newValue.save()
        }
        .onChange(of: isRecommendationEnabled) { _, enabled in
            if enabled {
                推荐后台分析中心.shared.启动需要的分析()
            } else {
                推荐后台分析中心.shared.停止分析()
            }
        }
    }

    private func updateRecommendationEnabledState(_ enabled: Bool) {
        guard 为你推荐偏好分析设置.此设备支持 else {
            isRecommendationEnabled = false
            return
        }
        isRecommendationEnabled = enabled
        guard enabled else { return }
        downloadState.refresh()
        guard !downloadState.hasDownloadedModel else { return }
        showsModelDownloadPrompt = true
    }
}

struct 语言与地区: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("subTitleLang") private var subTitleLang: 副标题语言 = .none
    @AppStorage("staffNameLang") private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    @AppStorage("descriptionTranslationLanguage")
    private var descriptionTranslationLanguage: 简介翻译语言 = .simplifiedChinese
    @AppStorage(Steam评论语言.设置键)
    private var steamReviewLanguages = Steam评论语言.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage(活动地区偏好.设置键)
    private var activityRegionSelection = 活动地区偏好.默认值

    @State private var showsTranslationModePopover = false

    var body: some View {
        平台滚动页面 {
            Section {
                Picker("偏好语言", selection: $preferredTitleLang) {
                    ForEach(标题语言.allCases) { language in
                        Text(verbatim: language.localizedTitle)
                            .tag(language)
                    }
                }

                Picker("回退语言", selection: $fallbackTitleLang) {
                    ForEach(标题语言.allCases) { language in
                        Text(verbatim: language.localizedTitle)
                            .tag(language)
                            .disabled(
                                preferredTitleLang != .original
                                    && language == preferredTitleLang
                            )
                    }
                }
                .disabled(preferredTitleLang == .original)

                Picker("副标题语言", selection: $subTitleLang) {
                    ForEach(副标题语言.allCases) { language in
                        Text(verbatim: language.localizedTitle)
                            .tag(language)
                            .disabled(
                                language != .none
                                    && language.对应的标题语言 == preferredTitleLang
                            )
                    }
                }

                Toggle("允许非官方标题", isOn: $allowUnofficialTitles)
            } header: {
                Text("标题")
            } footer: {
                Text("PaperVN按照“偏好语言 > 回退语言 > VNDB默认标题”的顺序获取标题。")
            }

            Section {
                Picker("翻译语言", selection: $descriptionTranslationLanguage) {
                    ForEach(简介翻译语言.allCases) { language in
                        Text(verbatim: language.title)
                            .tag(language)
                    }
                }

                简介翻译下载设置区()
            } header: {
                HStack {
                    Text("视觉小说简介与标签")
                    Spacer()
                    Button {
                        showsTranslationModePopover = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("偏好翻译模式")
                    .popover(
                        isPresented: $showsTranslationModePopover,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        translationModePopover
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }

            Section {
                NavigationLink {
                    Steam评论语言选择页面(
                        selection: steamLanguageSelection,
                        isPresented: $isPresented
                    )
                } label: {
                    LabeledContent("显示语言") {
                        Text(verbatim: steamLanguageSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Steam评论")
            } footer: {
            }

            Section {
                Picker("显示语言", selection: $staffNameLang) {
                    ForEach(制作人员语言.allCases) { language in
                        Text(verbatim: language.localizedTitle)
                            .tag(language)
                    }
                }
            } header: {
                Text("其他内容")
            } footer: {
                Text("会社、制作人员、角色与声优的显示语言。")
            }

            Section {
                NavigationLink {
                    活动地区选择页面(selection: activityRegionSelectionBinding)
                } label: {
                    LabeledContent("偏好地区") {
                        Text(verbatim: activityRegionSummary)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("活动")
            }
        }
        .平台分组列表样式()
        .navigationTitle("语言与地区")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
        .onChange(of: preferredTitleLang) { _, newValue in
            normalizeTitleLanguageSettings(preferred: newValue)
        }
        .onChange(of: fallbackTitleLang) { _, newValue in
            if preferredTitleLang != .original,
               newValue == preferredTitleLang {
                fallbackTitleLang = .original
            }
        }
        .onChange(of: subTitleLang) { _, newValue in
            if newValue != .none,
               newValue.对应的标题语言 == preferredTitleLang {
                subTitleLang = .none
            }
        }
        .onAppear {
            normalizeTitleLanguageSettings(preferred: preferredTitleLang)
        }
    }

    private var selectedSteamLanguages: Set<Steam评论语言> {
        Set(
            steamReviewLanguages
                .split(separator: ",")
                .compactMap { Steam评论语言(rawValue: String($0)) }
        )
    }

    private var steamLanguageSelection: Binding<Set<Steam评论语言>> {
        Binding(
            get: { selectedSteamLanguages },
            set: { values in
                Steam评论语言.save(values)
                steamReviewLanguages = Steam评论语言.allCases
                    .filter(values.contains)
                    .map(\.rawValue)
                    .joined(separator: ",")
            }
        )
    }

    private var steamLanguageSummary: String {
        let selected = Steam评论语言.allCases.filter(selectedSteamLanguages.contains)
        if selected.isEmpty { return String(localized: "未选择") }
        if selected.count == Steam评论语言.allCases.count {
            return String(localized: "全部")
        }
        return ListFormatter.localizedString(byJoining: selected.map(\.title))
    }

    private var selectedActivityRegionIDs: Set<String> {
        Set(activityRegionSelection.split(separator: ",").map(String.init))
            .intersection(活动地区目录.allRegionIDs)
    }

    private var activityRegionSelectionBinding: Binding<Set<String>> {
        Binding(
            get: { selectedActivityRegionIDs },
            set: { values in
                活动地区偏好.写入(values)
                activityRegionSelection = 活动地区偏好.当前选择标识符
            }
        )
    }

    private var activityRegionSummary: String {
        let selected = selectedActivityRegionIDs
        if selected.isEmpty { return String(localized: "未选择") }
        if selected.count == 活动地区目录.allRegionIDs.count {
            return String(localized: "全部")
        }
        return String.localizedStringWithFormat(
            String(localized: "已选择地区（%lld）"),
            selected.count
        )
    }

    private var translationModePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("偏好翻译模式")
                .font(.headline)
                .foregroundStyle(translationModeTextColor)

            Divider()

            ViewThatFits(in: .vertical) {
                translationModeDescription
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView {
                    translationModeDescription
                        .fixedSize(horizontal: false, vertical: true)
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: 420)
            }
        }
        .frame(
            idealWidth: 360,
            maxWidth: 420,
            alignment: .leading
        )
        .padding()
        .平台弹窗贴合内容尺寸()
    }

    private var translationModeDescription: some View {
        Text("“设备端模型”模式：在简介旁边显示翻译按钮，使用Apple离线翻译模型进行翻译；\n“开源项目（获取）”模式：从GitHub或PaperVN服务器获取翻译，并替换原简介文本；\n“开源项目（离线）”模式：先下载完整翻译文件，再替换原简介文本。\n尚未完成翻译的简介依然使用设备端模型自动翻译，你也可以点按简介旁的按钮提交自己的翻译。你可以前往关于页面了解此开源项目的更多信息。")
            .font(.callout)
            .foregroundStyle(translationModeTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    private var translationModeTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private func normalizeTitleLanguageSettings(preferred: 标题语言) {
        if preferred == .original || fallbackTitleLang == preferred {
            fallbackTitleLang = .original
        }

        if subTitleLang != .none,
           subTitleLang.对应的标题语言 == preferred {
            subTitleLang = .none
        }
    }
}

struct 设置项目标签: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        color: Color
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            设置项目图标(
                systemImage: systemImage,
                color: color,
                size: 28,
                symbolSize: 16,
                cornerRadius: 7
            )

            Text(title)
                .foregroundStyle(.primary)
        }
    }
}

private struct 设置项目图标: View {
    let systemImage: String
    let color: Color
    let size: CGFloat
    let symbolSize: CGFloat
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: symbolSize, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? color : .white)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(iconBackgroundStyle)
            }
            .overlay {
                if colorScheme == .dark {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.5)
                }
            }
            .accessibilityHidden(true)
    }

    private var iconBackgroundStyle: AnyShapeStyle {
        if colorScheme == .dark {
            AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.1), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.45),
                        .init(color: .black.opacity(0.28), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            AnyShapeStyle(color.gradient)
        }
    }
}

private struct 设置类别介绍: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            设置项目图标(
                systemImage: systemImage,
                color: color,
                size: 56,
                symbolSize: 30,
                cornerRadius: 14
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title2)
                    .bold()

                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct 通用设置: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    @AppStorage(沉浸详情外观.设置键)
    private var immersiveDetailAppearance: 沉浸详情外观 = .clear

    var body: some View {
        平台滚动页面 {
            Section {
                设置类别介绍(
                    title: "通用",
                    description: "管理PaperVN的整体设置和偏好设置，例如语言与地区等。",
                    systemImage: "gear",
                    color: .gray
                )
            }

            Section {
                NavigationLink {
                    关于页面(isPresented: $isPresented)
                } label: {
                        设置项目标签(
                            "关于",
                            systemImage: "info.circle.fill",
                            color: .gray
                    )
                }

                NavigationLink {
                    储存空间设置(
                        isPresented: $isPresented,
                        showsDismissButton: true
                    )
                } label: {
                    设置项目标签(
                        "储存空间",
                        systemImage: "internaldrive.fill",
                        color: .gray
                    )
                }
            }

            Section {
                NavigationLink {
                    语言与地区(
                        isPresented: $isPresented,
                        showsDismissButton: true
                    )
                } label: {
                        设置项目标签(
                            "语言与地区",
                            systemImage: "globe",
                            color: .blue
                    )
                }

                if #available(iOS 26.0, *) {
                    NavigationLink {
                        LiquidGlass设置(
                            selection: $immersiveDetailAppearance,
                            isPresented: $isPresented,
                            showsDismissButton: true
                        )
                    } label: {
                        HStack {
                            设置项目标签(
                                "Liquid Glass",
                                systemImage: "circle.hexagongrid.fill",
                                color: .blue
                            )
                            Spacer(minLength: 12)
                            Text(verbatim: immersiveDetailAppearance.localizedTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("通用")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }
}

private struct LiquidGlass设置: View {
    @Binding var selection: 沉浸详情外观
    @Binding var isPresented: Bool
    let showsDismissButton: Bool

    var body: some View {
        平台滚动页面 {
            Section {
                NavigationLink {
                    LiquidGlass外观选择页面(
                        selection: $selection,
                        isPresented: $isPresented,
                        showsDismissButton: true
                    )
                } label: {
                    HStack {
                        Text("外观")
                        Spacer(minLength: 12)
                        Text(verbatim: selection.localizedTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityValue(Text(verbatim: selection.localizedTitle))
            } footer: {
                Text("选取喜欢的Liquid Glass外观。")
            }
        }
        .平台分组列表样式()
        .navigationTitle("Liquid Glass")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                closeButton
            }
        }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .平台关闭操作) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
            }
            .accessibilityLabel("关闭")
        }
    }
}

private struct LiquidGlass外观选择页面: View {
    @Binding var selection: 沉浸详情外观
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    private let options: [沉浸详情外观] = [
        .clear,
        .standard,
        .reduced
    ]

    var body: some View {
        Form {
            if #available(iOS 27.0, *) {
                Section {
                    LiquidGlass详情预览(appearance: selection)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("星空列车与白的旅行详情预览")
                }
            }

            Section {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        HStack {
                            Text(verbatim: option.localizedTitle)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(
                        selection == option ? .isSelected : []
                    )
                }
            } footer: {
                Text("选取喜欢的Liquid Glass外观。“透明”更通透，可显示下方内容。“色调”可增加不透明度，并添加更多对比度。")
            }
        }
        .formStyle(.grouped)
        .平台柔和滚动边缘(for: .top)
        .navigationTitle("外观")
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }
}

private struct LiquidGlass详情预览: View {
    let appearance: 沉浸详情外观

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                previewBackdrop
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                previewHeroImageComposition
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    detailInformation
                }
                .padding(14)
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .zIndex(1)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1.68, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    private var heroImage: some View {
        Image("LiquidGlassPreviewHoshizora")
            .resizable()
            .scaledToFill()
            .offset(y: 24)
            .accessibilityHidden(true)
    }

    private var previewBackdrop: some View {
        heroImage
            .scaleEffect(1.55)
            .blur(radius: 96)
            .saturation(1.18)
            .opacity(0.56)
    }

    private var previewHeroImageComposition: some View {
        ZStack {
            heroImage
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.42),
                            .init(color: .white.opacity(0.78), location: 0.47),
                            .init(color: .white.opacity(0.38), location: 0.54),
                            .init(color: .clear, location: 0.64)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            heroImage
                .blur(radius: 16)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.4),
                            .init(color: .white.opacity(0.5), location: 0.49),
                            .init(color: .white, location: 0.64),
                            .init(color: .white, location: 0.84),
                            .init(color: .white.opacity(0.46), location: 0.96),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            heroImage
                .blur(radius: 36)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.68),
                            .init(color: .white.opacity(0.4), location: 0.76),
                            .init(color: .white, location: 0.88),
                            .init(color: .white, location: 0.96),
                            .init(color: .white.opacity(0.36), location: 0.99),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .compositingGroup()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .white, location: 0),
                    .init(color: .white, location: 0.58),
                    .init(color: .white.opacity(0.86), location: 0.7),
                    .init(color: .white.opacity(0.58), location: 0.84),
                    .init(color: .white.opacity(0.3), location: 0.92),
                    .init(color: .white.opacity(0.08), location: 0.99),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var detailInformation: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(alignment: .leading, spacing: 2) {
                Text("星空列车与白的旅行")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Text("星空鉄道とシロの旅")
                    .font(.caption)
                    .foregroundStyle(previewSecondaryTextColor)
                    .lineLimit(1)
            }

            HStack(spacing: 12) {
                detailItem("chart.bar.xaxis", title: "评分", value: "8.04")
                detailItem("calendar", title: "发行日期", value: "2020-12-30")
            }
        }
        .foregroundStyle(previewPrimaryTextColor)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情玻璃背景(
            appearance,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private func detailItem(
        _ systemImage: String,
        title: LocalizedStringKey,
        value: String
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption)
                .frame(width: 15, height: 15)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(previewSecondaryTextColor)
                Text(verbatim: value)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewPrimaryTextColor: Color {
        appearance == .standard ? .primary : .white
    }

    private var previewSecondaryTextColor: Color {
        previewPrimaryTextColor.opacity(0.78)
    }
}

struct 网络设置: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true
    @EnvironmentObject private var kunAccount: 鲲Galgame账户

    @AppStorage(PaperVNConnect自动策略.自动转发状态键)
    private var requestForwardingEnabled = false
    @AppStorage(NextMoe内容设置.设置键)
    private var nextMoeContentEnabled = false
    @State private var showsNextMoeInfoPopover = false
    @State private var showsNextMoeRegionAlert = false
    @State private var isCheckingNextMoeRegion = false

    private var kunAccountErrorPresented: Binding<Bool> {
        Binding(
            get: { kunAccount.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    kunAccount.errorMessage = nil
                }
            }
        )
    }

    private var nextMoeToggleBinding: Binding<Bool> {
        Binding(
            get: { nextMoeContentEnabled },
            set: { isEnabled in
                guard isEnabled else {
                    nextMoeContentEnabled = false
                    return
                }
                Task { @MainActor in
                    await enableNextMoeContent()
                }
            }
        )
    }

    var body: some View {
        平台滚动页面 {
            Section {
                Toggle(
                    "PaperVN Connect",
                    isOn: $requestForwardingEnabled
                )
            } footer: {
                Text(
                    "转发VNDB、Steam、Bangumi番组计划、Today与活动请求。"
                )
            }

            Section {
                Toggle(isOn: nextMoeToggleBinding) {
                    HStack {
                        Text("通过鲲Galgame获取内容")
                        Spacer()
                        Button {
                            showsNextMoeInfoPopover = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("此功能是如何运作的？")
                        .popover(
                            isPresented: $showsNextMoeInfoPopover,
                            attachmentAnchor: .rect(.bounds),
                            arrowEdge: .top
                        ) {
                            nextMoeInfoPopover
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                    .disabled(isCheckingNextMoeRegion)
            } footer: {
                Text(
                    "通过鲲Galgame间接获取原数据来源的内容。这将有助于改善部分用户的加载体验，但会受到NextMoe API的速率限制。"
                )
            }
        }
        .平台分组列表样式()
        .navigationTitle("网络")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .alert(
            "鲲Galgame登录失败",
            isPresented: kunAccountErrorPresented
        ) {
            Button("好") {
                kunAccount.errorMessage = nil
            }
        } message: {
            Text(verbatim: kunAccount.errorMessage ?? "")
        }
        .alert(
            "可能导致更慢的加载速度",
            isPresented: $showsNextMoeRegionAlert
        ) {
            Button("禁用", role: .cancel) {
                nextMoeContentEnabled = false
            }
            Button("启用") {
                nextMoeContentEnabled = true
                请求NextMoe访问权限()
            }
        } message: {
            Text(
                "此功能仅推荐居住在数据来源站点被封禁的国家或地区（如中国大陆）的用户启用。可能不适应你当前的网络环境。"
            )
        }
        .onChange(of: kunAccount.isRestoringSession) { _, isRestoring in
            guard !isRestoring, nextMoeContentEnabled else { return }
            请求NextMoe访问权限()
        }
        .task {
            guard nextMoeContentEnabled else { return }
            请求NextMoe访问权限()
        }
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }

    private var nextMoeInfoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("此功能是如何运作的？")
                .font(.headline)

            Divider()

            ViewThatFits(in: .vertical) {
                nextMoeInfoDescription

                ScrollView {
                    nextMoeInfoDescription
                }
                .scrollIndicators(.visible)
                .frame(maxHeight: 420)
            }
        }
        .frame(idealWidth: 360, maxWidth: 420, alignment: .leading)
        .padding(16)
        .平台弹窗贴合内容尺寸()
    }

    private var nextMoeInfoDescription: some View {
        Text(
            "鲲Galgame提供的NextMoe API聚合了多个平台的相关数据。PaperVN将利用NextMoe API获取需要的所有可用内容，并减少向原数据来源站点发送请求。PaperVN Connect与此功能同时启用时，向NextMoe API发送的请求不会通过代理。仅推荐居住在数据来源站点被封禁的国家或地区的用户启用。"
        )
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func enableNextMoeContent() async {
        guard !isCheckingNextMoeRegion else { return }
        isCheckingNextMoeRegion = true
        defer { isCheckingNextMoeRegion = false }

        let countryCode = await NextMoe内容设置.用户IP国家代码()
        guard countryCode != "CN" else {
            nextMoeContentEnabled = true
            请求NextMoe访问权限()
            return
        }

        guard countryCode != nil else {
            nextMoeContentEnabled = true
            请求NextMoe访问权限()
            return
        }

        showsNextMoeRegionAlert = true
    }

    private func 请求NextMoe访问权限() {
        guard !kunAccount.isAuthenticating,
              !kunAccount.isRestoringSession else { return }
        if kunAccount.isLoggedIn {
            guard !kunAccount.hasCatalogAccess else { return }
        }
        kunAccount.login()
    }
}

private struct iCloud同步设置区: View {
    @StateObject private var preferenceData = 偏好校准中心.shared

    private var iCloudBinding: Binding<Bool> {
        Binding(
            get: { preferenceData.isICloudSyncEnabled },
            set: { preferenceData.setICloudSyncEnabled($0) }
        )
    }

    var body: some View {
        Section {
            Toggle("iCloud同步", isOn: iCloudBinding)
        } footer: {
            Text("在不同设备间同步你的偏好数据和Today功能开关设置。")
        }
    }
}

struct Today设置: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    var body: some View {
        平台滚动页面 {
            Section {
                设置类别介绍(
                    title: "Today",
                    description: "管理Today页面的偏好设置。",
                    systemImage: "newspaper.fill",
                    color: .gray
                )
            }

            Today模块显示设置区()
            iCloud同步设置区()
        }
        .平台分组列表样式()
        .navigationTitle("Today")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }
}

struct 资料库设置: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    @AppStorage("autoFillStartDate") private var autoFillStartDate = true
    @AppStorage("autoFillFinishDate") private var autoFillFinishDate = true
    @AppStorage(评分数据来源.设置键)
    private var ratingSource = 评分数据来源.combined.rawValue
    @AppStorage("combinedRatingVNDBWeight")
    private var combinedRatingVNDBWeight = 0.5
    @AppStorage(评论数据来源.设置键)
    private var commentSource = 评论数据来源.combined.rawValue

    var body: some View {
        平台滚动页面 {
            Section {
                设置类别介绍(
                    title: "资料库",
                    description: "管理资料库页面的偏好设置。",
                    systemImage: "books.vertical.fill",
                    color: .gray
                )
            }

            Section {
                Picker("评分", selection: $ratingSource) {
                    ForEach(评分数据来源.allCases) { source in
                        Text(source.title).tag(source.rawValue)
                    }
                }

                if ratingSource == 评分数据来源.combined.rawValue {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("权重")
                            Spacer()
                            Text(
                                verbatim: "\(combinedRatingVNDBPercentage)% / \(combinedRatingBangumiPercentage)%"
                            )
                            .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: combinedRatingSliderBinding,
                            in: 0.1...0.9,
                            step: 0.1
                        ) {
                            Text("权重")
                        } minimumValueLabel: {
                            Text("VNDB")
                                .font(.caption2)
                        } maximumValueLabel: {
                            Text("Bangumi番组计划")
                                .font(.caption2)
                        }
                    }
                }

                Picker("评论", selection: $commentSource) {
                    ForEach(评论数据来源.allCases) { source in
                        Text(source.title).tag(source.rawValue)
                    }
                }
            } header: {
                Text("数据来源")
            }

            Section {
                Toggle("自动填充“开始日期”", isOn: $autoFillStartDate)
                Toggle("自动填充“结束日期”", isOn: $autoFillFinishDate)
            } header: {
                Text("游玩日期")
            } footer: {
                Text("更改游玩状态时自动填写开始或结束日期。")
            }

        }
        .平台分组列表样式()
        .navigationTitle("资料库")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }

    private var combinedRatingVNDBPercentage: Int {
        min(max(Int((combinedRatingVNDBWeight * 10).rounded()), 1), 9) * 10
    }

    private var combinedRatingBangumiPercentage: Int {
        100 - combinedRatingVNDBPercentage
    }

    private var combinedRatingSliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(combinedRatingBangumiPercentage) / 100
            },
            set: { newValue in
                let bangumiSteps = min(
                    max(Int((newValue * 10).rounded()), 1),
                    9
                )
                combinedRatingVNDBWeight = Double(10 - bangumiSteps) / 10
            }
        )
    }
}

struct 搜索设置: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    @AppStorage(搜索设置偏好.独立搜索Tab设置键)
    private var independentSearchTab = 搜索设置偏好.独立搜索Tab默认值

    var body: some View {
        平台滚动页面 {
            Section {
                设置类别介绍(
                    title: "搜索",
                    description: "管理搜索页面的偏好设置。",
                    systemImage: "magnifyingglass",
                    color: .gray
                )
            }

            if #available(iOS 27.0, *) {
                Section {
                    Toggle("独立搜索Tab", isOn: $independentSearchTab)
                } footer: {
                    Text(
                        ""
                    )
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("搜索")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }
}

struct 储存空间设置: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    var body: some View {
        平台滚动页面 {
            储存空间管理区()
        }
        .平台分组列表样式()
        .navigationTitle("储存空间")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }
}

private enum 储存空间删除项目: String, Identifiable {
    case cache
    case translations
    case recommendationModel

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .cache:
            "确定要删除缓存吗？"
        case .translations:
            "将偏好翻译模式切换为“开源项目（获取）”"
        case .recommendationModel:
            "禁用“为你推荐”"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .cache:
            "删除缓存后，所有内容都将重新加载。通常情况下，缓存会在不必要时自动删除。如果你遇到了异常的缓存占用，请向开发者提交错误报告。"
        case .translations:
            "“开源项目（离线）”翻译模式依赖此翻译文件。删除后偏好翻译模式将切换为“开源项目（获取）”。"
        case .recommendationModel:
            "“为你推荐”的偏好分析依赖此低秩模型。删除后将禁用“为你推荐”功能。"
        }
    }
}

private struct 储存空间管理区: View {
    @AppStorage(缓存策略.设置键)
    private var cacheStrategy: 缓存策略 = .balanced
    @AppStorage(VNDB简介翻译模式.设置键)
    private var translationMode: VNDB简介翻译模式 = .openSourceFetch
    @AppStorage(为你推荐偏好分析设置.启用键)
    private var recommendationPreferenceAnalysisEnabled = true
    @State private var recommendationModelDownloadState = 推荐模型下载状态.shared
    @State private var cacheSize: Int64 = 0
    @State private var translationSize: Int64 = 0
    @State private var recommendationModelSize: Int64 = 0
    @State private var hasDownloadedTranslations = false
    @State private var hasDownloadedRecommendationModel = false
    @State private var isClearingCache = false
    @State private var isDeletingTranslations = false
    @State private var isDeletingRecommendationModel = false
    @State private var pendingDeletion: 储存空间删除项目?
    @State private var deletionError: String?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("缓存策略")
                    Spacer()
                    Text(verbatim: cacheStrategy.title)
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: cacheStrategySliderValue,
                    in: 0...2,
                    step: 1
                ) {
                    Text("缓存策略")
                } minimumValueLabel: {
                    Text("更少")
                        .font(.caption)
                } maximumValueLabel: {
                    Text("更多")
                        .font(.caption)
                }
            }

            storageDeletionButton(
                title: "删除缓存",
                size: cacheSize,
                isWorking: isClearingCache,
                action: { pendingDeletion = .cache }
            )
        } header: {
            Text("缓存")
        } footer: {
            Text("“更少”缓存策略可能让你频繁地看到加载页面；“更多”缓存策略将大幅增加缓存时间与范围，并提前加载你可能查看的内容。")
        }
        .task { refreshSizes() }
        .alert(item: $pendingDeletion) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                primaryButton: .destructive(Text("删除")) {
                    performDeletion(item)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(
            "无法删除文件",
            isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )
        ) {
            Button("好") { deletionError = nil }
        } message: {
            Text(verbatim: deletionError ?? "")
        }
        .onChange(of: cacheStrategy) { _, _ in
            缓存策略.应用URLCache配置()
        }

        if hasDownloadedTranslations || hasDownloadedRecommendationModel {
            Section {
                if hasDownloadedTranslations {
                    storageDeletionButton(
                        title: "删除简介翻译文件",
                        size: translationSize,
                        isWorking: isDeletingTranslations,
                        action: { pendingDeletion = .translations }
                    )
                }

                if hasDownloadedRecommendationModel {
                    storageDeletionButton(
                        title: "删除低秩模型",
                        size: recommendationModelSize,
                        isWorking: isDeletingRecommendationModel,
                        action: { pendingDeletion = .recommendationModel }
                    )
                }
            }
        }
    }

    private var cacheStrategySliderValue: Binding<Double> {
        Binding(
            get: { cacheStrategy.sliderPosition },
            set: { cacheStrategy = 缓存策略(sliderPosition: $0) }
        )
    }

    private func storageDeletionButton(
        title: LocalizedStringKey,
        size: Int64,
        isWorking: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: .destructive, action: action) {
            HStack {
                Text(title)
                Spacer()
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(verbatim: formattedSize(size))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isWorking)
    }

    private func formattedSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func refreshSizes() {
        cacheSize = VNDB服务.shared.cacheSizeInBytes()
            + VNDB探索服务.shared.cacheSizeInBytes()
            + 视觉小说外部数据服务.shared.cacheSizeInBytes()
            + VNDB简介人工翻译.译文缓存大小字节数
        hasDownloadedTranslations = VNDB简介人工翻译.已有完整下载
        translationSize = VNDB简介人工翻译.已下载文件大小字节数
        recommendationModelDownloadState.refresh()
        hasDownloadedRecommendationModel =
            recommendationModelDownloadState.hasDownloadedModel
        recommendationModelSize = recommendationModelDownloadState.downloadedSize
    }

    private func performDeletion(_ item: 储存空间删除项目) {
        switch item {
        case .cache:
            clearCache()
        case .translations:
            deleteTranslations()
        case .recommendationModel:
            deleteRecommendationModel()
        }
    }

    private func clearCache() {
        guard !isClearingCache else { return }
        isClearingCache = true
        Task { @MainActor in
            await VNDB服务.shared.clearCache()
            await VNDB探索服务.shared.清除缓存()
            视觉小说外部数据服务.shared.clearCache()
            VNDB简介人工翻译.清除译文缓存()
            refreshSizes()
            isClearingCache = false
        }
    }

    private func deleteTranslations() {
        guard !isDeletingTranslations else { return }
        isDeletingTranslations = true
        do {
            try VNDB简介人工翻译.删除完整翻译文件()
            translationMode = .openSourceFetch
            简介翻译下载状态.shared.downloadedAt = nil
            refreshSizes()
        } catch {
            deletionError = error.localizedDescription
        }
        isDeletingTranslations = false
    }

    private func deleteRecommendationModel() {
        guard !isDeletingRecommendationModel else { return }
        isDeletingRecommendationModel = true
        do {
            try recommendationModelDownloadState.deleteModel()
            recommendationPreferenceAnalysisEnabled = false
            推荐后台分析中心.shared.停止分析()
            refreshSizes()
        } catch {
            deletionError = error.localizedDescription
        }
        isDeletingRecommendationModel = false
    }
}

struct 内容与安全限制: View {
    @Binding var isPresented: Bool
    var showsDismissButton: Bool = true

    enum 页面 {
        case categories
        case safety
        case spoilers
        case ageAppropriate
    }

    private let page: 页面

    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var parentalControls: 家长控制中心
    @StateObject private var emergencyAvoidance = 紧急回避中心.shared
    @AppStorage(强制内容安全策略.高级设置解锁键)
    private var advancedControlsUnlocked = false
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var contentRestrictionMethod: 内容限制方式 = .blurred
    @AppStorage("spoilerTagBlurLevel") private var spoilerTagBlurLevel = 剧透标签模糊设置.majorOnly.rawValue
    @AppStorage("blurAverageRating") private var blurAverageRating = false
    @AppStorage("blurDescription") private var blurDescription = false
    @AppStorage(紧急回避设置.启用键)
    private var emergencyAvoidanceEnabled = false

    private var emergencyAvoidanceTitle: String {
        UIDevice.current.userInterfaceIdiom == .pad
            ? String(localized: "翻转iPad以紧急回避")
            : String(localized: "翻转iPhone以紧急回避")
    }

    private var emergencyAvoidanceDeviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    private var safetySettingsAreLocked: Bool {
        emergencyAvoidance.isActive || parentalControls.policy.isEnforced
    }

    init(
        isPresented: Binding<Bool>,
        showsDismissButton: Bool = true,
        page: 页面 = .categories
    ) {
        _isPresented = isPresented
        self.showsDismissButton = showsDismissButton
        self.page = page
    }

    private var allowsAdvancedControls: Bool {
        advancedControlsUnlocked
            && 强制内容安全策略.可使用高级设置(token: auth.token)
    }

    private var sexualThresholdLimit: Double {
        allowsAdvancedControls
            ? 强制内容安全策略.最大色情阈值
            : 强制内容安全策略.色情阈值
    }

    private var spoilerSliderValue: Binding<Double> {
        Binding(
            get: {
                (剧透标签模糊设置(rawValue: spoilerTagBlurLevel) ?? .majorOnly)
                    .sliderPosition
            },
            set: { newValue in
                spoilerTagBlurLevel = 剧透标签模糊设置(
                    sliderPosition: newValue
                ).rawValue
            }
        )
    }

    private var currentSpoilerSetting: 剧透标签模糊设置 {
        剧透标签模糊设置(rawValue: spoilerTagBlurLevel) ?? .majorOnly
    }

    private var navigationTitle: LocalizedStringKey {
        switch page {
        case .categories:
            "内容与安全限制"
        case .safety:
            "安全限制"
        case .spoilers:
            "剧透内容"
        case .ageAppropriate:
            "适龄体验"
        }
    }

    var body: some View {
        平台滚动页面 {
            if page == .categories {
                Section {
                    设置类别介绍(
                        title: "内容与安全限制",
                        description: "限制不安全的内容或剧透内容显示。",
                        systemImage: "hand.raised.fill",
                        color: .blue
                    )
                }

                Section {
                    NavigationLink {
                        内容与安全限制(
                            isPresented: $isPresented,
                            showsDismissButton: true,
                            page: .safety
                        )
                    } label: {
                        设置项目标签(
                            "安全限制",
                            systemImage: "exclamationmark.shield.fill",
                            color: .indigo
                        )
                    }

                    NavigationLink {
                        内容与安全限制(
                            isPresented: $isPresented,
                            showsDismissButton: true,
                            page: .spoilers
                        )
                    } label: {
                        设置项目标签(
                            "剧透内容",
                            systemImage: "eye.slash.fill",
                            color: .indigo
                        )
                    }

                    NavigationLink {
                        内容与安全限制(
                            isPresented: $isPresented,
                            showsDismissButton: true,
                            page: .ageAppropriate
                        )
                    } label: {
                        设置项目标签(
                            "适龄体验",
                            systemImage: "person.crop.circle.badge.checkmark",
                            color: .blue
                        )
                    }
                }
            } else if page == .safety {
                Section {
                    Toggle(
                        "安全限制",
                        isOn: allowsAdvancedControls
                            ? $contentFilterEnabled
                            : .constant(true)
                    )
                    .disabled(
                        !allowsAdvancedControls
                            || safetySettingsAreLocked
                    )

                    if contentFilterEnabled {
                        Picker("限制范围", selection: $filterMode) {
                            ForEach(内容过滤模式.allCases) { mode in
                                Text(verbatim: mode.localizedTitle)
                                    .tag(mode)
                            }
                        }
                        .disabled(safetySettingsAreLocked)

                        Picker("限制模式", selection: $contentRestrictionMethod) {
                            ForEach(内容限制方式.allCases) { method in
                                Text(verbatim: method.localizedTitle)
                                    .tag(method)
                            }
                        }
                        .disabled(safetySettingsAreLocked)

                        if filterMode == .sexualOnly || filterMode == .both {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("色情阈值")
                                    Spacer()
                                    Text(
                                        verbatim: String(
                                            format: "%.1f",
                                            sexualThreshold
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: $sexualThreshold,
                                    in: 0...sexualThresholdLimit,
                                    step: 0.1
                                ) {
                                    Text("色情阈值")
                                } minimumValueLabel: {
                                    Text("严格")
                                        .font(.caption2)
                                } maximumValueLabel: {
                                    Text("宽松")
                                        .font(.caption2)
                                }
                                .disabled(safetySettingsAreLocked)
                            }
                        }

                        if filterMode == .violenceOnly || filterMode == .both {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("暴力阈值")
                                    Spacer()
                                    Text(
                                        verbatim: String(
                                            format: "%.1f",
                                            violenceThreshold
                                        )
                                    )
                                    .foregroundStyle(.secondary)
                                }
                                Slider(
                                    value: $violenceThreshold,
                                    in: 0...2,
                                    step: 0.1
                                ) {
                                    Text("暴力阈值")
                                } minimumValueLabel: {
                                    Text("严格")
                                        .font(.caption2)
                                } maximumValueLabel: {
                                    Text("宽松")
                                        .font(.caption2)
                                }
                                .disabled(safetySettingsAreLocked)
                            }
                        }
                    }

                } header: {
                    Text("安全限制")
                } footer: {
                    Text("过滤不安全的视觉小说封面、角色、截屏与标签。安全阈值越高对相关内容的容忍度越高。")
                }

                Section {
                    Toggle(isOn: $emergencyAvoidanceEnabled) {
                        Text(emergencyAvoidanceTitle)
                    }
                    .disabled(emergencyAvoidance.isActive)
                } header: {
                    Text("紧急回避")
                } footer: {
                    if emergencyAvoidance.isActive {
                        Text("紧急回避已启用。退出App以恢复用户设置。")
                    }
                }
            } else if page == .spoilers {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("模糊剧透标签")
                            Spacer()
                            Text(verbatim: currentSpoilerSetting.localizedTitle)
                                .foregroundStyle(.secondary)
                        }

                        Slider(
                            value: spoilerSliderValue,
                            in: 0...2,
                            step: 1
                        ) {
                            Text("剧透模糊等级")
                        } minimumValueLabel: {
                            Text("严格")
                                .font(.caption2)
                        } maximumValueLabel: {
                            Text("宽松")
                                .font(.caption2)
                        }
                    }

                    Toggle("模糊评分", isOn: $blurAverageRating)
                    Toggle("模糊视觉小说简介", isOn: $blurDescription)
                } footer: {
                    Text("在“已游玩”或“抛弃”前模糊可能导致剧透的内容。剧透标签的模糊等级越低，对剧透标签的容忍度越高。")
                }
            } else {
                家长控制状态设置区()
            }
        }
        .平台分组列表样式()
        .navigationTitle(navigationTitle)
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .task {
            强制内容安全策略.应用到用户设置(token: auth.token)
        }
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
                }
            }
        }
    }
}
