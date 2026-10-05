import Foundation
import Combine
import SwiftUI

nonisolated enum PaperVNURLRoute: Hashable, Sendable {
    case visualNovel(String)
    case character(String)

    static let scheme = "papervn"

    init?(url: URL) {
        guard url.scheme?.caseInsensitiveCompare(Self.scheme) == .orderedSame
        else {
            return nil
        }

        let host = url.host?
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard host != "oauth" else { return nil }

        let pathSegments = url.pathComponents
            .filter { $0 != "/" && !$0.isEmpty }
            .compactMap {
                $0.removingPercentEncoding?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        if let host,
           let entity = Self.entity(for: host),
           let id = pathSegments.first,
           let route = Self.route(entity: entity, id: id) {
            self = route
            return
        }

        if let host, let route = Self.route(forID: host) {
            self = route
            return
        }

        if let first = pathSegments.first,
           let route = Self.route(forID: first) {
            self = route
            return
        }

        if pathSegments.count >= 2,
           let entity = Self.entity(for: pathSegments[0]),
           let route = Self.route(entity: entity, id: pathSegments[1]) {
            self = route
            return
        }

        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        let type = queryItems.first { item in
            ["type", "kind"].contains(item.name.lowercased())
        }?.value
        let queryID = queryItems.first { item in
            ["id", "vndbid", "vndb_id"].contains(item.name.lowercased())
        }?.value
        if let type,
           let entity = Self.entity(for: type),
           let queryID,
           let route = Self.route(entity: entity, id: queryID) {
            self = route
            return
        }

        return nil
    }

    private enum Entity {
        case visualNovel
        case character
    }

    private static func entity(for value: String) -> Entity? {
        switch value.lowercased() {
        case "vn", "visual-novel", "visualnovel", "visual_novel", "visualnovels":
            .visualNovel
        case "c", "character", "characters":
            .character
        default:
            nil
        }
    }

    private static func route(entity: Entity, id: String) -> PaperVNURLRoute? {
        let normalizedID = id
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedID, isValidID(normalizedID) else { return nil }

        switch entity {
        case .visualNovel where normalizedID.first == "v":
            return .visualNovel(normalizedID)
        case .character where normalizedID.first == "c":
            return .character(normalizedID)
        default:
            return nil
        }
    }

    private static func route(forID id: String) -> PaperVNURLRoute? {
        let normalizedID = id
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let normalizedID, isValidID(normalizedID) else { return nil }

        switch normalizedID.first {
        case "v": return .visualNovel(normalizedID)
        case "c": return .character(normalizedID)
        default: return nil
        }
    }

    private static func isValidID(_ id: String) -> Bool {
        guard id.count > 1 else { return false }
        guard id.first == "v" || id.first == "c" else { return false }
        return id.dropFirst().allSatisfy { $0.isNumber }
    }
}

nonisolated struct PaperVNURLRequest: Equatable, Identifiable, Sendable {
    let id = UUID()
    let route: PaperVNURLRoute
}

@MainActor
final class PaperVNURLRouter: ObservableObject {
    @Published private(set) var pendingRequest: PaperVNURLRequest?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let route = PaperVNURLRoute(url: url) else { return false }
        pendingRequest = PaperVNURLRequest(route: route)
        return true
    }

    func consume(_ request: PaperVNURLRequest) {
        guard pendingRequest?.id == request.id else { return }
        pendingRequest = nil
    }
}

@ViewBuilder
func PaperVNURLDestination(
    _ route: PaperVNURLRoute,
    auth: 用户登录
) -> some View {
    switch route {
    case .visualNovel(let id):
        视觉小说详情(vnID: id, auth: auth)
    case .character(let id):
        角色详情(
            characterID: id,
            auth: auth,
            initialName: id
        )
    }
}
