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
    /// 顶部分段选择器用的短名称。分段平分屏幕宽度，每段只有约 58pt，
    /// 各语言单独翻译成放得下的词（英语 VNs、Chars 等），不影响其他地方的“视觉小说”等文案。
    var 短标题: String {
        switch self {
        case .visualNovel: return String(localized: "搜索分类.视觉小说", defaultValue: "视觉小说", comment: "搜索页顶部分段选择器，每段很窄，请用尽量短的词")
        case .character: return String(localized: "搜索分类.角色", defaultValue: "角色", comment: "搜索页顶部分段选择器，每段很窄，请用尽量短的词")
        case .release: return String(localized: "搜索分类.发行版本", defaultValue: "发行版本", comment: "搜索页顶部分段选择器，每段很窄，请用尽量短的词")
        case .staff: return String(localized: "搜索分类.制作人员", defaultValue: "制作人员", comment: "搜索页顶部分段选择器，每段很窄，请用尽量短的词")
        case .producer: return String(localized: "搜索分类.会社", defaultValue: "会社", comment: "搜索页顶部分段选择器，每段很窄，请用尽量短的词")
        }
    }

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

    @State private var searchInput: 搜索输入存储
    @State private var hasSearchTextState: Bool
    @State private var selectedSort = 视觉小说搜索排序选择()
    @State private var characterSort = 搜索扩展排序选择(sort: .added)
    @State private var releaseSort = 搜索扩展排序选择(sort: .released)
    @State private var staffSort = 搜索扩展排序选择(sort: .added)
    @State private var producerSort = 搜索扩展排序选择(sort: .added)
    /// 没有搜索词时顶部选择器选中的分类
    @State private var browseScope: 搜索范围 = .visualNovel
    @State private var filters = 视觉小说搜索筛选()
    @State private var draftFilters = 视觉小说搜索筛选()
    @State private var characterFilters = 搜索扩展筛选()
    @State private var staffFilters = 搜索扩展筛选()
    @State private var producerFilters = 搜索扩展筛选()
    @State private var draftCharacterFilters = 搜索扩展筛选()
    @State private var draftStaffFilters = 搜索扩展筛选()
    @State private var draftProducerFilters = 搜索扩展筛选()
    @State private var showsFilters = false
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
    @StateObject private var smartSearch = 智能搜索视图模型()
    @State private var smartSearchModelState = 智能搜索模型下载状态.shared
    @State private var resultDestination: 综合搜索导航目标?
    /// 用户点按展开或收起过的作品组；换了搜索词就清空，回到按相关性决定的默认状态
    @State private var 作品组平铺选择: [String: Int] = [:]
    @State private var 综合搜索区域尺寸: CGSize = .zero
    @State private var 作品组动画代次: [String: Int] = [:]
    @State private var keyboardSearchFieldClearance: CGFloat = 0

    private let externalSearchText: Binding<String>?
    private let showsSearchField: Bool

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
    @AppStorage(智能搜索设置.启用键)
    private var smartSearchEnabled = true

    init(
        searchText: Binding<String>? = nil,
        showsSearchField: Bool = true
    ) {
        let initialSearchText = searchText?.wrappedValue ?? ""
        let initiallyHasSearchText = !initialSearchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
        _searchInput = State(
            initialValue: 搜索输入存储(text: initialSearchText)
        )
        _hasSearchTextState = State(
            initialValue: initiallyHasSearchText
        )
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
        externalSearchText = searchText
        self.showsSearchField = showsSearchField
    }

    private var searchTextBinding: Binding<String> {
        Binding(
            get: { searchInput.text },
            set: { updateSearchText($0) }
        )
    }

    private var searchText: String {
        searchInput.text
    }

    private var externalSearchTextValue: String? {
        externalSearchText?.wrappedValue
    }

    private var searchNavigationTitle: String {
        String(localized: "搜索")
    }

    private var searchPrompt: String {
        String(localized: "搜索VNDB")
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
        .searchPresentationToolbarBehavior(.avoidHidingContent)
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
        .navigationDestination(item: $resultDestination) { item in
            resultDestinationView(item)
        }
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
            guard smartSearchEnabled, smartSearchModelState.isModelAvailable else { return }
            await 智能搜索引擎.shared.预热()
        }
        .onChange(of: smartSearchEnabled) { _, _ in
            updateSmartSearch()
        }
        .onChange(of: smartSearchModelState.isModelAvailable) { _, _ in
            updateSmartSearch()
        }
        .onChange(of: externalSearchTextValue) { _, newValue in
            guard let newValue, newValue != searchText else { return }
            updateSearchText(newValue)
        }
        .onChange(of: viewModel.视觉小说结果) { _, results in
            smartSearch.补充作品系列(results.map(\.id))
        }
        .onChange(of: viewModel.角色结果) { _, results in
            smartSearch.补充所属作品(results, 筛选: filters)
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
            submitSearch(immediately: true)
        }
        .onChange(of: characterSort) { _, _ in
            submitSearch(immediately: true)
        }
        .onChange(of: releaseSort) { _, _ in
            submitSearch(immediately: true)
        }
        .onChange(of: staffSort) { _, _ in
            submitSearch(immediately: true)
        }
        .onChange(of: producerSort) { _, _ in
            submitSearch(immediately: true)
        }
        .onChange(of: 浏览范围) { _, _ in
            submitSearch(immediately: true)
        }
    }

    private var searchFilterObservedContent: some View {
        searchSortObservedContent
        .onChange(of: filters) { _, _ in
            submitSearch(immediately: true)
        }
        .onChange(of: characterFilters) { _, _ in
            submitSearch(immediately: true)
        }
        .onChange(of: staffFilters) { _, _ in
            submitSearch(immediately: true)
        }
        .onChange(of: producerFilters) { _, _ in
            submitSearch(immediately: true)
        }
    }

    private var searchPresentationContent: some View {
        searchFilterObservedContent
        .toolbar {
            // iPad 的搜索框在右上角，展开时系统会把同一侧的其他按钮收进“…”，排序和筛选放到左侧
            ToolbarItemGroup(placement: usesExplicitSearchToolbarItem ? .topBarLeading : .平台主操作) {
                if hasSearchText || 浏览范围 == .visualNovel {
                    搜索排序菜单(
                        selection: $selectedSort,
                        hasSearchText: hasSearchText
                    )
                    .accessibilityIdentifier("search.sort")
                } else if let sortBinding = extendedSortBinding(for: 浏览范围) {
                    搜索扩展排序菜单(
                        selection: sortBinding,
                        scope: 浏览范围,
                        hasSearchText: false
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
                .matchedTransitionSource(id: "SearchFilterSheet", in: namespace)
            }

            if usesExplicitSearchToolbarItem, #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .平台主操作)

                DefaultToolbarItem(
                    kind: .search,
                    placement: .平台主操作
                )
            }


        }
        .sheet(isPresented: $showsFilters) {
            NavigationStack {
                综合搜索筛选页面(
                    visualNovelFilters: $draftFilters,
                    characterFilters: $draftCharacterFilters,
                    staffFilters: $draftStaffFilters,
                    producerFilters: $draftProducerFilters
                ) {
                    filters = draftFilters
                    characterFilters = draftCharacterFilters
                    staffFilters = draftStaffFilters
                    producerFilters = draftProducerFilters
                }
            }
            .navigationTransition(.zoom(sourceID: "SearchFilterSheet", in: namespace))
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
            "无法完成资料库操作",
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

    private var searchRootContent: some View {
        Group {
            if hasSearchText {
                综合搜索滚动页面
            } else {
                平台滚动页面 {
                    浏览内容(for: 浏览范围)
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
                .平台分组列表样式()
            }
        }
        .overlay {
            searchEmptyContentUnavailableView
        }
        // iOS 26 用 safeAreaBar，滚动边缘的渐进模糊会延伸到选择器下方，内容不会和选择器重叠
        .平台安全区域栏(edge: .top, spacing: 0) {
            if 显示浏览范围选择器 {
                浏览范围选择器
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: keyboardSearchFieldClearance)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var searchEmptyContentUnavailableView: some View {
        if hasSearchText {
            if !综合搜索正在载入,
               viewModel.视觉小说状态 != .loading,
               综合搜索条目列表.isEmpty,
               !综合搜索失败 {
                ContentUnavailableView.search
            }
        } else if 浏览页面状态(for: 浏览范围) == .empty {
            ContentUnavailableView.search
        }
    }

    private var 当前筛选为空: Bool {
        filters.isEmpty
            && characterFilters.isEmpty
            && staffFilters.isEmpty
            && producerFilters.isEmpty
    }

    private var hasSearchText: Bool {
        hasSearchTextState
    }

    private func updateSearchText(_ newValue: String) {
        guard searchInput.text != newValue else { return }
        searchInput.text = newValue
        作品组平铺选择 = [:]

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
        let wasRelevance = selectedSort.sort == .relevance
        selectedSort = .init(sort: .relevance)
        return !wasRelevance
    }

    @discardableResult
    private func resetRelevanceSortsForEmptySearch() -> Bool {
        guard selectedSort.sort == .relevance else { return false }
        selectedSort = .init(sort: .released)
        return true
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
                Text("正在载入…")
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
                Label("共享", systemImage: "square.and.arrow.up")
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
                Label("共享", systemImage: "square.and.arrow.up")
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
                Label("共享", systemImage: "square.and.arrow.up")
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
            format: String(localized: "要从资料库删除“%@”吗？"),
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
        violence: Double?,
        width: CGFloat = 列表封面布局.宽度,
        height: CGFloat = 列表封面布局.高度
    ) -> some View {
        // 小封面按宽度等比缩小圆角
        let cornerRadius = 列表封面布局.圆角(
            horizontalSizeClass: horizontalSizeClass
        ) * width / 列表封面布局.宽度
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
                    .accessibilityLabel("连按两次以解除模糊")
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

    // MARK: 浏览（没有搜索词）

    /// 没有搜索词时顶部选择器可选的分类：设置了筛选条件时只列出有条件的分类，否则列出全部分类。
    private var 可选浏览范围: [搜索范围] {
        let 有条件 = 搜索范围.allCases.filter { !浏览筛选为空(for: $0) }
        return 有条件.isEmpty ? 搜索范围.allCases : 有条件
    }

    private var 浏览范围: 搜索范围 {
        let 可选 = 可选浏览范围
        return 可选.contains(browseScope) ? browseScope : 可选[0]
    }

    private var 显示浏览范围选择器: Bool {
        !hasSearchText && 可选浏览范围.count > 1
    }

    private func 浏览筛选为空(for scope: 搜索范围) -> Bool {
        switch scope {
        case .visualNovel: return 浏览作品筛选.isEmpty
        case .character: return characterFilters.isEmpty
        case .release: return filters.发行版本规则.isEmpty
        case .staff: return staffFilters.isEmpty
        case .producer: return producerFilters.isEmpty
        }
    }

    /// 浏览作品时发行版本条件单独作为“发行版本”分类，不再用来筛选作品。
    private var 浏览作品筛选: 视觉小说搜索筛选 {
        var 筛选 = filters
        筛选.发行版本规则 = .init()
        return 筛选
    }

    /// 放得下时用分段选择器；字号很大或屏幕很窄、短名称也放不下时改用菜单，不截断文字。
    private var 浏览范围选择器: some View {
        let 选择 = Binding(
            get: { 浏览范围 },
            set: { browseScope = $0 }
        )
        return ViewThatFits(in: .horizontal) {
            Picker("搜索范围", selection: 选择) {
                ForEach(可选浏览范围) { scope in
                    Text(verbatim: scope.短标题)
                        .accessibilityLabel(Text(verbatim: scope.localizedTitle))
                        .tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Picker("搜索范围", selection: 选择) {
                ForEach(可选浏览范围) { scope in
                    Label(scope.localizedTitle, systemImage: scope.systemImage)
                        .tag(scope)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            浏览范围选择器背景
        }
        .accessibilityIdentifier("search.scope")
    }

    @ViewBuilder
    private var 浏览范围选择器背景: some View {
        if #available(iOS 26.0, *) {
            // iOS 26 起选择器放在 safeAreaBar 里，由滚动边缘效果模糊下方的内容
            Color.clear
        } else {
            Color.平台分组背景
                .ignoresSafeArea(edges: .top)
        }
    }

    private func extendedSortBinding(for scope: 搜索范围) -> Binding<搜索扩展排序选择>? {
        switch scope {
        case .character: return $characterSort
        case .release: return $releaseSort
        case .staff: return $staffSort
        case .producer: return $producerSort
        case .visualNovel: return nil
        }
    }

    private func extendedViewModel(for scope: 搜索范围) -> 扩展搜索视图模型 {
        switch scope {
        case .release: return releaseSearchViewModel
        case .producer: return producerSearchViewModel
        default: return staffSearchViewModel
        }
    }

    private func 浏览页面状态(for scope: 搜索范围) -> 搜索视图模型.页面状态 {
        switch scope {
        case .visualNovel: return viewModel.视觉小说状态
        case .character: return viewModel.角色状态
        case .release, .staff, .producer: return extendedViewModel(for: scope).当前状态
        }
    }

    @ViewBuilder
    private func 浏览内容(for scope: 搜索范围) -> some View {
        switch 浏览页面状态(for: scope) {
        case .idle, .empty:
            EmptyView()
        case .loading:
            searchLoadingSection(for: scope)
        case let .failed(message):
            探索加载失败页面(message: message) {
                if scope.is扩展搜索范围 {
                    extendedViewModel(for: scope).重试()
                } else {
                    viewModel.重试(范围: scope)
                }
            }
        case .loaded:
            switch scope {
            case .visualNovel:
                if 可见视觉小说结果.isEmpty {
                    受限隐藏空状态(范围: .visualNovel)
                } else {
                    visualNovelResults
                }
                paginationFooter(for: .visualNovel)
            case .character:
                if 可见角色结果.isEmpty {
                    受限隐藏空状态(范围: .character)
                } else {
                    characterResults
                }
                paginationFooter(for: .character)
            case .release:
                releaseResults
                extendedPaginationFooter(for: .release)
            case .staff:
                staffResults
                extendedPaginationFooter(for: .staff)
            case .producer:
                producerResults
                extendedPaginationFooter(for: .producer)
            }
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

    private var visualNovelResults: some View {
        Section {
            ForEach(
                Array(可见视觉小说结果.enumerated()),
                id: \.element.id
            ) { index, item in
                NavigationLink {
                    resultDestinationView(.作品(item))
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
                    resultDestinationView(.发行版本(item))
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
                    resultDestinationView(.制作人员(item))
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
                    resultDestinationView(.会社(item))
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
                resultDestinationView(.角色(item))
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

    @ViewBuilder
    private func extendedPaginationFooter(for scope: 搜索范围) -> some View {
        let model = extendedViewModel(for: scope)
        if model.正在加载下一页 {
            Section {
                ForEach(0..<2, id: \.self) { _ in
                    searchLoadingRow(for: scope)
                }
                .accessibilityHidden(true)
            }
            .id("extended-search-pagination-\(scope)-\(model.分页加载代次)")
        } else if let error = model.下一页错误 {
            Section {
                探索加载失败页面(message: error) {
                    model.加载下一页()
                }
            }
        }
    }

    // MARK: 综合搜索

    private var 当前智能搜索筛选: 智能搜索视图模型.筛选条件 {
        .init(作品: filters, 角色: characterFilters, 制作人员: staffFilters, 会社: producerFilters)
    }

    private func updateSmartSearch() {
        smartSearch.更新(
            关键词: searchText,
            可用: smartSearchEnabled && smartSearchModelState.isModelAvailable,
            筛选: 当前智能搜索筛选
        )
    }

    /// 按相关程度排序时完全按设备端智能搜索的顺序排列。
    private var 按相关程度排序: Bool {
        hasSearchText && selectedSort.sort == .relevance
    }

    private func 内容可见(_ 作品: 视觉小说搜索结果) -> Bool {
        guard contentFilterEnabled, contentRestrictionMethod == .hidden else { return true }
        return !内容安全限制判定.视觉小说需要限制(
            作品,
            enabled: contentFilterEnabled,
            sexualThreshold: sexualThreshold,
            violenceThreshold: violenceThreshold,
            mode: filterMode
        )
    }

    private func 内容可见(_ 角色: 角色搜索结果) -> Bool {
        guard contentFilterEnabled, contentRestrictionMethod == .hidden else { return true }
        return !shouldBlurImage(sexual: 角色.image?.sexual, violence: 角色.image?.violence)
    }

    private var 综合搜索条目列表: [综合搜索条目] {
        var 输入 = 综合搜索合并.输入()
        输入.按相关程度 = 按相关程度排序
        if 输入.按相关程度 {
            输入.智能搜索命中 = smartSearch.结果集.命中
            输入.制作人员 = smartSearch.制作人员
            输入.会社 = smartSearch.会社
            for 命中 in 输入.智能搜索命中 {
                if let 所属 = 命中.所属作品 { 输入.角色所属[命中.编号] = 所属 }
            }
        }
        // 角色的所属作品（即使不按相关程度排序也要用它们把角色挂在作品下）
        for (编号, 作品) in smartSearch.作品 where 内容可见(作品) {
            输入.作品[编号] = 作品
        }
        for (编号, 角色) in smartSearch.角色 where 输入.按相关程度 && 内容可见(角色) {
            输入.角色[编号] = 角色
        }
        for 作品 in 可见视觉小说结果 {
            输入.作品[作品.id] = 作品
            输入.VNDB作品顺序.append(作品.id)
        }
        for 角色 in 可见角色结果 {
            if 输入.角色[角色.id] == nil { 输入.角色[角色.id] = 角色 }
            输入.VNDB角色顺序.append(角色.id)
        }
        for item in staffSearchViewModel.制作人员结果 {
            if 输入.制作人员[item.id] == nil { 输入.制作人员[item.id] = item }
            输入.VNDB制作人员顺序.append(item.id)
        }
        for item in producerSearchViewModel.会社结果 {
            if 输入.会社[item.id] == nil { 输入.会社[item.id] = item }
            输入.VNDB会社顺序.append(item.id)
        }
        输入.作品系列 = smartSearch.作品系列
        return 综合搜索合并.合并(输入)
    }

    /// 智能搜索、VNDB 各分类的首页和角色所属作品都取回后才显示结果，避免结果出来后又重新排列。
    private var 综合搜索正在载入: Bool {
        viewModel.视觉小说状态 == .loading
            || viewModel.角色状态 == .loading
            || staffSearchViewModel.当前状态 == .loading
            || producerSearchViewModel.当前状态 == .loading
            || smartSearch.正在搜索
            || smartSearch.所属作品待补充(viewModel.角色结果)
            || smartSearch.系列待补充(viewModel.视觉小说结果.map(\.id))
    }

    private var 综合搜索失败: Bool {
        if case .failed = viewModel.视觉小说状态 { return true }
        return false
    }

    private var 综合搜索正在加载下一页: Bool {
        viewModel.是否正在加载下一页(for: .visualNovel)
            || viewModel.是否正在加载下一页(for: .character)
            || staffSearchViewModel.正在加载下一页
            || producerSearchViewModel.正在加载下一页
    }

    private func 加载更多() {
        if viewModel.是否还有更多(for: .visualNovel) {
            viewModel.加载下一页(范围: .visualNovel)
        }
        if viewModel.是否还有更多(for: .character) {
            viewModel.加载下一页(范围: .character)
        }
        if staffSearchViewModel.还有更多 {
            staffSearchViewModel.加载下一页()
        }
        if producerSearchViewModel.还有更多 {
            producerSearchViewModel.加载下一页()
        }
    }

    /// 有搜索词时的结果页：一张张圆角卡片。不用 List，卡片堆的展开收起才能做连贯的动画，
    /// 长按时也只浮起按住的那张卡片。
    /// iPad（常规宽度、且足够宽）时结果分两列显示；iPhone 和窄分屏保持单列。
    private var 综合搜索列数: Int {
        horizontalSizeClass == .regular && 综合搜索区域尺寸.width >= 700 ? 2 : 1
    }

    /// 有搜索词时的结果页：一张张圆角卡片。不用 List，卡片堆的展开收起才能做连贯的动画，
    /// 长按时也只浮起按住的那张卡片。两列时结果左右交替排列，两列各自往下排，
    /// 一列里的卡片堆展开时不会在另一列留下空白。
    private var 综合搜索滚动页面: some View {
        let 列数 = 综合搜索列数
        return ScrollView {
            Group {
                if 综合搜索正在载入 {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(0..<列数, id: \.self) { _ in
                            VStack(spacing: 12) {
                                ForEach(0..<5, id: \.self) { _ in
                                    搜索视觉小说加载占位行()
                                        .padding(综合行内边距)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.平台次级分组背景, in: 综合卡片形状(下属: false))
                                }
                            }
                        }
                    }
                    .accessibilityHidden(true)
                } else if case let .failed(message) = viewModel.视觉小说状态 {
                    探索加载失败页面(message: message) {
                        submitSearch(immediately: true)
                    }
                } else {
                    let 条目 = Array(综合搜索条目列表.enumerated())
                    VStack(spacing: 12) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(0..<列数, id: \.self) { 列 in
                                LazyVStack(spacing: 12) {
                                    ForEach(条目.filter { $0.offset % 列数 == 列 }, id: \.element.id) { 序号, item in
                                        综合搜索条目视图(item)
                                            // 前面的结果盖在后面的上面：卡片收回时下面的结果往上移，不会挡住正在收回的卡片
                                            .zIndex(Double(条目.count - 序号))
                                            // 卡片收回时原本在屏幕外的结果被懒加载出来，不要淡入，直接垫在正在收回的卡片下面
                                            .transition(.identity)
                                            .onAppear {
                                                if 序号 >= 条目.count - 平台列表分页.预取余量 * 列数 {
                                                    加载更多()
                                                }
                                            }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .top)
                            }
                        }
                        if 综合搜索正在加载下一页 {
                            ProgressView()
                                .padding()
                        }
                    }
                }
            }
            .frame(maxWidth: 列数 == 1 ? 720 : 1480)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { 综合搜索区域尺寸 = $0 }
        .scrollDismissesKeyboard(.immediately)
        .平台柔和滚动边缘(for: .top)
    }

    @ViewBuilder
    private func 综合搜索条目视图(_ item: 综合搜索条目) -> some View {
        switch item {
        case let .作品(组):
            作品组卡片堆(组)
        case let .角色(角色):
            综合搜索卡片(action: { openCharacter(角色) }) {
                characterRow(角色)
            }
            .contextMenu {
                shareContextMenu(for: .character, id: 角色.id)
            }
        case let .制作人员(人员):
            综合搜索卡片(action: { resultDestination = .制作人员(人员) }) {
                searchStaffRow(人员)
            }
            .contextMenu {
                shareContextMenu(for: .staff, id: 人员.id)
            }
        case let .会社(会社):
            综合搜索卡片(action: { resultDestination = .会社(会社) }) {
                searchProducerRow(会社)
            }
            .contextMenu {
                shareContextMenu(for: .producer, id: 会社.id)
            }
        }
    }

    // MARK: 作品组卡片堆

    /// 名字和搜索词对得上的条目：VNDB 按关键词搜到的，或智能搜索判断名字匹配的。
    /// 只因为是角色的所属作品而补进来的作品不算。
    private var 与搜索词相关的编号: Set<String> {
        var 编号 = Set(viewModel.视觉小说结果.map(\.id))
        编号.formUnion(viewModel.角色结果.map(\.id))
        for 命中 in smartSearch.结果集.命中 where 命中.名称匹配 {
            编号.insert(命中.编号)
        }
        return 编号
    }

    /// 要突出显示的下属条目：和搜索词相关，并且比上面的作品更像用户要找的——
    /// 作品本身和搜索词无关（只是角色的所属作品），或者这个条目在智能搜索里排在作品前面。
    /// 搜“steins”时系列作品虽然也相关，但作品本身排第一，不突出它们。
    private func 作品组突出编号(_ 组: 综合作品组, 相关: Set<String>, 名次: [String: Int]) -> Set<String> {
        let 下属 = 组.角色.map(\.id) + 组.同系列.map(\.id)
        let 作品相关 = 相关.contains(组.作品.id)
        let 作品名次 = 名次[组.作品.id] ?? .max
        return Set(下属.filter { 编号 in
            相关.contains(编号) && (!作品相关 || (名次[编号] ?? .max) < 作品名次)
        })
    }

    private var 智能搜索名次: [String: Int] {
        var 名次: [String: Int] = [:]
        for (序号, 命中) in smartSearch.结果集.命中.enumerated() where 名次[命中.编号] == nil {
            名次[命中.编号] = 序号
        }
        return 名次
    }

    /// 平铺开的下属卡片张数：有要突出显示的下属条目时默认全部平铺，否则叠成一摞；用户点按后以用户的选择为准。
    private func 作品组平铺数量(_ 组: 综合作品组, 下属数量: Int, 突出: Set<String>) -> Int {
        min(作品组平铺选择[组.id] ?? (突出.isEmpty ? 0 : 下属数量), 下属数量)
    }

    /// 一张接一张地弹出或收回：展开时从第一张往后，收起时从最后一张往前，每张错开一点时间。
    private func 切换作品组(_ 组: 综合作品组, 当前: Int, 总数: Int) {
        let 目标 = 当前 > 0 ? 0 : 总数
        let 代次 = (作品组动画代次[组.id] ?? 0) + 1
        作品组动画代次[组.id] = 代次
        let 步骤 = 目标 > 当前 ? Array((当前 + 1)...目标) : Array((目标..<当前).reversed())
        Task { @MainActor in
            for (序号, 数量) in 步骤.enumerated() {
                if 序号 > 0 {
                    try? await Task.sleep(for: .milliseconds(目标 > 当前 ? 55 : 40))
                }
                guard 作品组动画代次[组.id] == 代次 else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    作品组平铺选择[组.id] = 数量
                }
            }
        }
    }

    private enum 作品组下属: Identifiable {
        case 角色(角色搜索结果)
        case 作品(视觉小说搜索结果)

        var id: String {
            switch self {
            case let .角色(item): return item.id
            case let .作品(item): return item.id
            }
        }
    }

    /// 作品组下面的一类内容：所有角色合在一张卡片里，所有系列作品合在一张卡片里。
    private struct 作品组分类: Identifiable {
        let id: String
        let 条目: [作品组下属]
    }

    private func 作品组分类列表(_ 组: 综合作品组) -> [作品组分类] {
        var 分类: [作品组分类] = []
        if !组.角色.isEmpty {
            分类.append(.init(
                id: "characters",
                条目: 组.角色.map(作品组下属.角色)
            ))
        }
        if !组.同系列.isEmpty {
            分类.append(.init(
                id: "series",
                条目: 组.同系列.map(作品组下属.作品)
            ))
        }
        return 分类
    }

    /// 一部作品和挂在它下面的角色、系列作品。收起时“角色”“系列”两张卡片真的叠在作品卡片后面，只露出边缘；
    /// 点按作品卡片下面的胶囊，两张卡片一张张弹出来平铺，整组用一个灰色大框框起来；再点按一张张收回去。
    private func 作品组卡片堆(_ 组: 综合作品组) -> some View {
        let 突出编号 = 作品组突出编号(组, 相关: 与搜索词相关的编号, 名次: 智能搜索名次)
        let 分类 = 作品组分类列表(组)
        let 平铺数量 = 作品组平铺数量(组, 下属数量: 分类.count, 突出: 突出编号)
        let 已展开 = 平铺数量 > 0
        let 切换 = { 切换作品组(组, 当前: 平铺数量, 总数: 分类.count) }
        let 框内边距: CGFloat = 8

        return 卡片堆叠布局(平铺数量: 平铺数量, 露出: 9, 内缩: 0, 胶囊间距: 22) {
            综合搜索卡片(action: { resultDestination = .作品(组.作品) }) {
                visualNovelRow(组.作品)
            }
            .contextMenu {
                visualNovelContextMenu(for: 组.作品)
            }
            .overlay(alignment: .bottom) {
                if !分类.isEmpty {
                    作品组摘要胶囊(组, 已展开: 已展开, 切换: 切换)
                        .offset(y: 11)
                }
            }
            // 叠起来时作品卡片投下一点阴影，和后面的卡片边缘分开
            .shadow(color: .black.opacity(!分类.isEmpty && !已展开 ? 0.1 : 0), radius: 3, y: 1)
            .zIndex(Double(分类.count + 1))

            ForEach(Array(分类.enumerated()), id: \.element.id) { 序号, 类 in
                作品组分类卡片(
                    类,
                    已展开: 序号 < 平铺数量,
                    深度: 序号 - 平铺数量 + 1,
                    展开: 切换
                )
                .zIndex(Double(分类.count - 序号))
            }
        }
        .padding(已展开 ? 框内边距 : 0)
        .background {
            if 已展开 {
                RoundedRectangle(
                    cornerRadius: 综合卡片形状(下属: false).cornerSize.width + 框内边距,
                    style: .continuous
                )
                .fill(Color(uiColor: .systemGray5))
                .transition(.opacity)
            }
        }
    }

    private func 作品组摘要胶囊(_ 组: 综合作品组, 已展开: Bool, 切换: @escaping () -> Void) -> some View {
        Button(action: 切换) {
            HStack(spacing: 4) {
                Image(systemName: "square.stack")
                Text(verbatim: 作品组摘要(组))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(已展开 ? 180 : 0))
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(uiColor: 已展开 ? .systemGray5 : .systemGroupedBackground), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(已展开 ? "已展开" : "已收起"))
    }

    private func 作品组摘要(_ 组: 综合作品组) -> String {
        var 部分: [String] = []
        if !组.角色.isEmpty {
            部分.append(String(localized: "角色 \(组.角色.count)"))
        }
        if !组.同系列.isEmpty {
            部分.append(String(localized: "系列 \(组.同系列.count)"))
        }
        return 部分.joined(separator: " · ")
    }

    /// “角色”或“系列”卡片：一行行条目，类别和数量只写在作品卡片下面的胶囊上。收起时只是作品卡片后面的一层卡片边缘（内容透明，点按展开整组）。
    private func 作品组分类卡片(
        _ 类: 作品组分类,
        已展开: Bool,
        深度: Int,
        展开: @escaping () -> Void
    ) -> some View {
        let 形状 = RoundedRectangle(cornerRadius: 作品组行圆角 + 4, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(类.条目.enumerated()), id: \.element.id) { 序号, 条目 in
                if 序号 > 0 {
                    Divider()
                        .padding(.leading, 12 + 作品组下属封面宽度 + 10)
                }
                作品组下属行(条目)
            }
        }
        .padding(4)
        .opacity(已展开 ? 1 : 0)
        .allowsHitTesting(已展开)
        // 叠着时高度跟随布局给的作品卡片高度，展开时恢复内容高度
        .frame(maxWidth: .infinity, minHeight: 已展开 ? nil : 0, maxHeight: 已展开 ? nil : .infinity, alignment: .topLeading)
        .background {
            形状.fill(Color.平台次级分组背景)
            // 叠在后面的卡片越靠后越暗
            形状.fill(Color.primary.opacity(已展开 ? 0 : 0.05 * Double(min(深度, 2))))
        }
        .clipShape(形状)
        .overlay {
            if !已展开 {
                形状.fill(Color.clear)
                    .contentShape(形状)
                    .onTapGesture(perform: 展开)
            }
        }
        .shadow(color: .black.opacity(已展开 ? 0 : 0.08), radius: 2, y: 1)
        // 第三张以后的卡片收起时完全藏在后面
        .opacity(已展开 || 深度 <= 2 ? 1 : 0)
        .accessibilityHidden(!已展开)
    }

    /// 分类卡片里的一行。
    private func 作品组下属行(_ 条目: 作品组下属) -> some View {
        let 行形状 = RoundedRectangle(cornerRadius: 作品组行圆角, style: .continuous)
        let 行 = Button {
            switch 条目 {
            case let .角色(角色): openCharacter(角色)
            case let .作品(作品): resultDestination = .作品(作品)
            }
        } label: {
            HStack(spacing: 8) {
                作品组下属内容(条目)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .padding(.trailing, 4)
            .contentShape(行形状)
        }
        .buttonStyle(综合搜索卡片按钮样式(形状: 行形状))
        .contentShape(.contextMenuPreview, 行形状)

        return Group {
            switch 条目 {
            case let .角色(角色):
                行.contextMenu { shareContextMenu(for: .character, id: 角色.id) }
            case let .作品(作品):
                行.contextMenu { visualNovelContextMenu(for: 作品) }
            }
        }
    }

    @ViewBuilder
    private func 作品组下属内容(_ 条目: 作品组下属) -> some View {
        switch 条目 {
        case let .角色(角色):
            HStack(spacing: 10) {
                作品组下属封面(编号: "character-\(角色.id)", 图片: 角色.image?.url, sexual: 角色.image?.sexual, violence: 角色.image?.violence)
                Text(
                    verbatim: 人物名称工具.显示名称(
                        name: 角色.name,
                        original: 角色.original,
                        偏好: staffNameLang
                    )
                )
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            }
        case let .作品(作品):
            HStack(spacing: 10) {
                作品组下属封面(编号: "vn-\(作品.id)", 图片: 作品.image?.thumbnail ?? 作品.image?.url, sexual: 作品.image?.sexual, violence: 作品.image?.violence)
                VStack(alignment: .leading, spacing: 3) {
                    多语言列表文本(visualNovelDisplayTitle(for: 作品), 层级: .副标题)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let released = 作品.released {
                            metadata(icon: "calendar", text: released)
                        }
                        视觉小说统一评分标签(
                            vndbID: 作品.id,
                            vndbRating: 作品.rating,
                            vndbVoteCount: 作品.votecount
                        )
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func 作品组下属封面(编号: String, 图片: String?, sexual: Double?, violence: Double?) -> some View {
        resultImage(
            id: 编号,
            url: 图片,
            sexual: sexual,
            violence: violence,
            width: 作品组下属封面宽度,
            height: 作品组下属封面宽度 * 列表封面布局.高度 / 列表封面布局.宽度
        )
    }

    /// 分类卡片里每一行的圆角：小封面圆角 + 封面到行边缘的距离，同心；分类卡片再大 4。
    private var 作品组行圆角: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) * 作品组下属封面宽度 / 列表封面布局.宽度 + 8
    }

    private var 作品组下属封面宽度: CGFloat { 44 }

    private func 综合卡片形状(下属: Bool) -> RoundedRectangle {
        let 内边距 = 下属 ? 8 : 综合行内边距
        let 封面圆角 = 列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass)
            * (下属 ? 作品组下属封面宽度 / 列表封面布局.宽度 : 1)
        return RoundedRectangle(cornerRadius: 封面圆角 + 内边距, style: .continuous)
    }

    /// 搜索结果的一张卡片：卡片圆角 = 封面圆角 + 封面到卡片边缘的距离，两者同心。
    private func 综合搜索卡片<Label: View>(
        下属: Bool = false,
        内容可见: Bool = true,
        叠层深度: Int = 0,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let 形状 = 综合卡片形状(下属: 下属)
        return Button(action: action) {
            HStack(spacing: 8) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(下属 ? 8 : 综合行内边距)
            .padding(.trailing, 6)
            .opacity(内容可见 ? 1 : 0)
            .background {
                形状.fill(Color.平台次级分组背景)
                // 叠在后面的卡片越靠后越暗
                形状.fill(Color.primary.opacity(叠层深度 == 0 ? 0 : 0.05 * Double(叠层深度)))
            }
            .contentShape(形状)
        }
        .buttonStyle(综合搜索卡片按钮样式(形状: 形状))
        .contentShape(.contextMenuPreview, 形状)
    }

    /// 封面到卡片边缘的距离：卡片圆角减去封面圆角，封面和卡片的圆角成为同心圆。
    /// 封面圆角与资料库一致（iOS 26 起 16pt，单元格约 26pt）。
    private var 综合行内边距: CGFloat {
        列表封面布局.圆角(horizontalSizeClass: horizontalSizeClass) * 10 / 16
    }

    private func openCharacter(_ item: 角色搜索结果) {
        if item.id == 内容安全高级设置解锁入口.角色ID,
           内容安全高级设置解锁入口.是触发搜索(searchText) {
            unlockCharacterDestination = item
        } else {
            resultDestination = .角色(item)
        }
    }

    @ViewBuilder
    private func resultDestinationView(_ target: 综合搜索导航目标) -> some View {
        switch target {
        case let .作品(work):
            视觉小说详情(
                vnID: work.id,
                auth: auth,
                initialTitle: work.title,
                initialTitles: work.titles,
                initialImageURL: work.image?.url,
                initialImageSexual: work.image?.sexual,
                initialImageViolence: work.image?.violence,
                initialImageDimensions: work.image?.dims
            )
        case let .角色(character):
            角色详情(
                characterID: character.id,
                auth: auth,
                initialName: character.name,
                initialOriginal: character.original,
                initialAliases: character.aliases,
                initialImage: character.image
            )
        case let .制作人员(staff):
            探索制作人员详情(item: staff)
        case let .会社(producer):
            探索会社详情(item: producer)
        case let .发行版本(release):
            探索发行版本详情(item: release, auth: auth)
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

    private func submitSearch(immediately: Bool = false) {
        if hasSearchText {
            // 有搜索词：所有分类一起搜索，结果合并显示
            viewModel.更新搜索(
                关键词: searchText, 范围: .visualNovel, 筛选: filters,
                排序: selectedSort.sort, 降序: selectedSort.isDescending,
                允许空搜索: true, 立即: immediately
            )
            viewModel.更新搜索(
                关键词: searchText, 范围: .character, 筛选: filters,
                排序: selectedSort.sort, 扩展筛选: characterFilters,
                扩展排序: .relevance,
                允许空搜索: !characterFilters.isEmpty, 立即: immediately
            )
            staffSearchViewModel.更新搜索(
                关键词: searchText, 范围: .staff,
                筛选: staffFilters, 排序: .relevance, 立即: immediately
            )
            producerSearchViewModel.更新搜索(
                关键词: searchText, 范围: .producer,
                筛选: producerFilters, 排序: .relevance, 立即: immediately
            )
        } else {
            // 没有搜索词：只载入顶部选择器选中的分类
            switch 浏览范围 {
            case .visualNovel:
                viewModel.更新搜索(
                    关键词: "", 范围: .visualNovel, 筛选: 浏览作品筛选,
                    排序: selectedSort.sort, 降序: selectedSort.isDescending,
                    允许空搜索: true, 立即: immediately
                )
            case .character:
                viewModel.更新搜索(
                    关键词: "", 范围: .character, 筛选: filters,
                    扩展筛选: characterFilters,
                    扩展排序: characterSort.sort, 扩展降序: characterSort.isDescending,
                    允许空搜索: true, 立即: immediately
                )
            case .release:
                releaseSearchViewModel.更新搜索(
                    关键词: "", 范围: .release, 筛选: filters.发行版本规则,
                    排序: releaseSort.sort, 降序: releaseSort.isDescending, 立即: immediately
                )
            case .staff:
                staffSearchViewModel.更新搜索(
                    关键词: "", 范围: .staff, 筛选: staffFilters,
                    排序: staffSort.sort, 降序: staffSort.isDescending, 立即: immediately
                )
            case .producer:
                producerSearchViewModel.更新搜索(
                    关键词: "", 范围: .producer, 筛选: producerFilters,
                    排序: producerSort.sort, 降序: producerSort.isDescending, 立即: immediately
                )
            }
        }
        updateSmartSearch()
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
        draftCharacterFilters = characterFilters
        draftStaffFilters = staffFilters
        draftProducerFilters = producerFilters
        showsFilters = true
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

enum 综合搜索导航目标: Hashable, Identifiable {
    case 作品(视觉小说搜索结果)
    case 角色(角色搜索结果)
    case 制作人员(探索制作人员)
    case 会社(探索会社)
    case 发行版本(探索发行版本)

    var id: String {
        switch self {
        case let .作品(item): return item.id
        case let .角色(item): return item.id
        case let .制作人员(item): return item.id
        case let .会社(item): return item.id
        case let .发行版本(item): return item.id
        }
    }
}

/// 按下时卡片变暗，与系统列表行一致。
struct 综合搜索卡片按钮样式: ButtonStyle {
    let 形状: RoundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    形状.fill(Color.primary.opacity(0.08))
                }
            }
    }
}

/// 作品组的卡片堆：第一个子视图是作品卡片，其余是下属卡片。
/// 前 `平铺数量` 张下属卡片在作品卡片下面依次平铺（左右各内缩 `内缩`，居中）；
/// 其余的叠在作品卡片后面，底边依次往下错开 `露出`、宽度依次收窄，只露出边缘。
/// 在动画里逐张改变 `平铺数量`，卡片就一张张从作品卡片后面弹出或收回。
struct 卡片堆叠布局: Layout {
    var 平铺数量: Int
    var 露出: CGFloat
    var 内缩: CGFloat
    /// 作品卡片和第一张平铺卡片之间留出放胶囊的空隙
    var 胶囊间距: CGFloat
    var 间距: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let 作品 = subviews.first else { return .zero }
        let 宽 = proposal.width ?? 作品.sizeThatFits(.unspecified).width
        let 作品高 = 作品.sizeThatFits(.init(width: 宽, height: nil)).height
        let 下属 = Array(subviews.dropFirst())
        guard !下属.isEmpty else { return CGSize(width: 宽, height: 作品高) }
        let 平铺 = min(平铺数量, 下属.count)
        if 平铺 == 0 {
            return CGSize(width: 宽, height: 作品高 + 露出 * CGFloat(min(下属.count, 2)))
        }
        var 高 = 作品高 + 胶囊间距 - 间距
        for 卡片 in 下属.prefix(平铺) {
            高 += 间距 + 卡片.sizeThatFits(.init(width: 宽 - 内缩 * 2, height: nil)).height
        }
        return CGSize(width: 宽, height: 高)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let 作品 = subviews.first else { return }
        let 宽 = bounds.width
        let 作品高 = 作品.sizeThatFits(.init(width: 宽, height: nil)).height
        作品.place(at: bounds.origin, anchor: .topLeading, proposal: .init(width: 宽, height: 作品高))
        var y = bounds.minY + 作品高 + 胶囊间距 - 间距
        for (序号, 卡片) in subviews.dropFirst().enumerated() {
            if 序号 < 平铺数量 {
                let 卡片宽 = 宽 - 内缩 * 2
                let 高 = 卡片.sizeThatFits(.init(width: 卡片宽, height: nil)).height
                y += 间距
                卡片.place(at: CGPoint(x: bounds.minX + 内缩, y: y), anchor: .topLeading, proposal: .init(width: 卡片宽, height: 高))
                y += 高
            } else {
                // 还叠着的卡片：和作品卡片一样高，藏在作品卡片后面，底边错开露出边缘
                // （卡片本身可能比作品卡片高，按作品卡片的高度裁剪，否则会从作品卡片上方露出来）
                let 深度 = CGFloat(min(序号 - 平铺数量 + 1, 2))
                let 收窄 = 深度 * 10
                卡片.place(
                    at: CGPoint(x: bounds.minX + 收窄, y: bounds.minY + 露出 * 深度),
                    anchor: .topLeading,
                    proposal: .init(width: 宽 - 收窄 * 2, height: 作品高)
                )
            }
        }
    }
}
