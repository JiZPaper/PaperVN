import SwiftUI

/// 动画、漫画与轻小说列表的排序菜单，和视觉小说的排序菜单一样：排序依据与升降序。
struct 作品浏览排序菜单: View {
    let selection: 作品浏览排序选择
    let onChange: (作品浏览排序选择) -> Void

    var body: some View {
        Menu {
            Picker("排序依据", selection: Binding(
                get: { selection.sort },
                set: { onChange(作品浏览排序选择(sort: $0)) }
            )) {
                ForEach(作品浏览排序.allCases) { sort in
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

            Picker("排序方向", selection: Binding(
                get: { selection.isDescending },
                set: { value in
                    var next = selection
                    next.isDescending = value
                    onChange(next)
                }
            )) {
                Label("升序", systemImage: "arrow.up").tag(false)
                Label("降序", systemImage: "arrow.down").tag(true)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("排序")
        .accessibilityValue(Text(verbatim: "\(selection.sort.localizedTitle)，\(selection.isDescending ? String(localized: "降序") : String(localized: "升序"))"))
    }
}

