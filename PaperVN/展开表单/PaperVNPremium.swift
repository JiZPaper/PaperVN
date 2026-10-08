import Combine
import Foundation
import OSLog
import StoreKit
import SwiftUI

extension Notification.Name {
    static let paperVNLibraryDidChange = Notification.Name(
        "PaperVN.libraryDidChange"
    )
    static let paperVNRecommendationsDidUpdate = Notification.Name(
        "PaperVN.recommendationsDidUpdate"
    )
}

@MainActor
final class PaperVNPremiumStore: ObservableObject {
    static let productID = "PaperVN_Premium"

    private static let logger = Logger(
        subsystem: "com.jizpaper.PaperVN",
        category: "StoreKit"
    )

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isEntitlementResolved = false
    @Published private(set) var hasAttemptedProductLoad = false
    @Published private(set) var productLoadError: String?
    @Published var errorMessage: String?
    @Published private(set) var statusMessage: String?

    private let isPreviewing: Bool
    private let previewDisplayPrice: String?

    private var transactionUpdatesTask: Task<Void, Never>?

    var isProductAvailable: Bool {
        product != nil || previewDisplayPrice != nil
    }

    var displayPrice: String? {
        previewDisplayPrice ?? product?.displayPrice
    }

    init(previewing: Bool = false) {
        let isRunningForPreviews = ProcessInfo.processInfo.environment[
            "XCODE_RUNNING_FOR_PREVIEWS"
        ] == "1"
        isPreviewing = previewing || isRunningForPreviews
        previewDisplayPrice = isPreviewing ? "¥18.00" : nil

        guard !isPreviewing else {
            isEntitlementResolved = true
            hasAttemptedProductLoad = true
            return
        }

        transactionUpdatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handleTransaction(result)
            }
        }

        Task { await loadProduct() }
        Task { await refreshEntitlement() }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func loadProductIfNeeded() async {
        guard product == nil else { return }

        if isLoadingProduct {
            while isLoadingProduct {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
            }
            guard product == nil else { return }
        }

        await loadProduct()
    }

    func reloadProduct() async {
        await loadProduct()
    }

    func refreshForActiveScene() async {
        guard !isPreviewing else { return }
        await refreshEntitlement()
        guard product == nil else { return }
        await loadProduct()
    }

    @discardableResult
    func purchase() async -> Bool {
        guard !isPurchasing, !isRestoring else { return false }

        if isPreviewing {
            isPurchasing = true
            defer { isPurchasing = false }
            try? await Task.sleep(for: .milliseconds(450))
            isPurchased = true
            isEntitlementResolved = true
            return true
        }

        guard let product else {
            errorMessage = productLoadError ?? String(
                localized: "App Store商品暂时不可用，请稍后再试。"
            )
            return false
        }

        isPurchasing = true
        statusMessage = nil
        defer { isPurchasing = false }

        do {
            switch try await product.purchase() {
            case .success(let verificationResult):
                let transaction = try verified(verificationResult)
                guard transaction.productID == Self.productID else {
                    throw StoreError.unexpectedProduct
                }
                isPurchased = transaction.revocationDate == nil
                isEntitlementResolved = true
                await transaction.finish()
                return isPurchased

            case .userCancelled:
                return false

            case .pending:
                statusMessage = String(localized: "购买正在等待App Store处理。")
                return false

            @unknown default:
                throw StoreError.purchaseFailed
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restorePurchases() async -> Bool {
        guard !isRestoring, !isPurchasing else { return false }
        isRestoring = true
        statusMessage = nil
        defer { isRestoring = false }

        if isPreviewing {
            try? await Task.sleep(for: .milliseconds(450))
            isPurchased = true
            isEntitlementResolved = true
            return true
        }

        do {
            try await AppStore.sync()
            await refreshEntitlement()
            guard isPurchased else {
                statusMessage = String(localized: "没有找到PaperVN Premium的购买记录。")
                return false
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func loadProduct(maxAttempts: Int = 3) async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        hasAttemptedProductLoad = true
        productLoadError = nil
        statusMessage = nil
        defer { isLoadingProduct = false }

        var finalErrorMessage = String(
            localized: "App Store商品暂时不可用，请稍后再试。"
        )

        for attempt in 1...maxAttempts {
            do {
                let products = try await Product.products(for: [Self.productID])
                if let loadedProduct = products.first(where: {
                    $0.id == Self.productID
                }) {
                    product = loadedProduct
                    productLoadError = nil
                    return
                }

                finalErrorMessage = String(
                    localized: "App Store商品暂时不可用，请稍后再试。"
                )
                Self.logger.error(
                    "Product request attempt \(attempt, privacy: .public) returned no item for ID \(Self.productID, privacy: .public)"
                )
            } catch is CancellationError {
                return
            } catch {
                finalErrorMessage = String(
                    localized: "无法连接App Store，请检查网络后再试。"
                )
                Self.logger.error(
                    "Product request attempt \(attempt, privacy: .public) failed for ID \(Self.productID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }

            guard attempt < maxAttempts else { break }
            do {
                try await Task.sleep(for: .milliseconds(700 * attempt))
            } catch {
                return
            }
        }

        product = nil
        productLoadError = finalErrorMessage
    }

    private func refreshEntitlement() async {
        var ownsPremium = false

        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID else {
                continue
            }
            if transaction.revocationDate == nil {
                ownsPremium = true
            }
        }

        isPurchased = ownsPremium
        isEntitlementResolved = true
    }

    private func handleTransaction(
        _ result: VerificationResult<StoreKit.Transaction>
    ) async {
        guard case .verified(let transaction) = result,
              transaction.productID == Self.productID else {
            return
        }

        isPurchased = transaction.revocationDate == nil
        isEntitlementResolved = true
        await transaction.finish()
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified:
            throw StoreError.failedVerification
        }
    }

    private enum StoreError: LocalizedError {
        case failedVerification
        case purchaseFailed
        case unexpectedProduct

        var errorDescription: String? {
            switch self {
            case .failedVerification:
                return String(localized: "购买验证失败，请稍后再试。")
            case .purchaseFailed:
                return String(localized: "购买未完成，请稍后再试。")
            case .unexpectedProduct:
                return String(localized: "返回的商品与PaperVN Premium不匹配。")
            }
        }
    }
}

struct PaperVNPremiumView: View {
    @EnvironmentObject private var store: PaperVNPremiumStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false
    @State private var isShowingSuccess = false
    @State private var 内容宽度: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 56)
            .frame(maxWidth: PremiumMetrics.contentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .平台柔和滚动边缘(for: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.平台系统背景.ignoresSafeArea())
        .平台内联导航标题()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            purchaseBar
        }
        .task {
            await store.loadProductIfNeeded()
        }
        // 宽度稳定后再开始入场动画：作为弹窗（尤其是弹窗上的弹窗）出现时宽度会先变化，
        // 立即动画会把文字重新排版也一起动画，文字会斜着飞进来
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { 新宽度 in
            内容宽度 = 新宽度
        }
        .task(id: 内容宽度) {
            guard 内容宽度 > 0 else { return }
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            revealContent()
        }
        .alert(
            "购买遇到问题",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { isPresented in
                    if !isPresented { store.clearError() }
                }
            )
        ) {
            Button("好") {
                store.clearError()
            }
        } message: {
            Text(verbatim: store.errorMessage ?? "")
        }
        .平台全屏覆盖(isPresented: $isShowingSuccess) {
            PaperVNPremiumSuccessView {
                isShowingSuccess = false
            }
            .interactiveDismissDisabled()
        }
        .tint(PremiumPalette.action)
    }

    private var hero: some View {
        VStack(spacing: 24) {
            PremiumMark()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.92)
                .animation(
                    revealAnimation(delay: 0.04),
                    value: hasAppeared
                )

            Text("PaperVN Premium")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 8)
                .animation(
                    revealAnimation(delay: 0.12),
                    value: hasAppeared
                )

            Text(
                "我是一名即将进入大学的高中毕业生，当前我的主力机是一台3000元的丐版Mac mini。你的购买将支持我在2028年换一台更好的Mac，并继续认真维护PaperVN。"
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 520)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
            .animation(
                focusAnimation(delay: 0.2),
                value: hasAppeared
            )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            if store.isPurchased {
                purchasedBadge
            } else {
                purchaseButton
            }

            if let message = purchaseStatusMessage {
                purchaseStatus(message)
            }

            purchaseFooter
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 7)
        .frame(maxWidth: PremiumMetrics.purchaseBarWidth)
        .frame(maxWidth: .infinity)
        .opacity(hasAppeared ? 1 : 0)
        .blur(radius: hasAppeared ? 0 : 10)
        .scaleEffect(x: hasAppeared ? 1 : 0.86, y: 1)
        .animation(
            focusAnimation(delay: 0.42),
            value: hasAppeared
        )
    }

    private var purchaseButton: some View {
        Button {
            Task {
                if await store.purchase() {
                    isShowingSuccess = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                if store.isPurchasing || store.isLoadingProduct {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                }

                HStack(spacing: 0) {
                    Text(purchaseButtonTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    if let displayPrice = purchaseDisplayPrice {
                        Text(verbatim: "・")

                        Text(verbatim: displayPrice)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            .font(.headline)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22)
        }
        .液态玻璃醒目按钮(in: Capsule())
        .tint(.blue)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(
            !store.isProductAvailable
                || store.isPurchasing
                || store.isRestoring
                || store.isLoadingProduct
        )
        .frame(maxWidth: PremiumMetrics.primaryButtonWidth)
    }

    private var purchasedBadge: some View {
        Label("已购买PaperVN Premium", systemImage: "checkmark.seal.fill")
            .font(.headline)
            .foregroundStyle(.green)
            .padding(.horizontal, 18)
            .frame(maxWidth: PremiumMetrics.primaryButtonWidth, minHeight: 52)
            .液态玻璃(.regular, in: Capsule())
            .accessibilityElement(children: .combine)
    }

    private func purchaseStatus(_ message: String) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: message)
                .multilineTextAlignment(.center)

            if !store.isProductAvailable,
               store.hasAttemptedProductLoad,
               !store.isLoadingProduct {
                Button {
                    Task { await store.reloadProduct() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("重试")
                .help("重试")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var purchaseFooter: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                restoreButton
                policyLinks
            }

            VStack(spacing: 8) {
                restoreButton
                policyLinks
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var restoreButton: some View {
        Button {
            Task {
                if await store.restorePurchases() {
                    isShowingSuccess = true
                }
            }
        } label: {
            HStack(spacing: 5) {
                if store.isRestoring {
                    ProgressView()
                        .controlSize(.mini)
                }

                Text(restoreButtonTitle)
                    .lineLimit(1)
            }
            .frame(minHeight: 22)
        }
        .buttonStyle(.plain)
        .disabled(store.isRestoring || store.isPurchasing)
    }

    private var policyLinks: some View {
        HStack(spacing: 18) {
            Link("隐私政策", destination: Self.privacyPolicyURL)
                .lineLimit(1)
            Link("服务条款", destination: Self.termsOfServiceURL)
                .lineLimit(1)
        }
    }

    private var purchaseButtonTitle: LocalizedStringKey {
        if store.isLoadingProduct {
            return "正在连接App Store…"
        }
        if store.isPurchasing {
            return "正在处理…"
        }
        if store.isProductAvailable {
            return "支持PaperVN"
        }
        return "暂时无法购买"
    }

    private var restoreButtonTitle: LocalizedStringKey {
        store.isRestoring ? "正在恢复…" : "恢复购买"
    }

    private var purchaseDisplayPrice: String? {
        guard !store.isLoadingProduct, !store.isPurchasing else { return nil }
        return store.displayPrice
    }

    private var purchaseStatusMessage: String? {
        store.productLoadError ?? store.statusMessage
    }

    private func revealContent() {
        guard !hasAppeared else { return }
        if reduceMotion {
            hasAppeared = true
        } else {
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78)) {
                hasAppeared = true
            }
        }
    }

    private func revealAnimation(delay: Double) -> Animation? {
        guard !reduceMotion else { return nil }
        return .smooth(duration: 0.62)
            .delay(delay)
    }

    private func focusAnimation(delay: Double) -> Animation? {
        guard !reduceMotion else { return nil }
        return .smooth(duration: 0.62)
            .delay(delay)
    }

    private static let privacyPolicyURL = URL(
        string: "https://papervn.jizpaper.com/PrivacyPolicy.html"
    )!
    private static let termsOfServiceURL = URL(
        string: "https://papervn.jizpaper.com/TermsOfService.html"
    )!
}

private struct PremiumMark: View {
    var body: some View {
        Image("PaperVNAppIcon")
            .resizable()
            .scaledToFit()
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}

private struct PaperVNPremiumSuccessView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onDone: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                PremiumSuccessMark(isComplete: hasAppeared)
                    .frame(width: 148, height: 148)
                    .accessibilityHidden(true)

                Text("感谢你的支持")
                    .font(
                        .system(
                            .largeTitle,
                            design: .rounded,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .opacity(hasAppeared ? 1 : 0)
                    .blur(radius: hasAppeared ? 0 : 12)
                    .scaleEffect(hasAppeared ? 1 : 1.1)
                    .rotation3DEffect(
                        .degrees(hasAppeared ? 0 : 16),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.45
                    )
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.82, dampingFraction: 0.74)
                                .delay(0.28),
                        value: hasAppeared
                    )

                Label(
                    "已购买PaperVN Premium",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.headline)
                .foregroundStyle(.green)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .opacity(hasAppeared ? 1 : 0)
                .blur(radius: hasAppeared ? 0 : 10)
                .scaleEffect(hasAppeared ? 1 : 1.08)
                .rotation3DEffect(
                    .degrees(hasAppeared ? 0 : 14),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.45
                )
                .animation(
                    reduceMotion
                        ? nil
                        : .spring(response: 0.82, dampingFraction: 0.76)
                            .delay(0.44),
                    value: hasAppeared
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 64)
            .frame(maxWidth: PremiumMetrics.contentWidth)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
                max(length, 480)
            }
            .accessibilityElement(children: .combine)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.平台系统背景.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            completionBar
        }
        .sensoryFeedback(.success, trigger: hasAppeared)
        .onAppear {
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(.spring(response: 0.78, dampingFraction: 0.72)) {
                    hasAppeared = true
                }
            }
        }
        .tint(PremiumPalette.action)
    }

    private var completionBar: some View {
        Button(action: onDone) {
            Text("完成")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .液态玻璃醒目按钮(in: Capsule())
        .tint(.blue)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .frame(maxWidth: PremiumMetrics.primaryButtonWidth)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity)
    }
}

