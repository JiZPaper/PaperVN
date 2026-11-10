import Combine
import Foundation

/// 搜索页没有搜索词时，动画、漫画与轻小说分类的列表（AniList，默认按开始日期，可排序与筛选，分页加载）。
@MainActor
final class 作品浏览视图模型: ObservableObject {
    @Published private(set) var 结果: [作品类型: [作品搜索结果]] = [:]
    @Published private(set) var 状态: [作品类型: 搜索视图模型.页面状态] = [:]
    @Published private(set) var 正在加载下一页: Set<作品类型> = []
    @Published private(set) var 下一页错误: [作品类型: String] = [:]
    private var 还有更多: [作品类型: Bool] = [:]
    private var 当前页: [作品类型: Int] = [:]
    private var 任务: [作品类型: Task<Void, Never>] = [:]
    /// 按开始日期排序时，有日期的作品已经读完，正在读没定日期的（排在最后）。
    private var 读未定日期: Set<作品类型> = []
    /// 每种作品各自的排序与筛选；改了就从第一页重新载入。
    @Published private(set) var 排序: [作品类型: 作品浏览排序选择] = [:]
    @Published private(set) var 筛选: [作品类型: 作品浏览筛选] = [:]

    func 排序(_ type: 作品类型) -> 作品浏览排序选择 { 排序[type] ?? 作品浏览排序选择() }
    func 筛选(_ type: 作品类型) -> 作品浏览筛选 { 筛选[type] ?? 作品浏览筛选() }

    func 设置排序(_ value: 作品浏览排序选择, for type: 作品类型) {
        guard value != 排序(type) else { return }
        排序[type] = value
        加载首页(type, 强制: true)
    }

    func 设置筛选(_ value: 作品浏览筛选, for type: 作品类型) {
        guard value != 筛选(type) else { return }
        筛选[type] = value
        加载首页(type, 强制: true)
    }

    func 页面状态(_ type: 作品类型) -> 搜索视图模型.页面状态 {
        状态[type] ?? .idle
    }

    func 是否还有更多(_ type: 作品类型) -> Bool {
        还有更多[type] ?? false
    }

    /// 已经载入过的分类不重新请求，除非 `强制`。
    func 加载首页(_ type: 作品类型, 强制: Bool = false) {
        switch 页面状态(type) {
        case .loaded, .loading, .empty: guard 强制 else { return }
        case .idle, .failed: break
        }
        任务[type]?.cancel()
        状态[type] = .loading
        下一页错误[type] = nil
        读未定日期.remove(type)
        任务[type] = Task { [weak self] in
            do {
                guard let self else { return }
                let page = try await self.读取(type, 页码: 1)
                guard !Task.isCancelled else { return }
                self.结果[type] = page.结果
                self.还有更多[type] = page.还有更多
                self.当前页[type] = page.页码
                self.状态[type] = page.结果.isEmpty ? .empty : .loaded
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.状态[type] = .failed(error.localizedDescription)
            }
        }
    }

    /// 读一页。按开始日期排序时分两段：先读有日期的，读完后换成没定日期的，从第一页接着读（排在最后）。
    /// 返回的 `页码` 是下次续读时的当前页：刚换段时为 0。
    private func 读取(_ type: 作品类型, 页码 page: Int) async throws -> (结果: [作品搜索结果], 还有更多: Bool, 页码: Int) {
        let sort = 排序(type), filter = 筛选(type)
        guard sort.sort == .startDate else {
            let result = try await 作品聚合搜索.shared.热门(类型: type, 页码: page, 排序: sort, 筛选: filter)
            return (result.结果, result.还有更多, page)
        }
        let undated = 读未定日期.contains(type)
        let result = try await 作品聚合搜索.shared.热门(
            类型: type, 页码: page, 排序: sort, 筛选: filter, 有开始日期: !undated
        )
        if !undated, !result.还有更多 {
            读未定日期.insert(type)
            return (result.结果, true, 0)
        }
        return (result.结果, result.还有更多, page)
    }

    func 加载下一页(_ type: 作品类型) {
        guard 页面状态(type) == .loaded, 是否还有更多(type), !正在加载下一页.contains(type) else { return }
        正在加载下一页.insert(type)
        下一页错误[type] = nil
        let next = (当前页[type] ?? 1) + 1
        Task { [weak self] in
            defer { self?.正在加载下一页.remove(type) }
            do {
                guard let self else { return }
                let page = try await self.读取(type, 页码: next)
                let existing = Set((self.结果[type] ?? []).map(\.id))
                self.结果[type, default: []].append(contentsOf: page.结果.filter { !existing.contains($0.id) })
                self.还有更多[type] = page.还有更多
                self.当前页[type] = page.页码
            } catch {
                self?.下一页错误[type] = error.localizedDescription
            }
        }
    }
}
