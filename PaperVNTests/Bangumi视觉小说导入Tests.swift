import Foundation
import Testing
@testable import PaperVN

/// Bangumi 游戏收藏导入：只有能对应到VNDB作品的条目才导入，一般游戏不导入。
@Suite
@MainActor
struct Bangumi视觉小说导入Tests {
    @Test func 能对应到VNDB的条目找得到作品() {
        let lookup = 视觉小说外部ID目录.shared.Bangumi反查()
        // Bangumi 1126 是 Ever17
        #expect(lookup(1126) == "v17")
    }

    @Test func 没有对应的Bangumi条目不导入() {
        let lookup = 视觉小说外部ID目录.shared.Bangumi反查()
        #expect(lookup(999_999_999) == nil)
    }

    @Test func 收藏类型对应资料库状态() {
        #expect(PaperVNSync中心.资料库状态(Bangumi收藏类型: 1) == .planning)
        #expect(PaperVNSync中心.资料库状态(Bangumi收藏类型: 2) == .completed)
        #expect(PaperVNSync中心.资料库状态(Bangumi收藏类型: 3) == .inProgress)
        #expect(PaperVNSync中心.资料库状态(Bangumi收藏类型: 4) == .onHold)
        #expect(PaperVNSync中心.资料库状态(Bangumi收藏类型: 5) == .dropped)
        #expect(PaperVNSync中心.资料库状态(Bangumi收藏类型: 0) == nil)
    }
}
