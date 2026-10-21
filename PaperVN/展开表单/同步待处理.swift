import SwiftUI

/// PaperVN Sync 遇到需要用户决定的情况时弹出：作品数量大幅减少、多个资料库内容不同、
/// 不是在 PaperVN 中做的更改、同一部作品记录不同，以及第一次同步前的确认。
/// 一步一步引导用户，可以返回上一步重新选择；确认后立即关闭，进度显示在资料库顶部和同步任务页面。
/// 关闭页面只是稍后再处理；“停止同步”才会丢弃这次读到的数据。
struct 同步待处理页面: View {
    @ObservedObject private var sync = PaperVNSync中心.shared

    private enum 阶段 {
        case 资料库减少
        case 导入方式
        case 检查更改
        case 确认
    }

    var body: some View {
        NavigationStack {
            if let session = sync.待处理 {
                Group {
                    switch 当前阶段(of: session) {
                    case .资料库减少: 资料库减少页面(session: session)
                    case .导入方式: 导入方式页面(session: session)
                    case .检查更改: 检查更改页面(session: session)
                    case .确认: 确认页面(session: session)
                    }
                }
                // 前进、返回时整页换掉，不保留上一步页面里的滚动位置和临时选择
                .id(sync.上一步.count)
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: sync.上一步.count)
        .平台近全屏弹窗(dragIndicator: .visible)
    }

    private func 当前阶段(of session: 同步会话) -> 阶段 {
        if session.需要确认推送 && !session.已确认推送 { return .确认 }
        if session.冲突已生成 && !session.冲突.isEmpty { return .检查更改 }
        if session.需要选择导入方式 && session.导入方式 == nil { return .导入方式 }
        return .资料库减少
    }
}

// MARK: - 每一步共用的框架

/// 每一步的导航栏、顶部说明和底部按钮。
/// 导航栏左侧关闭（稍后再处理）；右侧是同步菜单（重新读取、停止同步），需要时最右侧单独放“更多”菜单。
/// 底部有上一步时显示“上一步”，主按钮在右侧。
private struct 同步步骤框架<More: View>: ViewModifier {
    let 标题: LocalizedStringKey
    let 主按钮标题: String
    let 主按钮可用: Bool
    let 主操作: () -> Void
    /// 最右侧单独的“更多”菜单，例如检查更改时“全部使用…”。
    let 有更多菜单: Bool
    @ViewBuilder let 更多菜单: () -> More

    @ObservedObject private var sync = PaperVNSync中心.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showsStopConfirmation = false

    func body(content: Content) -> some View {
        content
            .平台分组列表样式()
            // 第一行是一句说明，不需要分组列表默认的顶部留白
            .contentMargins(.top, 4, for: .scrollContent)
            // 标题用大标题放在内容顶部（和新功能介绍一致），导航栏不再重复显示
            .navigationTitle(标题)
            .toolbar(removing: .title)
            .平台内联导航标题()
            .平台柔和滚动边缘(for: .top)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("稍后", systemImage: "xmark")
                    }
                }
                ToolbarItem(placement: .平台主操作) {
                    Menu {
                        Button("重新读取", systemImage: "arrow.clockwise") {
                            sync.重试()
                        }
                        Button("停止同步", systemImage: "stop.circle", role: .destructive) {
                            showsStopConfirmation = true
                        }
                    } label: {
                        Label("同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    // 挂在按钮上：确认从这个按钮展开，和放弃资料库编辑的确认一致
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
                if 有更多菜单 {
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .平台主操作)
                    }
                    ToolbarItem(placement: .平台主操作) {
                        Menu {
                            更多菜单()
                        } label: {
                            Label("更多", systemImage: "ellipsis")
                        }
                    }
                }
            }
            .平台安全区域栏(edge: .bottom) {
                同步步骤按钮栏(
                    可返回: !sync.上一步.isEmpty,
                    主按钮标题: 主按钮标题,
                    主按钮可用: 主按钮可用,
                    返回: { sync.返回上一步() },
                    主操作: 主操作
                )
            }
    }
}

