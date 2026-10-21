import SwiftUI
import UIKit

/// 更新后弹出的匿名问卷：一页一个题目，部分题目根据上一题的回答决定是否出现。
/// 每份问卷只显示一次（提交或关闭都算），答案匿名发送到PaperVN服务器。
enum 进路调查 {
    /// 换一份问卷时改这里，服务器端 `surveys.mjs` 的题目定义也要同步。
    static let 问卷编号 = "2026.10"
    /// 弹窗关闭过（提交或直接关闭）就不再自动弹出。
    static let 已完成问卷键 = "PaperVN.survey.completedID"
    /// 关闭但没提交时，Today顶部显示横幅，可以随时再进入。
    static let 已提交问卷键 = "PaperVN.survey.submittedID"
    private static let 待提交键 = "PaperVN.survey.pendingResponse"
    private static let 提交地址 = URL(string: "https://papervn.jizpaper.com/api/surveys/responses")!

    static var 应显示: Bool {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1",
              !ProcessInfo.processInfo.arguments.contains("-PaperVNSkipWhatsNew"),
              !ProcessInfo.processInfo.arguments.contains("-PaperVNSkipSurvey") else {
            return false
        }
        return UserDefaults.standard.string(forKey: 已完成问卷键) != 问卷编号
    }

    static func 标记已完成() {
        UserDefaults.standard.set(问卷编号, forKey: 已完成问卷键)
    }

    /// 先存到本地再发送，发送失败时下次启动重试。
    static func 提交(_ 答案: [进路调查问题: 进路调查回答], 页面: [进路调查问题]) {
        var 回答 = [String: 进路调查请求.回答]()
        for 问题 in 页面 {
            guard let 答 = 答案[问题], !答.选项.isEmpty else { continue }
            let 其他 = 答.其他说明.trimmingCharacters(in: .whitespacesAndNewlines)
            回答[问题.rawValue] = 进路调查请求.回答(
                choices: 问题.选项.map(\.id).filter(答.选项.contains),
                other: 答.选项.contains(进路调查选项.其他编号) && !其他.isEmpty
                    ? String(其他.prefix(进路调查回答.说明字数上限))
                    : nil
            )
        }

        let 请求 = 进路调查请求(
            surveyID: 问卷编号,
            responseID: UUID().uuidString,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            platform: 当前平台,
            language: Bundle.main.preferredLocalizations.first ?? "zh-Hans",
            answers: 回答
        )
        guard let 数据 = try? JSONEncoder().encode(请求) else { return }
        UserDefaults.standard.set(数据, forKey: 待提交键)
        UserDefaults.standard.set(问卷编号, forKey: 已提交问卷键)
        发送待提交答案()
    }

    static func 发送待提交答案() {
        guard let 数据 = UserDefaults.standard.data(forKey: 待提交键) else { return }
        Task {
            var 请求 = URLRequest(url: 提交地址)
            请求.httpMethod = "POST"
            请求.setValue("application/json", forHTTPHeaderField: "Content-Type")
            请求.timeoutInterval = 20
            guard let (_, 响应) = try? await URLSession.shared.upload(for: 请求, from: 数据),
                  let 状态码 = (响应 as? HTTPURLResponse)?.statusCode else {
                return
            }
            // 400 说明这份答案本身有问题，重试也不会成功；
            // 404 等其他错误可能是服务器还没部署问卷，留到下次启动再试
            if (200..<300).contains(状态码) || 状态码 == 400,
               UserDefaults.standard.data(forKey: 待提交键) == 数据 {
                UserDefaults.standard.removeObject(forKey: 待提交键)
            }
        }
    }

    private static var 当前平台: String {
        if ProcessInfo.processInfo.isiOSAppOnMac { return "Mac" }
        switch UIDevice.current.userInterfaceIdiom {
        case .pad: return "iPad"
        case .vision: return "Vision"
        default: return "iPhone"
        }
    }
}

private struct 进路调查请求: Encodable {
    struct 回答: Encodable {
        let choices: [String]
        let other: String?
    }

    let surveyID: String
    let responseID: String
    let appVersion: String
    let build: String
    let platform: String
    let language: String
    let answers: [String: 回答]
}

