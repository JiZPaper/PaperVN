import Combine
import Foundation
import SwiftUI
import UIKit

// Today的语录栏目与“为你推荐”的视图模型。

struct Today语录栏目: View {
    let quote: 探索语录?
    let isLoading: Bool
    let errorMessage: String?
    let onReload: () -> Void
    let onSelectCharacter: (探索语录角色) -> Void
    let onSelectVisualNovel: (探索语录作品) -> Void
    var usesTodayContainerStyle = false
    var usesWideLayout = false

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
            if usesWideLayout {
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
                        icon: "zipper.page",
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

/// Today“为你推荐”里的一条：视觉小说来自 VNDB 公开评分训练的协同模型，动画、漫画与轻小说来自作品推荐模型。
enum 为你推荐条目: Identifiable, Hashable {
    case 视觉小说(探索推荐)
    case 作品(作品推荐项)

    var id: String {
        switch self {
        case let .视觉小说(item): item.visualNovel.id
        case let .作品(item): item.id
        }
    }

    var 类型: 作品类型 {
        switch self {
        case .视觉小说: .visualNovel
        case let .作品(item): item.作品.类型
        }
    }

    /// 几种类型混在一起显示：按平滑加权轮询交替，资料库里某类作品越多、这一类出现得越多
    /// （权重取数量的平方根，少的类型也不会被挤掉）。每一类内部保持原来的顺序。
    static func 交替(
        _ lists: [作品类型: [为你推荐条目]],
        资料库数量 counts: [作品类型: Int]
    ) -> [为你推荐条目] {
        let order = 作品类型.allCases.filter { !(lists[$0] ?? []).isEmpty }
        guard order.count > 1 else { return order.first.flatMap { lists[$0] } ?? [] }
        let weights = Dictionary(uniqueKeysWithValues: order.map {
            ($0, max(1, Double(counts[$0] ?? 0)).squareRoot())
        })
        let total = weights.values.reduce(0, +)
        var credits = Dictionary(uniqueKeysWithValues: order.map { ($0, 0.0) })
        var positions = Dictionary(uniqueKeysWithValues: order.map { ($0, 0) })
        var result: [为你推荐条目] = []
        while true {
            let remaining = order.filter { positions[$0]! < lists[$0]!.count }
            guard !remaining.isEmpty else { break }
            for type in remaining { credits[type]! += weights[type]! }
            let pick = remaining.max { credits[$0]! < credits[$1]! }!
            credits[pick]! -= total
            result.append(lists[pick]![positions[pick]!])
            positions[pick]! += 1
        }
        return result
    }
}

@MainActor
final class Today推荐视图模型: ObservableObject {
    @Published private(set) var recommendations: [为你推荐条目] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?

    private let feedback: 推荐反馈中心
    private var visualNovels: [探索推荐] = []
    private var works: [作品推荐项] = []
    private var enabledTypes = Set(作品类型.allCases)
    private var latestLoad = 0

    init(feedback: 推荐反馈中心? = nil) {
        self.feedback = feedback ?? .shared
    }

    func 记录展示(_ items: [为你推荐条目]) {
        guard let owner = 本地资料库.shared.所有者 else { return }
        feedback.记录展示(items.map(\.id), userID: 推荐反馈中心.作品曝光用户(owner))
    }

    func 记录打开(_ item: 为你推荐条目) {
        guard let owner = 本地资料库.shared.所有者 else { return }
        feedback.记录打开(item.id, userID: 推荐反馈中心.作品曝光用户(owner))
    }

    /// 所有类型都在设备上直接计算；先显示上一次的结果，算完再替换。
    func loadRecommendations(
        类型 types: Set<作品类型>,
        包含成人内容: Bool
    ) async {
        enabledTypes = types
        latestLoad &+= 1
        let load = latestLoad
        isLoading = true
        errorMessage = nil
        let exposureUser = 推荐反馈中心.作品曝光用户(本地资料库.shared.所有者 ?? "")
        func 应用(_ result: 为你推荐结果) {
            works = feedback.展示排序(result.作品, owner: 本地资料库.shared.所有者 ?? "")
            visualNovels = feedback.展示排序(result.视觉小说, userID: exposureUser)
            组合()
        }
        if works.isEmpty && visualNovels.isEmpty {
            应用(作品推荐中心.shared.已缓存推荐())
        }
        if types.isEmpty {
            应用(为你推荐结果())
        } else {
            do {
                let result = try await 作品推荐中心.shared.推荐(类型: types, 包含成人内容: 包含成人内容)
                // 同时可能有几次加载，只采用最后发起的一次
                guard load == latestLoad else { return }
                应用(result)
            } catch is CancellationError {
                // 保留正在显示的内容；还没有内容时继续显示加载中，等下一次加载
                if load == latestLoad { isLoading = false }
                return
            } catch {
                guard load == latestLoad else { return }
                // 已经有内容时继续显示，下次打开 Today 再更新
                if works.isEmpty && visualNovels.isEmpty {
                    errorMessage = error.localizedDescription
                }
            }
        }
        hasLoaded = true
        isLoading = false
    }

    /// 关闭的作品类型不显示。
    func 更新显示类型(_ types: Set<作品类型>) {
        enabledTypes = types
        组合()
    }

    private func 组合() {
        var lists: [作品类型: [为你推荐条目]] = [:]
        if enabledTypes.contains(.visualNovel) {
            lists[.visualNovel] = visualNovels.map(为你推荐条目.视觉小说)
        }
        for item in works where enabledTypes.contains(item.作品.类型) {
            lists[item.作品.类型, default: []].append(.作品(item))
        }
        var counts: [作品类型: Int] = [:]
        for entry in 本地资料库.shared.条目 { counts[entry.类型, default: 0] += 1 }
        recommendations = 为你推荐条目.交替(lists, 资料库数量: counts)
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
