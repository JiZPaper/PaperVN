import SwiftUI

/// 启动时说明PaperVN改为“延迟免费”模式：一封信，看完一次后不再显示。
/// 这个版本启动时只弹出这封信，不弹出新功能介绍。
enum 延迟免费说明 {
    static let 已读键 = "PaperVN.delayedFreeNotice.seen"

    static var 应显示: Bool {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              !ProcessInfo.processInfo.arguments.contains("-PaperVNSkipDelayedFreeNotice") else {
            return false
        }
        return !UserDefaults.standard.bool(forKey: 已读键)
    }

    static func 标记已读() {
        UserDefaults.standard.set(true, forKey: 已读键)
    }

    /// 落款日期
    static let 落款日期 = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "Asia/Shanghai"),
        year: 2026, month: 10, day: 25, hour: 20
    ).date ?? .now
}

/// 启动时弹出的延迟免费说明。弹出期间Today不弹出每日简报：
/// 两边同时呈现时系统只会保留一个，另一个会被忽略。
@MainActor
@Observable
final class 开屏弹窗状态 {
    static let shared = 开屏弹窗状态()
    var 进行中 = 延迟免费说明.应显示
}

struct 延迟免费说明页面: View {
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("关于PaperVN采用“延迟免费”模式")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 8)
                        .accessibilityAddTraits(.isHeader)

                    Text(问候语)

                    Text("自发布以来，PaperVN已保持完全免费90天。事实上，在PaperVN发布之初便一直是如此计划的。但是随着功能增多，当前我每个月在PaperVN上的支出已接近1000 CNY。对于一名每个月只有2000 CNY生活费的学生来说，这已经超出了我预想的程度。因此，为了能在接下来4年中保持正常更新，PaperVN将采用“延迟免费”模式。现作如下说明：")

                    段落(
                        "“延迟免费”的含义",
                        "即在2030年12月1日前通过App Store更新逐步开放部分功能为免费功能，直至所有功能全部免费。"
                    )
                    段落(
                        "PaperVN不以盈利为目的",
                        "PaperVN的所有代码包括延迟免费功能遵循CC BY-SA 4.0许可协议开源。“PaperVN先行”订阅当前对于中国大陆地区定价为1.8元/月。"
                    )
                    段落(
                        "对于当前TestFlight用户与原PaperVN Premium用户",
                        "对于当前TestFlight版本用户依然保持稳定更新且完全免费。在TestFlight中完成支付流程不会产生费用；已购买PaperVN Premium的用户无需再进行任何付费。"
                    )

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("PaperVN支持")
                        Text(verbatim: 中西文间距.去除空格(
                            延迟免费说明.落款日期.formatted(date: .long, time: .omitted)
                        ))
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 16)
                }
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .平台柔和滚动边缘(for: .bottom)
            .平台安全区域栏(edge: .bottom) {
                继续按钮
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarVisibility(.visible, for: .navigationBar)
        }
        .interactiveDismissDisabled()
    }

    /// 和原信一样按时间问候。
    private var 问候语: LocalizedStringKey {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "早上好，"
        case 12..<18: "下午好，"
        default: "晚上好，"
        }
    }

    private func 段落(_ 标题: LocalizedStringKey, _ 正文: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(标题)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(正文)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var 继续按钮: some View {
        let 按钮 = Button {
            onFinish()
        } label: {
            Text("继续")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)

        if #available(iOS 26.0, *) {
            按钮.buttonStyle(.glassProminent)
        } else {
            按钮.buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    延迟免费说明页面 {}
}
