import Foundation
import Testing

@testable import PaperVN

@MainActor
@Suite
struct 推荐展示排序Tests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    @Test
    func 连续展示五天没有打开会冷却两周() {
        var exposure: [String: 推荐曝光记录] = [:]
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<推荐展示排序.冷却前最多展示天数 {
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            推荐展示排序.记录展示(["v1"], 曝光: &exposure, 现在: date, calendar: calendar)
            // 同一天重复展示只计一次。
            推荐展示排序.记录展示(["v1"], 曝光: &exposure, 现在: date, calendar: calendar)
        }

        let lastDay = calendar.date(
            byAdding: .day,
            value: 推荐展示排序.冷却前最多展示天数 - 1,
            to: start
        )!
        func hidden(after days: Int) -> Bool {
            推荐展示排序.是否隐藏(
                "v1",
                曝光: exposure,
                现在: calendar.date(byAdding: .day, value: days, to: lastDay)!,
                calendar: calendar
            )
        }

        #expect(!hidden(after: 0))
        #expect(hidden(after: 1))
        #expect(hidden(after: 14))
        #expect(!hidden(after: 15))
    }

    @Test
    func 当天记录的展示不会改变当天的顺序() throws {
        let recommendations = try (0..<20).map {
            try recommendation(id: "v\($0)", score: 0.40 - Double($0) * 0.01)
        }
        let morning = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
            .addingTimeInterval(9 * 3_600)
        var exposure = (0..<20).reduce(into: [String: 推荐曝光记录]()) { result, index in
            result["v\(index)"] = 推荐曝光记录(未打开展示天数: 4, 最近展示日: nil, 冷却截止: nil)
        }
        func order(at date: Date) -> [String] {
            推荐展示排序.排列(
                recommendations,
                曝光: exposure,
                种子: "u1",
                现在: date,
                calendar: calendar
            ).map(\.id)
        }

        let before = order(at: morning)
        推荐展示排序.记录展示(Array(before.prefix(12)), 曝光: &exposure, 现在: morning, calendar: calendar)
        let after = order(at: morning.addingTimeInterval(10 * 3_600))

        #expect(before == after)
    }

    @Test
    func 打开过的推荐不会继续累计未打开天数() {
        var exposure: [String: 推荐曝光记录] = [:]
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for day in 0..<4 {
            let date = calendar.date(byAdding: .day, value: day, to: start)!
            推荐展示排序.记录展示(["v1"], 曝光: &exposure, 现在: date, calendar: calendar)
        }
        推荐展示排序.记录打开("v1", 曝光: &exposure)
        let nextDay = calendar.date(byAdding: .day, value: 4, to: start)!
        推荐展示排序.记录展示(["v1"], 曝光: &exposure, 现在: nextDay, calendar: calendar)

        #expect(exposure["v1"]?.未打开展示天数 == 1)
        #expect(exposure["v1"]?.冷却截止 == nil)
    }

    @Test
    func 同一天顺序不变而前两名之外每天重新抽样() throws {
        let recommendations = try (0..<30).map {
            try recommendation(id: "v\($0)", score: 0.40 - Double($0) * 0.005)
        }
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        func order(on day: Int, hour: Int = 9) -> [String] {
            let date = calendar.date(
                byAdding: DateComponents(day: day, hour: hour),
                to: start
            )!
            return 推荐展示排序.排列(
                recommendations,
                曝光: [:],
                种子: "u1",
                现在: date,
                calendar: calendar
            ).map(\.id)
        }

        #expect(order(on: 0, hour: 9) == order(on: 0, hour: 21))
        #expect(Array(order(on: 0).prefix(2)) == ["v0", "v1"])
        let visibleSets = Set((0..<7).map { Set(order(on: $0).prefix(12)) })
        #expect(visibleSets.count > 1)
        #expect(order(on: 0).count == recommendations.count)
    }

    @Test
    func 未打开的推荐每天降权() throws {
        let fresh = try recommendation(id: "v-fresh", score: 0.30)
        let repeated = try recommendation(id: "v-repeated", score: 0.33)
        let exposure = ["v-repeated": 推荐曝光记录(未打开展示天数: 3, 最近展示日: nil, 冷却截止: nil)]

        let order = 推荐展示排序.排列(
            [repeated, fresh],
            曝光: exposure,
            种子: "u1",
            现在: Date(timeIntervalSince1970: 1_800_000_000),
            calendar: calendar
        ).map(\.id)

        #expect(order == ["v-fresh", "v-repeated"])
    }

    @Test
    func 曝光记录按用户分开保存() {
        let suiteName = "PaperVN-RecommendationExposure-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let center = 推荐反馈中心(
            defaults: defaults,
            calendar: calendar,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )

        center.记录展示(["v1", "v2"], userID: "U1")

        #expect(center.曝光(userID: "u1")["v1"]?.未打开展示天数 == 1)
        #expect(center.曝光(userID: "u2").isEmpty)
    }

    private func recommendation(id: String, score: Double) throws -> 探索推荐 {
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "title": id])
        return 探索推荐(
            visualNovel: try JSONDecoder().decode(探索视觉小说.self, from: data),
            score: score,
            reason: .highlyRated
        )
    }
}
