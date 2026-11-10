import Foundation
import Testing
@testable import PaperVN

/// 需要网络：没有发行日期的作品是否未发行向公开接口读取，不需要登录任何平台。
@MainActor
struct 未发行判定网络Tests {
    private func 条目(_ id: String, _ type: 作品类型, 状态: 资料库状态? = .planning, 日期: String? = nil) -> 本地资料库条目 {
        var entry = 本地资料库条目(id: id, 类型: type, 平台ID: [:], 标题: id, 加入时间: nil)
        entry.状态 = 状态
        entry.发行日期 = 日期
        return entry
    }

    @Test
    func 已经发行的作品没有日期也不算未发行() async {
        let entries = [
            // 钢之炼金术师 FULLMETAL ALCHEMIST（动画）、剑风传奇（漫画）：两者的 MAL ID 各自编号
            条目("mal-anime:5114", .anime),
            条目("mal-manga:2", .manga),
        ]
        await 未发行判定.读取(entries)
        #expect(未发行判定.已知("mal-anime:5114") == false)
        #expect(未发行判定.已知("mal-manga:2") == false)
        #expect(entries.allSatisfy { !资料库排序.未发行($0) })
        // 结果还在有效期内，不再联网，也没有变化
        #expect(await 未发行判定.读取(entries) == false)
    }

    @Test
    func 只判断计划中且没有日期的作品() async {
        let entries = [
            条目("mal-anime:1", .anime, 状态: .completed),
            条目("mal-anime:20", .anime, 日期: "2002-10-03"),
        ]
        #expect(entries.allSatisfy { !未发行判定.需要判断($0) })
        await 未发行判定.读取(entries)
        #expect(未发行判定.已知("mal-anime:1") == nil)
        #expect(未发行判定.已知("mal-anime:20") == nil)
    }

    /// AniList 上此刻标为未发行的动画（每次现查，不写死作品），读出来应当算未发行。
    @Test
    func 平台标明未发行的作品算未发行() async throws {
        var request = URLRequest(url: URL(string: "https://graphql.anilist.co")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": "{ Page(perPage: 50) { media(type: ANIME, status: NOT_YET_RELEASED, sort: POPULARITY_DESC) { idMal } } }",
        ])
        struct 响应: Decodable {
            struct 作品: Decodable { let idMal: Int? }
            struct 页: Decodable { let media: [作品] }
            struct 数据: Decodable { let Page: 页 }
            let data: 数据
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        let id = try #require(try JSONDecoder().decode(响应.self, from: data).data.Page.media.compactMap(\.idMal).first)
        let entry = 条目("mal-anime:\(id)", .anime)
        await 未发行判定.读取([entry], now: .now.addingTimeInterval(2 * 86_400))
        #expect(未发行判定.已知(entry.id) == true)
        #expect(资料库排序.未发行(entry))
    }
}
