import Foundation
import SwiftUI

/// 当前语言的月份名称，例如“10月”“October”
private func 月份名称(_ month: Int) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = .current
    let symbols = calendar.standaloneMonthSymbols
    return symbols.indices.contains(month - 1) ? symbols[month - 1] : "\(month)"
}

private struct 筛选句子选项布局值: nonisolated LayoutValueKey {
    nonisolated static let defaultValue = false
}

/// 筛选规则句子的组成部分。句子以整句本地化模板给出，其中%1$@是显示方式菜单、%2$@是匹配方式菜单，
/// 拆分后各语言可以保留自己的语序。
private enum 筛选句子片段: Hashable {
    case 文本(String)
    case 显示方式
    case 匹配方式
    case 筛选对象

    static func 拆分(_ template: String) -> [筛选句子片段] {
        var result: [筛选句子片段] = []
        var remaining = Substring(template)
        while let range = remaining.range(of: #"%[123]\$@"#, options: .regularExpression) {
            appendText(remaining[..<range.lowerBound], to: &result)
            switch remaining[range] {
            case "%1$@": result.append(.显示方式)
            case "%2$@": result.append(.匹配方式)
            default: result.append(.筛选对象)
            }
            remaining = remaining[range.upperBound...]
        }
        appendText(remaining, to: &result)
        return result
    }

    /// 按词切分文本，让以空格分词的语言可以在词间换行
    private static func appendText(_ text: Substring, to result: inout [筛选句子片段]) {
        var token = ""
        for character in text {
            if !character.isWhitespace, token.last?.isWhitespace == true {
                result.append(.文本(token))
                token = ""
            }
            token.append(character)
        }
        if !token.isEmpty {
            result.append(.文本(token))
        }
    }
}

private struct 筛选句子布局: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        arrangement(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrangement(
            proposal: ProposedViewSize(width: bounds.width, height: nil),
            subviews: subviews
        )
        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func arrangement(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint], sizes: [CGSize]) {
        let availableWidth = proposal.width ?? .infinity
        let dimensions = subviews.map {
            $0.dimensions(in: .unspecified)
        }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let referenceIndex = subviews.indices.first { index in
            let baseline = dimensions[index][.firstTextBaseline]
            return !subviews[index][筛选句子选项布局值.self]
                && baseline.isFinite
                && baseline > 0
                && baseline < sizes[index].height
        }
        let baselines = dimensions.enumerated().map { index, viewDimensions in
            let baseline = viewDimensions[.firstTextBaseline]
            if baseline.isFinite,
               baseline > 0,
               baseline < sizes[index].height {
                return baseline
            }
            if subviews[index][筛选句子选项布局值.self],
               let referenceIndex {
                let referenceBaseline = self.dimensionsBaseline(
                    dimensions: dimensions[referenceIndex],
                    fallbackHeight: sizes[referenceIndex].height
                )
                return (sizes[index].height - sizes[referenceIndex].height) / 2
                    + referenceBaseline
            }
            return sizes[index].height / 2
        }
        var positions = Array(repeating: CGPoint.zero, count: subviews.count)
        var lineIndices: [Int] = []
        var lineWidth: CGFloat = 0
        var lineAscent: CGFloat = 0
        var lineDescent: CGFloat = 0
        var maximumLineWidth: CGFloat = 0
        var y: CGFloat = 0

        func finishLine() {
            guard !lineIndices.isEmpty else { return }
            for index in lineIndices {
                positions[index].y = y + lineAscent - baselines[index]
            }
            maximumLineWidth = max(maximumLineWidth, lineWidth)
            y += lineAscent + lineDescent + verticalSpacing
            lineIndices.removeAll(keepingCapacity: true)
            lineWidth = 0
            lineAscent = 0
            lineDescent = 0
        }

        for index in subviews.indices {
            let size = sizes[index]
            let proposedX = lineIndices.isEmpty
                ? 0
                : lineWidth + horizontalSpacing
            if !lineIndices.isEmpty,
               proposedX + size.width > availableWidth {
                finishLine()
            }

            let x = lineIndices.isEmpty
                ? 0
                : lineWidth + horizontalSpacing
            positions[index].x = x
            lineIndices.append(index)
            lineWidth = x + size.width
            lineAscent = max(lineAscent, baselines[index])
            lineDescent = max(
                lineDescent,
                size.height - baselines[index]
            )
        }
        finishLine()

        let height = max(0, y - verticalSpacing)
        return (
            CGSize(
                width: proposal.width ?? maximumLineWidth,
                height: height
            ),
            positions,
            sizes
        )
    }

    private func dimensionsBaseline(
        dimensions: ViewDimensions,
        fallbackHeight: CGFloat
    ) -> CGFloat {
        let baseline = dimensions[.firstTextBaseline]
        return baseline.isFinite
            && baseline > 0
            && baseline < fallbackHeight
            ? baseline
            : fallbackHeight / 2
    }
}

private struct 篇幅筛选选项: Identifiable {
    let id: Int
    let title: String
    let duration: String

    static let all = [
        篇幅筛选选项(
            id: 1,
            title: String(localized: "超短篇"),
            duration: String(localized: "小于约2小时")
        ),
        篇幅筛选选项(
            id: 2,
            title: String(localized: "短篇"),
            duration: String(localized: "约2～10小时")
        ),
        篇幅筛选选项(
            id: 3,
            title: String(localized: "中篇"),
            duration: String(localized: "约10～30小时")
        ),
        篇幅筛选选项(
            id: 4,
            title: String(localized: "长篇"),
            duration: String(localized: "约30～50小时")
        ),
        篇幅筛选选项(
            id: 5,
            title: String(localized: "超长篇"),
            duration: String(localized: "大于约50小时")
        )
    ]
}

private struct 筛选条件编辑上下文: Identifiable {
    let ruleID: UUID
    let condition: 视觉小说筛选条件
    let isNew: Bool

    var id: UUID { condition.id }
}

private struct 搜索扩展筛选条件编辑上下文: Identifiable {
    var scope: 搜索范围 = .character
    let ruleID: UUID
    let condition: 搜索扩展筛选条件
    let isNew: Bool

    var id: UUID { condition.id }
}

private struct 筛选冲突提示: Identifiable {
    let id = UUID()
    let message: String
}

private func 筛选冲突说明(_ conflict: 视觉小说筛选冲突) -> String {
    let ruleNumbers = conflict.ruleIndices
        .map { String($0 + 1) }
    let localizedRuleNumbers = ListFormatter.localizedString(
        byJoining: ruleNumbers
    )
    let format = String(
        localized: "筛选条件%@中的设置互相冲突。请调整其中一项。"
    )
    return String.localizedStringWithFormat(format, localizedRuleNumbers)
}

private func 搜索筛选标签显示名称(_ option: VNDB筛选选项) -> String {
    let tag = 视觉小说标签(
        id: option.code,
        name: option.name,
        rating: 0,
        spoiler: 0,
        lie: nil,
        category: nil
    )
    return VNDB标签人工翻译.界面译文(for: tag) ?? option.name
}

