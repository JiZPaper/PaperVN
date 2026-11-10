import Foundation
import Testing
@testable import PaperVN

@Suite
@MainActor
struct 作品列表配置Tests {
    @Test func 存储格式往返() {
        let 配置 = 作品列表配置(项: [.init(.rating), .init(.status, 显示: false), .init(.released)])
        #expect(配置.rawValue == "rating,-status,released")
        #expect(作品列表配置(rawValue: 配置.rawValue) == 配置)
    }

    @Test func 空字符串使用默认值() {
        #expect(作品列表配置(rawValue: "") == nil)
    }

    @Test func 整理时去掉不可用与重复的信息并补上新增的信息() {
        // progress 只在资料库可用；unknown 是以后的版本才有的信息；subtitle 已经不能设置（由副标题语言决定）
        let 配置 = 作品列表配置(rawValue: "rating,progress,unknown,rating,-subtitle,-developers")!
        let 整理后 = 配置.整理(for: .search)
        #expect(整理后.项.prefix(2) == [.init(.rating), .init(.developers, 显示: false)])
        #expect(Set(整理后.项.map(\.信息)) == Set(作品列表场景.search.默认项.map(\.信息)))
        #expect(整理后.项.count == 作品列表场景.search.默认项.count)
    }

    @Test func 默认显示与原来一致() {
        #expect(作品列表场景.library.默认配置.显示的信息(for: .library) ==
            [.status, .released, .myRating, .rating])
        #expect(作品列表场景.search.默认配置.显示的信息(for: .search) ==
            [.developers, .type, .released, .rating, .languages, .platforms])
    }
}
