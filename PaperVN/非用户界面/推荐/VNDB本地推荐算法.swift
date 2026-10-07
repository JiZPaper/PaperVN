import Foundation

enum 探索推荐理由: Codable, Hashable, Sendable {
    case sharedTag(String)
    case sameProducer(String)
    case preferredLanguage(String)
    case preferredPlatform(String)
    case preferredLength(Int)
    case preferredCharacterTrait(String)
    case typeAndCharacter(tags: [String], character: String?, traits: [String])
    case mainlyType(tags: [String])
    case similarUsers
    case highlyRated
}

enum 探索推荐置信度: String, Codable, Hashable, Sendable {
    case high
    case medium
    case exploratory

    var text: String {
        switch self {
        case .high: return String(localized: "高度符合你的偏好")
        case .medium: return String(localized: "可能符合你的偏好")
        case .exploratory: return String(localized: "尝试拓展你的兴趣")
        }
    }
}

struct 探索推荐证据: Codable, Hashable, Sendable {
    let gameTags: [String]
    let characterID: String?
    let characterName: String?
    let characterTraits: [String]
    let gameScore: Double
    let characterScore: Double?
    let collaborativeScore: Double?
    let confidence: 探索推荐置信度
    let isExploration: Bool
    let hasCharacterData: Bool?

    private enum CodingKeys: String, CodingKey {
        case gameTags, characterID, characterName, characterTraits
        case gameScore, characterScore, collaborativeScore, confidence
        case isExploration, hasCharacterData
    }

    var hasCharacterEvidence: Bool {
        characterScore != nil && !characterTraits.isEmpty
    }
}

struct 探索推荐: Codable, Hashable, Identifiable, Sendable {
    let visualNovel: 探索视觉小说
    let score: Double
    let reason: 探索推荐理由
    let evidence: 探索推荐证据?

    nonisolated init(
        visualNovel: 探索视觉小说,
        score: Double,
        reason: 探索推荐理由,
        evidence: 探索推荐证据? = nil
    ) {
        self.visualNovel = visualNovel
        self.score = score
        self.reason = reason
        self.evidence = evidence
    }

    var id: String { visualNovel.id }
}

struct VNDB偏好标签书架: Codable, Hashable, Identifiable, Sendable {
    let tagID: String
    let name: String
    let items: [探索视觉小说]

    var id: String { tagID }
}

struct 探索用户列表标签: Codable, Hashable, Sendable {
    let id: Int
    let label: String
}

struct 探索用户列表视觉小说: Codable, Hashable, Sendable {
    let title: String
    let titles: [探索多语言标题]?
    let image: 探索图片?
    let rating: Double?
    let voteCount: Int?
    let released: String?
    let languages: [String]?
    let platforms: [String]?
    let length: Int?
    let lengthMinutes: Int?
    let tags: [探索标签关联]?
    let developers: [探索会社摘要]?
    let relations: [探索视觉小说关系]?

    private enum CodingKeys: String, CodingKey {
        case title, titles, image, rating, released, languages, platforms, length, tags, developers, relations
        case voteCount = "votecount"
        case lengthMinutes = "length_minutes"
    }

    nonisolated func asVisualNovel(id: String) -> 探索视觉小说 {
        探索视觉小说(
            id: id,
            title: title,
            alttitle: nil,
            titles: titles,
            aliases: nil,
            released: released,
            languages: languages,
            platforms: platforms,
            image: image,
            length: length,
            lengthMinutes: lengthMinutes,
            rating: rating,
            voteCount: voteCount,
            tags: tags,
            developers: developers,
            relations: relations
        )
    }
}

struct 探索用户列表项目: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let added: Int?
    let voted: Int?
    let lastModified: Int?
    let vote: Int?
    let started: String?
    let finished: String?
    let labels: [探索用户列表标签]?
    let vn: 探索用户列表视觉小说

    private enum CodingKeys: String, CodingKey {
        case id, added, voted, vote, started, finished, labels, vn
        case lastModified = "lastmod"
    }
}

struct 探索用户列表响应: Codable, Sendable {
    let results: [探索用户列表项目]
    let more: Bool
    let count: Int?

    private enum CodingKeys: String, CodingKey {
        case results, more, count
    }

    init(
        results: [探索用户列表项目],
        more: Bool,
        count: Int? = nil
    ) {
        self.results = results
        self.more = more
        self.count = count
    }
}

struct VNDB兴趣原型: Codable, Hashable, Sendable {
    var tagWeights: [String: Double]
    var traitWeights: [String: Double]
    var confidence: Double
}

struct VNDB游戏兴趣原型: Codable, Hashable, Sendable {
    var tagWeights: [String: Double]
    var confidence: Double
    var share: Double
}

struct VNDB角色兴趣原型: Codable, Hashable, Sendable {
    var traitWeights: [String: Double]
    var confidence: Double
    var share: Double
}

struct VNDB偏好校准样本: Hashable, Sendable {
    let visualNovel: 探索视觉小说
    let signal: Double
}

struct VNDB本地推荐画像V2: Codable, Hashable, Sendable {
    var prototypes: [VNDB兴趣原型] = []
    var gamePrototypes: [VNDB游戏兴趣原型] = []
    var characterPrototypes: [VNDB角色兴趣原型] = []
    var tagWeights: [String: Double] = [:]
    var tagNames: [String: String] = [:]
    var tagPairWeights: [String: Double] = [:]
    var traitWeights: [String: Double] = [:]
    var traitNames: [String: String] = [:]
    var traitGroups: [String: String] = [:]
    var traitGroupWeights: [String: Double] = [:]
    var producerWeights: [String: Double] = [:]
    var producerNames: [String: String] = [:]
    var languageWeights: [String: Double] = [:]
    var platformWeights: [String: Double] = [:]
    var lengthWeights: [Int: Double] = [:]
    var releaseEraWeights: [Int: Double] = [:]
    var historicalPresentationAcceptance: [Int: Double] = [:]
    var historicalPresentationEvidence: [Int: Double] = [:]
    var audienceAcceptance: [String: Double] = [:]
    var audienceEvidence: [String: Double] = [:]
    var itemFeedback: [String: Double] = [:]
    var seedIDs: Set<String> = []
    var positiveSeedIDs: Set<String> = []
    var tagIDF: [String: Double] = [:]
    var tagSpecificity: [String: Double] = [:]
    var ignoredTagIDs: Set<String> = []
    var traitIDF: [String: Double] = [:]

    nonisolated var hasPositiveSignal: Bool {
        !positiveSeedIDs.isEmpty && (!gamePrototypes.isEmpty || !prototypes.isEmpty)
    }

    nonisolated var hasReliableCharacterSignal: Bool {
        !characterPrototypes.isEmpty
    }
}

struct VNDB候选角色证据: Hashable, Sendable {
    let characterID: String
    let characterName: String
    let traitID: String
    let traitName: String
    let groupName: String
    let role: String
    var reliability: Double = 1
    var canExplain: Bool = true

    nonisolated init(
        characterID: String,
        characterName: String,
        traitID: String,
        traitName: String,
        groupName: String,
        role: String,
        reliability: Double = 1,
        canExplain: Bool = true
    ) {
        self.characterID = characterID
        self.characterName = characterName
        self.traitID = traitID
        self.traitName = traitName
        self.groupName = groupName
        self.role = role
        self.reliability = reliability
        self.canExplain = canExplain
    }
}