/// 综合搜索的筛选：每个筛选条件组都可以选择筛选的对象（视觉小说、角色、发行版本、制作人员、
/// 开发与发行商）。发行版本的条件通过作品生效（作品至少有一个发行版本满足）。
struct 综合搜索筛选页面: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: 视觉小说搜索筛选
    @Binding var characterFilters: 搜索扩展筛选
    @Binding var staffFilters: 搜索扩展筛选
    @Binding var producerFilters: 搜索扩展筛选
    let onApply: () -> Void

    @State private var catalog = VNDB搜索筛选目录.builtIn
    @State private var editingCondition: 筛选条件编辑上下文?
    @State private var editingExtendedCondition: 搜索扩展筛选条件编辑上下文?
    @State private var conflictAlert: 筛选冲突提示?
    @State private var isLoadingTags = true
    @State private var isLoadingTraits = true

    init(
        visualNovelFilters: Binding<视觉小说搜索筛选>,
        characterFilters: Binding<搜索扩展筛选>,
        staffFilters: Binding<搜索扩展筛选>,
        producerFilters: Binding<搜索扩展筛选>,
        onApply: @escaping () -> Void
    ) {
        _filters = visualNovelFilters
        _characterFilters = characterFilters
        _staffFilters = staffFilters
        _producerFilters = producerFilters
        self.onApply = onApply
    }

    private static let 扩展筛选对象: [搜索范围] = [.release, .character, .staff, .producer]

    private func 扩展筛选(_ scope: 搜索范围) -> Binding<搜索扩展筛选> {
        switch scope {
        case .release: return $filters.发行版本规则
        case .character: return $characterFilters
        case .staff: return $staffFilters
        case .producer: return $producerFilters
        case .visualNovel: return .constant(.init())
        }
    }

    private var 没有任何规则: Bool {
        filters.rules.isEmpty && Self.扩展筛选对象.allSatisfy { 扩展筛选($0).wrappedValue.rules.isEmpty }
    }

    var body: some View {
        let conflict = VNDB筛选冲突检测器.conflict(in: filters)

        平台滚动页面 {
            ForEach($filters.rules) { $rule in
                ruleSection(rule: $rule, conflict: conflict)
            }

            ForEach(Self.扩展筛选对象, id: \.self) { scope in
                let 起始序号 = 扩展规则起始序号(scope)
                ForEach(Array(扩展筛选(scope).rules.enumerated()), id: \.element.id) { 序号, $rule in
                    扩展筛选规则分区(
                        scope: scope,
                        rule: $rule,
                        序号: 起始序号 + 序号,
                        catalog: catalog,
                        筛选对象菜单: AnyView(筛选对象菜单(ruleID: rule.id, current: scope)),
                        编辑条件: { condition, isNew in
                            editingExtendedCondition = 搜索扩展筛选条件编辑上下文(
                                scope: scope, ruleID: rule.id, condition: condition, isNew: isNew
                            )
                        },
                        删除规则: {
                            withAnimation {
                                扩展筛选(scope).wrappedValue.rules.removeAll { $0.id == rule.id }
                            }
                        }
                    )
                }
            }

            Section {
                addRuleButton
            }
        }
        .平台分组列表样式()
        .navigationTitle("筛选")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("取消")
            }

            ToolbarItem(placement: .平台主操作) {
                Menu {
                    Button(role: .destructive) {
                        withAnimation {
                            filters.rules.removeAll()
                            for scope in Self.扩展筛选对象 {
                                扩展筛选(scope).wrappedValue.rules.removeAll()
                            }
                        }
                    } label: {
                        Label("清除所有条件", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多")
                .disabled(没有任何规则)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    applyFilters()
                } label: {
                    Image(systemName: "checkmark")
                }
                .液态玻璃醒目按钮(in: Circle())
                .accessibilityLabel("完成")
            }
        }
        .sheet(item: $editingCondition) { context in
            NavigationStack {
                视觉小说筛选条件编辑页面(
                    initialCondition: context.condition,
                    catalog: $catalog,
                    isLoadingTags: $isLoadingTags,
                    validate: { condition in
                        VNDB筛选冲突检测器.conflict(
                            afterSetting: condition,
                            inRule: context.ruleID,
                            filters: filters
                        )
                    },
                    onSave: { condition in
                        saveCondition(
                            condition,
                            ruleID: context.ruleID,
                            isNew: context.isNew
                        )
                    }
                )
            }
            .平台近全屏弹窗(dragIndicator: .visible)
        }
        .sheet(item: $editingExtendedCondition) { context in
            NavigationStack {
                搜索扩展筛选条件编辑页面(
                    scope: context.scope,
                    initialCondition: context.condition,
                    catalog: $catalog,
                    isLoadingTraits: $isLoadingTraits,
                    onSave: { condition in
                        保存扩展条件(condition, context: context)
                    }
                )
            }
            .平台近全屏弹窗(dragIndicator: .visible)
        }
        .alert(item: $conflictAlert) { prompt in
            Alert(
                title: Text("筛选条件冲突"),
                message: Text(verbatim: prompt.message),
                dismissButton: .default(Text("好"))
            )
        }
        .task {
            let taxonomyService = VNDB探索服务.shared
            if let cachedTags = taxonomyService.已缓存标签目录() {
                mergeTags(cachedTags)
            }

            if let cachedTraits = taxonomyService.已缓存特征目录() {
                mergeTraits(cachedTraits)
            }

            async let loadedCatalog = try? await VNDB服务.shared.获取搜索筛选目录()
            async let loadedTags = try? await taxonomyService.所有标签(
                强制刷新: true
            )
            async let loadedTraits = try? await taxonomyService.所有特征(
                强制刷新: true
            )
            let tags = await loadedTags
            if let tags {
                mergeTags(tags)
            }
            isLoadingTags = false
            if let traits = await loadedTraits {
                mergeTraits(traits)
            }
            isLoadingTraits = false
            if let baseCatalog = await loadedCatalog {
                catalog = catalog.merging(baseCatalog)
            }
        }
    }

    private func mergeTraits(_ traits: [探索特征]) {
        let options = traits.map {
            VNDB筛选选项(code: $0.id, name: $0.name)
        }
        guard options != catalog.traits else { return }
        catalog = catalog.merging(
            VNDB搜索筛选目录(
                languages: [],
                platforms: [],
                traits: options
            )
        )
    }

    /// 视觉小说条件组之后，按发行版本、角色、制作人员、会社的顺序接着编号。
    private func 扩展规则起始序号(_ scope: 搜索范围) -> Int {
        var 序号 = filters.rules.count + 1
        for item in Self.扩展筛选对象 {
            if item == scope { break }
            序号 += 扩展筛选(item).wrappedValue.rules.count
        }
        return 序号
    }

    /// 句子里的筛选对象（“……条件的视觉小说”）：改成别的对象时，这组条件移到新对象下，
    /// 保留显示方式和匹配方式；原有的筛选项各对象不通用，清空后重新添加。
    private func 筛选对象菜单(ruleID: UUID, current: 搜索范围) -> some View {
        Menu {
            Picker("筛选对象", selection: Binding(
                get: { current },
                set: { 改变筛选对象(ruleID: ruleID, from: current, to: $0) }
            )) {
                ForEach(搜索范围.allCases) { scope in
                    Label(scope.localizedTitle, systemImage: scope.systemImage).tag(scope)
                }
            }
        } label: {
            sentenceChoiceLabel(current.localizedTitle)
        }
        .fixedSize()
        .layoutValue(key: 筛选句子选项布局值.self, value: true)
        .accessibilityLabel("筛选对象")
        .accessibilityValue(Text(verbatim: current.localizedTitle))
    }

    private func 改变筛选对象(ruleID: UUID, from: 搜索范围, to: 搜索范围) {
        guard from != to else { return }
        var matchMode = 视觉小说筛选匹配方式.all
        var isExcluded = false
        var 位置: Int?
        if from == .visualNovel {
            位置 = filters.rules.firstIndex { $0.id == ruleID }
            if let 位置 {
                matchMode = filters.rules[位置].matchMode
                isExcluded = filters.rules[位置].isExcluded
            }
        } else {
            位置 = 扩展筛选(from).wrappedValue.rules.firstIndex { $0.id == ruleID }
            if let 位置 {
                let rule = 扩展筛选(from).wrappedValue.rules[位置]
                matchMode = rule.matchMode
                isExcluded = rule.isExcluded
            }
        }
        guard let 位置 else { return }
        withAnimation {
            if from == .visualNovel {
                filters.rules.remove(at: 位置)
            } else {
                扩展筛选(from).wrappedValue.rules.remove(at: 位置)
            }
            if to == .visualNovel {
                filters.rules.append(视觉小说筛选规则组(matchMode: matchMode, isExcluded: isExcluded))
            } else {
                扩展筛选(to).wrappedValue.rules.append(
                    搜索扩展筛选规则组(matchMode: matchMode, isExcluded: isExcluded)
                )
            }
        }
    }

    private func 保存扩展条件(_ condition: 搜索扩展筛选条件, context: 搜索扩展筛选条件编辑上下文) {
        let 筛选 = 扩展筛选(context.scope)
        guard let index = 筛选.wrappedValue.rules.firstIndex(where: { $0.id == context.ruleID }) else { return }
        if context.isNew {
            筛选.wrappedValue.rules[index].conditions.append(condition)
        } else if let conditionIndex = 筛选.wrappedValue.rules[index].conditions.firstIndex(where: { $0.id == condition.id }) {
            筛选.wrappedValue.rules[index].conditions[conditionIndex] = condition
        }
    }

    private func mergeTags(_ tags: [探索标签]) {
        let options = tags.map {
            VNDB筛选选项(code: $0.id, name: $0.name)
        }
        guard options != catalog.tags else { return }
        catalog = catalog.merging(
            VNDB搜索筛选目录(
                languages: [],
                platforms: [],
                tags: options
            )
        )
    }

    @ViewBuilder
    private func ruleSection(
        rule: Binding<视觉小说筛选规则组>,
        conflict: 视觉小说筛选冲突?
    ) -> some View {
        let ruleID = rule.wrappedValue.id
        let ruleIndex = filters.rules.firstIndex { $0.id == ruleID }
        let ruleNumber = (ruleIndex ?? 0) + 1
        let isConflicting = ruleIndex.map {
            conflict?.ruleIndices.contains($0) == true
        } ?? false

        Section {
            ruleSentence(for: rule)

            ForEach(rule.wrappedValue.conditions) { condition in
                conditionRow(condition) {
                    editingCondition = 筛选条件编辑上下文(
                        ruleID: ruleID,
                        condition: condition,
                        isNew: false
                    )
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        removeCondition(condition.id, from: ruleID)
                    } label: {
                        Label("删除筛选项", systemImage: "trash")
                    }
                }
            }

            addConditionMenu(for: rule.wrappedValue)
        } header: {
            HStack {
                Label {
                    Text(
                        verbatim: "\(String(localized: "筛选条件"))\(ruleNumber)"
                    )
                } icon: {
                    Image(
                        systemName: isConflicting
                            ? "exclamationmark.triangle.fill"
                            : "line.3.horizontal.decrease.circle"
                    )
                }
                .foregroundStyle(isConflicting ? .red : .secondary)
                Spacer()
                Button(role: .destructive) {
                    withAnimation {
                        filters.rules.removeAll { $0.id == ruleID }
                    }
                } label: {
                    Image(systemName: "trash")
                        .imageScale(.small)
                        .frame(width: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除筛选条件")
            }
            .textCase(nil)
        } footer: {
            if isConflicting {
                Text("此筛选条件中的设置互相冲突。")
                    .foregroundStyle(.red)
                    .textCase(nil)
            }
        }
    }

    private var addRuleButton: some View {
        Button {
            addRule()
        } label: {
            Label("添加筛选条件", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("search.filter.addRule")
    }

    private func addConditionMenu(
        for rule: 视觉小说筛选规则组
    ) -> some View {
        Menu {
            ForEach(视觉小说筛选字段.availableFields) { field in
                Button {
                    editingCondition = 筛选条件编辑上下文(
                        ruleID: rule.id,
                        condition: 视觉小说筛选条件(field: field),
                        isNew: true
                    )
                } label: {
                    Label(
                        field.localizedTitle,
                        systemImage: field.systemImage
                    )
                }
                .disabled(rule.conditions.contains { $0.field == field })
            }
        } label: {
            Label("添加筛选项", systemImage: "plus")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("search.filter.rule.\(rule.id).addCondition")
    }

    private func conditionRow(
        _ condition: 视觉小说筛选条件,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: condition.field.systemImage)
                    .foregroundStyle(.tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: condition.field.localizedTitle)
                        .foregroundStyle(.primary)
                    Text(verbatim: conditionSummary(condition))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            "search.filter.condition.\(condition.field.rawValue)"
        )
    }

    private func addRule() {
        withAnimation {
            filters.rules.append(视觉小说筛选规则组())
        }
    }

    @ViewBuilder
    private func ruleSentence(
        for rule: Binding<视觉小说筛选规则组>
    ) -> some View {
        筛选句子布局(horizontalSpacing: 0, verticalSpacing: 6) {
            let parts = 筛选句子片段.拆分(String(localized: "%1$@满足以下%2$@条件的%3$@。"))
            ForEach(parts.indices, id: \.self) { index in
                switch parts[index] {
                case .文本(let text):
                    Text(verbatim: text)
                case .显示方式:
                    exclusionMenu(for: rule)
                case .匹配方式:
                    matchModeMenu(for: rule)
                case .筛选对象:
                    筛选对象菜单(ruleID: rule.wrappedValue.id, current: .visualNovel)
                }
            }
        }
        .font(.body)
        .accessibilityIdentifier(
            "search.filter.rule.\(rule.wrappedValue.id).mode"
        )
    }

    private func exclusionMenu(
        for rule: Binding<视觉小说筛选规则组>
    ) -> some View {
        let title = rule.wrappedValue.isExcluded
            ? String(localized: "排除")
            : String(localized: "显示")

        return Menu {
            Picker("显示方式", selection: exclusionBinding(for: rule)) {
                Text("显示").tag(false)
                Text("排除").tag(true)
            }
        } label: {
            sentenceChoiceLabel(title)
        }
        .fixedSize()
        .layoutValue(key: 筛选句子选项布局值.self, value: true)
        .accessibilityLabel("显示方式")
        .accessibilityValue(Text(verbatim: title))
    }

    private func matchModeMenu(
        for rule: Binding<视觉小说筛选规则组>
    ) -> some View {
        let title = rule.wrappedValue.matchMode == .all
            ? String(localized: "所有")
            : String(localized: "任一")

        return Menu {
            Picker("匹配条件", selection: matchModeBinding(for: rule)) {
                Text("所有").tag(视觉小说筛选匹配方式.all)
                Text("任一").tag(视觉小说筛选匹配方式.any)
            }
        } label: {
            sentenceChoiceLabel(title)
        }
        .fixedSize()
        .layoutValue(key: 筛选句子选项布局值.self, value: true)
        .accessibilityLabel("匹配条件")
        .accessibilityValue(Text(verbatim: title))
    }

    private func sentenceChoiceLabel(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: title)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .foregroundStyle(.tint)
    }

    private func exclusionBinding(
        for rule: Binding<视觉小说筛选规则组>
    ) -> Binding<Bool> {
        Binding(
            get: { rule.wrappedValue.isExcluded },
            set: { isExcluded in
                setRuleMode(
                    matchMode: rule.wrappedValue.matchMode,
                    isExcluded: isExcluded,
                    for: rule
                )
            }
        )
    }

    private func matchModeBinding(
        for rule: Binding<视觉小说筛选规则组>
    ) -> Binding<视觉小说筛选匹配方式> {
        Binding(
            get: { rule.wrappedValue.matchMode },
            set: { matchMode in
                setRuleMode(
                    matchMode: matchMode,
                    isExcluded: rule.wrappedValue.isExcluded,
                    for: rule
                )
            }
        )
    }

    private func setRuleMode(
        matchMode: 视觉小说筛选匹配方式,
        isExcluded: Bool,
        for rule: Binding<视觉小说筛选规则组>
    ) {
        guard matchMode != rule.wrappedValue.matchMode
            || isExcluded != rule.wrappedValue.isExcluded else { return }

        if let conflict = VNDB筛选冲突检测器.conflict(
            afterSetting: matchMode,
            isExcluded: isExcluded,
            inRule: rule.wrappedValue.id,
            filters: filters
        ) {
            showConflict(conflict)
            return
        }
        rule.wrappedValue.matchMode = matchMode
        rule.wrappedValue.isExcluded = isExcluded
    }

    private func saveCondition(
        _ condition: 视觉小说筛选条件,
        ruleID: UUID,
        isNew: Bool
    ) -> Bool {
        if let conflict = VNDB筛选冲突检测器.conflict(
            afterSetting: condition,
            inRule: ruleID,
            filters: filters
        ) {
            showConflict(conflict)
            return false
        }

        guard let ruleIndex = filters.rules.firstIndex(where: {
            $0.id == ruleID
        }) else {
            return false
        }

        if isNew {
            filters.rules[ruleIndex].conditions.append(condition)
        } else if let conditionIndex = filters.rules[ruleIndex].conditions
            .firstIndex(where: { $0.id == condition.id }) {
            filters.rules[ruleIndex].conditions[conditionIndex] = condition
        } else {
            return false
        }
        return true
    }

    private func applyFilters() {
        var candidate = filters
        candidate.rules.removeAll { !$0.isConfigured }
        candidate.发行版本规则.rules.removeAll { !$0.isConfigured }
        if let conflict = VNDB筛选冲突检测器.conflict(in: candidate) {
            showConflict(conflict)
            return
        }

        filters = candidate
        characterFilters.rules.removeAll { !$0.isConfigured }
        staffFilters.rules.removeAll { !$0.isConfigured }
        producerFilters.rules.removeAll { !$0.isConfigured }
        onApply()
        dismiss()
    }

    private func showConflict(_ conflict: 视觉小说筛选冲突) {
        conflictAlert = 筛选冲突提示(message: 筛选冲突说明(conflict))
    }

    private func removeCondition(_ conditionID: UUID, from ruleID: UUID) {
        guard let ruleIndex = filters.rules.firstIndex(where: {
            $0.id == ruleID
        }) else {
            return
        }
        withAnimation {
            filters.rules[ruleIndex].conditions.removeAll {
                $0.id == conditionID
            }
        }
    }

    private func conditionSummary(
        _ condition: 视觉小说筛选条件
    ) -> String {
        switch condition.field {
        case .language:
            return ListFormatter.localizedString(byJoining:
                condition.normalizedStringValues.map { code in
                    let fallback = catalog.languages.first {
                        $0.code == code
                    }?.name
                    return VNDB显示工具.语言名称(
                        code,
                        fallbackName: fallback
                    )
                }
            )
        case .platform:
            return ListFormatter.localizedString(byJoining:
                condition.normalizedStringValues.map { code in
                    let fallback = catalog.platforms.first {
                        $0.code == code
                    }?.name
                    return VNDB显示工具.平台名称(
                        code,
                        fallbackName: fallback
                    )
                }
            )
        case .length:
            return ListFormatter.localizedString(byJoining:
                condition.normalizedIntegerValues.compactMap { value in
                    篇幅筛选选项.all.first { $0.id == value }?.title
                }
            )
        case .rating:
            return ratingSummary(condition)
        case .developmentStatus:
            return ListFormatter.localizedString(
                byJoining: condition.normalizedIntegerValues
                    .map(developmentStatusTitle)
            )
        case .tag:
            return ListFormatter.localizedString(byJoining: condition.normalizedStringValues.map { code in
                guard let option = catalog.tags.first(where: { $0.code == code }) else {
                    return code
                }
                return 搜索筛选标签显示名称(option)
            })
        case .releaseYear:
            return ListFormatter.localizedString(byJoining: condition.normalizedIntegerValues.map { year in
                搜索发行年份显示文本(year)
            })
        }
    }

    private func ratingSummary(_ condition: 视觉小说筛选条件) -> String {
        let minimum = condition.normalizedMinimumRating
        let maximum = condition.normalizedMaximumRating
        switch (minimum, maximum) {
        case let (minimum?, maximum?):
            return String(
                format: "%.1f–%.1f",
                Double(minimum) / 10,
                Double(maximum) / 10
            )
        case let (minimum?, nil):
            let value = String(format: "%.1f", Double(minimum) / 10)
            return String(localized: "不低于\(value)")
        case let (nil, maximum?):
            let value = String(format: "%.1f", Double(maximum) / 10)
            return String(localized: "不高于\(value)")
        case (nil, nil):
            return String(localized: "未设置")
        }
    }
}

