import Foundation

nonisolated struct 活动地区项目: Codable, Hashable, Identifiable, Sendable {
    let identifier: String
    let countryCode: String
    let name: String
    let nativeName: String
    let simplifiedChineseName: String
    let traditionalChineseName: String
    let japaneseName: String
    let aliases: [String]

    var id: String { identifier }

    func localizedName(locale: Locale) -> String {
        let languageCode = locale.language.languageCode?.identifier
        switch languageCode {
        case "zh":
            return locale.language.script?.identifier == "Hant"
                ? traditionalChineseName
                : simplifiedChineseName
        case "ja":
            return japaneseName
        default:
            return name
        }
    }

    var searchNames: [String] {
        [
            name,
            nativeName,
            simplifiedChineseName,
            traditionalChineseName,
            japaneseName
        ] + aliases
    }

    init(
        identifier: String,
        countryCode: String,
        name: String,
        nativeName: String,
        simplifiedChineseName: String,
        traditionalChineseName: String,
        japaneseName: String,
        aliases: [String] = []
    ) {
        self.identifier = identifier
        self.countryCode = countryCode
        self.name = name
        self.nativeName = nativeName
        self.simplifiedChineseName = simplifiedChineseName
        self.traditionalChineseName = traditionalChineseName
        self.japaneseName = japaneseName
        self.aliases = aliases
    }
}

nonisolated struct 活动地区国家: Hashable, Identifiable, Sendable {
    let code: String
    let localizedName: String
    let englishName: String
    let regions: [活动地区项目]
    let searchNames: [String]

    var id: String { code }
    var regionIDs: Set<String> { Set(regions.map(\.identifier)) }

    var isFullySelectedByDefault: Bool {
        !regions.isEmpty
    }
}

private nonisolated struct 活动地区资源项目: Decodable, Sendable {
    let id: String
    let countryCode: String
    let name: String
    let nativeName: String
    let zhHans: String
    let zhHant: String
    let ja: String

    private enum CodingKeys: String, CodingKey {
        case id
        case countryCode
        case name
        case nativeName
        case zhHans
        case zhHant
        case ja
    }
}

