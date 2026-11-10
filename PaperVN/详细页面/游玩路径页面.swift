import Charts
import SwiftUI

/// 游玩路径：游玩时长、每个周期玩了多久、在一天中的什么时候玩。
/// 不传作品时显示所有作品（“账户与设置”进入），传作品时只显示这一部（资料库编辑页面进入）。
struct 游玩路径页面: View {
    var vnID: String?

    @ObservedObject private var 中心 = 游玩路径中心.shared
    @ObservedObject private var account = PaperAccount账户.shared
    @State private var 周期: 游玩路径周期 = .周
    /// 正在查看的周期里的任意一个时间点。
    @State private var 基准日期 = Date.now
    @State private var 已定位最近 = false
    @State private var 作品内容: [String: 作品列表行内容] = [:]
    @作品列表标题偏好读取 private var 标题偏好

    private let 日历 = Calendar.current

    private var 所有时间段: [游玩时间段] {
        guard let vnID else { return 中心.时间段 }
        return 中心.时间段(作品: vnID)
    }

    private var 当前范围: DateInterval {
        日历.dateInterval(of: 周期.日历单位, for: 基准日期) ?? DateInterval(start: 基准日期, duration: 86400)
    }

    private var 范围内时间段: [游玩时间段] {
        let range = 当前范围
        return 所有时间段
            .filter { $0.endedAt > range.start && $0.startedAt < range.end }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var 可前往下一周期: Bool { 当前范围.end <= .now }

    private var 可前往上一周期: Bool {
        guard let earliest = 所有时间段.map(\.startedAt).min() else { return false }
        return 当前范围.start > earliest
    }

    var body: some View {
        Group {
            if 中心.有数据来源 {
                内容页面
            } else if account.isLoggedIn && !中心.已加载 && 中心.错误 == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                游玩路径占位页面()
            }
        }
        .navigationTitle("游玩路径")
        .平台内联导航标题()
        .task(id: account.资料?.id) { await 中心.刷新() }
    }

