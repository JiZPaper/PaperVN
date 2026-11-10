import AuthenticationServices
import SwiftUI

/// “账户”中的 Paper Account：登录与注销、昵称、Paper Cloud。资料库设置中的“Paper Cloud”也进入此页面。
struct PaperAccount页面: View {
    @ObservedObject private var account = PaperAccount账户.shared
    @Environment(\.authorizationController) private var authorizationController
    @State private var errorMessage: String?
    @State private var confirmsDeletion = false
    @State private var isDeleting = false
    @State private var entersRecoveryKey = false

    var body: some View {
        平台滚动页面 {
            Section {
                设置类别介绍(
                    title: "Paper账户",
                    description: "用于同步资料库、反馈、数据维护和Today推荐。删除PaperVN后重新登录即可恢复资料库。",
                    systemImage: "person.crop.circle.badge.checkmark",
                    color: .indigo
                )
            }

            if let profile = account.资料 {
                if account.登录已过期 {
                    Section {
                        Paper账户登录按钮(errorMessage: $errorMessage)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    } header: {
                        Text("登录已过期")
                    } footer: {
                        Text("重新登录以继续同步资料库。在此期间，资料库保留在此设备上。")
                    }
                }

                Section {
                    NavigationLink {
                        PaperAccount昵称页面(nickname: profile.nickname ?? "")
                    } label: {
                        LabeledContent("昵称") {
                            Text(verbatim: profile.nickname ?? String(localized: "未设置"))
                        }
                    }
                } footer: {
                    Text("")
                }

                paperCloudSection

                Section {
                    NavigationLink("使用Paper账户的App") {
                        已授权App页面()
                    }
                } footer: {
                    Text("第三方模拟器和其他App可以登录Paper账户以传入游玩路径。")
                }

                Section {
                    Button("退出登录") {
                        Task { await account.退出登录() }
                    }
                }

                Section {
                    Button("删除账户", role: .destructive) { confirmsDeletion = true }
                        .disabled(isDeleting)
                } footer: {
                    Text("抹掉所有使用痕迹并删除Paper账户。此操作无法撤销。")
                }
            } else {
                #if DEBUG
                // 调试：不登录预览高级数据保护的开关与设置流程（`-AdvancedDataProtectionSample`）
                if ProcessInfo.processInfo.arguments.contains("-AdvancedDataProtectionSample") { paperCloudSection }
                #endif
                Section {
                    Paper账户登录按钮(errorMessage: $errorMessage)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("")
                }
            }
        }
        .平台分组列表样式()
        .navigationTitle("Paper账户")
        .平台内联导航标题()
        .task(id: account.isLoggedIn) {
            if account.isLoggedIn {
                // 取得其他设备上更改的高级数据保护设置
                await account.刷新云端资料库()
            } else {
                await account.准备登录()
            }
        }
        .alert("要删除Paper账户吗？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除账户", role: .destructive) { deleteAccount() }
        } message: {
            Text("抹掉所有使用痕迹并删除Paper账户。此操作无法撤销。")
        }
        .sheet(isPresented: $entersRecoveryKey) {
            输入恢复密钥页面()
        }
        .alert("Paper账户", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private var paperCloudSection: some View {
        Section {
            Toggle("Paper Cloud", isOn: Binding(get: { account.自动备份 }, set: { account.自动备份 = $0 }))
            高级数据保护开关(errorMessage: $errorMessage)
            if account.已开启高级数据保护 && account.需要恢复密钥 {
                Button("输入恢复密钥") { entersRecoveryKey = true }
            }
        } footer: {
            if let error = account.备份错误 {
                Text(verbatim: error)
            } else {
                Text("将资料库上传到Paper Cloud，并在你的设备之间同步。")
            }
        }
    }

    /// 注销前用 Sign in with Apple 重新验证，服务器核对是同一个 Apple 账户。
    private func deleteAccount() {
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                let challenge = try await account.新挑战()
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.nonce = PaperAccount账户.nonce(challenge)
                guard case let .appleID(credential) = try await authorizationController.performRequest(request) else { return }
                try await account.注销(credential: credential, challenge: challenge)
            } catch {
                if (error as? ASAuthorizationError)?.code != .canceled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

/// 液态玻璃胶囊按钮：苹果标志与“通过Apple登录”，样式按 Sign in with Apple 的规范用黑色（深色模式白色）。
/// Paper账户页面和新功能介绍共用。
struct Paper账户登录按钮: View {
    @Binding var errorMessage: String?

    @ObservedObject private var account = PaperAccount账户.shared
    @EnvironmentObject private var auth: 用户登录
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.authorizationController) private var authorizationController

    var body: some View {
        let 按钮 = Button {
            signIn()
        } label: {
            Label("通过Apple登录", systemImage: "apple.logo")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(colorScheme == .dark ? .white : .black)
        .disabled(account.正在登录)

        if #available(iOS 26.0, *) {
            按钮.buttonStyle(.glassProminent)
        } else {
            按钮.buttonStyle(.borderedProminent)
        }
    }

    private func signIn() {
        Task {
            do {
                if account.登录挑战 == nil { await account.准备登录() }
                guard let challenge = account.登录挑战 else { throw PaperAccount错误.无效响应 }
                let request = ASAuthorizationAppleIDProvider().createRequest()
                request.requestedScopes = [.fullName]
                request.nonce = PaperAccount账户.nonce(challenge)
                guard case let .appleID(credential) = try await authorizationController.performRequest(request) else { return }
                try await account.登录(credential: credential, vndbToken: auth.isLoggedIn ? auth.token : "")
            } catch {
                if (error as? ASAuthorizationError)?.code != .canceled {
                    errorMessage = error.localizedDescription
                }
                await account.准备登录()
            }
        }
    }
}

/// “高级数据保护”开关：打开时先确认并设置恢复密钥，关闭时先确认，开关在操作完成后才变。
/// Paper账户页面和新功能介绍共用。
struct 高级数据保护开关: View {
    @Binding var errorMessage: String?

    @ObservedObject private var account = PaperAccount账户.shared
    @State private var confirmsProtection = false
    @State private var confirmsDisablingProtection = false
    @State private var protectionSetup: 高级数据保护设置流程.起始页?

    var body: some View {
        Toggle("高级数据保护", isOn: Binding(
            get: { account.已开启高级数据保护 },
            set: { if $0 { confirmsProtection = true } else { confirmsDisablingProtection = true } }
        ))
        .disabled(!account.自动备份 && !account.已开启高级数据保护)
        .alert("为你的数据负责", isPresented: $confirmsProtection) {
            Button("取消", role: .cancel) {}
            Button("进一步了解") { protectionSetup = .介绍 }
            Button("继续") { protectionSetup = .恢复密钥 }
        } message: {
            Text("如果你无法访问自己的受信任设备，开发者将没有加密密钥来协助你进行恢复；你需要使用自己的恢复密钥。由于你的大多数Paper Cloud数据将受端对端加密保护，因此PaperVN将引导你设置一个恢复密钥。")
        }
        .alert("要关闭高级数据保护吗？", isPresented: $confirmsDisablingProtection) {
            Button("取消", role: .cancel) {}
            Button("关闭高级数据保护") { disableProtection() }
        } message: {
            Text("你的Paper Cloud数据将不再受端对端加密保护，开发者将能够协助你恢复这些数据。")
        }
        .sheet(item: $protectionSetup) { start in
            高级数据保护设置流程(起点: start)
        }
    }

    private func disableProtection() {
        Task {
            do {
                try await account.关闭高级数据保护()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct PaperAccount昵称页面: View {
    @State var nickname: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        平台滚动页面 {
            Section {
                TextField("昵称", text: $nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text(verbatim: errorMessage ?? String(localized: "最多30个字符。"))
            }
        }
        .平台分组列表样式()
        .navigationTitle("昵称")
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    isSaving = true
                    Task {
                        defer { isSaving = false }
                        do {
                            try await PaperAccount账户.shared.修改昵称(nickname)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(isSaving || nickname.count > 30)
            }
        }
    }
}

extension 高级数据保护设置流程.起始页: Identifiable {
    var id: Self { self }
}
