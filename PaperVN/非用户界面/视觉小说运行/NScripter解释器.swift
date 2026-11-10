import CoreGraphics
import CoreText
import Foundation
import Observation
import OSLog
import SwiftUI

// MARK: - 状态

nonisolated struct NScripter精灵: Codable, Equatable, Sendable {
    /// 带透明方式的完整标签，例如 `:a;image\tachi\foo.jpg`
    var 标签: String
    var x: Int
    var y: Int
    var 可见 = true
    var 透明度 = 255
    var 格 = 0
}

nonisolated struct NScripter场景: Codable, Equatable, Sendable {
    var 背景颜色: UInt32? = 0x000000
    var 背景图像: String?
    /// "l"、"c"、"r"
    var 立绘: [String: NScripter精灵] = [:]
    var 精灵: [Int: NScripter精灵] = [:]
    var 单色: UInt32?
    var 反色 = false
}

nonisolated struct NScripter文字片段: Codable, Equatable, Sendable, Identifiable {
    var 文字: String
    var 颜色: UInt32
    var id: String { "\(颜色)-\(文字)" }
}

nonisolated struct NScripter文本框: Codable, Equatable, Sendable {
    var 文字x = 8, 文字y = 16
    var 每行字数 = 23, 行数 = 16
    var 字宽 = 26, 字高 = 26
    var 字距 = 0, 行距 = 2
    var 速度 = 20
    var 粗体 = true, 阴影 = true
    /// 窗口颜色：NScripter 用乘法叠加，#999999 表示背景变暗到 60%
    var 窗口颜色: UInt32? = 0x999999
    var 窗口图像: String?
    var 窗口x1 = 0, 窗口y1 = 0, 窗口x2 = 639, 窗口y2 = 479
}

nonisolated enum NScripter等待: Equatable, Sendable {
    case 无
    case 点击(翻页: Bool)
    case 选择([String])
    case 按钮
    case 计时
}

nonisolated struct NScripter按钮: Equatable, Sendable, Identifiable {
    let 值: Int
    let 区域: CGRect
    /// btn 的按下图像（从 btndef 图上截取的位置），或 spbtn 的精灵编号
    let 按下图像: CGRect?
    let 精灵: Int?
    var id: Int { 值 }
}

nonisolated struct NScripter存档: Codable, Sendable {
    var 行: Int
    var 列: Int
    var 调用栈: [[Int]]
    var 循环栈: [NScripter循环]
    var 数值: [Int: Int]
    var 字符串: [Int: String]
    var 数组: [String: Int]
    var 场景: NScripter场景
    var 页面: [[NScripter文字片段]]
    var 文本框: NScripter文本框
    var 背景音乐: String?
    var 背景音乐循环: Bool
    var 时间: Date
    var 预览: String
}

nonisolated struct NScripter循环: Codable, Sendable {
    var 变量: Int
    var 终值: Int
    var 步长: Int
    var 行: Int
    var 列: Int
}

/// 命令参数的读取位置。
nonisolated struct NScripter游标 {
    var 字符: [Character]
    var i = 0

    init(_ characters: [Character]) { 字符 = characters }

    var 结束: Bool { i >= 字符.count }
    var 当前: Character? { i < 字符.count ? 字符[i] : nil }

    func 看(_ offset: Int = 0) -> Character? {
        i + offset < 字符.count ? 字符[i + offset] : nil
    }

    mutating func 跳过空白() {
        while let c = 当前, c == " " || c == "\t" { i += 1 }
    }

    @discardableResult
    mutating func 读(_ character: Character) -> Bool {
        跳过空白()
        guard 当前 == character else { return false }
        i += 1
        return true
    }

    mutating func 标识符() -> String {
        跳过空白()
        var result = ""
        while let c = 当前, c.isASCII, c.isLetter || c.isNumber || c == "_" {
            result.append(c)
            i += 1
        }
        return result
    }

    mutating func 是关键字(_ word: String) -> Bool {
        跳过空白()
        let saved = i
        if 标识符().lowercased() == word { return true }
        i = saved
        return false
    }
}

// MARK: - 解释器

/// NScripter（ONScripter）脚本解释器。覆盖常见的显示、文字、选项、按钮、变量、流程和声音命令；
/// 不认识的命令记录一次后跳过。画面状态由 `NScripter视图` 用 SwiftUI 显示。
@MainActor
@Observable
final class NScripter解释器 {
    @ObservationIgnored private static let logger = Logger(subsystem: "com.jizpaper.PaperVN", category: "NScripter")

    // 显示
    let 屏幕宽: Int
    let 屏幕高: Int
    private(set) var 显示场景 = NScripter场景()
    private(set) var 场景版本 = 0
    private(set) var 过渡类型 = 10
    private(set) var 过渡时长: Double = 0
    private(set) var 文本框 = NScripter文本框()
    private(set) var 文本框可见 = false
    private(set) var 页面: [[NScripter文字片段]] = []
    private(set) var 等待: NScripter等待 = .无
    private(set) var 按钮: [NScripter按钮] = []
    private(set) var 按钮图像: String?
    private(set) var 震动偏移: CGSize = .zero
    private(set) var 选择颜色: (选中: UInt32, 未选中: UInt32) = (0xffffff, 0x888888)
    private(set) var 字体名: String?
    /// 启动前检查出的和原版不一样的地方
    let 兼容问题: [视觉小说兼容问题]
    private(set) var 回想: [String] = []
    private(set) var 已结束 = false
    private(set) var 错误: String?
    var 快进 = false
    var 自动 = false
    /// 脚本执行了 systemcall（右键菜单、存储、载入等），由视图弹出对应界面
    var 系统请求: NScripter系统请求?

    @ObservationIgnored private(set) var 图像缓存: [String: NScripter图像] = [:]

    // 脚本
    @ObservationIgnored private let 脚本: NScripter脚本
    @ObservationIgnored let 资源: NScripter资源
    @ObservationIgnored private let 音频: NScripter音频
    @ObservationIgnored private let 数据文件夹: URL
    @ObservationIgnored private var 行 = 0
    @ObservationIgnored private var 列 = 0
    @ObservationIgnored private var 行缓存: (Int, [Character]) = (-1, [])
    @ObservationIgnored private var 调用栈: [[Int]] = []
    @ObservationIgnored private var 循环栈: [NScripter循环] = []
    @ObservationIgnored private var 数值: [Int: Int] = [:]
    @ObservationIgnored private var 字符串: [Int: String] = [:]
    @ObservationIgnored private var 数组: [String: Int] = [:]
    @ObservationIgnored private var 数值别名: [String: Int] = [:]
    @ObservationIgnored private var 字符串别名: [String: String] = [:]
    @ObservationIgnored private var 效果: [Int: (类型: Int, 时长: Int, 遮罩: String?)] = [:]
    @ObservationIgnored private var 自定义命令: Set<String> = []
    @ObservationIgnored private var 参数栈: [NScripter游标] = []
    @ObservationIgnored private var 待显示 = NScripter场景()
    @ObservationIgnored private var 默认速度 = 20
    @ObservationIgnored private var 当前速度 = 20
    @ObservationIgnored private var 文字颜色: UInt32 = 0xffffff
    @ObservationIgnored private var 当前行宽 = 0
    @ObservationIgnored private var 立即显示 = false
    @ObservationIgnored private var 计时起点 = Date.now
    @ObservationIgnored private var 擦除文本框 = true
    @ObservationIgnored private var 立绘层 = 499
    @ObservationIgnored private var 全局变量 = false
    @ObservationIgnored private var 已提示命令: Set<String> = []
    @ObservationIgnored private var 运行任务: Task<Void, Never>?
    @ObservationIgnored private var 输入: CheckedContinuation<Int, any Error>?
    @ObservationIgnored private var 输入编号 = 0
    @ObservationIgnored private var 系统请求等待: CheckedContinuation<Void, Never>?
    private(set) var 影片: URL?
    private(set) var 内置影片: 视觉小说影片?
    @ObservationIgnored private var 影片等待: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var 语句起点 = (0, 0)
    @ObservationIgnored private var 起点页面: [[NScripter文字片段]] = []
    @ObservationIgnored private var 起点场景 = NScripter场景()
    @ObservationIgnored private var 已执行 = 0
    @ObservationIgnored private var 允许存档 = true

