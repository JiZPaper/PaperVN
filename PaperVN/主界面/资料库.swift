import Combine
import Foundation
import SwiftUI

import UIKit

private typealias PaperVNCachedImage = UIImage

private enum 资料库删除来源: Equatable {
    case swipe
    case contextMenu
}

private struct 资料库删除请求: Identifiable {
    let item: 用户列表项目
    let source: 资料库删除来源

    var id: String { item.id }
}

private enum 图片加载错误: Error {
    case invalidResponse
    case httpStatus(Int)
    case invalidImageData

    var shouldRetry: Bool {
        switch self {
        case .invalidResponse, .invalidImageData:
            return true
        case .httpStatus(let statusCode):
            return statusCode == 408 || statusCode == 429
                || (500...599).contains(statusCode)
        }
    }
}

private actor 图片数据请求协调器 {
    static let shared = 图片数据请求协调器()

    private struct Key: Hashable {
        let url: URL
        let bypassingCache: Bool
    }

    private var tasks: [Key: Task<Data, Error>] = [:]

    func data(
        from url: URL,
        bypassingCache: Bool
    ) async throws -> Data {
        let key = Key(url: url, bypassingCache: bypassingCache)
        if let existing = tasks[key] {
            return try await existing.value
        }

        let task = Task {
            try await Self.fetchData(
                from: url,
                bypassingCache: bypassingCache
            )
        }
        tasks[key] = task

        do {
            let data = try await task.value
            tasks[key] = nil
            return data
        } catch {
            tasks[key] = nil
            throw error
        }
    }

    private static func fetchData(
        from url: URL,
        bypassingCache: Bool
    ) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: bypassingCache
                ? .reloadIgnoringLocalCacheData
                : .useProtocolCachePolicy,
            timeoutInterval: 30
        )
        if bypassingCache {
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        }

        let (data, httpResponse) = try await PaperVNConnect网络设置.发送图片请求(
            request,
            session: .shared
        )
        guard (200...299).contains(httpResponse.statusCode) else {
            throw 图片加载错误.httpStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else {
            throw 图片加载错误.invalidImageData
        }
        return data
    }
}

private struct 已加载图片资源 {
    let image: PaperVNCachedImage
    let data: Data
}

private struct 资料库排序选择: Equatable {
    var sort: 用户列表排序
    var isDescending: Bool

    init(
        sort: 用户列表排序 = .lastModified,
        isDescending: Bool? = nil
    ) {
        self.sort = sort
        self.isDescending = isDescending ?? sort.defaultIsDescending
    }
}

private struct 资料库自动加载标识: Equatable {
    let isSyncEnabled: Bool
    let token: String
    let userID: String
    let isLoggedIn: Bool
    let isRestoringSession: Bool
    /// 资料库所有者变化（登录或退出 Paper Account 等）时重新载入。
    let owner: String?
}

#if canImport(SwiftUI, _version: 8.0.85) // iOS 27.1 SDK（iPhone Duo API）
private extension View {
    @ViewBuilder
    func 读取纵向工具栏状态(isVertical: Binding<Bool>) -> some View {
        if #available(iOS 27.1, *) {
            modifier(纵向工具栏状态读取器(isVertical: isVertical))
        } else {
            self
        }
    }
}

@available(iOS 27.1, *)
private struct 纵向工具栏状态读取器: ViewModifier {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    @Binding var isVertical: Bool

    func body(content: Content) -> some View {
        content.onChange(of: toolbarVerticalEdge, initial: true) { _, edge in
            isVertical = edge != nil
        }
    }
}
#else
private extension View {
    @ViewBuilder
    func 读取纵向工具栏状态(isVertical: Binding<Bool>) -> some View {
        self
    }
}
#endif

/// 列表在顶部时隐藏顶部滚动边缘。是否在顶部只存在这个修饰器里：
/// 放在资料库的 @State 上的话，每次离开或回到顶部都会让整个资料库连同所有可见行重绘，开始滚动时会卡一下。
private struct 资料库顶部边缘隐藏: ViewModifier {
    let enabled: Bool
    @State private var isAtTop = true

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top <= 0.5
            } action: { _, newValue in
                isAtTop = newValue
            }
            .平台隐藏滚动边缘(enabled && isAtTop, for: .top)
    }
}

struct 资料库: View {
    @Namespace private var namespace
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var kunAccount: 鲲Galgame账户
    @EnvironmentObject private var parentalControls: 家长控制中心
    @EnvironmentObject private var myAnimeListAccount: MyAnimeList账户
    @StateObject private var apiService = VNDB服务.shared
    @ObservedObject private var library = 本地资料库.shared
    /// 不直接观察 PaperVN Sync：同步进度变化很频繁，资料库只需要知道 VNDB 是否正在导入（见 `vndb导入中`）。
    private let sync = PaperVNSync中心.shared
    @State private var vndb导入中 = false
    /// 右上角同步任务按钮显示的同步状态：需要确认、正在同步、失败或有缺失的作品。
    @State private var 同步提示: 同步状态提示?
    @State private var 显示同步任务 = false
    /// 已经自动载入过的账户与设置。从详情页等推入的页面返回时 `.task` 会重新执行，同一账户不再重复载入与同步。
    @State private var 已自动载入: 资料库自动加载标识?
    @AppStorage(PaperVNSync中心.启用设置键)
    private var paperVNSyncEnabled = PaperVNSync中心.默认启用
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()

    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false

    @State private var selectedStatus: 资料库状态?
    /// 选中的VNDB标签：作品带有任一选中的标签就显示。只用于视觉小说。
    @State private var selectedTagIDs: Set<Int> = []
    /// VNDB账户里的标签（来自 PaperVN Sync），以及当前类型、状态下带有各个标签的作品数。
    @State private var vndb标签: [用户列表标签信息] = []
    @State private var 标签作品数: [Int: Int] = [:]
    /// 资料库一次只显示一种作品类型。
    @AppStorage("libraryWorkType") private var selectedType: 作品类型 = .visualNovel
    @ObservedObject private var senkou = PaperVNSenkou中心.shared
    /// 选择动画、漫画、轻小说但没有 PaperVN Senkou 时弹出订阅页面，记下想切换到的类型。
    @State private var Senkou订阅类型: 作品类型?
    /// 动画、漫画、轻小说的列表与同步需要 PaperVN Senkou。
    private var 类型选择: Binding<作品类型> {
        Binding {
            selectedType
        } set: { type in
            if type != .visualNovel, senkou.已确认, !senkou.已解锁 {
                Senkou订阅类型 = type
            } else {
                selectedType = type
            }
        }
    }
    @State private var selectedSort = 资料库排序选择()
    @State private var statusPickerHeight: CGFloat = 44
    private let sidebarFilter: 用户列表筛选?

    init(sidebarFilter: 用户列表筛选? = nil) {
        self.sidebarFilter = sidebarFilter
        if let sidebarFilter {
            _selectedStatus = State(initialValue: 资料库状态(sidebarFilter))
        } else {
            let type = UserDefaults.standard.string(forKey: "libraryWorkType")
                .flatMap(作品类型.init(rawValue:)) ?? .visualNovel
            _selectedStatus = State(initialValue: Self.已存状态(for: type))
        }
    }

    /// 每种作品类型各自记住上次选择的状态，退出App或切换类型后回来仍保持。侧边栏里固定状态的资料库不记。
    private static func 已存状态键(_ type: 作品类型) -> String {
        "libraryStatus.\(type.rawValue)"
    }

    private static func 已存状态(for type: 作品类型) -> 资料库状态? {
        UserDefaults.standard.string(forKey: 已存状态键(type))
            .flatMap(资料库状态.init(rawValue:))
    }
    /// 按类型、状态筛选并排序后的作品（从本地资料库计算）。
    @State private var listItems: [用户列表项目] = []
    /// 视觉小说以外的作品。
    @State private var otherEntries: [本地资料库条目] = []
    /// 计划分类里未发行/播出的作品，排在 `listItems`、`otherEntries` 的最后，单独放在底部的分组里。
    @State private var 未发行IDs: Set<String> = []
    @AppStorage("librarySeparatesUnreleased") private var separatesUnreleased = false
    @State private var editorTarget: 资料库编辑目标?
    @State private var deleteRequest: 资料库删除请求?
    @State private var otherDeleteRequest: 本地资料库条目?
    /// 已登录的平台都无法同步这类作品时编辑资料库，提示需要登录的平台。
    @State private var 需要登录的平台: PaperVNSync中心.资料库编辑限制?
    @State private var otherEditorTarget: 本地资料库条目?
    @State private var isDeleting = false
    @State private var revealedRatingIDs: Set<String> = []
    @State private var revealedCoverIDs: Set<String> = []
    @State private var searchText = ""
    @State private var showAccountSheet = false
    @State private var hasVerticalToolbar = false
    @State private var 滚动条状态 = 资料库滚动条状态()
    /// 索引段只在列表、搜索或排序变化时重新计算（转写标题首字母比较耗时）
    @State private var 索引段缓存: [资料库索引段] = []
    @State private var 索引作品数 = 0

