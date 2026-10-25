import Combine
import OSLog
import StoreKit
import SwiftUI

/// PaperVN Senkou 订阅：动画、漫画、轻小说相关功能采用“延迟免费”，2030年12月1日前逐步开放为免费。
/// 已购买 PaperVN Premium 的用户终身解锁（Premium 已停止销售）。
@MainActor
final class PaperVNSenkou中心: ObservableObject {
    static let shared = PaperVNSenkou中心()

    static let productID = "PaperVN_Senkou"

    private static let logger = Logger(subsystem: "com.jizpaper.PaperVN", category: "Senkou")

    @Published private(set) var 已解锁 = false
    /// 读取完购买记录之前不知道是否已解锁：同步要等它，界面先不显示付费页面。
    @Published private(set) var 已确认 = false
    /// 通过 PaperVN Premium 终身解锁（不是订阅）。
    @Published private(set) var 由Premium解锁 = false
    /// PaperVN Premium 已停止销售，只有已购买的用户能看到它的页面。
    @Published private(set) var 已购买Premium = false

    static let 隐藏设置键 = "hidesDelayedFreeFeatures"

    /// 用户选择了“隐藏所有延迟免费功能”。
    @Published var 已选择隐藏 = UserDefaults.standard.bool(forKey: 隐藏设置键) {
        didSet { UserDefaults.standard.set(已选择隐藏, forKey: Self.隐藏设置键) }
    }

    /// Today 不显示动画、漫画、轻小说，搜索不显示它们，资料库不能切换到它们。
    var 隐藏延迟免费功能: Bool { 已选择隐藏 && !已解锁 }

    #if DEBUG
    /// 只在 Xcode 运行的 Debug 版本里：不改真实购买记录，直接把解锁状态当作某一种，方便反复测试。
    enum 调试状态类型: String, CaseIterable, Identifiable {
        case 跟随AppStore = "", 已订阅 = "subscribed", 已购买Premium = "premium", 未订阅 = "locked"
        var id: Self { self }
    }

    private static let 调试状态键 = "SenkouDebugOverride"

    @Published var 调试状态: 调试状态类型 = {
        // 兼容启动参数 -SenkouUnlocked YES
        if UserDefaults.standard.bool(forKey: "SenkouUnlocked") { return .已订阅 }
        return 调试状态类型(rawValue: UserDefaults.standard.string(forKey: 调试状态键) ?? "") ?? .跟随AppStore
    }() {
        didSet {
            UserDefaults.standard.set(调试状态.rawValue, forKey: Self.调试状态键)
            Task { await 刷新() }
        }
    }
    #endif

    private var 更新任务: Task<Void, Never>?
    private var 确认等待: [CheckedContinuation<Void, Never>] = []

    private init() {
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            已解锁 = true
            已确认 = true
            return
        }
        更新任务 = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard case .verified(let transaction) = result,
                      transaction.productID == Self.productID else { continue }
                await transaction.finish()
                await self?.刷新()
            }
        }
        Task { await 刷新() }
    }

    /// 等到购买记录读取完毕，返回是否已解锁。
    func 确认解锁() async -> Bool {
        if !已确认 {
            await withCheckedContinuation { 确认等待.append($0) }
        }
        return 已解锁
    }

    func 刷新() async {
        guard 更新任务 != nil else { return }
        var subscribed = false
        var premium = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.productID:
                if transaction.expirationDate.map({ $0 > .now }) ?? true { subscribed = true }
            case PaperVNPremiumStore.productID:
                // Premium 已停止销售，买过的都是之前的用户
                premium = true
            default:
                break
            }
        }
        #if DEBUG
        switch 调试状态 {
        case .跟随AppStore: break
        case .已订阅: (subscribed, premium) = (true, false)
        case .已购买Premium: (subscribed, premium) = (false, true)
        case .未订阅: (subscribed, premium) = (false, false)
        }
        #endif
        let wasUnlocked = 已解锁
        let wasConfirmed = 已确认
        已解锁 = subscribed || premium
        由Premium解锁 = premium && !subscribed
        已购买Premium = premium
        已确认 = true
        确认等待.forEach { $0.resume() }
        确认等待.removeAll()
        if 已解锁, !wasUnlocked, wasConfirmed {
            Self.logger.info("PaperVN Senkou unlocked")
            // 刚解锁时同步一次动画、漫画、轻小说资料库
            Task { await PaperVNSync中心.shared.同步动画漫画() }
        }
    }
}

