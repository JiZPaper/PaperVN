import Combine
import Foundation
import SwiftUI
import UIKit

// 制作人员与会社详情页面，以及其中的作品、发行版本列表。

struct 探索视觉小说编辑目标: Identifiable {
    let item: 探索视觉小说
    let currentItem: 用户列表项目
    let initialReleaseID: String?

    var id: String { item.id }
}

struct 探索视觉小说删除目标: Identifiable {
    let item: 探索视觉小说

    var id: String { item.id }
}

@MainActor
final class 探索作品资料库操作: ObservableObject {
    @Published private(set) var itemsByID: [String: 用户列表项目] = [:]
    @Published var editorTarget: 探索视觉小说编辑目标?
    @Published var deleteTarget: 探索视觉小说删除目标?
    @Published var errorMessage: String?
    @Published var isPerforming = false
    @Published var showLoginRequired = false
    /// 加入资料库后，同一系列里还没加入的作品。
    @Published var 系列补全结果: 系列补全.结果?

    private var loadedUserID: String?

    func load(auth: 用户登录) async {
        guard auth.可使用资料库 else {
            itemsByID = [:]
            loadedUserID = nil
            return
        }
        guard loadedUserID != auth.userID else { return }

        do {
            let items = try await VNDB服务.shared.fetchAllUserList(
                token: auth.token,
                userID: auth.userID
            )
            guard auth.userID == loadedUserID || loadedUserID == nil else {
                return
            }
            itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            loadedUserID = auth.userID
        } catch is CancellationError {
            return
        } catch {
        }
    }

    func actionTitle(for item: 探索视觉小说) -> String {
        itemsByID[item.id] == nil
            ? String(localized: "添加到资料库")
            : String(localized: "编辑")
    }

