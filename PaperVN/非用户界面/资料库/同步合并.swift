import Foundation
import UIKit

// PaperVN Sync 的合并规则：把本地资料库与各平台的资料库对齐。
//
// 每个平台保存一份“基线”——上次同步完成时该平台的状态。再次同步时，和基线不同的平台记录就是“在平台上被修改过”，
// 在 PaperVN 中修改过但还没推送成功的作品记在“待推送”里。
// 在 PaperVN 中做的修改自动推送到各平台；不是在 PaperVN 中做的修改（平台上的新增、修改、删除）一律交给用户确认。
// 第一次登录某个账户（或者换了账户）时没有基线，此时如果它和资料库的内容不同，先让用户选择合并、以某个账户为准，或者分别保留。

/// 各平台能同步的字段。
struct 同步能力: Hashable {
    /// 评分精度（10–100 制下的步长）；nil 表示不支持评分。
    var 评分步长: Int?
    var 支持进度: Bool
    var 支持的类型: Set<作品类型>
    /// Bangumi 没有删除收藏的接口。
    var 支持删除 = true
    /// Bangumi 只导入：没有删除接口，资料库删掉的作品在 Bangumi 上会一直留着，所以不向 Bangumi 写入。
    var 支持写入 = true
    /// TMDB 没有“在看”“看过”等状态，只有想看列表：状态只区分“计划观看”和其他。
    var 只区分想看 = false

    /// 平台能否记录这个值。TMDB 上“计划观看”以外的作品只能靠评分留在资料库里，没有评分就无法记录。
    func 可记录(_ value: 同步快照) -> Bool {
        !只区分想看 || value.状态 == .planning || value.评分 != nil
    }

    /// 资料库里的评分可能来自只有 10 分制的 MAL，和其他来源比较时按 10 分制的精度，避免 78 分和 8 分被当成冲突。
    /// 各平台和自己的基线比较时仍然用平台自己的精度，所以 AniList 上 78 改成 75 也能察觉。
    static let 本地 = 同步能力(评分步长: 10, 支持进度: true, 支持的类型: Set(作品类型.allCases))
}

extension 资料库平台 {
    var 同步能力: 同步能力 {
        switch self {
        case .myAnimeList:
            .init(评分步长: 10, 支持进度: true, 支持的类型: [.anime, .manga, .lightNovel])
        case .aniList:
            .init(评分步长: 1, 支持进度: true, 支持的类型: [.anime, .manga, .lightNovel])
        case .annict:
            // Annict 只记录观看状态；评分属于评论，进度需要逐集发布记录，都不同步
            .init(评分步长: nil, 支持进度: false, 支持的类型: [.anime])
        case .bangumi:
            // 视觉小说仍由原来的 Bangumi 推送处理，这里只管动画、漫画与轻小说：只从 Bangumi 导入，不写入
            .init(评分步长: 10, 支持进度: true, 支持的类型: [.anime, .manga, .lightNovel], 支持删除: false, 支持写入: false)
        case .tmdb:
            // TMDB 只有想看列表和评分（0.5–10，即 10 分制下步长 5），没有进度；只同步动画
            .init(评分步长: 5, 支持进度: false, 支持的类型: [.anime], 只区分想看: true)
        case .vndb:
            .init(评分步长: 1, 支持进度: false, 支持的类型: [.visualNovel])
        }
    }

    /// 参与动画、漫画、轻小说同步的平台。
    static let 动画漫画平台: [资料库平台] = [.myAnimeList, .aniList, .bangumi, .annict, .tmdb]
}

/// 一条记录中参与同步、可能冲突的字段。
struct 同步快照: Codable, Hashable {
    var 状态: 资料库状态
    /// 10–100，nil 表示没有评分。
    var 评分: Int?
    var 进度: Int?

    init(状态: 资料库状态, 评分: Int?, 进度: Int?) {
        self.状态 = 状态
        self.评分 = (评分 ?? 0) > 0 ? 评分 : nil
        self.进度 = (进度 ?? 0) > 0 ? 进度 : nil
    }

    /// 只比较双方都支持的字段；评分按较粗的精度比较。
    /// 空值表示该来源没有这项记录（例如 Bangumi 标了“看过”但没记集数），不是 0，比较时视为一致。
    /// 已看完、已读完的作品不比较进度：各平台对完成时的集数记法不同。
    static func 一致(_ a: 同步快照, _ 能力A: 同步能力, _ b: 同步快照, _ 能力B: 同步能力) -> Bool {
        if 能力A.只区分想看 || 能力B.只区分想看 {
            guard (a.状态 == .planning) == (b.状态 == .planning) else { return false }
        } else {
            guard a.状态 == b.状态 else { return false }
        }
        if let stepA = 能力A.评分步长, let stepB = 能力B.评分步长, a.评分 != nil, b.评分 != nil {
            let step = max(stepA, stepB)
            if 取整(a.评分, step) != 取整(b.评分, step) { return false }
        }
        if 能力A.支持进度, 能力B.支持进度, a.状态 != .completed,
           let progressA = a.进度, let progressB = b.进度, progressA != progressB {
            return false
        }
        return true
    }

    static func 取整(_ score: Int?, _ step: Int) -> Int {
        guard let score, score > 0 else { return 0 }
        return Int((Double(score) / Double(step)).rounded())
    }
}

/// 某个平台资料库中的一条记录，已经整理成统一的字段。
struct 平台资料库记录: Codable, Hashable {
    let 平台: 资料库平台
    /// 作品在该平台上的 ID。
    let 平台ID: String
    let 类型: 作品类型
    var malID: Int?
    var 标题: String
    var 日文标题: String?
    var 封面地址: String?
    var 快照: 同步快照
    var 总数: Int?
    /// 10–100。
    var 平均评分: Double?
    var 发行日期: String?
    var 开始日期: String?
    var 完成日期: String?
    var 修改时间: Date?
    /// 平台上这条记录的创建时间（AniList）。用来认出平台在创建时自动填写的日期。
    var 创建时间: Date? = nil
    /// 各语言的标题。
    var 多语言标题: [用户多语言标题] = []
    /// 作品映射给出的编号；没有时按 MAL ID 或平台 ID 编号。
    var 指定键: String?
    /// 是作品的附属条目（特别篇、单行本等）：导入时并入作品，不单独成为一部作品，也不写入。
    var 附属: Bool?

    var 键: String { 指定键 ?? 同步合并.键(类型: 类型, malID: malID, 平台: 平台, 平台ID: 平台ID) }
}

