import AuthenticationServices
import SwiftUI
import Combine
import Foundation
import Security
import UIKit

struct VNDBCredentialStore {
    private let service = "com.jizpaper.PaperVN"
    private let account = "vndbToken"

    func readToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            throw KeychainError(status: errSecDecode)
        }
        return token
    }

    func saveToken(_ token: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let value: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            value as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }

        var newItem = query
        newItem[kSecValueData as String] = Data(token.utf8)
        newItem[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus)
        }
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
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

            强制内容安全策略.同步当前Token(token)
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
        强制内容安全策略.同步当前Token("")
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
            强制内容安全策略.同步当前Token(candidate)
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
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("关闭")
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
    let showsCloseButton: Bool
    let closeAction: () -> Void
    @Environment(\.webAuthenticationSession)
    private var webAuthenticationSession
    @AppStorage(Bangumi账户.同步设置键)
    private var synchronizesWithBangumi = false

    private enum 输入焦点: Hashable {
        case vndbToken
    }

    private enum 账户提示: Identifiable {
        case vndbLogout
        case bangumiLogout
        case kunLogout
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
    @State private var isLoggingInToVNDB = false
    @State private var activeAlert: 账户提示?
    @FocusState private var focusedInput: 输入焦点?
    var body: some View {
        Form {
            vndbSection
            otherAccountsSection
        }
        .formStyle(.grouped)
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
        .onChange(of: bangumiAccount.synchronizationErrorMessage) { _, message in
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

    @ViewBuilder
    private var otherAccountsSection: some View {
        Section {
            NavigationLink {
                otherAccountsPage
            } label: {
                Text("其他账户")
                    .foregroundStyle(.primary)
            }
        }
    }

    private var otherAccountsPage: some View {
        Form {
            otherAccountsLoginSection
            bangumiSection
            kunSection
        }
        .formStyle(.grouped)
        .平台柔和滚动边缘(for: .top)
        .navigationTitle("其他账户")
        .平台内联导航标题()
        .账户与设置关闭按钮(
            isVisible: showsCloseButton,
            action: closeAction
        )
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
                    startBangumiSynchronizationIfNeeded(
                        enabled: synchronizesWithBangumi
                    )
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
                Toggle(isOn: $synchronizesWithBangumi) {
                    HStack(spacing: 8) {
                        Text("资料库同步")
                        if bangumiAccount.isSynchronizing {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                    .onChange(of: synchronizesWithBangumi) { _, enabled in
                        if enabled {
                            startBangumiSynchronizationIfNeeded(enabled: true)
                        } else {
                            bangumiAccount.cancelLibrarySynchronization()
                        }
                    }
                    .onChange(of: vndbAccount.isLoggedIn) { _, isLoggedIn in
                        if isLoggedIn {
                            startBangumiSynchronizationIfNeeded(
                                enabled: synchronizesWithBangumi
                            )
                        } else {
                            bangumiAccount.cancelLibrarySynchronization()
                        }
                    }
            } header: {
                Text("Bangumi番组计划")
            } footer: {
                Text("在编辑VNDB资料库时，向Bangumi番组计划资料库同步可用内容。")
            }

            Section {
                Button("退出登录", role: .destructive) {
                    activeAlert = .bangumiLogout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }

    private func startBangumiSynchronizationIfNeeded(enabled: Bool) {
        guard enabled,
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
            Section("VNDB") {
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
            Section("鲲Galgame") {
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
        }
    }

    @ViewBuilder
    private var otherAccountsLoginSection: some View {
        let showsBangumiLogin = !bangumiAccount.isLoggedIn
        let showsKunLogin = !kunAccount.isLoggedIn

        if showsBangumiLogin || showsKunLogin {
            Section {
                if showsBangumiLogin {
                    HStack(spacing: 12) {
                        Text("Bangumi番组计划")
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Button {
                            bangumiAccount.login(using: webAuthenticationSession)
                        } label: {
                            HStack(spacing: 6) {
                                if bangumiAccount.isRestoringSession
                                    || bangumiAccount.isAuthenticating {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(bangumiLoginButtonTitle)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(
                            bangumiAccount.isRestoringSession
                                || bangumiAccount.isAuthenticating
                        )
                    }
                }

                if showsKunLogin {
                    HStack(spacing: 12) {
                        Text("鲲Galgame")
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Button {
                            kunAccount.login(using: webAuthenticationSession)
                        } label: {
                            HStack(spacing: 6) {
                                if kunAccount.isRestoringSession
                                    || kunAccount.isAuthenticating
                                    || kunAccount.isLoggingOut {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(kunLoginButtonTitle)
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(
                            kunAccount.isRestoringSession
                                || kunAccount.isAuthenticating
                                || kunAccount.isLoggingOut
                        )
                    }
                }
            } footer: {
                if showsBangumiLogin && !BangumiOAuth配置.isConfigured {
                    Text("需要先在App配置中设置BangumiOAuthClientID和BangumiOAuthClientSecret。")
                }
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
        return "登录"
    }

    private var bangumiLoginButtonTitle: LocalizedStringKey {
        if bangumiAccount.isRestoringSession { return "正在载入…" }
        if bangumiAccount.isAuthenticating { return "正在登录…" }
        return "登录"
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
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("关闭")
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
    .environmentObject(家长控制中心.shared)
}

enum 开发环境配置 {
    static let 预设Token: String? = {
        #if DEBUG
        return 内容安全私有配置.开发预设Token
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
