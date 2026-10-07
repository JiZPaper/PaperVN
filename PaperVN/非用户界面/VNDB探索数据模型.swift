import Foundation

struct 探索多语言标题: Codable, Hashable, Sendable {
    let lang: String
    let title: String
    let latin: String?
    let official: Bool?
    let main: Bool?
}

struct 探索图片: Codable, Hashable, Sendable {
    let id: String?
    let url: String?
    let thumbnail: String?
    let dims: [Int]?
    let sexual: Double?
    let violence: Double?
}

struct 探索外链: Codable, Hashable, Sendable {
    let url: String
    let label: String
    let name: String?
    let id: 探索外链标识?
}

enum 探索外链标识: Codable, Hashable, Sendable {
    case string(String)
    case integer(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .integer(try container.decode(Int.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .integer(value): try container.encode(value)
        }
    }
}

struct 探索标签关联: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let rating: Double
    let spoiler: Int
    let lie: Bool?
    let category: String?
}

struct 探索会社摘要: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let lang: String?
    let type: String?
}

struct 探索视觉小说关系: Codable, Hashable, Sendable {
    let id: String
    let relation: String
    let relationOfficial: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, relation
        case relationOfficial = "relation_official"
    }
}

struct 探索视觉小说: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let alttitle: String?
    let titles: [探索多语言标题]?
    let aliases: [String]?
    let released: String?
    let languages: [String]?
    let platforms: [String]?
    let image: 探索图片?
    let length: Int?
    let lengthMinutes: Int?
    let rating: Double?
    let voteCount: Int?
    let tags: [探索标签关联]?
    let developers: [探索会社摘要]?
    let relations: [探索视觉小说关系]?

    private enum CodingKeys: String, CodingKey {
        case id, title, alttitle, titles, aliases, released, languages, platforms
        case image, length, rating, tags, developers, relations
        case lengthMinutes = "length_minutes"
        case voteCount = "votecount"
    }
}

struct 探索发行语言: Codable, Hashable, Sendable {
    let lang: String
    let title: String?
    let latin: String?
    let mtl: Bool?
    let main: Bool?
}

struct 探索发行介质: Codable, Hashable, Sendable {
    let medium: String
    let quantity: Int

    private enum CodingKeys: String, CodingKey {
        case medium
        case quantity = "qty"
    }
}

struct 探索发行作品: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let titles: [探索多语言标题]?
    let image: 探索图片?
    let releaseType: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, titles, image
        case releaseType = "rtype"
    }
}

struct 探索发行会社: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let developer: Bool?
    let publisher: Bool?
}

struct 探索发行图片: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let url: String?
    let thumbnail: String?
    let dims: [Int]?
    let sexual: Double?
    let violence: Double?
    let type: String?
    let visualNovelID: String?
    let languages: [String]?
    let photo: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, url, thumbnail, dims, sexual, violence, type, languages, photo
        case visualNovelID = "vn"
    }
}

enum 探索发行分辨率: Codable, Hashable, Sendable {
    case dimensions([Int])
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([Int].self) {
            self = .dimensions(value)
        } else {
            self = .text(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .dimensions(value): try container.encode(value)
        case let .text(value): try container.encode(value)
        }
    }
}

struct 探索发行版本: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let alttitle: String?
    let releaseType: String?
    let languages: [探索发行语言]?
    let platforms: [String]?
    let media: [探索发行介质]?
    let visualNovels: [探索发行作品]?
    let producers: [探索发行会社]?
    let images: [探索发行图片]?
    let released: String?
    let minimumAge: Int?
    let patch: Bool?
    let freeware: Bool?
    let uncensored: Bool?
    let official: Bool?
    let hasAdultContent: Bool?
    let resolution: 探索发行分辨率?
    let engine: String?
    let voiced: Int?
    let notes: String?
    let gtin: String?
    let catalog: String?
    let externalLinks: [探索外链]?

    private enum CodingKeys: String, CodingKey {
        case id, title, alttitle, languages, platforms, media, producers, images
        case releaseType = "rtype"
        case released, patch, freeware, uncensored, official, resolution
        case engine, voiced, notes, gtin, catalog
        case visualNovels = "vns"
        case minimumAge = "minage"
        case hasAdultContent = "has_ero"
        case externalLinks = "extlinks"
    }
}

struct 探索角色作品: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let titles: [探索多语言标题]?
    let image: 探索图片?
    let spoiler: Int?
    let role: String?
}

struct 探索角色特征关联: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let groupName: String
    let spoiler: Int?
    let lie: Bool?
    let sexual: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, name, spoiler, lie, sexual
        case groupName = "group_name"
    }
}

struct 探索角色: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let original: String?
    let aliases: [String]?
    let description: String?
    let image: 探索图片?
    let bloodType: String?
    let height: Int?
    let weight: Int?
    let bust: Int?
    let waist: Int?
    let hips: Int?
    let cup: String?
    let age: Int?
    let birthday: [Int]?
    let sex: [String?]?
    let gender: [String?]?
    let visualNovels: [探索角色作品]?
    let traits: [探索角色特征关联]?

    private enum CodingKeys: String, CodingKey {
        case id, name, original, aliases, description, image, height, weight
        case bust, waist, hips, cup, age, birthday, sex, gender, traits
        case bloodType = "blood_type"
        case visualNovels = "vns"
    }
}
