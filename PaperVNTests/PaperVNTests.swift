import Foundation
import Testing
@testable import PaperVN

private enum 测试错误: Error {
    case 缺少处理器
    case 请求不符合预期
    case 模拟失败
}

private final class VNDBURLProtocolStub: URLProtocol {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (statusCode: Int, data: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw 测试错误.缺少处理器
            }
            let result = try handler(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: result.statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                  ) else {
                throw 测试错误.请求不符合预期
            }
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            if !result.data.isEmpty {
                client?.urlProtocol(self, didLoad: result.data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

@MainActor
private final class 假搜索服务: VNDB搜索服务协议 {
    struct 调用: Equatable {
        let query: String
        let page: Int
    }

    var visualNovelCalls: [调用] = []
    var characterCalls: [调用] = []
    var characterFilterCalls: [搜索扩展筛选] = []
    var characterSortCalls: [(搜索扩展排序, Bool)] = []
    var visualNovelHandler:
        ((String, Int) async throws -> 搜索分页响应<视觉小说搜索结果>)?
    var characterHandler:
        ((String, Int) async throws -> 搜索分页响应<角色搜索结果>)?

    func 搜索视觉小说(
        关键词: String,
        筛选: 视觉小说搜索筛选,
        排序: 视觉小说搜索排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<视觉小说搜索结果> {
        visualNovelCalls.append(调用(query: 关键词, page: 页码))
        guard let visualNovelHandler else { throw 测试错误.缺少处理器 }
        return try await visualNovelHandler(关键词, 页码)
    }

    func 搜索角色(
        关键词: String,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<角色搜索结果> {
        characterCalls.append(调用(query: 关键词, page: 页码))
        characterFilterCalls.append(筛选)
        characterSortCalls.append((排序, 降序))
        guard let characterHandler else { throw 测试错误.缺少处理器 }
        return try await characterHandler(关键词, 页码)
    }

    func 搜索角色(
        关键词: String,
        页码: Int,
        每页: Int
    ) async throws -> 搜索分页响应<角色搜索结果> {
        characterCalls.append(调用(query: 关键词, page: 页码))
        guard let characterHandler else { throw 测试错误.缺少处理器 }
        return try await characterHandler(关键词, 页码)
    }
}

@Suite(.serialized)
struct PaperVNTests {
    @Test
    func URLScheme解析视觉小说和角色详情() throws {
        #expect(
            PaperVNURLRoute(url: URL(string: "papervn://vn/v123")!)
                == .visualNovel("v123")
        )
        #expect(
            PaperVNURLRoute(url: URL(string: "papervn://character/c456")!)
                == .character("c456")
        )
        #expect(
            PaperVNURLRoute(url: URL(string: "papervn://v789")!)
                == .visualNovel("v789")
        )
        #expect(
            PaperVNURLRoute(url: URL(string: "papervn:///character/c10")!)
                == .character("c10")
        )
    }

    @Test
    func URLScheme解析会拒绝OAuth和无效条目() {
        #expect(
            PaperVNURLRoute(url: URL(string: "papervn://oauth/callback")!) == nil
        )
        #expect(
            PaperVNURLRoute(url: URL(string: "papervn://vn/not-an-id")!) == nil
        )
        #expect(
            PaperVNURLRoute(url: URL(string: "https://vndb.org/v123")!) == nil
        )
    }

    @Test
    @MainActor
    func 视觉小说搜索使用公开接口并组合筛选() async throws {
        VNDBURLProtocolStub.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/kana/vn")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            guard let data = request.httpBody,
                  let body = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any] else {
                throw 测试错误.请求不符合预期
            }
            #expect(body["sort"] as? String == "searchrank")
            #expect(body["reverse"] as? Bool == false)
            #expect(body["page"] as? Int == 2)
            #expect(body["results"] as? Int == 25)
            #expect(body["count"] as? Bool == false)
            #expect(
                (body["fields"] as? String)?.contains(
                    "tags{category}"
                ) == true
            )

            let filterData = try JSONSerialization.data(
                withJSONObject: body["filters"] as Any
            )
            let filters = String(decoding: filterData, as: UTF8.self)
            #expect(filters.contains("search"))
            #expect(filters.contains("lang"))
            #expect(filters.contains("platform"))
            #expect(
                filters.contains(
                    "[\"or\",[\"length\",\"=\",1],[\"length\",\"=\",3],[\"length\",\"=\",5]]"
                )
            )
            #expect(filters.contains("[\"rating\",\">=\",80]"))
            #expect(filters.contains("[\"rating\",\"<=\",90]"))
            #expect(filters.contains("devstatus"))

            return (
                200,
                Data(
                    """
                    {"results":[{"id":"v1","title":"Test VN","tags":[{"category":"ero"}]}],"more":true}
                    """.utf8
                )
            )
        }

        let service = makeService()
        let filters = 视觉小说搜索筛选(
            languages: ["ja", "en"],
            platforms: ["win"],
            lengths: [1, 3, 5],
            minimumRating: 80,
            maximumRating: 90,
            developmentStatuses: [0]
        )
        let response = try await service.搜索视觉小说(
            关键词: "test",
            筛选: filters,
            排序: .relevance,
            降序: false,
            页码: 2,
            每页: 25
        )

        #expect(response.results.map(\.id) == ["v1"])
        #expect(response.results[0].tags?.contains(where: \.isAdultContent) == true)
        #expect(response.more)
    }

    @Test
    @MainActor
    func 开发与发行商关键词搜索不会组合空筛选() async throws {
        VNDBURLProtocolStub.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/kana/producer")

            guard let data = request.httpBody,
                  let body = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let filters = body["filters"] as? [Any] else {
                throw 测试错误.请求不符合预期
            }

            #expect(filters.count == 3)
            #expect(filters[0] as? String == "search")
            #expect(filters[1] as? String == "=")
            #expect(filters[2] as? String == "Key")
            #expect(body["sort"] as? String == "searchrank")

            return (
                200,
                Data(
                    "{\"results\":[{\"id\":\"p1\",\"name\":\"Key\"}],\"more\":false}"
                        .utf8
                )
            )
        }

        let service = makeService()
        let response = try await service.搜索会社(
            关键词: "Key",
            筛选: .init(),
            排序: .relevance,
            降序: false,
            页码: 1,
            每页: 40
        )

        #expect(response.results.map(\.id) == ["p1"])
    }

    @Test
    func 搜索发行年份不使用千位分隔符() {
        let text = 搜索发行年份显示文本(2026)
        #expect(text.contains("2026"))
        #expect(!text.contains(","))
    }

    @Test
    @MainActor
    func 隐藏模式会按作品色情标签排除安全封面的游戏() {
        let item = makeVN(
            id: "v-adult",
            title: "Adult VN",
            tags: [
                视觉小说搜索标签(category: "ero")
            ]
        )

        #expect(
            内容安全限制判定.视觉小说需要限制(
                item,
                enabled: true,
                sexualThreshold: 1,
                violenceThreshold: 1,
                mode: .both
            )
        )
        #expect(
            !内容安全限制判定.视觉小说需要限制(
                item,
                enabled: true,
                sexualThreshold: 2,
                violenceThreshold: 1,
                mode: .both
            )
        )
        #expect(
            !内容安全限制判定.视觉小说需要限制(
                item,
                enabled: true,
                sexualThreshold: 1,
                violenceThreshold: 1,
                mode: .violenceOnly
            )
        )
    }

    @Test
    @MainActor
    func 资料库排序传给公开接口并区分方向缓存() async throws {
        var capturedSorts: [String] = []
        var capturedDirections: [Bool] = []
        VNDBURLProtocolStub.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/kana/ulist")
            #expect(
                request.value(forHTTPHeaderField: "Authorization")
                    == "Token token"
            )

            guard let data = request.httpBody,
                  let body = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let sort = body["sort"] as? String,
                  let isDescending = body["reverse"] as? Bool else {
                throw 测试错误.请求不符合预期
            }
            capturedSorts.append(sort)
            capturedDirections.append(isDescending)

            return (
                200,
                Data("{\"results\":[],\"more\":false}".utf8)
            )
        }

        let service = makeService()
        let selections: [(用户列表排序, Bool)] = [
            (.lastModified, true),
            (.title, false),
            (.rating, false),
            (.averageRating, true),
            (.releaseDate, true),
            (.lastModified, false)
        ]

        for (sort, isDescending) in selections {
            _ = try await service.fetchUserList(
                token: "token",
                userID: "u1",
                filter: .all,
                sort: sort,
                isDescending: isDescending
            )
        }

        #expect(
            capturedSorts
                == ["lastmod", "title", "vote", "title", "released", "lastmod"]
        )
        #expect(capturedDirections == [true, false, false, true, true, false])
    }

    @Test
    @MainActor
    func 资料库按平均评分在本地排序() async throws {
        var capturedSorts: [String] = []
        VNDBURLProtocolStub.handler = { request in
            guard let data = request.httpBody,
                  let body = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let sort = body["sort"] as? String else {
                throw 测试错误.请求不符合预期
            }
            capturedSorts.append(sort)
            return (
                200,
                Data(
                    """
                    {"results":[
                    {"id":"v2","vn":{"title":"Beta","rating":70}},
                    {"id":"v1","vn":{"title":"Alpha","rating":90}},
                    {"id":"v3","vn":{"title":"Gamma"}}],"more":false}
                    """.utf8
                )
            )
        }

        let service = makeService()
        let descending = try await service.fetchAllUserList(
            token: "token",
            userID: "u1",
            sort: .averageRating,
            isDescending: true
        )
        let ascending = try await service.fetchAllUserList(
            token: "token",
            userID: "u1",
            sort: .averageRating,
            isDescending: false
        )

        #expect(capturedSorts == ["title", "title"])
        #expect(descending.map(\.id) == ["v1", "v2", "v3"])
        #expect(ascending.map(\.id) == ["v2", "v1", "v3"])
    }

    @Test
    @MainActor
    func 搜索排序只使用各端点支持的字段() {
        #expect(
            视觉小说搜索排序.allCases
                == [.relevance, .title, .rating, .voteCount, .released]
        )
        #expect(
            视觉小说搜索排序.available(hasSearchText: false)
                == [.title, .rating, .voteCount, .released]
        )
        #expect(
            视觉小说搜索排序.available(hasSearchText: true)
                == [.relevance, .title, .rating, .voteCount, .released]
        )
        #expect(视觉小说搜索排序.relevance.apiSort == "searchrank")
        #expect(视觉小说搜索排序.title.apiSort == "title")
        #expect(搜索扩展排序.available(for: .release) == [.title, .released])
        #expect(搜索扩展排序.available(for: .character) == [.name, .added])
        #expect(搜索扩展排序.available(for: .staff) == [.name, .added])
        #expect(搜索扩展排序.available(for: .producer) == [.name, .added])
        #expect(
            搜索扩展排序.available(for: .release, hasSearchText: true)
                == [.relevance, .title, .released]
        )
        #expect(
            搜索扩展排序.available(for: .character, hasSearchText: true)
                == [.relevance, .name, .added]
        )
        #expect(搜索扩展排序.relevance.apiSort(for: .staff) == "searchrank")
        #expect(搜索扩展排序.title.apiSort(for: .release) == "title")
        #expect(搜索扩展排序.name.apiSort(for: .character) == "name")
        #expect(搜索扩展排序.released.apiSort(for: .release) == "released")
        #expect(
            用户列表排序.allCases
                == [.lastModified, .title, .rating, .averageRating, .releaseDate]
        )
    }

    @Test
    @MainActor
    func 搜索筛选字段归属顺序与交互配置一致() {
        #expect(
            视觉小说筛选字段.availableFields
                == [
                    .language,
                    .platform,
                    .length,
                    .rating,
                    .developmentStatus,
                    .tag,
                    .releaseYear
                ]
        )
        #expect(
            搜索扩展筛选字段.available(for: .character)
                == [.birthday, .role, .trait]
        )
        #expect(
            搜索扩展筛选字段.available(for: .release)
                == [.language, .platform, .releaseTime, .releaseAttribute]
        )
        #expect(搜索扩展筛选字段.language.systemImage == "character.bubble")
        #expect(搜索扩展筛选字段.platform.systemImage == "rectangle.3.group")
        #expect(搜索扩展筛选字段.releaseTime.systemImage == "calendar")
        #expect(搜索扩展筛选字段.language.requiresSearch)
        #expect(搜索扩展筛选字段.platform.requiresSearch)
        #expect(搜索扩展筛选字段.trait.requiresSearch)
        #expect(!搜索扩展筛选字段.birthday.requiresSearch)
        #expect(!搜索扩展筛选字段.role.requiresSearch)
        #expect(!搜索扩展筛选字段.releaseTime.requiresSearch)
        #expect(!搜索扩展筛选字段.releaseAttribute.requiresSearch)
        #expect(!搜索扩展筛选字段.type.requiresSearch)
    }

    @Test
    @MainActor
    func 资料库全量加载会继续请求后续页() async throws {
        var capturedPages: [Int] = []
        VNDBURLProtocolStub.handler = { request in
            guard let data = request.httpBody,
                  let body = try JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let page = body["page"] as? Int else {
                throw 测试错误.请求不符合预期
            }
            capturedPages.append(page)

            guard page <= 2 else {
                throw 测试错误.请求不符合预期
            }
            let more = page == 1 ? "true" : "false"
            return (
                200,
                Data(
                    "{\"results\":[{\"id\":\"v\(page)\",\"vn\":{\"title\":\"Game \(page)\"}}],\"more\":\(more)}".utf8
                )
            )
        }

        let service = makeService()
        let items = try await service.fetchAllUserList(
            token: "token",
            userID: "u1",
            filter: .all,
            sort: .releaseDate,
            isDescending: false
        )

        #expect(capturedPages == [1, 2])
        #expect(items.map(\.id) == ["v1", "v2"])
    }

    @Test
    @MainActor
    func 评分上下限共同计为一组筛选() {
        let maximumOnly = 视觉小说搜索筛选(maximumRating: 90)
        let range = 视觉小说搜索筛选(
            minimumRating: 60,
            maximumRating: 90
        )

        #expect(!maximumOnly.isEmpty)
        #expect(maximumOnly.activeFilterCount == 1)
        #expect(range.activeFilterCount == 1)
    }

    @Test
    @MainActor
    func 特征目录每个分组只生成一次译文() {
        let groupCount = 128
        let traits = (0..<3_094).map { index in
            let groupIndex = index % groupCount
            return makeExploreTrait(
                id: "i\(index)",
                groupID: "g\(groupIndex)",
                groupName: "Group \(groupIndex)"
            )
        }
        var translatedSources: [String] = []

        let groups = 生成探索特征目录分组(traits) { source in
            translatedSources.append(source)
            return source
        }

        #expect(translatedSources.count == groupCount)
        #expect(Set(translatedSources).count == groupCount)
        #expect(groups.count == groupCount)
        #expect(groups.reduce(0) { $0 + $1.traits.count } == traits.count)
    }

    @Test
    @MainActor
    func 角色搜索解码并映射429错误() async throws {
        var shouldThrottle = false
        VNDBURLProtocolStub.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            if shouldThrottle {
                return (429, Data("Throttled".utf8))
            }
            return (
                200,
                Data(
                    """
                    {"results":[{"id":"c1","name":"Test Character"}],"more":false}
                    """.utf8
                )
            )
        }

        let service = makeService()
        let response = try await service.搜索角色(
            关键词: "character",
            页码: 1,
            每页: 20
        )
        #expect(response.results.first?.id == "c1")
        #expect(!response.more)

        shouldThrottle = true
        do {
            _ = try await service.搜索角色(
                关键词: "character",
                页码: 1,
                每页: 20
            )
            Issue.record("预期429错误")
        } catch {
            #expect(error as? VNDB服务错误 == .请求过于频繁)
        }
    }

    @Test
    @MainActor
    func 连续输入仅执行最新的防抖搜索() async throws {
        let service = 假搜索服务()
        service.visualNovelHandler = { query, _ in
            搜索分页响应(results: [makeVN(id: query, title: query)], more: false)
        }
        let viewModel = 搜索视图模型(
            service: service,
            debounceNanoseconds: 30_000_000
        )

        viewModel.更新搜索(
            关键词: "first",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title
        )
        viewModel.更新搜索(
            关键词: "latest",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title
        )

        try await Task.sleep(for: .milliseconds(100))
        #expect(service.visualNovelCalls == [.init(query: "latest", page: 1)])
        #expect(viewModel.视觉小说结果.map(\.id) == ["latest"])
    }

    @Test
    @MainActor
    func 分类切换立即开始请求并延迟提交结果() async throws {
        let service = 假搜索服务()
        service.visualNovelHandler = { query, _ in
            搜索分页响应(
                results: [makeVN(id: query, title: query)],
                more: false
            )
        }
        let resultCommitGate = 搜索结果提交门()
        resultCommitGate.延迟提交(纳秒: 250_000_000)
        let viewModel = 搜索视图模型(
            service: service,
            resultCommitGate: resultCommitGate,
            debounceNanoseconds: 0
        )

        viewModel.更新搜索(
            关键词: "immediate",
            范围: .visualNovel,
            筛选: .init(),
            排序: .relevance,
            立即: true
        )

        let requestStarted = await 等待直到 {
            service.visualNovelCalls == [
                .init(query: "immediate", page: 1)
            ]
        }
        #expect(requestStarted)
        #expect(viewModel.视觉小说状态 == .idle)
        #expect(viewModel.视觉小说结果.isEmpty)

        try await Task.sleep(for: .milliseconds(40))
        #expect(viewModel.视觉小说状态 == .idle)
        #expect(viewModel.视觉小说结果.isEmpty)

        let committed = await 等待直到 {
            viewModel.视觉小说结果.map(\.id) == ["immediate"]
        }
        #expect(committed)
        #expect(viewModel.视觉小说状态 == .loaded)
    }

    @Test
    @MainActor
    func 防抖等待期间保留已有搜索结果() async throws {
        let service = 假搜索服务()
        service.visualNovelHandler = { query, _ in
            搜索分页响应(
                results: [makeVN(id: query, title: query)],
                more: false
            )
        }
        let viewModel = 搜索视图模型(
            service: service,
            debounceNanoseconds: 80_000_000
        )

        viewModel.更新搜索(
            关键词: "existing",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title,
            立即: true
        )
        let loadedExisting = await 等待直到 {
            viewModel.视觉小说结果.map(\.id) == ["existing"]
        }
        #expect(loadedExisting)

        viewModel.更新搜索(
            关键词: "latest",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title
        )
        try await Task.sleep(for: .milliseconds(20))

        #expect(viewModel.视觉小说状态 == .loaded)
        #expect(viewModel.视觉小说结果.map(\.id) == ["existing"])

        let loadedLatest = await 等待直到 {
            viewModel.视觉小说结果.map(\.id) == ["latest"]
        }
        #expect(loadedLatest)
    }

    @Test
    @MainActor
    func 取消后的过期响应不会覆盖新结果() async throws {
        let service = 假搜索服务()
        service.visualNovelHandler = { query, _ in
            if query == "slow" {
                try? await Task.sleep(for: .milliseconds(80))
            }
            return 搜索分页响应(
                results: [makeVN(id: query, title: query)],
                more: false
            )
        }
        let viewModel = 搜索视图模型(
            service: service,
            debounceNanoseconds: 0
        )

        viewModel.更新搜索(
            关键词: "slow",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title,
            立即: true
        )
        try await Task.sleep(for: .milliseconds(10))
        viewModel.更新搜索(
            关键词: "new",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title,
            立即: true
        )

        try await Task.sleep(for: .milliseconds(120))
        #expect(viewModel.视觉小说结果.map(\.id) == ["new"])
    }

    @Test
    @MainActor
    func 分页追加时去重并正确停止() async throws {
        let service = 假搜索服务()
        service.visualNovelHandler = { _, page in
            if page == 1 {
                return 搜索分页响应(
                    results: [makeVN(id: "v1", title: "One")],
                    more: true
                )
            }
            return 搜索分页响应(
                results: [
                    makeVN(id: "v1", title: "One"),
                    makeVN(id: "v2", title: "Two")
                ],
                more: false
            )
        }
        let viewModel = 搜索视图模型(
            service: service,
            debounceNanoseconds: 0
        )

        viewModel.更新搜索(
            关键词: "page",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title,
            立即: true
        )
        try await Task.sleep(for: .milliseconds(40))
        viewModel.加载下一页()
        try await Task.sleep(for: .milliseconds(40))

        #expect(viewModel.视觉小说结果.map(\.id) == ["v1", "v2"])
        #expect(!viewModel.还有更多)
        #expect(service.visualNovelCalls.map(\.page) == [1, 2])
    }

    @Test
    @MainActor
    func 分类按需加载并在切换后保留各自结果() async {
        let service = 假搜索服务()
        service.visualNovelHandler = { query, _ in
            搜索分页响应(
                results: [makeVN(id: "v-\(query)", title: query)],
                more: false
            )
        }
        service.characterHandler = { query, _ in
            搜索分页响应(
                results: [makeCharacter(id: "c-\(query)", name: query)],
                more: false
            )
        }
        let viewModel = 搜索视图模型(
            service: service,
            debounceNanoseconds: 0
        )

        viewModel.更新搜索(
            关键词: "fate",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title,
            立即: true
        )

        let loadedVisualNovel = await 等待直到 {
            viewModel.视觉小说状态 == .loaded
        }
        #expect(loadedVisualNovel)
        #expect(service.visualNovelCalls == [.init(query: "fate", page: 1)])
        #expect(service.characterCalls.isEmpty)
        #expect(viewModel.视觉小说结果.map(\.id) == ["v-fate"])

        viewModel.更新搜索(
            关键词: "fate",
            范围: .character,
            筛选: .init(),
            排序: .title,
            立即: true
        )
        let loadedCharacter = await 等待直到 {
            viewModel.角色状态 == .loaded
        }

        #expect(loadedCharacter)
        #expect(viewModel.状态 == .loaded)
        #expect(service.visualNovelCalls.count == 1)
        #expect(service.characterCalls.count == 1)
        #expect(viewModel.视觉小说结果.map(\.id) == ["v-fate"])
        #expect(viewModel.角色结果.map(\.id) == ["c-fate"])

        viewModel.切换范围(.visualNovel)

        #expect(viewModel.状态 == .loaded)
        #expect(service.visualNovelCalls.count == 1)
        #expect(service.characterCalls.count == 1)
        #expect(viewModel.视觉小说结果.map(\.id) == ["v-fate"])
        #expect(viewModel.角色结果.map(\.id) == ["c-fate"])
    }

    @Test
    @MainActor
    func 更改角色查询不会重新搜索视觉小说且筛选独立保存() async {
        let service = 假搜索服务()
        service.visualNovelHandler = { query, _ in
            搜索分页响应(
                results: [makeVN(id: "v-\(query)", title: query)],
                more: false
            )
        }
        service.characterHandler = { query, _ in
            搜索分页响应(
                results: [makeCharacter(id: "c-\(query)", name: query)],
                more: false
            )
        }
        let viewModel = 搜索视图模型(
            service: service,
            debounceNanoseconds: 0
        )

        viewModel.更新搜索(
            关键词: "fate",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title,
            立即: true
        )
        let loadedVisualNovel = await 等待直到 {
            viewModel.视觉小说状态 == .loaded
        }
        #expect(loadedVisualNovel)
        #expect(service.visualNovelCalls == [.init(query: "fate", page: 1)])
        #expect(service.characterCalls.isEmpty)

        let characterFilters = 搜索扩展筛选(
            rules: [
                .init(
                    conditions: [
                        .init(field: .role, stringValues: ["main"])
                    ]
                )
            ]
        )

        viewModel.更新搜索(
            关键词: "umineko",
            范围: .character,
            筛选: .init(),
            排序: .title,
            扩展筛选: characterFilters,
            扩展排序: .name,
            扩展降序: false,
            立即: true
        )
        let loadedCharacter = await 等待直到 {
            viewModel.角色结果.map(\.id) == ["c-umineko"]
        }

        #expect(loadedCharacter)
        #expect(service.visualNovelCalls == [.init(query: "fate", page: 1)])
        #expect(service.characterCalls == [.init(query: "umineko", page: 1)])
        #expect(service.characterFilterCalls == [characterFilters])
        #expect(service.characterSortCalls.map { $0.0 } == [.name])
        #expect(service.characterSortCalls.map { $0.1 } == [false])
        #expect(viewModel.视觉小说结果.map(\.id) == ["v-fate"])

        viewModel.更新搜索(
            关键词: "fate",
            范围: .visualNovel,
            筛选: .init(),
            排序: .title,
            立即: true
        )

        #expect(service.visualNovelCalls == [.init(query: "fate", page: 1)])
        #expect(service.characterCalls == [.init(query: "umineko", page: 1)])
        #expect(viewModel.视觉小说结果.map(\.id) == ["v-fate"])
        #expect(viewModel.角色结果.map(\.id) == ["c-umineko"])
    }

    @Test
    @MainActor
    func 加入计划游玩写入标签5() async throws {
        var didPatch = false
        VNDBURLProtocolStub.handler = { request in
            if request.url?.path == "/kana/authinfo" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Token token")
                return (200, Data("{\"permissions\":[\"listwrite\"]}".utf8))
            }
            if request.url?.path == "/kana/ulist/v1" {
                guard let body = request.httpBody,
                      let object = try JSONSerialization.jsonObject(with: body)
                        as? [String: Any],
                      let labels = object["labels"] as? [Int] else {
                    throw 测试错误.请求不符合预期
                }
                #expect(request.httpMethod == "PATCH")
                #expect(labels == [5])
                didPatch = true
                return (204, Data())
            }
            throw 测试错误.请求不符合预期
        }

        let service = makeService()
        try await service.updateUserStatus(
            token: "token",
            vnID: "v1",
            status: .planning,
            existingLabels: []
        )
        #expect(didPatch)
    }

    @MainActor
    private func makeService() -> VNDB服务 {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VNDBURLProtocolStub.self]
        return VNDB服务(
            session: URLSession(configuration: configuration),
            baseURL: "https://example.test/kana",
            cacheDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )
    }
}

@MainActor
private func makeVN(
    id: String,
    title: String,
    tags: [视觉小说搜索标签]? = nil
) -> 视觉小说搜索结果 {
    视觉小说搜索结果(
        id: id,
        title: title,
        alttitle: nil,
        titles: nil,
        aliases: nil,
        released: nil,
        languages: nil,
        platforms: nil,
        image: nil,
        length: nil,
        length_minutes: nil,
        rating: nil,
        votecount: nil,
        tags: tags,
        developers: nil
    )
}

@MainActor
private func makeCharacter(id: String, name: String) -> 角色搜索结果 {
    角色搜索结果(
        id: id,
        name: name,
        original: nil,
        aliases: nil,
        image: nil
    )
}

private func makeExploreTrait(
    id: String,
    groupID: String?,
    groupName: String?
) -> 探索特征 {
    探索特征(
        id: id,
        name: id,
        aliases: nil,
        description: nil,
        searchable: nil,
        applicable: nil,
        sexual: nil,
        groupID: groupID,
        groupName: groupName,
        characterCount: nil
    )
}

@MainActor
private func 等待直到(
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<100 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
