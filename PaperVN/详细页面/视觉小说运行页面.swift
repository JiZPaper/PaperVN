import SwiftUI
import UIKit

/// 全屏运行视觉小说。iPhone 运行横版游戏时切到横屏（界面方向.swift），离开时切回竖屏。
struct 视觉小说运行页面: View {
    let vnID: String
    let 标题: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var 状态: 运行状态 = .载入中
    @State private var 显示退出确认 = false
    @State private var NScripter界面: NScripter系统请求?
    @State private var 正在访问的文件夹: URL?
    @State private var 兼容问题: [视觉小说兼容问题] = []
    @State private var 显示兼容提示 = false
    @State private var KiriKiri菜单: [KiriKiri菜单项]?
    @State private var 待点按菜单项: KiriKiri菜单项?

    private enum 运行状态 {
        case 载入中
        case 网页(网页游戏资源)
        case siglus(Siglus运行控制)
        case kirikiri(KiriKiri运行控制)
        case 帧缓冲(帧缓冲游戏控制)
        case yuris(YURIS运行控制)
        case nscripter(NScripter解释器)
        case 错误(String)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            内容
                .ignoresSafeArea()
            // 按钮留在安全区域内，横屏时不会被灵动岛和圆角挡住
            菜单按钮
                .padding(12)
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .task { await 载入() }
        .onAppear { 界面方向.切换(横版 ? .landscape : .portrait) }
        .onChange(of: 横版) { _, landscape in 界面方向.切换(landscape ? .landscape : .portrait) }
        .onDisappear { 结束() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                视觉小说游玩记录.shared.开始(作品: vnID)
                if case .nscripter(let interpreter) = 状态 { interpreter.进入后台(false) }
                if case .siglus(let control) = 状态 { control.暂停(false) }
                if case .kirikiri(let control) = 状态 { control.暂停(false) }
                if case .帧缓冲(let control) = 状态 { control.暂停(false) }
                if case .yuris(let control) = 状态 { control.暂停(false) }
            case .background:
                视觉小说游玩记录.shared.结束()
                if case .nscripter(let interpreter) = 状态 { interpreter.进入后台(true) }
                if case .siglus(let control) = 状态 { control.暂停(true) }
                if case .kirikiri(let control) = 状态 { control.暂停(true) }
                if case .帧缓冲(let control) = 状态 { control.暂停(true) }
                if case .yuris(let control) = 状态 { control.暂停(true) }
            default:
                break
            }
        }
        .alert("可能与预期效果不符", isPresented: $显示兼容提示) {
            Button("不再显示") {
                不再提示(兼容问题)
                开始运行()
            }
            Button("好", role: .cancel) { 开始运行() }
        } message: {
            Text(verbatim: 兼容问题.map(\.说明).joined(separator: "\n"))
        }
        .sheet(isPresented: Binding(get: { KiriKiri菜单 != nil }, set: { if !$0 { KiriKiri菜单 = nil } }), onDismiss: {
            // 等菜单关闭后再点按：游戏可能马上弹出提示框或切换画面
            if let item = 待点按菜单项, case .kirikiri(let control) = 状态 { control.点按菜单项(item) }
            待点按菜单项 = nil
        }) {
            KiriKiri游戏菜单页面(项目: KiriKiri菜单 ?? []) { item in
                待点按菜单项 = item
                KiriKiri菜单 = nil
            }
            .平台近全屏弹窗()
        }
        .sheet(item: $NScripter界面, onDismiss: 系统界面关闭) { request in
            if case .nscripter(let interpreter) = 状态 {
                Group {
                    switch request {
                    case .存储: NScripter存档页面(解释器: interpreter, 模式: .保存) { NScripter界面 = nil }
                    case .载入: NScripter存档页面(解释器: interpreter, 模式: .加载) { NScripter界面 = nil }
                    case .回想, .菜单: NScripter历史记录页面(解释器: interpreter) { NScripter界面 = nil }
                    }
                }
                .平台近全屏弹窗()
            }
        }
    }

    @ViewBuilder
    private var 内容: some View {
        ZStack(alignment: .topTrailing) {
            switch 状态 {
            case .载入中:
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .网页(let resources):
                网页游戏视图(资源: resources, vnID: vnID)
            case .kirikiri(let control):
                KiriKiri视图(控制: control)
                    .onChange(of: control.已结束) { _, ended in
                        if ended { dismiss() }
                    }
                    .overlay {
                        if let message = control.错误 {
                            错误提示(message)
                        }
                    }
                    .alert(
                        control.对话框?.标题 ?? "",
                        isPresented: Binding(get: { control.对话框 != nil }, set: { _ in }),
                        presenting: control.对话框
                    ) { dialog in
                        if dialog.是输入框 {
                            TextField("", text: Binding(
                                get: { control.对话框?.文字 ?? "" },
                                set: { control.对话框?.文字 = $0 }
                            ))
                        }
                        ForEach(Array(dialog.按钮.enumerated()), id: \.offset) { index, title in
                            Button(title) { control.回答(index) }
                        }
                        if dialog.按钮.isEmpty {
                            Button("好") { control.回答(0) }
                        }
                    } message: { dialog in
                        Text(verbatim: dialog.内容)
                    }
            case .帧缓冲(let control):
                帧缓冲游戏视图(控制: control)
                    .onChange(of: control.已结束) { _, ended in
                        if ended { dismiss() }
                    }
                    .overlay {
                        if let message = control.错误 {
                            错误提示(message)
                        }
                    }
            case .yuris(let control):
                YURIS游戏视图(控制: control)
                    .onChange(of: control.已结束) { _, ended in
                        if ended { dismiss() }
                    }
                    .overlay {
                        if let message = control.错误 {
                            错误提示(message)
                        }
                    }
                    .alert(
                        control.对话框?.请求.标题 ?? "",
                        isPresented: Binding(get: { control.对话框 != nil }, set: { _ in }),
                        presenting: control.对话框
                    ) { dialog in
                        switch dialog.请求.类型 {
                        case 1:
                            Button("是") { control.回答(1) }
                            Button("否", role: .cancel) { control.回答(2) }
                        case 2:
                            Button("好") { control.回答(1) }
                            Button("取消", role: .cancel) { control.回答(2) }
                        case 3:
                            Button("是") { control.回答(1) }
                            Button("否") { control.回答(2) }
                            Button("取消", role: .cancel) { control.回答(3) }
                        default:
                            Button("好", role: .cancel) { control.回答(1) }
                        }
                    } message: { dialog in
                        Text(verbatim: dialog.请求.内容)
                    }
            case .siglus(let control):
                Siglus视图(控制: control)
                    .onChange(of: control.已结束) { _, ended in
                        if ended { dismiss() }
                    }
                    .overlay {
                        if let message = control.错误 {
                            错误提示(message)
                        }
                    }
                    .alert(
                        control.对话框?.标题 ?? "",
                        isPresented: Binding(get: { control.对话框 != nil }, set: { if !$0 { control.对话框 = nil } }),
                        presenting: control.对话框
                    ) { dialog in
                        switch dialog.类型 {
                        case 1:
                            Button("好") { control.回答(0) }
                            Button("取消", role: .cancel) { control.回答(1) }
                        case 2:
                            Button("是") { control.回答(0) }
                            Button("否", role: .cancel) { control.回答(1) }
                        case 3:
                            Button("是") { control.回答(0) }
                            Button("否") { control.回答(1) }
                            Button("取消", role: .cancel) { control.回答(2) }
                        default:
                            Button("好", role: .cancel) { control.回答(0) }
                        }
                    } message: { dialog in
                        Text(verbatim: dialog.内容)
                    }
            case .nscripter(let interpreter):
                NScripter视图(解释器: interpreter)
                    .onChange(of: interpreter.已结束) { _, ended in
                        if ended { dismiss() }
                    }
                    .onChange(of: interpreter.系统请求) { _, request in
                        guard let request else { return }
                        if request == .菜单 {
                            // 脚本请求右键菜单：PaperVN 的菜单就在右上角，直接继续
                            interpreter.系统请求完成()
                        } else {
                            NScripter界面 = request
                        }
                    }
                    .overlay {
                        if let message = interpreter.错误 {
                            错误提示(message)
                        }
                    }
            case .错误(let message):
                错误提示(message)
            }
        }
    }

    private var 菜单按钮: some View {
        Menu {
            if case .nscripter(let interpreter) = 状态 {
                Button {
                    NScripter界面 = .存储
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }
                .disabled(!interpreter.可以存档)
                Button {
                    NScripter界面 = .载入
                } label: {
                    Label("加载", systemImage: "square.and.arrow.up")
                }
                Button {
                    NScripter界面 = .回想
                } label: {
                    Label("历史记录", systemImage: "text.alignleft")
                }
                Divider()
                Toggle(isOn: Binding(get: { interpreter.快进 }, set: { interpreter.快进 = $0; if $0 { interpreter.自动 = false; interpreter.轻点(nil) } })) {
                    Label("快进", systemImage: "forward")
                }
                Toggle(isOn: Binding(get: { interpreter.自动 }, set: { interpreter.自动 = $0; if $0 { interpreter.快进 = false } })) {
                    Label("自动", systemImage: "play")
                }
                Divider()
            }
            if case .siglus(let control) = 状态 {
                Button {
                    control.打开菜单()
                } label: {
                    Label("游戏菜单", systemImage: "list.bullet")
                }
                Toggle(isOn: Binding(get: { control.快进 }, set: { control.快进 = $0 })) {
                    Label("快进", systemImage: "forward")
                }
                Divider()
            }
            if case .帧缓冲(let control) = 状态 {
                Button {
                    control.打开菜单()
                } label: {
                    Label("游戏菜单", systemImage: "list.bullet")
                }
                Button {
                    control.辅助点按()
                } label: {
                    Label("辅助点按", systemImage: "cursorarrow.click.2")
                }
                Toggle(isOn: Binding(get: { control.快进 }, set: { control.快进 = $0 })) {
                    Label("快进", systemImage: "forward")
                }
                Divider()
            }
            if case .yuris(let control) = 状态 {
                Button {
                    control.辅助点按()
                } label: {
                    Label("辅助点按", systemImage: "cursorarrow.click.2")
                }
                Toggle(isOn: Binding(get: { control.快进 }, set: { control.快进 = $0 })) {
                    Label("快进", systemImage: "forward")
                }
                Divider()
            }
            if case .kirikiri(let control) = 状态 {
                Button {
                    // 没有窗口菜单的游戏大多用右键打开系统菜单
                    let items = control.读取菜单()
                    if items.isEmpty {
                        control.辅助点按()
                    } else {
                        KiriKiri菜单 = items
                    }
                } label: {
                    Label("游戏菜单", systemImage: "list.bullet")
                }
                Button {
                    control.辅助点按()
                } label: {
                    Label("辅助点按", systemImage: "cursorarrow.click.2")
                }
                Toggle(isOn: Binding(get: { control.快进 }, set: { control.快进 = $0 })) {
                    Label("快进", systemImage: "forward")
                }
                Divider()
            }
            Button(role: .destructive) {
                switch 状态 {
                case .nscripter, .siglus, .kirikiri, .帧缓冲, .yuris: 显示退出确认 = true
                default: dismiss()
                }
            } label: {
                Label("退出", systemImage: "xmark")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .液态玻璃(.regular.interactive(), in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel("更多")
        .confirmationDialog("要退出吗？", isPresented: $显示退出确认, titleVisibility: .visible) {
            Button("退出", role: .destructive) { dismiss() }
        } message: {
            Text("尚未保存的进度将会丢失。")
        }
    }

    private func 错误提示(_ message: String) -> some View {
        ContentUnavailableView {
            Label("无法运行视觉小说", systemImage: "exclamationmark.triangle")
        } description: {
            Text(verbatim: message)
        } actions: {
            Button("关闭") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    /// 绝大多数视觉小说是横版；NScripter 的脚本写明了画面大小，竖版的保持竖屏。载入中也先用横屏，免得载入完再转一次。
    private var 横版: Bool {
        if case .nscripter(let interpreter) = 状态 { return interpreter.屏幕宽 >= interpreter.屏幕高 }
        return true
    }

    private func 系统界面关闭() {
        if case .nscripter(let interpreter) = 状态, interpreter.系统请求 != nil {
            interpreter.系统请求完成()
        }
    }

    private func 载入() async {
        do {
            let center = 视觉小说文件夹中心.shared
            let folder = try center.文件夹地址(作品: vnID)
            if folder.startAccessingSecurityScopedResource() { 正在访问的文件夹 = folder }
            var recognition = center.记录(作品: vnID)?.识别
            if recognition == nil || recognition?.引擎.可运行 == false {
                // 文件夹的内容可能变了（例如刚下载完），再识别一次
                recognition = await center.重新识别(作品: vnID)
            }
            guard let recognition else { throw 视觉小说运行错误.无法识别 }
            let root = recognition.根目录.isEmpty ? folder : folder.appending(path: recognition.根目录, directoryHint: .isDirectory)
            switch recognition.引擎.运行方式 {
            case .网页:
                guard let package = recognition.网页包 else { throw 视觉小说运行错误.无法识别 }
                let resources = try await Task.detached(priority: .userInitiated) {
                    try 网页游戏资源(游戏文件夹: folder, 包: package)
                }.value
                状态 = .网页(resources)
            case .nscripter:
                let interpreter = try await NScripter解释器.载入(
                    游戏根目录: root, 数据文件夹: 视觉小说文件夹中心.数据文件夹(作品: vnID)
                )
                状态 = .nscripter(interpreter)
                // 有和原版不一样的地方时先提示，看完再开始，免得声音和开场在提示后面播放
                let ignored = Set(UserDefaults.standard.stringArray(forKey: 不再提示键) ?? [])
                兼容问题 = interpreter.兼容问题.filter { !ignored.contains($0.标识) }
                if 兼容问题.isEmpty { interpreter.开始() } else { 显示兼容提示 = true }
            case .siglus:
                let data = 视觉小说文件夹中心.数据文件夹(作品: vnID)
                let project = try await Task.detached(priority: .userInitiated) {
                    let project = try Siglus项目目录.准备(游戏根目录: root, 数据文件夹: data)
                    try Siglus运行控制.检查密钥(project)
                    return project
                }.value
                状态 = .siglus(Siglus运行控制(项目目录: project))
            case .kirikiri:
                let entry = try await Task.detached(priority: .userInitiated) {
                    try KiriKiri封包检查.检查(root)
                    guard let entry = KiriKiri封包检查.入口(root) else { throw 视觉小说运行错误.无法识别 }
                    return entry
                }.value
                let data = 视觉小说文件夹中心.数据文件夹(作品: vnID).appending(path: "KiriKiri", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
                状态 = .kirikiri(KiriKiri运行控制(入口: entry, 数据文件夹: data))
            case .帧缓冲:
                let data = 视觉小说文件夹中心.数据文件夹(作品: vnID)
                let project = try await Task.detached(priority: .userInitiated) {
                    try 帧缓冲项目目录.准备(游戏根目录: root, 数据文件夹: data)
                }.value
                状态 = .帧缓冲(帧缓冲游戏控制(游戏目录: project, 引擎: recognition.引擎.帧缓冲引擎名))
            case .renPy:
                let resources = try await Task.detached(priority: .userInitiated) {
                    try 网页游戏资源(RenPy游戏根目录: root)
                }.value
                状态 = .网页(resources)
            case .yuris:
                let saves = 视觉小说文件夹中心.数据文件夹(作品: vnID).appending(path: "YURIS", directoryHint: .isDirectory)
                try? FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
                状态 = .yuris(YURIS运行控制(游戏目录: root, 存档目录: saves))
            case nil:
                throw 视觉小说运行错误.暂不支持(recognition.引擎)
            }
            视觉小说游玩记录.shared.开始(作品: vnID)
            // 之前没传上去的游玩时间趁这时重试
            Task { await 视觉小说游玩记录.shared.上传() }
        } catch {
            状态 = .错误(error.localizedDescription)
        }
    }

    private var 不再提示键: String { "视觉小说运行.不再提示.\(vnID.lowercased())" }

    /// 只记住这次提示的问题；以后文件夹换了、出现新的问题时还会提示。
    private func 不再提示(_ issues: [视觉小说兼容问题]) {
        let ignored = Set(UserDefaults.standard.stringArray(forKey: 不再提示键) ?? []).union(issues.map(\.标识))
        UserDefaults.standard.set(ignored.sorted(), forKey: 不再提示键)
    }

    private func 开始运行() {
        if case .nscripter(let interpreter) = 状态 { interpreter.开始() }
    }

    private func 结束() {
        视觉小说游玩记录.shared.结束()
        if case .nscripter(let interpreter) = 状态 { interpreter.停止() }
        正在访问的文件夹?.stopAccessingSecurityScopedResource()
        正在访问的文件夹 = nil
        界面方向.切换(.portrait)
    }
}