nonisolated enum VNDB本地推荐算法V2 {
    static func 建立画像(
        library: [探索用户列表项目],
        characters: [探索角色],
        globalTagFrequencies: [String: Int] = [:],
        globalTraitFrequencies: [String: Int] = [:],
        globalVisualNovelCount: Int? = nil,
        globalCharacterCount: Int? = nil,
        calibrationSamples: [VNDB偏好校准样本] = []
    ) -> VNDB本地推荐画像V2 {
        var profile = VNDB本地推荐画像V2()
        profile.seedIDs = Set(library.map(\.id))
        profile.seedIDs.formUnion(calibrationSamples.map { $0.visualNovel.id })

        let votes = library.compactMap(\.vote).sorted()
        let medianVote: Double? = if votes.isEmpty {
            nil
        } else if votes.count.isMultiple(of: 2) {
            Double(votes[votes.count / 2 - 1] + votes[votes.count / 2]) / 2
        } else {
            Double(votes[votes.count / 2])
        }
        let medianAbsoluteDeviation: Double? = medianVote.map { median in
            let deviations = votes.map { abs(Double($0) - median) }.sorted()
            guard !deviations.isEmpty else { return 10 }
            if deviations.count.isMultiple(of: 2) {
                return (
                    deviations[deviations.count / 2 - 1]
                        + deviations[deviations.count / 2]
                ) / 2
            }
            return deviations[deviations.count / 2]
        }
        let voteScale = max(10, 1.4826 * (medianAbsoluteDeviation ?? 10))
        for item in library {
            let signal = feedback(
                for: item,
                medianVote: medianVote,
                voteScale: voteScale,
                hasReliableVoteDistribution: votes.count >= 5
            )
            profile.itemFeedback[item.id] = signal
            if signal > 0.08 { profile.positiveSeedIDs.insert(item.id) }
        }
        let positiveCalibrationCount = calibrationSamples.count { $0.signal > 0.08 }
        let negativeCalibrationCount = calibrationSamples.count { $0.signal < -0.08 }
        for sample in calibrationSamples {
            let id = sample.visualNovel.id
            let directionCount = sample.signal > 0.08
                ? positiveCalibrationCount
                : (sample.signal < -0.08 ? negativeCalibrationCount : 0)
            let calibrationScale = directionCount > 0
                ? min(0.55, 0.15 + 0.08 * Double(directionCount - 1))
                : 0.10
            let calibratedSignal = sample.signal * calibrationScale
            let signal: Double
            if let librarySignal = profile.itemFeedback[id] {
                signal = min(1, max(-1, librarySignal + 0.35 * calibratedSignal))
            } else {
                signal = calibratedSignal
            }
            profile.itemFeedback[id] = signal
            if signal > 0.08 { profile.positiveSeedIDs.insert(id) }
        }

        let libraryIDs = Set(library.map(\.id))
        let seriesScales = 系列证据缩放(
            library,
            feedback: profile.itemFeedback
        )
        profile.positiveSeedIDs.subtract(libraryIDs)
        for item in library {
            profile.itemFeedback[item.id] = (profile.itemFeedback[item.id] ?? 0)
                * (seriesScales[item.id] ?? 1)
            if (profile.itemFeedback[item.id] ?? 0) > 0.08 {
                profile.positiveSeedIDs.insert(item.id)
            }
        }

        let historicalCutoffs = [1999, 2004, 2009, 2014]
        var historicalPositive: [Int: Double] = [:]
        var historicalNegative: [Int: Double] = [:]
        var audiencePositive: [String: Double] = [:]
        var audienceNegative: [String: Double] = [:]
        for item in library {
            let signal = profile.itemFeedback[item.id] ?? 0
            if let year = releaseYear(item.vn.released) {
                let experience = historicalExperienceConfidence(item)
                if experience > 0 {
                    let distinctiveness = historicalWorkDistinctiveness(
                        voteCount: item.vn.voteCount
                    )
                    for cutoff in historicalCutoffs where year <= cutoff {
                        historicalPositive[cutoff, default: 0] += max(0, signal)
                            * experience * distinctiveness
                        historicalNegative[cutoff, default: 0] += abs(min(0, signal))
                            * experience * (0.75 + 0.25 * distinctiveness)
                    }
                }
            }

            let audienceExperience = audienceExperienceConfidence(item)
            guard audienceExperience > 0 else { continue }
            let boundaryKeys = Set(
                (item.vn.tags ?? []).compactMap(audienceBoundaryKey)
            )
            for key in boundaryKeys {
                audiencePositive[key, default: 0] += max(0, signal)
                    * audienceExperience
                audienceNegative[key, default: 0] += abs(min(0, signal))
                    * audienceExperience
            }
        }
        for cutoff in historicalCutoffs {
            let positive = historicalPositive[cutoff] ?? 0
            let negative = historicalNegative[cutoff] ?? 0
            let evidence = positive + negative
            profile.historicalPresentationEvidence[cutoff] = evidence
            profile.historicalPresentationAcceptance[cutoff] = min(
                1,
                max(0, (positive - 0.85 * negative) / (0.80 + evidence))
            )
        }
        for key in Set(audiencePositive.keys).union(audienceNegative.keys) {
            let positive = audiencePositive[key] ?? 0
            let negative = audienceNegative[key] ?? 0
            let evidence = positive + negative
            profile.audienceEvidence[key] = evidence
            profile.audienceAcceptance[key] = min(
                1,
                max(0, (positive - negative) / (0.45 + evidence))
            )
        }

        let profileItems: [(id: String, vn: 探索视觉小说, signal: Double)] =
            library.map { item in
                (
                    item.id,
                    item.vn.asVisualNovel(id: item.id),
                    profile.itemFeedback[item.id] ?? 0
                )
            } + calibrationSamples.map { sample in
                (
                    sample.visualNovel.id,
                    sample.visualNovel,
                    profile.itemFeedback[sample.visualNovel.id] ?? sample.signal
                )
            }
        let uniqueProfileItems = Dictionary(
            profileItems.map { ($0.id, $0) },
            uniquingKeysWith: { first, second in
                abs(second.signal) > abs(first.signal) ? second : first
            }
        ).values

        let documentCount = max(1, uniqueProfileItems.count)
        var tagDocumentFrequency: [String: Int] = [:]
        var visualPresentationTagIDs: Set<String> = []
        for item in uniqueProfileItems {
            let tags = item.vn.tags ?? []
            profile.ignoredTagIDs.formUnion(
                tags.filter { !recommendationEligibleTag($0) }.map(\.id)
            )
            let eligibleTags = tags.filter(recommendationEligibleTag)
            visualPresentationTagIDs.formUnion(
                eligibleTags.filter(isVisualPresentationTag).map(\.id)
            )
            let ids = Set(eligibleTags.map(\.id))
            for id in ids { tagDocumentFrequency[id, default: 0] += 1 }
        }
        for (id, localFrequency) in tagDocumentFrequency {
            let globalFrequency = globalTagFrequencies[id]
            let hasGlobalFrequency = globalFrequency != nil
                && globalVisualNovelCount != nil
            let corpusCount = hasGlobalFrequency
                ? max(documentCount, globalVisualNovelCount ?? documentCount)
                : documentCount
            let frequency = hasGlobalFrequency
                ? (globalFrequency ?? localFrequency)
                : localFrequency
            profile.tagIDF[id] = min(
                4,
                log((Double(corpusCount) + 1) / (Double(frequency) + 1)) + 1
            )
            let specificity = tagSpecificity(
                globalFrequency: globalFrequency,
                globalDocumentCount: globalVisualNovelCount
            )
            profile.tagSpecificity[id] = specificity
            let globalRatio = tagGlobalRatio(
                frequency: globalFrequency,
                documentCount: globalVisualNovelCount
            )
            if (globalRatio ?? 0) >= 0.30
                && !visualPresentationTagIDs.contains(id) {
                profile.ignoredTagIDs.insert(id)
            }
        }
        if let globalVisualNovelCount {
            for (id, frequency) in globalTagFrequencies where profile.tagIDF[id] == nil {
                profile.tagIDF[id] = min(
                    4,
                    log(
                        (Double(globalVisualNovelCount) + 1)
                            / (Double(frequency) + 1)
                    ) + 1
                )
                let ratio = Double(frequency) / Double(max(1, globalVisualNovelCount))
                profile.tagSpecificity[id] = frequencySpecificity(ratio)
                if ratio >= 0.30 { profile.ignoredTagIDs.insert(id) }
            }
        }

        let relevantCharacters = characters.filter { character in
            (character.visualNovels ?? []).contains {
                profile.seedIDs.contains($0.id)
            }
        }
        let characterCount = max(1, relevantCharacters.count)
        var traitDocumentFrequency: [String: Int] = [:]
        for character in relevantCharacters {
            let ids = Set((character.traits ?? []).filter {
                $0.lie != true
            }.map(\.id))
            for id in ids { traitDocumentFrequency[id, default: 0] += 1 }
        }
        let traitCorpusCount = max(
            characterCount,
            globalCharacterCount ?? characterCount
        )
        for (id, localFrequency) in traitDocumentFrequency {
            let frequency = globalTraitFrequencies[id] ?? localFrequency
            profile.traitIDF[id] = log(
                (Double(traitCorpusCount) + 1) / (Double(frequency) + 1)
            ) + 1
        }
        for (id, frequency) in globalTraitFrequencies where profile.traitIDF[id] == nil {
            profile.traitIDF[id] = log(
                (Double(traitCorpusCount) + 1) / (Double(frequency) + 1)
            ) + 1
        }

        var itemTraits: [String: [String: Double]] = [:]
        var traitExposure: [String: Double] = [:]
        var traitGroupExposure: [String: Double] = [:]
        var positiveTraitDocuments: [String: Set<String>] = [:]
        var negativeTraitDocuments: [String: Set<String>] = [:]
        var characterCountsByVisualNovel: [String: Int] = [:]
        for character in relevantCharacters {
            for relation in character.visualNovels ?? []
            where profile.seedIDs.contains(relation.id) {
                characterCountsByVisualNovel[relation.id, default: 0] += 1
            }
        }
        for character in relevantCharacters {
            let validTraits = (character.traits ?? []).filter {
                $0.lie != true
            }
            guard !validTraits.isEmpty else { continue }
            var grouped: [String: [探索角色特征关联]] = [:]
            for trait in validTraits {
                grouped[trait.groupName, default: []].append(trait)
                profile.traitGroups[trait.id] = trait.groupName
            }
            var characterVector: [String: Double] = [:]
            for traits in grouped.values {
                let groupScale = 1 / sqrt(Double(max(1, traits.count)))
                for trait in traits {
                    characterVector[trait.id] = (profile.traitIDF[trait.id] ?? 1)
                        * groupScale
                        * spoilerReliability(trait.spoiler)
                    if trait.spoiler == 0 {
                        profile.traitNames[trait.id] = trait.name
                    }
                }
            }
            characterVector = normalized(characterVector)

            for relation in character.visualNovels ?? [] {
                guard let signal = profile.itemFeedback[relation.id], signal != 0 else {
                    continue
                }
                let role = roleWeight(relation.role)
                    * spoilerReliability(relation.spoiler)
                let characterCountScale = 1 / sqrt(Double(
                    max(1, characterCountsByVisualNovel[relation.id] ?? 0)
                ))
                for (traitID, traitValue) in characterVector {
                    let evidence = role * traitValue * characterCountScale
                    let value = signal * evidence
                    profile.traitWeights[traitID, default: 0] += value
                    traitExposure[traitID, default: 0] += abs(signal) * evidence
                    if signal > 0.08 {
                        positiveTraitDocuments[traitID, default: []].insert(relation.id)
                    } else if signal < -0.08 {
                        negativeTraitDocuments[traitID, default: []].insert(relation.id)
                    }
                    itemTraits[relation.id, default: [:]][traitID, default: 0] += evidence
                }
                for groupName in grouped.keys {
                    profile.traitGroupWeights[groupName, default: 0] += signal * role * characterCountScale
                    traitGroupExposure[groupName, default: 0] += abs(signal) * role * characterCountScale
                }
            }
        }

        for traitID in profile.traitWeights.keys {
            let shrunk = (profile.traitWeights[traitID] ?? 0)
                / (1.5 + (traitExposure[traitID] ?? 0))
            let repeated = 独立证据作品数(
                positiveTraitDocuments[traitID],
                seriesScales: seriesScales
            ) >= 2 || 独立证据作品数(
                negativeTraitDocuments[traitID],
                seriesScales: seriesScales
            ) >= 2
            profile.traitWeights[traitID] = repeated ? shrunk : shrunk * 0.65
        }
        for groupName in profile.traitGroupWeights.keys {
            profile.traitGroupWeights[groupName] = (profile.traitGroupWeights[groupName] ?? 0)
                / (1.5 + (traitGroupExposure[groupName] ?? 0))
        }

        var tagExposure: [String: Double] = [:]
        var pairExposure: [String: Double] = [:]
        var releaseEraExposure: [Int: Double] = [:]
        var rawPrototypes: [VNDB兴趣原型] = []
        for item in uniqueProfileItems {
            let signal = item.signal
            guard signal != 0 else { continue }
            var tagVector: [String: Double] = [:]
            let validTags = (item.vn.tags ?? []).filter {
                recommendationEligibleTag($0)
                    && !profile.ignoredTagIDs.contains($0.id)
            }
            let categoryCounts = Dictionary(
                grouping: validTags,
                by: { $0.category ?? "unknown" }
            ).mapValues(\.count)
            for tag in validTags {
                let idf = profile.tagIDF[tag.id] ?? 1
                let categoryScale = 1 / sqrt(Double(
                    max(1, categoryCounts[tag.category ?? "unknown"] ?? 1)
                ))
                let strength = pow(max(0, min(3, tag.rating)) / 3, 1.5)
                    * idf
                    * (profile.tagSpecificity[tag.id] ?? 1)
                    * categoryScale
                    * spoilerReliability(tag.spoiler)
                tagVector[tag.id, default: 0] += strength
                profile.tagWeights[tag.id, default: 0] += signal * strength
                tagExposure[tag.id, default: 0] += abs(signal) * strength
                if tag.spoiler == 0 {
                    profile.tagNames[tag.id] = tag.name
                }
            }

            let pairTags = tagVector.sorted { lhs, rhs in
                if abs(lhs.value - rhs.value) > 0.000_001 {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }.prefix(10).map { ($0.key, $0.value) }
            if pairTags.count >= 2 {
                for lhs in 0..<(pairTags.count - 1) {
                    for rhs in (lhs + 1)..<pairTags.count {
                        let key = pairKey(pairTags[lhs].0, pairTags[rhs].0)
                        let strength = sqrt(pairTags[lhs].1 * pairTags[rhs].1)
                        profile.tagPairWeights[key, default: 0] += signal * strength
                        pairExposure[key, default: 0] += abs(signal) * strength
                    }
                }
            }

            for producer in item.vn.developers ?? [] {
                profile.producerWeights[producer.id, default: 0] += signal
                profile.producerNames[producer.id] = producer.name
            }
            for language in item.vn.languages ?? [] {
                profile.languageWeights[language, default: 0] += signal
            }
            for platform in item.vn.platforms ?? [] {
                profile.platformWeights[platform, default: 0] += signal
            }
            if let length = item.vn.length {
                profile.lengthWeights[length, default: 0] += signal
            }
            if let era = releaseEra(item.vn.released) {
                profile.releaseEraWeights[era, default: 0] += signal
                releaseEraExposure[era, default: 0] += abs(signal)
            }

            guard signal > 0.08 else { continue }
            let traitVector = itemTraits[item.id] ?? [:]
            guard !tagVector.isEmpty || !traitVector.isEmpty else { continue }
            rawPrototypes.append(
                VNDB兴趣原型(
                    tagWeights: normalized(tagVector),
                    traitWeights: normalized(traitVector),
                    confidence: min(1.5, max(0.1, signal))
                )
            )
        }

        for tagID in profile.tagWeights.keys {
            profile.tagWeights[tagID] = (profile.tagWeights[tagID] ?? 0)
                / (1.75 + (tagExposure[tagID] ?? 0))
        }
        let shrunkPairs = profile.tagPairWeights.map { key, value in
            (
                key,
                value / (1.5 + (pairExposure[key] ?? 0))
            )
        }.sorted { abs($0.1) > abs($1.1) }.prefix(80)
        profile.tagPairWeights = Dictionary(uniqueKeysWithValues: shrunkPairs)
        for era in profile.releaseEraWeights.keys {
            profile.releaseEraWeights[era] = (profile.releaseEraWeights[era] ?? 0)
                / (1.5 + (releaseEraExposure[era] ?? 0))
        }
        profile.prototypes = mergedPrototypes(rawPrototypes, limit: 6)

        let gameClusters = mergedPrototypes(
            rawPrototypes.compactMap { prototype in
                guard !prototype.tagWeights.isEmpty else { return nil }
                return VNDB兴趣原型(
                    tagWeights: prototype.tagWeights,
                    traitWeights: [:],
                    confidence: prototype.confidence
                )
            },
            limit: 6
        )
        let gameConfidenceTotal = max(
            0.000_001,
            gameClusters.reduce(0) { $0 + $1.confidence }
        )
        profile.gamePrototypes = gameClusters.map { prototype in
            VNDB游戏兴趣原型(
                tagWeights: prototype.tagWeights,
                confidence: prototype.confidence,
                share: prototype.confidence / gameConfidenceTotal
            )
        }

        let reliableTraitIDs = Set(positiveTraitDocuments.compactMap { traitID, documents in
            独立证据作品数(
                documents,
                seriesScales: seriesScales
            ) >= 2 && (profile.traitWeights[traitID] ?? 0) > 0
                ? traitID
                : nil
        })
        let characterClusters = mergedPrototypes(
            rawPrototypes.compactMap { prototype in
                let reliableTraits = prototype.traitWeights.filter {
                    reliableTraitIDs.contains($0.key)
                }
                guard !reliableTraits.isEmpty else { return nil }
                return VNDB兴趣原型(
                    tagWeights: [:],
                    traitWeights: normalized(reliableTraits),
                    confidence: min(1, prototype.confidence * 0.90)
                )
            },
            limit: 6
        )
        let characterConfidenceTotal = max(
            0.000_001,
            characterClusters.reduce(0) { $0 + $1.confidence }
        )
        profile.characterPrototypes = characterClusters.map { prototype in
            VNDB角色兴趣原型(
                traitWeights: prototype.traitWeights,
                confidence: prototype.confidence,
                share: prototype.confidence / characterConfidenceTotal
            )
        }
        return profile
    }

    private static func 系列证据缩放(
        _ library: [探索用户列表项目],
        feedback: [String: Double]
    ) -> [String: Double] {
        let ids = Set(library.map(\.id))
        guard ids.count > 1 else { return [:] }
        let seriesRelations: Set<String> = [
            "seq", "preq", "side", "par", "ser", "set", "alt"
        ]
        let relatedIDs = Set(library.lazy.flatMap { item in
            (item.vn.relations ?? []).compactMap { relation in
                relation.relationOfficial == true
                    && seriesRelations.contains(relation.relation)
                    ? relation.id
                    : nil
            }
        })
        let allIDs = ids.union(relatedIDs)
        var parent = Dictionary(uniqueKeysWithValues: allIDs.map { ($0, $0) })

        func root(of id: String) -> String {
            var value = id
            while let next = parent[value], next != value {
                value = next
            }
            return value
        }

        func union(_ lhs: String, _ rhs: String) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            guard lhsRoot != rhsRoot else { return }
            if lhsRoot < rhsRoot {
                parent[rhsRoot] = lhsRoot
            } else {
                parent[lhsRoot] = rhsRoot
            }
        }

        for item in library {
            for relation in item.vn.relations ?? []
            where relation.relationOfficial == true
                && seriesRelations.contains(relation.relation) {
                union(item.id, relation.id)
            }
        }

        let groups = Dictionary(grouping: ids, by: { root(of: $0) })
        var result: [String: Double] = [:]
        for group in groups.values where group.count > 1 {
            let positive = group.filter { (feedback[$0] ?? 0) > 0 }
            let negative = group.filter { (feedback[$0] ?? 0) < 0 }
            for sameDirectionGroup in [positive, negative]
            where sameDirectionGroup.count > 1 {
                let ordered = sameDirectionGroup.sorted { lhs, rhs in
                    let lhsMagnitude = abs(feedback[lhs] ?? 0)
                    let rhsMagnitude = abs(feedback[rhs] ?? 0)
                    if abs(lhsMagnitude - rhsMagnitude) > 0.000_001 {
                        return lhsMagnitude > rhsMagnitude
                    }
                    return lhs.localizedStandardCompare(rhs) == .orderedAscending
                }
                guard let representative = ordered.first else { continue }
                result[representative] = 1

                let additionalCount = Double(ordered.count - 1)
                let additionalEvidence = 0.75
                    * (1 - exp(-0.70 * additionalCount))
                let additionalScale = additionalEvidence / additionalCount
                for id in ordered.dropFirst() {
                    result[id] = additionalScale
                }
            }
        }
        return result
    }

    private static func 独立证据作品数(
        _ ids: Set<String>?,
        seriesScales: [String: Double]
    ) -> Int {
        ids?.count { (seriesScales[$0] ?? 1) >= 0.999 } ?? 0
    }

    static func 偏好标签书架(
        candidates: [探索视觉小说],
        profile: VNDB本地推荐画像V2,
        excludedIDs: Set<String>,
        maximumShelves: Int = 4,
        minimumItems: Int = 4
    ) -> [VNDB偏好标签书架] {
        guard maximumShelves > 0, minimumItems > 0 else { return [] }

        let preferredTags = profile.tagWeights.compactMap { tagID, weight
            -> (id: String, name: String, weight: Double)? in
            guard weight > 0.08,
                  let name = profile.tagNames[tagID],
                  !name.isEmpty else { return nil }
            return (tagID, name, weight)
        }.sorted { lhs, rhs in
            if abs(lhs.weight - rhs.weight) > 0.000_001 {
                return lhs.weight > rhs.weight
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }

        var shelves: [VNDB偏好标签书架] = []
        var usedNames: Set<String> = []
        for preferredTag in preferredTags {
            guard usedNames.insert(preferredTag.name).inserted else { continue }
            let items = candidates.compactMap { candidate
                -> (item: 探索视觉小说, relevance: Double)? in
                guard !excludedIDs.contains(candidate.id),
                      !profile.seedIDs.contains(candidate.id) else { return nil }
                let relation = (candidate.tags ?? []).first {
                    $0.id == preferredTag.id
                        && $0.lie != true
                        && $0.spoiler == 0
                }
                guard let relation else { return nil }
                let tagStrength = max(0, min(3, relation.rating)) / 3
                let voteConfidence = min(
                    1,
                    log10(Double(max(1, candidate.voteCount ?? 1))) / 4
                )
                let quality = max(0, ((candidate.rating ?? 50) - 50) / 50)
                return (
                    candidate,
                    (0.80 * tagStrength + 0.20 * quality * voteConfidence)
                        * 受众边界兼容度(candidate, profile: profile)
                )
            }.sorted { lhs, rhs in
                if abs(lhs.relevance - rhs.relevance) > 0.000_001 {
                    return lhs.relevance > rhs.relevance
                }
                return lhs.item.id.localizedStandardCompare(rhs.item.id)
                    == .orderedAscending
            }.map(\.item)

            guard items.count >= minimumItems else { continue }
            shelves.append(
                VNDB偏好标签书架(
                    tagID: preferredTag.id,
                    name: preferredTag.name,
                    items: items
                )
            )
            if shelves.count == maximumShelves { break }
        }
        return shelves
    }

    static func 角色证据按作品分组(
        _ characters: [探索角色]
    ) -> [String: [VNDB候选角色证据]] {
        var result: [String: [VNDB候选角色证据]] = [:]
        for character in characters {
            let traits = (character.traits ?? []).filter {
                $0.lie != true
            }
            for relation in character.visualNovels ?? [] {
                for trait in traits {
                    result[relation.id, default: []].append(
                        VNDB候选角色证据(
                            characterID: character.id,
                            characterName: character.name,
                            traitID: trait.id,
                            traitName: trait.name,
                            groupName: trait.groupName,
                            role: relation.role ?? "appears",
                            reliability: spoilerReliability(relation.spoiler)
                                * spoilerReliability(trait.spoiler),
                            canExplain: relation.spoiler == 0
                                && trait.spoiler == 0
                        )
                    )
                }
            }
        }
        return result
    }

    static func 排序候选(
        _ candidates: [探索视觉小说],
        charactersByVisualNovel: [String: [VNDB候选角色证据]],
        profile: VNDB本地推荐画像V2,
        excludedIDs: Set<String>,
        limit: Int,
        minimumExplorationCount: Int = 8,
        collaborativeScores: [String: Double] = [:]
    ) -> [探索推荐] {
        guard limit > 0, profile.hasPositiveSignal else { return [] }
        let unique = Dictionary(
            candidates.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var scored = unique.values.compactMap { candidate -> Scored? in
            guard !excludedIDs.contains(candidate.id),
                  !profile.seedIDs.contains(candidate.id) else { return nil }
            return evaluate(
                candidate,
                characterEvidence: charactersByVisualNovel[candidate.id] ?? [],
                profile: profile,
                collaborativeScore: collaborativeScores[candidate.id] ?? 0
            )
        }.filter { value in
            value.total > (value.isTypeFallback ? 0.04 : 0.08)
        }
        let seriesKeys = 系列分组(scored.map(\.vn))
        for index in scored.indices {
            scored[index].seriesKey = seriesKeys[scored[index].vn.id]
        }

        var selected: [Scored] = []
        var interestCounts: [Int: Int] = [:]
        var seriesCounts: [String: Int] = [:]
        // 与已选作品的最大相似度随选择增量更新，避免每轮重新比较全部已选作品。
        var maximumSimilarity = [Double](repeating: 0, count: scored.count)
        let reliableCandidateCount = scored.count { !$0.hasSparseEvidence }
        let shouldLimitSparseEvidence = reliableCandidateCount >= min(limit, 12)
        let maximumSparseEvidence = max(2, min(5, limit / 10))
        // 只有类型匹配的候选属于探索项，最多占列表的 15%。
        let primaryCandidateCount = scored.count { !$0.isTypeFallback }
        let shouldLimitFallback = primaryCandidateCount >= min(limit, 12)
        let maximumFallback = max(1, Int((Double(limit) * 0.15).rounded()))
        while selected.count < limit, !scored.isEmpty {
            let sparseSelected = selected.count(where: \.hasSparseEvidence)
            let fallbackSelected = selected.count(where: \.isTypeFallback)
            let evidenceEligibleIndices = scored.indices.filter { index in
                (!shouldLimitSparseEvidence
                    || !scored[index].hasSparseEvidence
                    || sparseSelected < maximumSparseEvidence)
                    && (!shouldLimitFallback
                        || !scored[index].isTypeFallback
                        || fallbackSelected < maximumFallback)
            }
            let seriesEligibleIndices = evidenceEligibleIndices.filter { index in
                guard let seriesKey = scored[index].seriesKey else { return true }
                return (seriesCounts[seriesKey] ?? 0) < 2
            }
            let eligibleIndices = seriesEligibleIndices.isEmpty
                ? evidenceEligibleIndices
                : seriesEligibleIndices
            guard !eligibleIndices.isEmpty else { break }
            func mmrScore(_ index: Int) -> Double {
                let candidate = scored[index]
                let sameSeriesCount = candidate.seriesKey.map {
                    seriesCounts[$0] ?? 0
                } ?? 0
                return candidate.total
                    - 0.08 * maximumSimilarity[index]
                    - 0.18 * Double(sameSeriesCount)
                    - 0.02 * Double(interestCounts[candidate.interestIndex] ?? 0)
            }
            let bestIndex = eligibleIndices.max { lhs, rhs in
                let lhsScore = mmrScore(lhs)
                let rhsScore = mmrScore(rhs)
                if abs(lhsScore - rhsScore) < 0.000_001 {
                    return scored[lhs].vn.id > scored[rhs].vn.id
                }
                return lhsScore < rhsScore
            }!
            let choice = scored.remove(at: bestIndex)
            maximumSimilarity.remove(at: bestIndex)
            selected.append(choice)
            interestCounts[choice.interestIndex, default: 0] += 1
            if let seriesKey = choice.seriesKey {
                seriesCounts[seriesKey, default: 0] += 1
            }
            for index in scored.indices {
                maximumSimilarity[index] = max(
                    maximumSimilarity[index],
                    candidateSimilarity(scored[index].features, choice.features)
                )
            }
        }

        let requestedExplorationCount = min(
            max(0, minimumExplorationCount),
            max(0, selected.count - 1)
        )
        let naturalExploration = selected.filter(\.isTypeFallback).count
        let additionalExploration = max(
            0,
            requestedExplorationCount - naturalExploration
        )
        let additionalExplorationIDs = Set(
            selected.filter { !$0.isTypeFallback }
                .sorted { lhs, rhs in
                    if abs(lhs.total - rhs.total) > 0.000_001 {
                        return lhs.total < rhs.total
                    }
                    return lhs.vn.id.localizedStandardCompare(rhs.vn.id)
                        == .orderedAscending
                }
                .prefix(additionalExploration)
                .map { $0.vn.id }
        )

        return selected.map { value in
            let tagNames = value.strongestTagIDs.compactMap { profile.tagNames[$0] }
            let traitNames = value.strongestTraitIDs.compactMap { profile.traitNames[$0] }
            let isExploration = value.isTypeFallback
                || additionalExplorationIDs.contains(value.vn.id)
            let confidence: 探索推荐置信度 = if isExploration {
                .exploratory
            } else if value.total >= 0.55 && (value.character ?? 0) >= 0.35 {
                .high
            } else {
                .medium
            }
            return 探索推荐(
                visualNovel: value.vn,
                score: value.total,
                reason: reason(for: value, profile: profile),
                evidence: 探索推荐证据(
                    gameTags: tagNames,
                    characterID: value.characterID,
                    characterName: value.characterName,
                    characterTraits: traitNames,
                    gameScore: value.game,
                    characterScore: value.character,
                    collaborativeScore: value.collaborative > 0
                        ? value.collaborative
                        : nil,
                    confidence: confidence,
                    isExploration: isExploration,
                    hasCharacterData: true
                )
            )
        }
    }

    private struct Scored {
        let vn: 探索视觉小说
        let total: Double
        let game: Double
        let character: Double?
        let collaborative: Double
        let metadata: Double
        let interestIndex: Int
        let strongestTagIDs: [String]
        let strongestTraitIDs: [String]
        let characterID: String?
        let characterName: String?
        let hasImportantCharacterMatch: Bool
        let isTypeFallback: Bool
        let hasSparseEvidence: Bool
        let features: 相似度特征
        var seriesKey: String?
    }

    private struct 相似度特征 {
        let tagIDs: Set<String>
        let producerIDs: Set<String>

        init(_ vn: 探索视觉小说) {
            tagIDs = Set((vn.tags ?? []).filter { $0.lie != true }.map(\.id))
            producerIDs = Set((vn.developers ?? []).map(\.id))
        }
    }

    private static func evaluate(
        _ vn: 探索视觉小说,
        characterEvidence: [VNDB候选角色证据],
        profile: VNDB本地推荐画像V2,
        collaborativeScore: Double
    ) -> Scored? {
        var tags: [String: Double] = [:]
        var matchedTags: [(String, Double)] = []
        var tagInformationMass = 0.0
        var matchedTagInformationMass = 0.0
        var nonTechnicalTagInformationMass = 0.0
        var nonTechnicalSpecificTagCount = 0
        var visualPresentationPreferenceMatch = 0.0
        let strongestPositiveTagWeight = max(
            0.000_001,
            profile.tagWeights.values.filter { $0 > 0 }.max() ?? 0
        )
        let validTags = (vn.tags ?? []).filter {
            recommendationEligibleTag($0)
                && !profile.ignoredTagIDs.contains($0.id)
        }
        let categoryCounts = Dictionary(
            grouping: validTags,
            by: { $0.category ?? "unknown" }
        ).mapValues(\.count)
        for tag in validTags {
            let categoryScale = 1 / sqrt(Double(
                max(1, categoryCounts[tag.category ?? "unknown"] ?? 1)
            ))
            let ratingStrength = pow(max(0, min(3, tag.rating)) / 3, 1.5)
            let specificity = profile.tagSpecificity[tag.id] ?? 1
            let reliability = spoilerReliability(tag.spoiler)
            let value = ratingStrength
                * (profile.tagIDF[tag.id] ?? 1)
                * specificity
                * categoryScale
                * reliability
            tags[tag.id, default: 0] += value
            tagInformationMass += ratingStrength * specificity * reliability
            if tag.category != "tech" {
                let information = ratingStrength * specificity * reliability
                nonTechnicalTagInformationMass += information
                if information >= 0.40 {
                    nonTechnicalSpecificTagCount += 1
                }
            }
            let preference = max(0, profile.tagWeights[tag.id] ?? 0)
            if preference > 0, isVisualPresentationTag(tag) {
                visualPresentationPreferenceMatch = max(
                    visualPresentationPreferenceMatch,
                    min(1, preference / strongestPositiveTagWeight)
                )
            }
            if preference > 0, tag.spoiler == 0 {
                matchedTags.append((tag.id, value * preference))
                let relativePreference = min(
                    1,
                    preference / strongestPositiveTagWeight
                )
                matchedTagInformationMass += ratingStrength
                    * specificity
                    * reliability
                    * relativePreference
            }
        }
        tags = normalized(tags)
        let strongestTagIDs = matchedTags.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)

        let pairTags = tags.sorted { $0.value > $1.value }
            .prefix(10).map { ($0.key, $0.value) }
        var positivePairScore = 0.0
        var negativePairPenalty = 0.0
        if pairTags.count >= 2 {
            for lhs in 0..<(pairTags.count - 1) {
                for rhs in (lhs + 1)..<pairTags.count {
                    let weight = profile.tagPairWeights[
                        pairKey(pairTags[lhs].0, pairTags[rhs].0)
                    ] ?? 0
                    let strength = sqrt(pairTags[lhs].1 * pairTags[rhs].1)
                    positivePairScore += max(0, weight) * strength
                    negativePairPenalty += abs(min(0, weight)) * strength
                }
            }
        }
        positivePairScore = clampPositive(positivePairScore)

        var characters: [(
            id: String,
            name: String,
            role: String,
            traits: [String: Double],
            explainableTraitIDs: Set<String>
        )] = []
        let maximumTraitGroupMagnitude = profile.traitGroupWeights.values
            .map { abs($0) }.max() ?? 0
        for group in Dictionary(grouping: characterEvidence, by: \.characterID).values {
            guard let first = group.first else { continue }
            let role = group.max { roleWeight($0.role) < roleWeight($1.role) }?.role ?? first.role
            var traitsByGroup: [String: [(String, Double)]] = [:]
            var explainableTraitIDs: Set<String> = []
            for evidence in group {
                let idf = profile.traitIDF[evidence.traitID] ?? 1
                traitsByGroup[evidence.groupName, default: []].append((
                    evidence.traitID,
                    idf * evidence.reliability
                ))
                if evidence.canExplain {
                    explainableTraitIDs.insert(evidence.traitID)
                }
            }
            var vector: [String: Double] = [:]
            for (groupName, traits) in traitsByGroup {
                let groupScale = 1 / sqrt(Double(max(1, traits.count)))
                let groupSalience = maximumTraitGroupMagnitude > 0
                    ? min(
                        1,
                        abs(profile.traitGroupWeights[groupName] ?? 0)
                            / maximumTraitGroupMagnitude
                    )
                    : 0
                for (traitID, idf) in traits {
                    vector[traitID, default: 0] += idf
                        * groupScale
                        * (1 + 0.35 * groupSalience)
                }
            }
            characters.append((
                first.characterID,
                first.characterName,
                role,
                normalized(vector),
                explainableTraitIDs
            ))
        }

        var bestIndex = 0
        var bestGame = -1.0
        for (index, prototype) in profile.gamePrototypes.enumerated() {
            let game = max(0, cosine(tags, prototype.tagWeights))
            if game > bestGame {
                bestIndex = index
                bestGame = game
            }
        }
        if profile.gamePrototypes.isEmpty {
            for (index, prototype) in profile.prototypes.enumerated() {
                let game = max(0, cosine(tags, prototype.tagWeights))
                if game > bestGame {
                    bestIndex = index
                    bestGame = game
                }
            }
        }
        let matchedTagCount = Set(matchedTags.map(\.0)).count
        let tagCountConfidence = min(1, Double(validTags.count) / 8)
        let tagInformationConfidence = min(1, tagInformationMass / 4)
        let matchedTagConfidence = min(1, Double(matchedTagCount) / 3)
        let matchedTagInformationConfidence = min(
            1,
            matchedTagInformationMass / 1.75
        )
        let tagEvidenceConfidence = pow(
            tagCountConfidence
                * tagInformationConfidence
                * matchedTagConfidence
                * matchedTagInformationConfidence,
            0.25
        )
        let preferenceSupportConfidence = matchedTagConfidence
        bestGame = clampPositive(
            0.82 * max(0, bestGame) + 0.18 * positivePairScore
        ) * tagEvidenceConfidence * preferenceSupportConfidence

        var rankedCharacters: [(
            id: String,
            name: String,
            role: String,
            score: Double,
            matchedTraits: [String],
            allTraits: [String: Double]
        )] = []
        let positiveTraitWeights = profile.traitWeights.filter { $0.value > 0 }
        let positiveTraitVector = normalized(positiveTraitWeights)
        let strongestPositiveTrait = positiveTraitWeights.values.max() ?? 0
        let positiveTraitMass = positiveTraitWeights.values.reduce(0, +)
        let directTraitConfidence = min(
            1,
            2 * strongestPositiveTrait + 0.25 * positiveTraitMass
        )
        for character in characters {
            var prototypeMatch = 0.0
            for prototype in profile.characterPrototypes {
                prototypeMatch = max(
                    prototypeMatch,
                    cosine(character.traits, prototype.traitWeights)
                )
            }
            let directTraitMatch = max(
                0,
                cosine(character.traits, positiveTraitVector)
            ) * directTraitConfidence
            let preferenceMatch = max(prototypeMatch, directTraitMatch)
            let matchedTraits = character.traits.compactMap { traitID, weight -> (String, Double)? in
                let preference = max(0, profile.traitWeights[traitID] ?? 0)
                return preference > 0 && character.explainableTraitIDs.contains(traitID)
                    ? (traitID, weight * preference)
                    : nil
            }.sorted { $0.1 > $1.1 }.prefix(3).map(\.0)
            // 只标了一两个特征的角色，余弦会因为单个特征重合而虚高；
            // 按特征数量收缩，资料完整的角色几乎不受影响。
            let traitCount = Double(character.traits.count)
            let traitEvidence = sqrt(traitCount / (traitCount + 10))
            rankedCharacters.append((
                character.id,
                character.name,
                character.role,
                max(0, preferenceMatch) * roleWeight(character.role) * traitEvidence,
                matchedTraits,
                character.traits
            ))
        }
        rankedCharacters.sort { $0.score > $1.score }
        let bestCharacter = rankedCharacters.first
        let secondCharacterScore = rankedCharacters.dropFirst().first?.score ?? 0
        let characterScore: Double? = bestCharacter.map {
            min(1, 0.8 * $0.score + 0.2 * secondCharacterScore)
        }
        let hasImportantCharacterMatch = bestCharacter.map {
            ($0.role == "main" || $0.role == "primary") && $0.score >= 0.20
        } ?? false
        let technicalTagCount = validTags.count { $0.category == "tech" }
        let nonTechnicalTagCount = validTags.count - technicalTagCount
        let isTechnicalOnlySparseCandidate = technicalTagCount >= 3
            && technicalTagCount >= max(3, nonTechnicalTagCount)
            && (nonTechnicalSpecificTagCount < 3
                || nonTechnicalTagInformationMass < 1.50)
        if isTechnicalOnlySparseCandidate {
            // 几乎只有技术标签时，游戏匹配主要来自格式而不是内容。
            bestGame *= 0.4
        }
        let boundaryPenalty = 0.35 * (1 - 受众边界兼容度(vn, profile: profile))

        let historicalPresentation = historicalPresentationAssessment(
            vn,
            profile: profile,
            visualPresentationPreferenceMatch: visualPresentationPreferenceMatch
        )
        let lacksPreferredCharacterEvidence = profile.hasReliableCharacterSignal
            && !hasImportantCharacterMatch
        let negativeTagPenalty = abs(tags.reduce(0.0) {
            $0 + min(0, profile.tagWeights[$1.key] ?? 0) * $1.value
        })
        let negativePrimaryTraitPenalty = characters.reduce(0.0) { result, character in
            guard character.role == "main" || character.role == "primary" else {
                return result
            }
            let penalty = abs(character.traits.reduce(0.0) {
                $0 + min(0, profile.traitWeights[$1.key] ?? 0) * $1.value
            }) * roleWeight(character.role)
            return max(result, penalty)
        }
        let negativePairEvidence = min(1, negativePairPenalty)
        let aversionEvidence = min(
            1,
            negativeTagPenalty
                + 0.75 * negativePrimaryTraitPenalty
                + 0.45 * negativePairEvidence
        )
        let collaborative = clampPositive(collaborativeScore)
            * max(0.05, 1 - 2.5 * aversionEvidence)
        let voteCount = max(0, vn.voteCount ?? 0)
        // 协同分已经按证据多少自然收缩，不再另设票数、评分和标签数门槛。
        let hasReliableCollaborativeEvidence = collaborative >= 0.72
            && historicalPresentation.allowsCollaborativeFallback
        let passesJointGate = bestGame >= 0.18
            && (characterScore ?? 0) >= 0.20
            && hasImportantCharacterMatch
        let hasPositiveGameOverlap = bestGame > 0 && !strongestTagIDs.isEmpty
        let hasPositiveCharacterOverlap = hasImportantCharacterMatch
        let hasDirectPreferenceEvidence = hasPositiveGameOverlap
            || hasPositiveCharacterOverlap
        let isTypeFallback = !passesJointGate && hasDirectPreferenceEvidence
        let isCollaborativeFallback = !passesJointGate
            && !isTypeFallback
            && hasReliableCollaborativeEvidence
        let core: Double
        if passesJointGate, let characterScore {
            let joint = pow(bestGame, 0.45) * pow(characterScore, 0.55)
            core = 0.88 * joint + 0.12 * collaborative
        } else if isTypeFallback {
            let gameFallbackWeight = profile.hasReliableCharacterSignal
                ? 0.48
                : 0.60
            // 只有一侧匹配时减半，始终排在同等强度的双匹配之后。
            core = 0.5 * max(
                bestGame * gameFallbackWeight,
                (characterScore ?? 0) * 0.72,
                collaborative * 0.42
            )
        } else if isCollaborativeFallback {
            core = collaborative * 0.55
        } else {
            core = 0
        }

        let producer = maxMatch(
            (vn.developers ?? []).map(\.id),
            weights: profile.producerWeights
        )
        let language = maxMatch(vn.languages ?? [], weights: profile.languageWeights)
        let platform = maxMatch(vn.platforms ?? [], weights: profile.platformWeights)
        let length = vn.length.map { profile.lengthWeights[$0] ?? 0 } ?? 0
        let releaseEra = releaseEra(vn.released).map {
            clampPositive(profile.releaseEraWeights[$0] ?? 0)
        } ?? 0
        let metadata = clampPositive(
            0.12 * producer
                + 0.28 * language
                + 0.28 * platform
                + 0.12 * length
                + 0.20 * releaseEra
        )
        let voteConfidence = min(1, log10(Double(max(1, vn.voteCount ?? 1))) / 4)
        let quality = clampPositive(((vn.rating ?? 50) - 50) / 50) * voteConfidence
        let evidenceConfidence = min(
            1,
            log1p(Double(voteCount)) / log(101)
        )
        let ratingQuality: Double
        if let rating = vn.rating, voteCount >= 3 {
            ratingQuality = min(1, max(-1, (rating - 60) / 25))
        } else {
            ratingQuality = -0.20
        }
        let sparseEvidencePenalty: Double = switch voteCount {
        case 0...2: 0.16
        case 3...9: 0.09
        case 10...24: 0.04
        default: 0
        }
        let lowRatingPenalty = max(0, -ratingQuality) * (0.12 + 0.08 * evidenceConfidence)
        var total = max(
            0,
            core * (0.90 + 0.10 * quality)
                + 0.04 * metadata
                + 0.06 * collaborative * evidenceConfidence
                - 0.75 * min(
                    1,
                    negativeTagPenalty
                        + 0.75 * negativePrimaryTraitPenalty
                        + 0.45 * negativePairEvidence
                )
                - sparseEvidencePenalty
                - lowRatingPenalty
                - historicalPresentation.penalty
                - boundaryPenalty
                - (isTypeFallback ? 0.02 : 0)
        )
        if lacksPreferredCharacterEvidence {
            total = min(total, 0.42)
        }
        return Scored(
            vn: vn,
            total: total,
            game: max(0, bestGame),
            character: characterScore,
            collaborative: collaborative,
            metadata: metadata,
            interestIndex: bestIndex,
            strongestTagIDs: strongestTagIDs,
            strongestTraitIDs: bestCharacter?.matchedTraits ?? [],
            characterID: bestCharacter?.id,
            characterName: bestCharacter?.name,
            hasImportantCharacterMatch: hasImportantCharacterMatch,
            isTypeFallback: isTypeFallback,
            hasSparseEvidence: voteCount < 10
                || vn.rating == nil
                || lacksPreferredCharacterEvidence
                || validTags.count < 4
                || tagInformationMass < 1.75,
            features: 相似度特征(vn),
            seriesKey: nil
        )
    }

    private static func reason(
        for value: Scored,
        profile: VNDB本地推荐画像V2
    ) -> 探索推荐理由 {
        let tags = value.strongestTagIDs.compactMap { profile.tagNames[$0] }
        let traits = value.strongestTraitIDs.compactMap { profile.traitNames[$0] }
        if value.collaborative > 0.15,
           value.collaborative >= max(value.game, value.character ?? 0) {
            return .similarUsers
        }
        if value.hasImportantCharacterMatch, !tags.isEmpty, !traits.isEmpty {
            return .typeAndCharacter(
                tags: tags,
                character: value.characterName,
                traits: traits
            )
        }
        if value.isTypeFallback,
           !value.hasImportantCharacterMatch,
           !tags.isEmpty {
            return .mainlyType(tags: tags)
        }
        if let tag = tags.first { return .sharedTag(tag) }
        if let trait = traits.first { return .preferredCharacterTrait(trait) }
        return .highlyRated
    }

    private static func feedback(
        for item: 探索用户列表项目,
        medianVote: Double?,
        voteScale: Double,
        hasReliableVoteDistribution: Bool
    ) -> Double {
        let statusSignal = 状态信号(item)
        if let vote = item.vote {
            let center = hasReliableVoteDistribution
                ? (medianVote ?? 70)
                : 70
            let scale = hasReliableVoteDistribution ? voteScale : 15
            let confidence = hasReliableVoteDistribution ? 1.0 : 0.75
            var ratingSignal = tanh((Double(vote) - center) / scale)
                * confidence
            if ratingSignal < 0 {
                // 70–80 分在 VNDB 上仍是好评，只是低于用户自己的中位数；
                // 只算作很弱的负面证据，明确的低分才是真正的负面。
                ratingSignal *= min(1, max(0.2, (80 - Double(vote)) / 30))
            }
            return min(1, max(-1, 0.90 * ratingSignal + 0.10 * statusSignal))
        }
        return statusSignal
    }

    /// 没有评分时，资料库状态代表的偏好信号；协同过滤折入也使用它。
    static func 状态信号(_ item: 探索用户列表项目) -> Double {
        let statusIDs = Set((item.labels ?? []).map(\.id))
        return if statusIDs.contains(4) {
            -0.45
        } else if statusIDs.contains(3) {
            -0.08
        } else if statusIDs.contains(5) {
            0.30
        } else if statusIDs.contains(2) || item.finished != nil {
            0.20
        } else if statusIDs.contains(1) || item.started != nil {
            0.12
        } else {
            0
        }
    }

    private static func recommendationEligibleTag(
        _ tag: 探索标签关联
    ) -> Bool {
        tag.lie != true
    }

    /// 乙女、BL、百合和写实 3D 是明确的受众边界。资料库里有足够正面证据时不扣分；
    /// 完全没有接触过时扣分足以让它们几乎不出现，但不再硬性排除。
    private static func 受众边界兼容度(
        _ vn: 探索视觉小说,
        profile: VNDB本地推荐画像V2
    ) -> Double {
        Set((vn.tags ?? []).compactMap(audienceBoundaryKey)).reduce(1.0) {
            compatibility, boundary in
            let evidence = profile.audienceEvidence[boundary] ?? 0
            let acceptance = profile.audienceAcceptance[boundary] ?? 0
            return min(
                compatibility,
                min(1, evidence / 0.18) * min(1, acceptance / 0.18)
            )
        }
    }

    private static func audienceBoundaryKey(
        _ tag: 探索标签关联
    ) -> String? {
        guard tag.lie != true else { return nil }
        switch tag.id {
        case "g542", "g3432": return "otome"
        case "g98", "g2002", "g2846": return "male-male-romance"
        case "g97", "g1986", "g2300": return "female-female-romance"
        case "g2693", "g3723": return "realistic-3d"
        default:
            let name = tag.name.lowercased()
            if name.contains("otome game") { return "otome" }
            if name.contains("boy x boy romance")
                || name.contains("yaoi game") { return "male-male-romance" }
            if name.contains("girl x girl romance")
                || name.contains("yuri game") { return "female-female-romance" }
            if name == "pre-rendered 3d graphics"
                || name == "realistic-looking 3d"
                || name == "预渲染3d图像"
                || name == "预渲染3d图形"
                || name == "写实风格3d" { return "realistic-3d" }
            return nil
        }
    }

    private static func historicalExperienceConfidence(
        _ item: 探索用户列表项目
    ) -> Double {
        let statusIDs = Set((item.labels ?? []).map(\.id))
        if item.vote != nil || item.finished != nil || statusIDs.contains(2) {
            return 1
        }
        if item.started != nil || statusIDs.contains(1) { return 0.75 }
        if statusIDs.contains(4) { return 1 }
        if statusIDs.contains(3) { return 0.55 }
        return 0
    }

    private static func audienceExperienceConfidence(
        _ item: 探索用户列表项目
    ) -> Double {
        let statusIDs = Set((item.labels ?? []).map(\.id))
        if statusIDs.contains(5) { return 0.75 }
        return historicalExperienceConfidence(item)
    }

    /// 高分老作品也是接受古早画风的证据。热门作品可能因名气才被玩，
    /// 权重略低，但不再几乎被忽略。
    private static func historicalWorkDistinctiveness(
        voteCount: Int?
    ) -> Double {
        guard let voteCount, voteCount > 0 else { return 0.5 }
        switch voteCount {
        case ...50: return 1
        case ...150: return 0.9
        case ...500: return 0.75
        case ...1_500: return 0.6
        default: return 0.5
        }
    }

    private static func historicalPresentationAssessment(
        _ vn: 探索视觉小说,
        profile: VNDB本地推荐画像V2,
        visualPresentationPreferenceMatch: Double
    ) -> (penalty: Double, allowsCollaborativeFallback: Bool) {
        guard let year = releaseYear(vn.released) else { return (0.03, true) }
        // 画风只是次要因素，最多扣 0.08，不能抵消明确的内容匹配。
        let tier: (cutoff: Int, maximumPenalty: Double)? = switch year {
        case ...1999: (1999, 0.08)
        case ...2004: (2004, 0.07)
        case ...2009: (2009, 0.05)
        case ...2014: (2014, 0.02)
        default: nil
        }
        guard let tier else { return (0, true) }
        let evidence = profile.historicalPresentationEvidence[tier.cutoff] ?? 0
        let acceptance = profile.historicalPresentationAcceptance[tier.cutoff] ?? 0
        let evidenceConfidence = min(1, evidence / 1.20)
        let demonstratedAcceptance = acceptance * evidenceConfidence
        let compatibility = max(
            demonstratedAcceptance,
            0.75 * visualPresentationPreferenceMatch
        )
        let penalty = tier.maximumPenalty * (1 - min(1, compatibility))
        let allowsCollaborativeFallback = year >= 2010
            || compatibility >= 0.22
            || (evidence >= 0.55 && acceptance >= 0.20)
        return (penalty, allowsCollaborativeFallback)
    }

    private static func isVisualPresentationTag(
        _ tag: 探索标签关联
    ) -> Bool {
        guard tag.category == "tech" else { return false }
        let name = tag.name.lowercased()
        return name.contains("graphic")
            || name.contains("photograph")
            || name.contains("photos only")
            || name.contains("pixel art")
            || name.contains("3d")
            || name.contains("2d")
            || ((name.contains("animated") || name.contains("animation"))
                && (name.contains("sprite")
                    || name.contains("graphic")
                    || name.contains("cg")))
            || name.contains("visual style")
            || name.contains("art style")
            || name.contains("illustration")
            || (name.contains("background") && !name.contains("music"))
            || name.contains(" cgs")
            || name.hasPrefix("cgs")
            || name == "no character sprites"
            || name == "lots of character sprites"
            || name == "stock sprites"
            || name == "super deformed sprites"
            || name == "minimalist sprites"
    }

    private static func tagSpecificity(
        globalFrequency: Int?,
        globalDocumentCount: Int?
    ) -> Double {
        var result = 1.0
        if let ratio = tagGlobalRatio(
            frequency: globalFrequency,
            documentCount: globalDocumentCount
        ) {
            result = min(result, frequencySpecificity(ratio, commonFrom: 0.02))
        }
        return result
    }

    private static func tagGlobalRatio(
        frequency: Int?,
        documentCount: Int?
    ) -> Double? {
        guard let frequency, let documentCount, documentCount > 0 else {
            return nil
        }
        return Double(frequency) / Double(documentCount)
    }

    private static func frequencySpecificity(
        _ ratio: Double,
        commonFrom: Double = 0.02
    ) -> Double {
        let upperBound = 0.30
        guard ratio > commonFrom else { return 1 }
        let progress = min(
            1,
            (ratio - commonFrom) / max(0.01, upperBound - commonFrom)
        )
        return max(0.08, 1 - 0.92 * progress)
    }

    private static func spoilerReliability(_ spoiler: Int?) -> Double {
        switch spoiler ?? 0 {
        case 1: 0.90
        case 2...: 0.80
        default: 1
        }
    }

    private static func pairKey(_ lhs: String, _ rhs: String) -> String {
        lhs < rhs ? "\(lhs)|\(rhs)" : "\(rhs)|\(lhs)"
    }

    private static func releaseEra(_ released: String?) -> Int? {
        guard let year = releaseYear(released) else { return nil }
        return year - year % 5
    }

    private static func releaseYear(_ released: String?) -> Int? {
        guard let released,
              released.count >= 4,
              let year = Int(released.prefix(4)),
              year >= 1970,
              year <= 2100 else { return nil }
        return year
    }

    private static func roleWeight(_ role: String?) -> Double {
        switch role {
        case "main": return 1
        case "primary": return 0.85
        case "side": return 0.45
        default: return 0.20
        }
    }

    private static func mergedPrototypes(
        _ source: [VNDB兴趣原型],
        limit: Int
    ) -> [VNDB兴趣原型] {
        var values = source
        let mergeThreshold = 0.42
        while values.count > 1 {
            var pair = (0, 1)
            var similarity = -Double.infinity
            for lhs in values.indices {
                for rhs in values.indices where rhs > lhs {
                    let value = 0.75 * cosine(
                        values[lhs].tagWeights,
                        values[rhs].tagWeights
                    ) + 0.25 * cosine(
                        values[lhs].traitWeights,
                        values[rhs].traitWeights
                    )
                    if value > similarity {
                        similarity = value
                        pair = (lhs, rhs)
                    }
                }
            }
            guard values.count > limit || similarity >= mergeThreshold else { break }
            let rhs = values.remove(at: pair.1)
            let lhs = values.remove(at: pair.0)
            values.append(merge(lhs, rhs))
        }
        return values.sorted { $0.confidence > $1.confidence }
    }

    private static func merge(
        _ lhs: VNDB兴趣原型,
        _ rhs: VNDB兴趣原型
    ) -> VNDB兴趣原型 {
        let total = lhs.confidence + rhs.confidence
        var tags = lhs.tagWeights.mapValues { $0 * lhs.confidence }
        for (key, value) in rhs.tagWeights {
            tags[key, default: 0] += value * rhs.confidence
        }
        var traits = lhs.traitWeights.mapValues { $0 * lhs.confidence }
        for (key, value) in rhs.traitWeights {
            traits[key, default: 0] += value * rhs.confidence
        }
        return VNDB兴趣原型(
            tagWeights: normalized(tags.mapValues { $0 / total }),
            traitWeights: normalized(traits.mapValues { $0 / total }),
            confidence: min(3, total)
        )
    }

    private static func 系列分组(
        _ candidates: [探索视觉小说]
    ) -> [String: String] {
        let candidateIDs = Set(candidates.map(\.id))
        let seriesRelations: Set<String> = [
            "seq", "preq", "side", "par", "ser", "set", "alt"
        ]
        let relatedIDs = Set(candidates.lazy.flatMap { candidate in
            (candidate.relations ?? []).compactMap { relation in
                relation.relationOfficial == true
                    && seriesRelations.contains(relation.relation)
                    ? relation.id
                    : nil
            }
        })
        let allIDs = candidateIDs.union(relatedIDs)
        guard !allIDs.isEmpty else { return [:] }
        var parent = Dictionary(uniqueKeysWithValues: allIDs.map { ($0, $0) })

        func root(of id: String) -> String {
            var value = id
            while let next = parent[value], next != value {
                value = next
            }
            return value
        }

        func union(_ lhs: String, _ rhs: String) {
            let lhsRoot = root(of: lhs)
            let rhsRoot = root(of: rhs)
            guard lhsRoot != rhsRoot else { return }
            if lhsRoot < rhsRoot {
                parent[rhsRoot] = lhsRoot
            } else {
                parent[lhsRoot] = rhsRoot
            }
        }

        for candidate in candidates {
            for relation in candidate.relations ?? []
            where relation.relationOfficial == true
                && seriesRelations.contains(relation.relation) {
                union(candidate.id, relation.id)
            }
        }

        let fallbackBuckets = Dictionary(grouping: candidates) { candidate in
            guard let titleKey = 系列标题键(candidate) else { return "" }
            let developerKey = (candidate.developers ?? []).map(\.id)
                .sorted().joined(separator: ",")
            guard !developerKey.isEmpty else { return "" }
            return "\(developerKey)|\(titleKey)"
        }
        for (key, bucket) in fallbackBuckets where !key.isEmpty && bucket.count > 1 {
            let ordered = bucket.sorted {
                $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
            for index in ordered.indices where index > 0 {
                let comparisonStart = max(0, index - 16)
                for earlierIndex in comparisonStart..<index
                where candidateSimilarity(
                    ordered[index],
                    ordered[earlierIndex]
                ) >= 0.78 {
                    union(ordered[index].id, ordered[earlierIndex].id)
                    break
                }
            }
        }
        return Dictionary(uniqueKeysWithValues: candidateIDs.map {
            ($0, root(of: $0))
        })
    }

    private static func 系列标题键(_ vn: 探索视觉小说) -> String? {
        let ignoredWords: Set<String> = [
            "the", "a", "an", "episode", "ep", "chapter", "chap",
            "volume", "vol", "part", "side", "route", "season",
            "edition", "version", "ver", "remake", "st", "nd", "rd", "th"
        ]
        for title in [vn.title, vn.alttitle].compactMap({ $0 }) {
            let folded = title.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            let tokens = folded.components(
                separatedBy: CharacterSet.letters.inverted
            ).filter { !$0.isEmpty && !ignoredWords.contains($0) }
            guard let first = tokens.first else { continue }
            let hasNonASCII = first.unicodeScalars.contains { !$0.isASCII }
            if (hasNonASCII && first.count >= 2) || first.count >= 5 {
                return first
            }
        }
        return nil
    }

    private static func candidateSimilarity(
        _ lhs: 探索视觉小说,
        _ rhs: 探索视觉小说
    ) -> Double {
        candidateSimilarity(相似度特征(lhs), 相似度特征(rhs))
    }

    private static func candidateSimilarity(
        _ lhs: 相似度特征,
        _ rhs: 相似度特征
    ) -> Double {
        let shared = lhs.tagIDs.intersection(rhs.tagIDs).count
        let unionCount = lhs.tagIDs.count + rhs.tagIDs.count - shared
        let tagSimilarity = unionCount == 0
            ? 0
            : Double(shared) / Double(unionCount)
        let producerMatch = lhs.producerIDs.isDisjoint(with: rhs.producerIDs)
            ? 0.0
            : 1.0
        return 0.82 * tagSimilarity + 0.18 * producerMatch
    }

    private static func normalized(_ source: [String: Double]) -> [String: Double] {
        let norm = sqrt(source.values.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return [:] }
        return source.mapValues { $0 / norm }
    }

    private static func cosine(
        _ lhs: [String: Double],
        _ rhs: [String: Double]
    ) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let smaller = lhs.count <= rhs.count ? lhs : rhs
        let larger = lhs.count <= rhs.count ? rhs : lhs
        return smaller.reduce(0) { $0 + $1.value * (larger[$1.key] ?? 0) }
    }

    private static func maxMatch(
        _ keys: [String],
        weights: [String: Double]
    ) -> Double {
        clampPositive(keys.map { weights[$0] ?? 0 }.max() ?? 0)
    }

    private static func clampPositive(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
