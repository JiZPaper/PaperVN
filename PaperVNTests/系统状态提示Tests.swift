import Foundation
import Testing
@testable import PaperVN

struct 系统状态提示Tests {
    private let services = #"[{"id":"paperVNToday","status":"available","impact":"none"}]"#

    @Test func 解码服务端写入的提示() throws {
        let json = #"{"schemaVersion":1,"notice":{"icon":"megaphone.fill","title":{"default":"标题","zh-Hans":"标题","de":"Titel"},"description":""},"services":\#(services)}"#
        let document = try JSONDecoder().decode(系统状态文档.self, from: Data(json.utf8))
        let notice = try #require(document.notice)
        #expect(notice.icon == "megaphone.fill")
        #expect(notice.title.resolved(localeIdentifier: "de_DE") == "Titel")
        #expect(notice.title.resolved(localeIdentifier: "pl_PL") == "标题")
        #expect(notice.cleanedDescription() == nil)
    }

    @Test func 没有提示或提示无效时仍能读取服务状态() throws {
        for notice in ["", #""notice":{"icon":1},"#] {
            let json = #"{"schemaVersion":1,\#(notice)"services":\#(services)}"#
            let document = try JSONDecoder().decode(系统状态文档.self, from: Data(json.utf8))
            #expect(document.notice == nil)
            #expect(document.services.count == 1)
        }
    }
}
