import Foundation
import Testing
@testable import PaperVN

/// 最近更改：连续更改合成一条、标题按操作显示、记录随 Paper Cloud 上传后能解码，旧版只有名称的原因也能读。
@Suite
@MainActor
struct 资料库最近更改Tests {
    private func 条目(_ id: String, _ status: 资料库状态) -> 本地资料库条目 {
        var entry = 本地资料库条目(id: id, 类型: .anime, 平台ID: [:], 标题: id, 加入时间: nil)
        entry.状态 = status
        return entry
    }

    @Test func 先添加再编辑合成一次添加() {
        let added = 资料库差异项.比较(之前: [], 之后: [条目("a", .planning)])
        let edited = 资料库差异项.比较(之前: [条目("a", .planning)], 之后: [条目("a", .completed)])
        let merged = 资料库差异项.合并(added, edited)
        #expect(merged.count == 1)
        #expect(merged.first?.种类 == .新增)
        #expect(merged.first?.之后?.状态 == .completed)
    }

    @Test func 先添加再删除不留记录() {
        let added = 资料库差异项.比较(之前: [], 之后: [条目("a", .planning)])
        let removed = 资料库差异项.比较(之前: [条目("a", .planning)], 之后: [])
        #expect(资料库差异项.合并(added, removed).isEmpty)
    }

    @Test func 单部作品的编辑显示作品名() {
        let change = 资料库更改(
            id: UUID(), 时间: .now, 原因: .手动编辑,
            差异: 资料库差异项.比较(之前: [], 之后: [条目("某作品", .planning)])
        )
        #expect(change.标题.contains("某作品"))
        #expect(change.摘要.contains("某作品"))
    }

    @Test func 记录可以编码再解码() throws {
        let change = 资料库更改(
            id: UUID(), 时间: Date(timeIntervalSince1970: 1_800_000_000), 原因: .覆盖资料库(.aniList),
            差异: 资料库差异项.比较(之前: [条目("a", .planning)], 之后: [])
        )
        let data = try 资料库快照.编码器().encode([change])
        let decoded = try 资料库快照.解码器().decode([资料库更改].self, from: data)
        #expect(decoded == [change])
        #expect(decoded.first?.差异.first?.之前?.状态 == .planning)
    }

    @Test func 旧版原因可以读取() throws {
        let decoded = try JSONDecoder().decode([资料库更改原因].self, from: Data(#"["同步","云端同步","未知"]"#.utf8))
        #expect(decoded == [.同步, .云端同步, .手动编辑])
    }
}
