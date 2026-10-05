#if os(iOS)
import ActivityKit
import Foundation

nonisolated struct 偏好分析实时活动属性: ActivityAttributes, Sendable {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum 阶段: String, Codable, Hashable, Sendable {
            case analyzing
            case completed
            case interrupted
        }

        let completedRequestCount: Int
        let totalRequestCount: Int
        let phase: 阶段

        var progress: Double {
            guard totalRequestCount > 0 else { return 0 }
            return min(
                max(
                    Double(completedRequestCount)
                        / Double(totalRequestCount),
                    0
                ),
                1
            )
        }

        var percentage: Int {
            Int((progress * 100).rounded(.down))
        }
    }

    let startedAt: Date
}
#endif
