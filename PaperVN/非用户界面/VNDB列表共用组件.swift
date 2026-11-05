import Combine
import Foundation
import SwiftUI
import UIKit

// VNDB作品、发行版本列表共用的图片、加载状态、占位行与分页视图模型（原探索页面留下的组件）。

enum 探索发行版本沉浸取样框PreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }

    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

extension View {
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
        .沉浸取样校准登记("发行版本", keys: keys)
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

func 探索发行版本沉浸取样框有效(_ frame: CGRect) -> Bool {
    frame.minX.isFinite
        && frame.minY.isFinite
        && frame.width.isFinite
        && frame.height.isFinite
        && frame.width > 0
        && frame.height > 0
}

extension View {
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

struct 探索详情液态玻璃背景Modifier: ViewModifier {
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

extension View {
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

func 探索人物名称富文本(
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

func 探索占位线(
    width: CGFloat,
    height: CGFloat,
    opacity: Double = 0.1
) -> some View {
    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        .fill(Color.secondary.opacity(opacity))
        .frame(width: width, height: height)
}

struct 探索加载中标题: View {
    var body: some View {
        HStack(spacing: 8) {
            平台持续加载指示器()
            Text("正在加载…")
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

func 探索自动重试<T>(
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

struct 探索视觉小说加载占位行: View {
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

struct 探索发行版本加载占位行: View {
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

struct 探索重试按钮: View {
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
            Label("无法加载", systemImage: "wifi.exclamationmark")
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

extension 探索视觉小说 {
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
