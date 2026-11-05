import Foundation
import Network
import Observation
import os
import StoreKit
import UIKit

/// 诊断信息的一项。标题和值是收集时按用户的语言写好的文字：用户在 App 里看到的就是提交的内容。
nonisolated struct 诊断项: Codable, Hashable, Identifiable, Sendable {
    enum 状态: String, Codable, Sendable {
        case 正常 = "ok"
        case 注意 = "warning"
        case 错误 = "error"
    }

    /// 稳定的英文标识，后台据此辨认，不随语言变化。
    let id: String
    let title: String
    let value: String
    var status: 状态?
}

nonisolated struct 诊断分组: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    var items: [诊断项]
}

/// 提交错误报告时附上的诊断信息。不含密码、令牌、资料库里的作品，只有设备、网络、账户登录状态和同步状态。
nonisolated struct 诊断报告: Codable, Hashable, Sendable {
    var version = 1
    /// ISO 8601，例如“2026-10-26T03:12:45Z”。
    let createdAt: String
    let sections: [诊断分组]

    var 收集时间: Date? { try? Date(createdAt, strategy: .iso8601) }
}

/// 诊断程序：新建反馈时开始运行，选择“错误报告”时显示进度，运行完才能提交错误报告。
@MainActor
@Observable
final class PaperVN诊断程序 {
    private(set) var 已完成步骤 = 0
    private(set) var 报告: 诊断报告?
    private var 正在运行 = false

    /// 网络检查之外的几步各算一步。
    static let 网络检查目标: [(id: String, 名称: String, 地址: URL)] = [
        ("papervn", "PaperVN", URL(string: "https://papervn.jizpaper.com/feedback/healthz")!),
        ("vndb", "VNDB", URL(string: "https://api.vndb.org/kana/stats")!),
        ("myAnimeList", "MyAnimeList", URL(string: "https://api.myanimelist.net/v2/anime?q=a&limit=1")!),
        ("aniList", "AniList", URL(string: "https://graphql.anilist.co")!),
        ("bangumi", "Bangumi", URL(string: "https://api.bgm.tv/v0/subjects/1")!),
        ("annict", "Annict", URL(string: "https://api.annict.com/graphql")!),
        ("tmdb", "TMDB", URL(string: "https://api.themoviedb.org/3")!),
        ("r2", "Cloudflare R2", URL(string: "https://r2-papervn.jizpaper.com/")!),
    ]
    static var 总步骤: Int { 网络检查目标.count + 5 }

    var 进度: Double { Double(已完成步骤) / Double(Self.总步骤) }
    var 已完成: Bool { 报告 != nil }

    /// 开始收集。已经在运行或已经收集完时不重复运行。
    func 开始() {
        guard !正在运行, 报告 == nil else { return }
        正在运行 = true
        Task { await 运行() }
    }

    private func 运行() async {
        var sections: [诊断分组] = []
        sections.append(await Self.App信息())
        已完成步骤 += 1
        sections.append(Self.设备信息())
        已完成步骤 += 1
        sections.append(await 网络信息())
        sections.append(Self.账户与同步())
        已完成步骤 += 1
        sections.append(Self.资料库信息())
        已完成步骤 += 1
        sections.append(Self.数据文件())
        已完成步骤 += 1
        报告 = 诊断报告(createdAt: Date.now.ISO8601Format(), sections: sections)
        正在运行 = false
    }

    // MARK: App 与设备

    private static func App信息() async -> 诊断分组 {
        let info = Bundle.main.infoDictionary ?? [:]
        let source: String
        #if DEBUG
        source = String(localized: "开发版")
        #else
        if case .verified(let transaction) = try? await AppTransaction.shared,
           transaction.environment == .sandbox {
            source = "TestFlight"
        } else {
            source = "App Store"
        }
        #endif
        let senkou = PaperVNSenkou中心.shared
        return 诊断分组(id: "app", title: String(localized: "App"), items: [
            诊断项(id: "version", title: String(localized: "版本"), value: info["CFBundleShortVersionString"] as? String ?? "—"),
            诊断项(id: "build", title: String(localized: "构建版本"), value: info["CFBundleVersion"] as? String ?? "—"),
            诊断项(id: "source", title: String(localized: "安装来源"), value: source),
            诊断项(id: "language", title: String(localized: "语言"), value: Locale.preferredLanguages.prefix(3).joined(separator: ", ")),
            诊断项(id: "region", title: String(localized: "地区"), value: Locale.current.region?.identifier ?? "—"),
            诊断项(id: "timeZone", title: String(localized: "时区"), value: TimeZone.current.identifier),
            诊断项(id: "senkou", title: "PaperVN Senkou", value: 是否(senkou.已解锁)),
        ])
    }