/// 综合筛选页里一个发行版本、角色、制作人员或会社条件组的分区。
private struct 扩展筛选规则分区: View {
    let scope: 搜索范围
    @Binding var rule: 搜索扩展筛选规则组
    let 序号: Int
    let catalog: VNDB搜索筛选目录
    let 筛选对象菜单: AnyView
    let 编辑条件: (搜索扩展筛选条件, Bool) -> Void
    let 删除规则: () -> Void

    private var availableFields: [搜索扩展筛选字段] {
        搜索扩展筛选字段.available(for: scope)
    }

    var body: some View {
        Section {
            筛选句子布局(horizontalSpacing: 0, verticalSpacing: 6) {
                let parts = 筛选句子片段.拆分(String(localized: "%1$@满足以下%2$@条件的%3$@。"))
                ForEach(parts.indices, id: \.self) { partIndex in
                    switch parts[partIndex] {
                    case .文本(let text):
                        Text(verbatim: text)
                    case .显示方式:
                        Menu {
                            Picker("显示方式", selection: $rule.isExcluded) {
                                Text("显示").tag(false)
                                Text("排除").tag(true)
                            }
                        } label: {
                            sentenceChoiceLabel(
                                rule.isExcluded ? String(localized: "排除") : String(localized: "显示")
                            )
                        }
                    case .匹配方式:
                        Menu {
                            Picker("匹配条件", selection: $rule.matchMode) {
                                Text("所有").tag(视觉小说筛选匹配方式.all)
                                Text("任一").tag(视觉小说筛选匹配方式.any)
                            }
                        } label: {
                            sentenceChoiceLabel(rule.matchMode.localizedShortTitle)
                        }
                    case .筛选对象:
                        筛选对象菜单
                    }
                }
            }
            .font(.body)
            .accessibilityIdentifier("search.filter.rule.\(rule.id).mode")

            ForEach(rule.conditions) { condition in
                Button {
                    编辑条件(condition, false)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: condition.field.systemImage)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(condition.field.localizedTitle(for: scope))
                            Text(verbatim: summary(condition))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward")
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("search.filter.condition.\(condition.field.rawValue)")
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation {
                            rule.conditions.removeAll { $0.id == condition.id }
                        }
                    } label: { Label("删除筛选项", systemImage: "trash") }
                }
            }

