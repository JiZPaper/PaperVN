import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// 导出的资料库：带格式版本的 JSON，扩展名 .papervnlibrary（在 Info.plist 中声明）。
    nonisolated static let PaperVN资料库 = UTType(exportedAs: "com.jizpaper.papervn.library", conformingTo: .json)
}

/// 资料库设置中的“最近更改”：最近10次更改，每条可以回退；右上角导出、导入整个资料库。
/// 开启 Paper Cloud 时与其他设备同步，各设备显示同一份。
struct 资料库更改记录页面: View {
    @ObservedObject private var records = 资料库更改记录.shared
    @ObservedObject private var library = 本地资料库.shared
    @EnvironmentObject private var auth: 用户登录
    @State private var exportDocument: 资料库导出文件?
    @State private var isImporting = false
    @State private var importedSnapshot: 资料库快照?
    @State private var importError: String?
    @State private var undoing: 资料库更改?
    @State private var reverting: 资料库更改?
    @State private var result: 资料库更改记录.回退结果?

    var body: some View {
        平台滚动页面 {
            Section {
                if records.更改.isEmpty {
                    Text("还没有更改。")
                        .foregroundStyle(.secondary)
                }
                ForEach(records.更改) { change in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: change.标题)
                            Text(verbatim: "\(change.时间.相对时间文本()) · \(change.摘要)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button {
                            if change.id == records.更改.first?.id { undoing = change } else { reverting = change }
                        } label: {
                            Label(change.id == records.更改.first?.id ? "撤销" : "回退", systemImage: "arrow.uturn.backward")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .disabled(records.正在回退 || !library.可写入)
                    }
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("最近更改")
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("导入资料库", systemImage: "square.and.arrow.down") {
                    isImporting = true
                }
                .disabled(!library.可写入)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("导出资料库", systemImage: "square.and.arrow.up") {
                    guard let owner = library.所有者 else { return }
                    exportDocument = 资料库导出文件(snapshot: 资料库快照(
                        owner: owner, createdAt: .now, reason: nil,
                        appVersion: 资料库快照.当前App版本, entries: library.条目
                    ))
                }
                .disabled(!library.可写入)
            }
        }
        .alert(
            "要撤销此更改吗？",
            isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } }),
            presenting: undoing
        ) { change in
            Button("取消", role: .cancel) {}
            Button("撤销", role: .destructive) { revert(change, to: .之前) }
        } message: { _ in
            Text("此操作无法撤销。")
        }
        .alert(
            "要回退此更改吗？",
            isPresented: Binding(get: { reverting != nil }, set: { if !$0 { reverting = nil } }),
            presenting: reverting
        ) { change in
            Button("取消", role: .cancel) {}
            Button("回退到此更改之后") { revert(change, to: .之后) }
            Button("回退到此更改之前") { revert(change, to: .之前) }
        } message: { _ in
            Text("此操作无法撤销。")
        }
        .alert(
            "部分作品未能回退",
            isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: (result?.失败 ?? []).prefix(5).map { "\($0.标题)：\($0.原因)" }.joined(separator: "\n"))
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: .PaperVN资料库,
            defaultFilename: String(localized: "PaperVN资料库\(Date.now.formatted(.iso8601.year().month().day()))")
        ) { _ in
            exportDocument = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.PaperVN资料库, .json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let snapshot = try 资料库快照.解码器().decode(资料库快照.self, from: Data(contentsOf: url))
                guard snapshot.formatVersion == 1 else { throw CocoaError(.fileReadCorruptFile) }
                importedSnapshot = snapshot
            } catch {
                importError = String(localized: "无法读取此文件。请选择从PaperVN导出的资料库。")
            }
        }
        .navigationDestination(item: $importedSnapshot) { snapshot in
            资料库恢复确认页面(目标: snapshot, 原因: .导入文件)
        }
        .alert("无法导入", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: importError ?? "")
        }
    }

    private func revert(_ change: 资料库更改, to position: 资料库更改记录.回退位置) {
        Task {
            let value = await records.回退(change, 到: position, vndbToken: auth.token)
            if !value.失败.isEmpty { result = value }
        }
    }
}

extension 资料库快照: Identifiable, Hashable {
    var id: String { "\(owner)|\(createdAt.timeIntervalSince1970)|\(entries.count)" }
    static func == (lhs: 资料库快照, rhs: 资料库快照) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct 资料库导出文件: FileDocument {
    static var readableContentTypes: [UTType] { [.PaperVN资料库, .json] }
    let snapshot: 资料库快照

    init(snapshot: 资料库快照) { self.snapshot = snapshot }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        snapshot = try 资料库快照.解码器().decode(资料库快照.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try 资料库快照.编码器().encode(snapshot))
    }
}