    private static func 设备信息() -> 诊断分组 {
        var system = utsname()
        uname(&system)
        // 模拟器里 uname 是 Mac 的“arm64”，改用模拟的机型
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"].map { "\($0) (Simulator)" }
            ?? withUnsafeBytes(of: &system.machine) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
        let device = UIDevice.current
        let freeSpace = (try? URL.homeDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        let thermal: (String, 诊断项.状态) = switch ProcessInfo.processInfo.thermalState {
        case .nominal: (String(localized: "正常"), .正常)
        case .fair: (String(localized: "略高"), .正常)
        case .serious: (String(localized: "较高"), .注意)
        case .critical: (String(localized: "过高"), .错误)
        @unknown default: ("—", .正常)
        }
        return 诊断分组(id: "device", title: String(localized: "设备"), items: [
            诊断项(id: "model", title: String(localized: "型号"), value: model),
            诊断项(id: "system", title: String(localized: "系统"), value: "\(device.systemName) \(device.systemVersion)"),
            诊断项(id: "memory", title: String(localized: "内存"), value: 大小(Int64(ProcessInfo.processInfo.physicalMemory))),
            诊断项(
                id: "freeSpace", title: String(localized: "可用空间"), value: freeSpace.map(大小) ?? "—",
                status: (freeSpace ?? .max) < 500_000_000 ? .注意 : .正常
            ),
            诊断项(id: "lowPower", title: String(localized: "低电量模式"), value: 是否(ProcessInfo.processInfo.isLowPowerModeEnabled)),
            诊断项(id: "thermal", title: String(localized: "温度状态"), value: thermal.0, status: thermal.1),
        ])
    }

    // MARK: 网络

    private func 网络信息() async -> 诊断分组 {
        var items: [诊断项] = []
        let path = await Self.当前网络()
        let connection: String
        if path.status != .satisfied {
            connection = String(localized: "未连接")
        } else if path.usesInterfaceType(.wifi) {
            connection = "Wi-Fi"
        } else if path.usesInterfaceType(.cellular) {
            connection = String(localized: "蜂窝网络")
        } else if path.usesInterfaceType(.wiredEthernet) {
            connection = String(localized: "有线网络")
        } else {
            connection = String(localized: "其他")
        }
        items.append(诊断项(id: "connection", title: String(localized: "网络连接"), value: connection,
                         status: path.status == .satisfied ? .正常 : .错误))
        items.append(诊断项(id: "lowData", title: String(localized: "低数据模式"), value: Self.是否(path.isConstrained)))
        // 各服务器同时检查，按列表顺序显示
        let results = await withTaskGroup(of: (Int, 诊断项).self) { group in
            for (index, target) in Self.网络检查目标.enumerated() {
                group.addTask { (index, await Self.连接检查(target.id, 名称: target.名称, 地址: target.地址)) }
            }
            var results: [(Int, 诊断项)] = []
            for await result in group {
                results.append(result)
                已完成步骤 += 1
            }
            return results
        }
        items += results.sorted { $0.0 < $1.0 }.map(\.1)
        return 诊断分组(id: "network", title: String(localized: "网络"), items: items)
    }

    private static func 当前网络() async -> NWPath {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            // 取消之前可能又来一次回调，只用第一次的结果
            let resumed = OSAllocatedUnfairLock(initialState: false)
            monitor.pathUpdateHandler = { path in
                guard resumed.withLock({ done in defer { done = true }; return !done }) else { return }
                monitor.cancel()
                continuation.resume(returning: path)
            }
            monitor.start(queue: DispatchQueue(label: "PaperVN诊断.网络"))
        }
    }

