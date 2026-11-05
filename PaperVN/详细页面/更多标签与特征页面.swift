import SwiftUI
@preconcurrency import Translation

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    struct Cache {
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for size in cache.sizes {
            if currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(
            width: proposal.width ?? currentX,
            height: currentY + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for (subview, size) in zip(subviews, cache.sizes) {
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct 更多标签页面: View {
    let tags: [视觉小说标签]
    /// 作品名称，结果页“+”菜单里那一组的标题用
    let 来源名称: String
    let spoilerUnlockedByProgress: Bool

    @Environment(\.详情内容限制方式覆盖)
    private var contentRestrictionMethodOverride
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("contentRestrictionMethod")
    private var storedContentRestrictionMethod: 内容限制方式 = .blurred

    private var contentRestrictionMethod: 内容限制方式 {
        contentRestrictionMethodOverride ?? storedContentRestrictionMethod
    }
    @AppStorage("spoilerTagBlurLevel")
    private var spoilerTagBlurLevel = 剧透标签模糊设置.majorOnly.rawValue
    @AppStorage("descriptionTranslationLanguage")
    private var targetLanguage: 简介翻译语言 = .simplifiedChinese

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var revealedTagIDs: Set<String> = []
    @Binding var showTranslatedText: Bool
    @Binding var translatedNames: [String: String]
    @State private var isTranslating = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?
    @State private var tagsContentOpacity = 1.0
    @State private var isSwitchingTranslation = false
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()
    @State private var 多选 = 标签多选()

    init(
        tags: [视觉小说标签],
        来源名称: String = "",
        spoilerUnlockedByProgress: Bool = false,
        showTranslatedText: Binding<Bool>,
        translatedNames: Binding<[String: String]>
    ) {
        self.tags = tags
        self.来源名称 = 来源名称
        self.spoilerUnlockedByProgress = spoilerUnlockedByProgress
        _showTranslatedText = showTranslatedText
        _translatedNames = translatedNames
    }

    /// 按内容、技术、色情分组，组内按权重排序。
    private var 分组列表: [(category: String, tags: [视觉小说标签])] {
        let visible = tags.filter { !shouldHide($0) }
        return ["cont", "tech", "ero"].compactMap { category in
            let group = visible
                .filter { ["tech", "ero"].contains($0.category ?? "") ? $0.category == category : category == "cont" }
                .sorted { $0.rating > $1.rating }
            return group.isEmpty ? nil : (category, group)
        }
    }

    var body: some View {
        let visibleTags = tags.filter { !shouldHide($0) }
        let groups = 分组列表

        平台滚动页面 {
            if visibleTags.isEmpty {
                平台内容不可用视图("无标签", systemImage: "tag")
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(groups, id: \.category) { group in
                    Section {
                        标签分栏(
                            items: group.tags,
                            id: \.id,
                            columns: 标签相关度行.列数(horizontalSizeClass)
                        ) { tag in
                            let blurred = shouldBlur(tag)
                            标签相关度行(
                                名称: displayedName(for: tag),
                                数值文本: String(format: "%.1f", tag.rating),
                                已模糊: blurred,
                                选中: 多选.正在选择 && !blurred ? 多选.选中(tag.id) : nil,
                                可轻点: true
                            )
                            .opacity(tagsContentOpacity)
                            .onTapGesture {
                                guard blurred else {
                                    withAnimation(.snappy(duration: 0.2)) {
                                        多选.轻点(浏览标签(tag), 对象: .视觉小说, 全部: 可筛选标签, 来源: 来源名称)
                                    }
                                    return
                                }
                                guard 内容安全限制判定.允许手动解除模糊(
                                        色情限制: isAdultTagRestricted(tag)
                                      ) else {
                                    return
                                }
                                blurRevealConfirmation.request(id: "all-tags") {
                                    withAnimation(.easeInOut(duration: 0.22)) {
                                        revealedTagIDs.formUnion(
                                            tags
                                                .filter {
                                                    内容安全限制判定.允许手动解除模糊(
                                                        色情限制: isAdultTagRestricted($0)
                                                    )
                                                }
                                                .map(\.id)
                                        )
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: 视觉小说标签类别样式(category: group.category).title)
                    }
                }
            }
        }
        .平台分组列表样式()
        .支持标签多选($多选, 对象: .视觉小说, 全部: 可筛选标签, 来源: 来源名称)
        .navigationTitle("标签（\(visibleTags.count)个）")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .平台主操作) {
                if hasTagsRequiringMachineTranslation {
                    Button {
                        toggleTranslation()
                    } label: {
                        if isTranslating {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 16, height: 16)
                        } else {
                            Label(
                                showTranslatedText
                                    ? "显示未人工翻译标签的原文"
                                    : "自动翻译没有人工译文的标签",
                                systemImage: "translate"
                            )
                            .font(.subheadline.weight(.medium))
                            .frame(width: 16, height: 16)
                        }
                    }
                    .disabled(isSwitchingTranslation)
                    .foregroundStyle(showTranslatedText ? Color.blue : .secondary)
                    .accessibilityLabel(
                        showTranslatedText
                            ? "显示未人工翻译标签的原文"
                            : "自动翻译没有人工译文的标签"
                    )
                }
            }
        }
        .task {
            if showTranslatedText {
                prepareTranslationIfNeeded()
            }
        }
        .translationTask(translationConfiguration) { session in
            await translateMissingTags(using: session)
        }
        .overlay(alignment: .bottom) {
            模糊解除提示(
                isPresented: blurRevealConfirmation.isPromptVisible
            )
            .padding(.bottom, 18)
        }
        .onDisappear {
            blurRevealConfirmation.cancel()
        }
        .alert(
            "无法翻译",
            isPresented: Binding(
                get: { translationError != nil },
                set: { if !$0 { translationError = nil } }
            )
        ) {
            Button("重试") {
                translationError = nil
                showTranslatedText = true
                prepareTranslationIfNeeded()
            }
            Button("取消", role: .cancel) {
                translationError = nil
            }
        } message: {
            Text(verbatim: translationError ?? "")
        }
    }

    private var spoilerSetting: 剧透标签模糊设置 {
        剧透标签模糊设置(rawValue: spoilerTagBlurLevel) ?? .majorOnly
    }

    /// 按页面上的顺序，没有隐藏或模糊的标签：结果页“+”菜单的候选。
    private var 可筛选标签: [标签浏览.标签] {
        分组列表.flatMap(\.tags).filter { !shouldBlur($0) }.map(浏览标签)
    }

    private func 浏览标签(_ tag: 视觉小说标签) -> 标签浏览.标签 {
        标签浏览.标签(值: tag.id, 名称: displayedName(for: tag))
    }

    private func shouldBlur(_ tag: 视觉小说标签) -> Bool {
        guard !shouldHide(tag),
              !revealedTagIDs.contains(tag.id) else {
            return false
        }

        let spoilerHidden =
            !spoilerUnlockedByProgress &&
            spoilerSetting.shouldBlur(spoilerLevel: tag.spoiler)
        let adultBlurred = isAdultTagRestricted(tag)
            && contentRestrictionMethod == .blurred

        return spoilerHidden || adultBlurred
    }

    private func shouldHide(_ tag: 视觉小说标签) -> Bool {
        isAdultTagRestricted(tag) && contentRestrictionMethod == .hidden
    }

    private func isAdultTagRestricted(_ tag: 视觉小说标签) -> Bool {
        内容安全限制判定.色情标签需要限制(
            tag.isAdultContent,
            enabled: contentFilterEnabled,
            mode: filterMode
        )
    }

    private var hasTagsRequiringMachineTranslation: Bool {
        targetLanguage.supportsAutomaticMetadataTranslation
            && tags.contains { VNDB标签人工翻译.界面译文(for: $0) == nil }
    }

    private func displayedName(for tag: 视觉小说标签) -> String {
        if let manual = VNDB标签人工翻译.界面译文(for: tag) {
            return manual
        }

        guard showTranslatedText else { return tag.name }
        return translatedNames[tag.id] ?? tag.name
    }

    private func toggleTranslation() {
        guard !isSwitchingTranslation else { return }
        let targetValue = !showTranslatedText
        isSwitchingTranslation = true

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.14)) {
                tagsContentOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.14))
            showTranslatedText = targetValue
            if targetValue {
                prepareTranslationIfNeeded()
            }
            withAnimation(.easeIn(duration: 0.18)) {
                tagsContentOpacity = 1
            }
            isSwitchingTranslation = false
        }
    }

    private func prepareTranslationIfNeeded() {
        let missing = tags.filter {
            VNDB标签人工翻译.界面译文(for: $0) == nil
                && translatedNames[$0.id] == nil
        }

        guard !missing.isEmpty else { return }

        if var configuration = translationConfiguration {
            configuration.source = Locale.Language(identifier: "en")
            configuration.target = targetLanguage.localeLanguage
            configuration.invalidate()
            translationConfiguration = configuration
        } else {
            translationConfiguration = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: targetLanguage.localeLanguage
            )
        }
    }

    private func translateMissingTags(using session: TranslationSession) async {
        let missing = tags.filter {
            VNDB标签人工翻译.界面译文(for: $0) == nil
                && translatedNames[$0.id] == nil
        }

        guard !missing.isEmpty else { return }

        await MainActor.run {
            isTranslating = true
            translationError = nil
        }

        let requestInputs = missing.map { ($0.name, $0.id) }
        let requests = await Task.detached {
            requestInputs.map { sourceText, clientIdentifier in
                TranslationSession.Request(
                    sourceText: sourceText,
                    clientIdentifier: clientIdentifier
                )
            }
        }.value

        do {
            let responses = try await session.translations(from: requests)
            let values = responses.reduce(into: [String: String]()) { result, response in
                if let id = response.clientIdentifier {
                    result[id] = response.targetText
                }
            }

            await applyTranslatedNames(values)
        } catch is CancellationError {
            await MainActor.run {
                isTranslating = false
                showTranslatedText = false
            }
        } catch {
            await MainActor.run {
                isTranslating = false
                showTranslatedText = false
                translationError = (error as? CocoaError)?.code == .userCancelled
                    ? nil
                    : error.localizedDescription
            }
        }
    }

    @MainActor
    private func applyTranslatedNames(
        _ values: [String: String]
    ) async {
        if showTranslatedText {
            withAnimation(.easeOut(duration: 0.14)) {
                tagsContentOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.14))
        }

        translatedNames.merge(values) { _, new in new }
        isTranslating = false

        if showTranslatedText {
            withAnimation(.easeIn(duration: 0.18)) {
                tagsContentOpacity = 1
            }
        }
    }
}