private extension View {
    func 同步步骤(
        _ 标题: LocalizedStringKey,
        主按钮标题: String,
        主按钮可用: Bool = true,
        主操作: @escaping () -> Void
    ) -> some View {
        modifier(同步步骤框架(
            标题: 标题,
            主按钮标题: 主按钮标题, 主按钮可用: 主按钮可用, 主操作: 主操作,
            有更多菜单: false, 更多菜单: { EmptyView() }
        ))
    }

    func 同步步骤<More: View>(
        _ 标题: LocalizedStringKey,
        主按钮标题: String,
        主按钮可用: Bool = true,
        主操作: @escaping () -> Void,
        @ViewBuilder 更多菜单: @escaping () -> More
    ) -> some View {
        modifier(同步步骤框架(
            标题: 标题,
            主按钮标题: 主按钮标题, 主按钮可用: 主按钮可用, 主操作: 主操作,
            有更多菜单: true, 更多菜单: 更多菜单
        ))
    }
}

/// 表示第几步的小标记：走过的步骤是小圆点，当前步骤拉长。
private struct 同步步骤标记: View {
    @ObservedObject private var sync = PaperVNSync中心.shared

    var body: some View {
        let current = sync.上一步.count
        HStack(spacing: 4) {
            ForEach(0...current, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: index == current ? 14 : 4, height: 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("第\(current + 1)步"))
    }
}

/// 每一步最上面的大标题和一句话说明，靠左对齐，排版和新功能介绍一致；不放在卡片里。
private struct 同步步骤说明: View {
    let 标题: LocalizedStringKey
    let 说明: String

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                // 第几步的标记和大标题同一高度，靠右
                HStack(alignment: .center) {
                    Text(标题)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 12)
                    同步步骤标记()
                }
                Text(verbatim: 说明)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
    }
}

private struct 同步步骤按钮栏: View {
    let 可返回: Bool
    let 主按钮标题: String
    let 主按钮可用: Bool
    let 返回: () -> Void
    let 主操作: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if 可返回 {
                Button(action: 返回) {
                    Label("上一步", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .font(.body.weight(.semibold))
                        .frame(width: 24, height: 24)
                }
                .液态玻璃按钮(in: Circle())
                .buttonBorderShape(.circle)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                if 主按钮可用 {
                    Button(action: 主操作) {
                        Text(verbatim: 主按钮标题)
                            .frame(maxWidth: .infinity)
                    }
                    .液态玻璃醒目按钮(in: Capsule())
                } else {
                    // 不可用时用普通液态玻璃，不显示成发黑的醒目按钮
                    Button(action: 主操作) {
                        Text(verbatim: 主按钮标题)
                            .frame(maxWidth: .infinity)
                    }
                    .液态玻璃按钮(in: Capsule())
                    .disabled(true)
                }
            }
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}

/// 读取失败的平台没有参与这次同步，放在每一步的说明下面。
private struct 读取失败分组: View {
    let session: 同步会话
    @ObservedObject private var sync = PaperVNSync中心.shared

