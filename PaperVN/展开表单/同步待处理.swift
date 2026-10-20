import SwiftUI

/// PaperVN Sync 遇到需要用户决定的情况时弹出：作品数量大幅减少、多个资料库内容不同、
/// 不是在 PaperVN 中做的更改、同一部作品记录不同，以及第一次同步前的确认。
/// 关闭页面只是稍后再处理；“停止同步”才会丢弃这次读到的数据。
struct 同步待处理页面: View {
    @ObservedObject private var sync = PaperVNSync中心.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showsStopConfirmation = false

    private enum 阶段 {
        case 资料库减少
        case 导入方式
        case 检查更改
        case 确认
    }

    var body: some View {
        NavigationStack {
            Group {
                if sync.正在执行 || sync.最近结果 != nil {
                    同步进度页面()
                } else if let session = sync.待处理 {
                    switch 当前阶段(of: session) {
                    case .资料库减少: 资料库减少页面(session: session)
                    case .导入方式: 导入方式页面(session: session)
                    case .检查更改: 检查更改页面(session: session)
                    case .确认: 确认页面(session: session)
                    }
                } else {
                    平台内容不可用视图(
                        "没有需要确认的更改",
                        systemImage: "checkmark.circle",
                        description: Text("资料库已是最新。")
                    )
                }
            }
            .disabled(sync.正在处理)
            .overlay {
                if sync.正在处理 {
                    ProgressView("正在匹配作品…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .平台柔和滚动边缘(for: .top)
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("稍后", systemImage: "xmark")
                    }
                }
                if sync.待处理 != nil {
                    ToolbarItem(placement: .平台主操作) {
                        Menu {
                            Button("重新读取", systemImage: "arrow.clockwise") {
                                sync.重试()
                            }
                            Button("停止同步", systemImage: "stop.circle", role: .destructive) {
                                showsStopConfirmation = true
                            }
                        } label: {
                            Label("更多", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .confirmationDialog(
                "要停止同步吗？",
                isPresented: $showsStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("停止同步", role: .destructive) {
                    sync.取消待处理()
                }
            } message: {
                Text("资料库和各平台都不会被更改。下次同步时会再次检查。")
            }
        }
        .平台近全屏弹窗(dragIndicator: .visible)
    }

    private func 当前阶段(of session: 同步会话) -> 阶段 {
        if session.需要确认推送 && !session.已确认推送 { return .确认 }
        if session.冲突已生成 && !session.冲突.isEmpty { return .检查更改 }
        if session.需要选择导入方式 && session.导入方式 == nil { return .导入方式 }
        return .资料库减少
    }
}

/// 读取失败的平台没有参与这次同步，放在每一步的最上面。
private struct 读取失败分组: View {
    let session: 同步会话
    @ObservedObject private var sync = PaperVNSync中心.shared

    var body: some View {
        if !session.读取失败.isEmpty {
            Section {
                ForEach(session.读取失败.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { platform in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(platform.localizedTitle, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(verbatim: session.读取失败[platform] ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("重试") {
                    sync.重试()
                }
            } header: {
                Text("未能同步")
            } footer: {
                Text("这些平台没有完成同步。")
            }
        }
    }
}

// MARK: - 同步进度与结果

/// 确认后显示同步进度；完成后显示结果，用户点“完成”关闭。
private struct 同步进度页面: View {
    @ObservedObject private var sync = PaperVNSync中心.shared

    var body: some View {
        平台滚动页面 {
            if let result = sync.最近结果 {
                ForEach(result.平台) { platform in
                    Section {
                        if let message = platform.失败 {
                            Text(verbatim: message)
                                .foregroundStyle(.red)
                        }
                        统计行("添加", platform.添加)
                        统计行("更改", platform.更改)
                        统计行("删除", platform.删除)
                        统计行("无法删除", platform.无法删除)
                        if !platform.找不到.isEmpty {
                            DisclosureGroup {
                                ForEach(platform.找不到, id: \.self) { title in
                                    Text(verbatim: title)
                                        .font(.subheadline)
                                }
                            } label: {
                                LabeledContent("找不到对应的作品") {
                                    Text(verbatim: platform.找不到.count.formatted())
                                }
                            }
                        }
                        if platform.失败 == nil && platform.添加 + platform.更改 + platform.删除 + platform.无法删除 == 0 && platform.找不到.isEmpty {
                            Text("没有更改")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(verbatim: platform.平台.localizedTitle)
                    }
                }
            } else {
                Section {
                    ForEach(sync.执行平台, id: \.self) { platform in
                        HStack {
                            Text(verbatim: platform.localizedTitle)
                            Spacer()
                            进度文本(sync.任务[platform]?.状态)
                        }
                    }
                } footer: {
                    Text("关闭此页面不会中断同步。")
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle(sync.最近结果 == nil ? "正在同步" : "同步完成")
        .平台安全区域栏(edge: .bottom) {
            if sync.最近结果 != nil {
                底部按钮(String(localized: "完成"), isEnabled: true) {
                    sync.关闭结果()
                }
            }
        }
    }

    @ViewBuilder
    private func 进度文本(_ state: PaperVNSync中心.任务状态?) -> some View {
        switch state {
        case let .进行中(done, total?):
            Text(verbatim: "\(done.formatted())/\(total.formatted())")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        case .完成:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("已同步")
        case .失败:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("同步失败")
        default:
            ProgressView()
        }
    }

    @ViewBuilder
    private func 统计行(_ title: LocalizedStringKey, _ count: Int) -> some View {
        if count > 0 {
            LabeledContent(title) {
                Text(verbatim: count.formatted())
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - 作品数量减少

private struct 资料库减少页面: View {
    let session: 同步会话
    @ObservedObject private var sync = PaperVNSync中心.shared

    var body: some View {
        平台滚动页面 {
            读取失败分组(session: session)
            Section {
                Text("\(session.减少提示.map(\.平台.localizedTitle).joined(separator: "、"))上的作品比上次同步时少了很多。")
                    .foregroundStyle(.secondary)
            }
            ForEach(session.减少提示) { prompt in
                Section {
                    Picker(selection: Binding(
                        get: { session.减少处理[prompt.平台] },
                        set: { if let value = $0 { sync.选择减少处理(value, for: prompt.平台) } }
                    )) {
                        Text("保留并重新上传到\(prompt.平台.localizedTitle)")
                            .tag(Optional(减少处理.保留并重新上传))
                        Text("也从资料库中删除")
                            .tag(Optional(减少处理.同样删除))
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(verbatim: "\(prompt.平台.localizedTitle)（\(prompt.账户名称)）")
                } footer: {
                    Text("上次同步时有\(prompt.上次数量)部作品，当前有\(prompt.现在数量)部。")
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("作品数量减少")
        .平台安全区域栏(edge: .bottom) {
            底部按钮(
                String(localized: "继续"),
                isEnabled: session.减少提示.allSatisfy { session.减少处理[$0.平台] != nil }
            ) {
                sync.确认减少处理()
            }
        }
    }
}

// MARK: - 导入方式

private struct 导入方式页面: View {
    let session: 同步会话
    @ObservedObject private var sync = PaperVNSync中心.shared

    private enum 方式: Hashable, CaseIterable {
        case 合并
        case 覆盖
        case 分别保留
    }

    @State private var 方式选择: 方式 = .合并
    @State private var 来源选择: 同步来源?

    private var 已选来源: 同步来源? { 来源选择 ?? session.来源概况.first?.来源 }

    var body: some View {
        平台滚动页面 {
            读取失败分组(session: session)
            Section {
                ForEach(session.来源概况) { summary in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(verbatim: summary.来源.名称)
                            if let name = summary.账户名称 {
                                Text(verbatim: name)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(verbatim: 数量文本(summary))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if summary.账户已更换 {
                            Label("和上次同步的不是同一个账户", systemImage: "person.crop.circle.badge.exclamationmark")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("参与导入的资料库")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("这些资料库的内容不同，选择导入方式。")
                    ForEach(未参与说明, id: \.self) { line in
                        Text(verbatim: line)
                    }
                }
            }

            Section {
                Picker(selection: $方式选择) {
                    Text("合并").tag(方式.合并)
                    Text("覆盖资料库").tag(方式.覆盖)
                    Text("分别保留").tag(方式.分别保留)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowSeparator(.hidden)

                导入方式演示(
                    模式: 演示方式,
                    来源名称: 演示来源名称,
                    主要来源在右侧: 主要来源在右侧
                )
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden, edges: .top)

                if 方式选择 != .合并 {
                    Picker("资料库", selection: Binding(
                        get: { 已选来源 },
                        set: { 来源选择 = $0 }
                    )) {
                        ForEach(session.来源概况) { summary in
                            Text(verbatim: summary.来源.资料库名称)
                                .tag(Optional(summary.来源))
                        }
                    }
                    .pickerStyle(.menu)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(说明)
                    if 方式选择 != .合并, 已选来源 == .平台(.annict) {
                        Text("同步Annict动画，漫画与轻小说仍然合并。")
                    }
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("选择导入方式")
        .animation(.smooth(duration: 0.3), value: 方式选择)
        .平台安全区域栏(edge: .bottom) {
            底部按钮(String(localized: "继续"), isEnabled: 方式选择 == .合并 || 已选来源 != nil) {
                switch 方式选择 {
                case .合并:
                    sync.选择导入方式(.合并)
                case .覆盖:
                    if let source = 已选来源 { sync.选择导入方式(.为准(source)) }
                case .分别保留:
                    if let source = 已选来源 { sync.选择导入方式(.分别保留(source)) }
                }
            }
        }
    }

    private var 说明: LocalizedStringKey {
        switch 方式选择 {
        case .合并: "保留所有资料库中的作品。同一部作品的记录不同时进行手动确认。"
        case .覆盖: session.仅导入.isEmpty
            ? "所有平台的资料库将被所选资料库覆盖。"
            : "所有平台的资料库将被所选资料库覆盖。“仅导入”的平台不会被更改。"
        case .分别保留: "资料库将显示所选的内容。其他账户中多出的作品会保留在原来的平台上，并在资料库中隐藏。你可以稍后在“同步任务”中显示这些作品。"
        }
    }

    /// 没有出现在上面的平台和原因，例如“AniList、Annict和TMDB：没有登录。”
    private var 未参与说明: [String] {
        let 顺序: [未参与原因] = [.未登录, .同步方式为无, .仅导出, .资料库为空]
        return 顺序.compactMap { reason in
            let platforms = 资料库平台.动画漫画平台.filter { session.未参与[$0] == reason }
            guard !platforms.isEmpty else { return nil }
            let names = ListFormatter.localizedString(byJoining: platforms.map(\.localizedTitle))
            switch reason {
            case .未登录: return String(localized: "\(names)：没有登录，不参与导入。")
            case .同步方式为无: return String(localized: "\(names)：同步方式为“无”，不参与导入。")
            case .仅导出: return String(localized: "\(names)：同步方式为“仅导出”，资料库会同步到这些平台，但不从这些平台导入。")
            case .资料库为空: return String(localized: "\(names)：没有动画、漫画与轻小说。")
            }
        }
    }

    private var 演示方式: 导入方式演示.演示模式 {
        switch 方式选择 {
        case .合并: .合并
        case .覆盖: .覆盖
        case .分别保留: .分别保留
        }
    }

    /// 演示里的两张来源卡片用前两个来源的名称。
    private var 演示来源名称: (String, String) {
        let names = session.来源概况.prefix(2).map(\.来源.名称)
        return (names.first ?? "", names.count > 1 ? names[1] : "")
    }

    private var 主要来源在右侧: Bool {
        session.来源概况.count > 1 && 已选来源 == session.来源概况[1].来源
    }

    private func 数量文本(_ summary: 来源概况) -> String {
        作品类型.allCases
            .compactMap { type in summary.数量[type].map { "\(type.localizedTitle)\($0)" } }
            .joined(separator: "・")
    }
}

/// 用小方块演示三种导入方式：上方两张卡片是两个来源的资料库，下方是导入后的资料库。
/// 蓝色是两边都有的作品，绿色、橙色是只在一边的作品，紫色是记录不同的作品。
private struct 导入方式演示: View {
    enum 演示模式: Hashable { case 合并, 覆盖, 分别保留 }

    let 模式: 演示模式
    let 来源名称: (String, String)
    /// 覆盖、分别保留时，所选来源是右边那个。
    let 主要来源在右侧: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum 阶段: CaseIterable { case 来源, 导入, 结果 }

    private struct 方块: Identifiable, Hashable {
        enum 种类: Hashable { case 共同, 左侧独有, 右侧独有, 记录不同左, 记录不同右 }
        let id: String
        let 种类: 种类
    }

    private let 左侧 = [
        方块(id: "s1", 种类: .共同), 方块(id: "s2", 种类: .共同),
        方块(id: "c", 种类: .记录不同左), 方块(id: "a1", 种类: .左侧独有),
    ]
    private let 右侧 = [
        方块(id: "s1", 种类: .共同), 方块(id: "s2", 种类: .共同),
        方块(id: "c", 种类: .记录不同右), 方块(id: "b1", 种类: .右侧独有), 方块(id: "b2", 种类: .右侧独有),
    ]

    var body: some View {
        Group {
            if reduceMotion {
                画面(阶段: .结果)
            } else {
                画面(阶段: .来源)
                    .hidden()
                    .overlay {
                        // 持续循环；切换选项时用 id 重新开始。延迟让每个阶段停留足够久，看得清楚
                        PhaseAnimator(阶段.allCases) { phase in
                            画面(阶段: phase)
                        } animation: { phase in
                            switch phase {
                            case .来源: .easeInOut(duration: 0.4).delay(2.4)
                            case .导入: .smooth(duration: 1.0).delay(0.8)
                            case .结果: .smooth(duration: 0.9).delay(0.4)
                            }
                        }
                        .id("\(模式)\(主要来源在右侧)")
                    }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(无障碍说明)
    }

    private var 无障碍说明: Text {
        switch 模式 {
        case .合并: Text("合并")
        case .覆盖: Text("覆盖资料库")
        case .分别保留: Text("分别保留")
        }
    }

    private func 画面(阶段: 阶段) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                卡片(名称: 来源名称.0, 方块: 来源显示(左侧, 是左侧: true, 阶段: 阶段), 强调: 强调来源(左侧: true))
                卡片(名称: 来源名称.1, 方块: 来源显示(右侧, 是左侧: false, 阶段: 阶段), 强调: 强调来源(左侧: false))
            }
            Image(systemName: "arrow.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(阶段 == .来源 ? 0.3 : 1)
            卡片(名称: String(localized: "资料库"), 方块: 阶段 == .来源 ? [] : 结果方块, 强调: true, 宽: true)
        }
    }

    private func 强调来源(左侧: Bool) -> Bool {
        模式 != .合并 && (左侧 != 主要来源在右侧)
    }

    /// 来源卡片里的方块。覆盖时，被覆盖的平台上多出的作品在结果阶段淡出，记录不同的作品变成所选的版本。
    private func 来源显示(_ items: [方块], 是左侧: Bool, 阶段: 阶段) -> [(方块, 状态)] {
        let 是主要 = 是左侧 != 主要来源在右侧
        return items.map { item in
            guard 阶段 == .结果, 模式 != .合并, !是主要 else { return (item, .正常) }
            switch item.种类 {
            case .左侧独有, .右侧独有:
                return (item, 模式 == .覆盖 ? .移除 : .正常)
            case .记录不同左, .记录不同右:
                return (方块(id: item.id, 种类: 是左侧 ? .记录不同右 : .记录不同左), .正常)
            case .共同:
                return (item, .正常)
            }
        }
    }

    private var 结果方块: [(方块, 状态)] {
        let 主要 = 主要来源在右侧 ? 右侧 : 左侧
        let 其他 = 主要来源在右侧 ? 左侧 : 右侧
        let 其他独有 = 其他.filter { $0.种类 == .左侧独有 || $0.种类 == .右侧独有 }
        switch 模式 {
        case .合并:
            let 独有 = (左侧 + 右侧).filter { $0.种类 == .左侧独有 || $0.种类 == .右侧独有 }
            return [(左侧[0], .正常), (左侧[1], .正常), (方块(id: "c", 种类: .记录不同左), .待确认)]
                + 独有.map { ($0, .正常) }
        case .覆盖:
            return 主要.map { ($0, .正常) }
        case .分别保留:
            return 主要.map { ($0, .正常) } + 其他独有.map { ($0, .隐藏) }
        }
    }

    enum 状态: Hashable { case 正常, 待确认, 移除, 隐藏 }

    private func 卡片(名称: String, 方块 items: [(方块, 状态)], 强调: Bool, 宽: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: 名称)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 4) {
                ForEach(items, id: \.0.id) { item, state in
                    方块视图(item.种类, 状态: state)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(height: 26, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(强调 && !宽 ? 0.8 : 0), lineWidth: 1.5)
        }
    }

    private func 方块视图(_ kind: 方块.种类, 状态 state: 状态) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(颜色(kind))
            .frame(width: 18, height: 26)
            .opacity(state == .隐藏 ? 0.3 : state == .移除 ? 0 : 1)
            .scaleEffect(state == .移除 ? 0.6 : 1)
            .overlay {
                switch state {
                case .待确认:
                    Image(systemName: "questionmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                case .隐藏:
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }
    }

    private func 颜色(_ kind: 方块.种类) -> Color {
        switch kind {
        case .共同: .blue.opacity(0.75)
        case .左侧独有: .green.opacity(0.8)
        case .右侧独有: .orange.opacity(0.85)
        case .记录不同左: .purple.opacity(0.8)
        case .记录不同右: .purple.opacity(0.4)
        }
    }
}

// MARK: - 检查更改

private struct 检查更改页面: View {
    let session: 同步会话
    @ObservedObject private var sync = PaperVNSync中心.shared

    private var 未选择数: Int { session.冲突.filter { $0.选择 == nil }.count }

    private var 来源: [同步来源] {
        var values: [同步来源] = []
        for conflict in session.冲突 {
            for version in conflict.版本 where !values.contains(version.来源) {
                values.append(version.来源)
            }
        }
        return values
    }

    var body: some View {
        平台滚动页面 {
            读取失败分组(session: session)
            let external = session.冲突.filter { $0.种类 == .外部更改 }
            let different = session.冲突.filter { $0.种类 == .记录不同 }
            // 每组的标题和说明放在第一部作品的分组标题里，不单独占一个卡片
            ForEach(Array(external.enumerated()), id: \.element.id) { index, conflict in
                冲突分组(
                    conflict: conflict,
                    分组标题: index == 0 ? String(localized: "其他平台上的更改") : nil,
                    分组说明: index == 0 ? String(localized: "这些更改似乎不是通过PaperVN进行的。选择要保留的记录，所选的记录会同步到其他平台。") : nil
                )
            }
            ForEach(Array(different.enumerated()), id: \.element.id) { index, conflict in
                冲突分组(
                    conflict: conflict,
                    分组标题: index == 0 ? String(localized: "记录不同") : nil,
                    分组说明: index == 0 ? String(localized: "这些作品在不同的地方被改成了不同的记录。为每部作品选择要保留的记录。") : nil
                )
            }
        }
        .平台分组列表样式()
        .navigationTitle("检查更改")
        .toolbar {
            ToolbarItem(placement: .平台主操作) {
                Menu {
                    ForEach(来源, id: \.self) { source in
                        Button {
                            sync.全部选择(source)
                        } label: {
                            Text("全部使用\(source.资料库名称)")
                        }
                    }
                } label: {
                    Label("全部使用", systemImage: "checklist")
                }
            }
        }
        .平台安全区域栏(edge: .bottom) {
            底部按钮(
                未选择数 > 0 ? String(localized: "还有\(未选择数)个项目未选择") : String(localized: "继续"),
                isEnabled: 未选择数 == 0
            ) {
                sync.确认冲突()
            }
        }
    }
}

private struct 冲突分组: View {
    let conflict: 条目冲突
    var 分组标题: String? = nil
    var 分组说明: String? = nil
    @ObservedObject private var sync = PaperVNSync中心.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false

    private var 标题: 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: conflict.多语言标题,
            defaultTitle: conflict.标题,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    var body: some View {
        Section {
            // 作品本身是卡片的第一行，下面是可选的记录
            HStack(spacing: 12) {
                CachedAsyncImage(url: conflict.封面地址.flatMap(URL.init(string:)), contentMode: .fill)
                    .frame(width: 40, height: 56)
                    .clipped()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) * 0.6, style: .continuous))
                    .accessibilityHidden(true)
                多语言列表文本(
                    标题,
                    层级: .主标题,
                    系统字体粗细: 标题.languageCode == 标题语言.chinese.langCode ? .medium : nil
                )
                .lineLimit(2)
                Spacer(minLength: 0)
            }
            ForEach(conflict.版本) { version in
                Button {
                    sync.选择冲突版本(version.来源, for: conflict.键)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: version.来源.名称)
                                .foregroundStyle(.primary)
                            Text(verbatim: 版本说明(version))
                                .font(.footnote)
                                .foregroundStyle(version.快照 == nil ? .red : .secondary)
                        }
                        Spacer()
                        if conflict.选择 == version.来源 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityLabel("已选择")
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            if let 分组标题 {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: 分组标题)
                    if let 分组说明 {
                        Text(verbatim: 分组说明)
                            .font(.footnote)
                            .textCase(nil)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func 版本说明(_ version: 同步版本) -> String {
        guard let value = version.快照 else {
            return version.来源 == .本地 ? String(localized: "不在资料库中") : String(localized: "已删除")
        }
        let type = conflict.类型
        let ability = version.来源.能力
        var parts = [value.状态.localizedTitle(for: type)]
        if ability.支持进度 {
            let progress = value.进度 ?? 0
            parts.append(type == .anime ? String(localized: "第\(progress)集") : String(localized: "第\(progress)话"))
        }
        if ability.评分步长 != nil {
            parts.append(value.评分.map { String(localized: "\(String(format: "%.1f", Double($0) / 10))分") }
                ?? String(localized: "未评分"))
        }
        return parts.joined(separator: "・")
    }
}

// MARK: - 确认同步

private struct 确认页面: View {
    let session: 同步会话
    @ObservedObject private var sync = PaperVNSync中心.shared

    /// 要写入的平台；只导入的平台（Bangumi）没有要写入的内容，不单独列出。
    private var 平台: [资料库平台] {
        session.平台.keys.filter(session.可导出).sorted { $0.rawValue < $1.rawValue }
    }

    private var 只导入平台: [资料库平台] {
        session.平台.keys.filter { !session.可导出($0) }.sorted { $0.rawValue < $1.rawValue }
    }

    var body: some View {
        平台滚动页面 {
            读取失败分组(session: session)
            if session.需要选择修改时间来源 {
                Section {
                    Picker(selection: Binding(
                        get: { session.修改时间来源 },
                        set: { if let value = $0 { sync.选择修改时间来源(value) } }
                    )) {
                        ForEach(session.可选修改时间来源, id: \.self) { platform in
                            Text(verbatim: platform.localizedTitle)
                                .tag(Optional(platform))
                        }
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("选择“最近更改”的依据")
                } footer: {
                    Text("资料库按“最近更改”排序时，使用所选平台上的更改时间。")
                }
            }
            Section {
                let changes = 资料库变化
                统计行("添加", changes.added)
                统计行("更改", changes.modified)
                统计行("删除", changes.removed)
                统计行("隐藏", session.新隐藏.count)
                if changes.added + changes.modified + changes.removed + session.新隐藏.count == 0 {
                    Text("没有更改")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(verbatim: 同步来源.本地名称)
            } footer: {
                ForEach(只导入平台, id: \.self) { platform in
                    Text("\(platform.localizedTitle)上的作品只会导入到资料库，资料库中的更改不会同步到\(platform.localizedTitle)。")
                }
            }

            ForEach(平台, id: \.self) { platform in
                let operations = session.推送.filter { $0.平台 == platform }
                let unmatched = session.未匹配[platform]?.count ?? 0
                let cannotDelete = session.无法删除[platform]?.count ?? 0
                let deletions = operations.filter { $0.种类 == .删除 }
                Section {
                    统计行("添加", operations.filter { $0.种类 == .新增 }.count)
                    统计行("更改", operations.filter { $0.种类 == .修改 }.count)
                    统计行("删除", deletions.count)
                    if unmatched > 0 {
                        LabeledContent("找不到对应的作品") {
                            Text(verbatim: unmatched.formatted())
                                .foregroundStyle(.orange)
                        }
                    }
                    if cannotDelete > 0 {
                        LabeledContent("无法删除") {
                            Text(verbatim: cannotDelete.formatted())
                                .foregroundStyle(.orange)
                        }
                    }
                    if operations.isEmpty && unmatched == 0 && cannotDelete == 0 {
                        Text("没有更改")
                            .foregroundStyle(.secondary)
                    }
                    if !deletions.isEmpty {
                        DisclosureGroup("将删除的作品") {
                            ForEach(deletions) { operation in
                                Text(verbatim: operation.标题)
                                    .font(.subheadline)
                            }
                        }
                    }
                } header: {
                    Text(verbatim: "\(platform.localizedTitle)（\(session.平台[platform]?.账户名称 ?? "")）")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if unmatched > 0 {
                            Text("在\(platform.localizedTitle)上找不到对应的作品，这些作品不会同步到\(platform.localizedTitle)。")
                        }
                        if cannotDelete > 0 {
                            Text("\(platform.localizedTitle)不支持通过PaperVN删除作品，需要在\(platform.localizedTitle)上手动删除。")
                        }
                        if operations.contains(where: { $0.种类 == .新增 && $0.平台ID == nil }) {
                            Text("添加前会先在\(platform.localizedTitle)上查找对应的作品，找不到的不会添加。")
                        }
                    }
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("确认同步")
        .平台安全区域栏(edge: .bottom) {
            底部按钮(
                !session.需要选择修改时间来源 || session.修改时间来源 != nil
                    ? String(localized: "同步")
                    : String(localized: "请选择“最近更改”的依据"),
                isEnabled: !session.需要选择修改时间来源 || session.修改时间来源 != nil
            ) {
                sync.确认推送()
            }
        }
    }

    private var 资料库变化: (added: Int, modified: Int, removed: Int) {
        let before = session.本地.filter { session.新隐藏[$0.key] == nil }
        let after = 同步合并.新资料库(session)
        let added = after.keys.filter { before[$0] == nil }.count
        let removed = before.keys.filter { after[$0] == nil }.count
        let modified = after.filter { key, entry in
            guard let old = before[key] else { return false }
            return 同步合并.快照(old) != 同步合并.快照(entry)
        }.count
        return (added, modified, removed)
    }

    @ViewBuilder
    private func 统计行(_ title: LocalizedStringKey, _ count: Int) -> some View {
        if count > 0 {
            LabeledContent(title) {
                Text(verbatim: count.formatted())
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - 共用

private struct 底部按钮: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    init(_ title: String, isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Group {
            if isEnabled {
                Button(action: action) {
                    Text(verbatim: title)
                        .frame(maxWidth: .infinity)
                }
                .液态玻璃醒目按钮(in: Capsule())
            } else {
                // 不可用时用普通液态玻璃，不显示成发黑的醒目按钮
                Button(action: action) {
                    Text(verbatim: title)
                        .frame(maxWidth: .infinity)
                }
                .液态玻璃按钮(in: Capsule())
                .disabled(true)
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// 在 App 根视图和“账户与设置”上都挂上这个修饰器，处理页面由最上层的那个弹出。
/// 单独观察 PaperVN Sync，同步进度变化时不会让所在的整个页面重新计算。
struct 同步待处理弹出: ViewModifier {
    @ObservedObject private var sync = PaperVNSync中心.shared
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { sync.注册弹出层级(id) }
            .onDisappear { sync.注销弹出层级(id) }
            .sheet(isPresented: Binding(
                get: { sync.显示待处理 && sync.弹出层级.last == id },
                set: { if !$0 { sync.显示待处理 = false } }
            )) {
                同步待处理页面()
            }
    }
}
