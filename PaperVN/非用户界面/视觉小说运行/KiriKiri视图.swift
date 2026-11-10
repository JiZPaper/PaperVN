import KiriKiri
import SwiftUI
import UIKit

/// KiriKiri（吉里吉里）的视觉小说，由 krkr2（MIT）运行。
/// krkr2 基于 cocos2d-x，画在 CAEAGLLayer 上，画面只能包一个 UIView；其余界面都在 SwiftUI 里。
/// cocos2d-x 和引擎都是单例，同时只能运行一部；退出后可以运行下一部。
@MainActor
@Observable
final class KiriKiri运行控制 {
    /// 游戏弹出的提示框或输入框
    struct 系统对话框: Identifiable {
        let id = UUID()
        let 是输入框: Bool
        let 标题: String
        let 内容: String
        var 文字: String
        let 按钮: [String]
    }

    /// 含 startup.tjs 的文件夹，或 data.xp3
    let 入口: URL
    let 数据文件夹: URL
    private(set) var 已结束 = false
    private(set) var 错误: String?
    var 对话框: 系统对话框?
    var 快进 = false {
        didSet {
            guard 快进 != oldValue, 已启动 else { return }
            // KAG 按住 Ctrl 快进
            papervn_kirikiri_set_fast_forward(快进 ? 1 : 0)
        }
    }

    fileprivate var 已启动 = false
    private var 启动代次: UInt64?

    init(入口: URL, 数据文件夹: URL) {
        self.入口 = 入口
        self.数据文件夹 = 数据文件夹
    }

    func 暂停(_ paused: Bool) {
        guard 已启动 else { return }
        papervn_kirikiri_set_paused(paused ? 1 : 0)
    }

    /// 游戏的窗口菜单（保存、加载等常在这里）。没有窗口菜单时返回空
    func 读取菜单() -> [KiriKiri菜单项] {
        guard 已启动, let pointer = papervn_kirikiri_copy_game_menu() else { return [] }
        defer { free(pointer) }
        return (try? JSONDecoder().decode([KiriKiri菜单项].self, from: Data(String(cString: pointer).utf8))) ?? []
    }

    func 点按菜单项(_ item: KiriKiri菜单项) {
        guard 已启动 else { return }
        item.path.withCString { papervn_kirikiri_click_game_menu($0) }
    }

    /// 触屏没有鼠标右键。多数 KAG 游戏用它隐藏文字或打开系统菜单
    func 辅助点按() {
        guard 已启动 else { return }
        papervn_kirikiri_secondary_click()
    }

    func 回答(_ button: Int) {
        guard let dialog = 对话框 else { return }
        对话框 = nil
        dialog.文字.withCString { papervn_kirikiri_answer_dialog(Int32(button), dialog.是输入框 ? $0 : nil) }
    }

    func 停止() {
        guard 已启动, !已结束, let 启动代次 else { return }
        papervn_kirikiri_stop_session(启动代次)
    }

    fileprivate func 启动() {
        guard !已启动 else { return }
        已启动 = true
        let user = Unmanaged.passUnretained(self).toOpaque()
        let result = 入口.path.withCString { game in
            数据文件夹.path.withCString { data in
                视觉小说运行资源.准备KiriKiri目录().withCString { resources in
                    papervn_kirikiri_start(game, data, resources, { userData, _ in
                        guard let userData else { return }
                        nonisolated(unsafe) let pointer = userData
                        Task { @MainActor in
                            Unmanaged<KiriKiri运行控制>.fromOpaque(pointer).takeUnretainedValue().已结束 = true
                        }
                    }, { userData, kind, title, message, text, buttons, count in
                        guard let userData else { return }
                        let dialog = 系统对话框(
                            是输入框: kind == 1,
                            标题: title.map { String(cString: $0) } ?? "",
                            内容: message.map { String(cString: $0) } ?? "",
                            文字: text.map { String(cString: $0) } ?? "",
                            按钮: (0..<Int(count)).map { buttons?[$0].map { String(cString: $0) } ?? "" }
                        )
                        // 引擎在主线程上转嵌套的 run loop 等回答，这里已经在主线程
                        MainActor.assumeIsolated {
                            Unmanaged<KiriKiri运行控制>.fromOpaque(userData).takeUnretainedValue().对话框 = dialog
                        }
                    }, user)
                }
            }
        }
        switch result {
        case 0: 启动代次 = papervn_kirikiri_session_id()
        default: 错误 = String(localized: "无法运行此视觉小说。")
        }
    }
}

/// 游戏窗口菜单（Windows 版的菜单栏）里的一项
nonisolated struct KiriKiri菜单项: Decodable, Identifiable, Hashable {
    let path: String
    let title: String
    let enabled: Bool
    let checked: Bool
    let children: [KiriKiri菜单项]

    var id: String { path }
    var 是分隔线: Bool { title == "-" }
    /// 去掉快捷键标记：“システム(&S)”“&Save”
    var 名称: String {
        title.replacing(/[(（]&.[)）]/, with: "").replacing("&", with: "")
    }
}

/// 游戏窗口菜单。第一层有子项的项目作为分组
struct KiriKiri游戏菜单页面: View {
    let 项目: [KiriKiri菜单项]
    let 选择: (KiriKiri菜单项) -> Void
    @Environment(\.dismiss) private var dismiss

