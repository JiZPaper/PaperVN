import Combine
import Foundation
import SwiftUI

enum パーパル卡片实体 {
    case visualNovel(视觉小说搜索结果)
    case character(角色搜索结果)

    var vndbID: String {
        switch self {
        case let .visualNovel(item): return item.id
        case let .character(item): return item.id
        }
    }
}

enum パーパル卡片状态 {
    case 待解析
    case 解析中
    case 已解析(パーパル卡片实体)
    case 未找到
    case 失败(String)
}

enum パーパル卡片布局 {
    static let 内边距: CGFloat = 16

    static func 外框圆角(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) + 内边距
    }
}

@MainActor
final class パーパル卡片解析器 {
    static let shared = パーパル卡片解析器()

    private var 缓存: [String: パーパル卡片实体] = [:]
    private let service: VNDB服务

    init(service: VNDB服务 = .shared) {
        self.service = service
    }

    func 已缓存(_ 引用: パーパル卡片引用) -> パーパル卡片实体? {
        缓存[引用.id]
    }

    func 解析(_ 引用: パーパル卡片引用) async -> パーパル卡片状态 {
        if let 命中 = 缓存[引用.id] {
            return .已解析(命中)
        }
        do {
            guard let 实体 = try await 查找(引用) else {
                return .未找到
            }
            缓存[引用.id] = 实体
            return .已解析(实体)
        } catch is CancellationError {
            return .待解析
        } catch {
            return .失败(error.localizedDescription)
        }
    }

    func 清除缓存(_ 引用: パーパル卡片引用) {
        缓存.removeValue(forKey: 引用.id)
    }

    private func 查找(
        _ 引用: パーパル卡片引用
    ) async throws -> パーパル卡片实体? {
        guard let vndbID = 引用.vndbID, vndbID != "-" else {
            return nil
        }

        switch 引用.类型 {
        case .visualNovel:
            return try await 按编号查找视觉小说(vndbID)
        case .character:
            return try await 按编号查找角色(vndbID)
        }
    }

    private func 按编号查找视觉小说(
        _ vndbID: String
    ) async throws -> パーパル卡片实体 {
        let 详情 = try await service.fetchVNDetail(vnID: vndbID)
        return .visualNovel(
            视觉小说搜索结果(
                id: 详情.id,
                title: 详情.title,
                alttitle: nil,
                titles: 详情.titles,
                aliases: 详情.aliases,
                released: 详情.released,
                languages: 详情.languages,
                platforms: 详情.platforms,
                image: 详情.image,
                length: 详情.length,
                length_minutes: 详情.length_minutes,
                rating: 详情.rating,
                votecount: 详情.votecount,
                tags: nil,
                developers: 详情.developers
            )
        )
    }

    private func 按编号查找角色(
        _ vndbID: String
    ) async throws -> パーパル卡片实体 {
        let 详情 = try await service.fetchCharacterDetail(
            characterID: vndbID
        )
        return .character(
            角色搜索结果(
                id: 详情.id,
                name: 详情.name,
                original: 详情.original,
                aliases: 详情.aliases,
                image: 详情.image
            )
        )
    }
}

struct パーパル卡片视图: View {
    let 引用: パーパル卡片引用