    func perform(
        item: 探索视觉小说,
        auth: 用户登录,
        bangumiAccount: Bangumi账户,
        selectedReleaseID: String? = nil
    ) {
        guard !isPerforming else { return }
        guard auth.可使用资料库 else {
            showLoginRequired = true
            return
        }

        isPerforming = true
        errorMessage = nil
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                let currentItem = try await resolveLibraryItem(
                    for: item.id,
                    auth: auth
                )
                if let currentItem {
                    itemsByID[item.id] = currentItem
                    editorTarget = 探索视觉小说编辑目标(
                        item: item,
                        currentItem: currentItem,
                        initialReleaseID: currentItem.releases?.first?.id == nil
                            ? selectedReleaseID
                            : nil
                    )
                    return
                }

                try await VNDB服务.shared.updateUserStatus(
                    token: auth.token,
                    vnID: item.id,
                    status: .planning,
                    existingLabels: []
                )
                if let selectedReleaseID {
                    try await VNDB服务.shared.updateReleaseSelection(
                        token: auth.token,
                        existingReleaseIDs: [],
                        selectedReleaseID: selectedReleaseID
                    )
                }
                资料库加入时间记录.record(userID: auth.userID, vnID: item.id)
                itemsByID[item.id] = provisionalLibraryItem(for: item)

                if PaperVNSync中心.已启用,
                   bangumiAccount.isLoggedIn {
                    try await bangumiAccount.synchronize(
                        vndbID: item.id,
                        status: .planning,
                        rating: nil
                    )
                }
                await refreshLibraryItem(for: item.id, auth: auth)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                return
            }
            isPerforming = false
            系列补全结果 = await 系列补全.检查(vnID: item.id)
        }
    }

    /// 在系列提醒里选中的作品加入资料库后，列表里的状态跟着更新。
    func 添加系列作品(_ works: [系列补全.作品], auth: 用户登录, bangumiAccount: Bangumi账户) async throws {
        try await 系列补全.添加视觉小说(works, auth: auth, bangumiAccount: bangumiAccount)
        for vnID in works.compactMap(\.vndbID) {
            await refreshLibraryItem(for: vnID, auth: auth)
        }
    }

    func requestDeletion(for item: 探索视觉小说, auth: 用户登录) {
        guard itemsByID[item.id] != nil else { return }
        guard auth.可使用资料库 else {
            showLoginRequired = true
            return
        }
        deleteTarget = 探索视觉小说删除目标(item: item)
    }

    func confirmDeletion(auth: 用户登录) {
        guard let target = deleteTarget else { return }
        guard !isPerforming else { return }
        guard auth.可使用资料库 else {
            deleteTarget = nil
            showLoginRequired = true
            return
        }

        deleteTarget = nil
        isPerforming = true
        errorMessage = nil
        Task { @MainActor in
            defer { isPerforming = false }
            do {
                try await VNDB服务.shared.deleteUserListEntry(
                    token: auth.token,
                    vnID: target.item.id
                )
                itemsByID.removeValue(forKey: target.item.id)
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshLibraryItem(for vnID: String, auth: 用户登录) async {
        guard auth.可使用资料库 else { return }
        do {
            let item = try await VNDB服务.shared.fetchUserListItem(
                token: auth.token,
                userID: auth.userID,
                vnID: vnID,
                forceRefresh: true
            )
            if let item {
                itemsByID[vnID] = item
            } else {
                itemsByID.removeValue(forKey: vnID)
            }
        } catch {
            return
        }
    }

    private func resolveLibraryItem(
        for vnID: String,
        auth: 用户登录
    ) async throws -> 用户列表项目? {
        if let cached = itemsByID[vnID] {
            return cached
        }
        if loadedUserID == auth.userID {
            return nil
        }
        return try await VNDB服务.shared.fetchUserListItem(
            token: auth.token,
            userID: auth.userID,
            vnID: vnID
        )
    }

    private func provisionalLibraryItem(
        for item: 探索视觉小说
    ) -> 用户列表项目 {
        let image = item.image.map {
            用户列表项目.用户列表详细信息.用户列表图片(
                url: $0.url,
                thumbnail: $0.thumbnail,
                sexual: $0.sexual,
                violence: $0.violence,
                dims: $0.dims
            )
        }
        return 用户列表项目(
            id: item.id,
            added: Int(Date.now.timeIntervalSince1970),
            vote: nil,
            started: nil,
            finished: nil,
            notes: nil,
            labels: [
                .init(
                    id: 用户列表筛选.planning.labelID ?? 5,
                    label: 用户列表筛选.planning.localizedString
                )
            ],
            releases: nil,
            vn: .init(
                title: item.title,
                titles: item.详情多语言标题,
                image: image,
                rating: item.rating,
                votecount: item.voteCount,
                released: item.released
            )
        )
    }
}

struct 探索视觉小说资料库操作Modifier: ViewModifier {
    let item: 探索视觉小说
    @ObservedObject var actions: 探索作品资料库操作
    let auth: 用户登录
    let bangumiAccount: Bangumi账户
    let parentalControls: 家长控制中心

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    actions.perform(
                        item: item,
                        auth: auth,
                        bangumiAccount: bangumiAccount
                    )
                } label: {
                    Label(
                        actions.actionTitle(for: item),
                        systemImage: actions.itemsByID[item.id] == nil
                            ? "plus"
                            : "square.and.pencil"
                    )
                }
                .tint(.blue)
                .disabled(actions.isPerforming)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if actions.itemsByID[item.id] != nil {
                    Button {
                        actions.requestDeletion(for: item, auth: auth)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .tint(.red)
                    .disabled(actions.isPerforming)
                }
            }
            .contextMenu {
                Button {
                    actions.perform(
                        item: item,
                        auth: auth,
                        bangumiAccount: bangumiAccount
                    )
                } label: {
                    Label(
                        actions.actionTitle(for: item),
                        systemImage: actions.itemsByID[item.id] == nil
                            ? "plus"
                            : "square.and.pencil"
                    )
                }
                .disabled(actions.isPerforming)

                if !parentalControls.policy.blocksUntrustedExternalLinks,
                   let url = URL(string: "https://vndb.org/\(item.id)") {
                    ShareLink(item: url) {
                        Label("共享", systemImage: "square.and.arrow.up")
                    }
                }

                if actions.itemsByID[item.id] != nil {
                    Divider()
                    Button(role: .destructive) {
                        actions.requestDeletion(for: item, auth: auth)
                    } label: {
                        Label("从资料库删除", systemImage: "trash")
                    }
                }
            }
            .accessibilityAction(named: Text(actions.actionTitle(for: item))) {
                actions.perform(
                    item: item,
                    auth: auth,
                    bangumiAccount: bangumiAccount
                )
            }
    }
}

