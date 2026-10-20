import SwiftUI

/// 同步任务里的“缺失的作品”：在某个平台上找不到、没有同步过去的作品，可以逐部手动匹配。
struct 未匹配作品页面: View {
    let 平台: 资料库平台
    @ObservedObject private var sync = PaperVNSync中心.shared
    @ObservedObject private var library = 本地资料库.shared

    var body: some View {
        let works = sync.未匹配作品[平台] ?? []
        let entries = library.动画漫画条目
        List {
            if !works.isEmpty {
                Section {
                    ForEach(works) { work in
                        NavigationLink {
                            作品手动匹配页面(作品: work, 平台: 平台)
                        } label: {
                            未匹配作品行(作品: work, 条目: entries[work.键])
                        }
                    }
                } footer: {
                    Text("这些作品在\(平台.localizedTitle)上找不到，已匿名发送给PaperVN以改进作品匹配。")
                }
            }
        }
        .平台分组列表样式()
        .overlay {
            if works.isEmpty {
                ContentUnavailableView("没有缺失的作品", systemImage: "checkmark.circle")
            }
        }
        .navigationTitle(平台.localizedTitle)
        .平台内联导航标题()
    }
}

/// 资料库里有这部作品时和资料库列表的行一样显示，否则只显示标题。
private struct 未匹配作品行: View {
    let 作品: 未匹配作品
    let 条目: 本地资料库条目?

    var body: some View {
        if let 条目 {
            资料库作品行(entry: 条目)
        } else {
            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                // 不知道标题的语言：用系统字体的中等字重，和资料库列表里的中文标题一致
                多语言列表文本(文本: 作品.标题, isJapanese: false, 层级: .主标题, 系统字体粗细: .medium)
                    .lineLimit(2)
                Text(作品.类型.localizedTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 在平台上搜索并选出对应的作品。选好后记下对应关系、匿名发送给 PaperVN 审核，然后重新同步。
struct 作品手动匹配页面: View {
    let 作品: 未匹配作品
    let 平台: 资料库平台
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = 本地资料库.shared
    @State private var query: String
    @State private var results: [匹配候选] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selection: 匹配候选?
    @State private var searchTask: Task<Void, Never>?

    init(作品: 未匹配作品, 平台: 资料库平台) {
        self.作品 = 作品
        self.平台 = 平台
        _query = State(initialValue: 作品.标题)
    }

    var body: some View {
        List {
            Section {
                未匹配作品行(作品: 作品, 条目: library.动画漫画条目[作品.键])
            } header: {
                Text("资料库中的作品")
            }

            Section {
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if let errorMessage {
                    Text(verbatim: errorMessage)
                        .foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("无结果")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { candidate in
                        Button {
                            selection = candidate
                        } label: {
                            匹配候选行(候选: candidate, 平台: 平台)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("\(平台.localizedTitle)上的作品")
            } footer: {
                Text("也可以输入作品编号或粘贴作品页面的链接。")
            }
        }
        .平台分组列表样式()
        .searchable(text: $query, prompt: "标题、编号或链接")
        .onSubmit(of: .search) { search() }
        .task { if results.isEmpty && errorMessage == nil { search() } }
        .onDisappear { searchTask?.cancel() }
        .confirmationDialog(
            "匹配作品",
            isPresented: Binding(get: { selection != nil }, set: { if !$0 { selection = nil } }),
            titleVisibility: .visible,
            presenting: selection
        ) { candidate in
            Button("是同一部作品") {
                PaperVNSync中心.shared.手动匹配(作品, 平台: 平台, 作品: candidate)
                dismiss()
            }
            Button("是此作品的特别篇或其他版本") {
                PaperVNSync中心.shared.手动匹配(作品, 平台: 平台, 作品: candidate, 附属: true)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: { candidate in
            Text("“\(作品.标题)”与\(平台.localizedTitle)上的“\(candidate.标题)”是什么关系？特别篇、单行本或其他版本会并入“\(candidate.标题)”，不单独同步。此匹配会匿名发送给PaperVN，审核后用于所有用户的同步。")
        }
        .navigationTitle("手动匹配")
        .平台内联导航标题()
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        isSearching = true
        errorMessage = nil
        searchTask = Task {
            do {
                let found = try await PaperVNSync中心.shared.搜索候选(平台, 类型: 作品.类型, 关键词: text)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                errorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "请求失败。")
            }
            isSearching = false
        }
    }
}

private struct 匹配候选行: View {
    let 候选: 匹配候选
    let 平台: 资料库平台
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: 候选.封面, contentMode: .fill)
                .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
                .clipped()
                .background(Color.secondary.opacity(0.1))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass),
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                // 与资料库列表相同：中文标题用中等字重，系统粗体的中文太重
                多语言列表文本(
                    文本: 候选.标题,
                    isJapanese: 候选.标题语言 == "ja",
                    语言代码: 候选.标题语言,
                    层级: .主标题,
                    系统字体粗细: 候选.标题语言?.hasPrefix("zh") == true ? .medium : nil
                )
                .foregroundStyle(.primary)
                .lineLimit(2)

                if let other = 候选.其他标题, 候选.其他标题为官方 || allowUnofficialTitles {
                    多语言列表文本(
                        文本: other,
                        isJapanese: 候选.其他标题语言 == "ja",
                        语言代码: 候选.其他标题语言,
                        层级: .副标题
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                let details = [候选.年份.map(String.init), 候选.种类, 平台 == .annict ? nil : "ID \(候选.id)"].compactMap { $0 }
                if !details.isEmpty {
                    Text(verbatim: details.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
