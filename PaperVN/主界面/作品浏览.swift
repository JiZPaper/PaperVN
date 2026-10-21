import Combine
import Foundation

/// 搜索页没有搜索词时，动画、漫画与轻小说分类的列表（AniList 热度排行，分页加载）。
@MainActor
final class 作品浏览视图模型: ObservableObject {
    @Published private(set) var 结果: [作品类型: [作品搜索结果]] = [:]
    @Published private(set) var 状态: [作品类型: 搜索视图模型.页面状态] = [:]
    @Published private(set) var 正在加载下一页: Set<作品类型> = []
    @Published private(set) var 下一页错误: [作品类型: String] = [:]
    private var 还有更多: [作品类型: Bool] = [:]
    private var 当前页: [作品类型: Int] = [:]
    private var 任务: [作品类型: Task<Void, Never>] = [:]

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
        任务[type] = Task { [weak self] in
            do {
                let page = try await 作品聚合搜索.shared.热门(类型: type, 页码: 1)
                guard let self, !Task.isCancelled else { return }
                self.结果[type] = page.结果
                self.还有更多[type] = page.还有更多
                self.当前页[type] = 1
                self.状态[type] = page.结果.isEmpty ? .empty : .loaded
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.状态[type] = .failed(error.localizedDescription)
            }
        }
    }

    func 加载下一页(_ type: 作品类型) {
        guard 页面状态(type) == .loaded, 是否还有更多(type), !正在加载下一页.contains(type) else { return }
        正在加载下一页.insert(type)
        下一页错误[type] = nil
        let next = (当前页[type] ?? 1) + 1
        Task { [weak self] in
            defer { self?.正在加载下一页.remove(type) }
            do {
                let page = try await 作品聚合搜索.shared.热门(类型: type, 页码: next)
                guard let self else { return }
                let existing = Set((self.结果[type] ?? []).map(\.id))
                self.结果[type, default: []].append(contentsOf: page.结果.filter { !existing.contains($0.id) })
                self.还有更多[type] = page.还有更多
                self.当前页[type] = next
            } catch {
                self?.下一页错误[type] = error.localizedDescription
            }
        }
    }
}