/// 一个已登录平台本次读到的完整资料库。
struct 平台资料库 {
    let 平台: 资料库平台
    let 账户ID: String
    let 账户名称: String
    var 记录: [String: 平台资料库记录]
    /// 同一部作品在这个平台上的其他条目（附属条目），只用来显示，不参与合并。
    var 附属记录: [平台资料库记录] = []

    init(平台: 资料库平台, 账户ID: String, 账户名称: String, 记录: [平台资料库记录]) {
        self.平台 = 平台
        self.账户ID = 账户ID
        self.账户名称 = 账户名称
        (self.记录, self.附属记录) = 同步合并.每部作品一条(记录)
    }
}

/// 上次同步完成时某个平台的状态。
struct 平台基线: Codable, Equatable {
    var 账户ID: String
    var 账户名称: String
    var 快照: [String: 同步快照]
}

/// 冲突或选择里的一个来源。
enum 同步来源: Hashable, Codable {
    case 本地
    case 平台(资料库平台)

    var 能力: 同步能力 {
        switch self {
        case .本地: .本地
        case let .平台(platform): platform.同步能力
        }
    }

    var 名称: String {
        switch self {
        case .本地: Self.本地名称
        case let .平台(platform): platform.localizedTitle
        }
    }

    /// 用在“使用…”“显示…”这类选项里，例如“MyAnimeList资料库”。
    var 资料库名称: String {
        switch self {
        case .本地: Self.本地名称
        case let .平台(platform): String(localized: "\(platform.localizedTitle)资料库")
        }
    }

    /// 例如“此iPhone上的资料库”。
    static var 本地名称: String {
        String(localized: "此\(UIDevice.current.localizedModel)上的资料库")
    }

    /// 字段越全的来源，越适合作为自动采用的结果。
    fileprivate var 优先级: Int {
        switch self {
        case .本地: 0
        case .平台(.myAnimeList): 1
        case .平台(.aniList): 2
        case .平台(.bangumi): 3
        case .平台(.annict): 4
        case .平台: 5
        }
    }
}

/// 一部作品在某个来源中的记录；快照为 nil 表示在该来源中被删除。
struct 同步版本: Hashable, Identifiable {
    let 来源: 同步来源
    let 快照: 同步快照?
    var id: 同步来源 { 来源 }
}

/// 需要用户选择的一部作品：不是在 PaperVN 中做的更改，或者多个来源的记录不同。
struct 条目冲突: Identifiable, Hashable {
    enum 种类: Hashable {
        /// 在其他平台上新增、修改或删除，需要确认是否采用。
        case 外部更改
        /// 多个来源的记录不同。
        case 记录不同
    }

    let 种类: 种类
    let 键: String
    let 标题: String
    var 多语言标题: [用户多语言标题]? = nil
    let 类型: 作品类型
    let 封面地址: String?
    let 版本: [同步版本]
    var 选择: 同步来源?
    var id: String { 键 }
}

/// 第一次登录账户时，资料库与账户内容不同的处理方式。
enum 导入方式: Hashable {
    /// 保留所有来源中的作品，记录不同的逐项选择。
    case 合并
    /// 和所选来源一致：其他来源中多出的作品会被删除。
    case 为准(同步来源)
    /// 资料库显示所选来源的内容；其他账户中多出的作品留在原来的平台上，在资料库中隐藏。
    case 分别保留(同步来源)

    var 主要来源: 同步来源? {
        switch self {
        case .合并: nil
        case let .为准(source), let .分别保留(source): source
        }
    }
}

/// 某个平台的作品比上次同步时少了很多，可能是账户被清空或暂时读不全。
struct 资料库减少提示: Identifiable, Hashable {
    let 平台: 资料库平台
    let 账户名称: String
    let 上次数量: Int
    let 现在数量: Int
    var id: 资料库平台 { 平台 }
}

enum 减少处理: Hashable {
    /// 保留资料库里的作品，并重新上传到该平台。
    case 保留并重新上传
    /// 资料库也删除这些作品。
    case 同样删除
}

/// 选择导入方式时显示的各来源概况。
enum 未参与原因: Hashable {
    case 未登录
    case 同步方式为无
    case 仅导出
    case 资料库为空
}

struct 来源概况: Identifiable, Hashable {
    let 来源: 同步来源
    let 账户名称: String?
    let 数量: [作品类型: Int]
    /// 账户和上次同步的不是同一个。
    let 账户已更换: Bool
    var id: 同步来源 { 来源 }
    var 总数: Int { 数量.values.reduce(0, +) }
}

/// 一部作品合并后的结果。
enum 合并结果: Hashable {
    case 保留(同步快照)
    case 删除
}

/// 推送到平台的一项修改。
struct 推送操作: Identifiable, Hashable {
    enum 种类: Hashable { case 新增, 修改, 删除 }

    let 平台: 资料库平台
    let 键: String
    let 种类: 种类
    let 类型: 作品类型
    let 标题: String
    let 日文标题: String?
    let malID: Int?
    /// 用来查找作品时比较年份。
    var 年份: Int? = nil
    /// 所有语言的标题，用来在平台上搜索。
    var 全部标题: [String] = []
    /// 新增时可能还不知道作品在该平台上的 ID，推送前再查找。
    var 平台ID: String?
    /// 删除时为 nil。
    let 目标: 同步快照?
    /// 写入前平台上的开始、完成日期（平台上还没有这部作品时都为 nil）与资料库里的日期。
    /// AniList 会给没有日期的记录自动填上当天，写入后用这两个值改回来，见 `同步合并.自动填写后的修正`。
    var 平台原有日期 = 同步日期()
    var 资料库日期 = 同步日期()

    var id: String { "\(平台.rawValue)|\(键)" }
}

/// 开始、完成日期（“2024-05-31”，也可能只有年或年月）。
struct 同步日期: Hashable, Sendable {
    var 开始: String?
    var 完成: String?
}

/// 一次同步的完整过程：读到的数据、用户的选择与最终的推送计划。
struct 同步会话 {
    var 本地: [String: 本地资料库条目]
    var 平台: [资料库平台: 平台资料库]
    var 基线: [资料库平台: 平台基线]
    var 待推送: [String: Set<资料库平台>]
    /// 在 PaperVN 中删除、但平台不支持删除（Bangumi）的作品，同步时不会从平台恢复回来。
    var 本地已删除: Set<String> = []
    /// 用户设为“仅导出”的平台：平台上的更改不导入资料库，只把资料库写到平台。
    var 仅导出: Set<资料库平台> = []
    /// 用户设为“仅导入”的平台（以及不能写入的 Bangumi）：只导入，不写入。
    var 仅导入: Set<资料库平台> = []