            Menu {
                ForEach(availableFields.filter { field in
                    !rule.conditions.contains { $0.field == field }
                }) { field in
                    Button {
                        编辑条件(搜索扩展筛选条件(field: field), true)
                    } label: { Label(field.localizedTitle(for: scope), systemImage: field.systemImage) }
                }
            } label: {
                Label("添加筛选项", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("search.filter.rule.\(rule.id).addCondition")
        } header: {
            HStack {
                Label {
                    Text(verbatim: "\(String(localized: "筛选条件"))\(序号)")
                } icon: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
                Spacer()
                Button(role: .destructive) {
                    删除规则()
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .accessibilityLabel("删除筛选条件")
            }
            .textCase(nil)
        }
    }

    private func sentenceChoiceLabel(_ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: title)
            Image(systemName: "chevron.up.chevron.down").font(.caption2)
        }
        .foregroundStyle(.tint)
        .fixedSize()
        .layoutValue(key: 筛选句子选项布局值.self, value: true)
    }

    private func summary(_ condition: 搜索扩展筛选条件) -> String {
        condition.normalizedStringValues.map { value in
            switch condition.field {
            case .birthday: return Int(value).map(月份名称) ?? value
            case .language: return VNDB显示工具.语言名称(value)
            case .platform: return VNDB显示工具.平台名称(value)
            case .role:
                return roleTitle(value)
            case .trait:
                let source = catalog.traits.first { $0.code == value }?.name
                    ?? value
                return VNDB特征人工翻译.界面译文(source) ?? source
            case .releaseTime:
                return value == "recent" ? String(localized: "最近发行") : String(localized: "即将发行")
            case .releaseAttribute:
                return value == "freeware" ? String(localized: "免费版本") : String(localized: "官方版本")
            case .type:
                switch value {
                case "co": return String(localized: "会社")
                case "in": return String(localized: "个人")
                default: return String(localized: "同人制作组")
                }
            }
        }.reduce(into: "") { result, value in
            result = result.isEmpty ? value : ListFormatter.localizedString(byJoining: [result, value])
        }
    }

    private func roleTitle(_ value: String) -> String {
        switch value {
        case "main": return String(localized: "主角")
        case "primary": return String(localized: "主要角色")
        case "side": return String(localized: "次要角色")
        case "appears": return String(localized: "登场角色")
        case "scenario": return String(localized: "剧本")
        case "director": return String(localized: "导演")
        case "chardesign": return String(localized: "角色设计")
        case "art": return String(localized: "美术")
        case "music": return String(localized: "音乐")
        case "songs": return String(localized: "歌曲")
        case "translator": return String(localized: "翻译")
        case "editor": return String(localized: "编辑")
        case "qa": return String(localized: "质量保证")
        default: return String(localized: "其他人员")
        }
    }

}

private struct 搜索扩展筛选条件编辑页面: View {
    @Environment(\.dismiss) private var dismiss

    let scope: 搜索范围
    @Binding var catalog: VNDB搜索筛选目录
    @Binding var isLoadingTraits: Bool
    let onSave: (搜索扩展筛选条件) -> Void
    @State private var condition: 搜索扩展筛选条件
    @State private var searchText = ""

    init(
        scope: 搜索范围,
        initialCondition: 搜索扩展筛选条件,
        catalog: Binding<VNDB搜索筛选目录>,
        isLoadingTraits: Binding<Bool>,
        onSave: @escaping (搜索扩展筛选条件) -> Void
    ) {
        self.scope = scope
        _catalog = catalog
        _isLoadingTraits = isLoadingTraits
        self.onSave = onSave
        _condition = State(initialValue: initialCondition)
    }

