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

    @State private var revealedTagIDs: Set<String> = []
    @Binding var showTranslatedText: Bool
    @Binding var translatedNames: [String: String]
    @State private var isTranslating = false
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?
    @State private var tagsContentOpacity = 1.0
    @State private var isSwitchingTranslation = false
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()

    init(
        tags: [视觉小说标签],
        spoilerUnlockedByProgress: Bool = false,
        showTranslatedText: Binding<Bool>,
        translatedNames: Binding<[String: String]>
    ) {
        self.tags = tags
        self.spoilerUnlockedByProgress = spoilerUnlockedByProgress
        _showTranslatedText = showTranslatedText
        _translatedNames = translatedNames
    }

    var body: some View {
        let visibleTags = tags.filter { !shouldHide($0) }

        ScrollView {
            if visibleTags.isEmpty {
                平台内容不可用视图("无标签", systemImage: "tag")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 72)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 20) {
                        categoryLegend(
                            title: "内容",
                            color: 视觉小说标签类别样式(category: "cont").color,
                            symbol: 视觉小说标签类别样式(category: "cont").systemImage
                        )
                        categoryLegend(
                            title: "色情",
                            color: 视觉小说标签类别样式(category: "ero").color,
                            symbol: 视觉小说标签类别样式(category: "ero").systemImage
                        )
                        categoryLegend(
                            title: "技术",
                            color: 视觉小说标签类别样式(category: "tech").color,
                            symbol: 视觉小说标签类别样式(category: "tech").systemImage
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                    FlowLayout(spacing: 10) {
                        ForEach(visibleTags, id: \.id) { tag in
                            let blurred = shouldBlur(tag)
                            translatedTagCapsule(tag)
                                .contentShape(Capsule())
                                .onTapGesture {
                                    guard blurred,
                                          内容安全限制判定.允许手动解除模糊(
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
                    }
                    .padding(.horizontal, 16)
                    .opacity(tagsContentOpacity)
                }
                .padding(.bottom, 32)
            }
        }
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
                            Image(systemName: "translate")
                                .font(.subheadline.weight(.medium))
                                .frame(width: 16, height: 16)
                        }
                    }
                    .disabled(isSwitchingTranslation)
                    .foregroundStyle(showTranslatedText ? .blue : .secondary)
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

    private func translatedTagCapsule(
        _ tag: 视觉小说标签
    ) -> some View {
        视觉小说标签胶囊(
            tag: tag,
            text: displayedName(for: tag),
            isBlurred: shouldBlur(tag),
            showsRating: true
        )
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

    private func categoryLegend(
        title: LocalizedStringKey,
        color: Color,
        symbol: String
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }
}

struct 更多特征页面: View {
    let traits: [角色特征]

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

    init(
        traits: [角色特征],
        showTranslatedTraits: Binding<Bool>
    ) {
        self.traits = traits
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
        .navigationTitle("特征（\(visibleTraits.count)个）")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            if targetLanguage.supportsAutomaticMetadataTranslation {
                ToolbarItem(placement: .平台主操作) {
                    Button {
                        toggleTranslation()
                    } label: {
                        Image(systemName: "translate")
                            .font(.subheadline.weight(.medium))
                            .frame(width: 16, height: 16)
                    }
                    .foregroundStyle(
                        showTranslatedTraits ? .blue : .secondary
                    )
                    .disabled(isSwitchingTranslation)
                    .accessibilityLabel(
                        showTranslatedTraits
                            ? "显示特征原文"
                            : "显示特征译文"
                    )
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

    private func traitCapsule(_ trait: 角色特征) -> some View {
        let blurred = shouldBlurTrait(trait)

        return traitCapsuleContent(
            name: displayedText(trait.name),
            groupName: displayedText(trait.group_name)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .blur(radius: blurred ? 5 : 0)
        .opacity(blurred ? 0.72 : 1)
        .contentShape(Capsule())
        .onTapGesture {
            guard blurred,
                  内容安全限制判定.允许手动解除模糊(
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
