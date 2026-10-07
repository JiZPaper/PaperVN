import Foundation
import SwiftUI

nonisolated struct 评论行内样式: Hashable, Sendable {
    var 粗体 = false
    var 斜体 = false
    var 下划线 = false
    var 删除线 = false
    var 剧透 = false
    var 链接: URL?
}

nonisolated struct 评论文本片段: Hashable, Sendable {
    var 文本: String
    var 样式: 评论行内样式
}

nonisolated enum 评论文本块类型: Hashable, Sendable {
    case 正文
    case 标题(级别: Int)
    case 引用
    case 代码
    case 列表项(标号: String?)
    case 分隔线
}

nonisolated struct 评论文本块: Identifiable, Hashable, Sendable {
    let id: Int
    var 类型: 评论文本块类型
    var 片段: [评论文本片段]

    var 纯文本: String { 片段.map(\.文本).joined() }
}

nonisolated struct 评论标记文本: Hashable, Sendable {
    var 块列表: [评论文本块]
    var 含剧透: Bool
    var 纯文本: String
    var 预估行数: Int

    var isEmpty: Bool { 块列表.isEmpty }
}

private nonisolated struct 标记标签 {
    let 名称: String
    let 参数: String?
    let 是结束: Bool

    init?(_ 内容: String) {
        var 主体 = 内容
        let 结束 = 主体.hasPrefix("/")
        if 结束 { 主体.removeFirst() }

        let 部分 = 主体.split(separator: "=", maxSplits: 1)
        guard let 名称部分 = 部分.first else { return nil }
        let 名称 = 名称部分
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !名称.isEmpty,
              名称.allSatisfy({
                  $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "*" || $0 == "_")
              }) else { return nil }

        self.名称 = 名称
        self.是结束 = 结束
        guard !结束, 部分.count > 1 else {
            self.参数 = nil
            return
        }
        let 原始参数 = 部分[1]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        self.参数 = 原始参数.isEmpty ? nil : 原始参数
    }
}

nonisolated enum 评论标记解析 {
    private static let 已知标签: Set<String> = [
        "b", "strong", "i", "em", "u", "s", "strike", "strikethrough", "del",
        "spoiler", "mask", "noparse", "url", "img", "color", "size", "font",
        "center", "left", "right", "indent", "sub", "sup", "style",
        "h1", "h2", "h3", "h4", "h5", "h6", "quote", "code",
        "list", "olist", "ol", "ul", "*", "hr", "br", "p",
        "table", "tr", "td", "th"
    ]

    static func 解析(_ 输入: String) -> 评论标记文本 {
        let 原文 = 输入
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var 解析器 = 标记解析器()
        var 位置 = 原文.startIndex

        while 位置 < 原文.endIndex {
            let 字符 = 原文[位置]
            guard 字符 == "[",
                  let (标签, 结束位置) = 读取标签(原文, from: 位置) else {
                解析器.追加文本(String(字符))
                位置 = 原文.index(after: 位置)
                continue
            }

            if 解析器.处理(标签) {
                位置 = 结束位置
            } else {
                解析器.追加文本(String(原文[位置..<结束位置]))
                位置 = 结束位置
            }
        }

        return 解析器.完成()
    }

    private static func 读取标签(
        _ 原文: String,
        from 起点: String.Index
    ) -> (标记标签, String.Index)? {
        var 位置 = 原文.index(after: 起点)
        var 内容 = ""

        while 位置 < 原文.endIndex, 内容.count <= 120 {
            let 字符 = 原文[位置]
            if 字符 == "]" {
                guard let 标签 = 标记标签(内容),
                      已知标签.contains(标签.名称) else { return nil }
                return (标签, 原文.index(after: 位置))
            }
            guard 字符 != "[", !字符.isNewline else { return nil }
            内容.append(字符)
            位置 = 原文.index(after: 位置)
        }
        return nil
    }
}