extension View {
    func 探索视觉小说资料库操作(
        item: 探索视觉小说,
        actions: 探索作品资料库操作,
        auth: 用户登录,
        bangumiAccount: Bangumi账户,
        parentalControls: 家长控制中心
    ) -> some View {
        modifier(
            探索视觉小说资料库操作Modifier(
                item: item,
                actions: actions,
                auth: auth,
                bangumiAccount: bangumiAccount,
                parentalControls: parentalControls
            )
        )
    }
}

struct 探索发行版本列表操作Modifier: ViewModifier {
    let item: 探索发行版本
    @ObservedObject var actions: 探索作品资料库操作
    let auth: 用户登录
    let bangumiAccount: Bangumi账户
    let parentalControls: 家长控制中心

    private var works: [探索视觉小说] {
        (item.visualNovels ?? []).map(探索视觉小说.init(发行作品:))
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if let work = works.first {
                    Button {
                        actions.perform(
                            item: work,
                            auth: auth,
                            bangumiAccount: bangumiAccount,
                            selectedReleaseID: item.id
                        )
                    } label: {
                        Label(
                            actions.actionTitle(for: work),
                            systemImage: actions.itemsByID[work.id] == nil
                                ? "plus"
                                : "square.and.pencil"
                        )
                    }
                    .tint(.blue)
                    .disabled(actions.isPerforming)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let work = works.first,
                   actions.itemsByID[work.id] != nil {
                    Button {
                        actions.requestDeletion(for: work, auth: auth)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .tint(.red)
                    .disabled(actions.isPerforming)
                }
            }
            .contextMenu {
                if !parentalControls.policy.blocksUntrustedExternalLinks,
                   let url = URL(string: "https://vndb.org/\(item.id)") {
                    ShareLink(item: url) {
                        Label("共享", systemImage: "square.and.arrow.up")
                    }
                }

                if !works.isEmpty {
                    Divider()
                    if works.count == 1, let work = works.first {
                        libraryActionButton(for: work)
                    } else {
                        Menu {
                            ForEach(works) { work in
                                libraryActionButton(
                                    for: work,
                                    selectedReleaseID: item.id
                                )
                            }
                        } label: {
                            Label("添加到资料库", systemImage: "plus")
                        }
                    }

                    if let work = works.first,
                       actions.itemsByID[work.id] != nil {
                        Button(role: .destructive) {
                            actions.requestDeletion(for: work, auth: auth)
                        } label: {
                            Label("从资料库删除", systemImage: "trash")
                        }
                    }
                }
            }
    }

    private func libraryActionButton(
        for work: 探索视觉小说,
        selectedReleaseID: String? = nil
    ) -> some View {
        Button {
            actions.perform(
                item: work,
                auth: auth,
                bangumiAccount: bangumiAccount,
                selectedReleaseID: selectedReleaseID ?? item.id
            )
        } label: {
            Label(
                actions.actionTitle(for: work),
                systemImage: actions.itemsByID[work.id] == nil
                    ? "plus"
                    : "square.and.pencil"
            )
        }
        .disabled(actions.isPerforming)
    }
}

extension View {
    func 探索发行版本列表操作(
        item: 探索发行版本,
        actions: 探索作品资料库操作,
        auth: 用户登录,
        bangumiAccount: Bangumi账户,
        parentalControls: 家长控制中心
    ) -> some View {
        modifier(
            探索发行版本列表操作Modifier(
                item: item,
                actions: actions,
                auth: auth,
                bangumiAccount: bangumiAccount,
                parentalControls: parentalControls
            )
        )
    }
}

struct 探索内联视觉小说列表: View {
    @ObservedObject var viewModel: 探索分页视图模型
    var emptyTitle: LocalizedStringKey = "无相关作品"
    var sectionTitle: String? = nil

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @作品列表标题偏好读取 private var 标题偏好

    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var bangumiAccount: Bangumi账户
    @EnvironmentObject private var parentalControls: 家长控制中心
    @StateObject private var confirmation = 模糊解除确认器()
    @StateObject private var libraryActions = 探索作品资料库操作()
    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("contentFilterEnabled")
    private var contentFilterEnabled = false
    @AppStorage("sexualThreshold")
    private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold")
    private var violenceThreshold: Double = 1
    @AppStorage("filterMode")
    private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var contentRestrictionMethod: 内容限制方式 = .blurred

