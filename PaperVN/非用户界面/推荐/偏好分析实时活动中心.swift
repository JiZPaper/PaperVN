@preconcurrency import ActivityKit
import OSLog
import UIKit

@MainActor
final class 偏好分析实时活动中心 {
    static let shared = 偏好分析实时活动中心()

    private static let logger = Logger(
        subsystem: "com.jizpaper.PaperVN",
        category: "PreferenceAnalysisLiveActivity"
    )

    private var activity: Activity<偏好分析实时活动属性>?
    private var latestState = 偏好分析实时活动属性.ContentState(
        completedRequestCount: 0,
        totalRequestCount: 1,
        phase: .analyzing
    )
    private var lastPublishedRequestCount = -1
    private var lastPublishedAt = Date.distantPast

    private init() {}

    func 开始(totalRequestCount: Int) {
        latestState = .init(
            completedRequestCount: 0,
            totalRequestCount: max(totalRequestCount, 1),
            phase: .analyzing
        )
        lastPublishedRequestCount = -1
        lastPublishedAt = .distantPast

        if let existing = 当前活动() {
            activity = existing
            发布(latestState, to: existing)
            return
        }

        guard UIApplication.shared.applicationState == .active else {
            Self.logger.info(
                "Skipped creating preference analysis Live Activity because the app is not active"
            )
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.logger.error(
                "Preference analysis Live Activity is disabled by the user or system"
            )
            return
        }

        do {
            let content = ActivityContent(
                state: latestState,
                staleDate: nil
            )
            activity = try Activity.request(
                attributes: 偏好分析实时活动属性(startedAt: .now),
                content: content,
                pushType: nil
            )
            lastPublishedRequestCount = 0
            lastPublishedAt = .now
            Self.logger.info("Preference analysis Live Activity started")
        } catch {
            Self.logger.error(
                "Preference analysis Live Activity failed to start: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func 更新(completed: Int, total: Int) {
        let total = max(total, 1)
        let completed = min(max(completed, 0), total)
        latestState = .init(
            completedRequestCount: completed,
            totalRequestCount: total,
            phase: .analyzing
        )

        guard let activity = 当前活动() else { return }
        self.activity = activity

        let minimumStep = max(total / 100, 1)
        let progressedEnough = completed - lastPublishedRequestCount
            >= minimumStep
        let waitedLongEnough = Date.now.timeIntervalSince(lastPublishedAt)
            >= 15
        guard progressedEnough || waitedLongEnough || completed == total else {
            return
        }
        发布(latestState, to: activity)
    }

    func 结束(success: Bool, immediately: Bool = false) {
        guard let activity = 当前活动() else {
            self.activity = nil
            return
        }

        let finalState = 偏好分析实时活动属性.ContentState(
            completedRequestCount: success
                ? latestState.totalRequestCount
                : latestState.completedRequestCount,
            totalRequestCount: latestState.totalRequestCount,
            phase: success ? .completed : .interrupted
        )
        let content = ActivityContent(state: finalState, staleDate: nil)
        let dismissalPolicy: ActivityUIDismissalPolicy = immediately
            ? .immediate
            : .after(.now.addingTimeInterval(15))

        Task {
            await activity.end(
                content,
                dismissalPolicy: dismissalPolicy
            )
        }
        self.activity = nil
        Self.logger.info(
            "Preference analysis Live Activity ended, success: \(success, privacy: .public)"
        )
    }

    private func 当前活动() -> Activity<偏好分析实时活动属性>? {
        activity ?? Activity<偏好分析实时活动属性>.activities.first
    }

    private func 发布(
        _ state: 偏好分析实时活动属性.ContentState,
        to activity: Activity<偏好分析实时活动属性>
    ) {
        let content = ActivityContent(state: state, staleDate: nil)
        lastPublishedRequestCount = state.completedRequestCount
        lastPublishedAt = .now
        Task {
            await activity.update(content)
        }
    }
}
