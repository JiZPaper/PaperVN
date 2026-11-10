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