    var body: some View {
        Group {
            if condition.field.requiresSearch {
                optionList
                    .searchable(
                        text: $searchText,
                        prompt: Text(verbatim: "搜索\(condition.field.localizedTitle(for: scope))")
                    )
            } else {
                optionList
            }
        }
        .navigationTitle(Text(verbatim: condition.field.localizedTitle(for: scope)))
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("取消")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    guard condition.isConfigured else { return }
                    onSave(condition)
                    dismiss()
                } label: { Image(systemName: "checkmark") }
                .液态玻璃醒目按钮(in: Circle())
                .disabled(!condition.isConfigured)
                .accessibilityLabel("完成")
            }
        }
    }

    private var optionList: some View {
        平台滚动页面 {
            if condition.field == .trait, isLoadingTraits, options.isEmpty {
                ForEach(0..<8, id: \.self) { index in
                    搜索筛选选项加载骨架行(index: index)
                }
            } else {
                ForEach(filteredOptions) { option in
                    Button {
                        condition.stringValues = toggled(option.code, in: condition.stringValues)
                    } label: {
                        HStack {
                            Text(verbatim: optionTitle(option))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .opacity(condition.stringValues.contains(option.code) ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(condition.stringValues.contains(option.code) ? "已选择" : "未选择")
                    .accessibilityIdentifier("search.filter.\(condition.field.rawValue).\(option.code)")
                }
            }
        }
        .平台分组列表样式()
    }

    private var options: [VNDB筛选选项] {
        switch condition.field {
        case .birthday:
            return (1...12).map { .init(code: "\($0)", name: 月份名称($0)) }
        case .role:
            if scope == .character {
                return [
                    .init(code: "main", name: String(localized: "主角")),
                    .init(code: "primary", name: String(localized: "主要角色")),
                    .init(code: "side", name: String(localized: "次要角色")),
                    .init(code: "appears", name: String(localized: "登场角色"))
                ]
            }
            return [
                .init(code: "scenario", name: String(localized: "剧本")),
                .init(code: "director", name: String(localized: "导演")),
                .init(code: "chardesign", name: String(localized: "角色设计")),
                .init(code: "art", name: String(localized: "美术")),
                .init(code: "music", name: String(localized: "音乐")),
                .init(code: "songs", name: String(localized: "歌曲")),
                .init(code: "translator", name: String(localized: "翻译")),
                .init(code: "editor", name: String(localized: "编辑")),
                .init(code: "qa", name: String(localized: "质量保证")),
                .init(code: "staff", name: String(localized: "其他人员"))
            ]
        case .trait:
            return catalog.traits
        case .releaseTime:
            return [
                .init(code: "recent", name: String(localized: "最近发行")),
                .init(code: "upcoming", name: String(localized: "即将发行"))
            ]
        case .releaseAttribute:
            return [
                .init(code: "freeware", name: String(localized: "免费版本")),
                .init(code: "official", name: String(localized: "官方版本"))
            ]
        case .language:
            return catalog.languages
        case .platform:
            return catalog.platforms
        case .type:
            return [
                .init(code: "co", name: String(localized: "会社")),
                .init(code: "in", name: String(localized: "个人")),
                .init(code: "ng", name: String(localized: "同人制作组"))
            ]
        }
    }

    private var filteredOptions: [VNDB筛选选项] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter {
            $0.code.localizedCaseInsensitiveContains(query)
                || optionTitle($0).localizedCaseInsensitiveContains(query)
        }
    }

    private func optionTitle(_ option: VNDB筛选选项) -> String {
        switch condition.field {
        case .language: return VNDB显示工具.语言名称(option.code, fallbackName: option.name)
        case .platform: return VNDB显示工具.平台名称(option.code, fallbackName: option.name)
        case .trait: return VNDB特征人工翻译.界面译文(option.name) ?? option.name
        default: return option.name
        }
    }

    private func toggled(_ value: String, in set: Set<String>) -> Set<String> {
        var result = set
        if result.contains(value) { result.remove(value) } else { result.insert(value) }
        return result
    }
}

private struct 视觉小说筛选条件编辑页面: View {
    @Environment(\.dismiss) private var dismiss

    @State private var condition: 视觉小说筛选条件
    @State private var searchText = ""

    @Binding var catalog: VNDB搜索筛选目录
    @Binding var isLoadingTags: Bool
    let validate: (视觉小说筛选条件) -> 视觉小说筛选冲突?
    let onSave: (视觉小说筛选条件) -> Bool

    init(
        initialCondition: 视觉小说筛选条件,
        catalog: Binding<VNDB搜索筛选目录>,
        isLoadingTags: Binding<Bool>,
        validate: @escaping (视觉小说筛选条件) -> 视觉小说筛选冲突?,
        onSave: @escaping (视觉小说筛选条件) -> Bool
    ) {
        _condition = State(initialValue: initialCondition)
        _catalog = catalog
        _isLoadingTags = isLoadingTags
        self.validate = validate
        self.onSave = onSave
    }

    var body: some View {
        let conflict = validate(condition)

        Group {
            switch condition.field {
            case .language:
                optionList(
                    filteredOptions(catalog.languages, field: .language),
                    field: .language
                )
                .searchable(text: $searchText, prompt: "搜索语言")
            case .platform:
                optionList(
                    filteredOptions(catalog.platforms, field: .platform),
                    field: .platform
                )
                .searchable(text: $searchText, prompt: "搜索平台")
            case .length:
                lengthList
            case .rating:
                ratingList
            case .developmentStatus:
                developmentStatusList
            case .tag:
                optionList(filteredOptions(catalog.tags, field: .tag), field: .tag)
                    .searchable(text: $searchText, prompt: "搜索标签")
            case .releaseYear:
                releaseYearList
            }
        }
        .navigationTitle(Text(verbatim: condition.field.localizedTitle))
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("取消")
            }

            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if onSave(condition) {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .液态玻璃醒目按钮(in: Circle())
                .disabled(!condition.isConfigured || conflict != nil)
                .accessibilityLabel("完成")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let conflict {
                Label {
                    Text(verbatim: 筛选冲突说明(conflict))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
                .accessibilityIdentifier("search.filter.conflict")
            }
        }
    }

    private func optionList(
        _ options: [VNDB筛选选项],
        field: 视觉小说筛选字段
    ) -> some View {
        平台滚动页面 {
            if field == .tag, isLoadingTags, options.isEmpty {
                ForEach(0..<8, id: \.self) { index in
                    搜索筛选选项加载骨架行(index: index)
                }
            } else {
                ForEach(options) { option in
                    let title = optionTitle(option, field: field)
                    selectionRow(
                        title: title,
                        selected: condition.stringValues.contains(option.code),
                        identifier: "search.filter.\(field.rawValue).\(option.code)"
                    ) {
                        condition.stringValues = toggled(
                            option.code,
                            in: condition.stringValues
                        )
                    }
                }
            }
        }
        .平台分组列表样式()
    }

    private var lengthList: some View {
        平台滚动页面 {
            Section {
                ForEach(篇幅筛选选项.all) { length in
                    selectionRow(
                        title: length.title,
                        detail: length.duration,
                        selected: condition.integerValues.contains(length.id),
                        identifier: "search.filter.length.\(length.id)"
                    ) {
                        condition.integerValues = toggled(
                            length.id,
                            in: condition.integerValues
                        )
                    }
                }
            }
        }
        .平台分组列表样式()
    }

    private var releaseYearList: some View {
        平台滚动页面 {
            ForEach(Array(stride(from: Calendar.current.component(.year, from: .now), through: 1985, by: -1)), id: \.self) { year in
                selectionRow(
                    title: 搜索发行年份显示文本(year),
                    selected: condition.integerValues.contains(year),
                    identifier: "search.filter.releaseYear.\(year)"
                ) {
                    condition.integerValues = toggled(year, in: condition.integerValues)
                }
            }
        }
        .平台分组列表样式()
    }

    private var developmentStatusList: some View {
        平台滚动页面 {
            Section {
                ForEach(0...2, id: \.self) { status in
                    selectionRow(
                        title: developmentStatusTitle(status),
                        selected: condition.integerValues.contains(status),
                        identifier: "search.filter.developmentStatus.\(status)"
                    ) {
                        condition.integerValues = toggled(
                            status,
                            in: condition.integerValues
                        )
                    }
                }
            }
        }
        .平台分组列表样式()
    }

    private var ratingList: some View {
        平台滚动页面 {
            Section("评分") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("评分范围", systemImage: "chart.bar.xaxis")
                        Spacer()
                        Text(verbatim: ratingRangeText)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    评分范围滑块(value: ratingRange)
                }
                .padding(.vertical, 4)
            }
        }
        .平台分组列表样式()
    }

    private var ratingRange: Binding<ClosedRange<Int>> {
        Binding(
            get: {
                let minimum = min(
                    max(condition.normalizedMinimumRating ?? 10, 10),
                    100
                )
                let maximum = min(
                    max(condition.normalizedMaximumRating ?? 100, minimum),
                    100
                )
                return minimum...maximum
            },
            set: { range in
                condition.minimumRating = range.lowerBound == 10
                    ? nil
                    : range.lowerBound
                condition.maximumRating = range.upperBound == 100
                    ? nil
                    : range.upperBound
            }
        )
    }

    private var ratingRangeText: String {
        let range = ratingRange.wrappedValue
        return String(
            format: "%.1f–%.1f",
            Double(range.lowerBound) / 10,
            Double(range.upperBound) / 10
        )
    }

    private func filteredOptions(
        _ options: [VNDB筛选选项],
        field: 视觉小说筛选字段
    ) -> [VNDB筛选选项] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { option in
            option.code.localizedCaseInsensitiveContains(query)
                || option.name.localizedCaseInsensitiveContains(query)
                || optionTitle(option, field: field)
                    .localizedCaseInsensitiveContains(query)
        }
    }

    private func optionTitle(
        _ option: VNDB筛选选项,
        field: 视觉小说筛选字段
    ) -> String {
        switch field {
        case .language:
            return VNDB显示工具.语言名称(
                option.code,
                fallbackName: option.name
            )
        case .platform:
            return VNDB显示工具.平台名称(
                option.code,
                fallbackName: option.name
            )
        case .tag:
            return 搜索筛选标签显示名称(option)
        default:
            return option.name
        }
    }

    private func selectionRow(
        title: String,
        detail: String? = nil,
        selected: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title)
                    .foregroundStyle(.primary)
                Spacer()
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .opacity(selected ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityIdentifier(identifier)
    }

    private func toggled<Value: Hashable>(
        _ value: Value,
        in set: Set<Value>
    ) -> Set<Value> {
        var result = set
        if result.contains(value) {
            result.remove(value)
        } else {
            result.insert(value)
        }
        return result
    }
}

private struct 搜索筛选选项加载骨架行: View {
    let index: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: index.isMultiple(of: 2) ? 166 : 132, height: 16)
            Spacer()
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 18, height: 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 3)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

nonisolated func 搜索发行年份显示文本(_ year: Int) -> String {
    String(
        format: String(localized: "%lld年"),
        Int64(year)
    )
}

private func developmentStatusTitle(_ status: Int) -> String {
    switch status {
    case 0: return String(localized: "已完结")
    case 1: return String(localized: "开发中")
    default: return String(localized: "已取消")
    }
}

enum 视觉小说筛选匹配方式: String, CaseIterable, Codable, Hashable, Identifiable {
    case all
    case any

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .all: return String(localized: "满足所有条件")
        case .any: return String(localized: "满足任一条件")
        }
    }

    var localizedShortTitle: String {
        switch self {
        case .all: return String(localized: "所有")
        case .any: return String(localized: "任一")
        }
    }
}

enum 视觉小说筛选字段: String, CaseIterable, Codable, Hashable, Identifiable {
    case language
    case platform
    case length
    case rating
    case developmentStatus
    case tag
    case releaseYear