    var body: some View {
        NavigationStack {
            Group {
                if !paperVNSyncEnabled {
                    平台内容不可用视图(
                        "PaperVN Sync已关闭",
                        systemImage: "arrow.triangle.2.circlepath",
                        description: Text("启用PaperVN Sync以使用资料库。")
                    )
                } else if library.所有者 == nil && !auth.isRestoringSession {
                    平台内容不可用视图(
                        "需要登录",
                        systemImage: "person.crop.circle",
                        description: Text("登录Paper账户或任意平台账户以使用资料库。")
                    )
                } else {
                    平台滚动页面 {
                        if isShowingListPlaceholders {
                            Section {
                                ForEach(0..<5, id: \.self) { index in
                                    资料库列表占位行(index: index)
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(
                                        auth.isRestoringSession
                                            ? "正在加载…"
                                            : "正在加载…"
                                    )
                                }
                                .textCase(nil)
                                .accessibilityElement(children: .combine)
                            }
                        } else {
                            Section {
                                ForEach(已发行视觉小说) { item in 视觉小说行(item) }
                            }

                            // 动画、漫画与轻小说（目前来自MyAnimeList）
                            Section {
                                ForEach(已发行其他作品) { entry in 其他作品行(entry) }
                            }

                            // 计划分类里未发行/播出的作品单独放在底部，不加标题
                            if !未发行视觉小说.isEmpty {
                                Section {
                                    ForEach(未发行视觉小说) { item in 视觉小说行(item) }
                                }
                            }
                            if !未发行其他作品.isEmpty {
                                Section {
                                    ForEach(未发行其他作品) { entry in 其他作品行(entry) }
                                }
                            }
                        }
                    }
                    .平台分组列表样式()
                    // 有同步状态提示时，它和下面列表的间距与它上方的间距（分段控件下方的留白）一致。
                    // 分组间距取相邻两个分组中较大的值，只设在提示所在的分组上不起作用，所以设在整个列表上；
                    // 视觉小说和动画等的分组同一时间只有一个有内容，不影响列表本身。
                    // 固定预留Picker的位置，不让它参与大标题的安全区计算。
                    .contentMargins(.top, sidebarFilter == nil ? statusPickerHeight : nil, for: .scrollContent)
                    // 顶部和下拉期间不绘制边缘效果；由SwiftUI决定，否则它会在更新时把UIKit里设的隐藏改回去。
                    .modifier(资料库顶部边缘隐藏(enabled: sidebarFilter == nil))
                    .记住滚动位置(key: listPositionKey)
                    .background {
                        // 按住位置只写进 滚动条状态，页面本身不读它，拖动滚动条时不会重绘整个资料库
                        资料库滚动条拖动检测 { [滚动条状态] 位置 in
                            滚动条状态.按住位置 = 位置
                        }
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                    }
                    .overlay(alignment: .trailing) {
                        if 显示索引条 {
                            资料库滚动位置气泡(
                                段: 索引段缓存,
                                作品数: 索引作品数,
                                状态: 滚动条状态
                            )
                            .padding(.vertical, 24)
                        }
                    }
                    .onChange(of: listItems, initial: true) { _, _ in 刷新索引段() }
                    .onChange(of: searchText) { _, _ in 刷新索引段() }
                    .onChange(of: selectedSort) { _, _ in 刷新索引段() }
                    .onChange(of: library.修订号) { _, _ in 刷新列表() }
                    .onChange(of: selectedStatus) { _, status in
                        if sidebarFilter == nil {
                            UserDefaults.standard.set(
                                status?.rawValue ?? "all",
                                forKey: Self.已存状态键(selectedType)
                            )
                        }
                        刷新列表()
                    }
                    .onChange(of: selectedTagIDs) { _, _ in 刷新列表() }
                    .onChange(of: separatesUnreleased) { _, _ in
                        刷新列表()
                        // 刚打开时，没有日期的作品还没读过状态
                        library.安排检查未发行()
                    }
                    .onChange(of: selectedType) { _, type in
                        selectedStatus = sidebarFilter.flatMap(资料库状态.init)
                            ?? Self.已存状态(for: type)
                        selectedTagIDs = []
                        刷新列表()
                    }
                    .onChange(of: selectedSort) { _, _ in 刷新列表() }
                    // 标题语言设置会改变按标题排序的结果
                    .onChange(of: preferredTitleLang) { _, _ in 刷新列表() }
                    .onChange(of: fallbackTitleLang) { _, _ in 刷新列表() }
                    .onChange(of: allowUnofficialTitles) { _, _ in 刷新列表() }
                    .onAppear { 刷新列表() }
                    .onReceive(sync.$VNDB标签.removeDuplicates()) { labels in
                        vndb标签 = labels
                        刷新列表()
                    }
                    .onReceive(
                        sync.$任务
                            .map { tasks -> Bool in
                                if case .进行中 = tasks[.vndb]?.状态 { return true }
                                return false
                            }
                            .removeDuplicates()
                    ) { vndb导入中 = $0 }
                    .onReceive(
                        sync.$待处理
                            .combineLatest(sync.$任务, sync.$未匹配作品, sync.$已忽略缺失)
                            .map { 同步状态提示.当前(待处理: $0, 任务: $1, 未匹配作品: $2, 已忽略缺失: $3) }
                            .removeDuplicates()
                    ) { value in
                        withAnimation(.smooth(duration: 0.3)) { 同步提示 = value }
                    }
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer,
                        prompt: Text(
                            "搜索“\(selectedStatusTitle)”"
                        )
                    )
                    .overlay {
                        if !有作品 && !isShowingListPlaceholders && 正在按标签筛选 {
                            平台内容不可用视图(
                                "无作品",
                                systemImage: "tag",
                                description: Text("为视觉小说添加一个标签。")
                            )
                        } else if !有作品 && !isShowingListPlaceholders {
                            平台内容不可用视图(
                                "无作品",
                                systemImage: "tray",
                                description: Text("添加作品到资料库。")
                            )
                        } else if 有作品 && searchedListItems.isEmpty && searchedOtherEntries.isEmpty {
                            平台内容不可用视图.search(text: searchText)
                        }
                    }
                    .refreshable {
                        await loadList(forceRefresh: true)
                    }
                    .task(id: automaticListLoadID) {
                        guard 已自动载入 != automaticListLoadID else { return }
                        已自动载入 = automaticListLoadID
                        resetRevealedRatings()
                        await loadList()
                    }
                    .navigationDestination(for: 作品详情目标.self) { target in
                        作品详情(目标: target)
                    }
                    .navigationDestination(for: 用户列表项目.self) { item in
                        视觉小说详情(
                            vnID: item.id,
                            auth: auth,
                            initialTitle: item.vn.title,
                            initialTitles: item.vn.titles,
                            initialImageURL: item.vn.image?.url,
                            initialImageSexual: item.vn.image?.sexual,
                            initialImageViolence: item.vn.image?.violence,
                            initialImageDimensions: item.vn.image?.dims
                        )
                    }
                    .onDisappear {
                        resetRevealedRatings()
                    }
                }
            }
            .overlay(alignment: .top) {
                if sidebarFilter == nil,
                   paperVNSyncEnabled,
                   library.所有者 != nil || auth.isRestoringSession {
                    statusPicker
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            if height > 0, statusPickerHeight != height {
                                statusPickerHeight = height
                            }
                        }

                }
            }
            .navigationTitle(navigationBarTitle)
            .平台柔和滚动边缘(for: .top)
            .toolbar {
                if sidebarFilter == nil {
                    ToolbarItem(placement: .平台前导操作) {
                        if hasVerticalToolbar {
                            反馈与参与菜单()
                        } else {
                            accountToolbarButton
                        }
                    }

                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .平台前导操作)
                    }