struct 进路调查回答: Equatable {
    static let 说明字数上限 = 200

    var 选项: Set<String> = []
    var 其他说明 = ""
}

struct 进路调查选项: Identifiable {
    static let 其他编号 = "other"

    let id: String
    let 标题: Text

    init(_ id: String, _ 标题: LocalizedStringKey) {
        self.id = id
        self.标题 = Text(标题)
    }

    /// 网站名称等专有名词不翻译。
    init(_ id: String, verbatim 标题: String) {
        self.id = id
        self.标题 = Text(verbatim: 标题)
    }

    static let 是 = 进路调查选项("yes", "是")
    static let 否 = 进路调查选项("no", "否")
    static let 其他 = 进路调查选项(其他编号, "其他")
}

/// rawValue 是服务器端的题目编号，选项的 id 同理，改动时两边要一致。
enum 进路调查问题: String, CaseIterable {
    case 记录习惯 = "tracksProgress"
    case 记录网站 = "trackingSites"
    case 第三方App = "usesThirdPartyApp"
    case 付费App = "thirdPartyAppPaid"
    case 移动设备游玩 = "playsOnMobile"
    case 更多功能 = "moreFeatures"
    case 升级系统 = "upgradedToOS27"
    case 未升级原因 = "notUpgradedReasons"
    case 升级原因 = "upgradedReasons"

    var 题目: LocalizedStringKey {
        switch self {
        case .记录习惯: "你有记录动画、漫画、轻小说观看/阅读状态的习惯吗？"
        case .记录网站: "你常使用什么网站记录这些？"
        case .第三方App: "你是否已经在使用第三方App来更改记录？"
        case .付费App: "它们之中有付费App吗？"
        case .移动设备游玩: "你常在iPhone或iPad上游玩视觉小说吗？"
        case .更多功能: "如果PaperVN要加入更多主要功能，你希望怎么做？"
        case .升级系统: "你升级到OS 27了吗？"
        case .未升级原因, .升级原因: "为什么？"
        }
    }

    var 多选: Bool {
        switch self {
        case .记录网站, .未升级原因, .升级原因: true
        default: false
        }
    }

    var 选项: [进路调查选项] {
        switch self {
        case .记录网站:
            [
                进路调查选项("bangumi", "Bangumi番组计划"),
                进路调查选项("myanimelist", verbatim: "MyAnimeList"),
                进路调查选项("anilist", verbatim: "AniList"),
                进路调查选项("kitsu", verbatim: "Kitsu"),
                进路调查选项("animeplanet", verbatim: "Anime-Planet"),
                进路调查选项("annict", verbatim: "Annict"),
                进路调查选项("simkl", verbatim: "Simkl"),
                进路调查选项("trakt", verbatim: "Trakt"),
                进路调查选项("tmdb", verbatim: "TMDB"),
                进路调查选项("tvdb", verbatim: "TVDB"),
                进路调查选项("novelupdates", verbatim: "Novel Updates"),
                进路调查选项("douban", "豆瓣"),
                .其他
            ]
        case .更多功能:
            [
                进路调查选项("separate", "分离为多个App"),
                进路调查选项("merge", "与当前App合并")
            ]
        case .未升级原因:
            [
                进路调查选项("ugly", "UI太丑了"),
                进路调查选项("factory", "我认为出厂系统就是最好的"),
                进路调查选项("lazy", "懒得更新"),
                .其他
            ]
        case .升级原因:
            [
                进路调查选项("automatic", "自动更新"),
                进路调查选项("earlyAdopter", "我喜欢尝鲜"),
                进路调查选项("os26", "OS 26华而不实"),
                进路调查选项("watch", "Apple Watch要求我更新系统"),
                .其他
            ]
        case .记录习惯, .第三方App, .付费App, .移动设备游玩, .升级系统:
            [.是, .否]
        }
    }