    static let 全局变量起点 = 200

    init(脚本: NScripter脚本, 资源: NScripter资源, 数据文件夹: URL, 检查: NScripter兼容检查.结果) {
        self.脚本 = 脚本
        self.资源 = 资源
        self.数据文件夹 = 数据文件夹
        兼容问题 = 检查.问题
        屏幕宽 = 脚本.屏幕宽
        屏幕高 = 脚本.屏幕高
        FFmpeg影片后端.启用()
        音频 = NScripter音频(资源: 资源)
        文本框.窗口x2 = 屏幕宽 - 1
        文本框.窗口y2 = 屏幕高 - 1
        注册字体(检查.字体文件)
    }

    /// 在后台读取脚本和封包目录。
    static func 载入(游戏根目录 root: URL, 数据文件夹: URL) async throws -> NScripter解释器 {
        let (script, resources, check) = try await Task.detached(priority: .userInitiated) {
            let script = try NScripter脚本.载入(root)
            let resources = NScripter资源(根目录: root, 编码: script.编码)
            return (script, resources, NScripter兼容检查.检查(脚本: script, 资源: resources))
        }.value
        return NScripter解释器(脚本: script, 资源: resources, 数据文件夹: 数据文件夹, 检查: check)
    }

    // MARK: 生命周期

    func 开始() {
        guard 运行任务 == nil else { return }
        音频.激活()
        读取全局变量()
        运行任务 = Task { await 运行() }
    }

    func 停止() {
        运行任务?.cancel()
        运行任务 = nil
        取消输入()
        系统请求完成()
        影片结束()
        保存全局变量()
        音频.停用()
    }

    func 进入后台(_ background: Bool) {
        音频.暂停(background)
        if background { 保存全局变量() }
    }