                    ToolbarItem(placement: .平台前导操作) {
                        if hasVerticalToolbar {
                            accountToolbarButton
                        } else {
                            反馈与参与菜单()
                        }
                    }
                }

                if sidebarFilter == nil {
                    ToolbarItem(placement: .平台主操作) {
                        syncTaskButton
                    }
                    .平台可见优先级(.高)

                    // 同步任务与排序是两个独立的按钮
                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .平台主操作)
                    }
                }

                ToolbarItem(placement: .平台主操作) {
                    sortMenu
                }
                .平台可见优先级(.高)
            }
            .读取纵向工具栏状态(isVertical: $hasVerticalToolbar)
            // 需要确认时处理页面由资料库弹出，才能从右上角的按钮缩放展开
            .modifier(同步待处理弹出(缩放来源: ("LibrarySyncTaskSheet", namespace)))
            // 用弹出页面打开：推入页面再返回时资料库会重新出现，不应该因此重新载入。
            // 挂在列表外面，资料库还不能使用（未登录、PaperVN Sync已关闭）时右上角的按钮也能打开
            .sheet(isPresented: $显示同步任务) {
                NavigationStack {
                    同步任务页面(showsCloseButton: true)
                }
                // 在同步任务里点“检查更改”时，处理页面要从这个弹出页面上弹出
                .modifier(同步待处理弹出())
                .平台近全屏弹窗(dragIndicator: .visible)
                .navigationTransition(.zoom(
                    sourceID: "LibrarySyncTaskSheet",
                    in: namespace
                ))
            }
            .sheet(isPresented: $showAccountSheet) {
                用户页面(
                    auth: auth,
                    isPresented: $showAccountSheet
                )
                .平台近全屏弹窗(dragIndicator: .hidden)
                .navigationTransition(.zoom(
                    sourceID: "LibraryAccountSheet",
                    in: namespace
                ))
            }
            .sheet(item: $editorTarget) { target in
                let displayedTitle = displayTitle(for: target.item)

                资料库编辑页面(
                    vnID: target.item.id,
                    title: displayedTitle,
                    token: auth.token,
                    currentItem: target.item,
                    releases: [],
                    mode: target.mode,
                    loadsReleasesOnAppear: target.mode == .full
                ) {
                    await loadList(forceRefresh: true)
                }
                .平台近全屏弹窗(dragIndicator: .visible)
                .navigationTransition(.zoom(
                    sourceID: editorTransitionID(for: target.item),
                    in: namespace
                ))
            }
            .sheet(item: $otherEditorTarget) { entry in
                作品资料库编辑页面(entry: entry, title: displayTitle(for: entry))
                    .平台近全屏弹窗(dragIndicator: .visible)
                    .navigationTransition(.zoom(
                        sourceID: otherEditorTransitionID(for: entry),
                        in: namespace
                    ))
            }
            .无法编辑资料库提示($需要登录的平台)
            .Senkou订阅弹出(
                isPresented: Binding {
                    Senkou订阅类型 != nil
                } set: { isPresented in
                    if !isPresented { Senkou订阅类型 = nil }
                }
            ) {
                // 订阅或恢复成功后切换到选择的类型
                if let type = Senkou订阅类型 { selectedType = type }
            }
            // 订阅到期后回到视觉小说
            .onChange(of: senkou.已解锁, initial: true) { _, unlocked in
                if senkou.已确认, !unlocked, selectedType != .visualNovel {
                    selectedType = .visualNovel
                }
            }
            .onChange(of: senkou.已确认) { _, confirmed in
                if confirmed, !senkou.已解锁, selectedType != .visualNovel {
                    selectedType = .visualNovel
                }
            }
            // 用 isPresented 的写法：同一视图上还有别的提示，旧的 alert(item:) { Alert } 不会弹出
            .alert(
                "从资料库删除",
                isPresented: Binding {
                    otherDeleteRequest != nil
                } set: { isPresented in
                    if !isPresented { otherDeleteRequest = nil }
                },
                presenting: otherDeleteRequest
            ) { entry in
                Button("从资料库删除", role: .destructive) {
                    Task {
                        do {
                            try await sync.删除(entry)
                        } catch {
                            apiService.errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { entry in
                Text(verbatim: String(
                    format: String(localized: "要从资料库删除“%@”吗？"),
                    displayTitle(for: entry).text
                ))
            }
            .alert(
                "从资料库删除",
                isPresented: Binding {
                    deleteRequest != nil
                } set: { isPresented in
                    if !isPresented { deleteRequest = nil }
                },
                presenting: deleteRequest
            ) { request in
                Button("从资料库删除", role: .destructive) {
                    Task {
                        await deleteFromLibrary(request.item)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { request in
                Text(verbatim: deleteConfirmationText(for: request.item))
            }
            .alert("无法获取", isPresented: .constant(apiService.errorMessage != nil)) {
                Button("好") {
                    apiService.errorMessage = nil
                }
            } message: {
                Text(verbatim: apiService.errorMessage ?? String(localized: "未知错误。"))
            }
            .overlay(alignment: .bottom) {
                模糊解除提示(
                    isPresented: blurRevealConfirmation.isPromptVisible
                )
                .padding(.bottom, 18)
            }
            .onChange(of: sidebarFilter, initial: true) { _, newFilter in
                if let newFilter {
                    selectedStatus = 资料库状态(newFilter)
                }
            }
            .onDisappear {
                blurRevealConfirmation.cancel()
                resetRevealedRatings()
            }
        }
    }

    private var accountToolbarButton: some View {
        Button {
            showAccountSheet = true
        } label: {
            鲲账户头像(
                profile: kunAccount.isLoggedIn
                    ? kunAccount.profile
                    : nil,
                size: 30
            )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .matchedTransitionSource(
            id: "LibraryAccountSheet",
            in: namespace
        )
        .accessibilityLabel("用户与设置")
    }

    /// 同步任务：需要确认时打开确认页面，其他情况打开同步任务页面。图标随同步状态变化。
    private var syncTaskButton: some View {
        Button {
            if case .需要确认 = 同步提示 {
                sync.显示待处理 = true
            } else {
                显示同步任务 = true
            }
        } label: {
            同步任务按钮图标(提示: 同步提示)
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .matchedTransitionSource(
            id: "LibrarySyncTaskSheet",
            in: namespace
        )
        .accessibilityLabel("同步任务")
    }

    /// 原生分段控件：放得下时占满整行，放不下时按文字的实际宽度排开并可以左右滑动，不用缩短状态名称。
    /// 最左边的圆形按钮选择作品类型。
    private var statusPicker: some View {
        可滚动分段控件(
            titles: statusOptions.map(statusTitle),
            selectedIndex: Binding(
                get: { statusOptions.firstIndex(of: selectedStatus) ?? 0 },
                set: { selectedStatus = statusOptions[$0] }
            ),
            前导菜单: typeMenu
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel("状态")
    }

    /// 选择动画、漫画、轻小说时没有 PaperVN Senkou 会弹出订阅页面，选择不变。
    /// 隐藏延迟免费功能时只能看视觉小说，不显示类型按钮。
    private var typeMenu: 分段栏前导菜单? {
        guard !senkou.隐藏延迟免费功能 else { return nil }
        let types = 作品类型.allCases
        let selection = 类型选择
        return 分段栏前导菜单(
            选项: types.map { .init(title: $0.localizedTitle, symbolName: $0.symbolName) },
            选中: types.firstIndex(of: selectedType) ?? 0,
            accessibilityLabel: String(localized: "类型")
        ) { selection.wrappedValue = types[$0] }
    }

    private var listPositionKey: String {
        "\(selectedType.rawValue)|\(selectedStatus?.rawValue ?? "all")"
    }

    private var statusOptions: [资料库状态?] {
        [nil] + 资料库状态.allCases.map(Optional.some)
    }

    private func statusTitle(_ option: 资料库状态?) -> String {
        option?.localizedTitle(for: selectedType) ?? String(localized: "全部")
    }

    private var sortMenu: some View {
        Menu {
            Picker("排序依据", selection: selectedSortBinding) {
                ForEach(用户列表排序.allCases) { sort in
                    Label {
                        Text(verbatim: sort.localizedTitle)
                    } icon: {
                        Image(systemName: sort.symbolName)
                    }
                    .tag(sort)
                }
            }
            .pickerStyle(.inline)

            Picker("排序方向", selection: $selectedSort.isDescending) {
                Label("升序", systemImage: "arrow.up")
                    .tag(false)
                Label("降序", systemImage: "arrow.down")
                    .tag(true)
            }
            .pickerStyle(.inline)

            if selectedType == .visualNovel, !可选标签.isEmpty {
                Section(String(localized: "资料库标签", defaultValue: "标签", comment: "VNDB用户列表的标签（labels），不是作品的内容标签（tags）")) {
                    ForEach(可选标签) { tag in
                        Toggle(isOn: tagBinding(tag.id)) {
                            if tag.private {
                                Label(tag.显示名称, systemImage: "lock")
                            } else {
                                Text(verbatim: tag.显示名称)
                            }
                            Text("\(标签作品数[tag.id] ?? 0)部作品")
                        }
                        // 可以连续选择多个标签
                        .menuActionDismissBehavior(.disabled)
                    }
                }
            }
        } label: {
            // 按标签筛选时换成实心图标
            Image(systemName: 正在按标签筛选 ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down")
                .font(.body.weight(.semibold))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .accessibilityLabel("排序")
        .accessibilityValue(
            ListFormatter.localizedString(
                byJoining: [selectedSort.sort.localizedTitle, sortDirectionTitle] + 可选标签
                    .filter { selectedTagIDs.contains($0.id) }
                    .map(\.显示名称)
            )
        )
    }

    private var 正在按标签筛选: Bool {
        selectedType == .visualNovel && !selectedTagIDs.isEmpty
    }

    /// VNDB账户里的标签；还没读到时用作品上已有的标签。
    private var 可选标签: [用户列表标签信息] {
        guard vndb标签.isEmpty else { return vndb标签 }
        var seen: Set<Int> = []
        return library.条目.lazy
            .compactMap(\.vndb?.labels)
            .joined()
            .filter { $0.可作为标签 && seen.insert($0.id).inserted }
            .map { 用户列表标签信息(id: $0.id, label: $0.label, private: false) }
            .sorted { $0.id < $1.id }
    }

    private func tagBinding(_ id: Int) -> Binding<Bool> {
        Binding(
            get: { selectedTagIDs.contains(id) },
            set: { isOn in
                if isOn { selectedTagIDs.insert(id) } else { selectedTagIDs.remove(id) }
            }
        )
    }

    private var selectedStatusTitle: String {
        selectedStatus?.localizedTitle(for: selectedType) ?? String(localized: "全部")
    }

    private var navigationBarTitle: String {
        String(localized: "资料库")
    }

    private var sortDirectionTitle: String {
        selectedSort.isDescending
            ? String(localized: "降序")
            : String(localized: "升序")
    }

    private var selectedSortBinding: Binding<用户列表排序> {
        Binding(
            get: { selectedSort.sort },
            set: { selectedSort = 资料库排序选择(sort: $0) }
        )
    }

    /// 同步顺序：先从 Paper Cloud 取回其他设备的更改，再写入并导入VNDB，再同步其他平台，
    /// 最后把这次同步的结果与最近更改一起上传到 Paper Cloud。
    private func loadList(forceRefresh: Bool = false) async {
        guard !auth.isRestoringSession, library.所有者 != nil else { return }
        apiService.errorMessage = nil
        await PaperAccount账户.shared.同步资料库()
        // Bangumi 的视觉小说先加进资料库，登录了VNDB时紧接着写入VNDB
        await sync.导入Bangumi视觉小说()
        if auth.isLoggedIn, !auth.token.isEmpty, !auth.userID.isEmpty {
            await sync.从VNDB导入(
                token: auth.token,
                userID: auth.userID,
                forceRefresh: forceRefresh
            )
            // 已有作品时，失败只在同步任务按钮上提示
            if case let .失败(message) = sync.任务[.vndb]?.状态,
               library.条目.isEmpty {
                apiService.errorMessage = message
            }
        }
        await sync.同步动画漫画()
        await PaperAccount账户.shared.同步资料库()
        let items = library.条目.compactMap(\.vndb)
        apiService.prefetchRecentlyChanged(items)
        apiService.prefetchVisualNovelGraph(vnIDs: items.map(\.id))
    }

    private var automaticListLoadID: 资料库自动加载标识 {
        资料库自动加载标识(
            isSyncEnabled: paperVNSyncEnabled,
            token: auth.token,
            userID: auth.userID,
            isLoggedIn: auth.isLoggedIn,
            isRestoringSession: auth.isRestoringSession,
            owner: library.所有者
        )
    }

    /// 从本地资料库按类型、状态（视觉小说还有标签）筛选并排序。视觉小说以外的类型目前还没有资料库行。
    private func 刷新列表() {
        var entries = library.条目.filter { entry in
            entry.类型 == selectedType
                && (selectedStatus == nil || entry.状态 == selectedStatus)
        }
        if selectedType == .visualNovel {
            var counts: [Int: Int] = [:]
            for entry in entries {
                for id in entry.vndb?.标签ID ?? [] { counts[id, default: 0] += 1 }
            }
            标签作品数 = counts
        }
        if 正在按标签筛选 {
            entries = entries.filter { entry in
                entry.vndb.map { !$0.标签ID.isDisjoint(with: selectedTagIDs) } ?? false
            }
        }
        // 先算好再一次性赋值：同一次刷新里先后赋两个不同的值，会让页面每次都重新计算，
        // 而重新计算又会让 onReceive 重新订阅、再次刷新，形成死循环。
        var 视觉小说 = 资料库排序.排序(
            entries.compactMap(\.vndb),
            by: selectedSort.sort,
            isDescending: selectedSort.isDescending
        ) { displayTitle(for: $0).text }
        var 其他作品 = 资料库排序.排序(
            entries.filter { $0.vndb == nil },
            by: selectedSort.sort,
            isDescending: selectedSort.isDescending
        ) { displayTitle(for: $0).text }

        var 未发行: Set<String> = []
        if separatesUnreleased, selectedStatus == .planning {
            let 未发行视觉小说 = 视觉小说.filter(资料库排序.未发行)
            let 未发行其他作品 = 其他作品.filter(资料库排序.未发行)
            未发行 = Set(未发行视觉小说.map(\.id) + 未发行其他作品.map(\.id))
            // 未发行的放到最后，索引条按这个顺序分段，与列表显示的顺序一致
            视觉小说 = 视觉小说.filter { !未发行.contains($0.id) } + 未发行视觉小说
            其他作品 = 其他作品.filter { !未发行.contains($0.id) } + 未发行其他作品
        }
        listItems = 视觉小说
        otherEntries = 其他作品
        未发行IDs = 未发行
    }

    private var 已发行视觉小说: [用户列表项目] {
        searchedListItems.filter { !未发行IDs.contains($0.id) }
    }

    private var 未发行视觉小说: [用户列表项目] {
        未发行IDs.isEmpty ? [] : searchedListItems.filter { 未发行IDs.contains($0.id) }
    }

    private var 已发行其他作品: [本地资料库条目] {
        searchedOtherEntries.filter { !未发行IDs.contains($0.id) }
    }

    private var 未发行其他作品: [本地资料库条目] {
        未发行IDs.isEmpty ? [] : searchedOtherEntries.filter { 未发行IDs.contains($0.id) }
    }

    private func 视觉小说行(_ item: 用户列表项目) -> some View {
        NavigationLink(value: item) {
            资料库列表行(
                item: item,
                isCoverRevealed:
                    revealedCoverIDs.contains(item.id),
                isAverageRatingRevealed:
                    revealedRatingIDs.contains(item.id),
                revealCover: {
                blurRevealConfirmation.request(
                    id: "library-cover-\(item.id)"
                ) {
                    withAnimation(
                        .easeInOut(duration: 0.22)
                    ) {
                        let _ = revealedCoverIDs.insert(
                            item.id
                        )
                    }
                }
                },
                revealAverageRating: {
                blurRevealConfirmation.request(
                    id: "library-rating-\(item.id)"
                ) {
                    withAnimation(
                        .easeInOut(duration: 0.22)
                    ) {
                        let _ = revealedRatingIDs.insert(
                            item.id
                        )
                    }
                }
                }
            )
        }
        .matchedTransitionSource(
            id: editorTransitionID(for: item),
            in: namespace
        )
        .swipeActions(
            edge: .trailing,
            allowsFullSwipe: true
        ) {
            deleteButton(for: item, source: .swipe)
        }
        .swipeActions(
            edge: .leading,
            allowsFullSwipe: true
        ) {
            Button {
                presentEditor(for: item, mode: .full)
            } label: {
                Label("编辑", systemImage: "square.and.pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                presentEditor(for: item, mode: .full)
            } label: {
                Label("编辑", systemImage: "square.and.pencil")
            }

            if !parentalControls.policy.blocksUntrustedExternalLinks {
                ShareLink(
                    item: URL(
                        string: "https://vndb.org/\(item.id)"
                    )!
                ) {
                    Label("共享", systemImage: "square.and.arrow.up")
                }

                Divider()
            }

            deleteButton(
                for: item,
                source: .contextMenu
            )
        }
    }

    private func 其他作品行(_ entry: 本地资料库条目) -> some View {
        Group {
            if let target = entry.详情目标(标题: displayTitle(for: entry).text) {
                NavigationLink(value: target) {
                    资料库作品行视图(for: entry)
                }
            } else {
                资料库作品行视图(for: entry)
            }
        }
        .matchedTransitionSource(
            id: otherEditorTransitionID(for: entry),
            in: namespace
        )
        .contextMenu { otherEntryMenu(entry) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // 不用 .destructive：它会让列表立刻移除这一行，而确认之前作品还在资料库里
            Button {
                if 可以编辑(entry) { otherDeleteRequest = entry }
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(.red)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                if 可以编辑(entry) { otherEditorTarget = entry }
            } label: {
                Label("编辑", systemImage: "square.and.pencil")
            }
            .tint(.blue)
        }
    }

    private var searchedOtherEntries: [本地资料库条目] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return otherEntries }
        return otherEntries.filter { entry in
            // 后台设置的标题也能搜到
            (entry.全部标题 + (entry.显示用多语言标题 ?? []).map(\.title)).contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var 有作品: Bool {
        !listItems.isEmpty || !otherEntries.isEmpty
    }

    /// 已登录的平台都无法同步这类作品时不能编辑，显示提示。
    private func 可以编辑(_ entry: 本地资料库条目) -> Bool {
        需要登录的平台 = sync.需要登录才能编辑(entry.类型)
        return 需要登录的平台 == nil
    }

    /// 和视觉小说的按住菜单一致：编辑、共享、从资料库删除。
    @ViewBuilder
    private func otherEntryMenu(_ entry: 本地资料库条目) -> some View {
        Button {
            if 可以编辑(entry) { otherEditorTarget = entry }
        } label: {
            Label("编辑", systemImage: "square.and.pencil")
        }
        if let mal = entry.myAnimeList,
           !parentalControls.policy.blocksUntrustedExternalLinks,
           let url = URL(string: "https://myanimelist.net/\(mal.kind.rawValue)/\(mal.id)") {
            ShareLink(item: url) {
                Label("共享", systemImage: "square.and.arrow.up")
            }
            Divider()
        }
        Button(role: .destructive) {
            if 可以编辑(entry) { otherDeleteRequest = entry }
        } label: {
            Label("从资料库删除", systemImage: "trash")
        }
    }

    /// 作品较多时才显示滚动位置气泡。
    private var 显示索引条: Bool {
        !isShowingListPlaceholders && !索引段缓存.isEmpty
    }

    private func 刷新索引段() {
        let 作品 = searchedListItems
        索引作品数 = 作品.count
        索引段缓存 = 作品.count >= 20
            ? 资料库索引.分段(作品, 排序: selectedSort.sort) { displayTitle(for: $0).text }
            : []
    }

    private var isShowingListPlaceholders: Bool {
        guard !有作品 else { return false }
        if auth.isRestoringSession || !library.已载入 { return true }
        if library.条目.isEmpty, vndb导入中 { return true }
        return false
    }

    private var searchedListItems: [用户列表项目] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return listItems }

        return listItems.filter { item in
            if item.vn.title.localizedCaseInsensitiveContains(query) {
                return true
            }
            return item.vn.titles?.contains { title in
                title.title.localizedCaseInsensitiveContains(query)
                    || title.latin?.localizedCaseInsensitiveContains(query) == true
            } == true
        }
    }

    @ViewBuilder
    private func deleteButton(
        for item: 用户列表项目,
        source: 资料库删除来源
    ) -> some View {
        if source == .swipe {
            Button {
                deleteRequest = 资料库删除请求(
                    item: item,
                    source: source
                )
            } label: {
                Label("删除", systemImage: "trash")
            }
            .tint(.red)
            .disabled(isDeleting)
        } else {
            Button(role: .destructive) {
                deleteRequest = 资料库删除请求(
                    item: item,
                    source: source
                )
            } label: {
                Label("从资料库删除", systemImage: "trash")
            }
            .disabled(isDeleting)
        }
    }

    private func displayTitle(
        for item: 用户列表项目
    ) -> 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: item.显示用多语言标题,
            defaultTitle: item.vn.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    private func displayTitle(for entry: 本地资料库条目) -> 标题工具.标题结果 {
        entry.显示标题(偏好: preferredTitleLang, 回退: fallbackTitleLang, 允许非官方: allowUnofficialTitles)
    }

    private func deleteConfirmationText(
        for item: 用户列表项目
    ) -> String {
        let title = displayTitle(for: item)
        return String(
            format: String(localized: "要从资料库删除“%@”吗？"),
            title.text
        )
    }

    /// 动画、漫画与轻小说的行。平均评分的模糊和视觉小说一样：第一次点按提示，再点按一次解除。
    private func 资料库作品行视图(for entry: 本地资料库条目) -> 资料库作品行 {
        资料库作品行(
            entry: entry,
            isAverageRatingRevealed: revealedRatingIDs.contains(entry.id),
            revealAverageRating: {
                blurRevealConfirmation.request(id: "library-rating-\(entry.id)") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        let _ = revealedRatingIDs.insert(entry.id)
                    }
                }
            }
        )
    }

    private func resetRevealedRatings() {
        revealedRatingIDs.removeAll()
        revealedCoverIDs.removeAll()
        blurRevealConfirmation.cancel()
    }

    @MainActor
    private func deleteFromLibrary(_ item: 用户列表项目) async {
        guard !isDeleting else { return }
        isDeleting = true
        deleteRequest = nil

        do {
            try await apiService.deleteUserListEntry(
                token: auth.token,
                vnID: item.id
            )
            library.删除(id: 本地资料库条目.视觉小说ID(item.id))
        } catch {
            apiService.errorMessage = error.localizedDescription
        }

        isDeleting = false
    }

    private func presentEditor(
        for item: 用户列表项目,
        mode: 资料库编辑模式
    ) {
        editorTarget = 资料库编辑目标(item: item, mode: mode)
    }

    private func otherEditorTransitionID(for entry: 本地资料库条目) -> String {
        "LibraryEditorSheet-\(entry.id)"
    }

    private func editorTransitionID(for item: 用户列表项目) -> String {
        "LibraryEditorSheet-\(item.id)"
    }
}

private struct 资料库编辑目标: Identifiable {
    let item: 用户列表项目
    let mode: 资料库编辑模式

    var id: String {
        "\(item.id)-\(mode.rawValue)"
    }
}

struct 资料库列表占位行: View {
    let index: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var coverCornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }

    @ViewBuilder
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 72, height: 100)

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                多语言列表文本(
                    文本: index.isMultiple(of: 2)
                        ? String(localized: "正在加载…")
                        : String(localized: "视觉小说标题"),
                    isJapanese: false,
                    层级: .主标题
                )
                    .lineLimit(1)

                多语言列表文本(
                    文本: "正在加载…",
                    isJapanese: false,
                    层级: .副标题
                )
                    .lineLimit(1)

                Text("游玩状态")
                    .font(.caption)

                HStack(spacing: 8) {
                    Text("0000-00-00")
                    Text("0")
                }
                .font(.caption2)
            }

            Spacer(minLength: 0)
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct 资料库列表行: View {
    let item: 用户列表项目
    let isCoverRevealed: Bool
    let isAverageRatingRevealed: Bool
    let revealCover: () -> Void
    let revealAverageRating: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @作品列表标题偏好读取 private var 标题偏好
    @AppStorage("blurAverageRating") private var blurAverageRating = false
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both

    private var coverCornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        var 内容 = 作品列表行内容(item, 标题: 标题偏好)
        内容.平均评分已模糊 = blurAverageRating && item.vote == nil && !isAverageRatingRevealed
        内容.显示平均评分 = revealAverageRating

        return 作品列表行(场景: .library, 内容: 内容) {
            cover
        }
    }

    private var cover: some View {
        let coverIsRestricted = shouldRestrictCover && !isCoverRevealed

        return ZStack {
            CachedAsyncImage(
                url: URL(
                    string: item.vn.image?.url
                        ?? item.vn.image?.thumbnail
                        ?? ""
                ),
                contentMode: .fill
            )
            .frame(width: 72, height: 100)
            .clipped()
            .应用不安全内容限制(
                coverIsRestricted,
                method: .blurred,
                blurRadius: 18
            )

            if coverIsRestricted && canRevealCover {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: revealCover)
                    .accessibilityLabel("连按两次以解除模糊")
            }
        }
        .frame(width: 72, height: 100)
        .background(Color.secondary.opacity(0.1))
        .clipShape(
            RoundedRectangle(
                cornerRadius: coverCornerRadius,
                style: .continuous
            )
        )
    }

    private var shouldRestrictCover: Bool {
        内容安全限制判定.图片需要限制(
            sexual: item.vn.image?.sexual,
            violence: item.vn.image?.violence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
    }

    private var canRevealCover: Bool {
        内容安全限制判定.图片允许手动解除模糊(
            sexual: item.vn.image?.sexual,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            mode: filterMode
        )
    }
}

struct CachedAsyncImage: View {
    private static let decodedImageCache: NSCache<NSURL, PaperVNCachedImage> = {
        let cache = NSCache<NSURL, PaperVNCachedImage>()
        cache.countLimit = 240
        return cache
    }()

    let url: URL?
    var contentMode: ContentMode = .fill
    var preservesOriginalAspectRatio = false
    var maximumRetryAttempts: Int? = nil
    var onImageLoaded: ((URL, Image, CGSize) -> Void)? = nil
    var onImageReady: ((URL) -> Void)? = nil
    var onImageLoadFailed: ((URL) -> Void)? = nil

    @State private var loadedImage: Image?
    @State private var loadedURL: URL?

    private var remoteURL: URL? {
        guard let url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.12)

            if let loadedImage, loadedURL == remoteURL {
                loadedImage
                    .resizable()
                    .aspectRatio(
                        contentMode: preservesOriginalAspectRatio
                            ? .fit
                            : contentMode
                    )
                    .transition(.opacity)
            }
        }
        .task(id: remoteURL) {
            guard loadedURL != remoteURL || loadedImage == nil else { return }
            loadedImage = nil
            loadedURL = nil

            guard let remoteURL else { return }
            if let cachedImage = Self.decodedImageCache.object(
                forKey: remoteURL as NSURL
            ) {
                let image = swiftUIImage(from: cachedImage)
                loadedImage = image
                loadedURL = remoteURL
                await prepareImmersiveTextSamplesIfNeeded(for: remoteURL)
                guard !Task.isCancelled, remoteURL == self.remoteURL else {
                    return
                }
                onImageReady?(remoteURL)
                onImageLoaded?(remoteURL, image, cachedImage.size)
                return
            }
            await loadImageWithRetry(from: remoteURL)
        }
        .animation(.easeInOut(duration: 0.2), value: loadedURL)
    }

    private func loadImageWithRetry(from url: URL) async {
        var failedAttempts = 0

        while !Task.isCancelled {
            do {
                let resource = try await fetchImage(
                    from: url,
                    bypassingCache: failedAttempts > 0
                )
                guard !Task.isCancelled, remoteURL == url else { return }
                let image = swiftUIImage(from: resource.image)
                loadedImage = image
                loadedURL = url
                await prepareImmersiveTextSamplesIfNeeded(
                    for: url,
                    data: resource.data
                )
                guard !Task.isCancelled, remoteURL == url else { return }
                onImageReady?(url)
                onImageLoaded?(url, image, resource.image.size)
                return
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled, remoteURL == url else { return }
                failedAttempts += 1
                removeCachedResponse(for: url)

                if let imageError = error as? 图片加载错误,
                   !imageError.shouldRetry {
                    onImageLoadFailed?(url)
                    return
                }
                if let maximumRetryAttempts,
                   failedAttempts >= max(1, maximumRetryAttempts) {
                    onImageLoadFailed?(url)
                    return
                }

                if failedAttempts > 1 {
                    let baseDelay = min(
                        pow(2, Double(failedAttempts - 2)),
                        30
                    )
                    let delay = baseDelay + Double.random(in: 0...0.5)
                    do {
                        try await Task.sleep(for: .seconds(delay))
                    } catch {
                        return
                    }
                }
            }
        }
    }

    private func fetchImage(
        from url: URL,
        bypassingCache: Bool
    ) async throws -> 已加载图片资源 {
        let data = try await 图片数据请求协调器.shared.data(
            from: url,
            bypassingCache: bypassingCache
        )

        if let cachedImage = Self.decodedImageCache.object(
            forKey: url as NSURL
        ) {
            return 已加载图片资源(image: cachedImage, data: data)
        }

        guard let decodedImage = PaperVNCachedImage(data: data) else {
            throw 图片加载错误.invalidImageData
        }
        Self.decodedImageCache.setObject(
            decodedImage,
            forKey: url as NSURL
        )
        return 已加载图片资源(image: decodedImage, data: data)
    }

    private func prepareImmersiveTextSamplesIfNeeded(
        for url: URL,
        data: Data? = nil
    ) async {
        guard onImageReady != nil else { return }

        if let data {
            await 沉浸封面文字分析缓存.shared.prepare(data: data, for: url)
            return
        }
        guard !沉浸封面文字分析缓存.shared.containsMap(for: url) else {
            return
        }
        guard let data = try? await 图片数据请求协调器.shared.data(
            from: url,
            bypassingCache: false
        ) else {
            return
        }
        await 沉浸封面文字分析缓存.shared.prepare(data: data, for: url)
    }

    private func removeCachedResponse(for url: URL) {
        URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
    }

    private func swiftUIImage(from image: PaperVNCachedImage) -> Image {
        return Image(uiImage: image)
    }
}

#Preview {
    资料库()
        .environmentObject(PaperVNPremiumStore(previewing: true))
        .environmentObject(用户登录(previewing: true))
        .environmentObject(鲲Galgame账户(previewing: true))
        .environmentObject(Bangumi账户(previewing: true))
        .environmentObject(MyAnimeList账户(previewing: true))
        .environmentObject(家长控制中心.shared)
}