    var body: some View {
        Group {
            if visibleItems.isEmpty,
               viewModel.initialLoadState != .finished {
                Section {
                    loadingRows
                } header: {
                    探索加载中标题()
                }
            } else if visibleItems.isEmpty,
                      let error = viewModel.errorMessage {
                Section {
                    探索加载失败页面(message: error) {
                        Task {
                            await viewModel.loadFirstPage(forceRefresh: true)
                        }
                    }
                }
            } else if visibleItems.isEmpty, !viewModel.hasMore {
                Section {
                    平台内容不可用视图(emptyTitle, systemImage: "zipper.page")
                }
            } else {
                if let error = viewModel.errorMessage {
                    Section {
                        探索加载失败页面(message: error) {
                            Task {
                                await viewModel.loadFirstPage(forceRefresh: true)
                            }
                        }
                    }
                }

                loadedSection {
                    ForEach(
                        Array(visibleItems.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        NavigationLink {
                            视觉小说详情(
                                vnID: item.id,
                                auth: auth,
                                initialTitle: item.title,
                                initialTitles: item.详情多语言标题,
                                initialImageURL: item.image?.url,
                                initialImageSexual: item.image?.sexual,
                                initialImageViolence: item.image?.violence,
                                initialImageDimensions: item.image?.dims
                            )
                        } label: {
                            作品列表行(
                                场景: .search,
                                内容: 作品列表行内容(item, 标题: 标题偏好)
                            ) {
                                探索安全图片(
                                    id: "list-vn-\(item.id)",
                                    url: item.image?.url ?? item.image?.thumbnail,
                                    sexual: item.image?.sexual,
                                    violence: item.image?.violence,
                                    width: 列表封面布局.宽度,
                                    height: 列表封面布局.高度,
                                    confirmation: confirmation,
                                    cornerRadius: 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass),
                                    showsBorder: false
                                )
                            }
                        }
                        .onAppear {
                            guard viewModel.hasMore,
                                  index >= max(
                                visibleItems.count - 平台列表分页.预取余量,
                                0
                            ) else { return }
                            Task { await viewModel.loadNextPage() }
                        }
                        .探索视觉小说资料库操作(
                            item: item,
                            actions: libraryActions,
                            auth: auth,
                            bangumiAccount: bangumiAccount,
                            parentalControls: parentalControls
                        )
                    }
                }

                paginationFooter
            }
        }
        .task(id: auth.userID) {
            await libraryActions.load(auth: auth)
        }
        .sheet(item: $libraryActions.editorTarget) { target in
            资料库编辑页面(
                vnID: target.item.id,
                title: titleResult(for: target.item),
                token: auth.token,
                currentItem: target.currentItem,
                releases: [],
                loadsReleasesOnAppear: true,
                initialReleaseID: target.initialReleaseID
            ) {
                await libraryActions.refreshLibraryItem(
                    for: target.item.id,
                    auth: auth
                )
            }
            .平台近全屏弹窗(dragIndicator: .visible)
        }
        .alert(item: $libraryActions.deleteTarget) { target in
            Alert(
                title: Text("从资料库删除"),
                message: Text(verbatim: String(
                    format: String(localized: "要从资料库删除“%@”吗？"),
                    titleResult(for: target.item).text
                )),
                primaryButton: .destructive(Text("从资料库删除")) {
                    libraryActions.confirmDeletion(auth: auth)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(
            "需要登录",
            isPresented: Binding(
                get: { libraryActions.showLoginRequired },
                set: { libraryActions.showLoginRequired = $0 }
            )
        ) {
            Button("好") { libraryActions.showLoginRequired = false }
        } message: {
            Text("请先在“账户”中登录Paper账户或任意平台账户。")
        }
        .alert(
            "无法完成资料库操作",
            isPresented: Binding(
                get: { libraryActions.errorMessage != nil },
                set: { if !$0 { libraryActions.errorMessage = nil } }
            )
        ) {
            Button("好") { libraryActions.errorMessage = nil }
        } message: {
            Text(verbatim: libraryActions.errorMessage ?? "")
        }
        .系列补全提醒($libraryActions.系列补全结果) { works in
            try await libraryActions.添加系列作品(works, auth: auth, bangumiAccount: bangumiAccount)
        }
    }

    private func titleResult(
        for item: 探索视觉小说
    ) -> 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: item.详情多语言标题,
            defaultTitle: item.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    private var visibleItems: [探索视觉小说] {
        guard contentRestrictionMethod == .hidden else {
            return viewModel.visualNovels
        }
        return viewModel.visualNovels.filter { item in
            !内容安全限制判定.图片需要限制(
                sexual: item.image?.sexual,
                violence: item.image?.violence,
                enabled: contentFilterEnabled,
                sexualThreshold: sexualThreshold,
                violenceThreshold: violenceThreshold,
                mode: filterMode
            ) && !内容安全限制判定.色情标签需要限制(
                item.tags?.contains(where: { $0.category == "ero" }) == true,
                enabled: contentFilterEnabled,
                mode: filterMode
            )
        }
    }

    private var loadingRows: some View {
        ForEach(0..<4, id: \.self) { index in
            探索视觉小说加载占位行(index: index)
        }
    }

    @ViewBuilder
    private func loadedSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let sectionTitle {
            Section {
                content()
            } header: {
                Text(verbatim: sectionTitle)
            }
        } else {
            Section {
                content()
            }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.isLoadingMore {
            Section {
                ForEach(0..<2, id: \.self) { index in
                    探索视觉小说加载占位行(index: index)
                }
                .accessibilityHidden(true)
            } header: {
                探索加载中标题()
                    .id("inline-vn-pagination-\(viewModel.paginationGeneration)")
            }
            .id("inline-vn-pagination-section-\(viewModel.paginationGeneration)")
        } else if let error = viewModel.nextPageError {
            Section {
                探索加载失败页面(message: error) {
                    Task { await viewModel.loadNextPage() }
                }
            }
        } else if visibleItems.isEmpty, viewModel.hasMore {
            Section {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await viewModel.loadNextPage() }
                    }
                    .accessibilityHidden(true)
                }
        }
    }
}

struct 探索内联发行版本列表: View {
    @ObservedObject var viewModel: 探索分页视图模型
    var sectionTitle: String? = nil

    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var bangumiAccount: Bangumi账户
    @EnvironmentObject private var parentalControls: 家长控制中心
    @StateObject private var confirmation = 模糊解除确认器()
    @StateObject private var libraryActions = 探索作品资料库操作()
    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("contentFilterEnabled")
    private var contentFilterEnabled = false
    @AppStorage("sexualThreshold")
    private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold")
    private var violenceThreshold: Double = 1
    @AppStorage("filterMode")
    private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var contentRestrictionMethod: 内容限制方式 = .blurred

