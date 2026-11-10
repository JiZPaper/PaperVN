import Foundation
import OSLog

/// 在 PaperVN 中运行视觉小说的时间，作为游玩路径传入 Paper账户（来源显示为 PaperVN）。
/// 只在登录了 Paper账户时记录；上传失败的留在本机，下次运行或启动时重试。
@MainActor
final class 视觉小说游玩记录 {
    static let shared = 视觉小说游玩记录()

    private static let logger = Logger(subsystem: "com.jizpaper.PaperVN", category: "PlayHistory")
    /// 太短的多半是误触，不记录（和服务器一样一段最长 72 小时）
    private static let 最短秒数: TimeInterval = 60
    private static let 最长秒数: TimeInterval = 72 * 3600

    nonisolated struct 待上传: Codable, Sendable {
        var accountID: String
        var vn: String
        var startedAt: Date
        var endedAt: Date
    }

    private static let 不再重试的错误: Set<String> = [
        "invalid_sessions", "invalid_session", "invalid_vn", "invalid_time", "invalid_range", "session_too_long",
    ]

    private var 当前: (vn: String, accountID: String, 开始: Date)?
    private var 队列: [待上传] = []
    private var 正在上传 = false

    private init() {
        if let data = try? Data(contentsOf: Self.队列地址),
           let value = try? JSONDecoder().decode([待上传].self, from: data) {
            队列 = value
        }
    }

    func 开始(作品 vnID: String) {
        结束()
        guard let accountID = PaperAccount账户.shared.资料?.id, vnID.lowercased().hasPrefix("v") else { return }
        当前 = (vnID.lowercased(), accountID, .now)
    }

    /// 离开游戏、进入后台时调用。
    func 结束() {
        guard let current = 当前 else { return }
        当前 = nil
        var start = current.开始
        let end = Date.now
        guard end.timeIntervalSince(start) >= Self.最短秒数 else { return }
        while start < end {
            let segmentEnd = min(end, start.addingTimeInterval(Self.最长秒数))
            队列.append(待上传(accountID: current.accountID, vn: current.vn, startedAt: start, endedAt: segmentEnd))
            start = segmentEnd
        }
        保存()
        Task { await 上传() }
    }

    func 上传() async {
        let account = PaperAccount账户.shared
        guard !正在上传, let accountID = account.资料?.id else { return }
        // 换了账户：之前账户没传上去的不再传，也不留在本机
        if 队列.contains(where: { $0.accountID != accountID }) {
            队列.removeAll { $0.accountID != accountID }
            保存()
        }
        // 服务器一次最多收 500 段
        let pending = Array(队列.prefix(500))
        guard !pending.isEmpty else { return }
        正在上传 = true
        defer { 正在上传 = false }
        do {
            try await account.上传游玩路径(pending.map { ($0.vn, $0.startedAt, $0.endedAt) })
            队列.removeAll { item in
                pending.contains { $0.accountID == item.accountID && $0.vn == item.vn && $0.startedAt == item.startedAt }
            }
            保存()
            await 游玩路径中心.shared.刷新(强制: true)
        } catch let error as PaperAccount错误 where error.code.map(Self.不再重试的错误.contains) == true {
            // 服务器认为这批数据本身不合格（例如设备时间不对），重发也不会成功，丢掉以免一直卡住
            队列.removeAll { item in
                pending.contains { $0.accountID == item.accountID && $0.vn == item.vn && $0.startedAt == item.startedAt }
            }
            保存()
            Self.logger.error("Play history rejected: \(error.localizedDescription, privacy: .public)")
        } catch {
            Self.logger.error("Play history upload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func 保存() {
        let url = Self.队列地址
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(队列) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private static var 队列地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "视觉小说运行", directoryHint: .isDirectory)
            .appending(path: "待上传游玩路径.json")
    }
}
