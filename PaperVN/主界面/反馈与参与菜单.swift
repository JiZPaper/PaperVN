import SwiftUI

/// “反馈与参与”菜单：反馈（含数据维护和贡献的翻译）、参与Today。显示在资料库左上角。
struct 反馈与参与菜单: View {
    @EnvironmentObject private var auth: 用户登录
    @ObservedObject private var feedbackUpdates = 反馈更新提醒中心.shared
    @Namespace private var namespace
    @State private var showFeedbackSheet = false
    @State private var showTodayRecommendationSheet = false

    var body: some View {
        Menu {
            Button {
                showFeedbackSheet = true
            } label: {
                Label("反馈", systemImage: "exclamationmark.bubble")
            }

            Button {
                showTodayRecommendationSheet = true
            } label: {
                Label("参与Today", systemImage: "doc.text.image")
            }
        } label: {
            // 与工具栏按钮一致：30pt 图标区加上玻璃按钮的内边距正好是 44pt
            Image(systemName: "ellipsis.bubble")
                .frame(width: 30, height: 30)
                // 有反馈更新时显示红点，并在图标上挖出一圈空隙，不让红点压住线条
                .mask {
                    Rectangle()
                        .overlay(alignment: .topTrailing) {
                            if feedbackUpdates.提示 != nil {
                                Circle()
                                    .frame(width: 13, height: 13)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                }
                .overlay(alignment: .topTrailing) {
                    if feedbackUpdates.提示 != nil {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                            .padding(2.5)
                    }
                }
        }
        .matchedTransitionSource(id: "FeedbackSheet", in: namespace)
        .accessibilityLabel("反馈与参与")
        .accessibilityValue(feedbackUpdates.提示 ?? "")
        .sheet(isPresented: $showFeedbackSheet) {
            NavigationStack {
                反馈页面(
                    showsCloseButton: true,
                    closeAction: { showFeedbackSheet = false }
                )
            }
            // 数据维护的详情要编辑贡献的翻译，翻译页面读取登录状态
            .environmentObject(auth)
            .平台近全屏弹窗(dragIndicator: .hidden)
            .navigationTransition(.zoom(sourceID: "FeedbackSheet", in: namespace))
        }
        .sheet(isPresented: $showTodayRecommendationSheet) {
            Today推荐页面(vndbAccount: PaperAccount账户.shared.Today账户)
                .平台近全屏弹窗(dragIndicator: .hidden)
                .navigationTransition(.zoom(sourceID: "FeedbackSheet", in: namespace))
        }
    }
}

#if DEBUG
#Preview("反馈与参与菜单") {
    NavigationStack {
        Text("轻点左上角的按钮")
            .foregroundStyle(.secondary)
            .navigationTitle("资料库")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    反馈与参与菜单()
                }
            }
    }
    .预览环境()
}
#endif