struct 更多特征页面: View {
    let traits: [角色特征]
    /// 角色名称，结果页“+”菜单里那一组的标题用
    let 来源名称: String

    @Environment(\.详情内容限制方式覆盖)
    private var contentRestrictionMethodOverride
    @AppStorage("contentFilterEnabled")
    private var contentFilterEnabled = false
    @AppStorage("filterMode")
    private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var storedContentRestrictionMethod: 内容限制方式 = .blurred

    private var contentRestrictionMethod: 内容限制方式 {
        contentRestrictionMethodOverride ?? storedContentRestrictionMethod
    }
    @AppStorage("spoilerTagBlurLevel")
    private var spoilerTagBlurLevel = 剧透标签模糊设置.majorOnly.rawValue
    @AppStorage("descriptionTranslationLanguage")
    private var targetLanguage: 简介翻译语言 = .simplifiedChinese

    @State private var revealedTraitIDs: Set<String> = []
    @Binding var showTranslatedTraits: Bool
    @State private var traitsContentOpacity = 1.0
    @State private var isSwitchingTranslation = false
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()
    @State private var 多选 = 标签多选()

    init(
        traits: [角色特征],
        来源名称: String = "",
        showTranslatedTraits: Binding<Bool>
    ) {
        self.traits = traits
        self.来源名称 = 来源名称
        _showTranslatedTraits = showTranslatedTraits
    }