    @EnvironmentObject private var auth: 用户登录
    @State private var 状态: パーパル卡片状态 = .待解析
    @State private var 重试代次 = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji
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
            switch 状态 {
            case let .已解析(实体):
                switch 实体 {
                case let .visualNovel(item):
                    NavigationLink {
                        视觉小说详情(
                            vnID: item.id,
                            auth: auth,
                            initialTitle: item.title,
                            initialTitles: item.titles,
                            initialImageURL: item.image?.url,
                            initialImageSexual: item.image?.sexual,
                            initialImageViolence: item.image?.violence,
                            initialImageDimensions: item.image?.dims
                        )
                    } label: {
                        视觉小说卡片内容(item)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                case let .character(item):
                    NavigationLink {
                        角色详情(
                            characterID: item.id,
                            auth: auth,
                            initialName: item.name,
                            initialOriginal: item.original,
                            initialAliases: item.aliases,
                            initialImage: item.image
                        )
                    } label: {
                        角色卡片内容(item)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            case .待解析, .解析中:
                占位卡片(说明: String(localized: "正在查找…"), 可重试: false)
            case .未找到:
                占位卡片(说明: String(localized: "VNDB上没有找到"), 可重试: true)
            case let .失败(消息):
                占位卡片(说明: 消息, 可重试: true)
            }
        }
        .task(id: "\(引用.id)|\(重试代次)") {
            if let 命中 = パーパル卡片解析器.shared.已缓存(引用) {
                状态 = .已解析(命中)
                return
            }
            状态 = .解析中
            状态 = await パーパル卡片解析器.shared.解析(引用)
        }
    }

    private func 视觉小说卡片内容(
        _ item: 视觉小说搜索结果
    ) -> some View {
        let 标题 = 标题工具.获取主标题(
            titles: item.titles,
            defaultTitle: item.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )

        return 卡片外框 {
            HStack(spacing: 12) {
                封面(
                    url: item.image?.url ?? item.image?.thumbnail,
                    sexual: item.image?.sexual,
                    violence: item.image?.violence,
                    占位符号: "book.closed"
                )

                VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                    类型徽标(
                        文本: String(localized: "视觉小说"),
                        符号: 搜索范围.visualNovel.systemImage
                    )

                    多语言列表文本(标题, 层级: .主标题)
                        .lineLimit(2)

                    if let developers = item.developers, !developers.isEmpty {
                        Text(
                            verbatim: ListFormatter.localizedString(
                                byJoining: developers.prefix(2).map(\.name)
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        if let released = item.released {
                            元信息(符号: "calendar", 文本: released)
                        }
                        视觉小说统一评分标签(
                            vndbID: item.id,
                            vndbRating: item.rating,
                            vndbVoteCount: item.votecount
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(パーパル卡片布局.内边距)
        }
    }

    private func 角色卡片内容(_ item: 角色搜索结果) -> some View {
        卡片外框 {
            HStack(spacing: 12) {
                封面(
                    url: item.image?.url,
                    sexual: item.image?.sexual,
                    violence: item.image?.violence,
                    占位符号: "person.crop.rectangle"
                )

                VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                    类型徽标(
                        文本: String(localized: "角色"),
                        符号: "person.crop.rectangle"
                    )

                    多语言列表文本(
                        文本: 人物名称工具.显示名称(
                            name: item.name,
                            original: item.original,
                            偏好: staffNameLang
                        ),
                        isJapanese: staffNameLang == .original,
                        层级: .主标题,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                    .lineLimit(2)

                    if let 备用 = 人物名称工具.备用名称(
                        name: item.name,
                        original: item.original,
                        偏好: staffNameLang
                    ) {
                        多语言列表文本(
                            文本: 备用,
                            isJapanese: staffNameLang != .original,
                            层级: .副标题,
                            语言来源已知: false,
                            空格视为日语: true
                        )
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(パーパル卡片布局.内边距)
        }
    }

    private func 占位卡片(说明: String, 可重试: Bool) -> some View {
        卡片外框 {
            HStack(spacing: 12) {
                RoundedRectangle(
                    cornerRadius: 列表封面布局.圆角(
                        horizontalSizeClass: horizontalSizeClass
                    ),
                    style: .continuous
                )
                .fill(Color.secondary.opacity(0.14))
                .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
                .overlay {
                    if 可重试 {
                        Image(systemName: "questionmark")
                            .foregroundStyle(.secondary)
                    } else {
                        平台持续加载指示器()
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: 引用.名称)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(verbatim: 说明)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if 可重试 {
                    Button {
                        パーパル卡片解析器.shared.清除缓存(引用)
                        重试代次 += 1
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("重新查找")
                }
            }
            .padding(パーパル卡片布局.内边距)
        }
    }

    private func 卡片外框<内容: View>(
        @ViewBuilder _ 内容: () -> 内容
    ) -> some View {
        内容()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func 类型徽标(文本: String, 符号: String) -> some View {
        HStack(spacing: 列表行布局.图标文字间距) {
            Image(systemName: 符号)
            Text(verbatim: 文本)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func 元信息(符号: String, 文本: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: 符号)
            Text(verbatim: 文本)
        }
    }

    private func 封面(
        url: String?,
        sexual: Double?,
        violence: Double?,
        占位符号: String
    ) -> some View {
        let 宽 = 列表封面布局.宽度
        let 高 = 列表封面布局.高度
        let 圆角 = 列表封面布局.圆角(
            horizontalSizeClass: horizontalSizeClass
        )
        let 需要限制 = 内容安全限制判定.图片需要限制(
            sexual: sexual,
            violence: violence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )

        return ZStack {
            Image(systemName: 占位符号)
                .font(.title3)
                .foregroundStyle(.tertiary)

            CachedAsyncImage(
                url: URL(string: url ?? ""),
                contentMode: .fill
            )
            .frame(width: 宽, height: 高)
            .clipped()
            .应用不安全内容限制(
                需要限制,
                method: contentRestrictionMethod,
                blurRadius: 16
            )
        }
        .frame(width: 宽, height: 高)
        .background(Color.secondary.opacity(0.1))
        .clipShape(
            RoundedRectangle(cornerRadius: 圆角, style: .continuous)
        )
    }
}

nonisolated enum パーパル光効配置 {
    static let 色環: [Color] = [
        Color(red: 0.40, green: 0.68, blue: 1.00),
        Color(red: 0.65, green: 0.52, blue: 1.00),
        Color(red: 1.00, green: 0.50, blue: 0.88),
        Color(red: 1.00, green: 0.62, blue: 0.48),
        Color(red: 1.00, green: 0.85, blue: 0.45),
        Color(red: 0.50, green: 0.92, blue: 0.78),
        Color(red: 0.40, green: 0.68, blue: 1.00)
    ]

    static let 周期: Double = 35
}

struct パーパル输入框彩虹描边: View {
    let 形状: AnyShape
    var 强度: Double = 1

    @Environment(\.accessibilityReduceMotion) private var 减弱动态效果
    @Environment(\.colorScheme) private var 配色方案
    @State private var 角度: Double = 0

    var body: some View {
        ZStack {
            形状
                .stroke(渐变, lineWidth: 6)
                .blur(radius: 40)
                .opacity(0.85)

            形状
                .stroke(渐变, lineWidth: 5)
                .blur(radius: 24)
                .opacity(0.8)

            形状
                .stroke(渐变, lineWidth: 4)
                .blur(radius: 14)
                .opacity(0.75)

            形状
                .stroke(渐变, lineWidth: 3)
                .blur(radius: 6)
                .opacity(0.7)
        }
        .opacity(强度)
        .blendMode(.plusLighter)
        .saturation(配色方案 == .dark ? 1.4 : 1.5)
        .brightness(配色方案 == .dark ? 0.15 : 0.2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            if 角度 == 0 {
                启动动画()
            }
        }
        .onChange(of: 减弱动态效果) { _, _ in 启动动画() }
    }

    private var 渐变: AngularGradient {
        AngularGradient(
            colors: パーパル光効配置.色環,
            center: .center,
            startAngle: .degrees(角度),
            endAngle: .degrees(角度 + 360)
        )
    }

    private func 启动动画() {
        guard !减弱动态效果 else {
            角度 = 0
            return
        }
        if 角度 == 0 {
            withAnimation(
                .linear(duration: パーパル光効配置.周期).repeatForever(autoreverses: false)
            ) {
                角度 = 360
            }
        }
    }
}

struct パーパル输入框阴影: View {
    let 形状: AnyShape

    private let 外扩: CGFloat = 32

    var body: some View {
        Canvas { context, size in
            let 绘制区域 = CGRect(origin: .zero, size: size)
                .insetBy(dx: 外扩, dy: 外扩)
            let 路径 = 形状.path(in: 绘制区域)

            context.drawLayer { layer in
                layer.addFilter(
                    .shadow(
                        color: .black.opacity(0.12),
                        radius: 16,
                        y: 8,
                        options: .shadowOnly
                    )
                )
                layer.fill(路径, with: .color(.black))
            }

            context.drawLayer { layer in
                layer.addFilter(
                    .shadow(
                        color: .black.opacity(0.08),
                        radius: 4,
                        y: 2,
                        options: .shadowOnly
                    )
                )
                layer.fill(路径, with: .color(.black))
            }

            context.blendMode = .destinationOut
            context.fill(路径, with: .color(.black))
        }
        .padding(-外扩)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct パーパル底部区域光晕: View {
    var 强度: Double = 1

    @Environment(\.accessibilityReduceMotion) private var 减弱动态效果
    @Environment(\.colorScheme) private var 配色方案
    @State private var 角度: Double = 0

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        渐变色.opacity(0.06),
                        渐变色.opacity(0.10),
                        渐变色.opacity(0.12),
                        渐变色.opacity(0.10)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(强度)
            .ignoresSafeArea(.keyboard)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { 启动动画() }
            .onChange(of: 减弱动态效果) { _, _ in 启动动画() }
    }

    private var 渐变色: Color {
        let 色環 = パーパル光効配置.色環
        let 索引 = Int(角度 / 60) % (色環.count - 1)
        return 色環[索引]
    }

    private func 启动动画() {
        guard !减弱动态效果 else {
            角度 = 0
            return
        }
        角度 = 0
        withAnimation(
            .linear(duration: パーパル光効配置.周期).repeatForever(autoreverses: false)
        ) {
            角度 = 360
        }
    }
}

struct パーパル思考指示: View {
    private static let 宽度: CGFloat = 46
    private static let 高度: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var 减弱动态效果
    @State private var 偏移: CGFloat = 0

    var body: some View {
        LinearGradient(
            colors: [
                Color.secondary.opacity(0.3),
                Color.secondary.opacity(0.6),
                Color.secondary.opacity(0.3)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: Self.宽度 * 3, height: Self.高度)
        .offset(x: 偏移)
        .frame(width: Self.宽度, height: Self.高度, alignment: .leading)
        .clipShape(Capsule())
        .accessibilityLabel("Paparu正在思考")
        .onAppear { 启动动画() }
        .onChange(of: 减弱动态效果) { _, _ in 启动动画() }
    }

    private func 启动动画() {
        guard !减弱动态效果 else {
            偏移 = -Self.宽度
            return
        }
        偏移 = 0
        withAnimation(
            .linear(duration: 1.8).repeatForever(autoreverses: false)
        ) {
            偏移 = -Self.宽度 * 1.5
        }
    }
}

struct パーパル卡片彩虹光效: ViewModifier {
    @State private var 角度: Double = 0
    @State private var 光效可见: Bool = true
    @Environment(\.accessibilityReduceMotion) private var 减弱动态效果
    @Environment(\.colorScheme) private var 配色方案

    func body(content: Content) -> some View {
        content
            .background {
                if 光效可见 {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            AngularGradient(
                                colors: パーパル光効配置.色環,
                                center: .center,
                                startAngle: .degrees(角度),
                                endAngle: .degrees(角度 + 360)
                            ),
                            lineWidth: 3
                        )
                        .blur(radius: 16)
                        .opacity(0.8)
                        .blendMode(.plusLighter)
                        .saturation(配色方案 == .dark ? 1.3 : 1.4)
                }
            }
            .onAppear {
                guard !减弱动态效果 else { return }

                withAnimation(
                    .linear(duration: 2).repeatForever(autoreverses: false)
                ) {
                    角度 = 360
                }

                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.easeOut(duration: 0.8)) {
                        光效可见 = false
                    }
                }
            }
    }
}

extension View {
}
