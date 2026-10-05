import Foundation
import Testing
@testable import PaperVN

private enum JSONAST错误: Error {
  case 不支持的值(String)
}

private indirect enum JSONAST: Equatable,
  ExpressibleByArrayLiteral,
  ExpressibleByIntegerLiteral,
  ExpressibleByStringLiteral
{
  case array([JSONAST])
  case integer(Int)
  case string(String)

  init(arrayLiteral elements: JSONAST...) {
    self = .array(elements)
  }

  init(integerLiteral value: Int) {
    self = .integer(value)
  }

  init(stringLiteral value: String) {
    self = .string(value)
  }

  init(jsonObject: Any) throws {
    if let value = jsonObject as? String {
      self = .string(value)
    } else if let value = jsonObject as? Int {
      self = .integer(value)
    } else if let values = jsonObject as? [Any] {
      self = try .array(values.map(JSONAST.init(jsonObject:)))
    } else {
      throw JSONAST错误.不支持的值(String(describing: jsonObject))
    }
  }
}

@MainActor
private final class 搜索筛选服务Fake: VNDB搜索服务协议 {
  struct 视觉小说调用 {
    let keyword: String
    let filters: 视觉小说搜索筛选
    let sort: 视觉小说搜索排序
    let isDescending: Bool
    let page: Int
    let pageSize: Int
  }

  private(set) var visualNovelCalls: [视觉小说调用] = []
  private(set) var characterCallCount = 0
  var visualNovelResponse = 搜索分页响应<视觉小说搜索结果>(
    results: [],
    more: false
  )

  func 搜索视觉小说(
    关键词: String,
    筛选: 视觉小说搜索筛选,
    排序: 视觉小说搜索排序,
    降序: Bool,
    页码: Int,
    每页: Int
  ) async throws -> 搜索分页响应<视觉小说搜索结果> {
    visualNovelCalls.append(
      .init(
        keyword: 关键词,
        filters: 筛选,
        sort: 排序,
        isDescending: 降序,
        page: 页码,
        pageSize: 每页
      )
    )
    return visualNovelResponse
  }

  func 搜索角色(
    关键词: String,
    页码: Int,
    每页: Int
  ) async throws -> 搜索分页响应<角色搜索结果> {
    characterCallCount += 1
    return .init(results: [], more: false)
  }
}