    /// 根据已有的回答决定要问哪些题目。
    /// 决定分支的题目还没回答时按需要追问来计算，页数指示和“继续”按钮不会在回答后突然变化。
    static func 页面(答案: [Self: 进路调查回答]) -> [Self] {
        func 不是否(_ 问题: Self) -> Bool {
            答案[问题]?.选项.contains(进路调查选项.否.id) != true
        }

        var 页面: [Self] = [.记录习惯]
        if 不是否(.记录习惯) {
            页面 += [.记录网站, .第三方App]
            if 不是否(.第三方App) {
                页面.append(.付费App)
            }
        }
        页面 += [.移动设备游玩, .更多功能, .升级系统]
        页面.append(不是否(.升级系统) ? .升级原因 : .未升级原因)
        return 页面
    }
}

struct 进路调查页面: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var 答案: [进路调查问题: 进路调查回答] = [:]
    @State private var 序号 = 0
    /// 换页方向：向后翻时新页面从右侧进入，返回时从左侧进入。
    @State private var 向后翻页 = true

    private var 页面: [进路调查问题] { 进路调查问题.页面(答案: 答案) }
    private var 当前问题: 进路调查问题 { 页面[min(序号, 页面.count - 1)] }
    private var 是最后一页: Bool { 序号 >= 页面.count - 1 }
    private var 已回答: Bool { 答案[当前问题]?.选项.isEmpty == false }

    var body: some View {
        NavigationStack {
            ZStack {
                进路调查单页(
                    问题: 当前问题,
                    是第一页: 序号 == 0,
                    回答: Binding {
                        答案[当前问题] ?? 进路调查回答()
                    } set: {
                        答案[当前问题] = $0
                    }
                )
                .id(当前问题)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .move(edge: 向后翻页 ? .trailing : .leading),
                            removal: .move(edge: 向后翻页 ? .leading : .trailing)
                        )
                )
            }
            .平台柔和滚动边缘(for: .bottom)
            .平台安全区域栏(edge: .bottom) {
                VStack(spacing: 14) {
                    页数指示
                    继续按钮
                        .frame(maxWidth: 320)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            // 第一页没有返回按钮，导航栏也要保持显示，否则文字会比其他页面高
            .toolbarVisibility(.visible, for: .navigationBar)
            .toolbar {
                if 序号 > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            翻页(到: 序号 - 1)
                        } label: {
                            Label("上一页", systemImage: "chevron.backward")
                        }
                    }
                }
                ToolbarItem(placement: .平台关闭操作) {
                    Button(role: .cancel) {
                        onFinish()
                    } label: {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var 页数指示: some View {
        HStack(spacing: 8) {
            ForEach(页面.indices, id: \.self) { 位置 in
                Capsule()
                    .fill(位置 == 序号 ? Color.primary : Color.secondary.opacity(0.35))
                    .frame(width: 位置 == 序号 ? 20 : 8, height: 8)
            }
        }
        .animation(.smooth(duration: 0.3), value: 序号)
        .animation(.smooth(duration: 0.3), value: 页面.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("第\(序号 + 1)页，共\(页面.count)页"))
    }

    @ViewBuilder
    private var 继续按钮: some View {
        let 按钮 = Button {
            if 是最后一页 {
                进路调查.提交(答案, 页面: 页面)
                onFinish()
            } else {
                翻页(到: 序号 + 1)
            }
        } label: {
            Text(是最后一页 ? "提交" : "继续")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(!已回答)

        if #available(iOS 26.0, *) {
            按钮.buttonStyle(.glassProminent)
        } else {
            按钮.buttonStyle(.borderedProminent)
        }
    }

    /// 先更新方向，下一帧再换页，原因见 `新功能介绍页面.翻页(到:)`。
    private func 翻页(到 目标: Int) {
        guard 页面.indices.contains(目标), 目标 != 序号 else { return }
        向后翻页 = 目标 > 序号
        Task { @MainActor in
            withAnimation(.smooth(duration: 0.4)) {
                序号 = 目标
            }
        }
    }
}

private struct 进路调查单页: View {
    let 问题: 进路调查问题
    let 是第一页: Bool
    @Binding var 回答: 进路调查回答

    @FocusState private var 正在输入说明: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    if 是第一页 {
                        Text("PaperVN进路调查")
                            .font(.headline)
                            .foregroundStyle(.tint)
                    }

                    Text(问题.题目)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)

                if 问题.多选 {
                    Text("可以选择多项。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                选项列表
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // 与新功能介绍相同的底部淡出
        .mask {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.2), location: 0.25),
                            .init(color: .black.opacity(0.06), location: 0.55),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: proxy.safeAreaInsets.bottom + 24)
                }
                .ignoresSafeArea()
            }
        }
    }

    private var 选项列表: some View {
        VStack(spacing: 0) {
            ForEach(Array(问题.选项.enumerated()), id: \.element.id) { 位置, 选项 in
                if 位置 > 0 {
                    Divider().padding(.leading, 16)
                }
                选项行(选项)
                if 选项.id == 进路调查选项.其他编号, 回答.选项.contains(选项.id) {
                    Divider().padding(.leading, 16)
                    其他说明输入框
                        .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: 回答.选项.contains(进路调查选项.其他编号))
        .background(
            Color.演示区域背景,
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
    }

    private var 其他说明输入框: some View {
        TextField("请说明（可选）", text: $回答.其他说明, axis: .vertical)
            .lineLimit(1...4)
            .focused($正在输入说明)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .onChange(of: 回答.其他说明) { _, 新值 in
                if 新值.count > 进路调查回答.说明字数上限 {
                    回答.其他说明 = String(新值.prefix(进路调查回答.说明字数上限))
                }
            }
    }

    private func 选项行(_ 选项: 进路调查选项) -> some View {
        let 已选中 = 回答.选项.contains(选项.id)
        return Button {
            选择(选项)
        } label: {
            HStack(spacing: 12) {
                选项.标题
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if 问题.多选 {
                    Image(systemName: 已选中 ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(已选中 ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .opacity(已选中 ? 1 : 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(已选中 ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: 已选中)
    }

    private func 选择(_ 选项: 进路调查选项) {
        var 选项集合 = 回答.选项
        if !问题.多选 {
            选项集合 = [选项.id]
        } else if 选项集合.contains(选项.id) {
            选项集合.remove(选项.id)
        } else {
            选项集合.insert(选项.id)
        }
        if !选项集合.contains(进路调查选项.其他编号) {
            正在输入说明 = false
        }
        回答.选项 = 选项集合
    }
}

#Preview("进路调查") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            进路调查页面 {}
        }
}

#if DEBUG
extension 进路调查页面 {
    /// 预览用：带着已有的回答，从指定的题目开始显示。
    init(预览答案: [进路调查问题: 进路调查回答], 问题: 进路调查问题, onFinish: @escaping () -> Void) {
        self.init(onFinish: onFinish)
        _答案 = State(initialValue: 预览答案)
        _序号 = State(initialValue: 进路调查问题.页面(答案: 预览答案).firstIndex(of: 问题) ?? 0)
    }
}

#Preview("进路调查：各题") {
    let 是 = 进路调查回答(选项: [进路调查选项.是.id])
    let 否 = 进路调查回答(选项: [进路调查选项.否.id])
    let 题目: [(String, 进路调查问题, [进路调查问题: 进路调查回答])] = [
        ("记录习惯", .记录习惯, [:]),
        ("记录网站（多选）", .记录网站, [.记录习惯: 是, .记录网站: 进路调查回答(选项: ["bangumi", "myanimelist", "anilist"])]),
        ("第三方App", .第三方App, [.记录习惯: 是]),
        ("付费App", .付费App, [.记录习惯: 是, .第三方App: 是]),
        ("移动设备游玩", .移动设备游玩, [.记录习惯: 否]),
        ("更多功能", .更多功能, [.记录习惯: 否, .移动设备游玩: 是]),
        ("升级系统", .升级系统, [.记录习惯: 否, .移动设备游玩: 是, .更多功能: 进路调查回答(选项: ["merge"])]),
        ("升级原因", .升级原因, [.记录习惯: 否, .升级系统: 是]),
        ("未升级原因（填写其他）", .未升级原因, [
            .记录习惯: 否,
            .升级系统: 否,
            .未升级原因: 进路调查回答(选项: ["lazy", 进路调查选项.其他编号], 其他说明: "等正式版稳定一些再更新"),
        ]),
    ]
    预览状态切换(题目.map { 名称, 问题, 答案 in
        .init(名称) { 进路调查页面(预览答案: 答案, 问题: 问题) {} }
    })
}
#endif
