import SwiftUI

/// “反馈与参与”菜单：反馈、贡献翻译、参与Today。显示在资料库左上角。
struct 反馈与参与菜单: View {
    @EnvironmentObject private var auth: 用户登录
    @Namespace private var namespace
    @State private var showFeedbackSheet = false
    @State private var showTranslationContributionSheet = false
    @State private var showTodayRecommendationSheet = false

    var body: some View {
        Menu {
            Button {
                showFeedbackSheet = true
            } label: {
                Label("反馈", systemImage: "exclamationmark.bubble")
            }

            Button {
                showTranslationContributionSheet = true
            } label: {
                Label("贡献翻译", systemImage: "character.bubble")
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
        }
        .matchedTransitionSource(id: "FeedbackSheet", in: namespace)
        .accessibilityLabel("反馈与参与")
        .sheet(isPresented: $showFeedbackSheet) {
            NavigationStack {
                反馈页面(
                    showsCloseButton: true,
                    closeAction: { showFeedbackSheet = false }
                )
            }
            .平台近全屏弹窗(dragIndicator: .hidden)
            .navigationTransition(.zoom(sourceID: "FeedbackSheet", in: namespace))
        }
        .sheet(isPresented: $showTranslationContributionSheet) {
            简介翻译贡献页面(auth: auth)
                .平台近全屏弹窗(dragIndicator: .hidden)
                .navigationTransition(.zoom(sourceID: "FeedbackSheet", in: namespace))
        }
        .sheet(isPresented: $showTodayRecommendationSheet) {
            Today推荐页面(vndbAccount: auth.vndb账户)
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
