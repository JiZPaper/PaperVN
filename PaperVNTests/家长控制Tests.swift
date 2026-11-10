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
    func 网站登记设备特例后可关闭安全限制且阈值不超过露骨阈值() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "contentFilterEnabled")
        defaults.set(1.2, forKey: "sexualThreshold")

        敏感内容网页设置.保存(已开启: true, defaults: defaults)

        #expect(强制内容安全策略.可使用高级设置(defaults: defaults))
        #expect(!defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 1.2)

        defaults.set(3.0, forKey: "sexualThreshold")
        强制内容安全策略.应用到用户设置(defaults)
        #expect(defaults.double(forKey: "sexualThreshold") == 强制内容安全策略.露骨阈值)
    }

    @Test
    func 网站撤销设备特例后重新强制安全设置() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        敏感内容网页设置.保存(已开启: true, defaults: defaults)
        defaults.set(false, forKey: "contentFilterEnabled")
        defaults.set(1.2, forKey: "sexualThreshold")

        敏感内容网页设置.保存(已开启: false, defaults: defaults)

        #expect(!强制内容安全策略.可使用高级设置(defaults: defaults))
        #expect(defaults.bool(forKey: "contentFilterEnabled"))
        #expect(defaults.double(forKey: "sexualThreshold") == 0.8)
    }

    @Test
    func 设备码与服务器使用相同算法() {
        let 密钥 = Data((0..<32).map { UInt8($0) })
        // 服务器 deviceCodeFromSecret 对同一密钥的结果。
        #expect(敏感内容网页设置.设备码(密钥: 密钥) == "CC6W-TAB6-RGSP-D48J")
    }

    @Test
    func 旧版本地解锁标记不再生效() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "contentSafetyAdvancedControlsUnlocked")
        #expect(!强制内容安全策略.可使用高级设置(defaults: defaults))

        敏感内容网页设置.移除旧版本地解锁(defaults: defaults)
        #expect(defaults.object(forKey: "contentSafetyAdvancedControlsUnlocked") == nil)
    }

    @Test
    func 只有网站登记后才允许手动解除色情内容模糊() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!内容安全限制判定.允许手动解除模糊(
            色情限制: true,
            defaults: defaults
        ))
        #expect(内容安全限制判定.允许手动解除模糊(
            色情限制: false,
            defaults: defaults
        ))

        敏感内容网页设置.保存(已开启: true, defaults: defaults)

        #expect(内容安全限制判定.图片允许手动解除模糊(
            sexual: 1.2,
            enabled: true,
            sexualThreshold: 0.8,
            mode: .both,
            defaults: defaults
        ))
    }

    @Test
    func 露骨图片始终受限制() {
        #expect(!内容安全限制判定.是露骨图片(强制内容安全策略.露骨阈值))
        #expect(内容安全限制判定.是露骨图片(1.4))
        #expect(内容安全限制判定.是露骨图片(2))

        // 关闭安全限制或只限制暴力内容时，露骨图片仍然受限制。
        for (enabled, mode) in [
            (false, 内容过滤模式.both),
            (true, .violenceOnly),
            (true, .sexualOnly)
        ] {
            #expect(内容安全限制判定.图片需要限制(
                sexual: 2,
                violence: 0,
                enabled: enabled,
                sexualThreshold: 强制内容安全策略.最大色情阈值,
                violenceThreshold: 2,
                mode: mode
            ))
        }
        #expect(!内容安全限制判定.图片需要限制(
            sexual: 1,
            violence: 0,
            enabled: false,
            sexualThreshold: 0,
            violenceThreshold: 0,
            mode: .both
        ))
        #expect(内容安全限制判定.图片需要限制(
            sexual: 0,
            violence: 1.5,
            enabled: true,
            sexualThreshold: 0.8,
            violenceThreshold: 1,
            mode: .violenceOnly
        ))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "PaperVNTests.ParentalControls.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
