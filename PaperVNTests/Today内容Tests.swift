import Combine
import Foundation
import Testing
@testable import PaperVN

private enum Today缓存测试错误: Error {
    case unexpectedRequest
}

private final class TodayURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var feedData = Data()
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let url = request.url else {
                throw Today缓存测试错误.unexpectedRequest
            }
            Self.requestCount += 1

            let data: Data
            switch url.lastPathComponent {
            case "manifest.json":
                data = Data(
                    #"{"schemaVersion":1,"currentFeed":"feeds/2026-08-21.json"}"#.utf8
                )
            case "2026-08-21.json":
                data = Self.feedData
            default:
                throw Today缓存测试错误.unexpectedRequest
            }

            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) else {
                throw Today缓存测试错误.unexpectedRequest
            }
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

struct Today内容Tests {
    @Test
    func 解析每日内容与关联跳转() throws {
        let data = Data(
            #"""
            {
              "schemaVersion": 1,
              "date": "2026-08-07",
              "stories": [
                {
                  "id": "story-v4",
                  "visualNovelID": "v4",
                  "accessibilityTitle": "CLANNAD",
                  "eyebrow": "你知道吗",
                  "description": "今天是宫泽有纪宁的生日。",
                  "image": {
                    "path": "images/2026-08-07/v4.jpg",
                    "width": 600,
                    "height": 900
                  },
                  "related": [
                    {
                      "type": "character",
                      "id": "c15850",
                      "title": "宫泽有纪宁",
                      "original": "宮沢 有紀寧"
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )

        let feed = try JSONDecoder().decode(Today内容.self, from: data)
        let story = try #require(feed.stories.first)
        let related = try #require(story.related.first)

        #expect(feed.date == "2026-08-07")
        #expect(story.image?.aspectRatio == 2.0 / 3.0)
        #expect(
            story.image?.url?.absoluteString
                == "https://papervn.jizpaper.com/today/images/2026-08-07/v4.jpg"
        )
        guard case .character = related.type else {
            Issue.record("关联内容应解析为角色。")
            return
        }
        #expect(related.id == "c15850")
    }

    @Test
    func 解析多语言字段并保留旧字符串格式兼容() throws {
        let data = Data(
            #"""
            {
              "schemaVersion": 1,
              "date": "2026-08-07",
              "stories": [
                {
                  "id": "localized-story",
                  "visualNovelID": "v4",
                  "accessibilityTitle": {
                    "default": "CLANNAD"
                  },
                  "eyebrow": {
                    "default": "默认标题",
                    "en": "English title"
                  },
                  "description": "旧格式描述",
                  "image": {
                    "path": "images/2026-08-07/v4.jpg",
                    "width": 600,
                    "height": 900
                  },
                  "related": [
                    {
                      "type": "visualNovel",
                      "id": "v4",
                      "title": {
                        "default": "CLANNAD"
                      }
                    }
                  ]
                }
              ]
            }
            """#.utf8
        )

        let feed = try JSONDecoder().decode(Today内容.self, from: data)
        let story = try #require(feed.stories.first)
        let related = try #require(story.related.first)

        #expect(story.eyebrow == "默认标题" || story.eyebrow == "English title")
        #expect(story.description == "旧格式描述")
        #expect(related.title == "CLANNAD")
    }

    @Test
    func 按App界面语言区分简体与繁体中文() throws {
        let data = Data(
            #"""
            {
              "schemaVersion": 1,
              "date": "2026-08-07",
              "stories": [
                {
                  "id": "localized-chinese-story",
                  "visualNovelID": "v28297",
                  "accessibilityTitle": {
                    "default": "星空列车与白的旅行",
                    "zh-Hant": "星空列車與白的旅行"
                  },
                  "eyebrow": {
                    "default": "更多来自卷心菜社",
                    "zh-Hant": "更多來自卷心菜社"
                  },
                  "description": {
                    "default": "白玉的最新作品。",
                    "zh-Hant": "白玉的最新作品。"
                  },
                  "image": {
                    "path": "images/2026-08-07/v28297.jpg",
                    "width": 383,
                    "height": 512
                  },
                  "related": []
                }
              ]
            }
            """#.utf8
        )

        let simplified = try Today内容解码器.decode(
            data,
            localeIdentifier: "zh-Hans"
        )
        let traditional = try Today内容解码器.decode(
            data,
            localeIdentifier: "zh-Hant"
        )

        #expect(simplified.stories.first?.accessibilityTitle == "星空列车与白的旅行")
        #expect(simplified.stories.first?.eyebrow == "更多来自卷心菜社")
        #expect(traditional.stories.first?.accessibilityTitle == "星空列車與白的旅行")
        #expect(traditional.stories.first?.eyebrow == "更多來自卷心菜社")
    }

    @Test
    func 空翻译回退到Today默认文本() throws {
        let data = Data(
            #"""
            {
              "schemaVersion": 2,
              "date": "2026-08-12",
              "stories": [
                {
                  "id": "empty-translation-story",
                  "visualNovelID": "v52251",
                  "accessibilityTitle": {
                    "default": "赝作",
                    "zh-Hant": "",
                    "ja": "",
                    "ko": "",
                    "en": ""
                  },
                  "eyebrow": {
                    "default": "即将发行",
                    "en": "Coming Soon"
                  },
                  "description": {
                    "default": "默认描述",
                    "en": "English description"
                  },
                  "related": []
                }
              ]
            }
            """#.utf8
        )

        for localeIdentifier in ["zh-Hant", "ja", "ko", "en"] {
            let feed = try Today内容解码器.decode(
                data,
                localeIdentifier: localeIdentifier
            )
            #expect(feed.stories.first?.accessibilityTitle == "赝作")
        }
    }

    @Test
    func Today只读取PaperVN服务器() {
        #expect(
            Today内容源.preferredSources(connectEnabled: false).map(\.baseURL)
                == [Today内容源.mirror.baseURL]
        )
        #expect(
            Today内容源.preferredSources(connectEnabled: true).map(\.baseURL)
                == [Today内容源.connect.baseURL]
        )
    }

    @Test
    func 镜像源的相对资源会解析到自有域名() throws {
        let data = Data(
            #"""
            {
              "schemaVersion": 1,
              "date": "2026-08-08",
              "stories": [
                {
                  "id": "mirror-story",
                  "visualNovelID": "v4",
                  "accessibilityTitle": "CLANNAD",
                  "eyebrow": "今天",
                  "description": "镜像源测试",
                  "image": {
                    "path": "images/2026-08-08/v4.jpg",
                    "width": 600,
                    "height": 900
                  },
                  "video": {
                    "path": "videos/2026-08-08/v4.mp4"
                  },
                  "related": []
                }
              ]
            }
            """#.utf8
        )

        let feed = try Today内容解码器.decode(
            data,
            localeIdentifier: "zh-Hans",
            contentBaseURL: Today内容源.mirror.baseURL
        )
        let story = try #require(feed.stories.first)

        #expect(
            story.image?.url?.absoluteString
                == "https://papervn.jizpaper.com/today/images/2026-08-08/v4.jpg"
        )
        #expect(
            story.video?.url?.absoluteString
                == "https://papervn.jizpaper.com/today/videos/2026-08-08/v4.mp4"
        )
    }
}

@Suite(.serialized)
struct Today缓存Tests {
    @Test
    @MainActor
    func 重启后先显示缓存并只在内容变化时更新() async throws {
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PaperVN-TodayTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TodayURLProtocolStub.self]
        let session = URLSession(configuration: configuration)

        TodayURLProtocolStub.feedData = feedData(description: "缓存内容")
        TodayURLProtocolStub.requestCount = 0
        let initialService = Today服务(
            session: session,
            cacheDirectory: cacheDirectory
        )
        let initialFeed = try await initialService.load(
            localeIdentifier: "en",
            forceRefresh: true
        )
        #expect(initialFeed.stories.first?.description == "缓存内容")

        for url in try FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) where url.lastPathComponent != "last-successful-feed.json" {
            try FileManager.default.removeItem(at: url)
        }

        let requestCountAfterInitialLoad = TodayURLProtocolStub.requestCount
        let relaunchedService = Today服务(
            session: session,
            cacheDirectory: cacheDirectory
        )
        let cachedFeed = await relaunchedService.cachedFeed(
            localeIdentifier: "en"
        )
        #expect(cachedFeed?.stories.first?.description == "缓存内容")
        #expect(TodayURLProtocolStub.requestCount == requestCountAfterInitialLoad)

        let model = Today视图模型(service: relaunchedService)
        var publishedDescriptions: [String] = []
        let observation = model.$feed
            .compactMap { $0?.stories.first?.description }
            .sink { publishedDescriptions.append($0) }

        await model.load(localeIdentifier: "en")
        #expect(publishedDescriptions == ["缓存内容"])

        TodayURLProtocolStub.feedData = feedData(description: "更新内容")
        await model.load(localeIdentifier: "en")
        #expect(publishedDescriptions == ["缓存内容", "更新内容"])
        #expect(model.feed?.stories.first?.description == "更新内容")
        withExtendedLifetime(observation) { }
    }

    private func feedData(description: String) -> Data {
        Data(
            """
            {
              "schemaVersion": 1,
              "date": "2026-08-21",
              "stories": [
                {
                  "id": "cache-story",
                  "visualNovelID": "v4",
                  "accessibilityTitle": "CLANNAD",
                  "eyebrow": "Today",
                  "description": "\(description)",
                  "related": []
                }
              ]
            }
            """.utf8
        )
    }
}
