import Foundation

/// 本机记录的推荐曝光，按 VNDB 用户分开保存，不上传。
@MainActor
final class 推荐反馈中心 {
    static let shared = 推荐反馈中心()

    private static let 曝光键前缀 = "recommendationExposure.v1."
    /// 超过这个天数没有再展示、也不在冷却中的曝光记录会被清理。
    private static let 曝光保留天数 = 60

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
    }

    func 曝光(userID: String) -> [String: 推荐曝光记录] {
        guard let data = defaults.data(forKey: 曝光键(userID)) else { return [:] }
        return (try? decoder.decode([String: 推荐曝光记录].self, from: data)) ?? [:]
    }

    func 展示排序(
        _ recommendations: [探索推荐],
        userID: String
    ) -> [探索推荐] {
        推荐展示排序.排列(
            recommendations,
            曝光: 曝光(userID: userID),
            种子: userID.lowercased(),
            现在: now(),
            calendar: calendar
        )
    }

    func 记录展示(_ ids: [String], userID: String) {
        guard !ids.isEmpty, !userID.isEmpty else { return }
        var exposure = 曝光(userID: userID)
        推荐展示排序.记录展示(ids, 曝光: &exposure, 现在: now(), calendar: calendar)
        保存(清理过期曝光(exposure), userID: userID)
    }

    func 记录打开(_ id: String, userID: String) {
        guard !userID.isEmpty else { return }
        var exposure = 曝光(userID: userID)
        推荐展示排序.记录打开(id, 曝光: &exposure)
        保存(exposure, userID: userID)
    }

    private func 清理过期曝光(
        _ exposure: [String: 推荐曝光记录]
    ) -> [String: 推荐曝光记录] {
        let current = now()
        let today = 推荐展示排序.日序号(current, calendar: calendar)
        return exposure.filter { _, record in
            if let cooldown = record.冷却截止, current < cooldown { return true }
            guard let lastShown = record.最近展示日 else { return false }
            return today - lastShown <= Self.曝光保留天数
        }
    }

    private func 曝光键(_ userID: String) -> String {
        Self.曝光键前缀 + userID.lowercased()
    }

    private func 保存(_ exposure: [String: 推荐曝光记录], userID: String) {
        guard let data = try? encoder.encode(exposure) else { return }
        defaults.set(data, forKey: 曝光键(userID))
    }
}
