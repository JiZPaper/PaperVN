import AuthenticationServices
import SwiftUI
import Combine
import Foundation
import Security
import UIKit

/// VNDB Token保存在App自己的钥匙串组中。
struct VNDBCredentialStore {
    private static let service = "com.jizpaper.PaperVN"
    private static let account = "vndbToken"

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func readToken() throws -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else { return nil }
        return token
    }

    func saveToken(_ token: String) throws {
        let value: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, value as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw KeychainError(status: updateStatus) }
        var newItem = query
        newItem.merge(value) { _, new in new }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    func deleteToken() {
        SecItemDelete(query as CFDictionary)
    }

    private struct KeychainError: Error {
        let status: OSStatus
    }
}

struct VNDB已保存凭据: Sendable {
    let token: String
    let userID: String
}

struct VNDB账户 {
    let userID: String
    let username: String
    let 已登录: Bool

    var 用户ID: String { userID }
    var 用户名: String { username }
}

func 读取VNDB已保存凭据() -> VNDB已保存凭据? {
    guard let token = try? VNDBCredentialStore().readToken(),
          !token.isEmpty,
          let userID = UserDefaults.standard.string(forKey: "vndbUserID"),
          !userID.isEmpty else {
        return nil
    }
    return VNDB已保存凭据(token: token, userID: userID)
}

@MainActor
class 用户登录: ObservableObject {
    @Published private(set) var token: String = ""
    @Published var isLoggedIn = false
    @Published private(set) var isRestoringSession = true
    @Published var username: String = ""
    @Published var userID: String = ""
    @Published var errorMessage: String?

    var vndb账户: VNDB账户 {
        VNDB账户(userID: userID, username: username, 已登录: isLoggedIn)
    }

    private let baseURL = "https://api.vndb.org/kana"
    private let credentialStore = VNDBCredentialStore()
    private var authenticationGeneration = 0
    private var credentialStoreUnavailable = false

    private enum AuthInfoRequestError: Error, Equatable {
        case unauthorized
        case invalidResponse
        case unexpectedStatus(Int)
    }

    init(previewing: Bool = false) {
        let isRunningForPreviews = ProcessInfo.processInfo.environment[
            "XCODE_RUNNING_FOR_PREVIEWS"
        ] == "1"

        if (previewing || isRunningForPreviews) && 开发环境配置.启用开发环境自动登录 {
            if let devToken = 开发环境配置.预设Token {
                self.token = devToken
                self.username = UserDefaults.standard.string(forKey: "vndbUsername") ?? ""
                self.userID = UserDefaults.standard.string(forKey: "vndbUserID") ?? ""
                self.isLoggedIn = !self.userID.isEmpty
                self.isRestoringSession = false

                if self.userID.isEmpty {
                    Task { @MainActor in
                        await self.fetchUserInfo(using: devToken, shouldPersist: true, generation: 0)
                    }
                }
            } else {
                isRestoringSession = false
            }
            return
        }

        guard !previewing && !isRunningForPreviews else {
            isRestoringSession = false
            return
        }

        username = UserDefaults.standard.string(
            forKey: "vndbUsername"
        ) ?? ""
        userID = UserDefaults.standard.string(
            forKey: "vndbUserID"
        ) ?? ""

        do {
            try migrateLegacyToken()
            token = try credentialStore.readToken() ?? ""

            if token.isEmpty,
               开发环境配置.启用开发环境自动登录,
               let devToken = 开发环境配置.预设Token {
                token = devToken
                try credentialStore.saveToken(devToken)
            }

            敏感内容网页设置.移除旧版本地解锁()
            if !token.isEmpty {
                try credentialStore.saveToken(token)
            }
            checkLoginStatus()
        } catch {
            credentialStoreUnavailable = true
            isLoggedIn = !userID.isEmpty
            isRestoringSession = false
            errorMessage = userID.isEmpty
                ? nil
                : String(localized: "暂时无法读取登录凭据，请稍后再试。")
        }
    }

    func checkLoginStatus() {
        authenticationGeneration += 1
        guard !token.isEmpty else {
            if credentialStoreUnavailable {
                isLoggedIn = !userID.isEmpty
                isRestoringSession = false
                return
            }
            clearUserMetadata()
            isLoggedIn = false
            isRestoringSession = false
            return
        }

        isRestoringSession = true
        isLoggedIn = !userID.isEmpty
        let savedToken = token
        let generation = authenticationGeneration
        Task { await fetchUserInfo(using: savedToken, shouldPersist: false, generation: generation) }
    }

