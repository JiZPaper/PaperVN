import Combine
import Foundation
import SwiftUI
import UIKit

private enum 探索发行版本沉浸取样框PreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private extension View {
    func 发行版本沉浸取样框(_ keys: [String]) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("ReleaseImmersiveDetailSampling"))
                if 探索发行版本沉浸取样框有效(frame) {
                    Color.clear.preference(
                        key: 探索发行版本沉浸取样框PreferenceKey.self,
                        value: Dictionary(uniqueKeysWithValues: keys.map { ($0, frame) })
                    )
                } else {
                    Color.clear
                }
            }
        }
    }

    @ViewBuilder
    func 发行版本沉浸取样框(_ frames: [String: CGRect]) -> some View {
        if frames.values.allSatisfy(探索发行版本沉浸取样框有效) {
            preference(
                key: 探索发行版本沉浸取样框PreferenceKey.self,
                value: frames
            )
        } else {
            self
        }
    }
}

private func 探索发行版本沉浸取样框有效(_ frame: CGRect) -> Bool {
    frame.minX.isFinite
        && frame.minY.isFinite
        && frame.width.isFinite
        && frame.height.isFinite
        && frame.width > 0
        && frame.height > 0
}

private extension View {
    @ViewBuilder
    func 探索列表样式(隐藏背景: Bool = false) -> some View {
        if 隐藏背景 {
            平台分组列表样式()
                .scrollContentBackground(.hidden)
        } else {
            平台分组列表样式()
                .scrollContentBackground(.visible)
        }
    }

}

private struct 探索详情液态玻璃背景Modifier: ViewModifier {
    let appearance: 沉浸详情外观
    let hasImage: Bool
    let fallbackTint: Color?
    let backgroundColor: Color

    func body(content: Content) -> some View {
        let tint = appearance == .clear && !hasImage
            ? fallbackTint
            : nil

        content
            .scrollContentBackground(.hidden)
            .background(backgroundColor.ignoresSafeArea())
            .background {
                Rectangle()
                    .fill(.clear)
                    .液态玻璃(
                        appearance.glass(tint: tint),
                        in: Rectangle()
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
    }
}

private extension View {
    func 探索详情液态玻璃背景(
        _ appearance: 沉浸详情外观,
        hasImage: Bool = false,
        fallbackTint: Color?,
        backgroundColor: Color = .平台系统背景
    ) -> some View {
        modifier(
            探索详情液态玻璃背景Modifier(
                appearance: appearance,
                hasImage: hasImage,
                fallbackTint: fallbackTint,
                backgroundColor: backgroundColor
            )
        )
    }
}

struct 探索安全图片: View {
    let id: String
    let url: String?
    let sexual: Double?
    let violence: Double?
    let width: CGFloat
    let height: CGFloat
    let confirmation: 模糊解除确认器
    var cornerRadius: CGFloat = 22
    var showsBorder = true
    var allowsReveal = false

    @State private var isRevealed = false

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

    private var isRestricted: Bool {
        shouldRestrict && (
            contentRestrictionMethod == .hidden || !isRevealed
        )
    }

    var body: some View {
        ZStack {
            CachedAsyncImage(url: URL(string: url ?? ""), contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .应用不安全内容限制(
                    isRestricted,
                    method: contentRestrictionMethod,
                    blurRadius: 16
                )

            if url == nil || URL(string: url ?? "") == nil {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }

            if isRestricted,
               contentRestrictionMethod == .blurred,
               allowsReveal,
               canRevealRestriction {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        confirmation.request(id: id) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                isRevealed = true
                            }
                        }
                    }
                    .accessibilityLabel("连按两次以解除模糊")
            }
        }
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.1))
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
        .overlay {
            if showsBorder {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
            }
        }
        .accessibilityHidden(url == nil)
    }

    private var shouldRestrict: Bool {
        内容安全限制判定.图片需要限制(
            sexual: sexual,
            violence: violence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
    }

    private var canRevealRestriction: Bool {
        内容安全限制判定.图片允许手动解除模糊(
            sexual: sexual,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            mode: filterMode
        )
    }
}