    /// 第一层只有一个字符的项目是 Windows 菜单栏上的窗口控制（如 9-nine 的“x”，点按后变成“+”），在这里没有意义
    private var 单独项目: [KiriKiri菜单项] { 项目.filter { $0.children.isEmpty && !$0.是分隔线 && $0.名称.count > 1 } }
    private var 分组: [KiriKiri菜单项] { 项目.filter { !$0.children.isEmpty } }

    var body: some View {
        NavigationStack {
            List {
                if !单独项目.isEmpty {
                    Section { 行列表(单独项目) }
                }
                ForEach(分组) { group in
                    Section {
                        行列表(group.children)
                    } header: {
                        Text(verbatim: group.名称)
                    }
                }
            }
            .navigationTitle("游戏菜单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .平台关闭操作) {
                    Button {
                        dismiss()
                    } label: {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
        }
    }

    // 子菜单是递归的，这里不能用 some View
    private func 行列表(_ items: [KiriKiri菜单项]) -> AnyView {
        AnyView(ForEach(items.filter { !$0.是分隔线 }) { item in
            if item.children.isEmpty {
                Button {
                    选择(item)
                } label: {
                    HStack {
                        Text(verbatim: item.名称)
                        Spacer()
                        if item.checked {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
                .disabled(!item.enabled)
            } else {
                NavigationLink {
                    List { 行列表(item.children) }
                        .navigationTitle(Text(verbatim: item.名称))
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Text(verbatim: item.名称)
                }
                .disabled(!item.enabled)
            }
        })
    }
}

struct KiriKiri视图: UIViewRepresentable {
    let 控制: KiriKiri运行控制

    func makeUIView(context: Context) -> KiriKiri容器视图 {
        KiriKiri容器视图(控制: 控制)
    }

    func updateUIView(_ uiView: KiriKiri容器视图, context: Context) {}

    static func dismantleUIView(_ uiView: KiriKiri容器视图, coordinator: ()) {
        uiView.控制?.停止()
    }
}

/// 第一次有尺寸时创建 cocos2d-x 的画面并启动引擎。
final class KiriKiri容器视图: UIView {
    fileprivate weak var 控制: KiriKiri运行控制?
    private var 画面: UIView?

    init(控制: KiriKiri运行控制) {
        self.控制 = 控制
        super.init(frame: .zero)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if let 画面 {
            画面.frame = bounds
            return
        }
        guard let 控制, !控制.已启动 else { return }
        // cocos2d-x 按创建时的尺寸定分辨率；iPhone 上等运行页面转到横屏再创建
        if UIDevice.current.userInterfaceIdiom == .phone, bounds.width < bounds.height { return }
        let scale = window?.screen.scale ?? traitCollection.displayScale
        guard let pointer = papervn_kirikiri_create_view(bounds.width, bounds.height, scale) else { return }
        let view = Unmanaged<UIView>.fromOpaque(pointer).takeRetainedValue()
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
        画面 = view
        控制.启动()
    }
}

/// 启动前检查 XP3 封包：商业版常用哈希文件名（目录里的 hnfn 块）配合加密，krkr2 读不了；
/// 模拟器适配版是普通文件名，或附带解密脚本 xp3filter.tjs。
/// info 块 flags 的最高位只是“保护”标记（不让解包工具导出），不代表加密，不能拿来判断。
nonisolated enum KiriKiri封包检查 {
    /// 交给引擎的入口：有 startup.tjs 用文件夹，否则用 data.xp3
    static func 入口(_ root: URL) -> URL? {
        let names = Dictionary(
            ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if names["startup.tjs"] != nil { return root }
        if let data = names["data.xp3"] { return root.appending(path: data) }
        return nil
    }

    static func 检查(_ root: URL) throws {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        if names.contains(where: { $0.lowercased() == "xp3filter.tjs" }) { return }
        guard let data = names.first(where: { $0.lowercased() == "data.xp3" }) else { return }
        if (try? 使用哈希文件名(root.appending(path: data))) == true {
            throw 视觉小说运行错误.无法读取(String(localized: "此视觉小说的封包已加密，请使用适配模拟器的版本。"))
        }
    }

    /// XP3 目录里有没有哈希文件名的块。
    private static func 使用哈希文件名(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        func read(_ count: Int) throws -> Data { try handle.read(upToCount: count) ?? Data() }
        func u64(_ data: Data, _ offset: Int) -> UInt64 {
            data[data.startIndex + offset ..< data.startIndex + offset + 8].enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * $1.offset) }
        }
        let header = try read(19)
        guard header.count == 19, header.prefix(3) == Data("XP3".utf8) else { return false }
        var offset = u64(header, 11)
        try handle.seek(toOffset: offset)
        var flag = try read(1).first ?? 0
        if flag == 0x80 {
            // 吉里吉里2.30 之后的格式：先跳过一段再读真正的目录位置
            _ = try read(8)
            offset = u64(try read(8), 0)
            try handle.seek(toOffset: offset)
            flag = try read(1).first ?? 0
        }
        let index: Data
        if flag & 7 == 1 {
            let sizes = try read(16)
            let compressed = try read(Int(u64(sizes, 0)))
            index = try (compressed.dropFirst(2) as NSData).decompressed(using: .zlib) as Data
        } else {
            index = try read(Int(u64(try read(8), 0)))
        }
        let hashedNameTags: Set<Data> = [Data("hnfn".utf8), Data("Hxv4".utf8)]
        var i = index.startIndex
        while i + 12 <= index.endIndex {
            if hashedNameTags.contains(index[i ..< i + 4]) { return true }
            i += 12 + Int(u64(index, i - index.startIndex + 4))
        }
        return false
    }
}
