import Foundation
import Testing
@testable import PaperVN

/// 游玩路径的统计：重叠的时间段不重复计算，跨过午夜和周期边界的时间段正确拆开。
@Suite
struct 游玩路径统计Tests {
    private var 日历: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func 时间(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        日历.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func 段(_ start: Date, _ end: Date, vn: String = "v17") -> 游玩时间段 {
        .init(id: UUID().uuidString, vn: vn, startedAt: start, endedAt: end, client: .init(id: "a", name: "A"))
    }

    @Test func 重叠和重复的时间段只算一次() {
        let sessions = [
            段(时间(1, 10), 时间(1, 11)),
            段(时间(1, 10, 30), 时间(1, 12)),
            段(时间(1, 10, 40), 时间(1, 10, 50)),
            段(时间(1, 14), 时间(1, 15)),
            段(时间(1, 14), 时间(1, 15)),
        ]
        #expect(游玩路径统计.总秒数(sessions) == 3 * 3600)
    }

    @Test func 范围外的部分不计入() {
        let sessions = [段(时间(1, 23), 时间(2, 1))]
        let day = 日历.dateInterval(of: .day, for: 时间(2, 12))!
        #expect(游玩路径统计.总秒数(sessions, 范围: day) == 3600)
    }

    @Test func 分桶包含没有玩的日期() {
        let sessions = [段(时间(2, 23), 时间(3, 1))]
        let week = DateInterval(start: 时间(2, 0), end: 时间(5, 0))
        let buckets = 游玩路径统计.分桶(sessions, 范围: week, 单位: .day, 日历: 日历)
        #expect(buckets.map(\.秒数) == [3600, 3600, 0])
    }

    @Test func 跨过午夜的时段拆成两段() {
        let sessions = [段(时间(2, 23), 时间(3, 1, 30))]
        let range = DateInterval(start: 时间(2, 0), end: 时间(9, 0))
        let segments = 游玩路径统计.时段(sessions, 范围: range, 日历: 日历)
        #expect(segments.count == 2)
        #expect(segments[0].开始小时 == 23 && segments[0].结束小时 == 24)
        #expect(segments[1].日期 == 时间(3, 0) && segments[1].结束小时 == 1.5)
    }

    @Test func 作品按时长排行() {
        let range = DateInterval(start: 时间(1, 0), end: 时间(8, 0))
        let ranking = 游玩路径统计.作品排行([
            段(时间(1, 10), 时间(1, 11), vn: "v1"),
            段(时间(2, 10), 时间(2, 13), vn: "v2"),
            段(时间(9, 10), 时间(9, 20), vn: "v3"),
        ], 范围: range)
        #expect(ranking.map(\.vn) == ["v2", "v1"])
    }

    @Test func 服务器响应可以解码() throws {
        let json = #"{"id":"x","vn":"v17","startedAt":"2026-11-03T12:15:30.000Z","endedAt":"2026-11-03T13:47:02.000Z","client":{"id":"a","name":"A"},"createdAt":"2026-11-03T13:47:05.120Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text)!
        }
        let session = try decoder.decode(游玩时间段.self, from: Data(json.utf8))
        #expect(session.endedAt.timeIntervalSince(session.startedAt) == 5492)
    }
}
