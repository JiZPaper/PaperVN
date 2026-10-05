import Combine
import Foundation
import SwiftUI
import UIKit

private func 搜索自动重试<T>(
    operation: () async throws -> T
) async throws -> T {
    let maximumRetries = 3
    var lastError: Error = URLError(.unknown)

    for retryCount in 0...maximumRetries {
        do {
            return try await operation()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            lastError = error
            guard retryCount < maximumRetries else { break }
            try await Task.sleep(
                nanoseconds: UInt64(retryCount + 1) * 300_000_000
            )
        }
    }
    throw lastError
}

@MainActor
final class 搜索结果提交门: ObservableObject {
    private var earliestCommitUptimeNanoseconds: UInt64 = 0

    var 正在阻止提交: Bool {
        DispatchTime.now().uptimeNanoseconds
            < earliestCommitUptimeNanoseconds
    }

    func 延迟提交(纳秒: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        earliestCommitUptimeNanoseconds = max(
            earliestCommitUptimeNanoseconds,
            now &+ 纳秒
        )
    }

    func 等待允许提交() async throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < earliestCommitUptimeNanoseconds else { return }
            try await Task.sleep(
                nanoseconds: earliestCommitUptimeNanoseconds - now
            )
        }
    }
}

@MainActor
final class 搜索视图模型: ObservableObject {
    enum 页面状态: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case failed(String)
    }

    @Published private(set) var 视觉小说结果: [视觉小说搜索结果] = []
    @Published private(set) var 角色结果: [角色搜索结果] = []
    private(set) var 当前范围: 搜索范围 = .visualNovel
    @Published private(set) var 视觉小说状态: 页面状态 = .idle
    @Published private(set) var 角色状态: 页面状态 = .idle

    var 状态: 页面状态 {
        当前页面状态(for: 当前范围)
    }

    var 正在加载下一页: Bool {
        是否正在加载下一页(for: 当前范围)
    }

    var 下一页错误: String? {
        加载下一页错误(for: 当前范围)
    }

    var 还有更多: Bool {
        是否还有更多(for: 当前范围)
    }

    private let service: any VNDB搜索服务协议
    private let resultCommitGate: 搜索结果提交门
    private let debounceNanoseconds: UInt64
    private let pageSize: Int
    private var 视觉小说搜索任务: Task<Void, Never>?
    private var 角色搜索任务: Task<Void, Never>?
    private var 视觉小说延迟加载任务: Task<Void, Never>?
    private var 角色延迟加载任务: Task<Void, Never>?
    private var 视觉小说分页任务: Task<Void, Never>?
    private var 角色分页任务: Task<Void, Never>?
    private var 视觉小说请求代次 = 0
    private var 角色请求代次 = 0
    private var 视觉小说当前页 = 0
    private var 角色当前页 = 0
    @Published private var 视觉小说还有更多 = false
    @Published private var 角色还有更多 = false
    @Published private var 视觉小说正在加载下一页 = false
    @Published private var 角色正在加载下一页 = false
    @Published private var 视觉小说下一页错误: String?
    @Published private var 角色下一页错误: String?
    @Published private(set) var 分页加载代次 = 0
    private var 视觉小说等待开始 = false
    private var 角色等待开始 = false
    private var currentVisualNovelQuery = ""
    private var currentVisualNovelFilters = 视觉小说搜索筛选()
    private var currentVisualNovelSort: 视觉小说搜索排序 = .released
    private var currentVisualNovelSortDescending = true
    private var allowsEmptyVisualNovelSearch = false
    private var currentCharacterQuery = ""
    private var currentCharacterFilters = 搜索扩展筛选()
    private var currentCharacterSort: 搜索扩展排序 = .added
    private var currentCharacterSortDescending = true
    private var allowsEmptyCharacterSearch = false

    init(
        service: (any VNDB搜索服务协议)? = nil,
        resultCommitGate: 搜索结果提交门? = nil,
        debounceNanoseconds: UInt64 = 400_000_000,
        pageSize: Int = 平台列表分页.每页
    ) {
        self.service = service ?? VNDB服务.shared
        self.resultCommitGate = resultCommitGate ?? 搜索结果提交门()
        self.debounceNanoseconds = debounceNanoseconds
        self.pageSize = min(max(pageSize, 1), 100)
    }

    deinit {
        视觉小说搜索任务?.cancel()
        角色搜索任务?.cancel()
        视觉小说延迟加载任务?.cancel()
        角色延迟加载任务?.cancel()
        视觉小说分页任务?.cancel()
        角色分页任务?.cancel()
    }

    func 更新搜索(
        关键词: String,
        范围: 搜索范围,
        筛选: 视觉小说搜索筛选,
        排序: 视觉小说搜索排序 = .released,
        扩展筛选: 搜索扩展筛选 = .init(),
        扩展排序: 搜索扩展排序 = .added,
        扩展降序: Bool? = nil,
        降序: Bool? = nil,
        允许空搜索: Bool = false,
        立即: Bool = false
    ) {
        let query = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        let descending = 降序 ?? 排序.defaultIsDescending
        let characterDescending = 扩展降序 ?? 扩展排序.defaultIsDescending
        if 当前范围 != 范围 {
            当前范围 = 范围
        }

        switch 范围 {
        case .visualNovel:
            let changed = query != currentVisualNovelQuery
                || 筛选 != currentVisualNovelFilters
                || 排序 != currentVisualNovelSort
                || descending != currentVisualNovelSortDescending
                || 允许空搜索 != allowsEmptyVisualNovelSearch
            currentVisualNovelQuery = query
            currentVisualNovelFilters = 筛选
            currentVisualNovelSort = 排序
            currentVisualNovelSortDescending = descending
            allowsEmptyVisualNovelSearch = 允许空搜索
            let canSearch = 允许空搜索 || !query.isEmpty || !筛选.isEmpty
            guard canSearch else {
                重置视觉小说搜索()
                return
            }
            if changed || (立即 && (视觉小说等待开始 || 视觉小说状态 == .idle)) {
                安排视觉小说首页(立即: 立即)
            }
        case .character:
            let changed = query != currentCharacterQuery
                || 扩展筛选 != currentCharacterFilters
                || 扩展排序 != currentCharacterSort
                || characterDescending != currentCharacterSortDescending
                || 允许空搜索 != allowsEmptyCharacterSearch
            currentCharacterQuery = query
            currentCharacterFilters = 扩展筛选
            currentCharacterSort = 扩展排序
            currentCharacterSortDescending = characterDescending
            allowsEmptyCharacterSearch = 允许空搜索
            let canSearch = 允许空搜索 || !query.isEmpty
            guard canSearch else {
                重置角色搜索()
                return
            }
            if changed || (立即 && (角色等待开始 || 角色状态 == .idle)) {
                安排角色首页(立即: 立即)
            }
        default:
            return
        }
    }

    func 切换范围(_ 范围: 搜索范围) {
        guard 当前范围 != 范围 else { return }
        当前范围 = 范围
    }

    func 当前页面状态(for 范围: 搜索范围) -> 页面状态 {
        switch 范围 {
        case .visualNovel: return 视觉小说状态
        case .character: return 角色状态
        default: return .idle
        }
    }

    func 是否正在加载下一页(for 范围: 搜索范围) -> Bool {
        switch 范围 {
        case .visualNovel: return 视觉小说正在加载下一页
        case .character: return 角色正在加载下一页
        default: return false
        }
    }

    func 加载下一页错误(for 范围: 搜索范围) -> String? {
        switch 范围 {
        case .visualNovel: return 视觉小说下一页错误
        case .character: return 角色下一页错误
        default: return nil
        }
    }

    func 是否还有更多(for 范围: 搜索范围) -> Bool {
        switch 范围 {
        case .visualNovel: return 视觉小说还有更多
        case .character: return 角色还有更多
        default: return false
        }
    }

    func 重试() {
        重试(范围: 当前范围)
    }

    func 重试(范围: 搜索范围) {
        当前范围 = 范围
        switch 范围 {
        case .visualNovel:
            guard allowsEmptyVisualNovelSearch
                || !currentVisualNovelQuery.isEmpty
                || !currentVisualNovelFilters.isEmpty else { return }
            安排视觉小说首页(立即: true)
        case .character:
            guard allowsEmptyCharacterSearch || !currentCharacterQuery.isEmpty else { return }
            安排角色首页(立即: true)
        default:
            return
        }
    }

    func 加载下一页() {
        加载下一页(范围: 当前范围)
    }

    func 加载下一页(范围: 搜索范围) {
        switch 范围 {
        case .visualNovel:
            加载视觉小说下一页()
        case .character:
            加载角色下一页()
        default:
            return
        }
    }

    private func 安排视觉小说首页(立即: Bool) {
        视觉小说搜索任务?.cancel()
        视觉小说分页任务?.cancel()
        视觉小说延迟加载任务?.cancel()
        视觉小说请求代次 += 1
        let generation = 视觉小说请求代次
        let query = currentVisualNovelQuery
        let filters = currentVisualNovelFilters
        let sort = currentVisualNovelSort
        let descending = currentVisualNovelSortDescending

        视觉小说等待开始 = true
        if resultCommitGate.正在阻止提交 {
            安排视觉小说延迟加载(generation: generation)
        } else if 立即 || (视觉小说结果.isEmpty && 视觉小说状态 != .loading) {
            视觉小说状态 = .loading
        }

        视觉小说搜索任务 = Task { [weak self] in
            guard let self else { return }
            do {
                try await 等待防抖(立即: 立即)
                try Task.checkCancellation()
                guard generation == 视觉小说请求代次 else { return }

                视觉小说等待开始 = false
                if resultCommitGate.正在阻止提交 {
                    安排视觉小说延迟加载(generation: generation)
                } else {
                    准备视觉小说首页加载()
                }

                let response = try await 搜索自动重试 {
                    try await service.搜索视觉小说(
                        关键词: query,
                        筛选: filters,
                        排序: sort,
                        降序: descending,
                        页码: 1,
                        每页: pageSize
                    )
                }
                try await resultCommitGate.等待允许提交()
                try Task.checkCancellation()
                guard generation == 视觉小说请求代次 else { return }

                视觉小说延迟加载任务?.cancel()
                视觉小说结果 = response.results
                视觉小说当前页 = 1
                视觉小说还有更多 = response.more
                视觉小说状态 = response.results.isEmpty ? .empty : .loaded
            } catch is CancellationError {
                return
            } catch {
                let message = error.localizedDescription
                do {
                    try await resultCommitGate.等待允许提交()
                } catch {
                    return
                }
                guard generation == 视觉小说请求代次 else { return }
                视觉小说延迟加载任务?.cancel()
                视觉小说状态 = .failed(message)
            }
        }
    }

    private func 安排角色首页(立即: Bool) {
        角色搜索任务?.cancel()
        角色分页任务?.cancel()
        角色延迟加载任务?.cancel()
        角色请求代次 += 1
        let generation = 角色请求代次
        let query = currentCharacterQuery
        let filters = currentCharacterFilters
        let sort = currentCharacterSort
        let descending = currentCharacterSortDescending

        角色等待开始 = true
        if resultCommitGate.正在阻止提交 {
            安排角色延迟加载(generation: generation)
        } else if 立即 || (角色结果.isEmpty && 角色状态 != .loading) {
            角色状态 = .loading
        }

        角色搜索任务 = Task { [weak self] in
            guard let self else { return }
            do {
                try await 等待防抖(立即: 立即)
                try Task.checkCancellation()
                guard generation == 角色请求代次 else { return }

                角色等待开始 = false
                if resultCommitGate.正在阻止提交 {
                    安排角色延迟加载(generation: generation)
                } else {
                    准备角色首页加载()
                }

                let response = try await 搜索自动重试 {
                    try await service.搜索角色(
                        关键词: query,
                        筛选: filters,
                        排序: sort,
                        降序: descending,
                        页码: 1,
                        每页: pageSize
                    )
                }
                try await resultCommitGate.等待允许提交()
                try Task.checkCancellation()
                guard generation == 角色请求代次 else { return }

                角色延迟加载任务?.cancel()
                角色结果 = 内容安全高级设置解锁入口.合并固定结果(
                    response.results,
                    query: query
                )
                角色当前页 = 1
                角色还有更多 = response.more
                角色状态 = 角色结果.isEmpty ? .empty : .loaded
            } catch is CancellationError {
                return
            } catch {
                let message = error.localizedDescription
                do {
                    try await resultCommitGate.等待允许提交()
                } catch {
                    return
                }
                guard generation == 角色请求代次 else { return }
                角色延迟加载任务?.cancel()
                if 内容安全高级设置解锁入口.是触发搜索(query),
                   let 固定角色结果 = 内容安全高级设置解锁入口.固定角色结果 {
                    角色结果 = [固定角色结果]
                    角色当前页 = 1
                    角色还有更多 = false
                    角色状态 = .loaded
                } else {
                    角色状态 = .failed(message)
                }
            }
        }
    }

    private func 安排视觉小说延迟加载(generation: Int) {
        视觉小说延迟加载任务?.cancel()
        视觉小说延迟加载任务 = Task { [weak self] in
            guard let self else { return }
            do {
                try await resultCommitGate.等待允许提交()
                try Task.checkCancellation()
                guard generation == 视觉小说请求代次 else { return }
                准备视觉小说首页加载()
            } catch {
                return
            }
        }
    }

    private func 安排角色延迟加载(generation: Int) {
        角色延迟加载任务?.cancel()
        角色延迟加载任务 = Task { [weak self] in
            guard let self else { return }
            do {
                try await resultCommitGate.等待允许提交()
                try Task.checkCancellation()
                guard generation == 角色请求代次 else { return }
                准备角色首页加载()
            } catch {
                return
            }
        }
    }

    private func 准备视觉小说首页加载() {
        视觉小说结果 = []
        视觉小说当前页 = 0
        视觉小说还有更多 = false
        视觉小说正在加载下一页 = false
        视觉小说下一页错误 = nil
        视觉小说状态 = .loading
    }

    private func 准备角色首页加载() {
        角色结果 = []
        角色当前页 = 0
        角色还有更多 = false
        角色正在加载下一页 = false
        角色下一页错误 = nil
        角色状态 = .loading
    }

    private func 等待防抖(立即: Bool) async throws {
        if !立即, debounceNanoseconds > 0 {
            try await Task.sleep(nanoseconds: debounceNanoseconds)
        }
    }

    private func 重置视觉小说搜索() {
        视觉小说搜索任务?.cancel()
        视觉小说分页任务?.cancel()
        视觉小说延迟加载任务?.cancel()
        视觉小说请求代次 += 1
        视觉小说结果 = []
        视觉小说当前页 = 0
        视觉小说还有更多 = false
        视觉小说正在加载下一页 = false
        视觉小说下一页错误 = nil
        视觉小说等待开始 = false
        视觉小说状态 = .idle
    }

    private func 重置角色搜索() {
        角色搜索任务?.cancel()
        角色分页任务?.cancel()
        角色延迟加载任务?.cancel()
        角色请求代次 += 1
        角色结果 = []
        角色当前页 = 0
        角色还有更多 = false
        角色正在加载下一页 = false
        角色下一页错误 = nil
        角色等待开始 = false
        角色状态 = .idle
    }

    private func 加载视觉小说下一页() {
        guard 视觉小说状态 == .loaded,
              视觉小说还有更多,
              !视觉小说正在加载下一页,
              allowsEmptyVisualNovelSearch
                || !currentVisualNovelQuery.isEmpty
                || !currentVisualNovelFilters.isEmpty
        else { return }

        视觉小说正在加载下一页 = true
        视觉小说下一页错误 = nil
        分页加载代次 += 1
        let generation = 视觉小说请求代次
        let page = 视觉小说当前页 + 1
        let query = currentVisualNovelQuery
        let filters = currentVisualNovelFilters
        let sort = currentVisualNovelSort
        let descending = currentVisualNovelSortDescending

        视觉小说分页任务 = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await 搜索自动重试 {
                    try await service.搜索视觉小说(
                        关键词: query,
                        筛选: filters,
                        排序: sort,
                        降序: descending,
                        页码: page,
                        每页: pageSize
                    )
                }
                try Task.checkCancellation()
                guard generation == 视觉小说请求代次 else { return }

                视觉小说结果 = 合并去重(视觉小说结果, response.results)
                视觉小说当前页 = page
                视觉小说还有更多 = response.more
                视觉小说正在加载下一页 = false
                视觉小说下一页错误 = nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == 视觉小说请求代次 else { return }
                视觉小说下一页错误 = error.localizedDescription
                视觉小说正在加载下一页 = false
            }
        }
    }

    private func 加载角色下一页() {
        guard 角色状态 == .loaded,
              角色还有更多,
              !角色正在加载下一页,
              allowsEmptyCharacterSearch || !currentCharacterQuery.isEmpty
        else { return }

        角色正在加载下一页 = true
        角色下一页错误 = nil
        分页加载代次 += 1
        let generation = 角色请求代次
        let page = 角色当前页 + 1
        let query = currentCharacterQuery
        let filters = currentCharacterFilters
        let sort = currentCharacterSort
        let descending = currentCharacterSortDescending

        角色分页任务 = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await 搜索自动重试 {
                    try await service.搜索角色(
                        关键词: query,
                        筛选: filters,
                        排序: sort,
                        降序: descending,
                        页码: page,
                        每页: pageSize
                    )
                }
                try Task.checkCancellation()
                guard generation == 角色请求代次 else { return }

                角色结果 = 合并去重(角色结果, response.results)
                角色当前页 = page
                角色还有更多 = response.more
                角色正在加载下一页 = false
                角色下一页错误 = nil
            } catch is CancellationError {
                return
            } catch {
                guard generation == 角色请求代次 else { return }
                角色下一页错误 = error.localizedDescription
                角色正在加载下一页 = false
            }
        }
    }

    private func 合并去重<Item: Identifiable>(
        _ existing: [Item],
        _ incoming: [Item]
    ) -> [Item] where Item.ID: Hashable {
        var seen = Set(existing.map(\.id))
        return existing + incoming.filter { seen.insert($0.id).inserted }
    }
}