    var body: some View {
        Group {
            if visibleItems.isEmpty,
               viewModel.initialLoadState != .finished {
                Section {
                    ForEach(0..<4, id: \.self) { index in
                        探索发行版本加载占位行(index: index)
                    }
                    .accessibilityHidden(true)
                } header: {
                    探索加载中标题()
                }
            } else if visibleItems.isEmpty,
                      let error = viewModel.errorMessage {
                Section {
                    探索加载失败页面(message: error) {
                        Task {
                            await viewModel.loadFirstPage(forceRefresh: true)
                        }
                    }
                }
            } else if visibleItems.isEmpty, !viewModel.hasMore {
                Section {
                    平台内容不可用视图(
                        "无发行版本",
                        systemImage: "shippingbox"
                    )
                }
            } else {
                loadedSection {
                    ForEach(
                        Array(visibleItems.enumerated()),
                        id: \.element.id
                    ) { index, item in
                        NavigationLink {
                            发行版本详情(item: item, auth: auth)
                        } label: {
                            探索发行版本行(
                                item: item,
                                confirmation: confirmation
                            )
                        }
                        .onAppear {
                            guard viewModel.hasMore,
                                  index >= max(
                                visibleItems.count - 平台列表分页.预取余量,
                                0
                            ) else { return }
                            Task { await viewModel.loadNextPage() }
                        }
                        .探索发行版本列表操作(
                            item: item,
                            actions: libraryActions,
                            auth: auth,
                            bangumiAccount: bangumiAccount,
                            parentalControls: parentalControls
                        )
                    }
                }

                paginationFooter
            }
        }
        .task(id: auth.userID) {
            await libraryActions.load(auth: auth)
        }
        .sheet(item: $libraryActions.editorTarget) { target in
            资料库编辑页面(
                vnID: target.item.id,
                title: releaseWorkTitleResult(for: target.item),
                token: auth.token,
                currentItem: target.currentItem,
                releases: [],
                loadsReleasesOnAppear: true,
                initialReleaseID: target.initialReleaseID
            ) {
                await libraryActions.refreshLibraryItem(
                    for: target.item.id,
                    auth: auth
                )
            }
            .平台近全屏弹窗(dragIndicator: .visible)
        }
        .alert(item: $libraryActions.deleteTarget) { target in
            Alert(
                title: Text("从资料库删除"),
                message: Text(verbatim: String(
                    format: String(localized: "要从资料库删除“%@”吗？"),
                    releaseWorkTitleResult(for: target.item).text
                )),
                primaryButton: .destructive(Text("从资料库删除")) {
                    libraryActions.confirmDeletion(auth: auth)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .alert(
            "需要登录",
            isPresented: Binding(
                get: { libraryActions.showLoginRequired },
                set: { libraryActions.showLoginRequired = $0 }
            )
        ) {
            Button("好") { libraryActions.showLoginRequired = false }
        } message: {
            Text("请先在“账户”中登录Paper账户或任意平台账户。")
        }
        .alert(
            "无法完成资料库操作",
            isPresented: Binding(
                get: { libraryActions.errorMessage != nil },
                set: { if !$0 { libraryActions.errorMessage = nil } }
            )
        ) {
            Button("好") { libraryActions.errorMessage = nil }
        } message: {
            Text(verbatim: libraryActions.errorMessage ?? "")
        }
        .系列补全提醒($libraryActions.系列补全结果) { works in
            try await libraryActions.添加系列作品(works, auth: auth, bangumiAccount: bangumiAccount)
        }
    }

    private func releaseWorkTitleResult(
        for item: 探索视觉小说
    ) -> 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: item.详情多语言标题,
            defaultTitle: item.title,
            偏好: .original,
            回退: .original,
            允许非官方: false
        )
    }

    @ViewBuilder
    private func loadedSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let sectionTitle {
            Section {
                content()
            } header: {
                Text(verbatim: sectionTitle)
            }
        } else {
            Section {
                content()
            }
        }
    }

    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.isLoadingMore {
            Section {
                ForEach(0..<2, id: \.self) { index in
                    探索发行版本加载占位行(index: index)
                }
                .accessibilityHidden(true)
            } header: {
                探索加载中标题()
                    .id("inline-release-pagination-\(viewModel.paginationGeneration)")
            }
            .id("inline-release-pagination-section-\(viewModel.paginationGeneration)")
        } else if let error = viewModel.nextPageError {
            Section {
                探索加载失败页面(message: error) {
                    Task { await viewModel.loadNextPage() }
                }
            }
        } else if visibleItems.isEmpty, viewModel.hasMore {
            Section {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        Task { await viewModel.loadNextPage() }
                    }
                    .accessibilityHidden(true)
            }
        }
    }