nonisolated enum 活动地区目录 {
    private static let fallbackRegionSuffix = "-ALL"

    private static let resourceRegions: [活动地区资源项目] = {
        guard let url = Bundle.main.url(
            forResource: "PaperVNActivityRegions",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? Bundle.main.url(
            forResource: "PaperVNActivityRegions",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let values = try? JSONDecoder().decode(
            [活动地区资源项目].self,
            from: data
        ) else {
            return []
        }
        return values
    }()

    private static let manualAliases: [String: [String]] = [
        "JP-01": ["札幌", "函館", "旭川", "釧路", "帯広", "北海道"],
        "JP-02": ["青森", "弘前", "八戸"],
        "JP-03": ["盛岡", "一関", "北上"],
        "JP-04": ["仙台", "石巻", "宮城"],
        "JP-05": ["秋田", "横手", "大館"],
        "JP-06": ["山形", "米沢", "酒田", "鶴岡"],
        "JP-07": ["福島", "郡山", "いわき", "会津若松"],
        "JP-08": ["水戸", "つくば", "土浦", "日立"],
        "JP-09": ["宇都宮", "小山", "栃木"],
        "JP-10": ["前橋", "高崎", "太田", "群馬"],
        "JP-11": ["さいたま", "大宮", "川越", "熊谷", "埼玉"],
        "JP-12": ["千葉", "船橋", "柏", "成田"],
        "JP-13": ["東京", "渋谷", "新宿", "池袋", "秋葉原", "品川", "六本木", "上野", "有明", "日本橋"],
        "JP-14": ["横浜", "川崎", "鎌倉", "小田原", "相模原", "神奈川"],
        "JP-15": ["新潟", "長岡", "上越"],
        "JP-16": ["富山", "高岡"],
        "JP-17": ["金沢", "小松", "石川"],
        "JP-18": ["福井", "敦賀"],
        "JP-19": ["甲府", "山梨"],
        "JP-20": ["長野", "松本", "上田"],
        "JP-21": ["岐阜", "大垣", "高山"],
        "JP-22": ["静岡", "浜松", "沼津", "富士", "熱海"],
        "JP-23": ["名古屋", "豊橋", "岡崎", "豊田", "愛知"],
        "JP-24": ["津", "四日市", "伊勢", "三重"],
        "JP-25": ["大津", "彦根", "草津", "滋賀"],
        "JP-26": ["京都", "宇治", "舞鶴", "祇園", "烏丸"],
        "JP-27": ["大阪", "梅田", "難波", "心斎橋", "天王寺", "堺", "大阪府"],
        "JP-28": ["神戸", "姫路", "西宮", "尼崎", "兵庫"],
        "JP-29": ["奈良", "橿原", "生駒"],
        "JP-30": ["和歌山", "田辺"],
        "JP-31": ["鳥取", "米子", "倉吉"],
        "JP-32": ["松江", "出雲", "浜田"],
        "JP-33": ["岡山", "倉敷", "津山"],
        "JP-34": ["広島", "福山", "呉", "宮島"],
        "JP-35": ["山口", "下関", "宇部", "萩"],
        "JP-36": ["徳島", "鳴門"],
        "JP-37": ["高松", "丸亀", "香川"],
        "JP-38": ["松山", "今治", "新居浜"],
        "JP-39": ["高知", "四万十"],
        "JP-40": ["福岡", "博多", "天神", "北九州", "久留米"],
        "JP-41": ["佐賀", "唐津", "鳥栖"],
        "JP-42": ["長崎", "佐世保", "諫早"],
        "JP-43": ["熊本", "八代", "阿蘇"],
        "JP-44": ["大分", "別府", "中津"],
        "JP-45": ["宮崎", "都城", "延岡"],
        "JP-46": ["鹿児島", "霧島", "指宿"],
        "JP-47": ["那覇", "沖縄", "石垣", "宮古島"]
    ]

    static let countries: [活动地区国家] = makeCountries()

    static var allRegionIDs: Set<String> {
        Set(countries.flatMap(\.regions).map(\.identifier))
    }

    static var allRegionIDsValue: String {
        allRegionIDs.sorted().joined(separator: ",")
    }

    static func country(code: String) -> 活动地区国家? {
        countries.first { $0.code == code }
    }

    static func region(identifier: String) -> 活动地区项目? {
        countries
            .flatMap(\.regions)
            .first { $0.identifier == identifier }
    }

    static func regionIDs(forCountry code: String) -> Set<String> {
        country(code: code)?.regionIDs ?? []
    }

    static func localizedName(
        for regionIdentifier: String,
        locale: Locale
    ) -> String {
        region(identifier: regionIdentifier)?.localizedName(locale: locale)
            ?? regionIdentifier
    }

    static func countryCode(forRegionIdentifier identifier: String) -> String {
        String(identifier.split(separator: "-", maxSplits: 1).first ?? "")
    }

    static func eventRegionIdentifiers(for event: PaperVN活动) -> Set<String> {
        let placeText = event.placeName?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ) ?? ""
        let text = placeText.isEmpty ? event.name : placeText
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else { return ["JP"] }

        let matchingRegions = countries
            .flatMap(\.regions)
            .filter { region in
                region.searchNames.contains { alias in
                    let normalizedAlias = normalized(alias)
                    return normalizedAlias.count >= 2
                        && normalizedText.contains(normalizedAlias)
                }
            }
            .map(\.identifier)

        if !matchingRegions.isEmpty {
            return Set(matchingRegions)
        }

        let countryMatches = countries.filter { country in
            country.searchNames.contains { alias in
                let normalizedAlias = normalized(alias)
                return normalizedAlias.count >= 2
                    && normalizedText.contains(normalizedAlias)
            }
        }
        if let country = countryMatches.first {
            return [country.code]
        }

        return ["JP"]
    }

    private static func makeCountries() -> [活动地区国家] {
        let grouped = Dictionary(grouping: resourceRegions) {
            $0.countryCode.uppercased()
        }
        let countryCodes = Locale.Region.isoRegions
            .filter(\.isISORegion)
            .map(\.identifier)

        return countryCodes.compactMap { code in
            let normalizedCode = code.uppercased()
            let englishName = Locale(identifier: "en_US")
                .localizedString(forRegionCode: normalizedCode)
                ?? normalizedCode
            let currentName = countryName(
                for: normalizedCode,
                locale: .autoupdatingCurrent
            )
            let regionValues = (grouped[normalizedCode] ?? [])
                .filter { resource in
                    normalizedCode != "CN"
                        || !["CN-HK", "CN-MO", "CN-TW"].contains(resource.id)
                }
                .map { resource in
                    活动地区项目(
                        identifier: resource.id,
                        countryCode: normalizedCode,
                        name: resource.name,
                        nativeName: resource.nativeName,
                        simplifiedChineseName: resource.zhHans,
                        traditionalChineseName: resource.zhHant,
                        japaneseName: resource.ja,
                        aliases: manualAliases[resource.id] ?? []
                    )
                }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let regions: [活动地区项目]
            if regionValues.isEmpty {
                regions = [
                    活动地区项目(
                        identifier: normalizedCode + fallbackRegionSuffix,
                        countryCode: normalizedCode,
                        name: "All regions",
                        nativeName: currentName,
                        simplifiedChineseName: "全部地区",
                        traditionalChineseName: "全部地區",
                        japaneseName: "すべての地域",
                        aliases: [englishName, currentName]
                    )
                ]
            } else {
                regions = regionValues
            }

            let aliases = Set([
                normalizedCode,
                englishName,
                currentName,
                Locale(identifier: "zh-Hans")
                    .localizedString(forRegionCode: normalizedCode) ?? "",
                Locale(identifier: "ja")
                    .localizedString(forRegionCode: normalizedCode) ?? ""
            ]).filter { !$0.isEmpty }

            return 活动地区国家(
                code: normalizedCode,
                localizedName: currentName,
                englishName: englishName,
                regions: regions,
                searchNames: Array(aliases)
            )
        }
        .sorted {
            $0.localizedName.localizedStandardCompare($1.localizedName)
                == .orderedAscending
        }
    }

    private static func countryName(for code: String, locale: Locale) -> String {
        let languageCode = locale.language.languageCode?.identifier
        if code == "CN" {
            switch languageCode {
            case "zh":
                return locale.language.script?.identifier == "Hant"
                    ? "中國大陸"
                    : "中国大陆"
            case "ja":
                return "中国大陸"
            default:
                return "Mainland China"
            }
        }
        return locale.localizedString(forRegionCode: code) ?? code
    }

    private static func normalized(_ value: String) -> String {
        value
            .decomposedStringWithCompatibilityMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

nonisolated enum 活动地区偏好 {
    static let 设置键 = "preferredActivityRegions"

    static var 默认值: String { 活动地区目录.allRegionIDsValue }

    static var 当前选中地区: Set<String> {
        guard let value = UserDefaults.standard.string(forKey: 设置键) else {
            return 活动地区目录.allRegionIDs
        }
        return Set(value.split(separator: ",").map(String.init))
            .intersection(活动地区目录.allRegionIDs)
    }

    static var 当前选择标识符: String {
        当前选中地区.sorted().joined(separator: ",")
    }

    static func 写入(_ selection: Set<String>) {
        UserDefaults.standard.set(
            selection.intersection(活动地区目录.allRegionIDs)
                .sorted()
                .joined(separator: ","),
            forKey: 设置键
        )
    }

    static func 包含(_ event: PaperVN活动) -> Bool {
        let selection = 当前选中地区
        guard !selection.isEmpty else { return false }
        guard selection.count < 活动地区目录.allRegionIDs.count else {
            return true
        }

        let eventIdentifiers = 活动地区目录.eventRegionIdentifiers(for: event)
        if !eventIdentifiers.intersection(selection).isEmpty {
            return true
        }

        return eventIdentifiers.contains { identifier in
            let countryCode = identifier.contains("-")
                ? 活动地区目录.countryCode(forRegionIdentifier: identifier)
                : identifier
            let countryIDs = 活动地区目录.regionIDs(forCountry: countryCode)
            return !countryIDs.isEmpty && countryIDs.isSubset(of: selection)
        }
    }

    static func 筛选(_ events: [PaperVN活动]) -> [PaperVN活动] {
        guard 当前选中地区.count < 活动地区目录.allRegionIDs.count else {
            return events
        }
        return events.filter(包含)
    }
}
