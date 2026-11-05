import Combine
import Foundation

/// 游玩路径：用户什么时候玩了哪部视觉小说。由第三方模拟器或管理软件登录 Paper账户后通过 Hiro API 传入，
/// 在 PaperVN 中运行视觉小说的时间也会传入（`视觉小说游玩记录`）。只保存在 Paper账户中；手动更改由传入数据的 App 负责。
/// 服务器在 deploy/vps/papervn-account.mjs，字段名两边保持一致。
nonisolated struct 游玩时间段: Codable, Identifiable, Hashable, Sendable {
    nonisolated struct 来源: Codable, Hashable, Sendable {
        let id: String
        let name: String
    }

    let id: String
    let vn: String
    let startedAt: Date
    let endedAt: Date
    let client: 来源
}

/// 登录了 Paper账户并可以传入游玩路径的 App。
nonisolated struct 已授权App: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let connectedAt: Date
    let lastUsedAt: Date
}

nonisolated struct 游玩路径内容: Codable, Sendable {
    var sessions: [游玩时间段]
    var apps: [已授权App]
}

nonisolated enum 游玩路径周期: String, CaseIterable, Identifiable, Sendable {
    case 日, 周, 月, 年

    var id: Self { self }

    var 日历单位: Calendar.Component {
        switch self {
        case .日: .day
        case .周: .weekOfYear
        case .月: .month
        case .年: .year
        }
    }

    /// 图表每根柱子代表的长度。
    var 分桶单位: Calendar.Component {
        switch self {
        case .日: .hour
        case .周, .月: .day
        case .年: .month
        }
    }
}

nonisolated enum 游玩路径统计 {
    nonisolated struct 时长分桶: Identifiable, Hashable, Sendable {
        let 开始: Date
        let 秒数: TimeInterval
        var id: Date { 开始 }
    }

    /// 一天之内的一段，用于按时刻排列的图表。跨过午夜的时间段会拆成两段。
    nonisolated struct 当日时段: Identifiable, Hashable, Sendable {
        let 日期: Date
        let 开始小时: Double
        let 结束小时: Double
        var id: String { "\(日期.timeIntervalSince1970)-\(开始小时)" }
    }

    /// 合并重叠的时间段。两个 App 同时记录、或同一段被传了两次都不会重复计算（和服务器的 playTotalSeconds 一致）。
    static func 合并区间(_ sessions: [游玩时间段]) -> [DateInterval] {
        var result: [DateInterval] = []
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) where session.endedAt > session.startedAt {
            if let last = result.last, session.startedAt <= last.end {
                if session.endedAt > last.end {
                    result[result.count - 1] = DateInterval(start: last.start, end: session.endedAt)
                }
            } else {
                result.append(DateInterval(start: session.startedAt, end: session.endedAt))
            }
        }
        return result
    }

    static func 总秒数(_ sessions: [游玩时间段]) -> TimeInterval {
        合并区间(sessions).reduce(0) { $0 + $1.duration }
    }

    /// 范围内的总时长，跨出范围的部分不计。
    static func 总秒数(_ sessions: [游玩时间段], 范围 range: DateInterval) -> TimeInterval {
        合并区间(sessions).reduce(0) { $0 + ($1.intersection(with: range)?.duration ?? 0) }
    }

    /// 把范围分成等长的桶（按日历），每桶的游玩秒数。没有玩的桶也会返回，秒数为 0。
    static func 分桶(
        _ sessions: [游玩时间段],
        范围 range: DateInterval,
        单位 unit: Calendar.Component,
        日历 calendar: Calendar
    ) -> [时长分桶] {
        let merged = 合并区间(sessions)
        var result: [时长分桶] = []
        var start = range.start
        while start < range.end {
            guard let next = calendar.date(byAdding: unit, value: 1, to: start), next > start else { break }
            let bucket = DateInterval(start: start, end: min(next, range.end))
            let seconds = merged.reduce(0) { $0 + ($1.intersection(with: bucket)?.duration ?? 0) }
            result.append(.init(开始: start, 秒数: seconds))
            start = next
        }
        return result
    }

    static func 时段(
        _ sessions: [游玩时间段],
        范围 range: DateInterval,
        日历 calendar: Calendar
    ) -> [当日时段] {
        var result: [当日时段] = []
        for interval in 合并区间(sessions) {
            guard let clipped = interval.intersection(with: range), clipped.duration > 0 else { continue }
            var start = clipped.start
            while start < clipped.end {
                let day = calendar.startOfDay(for: start)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let end = min(clipped.end, nextDay)
                result.append(.init(
                    日期: day,
                    开始小时: start.timeIntervalSince(day) / 3600,
                    结束小时: end.timeIntervalSince(day) / 3600
                ))
                start = end
            }
        }
        return result
    }

    /// 周期内玩过的作品，时长从多到少。
    static func 作品排行(_ sessions: [游玩时间段], 范围 range: DateInterval) -> [(vn: String, 秒数: TimeInterval)] {
        Dictionary(grouping: sessions, by: \.vn)
            .map { (vn: $0.key, 秒数: 总秒数($0.value, 范围: range)) }
            .filter { $0.秒数 > 0 }
            .sorted { $0.秒数 != $1.秒数 ? $0.秒数 > $1.秒数 : $0.vn < $1.vn }
    }

    /// 图表纵轴的文字，只用一种单位免得占太宽。0 不带单位。
    static func 刻度文本(_ seconds: TimeInterval, 单位 unit: NSCalendar.Unit) -> String {
        guard seconds > 0 else { return "0" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = unit
        return 中西文间距.去除空格(formatter.string(from: seconds) ?? "")
    }

    /// “1小时37分钟”。不满一分钟时显示秒，中日文与数字之间不留空格。
    static func 时长文本(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds < 60 ? [.second] : [.hour, .minute]
        formatter.zeroFormattingBehavior = seconds < 60 ? [.pad] : [.dropAll]
        return 中西文间距.去除空格(formatter.string(from: seconds.rounded()) ?? "")
    }
}