private nonisolated struct 标记解析器 {
    private var 块列表: [评论文本块] = []
    private var 片段列表: [评论文本片段] = []
    private var 当前类型: 评论文本块类型 = .正文
    private var 样式栈: [评论行内样式] = [评论行内样式()]
    private var 列表栈: [(有序: Bool, 计数: Int)] = []
    private var 原样标签: String?
    private var 抑制层级 = 0
    private var 待定链接起点: Int?
    private var 含剧透 = false
    private var 下一个ID = 0

    private var 当前样式: 评论行内样式 { 样式栈[样式栈.count - 1] }

    mutating func 追加文本(_ 文本: String) {
        guard 抑制层级 == 0, !文本.isEmpty else { return }
        if var 末尾 = 片段列表.last, 末尾.样式 == 当前样式 {
            末尾.文本 += 文本
            片段列表[片段列表.count - 1] = 末尾
        } else {
            片段列表.append(评论文本片段(文本: 文本, 样式: 当前样式))
        }
    }

    mutating func 处理(_ 标签: 标记标签) -> Bool {
        if let 原样标签 {
            guard 标签.是结束, 标签.名称 == 原样标签 else { return false }
            self.原样标签 = nil
            if 标签.名称 == "code" { 结束块() }
            else if 样式栈.count > 1 { 样式栈.removeLast() }
            return true
        }

        switch 标签.名称 {
        case "b", "strong": 应用行内(标签) { $0.粗体 = true }
        case "i", "em": 应用行内(标签) { $0.斜体 = true }
        case "u": 应用行内(标签) { $0.下划线 = true }
        case "s", "strike", "strikethrough", "del": 应用行内(标签) { $0.删除线 = true }
        case "spoiler", "mask":
            应用行内(标签) { $0.剧透 = true }
            if !标签.是结束 { 含剧透 = true }
        case "color", "size", "font", "style", "center", "left", "right",
             "indent", "sub", "sup":
            break
        case "noparse":
            if 标签.是结束 { 原样标签 = nil } else { 原样标签 = "noparse" }
        case "url": 处理链接(标签)
        case "img": 抑制层级 = 标签.是结束 ? max(抑制层级 - 1, 0) : 抑制层级 + 1
        default: return 处理块级(标签)
        }
        return true
    }

    private mutating func 应用行内(
        _ 标签: 标记标签,
        _ 变更: (inout 评论行内样式) -> Void
    ) {
        if 标签.是结束 {
            if 样式栈.count > 1 { 样式栈.removeLast() }
        } else {
            var 样式 = 当前样式
            变更(&样式)
            样式栈.append(样式)
        }
    }

    private mutating func 处理链接(_ 标签: 标记标签) {
        guard !标签.是结束 else {
            if let 起点 = 待定链接起点 {
                待定链接起点 = nil
                补全链接(从: 起点)
            }
            if 样式栈.count > 1 { 样式栈.removeLast() }
            return
        }

        var 样式 = 当前样式
        样式.下划线 = true
        if let 参数 = 标签.参数, let 地址 = 规范化地址(参数) {
            样式.链接 = 地址
        } else {
            待定链接起点 = 片段列表.count
        }
        样式栈.append(样式)
    }

    private mutating func 补全链接(从 起点: Int) {
        guard 起点 < 片段列表.count else { return }
        let 文字 = 片段列表[起点...].map(\.文本).joined()
        guard let 地址 = 规范化地址(文字) else { return }
        for 序号 in 起点..<片段列表.count {
            片段列表[序号].样式.链接 = 地址
        }
    }

    private func 规范化地址(_ 原始: String) -> URL? {
        let 修剪 = 原始.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !修剪.isEmpty, !修剪.contains(" ") else { return nil }
        let 补全 = 修剪.contains("://") ? 修剪 : "https://\(修剪)"
        guard let 地址 = URL(string: 补全),
              let 协议 = 地址.scheme?.lowercased(),
              协议 == "https" || 协议 == "http",
              地址.host?.isEmpty == false else { return nil }
        return 地址
    }
}