    /// 参与导入的平台：“仅导出”的平台不导入。
    var 可导入平台库: [平台资料库] { 平台.values.filter { !仅导出.contains($0.平台) } }

    func 可导出(_ platform: 资料库平台) -> Bool {
        platform.同步能力.支持写入 && !仅导入.contains(platform)
    }

    var 减少提示: [资料库减少提示] = []
    var 减少处理: [资料库平台: 减少处理] = [:]
    var 需要选择导入方式 = false
    var 来源概况: [来源概况] = []
    var 导入方式: 导入方式?
    var 冲突: [条目冲突] = []
    var 冲突已生成 = false
    var 结果: [String: 合并结果] = [:]
    var 推送: [推送操作] = []
    /// 新增时在平台上找不到对应作品，不会同步到该平台。
    var 未匹配: [资料库平台: [String]] = [:]
    /// 平台不支持删除（Bangumi），需要用户在平台上手动删除的作品。
    var 无法删除: [资料库平台: [String]] = [:]
    /// 分别保留时在资料库中隐藏的作品，以及它们所在的平台。
    var 新隐藏: [String: Set<资料库平台>] = [:]
    /// 读取失败、没有参与这次同步的平台与原因。
    var 读取失败: [资料库平台: String] = [:]
    /// 没有参与这次同步的动画漫画平台和原因（读取失败的另见 `读取失败`），在选择导入方式时说明。
    var 未参与: [资料库平台: 未参与原因] = [:]
    var 需要确认推送 = false
    /// AniList 自动填写、要改回来的日期（作品 → 应有的日期），见 `同步合并.AniList自动填写的日期`。
    var AniList日期修正: [String: 同步日期] = [:]
    /// 第一次导入时，资料库“最近更改”使用哪个平台记录的更改时间，由用户选择。
    var 修改时间来源: 资料库平台?
    var 已确认推送 = false
    var 已应用减少处理 = false
    var 已检查导入方式 = false
    /// 推送前查到的平台 ID，切换选项重新生成推送计划时不用再查。
    var 查找到的ID: [资料库平台: [String: String]] = [:]

    /// 有更改时间的平台（Annict 不提供），第一次导入时可以选择按哪个平台的时间排序。
    var 可选修改时间来源: [资料库平台] {
        资料库平台.动画漫画平台.filter { platform in
            平台[platform]?.记录.values.contains { $0.修改时间 != nil } == true
        }
    }

    var 需要选择修改时间来源: Bool {
        !新账户平台.isEmpty && 可选修改时间来源.count >= 2
    }

    /// 是否有账户是第一次同步（或者换了账户）。
    var 新账户平台: Set<资料库平台> {
        Set(可导入平台库.filter { 基线[$0.平台]?.账户ID != $0.账户ID }.map(\.平台))
    }
}

enum 同步合并 {
    /// 映射目录上线前，有 MAL ID 的作品用 MAL ID 作为 PaperVN ID，其他用平台 ID。
    static func 键(类型: 作品类型, malID: Int?, 平台: 资料库平台, 平台ID: String) -> String {
        let kind = 类型 == .anime ? "anime" : "manga"
        if let malID { return "mal-\(kind):\(malID)" }
        return "\(平台.rawValue)-\(kind):\(平台ID)"
    }