    var body: some View {
        let visibleTraits = traits.filter { !shouldHideTrait($0) }

        ScrollView {
            if visibleTraits.isEmpty {
                平台内容不可用视图("无特征", systemImage: "person.text.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 72)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(visibleTraits, id: \.id) { trait in
                        traitCapsule(trait)
                    }
                }
                .opacity(traitsContentOpacity)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .支持标签多选($多选, 对象: .角色, 全部: 可筛选特征, 来源: 来源名称)
        .navigationTitle("特征（\(visibleTraits.count)个）")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if targetLanguage.supportsAutomaticMetadataTranslation {
                ToolbarItem(placement: .平台主操作) {
                    Button {
                        toggleTranslation()
                    } label: {
                        Label(
                            showTranslatedTraits
                                ? "显示特征原文"
                                : "显示特征译文",
                            systemImage: "translate"
                        )
                        .font(.subheadline.weight(.medium))
                        .frame(width: 16, height: 16)
                    }
                    .foregroundStyle(
                        showTranslatedTraits ? Color.blue : .secondary
                    )
                    .disabled(isSwitchingTranslation)
                }
            }
        }
        .overlay(alignment: .bottom) {
            模糊解除提示(
                isPresented: blurRevealConfirmation.isPromptVisible
            )
            .padding(.bottom, 18)
        }
        .onDisappear {
            blurRevealConfirmation.cancel()
        }
    }

