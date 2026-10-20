import SwiftUI

extension View {
    /// 按 `key` 分别记住滚动位置：切到别的分类再切回来时回到上次的位置，没看过的分类从顶部开始。
    /// 内容异步加载时，会等内容够长再恢复；这期间用户自己滚动就放弃恢复。
    func 记住滚动位置<Key: Hashable>(key: Key) -> some View {
        modifier(滚动位置记忆修饰器(key: key))
    }
}

/// 记录原始的 contentOffset：大标题展开和收起时顶部内边距会变，
/// 只有原始偏移量能把大标题的状态也一起还原。
/// 放在泛型修饰器外面并用 AnyHashable 作键：嵌套在里面会随 Key 泛型化，
/// @State 生成的存储代码就要跨隔离使用 Key 的 Hashable 一致性，编译器会警告。
private final class 滚动位置记录 {
    var current: CGFloat?
    var saved: [AnyHashable: CGFloat] = [:]
    var topInset: CGFloat = 0
    /// 等内容加载到足够长时再滚到的原始偏移量。
    var pending: CGFloat?
}

private struct 滚动位置记忆修饰器<Key: Hashable>: ViewModifier {
    let key: Key

    @State private var position = ScrollPosition(edge: .top)
    /// 滚动位置每帧都会变，存在不触发刷新的引用里，避免整页每帧重绘。
    @State private var record = 滚动位置记录()

    private struct 几何: Equatable {
        var offset: CGFloat
        var topInset: CGFloat
        var maxOffset: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: 几何.self) { geometry in
                几何(
                    offset: geometry.contentOffset.y,
                    topInset: geometry.contentInsets.top,
                    maxOffset: geometry.contentSize.height + geometry.contentInsets.bottom
                        - geometry.containerSize.height
                )
            } action: { _, geometry in
                record.topInset = geometry.topInset
                if let pending = record.pending {
                    if geometry.maxOffset >= pending - 1 {
                        record.pending = nil
                        scroll(toOffset: pending)
                    }
                    return
                }
                record.current = geometry.offset
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting {
                    record.pending = nil
                }
            }
            .onChange(of: key) { oldKey, newKey in
                if let current = record.current {
                    record.saved[AnyHashable(oldKey)] = current
                }
                record.current = nil
                guard let target = record.saved[AnyHashable(newKey)] else {
                    record.pending = nil
                    Task { @MainActor in position.scrollTo(edge: .top) }
                    return
                }
                record.pending = target
                Task { @MainActor in scroll(toOffset: target) }
            }
    }

    /// ScrollPosition 的 y 从内容顶部算起，换算成原始偏移量需要加上当前的顶部内边距。
    private func scroll(toOffset offset: CGFloat) {
        position.scrollTo(y: offset + record.topInset)
    }
}