    /// 比较标题时忽略大小写、空白和常见符号。
    nonisolated static func 标题比较键(_ title: String) -> String {
        title.lowercased()
            .folding(options: [.widthInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    /// 比较不同平台标题用的键：统一全半角和大小写，去掉“映画”“劇場版”等前缀，
    /// 把“第2期”“2期”“2nd Season”“Season 2”“第二季”统一成同一种写法，再去掉空格和符号。
    nonisolated static func 标题匹配键(_ title: String) -> String {
        var text = title.precomposedStringWithCompatibilityMapping.lowercased()
        for prefix in ["映画", "劇場版", "剧场版", "电影", "電影", "tvアニメ", "the movie"] {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        let 数字: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        func 季(_ value: String) -> String {
            if let number = Int(value) { return "s\(number)" }
            return value.count == 1 ? (数字[value.first!].map { "s\($0)" } ?? value) : value
        }
        // 分割放送的写法（Part 2、Part.2、第2クール、2nd Cour）统一成同一个记号，免得末尾的数字被当成季数
        for pattern in [#"part\s*\.?\s*([0-9]+)"#, #"第?\s*([0-9]+)\s*クール"#, #"([0-9]+)\s*(?:st|nd|rd|th)?\s*cour"#] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            while let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let whole = Range(match.range, in: text),
                  let number = Range(match.range(at: 1), in: text) {
                text.replaceSubrange(whole, with: " pt\(Int(text[number]) ?? 0) ")
            }
        }
        let patterns: [(String, Int)] = [
            (#"第\s*([0-9]+|[一二三四五六七八九十])\s*(期|季|シーズン|部)"#, 1),
            (#"([0-9]+)\s*(st|nd|rd|th)?\s*season"#, 1),
            (#"season\s*([0-9]+)"#, 1),
            (#"([0-9]+)\s*期"#, 1),
            // “…同好会 2”这样标题末尾单独的数字也是季数
            (#"\s([0-9]{1,2})$"#, 1),
        ]
        for (pattern, group) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            while let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let whole = Range(match.range, in: text),
                  let number = Range(match.range(at: group), in: text) {
                text.replaceSubrange(whole, with: " " + 季(String(text[number])) + " ")
            }
        }
        return 标题比较键(text)
    }

    /// 一条记录可用来比较的所有标题（原名、罗马字、英文、中文等）。
    private static func 全部标题(日文标题: String?, 标题: String, 多语言标题: [用户多语言标题]?) -> [String] {
        var titles = [标题]
        if let 日文标题 { titles.append(日文标题) }
        for item in 多语言标题 ?? [] {
            titles.append(item.title)
            if let latin = item.latin { titles.append(latin) }
        }
        return titles
    }

    private static func 年份(_ date: String?) -> Int? {
        date.flatMap { Int($0.prefix(4)) }
    }

    /// 没有 MAL ID 的记录（Bangumi 的书籍、对应表里没有的动画），按标题找到其他来源里同一部作品的 MAL ID。
    /// 比较所有语言的标题，季度和前缀的写法统一后再比；两边都有年份时相差不超过一年。
    /// 只在所有标题都指向同一部作品时采用，避免同名作品被并成一部。
    /// 同一部作品在一个平台上有多个条目时（Bangumi 的特别篇、单行本，AniList 的自定义列表等）只保留一条参与同步：
    /// 主条目优先；只有附属条目时取进展最多、其次最近更改的那条。其余的记为附属记录，不参与合并，也不会被写入。
    static func 每部作品一条(_ records: [平台资料库记录]) -> (记录: [String: 平台资料库记录], 附属: [平台资料库记录]) {
        func rank(_ record: 平台资料库记录) -> (Int, Int, Date) {
            let progress: Int = switch record.快照.状态 {
            case .completed: 4
            case .inProgress: 3
            case .onHold: 2
            case .planning: 1
            case .dropped: 0
            }
            return (record.附属 == true ? 0 : 1, progress, record.修改时间 ?? .distantPast)
        }
        var kept: [String: 平台资料库记录] = [:]
        var others: [平台资料库记录] = []
        for record in records {
            guard let existing = kept[record.键] else {
                kept[record.键] = record
                continue
            }
            if rank(record) > rank(existing) {
                others.append(existing)
                kept[record.键] = record
            } else {
                others.append(record)
            }
        }
        return (kept, others)
    }

    static func 快照(_ entry: 本地资料库条目) -> 同步快照 {
        同步快照(状态: entry.状态 ?? .planning, 评分: entry.评分, 进度: entry.进度)
    }

    // MARK: 第一步：检查资料库是否异常减少

    static func 检查减少(_ session: inout 同步会话) {
        session.减少提示 = session.可导入平台库.compactMap { library in
            guard let base = session.基线[library.平台], base.账户ID == library.账户ID else { return nil }
            let before = base.快照.count
            let now = library.记录.count
            let removed = base.快照.keys.filter { library.记录[$0] == nil }.count
            let 清空 = before > 0 && now == 0
            let 大量减少 = removed >= 20 && removed * 2 >= before
            guard 清空 || 大量减少 else { return nil }
            return 资料库减少提示(平台: library.平台, 账户名称: library.账户名称, 上次数量: before, 现在数量: now)
        }
        .sorted { $0.平台.rawValue < $1.平台.rawValue }
    }

    // MARK: 第二步：新账户是否需要选择导入方式

    static func 检查导入方式(_ session: inout 同步会话) {
        let newPlatforms = session.新账户平台.filter { !(session.平台[$0]?.记录.isEmpty ?? true) }
        session.需要选择导入方式 = false
        guard !newPlatforms.isEmpty else { return }

        var sources: [(同步来源, [String: 同步快照])] = []
        if !session.本地.isEmpty {
            sources.append((.本地, session.本地.mapValues(快照)))
        }
        for library in session.可导入平台库 where !library.记录.isEmpty {
            sources.append((.平台(library.平台), library.记录.mapValues(\.快照)))
        }
        guard sources.count >= 2, 来源之间有差异(sources, 类型: 类型表(session)) else { return }

        session.需要选择导入方式 = true
        session.来源概况 = sources.map { source, values in
            let types = 类型表(session)
            var counts: [作品类型: Int] = [:]
            for key in values.keys {
                counts[types[key] ?? .anime, default: 0] += 1
            }
            var name: String?
            var switched = false
            if case let .平台(platform) = source, let library = session.平台[platform] {
                name = library.账户名称
                if let base = session.基线[platform] { switched = base.账户ID != library.账户ID }
            }
            return 来源概况(来源: source, 账户名称: name, 数量: counts, 账户已更换: switched)
        }
        .sorted { $0.来源.优先级 < $1.来源.优先级 }
    }

    private static func 来源之间有差异(_ sources: [(同步来源, [String: 同步快照])], 类型: [String: 作品类型]) -> Bool {
        let keys = Set(sources.flatMap(\.1.keys))
        for key in keys {
            let type = 类型[key] ?? .anime
            let relevant = sources.filter { $0.0.能力.支持的类型.contains(type) }
            var present: [(同步来源, 同步快照)] = []
            for (source, values) in relevant {
                guard let value = values[key] else { return true }
                present.append((source, value))
            }
            for i in present.indices.dropFirst()
            where !同步快照.一致(present[0].1, present[0].0.能力, present[i].1, present[i].0.能力) {
                return true
            }
        }
        return false
    }

    /// 每部作品的类型，以本地资料库为准，其次是平台记录。
    static func 类型表(_ session: 同步会话) -> [String: 作品类型] {
        var types: [String: 作品类型] = [:]
        for library in session.平台.values.sorted(by: { 同步来源.平台($0.平台).优先级 > 同步来源.平台($1.平台).优先级 }) {
            for (key, record) in library.记录 { types[key] = record.类型 }
        }
        for (key, entry) in session.本地 { types[key] = entry.类型 }
        return types
    }

    // MARK: 第三步：逐项合并

    /// 计算每部作品的结果；多个来源改得不一样时生成冲突。
    static func 合并(_ session: inout 同步会话) {
        let types = 类型表(session)
        let newPlatforms = session.新账户平台
        var keys = Set(session.本地.keys).union(session.待推送.keys)
        for library in session.平台.values { keys.formUnion(library.记录.keys) }
        for platform in session.平台.keys {
            keys.formUnion(session.基线[platform].map { Array($0.快照.keys) } ?? [])
        }

        var results: [String: 合并结果] = [:]
        var conflicts: [条目冲突] = []

        var hidden: [String: Set<资料库平台>] = [:]

        for key in keys.sorted() {
            let type = types[key] ?? .anime

            // 以某个来源为准或分别保留：该来源支持的类型直接采用它的记录
            if let primary = session.导入方式?.主要来源, primary.能力.支持的类型.contains(type) {
                if let value = 记录(of: primary, key: key, session: session) {
                    results[key] = .保留(补全(value, from: primary, key: key, session: session))
                } else if case .分别保留 = session.导入方式 {
                    let platforms = Set(session.平台.values.filter { $0.记录[key] != nil }.map(\.平台))
                    if !platforms.isEmpty || session.本地[key] != nil {
                        hidden[key] = platforms
                    }
                } else {
                    results[key] = .删除
                }
                continue
            }

            let candidates = 候选版本(key: key, type: type, session: session, newPlatforms: newPlatforms)
            guard !candidates.isEmpty else {
                // 平台上没有变化、本地却没有这部作品，又不是在 PaperVN 中删除的（例如资料库文件读写出错丢失了）：
                // 从平台恢复，不算外部更改
                // 只恢复在能删除的平台（MAL、AniList、Annict）上也有的作品：只在 Bangumi 上的作品不能删除，
                // 资料库里没有它多半是选了“覆盖”或在 PaperVN 中删除后 Bangumi 删不掉，不能恢复回来
                let holders = session.可导入平台库.filter { $0.记录[key] != nil }.map(\.平台)
                if session.本地[key] == nil, session.待推送[key] == nil, !session.本地已删除.contains(key),
                   holders.contains(where: { $0.同步能力.支持删除 }),
                   let record = 最佳记录(key: key, session: session) {
                    results[key] = .保留(补全(record.快照, from: .平台(record.平台), key: key, session: session))
                }
                continue
            }

            // 资料库大量减少时选了“资料库中也删除”，这些删除不再逐项确认
            if let result = 删除处理(candidates, session: session) {
                results[key] = result
                continue
            }

            // 不是在 PaperVN 中做的更改：来自已经同步过的平台的版本
            let external = candidates.contains { version in
                if case let .平台(platform) = version.来源 { return !newPlatforms.contains(platform) }
                return false
            }
            var options = candidates
            if external, !options.contains(where: { $0.来源 == .本地 }) {
                // 让用户可以选择保持资料库现在的样子
                options.append(同步版本(来源: .本地, 快照: session.本地[key].map(快照)))
            }

            if let winner = 一致的版本(options) {
                if let value = winner.快照 {
                    results[key] = .保留(补全(value, from: winner.来源, key: key, session: session))
                } else if session.本地[key] != nil || session.平台.values.contains(where: { $0.记录[key] != nil }) {
                    results[key] = .删除
                }
                continue
            }

            let others = options.filter { $0.来源 != .本地 }
            conflicts.append(条目冲突(
                种类: external && 一致的版本(others) != nil ? .外部更改 : .记录不同,
                键: key,
                标题: 标题(key: key, session: session),
                多语言标题: 多语言标题(key: key, session: session),
                类型: type,
                封面地址: 封面(key: key, session: session),
                版本: options.sorted { $0.来源.优先级 < $1.来源.优先级 }
            ))
        }

        session.新隐藏 = hidden
        session.结果 = results
        session.冲突 = conflicts
        session.冲突已生成 = true
    }

    /// 参与比较的版本：上次同步后改过的来源，以及新账户里的记录。
    private static func 候选版本(
        key: String,
        type: 作品类型,
        session: 同步会话,
        newPlatforms: Set<资料库平台>
    ) -> [同步版本] {
        var candidates: [同步版本] = []
        var hasNewAccountVersion = false

        for library in session.可导入平台库 where library.平台.同步能力.支持的类型.contains(type) {
            // 这个平台的集数划分和作品不同时，它的进度不和其他来源比较（视为未知）
            let current = library.记录[key].map { record in
                var value = record.快照
                if !进度可比(record, key: key, session: session) { value.进度 = nil }
                return value
            }
            if newPlatforms.contains(library.平台) {
                // 新账户没有基线：有记录就参与比较，没有记录不代表删除
                if let current {
                    candidates.append(同步版本(来源: .平台(library.平台), 快照: current))
                    hasNewAccountVersion = true
                }
                continue
            }
            let base = session.基线[library.平台]?.快照[key]
            switch (base, current) {
            case (nil, nil):
                continue
            case let (base?, current?) where 同步快照.一致(base, library.平台.同步能力, current, library.平台.同步能力):
                continue
            case (_, nil):
                candidates.append(同步版本(来源: .平台(library.平台), 快照: nil))
            case let (_, current?):
                candidates.append(同步版本(来源: .平台(library.平台), 快照: current))
            }
        }

        let local = session.本地[key]
        let localPending = session.待推送[key] != nil
        let platformsKnowIt = session.平台.values.contains { $0.记录[key] != nil }
            || session.基线.values.contains { $0.快照[key] != nil }
        if localPending || (local != nil && !platformsKnowIt) {
            candidates.append(同步版本(来源: .本地, 快照: local.map(快照)))
        } else if hasNewAccountVersion {
            // 新账户要和资料库现有的内容比较，而不只是和改动比较
            if let local {
                candidates.append(同步版本(来源: .本地, 快照: 快照(local)))
            } else {
                for library in session.可导入平台库 where !newPlatforms.contains(library.平台) {
                    if let current = library.记录[key]?.快照,
                       !candidates.contains(where: { $0.来源 == .平台(library.平台) }) {
                        candidates.append(同步版本(来源: .平台(library.平台), 快照: current))
                    }
                }
            }
        }
        return candidates
    }

    /// 所有版本一致时返回字段最全的那个。
    private static func 一致的版本(_ candidates: [同步版本]) -> 同步版本? {
        for i in candidates.indices {
            for j in candidates.indices where j > i {
                switch (candidates[i].快照, candidates[j].快照) {
                case (nil, nil):
                    continue
                case let (a?, b?) where 同步快照.一致(a, candidates[i].来源.能力, b, candidates[j].来源.能力):
                    continue
                default:
                    return nil
                }
            }
        }
        return candidates.min { $0.来源.优先级 < $1.来源.优先级 }
    }

    /// 资料库大量减少时用户已经统一选过处理方式，相应的删除不再逐项询问。
    private static func 删除处理(_ candidates: [同步版本], session: 同步会话) -> 合并结果? {
        let accepted = candidates.allSatisfy { version in
            guard version.快照 == nil, case let .平台(platform) = version.来源 else { return false }
            return session.减少处理[platform] == .同样删除
        }
        return accepted ? .删除 : nil
    }

    /// 选择“保留并重新上传”时，该平台的删除视为没有发生。
    static func 忽略保留平台的删除(_ session: inout 同步会话) {
        let keep = Set(session.减少处理.filter { $0.value == .保留并重新上传 }.map(\.key))
        guard !keep.isEmpty else { return }
        for platform in keep {
            guard var base = session.基线[platform], let library = session.平台[platform] else { continue }
            // 基线里去掉平台上已经没有的作品，它们就会作为“平台上缺少”重新上传
            base.快照 = base.快照.filter { library.记录[$0.key] != nil }
            session.基线[platform] = base
        }
    }

    /// 用户在冲突里选定版本后写入结果。
    static func 应用冲突选择(_ session: inout 同步会话) {
        for conflict in session.冲突 {
            guard let choice = conflict.选择,
                  let version = conflict.版本.first(where: { $0.来源 == choice }) else { continue }
            session.结果[conflict.键] = version.快照.map { .保留(补全($0, from: choice, key: conflict.键, session: session)) } ?? .删除
        }
    }

    /// 来源不支持的字段（例如 Annict 没有评分和进度）用资料库现有的值补上。
    /// 采用的版本缺少的评分、进度（来源不支持，或者来源没有记录），用资料库和其他来源已有的值补上，不清空。
    private static func 补全(_ value: 同步快照, from source: 同步来源, key: String, session: 同步会话) -> 同步快照 {
        let ability = source.能力
        guard ability.评分步长 == nil || !ability.支持进度 || value.评分 == nil || value.进度 == nil else { return value }
        var others: [(同步快照, 同步能力)] = []
        if let local = session.本地[key] { others.append((快照(local), .本地)) }
        for library in session.可导入平台库 {
            if let record = library.记录[key], 进度可比(record, key: key, session: session) {
                others.append((record.快照, library.平台.同步能力))
            }
        }
        var result = value
        if ability.评分步长 == nil || value.评分 == nil,
           let score = others.first(where: { $0.1.评分步长 != nil && $0.0.评分 != nil })?.0.评分 {
            result.评分 = score
        }
        if !ability.支持进度 || value.进度 == nil,
           let progress = others.first(where: { $0.1.支持进度 && $0.0.进度 != nil })?.0.进度 {
            result.进度 = progress
        }
        return result
    }

    /// 各平台对一部作品的集数（话数）划分可能不同：MAL 一季 16 集、Bangumi 分成两个 8 集的条目；剧场版 MAL 分上下篇、
    /// Bangumi 算一集。总数和作品不一样的平台，进度不能和其他来源互相比较、互相写入，否则每次同步都会出现冲突。
    /// 作品的总数以 MAL、AniList 为准，没有时用资料库里的。
    static func 进度可比(_ record: 平台资料库记录, key: String, session: 同步会话) -> Bool {
        guard let total = record.总数, total > 0 else { return true }
        let reference = [资料库平台.myAnimeList, .aniList].lazy
            .compactMap { session.平台[$0]?.记录[key]?.总数 }
            .first { $0 > 0 } ?? session.本地[key]?.总数
        guard let reference, reference > 0 else { return true }
        return reference == total
    }

    private static func 记录(of source: 同步来源, key: String, session: 同步会话) -> 同步快照? {
        switch source {
        case .本地: session.本地[key].map(快照)
        case let .平台(platform): session.平台[platform]?.记录[key]?.快照
        }
    }

    static func 最佳记录(key: String, session: 同步会话) -> 平台资料库记录? {
        session.平台.values
            .sorted { 同步来源.平台($0.平台).优先级 < 同步来源.平台($1.平台).优先级 }
            .lazy
            .compactMap { $0.记录[key] }
            .first
    }

    private static func 标题(key: String, session: 同步会话) -> String {
        session.本地[key]?.标题 ?? 最佳记录(key: key, session: session)?.标题 ?? key
    }

    /// 各来源的标题合在一起：AniList 的原名带语言信息，排在最前。
    static func 多语言标题(key: String, session: 同步会话) -> [用户多语言标题] {
        let order: [资料库平台] = [.aniList, .myAnimeList, .bangumi, .annict]
        var lists = order.compactMap { session.平台[$0]?.记录[key]?.多语言标题 }.filter { !$0.isEmpty }
        if let local = session.本地[key]?.多语言标题 {
            if lists.isEmpty {
                lists.append(local)
            } else {
                // 平台上有标题时原名只用平台的：资料库里存的原名可能是旧版本按文字猜出来的语言。
                // 其他语言的标题保留下来：这次没读到的平台（没登录、设为“无”）带来的标题，例如 Bangumi 的中文名，不能因此丢掉
                let languages = Set(lists.joined().map(\.lang))
                lists.append(local.filter { !$0.main && !languages.contains($0.lang) })
            }
        }
        return 作品多语言标题.合并(lists)
    }

    private static func 封面(key: String, session: 同步会话) -> String? {
        session.本地[key]?.封面地址 ?? 最佳记录(key: key, session: session)?.封面地址
    }

    // MARK: 第四步：推送计划与新的资料库

    /// 合并后的资料库（只含动画、漫画、轻小说）。没有结果的作品保持不变。
    static func 新资料库(_ session: 同步会话) -> [String: 本地资料库条目] {
        var library = session.本地
        var changedBySync: Set<String> = []
        for (key, result) in session.结果 {
            switch result {
            case .删除:
                library[key] = nil
            case let .保留(value):
                var entry = library[key] ?? 新条目(key: key, session: session)
                if library[key] == nil || 快照(entry) != value { changedBySync.insert(key) }
                entry.状态 = value.状态
                // 结果里没有的评分、进度表示没有记录，不清空资料库里已有的值
                entry.评分 = value.评分 ?? entry.评分
                entry.进度 = value.进度 ?? entry.进度
                library[key] = entry
            }
        }
        let firstImport = !session.新账户平台.isEmpty
        let timeSource = session.修改时间来源 ?? (session.可选修改时间来源.count == 1 ? session.可选修改时间来源.first : nil)
        // 分别保留时，其他账户中多出的作品在资料库中隐藏
        for key in session.新隐藏.keys { library[key] = nil }
        // 平台记录里的元数据（标题、封面、总数、各平台 ID）也更新进来
        for key in library.keys {
            guard var entry = library[key] else { continue }
            for platform in 资料库平台.动画漫画平台 {
                if let record = session.平台[platform]?.记录[key] {
                    entry.平台ID[platform] = record.平台ID
                }
            }
            let titles = 多语言标题(key: key, session: session)
            if !titles.isEmpty { entry.多语言标题 = titles }
            if let best = 最佳记录(key: key, session: session) {
                entry.标题 = best.标题
                entry.封面地址 = best.封面地址 ?? entry.封面地址
                entry.总数 = best.总数 ?? entry.总数
                entry.平均评分 = best.平均评分 ?? entry.平均评分
                entry.发行日期 = best.发行日期 ?? entry.发行日期
                entry.开始日期 = best.开始日期 ?? entry.开始日期
                entry.完成日期 = best.完成日期 ?? entry.完成日期
            }
            // 更改时间：第一次导入按用户选择的平台；之后同步过来的更改用平台记录的时间
            if firstImport, let timeSource, let time = session.平台[timeSource]?.记录[key]?.修改时间 {
                entry.修改时间 = time
            } else if changedBySync.contains(key) || entry.修改时间 == nil {
                entry.修改时间 = 最新修改时间(key: key, session: session) ?? entry.修改时间 ?? .now
            }
            library[key] = entry
        }
        return library
    }

    private static func 最新修改时间(key: String, session: 同步会话) -> Date? {
        session.平台.values.compactMap { $0.记录[key]?.修改时间 }.max()
    }

    /// 隐藏的作品没有本地记录时，用平台记录生成一条，重新显示时加回资料库。
    static func 隐藏条目(key: String, session: 同步会话) -> 本地资料库条目? {
        guard let record = 最佳记录(key: key, session: session) else { return nil }
        var entry = 新条目(key: key, session: session)
        entry.状态 = record.快照.状态
        entry.评分 = record.快照.评分
        entry.进度 = record.快照.进度
        entry.封面地址 = record.封面地址
        entry.总数 = record.总数
        entry.日文标题 = record.日文标题
        entry.多语言标题 = 多语言标题(key: key, session: session)
        for platform in 资料库平台.动画漫画平台 {
            if let value = session.平台[platform]?.记录[key] { entry.平台ID[platform] = value.平台ID }
        }
        return entry
    }

    private static func 新条目(key: String, session: 同步会话) -> 本地资料库条目 {
        let record = 最佳记录(key: key, session: session)
        return 本地资料库条目(
            id: key,
            类型: record?.类型 ?? .anime,
            平台ID: [:],
            标题: record?.标题 ?? key,
            加入时间: .now
        )
    }

    /// 让每个平台和新的资料库一致需要的修改。
    static func 生成推送(_ session: inout 同步会话) {
        let library = 新资料库(session)
        var operations: [推送操作] = []
        var cannotDelete: [资料库平台: [String]] = [:]

        for platform in session.平台.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let current = session.平台[platform] else { continue }
            let ability = platform.同步能力
            // 只导入的平台（Bangumi，或用户设为“仅导入”）不写入；它的基线保持平台上原来的值，资料库后来的修改不会被当成平台上的更改
            guard session.可导出(platform) else { continue }
            let keys = Set(library.keys).union(current.记录.keys)
            for key in keys.sorted() where session.新隐藏[key] == nil {
                let entry = library[key]
                let record = current.记录[key]
                let type = entry?.类型 ?? record?.类型 ?? .anime
                guard ability.支持的类型.contains(type) else { continue }

                switch (entry, record) {
                case let (_, record?) where record.附属 == true:
                    // 平台上只有这部作品的附属条目（例如只看过特别篇）：不写入附属条目，也不另外添加主条目
                    continue
                case let (entry?, record?):
                    var target = 写入目标(entry, 现有: record.快照, ability: ability)
                    // 集数划分不同的平台不写进度，保留平台上原来的
                    if !进度可比(record, key: key, session: session) { target.进度 = record.快照.进度 }
                    // TMDB 记录不了这个值（不是“计划观看”又没有评分）：从想看列表移除
                    guard ability.可记录(target) else {
                        operations.append(操作(platform, key, .删除, entry: nil, record: record, target: nil))
                        continue
                    }
                    if !同步快照.一致(target, .本地, record.快照, ability) || 需要补满进度(entry, record, platform: platform) {
                        operations.append(操作(platform, key, .修改, entry: entry, record: record, target: target))
                    }
                case let (entry?, nil):
                    let target = 写入目标(entry, 现有: nil, ability: ability)
                    guard ability.可记录(target) else { continue }
                    operations.append(操作(platform, key, .新增, entry: entry, record: nil, target: target))
                case let (nil, record?):
                    // 资料库没有这部作品：只有结果明确是删除的才删
                    guard session.结果[key] == .删除 else { continue }
                    guard ability.支持删除 else {
                        cannotDelete[platform, default: []].append(key)
                        continue
                    }
                    operations.append(操作(platform, key, .删除, entry: nil, record: record, target: nil))
                case (nil, nil):
                    continue
                }
            }
        }
        session.推送 = operations
        session.无法删除 = cannotDelete
        // 新账户第一次同步，或者计划删除平台上的作品时，先给用户确认
        // 只为不一致的作品生成操作，平台上已经一致的作品不会重新写入，避免打乱平台上的更改时间
        session.需要确认推送 = !session.新账户平台.isEmpty && (!operations.isEmpty || session.需要选择修改时间来源)
    }

    /// 写到平台上的值：资料库没有记录的评分、进度沿用平台上现有的值，不会被写成 0；
    /// 已看完、已读完而不知道进度时，进度记为总集数（话数）。
    static func 写入目标(_ entry: 本地资料库条目, 现有: 同步快照?, ability: 同步能力) -> 同步快照 {
        var target = 快照(entry)
        if target.评分 == nil { target.评分 = 现有?.评分 }
        if target.进度 == nil { target.进度 = 现有?.进度 }
        if target.状态 == .completed, ability.支持进度, let total = entry.总数, (target.进度 ?? 0) < total {
            target.进度 = total
        }
        return target
    }

    /// MAL、AniList 上标为已看完、进度却没有填满的作品（例如之前同步时被写成了 0 集），把进度补满。
    /// Bangumi 的“看过”本来就常常不记集数，补满要逐集标记，不在这里处理。
    static func 需要补满进度(_ entry: 本地资料库条目, _ record: 平台资料库记录, platform: 资料库平台) -> Bool {
        guard platform == .myAnimeList || platform == .aniList,
              entry.状态 == .completed, record.快照.状态 == .completed,
              let total = entry.总数 ?? record.总数, total > 0 else { return false }
        return (record.快照.进度 ?? 0) < total
    }

    private static func 操作(
        _ platform: 资料库平台,
        _ key: String,
        _ kind: 推送操作.种类,
        entry: 本地资料库条目?,
        record: 平台资料库记录?,
        target: 同步快照?
    ) -> 推送操作 {
        推送操作(
            平台: platform,
            键: key,
            种类: kind,
            类型: entry?.类型 ?? record?.类型 ?? .anime,
            标题: entry?.标题 ?? record?.标题 ?? key,
            日文标题: entry?.日文标题 ?? record?.日文标题,
            malID: entry?.malID ?? record?.malID,
            年份: 年份(entry?.发行日期 ?? record?.发行日期),
            全部标题: entry.map { 全部标题(日文标题: $0.日文标题, 标题: $0.标题, 多语言标题: $0.多语言标题) }
                ?? record.map { 全部标题(日文标题: $0.日文标题, 标题: $0.标题, 多语言标题: $0.多语言标题) } ?? [],
            平台ID: record?.平台ID ?? entry?.平台ID[platform],
            目标: target,
            平台原有日期: 同步日期(开始: record?.开始日期, 完成: record?.完成日期),
            资料库日期: 同步日期(开始: entry?.开始日期, 完成: entry?.完成日期)
        )
    }

    // MARK: 平台自动填写的日期

    /// AniList 新建记录或改成“看过”“在看”时，没有传日期会自动填上当天（MAL 不会）。
    /// 写入后平台上原来没有的日期被填上、又和资料库里的不同，返回要改成的日期（资料库里没有就清除）；不需要修正时返回 nil。
    static func 自动填写后的修正(原有: 同步日期, 保存后: 同步日期, 期望: 同步日期) -> 同步日期? {
        var result = 保存后
        var changed = false
        if 原有.开始 == nil, 保存后.开始 != nil, 保存后.开始 != 期望.开始 {
            result.开始 = 期望.开始
            changed = true
        }
        if 原有.完成 == nil, 保存后.完成 != nil, 保存后.完成 != 期望.完成 {
            result.完成 = 期望.完成
            changed = true
        }
        return changed ? result : nil
    }

    /// 以前同步时 PaperVN 在 AniList 上新建记录，AniList 把开始、完成日期自动填成了新建那天，下一次同步又把这个日期导入了资料库。
    /// 认出这样的日期：
    /// - 日期就是 AniList 上这条记录创建的那天；
    /// - 资料库里早在那之前就有这部作品（记录是 PaperVN 推送过去才新建的）；
    /// - 上次同步时 AniList 上的状态已经和现在相同（创建之后没有在 AniList 上改过状态）；
    /// - 其他平台没有记着同一天。
    /// 返回应有的日期（其他平台记着的日期，没有就为空）；不是自动填写的返回 nil。
    static func AniList自动填写的日期(
        _ record: 平台资料库记录,
        本地 entry: 本地资料库条目,
        基线 base: 同步快照?,
        其他记录 others: [平台资料库记录]
    ) -> 同步日期? {
        guard record.平台 == .aniList, let created = record.创建时间,
              let added = entry.加入时间, added < created.addingTimeInterval(-3600),
              let base, base.状态 == record.快照.状态 else { return nil }
        // AniList 按用户设置的时区记日期，创建时间前后一天都算
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let days = Set((-1...1).compactMap { offset -> String? in
            guard let day = utc.date(byAdding: .day, value: offset, to: created) else { return nil }
            let parts = utc.dateComponents([.year, .month, .day], from: day)
            return 平台账户工具.日期文本(year: parts.year, month: parts.month, day: parts.day)
        })
        func 修正(_ value: String?, 其他: [String?]) -> (自动: Bool, 应有: String?) {
            guard let value, days.contains(value), !其他.contains(value) else { return (false, value) }
            return (true, 其他.compactMap { $0 }.first)
        }
        let start = 修正(record.开始日期, 其他: others.map(\.开始日期))
        let finish = 修正(record.完成日期, 其他: others.map(\.完成日期))
        guard start.自动 || finish.自动 else { return nil }
        return 同步日期(开始: start.应有, 完成: finish.应有)
    }

    /// 推送完成后，各平台新的基线：成功的操作按目标值，失败的保持平台原来的值。
    /// 写入后平台上实际保存的值：评分按平台的精度取整，平台不支持或这次没有写的字段保持原来的值。
    /// 基线要记这个值，否则下次同步读回来时会和基线对不上，被当成平台上的新更改。
    static func 平台保存的值(_ target: 同步快照, 现有: 同步快照?, platform: 资料库平台, type: 作品类型) -> 同步快照 {
        let ability = platform.同步能力
        var value = target
        if let step = ability.评分步长 {
            if let score = target.评分 { value.评分 = 取整步长(score, step) } else { value.评分 = 现有?.评分 }
        } else {
            value.评分 = nil
        }
        if !ability.支持进度 || target.进度 == nil {
            value.进度 = ability.支持进度 ? 现有?.进度 : nil
        }
        // Bangumi 的“看过”不逐集标记，动画的集数保持原样
        if platform == .bangumi, type == .anime, target.状态 == .completed {
            value.进度 = 现有?.进度
        }
        return 同步快照(状态: value.状态, 评分: value.评分, 进度: value.进度)
    }

    private static func 取整步长(_ score: Int, _ step: Int) -> Int {
        Int((Double(score) / Double(step)).rounded()) * step
    }

    static func 新基线(_ session: 同步会话, 失败: Set<String>) -> [资料库平台: 平台基线] {
        var bases: [资料库平台: 平台基线] = [:]
        for (platform, library) in session.平台 {
            var values = library.记录.mapValues(\.快照)
            for operation in session.推送 where operation.平台 == platform && !失败.contains(operation.id) {
                switch operation.种类 {
                case .删除: values[operation.键] = nil
                case .新增, .修改:
                    values[operation.键] = operation.目标.map {
                        平台保存的值($0, 现有: library.记录[operation.键]?.快照, platform: platform, type: operation.类型)
                    }
                }
            }
            // 没找到对应作品的新增没有推送，不进基线
            for key in session.未匹配[platform] ?? [] where library.记录[key] == nil {
                values[key] = nil
            }
            bases[platform] = 平台基线(账户ID: library.账户ID, 账户名称: library.账户名称, 快照: values)
        }
        return bases
    }
}

/// 用户为每个账户选择的同步方式。
nonisolated enum 同步方向: String, CaseIterable, Identifiable, Sendable {
    case 双向
    case 仅导入
    case 仅导出
    case 无

    var id: Self { self }

    var localizedTitle: String {
        switch self {
        case .双向: String(localized: "双向同步")
        case .仅导入: String(localized: "仅导入")
        case .仅导出: String(localized: "仅导出")
        case .无: String(localized: "无")
        }
    }
}

extension 资料库平台 {
    nonisolated static func 同步方向设置键(_ platform: 资料库平台) -> String { "paperVNSyncDirection.\(platform.rawValue)" }

    /// 不能写入的平台（Bangumi）只能“仅导入”或“无”。
    var 可选同步方向: [PaperVN.同步方向] {
        同步能力.支持写入 ? PaperVN.同步方向.allCases : [.仅导入, .无]
    }

    var 默认同步方向: PaperVN.同步方向 { 同步能力.支持写入 ? .双向 : .仅导入 }

    var 同步方向: PaperVN.同步方向 {
        let stored = UserDefaults.standard.string(forKey: Self.同步方向设置键(self)).flatMap(PaperVN.同步方向.init(rawValue:))
        guard let stored, 可选同步方向.contains(stored) else { return 默认同步方向 }
        return stored
    }

    /// 资料库的修改会写入这个平台。
    var 可导出: Bool { 同步能力.支持写入 && (同步方向 == .双向 || 同步方向 == .仅导出) }
}