    static let availableFields: [Self] = [
        .language,
        .platform,
        .length,
        .rating,
        .developmentStatus,
        .tag,
        .releaseYear
    ]

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .language: return String(localized: "语言")
        case .platform: return String(localized: "平台")
        case .length: return String(localized: "篇幅")
        case .rating: return String(localized: "评分")
        case .developmentStatus: return String(localized: "开发状态")
        case .tag: return String(localized: "标签")
        case .releaseYear: return String(localized: "发行时间")
        }
    }

    var systemImage: String {
        switch self {
        case .language: return "character.bubble"
        case .platform: return "rectangle.3.group"
        case .length: return "clock"
        case .rating: return "chart.bar.xaxis"
        case .developmentStatus: return "hammer"
        case .tag: return "tag"
        case .releaseYear: return "calendar"
        }
    }
}

struct 视觉小说筛选条件: Codable, Hashable, Identifiable {
    let id: UUID
    var field: 视觉小说筛选字段
    var stringValues: Set<String>
    var integerValues: Set<Int>
    var minimumRating: Int?
    var maximumRating: Int?

    init(
        id: UUID = UUID(),
        field: 视觉小说筛选字段,
        stringValues: Set<String> = [],
        integerValues: Set<Int> = [],
        minimumRating: Int? = nil,
        maximumRating: Int? = nil
    ) {
        self.id = id
        self.field = field
        self.stringValues = stringValues
        self.integerValues = integerValues
        self.minimumRating = minimumRating
        self.maximumRating = maximumRating
    }

    nonisolated var isConfigured: Bool {
        switch field {
        case .language, .platform, .tag:
            return !normalizedStringValues.isEmpty
        case .length, .developmentStatus, .releaseYear:
            return !normalizedIntegerValues.isEmpty
        case .rating:
            return normalizedMinimumRating != nil || normalizedMaximumRating != nil
        }
    }

    nonisolated var normalizedStringValues: [String] {
        Set(
            stringValues.compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        ).sorted()
    }

    nonisolated var normalizedIntegerValues: [Int] {
        let allowedRange: ClosedRange<Int>
        switch field {
        case .length: allowedRange = 1...5
        case .developmentStatus: allowedRange = 0...2
        case .releaseYear: allowedRange = 1980...2100
        default: return integerValues.sorted()
        }
        return integerValues.filter(allowedRange.contains).sorted()
    }

    nonisolated var normalizedMinimumRating: Int? {
        minimumRating.map { min(max($0, 10), 100) }
    }

    nonisolated var normalizedMaximumRating: Int? {
        maximumRating.map { min(max($0, 10), 100) }
    }
}

struct 视觉小说筛选规则组: Codable, Hashable, Identifiable {
    let id: UUID
    var matchMode: 视觉小说筛选匹配方式
    var isExcluded: Bool
    var conditions: [视觉小说筛选条件]

    init(
        id: UUID = UUID(),
        matchMode: 视觉小说筛选匹配方式 = .all,
        isExcluded: Bool = false,
        conditions: [视觉小说筛选条件] = []
    ) {
        self.id = id
        self.matchMode = matchMode
        self.isExcluded = isExcluded
        self.conditions = conditions
    }

    nonisolated var configuredConditions: [视觉小说筛选条件] {
        conditions.filter(\.isConfigured)
    }

    nonisolated var isConfigured: Bool {
        !configuredConditions.isEmpty
    }
}

struct 视觉小说搜索筛选: Codable, Hashable {
    var rules: [视觉小说筛选规则组]
    /// 对作品的发行版本的筛选：作品至少有一个发行版本满足这些条件。
    /// 综合搜索里发行版本收在作品下面，发行版本的筛选通过作品生效。
    var 发行版本规则 = 搜索扩展筛选()

    init(
        rules: [视觉小说筛选规则组] = [],
        languages: Set<String> = [],
        platforms: Set<String> = [],
        lengths: Set<Int> = [],
        minimumRating: Int? = nil,
        maximumRating: Int? = nil,
        developmentStatuses: Set<Int> = []
    ) {
        self.rules = rules

        if !languages.isEmpty {
            self.rules.append(
                视觉小说筛选规则组(
                    matchMode: .any,
                    conditions: [
                        视觉小说筛选条件(
                            field: .language,
                            stringValues: languages
                        )
                    ]
                )
            )
        }
        if !platforms.isEmpty {
            self.rules.append(
                视觉小说筛选规则组(
                    matchMode: .any,
                    conditions: [
                        视觉小说筛选条件(
                            field: .platform,
                            stringValues: platforms
                        )
                    ]
                )
            )
        }
        if !lengths.isEmpty {
            self.rules.append(
                视觉小说筛选规则组(
                    matchMode: .any,
                    conditions: [
                        视觉小说筛选条件(
                            field: .length,
                            integerValues: lengths
                        )
                    ]
                )
            )
        }
        if minimumRating != nil || maximumRating != nil {
            self.rules.append(
                视觉小说筛选规则组(
                    conditions: [
                        视觉小说筛选条件(
                            field: .rating,
                            minimumRating: minimumRating,
                            maximumRating: maximumRating
                        )
                    ]
                )
            )
        }
        if !developmentStatuses.isEmpty {
            self.rules.append(
                视觉小说筛选规则组(
                    matchMode: .any,
                    conditions: [
                        视觉小说筛选条件(
                            field: .developmentStatus,
                            integerValues: developmentStatuses
                        )
                    ]
                )
            )
        }
    }

    nonisolated var configuredRules: [视觉小说筛选规则组] {
        rules.filter(\.isConfigured)
    }

    nonisolated var isEmpty: Bool {
        configuredRules.isEmpty && 发行版本规则.isEmpty
    }

    nonisolated var activeFilterCount: Int {
        configuredRules.reduce(0) { count, rule in
            count + rule.configuredConditions.count
        }
    }
}

struct VNDB筛选选项: Codable, Hashable, Identifiable {
    let code: String
    let name: String

    var id: String { code }
}

struct VNDB搜索筛选目录: Codable, Hashable {
    var languages: [VNDB筛选选项]
    var platforms: [VNDB筛选选项]
    var tags: [VNDB筛选选项]
    var traits: [VNDB筛选选项]

    nonisolated init(
        languages: [VNDB筛选选项],
        platforms: [VNDB筛选选项],
        tags: [VNDB筛选选项] = [],
        traits: [VNDB筛选选项] = []
    ) {
        self.languages = languages
        self.platforms = platforms
        self.tags = tags
        self.traits = traits
    }

    private enum CodingKeys: String, CodingKey {
        case languages, platforms, tags, traits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languages = try container.decodeIfPresent([VNDB筛选选项].self, forKey: .languages) ?? []
        platforms = try container.decodeIfPresent([VNDB筛选选项].self, forKey: .platforms) ?? []
        tags = try container.decodeIfPresent([VNDB筛选选项].self, forKey: .tags) ?? []
        traits = try container.decodeIfPresent([VNDB筛选选项].self, forKey: .traits) ?? []
    }

    static let builtIn = VNDB搜索筛选目录(
        languages: [
            .init(code: "ja", name: "Japanese"),
            .init(code: "zh-Hans", name: "Simplified Chinese"),
            .init(code: "zh-Hant", name: "Traditional Chinese"),
            .init(code: "en", name: "English"),
            .init(code: "ko", name: "Korean"),
            .init(code: "ar", name: "Arabic"),
            .init(code: "bg", name: "Bulgarian"),
            .init(code: "ca", name: "Catalan"),
            .init(code: "cs", name: "Czech"),
            .init(code: "da", name: "Danish"),
            .init(code: "de", name: "German"),
            .init(code: "el", name: "Greek"),
            .init(code: "eo", name: "Esperanto"),
            .init(code: "es", name: "Spanish"),
            .init(code: "eu", name: "Basque"),
            .init(code: "fa", name: "Persian"),
            .init(code: "fi", name: "Finnish"),
            .init(code: "fr", name: "French"),
            .init(code: "ga", name: "Irish"),
            .init(code: "he", name: "Hebrew"),
            .init(code: "hi", name: "Hindi"),
            .init(code: "hr", name: "Croatian"),
            .init(code: "hu", name: "Hungarian"),
            .init(code: "id", name: "Indonesian"),
            .init(code: "it", name: "Italian"),
            .init(code: "lt", name: "Lithuanian"),
            .init(code: "lv", name: "Latvian"),
            .init(code: "ms", name: "Malay"),
            .init(code: "nl", name: "Dutch"),
            .init(code: "no", name: "Norwegian"),
            .init(code: "pl", name: "Polish"),
            .init(code: "pt-br", name: "Brazilian Portuguese"),
            .init(code: "pt-pt", name: "Portuguese"),
            .init(code: "ro", name: "Romanian"),
            .init(code: "ru", name: "Russian"),
            .init(code: "sk", name: "Slovak"),
            .init(code: "sl", name: "Slovenian"),
            .init(code: "sr", name: "Serbian"),
            .init(code: "sv", name: "Swedish"),
            .init(code: "ta", name: "Tamil"),
            .init(code: "th", name: "Thai"),
            .init(code: "tr", name: "Turkish"),
            .init(code: "uk", name: "Ukrainian"),
            .init(code: "ur", name: "Urdu"),
            .init(code: "vi", name: "Vietnamese")
        ],
        platforms: [
            .init(code: "win", name: "Windows"),
            .init(code: "mac", name: "macOS"),
            .init(code: "lin", name: "Linux"),
            .init(code: "ios", name: "iOS"),
            .init(code: "and", name: "Android"),
            .init(code: "web", name: "Web browser"),
            .init(code: "dos", name: "DOS"),
            .init(code: "switch", name: "Nintendo Switch"),
            .init(code: "ps5", name: "PlayStation 5"),
            .init(code: "ps4", name: "PlayStation 4"),
            .init(code: "ps3", name: "PlayStation 3"),
            .init(code: "ps2", name: "PlayStation 2"),
            .init(code: "ps1", name: "PlayStation"),
            .init(code: "psv", name: "PlayStation Vita"),
            .init(code: "psp", name: "PSP"),
            .init(code: "xboxx", name: "Xbox Series"),
            .init(code: "xone", name: "Xbox One"),
            .init(code: "x360", name: "Xbox 360"),
            .init(code: "n3ds", name: "Nintendo 3DS"),
            .init(code: "nds", name: "Nintendo DS"),
            .init(code: "wiiu", name: "Wii U"),
            .init(code: "wii", name: "Wii"),
            .init(code: "dc", name: "Dreamcast"),
            .init(code: "sat", name: "Sega Saturn"),
            .init(code: "sfc", name: "Super Nintendo"),
            .init(code: "nes", name: "Nintendo Entertainment System"),
            .init(code: "gba", name: "Game Boy Advance"),
            .init(code: "gbc", name: "Game Boy Color"),
            .init(code: "pce", name: "PC Engine"),
            .init(code: "pcfx", name: "PC-FX"),
            .init(code: "p98", name: "PC-98"),
            .init(code: "p88", name: "PC-88"),
            .init(code: "fmt", name: "FM Towns"),
            .init(code: "msx", name: "MSX"),
            .init(code: "x68", name: "Sharp X68000"),
            .init(code: "ws", name: "WonderSwan"),
            .init(code: "ngp", name: "Neo Geo Pocket"),
            .init(code: "dvd", name: "DVD Player"),
            .init(code: "bdp", name: "Blu-ray Player")
        ]
    )

