import Foundation
import Testing
@testable import PaperVN

/// Paper Account 同步的三方合并：只有一边改过取改过的一边，两边都改过取修改时间较新的，没有基准时取并集。
@Suite
@MainActor
struct PaperAccount资料库合并Tests {
    private func 条目(_ id: String, _ status: 资料库状态, 评分: Int? = nil, 时间: TimeInterval = 0) -> 本地资料库条目 {
        var entry = 本地资料库条目(id: id, 类型: .anime, 平台ID: [:], 标题: id, 加入时间: nil)
        entry.状态 = status
        entry.评分 = 评分
        entry.修改时间 = Date(timeIntervalSince1970: 时间)
        return entry
    }

    private func 状态(_ entries: [本地资料库条目]) -> [String: 资料库状态?] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.状态) })
    }

    @Test func 只有一边更改时采用更改的一边() {
        let base = [条目("a", .planning), 条目("b", .planning), 条目("c", .planning)]
        let local = [条目("a", .inProgress), 条目("b", .planning), 条目("c", .planning)]
        let remote = [条目("a", .planning), 条目("b", .completed)]
        let merged = PaperAccount账户.合并(基准: base, 本机: local, 云端: remote)
        // a 本机改了，b 云端改了，c 在云端被删除
        #expect(状态(merged) == ["a": .inProgress, "b": .completed])
    }

    @Test func 两边都改过时取较新的修改() {
        let base = [条目("a", .planning)]
        let local = [条目("a", .inProgress, 时间: 100)]
        let remote = [条目("a", .dropped, 时间: 200)]
        #expect(状态(PaperAccount账户.合并(基准: base, 本机: local, 云端: remote)) == ["a": .dropped])
    }

    @Test func 一边删除一边修改时保留修改() {
        let base = [条目("a", .planning)]
        let merged = PaperAccount账户.合并(基准: base, 本机: [], 云端: [条目("a", .completed)])
        #expect(状态(merged) == ["a": .completed])
    }

    @Test func 第一次同步取并集() {
        let merged = PaperAccount账户.合并(基准: nil, 本机: [条目("a", .planning)], 云端: [条目("b", .completed)])
        #expect(状态(merged) == ["a": .planning, "b": .completed])
    }
}