    private var visibleItems: [探索发行版本] {
        guard contentRestrictionMethod == .hidden else {
            return viewModel.releases
        }
        return viewModel.releases.filter { item in
            let cover = item.images?.first
            return !内容安全限制判定.图片需要限制(
                sexual: cover?.sexual
                    ?? item.visualNovels?.first?.image?.sexual,
                violence: cover?.violence
                    ?? item.visualNovels?.first?.image?.violence,
                enabled: contentFilterEnabled,
                sexualThreshold: sexualThreshold,
                violenceThreshold: violenceThreshold,
                mode: filterMode
            )
        }
    }
}

struct 探索发行版本信息项: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let value: String?
    let icon: String
}

struct 制作人员详情: View {
    let item: 探索制作人员

    @StateObject private var worksViewModel: 探索分页视图模型

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var immersiveDetailAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }

    init(item: 探索制作人员) {
        self.item = item
        _worksViewModel = StateObject(
            wrappedValue: 探索分页视图模型(
                source: .visualNovel(.staff(id: item.id, name: item.name))
            )
        )
    }

    var body: some View {
        平台滚动页面 {
            if let description = item.description, !description.isEmpty {
                Section("简介") {
                    Text(verbatim: description)
                        .textSelection(.enabled)
                }
            }

            探索内联视觉小说列表(
                viewModel: worksViewModel,
                sectionTitle: String(localized: "参与作品")
            )
        }
        .探索列表样式(隐藏背景: true)
        .探索详情液态玻璃背景(
            immersiveDetailAppearance,
            fallbackTint: immersiveSystemGlassTint,
            backgroundColor: Color.平台分组背景
        )
        .navigationTitle(displayName)
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .task(id: item.id) {
            await worksViewModel.loadFirstPage()
        }
        .refreshable {
            await worksViewModel.loadFirstPage(forceRefresh: true)
        }
    }

    private var displayName: String {
        人物名称工具.显示名称(
            name: item.name,
            original: item.original,
            偏好: staffNameLang
        )
    }

    private var immersiveSystemGlassTint: Color? {
        guard immersiveDetailAppearance == .clear else { return nil }
        return colorScheme == .dark ? .black : .white
    }
}