    func login(with newToken: String) async {
        authenticationGeneration += 1
        credentialStoreUnavailable = false
        let generation = authenticationGeneration
        let candidate = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            clearSession()
            errorMessage = String(localized: "请粘贴Token。")
            return
        }
        await fetchUserInfo(using: candidate, shouldPersist: true, generation: generation)
    }

    func logout() {
        authenticationGeneration += 1
        credentialStoreUnavailable = false
        推荐后台分析中心.shared.停止分析()
        clearSession()
        errorMessage = nil
    }

    private func migrateLegacyToken() throws {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "vndbToken") != nil else { return }

        if try credentialStore.readToken() != nil {
            defaults.removeObject(forKey: "vndbToken")
            return
        }

        guard let legacyToken = defaults.string(forKey: "vndbToken")?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !legacyToken.isEmpty else {
            defaults.removeObject(forKey: "vndbToken")
            return
        }
        try credentialStore.saveToken(legacyToken)
        defaults.removeObject(forKey: "vndbToken")
    }

    private func clearSession() {
        credentialStore.deleteToken()
        token = ""
        isLoggedIn = false
        clearUserMetadata()
        isRestoringSession = false
    }

    private func clearUserMetadata() {
        username = ""
        userID = ""
        UserDefaults.standard.removeObject(forKey: "vndbUsername")
        UserDefaults.standard.removeObject(forKey: "vndbUserID")
    }

    private func fetchUserInfo(
        using candidate: String,
        shouldPersist: Bool,
        generation: Int
    ) async {
        let authURL = URL(string: "\(baseURL)/authinfo")!
        var request = URLRequest(url: authURL)
        request.setValue("Token \(candidate)", forHTTPHeaderField: "Authorization")

        do {
            let (data, http) = try await PaperVNConnect网络设置.发送请求(
                request,
                session: .shared
            )
            if http.statusCode == 401 {
                throw AuthInfoRequestError.unauthorized
            }
            guard http.statusCode == 200 else {
                throw AuthInfoRequestError.unexpectedStatus(http.statusCode)
            }

            let authInfo = try JSONDecoder().decode(AuthInfo.self, from: data)
            guard generation == authenticationGeneration else { return }
            if shouldPersist {
                try credentialStore.saveToken(candidate)
            }
            self.token = candidate
            self.username = authInfo.username
            self.userID = authInfo.id
            self.isLoggedIn = true
            self.isRestoringSession = false
            self.errorMessage = nil
            UserDefaults.standard.set(
                authInfo.username,
                forKey: "vndbUsername"
            )
            UserDefaults.standard.set(
                authInfo.id,
                forKey: "vndbUserID"
            )
        } catch {
            guard generation == authenticationGeneration else { return }
            if (error as? AuthInfoRequestError) == .unauthorized {
                clearSession()
                self.errorMessage = shouldPersist
                    ? String(localized: "Token无效。")
                    : nil
            } else if shouldPersist {
                isRestoringSession = false
                self.errorMessage = String(
                    localized: "无法验证Token，请检查网络连接后再试。"
                )
            } else {
                isLoggedIn = !token.isEmpty && !userID.isEmpty
                isRestoringSession = false
                self.errorMessage = nil
            }
        }
    }
}

struct AuthInfo: Codable {
    let id: String
    let username: String
}

struct 鲲账户头像: View {
    let profile: 鲲用户资料?
    let size: CGFloat

    var body: some View {
        Group {
            if let picture = profile?.picture,
               let url = URL(string: picture) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: "person.crop.circle")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
    }
}

struct 用户页面: View {
    @ObservedObject var auth: 用户登录
    @EnvironmentObject private var kunAccount: 鲲Galgame账户
    @EnvironmentObject private var bangumiAccount: Bangumi账户
    @Binding var isPresented: Bool
    var showsSettings: Bool
    var isEmbedded: Bool

    @Environment(\.dismiss) private var dismiss

    init(
        auth: 用户登录,
        isPresented: Binding<Bool>,
        showsSettings: Bool = true
    ) {
        self.init(
            auth: auth,
            isPresented: isPresented,
            showsSettings: showsSettings,
            isEmbedded: false
        )
    }

    init(
        auth: 用户登录,
        isPresented: Binding<Bool>,
        showsSettings: Bool = true,
        isEmbedded: Bool
    ) {
        self.auth = auth
        _isPresented = isPresented
        self.showsSettings = showsSettings
        self.isEmbedded = isEmbedded
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("账户") {
                    NavigationLink {
                        账户页面(
                            vndbAccount: auth,
                            kunAccount: kunAccount,
                            bangumiAccount: bangumiAccount,
                            showsCloseButton: !isEmbedded,
                            closeAction: dismissPage
                        )
                    } label: {
                        设置项目标签(
                            "账户",
                            systemImage: "person.crop.circle.fill",
                            color: .blue
                        )
                    }

                    NavigationLink {
                        同步任务页面()
                            .environmentObject(auth)
                    } label: {
                        设置项目标签(
                            "同步任务",
                            systemImage: "arrow.triangle.2.circlepath",
                            color: .gray
                        )
                    }
                }

                if showsSettings {
                    settingsSection
                    supportSection
                }
            }
            .formStyle(.grouped)
            .平台柔和滚动边缘(for: .top)
            .navigationTitle("账户与设置")
            .平台内联导航标题()
            .账户与设置关闭按钮(
                isVisible: !isEmbedded,
                action: dismissPage
            )
        }
        // 挂在 NavigationStack 外层：推入子页面时它不会消失，“同步任务”页面里也能弹出处理页面
        .modifier(同步待处理弹出())
        .interactiveDismissDisabled(!isEmbedded)
    }

    @ViewBuilder
    private var settingsSection: some View {
        Section("设置") {
            NavigationLink {
                网络设置(
                    isPresented: $isPresented,
                    showsDismissButton: true
                )
            } label: {
                设置项目标签(
                    "网络",
                    systemImage: "network",
                    color: .blue
                )
            }

            NavigationLink {
                内容与安全限制(
                    isPresented: $isPresented,
                    showsDismissButton: true
                )
            } label: {
                设置项目标签(
                    "内容与安全限制",
                    systemImage: "hand.raised.fill",
                    color: .blue
                )
            }

            NavigationLink {
                通用设置(
                    isPresented: $isPresented,
                    showsDismissButton: true
                )
            } label: {
                设置项目标签(
                    "通用",
                    systemImage: "gear",
                    color: .gray
                )
            }

        }

        Section {
            NavigationLink {
                Today设置(
                    isPresented: $isPresented,
                    showsDismissButton: true
                )
            } label: {
                设置项目标签(
                    "Today",
                    systemImage: "newspaper.fill",
                    color: .gray
                )
            }

            NavigationLink {
                资料库设置(
                    isPresented: $isPresented,
                    showsDismissButton: true
                )
            } label: {
                设置项目标签(
                    "资料库",
                    systemImage: "books.vertical.fill",
                    color: .gray
                )
            }

            if #available(iOS 27.0, *),
               UIDevice.current.userInterfaceIdiom != .pad {
                NavigationLink {
                    搜索设置(
                        isPresented: $isPresented,
                        showsDismissButton: true
                    )
                } label: {
                    设置项目标签(
                        "搜索",
                        systemImage: "magnifyingglass",
                        color: .gray
                    )
                }
            }
        }
    }

    private var supportSection: some View {
        Section {
            NavigationLink {
                PaperVNPremiumView()
                    .账户与设置关闭按钮(
                        isVisible: !isEmbedded,
                        action: dismissPage
                    )
            } label: {
                设置项目标签(
                    "资助开发者换台电脑",
                    systemImage: "heart.fill",
                    color: .pink
                )
            }
        }
    }

    private func dismissPage() {
        isPresented = false
        dismiss()
    }
}

