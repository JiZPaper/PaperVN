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
    let filter: 用户列表筛选
    let sortSelection: 资料库排序选择
    let token: String
    let userID: String
    let isLoggedIn: Bool
    let isRestoringSession: Bool
}

#if compiler(>=6.5)
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

struct 资料库: View {
    @Namespace private var namespace
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var kunAccount: 鲲Galgame账户
    @EnvironmentObject private var parentalControls: 家长控制中心
    @StateObject private var apiService = VNDB服务.shared
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()

    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false

    @State private var selectedFilter: 用户列表筛选 = .all
    @State private var selectedSort = 资料库排序选择()
    private let sidebarFilter: 用户列表筛选?

    init(sidebarFilter: 用户列表筛选? = nil) {
        self.sidebarFilter = sidebarFilter
        if let sidebarFilter {
            _selectedFilter = State(initialValue: sidebarFilter)
        }
    }
    @State private var listItems: [用户列表项目] = []
    @State private var isLoadingList = false
    @State private var hasCompletedListLoad = false
    @State private var listLoadGeneration = 0
    @State private var displayedListUserID: String?
    @State private var displayedListFilter: 用户列表筛选?
    @State private var editorTarget: 资料库编辑目标?
    @State private var deleteRequest: 资料库删除请求?
    @State private var isDeleting = false
    @State private var revealedRatingIDs: Set<String> = []
    @State private var revealedCoverIDs: Set<String> = []
    @State private var searchText = ""
    @State private var showAccountSheet = false
    @State private var showFeedbackSheet = false
    @State private var showTranslationContributionSheet = false
    @State private var showTodayRecommendationSheet = false
    @State private var hasVerticalToolbar = false