/// 可以横向滚动的原生分段控件。
///
/// 系统分段控件放进SwiftUI的ScrollView后，横向拖动会被控件接住、容易误切换。
/// 这里用UIScrollView包住UISegmentedControl，手指开始横向滑动时取消控件上的触摸，交给滚动。
struct 可滚动分段控件: UIViewRepresentable {
    let titles: [String]
    @Binding var selectedIndex: Int
    /// 最左边的圆形按钮，点按展开菜单，例如资料库的作品类型。
    var 前导菜单: 分段栏前导菜单? = nil
    /// 下面的列表会被整个换掉时（如搜索页切换分类），传入能区分列表的值；变了就重新找要跟随的列表。
    var 列表标识: AnyHashable? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> 资料库分段栏视图 {
        let view = 资料库分段栏视图()
        view.scrollView.delegate = context.coordinator
        view.scrollView.segmentedControl.addTarget(
            context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)),
            for: .valueChanged
        )
        return view
    }

    func updateUIView(_ view: 资料库分段栏视图, context: Context) {
        context.coordinator.parent = self
        view.setLeadingMenu(前导菜单)
        view.setListIdentity(列表标识)
        view.scrollView.setTitles(titles)
        if view.scrollView.segmentedControl.selectedSegmentIndex != selectedIndex {
            view.scrollView.segmentedControl.selectedSegmentIndex = selectedIndex
        }
    }

    /// 分段控件上下的留白。下边距也是它和下方第一个列表分组之间看起来的距离。
    static let 上边距: CGFloat = 4
    static let 下边距: CGFloat = 8

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: 资料库分段栏视图, context: Context) -> CGSize? {
        let controlHeight = uiView.scrollView.segmentedControl.intrinsicContentSize.height
        let height = controlHeight + Self.上边距 + Self.下边距
        let menuWidth = 前导菜单 == nil ? 0 : controlHeight + 资料库分段栏视图.菜单间距
        return CGSize(width: proposal.width ?? uiView.scrollView.contentWidth + menuWidth + 32, height: height)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: 可滚动分段控件

        init(_ parent: 可滚动分段控件) {
            self.parent = parent
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            (scrollView as? 分段滚动视图)?.updateEdgeMask()
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            guard let view = scrollView as? 分段滚动视图 else { return }
            view.didScrollDuringTouch = true
            // 只有选中块真的被拖走时才恢复，重复设置同一个值也会播放一次选中动画
            if view.segmentedControl.selectedSegmentIndex != parent.selectedIndex {
                UIView.performWithoutAnimation {
                    view.segmentedControl.selectedSegmentIndex = parent.selectedIndex
                }
            }
        }

        /// 这次触摸里横向滚动过，就不是点按：撤销分段控件自己做的切换。
        @objc func selectionChanged(_ control: UISegmentedControl) {
            guard let view = control.superview as? 分段滚动视图 else { return }
            if view.didScrollDuringTouch || view.isDragging || view.isDecelerating {
                if control.selectedSegmentIndex != parent.selectedIndex {
                    UIView.performWithoutAnimation {
                        control.selectedSegmentIndex = parent.selectedIndex
                    }
                }
                return
            }
            parent.selectedIndex = control.selectedSegmentIndex
            view.scrollSegmentToVisible(control.selectedSegmentIndex)
        }
    }
}