/// 已解锁时显示内容；未解锁时显示 PaperVN Senkou 的介绍与订阅。
struct PaperVNSenkou门控<Content: View>: View {
    @ObservedObject private var senkou = PaperVNSenkou中心.shared
    /// 订阅成功的动画播完之前仍显示订阅页面（动画挂在它上面）。
    @State private var 正在显示成功 = false
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if senkou.已解锁 && !正在显示成功 {
            content
        } else if senkou.已确认 {
            PaperVNSenkou订阅页面(
                开始成功动画: { 正在显示成功 = true },
                完成: { 正在显示成功 = false }
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 付费页面：标注“于2030年12月1日前免费”并说明延迟免费模式。
/// 不用 SubscriptionStoreView：要把“恢复订阅”放进条款那一行，主按钮下面放“隐藏所有延迟免费功能”。
struct PaperVNSenkou订阅页面: View {
    /// 选择隐藏后关闭页面（弹出页面与详情页）；设置里不关闭，方便再改回来。
    var 隐藏后关闭 = true
    /// 购买成功、播放成功动画之前调用：调用方在动画结束前不要换掉这个页面。
    var 开始成功动画: () -> Void = {}
    /// 成功动画播完或恢复成功后调用。
    var 完成: () -> Void = {}

    @ObservedObject private var senkou = PaperVNSenkou中心.shared
    @State private var 显示成功 = false
    @Environment(\.purchase) private var purchase
    @Environment(\.dismiss) private var dismiss
    @State private var product: Product?
    @State private var 可以免费试用 = false
    @State private var 载入失败 = false
    @State private var 正在购买 = false
    @State private var 正在恢复 = false
    @State private var 提示: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PaperVNSenkou说明()
                Text(String(localized: "订阅自动续期，可随时在App Store账户设置中取消。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .平台柔和滚动边缘(for: .bottom)
        .background(Color.平台系统背景.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            操作栏
        }
        .task {
            await 载入商品()
            // 恢复购买或在其他设备上购买后，回到页面时重新读取
            await senkou.刷新()
        }
        .平台全屏覆盖(isPresented: $显示成功) {
            PaperVNPremiumSuccessView(徽章: "已订阅PaperVN Senkou") {
                显示成功 = false
                完成()
            }
            .interactiveDismissDisabled()
        }
        .alert(
            String(localized: "PaperVN Senkou"),
            isPresented: Binding { 提示 != nil } set: { if !$0 { 提示 = nil } }
        ) {
            Button("好") { 提示 = nil }
        } message: {
            Text(verbatim: 提示 ?? "")
        }
    }

    private var 操作栏: some View {
        VStack(spacing: 12) {
            Button {
                Task { await 购买() }
            } label: {
                VStack(spacing: 0) {
                    if 正在购买 || (product == nil && !载入失败) {
                        ProgressView()
                    } else {
                        Text(verbatim: 按钮标题)
                            .font(.headline)
                        if let 按钮副标题 {
                            Text(verbatim: 按钮副标题)
                                .font(.caption)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .modifier(Senkou按钮样式(突出: true))
            .controlSize(.large)
            .disabled(product == nil || 正在购买 || 正在恢复)

            Button {
                withAnimation { senkou.已选择隐藏.toggle() }
                if senkou.已选择隐藏, 隐藏后关闭 { dismiss() }
            } label: {
                Text(String(localized: senkou.已选择隐藏 ? "显示所有延迟免费功能" : "隐藏所有延迟免费功能"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .modifier(Senkou按钮样式(突出: false))
            .controlSize(.large)

            PaperVNSenkou条款链接(恢复订阅: 正在恢复 ? nil : { Task { await 恢复() } })
                .padding(.top, 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var 按钮标题: String {
        guard let product else {
            return String(localized: "App Store商品暂时不可用，请稍后再试。")
        }
        if 可以免费试用, let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial {
            return String(localized: "免费试用\(Self.时长文本(offer.period))")
        }
        return String(localized: "订阅")
    }

    private var 按钮副标题: String? {
        guard let product, let period = product.subscription?.subscriptionPeriod else { return nil }
        let price = Self.每期价格(product.displayPrice, period)
        return 按钮标题 == String(localized: "订阅") ? price : String(localized: "之后\(price)")
    }

    /// “1个月”“2周”这样的时长。中日文去掉数字和单位之间的空格。
    private static func 时长文本(_ period: Product.SubscriptionPeriod) -> String {
        var components = DateComponents()
        switch period.unit {
        case .day: components.day = period.value
        case .week: components.weekOfMonth = period.value
        case .month: components.month = period.value
        case .year: components.year = period.value
        @unknown default: components.day = period.value
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.day, .weekOfMonth, .month, .year]
        return 中西文间距.去除空格(formatter.string(from: components) ?? "")
    }

    private static func 每期价格(_ price: String, _ period: Product.SubscriptionPeriod) -> String {
        guard period.value == 1 else {
            return String(localized: "\(price)/\(时长文本(period))")
        }
        switch period.unit {
        case .day: return String(localized: "\(price)/天")
        case .week: return String(localized: "\(price)/周")
        case .year: return String(localized: "\(price)/年")
        default: return String(localized: "\(price)/月")
        }
    }

    private func 载入商品() async {
        guard product == nil else { return }
        do {
            guard let loaded = try await Product.products(for: [PaperVNSenkou中心.productID]).first else {
                载入失败 = true
                return
            }
            可以免费试用 = await loaded.subscription?.isEligibleForIntroOffer ?? false
            product = loaded
        } catch {
            载入失败 = true
        }
    }

    private func 购买() async {
        guard let product else { return }
        正在购买 = true
        defer { 正在购买 = false }
        do {
            switch try await purchase(product) {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    提示 = String(localized: "购买验证失败，请稍后再试。")
                    return
                }
                await transaction.finish()
                开始成功动画()
                显示成功 = true
                await senkou.刷新()
            case .pending:
                提示 = String(localized: "购买正在等待App Store处理。")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            提示 = error.localizedDescription
        }
    }

    private func 恢复() async {
        正在恢复 = true
        defer { 正在恢复 = false }
        do {
            try await AppStore.sync()
            await senkou.刷新()
            if senkou.已解锁 {
                完成()
            } else {
                提示 = String(localized: "没有找到可恢复的订阅。")
            }
        } catch {
            提示 = error.localizedDescription
        }
    }
}

/// iOS 26 起用液态玻璃按钮，iOS 18 用有边框按钮。
struct Senkou按钮样式: ViewModifier {
    let 突出: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if 突出 {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if 突出 {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

/// “服务条款 · 隐私政策 · 恢复订阅”。
struct PaperVNSenkou条款链接: View {
    var 恢复订阅: (() -> Void)?

    private static let privacyPolicyURL = URL(string: "https://papervn.jizpaper.com/PrivacyPolicy.html")!
    private static let termsOfServiceURL = URL(string: "https://papervn.jizpaper.com/TermsOfService.html")!

    var body: some View {
        HStack(spacing: 6) {
            Link(String(localized: "服务条款"), destination: Self.termsOfServiceURL)
            分隔点
            Link(String(localized: "隐私政策"), destination: Self.privacyPolicyURL)
            if let 恢复订阅 {
                分隔点
                Button(String(localized: "恢复订阅"), action: 恢复订阅)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
        }
        .font(.footnote)
    }

    private var 分隔点: some View {
        Text(verbatim: "·")
            .foregroundStyle(.secondary)
    }
}

struct PaperVNSenkou说明: View {

    var body: some View {
        VStack(spacing: 16) {
            Image("PaperVNAppIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(String(localized: "PaperVN Senkou"))
                    .font(.title.bold())
                Text(String(localized: "于2030年12月1日前免费"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "为了PaperVN能在接下来4年中保持正常更新，PaperVN现采用“延迟免费”模式。即在2030年12月1日前App Store更新逐步开放部分功能为免费功能，直至所有功能全部免费。"))
                Text(String(localized: "所有代码遵循CC BY-SA 4.0许可协议开源，包括延迟免费功能。"))
                Text(String(localized: "当前已有功能不受影响。"))
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: 560)
    }
}

/// “账户与设置”里的 PaperVN Senkou：未解锁时订阅，已解锁时显示解锁方式，订阅用户可以管理订阅。
struct PaperVNSenkou设置页面: View {
    @ObservedObject private var senkou = PaperVNSenkou中心.shared
    @State private var 显示管理订阅 = false
    @State private var 正在显示成功 = false
    #if DEBUG
    @State private var 调试显示成功动画 = false
    @State private var 调试退款交易: UInt64?
    @State private var 调试显示退款 = false
    #endif

    var body: some View {
        Group {
            if !senkou.已确认 {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !senkou.已解锁 || 正在显示成功 {
                PaperVNSenkou订阅页面(
                    隐藏后关闭: false,
                    开始成功动画: { 正在显示成功 = true },
                    完成: { 正在显示成功 = false }
                )
            } else {
                ScrollView {
                    PaperVNSenkou说明()
                        .frame(maxWidth: .infinity)
                    .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .平台柔和滚动边缘(for: .bottom)
                .background(Color.平台系统背景.ignoresSafeArea())
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 12) {
                        // 与以前 PaperVN Premium 的“已购买”相同：绿色、液态玻璃胶囊
                        Label(
                            String(localized: senkou.由Premium解锁 ? "已购买PaperVN Premium" : "已订阅PaperVN Senkou"),
                            systemImage: "checkmark.seal.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .液态玻璃(.regular, in: Capsule())
                        .accessibilityElement(children: .combine)

                        if !senkou.由Premium解锁 {
                            Button {
                                显示管理订阅 = true
                            } label: {
                                Text(String(localized: "管理订阅"))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .modifier(Senkou按钮样式(突出: true))
                            .controlSize(.large)
                        }
                        PaperVNSenkou条款链接()
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .manageSubscriptionsSheet(isPresented: $显示管理订阅)
                .onChange(of: 显示管理订阅) { _, isPresented in
                    // 在管理订阅里取消或更改后重新读取
                    if !isPresented { Task { await senkou.刷新() } }
                }
            }
        }
        // 页面里已有大标题，导航栏不显示标题
        .平台内联导航标题()
        #if DEBUG
        .toolbar {
            ToolbarItem(placement: .平台主操作) {
                调试菜单
            }
        }
        .平台全屏覆盖(isPresented: $调试显示成功动画) {
            PaperVNPremiumSuccessView(徽章: "已订阅PaperVN Senkou") {
                调试显示成功动画 = false
            }
        }
        .refundRequestSheet(for: 调试退款交易 ?? 0, isPresented: $调试显示退款) { _ in
            Task { await senkou.刷新() }
        }
        #endif
    }
}

#if DEBUG
extension PaperVNSenkou设置页面 {
    /// 只在 Xcode 运行的 Debug 版本里显示。要恢复免费试用资格，仍需在 Xcode 的
    /// Debug → StoreKit → Manage Transactions 里删除交易。
    private var 调试菜单: some View {
        Menu {
            Picker(selection: $senkou.调试状态) {
                Text(verbatim: "跟随App Store").tag(PaperVNSenkou中心.调试状态类型.跟随AppStore)
                Text(verbatim: "当作已订阅").tag(PaperVNSenkou中心.调试状态类型.已订阅)
                Text(verbatim: "当作已购买Premium").tag(PaperVNSenkou中心.调试状态类型.已购买Premium)
                Text(verbatim: "当作未订阅").tag(PaperVNSenkou中心.调试状态类型.未订阅)
            } label: {
                Text(verbatim: "订阅状态")
            }
            .pickerStyle(.inline)

            Section {
                Button {
                    调试显示成功动画 = true
                } label: {
                    Label { Text(verbatim: "播放订阅成功动画") } icon: { Image(systemName: "checkmark.seal") }
                }
                Button {
                    Task {
                        guard case .verified(let transaction)? = await StoreKit.Transaction.latest(for: PaperVNSenkou中心.productID) else { return }
                        调试退款交易 = transaction.id
                        调试显示退款 = true
                    }
                } label: {
                    Label { Text(verbatim: "退款最近一次订阅") } icon: { Image(systemName: "arrow.uturn.backward") }
                }
                Button {
                    senkou.已选择隐藏 = false
                } label: {
                    Label { Text(verbatim: "取消“隐藏所有延迟免费功能”") } icon: { Image(systemName: "eye") }
                }
                .disabled(!senkou.已选择隐藏)
            }
        } label: {
            Label { Text(verbatim: "调试") } icon: { Image(systemName: "hammer") }
        }
    }
}
#endif

/// 进入动画、漫画、轻小说相关页面的链接：没有 PaperVN Senkou 时不推入页面，改为弹出订阅页面。
struct Senkou导航链接<Destination: View, Label: View>: View {
    @ObservedObject private var senkou = PaperVNSenkou中心.shared
    @State private var 显示订阅 = false
    private let 需要订阅: Bool
    private let zoomSourceID: AnyHashable?
    private let zoomNamespace: Namespace.ID?
    private let destination: () -> Destination
    private let label: Label

    /// `zoomSourceID`、`in` 与推入页面的缩放转场相同，订阅页面从同一个来源放大弹出。
    init(
        需要订阅: Bool = true,
        zoomSourceID: AnyHashable? = nil,
        in zoomNamespace: Namespace.ID? = nil,
        @ViewBuilder destination: @escaping () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        self.需要订阅 = 需要订阅
        self.zoomSourceID = zoomSourceID
        self.zoomNamespace = zoomNamespace
        self.destination = destination
        self.label = label()
    }

    var body: some View {
        if !需要订阅 || senkou.已解锁 {
            NavigationLink(destination: destination) { label }
        } else {
            Button {
                显示订阅 = true
            } label: {
                label
            }
            .Senkou订阅弹出(isPresented: $显示订阅, zoomSourceID: zoomSourceID, in: zoomNamespace)
        }
    }
}

extension View {
    /// 弹出 PaperVN Senkou 的订阅页面；订阅或恢复成功后自动关闭。
    func Senkou订阅弹出(
        isPresented: Binding<Bool>,
        zoomSourceID: AnyHashable? = nil,
        in zoomNamespace: Namespace.ID? = nil,
        onUnlock: @escaping () -> Void = {}
    ) -> some View {
        sheet(isPresented: isPresented) {
            Senkou订阅弹出页面(isPresented: isPresented, onUnlock: onUnlock)
                .平台近全屏弹窗(dragIndicator: .hidden)
                .modifier(Senkou缩放转场(sourceID: zoomSourceID, namespace: zoomNamespace))
        }
    }
}

private struct Senkou缩放转场: ViewModifier {
    let sourceID: AnyHashable?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let sourceID, let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private struct Senkou订阅弹出页面: View {
    @Binding var isPresented: Bool
    let onUnlock: () -> Void
    @ObservedObject private var senkou = PaperVNSenkou中心.shared
    @State private var 正在显示成功 = false

    var body: some View {
        NavigationStack {
            PaperVNSenkou订阅页面(
                开始成功动画: { 正在显示成功 = true },
                完成: 关闭
            )
                .toolbar {
                    ToolbarItem(placement: .平台关闭操作) {
                        Button {
                            isPresented = false
                        } label: {
                            Label("关闭", systemImage: "xmark")
                        }
                    }
                }
        }
        .onChange(of: senkou.已解锁) { _, unlocked in
            // 在其他地方解锁（例如家人共享、其他设备）时直接关闭；在这里购买的等成功动画播完
            guard unlocked, !正在显示成功 else { return }
            关闭()
        }
    }

    private func 关闭() {
        onUnlock()
        isPresented = false
    }
}

#Preview("订阅页面") {
    NavigationStack {
        PaperVNSenkou订阅页面()
    }
}