nonisolated extension 标记解析器 {
    fileprivate mutating func 处理块级(_ 标签: 标记标签) -> Bool {
        switch 标签.名称 {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let 级别 = Int(标签.名称.dropFirst()) ?? 1
            结束块()
            if !标签.是结束 { 当前类型 = .标题(级别: 级别) }
        case "quote":
            结束块()
            if !标签.是结束 { 当前类型 = .引用 }
        case "code":
            结束块()
            if !标签.是结束 {
                当前类型 = .代码
                原样标签 = "code"
            }
        case "list", "ul":
            结束块()
            if 标签.是结束 { 退出列表() } else { 列表栈.append((有序: false, 计数: 0)) }
        case "olist", "ol":
            结束块()
            if 标签.是结束 { 退出列表() } else { 列表栈.append((有序: true, 计数: 0)) }
        case "*":
            结束块()
            if !标签.是结束 { 当前类型 = .列表项(标号: 下一个标号()) }
        case "hr":
            guard !标签.是结束 else { return true }
            结束块()
            块列表.append(评论文本块(id: 取用ID(), 类型: .分隔线, 片段: []))
        case "br":
            if !标签.是结束 { 追加文本("\n") }
        case "p", "table", "tr":
            结束块()
        case "td", "th":
            if !标签.是结束, !片段列表.isEmpty { 追加文本("  ") }
        default:
            return false
        }
        return true
    }

    private mutating func 退出列表() {
        if !列表栈.isEmpty { 列表栈.removeLast() }
    }

    private mutating func 下一个标号() -> String? {
        guard var 末尾 = 列表栈.last else { return nil }
        guard 末尾.有序 else { return nil }
        末尾.计数 += 1
        列表栈[列表栈.count - 1] = 末尾
        return "\(末尾.计数)."
    }

    fileprivate mutating func 结束块(下一个类型: 评论文本块类型 = .正文) {
        defer { 当前类型 = 下一个类型 }
        guard !片段列表.isEmpty else { return }

        var 片段 = 片段列表
        片段列表 = []
        修剪首尾空白(&片段)
        guard !片段.isEmpty else { return }
        块列表.append(评论文本块(id: 取用ID(), 类型: 当前类型, 片段: 片段))
    }

    private func 修剪首尾空白(_ 片段: inout [评论文本片段]) {
        while let 首个 = 片段.first {
            let 修剪 = 去掉前导空白(首个.文本)
            if 修剪.isEmpty { 片段.removeFirst() } else {
                片段[0].文本 = 修剪
                break
            }
        }
        while let 末尾 = 片段.last {
            let 修剪 = 去掉尾随空白(末尾.文本)
            if 修剪.isEmpty { 片段.removeLast() } else {
                片段[片段.count - 1].文本 = 修剪
                break
            }
        }
    }

    private func 去掉前导空白(_ 文本: String) -> String {
        String(文本.drop { $0.isWhitespace || $0.isNewline })
    }

    private func 去掉尾随空白(_ 文本: String) -> String {
        var 结果 = Substring(文本)
        while let 末尾 = 结果.last, 末尾.isWhitespace || 末尾.isNewline {
            结果.removeLast()
        }
        return String(结果)
    }

    private mutating func 取用ID() -> Int {
        defer { 下一个ID += 1 }
        return 下一个ID
    }

    fileprivate mutating func 完成() -> 评论标记文本 {
        结束块()
        var 结果 = 块列表
        规整空行(&结果)
        let 纯文本 = 结果.map(\.纯文本).joined(separator: "\n")
        return 评论标记文本(
            块列表: 结果,
            含剧透: 含剧透,
            纯文本: 纯文本,
            预估行数: 估算行数(纯文本)
        )
    }

    private func 估算行数(_ 文本: String) -> Int {
        var 行数 = 0
        var 当前行宽 = 0

        func 结束当前行() {
            行数 += max(1, (当前行宽 + 41) / 42)
            当前行宽 = 0
        }

        for 标量 in 文本.unicodeScalars {
            if 标量 == "\n" {
                结束当前行()
                continue
            }
            let 是宽字符 = (0x2E80...0x9FFF).contains(标量.value)
                || (0x3040...0x30FF).contains(标量.value)
                || (0xAC00...0xD7AF).contains(标量.value)
            当前行宽 += 是宽字符 ? 2 : 1
        }
        结束当前行()
        return 行数
    }

    private func 规整空行(_ 块列表: inout [评论文本块]) {
        for 块序号 in 块列表.indices {
            for 片段序号 in 块列表[块序号].片段.indices {
                块列表[块序号].片段[片段序号].文本 = 块列表[块序号]
                    .片段[片段序号].文本
                    .replacingOccurrences(
                        of: "\n{3,}",
                        with: "\n\n",
                        options: .regularExpression
                    )
            }
        }
    }
}