/// 分段控件左边圆形按钮的菜单。
struct 分段栏前导菜单 {
    struct 选项 {
        let title: String
        let symbolName: String
    }

    let 选项: [选项]
    let 选中: Int
    let accessibilityLabel: String
    let 选择: (Int) -> Void
}

/// Picker覆盖在列表顶部，下拉时和原生滚动边缘使用同一个容器跟随列表。
final class 资料库分段栏视图: UIView {
    let scrollView = 分段滚动视图()
    /// 和分段控件放在同一个随列表移动的容器里，下拉时一起移动。
    private let menuButton = UIButton(type: .system)
    private var menuSignature: [String] = []
    private var menuSelection: ((Int) -> Void)?
    static let 菜单间距: CGFloat = 8

    private let movingContainer = UIView()
    /// iOS 26的UIScrollEdgeElementContainerInteraction；iOS 18没有滚动边缘效果，保持nil。
    private var edgeInteraction: UIInteraction?
    private weak var listScrollView: UIScrollView?
    private var offsetObservation: NSKeyValueObservation?
    private var insetObservation: NSKeyValueObservation?
    private var isUpdatingPullDown = false
    private var listIdentity: AnyHashable?
    /// 切换列表时正在移走的旧列表，重新查找时跳过。
    private weak var excludedListScrollView: UIScrollView?
    /// 只让最近一次切换的重新连接生效。
    private var reconnectGeneration = 0
    /// 已经照着复制过的列表位置动画，避免同一个动画重复叠加。
    private let followedListAnimations = NSHashTable<CAAnimation>.weakObjects()

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = false
        addSubview(movingContainer)
        movingContainer.addSubview(scrollView)
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.cornerStyle = .capsule
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .subheadline, scale: .medium)
        configuration.contentInsets = .zero
        menuButton.configuration = configuration
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.isHidden = true
        movingContainer.addSubview(menuButton)
        // 让包含真实Picker的容器参与系统边缘效果，范围由控件决定。
        // 交互和Picker一起移动，避免在固定的外层容器内单独移动其边缘元素。
        if #available(iOS 26.0, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .top
            movingContainer.addInteraction(interaction)
            edgeInteraction = interaction
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLeadingMenu(_ menu: 分段栏前导菜单?) {
        guard let menu, menu.选项.indices.contains(menu.选中) else {
            if !menuButton.isHidden {
                menuButton.isHidden = true
                menuSignature = []
                setNeedsLayout()
            }
            return
        }
        // 资料库每次重绘都会调用这里。选择闭包每次都会换，只记下最新的；
        // 菜单内容不变时不重建菜单和按钮配置，展开中的菜单也不会被替换
        menuSelection = menu.选择
        let signature = menu.选项.map { $0.title + $0.symbolName }
            + [String(menu.选中), menu.accessibilityLabel]
        guard menuButton.isHidden || signature != menuSignature else { return }
        menuSignature = signature
        menuButton.isHidden = false
        menuButton.accessibilityLabel = menu.accessibilityLabel
        menuButton.accessibilityValue = menu.选项[menu.选中].title
        menuButton.configuration?.image = UIImage(systemName: menu.选项[menu.选中].symbolName)
        menuButton.menu = UIMenu(options: .singleSelection, children: menu.选项.enumerated().map { index, item in
            UIAction(
                title: item.title,
                image: UIImage(systemName: item.symbolName),
                state: index == menu.选中 ? .on : .off
            ) { [weak self] _ in self?.menuSelection?(index) }
        })
        setNeedsLayout()
    }

    /// 列表换成新的滚动视图后还跟着旧的，Picker会停在旧列表的位置，和新列表的内容重叠。
    func setListIdentity(_ identity: AnyHashable?) {
        guard identity != listIdentity else { return }
        listIdentity = identity
        guard let previous = listScrollView else { return }
        // 切换时旧列表可能还没移出层级（两个列表一样大），重新查找时先跳过它，
        // 否则又会连回正在移走的旧列表。同一个列表只是换了内容时，找不到别的再连回它。
        excludedListScrollView = previous
        reconnectGeneration += 1
        let generation = reconnectGeneration
        DispatchQueue.main.async { [weak self] in
            self?.reconnectList(generation: generation, remainingAttempts: 8)
        }
    }

    private func disconnectList() {
        offsetObservation = nil
        insetObservation = nil
        if #available(iOS 26.0, *) {
            (edgeInteraction as? UIScrollEdgeElementContainerInteraction)?.scrollView = nil
        }
        listScrollView = nil
        for key in movingContainer.layer.animationKeys() ?? [] where key.hasPrefix("followListScroll.") {
            movingContainer.layer.removeAnimation(forKey: key)
        }
        movingContainer.transform = .identity
    }

    private func reconnectList(generation: Int, remainingAttempts: Int) {
        guard generation == reconnectGeneration else { return }
        disconnectList()
        connectListIfNeeded()
        guard listScrollView == nil, excludedListScrollView != nil else {
            excludedListScrollView = nil
            return
        }
        if remainingAttempts > 0, window != nil {
            // 新列表还没装进层级，下一轮再找。
            DispatchQueue.main.async { [weak self] in
                self?.reconnectList(generation: generation, remainingAttempts: remainingAttempts - 1)
            }
        } else {
            // 一直只有原来的列表：列表本身没换，只是内容变了，连回它。
            excludedListScrollView = nil
            connectListIfNeeded()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            disconnectList()
            return
        }
        // 等SwiftUI完成List层级安装，再连接真正的纵向滚动视图。
        DispatchQueue.main.async { [weak self] in
            self?.connectListIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let contentBounds = CGRect(origin: .zero, size: bounds.size)
        let contentCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        if movingContainer.bounds != contentBounds {
            movingContainer.bounds = contentBounds
        }
        if movingContainer.center != contentCenter {
            movingContainer.center = contentCenter
        }

        let controlHeight = max(0, bounds.height - 可滚动分段控件.上边距 - 可滚动分段控件.下边距)
        var leading: CGFloat = 16
        if !menuButton.isHidden {
            let buttonFrame = CGRect(x: leading, y: 可滚动分段控件.上边距, width: controlHeight, height: controlHeight)
            if menuButton.frame != buttonFrame {
                menuButton.frame = buttonFrame
            }
            leading += controlHeight + Self.菜单间距
        }
        let scrollFrame = CGRect(
            x: leading,
            y: 可滚动分段控件.上边距,
            width: max(0, bounds.width - leading - 16),
            height: controlHeight
        )
        if scrollView.frame != scrollFrame {
            scrollView.frame = scrollFrame
        }

        connectListIfNeeded()
        updatePullDown()
        // SwiftUI会把覆盖层直接放到新的安全区位置，列表却还在动画里。
        followListAnimation()
    }

    private func connectListIfNeeded() {
        // 跟随的列表已经离开窗口（被换掉了），断开后重新找。
        if let listScrollView, listScrollView.window == nil {
            disconnectList()
        }
        guard listScrollView == nil, let window else { return }
        let headerRect = convert(bounds, to: window)
        var ancestor = superview
        while let view = ancestor {
            var candidate: UIScrollView?
            func search(_ view: UIView) {
                guard view !== self, !view.isHidden, view.alpha > 0.01 else { return }
                if let scroll = view as? UIScrollView,
                   scroll !== excludedListScrollView,
                   scroll.bounds.height > bounds.height * 2,
                   scroll.convert(scroll.bounds, to: window).intersects(headerRect),
                   scroll.bounds.height > (candidate?.bounds.height ?? 0) {
                    candidate = scroll
                }
                view.subviews.forEach(search)
            }
            search(view)
            if let candidate {
                listScrollView = candidate
                excludedListScrollView = nil
                if #available(iOS 26.0, *) {
                    candidate.topEdgeEffect.style = .soft
                    (edgeInteraction as? UIScrollEdgeElementContainerInteraction)?.scrollView = candidate
                }
                offsetObservation = candidate.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        self?.updatePullDown()
                        self?.followListAnimationIfNeeded()
                    }
                }
                insetObservation = candidate.observe(\.adjustedContentInset, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated {
                        self?.updatePullDown()
                        self?.followListAnimationIfNeeded()
                    }
                    // SwiftUI移动的是外层容器，Picker自己收不到布局回调；等覆盖层挪到新位置后再对齐一次。
                    DispatchQueue.main.async { [weak self] in
                        self?.updatePullDown()
                    }
                }
                return
            }
            ancestor = view.superview
        }
    }

    private func updatePullDown() {
        guard !isUpdatingPullDown, let listScrollView else { return }
        // 跟随的列表已经被移走，按它算出来的位置不对；回到原位并重新找列表。
        guard listScrollView.window != nil else {
            disconnectList()
            DispatchQueue.main.async { [weak self] in
                self?.connectListIfNeeded()
            }
            return
        }
        let distanceFromTop = listScrollView.contentOffset.y
            + listScrollView.adjustedContentInset.top
        // Picker停在导航栏底部，下拉时跟着内容顶部往下走，两者都按Picker自己的坐标算。
        // 大标题展开收起、开始刷新时，列表的inset先变，SwiftUI晚一点（有时晚一帧）才把覆盖层挪到新的安全区；
        // 只按inset差值算的话，这段时间Picker会停在旧位置顿一下。
        let restingTop = listScrollView.convert(
            CGPoint(x: 0, y: listScrollView.bounds.minY + listScrollView.adjustedContentInset.top),
            to: self
        ).y
        let contentTop = listScrollView.convert(CGPoint.zero, to: self).y
        let offset = max(restingTop, contentTop)
        let shouldHideTopEdgeEffect = distanceFromTop <= 0.5
        // iOS 18没有滚动边缘效果，只需要跟随下拉。
        let needsEdgeVisibilityUpdate: Bool
        if #available(iOS 26.0, *) {
            needsEdgeVisibilityUpdate = listScrollView.topEdgeEffect.isHidden
                != shouldHideTopEdgeEffect
        } else {
            needsEdgeVisibilityUpdate = false
        }
        let transform = CGAffineTransform(translationX: 0, y: offset)
        let needsTransformUpdate = movingContainer.transform != transform
        guard needsTransformUpdate || needsEdgeVisibilityUpdate else { return }
        isUpdatingPullDown = true
        defer { isUpdatingPullDown = false }
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if needsEdgeVisibilityUpdate, #available(iOS 26.0, *) {
                // 顶部和下拉期间不绘制边缘遮罩，内容离开顶部后再启用。
                // 这里只让切换落在同一帧；真正保持隐藏靠列表上的 平台隐藏滚动边缘。
                listScrollView.topEdgeEffect.isHidden = shouldHideTopEdgeEffect
            }
            if needsTransformUpdate {
                movingContainer.transform = transform
                // 将当前待处理的边缘布局也放进同一次无动画更新；
                // 只禁止transform动画不能覆盖随后发生的滚动视图布局。
                // 只切换边缘效果时（手指刚离开顶部）不强制布局：这时正在滚动，同步布局整个列表会卡一下。
                movingContainer.layoutIfNeeded()
                listScrollView.layoutIfNeeded()
            }
            CATransaction.commit()
        }
    }

    /// 导航栏收起或展开时（如点搜索框），系统用Core Animation移动列表，contentOffset直接是终点，
    /// SwiftUI也把Picker直接放到了终点。把列表的位置动画原样复制一份给Picker，
    /// 两者由同一套渲染时序驱动，才能逐帧对齐。
    private func followListAnimationIfNeeded() {
        // 只有系统动画块里的改变才会带动画；手指滚动不在动画块里，直接跳过。
        guard UIView.inheritedAnimationDuration > 0 else { return }
        followListAnimation()
        // 动画可能在这次回调之后才加到列表上。
        DispatchQueue.main.async { [weak self] in
            self?.followListAnimation()
        }
    }

    private func followListAnimation() {
        guard let listScrollView else { return }
        let listLayer = listScrollView.layer
        // 关闭搜索时系统会在相邻两帧各加一段（"bounds.origin"、"bounds.origin-2"），
        // 叠加起来才是完整位移，每一段都要跟。
        for key in listLayer.animationKeys() ?? [] where key.hasPrefix("bounds.origin") {
            guard let source = listLayer.animation(forKey: key) as? CABasicAnimation,
                  !followedListAnimations.contains(source),
                  let copy = source.copy() as? CABasicAnimation else { continue }
            followedListAnimations.add(source)
            // 列表内容显示在 终点 - (显示中的bounds.origin - 终点)，Picker要偏移同样的距离。
            func pickerOffset(_ value: Any?) -> NSValue? {
                guard let origin = (value as? NSValue)?.cgPointValue else { return nil }
                let delta = source.isAdditive ? origin.y : origin.y - listScrollView.bounds.origin.y
                return NSValue(cgPoint: CGPoint(x: 0, y: -delta))
            }
            copy.keyPath = "position"
            copy.isAdditive = true
            copy.fromValue = pickerOffset(source.fromValue ?? listLayer.presentation()?.bounds.origin)
            copy.toValue = pickerOffset(source.toValue ?? listScrollView.bounds.origin)
            copy.byValue = nil
            if copy.beginTime != 0 {
                copy.beginTime = movingContainer.layer.convertTime(source.beginTime, from: listLayer)
            }
            movingContainer.layer.add(copy, forKey: "followListScroll." + key)
        }
    }
}