enum 会社详情列表类型: String, CaseIterable, Identifiable {
    case works
    case releases

    var id: String { rawValue }

    var title: String {
        switch self {
        case .works: return String(localized: "开发或发行作品")
        case .releases: return String(localized: "发行版本")
        }
    }
}

struct 会社详情: View {
    let item: 探索会社

    @StateObject private var worksViewModel: 探索分页视图模型
    @StateObject private var releasesViewModel: 探索分页视图模型
    @State private var selectedList: 会社详情列表类型 = .works

    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var immersiveDetailAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }

    init(item: 探索会社) {
        self.item = item
        _worksViewModel = StateObject(
            wrappedValue: 探索分页视图模型(
                source: .visualNovel(.producer(id: item.id, name: item.name))
            )
        )
        _releasesViewModel = StateObject(
            wrappedValue: 探索分页视图模型(
                source: .release(.producer(id: item.id, name: item.name))
            )
        )
    }

    var body: some View {
        平台滚动页面 {
            if let description = item.description, !description.isEmpty {
                Section("简介") {
                    Text(verbatim: description)
                        .textSelection(.enabled)
                }
            }

            if selectedList == .works {
                探索内联视觉小说列表(viewModel: worksViewModel)
            } else {
                探索内联发行版本列表(viewModel: releasesViewModel)
            }
        }
        .探索列表样式(隐藏背景: true)
        .探索详情液态玻璃背景(
            immersiveDetailAppearance,
            fallbackTint: immersiveSystemGlassTint,
            backgroundColor: Color.平台分组背景
        )
        .navigationTitle(displayName)
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .平台安全区域栏(edge: .top, spacing: 0) {
            Picker("列表", selection: $selectedList) {
                ForEach(会社详情列表类型.allCases) { list in
                    Text(verbatim: list.title)
                        .tag(list)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .task(id: "\(item.id)-\(selectedList.rawValue)") {
            await loadSelectedList()
        }
        .refreshable {
            await loadSelectedList(forceRefresh: true)
        }
    }

    @MainActor
    private func loadSelectedList(forceRefresh: Bool = false) async {
        switch selectedList {
        case .works:
            guard forceRefresh || worksViewModel.initialLoadState == .idle else {
                return
            }
            await worksViewModel.loadFirstPage(forceRefresh: forceRefresh)
        case .releases:
            guard forceRefresh || releasesViewModel.initialLoadState == .idle else {
                return
            }
            await releasesViewModel.loadFirstPage(forceRefresh: forceRefresh)
        }
    }

    private var displayName: String {
        人物名称工具.显示名称(
            name: item.name,
            original: item.original,
            偏好: staffNameLang
        )
    }

    private var immersiveSystemGlassTint: Color? {
        guard immersiveDetailAppearance == .clear else { return nil }
        return colorScheme == .dark ? .black : .white
    }

}