private struct 账户与设置关闭按钮修饰器: ViewModifier {
    let isVisible: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            if isVisible {
                ToolbarItem(placement: .平台关闭操作) {
                    Button(action: action) {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
        }
    }
}

private extension View {
    func 账户与设置关闭按钮(
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        modifier(
            账户与设置关闭按钮修饰器(
                isVisible: isVisible,
                action: action
            )
        )
    }
}

private struct 账户页面: View {
    @ObservedObject var vndbAccount: 用户登录
    @ObservedObject var kunAccount: 鲲Galgame账户
    @ObservedObject var bangumiAccount: Bangumi账户
    @EnvironmentObject private var myAnimeListAccount: MyAnimeList账户
    @EnvironmentObject private var aniListAccount: AniList账户
    @EnvironmentObject private var annictAccount: Annict账户
    @EnvironmentObject private var tmdbAccount: TMDB账户
    @State private var tmdbTokenInput = ""
    let showsCloseButton: Bool
    let closeAction: () -> Void

    private enum 输入焦点: Hashable {
        case vndbToken
    }

    private enum 账户提示: Identifiable {
        case vndbLogout
        case bangumiLogout
        case kunLogout
        case malLogout
        case malError(String)
        case aniListLogout
        case aniListError(String)
        case annictLogout
        case annictError(String)
        case tmdbLogout
        case tmdbError(String)
        case vndbError(String)
        case bangumiError(String)
        case bangumiSyncError(String)
        case kunError(String)

        var id: String {
            switch self {
            case .vndbLogout:
                return "vndbLogout"
            case .bangumiLogout:
                return "bangumiLogout"
            case .kunLogout:
                return "kunLogout"
            case .malLogout:
                return "malLogout"
            case let .malError(message):
                return "malError:\(message)"
            case .aniListLogout:
                return "aniListLogout"
            case let .aniListError(message):
                return "aniListError:\(message)"
            case .annictLogout:
                return "annictLogout"
            case let .annictError(message):
                return "annictError:\(message)"
            case .tmdbLogout:
                return "tmdbLogout"
            case let .tmdbError(message):
                return "tmdbError:\(message)"
            case let .vndbError(message):
                return "vndbError:\(message)"
            case let .bangumiError(message):
                return "bangumiError:\(message)"
            case let .bangumiSyncError(message):
                return "bangumiSyncError:\(message)"
            case let .kunError(message):
                return "kunError:\(message)"
            }
        }
    }