@Suite
struct 搜索筛选Tests {
  @Test
  @MainActor
  func 空筛选只生成搜索条件() throws {
    let actual = try JSONAST(
      jsonObject: VNDB视觉小说筛选编译器.filterObject(
        keyword: "planetarian",
        filters: .init()
      )
    )
    let expected: JSONAST = ["search", "=", "planetarian"]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 满足所有条件要求全部语言和平台() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .all,
          conditions: [
            .init(
              field: .language,
              stringValues: ["zh-Hans", "ja"]
            ),
            .init(field: .platform, stringValues: ["win"]),
          ]
        )
      ]
    )
    let actual = try compile(filters)
    let expected: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      ["lang", "=", "ja"],
      ["lang", "=", "zh-Hans"],
      ["platform", "=", "win"],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 空关键词生成不含搜索叶子的纯筛选AST() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .all,
          conditions: [
            .init(
              field: .language,
              stringValues: ["zh-Hans", "ja"]
            ),
            .init(field: .platform, stringValues: ["win"]),
          ]
        )
      ]
    )
    let actual = try compile(filters, keyword: "  \n")
    let expected: JSONAST = [
      "and",
      ["lang", "=", "ja"],
      ["lang", "=", "zh-Hans"],
      ["platform", "=", "win"],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 满足任一条件生成或表达式() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .any,
          conditions: [
            .init(
              field: .language,
              stringValues: ["zh-Hans", "ja"]
            ),
            .init(field: .platform, stringValues: ["win", "mac"]),
          ]
        )
      ]
    )
    let actual = try compile(filters)
    let expected: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      [
        "or",
        ["lang", "=", "ja"],
        ["lang", "=", "zh-Hans"],
      ],
      [
        "or",
        ["platform", "=", "mac"],
        ["platform", "=", "win"],
      ],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 排除全部匹配使用德摩根或表达式() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .all,
          isExcluded: true,
          conditions: [
            .init(
              field: .language,
              stringValues: ["zh-Hans", "ja"]
            ),
            .init(field: .platform, stringValues: ["win", "mac"]),
          ]
        )
      ]
    )
    let actual = try compile(filters)
    let expected: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      [
        "or",
        ["lang", "!=", "ja"],
        ["lang", "!=", "zh-Hans"],
        ["platform", "!=", "mac"],
        ["platform", "!=", "win"],
      ],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 排除任一匹配使用德摩根与表达式() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .any,
          isExcluded: true,
          conditions: [
            .init(
              field: .language,
              stringValues: ["zh-Hans", "ja"]
            ),
            .init(field: .platform, stringValues: ["win", "mac"]),
          ]
        )
      ]
    )
    let actual = try compile(filters)
    let expected: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      [
        "or",
        [
          "and",
          ["lang", "!=", "ja"],
          ["lang", "!=", "zh-Hans"],
        ],
        [
          "and",
          ["platform", "!=", "mac"],
          ["platform", "!=", "win"],
        ],
      ],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 篇幅和开发状态的多值固定使用或表达式() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .all,
          conditions: [
            .init(field: .length, integerValues: [5, 1, 3]),
            .init(
              field: .developmentStatus,
              integerValues: [2, 0]
            ),
          ]
        )
      ]
    )
    let actual = try compile(filters)
    let expected: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      [
        "or",
        ["length", "=", 1],
        ["length", "=", 3],
        ["length", "=", 5],
      ],
      [
        "or",
        ["devstatus", "=", 0],
        ["devstatus", "=", 2],
      ],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 评分范围生成上下界且排除时反转() throws {
    let condition = 视觉小说筛选条件(
      field: .rating,
      minimumRating: 60,
      maximumRating: 90
    )
    let included = try compile(
      .init(rules: [.init(conditions: [condition])])
    )
    let excluded = try compile(
      .init(
        rules: [
          .init(isExcluded: true, conditions: [condition])
        ]
      )
    )
    let expectedIncluded: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      ["rating", ">=", 60],
      ["rating", "<=", 90],
    ]
    let expectedExcluded: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      [
        "or",
        ["rating", "<", 60],
        ["rating", ">", 90],
        ["votecount", "=", 0],
      ],
    ]

    #expect(included == expectedIncluded)
    #expect(excluded == expectedExcluded)
  }

  @Test
  @MainActor
  func 排除评分与语言条件时保留未评分项目的补集() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          isExcluded: true,
          conditions: [
            .init(
              field: .rating,
              minimumRating: 60,
              maximumRating: 90
            ),
            .init(field: .language, stringValues: ["ja"]),
          ]
        )
      ]
    )
    let actual = try compile(filters)
    let expected: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      [
        "or",
        ["rating", "<", 60],
        ["rating", ">", 90],
        ["votecount", "=", 0],
        ["lang", "!=", "ja"],
      ],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 空条件被忽略且单个有效条件折叠() throws {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .any,
          conditions: [
            .init(
              field: .language,
              stringValues: ["", "  ", "\n"]
            ),
            .init(field: .length, integerValues: [0, 6]),
            .init(field: .rating),
            .init(field: .platform, stringValues: ["win"]),
          ]
        ),
        .init(conditions: []),
      ]
    )
    let actual = try compile(filters)
    let expected: JSONAST = [
      "and",
      ["search", "=", "keyword"],
      ["platform", "=", "win"],
    ]

    #expect(actual == expected)
  }

  @Test
  @MainActor
  func 活跃筛选数按有效条件而非所选值计数() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(
              field: .language,
              stringValues: ["ja", "zh-Hans"]
            ),
            .init(field: .platform, stringValues: [" "]),
          ]
        ),
        .init(
          isExcluded: true,
          conditions: [
            .init(
              field: .rating,
              minimumRating: 60,
              maximumRating: 90
            ),
            .init(field: .developmentStatus, integerValues: [3]),
          ]
        ),
        .init(),
      ]
    )

    #expect(filters.activeFilterCount == 2)
    #expect(filters.configuredRules.count == 2)
    #expect(视觉小说搜索筛选().activeFilterCount == 0)
  }

  @Test
  @MainActor
  func 空关键词和有效筛选会发起视觉小说搜索并加载结果() async {
    let service = 搜索筛选服务Fake()
    service.visualNovelResponse = .init(
      results: [makeSearchFilterVN(id: "v-filter", title: "Filtered VN")],
      more: false
    )
    let viewModel = 搜索视图模型(
      service: service,
      debounceNanoseconds: 0,
      pageSize: 12
    )
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(field: .platform, stringValues: ["win"])
          ]
        )
      ]
    )

    viewModel.更新搜索(
      关键词: "  \n",
      范围: .visualNovel,
      筛选: filters,
      排序: .voteCount,
      降序: true,
      立即: true
    )
    for _ in 0..<20 where viewModel.状态 == .loading {
      await Task.yield()
    }

    let call = service.visualNovelCalls.first
    #expect(service.visualNovelCalls.count == 1)
    #expect(call?.keyword == "")
    #expect(call?.filters == filters)
    #expect(call?.sort == .voteCount)
    #expect(call?.isDescending == true)
    #expect(call?.page == 1)
    #expect(call?.pageSize == 12)
    #expect(service.characterCallCount == 0)
    #expect(viewModel.状态 == .loaded)
    #expect(viewModel.视觉小说结果.map(\.id) == ["v-filter"])
  }

  @Test
  @MainActor
  func 空关键词和空筛选保持空闲且不调用服务() async {
    let service = 搜索筛选服务Fake()
    let viewModel = 搜索视图模型(
      service: service,
      debounceNanoseconds: 0
    )

    viewModel.更新搜索(
      关键词: "  \n",
      范围: .visualNovel,
      筛选: .init(),
      排序: .title,
      立即: true
    )
    await Task.yield()

    #expect(viewModel.状态 == .idle)
    #expect(service.visualNovelCalls.isEmpty)
    #expect(service.characterCallCount == 0)
    #expect(viewModel.视觉小说结果.isEmpty)
  }

  @Test
  @MainActor
  func 解析顶层字典Schema并保留未知平台代码() throws {
    let data = Data(
      """
      {
        "languages": {
          "ja": {"name": "Japanese"},
          "x-test": {"label": "Test Language"}
        },
        "platforms": {
          "win": "Windows",
          "future-console": {"title": "Future Console"}
        }
      }
      """.utf8
    )

    let catalog = try VNDB服务.解析搜索筛选目录(data)
    let languages = Dictionary(
      uniqueKeysWithValues: catalog.languages.map { ($0.code, $0.name) }
    )
    let platforms = Dictionary(
      uniqueKeysWithValues: catalog.platforms.map { ($0.code, $0.name) }
    )

    #expect(
      languages == [
        "ja": "Japanese",
        "x-test": "Test Language",
      ]
    )
    #expect(
      platforms == [
        "future-console": "Future Console",
        "win": "Windows",
      ]
    )
  }

  @Test
  @MainActor
  func 目录合并按代码去重并保留新增选项() {
    let newer = VNDB搜索筛选目录(
      languages: [
        .init(code: "ja", name: "Japanese from schema"),
        .init(code: "x-test", name: "Test Language"),
        .init(code: "x-test", name: "Updated Test Language"),
      ],
      platforms: [
        .init(code: "win", name: "Windows from schema"),
        .init(code: "future-console", name: "Future Console"),
        .init(code: "future-console", name: "Updated Future Console"),
      ]
    )

    let merged = VNDB搜索筛选目录.builtIn.merging(newer)
    let languageCodes = merged.languages.map(\.code)
    let platformCodes = merged.platforms.map(\.code)

    #expect(languageCodes.count == Set(languageCodes).count)
    #expect(platformCodes.count == Set(platformCodes).count)
    #expect(languageCodes.filter { $0 == "ja" }.count == 1)
    #expect(platformCodes.filter { $0 == "win" }.count == 1)
    #expect(merged.languages.first { $0.code == "ja" }?.name == "Japanese from schema")
    #expect(merged.platforms.first { $0.code == "win" }?.name == "Windows from schema")
    #expect(
      merged.platforms.first { $0.code == "future-console" }?.name
        == "Updated Future Console"
    )
    #expect(merged.platforms.contains { $0.code == "dc" })
  }

  @MainActor
  private func compile(
    _ filters: 视觉小说搜索筛选,
    keyword: String = "keyword"
  ) throws -> JSONAST {
    try JSONAST(
      jsonObject: VNDB视觉小说筛选编译器.filterObject(
        keyword: keyword,
        filters: filters
      )
    )
  }
}

