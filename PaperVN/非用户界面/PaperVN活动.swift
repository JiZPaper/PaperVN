import Foundation
import Combine
import SQLite3
import SwiftUI

nonisolated struct PaperVN活动: Codable, Identifiable, Hashable, Sendable {
    let eventernoteID: Int
    let name: String
    let eventDate: String?
    let weekday: String?
    let openTime: String?
    let startTime: String?
    let endTime: String?
    let placeName: String?
    let imageURL: String?
    let url: String?
    let officialURL: String?

    var id: Int { eventernoteID }

    var destinationURL: URL? {
        guard let officialURL,
              let url = URL(string: officialURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    func replacingOfficialURL(_ value: String?) -> PaperVN活动 {
        PaperVN活动(
            eventernoteID: eventernoteID,
            name: name,
            eventDate: eventDate,
            weekday: weekday,
            openTime: openTime,
            startTime: startTime,
            endTime: endTime,
            placeName: placeName,
            imageURL: imageURL,
            url: url,
            officialURL: value
        )
    }

    func dateText(locale: Locale) -> String {
        if let eventDate,
           let date = Self.dateFormatter.date(from: eventDate) {
            return Self.localizedDateText(date, locale: locale)
        }
        return eventDate ?? String(localized: "日期待定")
    }

    func timeText(locale: Locale) -> String? {
        Self.localizedTimeText(
            startTime: startTime,
            endTime: endTime,
            locale: locale
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func localizedDateText(
        _ date: Date,
        locale: Locale
    ) -> String {
        let languageCode = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .split(separator: "-")
            .first
            .map(String.init)

        if languageCode == "zh" {
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.locale = locale
            dateFormatter.setLocalizedDateFormatFromTemplate("yMMMMd")

            let weekdayFormatter = DateFormatter()
            weekdayFormatter.calendar = Calendar(identifier: .gregorian)
            weekdayFormatter.locale = locale
            weekdayFormatter.setLocalizedDateFormatFromTemplate("EEEE")
            return "\(dateFormatter.string(from: date)) \(weekdayFormatter.string(from: date))"
        }

        if languageCode == "ja" {
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = Calendar(identifier: .gregorian)
            dateFormatter.locale = locale
            dateFormatter.setLocalizedDateFormatFromTemplate("yMMMMd")

            let weekdayFormatter = DateFormatter()
            weekdayFormatter.calendar = Calendar(identifier: .gregorian)
            weekdayFormatter.locale = locale
            weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
            return "\(dateFormatter.string(from: date))（\(weekdayFormatter.string(from: date))）"
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("yMdEEE")
        return formatter.string(from: date)
    }

    private static func localizedTimeText(
        startTime: String?,
        endTime: String?,
        locale: Locale
    ) -> String? {
        let values = [startTime, endTime]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }

        let hasSeconds = startTime?.split(separator: ":").count ?? 0 >= 3
            || endTime?.split(separator: ":").count ?? 0 >= 3
        let hidesSeconds = startTime?.hasSuffix(":00") == true
            && endTime?.hasSuffix(":00") == true
            && startTime?.split(separator: ":").count ?? 0 >= 3
            && endTime?.split(separator: ":").count ?? 0 >= 3
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar(identifier: .gregorian)
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")

        let outputFormatter = DateFormatter()
        outputFormatter.calendar = Calendar(identifier: .gregorian)
        outputFormatter.locale = locale
        outputFormatter.dateStyle = .none
        outputFormatter.timeStyle = hasSeconds && !hidesSeconds ? .medium : .short

        return values.map { value in
            inputFormatter.dateFormat = value.split(separator: ":").count >= 3
                ? "HH:mm:ss"
                : "HH:mm"
            guard let date = inputFormatter.date(from: value) else {
                return value
            }
            return outputFormatter.string(from: date)
        }
        .joined(separator: " — ")
    }

    init(
        eventernoteID: Int,
        name: String,
        eventDate: String?,
        weekday: String? = nil,
        openTime: String? = nil,
        startTime: String? = nil,
        endTime: String? = nil,
        placeName: String? = nil,
        imageURL: String? = nil,
        url: String? = nil,
        officialURL: String? = nil
    ) {
        self.eventernoteID = eventernoteID
        self.name = name
        self.eventDate = eventDate
        self.weekday = weekday
        self.openTime = openTime
        self.startTime = startTime
        self.endTime = endTime
        self.placeName = placeName
        self.imageURL = imageURL
        self.url = url
        self.officialURL = officialURL
    }

    private enum CodingKeys: String, CodingKey {
        case eventernoteID = "eventernote_id"
        case name
        case eventDate = "event_date"
        case weekday
        case openTime = "open_time"
        case startTime = "start_time"
        case endTime = "end_time"
        case placeName
        case imageURL = "image_url"
        case url
        case officialURL = "official_url"
    }
}

private nonisolated struct PaperVN活动原始活动: Decodable, Sendable {
    let id: Int
    let url: String?
    let date: String?
    let name: String
    let place: PaperVN活动原始场所?
    let weekday: String?
    let end_time: String?
    let image_url: String?
    let open_time: String?
    let start_time: String?

    var event: PaperVN活动 {
        PaperVN活动(
            eventernoteID: id,
            name: name,
            eventDate: date,
            weekday: weekday,
            openTime: open_time,
            startTime: start_time,
            endTime: end_time,
            placeName: place?.name,
            imageURL: image_url,
            url: url
        )
    }
}

private nonisolated struct PaperVN活动原始场所: Decodable, Sendable {
    let name: String?
}

private nonisolated struct PaperVN活动链接记录: Decodable, Sendable {
    let event_id: Int
    let url: String
}

private nonisolated struct PaperVN活动演员索引: Decodable, Sendable {
    let id: Int
    let name: String
    let shard: String
}

private nonisolated struct PaperVN活动演员记录: Decodable, Sendable {
    let eventernote_id: Int
    let raw: PaperVN活动演员原始数据?
}

private nonisolated struct PaperVN活动演员原始数据: Decodable, Sendable {
    let recent_events: [PaperVN活动原始活动]?
}

private nonisolated struct PaperVN活动日期索引: Decodable, Sendable {
    let date: String
    let shards: [String]
}

private nonisolated struct PaperVN活动清单: Decodable, Sendable {
    let path: String
    let firstID: Int?
    let lastID: Int?

    private enum CodingKeys: String, CodingKey {
        case path
        case firstID = "first_id"
        case lastID = "last_id"
    }
}

private nonisolated struct PaperVN活动数据集清单: Decodable, Sendable {
    let entities: Entities
    let indexes: Indexes

    struct Entities: Decodable, Sendable {
        let actors: Definition
        let eventLinks: Definition

        private enum CodingKeys: String, CodingKey {
            case actors
            case eventLinks = "event_links"
        }
    }

    struct Indexes: Decodable, Sendable {
        let actors: Definition
        let eventsByDate: Definition

        private enum CodingKeys: String, CodingKey {
            case actors
            case eventsByDate = "events_by_date"
        }
    }

    struct Definition: Decodable, Sendable {
        let catalog: Catalog
    }

    struct Catalog: Decodable, Sendable {
        let shardCount: Int

        private enum CodingKeys: String, CodingKey {
            case shardCount = "shard_count"
        }
    }
}

private nonisolated struct PaperVN活动事件原始记录: Decodable, Sendable {
    let eventernote_id: Int
    let name: String
    let event_date: String?
    let weekday: String?
    let open_time: String?
    let start_time: String?
    let end_time: String?
    let place_id: Int?
    let image_url: String?
    let url: String?
    let official_url: String?

    var event: PaperVN活动 {
        PaperVN活动(
            eventernoteID: eventernote_id,
            name: name,
            eventDate: event_date,
            weekday: weekday,
            openTime: open_time,
            startTime: start_time,
            endTime: end_time,
            imageURL: image_url,
            url: url,
            officialURL: official_url
        )
    }
}

private nonisolated enum PaperVN活动服务错误: LocalizedError {
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: "活动数据响应无效。")
        case .unavailable:
            String(localized: "暂时无法载入活动。")
        }
    }
}

private nonisolated final class PaperVN活动本地数据库 {
    private var connection: OpaquePointer?

    init?() {
        let resourceURL = Bundle.main.url(
            forResource: "PaperVNEvents",
            withExtension: "sqlite",
            subdirectory: "Resources"
        ) ?? Bundle.main.url(
            forResource: "PaperVNEvents",
            withExtension: "sqlite"
        )
        guard let resourceURL else { return nil }
        guard sqlite3_open_v2(
            resourceURL.path,
            &connection,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            return nil
        }
    }

    deinit {
        if let connection { sqlite3_close(connection) }
    }

    func upcomingEvents(
        from date: String,
        limit: Int
    ) -> [PaperVN活动]? {
        guard let connection else { return nil }
        let sql = """
            SELECT id, name, event_date, weekday, open_time, start_time,
                   end_time, place_name, image_url, url, official_url
            FROM events
            WHERE event_date >= ?
            ORDER BY event_date, start_time IS NULL, start_time, id
            LIMIT ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        Self.bind(date, at: 1, in: statement)
        sqlite3_bind_int(statement, 2, Int32(limit))
        return Self.readEvents(from: statement)
    }

    func recentEvents(
        actorNames: [String],
        from date: String
    ) -> [PaperVN活动]? {
        guard let connection else { return nil }
        let normalizedNames = Set(actorNames.map(Self.normalizedName))
            .filter { !$0.isEmpty }
        guard !normalizedNames.isEmpty else { return [] }

        let actorIDs = actorIDs(
            matching: Array(normalizedNames),
            connection: connection
        )
        guard !actorIDs.isEmpty else { return [] }

        var eventsByID: [Int: PaperVN活动] = [:]
        for start in stride(from: 0, to: actorIDs.count, by: 400) {
            let end = Swift.min(start + 400, actorIDs.count)
            let ids = actorIDs[start..<end]
            let placeholders = Array(repeating: "?", count: ids.count)
                .joined(separator: ",")
            let sql = """
                SELECT DISTINCT e.id, e.name, e.event_date, e.weekday,
                       e.open_time, e.start_time, e.end_time, e.place_name,
                       e.image_url, e.url, e.official_url
                FROM events e
                JOIN event_actors ea ON ea.event_id = e.id
                WHERE e.event_date >= ?
                  AND ea.actor_id IN (\(placeholders))
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(
                connection, sql, -1, &statement, nil
            ) == SQLITE_OK, let statement else { return nil }
            Self.bind(date, at: 1, in: statement)
            for (offset, id) in ids.enumerated() {
                sqlite3_bind_int64(statement, Int32(offset + 2), Int64(id))
            }
            for event in Self.readEvents(from: statement) {
                eventsByID[event.id] = event
            }
            sqlite3_finalize(statement)
        }
        return Array(eventsByID.values)
    }

    private func actorIDs(
        matching normalizedNames: [String],
        connection: OpaquePointer
    ) -> [Int] {
        let sql = "SELECT id FROM actors WHERE normalized_name = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            connection, sql, -1, &statement, nil
        ) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }

        var result = Set<Int>()
        for name in normalizedNames {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            Self.bind(name, at: 1, in: statement)
            while sqlite3_step(statement) == SQLITE_ROW {
                result.insert(Int(sqlite3_column_int64(statement, 0)))
            }
        }
        return Array(result)
    }

    private static func readEvents(
        from statement: OpaquePointer
    ) -> [PaperVN活动] {
        var result: [PaperVN活动] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(
                PaperVN活动(
                    eventernoteID: Int(sqlite3_column_int64(statement, 0)),
                    name: text(at: 1, in: statement) ?? "",
                    eventDate: text(at: 2, in: statement),
                    weekday: text(at: 3, in: statement),
                    openTime: text(at: 4, in: statement),
                    startTime: text(at: 5, in: statement),
                    endTime: text(at: 6, in: statement),
                    placeName: text(at: 7, in: statement),
                    imageURL: text(at: 8, in: statement),
                    url: text(at: 9, in: statement),
                    officialURL: text(at: 10, in: statement)
                )
            )
        }
        return result
    }

    private static func text(
        at index: Int32,
        in statement: OpaquePointer
    ) -> String? {
        guard let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private static func bind(
        _ value: String,
        at index: Int32,
        in statement: OpaquePointer
    ) {
        _ = value.withCString { pointer in
            sqlite3_bind_text(
                statement, index, pointer, -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
        }
    }

    private static func normalizedName(_ value: String) -> String {
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

actor PaperVN活动服务 {
    static let shared = PaperVN活动服务()

    private let baseURL = URL(string: "https://papervn.jizpaper.com/event/")!
    private let session: URLSession
    private let localDatabase = PaperVN活动本地数据库()
    private let diskCacheDirectory: URL
    private let diskCacheLifetime: TimeInterval = 24 * 60 * 60
    private var dataCache: [String: Data] = [:]
    private var datasetManifestCache: PaperVN活动数据集清单?
    private var actorShardPaths: [PaperVN活动清单]?
    private var actorIndexCache: [PaperVN活动演员索引]?
    private var actorEventCache: [Int: [PaperVN活动]] = [:]
    private var globalEventCache: [PaperVN活动]?
    private var eventDateIndexPathsCache: [String]?
    private var eventLinkShardPaths: [PaperVN活动清单]?
    private var eventLinksCache: [Int: [String]] = [:]

    init(session: URLSession = .shared) {
        self.session = session
        diskCacheDirectory = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("PaperVNEventData", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: diskCacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func cachedUpcomingEvents(limit: Int = 12) -> [PaperVN活动] {
        let today = Self.todayString()
        return Array(
            Self.readPersistentEvents(forKey: Self.upcomingCacheKey)
                .filter { ($0.eventDate ?? "") >= today }
                .filter(活动地区偏好.包含)
                .prefix(limit)
        )
    }

    func cachedRecentEvents(
        forActorNames names: [String],
        relatedTerms: [String] = [],
        limit: Int = 12
    ) -> [PaperVN活动] {
        let today = Self.todayString()
        return Array(
            Self.readPersistentEvents(
                forKey: Self.recentCacheKey(
                    for: names,
                    relatedTerms: relatedTerms
                )
            )
            .filter { ($0.eventDate ?? "") >= today }
            .filter(活动地区偏好.包含)
            .prefix(limit)
        )
    }

    func upcomingEvents(
        limit: Int = 12,
        forceRefresh: Bool = false
    ) async throws -> [PaperVN活动] {
        let today = Self.todayString()
        if let localDatabase,
           let localEvents = localDatabase.upcomingEvents(
               from: today,
               limit: max(limit * 100, 1000)
           ) {
            let filteredEvents = Array(
                活动地区偏好.筛选(localEvents).prefix(limit)
            )
            globalEventCache = filteredEvents
            if !localEvents.isEmpty {
                Self.writePersistentEvents(
                    localEvents,
                    forKey: Self.upcomingCacheKey
                )
            }
            return filteredEvents
        }
        let indexPaths = try await dateIndexPaths(
            containing: today,
            forceRefresh: forceRefresh
        )
        var indexRows: [PaperVN活动日期索引] = []
        var successfulIndexLoads = 0
        await withTaskGroup(
            of: [PaperVN活动日期索引]?.self
        ) { group in
            for path in indexPaths {
                group.addTask { [self] in
                    try? await decode(
                        [PaperVN活动日期索引].self,
                        path: path,
                        forceRefresh: forceRefresh
                    )
                }
            }
            for await rows in group {
                if let rows {
                    successfulIndexLoads += 1
                    indexRows.append(contentsOf: rows)
                }
            }
        }
        guard successfulIndexLoads == indexPaths.count else {
            throw PaperVN活动服务错误.unavailable
        }

        let futureRows = indexRows
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
        var seenPaths = Set<String>()
        let shardPaths = Array(
            futureRows
                .flatMap(\.shards)
                .filter { seenPaths.insert($0).inserted }
                .prefix(max(limit * 2, 24))
        )
        guard !shardPaths.isEmpty else { return [] }

        var events: [PaperVN活动] = []
        var successfulEventLoads = 0
        await withTaskGroup(
            of: [PaperVN活动事件原始记录]?.self
        ) { group in
            for path in shardPaths {
                group.addTask { [self] in
                    try? await decode(
                        [PaperVN活动事件原始记录].self,
                        path: path,
                        forceRefresh: forceRefresh
                    )
                }
            }
            for await records in group {
                if let records {
                    successfulEventLoads += 1
                    events.append(
                        contentsOf: records
                            .map(\.event)
                            .filter { ($0.eventDate ?? "") >= today }
                    )
                }
            }
        }
        guard successfulEventLoads == shardPaths.count else {
            throw PaperVN活动服务错误.unavailable
        }

        let orderedEvents = events.sorted { lhs, rhs in
            let leftDate = lhs.eventDate ?? ""
            let rightDate = rhs.eventDate ?? ""
            if leftDate != rightDate { return leftDate < rightDate }
            return (lhs.startTime ?? "") < (rhs.startTime ?? "")
        }
        let result = Array(
            活动地区偏好.筛选(orderedEvents).prefix(limit)
        )
        let enriched = await addingOfficialLinks(
            to: result,
            forceRefresh: forceRefresh
        )
        if !enriched.isEmpty {
            globalEventCache = enriched
            Self.writePersistentEvents(enriched, forKey: Self.upcomingCacheKey)
        }
        return enriched
    }

    private func datasetManifest(
        forceRefresh: Bool = false
    ) async throws -> PaperVN活动数据集清单 {
        if !forceRefresh, let datasetManifestCache {
            return datasetManifestCache
        }
        let manifest = try await decode(
            PaperVN活动数据集清单.self,
            path: "manifest.json",
            forceRefresh: forceRefresh
        )
        datasetManifestCache = manifest
        return manifest
    }

    private func dateIndexPaths(
        containing date: String,
        forceRefresh: Bool
    ) async throws -> [String] {
        let paths: [String]
        if !forceRefresh, let eventDateIndexPathsCache {
            paths = eventDateIndexPathsCache
        } else {
            let manifest = try await datasetManifest(forceRefresh: forceRefresh)
            let catalogCount = manifest.indexes.eventsByDate.catalog.shardCount
            paths = try await decodeCatalogs(
                directory: "indexes/catalogs/events-by-date",
                prefix: "events-by-date-catalog-",
                count: catalogCount,
                forceRefresh: forceRefresh
            )
                .map(\.path)
                .sorted()
            guard !paths.isEmpty else {
                throw PaperVN活动服务错误.unavailable
            }
            eventDateIndexPathsCache = paths
        }

        var lowerBound = 0
        var upperBound = paths.count - 1
        var firstMatchingIndex = paths.count

        while lowerBound <= upperBound {
            let middle = (lowerBound + upperBound) / 2
            let rows = try await decode(
                [PaperVN活动日期索引].self,
                path: paths[middle],
                forceRefresh: forceRefresh
            )
            guard let lastDate = rows.last?.date else {
                throw PaperVN活动服务错误.invalidResponse
            }

            if lastDate < date {
                lowerBound = middle + 1
            } else {
                firstMatchingIndex = middle
                upperBound = middle - 1
            }
        }

        if firstMatchingIndex == paths.count {
            firstMatchingIndex = max(paths.count - 1, 0)
        }
        let lastIndex = min(paths.count - 1, firstMatchingIndex + 3)
        return Array(paths[firstMatchingIndex...lastIndex])
    }

    func recentEvents(
        forActorNames names: [String],
        relatedTerms: [String] = [],
        limit: Int = 12,
        forceRefresh: Bool = false
    ) async throws -> [PaperVN活动] {
        let queries = names.map(Self.normalizedName).filter { !$0.isEmpty }
        guard !queries.isEmpty else { return [] }
        let today = Self.todayString()
        if let localEvents = localDatabase?.recentEvents(
            actorNames: names,
            from: today
        ) {
            return persistRecentEvents(
                localEvents,
                names: names,
                relatedTerms: relatedTerms,
                limit: limit
            )
        }
        let actorIndex = try await actorIndex(forceRefresh: forceRefresh)
        let actorIDs = actorIndex.filter { actor in
            let candidate = Self.normalizedName(actor.name)
            return queries.contains { query in
                candidate == query
                    || (query.count >= 4 && candidate.contains(query))
                    || (candidate.count >= 4 && query.contains(candidate))
            }
        }.map(\.id)

        var events: [PaperVN活动] = []
        var actorIDsToLoad: [Int] = []
        for actorID in Set(actorIDs) {
            if !forceRefresh, let cached = actorEventCache[actorID] {
                events.append(contentsOf: cached)
            } else {
                actorIDsToLoad.append(actorID)
            }
        }

        let actorCatalogs = try await actorCatalogs(forceRefresh: forceRefresh)
        await withTaskGroup(of: (Int, [PaperVN活动])?.self) { group in
            for actorID in actorIDsToLoad {
                group.addTask { [self] in
                    guard let record = try? await loadActorRecord(
                        id: actorID,
                        catalogs: actorCatalogs,
                        forceRefresh: forceRefresh
                    ) else {
                        return nil
                    }
                    return (
                        actorID,
                        record.raw?.recent_events?.map(\.event) ?? []
                    )
                }
            }
            for await result in group {
                guard let (actorID, values) = result else {
                    continue
                }
                actorEventCache[actorID] = values
                events.append(contentsOf: values)
            }
        }

        guard !events.isEmpty else { return [] }

        let result = rankedRecentEvents(
            events,
            relatedTerms: relatedTerms,
            limit: limit
        )
        let enriched = await addingOfficialLinks(
            to: result,
            forceRefresh: forceRefresh
        )
        if !enriched.isEmpty {
            Self.writePersistentEvents(
                enriched,
                forKey: Self.recentCacheKey(
                    for: names,
                    relatedTerms: relatedTerms
                )
            )
        }
        return enriched
    }

    private func persistRecentEvents(
        _ events: [PaperVN活动],
        names: [String],
        relatedTerms: [String],
        limit: Int
    ) -> [PaperVN活动] {
        let result = rankedRecentEvents(
            events,
            relatedTerms: relatedTerms,
            limit: limit
        )
        if !result.isEmpty {
            Self.writePersistentEvents(
                result,
                forKey: Self.recentCacheKey(
                    for: names,
                    relatedTerms: relatedTerms
                )
            )
        }
        return result
    }

    private func rankedRecentEvents(
        _ events: [PaperVN活动],
        relatedTerms: [String],
        limit: Int
    ) -> [PaperVN活动] {
        var seen = Set<Int>()
        let today = Self.todayString()
        let relatedQueries = relatedTerms
            .map(Self.normalizedName)
            .filter { $0.count >= 2 }
        return Array(
            events
                .filter { seen.insert($0.id).inserted }
                .filter { ($0.eventDate ?? "") >= today }
                .filter(活动地区偏好.包含)
                .filter { event in
                    relatedQueries.isEmpty
                        || Self.eventRelevanceScore(
                            name: event.name,
                            queries: relatedQueries
                        ) > 0
                }
                .sorted { lhs, rhs in
                    let leftScore = Self.eventRelevanceScore(
                        name: lhs.name,
                        queries: relatedQueries
                    )
                    let rightScore = Self.eventRelevanceScore(
                        name: rhs.name,
                        queries: relatedQueries
                    )
                    if leftScore != rightScore { return leftScore > rightScore }
                    let left = lhs.eventDate ?? ""
                    let right = rhs.eventDate ?? ""
                    if left != right { return left < right }
                    return lhs.id < rhs.id
                }
                .prefix(limit)
        )
    }

    private func addingOfficialLinks(
        to events: [PaperVN活动],
        forceRefresh: Bool
    ) async -> [PaperVN活动] {
        guard !events.isEmpty else { return [] }
        let missingOfficialLinkIDs = events
            .filter { $0.officialURL == nil }
            .map(\.id)
        guard !missingOfficialLinkIDs.isEmpty else { return events }
        guard let links = try? await eventLinks(
            for: missingOfficialLinkIDs,
            forceRefresh: forceRefresh
        ) else { return events }
        return events.map { event in
            guard event.officialURL == nil,
                  let urls = links[event.id],
                  let url = Self.preferredOfficialURL(from: urls) else {
                return event
            }
            return event.replacingOfficialURL(url)
        }
    }

    private func eventLinks(
        for eventIDs: [Int],
        forceRefresh: Bool
    ) async throws -> [Int: [String]] {
        let requestedIDs = Set(eventIDs)
        guard !requestedIDs.isEmpty else { return [:] }

        let missingIDs = requestedIDs.filter {
            forceRefresh || eventLinksCache[$0] == nil
        }
        guard !missingIDs.isEmpty else {
            return requestedIDs.reduce(into: [:]) { result, id in
                result[id] = eventLinksCache[id] ?? []
            }
        }

        let catalogs = try await eventLinkCatalogs(forceRefresh: forceRefresh)
        let paths = catalogs.filter { catalog in
            guard let firstID = catalog.firstID,
                  let lastID = catalog.lastID else { return false }
            return missingIDs.contains { $0 >= firstID && $0 <= lastID }
        }.map(\.path)

        var values: [Int: [String]] = [:]
        await withTaskGroup(of: [PaperVN活动链接记录]?.self) { group in
            for path in paths {
                group.addTask { [self] in
                    try? await decode(
                        [PaperVN活动链接记录].self,
                        path: path,
                        forceRefresh: forceRefresh
                    )
                }
            }
            for await rows in group {
                for row in rows ?? [] where missingIDs.contains(row.event_id) {
                    values[row.event_id, default: []].append(row.url)
                }
            }
        }

        for id in missingIDs {
            eventLinksCache[id] = values[id] ?? []
        }
        return requestedIDs.reduce(into: [:]) { result, id in
            result[id] = eventLinksCache[id] ?? []
        }
    }

    private func eventLinkCatalogs(
        forceRefresh: Bool
    ) async throws -> [PaperVN活动清单] {
        if !forceRefresh, let eventLinkShardPaths {
            return eventLinkShardPaths
        }
        let paths = try await decodeCatalogs(
            directory: "indexes/catalogs/event_links",
            prefix: "event_links-catalog-",
            count: try await datasetManifest(
                forceRefresh: forceRefresh
            ).entities.eventLinks.catalog.shardCount,
            forceRefresh: forceRefresh
        )
        eventLinkShardPaths = paths
        return paths
    }

    private func actorIndex(
        forceRefresh: Bool = false
    ) async throws -> [PaperVN活动演员索引] {
        if !forceRefresh, let actorIndexCache { return actorIndexCache }
        var values: [PaperVN活动演员索引] = []
        var shardPaths: [String] = []
        let catalogCount = try await datasetManifest(
            forceRefresh: forceRefresh
        ).indexes.actors.catalog.shardCount
        guard catalogCount > 0 else {
            throw PaperVN活动服务错误.invalidResponse
        }
        await withTaskGroup(of: [PaperVN活动清单]?.self) { group in
            for number in 1...catalogCount {
                let catalogPath = "indexes/catalogs/actors-index/actors-index-catalog-\(String(format: "%06d", number)).json"
                group.addTask { [self] in
                    try? await decode(
                        [PaperVN活动清单].self,
                        path: catalogPath,
                        forceRefresh: forceRefresh
                    )
                }
            }
            for await catalog in group {
                if let catalog {
                    shardPaths.append(contentsOf: catalog.map(\.path))
                }
            }
        }
        guard !shardPaths.isEmpty else {
            throw PaperVN活动服务错误.unavailable
        }

        var successfulIndexShardLoads = 0
        await withTaskGroup(of: [PaperVN活动演员索引]?.self) { group in
            for path in shardPaths {
                group.addTask { [self] in
                    try? await decode(
                        [PaperVN活动演员索引].self,
                        path: path,
                        forceRefresh: forceRefresh
                    )
                }
            }
            for await rows in group {
                if let rows {
                    successfulIndexShardLoads += 1
                    values.append(contentsOf: rows)
                }
            }
        }
        guard successfulIndexShardLoads == shardPaths.count else {
            throw PaperVN活动服务错误.unavailable
        }

        actorIndexCache = values
        return values
    }

    private func loadActorRecord(
        id: Int,
        catalogs: [PaperVN活动清单],
        forceRefresh: Bool = false
    ) async throws -> PaperVN活动演员记录 {
        guard let catalog = catalogs.first(where: { entry in
            guard let first = entry.firstID, let last = entry.lastID else { return false }
            return id >= first && id <= last
        }) else { throw PaperVN活动服务错误.unavailable }
        let records = try await decode(
            [PaperVN活动演员记录].self,
            path: catalog.path,
            forceRefresh: forceRefresh
        )
        guard let record = records.first(where: { $0.eventernote_id == id }) else {
            throw PaperVN活动服务错误.unavailable
        }
        return record
    }

    private func actorCatalogs(
        forceRefresh: Bool = false
    ) async throws -> [PaperVN活动清单] {
        if !forceRefresh, let actorShardPaths { return actorShardPaths }
        let paths = try await decodeCatalogs(
            directory: "indexes/catalogs/actors",
            prefix: "actors-catalog-",
            count: try await datasetManifest(
                forceRefresh: forceRefresh
            ).entities.actors.catalog.shardCount,
            forceRefresh: forceRefresh
        )
        actorShardPaths = paths
        return paths
    }

    private func decodeCatalogs(
        directory: String,
        prefix: String,
        count: Int,
        forceRefresh: Bool = false
    ) async throws -> [PaperVN活动清单] {
        guard count > 0 else {
            throw PaperVN活动服务错误.invalidResponse
        }
        var result: [PaperVN活动清单] = []
        await withTaskGroup(of: [PaperVN活动清单]?.self) { group in
            for number in 1...count {
                let path = "\(directory)/\(prefix)\(String(format: "%06d", number)).json"
                group.addTask { [self] in
                    try? await decode(
                        [PaperVN活动清单].self,
                        path: path,
                        forceRefresh: forceRefresh
                    )
                }
            }
            for await values in group {
                if let values { result.append(contentsOf: values) }
            }
        }
        guard !result.isEmpty else {
            throw PaperVN活动服务错误.unavailable
        }
        return result
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        path: String,
        forceRefresh: Bool = false
    ) async throws -> Value {
        if !forceRefresh, let data = dataCache[path] {
            return try JSONDecoder().decode(type, from: data)
        }
        if !forceRefresh,
           let data = readDiskCacheData(for: path) {
            dataCache[path] = data
            return try JSONDecoder().decode(type, from: data)
        }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw PaperVN活动服务错误.unavailable }
        var lastError: Error = PaperVN活动服务错误.unavailable
        for attempt in 0..<2 {
            do {
                var request = URLRequest(url: url)
                request.cachePolicy = forceRefresh
                    ? .reloadRevalidatingCacheData
                    : .returnCacheDataElseLoad
                request.timeoutInterval = 12
                let (data, response) = try await PaperVNConnect网络设置.发送请求(
                    request,
                    session: session
                )
                guard response.statusCode == 200 else {
                    throw PaperVN活动服务错误.invalidResponse
                }
                dataCache[path] = data
                try? data.write(
                    to: diskCacheURL(for: path),
                    options: .atomic
                )
                return try JSONDecoder().decode(type, from: data)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
        }
        throw lastError
    }

    private func diskCacheURL(for path: String) -> URL {
        let filename = path.map { character -> Character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character
                : "_"
        }
        return diskCacheDirectory.appendingPathComponent(String(filename) + ".data")
    }

    private func readDiskCacheData(for path: String) -> Data? {
        let url = diskCacheURL(for: path)
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ),
        let modifiedAt = attributes[.modificationDate] as? Date,
        Date().timeIntervalSince(modifiedAt) < diskCacheLifetime else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func normalizedName(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func eventRelevanceScore(
        name: String,
        queries: [String]
    ) -> Int {
        guard !queries.isEmpty else { return 0 }
        let eventName = normalizedName(name)
        guard !eventName.isEmpty else { return 0 }

        var score = 0
        for query in queries {
            if eventName == query {
                score = max(score, 300 + min(query.count, 80))
            } else if eventName.contains(query) {
                score = max(score, 200 + min(query.count, 80))
            } else if eventName.count >= 4, query.contains(eventName) {
                score = max(score, 120 + min(eventName.count, 40))
            }
        }
        return score
    }

    private static func preferredOfficialURL(from values: [String]) -> String? {
        let validValues = values.filter { value in
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let host = url.host?.lowercased() else {
                return false
            }
            return !host.contains("eventernote.com")
        }
        guard !validValues.isEmpty else { return nil }

        let socialHosts = [
            "x.com", "twitter.com", "facebook.com", "instagram.com",
            "youtube.com", "youtu.be", "tiktok.com"
        ]
        return validValues.first {
            guard let host = URL(string: $0)?.host?.lowercased() else {
                return false
            }
            return !socialHosts.contains {
                host == $0 || host.hasSuffix(".\($0)")
            }
        } ?? validValues.first
    }

    private static var upcomingCacheKey: String {
        "PaperVN活动.upcoming.v3."
            + 活动地区偏好.当前选择标识符
    }

    private static func recentCacheKey(
        for names: [String],
        relatedTerms: [String] = []
    ) -> String {
        "PaperVN活动.recent.v4."
            + names.map(normalizedName).filter { !$0.isEmpty }.sorted().joined(separator: "|")
            + ".terms."
            + relatedTerms.map(normalizedName).filter { !$0.isEmpty }.sorted().joined(separator: "|")
            + ".regions."
            + 活动地区偏好.当前选择标识符
    }

    private static func readPersistentEvents(forKey key: String) -> [PaperVN活动] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode(
                [PaperVN活动].self,
                from: data
              ) else {
            return []
        }
        return events
    }

    private static func writePersistentEvents(
        _ events: [PaperVN活动],
        forKey key: String
    ) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

}

@MainActor
final class PaperVN活动视图模型: ObservableObject {
    @Published private(set) var events: [PaperVN活动] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPersonalized = false

    func loadUpcoming(forceRefresh: Bool = false) async {
        isPersonalized = false
        let cached = await PaperVN活动服务.shared.cachedUpcomingEvents()
        if !cached.isEmpty {
            events = cached
            hasLoaded = true
        } else {
            events = []
            hasLoaded = false
        }
        await load {
            try await PaperVN活动服务.shared.upcomingEvents(
                forceRefresh: forceRefresh
            )
        }
    }

    func loadForLibrary(
        token: String,
        userID: String,
        forceRefresh: Bool = false
    ) async {
        guard !token.isEmpty, !userID.isEmpty else {
            await loadUpcoming(forceRefresh: forceRefresh)
            return
        }

        do {
            let library = try await VNDB服务.shared.fetchUserLibraryEventMetadata(
                token: token,
                userID: userID,
                forceRefresh: forceRefresh
            )
            let metadata = try await VNDB服务.shared.fetchVNEventMetadata(
                vnIDs: library.map(\.id),
                forceRefresh: forceRefresh
            )

            var actorNames: [String] = []
            var seenNames = Set<String>()
            for item in metadata {
                for name in item.va?.flatMap({
                    [$0.staff.name, $0.staff.original]
                }).compactMap({ $0 }) ?? [] {
                    let value = name.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !value.isEmpty,
                          seenNames.insert(value).inserted else { continue }
                    actorNames.append(value)
                }
            }

            guard !actorNames.isEmpty else {
                await loadUpcoming(forceRefresh: forceRefresh)
                return
            }

            isPersonalized = true
            await load(
                actorNames: actorNames,
                forceRefresh: forceRefresh
            )
        } catch is CancellationError {
            return
        } catch {
            await loadUpcoming(forceRefresh: forceRefresh)
        }
    }

    func load(
        actorNames: [String],
        relatedTerms: [String] = [],
        forceRefresh: Bool = false
    ) async {
        events = []
        hasLoaded = false
        errorMessage = nil
        let cached = await PaperVN活动服务.shared.cachedRecentEvents(
            forActorNames: actorNames,
            relatedTerms: relatedTerms
        )
        if !cached.isEmpty {
            events = cached
            hasLoaded = true
        } else {
            events = []
            hasLoaded = false
        }
        await load {
            try await PaperVN活动服务.shared.recentEvents(
                forActorNames: actorNames,
                relatedTerms: relatedTerms,
                forceRefresh: forceRefresh
            )
        }
    }

    private func load(
        _ operation: @escaping () async throws -> [PaperVN活动]
    ) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await operation()
            withAnimation(.easeInOut(duration: 0.28)) {
                events = result
            }
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch {
            hasLoaded = true
            if events.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

nonisolated enum PaperVN活动卡片场景: Sendable, Equatable {
    case today
    case detail
}

private extension View {
    @ViewBuilder
    func PaperVN活动横向书架适配(horizontalInset: CGFloat) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.平台横向书架(内容边距: horizontalInset)
        } else {
            self
                .padding(.horizontal, -horizontalInset)
                .contentMargins(
                    .horizontal,
                    horizontalInset,
                    for: .scrollContent
                )
                .scrollClipDisabled()
        }
    }

    @ViewBuilder
    func PaperVN活动半折双栏适配(_ isEnabled: Bool) -> some View {
        if isEnabled {
            self
                .frame(maxWidth: .infinity, alignment: .leading)
                .containerRelativeFrame(
                    .horizontal,
                    count: 2,
                    span: 1,
                    spacing: 20
                )
        } else {
            self
        }
    }
}

struct PaperVN活动栏目: View {
    let events: [PaperVN活动]
    let isLoading: Bool
    let hasLoaded: Bool
    let errorMessage: String?
    var cardScene: PaperVN活动卡片场景 = .today
    var 液态玻璃外观: 沉浸详情外观? = nil
    var 液态玻璃回退色调: Color? = nil
    var title: String?
    var horizontalInset: CGFloat = 20
    var usesTwoColumnFoldLayout = false
    var hidesWhenEmpty = false
    var onRetry: (() -> Void)?

    @Environment(\.locale) private var locale
    @Environment(\.legibilityWeight) private var legibilityWeight
    @ScaledMetric(relativeTo: .title2)
    private var sectionTitleSize: CGFloat = 22

    var body: some View {
        if hidesWhenEmpty,
           events.isEmpty,
           hasLoaded,
           !isLoading,
           errorMessage == nil {
            EmptyView()
        } else {
            activityContent
        }
    }

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sectionTitle
                if isLoading && !events.isEmpty {
                    ProgressView().controlSize(.small)
                }
            }

            if events.isEmpty, !hasLoaded || isLoading {
                loadingContent
            } else if events.isEmpty, let errorMessage {
                unavailableContent(
                    title: "无法载入活动",
                    systemImage: "wifi.exclamationmark",
                    description: errorMessage,
                    showsRetry: true
                )
            } else if events.isEmpty {
                unavailableContent(
                    title: "无活动",
                    systemImage: "calendar.badge.exclamationmark",
                    description: nil,
                    showsRetry: false
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(
                        alignment: .top,
                        spacing: usesTwoColumnFoldLayout ? 20 : 14
                    ) {
                        ForEach(events) { event in
                            PaperVN活动卡片(
                                event: event,
                                scene: cardScene,
                                液态玻璃外观: 液态玻璃外观,
                                液态玻璃回退色调: 液态玻璃回退色调
                            )
                            .PaperVN活动半折双栏适配(
                                usesTwoColumnFoldLayout
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .PaperVN活动横向书架适配(
                    horizontalInset: horizontalInset
                )
            }
        }
    }

    private var sectionTitle: some View {
        let sectionTitleText = self.title ?? (cardScene == .detail
            ? String(localized: "活动")
            : String(localized: "最近活动"))
        return Text(
            标题工具.生成富文本(
                文本: sectionTitleText,
                isJapanese: locale.identifier
                    .replacingOccurrences(of: "_", with: "-")
                    .lowercased()
                    .hasPrefix("ja"),
                基础大小: sectionTitleSize,
                是粗体: true,
                日文字体名称: "HiraginoSans-W6",
                系统字体粗细: .bold,
                语言来源已知: true,
                语言代码: locale.identifier,
                精确字号: true,
                辅助功能粗体: legibilityWeight == .bold
            )
        )
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在载入…")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(
                    alignment: .top,
                    spacing: usesTwoColumnFoldLayout ? 20 : 14
                ) {
                    ForEach(0..<3, id: \.self) { _ in
                        PaperVN活动加载骨架卡片(scene: cardScene)
                            .PaperVN活动半折双栏适配(
                                usesTwoColumnFoldLayout
                            )
                    }
                }
                .padding(.vertical, 2)
            }
            .PaperVN活动横向书架适配(
                horizontalInset: horizontalInset
            )
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func unavailableContent(
        title: LocalizedStringKey,
        systemImage: String,
        description: String?,
        showsRetry: Bool
    ) -> some View {
        Group {
            if showsRetry, let onRetry {
                平台内容不可用视图 {
                    Label(title, systemImage: systemImage)
                } description: {
                    if let description {
                        Text(verbatim: description)
                    }
                } actions: {
                    Button("重试", action: onRetry)
                }
            } else {
                平台内容不可用视图(title, systemImage: systemImage)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(12)
        .background(
            Color.平台次级分组背景,
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
    }
}

struct PaperVN活动卡片: View {
    let event: PaperVN活动
    let scene: PaperVN活动卡片场景
    let 液态玻璃外观: 沉浸详情外观?
    let 液态玻璃回退色调: Color?

    @Environment(\.locale) private var locale

    private var displayedTitle: 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: nil,
            defaultTitle: event.name,
            偏好: .original,
            回退: .original
        )
    }

    private var informationShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: 28,
                bottomTrailing: 28,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    var body: some View {
        Group {
            if let destinationURL = event.destinationURL {
                Link(destination: destinationURL) { content }
            } else {
                content
            }
        }
        .buttonStyle(.plain)
        .frame(width: 260, alignment: .leading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            CachedAsyncImage(url: URL(string: event.imageURL ?? ""), contentMode: .fill)
                .frame(width: 260, height: 146)
                .background(Color.secondary.opacity(0.12))
                .clipped()

            informationContent
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var informationContent: some View {
        let content = VStack(alignment: .leading, spacing: 6) {
                多语言列表文本(
                    displayedTitle,
                    层级: .主标题,
                    日文字体名称: "HiraginoSans-W5",
                    语言来源已知: false
                )
                    .lineLimit(3)

                HStack(alignment: .top, spacing: 6) {
                    eventMetadataIcon("calendar")

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 4) {
                            eventDateText(event.dateText(locale: locale))
                            if let timeText = event.timeText(locale: locale) {
                                eventTimeText(timeText)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: event.dateText(locale: locale))
                                .fixedSize(horizontal: false, vertical: true)
                            if let timeText = event.timeText(locale: locale) {
                                eventTimeText(timeText)
                            }
                        }
                    }
                    .layoutPriority(1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                if let placeName = event.placeName, !placeName.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        eventMetadataIcon("mappin.and.ellipse")
                        Text(verbatim: placeName)
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)

            switch scene {
        case .today:
            content.background(
                Color.平台次级分组背景,
                in: informationShape
            )
        case .detail:
            if let 液态玻璃外观 {
                content.沉浸详情玻璃背景(
                    液态玻璃外观,
                    fallbackTint: 液态玻璃回退色调,
                    in: informationShape
                )
            } else {
                content.background(
                    .regularMaterial,
                    in: informationShape
                )
            }
        }
    }

    private func eventMetadataIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.caption.weight(.medium))
            .frame(width: 16, alignment: .center)
    }

    private func eventDateText(_ text: String) -> some View {
        Text(verbatim: text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .allowsTightening(false)
    }

    private func eventTimeText(_ text: String) -> some View {
        Text(verbatim: text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .allowsTightening(false)
    }
}

private struct PaperVN活动加载骨架卡片: View {
    let scene: PaperVN活动卡片场景

    private var informationShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: 28,
                bottomTrailing: 28,
                topTrailing: 0
            ),
            style: .continuous
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.secondary.opacity(0.12)
                .frame(width: 260, height: 146)

            informationPlaceholder
        }
        .frame(width: 260, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder
    private var informationPlaceholder: some View {
        let content = VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.22))
                .frame(width: 208, height: 16)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 176, height: 12)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.16))
                .frame(width: 132, height: 12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)

        switch scene {
        case .today:
            content.background(
                Color.平台次级分组背景,
                in: informationShape
            )
        case .detail:
            content.background(
                .regularMaterial,
                in: informationShape
            )
        }
    }
}
