import Foundation
import Testing
@testable import PaperVN

struct PaperVNConnect自动策略Tests {
    @Test
    func 时区语言或地区任一符合即识别为中国大陆() {
        #expect(PaperVNConnect自动策略.具有中国大陆特征(
            timeZoneIdentifier: "Asia/Shanghai",
            preferredLanguageIdentifiers: ["en-US"],
            regionIdentifiers: ["US"]
        ))
        #expect(PaperVNConnect自动策略.具有中国大陆特征(
            timeZoneIdentifier: "Europe/London",
            preferredLanguageIdentifiers: ["zh-Hans"],
            regionIdentifiers: ["GB"]
        ))
        #expect(PaperVNConnect自动策略.具有中国大陆特征(
            timeZoneIdentifier: "Asia/Tokyo",
            preferredLanguageIdentifiers: ["ja-JP"],
            regionIdentifiers: ["CN"]
        ))
    }

    @Test
    func 繁体中文不会单独触发中国大陆特征() {
        #expect(!PaperVNConnect自动策略.具有中国大陆特征(
            timeZoneIdentifier: "Asia/Taipei",
            preferredLanguageIdentifiers: ["zh-Hant-TW"],
            regionIdentifiers: ["TW"]
        ))
    }

    @Test
    func 首次默认仅应用一次之后保留用户选择() {
        let suiteName = "PaperVNConnect首次默认Tests"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        PaperVNConnect自动策略.准备初始状态(defaults: defaults)
        let initialValue = defaults.bool(
            forKey: PaperVNConnect自动策略.自动转发状态键
        )
        defaults.set(!initialValue, forKey: PaperVNConnect自动策略.自动转发状态键)

        PaperVNConnect自动策略.准备初始状态(defaults: defaults)

        #expect(defaults.bool(
            forKey: PaperVNConnect自动策略.自动转发状态键
        ) == !initialValue)
    }
}

struct PaperVNConnect网络设置Tests {
    @Test
    func Bangumi换取令牌始终直连() throws {
        let request = URLRequest(url: URL(string: "https://bgm.tv/oauth/access_token")!)

        let candidates = try PaperVNConnect网络设置.请求候选(
            for: request,
            自动转发已启用: true
        )

        #expect(candidates.map(\.url) == [request.url])
    }

    @Test
    func BangumiAPI仍经转发并保留直连回退() throws {
        let request = URLRequest(url: URL(string: "https://api.bgm.tv/v0/me")!)

        let candidates = try PaperVNConnect网络设置.请求候选(
            for: request,
            自动转发已启用: true
        )

        #expect(candidates.map(\.url?.absoluteString) == [
            "https://papervn.jizpaper.com/connect/bangumi/v0/me",
            "https://api.bgm.tv/v0/me"
        ])
    }
}