    func merging(_ newer: VNDB搜索筛选目录) -> VNDB搜索筛选目录 {
        VNDB搜索筛选目录(
            languages: Self.merged(builtIn: languages, newer: newer.languages),
            platforms: Self.merged(builtIn: platforms, newer: newer.platforms),
            tags: Self.merged(builtIn: tags, newer: newer.tags),
            traits: Self.merged(builtIn: traits, newer: newer.traits)
        )
    }

    private static func merged(
        builtIn: [VNDB筛选选项],
        newer: [VNDB筛选选项]
    ) -> [VNDB筛选选项] {
        var values: [String: VNDB筛选选项] = [:]
        for option in builtIn where !option.code.isEmpty {
            values[option.code] = option
        }
        for option in newer where !option.code.isEmpty {
            values[option.code] = option
        }

        let preferredOrder = Dictionary(
            uniqueKeysWithValues: builtIn.enumerated().map { ($0.element.code, $0.offset) }
        )
        return values.values.sorted { lhs, rhs in
            let lhsOrder = preferredOrder[lhs.code]
            let rhsOrder = preferredOrder[rhs.code]
            switch (lhsOrder, rhsOrder) {
            case let (lhs?, rhs?): return lhs < rhs
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
        }
    }
}

private enum VNDB筛选值: Equatable {
    case string(String)
    case integer(Int)
    case array([VNDB筛选值])

    nonisolated var jsonObject: Any {
        switch self {
        case let .string(value): return value
        case let .integer(value): return value
        case let .array(values): return values.map(\.jsonObject)
        }
    }
}

private indirect enum VNDB筛选表达式: Equatable {
    case comparison(
        field: String,
        comparisonOperator: String,
        value: VNDB筛选值
    )
    case all([VNDB筛选表达式])
    case any([VNDB筛选表达式])

    nonisolated var jsonObject: Any {
        switch self {
        case let .comparison(field, comparisonOperator, value):
            return [field, comparisonOperator, value.jsonObject] as [Any]
        case let .all(expressions):
            var result: [Any] = ["and"]
            result.append(contentsOf: expressions.map(\.jsonObject))
            return result
        case let .any(expressions):
            var result: [Any] = ["or"]
            result.append(contentsOf: expressions.map(\.jsonObject))
            return result
        }
    }

    nonisolated var negated: VNDB筛选表达式 {
        switch self {
        case let .comparison(field, comparisonOperator, value):
            return .comparison(
                field: field,
                comparisonOperator: Self.inverted(comparisonOperator),
                value: value
            )
        case let .all(expressions):
            return .any(expressions.map(\.negated))
        case let .any(expressions):
            return .all(expressions.map(\.negated))
        }
    }

    nonisolated private static func inverted(_ comparisonOperator: String) -> String {
        switch comparisonOperator {
        case "=": return "!="
        case "!=": return "="
        case ">=": return "<"
        case ">": return "<="
        case "<=": return ">"
        case "<": return ">="
        default: return comparisonOperator
        }
    }
}

enum VNDB视觉小说筛选编译器 {
    nonisolated static func filterObject(
        keyword: String,
        filters: 视觉小说搜索筛选
    ) -> Any {
        let rules = filters.configuredRules.compactMap(ruleExpression)
        var expressions = rules
        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            expressions.insert(
                .comparison(
                    field: "search",
                    comparisonOperator: "=",
                    value: .string(keyword)
                ),
                at: 0
            )
        }

        guard let expression = combined(expressions, mode: .all) else {
            return ["id", ">=", "v1"] as [Any]
        }
        return expression.jsonObject
    }

    nonisolated private static func ruleExpression(
        _ rule: 视觉小说筛选规则组
    ) -> VNDB筛选表达式? {
        let configuredConditions = rule.configuredConditions
        let conditions = configuredConditions.compactMap { condition in
            conditionExpression(condition, groupMode: rule.matchMode)
        }
        guard let expression = combined(conditions, mode: .all) else {
            return nil
        }
        guard rule.isExcluded else { return expression }

        let negatedConditions: [VNDB筛选表达式] = configuredConditions.compactMap {
            condition -> VNDB筛选表达式? in
            guard let conditionExpression = conditionExpression(
                condition,
                groupMode: rule.matchMode
            ) else {
                return nil
            }
            guard condition.field == .rating else {
                return conditionExpression.negated
            }
            return combined(
                [
                    conditionExpression.negated,
                    .comparison(
                        field: "votecount",
                        comparisonOperator: "=",
                        value: .integer(0)
                    )
                ],
                mode: .any
            )
        }
        return combined(negatedConditions, mode: .any)
    }

    nonisolated private static func conditionExpression(
        _ condition: 视觉小说筛选条件,
        groupMode: 视觉小说筛选匹配方式
    ) -> VNDB筛选表达式? {
        switch condition.field {
        case .language:
            return equalityExpression(
                field: "lang",
                values: condition.normalizedStringValues.map(VNDB筛选值.string),
                mode: groupMode
            )
        case .platform:
            return equalityExpression(
                field: "platform",
                values: condition.normalizedStringValues.map(VNDB筛选值.string),
                mode: groupMode
            )
        case .tag:
            return equalityExpression(
                field: "tag",
                values: condition.normalizedStringValues.map(VNDB筛选值.string),
                mode: groupMode
            )
        case .length:
            return equalityExpression(
                field: "length",
                values: condition.normalizedIntegerValues.map(VNDB筛选值.integer),
                mode: .any
            )
        case .developmentStatus:
            return equalityExpression(
                field: "devstatus",
                values: condition.normalizedIntegerValues.map(VNDB筛选值.integer),
                mode: .any
            )
        case .rating:
            var bounds: [VNDB筛选表达式] = []
            if let minimum = condition.normalizedMinimumRating {
                bounds.append(
                    .comparison(
                        field: "rating",
                        comparisonOperator: ">=",
                        value: .integer(minimum)
                    )
                )
            }
            if let maximum = condition.normalizedMaximumRating {
                bounds.append(
                    .comparison(
                        field: "rating",
                        comparisonOperator: "<=",
                        value: .integer(maximum)
                    )
                )
            }
            return combined(bounds, mode: .all)
        case .releaseYear:
            let years = condition.normalizedIntegerValues.map { year in
                VNDB筛选表达式.all([
                    .comparison(field: "released", comparisonOperator: ">=", value: .string("\(year)-01-01")),
                    .comparison(field: "released", comparisonOperator: "<", value: .string("\(year + 1)-01-01"))
                ])
            }
            return combined(years, mode: groupMode)
        }
    }

    nonisolated private static func equalityExpression(
        field: String,
        values: [VNDB筛选值],
        mode: 视觉小说筛选匹配方式
    ) -> VNDB筛选表达式? {
        combined(
            values.map {
                .comparison(
                    field: field,
                    comparisonOperator: "=",
                    value: $0
                )
            },
            mode: mode
        )
    }