/// 包着原生分段控件的横向滚动视图。分段控件保留自己的触摸处理（按下动画是系统的），
/// 一次触摸里如果发生了横向滚动，就撤销这次切换。
final class 分段滚动视图: UIScrollView {
    let segmentedControl = 可横向滚动的分段控件()
    /// 当前这次触摸里是否滚动过；每次新触摸开始时清零。
    var didScrollDuringTouch = false
    private var titles: [String] = []
    /// 各段按文字算出的自然宽度。
    private var naturalWidths: [CGFloat] = []
    private var appliedSegmentWidths: [CGFloat] = []
    private let edgeMask = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        scrollsToTop = false
        // 这里只处理横向分段滚动，不参与列表的顶部安全区调整。
        contentInsetAdjustmentBehavior = .never
        alwaysBounceVertical = false
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = true
            bottomEdgeEffect.isHidden = true
        }
        // 内容放得下时不能拖动，也不回弹
        alwaysBounceHorizontal = false
        clipsToBounds = true
        edgeMask.startPoint = CGPoint(x: 0, y: 0.5)
        edgeMask.endPoint = CGPoint(x: 1, y: 0.5)
        layer.mask = edgeMask
        // 保留默认的触摸延迟：手指一按下就开始滑动时，分段控件根本收不到这次触摸，
        // 不会出现按下又松开的选中动画；按住不动约0.15秒后才交给分段控件
        addSubview(segmentedControl)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let view = super.hitTest(point, with: event) else { return nil }
        // 还在滚动（惯性滑动）时按下，这次触摸只用来停住或继续滚动，不交给分段控件，
        // 否则选中块会先播放按下动画，再被滚动取消，看起来像原地又选了一次
        if isDragging || isDecelerating {
            return self
        }
        if event?.type == .touches {
            didScrollDuringTouch = false
        }
        return view
    }

    /// UIScrollView默认不取消UIControl上的触摸，横向滑动时让分段控件放弃这次触摸。
    override func touchesShouldCancel(in view: UIView) -> Bool {
        true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setTitles(_ newTitles: [String]) {
        guard newTitles != titles else { return }
        titles = newTitles
        appliedSegmentWidths = []
        let selected = segmentedControl.selectedSegmentIndex
        segmentedControl.removeAllSegments()
        for (index, title) in newTitles.enumerated() {
            segmentedControl.insertSegment(withTitle: title, at: index, animated: false)
        }
        segmentedControl.selectedSegmentIndex = min(max(selected, 0), newTitles.count - 1)
        // 按选中时的粗体测量，保证切换选中后文字不会被截断
        let font = UIFont.systemFont(ofSize: UIFont.systemFontSize - 1, weight: .semibold)
        naturalWidths = newTitles.map {
            ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 28
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    var contentWidth: CGFloat {
        naturalWidths.reduce(0, +)
    }

    /// 放得下时各段按比例放大拉满整行，放不下时用自然宽度并可以滚动。
    private var segmentWidths: [CGFloat] {
        let total = contentWidth
        guard total > 0, bounds.width > total else { return naturalWidths }
        return naturalWidths.map { $0 * bounds.width / total }
    }

    /// 点到半露在边缘的分段时，把它完整滚进来。
    func scrollSegmentToVisible(_ index: Int) {
        let widths = segmentWidths
        guard widths.indices.contains(index) else { return }
        let start = widths[..<index].reduce(0, +)
        let frame = CGRect(x: start, y: 0, width: widths[index], height: bounds.height)
        scrollRectToVisible(frame.insetBy(dx: -24, dy: 0), animated: true)
    }

    /// 左右渐隐只取决于横向内容，不通过页面状态更新，也不参与纵向回弹动画。
    func updateEdgeMask() {
        let hasLeading = contentOffset.x > 1
        let hasTrailing = contentOffset.x + bounds.width < contentSize.width - 1
        let fade = min(28 / max(bounds.width, 1), 0.5)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeMask.frame = bounds
        edgeMask.colors = [
            (hasLeading ? UIColor.clear : .black).cgColor,
            UIColor.black.cgColor,
            UIColor.black.cgColor,
            (hasTrailing ? UIColor.clear : .black).cgColor
        ]
        edgeMask.locations = [0, NSNumber(value: Double(fade)), NSNumber(value: Double(1 - fade)), 1]
        CATransaction.commit()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let widths = segmentWidths
        if appliedSegmentWidths != widths {
            appliedSegmentWidths = widths
            for (index, width) in widths.enumerated() where index < segmentedControl.numberOfSegments {
                segmentedControl.setWidth(width, forSegmentAt: index)
            }
        }
        let width = max(widths.reduce(0, +), bounds.width)
        let controlFrame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        if segmentedControl.frame != controlFrame {
            segmentedControl.frame = controlFrame
        }
        if contentSize.width != width || contentSize.height != bounds.height {
            contentSize = CGSize(width: width, height: bounds.height)
        }
        updateEdgeMask()
    }
}

/// iOS 26 的分段控件会在 `gestureRecognizerShouldBegin` 里拦住父视图的滚动手势（为了拖动选中块），
/// 放进横向滚动视图后就滚不动。这里按手指的移动方向判断：横向为主时交给滚动，
/// 滚动开始后系统会取消分段控件这次的触摸，选中项不变；轻点仍由分段控件处理，保留系统动画。
final class 可横向滚动的分段控件: UISegmentedControl {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let pan = gestureRecognizer as? UIPanGestureRecognizer,
           let scrollView = pan.view as? UIScrollView,
           scrollView === superview {
            let velocity = pan.velocity(in: scrollView)
            return abs(velocity.x) > abs(velocity.y)
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

/// 动画、漫画与轻小说的资料库行：封面、标题、状态与进度。
/// 资料库行里的状态胶囊，视觉小说与动画、漫画、轻小说共用。
struct 资料库状态标签: View {
    let symbolName: String
    let title: String
    /// 动画、漫画与轻小说看到或读到第几话，跟在状态后面。
    var 进度: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.secondary.opacity(0.14), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                }
                .contentShape(Circle())

            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let 进度 {
                Text(verbatim: 进度)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 9)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 0.5)
        }
        .fixedSize()
    }
}

