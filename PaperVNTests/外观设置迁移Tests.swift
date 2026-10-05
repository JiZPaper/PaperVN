import Foundation
import Testing
@testable import PaperVN

@Suite
struct 外观设置迁移Tests {
    @Test
    @MainActor
    func 沉浸详情透明默认迁移只应用一次() throws {
        let suiteName = "PaperVNTests.AppearanceMigration.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("tiled", forKey: "visualNovelDetailView")
        defaults.set(
            沉浸详情外观.standard.rawValue,
            forKey: 沉浸详情外观.设置键
        )

        PaperVN设置迁移.应用沉浸详情透明默认迁移(
            defaults: defaults
        )

        #expect(
            defaults.string(forKey: "visualNovelDetailView") == "immersive"
        )
        #expect(
            defaults.string(forKey: 沉浸详情外观.设置键)
                == 沉浸详情外观.clear.rawValue
        )

        defaults.set(
            沉浸详情外观.standard.rawValue,
            forKey: 沉浸详情外观.设置键
        )
        PaperVN设置迁移.应用沉浸详情透明默认迁移(
            defaults: defaults
        )

        #expect(
            defaults.string(forKey: 沉浸详情外观.设置键)
                == 沉浸详情外观.standard.rawValue
        )
    }
}
