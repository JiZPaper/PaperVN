import ActivityKit
import SwiftUI
import WidgetKit

private let 偏好分析图标 = "wand.and.sparkles.inverse"

@main
struct PaperVN实时活动组件包: WidgetBundle {
    var body: some Widget {
        PaperVN偏好分析实时活动()
    }
}

struct PaperVN偏好分析实时活动: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: 偏好分析实时活动属性.self) { context in
            锁屏实时活动视图(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("分析偏好")
                    } icon: {
                        Image(systemName: 偏好分析图标)
                            .foregroundStyle(.blue)
                    }
                    .font(.headline)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.percentage)%")
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PaperVN需要一些时间分析你的偏好。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        ProgressView(value: context.state.progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .frame(maxWidth: 280)
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: 偏好分析图标)
                    .foregroundStyle(.blue)
            } compactTrailing: {
                Text("\(context.state.percentage)%")
                    .font(.caption.monospacedDigit())
                    .contentTransition(.numericText())
            } minimal: {
                Image(systemName: 偏好分析图标)
                    .foregroundStyle(.blue)
            }
            .keylineTint(.blue)
        }
    }
}

private struct 锁屏实时活动视图: View {
    let context: ActivityViewContext<偏好分析实时活动属性>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: 偏好分析图标)
                    .foregroundStyle(.blue)

                Text("分析偏好")
                    .font(.headline)

                Spacer(minLength: 12)

                Text("\(context.state.percentage)%")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
            }

            Text("PaperVN需要一些时间分析你的偏好。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: context.state.progress)
                .progressViewStyle(.linear)
                .tint(.blue)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
