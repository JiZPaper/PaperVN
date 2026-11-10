import SwiftUI

/// 动画详情页“角色”下面的片头曲、片尾曲、插入曲：一张卡片（外观和评论卡片相同）纵向列出，
/// 歌曲多时只列前几首，标题右边“查看全部”打开完整列表。在 Apple Music 里找到的歌曲轻点后用“音乐”App 打开。
/// 歌名和歌手都显示原语言：找到时用日本商店的写法，没找到时用 MAL 括号里的原名。
struct 动画主题曲区域: View {
    let 歌曲: [动画主题曲]
    /// 还在匹配时为 nil。
    let 匹配结果: [Int: AppleMusic匹配结果]?
    /// 作品原名的语言（来源标明的），歌名按它选字体。
    let 原名语言: String?
    let 页面边距: CGFloat
    /// 数据维护用：报告匹配错误和添加音乐。
    let 作品: 主题曲所属作品

    @State private var 显示添加音乐 = false

    /// 卡片里最多列几首；只多出一首时直接全部列出，不用为一首歌打开新页面。
    private static let 预览首数 = 5

    @ScaledMetric(relativeTo: .title2) private var 加载图标上移: CGFloat = 8

    private var 预览: [动画主题曲] {
        歌曲.count <= Self.预览首数 + 1 ? 歌曲 : Array(歌曲.prefix(Self.预览首数))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("主题曲")
                    .font(.title2.weight(.bold))
                主题曲Beta标识()
                if 匹配结果 == nil {
                    // 加载图标没有文字基线，默认会往下掉；让它的中心对齐标题文字的中心
                    ProgressView()
                        .controlSize(.small)
                        .alignmentGuide(.firstTextBaseline) { [上移 = 加载图标上移] d in d[VerticalAlignment.center] + 上移 }
                }
                Spacer()
                if 预览.count < 歌曲.count {
                    NavigationLink {
                        动画主题曲列表页面(歌曲: 歌曲, 匹配结果: 匹配结果, 原名语言: 原名语言, 作品: 作品)
                    } label: {
                        Text("查看全部")
                    }
                }
            }

            if !预览.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(预览.enumerated()), id: \.element.id) { index, song in
                        主题曲行(歌曲: song, 匹配: 匹配结果?[song.id], 正在匹配: 匹配结果 == nil, 原名语言: 原名语言, 作品: 作品)
                        if index < 预览.count - 1 {
                            Divider()
                                .padding(.leading, 主题曲行.封面边长 + 12)
                        }
                    }
                }
                .padding(.horizontal, 评论卡片布局.内边距)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 评论卡片布局.圆角, style: .continuous))
            }

            Text(主题曲Beta说明)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 评论卡片布局.内边距)

            Button("添加音乐", systemImage: "plus") {
                显示添加音乐 = true
            }
            .font(.footnote)
            .padding(.horizontal, 评论卡片布局.内边距)
        }
        .padding(.horizontal, 页面边距)
        .sheet(isPresented: $显示添加音乐) {
            数据维护提交页面(内容: .添加音乐(malID: 作品.malID, 作品: 作品.名称))
                .平台近全屏弹窗()
        }
    }
}

struct 主题曲所属作品: Hashable {
    let malID: Int
    let 名称: String
}

private let 主题曲Beta说明: LocalizedStringKey = "Apple Music匹配结果可能不准确或不完整。我们会不断提高准确性。"

/// 匹配还在改进，标题旁标明。所有语言都写“Beta”。
private struct 主题曲Beta标识: View {
    var body: some View {
        Text(verbatim: "Beta")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(.secondary, lineWidth: 1))
    }
}

/// 所有主题曲，片头曲、片尾曲、插入曲分开列出。
private struct 动画主题曲列表页面: View {
    let 歌曲: [动画主题曲]
    let 匹配结果: [Int: AppleMusic匹配结果]?
    let 原名语言: String?
    let 作品: 主题曲所属作品

    var body: some View {
        List {
            分组("片头曲", 歌曲.filter { $0.种类 == .片头曲 })
            分组("片尾曲", 歌曲.filter { $0.种类 == .片尾曲 })
            分组("插入曲", 歌曲.filter { $0.种类 == .插入曲 })
            Section {
            } footer: {
                Text(主题曲Beta说明)
            }
        }
        .navigationTitle("主题曲")
        .平台内联导航标题()
    }