    var body: some View {
        if !session.读取失败.isEmpty {
            Section {
                ForEach(session.读取失败.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { platform in
                    VStack(alignment: .leading, spacing: 2) {
                        // 不用 Label：列表里的 Label 会给图标留出很宽的位置，图标也会和标题一样大
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                            Text(verbatim: platform.localizedTitle)
                        }
                        Text(verbatim: session.读取失败[platform] ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                Button("重试") {
                    sync.重试()
                }
            } header: {
                Text("未能同步")
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
            同步步骤说明(标题: "作品数量减少", 说明: 说明)
            读取失败分组(session: session)
            ForEach(session.减少提示) { prompt in
                Section {
                    作品数量对比(上次: prompt.上次数量, 现在: prompt.现在数量)
                    Picker(selection: Binding(
                        get: { session.减少处理[prompt.平台] },
                        set: { if let value = $0 { sync.选择减少处理(value, for: prompt.平台) } }
                    )) {
                        Text("保留并重新上传到\(prompt.平台.localizedTitle)")
                            .tag(Optional(减少处理.保留并重新上传))
                        Text("从资料库中删除")
                            .tag(Optional(减少处理.同样删除))
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text(verbatim: "\(prompt.平台.localizedTitle)（\(prompt.账户名称)）")
                }
            }
        }
        .同步步骤(
            "作品数量减少",
            主按钮标题: String(localized: "继续"),
            主按钮可用: session.减少提示.allSatisfy { session.减少处理[$0.平台] != nil }
        ) {
            sync.确认减少处理()
        }
    }


    private var 说明: String {
        String(localized: "\(session.减少提示.map(\.平台.localizedTitle).顿号并列)上的作品比上次同步时少了很多。")
    }
}

/// 上次同步与现在的作品数，用两条长度不同的横条对比；出现时现在的那条从上次的长度缩短。
private struct 作品数量对比: View {
    let 上次: Int
    let 现在: Int
    @State private var 已显示 = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            横条(标题: "上次同步", 数量: 上次, 比例: 1, 颜色: .secondary.opacity(0.35))
            横条(
                标题: "当前",
                数量: 已显示 ? 现在 : 上次,
                比例: 已显示 ? Double(现在) / Double(max(上次, 1)) : 1,
                颜色: .orange
            )
        }
        .padding(.vertical, 6)
        .onAppear {
            guard !已显示 else { return }
            if reduceMotion {
                已显示 = true
            } else {
                withAnimation(.smooth(duration: 1.1).delay(0.35)) { 已显示 = true }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func 横条(标题: LocalizedStringKey, 数量: Int, 比例: Double, 颜色: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(标题)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: 数量.formatted())
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(数量)))
            }
            GeometryReader { proxy in
                Capsule()
                    .fill(颜色)
                    // 作品全部消失时也留一点长度，看得出这是一条横条
                    .frame(width: max(proxy.size.width * 比例, 6))
            }
            .frame(height: 8)
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
            同步步骤说明(标题: "选择导入方式", 说明: 说明文字)
            读取失败分组(session: session)

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
                    来源名称: session.来源概况.map(\.来源.名称),
                    主要来源: 主要来源序号,
                    选择来源: 方式选择 == .合并 ? nil : { index in
                        来源选择 = session.来源概况[index].来源
                    }
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
                    Text(方式说明)
                    if 方式选择 != .合并, 已选来源 == .平台(.annict) {
                        Text("同步Annict动画，漫画与轻小说仍然合并。")
                    }
                }
            }

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
                            // 不用 Label：列表里的 Label 会给图标留出很宽的位置
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "person.crop.circle.badge.exclamationmark")
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                                Text("与上次同步的账户不一致")
                            }
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("参与导入的资料库")
            }
        }
        .animation(.smooth(duration: 0.3), value: 方式选择)
        .同步步骤(
            "选择导入方式",
            主按钮标题: String(localized: "继续"),
            主按钮可用: 方式选择 == .合并 || 已选来源 != nil
        ) {
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


    private var 说明文字: String { String(localized: "这些资料库的内容不同，选择导入方式。") }

    private var 方式说明: LocalizedStringKey {
        switch 方式选择 {
        case .合并: "保留所有资料库中的作品，并手动确认冲突内容。"
        case .覆盖: session.仅导入.isEmpty
            ? "所有平台的资料库将被所选资料库覆盖。"
            : "所有平台的资料库将被所选资料库覆盖。“仅导入”的平台不会被更改。"
        case .分别保留: "资料库将显示所选的内容。其他作品会被保留在原来的平台上，并在资料库中隐藏。你可以稍后在“同步任务”中显示这些作品。"
        }
    }

    private var 演示方式: 导入方式演示.演示模式 {
        switch 方式选择 {
        case .合并: .合并
        case .覆盖: .覆盖
        case .分别保留: .分别保留
        }
    }

    private var 主要来源序号: Int {
        session.来源概况.firstIndex { $0.来源 == 已选来源 } ?? 0
    }

    private func 数量文本(_ summary: 来源概况) -> String {
        作品类型.allCases
            .compactMap { type in summary.数量[type].map { "\(type.localizedTitle)\($0)" } }
            .joined(separator: "・")
    }
}