@MainActor
private func makeSearchFilterVN(
  id: String,
  title: String
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
    tags: nil,
    developers: nil
  )
}

@Suite
struct 搜索筛选冲突Tests {
  @Test
  @MainActor
  func 语言任一仍可选择未被排除的语言() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .any,
          conditions: [
            .init(field: .language, stringValues: ["ja", "zh-Hans"])
          ]
        ),
        .init(
          matchMode: .any,
          isExcluded: true,
          conditions: [
            .init(field: .language, stringValues: ["ja"])
          ]
        ),
      ]
    )

    #expect(VNDB筛选冲突检测器.conflict(in: filters) == nil)
  }

  @Test
  @MainActor
  func 语言所有与排除任一产生冲突() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          matchMode: .all,
          conditions: [
            .init(field: .language, stringValues: ["ja", "zh-Hans"])
          ]
        ),
        .init(
          matchMode: .any,
          isExcluded: true,
          conditions: [
            .init(field: .language, stringValues: ["ja"])
          ]
        ),
      ]
    )

    #expect(
      VNDB筛选冲突检测器.conflict(in: filters)?.ruleIndices == [0, 1]
    )
  }

  @Test
  @MainActor
  func 平台任一可避开排除而所有会冲突() {
    let exclusion = 视觉小说筛选规则组(
      matchMode: .any,
      isExcluded: true,
      conditions: [
        .init(field: .platform, stringValues: ["win"])
      ]
    )
    let anyPlatform = 视觉小说筛选规则组(
      matchMode: .any,
      conditions: [
        .init(field: .platform, stringValues: ["mac", "win"])
      ]
    )
    let allPlatforms = 视觉小说筛选规则组(
      matchMode: .all,
      conditions: [
        .init(field: .platform, stringValues: ["mac", "win"])
      ]
    )

    #expect(
      VNDB筛选冲突检测器.conflict(
        in: .init(rules: [anyPlatform, exclusion])
      ) == nil
    )
    #expect(
      VNDB筛选冲突检测器.conflict(
        in: .init(rules: [allPlatforms, exclusion])
      )?.ruleIndices == [0, 1]
    )
  }

  @Test
  @MainActor
  func 复合排除只有全部字段命中时才冲突() {
    let languageRule = 视觉小说筛选规则组(
      conditions: [
        .init(field: .language, stringValues: ["ja"])
      ]
    )
    let excludedRule = 视觉小说筛选规则组(
      isExcluded: true,
      conditions: [
        .init(field: .language, stringValues: ["ja"]),
        .init(field: .platform, stringValues: ["win"]),
      ]
    )
    let platformRule = 视觉小说筛选规则组(
      conditions: [
        .init(field: .platform, stringValues: ["win"])
      ]
    )

    let satisfiable = 视觉小说搜索筛选(
      rules: [languageRule, excludedRule]
    )
    let conflicting = 视觉小说搜索筛选(
      rules: [languageRule, excludedRule, platformRule]
    )

    #expect(VNDB筛选冲突检测器.conflict(in: satisfiable) == nil)
    #expect(
      VNDB筛选冲突检测器.conflict(in: conflicting)?.ruleIndices
        == [0, 1, 2]
    )
  }

  @Test
  @MainActor
  func 篇幅交集为空并忽略无关规则() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(field: .platform, stringValues: ["win"])
          ]
        ),
        .init(
          conditions: [
            .init(field: .length, integerValues: [1])
          ]
        ),
        .init(
          conditions: [
            .init(field: .length, integerValues: [2])
          ]
        ),
      ]
    )

    #expect(
      VNDB筛选冲突检测器.conflict(in: filters)?.ruleIndices == [1, 2]
    )
  }

  @Test
  @MainActor
  func 篇幅集合存在交集时不冲突() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(field: .length, integerValues: [1, 2])
          ]
        ),
        .init(
          conditions: [
            .init(field: .length, integerValues: [2, 3])
          ]
        ),
      ]
    )

    #expect(VNDB筛选冲突检测器.conflict(in: filters) == nil)
  }

  @Test
  @MainActor
  func 开发状态被排除后产生冲突() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(field: .developmentStatus, integerValues: [0])
          ]
        ),
        .init(
          isExcluded: true,
          conditions: [
            .init(field: .developmentStatus, integerValues: [0, 1])
          ]
        ),
      ]
    )

    #expect(
      VNDB筛选冲突检测器.conflict(in: filters)?.ruleIndices == [0, 1]
    )
  }

  @Test
  @MainActor
  func 评分区间部分重叠时仍可满足() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(field: .rating, minimumRating: 60, maximumRating: 80)
          ]
        ),
        .init(
          isExcluded: true,
          conditions: [
            .init(field: .rating, minimumRating: 70, maximumRating: 90)
          ]
        ),
      ]
    )

    #expect(VNDB筛选冲突检测器.conflict(in: filters) == nil)
  }

  @Test
  @MainActor
  func 评分区间被完整排除时产生冲突() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(field: .rating, minimumRating: 60, maximumRating: 80)
          ]
        ),
        .init(
          isExcluded: true,
          conditions: [
            .init(field: .rating, minimumRating: 50, maximumRating: 90)
          ]
        ),
      ]
    )

    #expect(
      VNDB筛选冲突检测器.conflict(in: filters)?.ruleIndices == [0, 1]
    )
  }

  @Test
  @MainActor
  func 只排除评分时未评分项目仍可满足() {
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          isExcluded: true,
          conditions: [
            .init(field: .rating, minimumRating: 10, maximumRating: 100)
          ]
        )
      ]
    )

    #expect(VNDB筛选冲突检测器.conflict(in: filters) == nil)
  }

  @Test
  @MainActor
  func 候选条件API返回冲突规则索引() {
    let targetRule = 视觉小说筛选规则组()
    let filters = 视觉小说搜索筛选(
      rules: [
        .init(
          conditions: [
            .init(field: .length, integerValues: [1])
          ]
        ),
        targetRule,
      ]
    )
    let candidate = 视觉小说筛选条件(
      field: .length,
      integerValues: [2]
    )

    let conflict = VNDB筛选冲突检测器.conflict(
      afterSetting: candidate,
      inRule: targetRule.id,
      filters: filters
    )

    #expect(conflict?.ruleIndices == [0, 1])
  }

  @Test
  @MainActor
  func 候选规则方式API可在提交前发现冲突() {
    let targetRule = 视觉小说筛选规则组(
      matchMode: .any,
      conditions: [
        .init(field: .language, stringValues: ["ja", "zh-Hans"])
      ]
    )
    let filters = 视觉小说搜索筛选(
      rules: [
        targetRule,
        .init(
          matchMode: .any,
          isExcluded: true,
          conditions: [
            .init(field: .language, stringValues: ["ja"])
          ]
        ),
      ]
    )

    #expect(VNDB筛选冲突检测器.conflict(in: filters) == nil)

    let conflict = VNDB筛选冲突检测器.conflict(
      afterSetting: .all,
      isExcluded: false,
      inRule: targetRule.id,
      filters: filters
    )

    #expect(conflict?.ruleIndices == [0, 1])
  }
}