struct 探索元数据: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(verbatim: text)
                .lineLimit(1)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct 探索视觉小说列表行: View {
    let item: 探索视觉小说
    let confirmation: 模糊解除确认器

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("subTitleLang")
    private var subTitleLang: 副标题语言 = .none
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji

    var body: some View {
        let main = 标题工具.获取主标题(
            titles: item.详情多语言标题,
            defaultTitle: item.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
        let subtitle = 标题工具.获取副标题(
            titles: item.详情多语言标题,
            defaultTitle: item.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            副标题设置: subTitleLang,
            允许非官方: allowUnofficialTitles
        )

        HStack(alignment: .top, spacing: 12) {
            探索安全图片(
                id: "list-vn-\(item.id)",
                url: item.image?.url ?? item.image?.thumbnail,
                sexual: item.image?.sexual,
                violence: item.image?.violence,
                width: 72,
                height: 100,
                confirmation: confirmation,
                cornerRadius: coverCornerRadius,
                showsBorder: false
            )

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                多语言列表文本(main, 层级: .主标题)
                .lineLimit(1)
                .truncationMode(.tail)

                if let subtitle {
                    多语言列表文本(subtitle, 层级: .副标题)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if let developers = item.developers, !developers.isEmpty {
                    let names = ListFormatter.localizedString(byJoining:
                        developers.prefix(2).map {
                            人物名称工具.显示名称(
                                name: $0.name,
                                original: $0.original,
                                偏好: staffNameLang
                            )
                        }
                    )
                    Text(
                        标题工具.生成富文本(
                            文本: names,
                            isJapanese: staffNameLang == .original,
                            基础大小: 12,
                            日文字体名称: "HiraginoSans-W4",
                            语言来源已知: false,
                            空格视为日语: true
                        )
                    )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    视觉小说统一评分标签(
                        vndbID: item.id,
                        vndbRating: item.rating,
                        vndbVoteCount: item.voteCount
                    )
                    if 评分数据来源.current == .vndb,
                       let votes = item.voteCount {
                        探索元数据(systemImage: "person.2", text: votes.formatted())
                    }
                    if let released = item.released {
                        探索元数据(systemImage: "calendar", text: released)
                    }
                }

                let availability = availabilityText
                if !availability.isEmpty {
                    Text(verbatim: availability)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var coverCornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }

    private var availabilityText: String {
        let languages = ListFormatter.localizedString(byJoining:
            (item.languages ?? []).prefix(3)
            .map { VNDB显示工具.语言名称($0) }
        )
        let platforms = ListFormatter.localizedString(byJoining:
            (item.platforms ?? []).prefix(2)
            .map { VNDB显示工具.平台名称($0) }
        )
        return [languages, platforms]
            .filter { !$0.isEmpty }
            .joined(separator: "·")
    }
}

struct 探索发行版本行: View {
    let item: 探索发行版本
    let confirmation: 模糊解除确认器
    var verticalAlignment: VerticalAlignment = .top

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji

    private var cover: 探索发行图片? {
        item.images?.first {
            $0.url != nil || $0.thumbnail != nil
        }
    }

    var body: some View {
        HStack(alignment: verticalAlignment, spacing: 12) {
            探索安全图片(
                id: "release-\(item.id)",
                url: cover?.url
                    ?? cover?.thumbnail
                    ?? item.visualNovels?.first?.image?.url
                    ?? item.visualNovels?.first?.image?.thumbnail,
                sexual: cover?.sexual ?? item.visualNovels?.first?.image?.sexual,
                violence: cover?.violence ?? item.visualNovels?.first?.image?.violence,
                width: 72,
                height: 100,
                confirmation: confirmation,
                cornerRadius: coverCornerRadius
            )

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                多语言列表文本(
                    文本: displayedTitle,
                    isJapanese: staffNameLang == .original,
                    层级: .主标题,
                    语言来源已知: false,
                    空格视为日语: true
                )
                    .lineLimit(2)

                if let alternateTitle {
                    多语言列表文本(
                        文本: alternateTitle,
                        isJapanese: staffNameLang != .original,
                        层级: .副标题,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let released = item.released {
                        探索元数据(systemImage: "calendar", text: released)
                    }
                    if item.freeware == true {
                        探索元数据(systemImage: "gift", text: String(localized: "免费"))
                    }
                    if item.official == true {
                        探索元数据(systemImage: "checkmark.seal", text: String(localized: "官方"))
                    }
                }

                let languages = ListFormatter.localizedString(byJoining:
                    (item.languages ?? []).prefix(3).map {
                        VNDB显示工具.语言名称($0.lang)
                    }
                )
                let platforms = ListFormatter.localizedString(byJoining:
                    (item.platforms ?? []).prefix(2).map {
                        VNDB显示工具.平台名称($0)
                    }
                )
                let availability = [languages, platforms]
                    .filter { !$0.isEmpty }
                    .joined(separator: "·")
                if !availability.isEmpty {
                    Text(verbatim: availability)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var coverCornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }

    private var displayedTitle: String {
        人物名称工具.显示名称(
            name: item.title,
            original: item.alttitle,
            偏好: staffNameLang
        )
    }

    private var alternateTitle: String? {
        人物名称工具.备用名称(
            name: item.title,
            original: item.alttitle,
            偏好: staffNameLang
        )
    }
}

private func 探索人物名称富文本(
    _ text: String,
    language: 制作人员语言,
    size: CGFloat
) -> AttributedString {
    标题工具.生成富文本(
        文本: text,
        isJapanese: language == .original,
        基础大小: size,
        日文字体名称: "HiraginoSans-W4",
        语言来源已知: false,
        空格视为日语: true
    )
}

private func 探索占位线(
    width: CGFloat,
    height: CGFloat,
    opacity: Double = 0.1
) -> some View {
    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        .fill(Color.secondary.opacity(opacity))
        .frame(width: width, height: height)
}

private struct 探索加载中标题: View {
    var body: some View {
        HStack(spacing: 8) {
            平台持续加载指示器()
            Text("正在载入…")
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

private func 探索自动重试<T>(
    operation: () async throws -> T
) async throws -> T {
    let maximumRetries = 3
    var lastError: Error = URLError(.unknown)

    for retryCount in 0...maximumRetries {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error
            guard retryCount < maximumRetries else { break }
            try await Task.sleep(
                nanoseconds: UInt64(retryCount + 1) * 300_000_000
            )
        }
    }
    throw lastError
}

private struct 探索视觉小说加载占位行: View {
    let index: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var coverCornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 72, height: 100)

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                探索占位线(width: index.isMultiple(of: 2) ? 188 : 158, height: 16, opacity: 0.14)
                探索占位线(width: 132, height: 12)
                探索占位线(width: 156, height: 10, opacity: 0.08)
                探索占位线(width: 122, height: 10, opacity: 0.08)
                探索占位线(width: 168, height: 10, opacity: 0.06)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct 探索发行版本加载占位行: View {
    let index: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: coverCornerRadius, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 72, height: 100)

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                探索占位线(width: index.isMultiple(of: 2) ? 188 : 164, height: 16, opacity: 0.14)
                探索占位线(width: 132, height: 12, opacity: 0.1)
                探索占位线(width: 116, height: 10, opacity: 0.08)
                探索占位线(width: 150, height: 10, opacity: 0.08)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var coverCornerRadius: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
    }
}

enum 探索首次加载状态: Equatable {
    case idle
    case loading
    case finished
}

struct 探索加载失败提示: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(verbatim: message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if let retry {
                探索重试按钮(action: retry)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct 探索重试按钮: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("重试")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 88, minHeight: 44)
                .background(Color.blue, in: Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel("重试")
    }
}

struct 探索加载失败页面: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        平台内容不可用视图 {
            Label("无法载入", systemImage: "wifi.exclamationmark")
        } description: {
            Text(verbatim: message)
        } actions: {
            探索重试按钮(action: retry)
        }
    }
}

struct 探索特征目录分组: Identifiable {
    let id: String
    let title: String
    let traits: [探索特征]
}

func 生成探索特征目录分组(
    _ traits: [探索特征],
    localizedText: (String) -> String
) -> [探索特征目录分组] {
    Dictionary(grouping: traits) {
        $0.groupID ?? $0.groupName ?? "other"
    }
    .map { id, traits in
        let sourceName = traits.first?.groupName ?? String(localized: "其他")
        return 探索特征目录分组(
            id: id,
            title: localizedText(sourceName),
            traits: traits
        )
    }
    .sorted { lhs, rhs in
        let titleOrder = lhs.title.localizedStandardCompare(rhs.title)
        if titleOrder != .orderedSame {
            return titleOrder == .orderedAscending
        }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }
}

private struct 探索视觉小说编辑目标: Identifiable {
    let item: 探索视觉小说
    let currentItem: 用户列表项目
    let initialReleaseID: String?

    var id: String { item.id }
}

private struct 探索视觉小说删除目标: Identifiable {
    let item: 探索视觉小说

    var id: String { item.id }
}

@MainActor
private final class 探索作品资料库操作: ObservableObject {
    @Published private(set) var itemsByID: [String: 用户列表项目] = [:]
    @Published var editorTarget: 探索视觉小说编辑目标?
    @Published var deleteTarget: 探索视觉小说删除目标?
    @Published var errorMessage: String?
    @Published var isPerforming = false
    @Published var showLoginRequired = false

    private var loadedUserID: String?

    func load(auth: 用户登录) async {
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
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
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
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

                if UserDefaults.standard.bool(forKey: Bangumi账户.同步设置键),
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
            }
        }
    }

    func requestDeletion(for item: 探索视觉小说, auth: 用户登录) {
        guard itemsByID[item.id] != nil else { return }
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
            showLoginRequired = true
            return
        }
        deleteTarget = 探索视觉小说删除目标(item: item)
    }

    func confirmDeletion(auth: 用户登录) {
        guard let target = deleteTarget else { return }
        guard !isPerforming else { return }
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
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
        guard !auth.token.isEmpty, !auth.userID.isEmpty else { return }
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

private struct 探索视觉小说资料库操作Modifier: ViewModifier {
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
                    Button(role: .destructive) {
                        actions.requestDeletion(for: item, auth: auth)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
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

private extension View {
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

private struct 探索发行版本列表操作Modifier: ViewModifier {
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
                    Button(role: .destructive) {
                        actions.requestDeletion(for: work, auth: auth)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
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

private extension View {
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

private extension 探索视觉小说 {
    init(发行作品 work: 探索发行作品) {
        self.init(
            id: work.id,
            title: work.title,
            alttitle: nil,
            titles: work.titles,
            aliases: nil,
            released: nil,
            languages: nil,
            platforms: nil,
            image: work.image,
            length: nil,
            lengthMinutes: nil,
            rating: nil,
            voteCount: nil,
            tags: nil,
            developers: nil,
            relations: nil
        )
    }
}

private struct 探索内联视觉小说列表: View {
    @ObservedObject var viewModel: 探索分页视图模型
    var emptyTitle: LocalizedStringKey = "无相关作品"
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
                    平台内容不可用视图(emptyTitle, systemImage: "books.vertical")
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
                            探索视觉小说列表行(
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
            Text("请先在资料库页面登录VNDB账户。")
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

private struct 探索内联发行版本列表: View {
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
                            探索发行版本详情(item: item, auth: auth)
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
            Text("请先在资料库页面登录VNDB账户。")
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

private struct 探索发行版本信息项: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let value: String?
    let icon: String
}

struct 探索发行版本详情: View {
    let item: 探索发行版本
    let openedFromVisualNovelDetail: Bool

    @ObservedObject var auth: 用户登录
    @StateObject private var confirmation = 模糊解除确认器()
    @State private var detailedItem: 探索发行版本?
    @State private var browserURL: URL?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.详情内容限制方式覆盖)
    private var contentRestrictionMethodOverride
    @AppStorage("contentFilterEnabled")
    private var contentFilterEnabled = false
    @AppStorage("sexualThreshold")
    private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold")
    private var violenceThreshold: Double = 1
    @AppStorage("filterMode")
    private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var storedContentRestrictionMethod: 内容限制方式 = .blurred
    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var immersiveDetailAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }
    @State private var revealHeroImage = false
    @State private var immersiveHeroGestureIsActive = false
    @State private var immersiveViewportSize: CGSize = .zero
    @State private var immersiveTextSamples: [String: 沉浸玻璃文字取样结果] = [:]
    @State private var immersiveTextSampleURL: URL?
    @State private var immersiveTextRevealURL: URL?
    @State private var immersiveTextSampleGeometry: 沉浸封面文字取样几何?
    @State private var immersiveTextSamplingCoordinator = 沉浸封面文字取样任务协调器()
    @State private var immersiveLoadedHeroImage: Image?
    @State private var immersiveLoadedHeroImageURL: URL?
    @State private var immersiveLoadedHeroAspectRatio: CGFloat?
    @State private var immersiveOutgoingHeroImage: Image?
    @State private var immersiveHeroImageTransitionProgress: CGFloat = 1
    @State private var immersiveHeroImageTransitionGeneration = 0
    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji

    init(
        item: 探索发行版本,
        auth: 用户登录,
        openedFromVisualNovelDetail: Bool = false
    ) {
        self.item = item
        self.openedFromVisualNovelDetail = openedFromVisualNovelDetail
        _auth = ObservedObject(wrappedValue: auth)
    }

    var body: some View {
        ZStack {
            releaseBackdrop

            ScrollView {
                沉浸封面详情内容(
                    onGestureActivityChanged: updateImmersiveHeroGestureActivity
                ) { dragContext in
                    releaseHeroAndPrimaryInformation(dragContext)
                } content: {
                    releaseContent
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.always, axes: .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            immersiveViewportSize = size
        }
        .coordinateSpace(name: "ReleaseImmersiveDetailScroll")
        .onPreferenceChange(
            探索发行版本沉浸取样框PreferenceKey.self
        ) { frames in
            updateImmersiveTextSampleGeometry(from: frames)
        }
        .navigationTitle(displayedReleaseTitle)
        .平台柔和滚动边缘(for: .top)
        .平台隐藏导航标题占位(displayedReleaseTitle)
        .平台内联导航标题()
        .toolbar {
            if !validExternalLinks.isEmpty {
                ToolbarItem(placement: .平台主操作) {
                    externalLinksToolbarControl
                }
            }

            if showsIncludedWorksToolbarControl,
               !validExternalLinks.isEmpty {
                if #available(iOS 26.0, *) {
                    ToolbarSpacer(.fixed, placement: .平台主操作)
                }
            }

            if showsIncludedWorksToolbarControl {
                ToolbarItem(placement: .平台主操作) {
                    includedWorksToolbarControl
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .平台沉浸导航栏()
        .task(id: item.id) {
            guard let fetchedItem = try? await VNDB探索服务.shared.发行详情(
                id: item.id
            ), !Task.isCancelled else {
                return
            }
            detailedItem = fetchedItem
            presentPreloadedImmersiveHeroImageIfNeeded()
        }
        .onChange(of: colorScheme) { _, _ in
            immersiveTextSamples = [:]
            immersiveTextSampleURL = nil
            immersiveTextRevealURL = nil
            refreshImmersiveTextSamplesForCurrentAppearance()
        }
        .onDisappear {
            confirmation.cancel()
            immersiveTextSamplingCoordinator.cancel()
        }
        .overlay(alignment: .bottom) {
            模糊解除提示(isPresented: confirmation.isPromptVisible)
                .padding(.bottom, 12)
        }
        .sheet(
            isPresented: Binding(
                get: { browserURL != nil },
                set: { if !$0 { browserURL = nil } }
            )
        ) {
            if let browserURL {
                内置Safari浏览器(url: browserURL)
                    .平台近全屏弹窗()
            }
        }
    }

    private var contentRestrictionMethod: 内容限制方式 {
        contentRestrictionMethodOverride ?? storedContentRestrictionMethod
    }

    private var releaseImage: 探索发行图片? {
        guard !openedFromVisualNovelDetail else { return nil }
        return displayedItem.images?.first {
            $0.url != nil || $0.thumbnail != nil
        }
            ?? item.images?.first {
                $0.url != nil || $0.thumbnail != nil
            }
    }

    private var releaseImageURLs: [URL] {
        let values: [String?]
        if openedFromVisualNovelDetail {
            values = [
                item.visualNovels?.first?.image?.url,
                displayedItem.visualNovels?.first?.image?.url
            ]
        } else if let releaseImage {
            values = [releaseImage.url, releaseImage.thumbnail]
        } else {
            values = [
                displayedItem.visualNovels?.first?.image?.url,
                displayedItem.visualNovels?.first?.image?.thumbnail,
                item.visualNovels?.first?.image?.url,
                item.visualNovels?.first?.image?.thumbnail
            ]
        }
        return values
            .compactMap { value -> URL? in
                guard let value, let url = URL(string: value),
                      let scheme = url.scheme?.lowercased(),
                      (scheme == "http" || scheme == "https"),
                      url.host != nil,
                      !openedFromVisualNovelDetail || !url.path.contains("/cv.t/") else {
                    return nil
                }
                return url
            }
            .reduce(into: []) { urls, url in
                if !urls.contains(url) { urls.append(url) }
            }
    }

    private var immersivePresentedHeroImage: Image? {
        immersiveLoadedHeroImage
    }

    private var releaseHeroSourceAspectRatio: CGFloat? {
        if openedFromVisualNovelDetail {
            let dimensions = item.visualNovels?.first?.image?.dims
                ?? displayedItem.visualNovels?.first?.image?.dims
            if let dimensions,
               dimensions.count >= 2,
               dimensions[0] > 0,
               dimensions[1] > 0 {
                return CGFloat(dimensions[0]) / CGFloat(dimensions[1])
            }
        }
        if let immersiveLoadedHeroAspectRatio,
           immersiveLoadedHeroAspectRatio.isFinite,
           immersiveLoadedHeroAspectRatio > 0 {
            return immersiveLoadedHeroAspectRatio
        }
        let dimensions = releaseImage?.dims
            ?? item.visualNovels?.first?.image?.dims
            ?? displayedItem.visualNovels?.first?.image?.dims
        guard let dimensions, dimensions.count >= 2, dimensions[0] > 0, dimensions[1] > 0 else { return nil }
        return CGFloat(dimensions[0]) / CGFloat(dimensions[1])
    }

    private var releaseImageSexual: Double? {
        if openedFromVisualNovelDetail {
            return item.visualNovels?.first?.image?.sexual
                ?? displayedItem.visualNovels?.first?.image?.sexual
        }
        return releaseImage?.sexual
            ?? displayedItem.visualNovels?.first?.image?.sexual
            ?? item.visualNovels?.first?.image?.sexual
    }

    private var releaseImageViolence: Double? {
        if openedFromVisualNovelDetail {
            return item.visualNovels?.first?.image?.violence
                ?? displayedItem.visualNovels?.first?.image?.violence
        }
        return releaseImage?.violence
            ?? displayedItem.visualNovels?.first?.image?.violence
            ?? item.visualNovels?.first?.image?.violence
    }

    private var releaseImageIsRestricted: Bool {
        内容安全限制判定.图片需要限制(
            sexual: releaseImageSexual,
            violence: releaseImageViolence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        ) && !revealHeroImage
    }

    private var canRevealReleaseImage: Bool {
        内容安全限制判定.图片允许手动解除模糊(
            sexual: releaseImageSexual,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            mode: filterMode
        )
    }

    private var releaseBackdrop: some View {
        GeometryReader { proxy in
            ZStack {
                Color.平台系统背景
                if !releaseImageURLs.isEmpty {
                    releaseBackdropImageLayer(loadedImage: immersivePresentedHeroImage)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.55)
                        .blur(radius: 96)
                        .saturation(1.18)
                        .opacity(0.56)
                    ForEach(releaseImageURLs, id: \.absoluteString) { url in
                        CachedAsyncImage(
                            url: url,
                            contentMode: .fill,
                            onImageLoaded: { loadedURL, image, imageSize in
                                activateImmersiveHeroImage(
                                    image,
                                    for: loadedURL,
                                    imageSize: imageSize
                                )
                            },
                            onImageReady: { loadedURL in
                                updateImmersiveTextSamples(for: loadedURL)
                            }
                        )
                        .frame(width: 1, height: 1)
                        .clipped()
                        .opacity(0)
                        .accessibilityHidden(true)
                    }
                }
                Color.平台系统背景.opacity(0.2)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func releaseHeroAndPrimaryInformation(
        _ dragContext: 沉浸封面拖动上下文
    ) -> some View {
        let cardProgress = min(max(dragContext.progress, 0), 1)
        let cardOffset = releaseInformationOverlap * cardProgress

        return VStack(alignment: .leading, spacing: 24) {
            releaseHero(dragContext)
            releasePrimaryInformation
                .padding(.top, -releaseInformationOverlap)
                .padding(.bottom, cardOffset)
                .compositingGroup()
                .offset(y: cardOffset)
        }
        .coordinateSpace(name: "ReleaseImmersiveDetailSampling")
    }

    private func releaseHero(
        _ dragContext: 沉浸封面拖动上下文
    ) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let heroHeight = max(proxy.size.height, 1)
            let fadeOverflow: CGFloat = 72
            let scrollFrame = proxy.frame(in: .named("ReleaseImmersiveDetailScroll"))
            let samplingFrame = proxy.frame(in: .named("ReleaseImmersiveDetailSampling"))
            let pullDown = scrollFrame.minY.isFinite ? max(scrollFrame.minY, 0) : 0
            let expandedHeroHeight = releaseExpandedHeroHeight(width: width, collapsedHeight: heroHeight)
            let transitionProgress = min(max(dragContext.progress, 0), 1)
            let expandedImageTopInset = max((immersiveViewportSize.height - expandedHeroHeight) / 2, 0)
            let imageTopInset = expandedImageTopInset * transitionProgress
            let layoutHeroHeight = heroHeight + (expandedHeroHeight - heroHeight) * transitionProgress
            let informationExtension = releaseHeroInformationExtension
            let extendsThroughInformation = informationExtension > 0
            let renderedHeight = layoutHeroHeight
                + imageTopInset
                + pullDown
                + (fadeOverflow + informationExtension) * (1 - transitionProgress)
            let sampleImageFrame = CGRect(
                x: samplingFrame.minX,
                y: samplingFrame.minY - pullDown
                    + (horizontalSizeClass == .regular ? -60 : 0),
                width: width,
                height: heroHeight + fadeOverflow + informationExtension
            )
            let primaryInformationStart = heroHeight + 24 + pullDown
            let blurTransitionStart = min(
                max(
                    extendsThroughInformation
                        ? primaryInformationStart / renderedHeight
                        : 0.46,
                    0
                ),
                1
            )
            let hasImage = !releaseImageURLs.isEmpty

            沉浸封面拖动图层(
                isExpanded: dragContext.isExpanded,
                hasImage: hasImage,
                progress: dragContext.progressBinding,
                onExpansionChanged: dragContext.onExpansionChanged,
                onBounceChanged: dragContext.onBounceChanged,
                onGestureActivityChanged: dragContext.onGestureActivityChanged,
                onTap: {
                    guard releaseImageIsRestricted,
                          contentRestrictionMethod == .blurred,
                          canRevealReleaseImage else { return }
                    confirmation.request(id: "release-hero-image") {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            revealHeroImage = true
                        }
                    }
                }
            ) { progress in
                releaseHeroImagePresentation(
                    loadedImage: immersivePresentedHeroImage,
                    extendsThroughInformation: extendsThroughInformation,
                    width: width,
                    heroHeight: heroHeight,
                    renderedHeight: renderedHeight,
                    backgroundHeight: heroHeight + fadeOverflow + informationExtension,
                    imageTopInset: imageTopInset,
                    minimumRasterHeight: heroHeight + fadeOverflow + informationExtension + 160,
                    blurTransitionStart: blurTransitionStart,
                    pullProgress: progress
                )
                .应用不安全内容限制(releaseImageIsRestricted, method: contentRestrictionMethod, blurRadius: 28)
                .animation(.easeInOut(duration: 0.28), value: revealHeroImage)
            }
            .frame(width: width, height: renderedHeight)
            .offset(y: -pullDown)
            .发行版本沉浸取样框(["image": sampleImageFrame])
        }
        .frame(height: horizontalSizeClass == .regular ? 420 : nil)
        .aspectRatio(
            horizontalSizeClass == .regular ? nil : 1 / 0.72,
            contentMode: .fit
        )
        .frame(maxWidth: .infinity)
        .padding(.bottom, releaseHeroLayoutExtension(pullProgress: dragContext.progress))
        .offset(y: -dragContext.bounceOffset)
        .accessibilityElement(children: .contain)
    }

    private func releaseExpandedHeroHeight(width: CGFloat, collapsedHeight: CGFloat) -> CGFloat {
        let sourceAspectRatio = releaseHeroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(min(width - horizontalInset, collapsedHeight * sourceAspectRatio), 1)
        return max(expandedWidth / sourceAspectRatio, 1)
    }

    private func releaseHeroLayoutExtension(pullProgress: CGFloat) -> CGFloat {
        let width = immersiveViewportSize.width
        guard width > 0, immersiveViewportSize.height > 0 else { return 0 }
        let transitionProgress = min(max(pullProgress, 0), 1)
        let collapsedHeight = horizontalSizeClass == .regular ? CGFloat(420) : width * 0.72
        let expandedHeight = releaseExpandedHeroHeight(width: width, collapsedHeight: collapsedHeight)
        let expandedTopInset = max((immersiveViewportSize.height - expandedHeight) / 2, 0)
        return max(expandedTopInset + expandedHeight - collapsedHeight, 0) * transitionProgress
    }

    private var releaseHeroInformationExtension: CGFloat {
        guard !releaseImageURLs.isEmpty else { return 0 }
        return horizontalSizeClass == .regular ? 284 : 316
    }

    @ViewBuilder
    private func releaseHeroImagePresentation(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        width: CGFloat,
        heroHeight: CGFloat,
        renderedHeight: CGFloat,
        backgroundHeight: CGFloat,
        imageTopInset: CGFloat,
        minimumRasterHeight: CGFloat,
        blurTransitionStart: CGFloat,
        pullProgress: CGFloat
    ) -> some View {
        let progress = min(max(pullProgress, 0), 1)
        let sourceAspectRatio = releaseHeroSourceAspectRatio ?? (1 / 0.72)
        let horizontalInset: CGFloat = horizontalSizeClass == .regular ? 48 : 32
        let expandedWidth = max(min(width - horizontalInset, heroHeight * sourceAspectRatio), 1)
        let expandedHeight = max(expandedWidth / sourceAspectRatio, 1)
        let imageWidth = width + (expandedWidth - width) * progress
        let presentationHeight = backgroundHeight + (expandedHeight - backgroundHeight) * progress
        let cornerRadius = 28 * progress

        releaseRasterizedHeroImage(
            loadedImage: loadedImage,
            extendsThroughInformation: extendsThroughInformation,
            width: imageWidth,
            renderedHeight: presentationHeight,
            minimumRasterHeight: minimumRasterHeight,
            revealProgress: progress,
            blurTransitionStart: blurTransitionStart
        )
        .平台背景延伸效果()
        .frame(width: imageWidth, height: presentationHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .top)
        .offset(y: imageTopInset)
        .frame(width: width, height: renderedHeight, alignment: .top)
    }

    @ViewBuilder
    private func releaseRasterizedHeroImage(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        width: CGFloat,
        renderedHeight: CGFloat,
        minimumRasterHeight: CGFloat,
        revealProgress: CGFloat,
        blurTransitionStart: CGFloat
    ) -> some View {
        let rasterBucket: CGFloat = 128
        let rasterHeight = max(
            (minimumRasterHeight / rasterBucket).rounded(.up) * rasterBucket,
            (renderedHeight / rasterBucket).rounded(.up) * rasterBucket
        )
        ZStack(alignment: .top) {
            releaseHeroImage(
                loadedImage: loadedImage,
                extendsThroughInformation: extendsThroughInformation,
                blurTransitionStart: blurTransitionStart,
                revealProgress: revealProgress
            )
            .frame(width: width, height: renderedHeight)
        }
        .frame(width: width, height: rasterHeight, alignment: .top)
        .drawingGroup(opaque: false, colorMode: .nonLinear)
        .frame(width: width, height: renderedHeight, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private func releaseHeroImage(
        loadedImage: Image?,
        extendsThroughInformation: Bool,
        blurTransitionStart: CGFloat,
        revealProgress: CGFloat
    ) -> some View {
        if extendsThroughInformation, horizontalSizeClass == .regular {
            releaseHeroImageComposition(
                loadedImage: loadedImage,
                sharpStops: releaseRegularSharpStops(
                    transitionStart: blurTransitionStart
                ),
                mediumBlurRadius: 18,
                mediumStops: releaseRegularMediumBlurStops(
                    transitionStart: blurTransitionStart
                ),
                heavyBlurRadius: 42,
                heavyStops: releaseRegularHeavyBlurStops(
                    transitionStart: blurTransitionStart
                ),
                fadeStops: releaseRegularFadeStops(
                    transitionStart: blurTransitionStart
                ),
                revealProgress: revealProgress
            )
        } else if extendsThroughInformation {
            let transitionStart = max(blurTransitionStart, 0.32)
            releaseHeroImageComposition(
                loadedImage: loadedImage,
                sharpStops: [
                    .init(color: .white, location: 0),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.32,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.78),
                        location: releaseCompactGradientLocation(
                            0.37,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.38),
                        location: releaseCompactGradientLocation(
                            0.44,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.54,
                            from: 0.32,
                            to: transitionStart
                        )
                    )
                ],
                mediumBlurRadius: 16,
                mediumStops: [
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.3,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.5),
                        location: releaseCompactGradientLocation(
                            0.39,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.54,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.74,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.46),
                        location: releaseCompactGradientLocation(
                            0.88,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(color: .clear, location: 1)
                ],
                heavyBlurRadius: 36,
                heavyStops: [
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.58,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.4),
                        location: releaseCompactGradientLocation(
                            0.66,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.78,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.88,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.36),
                        location: releaseCompactGradientLocation(
                            0.97,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(color: .clear, location: 1)
                ],
                fadeStops: [
                    .init(color: .white, location: 0),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.5,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.86),
                        location: releaseCompactGradientLocation(
                            0.62,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.58),
                        location: releaseCompactGradientLocation(
                            0.76,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.3),
                        location: releaseCompactGradientLocation(
                            0.86,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.08),
                        location: releaseCompactGradientLocation(
                            0.95,
                            from: 0.32,
                            to: transitionStart
                        )
                    ),
                    .init(color: .clear, location: 1)
                ],
                revealProgress: revealProgress
            )
        } else {
            let transitionStart = max(blurTransitionStart, 0.46)
            releaseHeroImageComposition(
                loadedImage: loadedImage,
                sharpStops: [
                    .init(color: .white, location: 0),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.46,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.5),
                        location: releaseCompactGradientLocation(
                            0.64,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.84,
                            from: 0.46,
                            to: transitionStart
                        )
                    )
                ],
                mediumBlurRadius: 18,
                mediumStops: [
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.35,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.4),
                        location: releaseCompactGradientLocation(
                            0.49,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.7,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.55),
                        location: releaseCompactGradientLocation(
                            0.82,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.96,
                            from: 0.46,
                            to: transitionStart
                        )
                    )
                ],
                heavyBlurRadius: 42,
                heavyStops: [
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.64,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.5),
                        location: releaseCompactGradientLocation(
                            0.76,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.88,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.45),
                        location: releaseCompactGradientLocation(
                            0.98,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(color: .clear, location: 1)
                ],
                fadeStops: [
                    .init(color: .white, location: 0),
                    .init(
                        color: .white,
                        location: releaseCompactGradientLocation(
                            0.46,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.86),
                        location: releaseCompactGradientLocation(
                            0.58,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.62),
                        location: releaseCompactGradientLocation(
                            0.7,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.34),
                        location: releaseCompactGradientLocation(
                            0.82,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .white.opacity(0.1),
                        location: releaseCompactGradientLocation(
                            0.91,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(
                        color: .clear,
                        location: releaseCompactGradientLocation(
                            0.97,
                            from: 0.46,
                            to: transitionStart
                        )
                    ),
                    .init(color: .clear, location: 1)
                ],
                revealProgress: revealProgress
            )
        }
    }

    private func releaseRegularSharpStops(
        transitionStart: CGFloat
    ) -> [Gradient.Stop] {
        [
            .init(color: .white, location: 0),
            .init(color: .white, location: max(transitionStart - 0.08, 0)),
            .init(color: .white.opacity(0.76), location: transitionStart),
            .init(
                color: .white.opacity(0.34),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.17)
            ),
            .init(
                color: .clear,
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.34)
            )
        ]
    }

    private func releaseRegularMediumBlurStops(
        transitionStart: CGFloat
    ) -> [Gradient.Stop] {
        [
            .init(color: .clear, location: max(transitionStart - 0.09, 0)),
            .init(color: .white.opacity(0.42), location: max(transitionStart - 0.03, 0)),
            .init(
                color: .white,
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.24)
            ),
            .init(
                color: .white,
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.61)
            ),
            .init(
                color: .white.opacity(0.42),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.85)
            ),
            .init(color: .clear, location: 1)
        ]
    }

    private func releaseRegularHeavyBlurStops(
        transitionStart: CGFloat
    ) -> [Gradient.Stop] {
        [
            .init(
                color: .clear,
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.1)
            ),
            .init(
                color: .white.opacity(0.42),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.27)
            ),
            .init(
                color: .white,
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.51)
            ),
            .init(
                color: .white,
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.76)
            ),
            .init(
                color: .white.opacity(0.34),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.92)
            ),
            .init(color: .clear, location: 1)
        ]
    }

    private func releaseRegularFadeStops(
        transitionStart: CGFloat
    ) -> [Gradient.Stop] {
        [
            .init(color: .white, location: 0),
            .init(color: .white, location: transitionStart),
            .init(
                color: .white.opacity(0.86),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.24)
            ),
            .init(
                color: .white.opacity(0.6),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.51)
            ),
            .init(
                color: .white.opacity(0.32),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.7)
            ),
            .init(
                color: .white.opacity(0.08),
                location: releaseRegularGradientLocation(after: transitionStart, progress: 0.9)
            ),
            .init(color: .clear, location: 1)
        ]
    }

    private func releaseRegularGradientLocation(
        after transitionStart: CGFloat,
        progress: CGFloat
    ) -> CGFloat {
        transitionStart + (1 - transitionStart) * progress
    }

    private func releaseCompactGradientLocation(
        _ location: CGFloat,
        from baseLocation: CGFloat,
        to transitionStart: CGFloat
    ) -> CGFloat {
        min(max(location, 0), 1)
    }

    private func releaseHeroImageComposition(
        loadedImage: Image?,
        sharpStops: [Gradient.Stop],
        mediumBlurRadius: CGFloat,
        mediumStops: [Gradient.Stop],
        heavyBlurRadius: CGFloat,
        heavyStops: [Gradient.Stop],
        fadeStops: [Gradient.Stop],
        revealProgress: CGFloat
    ) -> some View {
        let progress = min(max(revealProgress, 0), 1)
        return ZStack {
            releaseHeroImageLayer(loadedImage: loadedImage, revealProgress: progress)
                .mask {
                    ZStack {
                        LinearGradient(stops: sharpStops, startPoint: .top, endPoint: .bottom)
                        Color.white.opacity(progress)
                    }
                }
            releaseHeroImageLayer(loadedImage: loadedImage, revealProgress: progress)
                .blur(radius: mediumBlurRadius)
                .mask { LinearGradient(stops: mediumStops, startPoint: .top, endPoint: .bottom) }
                .opacity(1 - progress)
            releaseHeroImageLayer(loadedImage: loadedImage, revealProgress: progress)
                .blur(radius: heavyBlurRadius)
                .mask { LinearGradient(stops: heavyStops, startPoint: .top, endPoint: .bottom) }
                .opacity(1 - progress)
        }
        .compositingGroup()
        .mask {
            ZStack {
                LinearGradient(stops: fadeStops, startPoint: .top, endPoint: .bottom)
                Color.white.opacity(progress)
            }
        }
    }

    @ViewBuilder
    private func releaseHeroImageLayer(loadedImage: Image?, revealProgress: CGFloat) -> some View {
        if loadedImage != nil || immersiveOutgoingHeroImage != nil {
            ZStack {
                if let immersiveOutgoingHeroImage {
                    releaseAlignedHeroImage(immersiveOutgoingHeroImage, revealProgress: revealProgress)
                }
                if let loadedImage {
                    releaseAlignedHeroImage(loadedImage, revealProgress: revealProgress)
                        .opacity(immersiveHeroImageTransitionProgress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: immersiveHeroImageTransitionProgress)
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    private func releaseAlignedHeroImage(_ image: Image, revealProgress: CGFloat) -> some View {
        GeometryReader { proxy in
            image.resizable()
                .aspectRatio(releaseHeroSourceAspectRatio, contentMode: .fill)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .offset(y: horizontalSizeClass == .regular ? -60 * (1 - revealProgress) : 0)
        }
        .clipped()
    }

    @ViewBuilder
    private func releaseBackdropImageLayer(loadedImage: Image?) -> some View {
        if loadedImage != nil || immersiveOutgoingHeroImage != nil {
            ZStack {
                if let immersiveOutgoingHeroImage {
                    immersiveOutgoingHeroImage.resizable().aspectRatio(releaseHeroSourceAspectRatio, contentMode: .fill)
                }
                if let loadedImage {
                    loadedImage.resizable().aspectRatio(releaseHeroSourceAspectRatio, contentMode: .fill)
                        .opacity(immersiveHeroImageTransitionProgress)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: immersiveHeroImageTransitionProgress)
                }
            }
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    private var releaseImmersivePrimaryInformationIsVisible: Bool {
        guard immersiveDetailAppearance == .clear else { return true }
        guard !releaseImageURLs.isEmpty else { return true }
        guard immersiveTextSampleGeometry != nil,
              let url = immersiveLoadedHeroImageURL else { return false }
        return immersiveTextSampleURL == url && immersiveTextRevealURL == url
    }

    private var immersiveSystemGlassTint: Color? {
        guard immersiveDetailAppearance == .clear,
              releaseImageURLs.isEmpty else {
            return nil
        }
        return colorScheme == .dark ? .black : .white
    }

    private func releaseMetadataTextStyle(for key: String) -> 沉浸详情文字样式 {
        沉浸详情文字样式(
            appearance: immersiveDetailAppearance,
            sample: immersiveTextSamples[key],
            fallbackColorScheme: colorScheme
        )
    }

    private var currentImmersiveImageURL: URL? {
        if let loaded = immersiveLoadedHeroImageURL, releaseImageURLs.contains(loaded) {
            return loaded
        }
        return releaseImageURLs.first
    }

    private func shouldAcceptImmersiveImage(at url: URL) -> Bool {
        guard let candidate = releaseImageURLs.firstIndex(of: url) else { return false }
        guard let loaded = immersiveLoadedHeroImageURL,
              let loadedIndex = releaseImageURLs.firstIndex(of: loaded) else { return true }
        return candidate <= loadedIndex
    }

    private func updateImmersiveTextSamples(for url: URL) {
        guard shouldAcceptImmersiveImage(at: url),
              let geometry = immersiveTextSamplingCoordinator.latestGeometry ?? immersiveTextSampleGeometry else { return }
        scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: false)
    }

    private func activateImmersiveHeroImage(
        _ image: Image,
        for url: URL,
        imageSize: CGSize
    ) {
        guard shouldAcceptImmersiveImage(at: url) else { return }
        if imageSize.width > 0, imageSize.height > 0 {
            immersiveLoadedHeroAspectRatio = imageSize.width / imageSize.height
        }
        let canPresent = true
        let shouldCrossfade = canPresent && !reduceMotion && immersiveLoadedHeroImage != nil && immersiveLoadedHeroImageURL != url
        let shouldFadeIn = canPresent && !reduceMotion && immersiveLoadedHeroImage == nil
        immersiveHeroImageTransitionGeneration += 1
        let generation = immersiveHeroImageTransitionGeneration
        var transaction = Transaction()
        transaction.animation = nil
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            immersiveOutgoingHeroImage = shouldCrossfade ? immersiveLoadedHeroImage : nil
            immersiveLoadedHeroImage = image
            immersiveLoadedHeroImageURL = url
            immersiveHeroImageTransitionProgress = (shouldCrossfade || shouldFadeIn) ? 0 : (canPresent ? 1 : 0)
        }
        guard shouldCrossfade || shouldFadeIn else { return }
        Task { @MainActor in
            await Task.yield()
            guard generation == immersiveHeroImageTransitionGeneration else { return }
            immersiveHeroImageTransitionProgress = 1
            try? await Task.sleep(for: .seconds(0.32))
            guard generation == immersiveHeroImageTransitionGeneration else { return }
            var cleanup = Transaction()
            cleanup.animation = nil
            cleanup.disablesAnimations = true
            withTransaction(cleanup) { immersiveOutgoingHeroImage = nil }
        }
    }

    private func presentPreloadedImmersiveHeroImageIfNeeded() {
        guard immersiveLoadedHeroImage != nil,
              let url = immersiveLoadedHeroImageURL else { return }
        updateImmersiveTextSamples(for: url)
        guard immersiveHeroImageTransitionProgress < 1 else { return }
        immersiveHeroImageTransitionGeneration += 1
        let generation = immersiveHeroImageTransitionGeneration
        if reduceMotion {
            immersiveHeroImageTransitionProgress = 1
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard immersiveLoadedHeroImageURL == url,
                  generation == immersiveHeroImageTransitionGeneration else { return }
            immersiveHeroImageTransitionProgress = 1
        }
    }

    private func refreshImmersiveTextSamplesForCurrentAppearance() {
        guard let url = currentImmersiveImageURL,
              let geometry = immersiveTextSamplingCoordinator.latestGeometry ?? immersiveTextSampleGeometry else { return }
        scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: true)
    }

    private func scheduleImmersiveTextSamples(for url: URL, geometry: 沉浸封面文字取样几何, revealsImmediately: Bool) {
        let request = 沉浸封面文字取样请求(
            url: url,
            layout: .visualNovel,
            background: colorScheme == .dark ? .dark : .light,
            extendsThroughInformation: false,
            itemCounts: [:],
            geometry: geometry
        )
        immersiveTextSamplingCoordinator.submit(request) { request, samples in
            guard !immersiveHeroGestureIsActive,
                  currentImmersiveImageURL == request.url,
                  shouldAcceptImmersiveImage(at: request.url) else { return }
            var transaction = Transaction()
            transaction.animation = nil
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                immersiveTextSampleGeometry = request.geometry
                immersiveTextSamples = samples
                immersiveTextSampleURL = request.url
                if revealsImmediately { immersiveTextRevealURL = request.url }
            }
            if !revealsImmediately {
                Task { @MainActor in
                    await Task.yield()
                    guard immersiveTextSampleURL == request.url else { return }
                    withAnimation(.easeOut(duration: 0.18)) { immersiveTextRevealURL = request.url }
                }
            }
        }
    }

    private func updateImmersiveTextSampleGeometry(from frames: [String: CGRect]) {
        guard let imageFrame = frames["image"], 探索发行版本沉浸取样框有效(imageFrame) else { return }
        var regions: [String: CGRect] = [:]
        for (key, frame) in frames where key != "image" {
            guard 探索发行版本沉浸取样框有效(frame) else { continue }
            let relative = frame.offsetBy(dx: -imageFrame.minX, dy: -imageFrame.minY)
            guard let sample = releaseImmersiveSamplingFrame(relative) else { continue }
            regions[key] = sample
        }
        let geometry = 沉浸封面文字取样几何(imageSize: CGSize(width: imageFrame.width, height: imageFrame.height), regions: regions)
        guard immersiveTextSamplingCoordinator.latestGeometry != geometry else { return }
        immersiveTextSamplingCoordinator.remember(geometry)
        guard !immersiveHeroGestureIsActive, let url = currentImmersiveImageURL else { return }
        scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: true)
    }

    private func updateImmersiveHeroGestureActivity(_ isActive: Bool) {
        guard immersiveHeroGestureIsActive != isActive else { return }
        immersiveHeroGestureIsActive = isActive
        if isActive {
            immersiveTextSamplingCoordinator.cancel()
        } else if let url = currentImmersiveImageURL,
                  let geometry = immersiveTextSamplingCoordinator.latestGeometry ?? immersiveTextSampleGeometry {
            scheduleImmersiveTextSamples(for: url, geometry: geometry, revealsImmediately: true)
        }
    }

    private func releaseImmersiveSamplingFrame(_ frame: CGRect) -> CGRect? {
        guard 探索发行版本沉浸取样框有效(frame) else { return nil }
        func snapped(_ value: CGFloat) -> CGFloat { (value * 2).rounded() / 2 }
        let result = CGRect(x: snapped(frame.minX), y: snapped(frame.minY), width: snapped(frame.width), height: snapped(frame.height))
        return 探索发行版本沉浸取样框有效(result) ? result : nil
    }

    private var releasePrimaryInformation: some View {
        let textStyle = releaseMetadataTextStyle(for: "metadata")
        let titleStyle = releaseMetadataTextStyle(for: "metadata.title")
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    标题工具.生成富文本(
                        文本: displayedReleaseTitle,
                        isJapanese: staffNameLang == .original,
                        基础大小: 24,
                        是粗体: true,
                        日文字体名称: "HiraginoSans-W6",
                        系统字体粗细: .bold,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                )
                .沉浸详情文字前景色(titleStyle.primary, style: titleStyle)
                .fixedSize(horizontal: false, vertical: true)

                if let alternateReleaseTitle {
                    Text(
                        标题工具.生成富文本(
                            文本: alternateReleaseTitle,
                            isJapanese: staffNameLang != .original,
                            基础大小: 16,
                            语言来源已知: false,
                            空格视为日语: true
                        )
                    )
                    .沉浸详情文字前景色(titleStyle.secondary, style: titleStyle)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .沉浸详情文字阴影(titleStyle)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = displayedReleaseTitle
                } label: {
                    Label("拷贝标题", systemImage: "doc.on.doc")
                }

                if let alternateReleaseTitle {
                    Button {
                        UIPasteboard.general.string = alternateReleaseTitle
                    } label: {
                        Label("拷贝副标题", systemImage: "doc.on.doc")
                    }
                }
            }
            .发行版本沉浸取样框(["metadata.title"])

            releasePrimaryMetadata
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .沉浸详情玻璃背景(
            immersiveDetailAppearance,
            sample: textStyle.sample,
            fallbackTint: immersiveSystemGlassTint,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .发行版本沉浸取样框(["metadata"])
        .environment(\.colorScheme, titleStyle.colorScheme)
        .opacity(releaseImmersivePrimaryInformationIsVisible ? 1 : 0)
        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
    }

    private var releasePrimaryMetadata: some View {
        let rowSpacing: CGFloat = horizontalSizeClass == .regular ? 14 : 8
        return LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 0), spacing: 16, alignment: .topLeading),
                GridItem(.flexible(minimum: 0), alignment: .topLeading)
            ],
            alignment: .leading,
            spacing: rowSpacing
        ) {
            if let released = displayedItem.released {
                releaseMetadataItem(
                    icon: "calendar",
                    title: "发行日期",
                    text: released,
                    textStyle: releaseMetadataTextStyle(for: "metadata.release"),
                    sampleKey: "metadata.release"
                )
            }

            if let releaseLanguagesText {
                releaseMetadataItem(
                    icon: "character.book.closed",
                    title: "语言",
                    text: releaseLanguagesText,
                    textStyle: releaseMetadataTextStyle(for: "metadata.rating"),
                    sampleKey: "metadata.rating"
                )
            }

            if let releaseType = displayedItem.releaseType {
                releaseMetadataItem(
                    icon: "shippingbox",
                    title: "发行类型",
                    text: releaseTypeName(releaseType),
                    textStyle: releaseMetadataTextStyle(for: "metadata.status"),
                    sampleKey: "metadata.status"
                )
            }
        }
    }

    private func releaseMetadataItem(
        icon: String,
        title: LocalizedStringKey,
        text: String,
        valueLineLimit: Int = 2,
        textStyle: 沉浸详情文字样式,
        sampleKey: String
    ) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.subheadline)
                .沉浸详情文字前景色(textStyle.secondary, style: textStyle)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .沉浸详情文字前景色(textStyle.tertiary, style: textStyle)

                Text(verbatim: text)
                    .font(.subheadline.weight(.regular))
                    .沉浸详情文字前景色(textStyle.primary, style: textStyle)
                    .lineLimit(valueLineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .沉浸详情文字阴影(textStyle)
        .发行版本沉浸取样框([sampleKey])
    }

    private var releaseContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            releaseFactsSection
            releaseProducersSection
            releaseNotesSection
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 24 : 16)
    }

    private var releaseFactsSection: some View {
        releaseCard(title: "版本信息") {
            VStack(spacing: 0) {
                ForEach(Array(releaseFactItems.enumerated()), id: \.element.id) { index, item in
                    if let value = item.value {
                        releaseFact(item.title, value: value, icon: item.icon)
                    } else {
                        releaseBooleanFact(item.title, icon: item.icon)
                    }
                    if index < releaseFactItems.count - 1 {
                        releaseFactDivider()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var releaseProducersSection: some View {
        if let producers = displayedItem.producers, !producers.isEmpty {
            releaseCard(title: "开发与发行商") {
                VStack(spacing: 0) {
                    ForEach(Array(producers.enumerated()), id: \.element.id) { index, producer in
                        releaseProducerRow(producer)
                        if index < producers.count - 1 {
                            releaseFactDivider()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var releaseNotesSection: some View {
        if let notes = displayedItem.notes, !notes.isEmpty {
            releaseCard(title: "备注") {
                Text(verbatim: notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .textSelection(.enabled)
            }
        }
    }

    private func releaseCard<Content: View>(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let textStyle = 沉浸详情文字样式(
            appearance: .standard,
            sample: nil,
            fallbackColorScheme: colorScheme
        )
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .沉浸详情文字前景色(textStyle.primary, style: textStyle)
                .沉浸详情文字阴影(textStyle)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, colorScheme)
    }

    private func releaseFact(
        _ label: LocalizedStringKey,
        value: String,
        icon: String
    ) -> some View {
        releaseFactLayout(label, icon: icon) {
            Text(verbatim: value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func releaseBooleanFact(
        _ label: LocalizedStringKey,
        icon: String
    ) -> some View {
        releaseFactLayout(label, icon: icon) {
            Text("是")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func releaseFactLayout<Value: View>(
        _ label: LocalizedStringKey,
        icon: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)

                value()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
    }

    private func releaseFactDivider() -> some View {
        Divider()
            .padding(.leading, 50)
    }

    private var releaseFactItems: [探索发行版本信息项] {
        var items: [探索发行版本信息项] = []

        if let platforms = displayedItem.platforms, !platforms.isEmpty {
            items.append(
                .init(
                    id: "platforms",
                    title: "平台",
                    value: ListFormatter.localizedString(byJoining: platforms.map { VNDB显示工具.平台名称($0) }),
                    icon: "gamecontroller"
                )
            )
        }
        if let engine = displayedItem.engine, !engine.isEmpty {
            items.append(.init(id: "engine", title: "引擎", value: engine, icon: "gearshape.2"))
        }
        if let minimumAge = displayedItem.minimumAge {
            items.append(
                .init(
                    id: "minimum-age",
                    title: "分级",
                    value: "\(minimumAge.formatted())+",
                    icon: "person.badge.shield.checkmark"
                )
            )
        }
        if let resolution = displayedItem.resolution {
            items.append(.init(id: "resolution", title: "分辨率", value: resolutionText(resolution), icon: "rectangle.on.rectangle"))
        }
        if let voiced = displayedItem.voiced {
            items.append(.init(id: "voiced", title: "语音", value: voicedText(voiced), icon: "waveform"))
        }
        if let releaseMediaText {
            items.append(.init(id: "media", title: "介质", value: releaseMediaText, icon: "opticaldisc"))
        }
        if displayedItem.patch == true {
            items.append(.init(id: "patch", title: "补丁", value: nil, icon: "wrench.and.screwdriver"))
        }
        if displayedItem.freeware == true {
            items.append(.init(id: "freeware", title: "免费版本", value: nil, icon: "gift"))
        }
        if displayedItem.uncensored == true {
            items.append(.init(id: "uncensored", title: "无码版本", value: nil, icon: "eye"))
        }
        if displayedItem.official == true {
            items.append(.init(id: "official", title: "官方版本", value: nil, icon: "checkmark.seal"))
        }
        if displayedItem.hasAdultContent == true {
            items.append(.init(id: "adult-content", title: "成人内容", value: nil, icon: "exclamationmark.triangle"))
        }
        if let gtin = displayedItem.gtin, !gtin.isEmpty {
            items.append(.init(id: "gtin", title: "GTIN", value: gtin, icon: "barcode"))
        }
        if let catalog = displayedItem.catalog, !catalog.isEmpty {
            items.append(.init(id: "catalog", title: "目录编号", value: catalog, icon: "list.number"))
        }
        return items
    }

    private func releaseProducerRow(
        _ producer: 探索发行会社
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "building.2")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                多语言列表文本(
                    文本: 人物名称工具.显示名称(
                        name: producer.name,
                        original: producer.original,
                        偏好: staffNameLang
                    ),
                    isJapanese: staffNameLang == .original,
                    层级: .主标题,
                    日文字体名称: "HiraginoSans-W4",
                    系统字体粗细: .regular,
                    语言来源已知: false,
                    空格视为日语: true
                )
                let roles = [
                    producer.developer == true ? String(localized: "开发商") : nil,
                    producer.publisher == true ? String(localized: "发行商") : nil
                ].compactMap { $0 }
                if !roles.isEmpty {
                    Text(verbatim: ListFormatter.localizedString(byJoining: roles))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var releaseInformationOverlap: CGFloat {
        horizontalSizeClass == .regular ? 154 : 82
    }

    private func releaseTypeName(_ value: String) -> String {
        switch value.lowercased() {
        case "complete": return String(localized: "完整版本")
        case "partial": return String(localized: "部分版本")
        case "trial": return String(localized: "试玩版本")
        case "patch": return String(localized: "补丁")
        case "add-on": return String(localized: "追加内容")
        case "demo": return String(localized: "演示版本")
        case "other": return String(localized: "其他")
        default: return value
        }
    }

    private func resolutionText(_ resolution: 探索发行分辨率) -> String {
        switch resolution {
        case let .dimensions(dimensions):
            return dimensions.map(String.init).joined(separator: "×")
        case let .text(value):
            return value
        }
    }

    private func voicedText(_ value: Int) -> String {
        switch value {
        case 0: return String(localized: "无语音")
        case 1: return String(localized: "部分语音")
        case 2: return String(localized: "完整语音")
        default: return value.formatted()
        }
    }

    private var displayedItem: 探索发行版本 {
        detailedItem ?? item
    }

    private var displayedReleaseTitle: String {
        人物名称工具.显示名称(
            name: displayedItem.title,
            original: displayedItem.alttitle,
            偏好: staffNameLang
        )
    }

    private var alternateReleaseTitle: String? {
        人物名称工具.备用名称(
            name: displayedItem.title,
            original: displayedItem.alttitle,
            偏好: staffNameLang
        )
    }

    private var releaseLanguagesText: String? {
        guard let languages = displayedItem.languages,
              !languages.isEmpty else { return nil }
        let text = ListFormatter.localizedString(
            byJoining: languages.map { VNDB显示工具.语言名称($0.lang) }
        )
        return text.isEmpty ? nil : text
    }

    private var releaseMediaText: String? {
        guard let media = displayedItem.media,
              !media.isEmpty else { return nil }
        let text = ListFormatter.localizedString(
            byJoining: media.map { medium in
                medium.quantity == 1
                    ? medium.medium
                    : "\(medium.medium)×\(medium.quantity.formatted())"
            }
        )
        return text.isEmpty ? nil : text
    }

    private var includedVisualNovels: [探索发行作品] {
        if let visualNovels = displayedItem.visualNovels,
           !visualNovels.isEmpty {
            return visualNovels
        }
        return item.visualNovels ?? []
    }

    private var showsIncludedWorksToolbarControl: Bool {
        !openedFromVisualNovelDetail && !includedVisualNovels.isEmpty
    }

    private var validExternalLinks: [(link: 探索外链, url: URL)] {
        (displayedItem.externalLinks ?? []).compactMap { link in
            guard let url = URL(string: link.url),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host != nil else { return nil }
            return (link, url)
        }
    }

    @ViewBuilder
    private var includedWorksToolbarControl: some View {
        if includedVisualNovels.count == 1,
           let visualNovel = includedVisualNovels.first {
            NavigationLink {
                includedVisualNovelDestination(visualNovel)
            } label: {
                Image(systemName: 搜索范围.visualNovel.systemImage)
                    .frame(width: 24, height: 24)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("查看包含作品")
        } else {
            Menu {
                ForEach(includedVisualNovels) { visualNovel in
                    NavigationLink {
                        includedVisualNovelDestination(visualNovel)
                    } label: {
                        Text(verbatim: displayedTitle(for: visualNovel).text)
                    }
                }
            } label: {
                Image(systemName: 搜索范围.visualNovel.systemImage)
                    .frame(width: 24, height: 24)
            }
            .buttonBorderShape(.circle)
            .accessibilityLabel("选择包含作品")
        }
    }

    @ViewBuilder
    private var externalLinksToolbarControl: some View {
        if validExternalLinks.count == 1,
           let externalLink = validExternalLinks.first {
            Button {
                browserURL = externalLink.url
            } label: {
                Image(systemName: "link")
                    .font(.body)
            }
            .accessibilityLabel("外部链接")
        } else {
            Menu {
                ForEach(Array(validExternalLinks.enumerated()), id: \.offset) { _, externalLink in
                    Button {
                        browserURL = externalLink.url
                    } label: {
                        Label {
                            Text(verbatim: externalLinkTitle(externalLink.link))
                        } icon: {
                            Image(systemName: "arrow.up.right")
                        }
                    }
                }
            } label: {
                Image(systemName: "link")
                    .font(.body)
            }
            .accessibilityLabel("外部链接")
        }
    }

    private func externalLinkTitle(_ link: 探索外链) -> String {
        if let name = link.name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        let label = link.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? link.url : label
    }

    private func includedVisualNovelDestination(
        _ visualNovel: 探索发行作品
    ) -> some View {
        视觉小说详情(
            vnID: visualNovel.id,
            auth: auth,
            initialTitle: visualNovel.title,
            initialTitles: visualNovel.详情多语言标题,
            initialImageURL: visualNovel.image?.url,
            initialImageSexual: visualNovel.image?.sexual,
            initialImageViolence: visualNovel.image?.violence,
            initialImageDimensions: visualNovel.image?.dims
        )
    }

    private func displayedTitle(
        for vn: 探索发行作品
    ) -> 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: vn.titles?.map {
                用户多语言标题(
                    lang: $0.lang,
                    title: $0.title,
                    latin: $0.latin,
                    official: $0.official ?? false,
                    main: $0.main ?? false
                )
            },
            defaultTitle: vn.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }
}

struct 探索制作人员详情: View {
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

private enum 探索会社详情列表类型: String, CaseIterable, Identifiable {
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

struct 探索会社详情: View {
    let item: 探索会社

    @StateObject private var worksViewModel: 探索分页视图模型
    @StateObject private var releasesViewModel: 探索分页视图模型
    @State private var selectedList: 探索会社详情列表类型 = .works

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
                ForEach(探索会社详情列表类型.allCases) { list in
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

struct Today语录栏目: View {
    let quote: 探索语录?
    let isLoading: Bool
    let errorMessage: String?
    let onReload: () -> Void
    let onSelectCharacter: (探索语录角色) -> Void
    let onSelectVisualNovel: (探索语录作品) -> Void
    var usesTodayContainerStyle = false
    var usesWideLayout = false
    var usesEqualWidthColumns = false

    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false

    private var containerBackground: Color {
        usesTodayContainerStyle
            ? Color.平台次级分组背景
            : Color.secondary.opacity(0.08)
    }

    private var containerStroke: Color {
        usesTodayContainerStyle
            ? .clear
            : Color.secondary.opacity(0.24)
    }

    private var containerCornerRadius: CGFloat {
        usesTodayContainerStyle ? 28 : (usesWideLayout ? 20 : 26)
    }

    var body: some View {
        Group {
            if let quote {
                quoteContent(quote)
            } else if let errorMessage {
                探索加载失败提示(message: errorMessage, retry: onReload)
                    .frame(maxWidth: .infinity, minHeight: 128)
            } else {
                quotePlaceholder
            }
        }
        .listRowInsets(
            EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var quotePlaceholder: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.title2)
                .foregroundStyle(.tertiary)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.14))
                .frame(maxWidth: .infinity)
                .frame(height: 15)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
                .frame(width: 190, height: 15)

            Divider()
                .padding(.top, 2)

            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 20, height: 20)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 126, height: 14)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .平台卡片容器(
            background: containerBackground,
            stroke: containerStroke,
            cornerRadius: containerCornerRadius,
            lightModeShadowOpacity: 0,
            shadowRadius: 10,
            shadowY: 0
        )
        .accessibilityHidden(true)
    }

    private func quoteContent(_ quote: 探索语录) -> some View {
        Group {
            if usesWideLayout, usesEqualWidthColumns, hasSources(quote) {
                沉浸详情等高双栏布局(spacing: 20) {
                    quoteText(quote)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()

                    quoteSources(quote)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                }
                .overlay {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Divider()
                        Spacer(minLength: 0)
                    }
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)
            } else if usesWideLayout {
                HStack(alignment: .top, spacing: 18) {
                    quoteText(quote)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if hasSources(quote) {
                        Divider()

                        quoteSources(quote)
                            .padding(.vertical, 16)
                            .frame(maxWidth: 360, alignment: .leading)
                    }
                }
                .padding(.horizontal, 18)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    quoteText(quote)
                        .padding(.vertical, 12)

                    if hasSources(quote) {
                        Divider()

                        quoteSources(quote)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .平台卡片容器(
            background: containerBackground,
            stroke: containerStroke,
            cornerRadius: containerCornerRadius,
            lightModeShadowOpacity: 0,
            shadowRadius: 10,
            shadowY: 0
        )
    }

    private func quoteText(_ quote: 探索语录) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "quote.opening")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(verbatim: quote.quote)
                .font(.body)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hasSources(_ quote: 探索语录) -> Bool {
        quote.character != nil || quote.visualNovel != nil
    }

    @ViewBuilder
    private func quoteSources(_ quote: 探索语录) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let character = quote.character {
                Button {
                    onSelectCharacter(character)
                } label: {
                    let name = 人物名称工具.显示名称(
                        name: character.name,
                        original: character.original,
                        偏好: staffNameLang
                    )
                    let localizedSource = String(
                        localized: "来自“\(name)”"
                    )
                    quoteSourceLabel(
                        icon: "person.crop.rectangle.stack",
                        text: 探索人物名称富文本(
                            localizedSource,
                            language: staffNameLang,
                            size: 16
                        )
                    )
                }
                .buttonStyle(.plain)
            }

            if let vn = quote.visualNovel {
                Button {
                    onSelectVisualNovel(vn)
                } label: {
                    let title = displayedTitle(for: vn)
                    quoteSourceLabel(
                        icon: "books.vertical",
                        text: quoteVisualNovelSourceText(title)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func quoteSourceLabel(
        icon: String,
        text: AttributedString
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
            Text(text)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func displayedTitle(
        for vn: 探索语录作品
    ) -> (text: String, languageCode: String?) {
        if let title = title(
            for: preferredTitleLang,
            in: vn.titles
        ) {
            return title
        }
        if let title = title(
            for: fallbackTitleLang,
            in: vn.titles
        ) {
            return title
        }
        return (vn.title, nil)
    }

    private func title(
        for preference: 标题语言,
        in titles: [探索多语言标题]?
    ) -> (text: String, languageCode: String?)? {
        guard let titles else { return nil }
        let candidates = titles.filter {
            allowUnofficialTitles || ($0.official ?? false)
        }

        switch preference {
        case .original:
            guard let match = candidates.first(where: { $0.main == true })
                    ?? candidates.first else {
                return nil
            }
            return (match.title, match.lang)

        case .romanized:
            let match = candidates.first(where: {
                $0.main == true
                    && !($0.latin ?? "").trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
            }) ?? candidates.first(where: {
                !($0.latin ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            })
            guard let latin = match?.latin else { return nil }
            return (latin, nil)

        case .japanese, .chinese, .traditionalChinese, .korean, .english:
            guard let languageCode = preference.langCode,
                  let match = candidates.first(where: {
                      $0.lang == languageCode
                  }) else {
                return nil
            }
            return (match.title, match.lang)
        }
    }

    private func quoteVisualNovelSourceText(
        _ title: (text: String, languageCode: String?)
    ) -> AttributedString {
        let placeholder = "__PAPERVN_QUOTE_SOURCE__"
        let localizedSource = String(localized: "来自“\(placeholder)”")
        guard let placeholderRange = localizedSource.range(of: placeholder) else {
            return 标题工具.生成富文本(
                文本: localizedSource,
                isJapanese: title.languageCode == "ja",
                基础大小: 16,
                日文字体名称: "HiraginoSans-W4",
                语言来源已知: true
            )
        }

        var result = AttributedString(localizedSource[..<placeholderRange.lowerBound])
        result.font = .callout
        result += 标题工具.生成富文本(
            文本: title.text,
            isJapanese: title.languageCode == "ja",
            基础大小: 16,
            日文字体名称: "HiraginoSans-W4",
            语言来源已知: true,
            语言代码: title.languageCode
        )
        var suffix = AttributedString(localizedSource[placeholderRange.upperBound...])
        suffix.font = .callout
        result += suffix
        return result
    }
}

@MainActor
final class Today推荐视图模型: ObservableObject {
    @Published private(set) var recommendations: [探索推荐] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?

    private let service: any VNDB探索服务协议
    private let feedback: 推荐反馈中心

    init(
        service: (any VNDB探索服务协议)? = nil,
        feedback: 推荐反馈中心? = nil
    ) {
        self.service = service ?? VNDB探索服务.shared
        self.feedback = feedback ?? .shared
    }

    func reloadCachedRecommendations(userID: String) async {
        guard !userID.isEmpty,
              let cached = await service.已缓存推荐(
                userID: userID,
                排除ID: []
              ), !cached.isEmpty else { return }
        recommendations = feedback.展示排序(cached, userID: userID)
        hasLoaded = true
        errorMessage = nil
    }

    func 记录展示(_ ids: [String], userID: String) {
        feedback.记录展示(ids, userID: userID)
    }

    func loadCachedRecommendations(userID: String) async {
        guard !userID.isEmpty else {
            recommendations = []
            hasLoaded = true
            errorMessage = nil
            return
        }

        isLoading = true
        errorMessage = nil
        recommendations = feedback.展示排序(
            await service.已缓存推荐(userID: userID, 排除ID: []) ?? [],
            userID: userID
        )
        hasLoaded = true
        isLoading = false
    }
}

@MainActor
final class 探索分页视图模型: ObservableObject {
    @Published private(set) var visualNovels: [探索视觉小说] = []
    @Published private(set) var releases: [探索发行版本] = []
    @Published private(set) var characters: [探索角色] = []
    @Published private(set) var staff: [探索制作人员] = []
    @Published private(set) var producers: [探索会社] = []
    @Published private(set) var tags: [探索标签] = []
    @Published private(set) var traits: [探索特征] = []
    @Published private(set) var isInitialLoading = false
    @Published private(set) var initialLoadState: 探索首次加载状态 = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var nextPageError: String?
    @Published private(set) var paginationGeneration = 0

    let source: 探索源
    private let service: any VNDB探索服务协议
    private let pageSize = 平台列表分页.每页
    private var currentPage = 0
    private var generation = 0
    private var isLoadingFirstPage = false
    private var nextPageRequestID: UUID?

    init(
        source: 探索源,
        service: (any VNDB探索服务协议)? = nil
    ) {
        self.source = source
        self.service = service ?? VNDB探索服务.shared
    }

    var itemsAreEmpty: Bool {
        switch source {
        case .visualNovel: return visualNovels.isEmpty
        case .release: return releases.isEmpty
        case .character: return characters.isEmpty
        case .staff: return staff.isEmpty
        case .producer: return producers.isEmpty
        case .tag: return tags.isEmpty
        case .trait: return traits.isEmpty
        }
    }

    func loadFirstPage(forceRefresh: Bool = false) async {
        guard !isLoadingFirstPage else { return }
        isLoadingFirstPage = true
        generation += 1
        let requestedGeneration = generation
        nextPageRequestID = nil
        isLoadingMore = false
        isInitialLoading = itemsAreEmpty
        initialLoadState = .loading
        errorMessage = nil
        nextPageError = nil
        defer {
            isLoadingFirstPage = false
            if requestedGeneration == generation {
                isInitialLoading = false
                initialLoadState = .finished
            }
        }

        do {
            try await 探索自动重试 {
                try await loadPage(
                    1,
                    append: false,
                    forceRefresh: forceRefresh,
                    generation: requestedGeneration
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestedGeneration == generation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadNextPage() async {
        guard hasMore, !isLoadingMore, !isLoadingFirstPage else { return }
        let requestID = UUID()
        nextPageRequestID = requestID
        paginationGeneration += 1
        isLoadingMore = true
        nextPageError = nil
        let requestedGeneration = generation
        defer {
            if nextPageRequestID == requestID {
                nextPageRequestID = nil
                isLoadingMore = false
            }
        }

        do {
            try await 探索自动重试 {
                try await loadPage(
                    currentPage + 1,
                    append: true,
                    forceRefresh: false,
                    generation: requestedGeneration
                )
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestedGeneration == generation else { return }
            nextPageError = error.localizedDescription
        }
    }

    func loadMoreIfNeeded(currentID: String) {
        guard hasMore, currentID == lastItemID else { return }
        Task { await loadNextPage() }
    }

    func loadMoreIfNeeded(currentIndex: Int, totalCount: Int) {
        guard hasMore,
              currentIndex >= max(totalCount - 平台列表分页.预取余量, 0) else {
            return
        }
        Task { await loadNextPage() }
    }

    private var lastItemID: String? {
        switch source {
        case .visualNovel: return visualNovels.last?.id
        case .release: return releases.last?.id
        case .character: return characters.last?.id
        case .staff: return staff.last?.id
        case .producer: return producers.last?.id
        case .tag: return tags.last?.id
        case .trait: return traits.last?.id
        }
    }

    private func loadPage(
        _ page: Int,
        append: Bool,
        forceRefresh: Bool,
        generation requestedGeneration: Int
    ) async throws {
        switch source {
        case let .visualNovel(source):
            let response = try await service.视觉小说(
                来源: source,
                页码: page,
                每页: pageSize,
                强制刷新: forceRefresh
            )
            guard requestedGeneration == generation else { return }
            visualNovels = append
                ? merge(visualNovels, response.results)
                : response.results
            hasMore = response.more

        case let .release(source):
            let response = try await service.发行版本(
                来源: source,
                页码: page,
                每页: pageSize,
                强制刷新: forceRefresh
            )
            guard requestedGeneration == generation else { return }
            releases = append ? merge(releases, response.results) : response.results
            hasMore = response.more

        case let .character(source):
            let response = try await service.角色(
                来源: source,
                页码: page,
                每页: pageSize,
                强制刷新: forceRefresh
            )
            guard requestedGeneration == generation else { return }
            characters = append ? merge(characters, response.results) : response.results
            hasMore = response.more

        case let .staff(source):
            let response = try await service.制作人员(
                来源: source,
                页码: page,
                每页: pageSize,
                强制刷新: forceRefresh
            )
            guard requestedGeneration == generation else { return }
            staff = append ? merge(staff, response.results) : response.results
            hasMore = response.more

        case let .producer(source):
            let response = try await service.会社(
                来源: source,
                页码: page,
                每页: pageSize,
                强制刷新: forceRefresh
            )
            guard requestedGeneration == generation else { return }
            producers = append ? merge(producers, response.results) : response.results
            hasMore = response.more

        case let .tag(source):
            let response = try await service.标签(
                来源: source,
                页码: page,
                每页: pageSize,
                强制刷新: forceRefresh
            )
            guard requestedGeneration == generation else { return }
            tags = append ? merge(tags, response.results) : response.results
            hasMore = response.more

        case let .trait(source):
            let response = try await service.特征(
                来源: source,
                页码: page,
                每页: pageSize,
                强制刷新: forceRefresh
            )
            guard requestedGeneration == generation else { return }
            traits = append ? merge(traits, response.results) : response.results
            hasMore = response.more
        }

        currentPage = page
        errorMessage = nil
        nextPageError = nil
    }

    private func merge<Item: Identifiable>(
        _ existing: [Item],
        _ incoming: [Item]
    ) -> [Item] where Item.ID: Hashable {
        var seen = Set(existing.map(\.id))
        return existing + incoming.filter { seen.insert($0.id).inserted }
    }
}

@MainActor
final class Today语录视图模型: ObservableObject {
    @Published private(set) var quote: 探索语录?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: any VNDB探索服务协议
    private var pendingForcedReload = false

    init(service: (any VNDB探索服务协议)? = nil) {
        self.service = service ?? VNDB探索服务.shared
    }

    func load(forceRefresh: Bool = false) async {
        if isLoading {
            pendingForcedReload = pendingForcedReload || forceRefresh
            return
        }

        var shouldForceRefresh = forceRefresh
        while true {
            pendingForcedReload = false
            isLoading = true
            errorMessage = nil

            do {
                quote = try await 探索自动重试 {
                    try await service.随机语录(
                        强制刷新: shouldForceRefresh
                    )
                }
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
            guard pendingForcedReload else { return }
            shouldForceRefresh = true
        }
    }
}