    nonisolated private static func combined(
        _ expressions: [VNDB筛选表达式],
        mode: 视觉小说筛选匹配方式
    ) -> VNDB筛选表达式? {
        let flattened = expressions.flatMap { expression in
            switch (mode, expression) {
            case let (.all, .all(children)):
                return children
            case let (.any, .any(children)):
                return children
            default:
                return [expression]
            }
        }

        switch flattened.count {
        case 0: return nil
        case 1: return flattened[0]
        default:
            return mode == .all ? .all(flattened) : .any(flattened)
        }
    }
}

struct 视觉小说筛选冲突: nonisolated Equatable {
    let ruleIndices: [Int]

    nonisolated init(ruleIndices: [Int]) {
        self.ruleIndices = ruleIndices
    }
}

enum VNDB筛选冲突检测器 {
    nonisolated static func conflict(
        in filters: 视觉小说搜索筛选
    ) -> 视觉小说筛选冲突? {
        var core = filters.rules.enumerated().compactMap { index, rule in
            rule.isConfigured ? 索引筛选规则(index: index, rule: rule) : nil
        }

        guard !isSatisfiable(core.map(\.rule)) else { return nil }

        var position = 0
        while position < core.count {
            var candidate = core
            candidate.remove(at: position)
            if !isSatisfiable(candidate.map(\.rule)) {
                core = candidate
            } else {
                position += 1
            }
        }

        return 视觉小说筛选冲突(ruleIndices: core.map(\.index))
    }

    nonisolated static func isSatisfiable(
        _ filters: 视觉小说搜索筛选
    ) -> Bool {
        isSatisfiable(filters.configuredRules)
    }

    nonisolated static func conflict(
        afterSetting condition: 视觉小说筛选条件,
        inRule ruleID: UUID,
        filters: 视觉小说搜索筛选
    ) -> 视觉小说筛选冲突? {
        var candidate = filters
        guard let ruleIndex = candidate.rules.firstIndex(where: {
            $0.id == ruleID
        }) else {
            return conflict(in: candidate)
        }

        if let conditionIndex = candidate.rules[ruleIndex].conditions
            .firstIndex(where: { $0.id == condition.id }) {
            candidate.rules[ruleIndex].conditions[conditionIndex] = condition
        } else {
            candidate.rules[ruleIndex].conditions.append(condition)
        }
        return conflict(in: candidate)
    }

    nonisolated static func conflict(
        afterSetting matchMode: 视觉小说筛选匹配方式,
        isExcluded: Bool,
        inRule ruleID: UUID,
        filters: 视觉小说搜索筛选
    ) -> 视觉小说筛选冲突? {
        var candidate = filters
        guard let ruleIndex = candidate.rules.firstIndex(where: {
            $0.id == ruleID
        }) else {
            return conflict(in: candidate)
        }

        candidate.rules[ruleIndex].matchMode = matchMode
        candidate.rules[ruleIndex].isExcluded = isExcluded
        return conflict(in: candidate)
    }

    nonisolated private static func isSatisfiable(
        _ rules: [视觉小说筛选规则组]
    ) -> Bool {
        let configuredRules = rules.filter(\.isConfigured)
        let variables = variables(in: configuredRules)
        var assignment: [筛选变量: 筛选变量值] = [:]
        return search(
            rules: configuredRules,
            variables: variables,
            assignment: &assignment
        )
    }

    nonisolated private static func search(
        rules: [视觉小说筛选规则组],
        variables: [筛选变量],
        assignment: inout [筛选变量: 筛选变量值]
    ) -> Bool {
        switch evaluate(rules: rules, assignment: assignment) {
        case .yes:
            return true
        case .no:
            return false
        case .unknown:
            break
        }

        guard let variable = variables.first(where: {
            assignment[$0] == nil
        }) else {
            return false
        }

        for value in domain(for: variable) {
            assignment[variable] = value
            if search(
                rules: rules,
                variables: variables,
                assignment: &assignment
            ) {
                assignment.removeValue(forKey: variable)
                return true
            }
        }
        assignment.removeValue(forKey: variable)
        return false
    }

    nonisolated private static func evaluate(
        rules: [视觉小说筛选规则组],
        assignment: [筛选变量: 筛选变量值]
    ) -> 部分真值 {
        部分真值.all(
            rules.map { rule in
                let match = 部分真值.all(
                    rule.configuredConditions.map { condition in
                        evaluate(
                            condition: condition,
                            matchMode: rule.matchMode,
                            assignment: assignment
                        )
                    }
                )
                return rule.isExcluded ? match.negated : match
            }
        )
    }

    nonisolated private static func evaluate(
        condition: 视觉小说筛选条件,
        matchMode: 视觉小说筛选匹配方式,
        assignment: [筛选变量: 筛选变量值]
    ) -> 部分真值 {
        switch condition.field {
        case .language:
            return evaluateMembership(
                condition.normalizedStringValues.map(筛选变量.language),
                matchMode: matchMode,
                assignment: assignment
            )
        case .platform:
            return evaluateMembership(
                condition.normalizedStringValues.map(筛选变量.platform),
                matchMode: matchMode,
                assignment: assignment
            )
        case .length:
            return evaluateInteger(
                variable: .length,
                allowedValues: Set(condition.normalizedIntegerValues),
                assignment: assignment
            )
        case .developmentStatus:
            return evaluateInteger(
                variable: .developmentStatus,
                allowedValues: Set(condition.normalizedIntegerValues),
                assignment: assignment
            )
        case .rating:
            guard let value = assignment[.rating] else { return .unknown }
            guard case let .integer(rating) = value else { return .no }
            if let minimum = condition.normalizedMinimumRating,
               rating < minimum {
                return .no
            }
            if let maximum = condition.normalizedMaximumRating,
               rating > maximum {
                return .no
            }
            return .yes
        case .tag, .releaseYear:
            return .yes
        }
    }

    nonisolated private static func evaluateMembership(
        _ variables: [筛选变量],
        matchMode: 视觉小说筛选匹配方式,
        assignment: [筛选变量: 筛选变量值]
    ) -> 部分真值 {
        let values: [部分真值] = variables.map { variable in
            guard let value = assignment[variable] else { return .unknown }
            return value == .flag(true) ? .yes : .no
        }
        return matchMode == .all
            ? 部分真值.all(values)
            : 部分真值.any(values)
    }

    nonisolated private static func evaluateInteger(
        variable: 筛选变量,
        allowedValues: Set<Int>,
        assignment: [筛选变量: 筛选变量值]
    ) -> 部分真值 {
        guard let value = assignment[variable] else { return .unknown }
        guard case let .integer(integer) = value else { return .no }
        return allowedValues.contains(integer) ? .yes : .no
    }

    nonisolated private static func variables(
        in rules: [视觉小说筛选规则组]
    ) -> [筛选变量] {
        var result: Set<筛选变量> = []
        for rule in rules {
            for condition in rule.configuredConditions {
                switch condition.field {
                case .language:
                    result.formUnion(
                        condition.normalizedStringValues.map(筛选变量.language)
                    )
                case .platform:
                    result.formUnion(
                        condition.normalizedStringValues.map(筛选变量.platform)
                    )
                case .length:
                    result.insert(.length)
                case .rating:
                    result.insert(.rating)
                case .developmentStatus:
                    result.insert(.developmentStatus)
                case .tag, .releaseYear:
                    break
                }
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.sortName < rhs.sortName
        }
    }

    nonisolated private static func domain(
        for variable: 筛选变量
    ) -> [筛选变量值] {
        switch variable {
        case .language, .platform:
            return [.flag(false), .flag(true)]
        case .developmentStatus:
            return (0...2).map(筛选变量值.integer)
        case .length:
            return [.unavailable] + (1...5).map(筛选变量值.integer)
        case .rating:
            return [.unavailable] + (10...100).map(筛选变量值.integer)
        }
    }
}

private struct 索引筛选规则 {
    let index: Int
    let rule: 视觉小说筛选规则组

    nonisolated init(index: Int, rule: 视觉小说筛选规则组) {
        self.index = index
        self.rule = rule
    }
}

private enum 筛选变量: nonisolated Hashable {
    case language(String)
    case platform(String)
    case length
    case rating
    case developmentStatus

    nonisolated var sortOrder: Int {
        switch self {
        case .language: return 0
        case .platform: return 1
        case .developmentStatus: return 2
        case .length: return 3
        case .rating: return 4
        }
    }

    nonisolated var sortName: String {
        switch self {
        case let .language(code), let .platform(code): return code
        case .length: return "length"
        case .rating: return "rating"
        case .developmentStatus: return "developmentStatus"
        }
    }
}

private enum 筛选变量值: nonisolated Equatable {
    case flag(Bool)
    case integer(Int)
    case unavailable
}

private enum 部分真值: nonisolated Equatable {
    case yes
    case no
    case unknown

    nonisolated var negated: 部分真值 {
        switch self {
        case .yes: return .no
        case .no: return .yes
        case .unknown: return .unknown
        }
    }

    nonisolated static func all(_ values: [部分真值]) -> 部分真值 {
        if values.contains(where: { $0 == .no }) { return .no }
        if values.contains(where: { $0 == .unknown }) { return .unknown }
        return .yes
    }

    nonisolated static func any(_ values: [部分真值]) -> 部分真值 {
        if values.contains(where: { $0 == .yes }) { return .yes }
        if values.contains(where: { $0 == .unknown }) { return .unknown }
        return .no
    }
}
