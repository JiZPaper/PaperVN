import Combine
@preconcurrency import CoreMotion
import Foundation
import UIKit

enum 紧急回避设置 {
    static let 启用键 = "emergencyAvoidanceEnabled"
    static let 会话进行中键 = "emergencyAvoidance.sessionActive"
    static let 备份存在键 = "emergencyAvoidance.hasBackup"
    static let 备份启用键 = "emergencyAvoidance.backup.contentFilterEnabled"
    static let 备份色情阈值键 = "emergencyAvoidance.backup.sexualThreshold"
    static let 备份暴力阈值键 = "emergencyAvoidance.backup.violenceThreshold"
    static let 备份过滤范围键 = "emergencyAvoidance.backup.filterMode"
    static let 备份限制模式键 = "emergencyAvoidance.backup.contentRestrictionMethod"

    static func 会话正在进行(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: 会话进行中键)
    }

    static func 应用最严格限制(to defaults: UserDefaults = .standard) {
        if defaults.object(forKey: "contentFilterEnabled") as? Bool != true {
            defaults.set(true, forKey: "contentFilterEnabled")
        }
        if defaults.object(forKey: "sexualThreshold") as? Double != 0 {
            defaults.set(0.0, forKey: "sexualThreshold")
        }
        if defaults.object(forKey: "violenceThreshold") as? Double != 0 {
            defaults.set(0.0, forKey: "violenceThreshold")
        }
        if defaults.string(forKey: "filterMode") != "色情与暴力" {
            defaults.set("色情与暴力", forKey: "filterMode")
        }
        if defaults.string(forKey: "contentRestrictionMethod") != "hidden" {
            defaults.set("hidden", forKey: "contentRestrictionMethod")
        }
    }
}

@MainActor
final class 紧急回避中心: ObservableObject {
    static let shared = 紧急回避中心()

    @Published private(set) var isActive = false

    private struct 姿态四元数 {
        let x: Double
        let y: Double
        let z: Double
        let w: Double
    }

    private let defaults: UserDefaults
    private let motionManager = CMMotionManager()
    private var defaultsObserver: AnyCancellable?
    private var startingAttitude: 姿态四元数?
    private var hasReachedOppositeSide = false
    private var lastKnownEnabled: Bool
    private var isApplyingStrictSettings = false
    private var hasStartedMonitoring = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastKnownEnabled = defaults.bool(forKey: 紧急回避设置.启用键)
        restorePendingSessionIfNeeded()

        defaultsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification,
            object: defaults
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
            self?.enforceStrictSettingsIfNeeded()
        }
    }

    func startMonitoring() {
        guard !hasStartedMonitoring else { return }
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 0.08
        motionManager.startDeviceMotionUpdates(
            using: .xArbitraryZVertical,
            to: OperationQueue.main
        ) { [weak self] motion, _ in
            guard let quaternion = motion?.attitude.quaternion else { return }
            self?.handleMotionQuaternion(
                x: quaternion.x,
                y: quaternion.y,
                z: quaternion.z,
                w: quaternion.w
            )
        }
        hasStartedMonitoring = true
    }

    func handleMotionQuaternion(x: Double, y: Double, z: Double, w: Double) {
        let current = 姿态四元数(x: x, y: y, z: z, w: w)
        let enabled = defaults.bool(forKey: 紧急回避设置.启用键)

        if !enabled {
            startingAttitude = current
            hasReachedOppositeSide = false
            lastKnownEnabled = false
            return
        }

        if !lastKnownEnabled {
            startingAttitude = current
            hasReachedOppositeSide = false
            lastKnownEnabled = true
            return
        }

        guard let startingAttitude else {
            self.startingAttitude = current
            return
        }

        let relative = Self.relativeQuaternion(
            current: current,
            baseline: startingAttitude
        )
        let sideComponent = abs(relative.y)
        let otherComponent = max(abs(relative.x), abs(relative.z))

        if sideComponent > 0.72,
           sideComponent > otherComponent * 1.25,
           abs(relative.w) < 0.55 {
            hasReachedOppositeSide = true
            return
        }

        guard hasReachedOppositeSide,
              abs(relative.w) > 0.9,
              sideComponent < 0.3,
              abs(relative.x) < 0.3,
              abs(relative.z) < 0.3 else {
            return
        }

        hasReachedOppositeSide = false
        activate()
    }

    private static func relativeQuaternion(
        current: 姿态四元数,
        baseline: 姿态四元数
    ) -> 姿态四元数 {
        let inverse = 姿态四元数(
            x: -baseline.x,
            y: -baseline.y,
            z: -baseline.z,
            w: baseline.w
        )
        return 姿态四元数(
            x: inverse.w * current.x + inverse.x * current.w
                + inverse.y * current.z - inverse.z * current.y,
            y: inverse.w * current.y - inverse.x * current.z
                + inverse.y * current.w + inverse.z * current.x,
            z: inverse.w * current.z + inverse.x * current.y
                - inverse.y * current.x + inverse.z * current.w,
            w: inverse.w * current.w - inverse.x * current.x
                - inverse.y * current.y - inverse.z * current.z
        )
    }

    private func activate() {
        guard !isActive else { return }

        defaults.set(
            defaults.object(forKey: "contentFilterEnabled") as? Bool ?? false,
            forKey: 紧急回避设置.备份启用键
        )
        defaults.set(
            defaults.object(forKey: "sexualThreshold") as? Double ?? 0.8,
            forKey: 紧急回避设置.备份色情阈值键
        )
        defaults.set(
            defaults.object(forKey: "violenceThreshold") as? Double ?? 1.0,
            forKey: 紧急回避设置.备份暴力阈值键
        )
        defaults.set(
            defaults.string(forKey: "filterMode") ?? "色情与暴力",
            forKey: 紧急回避设置.备份过滤范围键
        )
        defaults.set(
            defaults.string(forKey: "contentRestrictionMethod") ?? "blurred",
            forKey: 紧急回避设置.备份限制模式键
        )
        defaults.set(true, forKey: 紧急回避设置.备份存在键)
        defaults.set(true, forKey: 紧急回避设置.会话进行中键)

        applyStrictSettings()
        isActive = true
    }

    private func applyStrictSettings() {
        guard !isApplyingStrictSettings else { return }
        isApplyingStrictSettings = true
        defer { isApplyingStrictSettings = false }
        紧急回避设置.应用最严格限制(to: defaults)
    }

    private func enforceStrictSettingsIfNeeded() {
        guard 紧急回避设置.会话正在进行(defaults: defaults) else { return }
        applyStrictSettings()
    }

    private func restorePendingSessionIfNeeded() {
        guard 紧急回避设置.会话正在进行(defaults: defaults) else { return }

        if defaults.bool(forKey: 紧急回避设置.备份存在键) {
            defaults.set(
                defaults.object(forKey: 紧急回避设置.备份启用键) as? Bool ?? false,
                forKey: "contentFilterEnabled"
            )
            defaults.set(
                defaults.object(forKey: 紧急回避设置.备份色情阈值键) as? Double ?? 0.8,
                forKey: "sexualThreshold"
            )
            defaults.set(
                defaults.object(forKey: 紧急回避设置.备份暴力阈值键) as? Double ?? 1.0,
                forKey: "violenceThreshold"
            )
            defaults.set(
                defaults.string(forKey: 紧急回避设置.备份过滤范围键) ?? "色情与暴力",
                forKey: "filterMode"
            )
            defaults.set(
                defaults.string(forKey: 紧急回避设置.备份限制模式键) ?? "blurred",
                forKey: "contentRestrictionMethod"
            )
        }

        defaults.set(false, forKey: 紧急回避设置.会话进行中键)
        defaults.set(false, forKey: 紧急回避设置.备份存在键)
        defaults.removeObject(forKey: 紧急回避设置.备份启用键)
        defaults.removeObject(forKey: 紧急回避设置.备份色情阈值键)
        defaults.removeObject(forKey: 紧急回避设置.备份暴力阈值键)
        defaults.removeObject(forKey: 紧急回避设置.备份过滤范围键)
        defaults.removeObject(forKey: 紧急回避设置.备份限制模式键)
    }
}