    private var 内容页面: some View {
        平台滚动页面 {
            Section {
                LabeledContent("游玩时长") {
                    Text(verbatim: 游玩路径统计.时长文本(游玩路径统计.总秒数(所有时间段)))
                }
            } footer: {
                if let error = 中心.错误 {
                    Text(verbatim: error)
                }
            }

            Section {
                Picker("周期", selection: $周期.animation(.snappy)) {
                    ForEach(游玩路径周期.allCases) { item in
                        Text(item.标题).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowSeparator(.hidden)

                周期标题
                    .listRowSeparator(.hidden)
                时长图表
            }

            if 周期 != .年, !范围内时间段.isEmpty {
                Section("游玩时段") {
                    时段图表
                }
            }

            if vnID == nil {
                作品排行区域
            }

            if !范围内时间段.isEmpty {
                Section("记录") {
                    ForEach(范围内时间段.prefix(100)) { session in
                        记录行(session)
                    }
                }
            }
        }
        .平台分组列表样式()
        .refreshable { await 中心.刷新(强制: true) }
        .onAppear {
            // 单部作品可能很久没玩了，打开时直接显示最后玩的那个周期
            if vnID != nil, !已定位最近, let last = 所有时间段.map(\.startedAt).max() {
                基准日期 = last
                已定位最近 = true
            }
        }
        .task(id: 中心.时间段.count) { await 加载作品标题() }
    }

    private var 周期标题: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: 游玩路径统计.时长文本(游玩路径统计.总秒数(范围内时间段, 范围: 当前范围)))
                    .font(.title2.weight(.bold))
                    .contentTransition(.numericText())
                Text(verbatim: 周期文本)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                移动周期(-1)
            } label: {
                Label("上一个", systemImage: "chevron.left")
                    .labelStyle(.iconOnly)
            }
            .disabled(!可前往上一周期)
            Button {
                移动周期(1)
            } label: {
                Label("下一个", systemImage: "chevron.right")
                    .labelStyle(.iconOnly)
            }
            .disabled(!可前往下一周期)
        }
        .buttonStyle(.borderless)
    }

    private var 周期文本: String {
        let range = 当前范围
        switch 周期 {
        case .日:
            return range.start.formatted(date: .long, time: .omitted)
        case .周:
            let last = range.end.addingTimeInterval(-1)
            return "\(range.start.formatted(.dateTime.month().day()))–\(last.formatted(.dateTime.month().day()))"
        case .月:
            return range.start.formatted(.dateTime.year().month(.wide))
        case .年:
            return range.start.formatted(.dateTime.year())
        }
    }

    private func 移动周期(_ value: Int) {
        guard let date = 日历.date(byAdding: 周期.日历单位, value: value, to: 基准日期) else { return }
        withAnimation(.snappy) { 基准日期 = date }
    }

    // MARK: 图表

    private var 时长图表: some View {
        let buckets = 游玩路径统计.分桶(所有时间段, 范围: 当前范围, 单位: 周期.分桶单位, 日历: 日历)
        // 少于两小时的周期用分钟作单位，纵轴的数字才不会全是小数
        let usesMinutes = (buckets.map(\.秒数).max() ?? 0) < 7200
        return Chart(buckets) { bucket in
            BarMark(
                x: .value("时间", bucket.开始, unit: 周期.分桶单位),
                y: .value("时长", usesMinutes ? bucket.秒数 / 60 : bucket.秒数 / 3600)
            )
            .foregroundStyle(Color.accentColor)
            .cornerRadius(3)
        }
        .chartXScale(domain: 当前范围.start...当前范围.end)
        .chartXAxis { 横轴 }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(verbatim: 游玩路径统计.刻度文本(usesMinutes ? number * 60 : number * 3600, 单位: usesMinutes ? .minute : .hour))
                    }
                }
            }
        }
        .frame(height: 180)
        .accessibilityLabel("游玩时长")
    }

    @AxisContentBuilder
    private var 横轴: some AxisContent {
        switch 周期 {
        case .日:
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        case .周:
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        case .月:
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine()
                // 只写数字：月底的“29日”放不下会变成省略号
                AxisValueLabel { Text(verbatim: 日期数字(value)) }
            }
        case .年:
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.narrow), centered: true)
            }
        }
    }

    private func 日期数字(_ value: AxisValue) -> String {
        value.as(Date.self).map { String(日历.component(.day, from: $0)) } ?? ""
    }

    /// 横轴是日期，纵轴是一天中的时刻，色块就是玩的那一段。一眼看出什么时候在玩、玩了多久。
    private var 时段图表: some View {
        let segments = 游玩路径统计.时段(所有时间段, 范围: 当前范围, 日历: 日历)
        return Chart(segments) { segment in
            RectangleMark(
                xStart: .value("开始", segment.日期),
                xEnd: .value("结束", 日历.date(byAdding: .day, value: 1, to: segment.日期) ?? segment.日期),
                yStart: .value("开始时刻", segment.开始小时),
                yEnd: .value("结束时刻", segment.结束小时)
            )
            .foregroundStyle(Color.accentColor)
            .cornerRadius(2)
        }
        .chartXScale(domain: 当前范围.start...当前范围.end)
        .chartXAxis {
            // 只看一天时只有一列，横轴上不需要刻度
            if 周期 != .日 { 横轴 }
        }
        .chartYScale(domain: [24, 0])
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 6, 12, 18, 24]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text(verbatim: String(format: "%02d:00", hour))
                    }
                }
            }
        }
        .frame(height: 240)
        .accessibilityLabel("游玩时段")
    }

    // MARK: 列表

    @ViewBuilder
    private var 作品排行区域: some View {
        let ranking = 游玩路径统计.作品排行(范围内时间段, 范围: 当前范围)
        if !ranking.isEmpty {
            Section("作品") {
                ForEach(ranking, id: \.vn) { item in
                    NavigationLink {
                        游玩路径页面(vnID: item.vn)
                    } label: {
                        HStack {
                            作品标题(item.vn)
                                .lineLimit(2)
                            Spacer(minLength: 12)
                            Text(verbatim: 游玩路径统计.时长文本(item.秒数))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private func 记录行(_ session: 游玩时间段) -> some View {
        VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
            if vnID == nil {
                作品标题(session.vn)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: 记录时间文本(session))
                    .font(.subheadline)
                    .monospacedDigit()
                Spacer(minLength: 12)
                Text(verbatim: 游玩路径统计.时长文本(session.endedAt.timeIntervalSince(session.startedAt)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Text(verbatim: session.client.name)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func 记录时间文本(_ session: 游玩时间段) -> String {
        let start = session.startedAt.formatted(.dateTime.month().day().hour().minute())
        let end = 日历.isDate(session.startedAt, inSameDayAs: session.endedAt)
            ? session.endedAt.formatted(.dateTime.hour().minute())
            : session.endedAt.formatted(.dateTime.month().day().hour().minute())
        return 中西文间距.去除空格("\(start)–\(end)")
    }

    @ViewBuilder
    private func 作品标题(_ id: String) -> some View {
        if let title = 作品内容[id]?.主标题 {
            多语言列表文本(title, 层级: .主标题)
        } else {
            Text(verbatim: id)
        }
    }

    private func 加载作品标题() async {
        guard vnID == nil else { return }
        let ids = Array(Set(中心.时间段.map(\.vn))).filter { 作品内容[$0] == nil }.sorted()
        guard !ids.isEmpty, let items = try? await VNDB探索服务.shared.视觉小说(编号: ids) else { return }
        for item in items { 作品内容[item.id] = 作品列表行内容(item, 标题: 标题偏好) }
    }
}

/// 还没有 App 传入游玩路径时显示。
struct 游玩路径占位页面: View {
    @ObservedObject private var account = PaperAccount账户.shared

    var body: some View {
        ContentUnavailableView {
            Label("游玩路径", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
        } description: {
            Text("在第三方模拟器中登录Paper账户以查看此数据。")
        } actions: {
            if !account.isLoggedIn {
                NavigationLink("Paper账户") {
                    PaperAccount页面()
                }
            }
        }
    }
}

/// 资料库编辑页面中的游玩路径：这部作品的游玩时长，轻点后查看完整数据。
/// 已有 App 传入数据、但这部作品还没有玩过时不显示。
struct 编辑页面游玩路径区域: View {
    let vnID: String

    @ObservedObject private var 中心 = 游玩路径中心.shared
    @ObservedObject private var account = PaperAccount账户.shared

    private var 时间段: [游玩时间段] { 中心.时间段(作品: vnID) }

    var body: some View {
        if !时间段.isEmpty {
            Section("游玩路径") {
                NavigationLink {
                    游玩路径页面(vnID: vnID)
                } label: {
                    LabeledContent("游玩时长") {
                        Text(verbatim: 游玩路径统计.时长文本(游玩路径统计.总秒数(时间段)))
                    }
                }
            }
        } else if !中心.有数据来源, !account.isLoggedIn || 中心.已加载 {
            Section("游玩路径") {
                if account.isLoggedIn {
                    Text("在第三方模拟器中登录Paper账户以查看此数据。")
                        .foregroundStyle(.secondary)
                } else {
                    NavigationLink {
                        游玩路径页面(vnID: vnID)
                    } label: {
                        Text("在第三方模拟器中登录Paper账户以查看此数据。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// 使用 Paper账户登录过的第三方 App。移除后它就无法再读取和传入游玩路径，已传入的数据保留。
struct 已授权App页面: View {
    @ObservedObject private var 中心 = 游玩路径中心.shared
    @State private var 待移除: 已授权App?
    @State private var errorMessage: String?

    var body: some View {
        平台滚动页面 {
            if 中心.已授权.isEmpty {
                Section {
                    Text("没有App")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("在第三方模拟器中登录Paper账户以查看此数据。")
                }
            } else {
                Section {
                    ForEach(中心.已授权) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                                Text(verbatim: app.name)
                                Text(verbatim: app.id)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Button("移除", role: .destructive) { 待移除 = app }
                                .buttonStyle(.borderless)
                        }
                    }
                } footer: {
                    Text("这些App可以查看、添加、更改和删除你的游玩路径，无法访问资料库和其他数据。")
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("使用Paper账户的App")
        .平台内联导航标题()
        .task { await 中心.刷新(强制: true) }
        .alert(
            Text("要移除“\(待移除?.name ?? "")”吗？"),
            isPresented: Binding(get: { 待移除 != nil }, set: { if !$0 { 待移除 = nil } }),
            presenting: 待移除
        ) { app in
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                Task {
                    do {
                        try await 中心.移除App(app)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        } message: { _ in
            Text("此App将无法再传入游玩路径。已传入的游玩路径会保留。")
        }
        .alert("Paper账户", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }
}

extension 游玩路径周期 {
    var 标题: LocalizedStringKey {
        switch self {
        case .日: "日"
        case .周: "周"
        case .月: "月"
        case .年: "年"
        }
    }
}