    private func 运行() async {
        do {
            while !Task.isCancelled, !已结束 {
                try await 执行一条()
                已执行 += 1
                // 长段只有变量运算的脚本不会挂起，隔一段时间让出主线程
                if 已执行 % 500 == 0 { await Task.yield() }
            }
        } catch is CancellationError {
        } catch {
            错误 = error.localizedDescription
            Self.logger.error("NScripter stopped at line \(self.行 + 1): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: 输入

    /// 轻点画面。`位置` 是游戏画面坐标。
    func 轻点(_ 位置: CGPoint?) {
        switch 等待 {
        case .点击, .计时:
            提交输入(0)
        case .按钮:
            let hit = 按钮.first { $0.区域.contains(位置 ?? .init(x: -1, y: -1)) }
            提交输入(hit?.值 ?? 0)
        case .选择:
            break
        case .无:
            立即显示 = true
        }
    }

    func 选择(_ index: Int) {
        guard case .选择 = 等待 else { return }
        提交输入(index)
    }

    /// 相当于 NScripter 里的右键：按钮等待中返回 -1。
    func 取消() {
        if 等待 == .按钮 { 提交输入(-1) }
    }

    private func 提交输入(_ value: Int) {
        guard let continuation = 输入 else { return }
        输入 = nil
        等待 = .无
        continuation.resume(returning: value)
    }

    private func 取消输入() {
        guard let continuation = 输入 else { return }
        输入 = nil
        等待 = .无
        continuation.resume(throwing: CancellationError())
    }

    private func 等待输入(_ state: NScripter等待, 超时 timeout: Double? = nil) async throws -> Int {
        try Task.checkCancellation()
        输入编号 += 1
        let id = 输入编号
        if let timeout {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                guard let self, self.输入编号 == id else { return }
                self.提交输入(0)
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                输入 = continuation
                等待 = state
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.取消输入() }
        }
    }

    /// 点击等待。快进时直接继续；自动模式按文字长度等一会儿。
    private func 等待点击(翻页: Bool) async throws {
        立即显示 = false
        if 快进 {
            try await Task.sleep(for: .milliseconds(30))
            return
        }
        let auto = 自动 ? 1.2 + Double(页面.reduce(0) { $0 + $1.reduce(0) { $0 + $1.文字.count } }) * 0.04 : nil
        _ = try await 等待输入(.点击(翻页: 翻页), 超时: auto)
        立即显示 = false
    }

    private func 等待时间(_ milliseconds: Int, 可点击 clickable: Bool) async throws {
        guard milliseconds > 0, !快进 else { return }
        if clickable {
            _ = try await 等待输入(.计时, 超时: Double(milliseconds) / 1000)
        } else {
            try await Task.sleep(for: .milliseconds(milliseconds))
        }
    }

    /// 播放影片时脚本停在这里。MPEG-1、AVI、WMV 等自己解码；万一打不开再交给系统播放器，
    /// 文件可能在封包里，先放到临时文件夹。系统也放不了时视图会立刻结束。
    private func 播放影片(_ file: String) async {
        guard let data = 资源.读取(file) else { return }
        if let player = 视觉小说影片.打开(数据: data, 顺序: .bgra) {
            内置影片 = player
            await withCheckedContinuation { 影片等待 = $0 }
            player.停止()
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appending(path: "nscripter-movie-\(UUID().uuidString).\((file as NSString).pathExtension)")
        guard (try? data.write(to: url)) != nil else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        影片 = url
        await withCheckedContinuation { 影片等待 = $0 }
    }

    /// 影片放完、放不了，或者用户轻点跳过
    func 影片结束() {
        影片 = nil
        内置影片 = nil
        let continuation = 影片等待
        影片等待 = nil
        continuation?.resume()
    }

    private func 请求系统(_ request: NScripter系统请求) async {
        系统请求 = request
        await withCheckedContinuation { 系统请求等待 = $0 }
    }

    /// 视图关闭了 systemcall 打开的界面。
    func 系统请求完成() {
        系统请求 = nil
        let continuation = 系统请求等待
        系统请求等待 = nil
        continuation?.resume()
    }

    // MARK: 执行

    private var 当前行: [Character] {
        if 行缓存.0 != 行 {
            行缓存 = (行, 行 < 脚本.行.count ? Array(脚本.行[行]) : [])
        }
        return 行缓存.1
    }

    private func 下一行() {
        行 += 1
        列 = 0
    }

    private func 跳到(_ label: String) throws {
        var name = label.trimmingCharacters(in: .whitespaces).lowercased()
        if name.hasPrefix("*") { name.removeFirst() }
        guard let line = 脚本.标签[name] else {
            throw 视觉小说运行错误.无法读取(String(format: String(localized: "脚本中找不到标签“%@”。"), name))
        }
        行 = line + 1
        列 = 0
    }

    private func 执行一条() async throws {
        guard 行 < 脚本.行.count else {
            已结束 = true
            return
        }
        let line = 当前行
        while 列 < line.count, line[列] == " " || line[列] == "\t" { 列 += 1 }
        guard 列 < line.count else {
            下一行()
            return
        }
        let c = line[列]
        switch c {
        case ";":
            下一行()
        case ":":
            列 += 1
        case "*" where line[..<列].allSatisfy({ $0 == " " || $0 == "\t" }):
            下一行()
        case "~":
            列 += 1
        default:
            if 是文字开头(line, 列) {
                try await 显示文字()
            } else if c.isASCII, c.isLetter || c == "_" {
                var cursor = NScripter游标(line)
                cursor.i = 列
                let name = cursor.标识符().lowercased()
                列 = cursor.i
                try await 执行命令(name)
            } else {
                // 认不出的符号：跳过这一行，避免卡住
                Self.logger.debug("Skipping line \(self.行 + 1)")
                下一行()
            }
        }
    }

    private func 是文字开头(_ line: [Character], _ index: Int) -> Bool {
        let c = line[index]
        if !c.isASCII { return true }
        switch c {
        case "`", "@", "\\", "/": return true
        case "!":
            guard index + 1 < line.count else { return false }
            return ["s", "w", "d"].contains(line[index + 1])
        case "#":
            return index + 6 < line.count && line[(index + 1)...(index + 6)].allSatisfy(\.isHexDigit)
        default:
            return false
        }
    }

    /// 取出命令的参数：到行内的 `:` 或 `;` 为止（引号内除外），以 `,` 结尾时接着读下一行。
    private func 参数() -> NScripter游标 {
        var buffer: [Character] = []
        var line = 当前行
        var index = 列
        while true {
            var quoted = false
            while index < line.count {
                let c = line[index]
                if c == "\"" { quoted.toggle() }
                if !quoted, c == ":" || c == ";" { break }
                buffer.append(c)
                index += 1
            }
            let trimmed = buffer.reversed().drop(while: { $0 == " " || $0 == "\t" })
            guard trimmed.first == ",", index >= line.count, 行 + 1 < 脚本.行.count else { break }
            行 += 1
            line = 当前行
            index = 0
            buffer.append(" ")
        }
        列 = index
        return NScripter游标(buffer)
    }

    private func 提示未支持(_ name: String) {
        guard 已提示命令.insert(name).inserted else { return }
        Self.logger.info("Unsupported NScripter command \(name, privacy: .public) at line \(self.行 + 1)")
    }

    // MARK: 表达式

    private enum 变量引用 {
        case 数值(Int)
        case 字符串(Int)
        case 数组(String)
    }

    private func 引用(_ c: inout NScripter游标) -> 变量引用? {
        c.跳过空白()
        switch c.当前 {
        case "%":
            c.i += 1
            return .数值(原子(&c))
        case "$":
            c.i += 1
            return .字符串(原子(&c))
        case "?":
            c.i += 1
            var key = String(原子(&c))
            while c.读("[") {
                key += "|\(数值(&c))"
                c.读("]")
            }
            return .数组(key)
        default:
            // numalias 的名字也可以直接当数值变量编号用
            let saved = c.i
            let name = c.标识符().lowercased()
            if let value = 数值别名[name] { return .数值(value) }
            c.i = saved
            return nil
        }
    }

    private func 读取(_ ref: 变量引用) -> Int {
        switch ref {
        case .数值(let index): 数值[index] ?? 0
        case .字符串(let index): Int(字符串[index] ?? "") ?? 0
        case .数组(let key): 数组[key] ?? 0
        }
    }

    private func 写入(_ ref: 变量引用, _ value: Int) {
        switch ref {
        case .数值(let index): 数值[index] = value
        case .字符串(let index): 字符串[index] = String(value)
        case .数组(let key): 数组[key] = value
        }
    }

    private func 写入(_ ref: 变量引用, 文字 value: String) {
        switch ref {
        case .字符串(let index): 字符串[index] = value
        case .数值(let index): 数值[index] = Int(value) ?? 0
        case .数组(let key): 数组[key] = Int(value) ?? 0
        }
    }

    /// 数字、变量或别名（不含运算符）。
    private func 原子(_ c: inout NScripter游标) -> Int {
        c.跳过空白()
        guard let ch = c.当前 else { return 0 }
        if ch == "%" || ch == "?" {
            return 引用(&c).map(读取) ?? 0
        }
        if ch == "(" {
            c.i += 1
            let value = 数值(&c)
            c.读(")")
            return value
        }
        if ch == "-" {
            c.i += 1
            return -原子(&c)
        }
        if ch.isNumber {
            var text = ""
            while let d = c.当前, d.isNumber { text.append(d); c.i += 1 }
            return Int(text) ?? 0
        }
        if ch.isLetter || ch == "_" {
            let saved = c.i
            let name = c.标识符().lowercased()
            if let value = 数值别名[name] { return value }
            if name == "to" || name == "step" || name == "mod" { c.i = saved }
            return 0
        }
        return 0
    }

    private func 数值(_ c: inout NScripter游标) -> Int {
        var value = 项(&c)
        while true {
            c.跳过空白()
            if c.当前 == "+" { c.i += 1; value += 项(&c) }
            else if c.当前 == "-" { c.i += 1; value -= 项(&c) }
            else { return value }
        }
    }

    private func 项(_ c: inout NScripter游标) -> Int {
        var value = 原子(&c)
        while true {
            c.跳过空白()
            if c.当前 == "*" { c.i += 1; value *= 原子(&c) }
            else if c.当前 == "/" { c.i += 1; let d = 原子(&c); value = d == 0 ? 0 : value / d }
            else if c.是关键字("mod") { let d = 原子(&c); value = d == 0 ? 0 : value % d }
            else { return value }
        }
    }

    /// 字符串：`"…"`、`$变量`、stralias，或不加引号的单词（white、off、文件名等），可以用 `+` 连接。
    private func 文字(_ c: inout NScripter游标) -> String {
        var result = 文字项(&c)
        while c.读("+") { result += 文字项(&c) }
        return result
    }

    private func 文字项(_ c: inout NScripter游标) -> String {
        c.跳过空白()
        guard let ch = c.当前 else { return "" }
        switch ch {
        case "\"":
            c.i += 1
            var text = ""
            while let d = c.当前, d != "\"" { text.append(d); c.i += 1 }
            c.i += 1
            return text
        case "$":
            c.i += 1
            return 字符串[原子(&c)] ?? ""
        case "#":
            var text = "#"
            c.i += 1
            while let d = c.当前, d.isHexDigit, text.count < 7 { text.append(d); c.i += 1 }
            return text
        case "*":
            var text = "*"
            c.i += 1
            while let d = c.当前, d.isLetter || d.isNumber || d == "_" { text.append(d); c.i += 1 }
            return text
        case "%", "?", "(", "-":
            return String(数值(&c))
        default:
            if ch.isNumber { return String(数值(&c)) }
            let name = c.标识符()
            if let value = 字符串别名[name.lowercased()] { return value }
            if let value = 数值别名[name.lowercased()] { return String(value) }
            if name.isEmpty {
                // 不认识的字符，跳到下一个逗号
                while let d = c.当前, d != "," { c.i += 1 }
            }
            return name
        }
    }

    private func 是文字值(_ c: NScripter游标) -> Bool {
        var probe = c
        probe.跳过空白()
        switch probe.当前 {
        case "\"", "$", "#", "*": return true
        case let ch? where ch.isLetter || ch == "_":
            let name = probe.标识符().lowercased()
            return 字符串别名[name] != nil
        default: return false
        }
    }

    private func 标签名(_ c: inout NScripter游标) -> String {
        let text = 文字(&c)
        return text.hasPrefix("*") ? String(text.dropFirst()) : text
    }

    private func 条件(_ c: inout NScripter游标) -> Bool {
        var result = 比较(&c)
        while true {
            c.跳过空白()
            if c.当前 == "&" {
                c.i += 1
                if c.当前 == "&" { c.i += 1 }
                let next = 比较(&c)
                result = result && next
            } else if c.当前 == "|" {
                c.i += 1
                if c.当前 == "|" { c.i += 1 }
                let next = 比较(&c)
                result = result || next
            } else {
                return result
            }
        }
    }

    private func 比较(_ c: inout NScripter游标) -> Bool {
        if c.是关键字("fchk") { return 资源.存在(文字(&c)) }
        if c.是关键字("lchk") { return 脚本.标签[标签名(&c).lowercased()] != nil }
        let isText = 是文字值(c)
        let leftText = isText ? 文字(&c) : ""
        let leftNumber = isText ? 0 : 数值(&c)
        c.跳过空白()
        var op = ""
        while let ch = c.当前, "=!<>".contains(ch) { op.append(ch); c.i += 1 }
        guard !op.isEmpty else { return isText ? !leftText.isEmpty : leftNumber != 0 }
        let order: Int
        if isText {
            let right = 文字(&c)
            order = leftText == right ? 0 : (leftText < right ? -1 : 1)
        } else {
            let right = 数值(&c)
            order = leftNumber == right ? 0 : (leftNumber < right ? -1 : 1)
        }
        switch op {
        case "==", "=": return order == 0
        case "!=", "<>": return order != 0
        case "<": return order < 0
        case ">": return order > 0
        case "<=", "=<": return order <= 0
        case ">=", "=>": return order >= 0
        default: return false
        }
    }

    // MARK: 文字

    private func 字宽单位(_ c: Character) -> Int {
        guard let scalar = c.unicodeScalars.first else { return 2 }
        if scalar.value < 0x80 || (0xff61...0xff9f).contains(scalar.value) { return 1 }
        return 2
    }

    private func 追加(_ character: Character) async throws {
        let width = 字宽单位(character)
        if 当前行宽 + width > 文本框.每行字数 * 2 {
            try await 换行()
        }
        if 页面.isEmpty { 页面.append([]) }
        var line = 页面[页面.count - 1]
        if let last = line.last, last.颜色 == 文字颜色 {
            line[line.count - 1].文字.append(character)
        } else {
            line.append(NScripter文字片段(文字: String(character), 颜色: 文字颜色))
        }
        页面[页面.count - 1] = line
        当前行宽 += width
    }

    private func 换行() async throws {
        if 页面.isEmpty { 页面.append([]) }
        if 页面.count >= 文本框.行数 {
            try await 等待点击(翻页: true)
            清空页面()
        }
        页面.append([])
        当前行宽 = 0
    }

    private func 清空页面() {
        let text = 页面.map { $0.map(\.文字).joined() }.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            回想.append(text)
            if 回想.count > 300 { 回想.removeFirst(回想.count - 300) }
        }
        页面 = []
        当前行宽 = 0
    }

    private func 记录存档点() {
        语句起点 = (行, 列)
        起点页面 = 页面
        起点场景 = 显示场景
    }

    /// 显示一行文字，处理 `@`、`\`、`/`、`!s`、`!w`、`!d`、`#RRGGBB`。
    private func 显示文字() async throws {
        记录存档点()
        let line = 当前行
        var index = 列
        var printed = false
        var noNewline = false
        var pageBreak = false
        if !文本框可见 {
            文本框可见 = true
        }
        if 页面.isEmpty { 页面.append([]) }
        立即显示 = false
        while index < line.count {
            let c = line[index]
            pageBreak = false
            switch c {
            case "@":
                index += 1
                try await 等待点击(翻页: false)
                continue
            case "\\":
                index += 1
                try await 等待点击(翻页: true)
                清空页面()
                pageBreak = true
                continue
            case "/" where index == line.count - 1:
                noNewline = true
                index += 1
                continue
            case "`":
                index += 1
                continue
            case "!" where index + 1 < line.count && ["s", "w", "d"].contains(line[index + 1]):
                let kind = line[index + 1]
                index += 2
                if kind == "s", index < line.count, line[index] == "d" {
                    index += 1
                    当前速度 = 默认速度
                    continue
                }
                var digits = ""
                while index < line.count, line[index].isNumber { digits.append(line[index]); index += 1 }
                let value = Int(digits) ?? 0
                switch kind {
                case "s": 当前速度 = value
                case "w": try await 等待时间(value, 可点击: false)
                default: try await 等待时间(value, 可点击: true)
                }
                continue
            case "#" where index + 6 < line.count && line[(index + 1)...(index + 6)].allSatisfy(\.isHexDigit):
                文字颜色 = UInt32(String(line[(index + 1)...(index + 6)]), radix: 16) ?? 0xffffff
                index += 7
                continue
            default:
                break
            }
            try await 追加(c)
            printed = true
            index += 1
            if !立即显示, !快进, 当前速度 > 0 {
                try await Task.sleep(for: .milliseconds(当前速度))
            }
        }
        下一行()
        if printed, !noNewline, !pageBreak {
            页面.append([])
            当前行宽 = 0
            if 页面.count > 文本框.行数 {
                页面.removeLast()
                try await 等待点击(翻页: true)
                清空页面()
            }
        }
    }

    // MARK: 画面

    private func 规范标签(_ tag: String, 默认 defaultSpec: String) -> String {
        tag.hasPrefix(":") ? tag : ":\(defaultSpec);\(tag)"
    }

    func 图像(_ tag: String) -> NScripter图像? {
        图像缓存[tag]
    }

    @discardableResult
    private func 载入图像(_ tag: String) async -> NScripter图像? {
        if let cached = 图像缓存[tag] { return cached }
        let resources = 资源
        let image = await Task.detached(priority: .userInitiated) { () -> NScripter图像? in
            let parsed = NScripter图像解码.解析标签(tag, 默认: .不透明)
            guard let data = resources.读取(parsed.文件) else { return nil }
            return NScripter图像解码.解码(data, 方式: parsed.方式, 格数: parsed.格数)
        }.value
        if let image {
            // 缓存不需要太大：长篇作品的背景、立绘有几千张。画面上还在用的留着（视图同步读取缓存）
            if 图像缓存.count > 160 {
                let used = 使用中的图像
                图像缓存 = 图像缓存.filter { used.contains($0.key) }
            }
            图像缓存[tag] = image
        } else {
            Self.logger.debug("Missing image \(tag, privacy: .public)")
        }
        return image
    }

    private var 使用中的图像: Set<String> {
        var result = Set<String>()
        for scene in [显示场景, 待显示] {
            if let bg = scene.背景图像 { result.insert(bg) }
            result.formUnion(scene.立绘.values.map(\.标签))
            result.formUnion(scene.精灵.values.map(\.标签))
        }
        if let image = 文本框.窗口图像 { result.insert(image) }
        if let image = 按钮图像 { result.insert(image) }
        return result
    }

    private func 预载(_ scene: NScripter场景) async {
        if let bg = scene.背景图像 { await 载入图像(bg) }
        for sprite in scene.立绘.values { await 载入图像(sprite.标签) }
        for sprite in scene.精灵.values { await 载入图像(sprite.标签) }
        if let image = 文本框.窗口图像 { await 载入图像(image) }
        if let image = 按钮图像 { await 载入图像(image) }
    }

    private func 颜色值(_ text: String) -> UInt32? {
        switch text.lowercased() {
        case "white": return 0xffffff
        case "black": return 0x000000
        default:
            guard text.hasPrefix("#") else { return nil }
            return UInt32(text.dropFirst().prefix(6), radix: 16)
        }
    }

    /// 把暂存的画面显示出来，按效果编号决定过渡。
    private func 应用效果(_ number: Int) async throws {
        let info = 效果[number]
        let duration = number <= 1 ? 0 : (info?.时长 ?? 0)
        let instant = duration <= 0 || 快进
        await 预载(待显示)
        // 和 NScripter 一样，画面变化时收起文本框，下一段文字出现时再显示
        if 擦除文本框, number > 0, 文本框可见 {
            文本框可见 = false
        }
        过渡类型 = info?.类型 ?? 1
        过渡时长 = instant ? 0 : Double(duration) / 1000
        if instant {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                显示场景 = 待显示
                场景版本 += 1
            }
        } else {
            withAnimation(.linear(duration: 过渡时长)) {
                显示场景 = 待显示
                场景版本 += 1
            }
            try await 等待时间(duration, 可点击: true)
        }
    }

    private func 立绘位置(_ position: String, _ image: NScripter图像?) -> (Int, Int) {
        let width = image?.宽 ?? 0
        let height = image?.高 ?? 0
        let center: Int
        switch position {
        case "l": center = 屏幕宽 / 4
        case "r": center = 屏幕宽 * 3 / 4
        default: center = 屏幕宽 / 2
        }
        return (center - width / 2, 屏幕高 - height)
    }

    private func 震动(_ amplitude: Int, _ milliseconds: Int, 水平: Bool, 垂直: Bool) async throws {
        guard !快进, milliseconds > 0 else { return }
        let end = Date.now.addingTimeInterval(Double(milliseconds) / 1000)
        var sign = 1.0
        while Date.now < end {
            let distance = Double(amplitude * 4) * sign
            震动偏移 = CGSize(width: 水平 ? distance : 0, height: 垂直 ? distance : 0)
            sign = -sign
            try await Task.sleep(for: .milliseconds(30))
        }
        震动偏移 = .zero
    }

    // MARK: 命令

    private func 执行命令(_ name: String) async throws {
        switch name {
        // 流程
        case "if", "notif":
            var c = NScripter游标(当前行)
            c.i = 列
            let value = 条件(&c)
            列 = c.i
            if value == (name == "notif") { 下一行() }
        case "goto":
            var c = 参数()
            try 跳到(标签名(&c))
        case "gosub":
            var c = 参数()
            let label = 标签名(&c)
            调用栈.append([行, 列])
            try 跳到(label)
        case "return":
            var c = 参数()
            c.跳过空白()
            if !c.结束, c.当前 == "*" {
                _ = 调用栈.popLast()
                try 跳到(标签名(&c))
            } else if let frame = 调用栈.popLast() {
                行 = frame[0]
                列 = frame[1]
                行缓存 = (-1, [])
                if !参数栈.isEmpty, frame.count > 2 { 参数栈.removeLast() }
            }
        case "skip":
            var c = 参数()
            let line = 行
            let offset = 数值(&c)
            行 = max(0, line + offset)
            列 = 0
        case "jumpf":
            _ = 参数()
            var line = 行 + 1
            while line < 脚本.行.count, !脚本.行[line].trimmingCharacters(in: .whitespaces).hasPrefix("~") { line += 1 }
            行 = line
            列 = 0
        case "jumpb":
            _ = 参数()
            var line = 行 - 1
            while line > 0, !脚本.行[line].trimmingCharacters(in: .whitespaces).hasPrefix("~") { line -= 1 }
            行 = line + 1
            列 = 0
        case "for":
            var c = 参数()
            guard let ref = 引用(&c), case .数值(let index) = ref else { return }
            c.读("=")
            数值[index] = 数值(&c)
            _ = c.是关键字("to")
            let end = 数值(&c)
            let step = c.是关键字("step") ? 数值(&c) : 1
            循环栈.append(NScripter循环(变量: index, 终值: end, 步长: step == 0 ? 1 : step, 行: 行, 列: 列))
        case "next":
            _ = 参数()
            guard var loop = 循环栈.popLast() else { return }
            数值[loop.变量] = (数值[loop.变量] ?? 0) + loop.步长
            let value = 数值[loop.变量] ?? 0
            if loop.步长 > 0 ? value <= loop.终值 : value >= loop.终值 {
                行 = loop.行
                列 = loop.列
                行缓存 = (-1, [])
                loop.行 = 行
                循环栈.append(loop)
            }
        case "break":
            _ = 参数()
            guard !循环栈.isEmpty else { return }
            循环栈.removeLast()
            // 跳到对应的 next 之后
            var depth = 0
            var line = 行 + 1
            while line < 脚本.行.count {
                let trimmed = 脚本.行[line].trimmingCharacters(in: .whitespaces).lowercased()
                if trimmed.hasPrefix("for ") { depth += 1 }
                if trimmed.hasPrefix("next") {
                    if depth == 0 { break }
                    depth -= 1
                }
                line += 1
            }
            行 = line + 1
            列 = 0
        case "game":
            try 跳到("start")
        case "end":
            已结束 = true
        case "reset":
            重置变量()
            try 跳到("start")
        case "defsub":
            var c = 参数()
            自定义命令.insert(c.标识符().lowercased())
        case "getparam":
            var c = 参数()
            guard var source = 参数栈.popLast() else { return }
            repeat {
                guard let ref = 引用(&c) else { break }
                if case .字符串 = ref { 写入(ref, 文字: 文字(&source)) } else { 写入(ref, 数值(&source)) }
                source.读(",")
            } while c.读(",")
            参数栈.append(source)

        // 变量
        case "mov", "mov3", "mov4", "mov5", "mov6", "mov7", "mov8", "mov9", "mov10", "movl":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            var target = ref
            while c.读(",") {
                if case .字符串 = target { 写入(target, 文字: 文字(&c)) } else { 写入(target, 数值(&c)) }
                // movN 依次写入后面的变量
                switch target {
                case .数值(let index): target = .数值(index + 1)
                case .字符串(let index): target = .字符串(index + 1)
                case .数组: break
                }
            }
        case "add", "sub", "mul", "div", "mod":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            if case .字符串(let index) = ref, name == "add" {
                字符串[index] = (字符串[index] ?? "") + 文字(&c)
                return
            }
            let value = 数值(&c)
            let current = 读取(ref)
            switch name {
            case "add": 写入(ref, current + value)
            case "sub": 写入(ref, current - value)
            case "mul": 写入(ref, current * value)
            case "div": 写入(ref, value == 0 ? 0 : current / value)
            default: 写入(ref, value == 0 ? 0 : current % value)
            }
        case "inc", "dec":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            写入(ref, 读取(ref) + (name == "inc" ? 1 : -1))
        case "rnd", "rnd2":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            let first = 数值(&c)
            if name == "rnd" {
                写入(ref, first > 0 ? Int.random(in: 0..<first) : 0)
            } else {
                c.读(",")
                let second = 数值(&c)
                写入(ref, Int.random(in: min(first, second)...max(first, second)))
            }
        case "itoa", "itoa2":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            写入(ref, 文字: String(数值(&c)))
        case "atoi":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            写入(ref, Int(文字(&c).trimmingCharacters(in: .whitespaces)) ?? 0)
        case "len":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            // NScripter 按字节计数，双字节字符算 2
            写入(ref, 文字(&c).reduce(0) { $0 + 字宽单位($1) })
        case "mid":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            let text = Array(文字(&c))
            c.读(",")
            let start = 数值(&c) / 2
            c.读(",")
            let length = 数值(&c) / 2
            let lower = min(max(0, start), text.count)
            写入(ref, 文字: String(text[lower..<min(text.count, lower + max(0, length))]))
        case "cmp":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            let a = 文字(&c)
            c.读(",")
            let b = 文字(&c)
            写入(ref, a == b ? 0 : (a < b ? -1 : 1))
        case "numalias":
            var c = 参数()
            let alias = c.标识符().lowercased()
            c.读(",")
            数值别名[alias] = 数值(&c)
        case "stralias":
            var c = 参数()
            let alias = c.标识符().lowercased()
            c.读(",")
            字符串别名[alias] = 文字(&c)
        case "dim", "intlimit", "labellog", "filelog", "nsa", "ns2", "nsadir", "arc", "caption", "versionstr",
             "savename", "savenumber", "rmenu", "menusetwindow", "lookbackcolor", "lookbackbutton", "windoweffect",
             "effectblank", "killmenu", "deletemenu", "setcursor", "abssetcursor", "mode_saya", "underline",
             "transmode", "clickvoice", "soundpressplgin", "spi", "minimizewindow", "defaultfont", "shadedistance",
             "menuselectcolor", "menuselectvoice", "mousecursor", "linepage", "linepage2", "clickstr", "lookbackflush",
             "humanorder", "windowback", "automode_time", "maxkaisoupage", "autoclick", "selectvoice", "selectbtnwait",
             "textgosub", "pretextgosub", "loadgosub", "rgosub", "roff", "rlookback", "mode_ext", "mode_wave_demo",
             "nsadir2", "zenkakko", "savedir", "setkinsoku", "addkinsoku", "kidokuskip", "kidokumode", "mouse_mode",
             "texec", "textexbtn", "btndown", "getcselnum", "logsp", "logsp2", "allsphide", "allspresume",
             "allsp2hide", "allsp2resume", "isfull", "trap", "trap2", "cselgoto", "cselbtn", "setlayer", "layermessage",
             "exec_dll", "getret", "chvol", "voicevol", "sevol", "bgmvol", "mp3vol",
             "draw", "drawclear", "drawfill", "drawbg", "drawsp", "drawtext", "defvoicevol", "defsevol", "defmp3vol",
             "defbgmvol", "stop2", "gettag", "split", "setlayer2", "bdown", "lr_trap", "lr_trap2", "skipoff",
             "erasetextbtn", "noloaderror", "globalon_off":
            let c = 参数()
            switch name {
            case "humanz": break
            case "voicevol", "mp3vol", "bgmvol", "sevol", "chvol":
                var c = c
                if name == "chvol" { _ = 数值(&c); c.读(",") }
                let volume = Float(max(0, min(100, 数值(&c)))) / 100
                switch name {
                case "voicevol": 音频.语音音量 = volume
                case "sevol": 音频.效果音量 = volume
                case "mp3vol", "bgmvol": 音频.音乐音量 = volume
                default: break
                }
            case "lookbackflush": 回想.removeAll()
            case "textgosub", "pretextgosub", "exec_dll", "draw", "cselbtn":
                提示未支持(name)
            default: break
            }
        case "movie", "mpegplay", "avi":
            var c = 参数()
            let file = 文字(&c)
            if !file.isEmpty, file.lowercased() != "stop" { await 播放影片(file) }
        case "globalon":
            _ = 参数()
            全局变量 = true
        case "humanz":
            var c = 参数()
            立绘层 = 数值(&c)
        case "effect":
            var c = 参数()
            let number = 数值(&c)
            c.读(",")
            let type = 数值(&c)
            var duration = 0
            var mask: String?
            if c.读(",") { duration = 数值(&c) }
            if c.读(",") { mask = 文字(&c) }
            效果[number] = (type, duration, mask)
        case "date":
            var c = 参数()
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
            if let ref = 引用(&c) { 写入(ref, (parts.year ?? 2000) % 100) }
            c.读(",")
            if let ref = 引用(&c) { 写入(ref, parts.month ?? 1) }
            c.读(",")
            if let ref = 引用(&c) { 写入(ref, parts.day ?? 1) }
        case "time":
            var c = 参数()
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: .now)
            if let ref = 引用(&c) { 写入(ref, parts.hour ?? 0) }
            c.读(",")
            if let ref = 引用(&c) { 写入(ref, parts.minute ?? 0) }
            c.读(",")
            if let ref = 引用(&c) { 写入(ref, parts.second ?? 0) }
        case "getversion":
            var c = 参数()
            if let ref = 引用(&c) { 写入(ref, 280) }
        case "getreg", "getini":
            var c = 参数()
            if let ref = 引用(&c) { 写入(ref, 文字: "") }
        case "fileexist":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            c.读(",")
            写入(ref, 资源.存在(文字(&c)) ? 1 : 0)
        case "isskip":
            var c = 参数()
            if let ref = 引用(&c) { 写入(ref, 快进 ? 1 : (自动 ? 2 : 0)) }
        case "ispage", "isdown", "getmousepos", "getcursorpos", "getbtntimer", "getskipoff", "gettext", "getsavestr",
             "getlog", "getcursor", "getmouseover", "checkpage", "getwindowsize", "getspmode", "getspsize", "getscreenshot":
            var c = 参数()
            if let ref = 引用(&c) {
                if case .字符串 = ref { 写入(ref, 文字: "") } else { 写入(ref, name == "getwindowsize" ? 屏幕宽 : 0) }
            }
        case "resettimer":
            _ = 参数()
            计时起点 = .now
        case "gettimer":
            var c = 参数()
            if let ref = 引用(&c) { 写入(ref, Int(Date.now.timeIntervalSince(计时起点) * 1000)) }
        case "waittimer":
            var c = 参数()
            let target = 数值(&c)
            let elapsed = Int(Date.now.timeIntervalSince(计时起点) * 1000)
            try await 等待时间(target - elapsed, 可点击: false)
        case "wait":
            var c = 参数()
            try await 等待时间(数值(&c), 可点击: false)
        case "delay":
            var c = 参数()
            try await 等待时间(数值(&c), 可点击: true)
        case "click", "lrclick":
            _ = 参数()
            记录存档点()
            try await 等待点击(翻页: false)

        // 文字
        case "br":
            _ = 参数()
            if 页面.isEmpty { 页面.append([]) }
            页面.append([])
            当前行宽 = 0
            if 页面.count > 文本框.行数 { 页面.removeFirst() }
        case "textclear":
            _ = 参数()
            清空页面()
        case "erasetextwindow":
            var c = 参数()
            擦除文本框 = 数值(&c) != 0
        case "texton":
            _ = 参数()
            文本框可见 = true
        case "textoff":
            _ = 参数()
            文本框可见 = false
        case "setwindow", "setwindow2", "setwindow3":
            var c = 参数()
            if name == "setwindow2" {
                let value = 文字(&c)
                if let color = 颜色值(value) { 文本框.窗口颜色 = color; 文本框.窗口图像 = nil }
                else { 文本框.窗口图像 = 规范标签(value, 默认: "c"); 文本框.窗口颜色 = nil }
                return
            }
            var values: [Int] = []
            for index in 0..<11 {
                if index > 0 { c.读(",") }
                values.append(数值(&c))
            }
            c.读(",")
            let window = 文字(&c)
            var box = 文本框
            box.文字x = values[0]; box.文字y = values[1]
            box.每行字数 = max(1, values[2]); box.行数 = max(1, values[3])
            box.字宽 = values[4]; box.字高 = values[5]
            box.字距 = values[6]; box.行距 = values[7]
            box.速度 = values[8]; box.粗体 = values[9] != 0; box.阴影 = values[10] != 0
            c.读(",")
            box.窗口x1 = 数值(&c)
            c.读(",")
            box.窗口y1 = 数值(&c)
            if let color = 颜色值(window) {
                box.窗口颜色 = color
                box.窗口图像 = nil
                c.读(",")
                box.窗口x2 = 数值(&c)
                c.读(",")
                box.窗口y2 = 数值(&c)
            } else {
                box.窗口颜色 = nil
                box.窗口图像 = 规范标签(window, 默认: "c")
                if let image = await 载入图像(box.窗口图像!) {
                    box.窗口x2 = box.窗口x1 + image.宽 - 1
                    box.窗口y2 = box.窗口y1 + image.高 - 1
                }
            }
            文本框 = box
            默认速度 = box.速度
            当前速度 = box.速度
            清空页面()
        case "defaultspeed":
            var c = 参数()
            let values = [数值(&c), c.读(",") ? 数值(&c) : 0, c.读(",") ? 数值(&c) : 0]
            默认速度 = values[1] > 0 ? values[1] : values[0]
            当前速度 = 默认速度
        case "textspeed":
            var c = 参数()
            当前速度 = 数值(&c)
        case "locate":
            _ = 参数()
        case "selectcolor":
            var c = 参数()
            let on = 颜色值(文字(&c)) ?? 0xffffff
            c.读(",")
            let off = 颜色值(文字(&c)) ?? 0x888888
            选择颜色 = (on, off)
        case "select", "selgosub", "selnum", "csel":
            var c = 参数()
            var target: 变量引用?
            if name == "selnum" {
                target = 引用(&c)
                c.读(",")
            }
            var options: [(String, String?)] = []
            repeat {
                c.跳过空白()
                guard !c.结束 else { break }
                let text = 文字(&c)
                var label: String?
                if name != "selnum", c.读(",") { label = 标签名(&c) }
                options.append((text, label))
            } while c.读(",")
            guard !options.isEmpty else { return }
            // 和 NScripter 一样，遇到选项时停止快进
            快进 = false
            记录存档点()
            文本框可见 = true
            let choice = try await 等待输入(.选择(options.map(\.0)))
            清空页面()
            if let target {
                写入(target, choice)
            } else if let label = options[min(choice, options.count - 1)].1 {
                if name == "selgosub" { 调用栈.append([行, 列]) }
                try 跳到(label)
            }

        // 画面
        case "bg":
            var c = 参数()
            let value = 文字(&c)
            let effect = c.读(",") ? 数值(&c) : 1
            if let color = 颜色值(value) {
                待显示.背景颜色 = color
                待显示.背景图像 = nil
            } else {
                let tag = 规范标签(value, 默认: "c")
                待显示.背景图像 = tag
                待显示.背景颜色 = nil
            }
            待显示.立绘.removeAll()
            try await 应用效果(effect)
        case "ld":
            var c = 参数()
            let position = 文字(&c).lowercased()
            c.读(",")
            let tag = 规范标签(文字(&c), 默认: "l")
            let effect = c.读(",") ? 数值(&c) : 1
            let image = await 载入图像(tag)
            let (x, y) = 立绘位置(position, image)
            待显示.立绘[position] = NScripter精灵(标签: tag, x: x, y: y)
            try await 应用效果(effect)
        case "cl":
            var c = 参数()
            let position = 文字(&c).lowercased()
            let effect = c.读(",") ? 数值(&c) : 1
            if position == "a" { 待显示.立绘.removeAll() } else { 待显示.立绘[position] = nil }
            try await 应用效果(effect)
        case "print":
            var c = 参数()
            try await 应用效果(c.结束 ? 1 : 数值(&c))
        case "lsp", "lsph", "lsp2", "lsph2":
            var c = 参数()
            let number = 数值(&c)
            c.读(",")
            let tag = 规范标签(文字(&c), 默认: "l")
            c.读(",")
            let x = 数值(&c)
            c.读(",")
            let y = 数值(&c)
            let alpha = c.读(",") ? 数值(&c) : 255
            await 载入图像(tag)
            待显示.精灵[number] = NScripter精灵(标签: tag, x: x, y: y, 可见: !name.hasPrefix("lsph"), 透明度: alpha)
        case "csp", "csp2":
            var c = 参数()
            let number = c.结束 ? -1 : 数值(&c)
            if number < 0 { 待显示.精灵.removeAll() } else { 待显示.精灵[number] = nil }
        case "vsp", "vsp2":
            var c = 参数()
            let number = 数值(&c)
            c.读(",")
            待显示.精灵[number]?.可见 = 数值(&c) != 0
        case "msp", "amsp", "msp2", "amsp2":
            var c = 参数()
            let number = 数值(&c)
            c.读(",")
            let x = 数值(&c)
            c.读(",")
            let y = 数值(&c)
            let alpha = c.读(",") ? 数值(&c) : nil
            guard var sprite = 待显示.精灵[number] else { return }
            if name.hasPrefix("amsp") {
                sprite.x = x; sprite.y = y
                if let alpha { sprite.透明度 = alpha }
            } else {
                sprite.x += x; sprite.y += y
                if let alpha { sprite.透明度 = max(0, min(255, sprite.透明度 + alpha)) }
            }
            待显示.精灵[number] = sprite
        case "cell":
            var c = 参数()
            let number = 数值(&c)
            c.读(",")
            待显示.精灵[number]?.格 = 数值(&c)
        case "monocro":
            var c = 参数()
            let value = 文字(&c)
            待显示.单色 = value.lowercased() == "off" ? nil : 颜色值(value)
        case "nega":
            var c = 参数()
            待显示.反色 = 数值(&c) != 0
        case "quake", "quakex", "quakey":
            var c = 参数()
            let amplitude = 数值(&c)
            c.读(",")
            let duration = 数值(&c)
            try await 震动(amplitude, duration, 水平: name != "quakey", 垂直: name != "quakex")

        // 按钮
        case "btndef":
            var c = 参数()
            let value = 文字(&c)
            按钮.removeAll()
            if value.lowercased() == "clear" || value.isEmpty {
                按钮图像 = nil
            } else {
                let tag = 规范标签(value, 默认: "c")
                按钮图像 = tag
                await 载入图像(tag)
            }
        case "btn":
            var c = 参数()
            var values: [Int] = []
            for index in 0..<7 {
                if index > 0 { c.读(",") }
                values.append(数值(&c))
            }
            按钮.append(NScripter按钮(
                值: values[0],
                区域: CGRect(x: values[1], y: values[2], width: values[3], height: values[4]),
                按下图像: CGRect(x: values[5], y: values[6], width: values[3], height: values[4]),
                精灵: nil
            ))
        case "spbtn":
            var c = 参数()
            let number = 数值(&c)
            c.读(",")
            let value = 数值(&c)
            guard let sprite = 待显示.精灵[number], let image = 图像缓存[sprite.标签] else { return }
            按钮.append(NScripter按钮(
                值: value,
                区域: CGRect(x: sprite.x, y: sprite.y, width: image.宽, height: image.高),
                按下图像: nil,
                精灵: number
            ))
        case "btnwait", "btnwait2":
            var c = 参数()
            guard let ref = 引用(&c) else { return }
            if 待显示 != 显示场景 { try await 应用效果(1) }
            快进 = false
            记录存档点()
            let value = try await 等待输入(.按钮)
            写入(ref, value)
            if name == "btnwait" { 按钮.removeAll() }
        case "btntime", "btntime2", "exbtn", "exbtn_d", "transbtn":
            _ = 参数()
            提示未支持(name)

        // 声音
        case "mp3", "mp3loop", "bgm", "bgmonce", "loopbgm", "mp3save":
            var c = 参数()
            let file = 文字(&c)
            音频.播放音乐(file, 循环: name == "mp3loop" || name == "bgm" || name == "loopbgm")
        case "play", "playonce":
            var c = 参数()
            let value = 文字(&c)
            if value.hasPrefix("*"), let track = Int(value.dropFirst()) {
                let candidates = ["mp3", "ogg", "wav", "mid"].flatMap { ext in
                    [String(format: "cd/track%02d.%@", track, ext), String(format: "bgm/%02d.%@", track, ext)]
                }
                if let file = candidates.first(where: 资源.存在) { 音频.播放音乐(file, 循环: name == "play") }
            } else {
                音频.播放音乐(value, 循环: name == "play")
            }
        case "stop":
            _ = 参数()
            音频.全部停止()
        case "playstop", "mp3stop", "bgmstop":
            _ = 参数()
            音频.停止音乐()
        case "mp3fadeout", "bgmfadeout":
            var c = 参数()
            音频.淡出音乐(数值(&c))
        case "wave", "waveloop":
            var c = 参数()
            音频.播放效果音(文字(&c), 循环: name == "waveloop")
        case "wavestop":
            _ = 参数()
            音频.停止效果音()
        case "dwave", "dwaveloop", "dwaveload":
            var c = 参数()
            let channel = 数值(&c)
            c.读(",")
            let file = 文字(&c)
            if name != "dwaveload" { 音频.播放声道(channel, file, 循环: name == "dwaveloop") }
        case "dwavestop":
            var c = 参数()
            音频.停止声道(数值(&c))
        case "dwaveplay", "dwaveplayloop":
            _ = 参数()

        // 系统
        case "systemcall":
            var c = 参数()
            let call = c.标识符().lowercased()
            switch call {
            case "rmenu": await 请求系统(.菜单)
            case "load": await 请求系统(.载入)
            case "save": await 请求系统(.存储)
            case "lookback": await 请求系统(.回想)
            case "skip": 快进 = true
            case "automode": 自动 = true
            case "reset": 重置变量(); try 跳到("start")
            case "end": 已结束 = true
            default: break
            }
        case "saveon":
            _ = 参数()
            允许存档 = true
        case "saveoff":
            _ = 参数()
            允许存档 = false
        case "savegame", "savegame2":
            var c = 参数()
            try? 存储(到: 数值(&c))
        case "loadgame":
            var c = 参数()
            let slot = 数值(&c)
            if 存档摘要(slot) != nil {
                载入(slot)
                throw CancellationError()
            }
        default:
            if 自定义命令.contains(name) {
                let args = 参数()
                调用栈.append([行, 列, 1])
                参数栈.append(args)
                try 跳到(name)
            } else {
                _ = 参数()
                提示未支持(name)
            }
        }
    }