    @ViewBuilder
    private func 分组(_ title: LocalizedStringKey, _ songs: [动画主题曲]) -> some View {
        if !songs.isEmpty {
            Section(title) {
                ForEach(songs) { song in
                    主题曲行(歌曲: song, 匹配: 匹配结果?[song.id], 正在匹配: 匹配结果 == nil, 原名语言: 原名语言, 作品: 作品)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 主题曲行.封面边长 + 12 }
                }
            }
        }
    }
}

/// 歌曲不是原版、但 Apple Music 只有这个版本时显示。轻点弹出说明。
private struct 近似版本标签: View {
    let 原因: 主题曲映射.近似原因
    @Binding var 显示说明: Bool

    private var 说明: LocalizedStringKey {
        switch 原因 {
        case .剪辑版本: "Apple Music中没有这首歌的完整版。"
        case .其他阵容: "Apple Music中没有动画中的演唱阵容。"
        case .其他版本: "Apple Music中没有动画中的版本。"
        }
    }

    private var 标签: LocalizedStringKey {
        switch 原因 {
        case .剪辑版本: "剪辑版本"
        case .其他阵容: "其他阵容"
        case .其他版本: "其他版本"
        }
    }

    var body: some View {
        Button {
            显示说明 = true
        } label: {
            Text(标签)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(.secondary, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $显示说明) {
            Text(说明)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .padding()
                .frame(idealWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}

private struct 主题曲行: View {
    let 歌曲: 动画主题曲
    let 匹配: AppleMusic匹配结果?
    let 正在匹配: Bool
    let 原名语言: String?
    let 作品: 主题曲所属作品

    nonisolated static let 封面边长: CGFloat = 52

    @Environment(\.openURL) private var openURL
    @State private var 显示报告 = false
    @State private var 显示近似说明 = false

    /// 配上的是近似版本时的原因；没找到或还没匹配上时不显示。
    private var 近似原因: 主题曲映射.近似原因? {
        guard 用户填写 == nil, appleMusic != nil || (匹配 == nil && 映射歌曲 != nil) else { return nil }
        return 主题曲映射.查找近似原因(歌曲.id)
    }

    private var appleMusic: AppleMusic歌曲? {
        if case .已找到(let song)? = 匹配 { song } else { nil }
    }

    /// 映射里的日本商店歌曲：匹配还没完成时，先用它显示原语言的歌名和歌手。
    private var 映射歌曲: AppleMusic主题曲匹配.候选? {
        if case .歌曲(let item)? = 主题曲映射.查找(歌曲.id) { item } else { nil }
    }

    /// 原语言的歌名：Apple Music 日本商店的写法（去掉“TV Size”等版本说明），没找到时用 MAL 的原名。
    private var 用户填写: 主题曲映射.人工显示信息? { 主题曲映射.显示信息(歌曲.id) }

    /// 动画里实际用的版本的歌名和歌手：配上的是其他阵容、其他版本时，这一行仍然显示它，不显示 Apple Music 那首的。
    private var 正确信息: 主题曲映射.正确信息? {
        switch 近似原因 {
        case .其他阵容?, .其他版本?: 主题曲映射.查找正确信息(歌曲.id)
        default: nil
        }
    }

    private var 歌名: String {
        if let 用户填写 { return 用户填写.title }
        if 近似原因 == .其他版本 { return 正确信息?.歌名 ?? 歌曲.原标题 ?? 歌曲.标题 }
        if 近似原因 == .其他阵容, let name = 正确信息?.歌名 { return name }
        if let name = appleMusic?.标题 ?? 映射歌曲?.曲名 { return AppleMusic主题曲匹配.显示歌名(name) }
        return 歌曲.原标题 ?? 歌曲.标题
    }

    /// 歌名是原语言的写法（不是 MAL 引号里的罗马字或英文）时，语言按作品原名的语言。
    private var 歌名是原语言: Bool {
        用户填写 == nil && (appleMusic != nil || 映射歌曲 != nil || 歌曲.原标题 != nil)
    }

    private var 歌手: String {
        if let 用户填写 { return [用户填写.artist, 用户填写.album].compactMap { $0 }.joined(separator: " · ") }
        if 近似原因 == .其他阵容 || 近似原因 == .其他版本, let name = 正确信息?.歌手 ?? 歌曲.歌手原名 ?? (歌曲.歌手.isEmpty ? nil : 歌曲.歌手) {
            return name
        }
        return appleMusic?.歌手 ?? 映射歌曲?.歌手 ?? 歌曲.歌手原名 ?? 歌曲.歌手
    }

    /// 都用日本商店的链接：“音乐”App 打开时会按用户的 Apple Music 账户处理，不在 App 里猜用户的地区。
    private var 链接: URL? {
        appleMusic?.链接 ?? (匹配 == nil ? 映射歌曲?.链接 : nil)
    }

    private var 封面地址: URL? {
        appleMusic?.封面 ?? 映射歌曲?.封面
    }

    private var 种类名称: String {
        switch (歌曲.种类, 歌曲.序号) {
        case (.片头曲, let number?): String(localized: "片头曲\(number)")
        case (.片头曲, nil): String(localized: "片头曲")
        case (.片尾曲, let number?): String(localized: "片尾曲\(number)")
        case (.片尾曲, nil): String(localized: "片尾曲")
        case (.插入曲, _): String(localized: "插入曲")
        }
    }

    /// MAL 的话数只在是纯数字范围时显示（“1-16”“1-14, 16-28”），“Special Broadcast: 1-4”这类不显示。
    private var 话数: String? {
        guard let value = 歌曲.话数, value.range(of: #"^[\d\s,\-–]+$"#, options: .regularExpression) != nil else { return nil }
        let range = value.replacingOccurrences(of: "-", with: "–").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ", ")
        return range.contains("–") || range.contains(",")
            ? String(localized: "主题曲话数范围", defaultValue: "第\(range)话")
            : String(localized: "主题曲单话", defaultValue: "第\(range)话")
    }

    private var 说明: String {
        switch 匹配 {
        case .未找到?: [种类名称, String(localized: "未在Apple Music中找到")].joined(separator: " · ")
        default: [种类名称, 话数].compactMap { $0 }.joined(separator: " · ")
        }
    }

    var body: some View {
        // 标签放在主按钮外面：两个按钮不能嵌套
        HStack(spacing: 8) {
            主按钮
            if let 近似原因 {
                近似版本标签(原因: 近似原因, 显示说明: $显示近似说明)
            }
        }
    }

    private var 主按钮: some View {
        Button {
            if let 链接 { openURL(链接) }
        } label: {
            HStack(spacing: 12) {
                封面
                VStack(alignment: .leading, spacing: 2) {
                    Text(说明)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    // 字体规则同列表：歌名是标题（semibold，日文 W5），语言用作品原名标明的语言；
                    // 歌手照列表里人名的写法（regular，日文 W4，原语言名，由 生成富文本 判断中日文），字号是下属一级
                    多语言列表文本(
                        文本: 歌名,
                        isJapanese: 歌名是原语言 && 原名语言 == nil,
                        语言代码: 歌名是原语言 ? 原名语言 : nil,
                        层级: .主标题,
                        语言来源已知: 原名语言 != nil || !歌名是原语言
                    )
                    .foregroundStyle(链接 == nil && !正在匹配 ? .secondary : .primary)
                    .lineLimit(1)
                    多语言列表文本(
                        文本: 歌手,
                        isJapanese: true,
                        层级: .下属标题,
                        日文字体名称: "HiraginoSans-W4",
                        系统字体粗细: .regular,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 不用 disabled：匹配中的行不该显示成停用的样子，没有链接的行也要能长按报告错误
        .contextMenu {
            Button("报告音乐匹配错误", systemImage: "exclamationmark.bubble") {
                显示报告 = true
            }
        }
        .sheet(isPresented: $显示报告) {
            数据维护提交页面(内容: .音乐匹配错误(
                malID: 作品.malID, 作品: 作品.名称, 歌曲键: 歌曲.id, 种类: 歌曲.种类,
                歌名: 歌名, 歌手: 歌手, 当前曲目: appleMusic?.id ?? 映射歌曲?.trackId
            ))
            .平台近全屏弹窗()
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(链接 == nil ? Text(verbatim: "") : Text("在Apple Music中打开"))
    }

    private var 封面: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return ZStack {
            shape.fill(Color.secondary.opacity(0.12))
            if let artwork = 封面地址 {
                CachedAsyncImage(url: artwork, contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: Self.封面边长, height: Self.封面边长)
        .clipShape(shape)
        .overlay { shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5) }
    }
}