/// 导入文件：显示与当前资料库的差异，确认后把资料库改成目标的样子。
struct 资料库恢复确认页面: View {
    let 目标: 资料库快照
    let 原因: 资料库更改原因
    @ObservedObject private var records = 资料库更改记录.shared
    @ObservedObject private var library = 本地资料库.shared
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.dismiss) private var dismiss
    @State private var differences: [资料库差异项] = []
    @State private var selection: Set<String> = []
    @State private var isSelecting = false
    @State private var pendingRevert: [资料库差异项]?
    @State private var result: 资料库更改记录.回退结果?

    var body: some View {
        资料库差异列表(differences: differences, selection: $selection, isSelecting: isSelecting, 当前在前: true)
            .navigationTitle(原因 == .导入文件 ? "导入资料库" : "恢复资料库")
            .平台内联导航标题()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(isSelecting ? "完成" : "选择") {
                        isSelecting.toggle()
                        if !isSelecting { selection = [] }
                    }
                    .disabled(differences.isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(isSelecting ? "恢复所选作品" : "恢复") {
                        pendingRevert = isSelecting ? differences.filter { selection.contains($0.id) } : differences
                    }
                    .disabled(records.正在回退 || differences.isEmpty || (isSelecting && selection.isEmpty))
                }
            }
            .回退确认(items: $pendingRevert) { items in
                // 差异的“之后”就是目标中的样子
                let targets = Dictionary(items.map { ($0.id, $0.之后) }, uniquingKeysWith: { first, _ in first })
                result = await records.应用(targets, 原因: 原因, vndbToken: auth.token, 同步状态: 目标.sync)
            }
            .回退结果提示($result) { dismiss() }
            .task(id: library.修订号) {
                differences = 资料库差异项.比较(之前: library.条目, 之后: 目标.entries)
            }
    }
}

/// 差异列表：按“更改、添加、删除”分组，每部作品下列出改动的字段。
private struct 资料库差异列表: View {
    let differences: [资料库差异项]
    @Binding var selection: Set<String>
    let isSelecting: Bool
    /// 恢复页面里“之前”是此iPhone上现在的资料库。
    var 当前在前 = false

    var body: some View {
        平台滚动页面 {
            if differences.isEmpty {
                Section {
                    Text("与当前资料库相同。")
                        .foregroundStyle(.secondary)
                }
            }
            分组(.修改, 标题: "更改")
            分组(.新增, 标题: 当前在前 ? "将添加" : "添加")
            分组(.删除, 标题: 当前在前 ? "将删除" : "删除")
        }
        .平台分组列表样式()
    }

    @ViewBuilder
    private func 分组(_ kind: 资料库差异项.种类, 标题: LocalizedStringKey) -> some View {
        let items = differences.filter { $0.种类 == kind }
        if !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Button {
                        guard isSelecting else { return }
                        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            if isSelecting {
                                Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.contains(item.id) ? Color.accentColor : .secondary)
                                    .imageScale(.large)
                            }
                            差异行(item: item)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(标题)
            }
        }
    }
}

private struct 差异行: View {
    let item: 资料库差异项

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(verbatim: item.标题)
            } icon: {
                Image(systemName: item.类型.symbolName)
                    .foregroundStyle(.secondary)
            }
            ForEach(item.字段变化, id: \.名称) { change in
                Text(verbatim: "\(change.名称)：\(change.之前) → \(change.之后)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if item.种类 != .修改, let status = item.条目.状态 {
                Text(verbatim: status.localizedTitle(for: item.类型))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// 回退前确认：说明视觉小说会直接写入VNDB，其他作品会同步到已登录的平台。
    func 回退确认(items: Binding<[资料库差异项]?>, perform: @escaping ([资料库差异项]) async -> Void) -> some View {
        let value = items.wrappedValue ?? []
        let visualNovels = value.filter { $0.类型 == .visualNovel }.count
        return confirmationDialog(
            String(localized: "要更改\(value.count)部作品吗？"),
            isPresented: Binding(get: { items.wrappedValue != nil }, set: { if !$0 { items.wrappedValue = nil } }),
            titleVisibility: .visible
        ) {
            Button("更改\(value.count)部作品") {
                Task { await perform(value) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if visualNovels > 0 {
                Text("其中\(visualNovels)部视觉小说会立即写入VNDB；其他作品会通过PaperVN Sync写入已登录的平台。之后仍可以在“最近更改”中回退。")
            } else {
                Text("作品会通过PaperVN Sync写入已登录的平台。之后仍可以在“最近更改”中回退。")
            }
        }
    }

    func 回退结果提示(_ result: Binding<资料库更改记录.回退结果?>, onDone: @escaping () -> Void = {}) -> some View {
        let value = result.wrappedValue
        return alert(
            value?.失败.isEmpty == false ? String(localized: "部分作品未能更改") : String(localized: "已更改\(value?.已回退 ?? 0)部作品"),
            isPresented: Binding(get: { result.wrappedValue != nil }, set: { if !$0 { result.wrappedValue = nil } })
        ) {
            Button("好", role: .cancel) {
                if value?.失败.isEmpty != false { onDone() }
            }
        } message: {
            if let failures = value?.失败, !failures.isEmpty {
                Text(verbatim: failures.prefix(5).map { "\($0.标题)：\($0.原因)" }.joined(separator: "\n"))
            }
        }
    }
}
