import Combine
import Foundation
import OSLog

/// 作品对应的游戏文件夹。文件夹来自“文件”App，用安全范围书签保存，只在这台设备上有效，不随资料库同步。
nonisolated struct 视觉小说文件夹记录: Codable, Hashable, Sendable {
    var 书签: Data
    var 名称: String
    var 识别: 视觉小说引擎识别结果?
    var 添加时间: Date
}

@MainActor
final class 视觉小说文件夹中心: ObservableObject {
    static let shared = 视觉小说文件夹中心()

    private static let logger = Logger(subsystem: "com.jizpaper.PaperVN", category: "VisualNovelFolder")

    @Published private(set) var 记录: [String: 视觉小说文件夹记录] = [:]

    private init() {
        if let data = try? Data(contentsOf: Self.存储地址),
           let value = try? JSONDecoder().decode([String: 视觉小说文件夹记录].self, from: data) {
            记录 = value
        }
    }

    func 记录(作品 vnID: String) -> 视觉小说文件夹记录? {
        记录[vnID.lowercased()]
    }

    /// 用户在文件选择器里选了文件夹。`url` 是选择器给的安全范围地址。
    func 设置(_ url: URL, 作品 vnID: String) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let recognition = await Task.detached(priority: .userInitiated) {
            视觉小说引擎识别.识别(url)
        }.value
        记录[vnID.lowercased()] = 视觉小说文件夹记录(
            书签: bookmark, 名称: url.lastPathComponent, 识别: recognition, 添加时间: .now
        )
        保存()
        Self.logger.info("Folder set for \(vnID, privacy: .public): \(recognition?.引擎.名称 ?? "unknown", privacy: .public)")
    }

    func 移除(作品 vnID: String) {
        记录[vnID.lowercased()] = nil
        保存()
    }

    /// 解析书签。书签过期（文件夹被移动过）时顺便更新。调用方负责 start/stopAccessingSecurityScopedResource。
    func 文件夹地址(作品 vnID: String) throws -> URL {
        guard var item = 记录(作品: vnID) else { throw 视觉小说运行错误.没有文件夹 }
        var stale = false
        let url = try URL(resolvingBookmarkData: item.书签, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                item.书签 = bookmark
                item.名称 = url.lastPathComponent
                记录[vnID.lowercased()] = item
                保存()
            }
        }
        return url
    }

    /// 游戏文件更新（例如打了补丁）后重新识别。
    func 重新识别(作品 vnID: String) async -> 视觉小说引擎识别结果? {
        guard var item = 记录(作品: vnID), let url = try? 文件夹地址(作品: vnID) else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let recognition = await Task.detached(priority: .userInitiated) {
            视觉小说引擎识别.识别(url)
        }.value
        item.识别 = recognition
        记录[vnID.lowercased()] = item
        保存()
        return recognition
    }

    private func 保存() {
        let url = Self.存储地址
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(记录) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    private static var 存储地址: URL {
        URL.applicationSupportDirectory
            .appending(path: "视觉小说运行", directoryHint: .isDirectory)
            .appending(path: "文件夹.json")
    }

    /// 每部作品自己的数据（NScripter 存档等）。
    static func 数据文件夹(作品 vnID: String) -> URL {
        let url = URL.applicationSupportDirectory
            .appending(path: "视觉小说运行", directoryHint: .isDirectory)
            .appending(path: vnID.lowercased(), directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

nonisolated enum 视觉小说运行错误: LocalizedError {
    case 没有文件夹
    case 无法识别
    case 暂不支持(视觉小说引擎)
    case 无法读取(String)

    var errorDescription: String? {
        switch self {
        case .没有文件夹:
            String(localized: "找不到此视觉小说的文件夹。")
        case .无法识别:
            String(localized: "无法识别此文件夹中的视觉小说。")
        case .暂不支持(let engine):
            String(format: String(localized: "PaperVN暂不支持运行使用%@的视觉小说。"), engine.名称)
        case .无法读取(let reason):
            reason
        }
    }
}