private struct PremiumSuccessMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isComplete: Bool

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: isComplete ? 1 : 0.02)
                .stroke(
                    PremiumPalette.successGradient,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .padding(8)
                .rotationEffect(.degrees(isComplete ? 270 : -90))
                .animation(
                    reduceMotion
                        ? nil
                        : .smooth(duration: 1.05),
                    value: isComplete
                )

            Circle()
                .fill(.clear)
                .padding(17)
                .液态玻璃(.regular, in: Circle())

            PremiumCheckmarkShape()
                .trim(from: 0, to: isComplete ? 1 : 0)
                .stroke(
                    PremiumPalette.successGradient,
                    style: StrokeStyle(
                        lineWidth: 8,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: 62, height: 52)
                .animation(
                    reduceMotion
                        ? nil
                        : .smooth(duration: 0.58).delay(0.34),
                    value: isComplete
                )
        }
        .scaleEffect(isComplete ? 1 : 0.78)
        .opacity(isComplete ? 1 : 0)
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.74, dampingFraction: 0.76),
            value: isComplete
        )
        .shadow(
            color: Color.green.opacity(0.2),
            radius: 24,
            y: 14
        )
    }
}

private struct PremiumCheckmarkShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(
            to: CGPoint(
                x: rect.minX + rect.width * 0.08,
                y: rect.minY + rect.height * 0.52
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.38,
                y: rect.minY + rect.height * 0.84
            )
        )
        path.addLine(
            to: CGPoint(
                x: rect.minX + rect.width * 0.92,
                y: rect.minY + rect.height * 0.14
            )
        )
        return path
    }
}

private enum PremiumMetrics {
    static let contentWidth: CGFloat = 680
    static let purchaseBarWidth: CGFloat = 680
    static let primaryButtonWidth: CGFloat = 440
}

private enum PremiumPalette {
    static let action = Color.accentColor
    static let success = Color.green

    static let successGradient = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.76, blue: 0.42),
            Color(red: 0.13, green: 0.66, blue: 0.82)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

#Preview("购买") {
    NavigationStack {
        PaperVNPremiumView()
    }
    .environmentObject(PaperVNPremiumStore(previewing: true))
}

#Preview("购买完成") {
    PaperVNPremiumSuccessView {}
}