/// 动画、漫画与轻小说的资料库行。排版与 `资料库列表行`（视觉小说）一致：
/// 封面尺寸和圆角相同、行没有额外的上下边距，封面圆角才能和列表单元格形成同心圆。
struct 资料库作品行: View {
    let entry: 本地资料库条目
    /// 与视觉小说的行一样，由资料库页面记住哪些作品已解除模糊，并且先提示、再点按一次才解除。
    let isAverageRatingRevealed: Bool
    let revealAverageRating: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @作品列表标题偏好读取 private var 标题偏好
    @AppStorage("blurAverageRating") private var blurAverageRating = false
    @AppStorage private var ratingSources: String
    @AppStorage private var ratingMethod: String
    private let 评分快照 = 作品评分快照存储.shared

    init(entry: 本地资料库条目, isAverageRatingRevealed: Bool = false, revealAverageRating: (() -> Void)? = nil) {
        self.entry = entry
        self.isAverageRatingRevealed = isAverageRatingRevealed
        self.revealAverageRating = revealAverageRating
        // 读取“评分”设置只是为了设置改变时重新合成
        _ratingSources = AppStorage(wrappedValue: "", 评分设置.来源键(entry.类型))
        _ratingMethod = AppStorage(wrappedValue: "", 评分设置.方式键(entry.类型))
    }