/// 读取并缓存当前账户的游玩路径。缓存放在设备上，打开页面时不用等网络；退出登录时删除。
@MainActor
final class 游玩路径中心: ObservableObject {
    static let shared = 游玩路径中心()

    @Published private(set) var 内容 = 游玩路径内容(sessions: [], apps: [])
    /// 已经有过缓存或读取过一次。在这之前不显示“没有数据”的提示，免得一闪而过。
    @Published private(set) var 已加载 = false
    @Published private(set) var 错误: String?

    private var 当前账户: String?
    private var 上次刷新: Date?
    private var 刷新任务: Task<Void, Never>?
    private let 刷新间隔: TimeInterval = 60

    private init() {}

    var 时间段: [游玩时间段] { 内容.sessions }
    var 已授权: [已授权App] { 内容.apps }

    /// 登录了 Paper账户，并且有 App 已连接或传入过数据。否则显示提示，告诉用户去哪里传入。
    var 有数据来源: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PlayHistorySample") { return true }
        #endif
        return PaperAccount账户.shared.isLoggedIn && (!内容.apps.isEmpty || !内容.sessions.isEmpty)
    }

    func 时间段(作品 vnID: String) -> [游玩时间段] {
        内容.sessions.filter { $0.vn == vnID }
    }

    func 刷新(强制: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-PlayHistorySample") {
            内容 = Self.示例内容()
            已加载 = true
            return
        }
        #endif
        let account = PaperAccount账户.shared
        guard let accountID = account.资料?.id else {
            清除()
            return
        }
        if 当前账户 != accountID { 加载缓存(accountID) }
        if !强制, let 上次刷新, Date.now.timeIntervalSince(上次刷新) < 刷新间隔 { return }
        if let 刷新任务 {
            await 刷新任务.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let value = try await account.读取游玩路径()
                guard account.资料?.id == accountID else { return }
                self.内容 = value
                self.上次刷新 = .now
                self.错误 = nil
                self.已加载 = true
                self.保存缓存(value, accountID)
            } catch {
                self.错误 = error.localizedDescription
            }
        }
        刷新任务 = task
        await task.value
        刷新任务 = nil
    }

    func 移除App(_ app: 已授权App) async throws {
        内容.apps = try await PaperAccount账户.shared.移除已授权App(app.id)
        if let accountID = PaperAccount账户.shared.资料?.id { 保存缓存(内容, accountID) }
    }

    /// 退出登录后不留下上一个账户的数据。
    func 清除() {
        if let 当前账户 { try? FileManager.default.removeItem(at: Self.缓存地址(当前账户)) }
        当前账户 = nil
        上次刷新 = nil
        内容 = 游玩路径内容(sessions: [], apps: [])
        错误 = nil
        已加载 = false
    }

    private func 加载缓存(_ accountID: String) {
        当前账户 = accountID
        上次刷新 = nil
        if let data = try? Data(contentsOf: Self.缓存地址(accountID)),
           let value = try? JSONDecoder().decode(游玩路径内容.self, from: data) {
            内容 = value
            已加载 = true
        } else {
            内容 = 游玩路径内容(sessions: [], apps: [])
            已加载 = false
        }
    }

    private func 保存缓存(_ value: 游玩路径内容, _ accountID: String) {
        let url = Self.缓存地址(accountID)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func 缓存地址(_ accountID: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: "游玩路径", directoryHint: .isDirectory)
            .appending(path: "\(accountID).json")
    }

    #if DEBUG
    /// 预览用的示例数据（只在 Debug 构建、带 `-PlayHistorySample` 启动参数时使用）。
    private static func 示例内容() -> 游玩路径内容 {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let client = 游玩时间段.来源(id: "com.example.emulator", name: "Example Emulator")
        var sessions: [游玩时间段] = []
        for offset in 0..<70 where offset % 3 != 2 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let start = day.addingTimeInterval(TimeInterval(19 * 3600 + (offset * 37 % 180) * 60))
            let length = TimeInterval(1800 + (offset * 53 % 150) * 60)
            sessions.append(.init(
                id: UUID().uuidString, vn: offset % 4 == 0 ? "v2002" : "v17",
                startedAt: start, endedAt: min(start.addingTimeInterval(length), offset == 0 ? .now : .distantFuture), client: client
            ))
        }
        let app = 已授权App(id: client.id, name: client.name, connectedAt: today, lastUsedAt: today)
        return 游玩路径内容(sessions: sessions.filter { $0.endedAt > $0.startedAt }, apps: [app])
    }
    #endif
}