@MainActor
final class 评论标记缓存 {
    static let shared = 评论标记缓存()

    private struct 富文本缓存键: Hashable {
        let 块: 评论文本块
        let 语言代码: String?
        let 已解除剧透: Bool
    }

    private struct 合并富文本缓存键: Hashable {
        let 原文: String
        let 语言代码: String?
        let 已解除剧透: Bool
    }

    private var 存储: [String: 评论标记文本] = [:]
    private var 顺序: [String] = []
    private var 富文本存储: [富文本缓存键: AttributedString] = [:]
    private var 富文本顺序: [富文本缓存键] = []
    private var 合并富文本存储: [合并富文本缓存键: AttributedString] = [:]
    private var 合并富文本顺序: [合并富文本缓存键] = []
    private var 预览富文本存储: [合并富文本缓存键: AttributedString] = [:]
    private var 预览富文本顺序: [合并富文本缓存键] = []
    private let 上限 = 240
    private let 富文本上限 = 360
    private let 合并富文本上限 = 120
    private let 预览富文本上限 = 120

    private init() {}

    func 标记文本(for 原文: String) -> 评论标记文本 {
        if let 已有 = 存储[原文] { return 已有 }
        let 结果 = 评论标记解析.解析(原文)
        存储[原文] = 结果
        顺序.append(原文)
        if 顺序.count > 上限 {
            存储.removeValue(forKey: 顺序.removeFirst())
        }
        return 结果
    }

    func 富文本(
        for 块: 评论文本块,
        语言代码: String?,
        已解除剧透: Bool,
        构建: () -> AttributedString
    ) -> AttributedString {
        let 键 = 富文本缓存键(
            块: 块,
            语言代码: 语言代码,
            已解除剧透: 已解除剧透
        )
        if let 已有 = 富文本存储[键] { return 已有 }

        let 结果 = 构建()
        富文本存储[键] = 结果
        富文本顺序.append(键)
        if 富文本顺序.count > 富文本上限 {
            富文本存储.removeValue(forKey: 富文本顺序.removeFirst())
        }
        return 结果
    }

    func 合并富文本(
        for 原文: String,
        语言代码: String?,
        已解除剧透: Bool,
        构建: () -> AttributedString
    ) -> AttributedString {
        let 键 = 合并富文本缓存键(
            原文: 原文,
            语言代码: 语言代码,
            已解除剧透: 已解除剧透
        )
        if let 已有 = 合并富文本存储[键] { return 已有 }

        let 结果 = 构建()
        合并富文本存储[键] = 结果
        合并富文本顺序.append(键)
        if 合并富文本顺序.count > 合并富文本上限 {
            合并富文本存储.removeValue(forKey: 合并富文本顺序.removeFirst())
        }
        return 结果
    }

    func 预览富文本(
        for 原文: String,
        语言代码: String?,
        构建: () -> AttributedString
    ) -> AttributedString {
        let 键 = 合并富文本缓存键(
            原文: 原文,
            语言代码: 语言代码,
            已解除剧透: false
        )
        if let 已有 = 预览富文本存储[键] { return 已有 }

        let 结果 = 构建()
        预览富文本存储[键] = 结果
        预览富文本顺序.append(键)
        if 预览富文本顺序.count > 预览富文本上限 {
            预览富文本存储.removeValue(forKey: 预览富文本顺序.removeFirst())
        }
        return 结果
    }
}

struct 评论正文: View {
    let 原文: String
    var 字体: Font = .callout
    var 语言代码: String? = nil
    var 预先布局完整正文 = true