/// 用小方块演示三种导入方式：上方每张卡片是一个参与导入的资料库（有几个就显示几个），下方是导入后的资料库。
/// 蓝色是所有资料库都有的作品，其他颜色是只在某一个资料库里的作品，紫色深浅不同的是记录不同的作品。
/// 覆盖、分别保留时可以点按卡片选择以哪个资料库为准。
private struct 导入方式演示: View {
    enum 演示模式: Hashable { case 合并, 覆盖, 分别保留 }

    let 模式: 演示模式
    let 来源名称: [String]
    /// 覆盖、分别保留时所选的资料库。
    let 主要来源: Int
    var 选择来源: ((Int) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum 阶段: CaseIterable { case 来源, 导入, 结果 }

    private struct 方块: Identifiable, Hashable {
        enum 种类: Hashable {
            case 共同
            case 独有(Int)
            case 记录不同(Int)
        }
        let id: String
        let 种类: 种类
    }

    enum 状态: Hashable { case 正常, 待确认, 移除, 隐藏 }

    /// 每个资料库里的作品：两部共同的、一部记录不同的、一部只有它有的。
    private func 作品(_ index: Int) -> [方块] {
        [
            方块(id: "s1", 种类: .共同),
            方块(id: "s2", 种类: .共同),
            方块(id: "c", 种类: .记录不同(index)),
            独有作品(index),
        ]
    }

    private func 独有作品(_ index: Int) -> 方块 {
        方块(id: "u\(index)", 种类: .独有(index))
    }

    var body: some View {
        Group {
            if reduceMotion {
                画面(阶段: .结果)
            } else {
                画面(阶段: .结果)
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
                        .id("\(模式)\(主要来源)")
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
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(来源名称.indices, id: \.self) { index in
                    卡片(
                        名称: 来源名称[index],
                        方块: 来源显示(index, 阶段: 阶段),
                        强调: 模式 != .合并 && index == 主要来源
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onTapGesture {
                        选择来源?(index)
                    }
                }
            }
            Image(systemName: "arrow.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .opacity(阶段 == .来源 ? 0.3 : 1)
            卡片(名称: String(localized: "资料库"), 方块: 阶段 == .来源 ? [] : 结果方块, 强调: false)
        }
    }

    /// 来源卡片里的方块。覆盖、分别保留时，其他资料库里记录不同的作品变成所选的版本、加入所选资料库独有的作品；
    /// 覆盖时它们多出的作品在结果阶段淡出。
    private func 来源显示(_ index: Int, 阶段: 阶段) -> [(方块, 状态)] {
        let items = 作品(index)
        guard 阶段 == .结果, 模式 != .合并, index != 主要来源 else { return items.map { ($0, .正常) } }
        var shown: [(方块, 状态)] = items.map { item in
            switch item.种类 {
            case .独有:
                return (item, 模式 == .覆盖 ? .移除 : .正常)
            case .记录不同:
                return (方块(id: item.id, 种类: .记录不同(主要来源)), .正常)
            case .共同:
                return (item, .正常)
            }
        }
        shown.append((独有作品(主要来源), .正常))
        return shown
    }

    private var 结果方块: [(方块, 状态)] {
        switch 模式 {
        case .合并:
            return [
                (方块(id: "s1", 种类: .共同), .正常),
                (方块(id: "s2", 种类: .共同), .正常),
                (方块(id: "c", 种类: .记录不同(0)), .待确认),
            ] + 来源名称.indices.map { (独有作品($0), .正常) }
        case .覆盖:
            return 作品(主要来源).map { ($0, .正常) }
        case .分别保留:
            return 作品(主要来源).map { ($0, .正常) }
                + 来源名称.indices.filter { $0 != 主要来源 }.map { (独有作品($0), .隐藏) }
        }
    }

    private func 卡片(名称: String, 方块 items: [(方块, 状态)], 强调: Bool) -> some View {
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
                .strokeBorder(Color.accentColor.opacity(强调 ? 0.8 : 0), lineWidth: 1.5)
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

    private static let 独有颜色: [Color] = [.green, .orange, .pink, .teal, .yellow, .indigo, .mint]
    private static let 记录不同透明度: [Double] = [0.85, 0.4, 0.65, 0.3, 0.55, 0.75, 0.5]

    private func 颜色(_ kind: 方块.种类) -> Color {
        switch kind {
        case .共同: .blue.opacity(0.75)
        case let .独有(index): Self.独有颜色[index % Self.独有颜色.count].opacity(0.85)
        case let .记录不同(index): .purple.opacity(Self.记录不同透明度[index % Self.记录不同透明度.count])
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
            同步步骤说明(标题: "检查更改", 说明: 说明)
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
        .同步步骤(
            "检查更改",
            主按钮标题: 未选择数 > 0 ? String(localized: "还有\(未选择数)个项目未选择") : String(localized: "继续"),
            主按钮可用: 未选择数 == 0
        ) {
            sync.确认冲突()
        } 更多菜单: {
            ForEach(来源, id: \.self) { source in
                Button {
                    sync.全部选择(source)
                } label: {
                    Text("全部使用\(source.资料库名称)")
                }
            }
        }
    }


    private var 说明: String { String(localized: "有\(session.冲突.count)项更改需要确认。") }
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
            // 中文动画和漫画都用“话”，其他语言动画是“集”，用单独的键
            parts.append(type == .anime
                ? String(localized: "动画第几话", defaultValue: "第\(progress)话")
                : String(localized: "第\(progress)话"))
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

    private var 可以同步: Bool { !session.需要选择修改时间来源 || session.修改时间来源 != nil }

    var body: some View {
        平台滚动页面 {
            同步步骤说明(标题: "确认同步", 说明: 说明)
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
                    Text("“最近更改”的依据")
                } footer: {
                    Text("资料库按“最近更改”排序时，使用所选平台上的更改时间。")
                }
            }

            // 每个资料库一行：名称在上，要进行的更改在下（只有文字和数字，不放图形）；需要注意的另起一行用橙色。
            Section {
                let changes = 资料库变化
                更改行(
                    名称: 同步来源.本地名称,
                    账户: nil,
                    项目: [("添加", changes.added), ("更改", changes.modified), ("删除", changes.removed), ("隐藏", session.新隐藏.count)],
                    注意: []
                )
                ForEach(平台, id: \.self) { platform in
                    let operations = session.推送.filter { $0.平台 == platform }
                    let deletions = operations.filter { $0.种类 == .删除 }
                    let row = 更改行(
                        名称: platform.localizedTitle,
                        账户: session.平台[platform]?.账户名称,
                        项目: [
                            ("添加", operations.filter { $0.种类 == .新增 }.count),
                            ("更改", operations.filter { $0.种类 == .修改 }.count),
                            ("删除", deletions.count),
                        ],
                        注意: [
                            ("缺失", session.未匹配[platform]?.count ?? 0),
                            ("无法删除", session.无法删除[platform]?.count ?? 0),
                        ]
                    )
                    if deletions.isEmpty {
                        row
                    } else {
                        // 有要删除的作品时可以点进去查看是哪些
                        NavigationLink {
                            List(deletions) { operation in
                                Text(verbatim: operation.标题)
                            }
                            .navigationTitle("将删除的作品")
                            .平台内联导航标题()
                        } label: {
                            row
                        }
                    }
                }
            }
        }
        .同步步骤(
            "确认同步",
            主按钮标题: 可以同步 ? String(localized: "同步") : String(localized: "请选择“最近更改”的依据"),
            主按钮可用: 可以同步
        ) {
            sync.确认推送()
        }
    }

    private var 说明: String { String(localized: "确认以同步动画、漫画与轻小说。") }

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
}

/// 确认同步时一个资料库的一行：名称（和浅色的账户名），下面是“添加 2　更改 1”这样的文字；
/// 需要注意的（找不到、无法删除）另起一行用橙色。都没有时显示“没有更改”。
private struct 更改行: View {
    let 名称: String
    let 账户: String?
    let 项目: [(LocalizedStringKey, Int)]
    let 注意: [(LocalizedStringKey, Int)]

    var body: some View {
        let items = 项目.filter { $0.1 > 0 }
        let warnings = 注意.filter { $0.1 > 0 }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: 名称)
                if let 账户, !账户.isEmpty {
                    Text(verbatim: 账户)
                        .foregroundStyle(.secondary)
                }
            }
            if items.isEmpty && warnings.isEmpty {
                Text("没有更改")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !items.isEmpty {
                数量(items)
                    .foregroundStyle(.secondary)
            }
            if !warnings.isEmpty {
                数量(warnings)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func 数量(_ values: [(LocalizedStringKey, Int)]) -> some View {
        HStack(spacing: 14) {
            ForEach(values.indices, id: \.self) { index in
                HStack(spacing: 4) {
                    Text(values[index].0)
                    Text(verbatim: values[index].1.formatted())
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
            }
        }
        .font(.subheadline)
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
                // 没有需要处理的内容时不弹出：确认后、停止同步后页面直接关闭
                get: { sync.显示待处理 && sync.待处理 != nil && sync.弹出层级.last == id },
                set: { if !$0 { sync.显示待处理 = false } }
            )) {
                同步待处理页面()
            }
    }
}

#if DEBUG
// MARK: - 预览

#Preview("PaperVN Sync待处理（弹出样式）") {
    预览准备({ PaperVNSync中心.shared.预览设置(待处理: 预览数据.检查更改会话()) }) {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                同步待处理页面()
            }
    }
}

#Preview("PaperVN Sync待处理：所有状态") {
    let sync = PaperVNSync中心.shared
    预览状态切换([
        .init("作品数量减少", 准备: { sync.预览设置(待处理: 预览数据.资料库减少会话) }) { 同步待处理页面() },
        .init("选择导入方式", 准备: { sync.预览设置(待处理: 预览数据.导入方式会话()) }) { 同步待处理页面() },
        .init("选择导入方式（有平台未能同步）", 准备: { sync.预览设置(待处理: 预览数据.导入方式会话(读取失败: true)) }) { 同步待处理页面() },
        .init("检查更改（可返回上一步）", 准备: {
            sync.预览设置(待处理: 预览数据.检查更改会话(), 上一步: [预览数据.导入方式会话()])
        }) { 同步待处理页面() },
        .init("检查更改（已全部选择）", 准备: { sync.预览设置(待处理: 预览数据.检查更改会话(全部已选择: true)) }) { 同步待处理页面() },
        .init("确认同步", 准备: {
            sync.预览设置(待处理: 预览数据.确认会话(), 上一步: [预览数据.检查更改会话(全部已选择: true)])
        }) { 同步待处理页面() },
        .init("确认同步（首次同步）", 准备: { sync.预览设置(待处理: 预览数据.确认会话(首次同步: true)) }) { 同步待处理页面() },
    ])
}
#endif
