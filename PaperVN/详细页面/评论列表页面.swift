import SwiftUI

private extension View {
    @ViewBuilder
    func 评论容器背景(使用背景模糊: Bool) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: 评论卡片布局.圆角,
            style: .continuous
        )
        if 使用背景模糊 {
            background(.regularMaterial, in: shape)
        } else {
            background(Color.平台次级分组背景, in: shape)
        }
    }
}

enum 评论排序字段: String, CaseIterable, Identifiable {
    case 发布日期
    case 评分

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .发布日期: "按发布日期"
        case .评分: "按评分"
        }
    }
}

enum 评论排序方向: String, CaseIterable, Identifiable {
    case 降序
    case 升序

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .降序: "降序"
        case .升序: "升序"
        }
    }
}

struct 评论卡片: View {
    let 评论: 视觉小说评论
    var 使用背景模糊 = true
    var 预先布局完整正文 = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            头部
            评论正文(
                原文: 评论.text,
                语言代码: 评论.commentLanguageCode,
                预先布局完整正文: 预先布局完整正文
            )
            评价标签
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 评论卡片布局.内边距)
        .padding(.top, 评论卡片布局.顶部内边距)
        .padding(.bottom, 评论卡片布局.内边距)
        .评论容器背景(使用背景模糊: 使用背景模糊)
    }

    private var 头部: some View {
        HStack(spacing: 10) {
            if let avatarURL = 评论.avatarURL {
                CachedAsyncImage(
                    url: URL(string: avatarURL),
                    contentMode: .fill
                )
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: 评论.username)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(verbatim: 评论.source.title)
                    if let 时间 = 评论.timestamp {
                        Text(
                            Date(timeIntervalSince1970: TimeInterval(时间)),
                            format: .relative(
                                presentation: .numeric,
                                unitsStyle: .wide
                            )
                        )
                    } else if let dateText = 评论.dateText {
                        Text(verbatim: dateText)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var 评价标签: some View {
        if let 评分 = 评论.rating {
            HStack(spacing: 列表行布局.图标文字间距) {
                Image(systemName: "star.fill")
                Text(verbatim: "\(评分)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("评分\(评分)")
        } else if let 推荐 = 评论.isRecommended {
            Label(
                推荐 ? "推荐" : "不推荐",
                systemImage: 推荐 ? "hand.thumbsup" : "hand.thumbsdown"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct 评论列表页面: View {
    let vndbID: String
    private let 初始评论: [视觉小说评论]

    @AppStorage(评论数据来源.设置键)
    private var 评论来源设置 = 评论数据来源.combined.rawValue

    @State private var 评论列表: [视觉小说评论]
    @State private var 来源筛选: 评论数据来源 = .combined
    @State private var 排序字段: 评论排序字段 = .发布日期
    @State private var 排序方向: 评论排序方向 = .降序
    @State private var 正在加载 = true
    @State private var 错误信息: String?
    @State private var 已使用初始评论 = false

    init(vndbID: String, 初始评论: [视觉小说评论] = []) {
        self.vndbID = vndbID
        self.初始评论 = 初始评论
        _评论列表 = State(initialValue: [])
    }

    var body: some View {
        let 可见评论 = 计算可见评论()

        Group {
            if 可见评论.isEmpty, !正在加载 {
                无评论内容
            } else {
                评论滚动内容(可见评论)
                    .refreshable {
                        await 加载(forceRefresh: true)
                    }
            }
        }
        .平台安全区域栏(edge: .top, spacing: 0) {
            if 显示来源选择 {
                Picker("评论来源", selection: $来源筛选) {
                    ForEach(可选评论来源) { 来源 in
                        Text(verbatim: 来源.title).tag(来源)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(Color.平台分组背景.ignoresSafeArea())
        .navigationTitle("评论（\(可见评论.count)条）")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .平台主操作) {
                排序菜单
            }
        }
        .task(id: 加载标识) {
            await 加载()
        }
        .onChange(of: 评论来源设置) { _, _ in
            来源筛选 = .combined
        }
        .onChange(of: 可选评论来源) { _, 新来源 in
            if 新来源.count < 评论数据来源.allCases.count
                || !新来源.contains(来源筛选) {
                来源筛选 = .combined
            }
        }
    }

    private func 评论滚动内容(_ 可见评论: [视觉小说评论]) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                错误提示

                if 可见评论.isEmpty {
                    加载中提示
                    ForEach(0..<3, id: \.self) { 序号 in
                        评论加载占位卡片(
                            序号: 序号,
                            使用背景模糊: false
                        )
                    }
                } else {
                    ForEach(可见评论) { 评论 in
                        评论卡片(
                            评论: 评论,
                            使用背景模糊: false
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.24), value: 正在加载)
        }
        .平台柔和滚动边缘(for: .top)
    }

    private var 无评论内容: some View {
        VStack(spacing: 14) {
            错误提示
            平台内容不可用视图("无评论", systemImage: "text.bubble")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var 错误提示: some View {
        if let 错误信息 {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label {
                    Text(verbatim: 错误信息)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                Spacer(minLength: 8)
                Button {
                    Task {
                        await 加载(forceRefresh: true)
                    }
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(正在加载)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var 排序菜单: some View {
        Menu {
            Picker("排序方式", selection: $排序字段) {
                ForEach(评论排序字段.allCases) { 字段 in
                    Text(字段.title).tag(字段)
                }
            }
            .pickerStyle(.inline)

            Picker("排序顺序", selection: $排序方向) {
                ForEach(评论排序方向.allCases) { 方向 in
                    Text(方向.title).tag(方向)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("排序")
    }

    private var 加载中提示: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在载入…")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var 显示来源选择: Bool {
        (评论数据来源(rawValue: 评论来源设置) ?? .combined) == .combined
            && 可选评论来源.count == 评论数据来源.allCases.count
    }

    private var 可选评论来源: [评论数据来源] {
        var 来源: [评论数据来源] = [.combined]
        if 评论列表.contains(where: { $0.source == .bangumi }) {
            来源.append(.bangumi)
        }
        if 评论列表.contains(where: { $0.source == .steam }) {
            来源.append(.steam)
        }
        return 来源
    }

    private var 加载标识: String {
        let 语言 = Steam评论语言.selected
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        return "comments|\(vndbID)|\(评论来源设置)|\(语言)"
    }

    private func 计算可见评论() -> [视觉小说评论] {
        评论列表
            .filter { 评论 in
                switch 来源筛选 {
                case .combined: true
                case .bangumi: 评论.source == .bangumi
                case .steam: 评论.source == .steam
                }
            }
            .sorted(by: 排在前面)
    }

    private func 排在前面(
        _ 左: 视觉小说评论,
        _ 右: 视觉小说评论
    ) -> Bool {
        switch 排序字段 {
        case .发布日期:
            let 左值 = 左.timestamp ?? 0
            let 右值 = 右.timestamp ?? 0
            guard 左值 != 右值 else { return 左.id < 右.id }
            return 排序方向 == .升序 ? 左值 < 右值 : 左值 > 右值
        case .评分:
            switch (左.rating, 右.rating) {
            case let (左分?, 右分?):
                guard 左分 != 右分 else {
                    return (左.timestamp ?? 0) > (右.timestamp ?? 0)
                }
                return 排序方向 == .升序 ? 左分 < 右分 : 左分 > 右分
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return (左.timestamp ?? 0) > (右.timestamp ?? 0)
            }
        }
    }

    private func 加载(forceRefresh: Bool = false) async {
        正在加载 = true
        错误信息 = nil
        defer { 正在加载 = false }

        await Task.yield()
        guard !Task.isCancelled else { return }

        if !forceRefresh, !初始评论.isEmpty, !已使用初始评论 {
            已使用初始评论 = true
            withAnimation(.easeInOut(duration: 0.24)) {
                评论列表 = 初始评论
            }
            return
        }

        do {
            let 评论 = try await 视觉小说外部数据服务.shared.comments(
                vndbID: vndbID,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                评论列表 = 评论
            }
        } catch is CancellationError {
            return
        } catch {
            错误信息 = error.localizedDescription
        }
    }
}

struct 评论加载占位卡片: View {
    let 序号: Int
    var 使用背景模糊 = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "正在载入的用户名")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(verbatim: "Bangumi番组计划 0000-00-00")
                        .font(.caption2)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Text(verbatim: 占位正文)
                .font(.callout)

            HStack(spacing: 列表行布局.图标文字间距) {
                Image(systemName: "star.fill")
                Text(verbatim: "0")
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 评论卡片布局.内边距)
        .padding(.top, 评论卡片布局.顶部内边距)
        .padding(.bottom, 评论卡片布局.内边距)
        .评论容器背景(使用背景模糊: 使用背景模糊)
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var 占位正文: String {
        序号.isMultiple(of: 2)
            ? "正在载入的评论正文占位内容，长度用来撑开骨架的行数与宽度，遮蔽之后并不会显示出来。"
            : "正在载入的评论正文占位内容，稍短一些。"
    }
}