    var body: some View {
        var 内容 = 作品列表行内容(entry, 标题: 标题偏好)
        // 打开过详情页的作品，按详情页的各平台评分合成，和详情页显示的一致
        if let 快照 = 评分快照.快照(entry.id) {
            内容.平均评分 = 快照.综合评分.map { .数值($0.分数 * 10) }
        }
        内容.平均评分已模糊 = blurAverageRating && entry.评分 == nil && !isAverageRatingRevealed
        内容.显示平均评分 = revealAverageRating

        return 作品列表行(场景: .library, 内容: 内容) {
            CachedAsyncImage(url: entry.封面地址.flatMap(URL.init(string:)), contentMode: .fill)
                .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
                .clipped()
                .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
                .background(Color.secondary.opacity(0.1))
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass),
                        style: .continuous
                    )
                )
        }
    }
}

#if DEBUG
// MARK: - PaperVN 2 预览

#Preview("资料库：PaperVN 2组件") {
    预览状态切换([
        .init("同步状态提示") {
            // 需要确认的四种情况，以及正在同步、失败、缺失的作品
            let sessions = [
                预览数据.资料库减少会话,
                预览数据.导入方式会话(),
                预览数据.检查更改会话(),
                预览数据.确认会话(),
            ]
            let others: [同步状态提示] = [
                .正在同步(已完成: 37, 总数: 52, 平台: [.myAnimeList, .aniList]),
                .正在同步(已完成: 0, 总数: nil, 平台: [.annict]),
                .失败([.annict, .tmdb]),
                .缺失作品(4),
            ]
            List {
                ForEach(sessions.indices, id: \.self) { index in
                    if let text = PaperVNSync中心.待处理说明(sessions[index]) {
                        Section {
                            同步状态提示行(提示: .需要确认(text))
                        }
                    }
                }
                ForEach(others.indices, id: \.self) { index in
                    Section {
                        同步状态提示行(提示: others[index], 忽略: others[index] == .缺失作品(4) ? {} : nil)
                    }
                }
            }
        },
        .init("动画、漫画与轻小说的行") {
            NavigationStack {
                List(预览数据.资料库条目) { entry in
                    NavigationLink(value: entry.id) {
                        资料库作品行(entry: entry)
                    }
                }
                .navigationTitle("资料库")
            }
        },
        .init("状态标签") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(作品类型.allCases) { type in
                    HStack {
                        ForEach(资料库状态.allCases) { status in
                            资料库状态标签(symbolName: status.用户列表筛选.symbolName, title: status.localizedTitle(for: type))
                        }
                    }
                }
            }
            .padding()
        },
    ])
}

#Preview("资料库：PaperVN 2页面") {
    预览状态切换([
        .init("动画（有待确认的同步）", 准备: {
            本地资料库.shared.预览载入(预览数据.资料库条目)
            PaperVNSync中心.shared.预览设置(待处理: 预览数据.检查更改会话())
        }) {
            资料库()
                .defaultAppStorage(预览数据.设置("资料库动画", ["libraryWorkType": 作品类型.anime.rawValue]))
        },
        .init("漫画", 准备: {
            本地资料库.shared.预览载入(预览数据.资料库条目)
            PaperVNSync中心.shared.预览设置()
        }) {
            资料库()
                .defaultAppStorage(预览数据.设置("资料库漫画", ["libraryWorkType": 作品类型.manga.rawValue]))
        },
        .init("PaperVN Sync已关闭") {
            资料库()
                .defaultAppStorage(预览数据.设置("资料库同步关闭", [PaperVNSync中心.启用设置键: false]))
        },
        .init("需要登录") {
            资料库()
                .预览环境(已登录: false)
                .defaultAppStorage(预览数据.设置("资料库未登录"))
        },
    ])
    .预览环境()
}
#endif

/// 资料库右上角同步任务按钮的图标：正在同步时旋转，需要确认、失败时换成带感叹号的图标并着色。
private struct 同步任务按钮图标: View {
    let 提示: 同步状态提示?

    var body: some View {
        switch 提示 {
        case .需要确认:
            Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                .foregroundStyle(.orange)
        case .正在同步:
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolEffect(.rotate, options: .repeat(.continuous))
        case .失败:
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.red)
        case .缺失作品, nil:
            Image(systemName: "arrow.triangle.2.circlepath")
        }
    }
}