    @State private var 已解除剧透 = false
    @State private var 已展开 = false
    @State private var 完整高度: CGFloat = 0
    @State private var 收起高度: CGFloat = 0
    @ScaledMetric(relativeTo: .callout) private var 日文额外行距: CGFloat = 4

    private var 展开动画: Animation {
        .smooth(duration: 0.34, extraBounce: 0)
    }

    var body: some View {
        let 内容 = 评论标记缓存.shared.标记文本(for: 原文)
        let 需要解除剧透 = 内容.含剧透 && !已解除剧透

        VStack(alignment: .leading, spacing: 6) {
            正文层(内容)
                .animation(展开动画, value: 已展开)

            if 应显示更多按钮 {
                Button {
                    withAnimation(展开动画) {
                        已展开.toggle()
                    }
                } label: {
                    Text(已展开 ? "收起" : "更多")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 2)
                .accessibilityLabel(已展开 ? "收起评论" : "展开评论")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            guard 需要解除剧透 else { return }
            withAnimation(.easeInOut(duration: 0.2)) { 已解除剧透 = true }
        }
        .accessibilityHint(需要解除剧透 ? Text("轻点以显示剧透内容") : Text(verbatim: ""))
        .animation(.easeInOut(duration: 0.2), value: 已解除剧透)
    }

    private var 应显示更多按钮: Bool {
        guard 预先布局完整正文 else { return 可能需要更多按钮 }
        return 完整高度 > 0 && 收起高度 > 0 && 完整高度 > 收起高度 + 1
    }

    private var 可能需要更多按钮: Bool {
        评论标记缓存.shared.标记文本(for: 原文).预估行数 > 6
    }

    private var 评论语言是日文: Bool {
        let 语言 = 语言代码?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        return 语言 == "ja" || 语言 == "ja-jp"
    }

    private func 正文层(_ 内容: 评论标记文本) -> some View {
        ZStack(alignment: .topLeading) {
            if 预先布局完整正文 || 已展开 {
                完整正文(内容)
                    .opacity(已展开 ? 1 : 0)
                    .transition(.opacity)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: 评论正文完整高度Key.self,
                                value: proxy.size.height
                            )
                        }
                    }
            }

