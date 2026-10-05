import Foundation
import Testing
@testable import PaperVN

@Suite(.serialized)
@MainActor
struct 家长控制Tests {
    @Test
    func 年龄范围按最严格边界解析() {
        #expect(
            家长年龄级别.resolve(
                lowerBound: nil,
                upperBound: 12,
                hasActiveParentalControls: false
            ) == .childUnder13
        )
        #expect(
            家长年龄级别.resolve(
                lowerBound: 13,
                upperBound: 15,
                hasActiveParentalControls: false
            ) == .teen13To15
        )
        #expect(
            家长年龄级别.resolve(
                lowerBound: 16,
                upperBound: 17,
                hasActiveParentalControls: false
            ) == .teen16To17
        )
        #expect(
            家长年龄级别.resolve(
                lowerBound: 18,
                upperBound: nil,
                hasActiveParentalControls: false
            ) == .adult
        )
        #expect(
            家长年龄级别.resolve(
                lowerBound: nil,
                upperBound: nil,
                hasActiveParentalControls: true
            ) == .teen16To17
        )
    }

    @Test
    func 儿童授权与年龄范围采用更严格策略() {
        let unrestricted = 家长内容策略.policy(
            ageLevel: .adult,
            familyChildAuthorized: false
        )
        #expect(!unrestricted.isEnforced)

        let authorizedChild = 家长内容策略.policy(
            ageLevel: .adult,
            familyChildAuthorized: true
        )
        #expect(authorizedChild.isEnforced)
        #expect(authorizedChild.sexualThreshold == 1)
        #expect(authorizedChild.violenceThreshold == 1)

        let under13 = 家长内容策略.policy(
            ageLevel: .childUnder13,
            familyChildAuthorized: true
        )
        #expect(under13.sexualThreshold == 0)
        #expect(under13.violenceThreshold == 0)
        #expect(under13.blocksRestrictedContentReveal)
        #expect(under13.blocksUntrustedExternalLinks)
    }

    @Test
    func 强制保护只允许受信任法律页面() {
        let policy = 家长内容策略.policy(
            ageLevel: .teen13To15,
            familyChildAuthorized: false
        )

        #expect(
            家长控制中心.allowsExternalURL(
                URL(string: "https://papervn.jizpaper.com/PrivacyPolicy.html")!,
                policy: policy
            )
        )
        #expect(
            家长控制中心.allowsExternalURL(
                URL(string: "https://papervn.jizpaper.com/TermsOfService.html")!,
                policy: policy
            )
        )
        #expect(
            !家长控制中心.allowsExternalURL(
                URL(string: "https://papervn.jizpaper.com/")!,
                policy: policy
            )
        )
        #expect(
            !家长控制中心.allowsExternalURL(
                URL(string: "https://vndb.org/v1")!,
                policy: policy
            )
        )
        #expect(
            !家长控制中心.allowsExternalURL(
                URL(string: "http://papervn.jizpaper.com/PrivacyPolicy.html")!,
                policy: policy
            )
        )
    }

    @Test
    @MainActor
    func 强制设置会备份纠偏并在解除后应用全局上限() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "contentFilterEnabled")
        defaults.set(1.5, forKey: "sexualThreshold")
        defaults.set(0.25, forKey: "violenceThreshold")
        defaults.set("色情", forKey: "filterMode")
        defaults.set("blurred", forKey: "contentRestrictionMethod")
        defaults.set(
            家长年龄级别.teen13To15.rawValue,
            forKey: "parentalControls.ageLevel"
        )

        var center: 家长控制中心? = 家长控制中心(defaults: defaults)
        #expect(center?.policy.isEnforced == true)
        #expect(defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 0.5)
        #expect(defaults.double(forKey: "violenceThreshold") == 0.25)
        #expect(defaults.string(forKey: "filterMode") == "色情与暴力")
        #expect(defaults.string(forKey: "contentRestrictionMethod") == "hidden")

        defaults.set(2.0, forKey: "sexualThreshold")
        defaults.set("暴力", forKey: "filterMode")
        center?.refresh()
        #expect(defaults.double(forKey: "sexualThreshold") == 0.5)
        #expect(defaults.string(forKey: "filterMode") == "色情与暴力")

        center = nil
        defaults.set(
            家长年龄级别.adult.rawValue,
            forKey: "parentalControls.ageLevel"
        )
        let relaxedCenter = 家长控制中心(defaults: defaults)
        #expect(!relaxedCenter.policy.isEnforced)
        #expect(defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 0.8)
        #expect(defaults.double(forKey: "violenceThreshold") == 0.25)
        #expect(defaults.string(forKey: "filterMode") == "色情")
        #expect(defaults.string(forKey: "contentRestrictionMethod") == "blurred")
    }

    @Test
    @MainActor
    func 系统年龄限制放宽时重新应用用户偏好上限() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "contentFilterEnabled")
        defaults.set(2.0, forKey: "sexualThreshold")
        defaults.set(2.0, forKey: "violenceThreshold")
        defaults.set("色情与暴力", forKey: "filterMode")
        defaults.set("blurred", forKey: "contentRestrictionMethod")
        defaults.set(
            家长年龄级别.childUnder13.rawValue,
            forKey: "parentalControls.ageLevel"
        )

        var center: 家长控制中心? = 家长控制中心(defaults: defaults)
        #expect(defaults.double(forKey: "sexualThreshold") == 0)

        center = nil
        defaults.set(
            家长年龄级别.teen16To17.rawValue,
            forKey: "parentalControls.ageLevel"
        )
        center = 家长控制中心(defaults: defaults)
        #expect(center?.policy.isEnforced == true)
        #expect(defaults.double(forKey: "sexualThreshold") == 0.8)
        #expect(defaults.double(forKey: "violenceThreshold") == 1)
    }

    @Test
    func 全局安全策略保留有效范围与更严格色情阈值() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "contentFilterEnabled")
        defaults.set(0.4, forKey: "sexualThreshold")
        defaults.set("暴力", forKey: "filterMode")

        强制内容安全策略.应用到用户设置(defaults)

        #expect(defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 0.4)
        #expect(defaults.string(forKey: "filterMode") == "暴力")

        defaults.set(1.5, forKey: "sexualThreshold")
        defaults.removeObject(forKey: "filterMode")

        强制内容安全策略.应用到用户设置(defaults)

        #expect(defaults.double(forKey: "sexualThreshold") == 0.8)
        #expect(defaults.string(forKey: "filterMode") == "色情与暴力")
    }

    @Test
    func 紧急回避旋转一圈后应用严格隐藏并在下次启动恢复() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: 紧急回避设置.启用键)
        defaults.set(false, forKey: "contentFilterEnabled")
        defaults.set(1.4, forKey: "sexualThreshold")
        defaults.set(0.7, forKey: "violenceThreshold")
        defaults.set("色情", forKey: "filterMode")
        defaults.set("blurred", forKey: "contentRestrictionMethod")

        var center: 紧急回避中心? = 紧急回避中心(defaults: defaults)
        center?.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)
        center?.handleMotionQuaternion(x: 0, y: 1, z: 0, w: 0)
        center?.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)

        #expect(center?.isActive == true)
        #expect(defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 0)
        #expect(defaults.double(forKey: "violenceThreshold") == 0)
        #expect(defaults.string(forKey: "filterMode") == "色情与暴力")
        #expect(defaults.string(forKey: "contentRestrictionMethod") == "hidden")

        center = nil
        let nextLaunchCenter = 紧急回避中心(defaults: defaults)

        #expect(!nextLaunchCenter.isActive)
        #expect(!defaults.bool(forKey: 紧急回避设置.会话进行中键))
        #expect(!defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 1.4)
        #expect(defaults.double(forKey: "violenceThreshold") == 0.7)
        #expect(defaults.string(forKey: "filterMode") == "色情")
        #expect(defaults.string(forKey: "contentRestrictionMethod") == "blurred")
    }

    @Test
    func 紧急回避未启用时旋转不会改变安全设置() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: 紧急回避设置.启用键)
        defaults.set(1.2, forKey: "sexualThreshold")

        let center = 紧急回避中心(defaults: defaults)
        center.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)
        center.handleMotionQuaternion(x: 0, y: 1, z: 0, w: 0)
        center.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)

        #expect(!center.isActive)
        #expect(defaults.double(forKey: "sexualThreshold") == 1.2)
        #expect(!defaults.bool(forKey: 紧急回避设置.会话进行中键))
    }

    @Test
    func 紧急回避通过左右侧翻四元数触发() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: 紧急回避设置.启用键)
        defaults.set(0.8, forKey: "sexualThreshold")

        let center = 紧急回避中心(defaults: defaults)
        center.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)
        center.handleMotionQuaternion(x: 0, y: 1, z: 0, w: 0)
        center.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)

        #expect(center.isActive)
        #expect(defaults.double(forKey: "sexualThreshold") == 0)
        #expect(defaults.string(forKey: "contentRestrictionMethod") == "hidden")
    }

    @Test
    func 紧急回避上下翻转不会触发() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: 紧急回避设置.启用键)
        let center = 紧急回避中心(defaults: defaults)
        center.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)
        center.handleMotionQuaternion(x: 1, y: 0, z: 0, w: 0)
        center.handleMotionQuaternion(x: 0, y: 0, z: 0, w: 1)

        #expect(!center.isActive)
        #expect(!defaults.bool(forKey: 紧急回避设置.会话进行中键))
    }

    @Test
    func 特定入口解锁后可关闭安全限制并使用完整阈值() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "contentFilterEnabled")
        defaults.set(1.5, forKey: "sexualThreshold")

        #expect(强制内容安全策略.尝试解锁(token: "another-token", defaults: defaults))
        #expect(强制内容安全策略.可使用高级设置(token: "another-token", defaults: defaults))
        #expect(!defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 1.5)

        defaults.set(3.0, forKey: "sexualThreshold")
        强制内容安全策略.应用到用户设置(
            defaults,
            token: "another-token"
        )
        #expect(defaults.double(forKey: "sexualThreshold") == 2)
    }

    @Test(.enabled(if: 内容安全私有配置.禁止解锁Token != nil))
    func 禁止Token无法解锁且会重新强制安全设置() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blockedToken = try #require(内容安全私有配置.禁止解锁Token)

        #expect(强制内容安全策略.尝试解锁(token: "another-token", defaults: defaults))
        defaults.set(false, forKey: "contentFilterEnabled")
        defaults.set(1.7, forKey: "sexualThreshold")

        强制内容安全策略.同步当前Token(blockedToken, defaults: defaults)

        #expect(!强制内容安全策略.可使用高级设置(token: blockedToken, defaults: defaults))
        #expect(!强制内容安全策略.尝试解锁(token: blockedToken, defaults: defaults))
        #expect(defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 0.8)
    }

    @Test(.enabled(if: 内容安全私有配置.禁止解锁Token != nil))
    func 只有高级设置解锁后才允许手动解除色情内容模糊() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let blockedToken = try #require(内容安全私有配置.禁止解锁Token)

        #expect(!内容安全限制判定.允许手动解除模糊(
            色情限制: true,
            defaults: defaults
        ))
        #expect(内容安全限制判定.允许手动解除模糊(
            色情限制: false,
            defaults: defaults
        ))

        #expect(强制内容安全策略.尝试解锁(
            token: "another-token",
            defaults: defaults
        ))
        #expect(内容安全限制判定.图片允许手动解除模糊(
            sexual: 1.2,
            enabled: true,
            sexualThreshold: 0.8,
            mode: .both,
            defaults: defaults
        ))

        强制内容安全策略.同步当前Token(blockedToken, defaults: defaults)

        #expect(!内容安全限制判定.允许手动解除模糊(
            色情限制: true,
            defaults: defaults
        ))
    }

    @Test(.enabled(if: 内容安全私有配置.解锁搜索词 != nil))
    func 只有指定搜索词才注入固定角色() throws {
        let 搜索词 = try #require(内容安全私有配置.解锁搜索词)
        let 角色ID = try #require(内容安全私有配置.解锁角色?.id)
        let ordinary = 角色搜索结果(
            id: "c1",
            name: "Test",
            original: nil,
            aliases: nil,
            image: nil
        )

        let triggered = 内容安全高级设置解锁入口.合并固定结果(
            [ordinary],
            query: "  \(搜索词)  "
        )
        let ordinarySearch = 内容安全高级设置解锁入口.合并固定结果(
            [ordinary],
            query: 角色ID
        )

        #expect(triggered.map(\.id) == [角色ID, "c1"])
        #expect(ordinarySearch.map(\.id) == ["c1"])
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "PaperVNTests.ParentalControls.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