    private func 重置变量() {
        数值 = 数值.filter { 全局变量 && $0.key >= Self.全局变量起点 }
        字符串 = 字符串.filter { 全局变量 && $0.key >= Self.全局变量起点 }
        数组.removeAll()
        调用栈.removeAll()
        循环栈.removeAll()
        参数栈.removeAll()
        待显示 = NScripter场景()
        显示场景 = 待显示
        场景版本 += 1
        页面 = []
        文本框可见 = false
        音频.全部停止()
    }

    // MARK: 字体

    /// 字体文件由 `NScripter兼容检查` 选出；用不了的字体不注册，直接用系统字体。
    private func 注册字体(_ url: URL?) {
        guard let url else { return }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // 已经注册过（再次打开同一部作品）也会返回失败，照样读取字体名
            Self.logger.debug("Font register: \(String(describing: error?.takeRetainedValue()), privacy: .public)")
        }
        if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first,
           let fontName = CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String {
            字体名 = fontName
        }
        Self.logger.info("Game font \(url.lastPathComponent, privacy: .public): \(self.字体名 ?? "nil", privacy: .public)")
    }

    // MARK: 存档

    private var 存档文件夹: URL {
        let url = 数据文件夹.appending(path: "NScripter", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static let 存档数量 = 20

    private func 存档地址(_ slot: Int) -> URL {
        存档文件夹.appending(path: "save\(slot).json")
    }

    var 可以存档: Bool { 允许存档 && !已结束 }

    func 存档摘要(_ slot: Int) -> (时间: Date, 预览: String)? {
        guard let data = try? Data(contentsOf: 存档地址(slot)),
              let save = try? JSONDecoder().decode(NScripter存档.self, from: data) else { return nil }
        return (save.时间, save.预览)
    }

    func 存储(到 slot: Int) throws {
        let preview = 页面.flatMap { $0 }.map(\.文字).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let save = NScripter存档(
            行: 语句起点.0, 列: 语句起点.1,
            调用栈: 调用栈.filter { $0.count == 2 }, 循环栈: 循环栈,
            数值: 数值, 字符串: 字符串, 数组: 数组,
            场景: 起点场景, 页面: 起点页面, 文本框: 文本框,
            背景音乐: 音频.背景音乐文件, 背景音乐循环: 音频.背景音乐循环,
            时间: .now, 预览: String(preview.suffix(80))
        )
        let data = try JSONEncoder().encode(save)
        try data.write(to: 存档地址(slot), options: .atomic)
        保存全局变量()
    }

    func 删除存档(_ slot: Int) {
        try? FileManager.default.removeItem(at: 存档地址(slot))
    }

    func 载入(_ slot: Int) {
        guard let data = try? Data(contentsOf: 存档地址(slot)),
              let save = try? JSONDecoder().decode(NScripter存档.self, from: data) else { return }
        运行任务?.cancel()
        取消输入()
        系统请求 = nil
        系统请求等待?.resume()
        系统请求等待 = nil
        let globals = (数值.filter { 全局变量 && $0.key >= Self.全局变量起点 }, 字符串.filter { 全局变量 && $0.key >= Self.全局变量起点 })
        运行任务 = Task {
            await 预载(save.场景)
            行 = save.行
            列 = save.列
            行缓存 = (-1, [])
            调用栈 = save.调用栈
            循环栈 = save.循环栈
            参数栈 = []
            数值 = save.数值.merging(globals.0) { $1 }
            字符串 = save.字符串.merging(globals.1) { $1 }
            数组 = save.数组
            文本框 = save.文本框
            页面 = save.页面
            当前行宽 = 0
            待显示 = save.场景
            按钮 = []
            快进 = false
            已结束 = false
            withAnimation(.linear(duration: 0.3)) {
                显示场景 = save.场景
                场景版本 += 1
            }
            if let music = save.背景音乐 { 音频.播放音乐(music, 循环: save.背景音乐循环) } else { 音频.全部停止() }
            await 运行()
        }
    }

    private var 全局变量地址: URL { 存档文件夹.appending(path: "global.json") }

    private struct 全局存档: Codable {
        var 数值: [Int: Int]
        var 字符串: [Int: String]
    }

    private func 读取全局变量() {
        guard let data = try? Data(contentsOf: 全局变量地址),
              let value = try? JSONDecoder().decode(全局存档.self, from: data) else { return }
        数值.merge(value.数值) { $1 }
        字符串.merge(value.字符串) { $1 }
    }

    private func 保存全局变量() {
        guard 全局变量 else { return }
        let value = 全局存档(
            数值: 数值.filter { $0.key >= Self.全局变量起点 },
            字符串: 字符串.filter { $0.key >= Self.全局变量起点 }
        )
        if let data = try? JSONEncoder().encode(value) { try? data.write(to: 全局变量地址, options: .atomic) }
    }

    /// 绘制顺序：背景、编号大于等于 humanz 的精灵、立绘、其余精灵（编号小的在上）。
    var 精灵分层: (下层: [(Int, NScripter精灵)], 上层: [(Int, NScripter精灵)]) {
        let sorted = 显示场景.精灵.sorted { $0.key > $1.key }
        return (sorted.filter { $0.key >= 立绘层 }.map { ($0.key, $0.value) },
                sorted.filter { $0.key < 立绘层 }.map { ($0.key, $0.value) })
    }
}

nonisolated enum NScripter系统请求: String, Identifiable, Sendable {
    case 菜单, 存储, 载入, 回想
    var id: String { rawValue }
}
