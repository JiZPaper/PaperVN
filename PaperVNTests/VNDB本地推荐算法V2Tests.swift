import Foundation
import Testing

@testable import PaperVN

@MainActor
@Suite
struct VNDB本地推荐算法V2Tests {
    @Test
    func 为你推荐在支持的设备上默认开启() {
        let suiteName = "PaperVN-RecommendationAvailability-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let minimumMemory = 为你推荐偏好分析设置.最低物理内存字节

        #expect(为你推荐偏好分析设置.启用状态(
            defaults: defaults,
            物理内存: minimumMemory
        ))

        #expect(!为你推荐偏好分析设置.启用状态(
            defaults: defaults,
            物理内存: minimumMemory - 1
        ))
    }

    @Test
    func 为你推荐保留用户已关闭的选择() {
        let suiteName = "PaperVN-RecommendationDisabled-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let minimumMemory = 为你推荐偏好分析设置.最低物理内存字节

        defaults.set(false, forKey: 为你推荐偏好分析设置.启用键)

        为你推荐偏好分析设置.应用设备限制(
            defaults: defaults,
            物理内存: minimumMemory
        )

        #expect(!为你推荐偏好分析设置.启用状态(
            defaults: defaults,
            物理内存: minimumMemory
        ))
        #expect(defaults.object(forKey: 为你推荐偏好分析设置.启用键) as? Bool == false)
    }

    @Test
    func 为你推荐保留用户已开启的选择() {
        let suiteName = "PaperVN-RecommendationEnabled-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let minimumMemory = 为你推荐偏好分析设置.最低物理内存字节

        defaults.set(true, forKey: 为你推荐偏好分析设置.启用键)

        #expect(为你推荐偏好分析设置.启用状态(
            defaults: defaults,
            物理内存: minimumMemory
        ))
    }

    @Test
    func 低内存设备会清除旧的启用状态() {
        let suiteName = "PaperVN-RecommendationMemoryLimit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: 为你推荐偏好分析设置.启用键)

        为你推荐偏好分析设置.应用设备限制(
            defaults: defaults,
            物理内存: 为你推荐偏好分析设置.最低物理内存字节 - 1
        )

        #expect(!defaults.bool(forKey: 为你推荐偏好分析设置.启用键))
    }

    @Test
    func 推荐分析代次会在算法更新后要求重新分析() {
        let suiteName = "PaperVN-RecommendationGeneration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "u-generation-test"
        let generation = 为你推荐偏好分析设置.当前分析代次

        #expect(!为你推荐偏好分析设置.已完成分析(
            userID: userID,
            代次: generation,
            defaults: defaults
        ))

        为你推荐偏好分析设置.标记分析完成(
            userID: userID,
            代次: generation,
            defaults: defaults
        )

        #expect(为你推荐偏好分析设置.已完成分析(
            userID: userID,
            代次: generation,
            defaults: defaults
        ))
        #expect(!为你推荐偏好分析设置.已完成分析(
            userID: userID,
            代次: generation + 1,
            defaults: defaults
        ))
    }

    @Test
    func 离线模型变化后会要求重新分析() {
        let suiteName = "PaperVN-RecommendationModel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let userID = "u-model-test"
        let generation = 为你推荐偏好分析设置.当前分析代次
        let firstModel = "1|1000|48"
        let rebuiltModel = "1|2000|48"

        为你推荐偏好分析设置.标记分析完成(
            userID: userID,
            代次: generation,
            模型标识: firstModel,
            defaults: defaults
        )

        #expect(为你推荐偏好分析设置.已完成分析(
            userID: userID,
            代次: generation,
            模型标识: firstModel,
            defaults: defaults
        ))
        #expect(!为你推荐偏好分析设置.已完成分析(
            userID: userID,
            代次: generation,
            模型标识: rebuiltModel,
            defaults: defaults
        ))
    }

    @Test
    func 投票与列表状态共同形成反馈强度() throws {
        let loved = try libraryItem(
            id: "v1",
            vote: 95,
            labels: [2],
            finished: "2026-01-01",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let dropped = try libraryItem(
            id: "v2",
            vote: 45,
            labels: [4],
            tags: [tag(id: "g2", name: "Comedy")]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [loved, dropped],
            characters: []
        )

        #expect((profile.itemFeedback["v1"] ?? 0) > 0.5)
        #expect((profile.itemFeedback["v2"] ?? 0) < -0.5)
        #expect(profile.positiveSeedIDs == Set(["v1"]))
        #expect((profile.tagWeights["g1"] ?? 0) > 0)
        #expect((profile.tagWeights["g2"] ?? 0) < 0)
    }

    @Test
    func 计划游玩作为明确正向意图进入画像() throws {
        let planning = try libraryItem(
            id: "v-planning",
            vote: nil,
            labels: [5],
            tags: [tag(id: "g-planning", name: "Planned Preference")]
        )
        let finished = try libraryItem(
            id: "v-finished",
            vote: nil,
            labels: [2],
            tags: [tag(id: "g-finished", name: "Finished Preference")]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [planning, finished],
            characters: []
        )

        #expect(profile.itemFeedback[planning.id] == 0.30)
        #expect(
            (profile.itemFeedback[planning.id] ?? 0)
                > (profile.itemFeedback[finished.id] ?? 0)
        )
        #expect(profile.positiveSeedIDs.contains(planning.id))
    }

    @Test
    func 校准评分会进入本地画像并排除已校准作品() throws {
        let liked = try visualNovel(
            id: "v-calibrated-liked",
            tags: [tag(id: "g-liked", name: "Mystery")]
        )
        let disliked = try visualNovel(
            id: "v-calibrated-disliked",
            tags: [tag(id: "g-disliked", name: "Comedy")]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [],
            characters: [],
            calibrationSamples: [
                VNDB偏好校准样本(visualNovel: liked, signal: 0.85),
                VNDB偏好校准样本(visualNovel: disliked, signal: -1)
            ]
        )

        #expect(profile.seedIDs == Set([liked.id, disliked.id]))
        #expect(profile.positiveSeedIDs == Set([liked.id]))
        #expect((profile.tagWeights["g-liked"] ?? 0) > 0)
        #expect((profile.tagWeights["g-disliked"] ?? 0) < 0)
    }

    @Test
    func 同系列多部作品只提供递减的新增证据() throws {
        let library = try (1...5).map { index in
            try libraryItem(
                id: "v-series-\(index)",
                vote: nil,
                labels: [5],
                tags: [tag(id: "g-series", name: "Series Preference")],
                relations: [[
                    "id": "v-series-root",
                    "relation": "seq",
                    "relation_official": true
                ]]
            )
        }

        let profile = VNDB本地推荐算法V2.建立画像(
            library: library,
            characters: []
        )
        let totalEvidence = library.reduce(0.0) {
            $0 + (profile.itemFeedback[$1.id] ?? 0)
        }

        #expect(totalEvidence > 0.30)
        #expect(totalEvidence < 0.60)
        #expect(profile.positiveSeedIDs.count == 1)
    }

    @Test
    func 标签IDF保留剧透内部信号并过滤错误关联() throws {
        let common = tag(id: "g-common", name: "Common")
        let rare = tag(id: "g-rare", name: "Rare")
        let spoiler = tag(id: "g-spoiler", name: "Spoiler", spoiler: 1)
        let lie = tag(id: "g-lie", name: "Lie", lie: true)
        let first = try libraryItem(
            id: "v1",
            vote: 90,
            tags: [common, rare, spoiler, lie]
        )
        let second = try libraryItem(
            id: "v2",
            vote: 80,
            tags: [common]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [first, second],
            characters: []
        )

        #expect((profile.tagIDF["g-rare"] ?? 0) > (profile.tagIDF["g-common"] ?? 0))
        #expect(profile.tagWeights["g-spoiler"] != nil)
        #expect(profile.tagNames["g-spoiler"] == nil)
        #expect(profile.tagWeights["g-lie"] == nil)
    }

    @Test
    func 全局泛用技术标签会按普及率忽略() throws {
        let item = try libraryItem(
            id: "v1",
            vote: 95,
            tags: [
                tag(id: "g-content", name: "Mystery", category: "cont"),
                tag(id: "g-tech", name: "ADV", category: "tech")
            ]
        )
        let profile = VNDB本地推荐算法V2.建立画像(
            library: [item],
            characters: [],
            globalTagFrequencies: ["g-content": 20, "g-tech": 400],
            globalVisualNovelCount: 1_000
        )

        #expect(profile.ignoredTagIDs.contains("g-tech"))
        #expect(profile.tagWeights["g-tech"] == nil)
        #expect(profile.tagNames["g-tech"] == nil)
        #expect(profile.tagPairWeights.isEmpty)
        #expect(profile.prototypes.allSatisfy {
            $0.tagWeights["g-tech"] == nil
        })

        let candidate = try visualNovel(
            id: "v-candidate",
            tags: [tag(id: "g-tech", name: "ADV", category: "tech")]
        )
        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [:],
            profile: profile,
            excludedIDs: [],
            limit: 1,
            collaborativeScores: [candidate.id: 1]
        )

        #expect(recommendations.first?.reason != .sharedTag("ADV"))
    }

    @Test
    func 视觉呈现类技术标签可以形成正负偏好() throws {
        let liked = try libraryItem(
            id: "v-liked-visual",
            vote: 95,
            tags: [
                tag(
                    id: "g-liked-visual",
                    name: "Pixel Art",
                    category: "tech"
                )
            ]
        )
        let disliked = try libraryItem(
            id: "v-disliked-visual",
            vote: 40,
            labels: [4],
            tags: [
                tag(
                    id: "g-disliked-visual",
                    name: "Photographic Sprites",
                    category: "tech"
                )
            ]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [liked, disliked],
            characters: []
        )

        #expect((profile.tagWeights["g-liked-visual"] ?? 0) > 0)
        #expect((profile.tagWeights["g-disliked-visual"] ?? 0) < 0)
        #expect(!profile.ignoredTagIDs.contains("g-liked-visual"))
        #expect(!profile.ignoredTagIDs.contains("g-disliked-visual"))
    }

    @Test
    func 资料库中反复出现的具体标签会被识别为偏好() throws {
        let votes = [95, 90, 85, 75, 60]
        let library = try votes.enumerated().map { index, vote in
            var tags = [tag(id: "g-common", name: "Generic", category: "cont")]
            if index == 0 {
                tags.append(tag(id: "g-rare", name: "Distinctive", category: "cont"))
            }
            return try libraryItem(
                id: "v\(index)",
                vote: vote,
                tags: tags
            )
        }

        let profile = VNDB本地推荐算法V2.建立画像(
            library: library,
            characters: []
        )

        #expect(!profile.ignoredTagIDs.contains("g-common"))
        #expect((profile.tagWeights["g-common"] ?? 0) > 0)
        #expect((profile.tagWeights["g-rare"] ?? 0) > 0)
        #expect(profile.gamePrototypes.contains {
            $0.tagWeights["g-common"] != nil
        })
    }

    @Test
    func 多条同方向校准比单条孤立校准更可靠() throws {
        let first = try visualNovel(
            id: "v1",
            tags: [tag(id: "g-calibration", name: "Mystery", category: "cont")]
        )
        let single = VNDB本地推荐算法V2.建立画像(
            library: [],
            characters: [],
            calibrationSamples: [
                VNDB偏好校准样本(visualNovel: first, signal: 0.85)
            ]
        )
        let repeatedItems = try (1...3).map { index in
            try visualNovel(
                id: "v\(index)",
                tags: [tag(id: "g-calibration", name: "Mystery", category: "cont")]
            )
        }
        let repeated = VNDB本地推荐算法V2.建立画像(
            library: [],
            characters: [],
            calibrationSamples: repeatedItems.map {
                VNDB偏好校准样本(visualNovel: $0, signal: 0.85)
            }
        )

        #expect((single.itemFeedback[first.id] ?? 1) < 0.15)
        #expect(
            (repeated.itemFeedback[repeatedItems[0].id] ?? 0)
                > (single.itemFeedback[first.id] ?? 1)
        )
    }

    @Test
    func 角色戏份决定特征权重且剧透名称不进入解释() throws {
        let item = try libraryItem(
            id: "v1",
            vote: 90,
            tags: [tag(id: "g1", name: "Drama")]
        )
        let main = try character(
            id: "c1",
            vnID: "v1",
            role: "main",
            traits: [trait(id: "i-main", name: "Main Trait")]
        )
        let side = try character(
            id: "c2",
            vnID: "v1",
            role: "side",
            traits: [trait(id: "i-side", name: "Side Trait")]
        )
        let unsafe = try character(
            id: "c3",
            vnID: "v1",
            role: "main",
            traits: [
                trait(id: "i-spoiler", name: "Spoiler", spoiler: 1),
                trait(id: "i-lie", name: "Lie", lie: true)
            ]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [item],
            characters: [main, side, unsafe]
        )

        #expect((profile.traitWeights["i-main"] ?? 0) > (profile.traitWeights["i-side"] ?? 0))
        #expect(profile.traitWeights["i-spoiler"] != nil)
        #expect(profile.traitNames["i-spoiler"] == nil)
        #expect(profile.traitWeights["i-lie"] == nil)
    }

    @Test
    func 单部强正向作品也能形成较低置信度角色偏好() throws {
        let item = try libraryItem(
            id: "v-character-seed",
            vote: 95,
            tags: [tag(id: "g1", name: "Drama")]
        )
        let seedCharacter = try character(
            id: "c-seed",
            vnID: item.id,
            role: "main",
            traits: [trait(id: "i-distinct", name: "Distinct Trait")]
        )
        let profile = VNDB本地推荐算法V2.建立画像(
            library: [item],
            characters: [seedCharacter]
        )
        let matching = try visualNovel(
            id: "v-matching-character",
            tags: [tag(id: "g1", name: "Drama")]
        )
        let evidence = VNDB候选角色证据(
            characterID: "c-matching",
            characterName: "Matching Character",
            traitID: "i-distinct",
            traitName: "Distinct Trait",
            groupName: "Personality",
            role: "main"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [matching],
            charactersByVisualNovel: [matching.id: [evidence]],
            profile: profile,
            excludedIDs: [],
            limit: 1
        )

        #expect((profile.traitWeights["i-distinct"] ?? 0) > 0)
        #expect(recommendations.first?.evidence?.characterScore ?? 0 > 0)
        #expect(recommendations.first?.evidence?.characterID == "c-matching")
    }

    @Test
    func 多兴趣资料库最多合并为六个原型() throws {
        let contentTagNames = [
            "Mystery",
            "Romance",
            "Drama",
            "Comedy",
            "Action",
            "Horror",
            "Fantasy",
            "Science Fiction"
        ]
        let library = try contentTagNames.enumerated().map { index, name in
            try libraryItem(
                id: "v\(index + 1)",
                vote: nil,
                labels: [2],
                tags: [tag(id: "g\(index + 1)", name: name)]
            )
        }

        let profile = VNDB本地推荐算法V2.建立画像(
            library: library,
            characters: []
        )

        #expect(profile.prototypes.count == 6)
        #expect(profile.prototypes.allSatisfy { !$0.tagWeights.isEmpty })
    }

    @Test
    func 游戏与角色同时匹配优先于只有游戏匹配() throws {
        let profile = VNDB本地推荐画像V2(
            prototypes: [
                VNDB兴趣原型(
                    tagWeights: ["g1": 1],
                    traitWeights: ["i1": 1],
                    confidence: 1
                )
            ],
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            characterPrototypes: [
                VNDB角色兴趣原型(
                    traitWeights: ["i1": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g1": 1],
            tagNames: ["g1": "Mystery"],
            traitWeights: ["i1": 1],
            traitNames: ["i1": "Cool Heroine"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1],
            traitIDF: ["i1": 1]
        )
        let joint = try visualNovel(
            id: "v-joint",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let gameOnly = try visualNovel(
            id: "v-game",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let evidence = VNDB候选角色证据(
            characterID: "c1",
            characterName: "Heroine",
            traitID: "i1",
            traitName: "Cool Heroine",
            groupName: "Personality",
            role: "main"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [gameOnly, joint],
            charactersByVisualNovel: ["v-joint": [evidence]],
            profile: profile,
            excludedIDs: [],
            limit: 2
        )

        #expect(recommendations.map(\.id).first == "v-joint")
        #expect(
            recommendations.first?.reason
                == .typeAndCharacter(
                    tags: ["Mystery"],
                    character: "Heroine",
                    traits: ["Cool Heroine"]
                )
        )
        #expect(recommendations.first?.evidence?.characterID == "c1")
        #expect(recommendations.first?.evidence?.gameScore ?? 0 >= 0.25)
        #expect(recommendations.first?.evidence?.characterScore ?? 0 >= 0.20)
    }

    @Test
    func 负面标签与角色特征会降低候选分数() throws {
        let profile = VNDB本地推荐画像V2(
            prototypes: [
                VNDB兴趣原型(
                    tagWeights: ["g-good": 1],
                    traitWeights: ["i-good": 1],
                    confidence: 1
                )
            ],
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g-good": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            characterPrototypes: [
                VNDB角色兴趣原型(
                    traitWeights: ["i-good": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g-good": 1, "g-bad": -1.5],
            tagNames: ["g-good": "Good", "g-bad": "Bad"],
            traitWeights: ["i-good": 1, "i-bad": -1.5],
            traitNames: ["i-good": "Good Trait", "i-bad": "Bad Trait"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g-good": 1, "g-bad": 1],
            traitIDF: ["i-good": 1, "i-bad": 1]
        )
        let clean = try visualNovel(
            id: "v-clean",
            tags: [tag(id: "g-good", name: "Good")]
        )
        let penalized = try visualNovel(
            id: "v-penalized",
            tags: [
                tag(id: "g-good", name: "Good"),
                tag(id: "g-bad", name: "Bad")
            ]
        )
        let goodEvidence = VNDB候选角色证据(
            characterID: "c-good",
            characterName: "Good Character",
            traitID: "i-good",
            traitName: "Good Trait",
            groupName: "Personality",
            role: "main"
        )
        let badEvidence = VNDB候选角色证据(
            characterID: "c-good",
            characterName: "Good Character",
            traitID: "i-bad",
            traitName: "Bad Trait",
            groupName: "Personality",
            role: "main"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [penalized, clean],
            charactersByVisualNovel: [
                "v-clean": [goodEvidence],
                "v-penalized": [goodEvidence, badEvidence]
            ],
            profile: profile,
            excludedIDs: [],
            limit: 2
        )

        #expect(recommendations.map(\.id) == ["v-clean"])
    }

    @Test
    func 强负向内容标签不会被协同分数覆盖() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g-good": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g-good": 1, "g-disliked": -1],
            tagNames: ["g-good": "Mystery", "g-disliked": "Gore"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g-good": 1, "g-disliked": 1]
        )
        let candidate = try visualNovel(
            id: "v-negative-content",
            tags: [
                tag(id: "g-good", name: "Mystery", category: "cont"),
                tag(id: "g-disliked", name: "Gore", category: "cont")
            ]
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [:],
            profile: profile,
            excludedIDs: [],
            limit: 1,
            collaborativeScores: [candidate.id: 1]
        )

        #expect(recommendations.isEmpty)
    }

    @Test
    func 主要角色强负向特征会否决候选() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g-good": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g-good": 1],
            tagNames: ["g-good": "Mystery"],
            traitWeights: ["i-disliked": -1],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g-good": 1],
            traitIDF: ["i-disliked": 1]
        )
        let candidate = try visualNovel(
            id: "v-negative-character",
            tags: [tag(id: "g-good", name: "Mystery", category: "cont")]
        )
        let evidence = VNDB候选角色证据(
            characterID: "c1",
            characterName: "Disliked Character",
            traitID: "i-disliked",
            traitName: "Disliked Trait",
            groupName: "Personality",
            role: "main"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [candidate.id: [evidence]],
            profile: profile,
            excludedIDs: [],
            limit: 1,
            collaborativeScores: [candidate.id: 1]
        )

        #expect(recommendations.isEmpty)
    }

    @Test
    func 重排会优先选择不同兴趣与较少重复的候选() throws {
        let profile = VNDB本地推荐画像V2(
            prototypes: [
                VNDB兴趣原型(
                    tagWeights: ["g1": 1],
                    traitWeights: ["i1": 1],
                    confidence: 1
                ),
                VNDB兴趣原型(
                    tagWeights: ["g2": 1],
                    traitWeights: ["i2": 1],
                    confidence: 1
                )
            ],
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 1],
                    confidence: 1,
                    share: 0.5
                ),
                VNDB游戏兴趣原型(
                    tagWeights: ["g2": 1],
                    confidence: 1,
                    share: 0.5
                )
            ],
            characterPrototypes: [
                VNDB角色兴趣原型(
                    traitWeights: ["i1": 1],
                    confidence: 1,
                    share: 0.5
                ),
                VNDB角色兴趣原型(
                    traitWeights: ["i2": 1],
                    confidence: 1,
                    share: 0.5
                )
            ],
            tagWeights: ["g1": 1, "g2": 1],
            tagNames: ["g1": "Mystery", "g2": "Fantasy"],
            traitWeights: ["i1": 1, "i2": 1],
            traitNames: ["i1": "Calm", "i2": "Energetic"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1, "g2": 1],
            traitIDF: ["i1": 1, "i2": 1]
        )
        let first = try visualNovel(
            id: "v1",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let duplicate = try visualNovel(
            id: "v2",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let diverse = try visualNovel(
            id: "v3",
            tags: [tag(id: "g2", name: "Fantasy")]
        )
        let firstEvidence = VNDB候选角色证据(
            characterID: "c1",
            characterName: "Calm Character",
            traitID: "i1",
            traitName: "Calm",
            groupName: "Personality",
            role: "main"
        )
        let diverseEvidence = VNDB候选角色证据(
            characterID: "c2",
            characterName: "Energetic Character",
            traitID: "i2",
            traitName: "Energetic",
            groupName: "Personality",
            role: "main"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [duplicate, diverse, first],
            charactersByVisualNovel: [
                "v1": [firstEvidence],
                "v2": [firstEvidence],
                "v3": [diverseEvidence]
            ],
            profile: profile,
            excludedIDs: [],
            limit: 2
        )

        #expect(recommendations.map(\.id) == ["v1", "v3"])
    }

    @Test
    func 重排不会让同一官方系列占满推荐() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 0.5, "g2": 0.5, "g3": 0.5, "g4": 0.5],
                    confidence: 1,
                    share: 1
                )
            ],
            characterPrototypes: [
                VNDB角色兴趣原型(
                    traitWeights: ["i1": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            tagNames: ["g1": "Mystery", "g2": "Drama", "g3": "Romance", "g4": "Fantasy"],
            traitWeights: ["i1": 1],
            traitNames: ["i1": "Calm"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            tagSpecificity: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            traitIDF: ["i1": 1]
        )
        let tags = [
            tag(id: "g1", name: "Mystery"),
            tag(id: "g2", name: "Drama"),
            tag(id: "g3", name: "Romance"),
            tag(id: "g4", name: "Fantasy")
        ]
        let relation: [[String: Any]] = [[
            "id": "v-series-root",
            "relation": "seq",
            "relation_official": true
        ]]
        let series = try (1...3).map {
            try visualNovel(
                id: "v-series-\($0)",
                tags: tags,
                relations: relation
            )
        }
        let independent = try visualNovel(id: "v-independent", tags: tags)
        let evidence = VNDB候选角色证据(
            characterID: "c1",
            characterName: "Calm Character",
            traitID: "i1",
            traitName: "Calm",
            groupName: "Personality",
            role: "main"
        )
        let evidenceByID = Dictionary(uniqueKeysWithValues:
            (series + [independent]).map { ($0.id, [evidence]) }
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            series + [independent],
            charactersByVisualNovel: evidenceByID,
            profile: profile,
            excludedIDs: [],
            limit: 3
        )

        #expect(recommendations.contains { $0.id == independent.id })
        #expect(recommendations.count { $0.id.hasPrefix("v-series-") } <= 2)
    }

    @Test
    func 角色证据保留剧透内部信号但禁止用于解释() throws {
        let safe = try character(
            id: "c1",
            vnID: "v1",
            role: "primary",
            traits: [trait(id: "i1", name: "Safe")]
        )
        let relationSpoiler = try character(
            id: "c2",
            vnID: "v2",
            role: "main",
            relationSpoiler: 1,
            traits: [trait(id: "i2", name: "Hidden")]
        )
        let traitSpoiler = try character(
            id: "c3",
            vnID: "v3",
            role: "main",
            traits: [trait(id: "i3", name: "Hidden", spoiler: 1)]
        )

        let grouped = VNDB本地推荐算法V2.角色证据按作品分组(
            [safe, relationSpoiler, traitSpoiler]
        )

        #expect(grouped["v1"]?.first?.role == "primary")
        #expect(grouped["v2"]?.first?.canExplain == false)
        #expect(grouped["v3"]?.first?.canExplain == false)
        #expect((grouped["v2"]?.first?.reliability ?? 0) < 1)
        #expect((grouped["v3"]?.first?.reliability ?? 0) < 1)
        #expect(grouped["v1"]?.first?.characterID == "c1")
        #expect(grouped["v1"]?.first?.characterName == "c1")
    }

    @Test
    func 无评分状态只提供弱先验() throws {
        let finished = try libraryItem(
            id: "v-finished",
            vote: nil,
            labels: [2],
            tags: [tag(id: "g-finished", name: "Finished")]
        )
        let dropped = try libraryItem(
            id: "v-dropped",
            vote: nil,
            labels: [4],
            tags: [tag(id: "g-dropped", name: "Dropped")]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [finished, dropped],
            characters: []
        )

        #expect(profile.itemFeedback["v-finished"] == 0.20)
        #expect(profile.itemFeedback["v-dropped"] == -0.45)
    }

    @Test
    func 评分充足时使用用户中位数与MAD校准() throws {
        let votes = [50, 60, 70, 80, 100]
        let library = try votes.enumerated().map { index, vote in
            try libraryItem(
                id: "v\(index)",
                vote: vote,
                tags: [tag(id: "g\(index)", name: "Tag \(index)")]
            )
        }

        let profile = VNDB本地推荐算法V2.建立画像(
            library: library,
            characters: []
        )
        let expected = 0.9 * tanh(10 / (1.4826 * 10))

        #expect(abs((profile.itemFeedback["v3"] ?? 0) - expected) < 0.000_1)
        #expect(abs(profile.itemFeedback["v2"] ?? 1) < 0.000_1)
        #expect((profile.itemFeedback["v0"] ?? 0) < 0)
        #expect((profile.itemFeedback["v4"] ?? 0) > 0)
    }

    @Test
    func 标签组合与发行时期进入画像() throws {
        let item = try libraryItem(
            id: "v-era",
            vote: 95,
            released: "2003-05-10",
            tags: [
                tag(id: "g-mystery", name: "Mystery"),
                tag(id: "g-loop", name: "Time Loop")
            ]
        )

        let profile = VNDB本地推荐算法V2.建立画像(
            library: [item],
            characters: []
        )

        #expect((profile.tagPairWeights["g-loop|g-mystery"] ?? 0) > 0)
        #expect((profile.releaseEraWeights[2000] ?? 0) > 0)
    }

    @Test
    func 热门旧作不会单独证明古早画风接受度() throws {
        let popular = try libraryItem(
            id: "v-popular-old",
            vote: 95,
            labels: [2],
            released: "2003-05-10",
            voteCount: 5_000,
            tags: [tag(id: "g-old", name: "Classic")]
        )
        let distinctive = try libraryItem(
            id: "v-distinctive-old",
            vote: 95,
            labels: [2],
            released: "2003-05-10",
            voteCount: 40,
            tags: [tag(id: "g-old", name: "Classic")]
        )

        let popularProfile = VNDB本地推荐算法V2.建立画像(
            library: [popular],
            characters: []
        )
        let distinctiveProfile = VNDB本地推荐算法V2.建立画像(
            library: [distinctive],
            characters: []
        )

        #expect(
            (popularProfile.historicalPresentationAcceptance[2004] ?? 0)
                < (distinctiveProfile.historicalPresentationAcceptance[2004] ?? 0)
        )
        #expect((popularProfile.historicalPresentationEvidence[2004] ?? 0) < 0.15)
    }

    @Test
    func 未表达乙女游戏意图时直接排除乙女候选() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g-story": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g-story": 1],
            tagNames: ["g-story": "Drama"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g-story": 1]
        )
        let candidate = try visualNovel(
            id: "v-otome",
            rating: 75,
            voteCount: 500,
            tags: [
                tag(id: "g-story", name: "Drama", category: "cont"),
                tag(id: "g-romance", name: "Romance", category: "cont"),
                tag(id: "g-female", name: "Female Protagonist", category: "cont"),
                tag(id: "g542", name: "Otome Game", category: "tech")
            ]
        )
        let characterEvidence = VNDB候选角色证据(
            characterID: "c-otome",
            characterName: "Otome Character",
            traitID: "i-calm",
            traitName: "Calm",
            groupName: "Personality",
            role: "primary"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [candidate.id: [characterEvidence]],
            profile: profile,
            excludedIDs: [],
            limit: 1,
            collaborativeScores: [candidate.id: 1]
        )

        #expect(recommendations.isEmpty)
    }

    @Test
    func 以技术标签为主的稀疏候选即使有角色也排除() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g-content": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g-content": 1],
            tagNames: ["g-content": "Female Protagonist"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g-content": 1]
        )
        let candidate = try visualNovel(
            id: "v-tech-sparse",
            rating: 66.8,
            voteCount: 25,
            tags: [
                tag(id: "g32", name: "ADV", rating: 2, category: "tech"),
                tag(id: "g-content", name: "Female Protagonist", rating: 2, category: "cont"),
                tag(id: "g203", name: "Nameable Protagonist", rating: 2, category: "tech"),
                tag(id: "g235", name: "No Sexual Content", rating: 2, category: "tech"),
                tag(id: "g-tech-four", name: "Mobile Port", rating: 2, category: "tech"),
                tag(id: "g-adults", name: "Only Adult Heroes", rating: 2, category: "cont")
            ]
        )
        let evidence = VNDB候选角色证据(
            characterID: "c1",
            characterName: "Character",
            traitID: "i1",
            traitName: "Reserved",
            groupName: "Personality",
            role: "primary"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [candidate.id: [evidence]],
            profile: profile,
            excludedIDs: [],
            limit: 1,
            collaborativeScores: [candidate.id: 1]
        )

        #expect(recommendations.isEmpty)
    }

    @Test
    func 协同分数足够强时使用相似用户理由() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g-liked": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g-liked": 1],
            tagNames: ["g-liked": "Mystery"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g-liked": 1]
        )
        let candidate = try visualNovel(
            id: "v-collaborative",
            rating: 75,
            voteCount: 100,
            tags: [
                tag(id: "g1", name: "Mystery"),
                tag(id: "g2", name: "Drama"),
                tag(id: "g3", name: "Romance"),
                tag(id: "g4", name: "Fantasy"),
                tag(id: "g5", name: "Time Loop")
            ]
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [candidate.id: [
                VNDB候选角色证据(
                    characterID: "c1",
                    characterName: "Character",
                    traitID: "i1",
                    traitName: "Trait",
                    groupName: "Personality",
                    role: "main"
                )
            ]],
            profile: profile,
            excludedIDs: [],
            limit: 1,
            collaborativeScores: [candidate.id: 0.8]
        )

        #expect(recommendations.first?.reason == .similarUsers)
        #expect(recommendations.first?.evidence?.collaborativeScore == 0.8)
    }

    @Test
    func 剧透角色特征参与评分但不会出现在理由中() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            characterPrototypes: [
                VNDB角色兴趣原型(
                    traitWeights: ["i-hidden": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g1": 1],
            tagNames: ["g1": "Mystery"],
            traitWeights: ["i-hidden": 1],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1],
            traitIDF: ["i-hidden": 1]
        )
        let candidate = try visualNovel(
            id: "v-hidden",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let hiddenEvidence = VNDB候选角色证据(
            characterID: "c-hidden",
            characterName: "Hidden Character",
            traitID: "i-hidden",
            traitName: "Hidden Trait",
            groupName: "Identity",
            role: "main",
            reliability: 0.8,
            canExplain: false
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [candidate.id: [hiddenEvidence]],
            profile: profile,
            excludedIDs: [],
            limit: 1
        )

        #expect(recommendations.first?.evidence?.characterScore != nil)
        #expect(recommendations.first?.reason == .sharedTag("Mystery"))
    }

    @Test
    func 单个宽泛标签且无角色资料时不会进入推荐() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g1": 1],
            tagNames: ["g1": "Mystery"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1]
        )
        let candidate = try visualNovel(
            id: "v-fallback",
            tags: [tag(id: "g1", name: "Mystery")]
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [:],
            profile: profile,
            excludedIDs: [],
            limit: 1
        )

        #expect(recommendations.isEmpty)
    }

    @Test
    func 标签过少的候选不会因单个命中而超过标签完整候选() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 0.5, "g2": 0.5, "g3": 0.5, "g4": 0.5],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            tagNames: [
                "g1": "Mystery",
                "g2": "Drama",
                "g3": "Romance",
                "g4": "Time Loop"
            ],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            tagSpecificity: ["g1": 1, "g2": 1, "g3": 1, "g4": 1]
        )
        let sparse = try visualNovel(
            id: "v-sparse-tags",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let complete = try visualNovel(
            id: "v-complete-tags",
            tags: [
                tag(id: "g1", name: "Mystery"),
                tag(id: "g2", name: "Drama"),
                tag(id: "g3", name: "Romance"),
                tag(id: "g4", name: "Time Loop")
            ]
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [sparse, complete],
            charactersByVisualNovel: [
                sparse.id: [VNDB候选角色证据(
                    characterID: "c-sparse",
                    characterName: "Sparse Character",
                    traitID: "i-other",
                    traitName: "Other",
                    groupName: "Personality",
                    role: "main"
                )],
                complete.id: [VNDB候选角色证据(
                    characterID: "c-complete",
                    characterName: "Complete Character",
                    traitID: "i-other",
                    traitName: "Other",
                    groupName: "Personality",
                    role: "main"
                )]
            ],
            profile: profile,
            excludedIDs: [],
            limit: 2
        )

        #expect(recommendations.map(\.id) == [complete.id])
    }

    @Test
    func 偏好标签书架只从本地候选分组并排除资料库作品() throws {
        let profile = VNDB本地推荐画像V2(
            tagWeights: ["g-favorite": 1.2, "g-secondary": 0.6],
            tagNames: [
                "g-favorite": "Mystery",
                "g-secondary": "Fantasy"
            ],
            seedIDs: ["v-seed"]
        )
        let candidates = try [
            visualNovel(
                id: "v-seed",
                tags: [tag(id: "g-favorite", name: "Mystery")]
            ),
            visualNovel(
                id: "v1",
                tags: [tag(id: "g-favorite", name: "Mystery")]
            ),
            visualNovel(
                id: "v2",
                tags: [tag(id: "g-favorite", name: "Mystery")]
            ),
            visualNovel(
                id: "v3",
                tags: [tag(id: "g-secondary", name: "Fantasy")]
            ),
            visualNovel(
                id: "v4",
                tags: [tag(id: "g-secondary", name: "Fantasy")]
            ),
            visualNovel(
                id: "v-spoiler",
                tags: [
                    tag(
                        id: "g-favorite",
                        name: "Mystery",
                        spoiler: 1
                    )
                ]
            )
        ]

        let shelves = VNDB本地推荐算法V2.偏好标签书架(
            candidates: candidates,
            profile: profile,
            excludedIDs: ["v2"],
            maximumShelves: 2,
            minimumItems: 1
        )

        #expect(shelves.map(\.tagID) == ["g-favorite", "g-secondary"])
        #expect(shelves.first?.items.map(\.id) == ["v1"])
        #expect(shelves.flatMap(\.items).allSatisfy {
            $0.id != "v-seed" && $0.id != "v2" && $0.id != "v-spoiler"
        })
    }

    @Test
    func 偏好标签书架忽略负向和证据不足的标签() throws {
        let profile = VNDB本地推荐画像V2(
            tagWeights: ["g-positive": 0.9, "g-weak": 0.05, "g-negative": -1],
            tagNames: [
                "g-positive": "Drama",
                "g-weak": "Weak",
                "g-negative": "Disliked"
            ]
        )
        let candidates = try [
            visualNovel(
                id: "v1",
                tags: [tag(id: "g-positive", name: "Drama")]
            ),
            visualNovel(
                id: "v2",
                tags: [tag(id: "g-weak", name: "Weak")]
            ),
            visualNovel(
                id: "v3",
                tags: [tag(id: "g-negative", name: "Disliked")]
            )
        ]

        let shelves = VNDB本地推荐算法V2.偏好标签书架(
            candidates: candidates,
            profile: profile,
            excludedIDs: [],
            maximumShelves: 3,
            minimumItems: 1
        )

        #expect(shelves.map(\.tagID) == ["g-positive"])
    }

    @Test
    func 缺少角色资料时即使标签充分也直接排除() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 0.5, "g2": 0.5, "g3": 0.5, "g4": 0.5],
                    confidence: 1,
                    share: 1
                )
            ],
            characterPrototypes: [
                VNDB角色兴趣原型(
                    traitWeights: ["i1": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            tagNames: [
                "g1": "Mystery",
                "g2": "Drama",
                "g3": "Romance",
                "g4": "Time Loop"
            ],
            traitWeights: ["i1": 1],
            traitNames: ["i1": "Calm"],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            tagSpecificity: ["g1": 1, "g2": 1, "g3": 1, "g4": 1],
            traitIDF: ["i1": 1]
        )
        let candidate = try visualNovel(
            id: "v-game-only",
            tags: [
                tag(id: "g1", name: "Mystery"),
                tag(id: "g2", name: "Drama"),
                tag(id: "g3", name: "Romance"),
                tag(id: "g4", name: "Time Loop")
            ]
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [:],
            profile: profile,
            excludedIDs: [],
            limit: 1
        )

        #expect(recommendations.isEmpty)
    }

    @Test
    func 无关角色资料不能帮助稀疏标签候选通过门槛() throws {
        let profile = VNDB本地推荐画像V2(
            gamePrototypes: [
                VNDB游戏兴趣原型(
                    tagWeights: ["g1": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            characterPrototypes: [
                VNDB角色兴趣原型(
                    traitWeights: ["i-liked": 1],
                    confidence: 1,
                    share: 1
                )
            ],
            tagWeights: ["g1": 1],
            tagNames: ["g1": "Mystery"],
            traitWeights: ["i-liked": 1],
            itemFeedback: ["seed": 1],
            seedIDs: ["seed"],
            positiveSeedIDs: ["seed"],
            tagIDF: ["g1": 1],
            traitIDF: ["i-liked": 1, "i-other": 1]
        )
        let candidate = try visualNovel(
            id: "v-unrelated-character",
            tags: [tag(id: "g1", name: "Mystery")]
        )
        let unrelatedEvidence = VNDB候选角色证据(
            characterID: "c-other",
            characterName: "Other Character",
            traitID: "i-other",
            traitName: "Other Trait",
            groupName: "Personality",
            role: "main"
        )

        let recommendations = VNDB本地推荐算法V2.排序候选(
            [candidate],
            charactersByVisualNovel: [candidate.id: [unrelatedEvidence]],
            profile: profile,
            excludedIDs: [],
            limit: 1
        )

        #expect(recommendations.isEmpty)
    }

    private func libraryItem(
        id: String,
        vote: Int?,
        labels: [Int] = [],
        started: String? = nil,
        finished: String? = nil,
        released: String? = nil,
        voteCount: Int? = nil,
        tags: [[String: Any]],
        relations: [[String: Any]]? = nil
    ) throws -> 探索用户列表项目 {
        var visualNovel: [String: Any] = ["title": id, "tags": tags]
        if let released { visualNovel["released"] = released }
        if let voteCount { visualNovel["votecount"] = voteCount }
        if let relations { visualNovel["relations"] = relations }
        var object: [String: Any] = [
            "id": id,
            "labels": labels.map { ["id": $0, "label": "status"] },
            "vn": visualNovel
        ]
        if let vote { object["vote"] = vote }
        if let started { object["started"] = started }
        if let finished { object["finished"] = finished }
        return try decode(object)
    }

    private func visualNovel(
        id: String,
        rating: Double = 70,
        voteCount: Int? = nil,
        tags: [[String: Any]],
        relations: [[String: Any]]? = nil
    ) throws -> 探索视觉小说 {
        var object: [String: Any] = [
            "id": id,
            "title": id,
            "rating": rating,
            "tags": tags
        ]
        if let voteCount { object["votecount"] = voteCount }
        if let relations { object["relations"] = relations }
        return try decode(object)
    }

    private func character(
        id: String,
        vnID: String,
        role: String,
        relationSpoiler: Int = 0,
        traits: [[String: Any]]
    ) throws -> 探索角色 {
        try decode([
            "id": id,
            "name": id,
            "vns": [[
                "id": vnID,
                "title": vnID,
                "role": role,
                "spoiler": relationSpoiler
            ]],
            "traits": traits
        ])
    }

    private func tag(
        id: String,
        name: String,
        rating: Double = 3,
        spoiler: Int = 0,
        lie: Bool = false,
        category: String? = nil
    ) -> [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "name": name,
            "rating": rating,
            "spoiler": spoiler,
            "lie": lie
        ]
        if let category { value["category"] = category }
        return value
    }

    private func trait(
        id: String,
        name: String,
        spoiler: Int = 0,
        lie: Bool = false
    ) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "group_name": "Personality",
            "spoiler": spoiler,
            "lie": lie
        ]
    }

    private func decode<Value: Decodable>(_ object: Any) throws -> Value {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