    private func toggleTranslation() {
        guard !isSwitchingTranslation else { return }
        let targetValue = !showTranslatedTraits
        isSwitchingTranslation = true

        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.14)) {
                traitsContentOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.14))
            showTranslatedTraits = targetValue
            withAnimation(.easeIn(duration: 0.18)) {
                traitsContentOpacity = 1
            }
            isSwitchingTranslation = false
        }
    }

    /// 按页面上的顺序，没有隐藏或模糊的特征：结果页“+”菜单的候选。
    private var 可筛选特征: [标签浏览.标签] {
        traits.filter { !shouldHideTrait($0) && !shouldBlurTrait($0) }.map(浏览特征)
    }

    private func 浏览特征(_ trait: 角色特征) -> 标签浏览.标签 {
        .特征(值: trait.id, 名称: displayedText(trait.name), 分组: displayedText(trait.group_name))
    }

    private func traitCapsule(_ trait: 角色特征) -> some View {
        let blurred = shouldBlurTrait(trait)
        let 选中: Bool? = 多选.正在选择 && !blurred ? 多选.选中(trait.id) : nil

        return traitCapsuleContent(
            name: displayedText(trait.name),
            groupName: displayedText(trait.group_name)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            选中 == true ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(Color.secondary.opacity(0.12)),
            in: Capsule()
        )
        // 勾选圈压在胶囊右上角，不占胶囊里的位置：进入勾选时胶囊不会变宽、整页不会重新排列
        .overlay(alignment: .topTrailing) {
            if let 选中 {
                Image(systemName: 选中 ? "checkmark.circle.fill" : "circle")
                    .font(.subheadline)
                    .foregroundStyle(选中 ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .background(Circle().fill(.background))
                    .offset(x: 4, y: -4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .blur(radius: blurred ? 5 : 0)
        .opacity(blurred ? 0.72 : 1)
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(blurred ? [] : .isButton)
        .accessibilityAddTraits(选中 == true ? .isSelected : [])
        .onTapGesture {
            guard blurred else {
                withAnimation(.snappy(duration: 0.2)) {
                    多选.轻点(浏览特征(trait), 对象: .角色, 全部: 可筛选特征, 来源: 来源名称)
                }
                return
            }
            guard 内容安全限制判定.允许手动解除模糊(
                    色情限制: isAdultTraitRestricted(trait)
                  ) else {
                return
            }
            blurRevealConfirmation.request(id: "all-traits") {
                withAnimation(.easeInOut(duration: 0.22)) {
                    revealedTraitIDs.formUnion(
                        traits
                            .filter {
                                内容安全限制判定.允许手动解除模糊(
                                    色情限制: isAdultTraitRestricted($0)
                                )
                            }
                            .map(\.id)
                    )
                }
            }
        }
    }

    private func traitCapsuleContent(
        name: String,
        groupName: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: name)
                .font(.caption.weight(.medium))
            Text(verbatim: groupName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func displayedText(_ source: String) -> String {
        if let manual = VNDB特征人工翻译.界面译文(source) {
            return manual
        }
        guard showTranslatedTraits else { return source }
        return VNDB特征人工翻译.译文(
            source,
            target: targetLanguage
        ) ?? source
    }

    private func shouldBlurTrait(_ trait: 角色特征) -> Bool {
        guard !shouldHideTrait(trait),
              !revealedTraitIDs.contains(trait.id) else {
            return false
        }
        let spoilerSetting =
            剧透标签模糊设置(rawValue: spoilerTagBlurLevel) ?? .majorOnly
        let spoilerHidden = spoilerSetting.shouldBlur(
            spoilerLevel: trait.spoiler
        )
        let adultBlurred = isAdultTraitRestricted(trait)
            && contentRestrictionMethod == .blurred
        return spoilerHidden || adultBlurred
    }

    private func shouldHideTrait(_ trait: 角色特征) -> Bool {
        isAdultTraitRestricted(trait) && contentRestrictionMethod == .hidden
    }

    private func isAdultTraitRestricted(_ trait: 角色特征) -> Bool {
        内容安全限制判定.色情特征需要限制(
            trait.sexual,
            enabled: contentFilterEnabled,
            mode: filterMode
        )
    }
}

/// 全部标签页面的一格：名称在左、相关度数值在右；剧透或色情限制时模糊。由 `标签分栏` 排成多列并在行间画分隔线，动画、漫画、轻小说与视觉小说共用。
struct 标签相关度行: View {
    /// iPhone 两列，iPad 等宽屏三列。
    static func 列数(_ sizeClass: UserInterfaceSizeClass?) -> Int {
        sizeClass == .regular ? 3 : 2
    }

    let 名称: String
    var 数值文本: String? = nil
    var 已模糊 = false
    /// 正在选择时是否勾选；不在选择（或这个标签不能选）时为 nil，不显示勾选圈
    var 选中: Bool? = nil
    /// 轻点会进入按此标签筛选的列表（读屏时是按钮）
    var 可轻点 = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: 名称)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if 数值文本 != nil || 可轻点 {
                // 数值和勾选圈叠在同一个位置，宽度一直取两者中较宽的：进入勾选时名称不会重新换行
                ZStack(alignment: .trailing) {
                    Text(verbatim: 数值文本 ?? "")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .opacity(选中 == nil ? 1 : 0)
                    Image(systemName: 选中 == true ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(选中 == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .opacity(选中 == nil ? 0 : 1)
                        .scaleEffect(选中 == nil ? 0.6 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        .compositingGroup()
        .blur(radius: 已模糊 ? 5 : 0)
        .opacity(已模糊 ? 0.72 : 1)
        .animation(.easeInOut(duration: 0.28), value: 已模糊)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(已模糊 ? Text("内容已隐藏") : Text(verbatim: 名称))
        .accessibilityValue(已模糊 ? Text(verbatim: "") : Text(verbatim: 数值文本 ?? ""))
        .accessibilityAddTraits(可轻点 && !已模糊 ? .isButton : [])
        .accessibilityAddTraits(选中 == true ? .isSelected : [])
    }
}

/// 把标签按列数分行排列，行与行之间每列各画一条分隔线；同一行的格子垂直居中，有标签换成两行时整行一起变高。
struct 标签分栏<Item, ID: Hashable, Cell: View>: View {
    let items: [Item]
    let id: KeyPath<Item, ID>
    let columns: Int
    @ViewBuilder let cell: (Item) -> Cell

    private var rows: [[Item]] {
        stride(from: 0, to: items.count, by: columns).map {
            Array(items[$0..<min($0 + columns, items.count)])
        }
    }

    var body: some View {
        let rows = rows
        // 不用 Grid：Grid 按单行的理想高度定行高，标签换成两行时会被压扁
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                if rowIndex > 0 {
                    HStack(spacing: 20) {
                        ForEach(0..<columns, id: \.self) { _ in
                            // 放在 HStack 里的 Divider 是竖线，包一层 VStack 才是横线
                            VStack { Divider() }
                        }
                    }
                }

                HStack(alignment: .center, spacing: 20) {
                    ForEach(rows[rowIndex], id: id) { item in
                        cell(item)
                    }
                    ForEach(0..<(columns - rows[rowIndex].count), id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
                // 第一行上方、最后一行下方只留列表本身的边距
                .padding(.top, rowIndex == 0 ? 0 : 11)
                .padding(.bottom, rowIndex == rows.count - 1 ? 0 : 11)
            }
        }
    }
}