@MainActor
final class 扩展搜索视图模型: ObservableObject {
    typealias 状态 = 搜索视图模型.页面状态

    @Published private(set) var 发行版本结果: [探索发行版本] = []
    @Published private(set) var 制作人员结果: [探索制作人员] = []
    @Published private(set) var 会社结果: [探索会社] = []
    @Published private(set) var 当前状态: 状态 = .idle
    @Published private(set) var 正在加载下一页 = false
    @Published private(set) var 下一页错误: String?
    @Published private(set) var 还有更多 = false
    @Published private(set) var 分页加载代次 = 0

    private let service: any VNDB搜索服务协议
    private let resultCommitGate: 搜索结果提交门
    private let debounceNanoseconds: UInt64
    private let pageSize: Int
    private var searchTask: Task<Void, Never>?
    private var delayedLoadingTask: Task<Void, Never>?
    private var pageTask: Task<Void, Never>?
    private var requestGeneration = 0
    private var currentPage = 0
    private var currentQuery = ""
    private var currentScope: 搜索范围 = .visualNovel
    private var currentFilters = 搜索扩展筛选()
    private var currentSort: 搜索扩展排序 = .added
    private var currentSortDescending = true
    private var searchWaitingToStart = false

    init(
        service: (any VNDB搜索服务协议)? = nil,
        resultCommitGate: 搜索结果提交门? = nil,
        debounceNanoseconds: UInt64 = 400_000_000,
        pageSize: Int = 平台列表分页.每页
    ) {
        self.service = service ?? VNDB服务.shared
        self.resultCommitGate = resultCommitGate ?? 搜索结果提交门()
        self.debounceNanoseconds = debounceNanoseconds
        self.pageSize = min(max(pageSize, 1), 100)
    }

    deinit {
        searchTask?.cancel()
        delayedLoadingTask?.cancel()
        pageTask?.cancel()
    }

    var 结果数量: Int {
        switch currentScope {
        case .release: return 发行版本结果.count
        case .staff: return 制作人员结果.count
        case .producer: return 会社结果.count
        default: return 0
        }
    }

    func 更新搜索(
        关键词: String,
        范围: 搜索范围,
        筛选: 搜索扩展筛选 = .init(),
        排序: 搜索扩展排序 = .added,
        降序: Bool? = nil,
        立即: Bool = false
    ) {
        guard 范围.is扩展搜索范围 else {
            if currentScope.is扩展搜索范围 {
                重置()
            }
            currentQuery = ""
            currentScope = 范围
            return
        }

        let query = 关键词.trimmingCharacters(in: .whitespacesAndNewlines)
        let descending = 降序 ?? 排序.defaultIsDescending
        let changed = query != currentQuery
            || 范围 != currentScope
            || 筛选 != currentFilters
            || 排序 != currentSort
            || descending != currentSortDescending
        currentQuery = query
        currentScope = 范围
        currentFilters = 筛选
        currentSort = 排序
        currentSortDescending = descending
        guard changed else {
            if 立即, searchWaitingToStart {
                安排首页(立即: true)
            }
            return
        }

        安排首页(立即: 立即)
    }

    func 重试() {
        安排首页(立即: true)
    }