            if 预先布局完整正文 || !已展开 {
                收起正文(内容)
                    .opacity(已展开 ? 0 : 1)
                    .transition(.opacity)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: 评论正文收起高度Key.self,
                                value: proxy.size.height
                            )
                        }
                    }
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 0,
            alignment: .topLeading
        )
        .frame(
            height: 已展开
                ? (完整高度 > 0 ? 完整高度 : nil)
                : (收起高度 > 0 ? 收起高度 : nil),
            alignment: .topLeading
        )
        .clipped()
        .onPreferenceChange(评论正文收起高度Key.self) {
            收起高度 = $0
        }
        .onPreferenceChange(评论正文完整高度Key.self) {
            完整高度 = $0
        }
    }

    @ViewBuilder
    private func 收起正文(_ 内容: 评论标记文本) -> some View {
        if 预先布局完整正文 {
            合并正文文本(内容)
                .lineLimit(6)
                .lineSpacing(评论语言是日文 ? 日文额外行距 : 0)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            轻量预览文本(内容)
                .lineLimit(6)
                .lineSpacing(评论语言是日文 ? 日文额外行距 : 0)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func 轻量预览文本(_ 内容: 评论标记文本) -> Text {
        let 结果 = 评论标记缓存.shared.预览富文本(
            for: 原文,
            语言代码: 语言代码
        ) {
            var 富文本 = AttributedString(内容.纯文本)
            富文本.font = 评论预览字体
            评论文字语言标记.应用(
                to: &富文本,
                文本原文: 内容.纯文本,
                语言代码: 语言代码,
                日文字体: .custom("HiraginoSans-W4", size: 17, relativeTo: .callout),
                日文字体名称: "HiraginoSans-W4",
                中文字体: .custom("PingFangSC-Regular", size: 17, relativeTo: .callout)
            )
            return 富文本
        }
        return Text(结果)
    }

    private var 评论预览字体: Font {
        let 语言 = 语言代码?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        switch 语言 {
        case "ja", "ja-jp":
            return 字体
        case "zh", "zh-hans", "zh-cn", "zh-sg":
            return .custom("PingFangSC-Regular", size: 17, relativeTo: .callout)
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo":
            return .custom("PingFangTC-Regular", size: 17, relativeTo: .callout)
        case "ko", "ko-kr":
            return .custom("AppleSDGothicNeo-Regular", size: 17, relativeTo: .callout)
        default:
            return 字体
        }
    }

    private func 完整正文(_ 内容: 评论标记文本) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(内容.块列表) { 块 in
                块视图(块)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func 合并正文文本(_ 内容: 评论标记文本) -> Text {
        let 结果 = 评论标记缓存.shared.合并富文本(
            for: 原文,
            语言代码: 语言代码,
            已解除剧透: 已解除剧透
        ) {
            var 合并结果 = AttributedString()
            for (索引, 块) in 内容.块列表.enumerated() {
                if 索引 > 0 {
                    合并结果 += AttributedString("\n\n")
                }
                if case .列表项(let 标号) = 块.类型 {
                    var 前缀 = AttributedString("\(标号 ?? "•") ")
                    前缀.font = 字体.weight(.semibold)
                    前缀.foregroundColor = .secondary
                    合并结果 += 前缀
                }
                合并结果 += 富文本(块)
            }
            return 合并结果
        }
        return Text(结果)
    }

    @ViewBuilder
    private func 块视图(_ 块: 评论文本块) -> some View {
        switch 块.类型 {
        case .分隔线:
            Divider()
                .padding(.vertical, 2)
        case .引用:
            HStack(alignment: .top, spacing: 8) {
                Capsule(style: .continuous)
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 3)
                文本视图(块)
                    .foregroundStyle(.secondary)
            }
        case .代码:
            文本视图(块)
                .padding(10)
                .background(
                    Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        case .列表项(let 标号):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: 标号 ?? "•")
                    .font(字体.weight(.semibold))
                    .foregroundStyle(.secondary)
                文本视图(块)
            }
        case .正文, .标题:
            文本视图(块)
        }
    }

    private func 文本视图(_ 块: 评论文本块) -> some View {
        Text(富文本(块))
            .lineSpacing(评论语言是日文 ? 日文额外行距 : 0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func 基准字体(_ 块: 评论文本块) -> Font {
        switch 块.类型 {
        case .标题(let 级别):
            switch 级别 {
            case 1: return .title3.weight(.bold)
            case 2: return .headline
            default: return .subheadline.weight(.semibold)
            }
        case .代码:
            return .system(.footnote, design: .monospaced)
        default:
            return 字体
        }
    }

    private func 富文本(_ 块: 评论文本块) -> AttributedString {
        评论标记缓存.shared.富文本(
            for: 块,
            语言代码: 语言代码,
            已解除剧透: 已解除剧透
        ) {
            var 结果 = AttributedString()
            for 片段 in 块.片段 {
                var 部分 = AttributedString(片段.文本)
                部分.font = 评论基准字体(for: 块)
                var 强调: InlinePresentationIntent = []
                if 片段.样式.粗体 { 强调.insert(.stronglyEmphasized) }
                if 片段.样式.斜体 { 强调.insert(.emphasized) }
                if !强调.isEmpty { 部分.inlinePresentationIntent = 强调 }
                if 片段.样式.下划线 { 部分.underlineStyle = .single }
                if 片段.样式.删除线 { 部分.strikethroughStyle = .single }
                if let 链接 = 片段.样式.链接 { 部分.link = 链接 }
                if 片段.样式.剧透 {
                    if 已解除剧透 {
                        部分.backgroundColor = .secondary.opacity(0.22)
                    } else {
                        部分.foregroundColor = .clear
                        部分.backgroundColor = .secondary.opacity(0.55)
                    }
                }
                结果 += 部分
            }

            评论文字语言标记.应用(
                to: &结果,
                文本原文: 块.片段.map(\.文本).joined(),
                语言代码: 语言代码,
                日文字体: 日文字体(for: 块),
                日文字体名称: 日文字体名称(for: 块),
                中文字体: 中文字体(for: 块)
            )
            return 结果
        }
    }

    private func 评论基准字体(for 块: 评论文本块) -> Font {
        let 样式: Font.TextStyle
        switch 块.类型 {
        case .标题(let 级别):
            样式 = 级别 == 1 ? .title3 : (级别 == 2 ? .headline : .subheadline)
        case .代码:
            样式 = .footnote
        default:
            样式 = .callout
        }

        let 语言 = 语言代码?
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
        let 字体名称: String?
        switch 语言 {
        case "zh", "zh-hans", "zh-cn", "zh-sg":
            字体名称 = "PingFangSC-Regular"
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo":
            字体名称 = "PingFangTC-Regular"
        case "ko", "ko-kr":
            字体名称 = "AppleSDGothicNeo-Regular"
        case "ja", "ja-jp":
            字体名称 = nil
        default:
            字体名称 = nil
        }
        guard let 字体名称 else { return 基准字体(块) }
        let 字体 = Font.custom(字体名称, size: 17, relativeTo: 样式)
        switch 块.类型 {
        case .标题(let 级别):
            return 字体.weight(级别 == 1 ? .bold : (级别 == 2 ? .semibold : .medium))
        case .代码:
            return 基准字体(块)
        default:
            return 字体
        }
    }

    private func 日文字体(for 块: 评论文本块) -> Font {
        let 相对样式: Font.TextStyle
        switch 块.类型 {
            case .标题(let 级别):
            相对样式 = 级别 == 1 ? .title3 : (级别 == 2 ? .headline : .subheadline)
        case .代码:
            相对样式 = .footnote
        default:
            相对样式 = .callout
        }
        return .custom(日文字体名称(for: 块), size: 17, relativeTo: 相对样式)
    }

    private func 日文字体名称(for 块: 评论文本块) -> String {
        switch 块.类型 {
        case .标题(let 级别):
            switch 级别 {
            case 1: return "HiraginoSans-W6"
            case 2: return "HiraginoSans-W5"
            default: return "HiraginoSans-W4"
            }
        default:
            return "HiraginoSans-W4"
        }
    }

    private func 中文字体(for 块: 评论文本块) -> Font {
        let 样式: Font.TextStyle
        switch 块.类型 {
        case .标题(let 级别):
            样式 = 级别 == 1 ? .title3 : (级别 == 2 ? .headline : .subheadline)
        case .代码:
            return 基准字体(块)
        default:
            样式 = .callout
        }

        let 字体 = Font.custom("PingFangSC-Regular", size: 17, relativeTo: 样式)
        switch 块.类型 {
        case .标题(let 级别):
            return 字体.weight(级别 == 1 ? .bold : (级别 == 2 ? .semibold : .medium))
        default:
            return 字体
        }
    }
}

private enum 评论文字语言标记 {
    private static let 日文词组正则 = try! NSRegularExpression(
        pattern: "[\\p{Hiragana}\\p{Katakana}\\uFF66-\\uFF9D]+"
    )
    private static let 日文文字正则 = try! NSRegularExpression(
        pattern: "[\\p{Hiragana}\\p{Katakana}\\p{Han}\\u3000-\\u303F\\uFF66-\\uFF9D]+"
    )
    private static let 句末字符: Set<Character> = Set("。！？!?；;：:\n\r.")

    static func 应用(
        to 文本: inout AttributedString,
        文本原文: String,
        语言代码: String?,
        日文字体: Font,
        日文字体名称: String,
        中文字体: Font
    ) {
        let 语言 = 语言代码?.replacingOccurrences(of: "_", with: "-").lowercased()

        switch 语言 {
        case "ja", "ja-jp":
            文本.languageIdentifier = "ja"
            标记日文文字(
                文本原文: 文本原文,
                文本: &文本,
                日文字体: 日文字体,
                日文字体名称: 日文字体名称,
                中文字体: 中文字体
            )
        case "zh", "zh-hans", "zh-cn", "zh-sg":
            文本.languageIdentifier = "zh-Hans"
            标记日文假名(文本原文: 文本原文, 文本: &文本, 字体: 日文字体)
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo":
            文本.languageIdentifier = "zh-Hant"
            标记日文假名(文本原文: 文本原文, 文本: &文本, 字体: 日文字体)
        case "ko", "ko-kr":
            文本.languageIdentifier = "ko"
            标记日文假名(文本原文: 文本原文, 文本: &文本, 字体: 日文字体)
        case "en", "en-us", "en-gb":
            文本.languageIdentifier = "en"
            标记日文假名(文本原文: 文本原文, 文本: &文本, 字体: 日文字体)
        default:
            标记日文假名(文本原文: 文本原文, 文本: &文本, 字体: 日文字体)
        }
    }

    private static func 标记日文假名(
        文本原文: String,
        文本: inout AttributedString,
        字体: Font
    ) {
        guard 文本原文.unicodeScalars.contains(where: { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D:
                return true
            default:
                return false
            }
        }) else { return }

        标记(
            nil,
            正则: 日文词组正则,
            文本原文: 文本原文,
            文本: &文本,
            字体: 字体
        )
    }

    private static func 标记日文文字(
        文本原文: String,
        文本: inout AttributedString,
        日文字体: Font,
        日文字体名称: String,
        中文字体: Font
    ) {
        guard 文本原文.unicodeScalars.contains(where: { scalar in
            switch scalar.value {
            case 0x3000...0x30FF, 0x31F0...0x31FF,
                 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xF900...0xFAFF, 0xFF66...0xFF9D:
                return true
            default:
                return false
            }
        }) else { return }

        标记(
            nil,
            正则: 日文文字正则,
            文本原文: 文本原文,
            文本: &文本,
            字体: 日文字体
        )

        标记中文句子(
            文本原文: 文本原文,
            文本: &文本,
            日文字体名称: 日文字体名称,
            字体: 中文字体
        )
    }

    private static func 标记中文句子(
        文本原文: String,
        文本: inout AttributedString,
        日文字体名称: String,
        字体: Font
    ) {
        var 句子起点 = 文本原文.startIndex
        var 游标 = 句子起点

        while 游标 < 文本原文.endIndex {
            let 下一位置 = 文本原文.index(after: 游标)
            if 句末字符.contains(文本原文[游标]) {
                标记中文句子(
                    文本原文: 文本原文,
                    文本: &文本,
                    范围: 句子起点..<下一位置,
                    日文字体名称: 日文字体名称,
                    字体: 字体
                )
                句子起点 = 下一位置
            }
            游标 = 下一位置
        }

        if 句子起点 < 文本原文.endIndex {
            标记中文句子(
                文本原文: 文本原文,
                文本: &文本,
                范围: 句子起点..<文本原文.endIndex,
                日文字体名称: 日文字体名称,
                字体: 字体
            )
        }
    }

    private static func 标记中文句子(
        文本原文: String,
        文本: inout AttributedString,
        范围: Range<String.Index>,
        日文字体名称: String,
        字体: Font
    ) {
        let 句子 = 文本原文[范围]
        guard 标题工具.日文句子需要中文字体(
            句子,
            日文字体名称: 日文字体名称
        ) else {
            return
        }

        let NS范围 = NSRange(范围, in: 文本原文)
        for 匹配 in 日文文字正则.matches(
            in: 文本原文,
            range: NS范围
        ) {
            guard let 属性范围 = Range(匹配.range, in: 文本) else { continue }
            文本[属性范围].languageIdentifier = "zh-Hans"
            文本[属性范围].font = 字体
        }
    }

    private static func 标记(
        _ 语言: String?,
        正则: NSRegularExpression,
        文本原文: String,
        文本: inout AttributedString,
        字体: Font? = nil
    ) {
        let NSString文本 = 文本原文 as NSString
        for 匹配 in 正则.matches(
            in: 文本原文,
            range: NSRange(location: 0, length: NSString文本.length)
        ) {
            guard let 范围 = Range(匹配.range, in: 文本) else { continue }
            if let 语言 {
                文本[范围].languageIdentifier = 语言
            }
            if let 字体 {
                文本[范围].font = 字体
            }
        }
    }
}

private struct 评论正文收起高度Key: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct 评论正文完整高度Key: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