    /// 能收到任何 HTTP 响应就算能连接（有的接口不带参数会返回 4xx），只有超时、断网等才算无法连接。
    nonisolated private static func 连接检查(_ id: String, 名称: String, 地址: URL) async -> 诊断项 {
        // 用 GET：有的服务器（包括 PaperVN 自己的健康检查）不接受 HEAD；这些地址的响应都很小
        let request = URLRequest(url: 地址, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let start = Date()
        do {
            let (_, response) = try await session.data(for: request)
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            return 诊断项(
                id: "endpoint.\(id)", title: 名称,
                value: String(localized: "可连接（\(milliseconds) ms，HTTP \(code)）"),
                status: code >= 500 ? .注意 : (milliseconds > 3000 ? .注意 : .正常)
            )
        } catch {
            let reason = (error as? URLError).map { "URLError \($0.code.rawValue)" } ?? error.localizedDescription
            return 诊断项(id: "endpoint.\(id)", title: 名称, value: String(localized: "无法连接（\(reason)）"), status: .错误)
        }
    }

    // MARK: 账户与同步

    private static func 账户与同步() -> 诊断分组 {
        let sync = PaperVNSync中心.shared
        let loggedIn = Set(sync.已登录平台)
        var items: [诊断项] = [
            诊断项(id: "sync.enabled", title: "PaperVN Sync", value: 是否(PaperVNSync中心.已启用)),
        ]
        for platform in 资料库平台.动画漫画平台 {
            var parts = [loggedIn.contains(platform) ? String(localized: "已登录") : String(localized: "未登录")]
            var status: 诊断项.状态 = .正常
            if loggedIn.contains(platform) {
                parts.append(platform.同步方向.localizedTitle)
                if let date = sync.最近同步时间[platform] {
                    parts.append(String(localized: "最近同步：\(date.formatted(date: .numeric, time: .shortened))"))
                }
                switch sync.任务[platform]?.状态 {
                case let .失败(message)?:
                    parts.append(String(localized: "失败：\(message)"))
                    status = .错误
                case .需要处理?:
                    parts.append(String(localized: "等待处理"))
                    status = .注意
                case .进行中?:
                    parts.append(String(localized: "正在同步"))
                default:
                    break
                }
                if let failure = sync.读取失败[platform] {
                    parts.append(String(localized: "读取失败：\(failure)"))
                    status = .错误
                }
            }
            items.append(诊断项(id: "sync.\(platform.rawValue)", title: platform.localizedTitle,
                             value: parts.joined(separator: String(localized: "，")), status: status))
        }
        let unmatched = sync.未匹配作品.values.reduce(0) { $0 + $1.count }
        items.append(诊断项(id: "sync.unmatched", title: String(localized: "找不到的作品"), value: "\(unmatched)",
                         status: unmatched > 0 ? .注意 : .正常))
        items.append(诊断项(id: "sync.hidden", title: String(localized: "隐藏的作品"), value: "\(sync.隐藏数)"))
        return 诊断分组(id: "sync", title: String(localized: "账户与同步"), items: items)
    }

    private static func 资料库信息() -> 诊断分组 {
        let library = 本地资料库.shared
        var counts: [作品类型: Int] = [:]
        for entry in library.条目 { counts[entry.类型, default: 0] += 1 }
        var items = [诊断项(id: "library.loaded", title: String(localized: "已加载"), value: 是否(library.已载入))]
        for type in 作品类型.allCases {
            items.append(诊断项(id: "library.\(type.rawValue)", title: type.localizedTitle, value: "\(counts[type] ?? 0)"))
        }
        return 诊断分组(id: "library", title: String(localized: "资料库"), items: items)
    }

    // MARK: 数据文件

    private static func 数据文件() -> 诊断分组 {
        let map = 作品映射更新.shared.状态
        var mapItems = [
            诊断项(id: "workMap.version", title: String(localized: "作品映射"),
                 value: (map.正在使用的版本 ?? "—") + (map.使用下载的更新 ? String(localized: "（已更新）") : String(localized: "（内置）"))),
        ]
        if let last = map.上次检查 {
            mapItems.append(诊断项(id: "workMap.lastCheck", title: String(localized: "作品映射上次检查"),
                                value: last.formatted(date: .numeric, time: .shortened)))
        }
        if let result = map.上次结果 {
            mapItems.append(诊断项(id: "workMap.lastResult", title: String(localized: "作品映射更新状态"), value: result))
        }
        return 诊断分组(id: "data", title: String(localized: "数据文件"), items: mapItems + [
            诊断项(id: "calibration", title: String(localized: "作品匹配校准表"),
                 value: 作品匹配校准.shared.校准表版本?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "—"),
            诊断项(id: "titleOverrides", title: String(localized: "作品标题"),
                 value: 作品标题覆盖.shared.版本?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? "—"),
            诊断项(id: "smartSearch", title: String(localized: "智能搜索模型"),
                 value: 智能搜索模型存储.当前URL.flatMap(智能搜索模型存储.读取标识) ?? "—"),
            诊断项(id: "recommendation", title: String(localized: "为你推荐模型"),
                 value: 推荐模型存储.当前URL.flatMap(作品推荐模型.标识(of:)) ?? "—"),
        ])
    }

    // MARK: 工具

    private static func 是否(_ value: Bool) -> String {
        value ? String(localized: "是") : String(localized: "否")
    }

    nonisolated private static func 大小(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