    func 加载下一页() {
        guard 当前状态 == .loaded,
              还有更多,
              !正在加载下一页 else { return }

        正在加载下一页 = true
        下一页错误 = nil
        分页加载代次 += 1
        let generation = requestGeneration
        let page = currentPage + 1
        let query = currentQuery
        let scope = currentScope
        let filters = currentFilters
        let sort = currentSort
        let descending = currentSortDescending

        pageTask?.cancel()
        pageTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await 搜索自动重试 {
                    try await self.请求(
                        关键词: query,
                        范围: scope,
                        筛选: filters,
                        排序: sort,
                        降序: descending,
                        页码: page
                    )
                }
                try Task.checkCancellation()
                guard generation == requestGeneration, scope == currentScope else { return }
                合并(response.results, 范围: scope)
                currentPage = page
                还有更多 = response.more
                正在加载下一页 = false
            } catch is CancellationError {
                return
            } catch {
                guard generation == requestGeneration else { return }
                下一页错误 = error.localizedDescription
                正在加载下一页 = false
            }
        }
    }

    private func 安排首页(立即: Bool) {
        searchTask?.cancel()
        delayedLoadingTask?.cancel()
        pageTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let query = currentQuery
        let scope = currentScope
        let filters = currentFilters
        let sort = currentSort
        let descending = currentSortDescending

        searchWaitingToStart = true
        if resultCommitGate.正在阻止提交 {
            安排延迟加载(generation: generation, scope: scope)
        } else if 立即 || (结果数量 == 0 && 当前状态 != .loading) {
            当前状态 = .loading
        }

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !立即, debounceNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: debounceNanoseconds)
                }
                try Task.checkCancellation()
                guard generation == requestGeneration, scope == currentScope else { return }

                searchWaitingToStart = false
                if resultCommitGate.正在阻止提交 {
                    安排延迟加载(generation: generation, scope: scope)
                } else {
                    准备首页加载()
                }

                let response = try await 搜索自动重试 {
                    try await self.请求(
                        关键词: query,
                        范围: scope,
                        筛选: filters,
                        排序: sort,
                        降序: descending,
                        页码: 1
                    )
                }
                try await resultCommitGate.等待允许提交()
                try Task.checkCancellation()
                guard generation == requestGeneration, scope == currentScope else { return }
                delayedLoadingTask?.cancel()
                设置结果(response.results, 范围: scope)
                currentPage = 1
                还有更多 = response.more
                当前状态 = 结果数量 == 0 ? .empty : .loaded
            } catch is CancellationError {
                return
            } catch {
                let message = error.localizedDescription
                do {
                    try await resultCommitGate.等待允许提交()
                } catch {
                    return
                }
                guard generation == requestGeneration else { return }
                delayedLoadingTask?.cancel()
                当前状态 = .failed(message)
            }
        }
    }

    private func 安排延迟加载(generation: Int, scope: 搜索范围) {
        delayedLoadingTask?.cancel()
        delayedLoadingTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await resultCommitGate.等待允许提交()
                try Task.checkCancellation()
                guard generation == requestGeneration,
                      scope == currentScope else { return }
                准备首页加载()
            } catch {
                return
            }
        }
    }

    private func 准备首页加载() {
        发行版本结果 = []
        制作人员结果 = []
        会社结果 = []
        当前状态 = .loading
        正在加载下一页 = false
        下一页错误 = nil
        还有更多 = false
        currentPage = 0
    }

    private func 请求(
        关键词: String,
        范围: 搜索范围,
        筛选: 搜索扩展筛选,
        排序: 搜索扩展排序,
        降序: Bool,
        页码: Int
    ) async throws -> 扩展搜索响应 {
        switch 范围 {
        case .release:
            let response = try await service.搜索发行版本(
                关键词: 关键词, 筛选: 筛选, 排序: 排序, 降序: 降序,
                页码: 页码, 每页: pageSize
            )
            return .init(results: response.results.map(扩展搜索结果.release), more: response.more)
        case .staff:
            let response = try await service.搜索制作人员(
                关键词: 关键词, 筛选: 筛选, 排序: 排序, 降序: 降序,
                页码: 页码, 每页: pageSize
            )
            return .init(results: response.results.map(扩展搜索结果.staff), more: response.more)
        case .producer:
            let response = try await service.搜索会社(
                关键词: 关键词, 筛选: 筛选, 排序: 排序, 降序: 降序,
                页码: 页码, 每页: pageSize
            )
            return .init(results: response.results.map(扩展搜索结果.producer), more: response.more)
        default:
            throw VNDB服务错误.无效搜索关键词
        }
    }

    private func 设置结果(_ results: [扩展搜索结果], 范围: 搜索范围) {
        switch 范围 {
        case .release: 发行版本结果 = results.compactMap { if case let .release(item) = $0 { return item }; return nil }
        case .staff: 制作人员结果 = results.compactMap { if case let .staff(item) = $0 { return item }; return nil }
        case .producer: 会社结果 = results.compactMap { if case let .producer(item) = $0 { return item }; return nil }
        default: break
        }
    }

    private func 合并(_ results: [扩展搜索结果], 范围: 搜索范围) {
        switch 范围 {
        case .release:
            let incoming = results.compactMap { if case let .release(item) = $0 { return item }; return nil }
            发行版本结果 = 合并去重(发行版本结果, incoming)
        case .staff:
            let incoming = results.compactMap { if case let .staff(item) = $0 { return item }; return nil }
            制作人员结果 = 合并去重(制作人员结果, incoming)
        case .producer:
            let incoming = results.compactMap { if case let .producer(item) = $0 { return item }; return nil }
            会社结果 = 合并去重(会社结果, incoming)
        default: break
        }
    }

    private func 合并去重<Item: Identifiable>(
        _ existing: [Item],
        _ incoming: [Item]
    ) -> [Item] where Item.ID: Hashable {
        var seen = Set(existing.map(\.id))
        return existing + incoming.filter { seen.insert($0.id).inserted }
    }

    private func 重置() {
        searchTask?.cancel()
        delayedLoadingTask?.cancel()
        pageTask?.cancel()
        requestGeneration += 1
        searchWaitingToStart = false
        发行版本结果 = []
        制作人员结果 = []
        会社结果 = []
        当前状态 = .idle
        正在加载下一页 = false
        下一页错误 = nil
        还有更多 = false
        currentPage = 0
    }
}

private enum 扩展搜索结果 {
    case release(探索发行版本)
    case staff(探索制作人员)
    case producer(探索会社)
}

private struct 扩展搜索响应 {
    let results: [扩展搜索结果]
    let more: Bool
}

private extension 搜索范围 {
    var is扩展搜索范围: Bool {
        switch self {
        case .release, .staff, .producer: return true
        default: return false
        }
    }
}

private struct 视觉小说搜索排序选择: Equatable {
    var sort: 视觉小说搜索排序
    var isDescending: Bool

    init(
        sort: 视觉小说搜索排序 = .released,
        isDescending: Bool? = nil
    ) {
        self.sort = sort
        self.isDescending = isDescending ?? sort.defaultIsDescending
    }
}

private struct 搜索扩展排序选择: Equatable {
    var sort: 搜索扩展排序
    var isDescending: Bool

    init(
        sort: 搜索扩展排序 = .added,
        isDescending: Bool? = nil
    ) {
        self.sort = sort
        self.isDescending = isDescending ?? sort.defaultIsDescending
    }
}

private struct 搜索资料库作品: Identifiable {
    let id: String
    let title: String
    let titles: [用户多语言标题]?
    let image: 用户列表项目.用户列表详细信息.用户列表图片?
    let rating: Double?
    let voteCount: Int?
    let released: String?

    init(_ result: 视觉小说搜索结果) {
        id = result.id
        title = result.title
        titles = result.titles
        image = result.image.map {
            .init(
                url: $0.url,
                thumbnail: $0.thumbnail,
                sexual: $0.sexual,
                violence: $0.violence,
                dims: $0.dims
            )
        }
        rating = result.rating
        voteCount = result.votecount
        released = result.released
    }

    init(_ work: 探索发行作品) {
        id = work.id
        title = work.title
        titles = work.详情多语言标题
        image = work.image.map {
            .init(
                url: $0.url,
                thumbnail: $0.thumbnail,
                sexual: $0.sexual,
                violence: $0.violence,
                dims: $0.dims
            )
        }
        rating = nil
        voteCount = nil
        released = nil
    }
}

private struct 搜索资料库编辑目标: Identifiable {
    let work: 搜索资料库作品
    let currentItem: 用户列表项目
    let initialReleaseID: String?

    var id: String { work.id }
}

private struct 搜索资料库删除目标: Identifiable {
    let work: 搜索资料库作品

    var id: String { work.id }
}

@MainActor
private final class 搜索输入存储 {
    var text: String

    init(text: String) {
        self.text = text
    }
}

struct 搜索: View {
    @EnvironmentObject private var auth: 用户登录
    @EnvironmentObject private var bangumiAccount: Bangumi账户
    @EnvironmentObject private var parentalControls: 家长控制中心
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var namespace
    @StateObject private var resultCommitGate: 搜索结果提交门
    @StateObject private var viewModel: 搜索视图模型
    @StateObject private var releaseSearchViewModel: 扩展搜索视图模型
    @StateObject private var staffSearchViewModel: 扩展搜索视图模型
    @StateObject private var producerSearchViewModel: 扩展搜索视图模型
    @StateObject private var blurRevealConfirmation = 模糊解除确认器()

    @State private var localSelectedScope: 搜索范围 = .visualNovel
    @State private var scopeTransitionGeneration = 0
    @State private var scopeTransitionTarget: 搜索范围?
    @State private var displayedScope: 搜索范围
    @State private var isScopeTransitioning = false
    @State private var searchInput: 搜索输入存储
    @State private var hasSearchTextState: Bool
    @State private var selectedSort = 视觉小说搜索排序选择()
    @State private var filters = 视觉小说搜索筛选()
    @State private var draftFilters = 视觉小说搜索筛选()
    @State private var characterSort = 搜索扩展排序选择(sort: .added)
    @State private var releaseSort = 搜索扩展排序选择(sort: .released)
    @State private var staffSort = 搜索扩展排序选择(sort: .added)
    @State private var producerSort = 搜索扩展排序选择(sort: .added)
    @State private var characterFilters = 搜索扩展筛选()
    @State private var releaseFilters = 搜索扩展筛选()
    @State private var staffFilters = 搜索扩展筛选()
    @State private var producerFilters = 搜索扩展筛选()
    @State private var draftExtendedFilters = 搜索扩展筛选()
    @State private var filterPresentationScope: 搜索范围?
    @State private var revealedImageIDs: Set<String> = []
    @State private var unlockCharacterDestination: 角色搜索结果?
    @State private var libraryItemsByID: [String: 用户列表项目] = [:]
    @State private var libraryListLoadedForUserID: String?
    @State private var libraryMutationGeneration = 0
    @State private var libraryEditorTarget: 搜索资料库编辑目标?
    @State private var libraryDeleteTarget: 搜索资料库删除目标?
    @State private var libraryActionError: String?
    @State private var showLoginRequiredAlert = false
    @State private var isPerformingLibraryAction = false
    @State private var isパーパルPresented = false
    @State private var keyboardSearchFieldClearance: CGFloat = 0

    private let externalSelectedScope: Binding<搜索范围>?
    private let externalSearchText: Binding<String>?
    private let showsSearchField: Bool
    private let showsIPadToolbarScopePicker: Bool
    private let scopeGlassAnimationNanoseconds: UInt64 = 450_000_000
    private let scopeTransitionDelayNanoseconds: UInt64 = 600_000_000

    @AppStorage("preferredTitleLang")
    private var preferredTitleLang: 标题语言 = .original
    @AppStorage("fallbackTitleLang")
    private var fallbackTitleLang: 标题语言 = .original
    @AppStorage("subTitleLang")
    private var subTitleLang: 副标题语言 = .none
    @AppStorage("allowUnofficialTitles")
    private var allowUnofficialTitles = false
    @AppStorage("staffNameLang")
    private var staffNameLang: 制作人员语言 = .romaji
    @AppStorage("contentFilterEnabled")
    private var contentFilterEnabled = false
    @AppStorage("sexualThreshold")
    private var sexualThreshold: Double = 0.8
    @AppStorage("violenceThreshold")
    private var violenceThreshold: Double = 1
    @AppStorage("filterMode")
    private var filterMode: 内容过滤模式 = .both
    @AppStorage("contentRestrictionMethod")
    private var contentRestrictionMethod: 内容限制方式 = .blurred