    var body: some View {
        NavigationStack {
            Group {
                if !auth.isLoggedIn && !auth.isRestoringSession {
                    平台内容不可用视图(
                        "需要登录",
                        systemImage: "person.crop.circle",
                        description: Text("登录VNDB账户以使用资料库功能。")
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
                                            ? "正在载入…"
                                            : "正在载入…"
                                    )
                                }
                                .textCase(nil)
                                .accessibilityElement(children: .combine)
                            }
                        } else {
                            Section {
                                ForEach(searchedListItems) { item in
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
                            }
                        }
                    }
                    .平台分组列表样式()
                    .searchable(
                        text: $searchText,
                        prompt: Text(
                            "搜索“\(selectedFilter.localizedTitle)”"
                        )
                    )
                    .overlay {
                        if listItems.isEmpty && !isShowingListPlaceholders {
                            平台内容不可用视图(
                                "无视觉小说",
                                systemImage: "tray",
                                description: Text("添加视觉小说到资料库。")
                            )
                        } else if !listItems.isEmpty && searchedListItems.isEmpty {
                            平台内容不可用视图.search(text: searchText)
                        }
                    }
                    .refreshable {
                        await loadList(forceRefresh: true)
                    }
                    .task(id: automaticListLoadID) {
                        resetRevealedRatings()
                        await loadList()
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
            .navigationTitle(navigationBarTitle)
            .平台柔和滚动边缘(for: .top)
            .toolbar {
                if sidebarFilter == nil {
                    ToolbarItem(placement: .平台前导操作) {
                        if hasVerticalToolbar {
                            feedbackToolbarButton
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
                            feedbackToolbarButton
                        }
                    }
                }

                ToolbarItem(placement: .平台主操作) {
                    Menu {
                        if sidebarFilter == nil {
                            Picker("筛选", selection: $selectedFilter) {
                                ForEach(用户列表筛选.allCases) { filter in
                                    Label {
                                        Text(verbatim: filter.localizedTitle)
                                    } icon: {
                                        Image(systemName: filter.symbolName)
                                    }
                                    .tag(filter)
                                }
                            }
                            .pickerStyle(.inline)

                            Divider()
                        }

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
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.body.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(sidebarFilter == nil ? "筛选与排序" : "排序")
                    .accessibilityValue(filterAndSortAccessibilityValue)
                }
            }
            .读取纵向工具栏状态(isVertical: $hasVerticalToolbar)
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
            .sheet(isPresented: $showFeedbackSheet) {
                NavigationStack {
                    反馈页面(
                        showsCloseButton: true,
                        closeAction: { showFeedbackSheet = false }
                    )
                }
                .平台近全屏弹窗(dragIndicator: .hidden)
                .navigationTransition(.zoom(
                    sourceID: "LibraryFeedbackSheet",
                    in: namespace
                ))
            }
            .sheet(isPresented: $showTranslationContributionSheet) {
                简介翻译贡献页面(auth: auth)
                    .平台近全屏弹窗(dragIndicator: .hidden)
                    .navigationTransition(.zoom(
                        sourceID: "LibraryFeedbackSheet",
                        in: namespace
                    ))
            }
            .sheet(isPresented: $showTodayRecommendationSheet) {
                Today推荐页面(vndbAccount: auth.vndb账户)
                    .平台近全屏弹窗(dragIndicator: .hidden)
                    .navigationTransition(.zoom(
                        sourceID: "LibraryFeedbackSheet",
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
            .alert(item: $deleteRequest) { request in
                Alert(
                    title: Text("从资料库删除"),
                    message: Text(verbatim: deleteConfirmationText(for: request.item)),
                    primaryButton: .destructive(Text("从资料库删除")) {
                        Task {
                            await deleteFromLibrary(request.item)
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
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
            .onChange(of: sidebarFilter) { _, newFilter in
                if let newFilter {
                    selectedFilter = newFilter
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

    private var feedbackToolbarButton: some View {
        Menu {
            Button {
                showFeedbackSheet = true
            } label: {
                Label("反馈", systemImage: "exclamationmark.bubble")
            }

            Button {
                showTranslationContributionSheet = true
            } label: {
                Label("贡献翻译", systemImage: "character.bubble")
            }

            Button {
                showTodayRecommendationSheet = true
            } label: {
                Label("参与Today", systemImage: "doc.text.image")
            }
        } label: {
            Image(systemName: "ellipsis.bubble")
        }
        .matchedTransitionSource(
            id: "LibraryFeedbackSheet",
            in: namespace
        )
        .accessibilityLabel("反馈与参与")
    }

    private var navigationBarTitle: String {
        String(localized: "资料库")
    }

    private var sortDirectionTitle: String {
        selectedSort.isDescending
            ? String(localized: "降序")
            : String(localized: "升序")
    }

    private var filterAndSortAccessibilityValue: String {
        ListFormatter.localizedString(
            byJoining: [
                selectedFilter.localizedTitle,
                selectedSort.sort.localizedTitle,
                sortDirectionTitle
            ]
        )
    }

    private var selectedSortBinding: Binding<用户列表排序> {
        Binding(
            get: { selectedSort.sort },
            set: { selectedSort = 资料库排序选择(sort: $0) }
        )
    }

    private func loadList(forceRefresh: Bool = false) async {
        guard !auth.isRestoringSession,
              auth.isLoggedIn,
              !auth.token.isEmpty,
              !auth.userID.isEmpty else {
            return
        }
        let requestedFilter = selectedFilter
        let requestedSortSelection = selectedSort
        let requestedToken = auth.token
        let requestedUserID = auth.userID
        listLoadGeneration &+= 1
        let generation = listLoadGeneration
        var didFinishRequest = false

        defer {
            if isCurrentListRequest(
                generation: generation,
                filter: requestedFilter,
                sortSelection: requestedSortSelection,
                token: requestedToken,
                userID: requestedUserID
            ) {
                isLoadingList = false
                if didFinishRequest {
                    hasCompletedListLoad = true
                }
            }
        }

        if let cached = VNDB服务.shared.loadCachedList(
            filter: requestedFilter,
            userID: requestedUserID,
            sort: requestedSortSelection.sort,
            isDescending: requestedSortSelection.isDescending
        ) {
            guard isCurrentListRequest(
                generation: generation,
                filter: requestedFilter,
                sortSelection: requestedSortSelection,
                token: requestedToken,
                userID: requestedUserID
            ) else { return }
            listItems = cached
            displayedListUserID = requestedUserID
            displayedListFilter = requestedFilter
            apiService.prefetchRecentlyChanged(cached)
            apiService.prefetchVisualNovelGraph(
                vnIDs: cached.map(\.id)
            )
        } else {
            guard isCurrentListRequest(
                generation: generation,
                filter: requestedFilter,
                sortSelection: requestedSortSelection,
                token: requestedToken,
                userID: requestedUserID
            ) else { return }
            let isDisplayingRequestedList =
                displayedListUserID == requestedUserID
                && displayedListFilter == requestedFilter
            if !forceRefresh || !isDisplayingRequestedList {
                listItems = []
                displayedListUserID = requestedUserID
                displayedListFilter = requestedFilter
            }
        }

        if !forceRefresh {
            hasCompletedListLoad = false
        }
        isLoadingList = listItems.isEmpty
        apiService.errorMessage = nil

        do {
            let items = try await apiService.fetchAllUserList(
                token: requestedToken,
                userID: requestedUserID,
                filter: requestedFilter,
                sort: requestedSortSelection.sort,
                isDescending: requestedSortSelection.isDescending,
                forceRefresh: forceRefresh
            )
            guard isCurrentListRequest(
                generation: generation,
                filter: requestedFilter,
                sortSelection: requestedSortSelection,
                token: requestedToken,
                userID: requestedUserID
            ) else { return }
            listItems = items
            displayedListUserID = requestedUserID
            displayedListFilter = requestedFilter
            apiService.prefetchRecentlyChanged(items)
            apiService.prefetchVisualNovelGraph(
                vnIDs: items.map(\.id)
            )
            apiService.errorMessage = nil
            didFinishRequest = true
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentListRequest(
                generation: generation,
                filter: requestedFilter,
                sortSelection: requestedSortSelection,
                token: requestedToken,
                userID: requestedUserID
            ) else { return }
            if error as? VNDB服务错误 == .token无效
                || (error as? URLError)?.code == .userAuthenticationRequired {
                apiService.errorMessage = String(
                    localized: "资料库请求未通过登录验证，请稍后再试。"
                )
            } else if listItems.isEmpty {
                apiService.errorMessage = String(localized: "无法获取游戏，请检查网络连接或稍后再试。")
            }
            didFinishRequest = true
        }
    }

    private var automaticListLoadID: 资料库自动加载标识 {
        资料库自动加载标识(
            filter: selectedFilter,
            sortSelection: selectedSort,
            token: auth.token,
            userID: auth.userID,
            isLoggedIn: auth.isLoggedIn,
            isRestoringSession: auth.isRestoringSession
        )
    }

    private func isCurrentListRequest(
        generation: Int,
        filter: 用户列表筛选,
        sortSelection: 资料库排序选择,
        token: String,
        userID: String
    ) -> Bool {
        generation == listLoadGeneration
            && filter == selectedFilter
            && sortSelection == selectedSort
            && token == auth.token
            && userID == auth.userID
            && auth.isLoggedIn
            && !auth.isRestoringSession
    }

    private var isShowingListPlaceholders: Bool {
        listItems.isEmpty
            && (auth.isRestoringSession
                || isLoadingList
                || !hasCompletedListLoad)
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
            titles: item.vn.titles,
            defaultTitle: item.vn.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
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
            listItems.removeAll { $0.id == item.id }
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
                        ? String(localized: "正在载入…")
                        : String(localized: "视觉小说标题"),
                    isJapanese: false,
                    层级: .主标题
                )
                    .lineLimit(1)

                多语言列表文本(
                    文本: "正在载入…",
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

    @AppStorage("preferredTitleLang") private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang") private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("subTitleLang") private var subTitleLang: 副标题语言 = .none
    @AppStorage("allowUnofficialTitles") private var allowUnofficialTitles = false
    @AppStorage("blurAverageRating") private var blurAverageRating = false
    @AppStorage("contentFilterEnabled") private var contentFilterEnabled = false
    @AppStorage("sexualThreshold") private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold") private var violenceThreshold: Double = 1
    @AppStorage("filterMode") private var filterMode: 内容过滤模式 = .both

    private var coverCornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        let mainTitle = 标题工具.获取主标题(
            titles: item.vn.titles,
            defaultTitle: item.vn.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
        let subtitle = 标题工具.获取副标题(
            titles: item.vn.titles,
            defaultTitle: item.vn.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            副标题设置: subTitleLang,
            允许非官方: allowUnofficialTitles
        )

        let coverNeedsRestriction = shouldRestrictCover
        let coverIsRestricted = coverNeedsRestriction && !isCoverRevealed

        HStack(spacing: 12) {
            ZStack {
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

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                多语言列表文本(
                    mainTitle,
                    层级: .主标题,
                    系统字体粗细: mainTitle.languageCode
                        == 标题语言.chinese.langCode ? .medium : nil
                )
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(.bottom, subtitle == nil ? 6 : 0)

                if let subtitle {
                    多语言列表文本(subtitle, 层级: .副标题)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if let status = item.primaryStatus {
                    statusBadge(status)
                }

                HStack(spacing: 列表行布局.元数据间距) {
                    if let released = item.vn.released {
                        compactMetadata(icon: "calendar", text: released)
                    }

                    if let vote = item.vote {
                        compactMetadata(
                            icon: "star",
                            text: String(format: "%.0f", Double(vote) / 10)
                        )
                    }

                    let ratingIsHidden =
                        blurAverageRating && item.vote == nil &&
                        !isAverageRatingRevealed
                    if ratingIsHidden {
                        Button(action: revealAverageRating) {
                            视觉小说统一评分标签(
                                vndbID: item.id,
                                vndbRating: item.vn.rating,
                                vndbVoteCount: item.vn.votecount
                            )
                            .blur(radius: 4)
                        }
                        .buttonStyle(.plain)
                    } else {
                        视觉小说统一评分标签(
                            vndbID: item.id,
                            vndbRating: item.vn.rating,
                            vndbVoteCount: item.vn.votecount
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
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

    private func statusBadge(_ status: 用户列表筛选) -> some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbolName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(Color.secondary.opacity(0.14), in: Circle())
                .overlay {
                    Circle()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                }
                .contentShape(Circle())

            Text(verbatim: status.localizedTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private func compactMetadata(icon: String, text: String) -> some View {
        HStack(spacing: 列表行布局.图标文字间距) {
            Image(systemName: icon)
                .font(.caption2)
            Text(verbatim: text)
        }
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
        .environmentObject(家长控制中心.shared)
}