    @State private var inputToken = ""
    @State private var deviceCode: String?
    @State private var isLoggingInToVNDB = false
    @State private var activeAlert: 账户提示?
    @FocusState private var focusedInput: 输入焦点?
    var body: some View {
        Form {
            Section {
                NavigationLink {
                    accountDetailPage("VNDB") { vndbSection }
                } label: {
                    accountRow("VNDB", status: vndbStatus)
                }
                NavigationLink {
                    accountDetailPage("Bangumi番组计划") { bangumiSection }
                } label: {
                    accountRow("Bangumi番组计划", status: bangumiStatus)
                }
                NavigationLink {
                    accountDetailPage("MyAnimeList") { malSection }
                } label: {
                    accountRow("MyAnimeList", status: malStatus)
                }
                NavigationLink {
                    accountDetailPage("AniList") { aniListSection }
                } label: {
                    accountRow("AniList", status: aniListStatus)
                }
                NavigationLink {
                    accountDetailPage("Annict") { annictSection }
                } label: {
                    accountRow("Annict", status: annictStatus)
                }
                NavigationLink {
                    accountDetailPage("TMDB") { tmdbSection }
                } label: {
                    accountRow("TMDB", status: tmdbStatus)
                }
                NavigationLink {
                    accountDetailPage("鲲Galgame") { kunSection }
                } label: {
                    accountRow("鲲Galgame", status: kunStatus)
                }
            }

            Section {
                LabeledContent("设备码") {
                    if let deviceCode {
                        Text(verbatim: deviceCode)
                            .monospaced()
                            .textSelection(.enabled)
                    } else {
                        Text("不可用")
                    }
                }
                .contextMenu {
                    if let deviceCode {
                        Button("拷贝", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = deviceCode
                        }
                    }
                }
            } footer: {
                Text("")
            }
        }
        .formStyle(.grouped)
        .task {
            deviceCode = 敏感内容网页设置.设备码
        }
        .onChange(of: bangumiAccount.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                startBangumiSynchronizationIfNeeded()
                Task { await PaperVNSync中心.shared.同步动画漫画() }
            }
        }
        .onChange(of: vndbAccount.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                startBangumiSynchronizationIfNeeded()
            } else {
                bangumiAccount.cancelLibrarySynchronization()
            }
        }
        .平台柔和滚动边缘(for: .top)
        .navigationTitle("账户")
        .平台内联导航标题()
        .账户与设置关闭按钮(
            isVisible: showsCloseButton,
            action: closeAction
        )
        .scrollDismissesKeyboard(.interactively)
        .alert(item: $activeAlert) { alert in
            accountAlert(alert)
        }
        .onChange(of: vndbAccount.errorMessage) { _, message in
            guard let message else { return }
            activeAlert = .vndbError(message)
        }
        .onChange(of: kunAccount.errorMessage) { _, message in
            guard let message else { return }
            activeAlert = .kunError(message)
        }
        .onChange(of: bangumiAccount.errorMessage) { _, message in
            guard let message else { return }
            activeAlert = .bangumiError(message)
        }
        .onChange(of: myAnimeListAccount.errorMessage) { _, message in
            guard let message else { return }
            activeAlert = .malError(message)
        }
        .onChange(of: myAnimeListAccount.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await PaperVNSync中心.shared.同步动画漫画() }
            }
        }
        .onChange(of: aniListAccount.errorMessage) { _, message in
            guard let message else { return }
            activeAlert = .aniListError(message)
        }
        .onChange(of: aniListAccount.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await PaperVNSync中心.shared.同步动画漫画() }
            }
        }
        .onChange(of: annictAccount.errorMessage) { _, message in
            guard let message else { return }
            activeAlert = .annictError(message)
        }
        .onChange(of: annictAccount.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await PaperVNSync中心.shared.同步动画漫画() }
            }
        }
        .onChange(of: tmdbAccount.errorMessage) { _, message in
            guard let message else { return }
            activeAlert = .tmdbError(message)
        }
        .onChange(of: tmdbAccount.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn {
                Task { await PaperVNSync中心.shared.同步动画漫画() }
            }
        }
        .onReceive(bangumiAccount.同步进度.$synchronizationErrorMessage.removeDuplicates()) { message in
            guard let message else { return }
            activeAlert = .bangumiSyncError(message)
        }
        .onAppear {
            if !vndbAccount.isLoggedIn,
               !vndbAccount.isRestoringSession {
                vndbAccount.errorMessage = nil
            } else if let message = vndbAccount.errorMessage {
                activeAlert = .vndbError(message)
            }

            if !kunAccount.isLoggedIn,
               !kunAccount.isRestoringSession,
               !kunAccount.isAuthenticating {
                kunAccount.errorMessage = nil
            } else if let message = kunAccount.errorMessage {
                activeAlert = .kunError(message)
            }

            if !bangumiAccount.isLoggedIn,
               !bangumiAccount.isRestoringSession,
               !bangumiAccount.isAuthenticating {
                bangumiAccount.errorMessage = nil
            } else if let message = bangumiAccount.errorMessage {
                activeAlert = .bangumiError(message)
            }
        }
    }

    private func accountRow(_ title: LocalizedStringKey, status: Text) -> some View {
        LabeledContent {
            status
        } label: {
            Text(title)
                .foregroundStyle(.primary)
        }
    }

    private func accountStatus(
        isLoggedIn: Bool,
        isLoading: Bool,
        name: String?
    ) -> Text {
        if isLoading { return Text("正在载入…") }
        guard isLoggedIn else { return Text("未登录") }
        if let name, !name.isEmpty { return Text(verbatim: name) }
        return Text("已登录")
    }

    private var vndbStatus: Text {
        accountStatus(
            isLoggedIn: vndbAccount.isLoggedIn,
            isLoading: vndbAccount.isRestoringSession,
            name: vndbAccount.username
        )
    }

    private var bangumiStatus: Text {
        accountStatus(
            isLoggedIn: bangumiAccount.isLoggedIn,
            isLoading: bangumiAccount.isRestoringSession,
            name: bangumiAccount.profile?.displayName
        )
    }

    private var malStatus: Text {
        accountStatus(
            isLoggedIn: myAnimeListAccount.isLoggedIn,
            isLoading: false,
            name: myAnimeListAccount.profile?.name
        )
    }

    @ViewBuilder
    private var malSection: some View {
        if myAnimeListAccount.isLoggedIn {
            Section {
                if let picture = myAnimeListAccount.profile?.picture {
                    LabeledContent("头像") {
                        CachedAsyncImage(url: URL(string: picture), contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    }
                }
                if let profile = myAnimeListAccount.profile {
                    LabeledContent("用户名", value: profile.name)
                    LabeledContent("ID", value: String(profile.id))
                }
            } footer: {
                Text("通过PaperVN Sync同步资料库中的动画、漫画与轻小说。")
            }

            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .malLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        } else {
            Section {
                webLoginButton(
                    title: myAnimeListAccount.isAuthenticating ? "正在登录…" : "登录MyAnimeList",
                    isBusy: myAnimeListAccount.isAuthenticating
                ) { authenticator in
                    myAnimeListAccount.login(using: authenticator)
                }
            } header: {
                Text("使用MyAnimeList账户登录")
            } footer: {
                if !MyAnimeListOAuth配置.isConfigured {
                    Text("需要先在App配置中设置MALClientID。")
                } else {
                    Text("通过PaperVN Sync同步资料库中的动画、漫画与轻小说。")
                }
            }
        }
    }

    private var aniListStatus: Text {
        accountStatus(isLoggedIn: aniListAccount.isLoggedIn, isLoading: false, name: aniListAccount.profile?.name)
    }

    private var annictStatus: Text {
        accountStatus(isLoggedIn: annictAccount.isLoggedIn, isLoading: false, name: annictAccount.profile?.username)
    }

    private var tmdbStatus: Text {
        accountStatus(isLoggedIn: tmdbAccount.isLoggedIn, isLoading: false, name: tmdbAccount.profile?.username)
    }

    @ViewBuilder
    private var tmdbSection: some View {
        // 与 VNDB 的登录页面一致：已登录时显示用户名与 ID；未登录时粘贴令牌后登录
        if tmdbAccount.isLoggedIn {
            Section {
                if let profile = tmdbAccount.profile {
                    LabeledContent("用户名", value: profile.username)
                    LabeledContent("ID", value: String(profile.id))
                }
            }

            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .tmdbLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        } else {
            Section {
                TMDB令牌输入行(token: $tmdbTokenInput, account: tmdbAccount)
            } header: {
                Text("使用TMDB账户登录")
            } footer: {
                Text("你需要使用API读取访问令牌来登录TMDB。如果你还没有，可以在TMDB网站的Settings > API中申请。")
            }
        }
    }

    @ViewBuilder
    private var aniListSection: some View {
        if aniListAccount.isLoggedIn {
            Section {
                if let avatar = aniListAccount.profile?.avatar {
                    LabeledContent("头像") {
                        CachedAsyncImage(url: URL(string: avatar), contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    }
                }
                if let profile = aniListAccount.profile {
                    LabeledContent("用户名", value: profile.name)
                    LabeledContent("ID", value: String(profile.id))
                }
            } footer: {
                Text("通过PaperVN Sync同步资料库中的动画、漫画与轻小说。")
            }
            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .aniListLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        } else {
            Section {
                webLoginButton(
                    title: aniListAccount.isAuthenticating ? "正在登录…" : "登录AniList",
                    isBusy: aniListAccount.isAuthenticating
                ) { authenticator in
                    aniListAccount.login(using: authenticator)
                }
            } header: {
                Text("使用AniList账户登录")
            } footer: {
                Text("通过PaperVN Sync同步资料库中的动画、漫画与轻小说。")
            }
        }
    }

    @ViewBuilder
    private var annictSection: some View {
        if annictAccount.isLoggedIn {
            Section {
                if let avatar = annictAccount.profile?.avatarUrl {
                    LabeledContent("头像") {
                        CachedAsyncImage(url: URL(string: avatar), contentMode: .fill)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    }
                }
                if let profile = annictAccount.profile {
                    LabeledContent("用户名", value: profile.username)
                    LabeledContent("名称", value: profile.name)
                }
            } footer: {
                Text("通过PaperVN Sync同步资料库中动画的观看状态。Annict不同步评分与进度。")
            }
            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .annictLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        } else {
            Section {
                webLoginButton(
                    title: annictAccount.isAuthenticating ? "正在登录…" : "登录Annict",
                    isBusy: annictAccount.isAuthenticating
                ) { authenticator in
                    annictAccount.login(using: authenticator)
                }
            } header: {
                Text("使用Annict账户登录")
            } footer: {
                Text("通过PaperVN Sync同步资料库中动画的观看状态。Annict不同步评分与进度。")
            }
        }
    }

    private var kunStatus: Text {
        accountStatus(
            isLoggedIn: kunAccount.isLoggedIn,
            isLoading: kunAccount.isRestoringSession,
            name: kunAccount.profile?.displayName
        )
    }

    /// 单个账户的页面：已登录时显示资料与退出登录，未登录时显示登录方式。
    private func accountDetailPage<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .平台柔和滚动边缘(for: .top)
        .navigationTitle(title)
        .平台内联导航标题()
        .账户与设置关闭按钮(
            isVisible: showsCloseButton,
            action: closeAction
        )
        .scrollDismissesKeyboard(.interactively)
        .alert(item: $activeAlert) { alert in
            accountAlert(alert)
        }
    }

    private func accountAlert(_ alert: 账户提示) -> Alert {
        switch alert {
        case .vndbLogout:
            return Alert(
                title: Text("要退出VNDB账户吗？"),
                message: Text("退出后将无法使用资料库功能。"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("退出登录")) {
                    vndbAccount.logout()
                }
            )
        case .kunLogout:
            return Alert(
                title: Text("要退出鲲Galgame账户吗？"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("退出登录")) {
                    kunAccount.logout()
                }
            )
        case .bangumiLogout:
            return Alert(
                title: Text("要退出Bangumi番组计划账户吗？"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("退出登录")) {
                    bangumiAccount.logout()
                }
            )
        case .malLogout:
            return Alert(
                title: Text("要退出MyAnimeList账户吗？"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("退出登录")) {
                    myAnimeListAccount.logout()
                }
            )
        case .aniListLogout:
            return Alert(
                title: Text("要退出AniList账户吗？"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("退出登录")) {
                    aniListAccount.logout()
                }
            )
        case let .aniListError(message):
            return Alert(
                title: Text("无法登录AniList"),
                message: Text(verbatim: message),
                dismissButton: .default(Text("好")) {
                    aniListAccount.errorMessage = nil
                }
            )
        case .annictLogout:
            return Alert(
                title: Text("要退出Annict账户吗？"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("退出登录")) {
                    annictAccount.logout()
                }
            )
        case let .annictError(message):
            return Alert(
                title: Text("无法登录Annict"),
                message: Text(verbatim: message),
                dismissButton: .default(Text("好")) {
                    annictAccount.errorMessage = nil
                }
            )
        case .tmdbLogout:
            return Alert(
                title: Text("要退出TMDB账户吗？"),
                primaryButton: .cancel(Text("取消")),
                secondaryButton: .destructive(Text("退出登录")) {
                    tmdbAccount.logout()
                }
            )
        case let .tmdbError(message):
            return Alert(
                title: Text("无法登录TMDB"),
                message: Text(verbatim: message),
                dismissButton: .default(Text("好")) {
                    tmdbAccount.errorMessage = nil
                }
            )
        case let .malError(message):
            return Alert(
                title: Text("无法登录MyAnimeList"),
                message: Text(verbatim: message),
                dismissButton: .default(Text("好")) {
                    myAnimeListAccount.errorMessage = nil
                }
            )
        case let .vndbError(message):
            return Alert(
                title: Text("无法登录VNDB"),
                message: Text(verbatim: message),
                dismissButton: .default(Text("好")) {
                    vndbAccount.errorMessage = nil
                }
            )
        case let .kunError(message):
            return Alert(
                title: Text("无法登录鲲Galgame"),
                message: Text(verbatim: message),
                dismissButton: .default(Text("好")) {
                    kunAccount.errorMessage = nil
                }
            )
        case let .bangumiError(message):
            return Alert(
                title: Text("无法登录Bangumi番组计划"),
                message: Text(verbatim: message),
                dismissButton: .default(Text("好")) {
                    bangumiAccount.errorMessage = nil
                }
            )
        case let .bangumiSyncError(message):
            return Alert(
                title: Text("无法同步到Bangumi番组计划"),
                message: Text(verbatim: message),
                primaryButton: .cancel(Text("取消")) {
                    bangumiAccount.synchronizationErrorMessage = nil
                },
                secondaryButton: .default(Text("重试")) {
                    bangumiAccount.synchronizationErrorMessage = nil
                    startBangumiSynchronizationIfNeeded()
                }
            )
        }
    }

    @ViewBuilder
    private var bangumiSection: some View {
        if bangumiAccount.isLoggedIn, let profile = bangumiAccount.profile {
            Section {
                LabeledContent("头像") {
                    CachedAsyncImage(
                        url: URL(string: profile.avatar.medium),
                        contentMode: .fill
                    )
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                }
                LabeledContent("用户名", value: profile.displayName)
                LabeledContent("ID", value: String(profile.id))
                if !profile.username.isEmpty {
                    LabeledContent("账户名", value: profile.username)
                }
                if !profile.sign.isEmpty {
                    LabeledContent("个人签名", value: profile.sign)
                }
            } footer: {
                Text("通过PaperVN Sync同步资料库中的视觉小说、动画、漫画与轻小说。")
            }

            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .bangumiLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        } else {
            Section {
                webLoginButton(
                    title: bangumiLoginButtonTitle,
                    isBusy: bangumiAccount.isRestoringSession
                        || bangumiAccount.isAuthenticating
                ) { authenticator in
                    bangumiAccount.login(using: authenticator)
                }
            } header: {
                Text("使用Bangumi番组计划账户登录")
            } footer: {
                if !BangumiOAuth配置.isConfigured {
                    Text("需要先在App配置中设置BangumiOAuthClientID。")
                } else {
                    Text("登录后可以发布吐槽，并通过PaperVN Sync同步资料库中的视觉小说、动画、漫画与轻小说。")
                }
            }
        }
    }

    private func webLoginButton(
        title: LocalizedStringKey,
        isBusy: Bool,
        action: @escaping (WebAuthenticationSession) -> Void
    ) -> some View {
        网页登录按钮(title: title, isBusy: isBusy, action: action)
    }

    private func startBangumiSynchronizationIfNeeded() {
        guard PaperVNSync中心.已启用,
              vndbAccount.isLoggedIn,
              bangumiAccount.isLoggedIn else { return }
        bangumiAccount.startLibrarySynchronization(
            vndbToken: vndbAccount.token,
            userID: vndbAccount.userID
        )
    }

    @ViewBuilder
    private var vndbSection: some View {
        if vndbAccount.isLoggedIn {
            Section {
                LabeledContent("用户名", value: vndbAccount.username)
                LabeledContent("ID", value: vndbAccount.userID)
            }

            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .vndbLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        } else {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    TextField("在此处粘贴Token…", text: $inputToken)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .平台Token输入样式()
                        .focused($focusedInput, equals: .vndbToken)
                        .lineLimit(1)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.76),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .onSubmit(performVNDBLogin)

                    Button(action: performVNDBLogin) {
                        Group {
                            if vndbAccount.isRestoringSession
                                || isLoggingInToVNDB {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "arrow.right")
                            }
                        }
                        .frame(width: 16, height: 16)
                    }
                    .buttonBorderShape(.circle)
                    .液态玻璃醒目按钮(in: Circle())
                    .controlSize(.small)
                    .frame(width: 30, height: 30)
                    .tint(isVNDBLoginDisabled ? .gray : .blue)
                    .disabled(isVNDBLoginDisabled)
                    .accessibilityLabel(Text(vndbLoginButtonTitle))
                }

            } header: {
                Text("使用VNDB账户登录")
            } footer: {
                Text("你需要使用Token来登录VNDB。如果你还没有Token，可以在My Profile > Applications中创建。请为此Token开放所有权限，否则将无法对资料库进行操作。")
            }
        }
    }

    @ViewBuilder
    private var kunSection: some View {
        if kunAccount.isLoggedIn, let profile = kunAccount.profile {
            Section {
                LabeledContent("头像") {
                    鲲账户头像(profile: profile, size: 44)
                }
                kunDetailRow("用户名", value: profile.displayName)
                kunDetailRow("ID", value: String(profile.id))
                kunDetailRow("UUID", value: profile.sub)
                kunDetailRow("电子邮件", value: profile.email)
                kunDetailRow("个人简介", value: profile.bio)
                kunDetailRow(
                    "萌萌点",
                    value: profile.moemoepoint.map(String.init)
                )
                kunDetailRow(
                    "账户状态",
                    value: profile.status.map(String.init)
                )
                kunDetailRow(
                    "角色",
                    value: joinedRoles(profile.roles)
                )
                kunDetailRow(
                    "站点角色",
                    value: joinedRoles(profile.siteRoles ?? [])
                )
                kunDetailRow(
                    "注册时间",
                    value: formattedISO8601Date(profile.createdAt)
                )
                kunDetailRow(
                    "资料更新时间",
                    value: formattedTimestamp(profile.updatedAt)
                )
            }

            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .kunLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .disabled(kunAccount.isLoggingOut)
            }
        } else {
            Section {
                webLoginButton(
                    title: kunLoginButtonTitle,
                    isBusy: kunAccount.isRestoringSession
                        || kunAccount.isAuthenticating
                        || kunAccount.isLoggingOut
                ) { authenticator in
                    kunAccount.login(using: authenticator)
                }
            } header: {
                Text("使用鲲Galgame账户登录")
            }
        }
    }

    @ViewBuilder
    private func kunDetailRow(
        _ label: LocalizedStringKey,
        value: String?
    ) -> some View {
        if let value, !value.isEmpty {
            ViewThatFits(in: .horizontal) {
                LabeledContent {
                    Text(verbatim: value)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                } label: {
                    Text(label)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                    Text(verbatim: value)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func joinedRoles(_ roles: [String]) -> String? {
        guard !roles.isEmpty else { return nil }
        return roles.joined(separator: "、")
    }

    private func formattedTimestamp(_ timestamp: Int?) -> String? {
        guard let timestamp else { return nil }
        return formattedAccountDate(
            Date(timeIntervalSince1970: TimeInterval(timestamp))
        )
    }

    private func formattedISO8601Date(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) {
            return formattedAccountDate(date)
        }

        formatter.formatOptions.insert(.withFractionalSeconds)
        guard let date = formatter.date(from: value) else { return value }
        return formattedAccountDate(date)
    }

    private func formattedAccountDate(_ date: Date) -> String {
        date.formatted(
            date: .abbreviated,
            time: .shortened
        )
    }

    private var isVNDBLoginDisabled: Bool {
        (inputToken.isEmpty && vndbAccount.token.isEmpty)
            || isLoggingInToVNDB
            || vndbAccount.isRestoringSession
    }

    private var vndbLoginButtonTitle: LocalizedStringKey {
        if vndbAccount.isRestoringSession { return "正在载入…" }
        if isLoggingInToVNDB { return "正在登录…" }
        if inputToken.isEmpty && !vndbAccount.token.isEmpty {
            return "使用上次登录时的Token"
        }
        return "登录VNDB"
    }

    private var kunLoginButtonTitle: LocalizedStringKey {
        if kunAccount.isRestoringSession { return "正在载入…" }
        if kunAccount.isLoggingOut { return "正在退出…" }
        if kunAccount.isAuthenticating { return "正在登录…" }
        return "登录鲲Galgame"
    }

    private var bangumiLoginButtonTitle: LocalizedStringKey {
        if bangumiAccount.isRestoringSession { return "正在载入…" }
        if bangumiAccount.isAuthenticating { return "正在登录…" }
        return "登录Bangumi番组计划"
    }

    private func performVNDBLogin() {
        guard !isLoggingInToVNDB else { return }
        focusedInput = nil
        isLoggingInToVNDB = true
        Task {
            let tokenToUse = inputToken.isEmpty
                ? vndbAccount.token
                : inputToken
            if !tokenToUse.isEmpty {
                await vndbAccount.login(with: tokenToUse)
            } else {
                vndbAccount.errorMessage = String(localized: "请粘贴Token。")
            }
            isLoggingInToVNDB = false
        }
    }

}

struct 关于页面: View {
    @Binding var isPresented: Bool

    var body: some View {
        平台滚动页面 {
            Section("法律信息") {
                Link(destination: Self.privacyPolicyURL) {
                    关于外部链接标签("隐私政策") {
                        Image(systemName: "hand.raised")
                    }
                }

                Link(destination: Self.termsOfServiceURL) {
                    关于外部链接标签("服务条款") {
                        Image(systemName: "doc.text")
                    }
                }
            }

            Section("社区") {
                Link(destination: Self.discordURL) {
                    关于外部链接标签("Discord服务器") {
                        Image("DiscordIcon")
                            .resizable()
                            .scaledToFit()
                    }
                }

                Link(destination: Self.telegramURL) {
                    关于外部链接标签("Telegram群组") {
                        Image("TelegramIcon")
                            .resizable()
                            .scaledToFit()
                    }
                }

                Link(destination: Self.qqGroupURL) {
                    关于外部链接标签(
                        "QQ群",
                        detail: "1085135885"
                    ) {
                        Image("QQIcon")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.primary)
                    }
                }

                Link(destination: Self.bilibiliURL) {
                    关于外部链接标签("哔哩哔哩频道") {
                        Image("BilibiliIcon")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.primary)
                    }
                }
            }

            Section("开源项目") {
                Link(destination: Self.localizationsRepositoryURL) {
                    关于外部链接标签("翻译PaperVN") {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }

                Link(destination: Self.descriptionTranslationsRepositoryURL) {
                    关于外部链接标签("翻译VNDB视觉小说与角色简介") {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                    }
                }
            }

            Section("联系方式") {
                Link(destination: Self.emailURL) {
                    关于外部链接标签("JiZPaper@gmail.com") {
                        Image(systemName: "envelope")
                    }
                }
            }
        }
        .navigationTitle("关于")
        .平台柔和滚动边缘(for: .top)
        .平台内联导航标题()
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

    private static var versionText: String {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String

        guard let build, build != version else { return version }
        return "\(version) (\(build))"
    }

    private static let privacyPolicyURL = URL(
        string: "https://papervn.jizpaper.com/PrivacyPolicy.html"
    )!
    private static let termsOfServiceURL = URL(
        string: "https://papervn.jizpaper.com/TermsOfService.html"
    )!
    private static let discordURL = URL(string: "https://discord.gg/h2szTmfWS")!
    static let telegramURL = URL(string: "https://t.me/papervn_app")!
    static let qqGroupURL = URL(
        string: "https://qun.qq.com/universal-share/share?ac=1"
            + "&authKey=NfqZvKjR4Ud0TcvNvrc6zeIFlr6Q8uj68x4QiefywLd02ohNMFSHfb0XG822S0g4"
            + "&busi_data=eyJncm91cENvZGUiOiIxMDg1MTM1ODg1IiwidG9rZW4iOiJGY1dGVDRxakx5WHBhcFJHa0lZTzBiWDFVdWl0bXhweWY4aUtNOE1VdHZmcFNFZmxWcXFrN1puOXRkZ3creC81IiwidWluIjoiMjQ5MTYwMjgxOSJ9"
            + "&data=Zkh5UwOc5B2nq8T5Vqw5KyF5eh98Q9zwR03-bTkYvpJBH1YfomLzLUDcOP6U6ZbaUKA9kasq6ODivExs5WAq9Q"
            + "&svctype=4&tempid=h5_group_info"
    )!
    private static let bilibiliURL = URL(
        string: "https://space.bilibili.com/355150816"
    )!
    private static let localizationsRepositoryURL = URL(
        string: "https://github.com/JiZPaper/PaperVN-Localizations"
    )!
    private static let descriptionTranslationsRepositoryURL = URL(
        string: "https://github.com/JiZPaper/VNDB-Description-Translations"
    )!
    private static let emailURL = URL(string: "mailto:JiZPaper@gmail.com")!
}

struct 关于外部链接标签<IconContent: View>: View {
    private let title: LocalizedStringKey
    private let detail: String?
    private let icon: IconContent

    init(
        _ title: LocalizedStringKey,
        detail: String? = nil,
        @ViewBuilder icon: () -> IconContent
    ) {
        self.title = title
        self.detail = detail
        self.icon = icon()
    }

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            Text(title)

            Spacer(minLength: 8)

            if let detail {
                Text(verbatim: detail)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    NavigationStack {
        用户页面(
            auth: 用户登录(previewing: true),
            isPresented: .constant(true)
        )
    }
    .environmentObject(PaperVNPremiumStore(previewing: true))
    .environmentObject(鲲Galgame账户(previewing: true))
    .environmentObject(Bangumi账户(previewing: true))
    .environmentObject(MyAnimeList账户(previewing: true))
    .environmentObject(家长控制中心.shared)
}

enum 开发环境配置 {
    static let 预设Token: String? = {
        #if DEBUG
        // 在Scheme的环境变量中设置，不要写进源码。
        let token = ProcessInfo.processInfo.environment["PAPERVN_DEV_VNDB_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
        #else
        return nil
        #endif
    }()

    static let 启用开发环境自动登录: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()
}

/// 网页登录按钮。`webAuthenticationSession` 要由按钮所在的页面读取：
/// 在上一级页面读取后传进推入的账户页面，系统找不到用来弹出登录窗口的窗口，点按后没有反应。
private struct 网页登录按钮: View {
    let title: LocalizedStringKey
    let isBusy: Bool
    let action: (WebAuthenticationSession) -> Void
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    var body: some View {
        Button {
            action(webAuthenticationSession)
        } label: {
            HStack(spacing: 8) {
                Text(title)
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isBusy)
    }
}


/// TMDB 的令牌输入行，排版与 VNDB 的 Token 输入相同。粘贴令牌后点箭头，在 TMDB 网站上批准登录。
private struct TMDB令牌输入行: View {
    @Binding var token: String
    @ObservedObject var account: TMDB账户
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private var isDisabled: Bool {
        account.isAuthenticating || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField("在此处粘贴Token…", text: $token)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .平台Token输入样式()
                .lineLimit(1)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.76),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .onSubmit(login)

            Button(action: login) {
                Group {
                    if account.isAuthenticating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.right")
                    }
                }
                .frame(width: 16, height: 16)
            }
            .buttonBorderShape(.circle)
            .液态玻璃醒目按钮(in: Circle())
            .controlSize(.small)
            .frame(width: 30, height: 30)
            .tint(isDisabled ? .gray : .blue)
            .disabled(isDisabled)
            .accessibilityLabel(Text("登录TMDB"))
        }
    }

    private func login() {
        guard !isDisabled else { return }
        account.login(令牌: token, using: webAuthenticationSession)
    }
}
