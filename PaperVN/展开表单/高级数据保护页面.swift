import SwiftUI

/// 开启高级数据保护的弹出页面：（关于高级数据保护 →）恢复密钥 → 确认恢复密钥。确认无误后才真正开启。
struct 高级数据保护设置流程: View {
    enum 起始页 { case 介绍, 恢复密钥 }

    let 起点: 起始页
    @Environment(\.dismiss) private var dismiss
    @State private var path: [步骤] = []
    /// 整个流程只生成一次，返回上一步再继续看到的还是同一个恢复密钥。
    @State private var recoveryKey = 高级数据保护.生成恢复密钥()

    private enum 步骤: Hashable { case 恢复密钥, 确认 }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch 起点 {
                case .介绍: 关于高级数据保护页面 { path.append(.恢复密钥) }
                case .恢复密钥: 恢复密钥页面(recoveryKey: recoveryKey) { path.append(.确认) }
                }
            }
            .toolbar { 关闭按钮 }
            .navigationDestination(for: 步骤.self) { step in
                switch step {
                case .恢复密钥: 恢复密钥页面(recoveryKey: recoveryKey) { path.append(.确认) }
                case .确认:
                    恢复密钥输入页面(标题: "确认恢复密钥", 说明: "输入你的恢复密钥以确认其已被安全保管。", 按钮: "打开") { input in
                        guard input == recoveryKey else { throw 高级数据保护.错误.恢复密钥不正确 }
                        try await PaperAccount账户.shared.开启高级数据保护(恢复密钥: recoveryKey)
                        dismiss()
                    }
                }
            }
        }
        .平台近全屏弹窗()
    }

    private var 关闭按钮: some ToolbarContent {
        ToolbarItem(placement: .平台前导关闭操作) {
            Button {
                dismiss()
            } label: {
                Label("取消", systemImage: "xmark")
            }
        }
    }
}

/// 在不是受信任设备的设备上输入恢复密钥。
struct 输入恢复密钥页面: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            恢复密钥输入页面(
                标题: "输入恢复密钥",
                说明: "此账户已打开高级数据保护。输入恢复密钥以在此设备上访问Paper Cloud数据。",
                按钮: "完成"
            ) { input in
                try await PaperAccount账户.shared.输入恢复密钥(input)
                dismiss()
            }
            .toolbar {
                ToolbarItem(placement: .平台前导关闭操作) {
                    Button {
                        dismiss()
                    } label: {
                        Label("取消", systemImage: "xmark")
                    }
                }
            }
        }
        .平台近全屏弹窗()
    }
}

private struct 关于高级数据保护页面: View {
    let 继续: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                设置类别介绍(
                    title: "高级数据保护",
                    description: "高级数据保护是一项可选设置，用于提供Paper Cloud最高级别的数据安全。",
                    systemImage: "lock.shield.fill",
                    color: .blue
                )
                .padding(.bottom, 8)

                Text("如果你选择启用“高级数据保护”，那么对于你的大多数Paper Cloud数据，只有你的受信任设备可以访问对应的加密密钥，因此这些Paper Cloud数据均受端对端加密保护。")
                Text("端对端加密数据只能在你已登录Paper账户的受信任设备上解密。任何其他人，甚至是开发者，都无法访问你的端对端加密数据，并且即使云端发生数据泄露，这些数据也是安全的。")
                Text("如果你无法访问自己的受信任设备，只有你自己可以使用恢复密钥来恢复这些数据。")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("关于高级数据保护")
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                主题色工具栏按钮(title: "继续", systemImage: "lock.fill", action: 继续)
            }
        }
    }
}

private struct 恢复密钥页面: View {
    let recoveryKey: String
    let 继续: () -> Void

    /// 7组分两行显示，每行用连字符连接。
    private var 行: [String] {
        let groups = 高级数据保护.格式化(recoveryKey).split(separator: "-").map(String.init)
        return [groups.prefix(4), groups.dropFirst(4)].map { $0.joined(separator: "-") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                设置类别介绍(
                    title: "恢复密钥",
                    description: "恢复密钥是一个由28个字符组成的秘密代码，你可以使用它来恢复自己的Paper Cloud数据。请妥善保管此恢复密钥，如果你无法访问自己的受信任设备，开发者将没有加密密钥来协助你进行恢复。",
                    systemImage: "key.fill",
                    color: .gray
                )

                // 显示成两行，按住拷贝的是完整的一行
                Text(verbatim: 行.joined(separator: "\n"))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = 高级数据保护.格式化(recoveryKey)
                        } label: {
                            Label("拷贝", systemImage: "doc.on.doc")
                        }
                    }
                    .accessibilityLabel(Text(verbatim: recoveryKey.map(String.init).joined(separator: " ")))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle("恢复密钥")
        .平台内联导航标题()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                主题色工具栏按钮(title: "继续", systemImage: "arrow.right", action: 继续)
            }
        }
    }
}

private struct 恢复密钥输入页面: View {
    let 标题: LocalizedStringKey
    let 说明: LocalizedStringKey
    let 按钮: LocalizedStringKey
    /// 传入规范化后的恢复密钥；抛出的错误显示在输入框下方。
    let 完成: (String) async throws -> Void

    @State private var input = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                设置类别介绍(title: 标题, description: 说明, systemImage: "key.fill", color: .gray)

                VStack(alignment: .leading, spacing: 8) {
                    TextField(text: $input, axis: .vertical) {
                        Text(verbatim: "XXXX-XXXX-XXXX-XXXX-XXXX-XXXX-XXXX")
                    }
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focused)
                    .padding(16)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: input) { errorMessage = nil }

                    if let errorMessage {
                        Text(verbatim: errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(标题)
        .平台内联导航标题()
        .onAppear { focused = true }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isWorking {
                    ProgressView()
                } else {
                    主题色工具栏按钮(title: 按钮, systemImage: "checkmark", action: submit)
                        .disabled(高级数据保护.规范化(input) == nil)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private func submit() {
        guard let key = 高级数据保护.规范化(input) else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await 完成(key)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 工具栏右上角的主题色按钮：iOS 26 起是液态玻璃，iOS 18 是实心按钮。
private struct 主题色工具栏按钮: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        if #available(iOS 26.0, *) {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }
}