    init(
        searchText: Binding<String>? = nil,
        selectedScope: Binding<搜索范围>? = nil,
        showsSearchField: Bool = true,
        showsIPadToolbarScopePicker: Bool = true
    ) {
        let initialSearchText = searchText?.wrappedValue ?? ""
        let initialScope = selectedScope?.wrappedValue ?? .visualNovel
        let initiallyHasSearchText = !initialSearchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        _searchInput = State(
            initialValue: 搜索输入存储(text: initialSearchText)
        )
        _hasSearchTextState = State(
            initialValue: initiallyHasSearchText
        )
        _displayedScope = State(initialValue: initialScope)
        let resultCommitGate = 搜索结果提交门()
        _resultCommitGate = StateObject(wrappedValue: resultCommitGate)
        _viewModel = StateObject(
            wrappedValue: 搜索视图模型(resultCommitGate: resultCommitGate)
        )
        _releaseSearchViewModel = StateObject(
            wrappedValue: 扩展搜索视图模型(resultCommitGate: resultCommitGate)
        )
        _staffSearchViewModel = StateObject(
            wrappedValue: 扩展搜索视图模型(resultCommitGate: resultCommitGate)
        )
        _producerSearchViewModel = StateObject(
            wrappedValue: 扩展搜索视图模型(resultCommitGate: resultCommitGate)
        )
        _selectedSort = State(
            initialValue: .init(
                sort: initiallyHasSearchText ? .relevance : .released
            )
        )
        _characterSort = State(
            initialValue: .init(
                sort: initiallyHasSearchText ? .relevance : .added
            )
        )
        _releaseSort = State(
            initialValue: .init(
                sort: initiallyHasSearchText ? .relevance : .released
            )
        )
        _staffSort = State(
            initialValue: .init(
                sort: initiallyHasSearchText ? .relevance : .added
            )
        )
        _producerSort = State(
            initialValue: .init(
                sort: initiallyHasSearchText ? .relevance : .added
            )
        )
        externalSearchText = searchText
        externalSelectedScope = selectedScope
        self.showsSearchField = showsSearchField
        self.showsIPadToolbarScopePicker = showsIPadToolbarScopePicker
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchInput.text },
            set: { updateSearchText($0) }
        )
    }

    private var selectedScopeBinding: Binding<搜索范围> {
        externalSelectedScope ?? $localSelectedScope
    }

    private var searchText: String {
        searchInput.text
    }

    private var externalSearchTextValue: String? {
        externalSearchText?.wrappedValue
    }

    private var selectedScope: 搜索范围 {
        selectedScopeBinding.wrappedValue
    }

    private var visualSelectedScope: 搜索范围 {
        scopeTransitionTarget ?? displayedScope
    }

    private var displayedScopeBinding: Binding<搜索范围> {
        Binding(
            get: { visualSelectedScope },
            set: { startScopeTransition(to: $0) }
        )
    }

    private var currentExtendedSortBinding: Binding<搜索扩展排序选择> {
        switch selectedScope {
        case .character: return $characterSort
        case .release: return $releaseSort
        case .staff: return $staffSort
        case .producer: return $producerSort
        case .visualNovel: return .constant(.init())
        }
    }

    private var currentExtendedFilters: 搜索扩展筛选 {
        filters(for: selectedScope)
    }

    private func extendedViewModel(for scope: 搜索范围) -> 扩展搜索视图模型 {
        switch scope {
        case .staff: return staffSearchViewModel
        case .producer: return producerSearchViewModel
        default: return releaseSearchViewModel
        }
    }

    private var searchNavigationTitle: String {
        String(localized: "搜索")
    }

    private var searchPrompt: String {
        switch selectedScope {
        case .visualNovel: return String(localized: "搜索视觉小说")
        case .character: return String(localized: "搜索角色")
        case .release: return String(localized: "搜索发行版本")
        case .staff: return String(localized: "搜索制作人员")
        case .producer: return String(localized: "搜索开发与发行商")
        }
    }

    private var usesIOS27SearchLayout: Bool {
        if #available(iOS 27.0, *) {
            return true
        }
        return false
    }

    private var usesIPadSearchLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var showsToolbarScopePicker: Bool {
        usesIPadSearchLayout
            && showsIPadToolbarScopePicker
    }

    private var showsTopScopePicker: Bool {
        usesIOS27SearchLayout || showsToolbarScopePicker
    }

    private var usesExplicitSearchToolbarItem: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return usesIPadSearchLayout && showsSearchField
    }

    var body: some View {
        searchPage
    }

    private var searchPage: some View {
        Group {
            if usesIPadSearchLayout {
                if showsSearchField {
                    searchContent
                        .searchable(
                            text: searchTextBinding,
                            prompt: Text(searchPrompt)
                        )
                } else {
                    searchContent
                }
            } else if showsSearchField {
                searchContent
                    .searchable(
                        text: searchTextBinding,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(searchPrompt)
                    )
            } else {
                searchContent
            }
        }
        .平台搜索栏保持内容可见()
        .safeAreaInset(edge: .top, spacing: 0) {
            if showsTopScopePicker {
                topSearchScopePicker
            }
        }
        .modifier(
            iPad搜索工具栏项配置(
                usesExplicitSearchItem: usesExplicitSearchToolbarItem
            )
        )
    }

    private var searchContent: some View {
        searchPresentationContent
            .onAppear {
                syncExternalSearchTextIfNeeded()
            }
            .onDisappear {
                syncExternalSearchTextIfNeeded()
                blurRevealConfirmation.cancel()
            }
    }

    private var searchBaseContent: some View {
        searchRootContent
        .background(Color.平台分组背景.ignoresSafeArea())
        .navigationTitle(Text(verbatim: searchNavigationTitle))
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
        .navigationDestination(item: $unlockCharacterDestination) { item in
            角色详情(
                characterID: item.id,
                auth: auth,
                initialName: item.name,
                initialOriginal: item.original,
                initialAliases: item.aliases,
                initialImage: item.image
            )
        }
        .平台键盘搜索栏避让($keyboardSearchFieldClearance)
        .modifier(
            搜索提交处理器 {
                syncExternalSearchTextIfNeeded()
                submitSearch(immediately: true)
            }
        )
        .task {
            submitSearch(immediately: true)
        }
        .onChange(of: externalSearchTextValue) { _, newValue in
            guard let newValue, newValue != searchText else { return }
            updateSearchText(newValue)
        }
        .onChange(of: selectedScope) { _, newScope in
            guard newScope != visualSelectedScope || !isScopeTransitioning else {
                return
            }
            startScopeTransition(to: newScope)
        }
        .task(id: scopeTransitionGeneration) {
            guard scopeTransitionGeneration > 0,
                  let target = scopeTransitionTarget else { return }
            let generation = scopeTransitionGeneration
            do {
                try await Task.sleep(
                    nanoseconds: max(
                        scopeGlassAnimationNanoseconds,
                        scopeTransitionDelayNanoseconds
                    )
                )
            } catch {
                return
            }
            guard generation == scopeTransitionGeneration,
                  target == scopeTransitionTarget else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isScopeTransitioning = false
                scopeTransitionTarget = nil
            }
        }
        .onChange(of: unlockCharacterDestination) { previous, current in
            guard let 解锁角色ID = 内容安全高级设置解锁入口.角色ID,
                  previous?.id == 解锁角色ID,
                  current == nil else {
                return
            }
            强制内容安全策略.尝试解锁(token: auth.token)
        }
        .task(id: "\(auth.userID)|\(auth.token)") {
            await loadLibraryItems()
        }
    }

    private var searchSortObservedContent: some View {
        searchBaseContent
        .onChange(of: selectedSort) { _, _ in
            guard selectedScope == .visualNovel else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: characterSort) { _, _ in
            guard selectedScope == .character else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: releaseSort) { _, _ in
            guard selectedScope == .release else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: staffSort) { _, _ in
            guard selectedScope == .staff else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: producerSort) { _, _ in
            guard selectedScope == .producer else { return }
            submitSearch(immediately: true)
        }
    }

    private var searchFilterObservedContent: some View {
        searchSortObservedContent
        .onChange(of: filters) { _, _ in
            guard selectedScope == .visualNovel else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: characterFilters) { _, _ in
            guard selectedScope == .character else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: releaseFilters) { _, _ in
            guard selectedScope == .release else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: staffFilters) { _, _ in
            guard selectedScope == .staff else { return }
            submitSearch(immediately: true)
        }
        .onChange(of: producerFilters) { _, _ in
            guard selectedScope == .producer else { return }
            submitSearch(immediately: true)
        }
    }

    private var searchPresentationContent: some View {
        searchFilterObservedContent
        .toolbar {
            ToolbarItem(placement: .平台前导操作) {
                Button {
                    isパーパルPresented = true
                } label: {
                    Image(systemName: "sparkles")
                        .foregroundStyle(
                            LinearGradient(
                                colors: パーパル光効配置.色環,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .accessibilityLabel("パーパル")
                .accessibilityIdentifier("search.assistant")
                .平台匹配转场源(id: "パーパル页面", in: namespace)
            }

            ToolbarItemGroup(placement: .平台主操作) {
                if selectedScope == .visualNovel {
                    搜索排序菜单(
                        selection: $selectedSort,
                        hasSearchText: hasSearchText
                    )
                    .accessibilityIdentifier("search.sort")
                } else {
                    搜索扩展排序菜单(
                        selection: currentExtendedSortBinding,
                        scope: selectedScope,
                        hasSearchText: hasSearchText
                    )
                    .accessibilityIdentifier("search.sort")
                }

                Button {
                    presentFilters()
                } label: {
                    Image(
                        systemName: 当前筛选为空
                            ? "line.3.horizontal.decrease"
                            : "line.3.horizontal.decrease.circle.fill"
                    )
                }
                .accessibilityLabel("筛选")
                .accessibilityIdentifier("search.filter")
                .平台匹配转场源(id: "SearchFilterSheet", in: namespace)
            }

            if usesExplicitSearchToolbarItem, #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .平台主操作)

                DefaultToolbarItem(
                    kind: .search,
                    placement: .平台主操作
                )
            }

        }
        .平台全屏覆盖(isPresented: $isパーパルPresented) {
            パーパル页面(isPresented: $isパーパルPresented)
                .平台缩放转场(sourceID: "パーパル页面", in: namespace)
        }
        .sheet(item: $filterPresentationScope) { scope in
            NavigationStack {
                搜索筛选页面(
                    scope: scope,
                    visualNovelFilters: $draftFilters,
                    extendedFilters: $draftExtendedFilters
                ) {
                    if scope == .visualNovel {
                        filters = draftFilters
                    } else {
                        applyDraftExtendedFilters(for: scope)
                    }
                }
            }
            .平台缩放转场(sourceID: "SearchFilterSheet", in: namespace)
            .平台近全屏弹窗()
        }
        .sheet(item: $libraryEditorTarget) { target in
            资料库编辑页面(
                vnID: target.work.id,
                title: libraryDisplayTitle(for: target.work),
                token: auth.token,
                currentItem: target.currentItem,
                releases: [],
                loadsReleasesOnAppear: true,
                initialReleaseID: target.initialReleaseID
            ) {
                await refreshLibraryItem(for: target.work.id)
            }
            .平台近全屏弹窗(dragIndicator: .visible)
        }
        .alert("需要登录", isPresented: $showLoginRequiredAlert) {
            Button("好") { }
        } message: {
            Text("请先在资料库页面登录VNDB账户。")
        }
        .alert(
            "资料库操作失败",
            isPresented: Binding(
                get: { libraryActionError != nil },
                set: { if !$0 { libraryActionError = nil } }
            )
        ) {
            Button("好") { libraryActionError = nil }
        } message: {
            Text(verbatim: libraryActionError ?? "")
        }
        .alert(item: $libraryDeleteTarget) { target in
            Alert(
                title: Text("从资料库删除"),
                message: Text(
                    verbatim: libraryDeleteConfirmationMessage(
                        for: target.work
                    )
                ),
                primaryButton: .destructive(Text("从资料库删除")) {
                    deleteFromLibrary(target.work)
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .overlay(alignment: .bottom) {
            模糊解除提示(
                isPresented: blurRevealConfirmation.isPromptVisible
            )
            .padding(.bottom, 18)
        }
    }

    @ViewBuilder
    private var searchRootContent: some View {
        let content = 平台滚动页面 {
            if isScopeTransitioning {
                searchLoadingSection(for: displayedScope)
            } else {
                resultContent(for: displayedScope)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .平台分组列表样式()
        .overlay {
            searchEmptyContentUnavailableView
        }
        .allowsHitTesting(!isScopeTransitioning)

        if showsTopScopePicker {
            content
        } else {
            searchScopeLayout(content)
        }
    }

    @ViewBuilder
    private var searchEmptyContentUnavailableView: some View {
        if isScopeTransitioning {
            EmptyView()
        } else if displayedScope.is扩展搜索范围 {
            switch extendedViewModel(for: displayedScope).当前状态 {
            case .empty:
                ContentUnavailableView.search
            default:
                EmptyView()
            }
        } else {
            switch viewModel.当前页面状态(for: displayedScope) {
            case .empty:
                ContentUnavailableView.search
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var topSearchScopePicker: some View {
        if usesIPadSearchLayout {
            iPadSearchScopePicker
        } else {
            搜索范围切换栏(
                selection: visualSelectedScope,
                onSelect: { startScopeTransition(to: $0) }
            )
            .equatable()
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
    }

    private var iPadSearchScopePicker: some View {
        HStack(spacing: 0) {
            Picker(selection: displayedScopeBinding) {
                ForEach(搜索范围.allCases) { scope in
                    Label {
                        Text(verbatim: scope.localizedTitle)
                    } icon: {
                        Image(systemName: scope.systemImage)
                    }
                    .labelStyle(.titleAndIcon)
                    .tag(scope)
                }
            } label: {
                Label {
                    Text(verbatim: visualSelectedScope.localizedTitle)
                } icon: {
                    Image(systemName: visualSelectedScope.systemImage)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
        }
        .padding(6)
        .液态玻璃(.regular, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("搜索范围")
        .accessibilityIdentifier("search.scope")
    }

    @ViewBuilder
    private func searchScopeLayout<Content: View>(_ content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                搜索范围切换栏(
                    selection: visualSelectedScope,
                    onSelect: { startScopeTransition(to: $0) }
                )
                .equatable()
                .offset(y: keyboardSearchFieldClearance == 0 ? 6 : 0)

                Color.clear
                    .frame(height: keyboardSearchFieldClearance)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    private var 当前筛选为空: Bool {
        selectedScope == .visualNovel
            ? filters.isEmpty
            : currentExtendedFilters.isEmpty
    }

    private var hasSearchText: Bool {
        hasSearchTextState
    }

    private func updateSearchText(_ newValue: String) {
        guard searchInput.text != newValue else { return }
        searchInput.text = newValue

        let previouslyHadText = hasSearchTextState
        let hasText = !newValue.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        if hasSearchTextState != hasText {
            hasSearchTextState = hasText
        }

        let activeSortChanged: Bool
        if hasText, !previouslyHadText {
            activeSortChanged = useRelevanceSortsForSearch()
        } else if !hasText, previouslyHadText {
            activeSortChanged = resetRelevanceSortsForEmptySearch()
        } else {
            activeSortChanged = false
        }
        if !activeSortChanged {
            submitSearch()
        }
    }

    @discardableResult
    private func useRelevanceSortsForSearch() -> Bool {
        let activeSortWasRelevance = switch selectedScope {
        case .visualNovel: selectedSort.sort == .relevance
        case .character: characterSort.sort == .relevance
        case .release: releaseSort.sort == .relevance
        case .staff: staffSort.sort == .relevance
        case .producer: producerSort.sort == .relevance
        }

        selectedSort = .init(sort: .relevance)
        characterSort = .init(sort: .relevance)
        releaseSort = .init(sort: .relevance)
        staffSort = .init(sort: .relevance)
        producerSort = .init(sort: .relevance)
        return !activeSortWasRelevance
    }

    @discardableResult
    private func resetRelevanceSortsForEmptySearch() -> Bool {
        let activeSortWasRelevance = switch selectedScope {
        case .visualNovel: selectedSort.sort == .relevance
        case .character: characterSort.sort == .relevance
        case .release: releaseSort.sort == .relevance
        case .staff: staffSort.sort == .relevance
        case .producer: producerSort.sort == .relevance
        }

        if selectedSort.sort == .relevance {
            selectedSort = .init(sort: .released)
        }
        if characterSort.sort == .relevance {
            characterSort = .init(sort: .added)
        }
        if releaseSort.sort == .relevance {
            releaseSort = .init(sort: .released)
        }
        if staffSort.sort == .relevance {
            staffSort = .init(sort: .added)
        }
        if producerSort.sort == .relevance {
            producerSort = .init(sort: .added)
        }
        return activeSortWasRelevance
    }

    @ViewBuilder
    private func resultContent(for scope: 搜索范围) -> some View {
        if scope.is扩展搜索范围 {
            extendedResultContent(for: scope)
        } else {
            switch viewModel.当前页面状态(for: scope) {
            case .idle:
                EmptyView()
            case .loading:
                searchLoadingSection(for: scope)
            case .empty:
                EmptyView()
            case let .failed(message):
                探索加载失败页面(message: message) {
                    viewModel.重试(范围: scope)
                }
            case .loaded:
                if scope == .visualNovel {
                    if 可见视觉小说结果.isEmpty {
                        受限隐藏空状态(范围: .visualNovel)
                    } else {
                        visualNovelResults
                    }
                } else {
                    if 可见角色结果.isEmpty {
                        受限隐藏空状态(范围: .character)
                    } else {
                        characterResults
                    }
                }
                paginationFooter(for: scope)
            }
        }
    }

    @ViewBuilder
    private func extendedResultContent(for scope: 搜索范围) -> some View {
        let model = extendedViewModel(for: scope)
        switch model.当前状态 {
        case .idle:
            EmptyView()
        case .loading:
            searchLoadingSection(for: scope)
        case .empty:
            EmptyView()
        case let .failed(message):
            探索加载失败页面(message: message) {
                model.重试()
            }
        case .loaded:
            switch scope {
            case .release: releaseResults
            case .staff: staffResults
            case .producer: producerResults
            default: EmptyView()
            }
            extendedPaginationFooter(for: scope)
        }
    }

    @ViewBuilder
    private func 受限隐藏空状态(范围: 搜索范围) -> some View {
        Section {
            if viewModel.是否还有更多(for: 范围) {
                ForEach(0..<2, id: \.self) { _ in
                    searchLoadingRow(for: 范围)
                }
                .accessibilityHidden(true)
                .onAppear {
                    viewModel.加载下一页(范围: 范围)
                }
            } else {
                平台内容不可用视图(
                    "内容已隐藏",
                    systemImage: "eye.slash",
                    description: Text("符合条件的结果已按安全限制隐藏。")
                )
            }
        }
    }

    private func searchLoadingSection(for scope: 搜索范围) -> some View {
        Section {
            ForEach(0..<5, id: \.self) { _ in
                searchLoadingRow(for: scope)
            }
            .accessibilityHidden(true)
        } header: {
            HStack(spacing: 8) {
                平台持续加载指示器()
                Text("加载中…")
            }
            .textCase(nil)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func searchLoadingRow(for scope: 搜索范围) -> some View {
        if scope == .visualNovel {
            搜索视觉小说加载占位行()
        } else if scope == .character {
            搜索角色加载占位行()
        } else {
            搜索扩展加载占位行()
        }
    }

    private var visualNovelResults: some View {
        Section {
            ForEach(
                Array(可见视觉小说结果.enumerated()),
                id: \.element.id
            ) { index, item in
                NavigationLink {
                    视觉小说详情(
                        vnID: item.id,
                        auth: auth,
                        initialTitle: item.title,
                        initialTitles: item.titles,
                        initialImageURL: item.image?.url,
                        initialImageSexual: item.image?.sexual,
                        initialImageViolence: item.image?.violence,
                        initialImageDimensions: item.image?.dims
                    )
                } label: {
                    visualNovelRow(item)
                }
                .onAppear {
                    guard viewModel.是否还有更多(for: .visualNovel),
                          index >= max(
                        可见视觉小说结果.count - 平台列表分页.预取余量,
                        0
                    ) else { return }
                    viewModel.加载下一页(范围: .visualNovel)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    visualNovelLibraryActionButton(for: item)
                }
                .contextMenu {
                    visualNovelContextMenu(for: item)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if libraryItemsByID[item.id] != nil {
                        librarySwipeRemoveButton(
                            for: 搜索资料库作品(item),
                            title: "删除"
                        )
                    }
                }
            }
        }
    }

    private var characterResults: some View {
        Section {
            ForEach(
                Array(可见角色结果.enumerated()),
                id: \.element.id
            ) { index, item in
                characterResultLink(item)
                .onAppear {
                    guard viewModel.是否还有更多(for: .character),
                          index >= max(
                        可见角色结果.count - 平台列表分页.预取余量,
                        0
                    ) else { return }
                    viewModel.加载下一页(范围: .character)
                }
                .contextMenu {
                    shareContextMenu(for: .character, id: item.id)
                }
            }
        }
    }

    private var releaseResults: some View {
        Section {
            ForEach(Array(releaseSearchViewModel.发行版本结果.enumerated()), id: \.element.id) { index, item in
                let works = releaseWorks(for: item)
                NavigationLink {
                    探索发行版本详情(item: item, auth: auth)
                } label: {
                    探索发行版本行(
                        item: item,
                        confirmation: blurRevealConfirmation,
                        verticalAlignment: .center
                    )
                }
                .onAppear {
                    if index >= max(releaseSearchViewModel.发行版本结果.count - 平台列表分页.预取余量, 0) {
                        releaseSearchViewModel.加载下一页()
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if let work = works.first {
                        releaseLibraryActionButton(
                            for: work,
                            releaseID: item.id
                        )
                    }
                }
                .contextMenu {
                    releaseContextMenu(for: item, works: works)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if let work = works.first,
                       libraryItemsByID[work.id] != nil {
                        librarySwipeRemoveButton(
                            for: work,
                            title: "删除"
                        )
                    }
                }
            }
        }
    }

    private var staffResults: some View {
        Section {
            ForEach(Array(staffSearchViewModel.制作人员结果.enumerated()), id: \.element.id) { index, item in
                NavigationLink {
                    探索制作人员详情(item: item)
                } label: {
                    searchStaffRow(item)
                }
                .onAppear {
                    if index >= max(staffSearchViewModel.制作人员结果.count - 平台列表分页.预取余量, 0) {
                        staffSearchViewModel.加载下一页()
                    }
                }
                .contextMenu {
                    shareContextMenu(for: .staff, id: item.id)
                }
            }
        }
    }

    private var producerResults: some View {
        Section {
            ForEach(Array(producerSearchViewModel.会社结果.enumerated()), id: \.element.id) { index, item in
                NavigationLink {
                    探索会社详情(item: item)
                } label: {
                    searchProducerRow(item)
                }
                .onAppear {
                    if index >= max(producerSearchViewModel.会社结果.count - 平台列表分页.预取余量, 0) {
                        producerSearchViewModel.加载下一页()
                    }
                }
                .contextMenu {
                    shareContextMenu(for: .producer, id: item.id)
                }
            }
        }
    }

    @ViewBuilder
    private func extendedPaginationFooter(for scope: 搜索范围) -> some View {
        let model = extendedViewModel(for: scope)
        if model.正在加载下一页 {
            Section {
                ForEach(0..<2, id: \.self) { _ in
                    searchLoadingRow(for: scope)
                }
            } header: {
                HStack(spacing: 8) {
                    平台持续加载指示器()
                    Text("加载中…")
                }
                .textCase(nil)
                .id("extended-search-pagination-\(model.分页加载代次)")
            }
        } else if let error = model.下一页错误 {
            Section {
                探索加载失败页面(message: error) {
                    model.加载下一页()
                }
            }
        }
    }

    @ViewBuilder
    private func characterResultLink(_ item: 角色搜索结果) -> some View {
        if item.id == 内容安全高级设置解锁入口.角色ID,
           内容安全高级设置解锁入口.是触发搜索(searchText) {
            Button {
                unlockCharacterDestination = item
            } label: {
                characterRow(item)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                角色详情(
                    characterID: item.id,
                    auth: auth,
                    initialName: item.name,
                    initialOriginal: item.original,
                    initialAliases: item.aliases,
                    initialImage: item.image
                )
            } label: {
                characterRow(item)
            }
        }
    }

    @ViewBuilder
    private func paginationFooter(for scope: 搜索范围) -> some View {
        if viewModel.是否正在加载下一页(for: scope) {
            Section {
                ForEach(0..<2, id: \.self) { _ in
                    searchLoadingRow(for: scope)
                }
                .accessibilityHidden(true)
            } header: {
                HStack(spacing: 8) {
                    平台持续加载指示器()
                    Text("加载中…")
                }
                .textCase(nil)
                .accessibilityElement(children: .combine)
                .id("search-pagination-\(scope)-\(viewModel.分页加载代次)")
            }
            .id("search-pagination-section-\(scope)-\(viewModel.分页加载代次)")
        } else if let error = viewModel.加载下一页错误(for: scope) {
            Section {
                探索加载失败页面(message: error) {
                    viewModel.加载下一页(范围: scope)
                }
            }
        }
    }

    private func visualNovelRow(_ item: 视觉小说搜索结果) -> some View {
        let main = visualNovelDisplayTitle(for: item)
        let subtitle = 标题工具.获取副标题(
            titles: item.titles,
            defaultTitle: item.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            副标题设置: subTitleLang,
            允许非官方: allowUnofficialTitles
        )

        return HStack(spacing: 12) {
            resultImage(
                id: "vn-\(item.id)",
                url: item.image?.url ?? item.image?.thumbnail,
                sexual: item.image?.sexual,
                violence: item.image?.violence
            )

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                多语言列表文本(
                    main,
                    层级: .主标题,
                    系统字体粗细: main.languageCode
                        == 标题语言.chinese.langCode ? .medium : nil
                )
                    .lineLimit(2)

                if let subtitle {
                    多语言列表文本(subtitle, 层级: .副标题)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if let developers = item.developers, !developers.isEmpty {
                    Text(
                        verbatim: ListFormatter.localizedString(
                            byJoining: developers.prefix(2).map(\.name)
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let released = item.released {
                        metadata(icon: "calendar", text: released)
                    }
                    视觉小说统一评分标签(
                        vndbID: item.id,
                        vndbRating: item.rating,
                        vndbVoteCount: item.votecount
                    )
                    if 评分数据来源.current == .vndb,
                       let votes = item.votecount {
                        metadata(icon: "person.2", text: votes.formatted())
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                let availability = availabilityText(item)
                if !availability.isEmpty {
                    Text(verbatim: availability)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func visualNovelDisplayTitle(
        for item: 视觉小说搜索结果
    ) -> 标题工具.标题结果 {
        libraryDisplayTitle(for: 搜索资料库作品(item))
    }

    private func libraryDisplayTitle(
        for work: 搜索资料库作品
    ) -> 标题工具.标题结果 {
        标题工具.获取主标题(
            titles: work.titles,
            defaultTitle: work.title,
            偏好: preferredTitleLang,
            回退: fallbackTitleLang,
            允许非官方: allowUnofficialTitles
        )
    }

    @ViewBuilder
    private func visualNovelLibraryActionButton(
        for item: 视觉小说搜索结果
    ) -> some View {
        Button {
            performVisualNovelLibraryAction(for: item)
        } label: {
            Label(
                libraryActionTitle(for: item),
                systemImage: libraryItemsByID[item.id] == nil
                    ? "plus"
                : "square.and.pencil"
            )
        }
        .tint(.blue)
        .disabled(isPerformingLibraryAction)
    }

    @ViewBuilder
    private func visualNovelContextMenu(
        for item: 视觉小说搜索结果
    ) -> some View {
        visualNovelContextMenuLibraryActionButton(for: item)
        if !parentalControls.policy.blocksUntrustedExternalLinks,
           let url = shareURL(for: .visualNovel, id: item.id) {
            ShareLink(item: url) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        }
        if libraryItemsByID[item.id] != nil {
            Divider()
            visualNovelDeleteActionButton(for: item)
        }
    }

    private func visualNovelContextMenuLibraryActionButton(
        for item: 视觉小说搜索结果
    ) -> some View {
        Button {
            performVisualNovelLibraryAction(for: item)
        } label: {
            Label(
                libraryActionTitle(for: item),
                systemImage: libraryItemsByID[item.id] == nil
                    ? "plus"
                : "square.and.pencil"
            )
        }
        .disabled(isPerformingLibraryAction)
    }

    @ViewBuilder
    private func visualNovelDeleteActionButton(
        for item: 视觉小说搜索结果,
        title: String = "从资料库删除"
    ) -> some View {
        libraryDeleteActionButton(
            for: 搜索资料库作品(item),
            title: title
        )
    }

    private func libraryDeleteActionButton(
        for work: 搜索资料库作品,
        title: String = "从资料库删除"
    ) -> some View {
        Button(role: .destructive) {
            requestLibraryDeletion(for: work)
        } label: {
            Label(title, systemImage: "trash")
        }
        .disabled(isPerformingLibraryAction)
    }

    private func librarySwipeRemoveButton(
        for work: 搜索资料库作品,
        title: String
    ) -> some View {
        Button {
            requestLibraryDeletion(for: work)
        } label: {
            Label(title, systemImage: "trash")
        }
        .tint(.red)
        .disabled(isPerformingLibraryAction)
    }

    private func releaseWorks(
        for item: 探索发行版本
    ) -> [搜索资料库作品] {
        (item.visualNovels ?? []).map(搜索资料库作品.init)
    }

    private func releaseLibraryActionButton(
        for work: 搜索资料库作品,
        releaseID: String
    ) -> some View {
        Button {
            performLibraryAction(
                for: work,
                selectedReleaseID: releaseID
            )
        } label: {
            Label(
                libraryActionTitle(for: work.id),
                systemImage: libraryItemsByID[work.id] == nil
                    ? "plus"
                    : "square.and.pencil"
            )
        }
        .tint(.blue)
        .disabled(isPerformingLibraryAction)
    }

    @ViewBuilder
    private func releaseContextMenu(
        for item: 探索发行版本,
        works: [搜索资料库作品]
    ) -> some View {
        if !parentalControls.policy.blocksUntrustedExternalLinks,
           let url = shareURL(for: .release, id: item.id) {
            ShareLink(item: url) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        }

        if !works.isEmpty {
            Divider()

            if works.count == 1, let work = works.first {
                releaseLibraryActionButton(
                    for: work,
                    releaseID: item.id
                )
            } else {
                Menu {
                    ForEach(works) { work in
                        Button {
                            performLibraryAction(
                                for: work,
                                selectedReleaseID: item.id
                            )
                        } label: {
                            Label(
                                libraryDisplayTitle(for: work).text,
                                systemImage: libraryItemsByID[work.id] == nil
                                    ? "plus"
                                    : "square.and.pencil"
                            )
                        }
                        .disabled(isPerformingLibraryAction)
                    }
                } label: {
                    Label("添加到资料库", systemImage: "plus")
                }
            }

            if let work = works.first,
               libraryItemsByID[work.id] != nil {
                libraryDeleteActionButton(for: work)
            }
        }
    }

    @ViewBuilder
    private func shareContextMenu(
        for scope: 搜索范围,
        id: String
    ) -> some View {
        if !parentalControls.policy.blocksUntrustedExternalLinks,
           let url = shareURL(for: scope, id: id) {
            ShareLink(item: url) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func shareURL(for scope: 搜索范围, id: String) -> URL? {
        guard !id.isEmpty else { return nil }
        guard scope == .visualNovel
            || scope == .character
            || scope == .release
            || scope == .staff
            || scope == .producer else { return nil }
        return URL(string: "https://vndb.org/\(id)")
    }

    private func libraryActionTitle(for item: 视觉小说搜索结果) -> String {
        libraryActionTitle(for: item.id)
    }

    private func libraryActionTitle(for vnID: String) -> String {
        libraryItemsByID[vnID] == nil
            ? String(localized: "添加到资料库")
            : String(localized: "编辑")
    }

    private func performVisualNovelLibraryAction(
        for item: 视觉小说搜索结果
    ) {
        performLibraryAction(for: 搜索资料库作品(item))
    }

    private func performLibraryAction(
        for work: 搜索资料库作品,
        selectedReleaseID: String? = nil
    ) {
        guard !isPerformingLibraryAction else { return }
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
            showLoginRequiredAlert = true
            return
        }

        isPerformingLibraryAction = true
        libraryActionError = nil
        Task { @MainActor in
            defer { isPerformingLibraryAction = false }

            do {
                let currentItem = try await resolveLibraryItem(for: work.id)
                if let currentItem {
                    libraryItemsByID[work.id] = currentItem
                    libraryEditorTarget = 搜索资料库编辑目标(
                        work: work,
                        currentItem: currentItem,
                        initialReleaseID:
                            currentItem.releases?.first?.id == nil
                                ? selectedReleaseID
                                : nil
                    )
                    return
                }

                try await VNDB服务.shared.updateUserStatus(
                    token: auth.token,
                    vnID: work.id,
                    status: .planning,
                    existingLabels: []
                )
                if let selectedReleaseID {
                    try await VNDB服务.shared.updateReleaseSelection(
                        token: auth.token,
                        existingReleaseIDs: [],
                        selectedReleaseID: selectedReleaseID
                    )
                }
                libraryMutationGeneration += 1
                libraryItemsByID[work.id] = provisionalLibraryItem(for: work)
                资料库加入时间记录.record(
                    userID: auth.userID,
                    vnID: work.id
                )
                isPerformingLibraryAction = false
                finishAddingToLibrary(work)
            } catch is CancellationError {
                return
            } catch {
                libraryActionError = error.localizedDescription
            }
        }
    }

    private func provisionalLibraryItem(
        for work: 搜索资料库作品
    ) -> 用户列表项目 {
        用户列表项目(
            id: work.id,
            added: Int(Date.now.timeIntervalSince1970),
            vote: nil,
            started: nil,
            finished: nil,
            notes: nil,
            labels: [
                .init(
                    id: 用户列表筛选.planning.labelID ?? 5,
                    label: 用户列表筛选.planning.localizedString
                )
            ],
            releases: nil,
            vn: .init(
                title: work.title,
                titles: work.titles,
                image: work.image,
                rating: work.rating,
                votecount: work.voteCount,
                released: work.released
            )
        )
    }

    private func finishAddingToLibrary(
        _ work: 搜索资料库作品
    ) {
        Task { @MainActor in
            if UserDefaults.standard.bool(
                forKey: Bangumi账户.同步设置键
            ), bangumiAccount.isLoggedIn {
                do {
                    try await bangumiAccount.synchronize(
                        vndbID: work.id,
                        status: .planning,
                        rating: nil
                    )
                } catch is CancellationError {
                    return
                } catch {
                    libraryActionError = error.localizedDescription
                }
            }

            await refreshLibraryItem(
                for: work.id,
                preservesExistingOnMissing: true
            )
        }
    }

    private func requestLibraryDeletion(
        for work: 搜索资料库作品
    ) {
        guard libraryItemsByID[work.id] != nil else { return }
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
            showLoginRequiredAlert = true
            return
        }
        libraryDeleteTarget = 搜索资料库删除目标(work: work)
    }

    private func libraryDeleteConfirmationMessage(
        for work: 搜索资料库作品
    ) -> String {
        let title = libraryDisplayTitle(for: work)
        return String(
            format: String(localized: "确定要从资料库删除“%@”吗？"),
            title.text
        )
    }

    private func deleteFromLibrary(_ work: 搜索资料库作品) {
        guard !isPerformingLibraryAction else { return }
        guard !auth.token.isEmpty, !auth.userID.isEmpty else {
            libraryDeleteTarget = nil
            showLoginRequiredAlert = true
            return
        }

        libraryDeleteTarget = nil
        isPerformingLibraryAction = true
        libraryActionError = nil
        Task { @MainActor in
            defer { isPerformingLibraryAction = false }
            do {
                try await VNDB服务.shared.deleteUserListEntry(
                    token: auth.token,
                    vnID: work.id
                )
                libraryMutationGeneration += 1
                var transaction = Transaction()
                transaction.animation = nil
                _ = withTransaction(transaction) {
                    libraryItemsByID.removeValue(forKey: work.id)
                }
            } catch is CancellationError {
                return
            } catch {
                libraryActionError = error.localizedDescription
            }
        }
    }

    private func resolveLibraryItem(for vnID: String) async throws -> 用户列表项目? {
        if let cached = libraryItemsByID[vnID] {
            return cached
        }
        if libraryListLoadedForUserID == auth.userID {
            return nil
        }
        return try await VNDB服务.shared.fetchUserListItem(
            token: auth.token,
            userID: auth.userID,
            vnID: vnID
        )
    }

    private func loadLibraryItems() async {
        let token = auth.token
        let userID = auth.userID
        let mutationGeneration = libraryMutationGeneration
        guard !token.isEmpty, !userID.isEmpty else {
            libraryItemsByID = [:]
            libraryListLoadedForUserID = nil
            return
        }

        libraryItemsByID = [:]
        libraryListLoadedForUserID = nil
        do {
            let items = try await VNDB服务.shared.fetchAllUserList(
                token: token,
                userID: userID
            )
            guard token == auth.token,
                  userID == auth.userID,
                  mutationGeneration == libraryMutationGeneration else {
                return
            }
            libraryItemsByID = Dictionary(
                uniqueKeysWithValues: items.map { ($0.id, $0) }
            )
            libraryListLoadedForUserID = userID
        } catch is CancellationError {
            return
        } catch {
        }
    }

    private func refreshLibraryItem(
        for vnID: String,
        preservesExistingOnMissing: Bool = false
    ) async {
        guard !auth.token.isEmpty, !auth.userID.isEmpty else { return }
        do {
            let item = try await VNDB服务.shared.fetchUserListItem(
                token: auth.token,
                userID: auth.userID,
                vnID: vnID,
                forceRefresh: true
            )
            if let item {
                libraryItemsByID[vnID] = item
            } else if !preservesExistingOnMissing {
                libraryItemsByID.removeValue(forKey: vnID)
            }
        } catch {
            return
        }
    }

    private func characterRow(_ item: 角色搜索结果) -> some View {
        HStack(spacing: 12) {
            resultImage(
                id: "character-\(item.id)",
                url: item.image?.url,
                sexual: item.image?.sexual,
                violence: item.image?.violence
            )

            VStack(alignment: .leading, spacing: 6) {
                多语言列表文本(
                    文本: 人物名称工具.显示名称(
                        name: item.name,
                        original: item.original,
                        偏好: staffNameLang
                    ),
                    isJapanese: staffNameLang == .original,
                    层级: .主标题,
                    语言来源已知: false,
                    空格视为日语: true
                )
                .lineLimit(2)
            }
        }
        .contentShape(Rectangle())
    }

    private func searchStaffRow(_ item: 探索制作人员) -> some View {
        searchNamedEntityRow(
            title: 人物名称工具.显示名称(
                name: item.name,
                original: item.original,
                偏好: staffNameLang
            ),
            subtitle: 人物名称工具.备用名称(
                name: item.name,
                original: item.original,
                偏好: staffNameLang
            ),
            language: item.language,
            placeholder: "person.text.rectangle"
        )
    }

    private func searchProducerRow(_ item: 探索会社) -> some View {
        let placeholder = switch item.type {
        case "in": "person"
        case "ng": "person.3"
        default: "building.2"
        }
        return searchNamedEntityRow(
            title: 人物名称工具.显示名称(
                name: item.name,
                original: item.original,
                偏好: staffNameLang
            ),
            subtitle: 人物名称工具.备用名称(
                name: item.name,
                original: item.original,
                偏好: staffNameLang
            ),
            language: item.language,
            placeholder: placeholder
        )
    }

    private func searchNamedEntityRow(
        title: String,
        subtitle: String?,
        language: String?,
        placeholder: String
    ) -> some View {
        HStack(spacing: 12) {
            searchPlaceholderCover(systemImage: placeholder)

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                多语言列表文本(
                    文本: title,
                    isJapanese: staffNameLang == .original,
                    层级: .主标题,
                    语言来源已知: false,
                    空格视为日语: true
                )
                .lineLimit(2)

                if let subtitle {
                    多语言列表文本(
                        文本: subtitle,
                        isJapanese: staffNameLang != .original,
                        层级: .副标题,
                        语言来源已知: false,
                        空格视为日语: true
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                if let language {
                    metadata(
                        icon: "character.bubble",
                        text: VNDB显示工具.语言名称(language)
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func searchPlaceholderCover(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)
            .background(Color.secondary.opacity(0.1))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: 列表封面布局.圆角(
                        horizontalSizeClass: horizontalSizeClass
                    ),
                    style: .continuous
                )
            )
    }

    private func resultImage(
        id: String,
        url: String?,
        sexual: Double?,
        violence: Double?
    ) -> some View {
        let width = 列表封面布局.宽度
        let height = 列表封面布局.高度
        let cornerRadius = 列表封面布局.圆角(
            horizontalSizeClass: horizontalSizeClass
        )
        let needsRestriction = shouldBlurImage(
            sexual: sexual,
            violence: violence
        )
        let isRevealed = revealedImageIDs.contains(id)
        let isRestricted = needsRestriction && (
            contentRestrictionMethod == .hidden || !isRevealed
        )

        return ZStack {
            CachedAsyncImage(url: URL(string: url ?? ""), contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .应用不安全内容限制(
                    isRestricted,
                    method: contentRestrictionMethod,
                    blurRadius: 16
                )

            if isRestricted,
               contentRestrictionMethod == .blurred,
               内容安全限制判定.图片允许手动解除模糊(
                    sexual: sexual,
                    enabled: contentFilterEnabled,
                    sexualThreshold: sexualThreshold,
                    mode: filterMode
               ) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        blurRevealConfirmation.request(id: id) {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                let _ = revealedImageIDs.insert(id)
                            }
                        }
                    }
                    .accessibilityLabel("轻触两次以解除模糊")
            }
        }
        .frame(width: width, height: height)
        .background(Color.secondary.opacity(0.1))
        .clipShape(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    private func metadata(icon: String, text: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption2)
            Text(verbatim: text)
        }
    }

    private func availabilityText(_ item: 视觉小说搜索结果) -> String {
        let languages = ListFormatter.localizedString(byJoining:
            (item.languages ?? []).prefix(3)
            .map { VNDB显示工具.语言名称($0) }
        )
        let platforms = ListFormatter.localizedString(byJoining:
            (item.platforms ?? []).prefix(2)
            .map { VNDB显示工具.平台名称($0) }
        )
        return [languages, platforms]
            .filter { !$0.isEmpty }
            .joined(separator: "·")
    }

    private var 可见视觉小说结果: [视觉小说搜索结果] {
        guard contentFilterEnabled, contentRestrictionMethod == .hidden else {
            return viewModel.视觉小说结果
        }
        return viewModel.视觉小说结果.filter {
            !内容安全限制判定.视觉小说需要限制(
                $0,
                enabled: contentFilterEnabled,
                sexualThreshold: sexualThreshold,
                violenceThreshold: violenceThreshold,
                mode: filterMode
            )
        }
    }

    private var 可见角色结果: [角色搜索结果] {
        guard contentFilterEnabled, contentRestrictionMethod == .hidden else {
            return viewModel.角色结果
        }
        return viewModel.角色结果.filter {
            !shouldBlurImage(
                sexual: $0.image?.sexual,
                violence: $0.image?.violence
            )
        }
    }

    private func shouldBlurImage(
        sexual: Double?,
        violence: Double?
    ) -> Bool {
        内容安全限制判定.图片需要限制(
            sexual: sexual,
            violence: violence,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
    }

    private func startScopeTransition(
        to scope: 搜索范围
    ) {
        guard scope != visualSelectedScope else { return }

        scopeTransitionGeneration += 1
        resultCommitGate.延迟提交(纳秒: scopeTransitionDelayNanoseconds)

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            scopeTransitionTarget = scope
            displayedScope = scope
            isScopeTransitioning = true
            if selectedScope != scope {
                selectedScopeBinding.wrappedValue = scope
            }
        }
        revealedImageIDs.removeAll()
        viewModel.切换范围(scope)
        submitSearch(for: scope, immediately: true)
    }

    private func submitSearch(immediately: Bool = false) {
        submitSearch(for: selectedScope, immediately: immediately)
    }

    private func submitSearch(
        for scope: 搜索范围,
        immediately: Bool = false
    ) {
        switch scope {
        case .visualNovel:
            viewModel.更新搜索(
                关键词: searchText, 范围: .visualNovel, 筛选: filters,
                排序: selectedSort.sort, 降序: selectedSort.isDescending,
                允许空搜索: true, 立即: immediately
            )
        case .character:
            viewModel.更新搜索(
                关键词: searchText, 范围: .character, 筛选: filters,
                排序: selectedSort.sort, 扩展筛选: characterFilters,
                扩展排序: characterSort.sort,
                扩展降序: characterSort.isDescending,
                允许空搜索: true, 立即: immediately
            )
        case .release:
            releaseSearchViewModel.更新搜索(
                关键词: searchText, 范围: .release, 筛选: releaseFilters,
                排序: releaseSort.sort, 降序: releaseSort.isDescending,
                立即: immediately
            )
        case .staff:
            staffSearchViewModel.更新搜索(
                关键词: searchText, 范围: .staff, 筛选: staffFilters,
                排序: staffSort.sort, 降序: staffSort.isDescending,
                立即: immediately
            )
        case .producer:
            producerSearchViewModel.更新搜索(
                关键词: searchText, 范围: .producer, 筛选: producerFilters,
                排序: producerSort.sort, 降序: producerSort.isDescending,
                立即: immediately
            )
        }
    }

    private func syncExternalSearchTextIfNeeded() {
        guard let externalSearchText,
              externalSearchText.wrappedValue != searchText else {
            return
        }
        externalSearchText.wrappedValue = searchText
    }

    private func presentFilters() {
        draftFilters = filters
        draftExtendedFilters = currentExtendedFilters
        filterPresentationScope = selectedScope
    }

    private func filters(for scope: 搜索范围) -> 搜索扩展筛选 {
        switch scope {
        case .character: return characterFilters
        case .release: return releaseFilters
        case .staff: return staffFilters
        case .producer: return producerFilters
        case .visualNovel: return .init()
        }
    }

    private func applyDraftExtendedFilters(for scope: 搜索范围) {
        switch scope {
        case .character: characterFilters = draftExtendedFilters
        case .release: releaseFilters = draftExtendedFilters
        case .staff: staffFilters = draftExtendedFilters
        case .producer: producerFilters = draftExtendedFilters
        case .visualNovel: break
        }
    }

}

private struct iPad搜索工具栏项配置: ViewModifier {
    let usesExplicitSearchItem: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesExplicitSearchItem, #available(iOS 26.0, *) {
            content.toolbar(removing: .search)
        } else {
            content
        }
    }
}

private struct 搜索提交处理器: ViewModifier {
    @Environment(\.dismissSearch) private var dismissSearch

    let submit: () -> Void

    func body(content: Content) -> some View {
        content.onSubmit(of: .search) {
            submit()
            dismissSearch()
        }
    }
}

private struct 搜索范围切换栏: View, Equatable {
    let selection: 搜索范围
    let onSelect: (搜索范围) -> Void

    @State private var visualSelection: 搜索范围

    @AppStorage(沉浸详情外观.设置键)
    private var 已存沉浸详情外观: 沉浸详情外观 = .clear
    private var liquidGlassAppearance: 沉浸详情外观 {
        已存沉浸详情外观.平台生效值
    }

    init(
        selection: 搜索范围,
        onSelect: @escaping (搜索范围) -> Void
    ) {
        self.selection = selection
        self.onSelect = onSelect
        _visualSelection = State(initialValue: selection)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selection == rhs.selection
    }

    var body: some View {
        Group {
            ViewThatFits(in: .horizontal) {
                scopeButtons
                    .fixedSize(horizontal: true, vertical: false)

                ScrollView(.horizontal) {
                    scopeButtons
                }
                .平台横向书架()
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollClipDisabled()
                .padding(.vertical, 8)
            }
        }
        .modifier(
            搜索范围玻璃容器Modifier(
                enabled: liquidGlassAppearance != .reduced
            )
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selection) { _, newSelection in
            visualSelection = newSelection
        }
    }

    private var scopeButtons: some View {
        HStack(spacing: 10) {
            ForEach(搜索范围.allCases) { scope in
                scopeButton(scope)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func scopeButton(_ scope: 搜索范围) -> some View {
        let isSelected = visualSelection == scope

        return Label {
            Text(verbatim: scope.localizedTitle)
                .lineLimit(1)
        } icon: {
            Image(systemName: scope.systemImage)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .modifier(搜索范围玻璃按钮样式(isSelected: isSelected))
        .onTapGesture {
            visualSelection = scope
            onSelect(scope)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction {
            visualSelection = scope
            onSelect(scope)
        }
        .accessibilityIdentifier("search.scope.\(scope.rawValue)")
    }
}

private struct 搜索范围玻璃容器Modifier: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled, #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) { content }
        } else {
            content
        }
    }
}

private struct 搜索范围玻璃按钮样式: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background {
                Capsule()
                    .fill(isSelected ? Color.blue.opacity(0.72) : Color.clear)
            }
            .contentShape(Capsule())
            .液态玻璃(.regular.interactive(), in: Capsule())
    }
}

private struct 搜索排序菜单: View {
    @Binding var selection: 视觉小说搜索排序选择
    let hasSearchText: Bool

    var body: some View {
        Menu {
            Picker("排序依据", selection: sortBinding) {
                ForEach(视觉小说搜索排序.available(hasSearchText: hasSearchText)) { sort in
                    Label {
                        Text(verbatim: sort.localizedTitle)
                    } icon: {
                        Image(systemName: sort.symbolName)
                    }
                    .tag(sort)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("排序方向", selection: $selection.isDescending) {
                Label("升序", systemImage: "arrow.up")
                    .tag(false)
                Label("降序", systemImage: "arrow.down")
                    .tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("排序")
        .accessibilityValue(
            Text(
                verbatim: "\(selection.sort.localizedTitle)，\(directionTitle)"
            )
        )
    }

    private var directionTitle: String {
        selection.isDescending
            ? String(localized: "降序")
            : String(localized: "升序")
    }

    private var sortBinding: Binding<视觉小说搜索排序> {
        Binding(
            get: { selection.sort },
            set: { selection = .init(sort: $0) }
        )
    }
}

private struct 搜索扩展排序菜单: View {
    @Binding var selection: 搜索扩展排序选择
    let scope: 搜索范围
    let hasSearchText: Bool

    var body: some View {
        Menu {
            Picker("排序依据", selection: sortBinding) {
                ForEach(
                    搜索扩展排序.available(
                        for: scope,
                        hasSearchText: hasSearchText
                    )
                ) { sort in
                    Label {
                        Text(verbatim: sort.localizedTitle)
                    } icon: {
                        Image(systemName: sort.symbolName)
                    }
                    .tag(sort)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Picker("排序方向", selection: $selection.isDescending) {
                Label("升序", systemImage: "arrow.up").tag(false)
                Label("降序", systemImage: "arrow.down").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("排序")
        .accessibilityValue(
            Text(verbatim: "\(selection.sort.localizedTitle)，\(directionTitle)")
        )
    }

    private var sortBinding: Binding<搜索扩展排序> {
        Binding(
            get: { selection.sort },
            set: { selection = .init(sort: $0) }
        )
    }

    private var directionTitle: String {
        selection.isDescending
            ? String(localized: "降序")
            : String(localized: "升序")
    }
}

struct 评分范围滑块: View {
    private enum Thumb {
        case minimum
        case maximum
    }

    @Binding var value: ClosedRange<Int>
    @State private var activeThumb: Thumb?

    private let bounds = 10...100
    private let thumbHitSize: CGFloat = 44
    private let thumbSize: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(geometry.size.width - thumbHitSize, 1)
            let minimumX = xPosition(for: value.lowerBound, trackWidth: trackWidth)
            let maximumX = xPosition(for: value.upperBound, trackWidth: trackWidth)

            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: trackWidth, height: 4)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(maximumX - minimumX, 4), height: 4)
                    .position(
                        x: (minimumX + maximumX) / 2,
                        y: thumbHitSize / 2
                    )

                thumb(
                    label: String(localized: "最低评分"),
                    rating: value.lowerBound
                )
                .position(x: minimumX, y: thumbHitSize / 2)

                thumb(
                    label: String(localized: "最高评分"),
                    rating: value.upperBound
                )
                .position(x: maximumX, y: thumbHitSize / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                dragGesture(
                    minimumX: minimumX,
                    maximumX: maximumX,
                    trackWidth: trackWidth
                )
            )
        }
        .frame(height: thumbHitSize)
    }

    private func thumb(label: String, rating: Int) -> some View {
        Circle()
            .fill(Color.clear)
            .frame(width: thumbHitSize, height: thumbHitSize)
            .overlay {
                Circle()
                    .fill(.background)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        Circle()
                            .stroke(Color.accentColor, lineWidth: 2.5)
                    }
                    .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            }
            .contentShape(Circle())
            .accessibilityElement()
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(
                Text(verbatim: String(format: "%.1f", Double(rating) / 10))
            )
            .accessibilityAdjustableAction { direction in
                adjust(rating: rating, direction: direction, label: label)
            }
            .accessibilityIdentifier(
                label == String(localized: "最低评分")
                    ? "search.filter.rating.minimum"
                    : "search.filter.rating.maximum"
            )
    }

    private func xPosition(for rating: Int, trackWidth: CGFloat) -> CGFloat {
        let progress = CGFloat(rating - bounds.lowerBound)
            / CGFloat(bounds.upperBound - bounds.lowerBound)
        return thumbHitSize / 2 + progress * trackWidth
    }

    private func dragGesture(
        minimumX: CGFloat,
        maximumX: CGFloat,
        trackWidth: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if activeThumb == nil {
                    if value.lowerBound == value.upperBound {
                        if value.lowerBound == bounds.lowerBound {
                            activeThumb = .maximum
                        } else if value.upperBound == bounds.upperBound {
                            activeThumb = .minimum
                        } else {
                            activeThumb = gesture.startLocation.x < minimumX
                                ? .minimum
                                : .maximum
                        }
                    } else {
                        let minimumDistance = abs(
                            gesture.startLocation.x - minimumX
                        )
                        let maximumDistance = abs(
                            gesture.startLocation.x - maximumX
                        )
                        activeThumb = minimumDistance <= maximumDistance
                            ? .minimum
                            : .maximum
                    }
                }

                let progress = min(
                    max(
                        (gesture.location.x - thumbHitSize / 2) / trackWidth,
                        0
                    ),
                    1
                )
                let rating = bounds.lowerBound + Int(
                    (progress * CGFloat(bounds.upperBound - bounds.lowerBound))
                        .rounded()
                )

                switch activeThumb {
                case .minimum:
                    updateMinimum(rating)
                case .maximum:
                    updateMaximum(rating)
                case nil:
                    break
                }
            }
            .onEnded { _ in
                activeThumb = nil
            }
    }

    private func updateMinimum(_ rating: Int) {
        let minimum = min(
            max(rating, bounds.lowerBound),
            value.upperBound
        )
        value = minimum...value.upperBound
    }

    private func updateMaximum(_ rating: Int) {
        let maximum = max(
            min(rating, bounds.upperBound),
            value.lowerBound
        )
        value = value.lowerBound...maximum
    }

    private func adjust(
        rating: Int,
        direction: AccessibilityAdjustmentDirection,
        label: String
    ) {
        let delta: Int
        switch direction {
        case .increment: delta = 1
        case .decrement: delta = -1
        @unknown default: return
        }

        if label == String(localized: "最低评分") {
            updateMinimum(rating + delta)
        } else {
            updateMaximum(rating + delta)
        }
    }
}

private func 搜索占位线(
    width: CGFloat,
    height: CGFloat,
    opacity: Double = 0.1
) -> some View {
    RoundedRectangle(cornerRadius: height / 2, style: .continuous)
        .fill(Color.secondary.opacity(opacity))
        .frame(width: width, height: height)
}

private struct 搜索视觉小说加载占位行: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(
                cornerRadius: 列表封面布局.圆角(
                    horizontalSizeClass: horizontalSizeClass
                ),
                style: .continuous
            )
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)

            VStack(alignment: .leading, spacing: 列表行布局.主副标题间距) {
                搜索占位线(width: 184, height: 16, opacity: 0.14)
                搜索占位线(width: 132, height: 12)
                搜索占位线(width: 156, height: 10, opacity: 0.08)
                搜索占位线(width: 104, height: 10, opacity: 0.08)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct 搜索角色加载占位行: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(
                cornerRadius: 列表封面布局.圆角(
                    horizontalSizeClass: horizontalSizeClass
                ),
                style: .continuous
            )
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)

            VStack(alignment: .leading, spacing: 5) {
                搜索占位线(width: 176, height: 16, opacity: 0.14)
                搜索占位线(width: 126, height: 14, opacity: 0.1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct 搜索扩展加载占位行: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(
                cornerRadius: 列表封面布局.圆角(
                    horizontalSizeClass: horizontalSizeClass
                ),
                style: .continuous
            )
            .fill(Color.secondary.opacity(0.14))
            .frame(width: 列表封面布局.宽度, height: 列表封面布局.高度)

            VStack(alignment: .leading, spacing: 6) {
                搜索占位线(width: 184, height: 16, opacity: 0.14)
                搜索占位线(width: 132, height: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        搜索()
    }
    .environmentObject(用户登录(previewing: true))
    .environmentObject(Bangumi账户(previewing: true))
    .environmentObject(家长控制中心.shared)
}
