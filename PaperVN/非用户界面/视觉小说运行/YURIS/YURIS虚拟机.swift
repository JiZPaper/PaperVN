import Foundation

/// 变量。标量放在 `标量`，数组放在 `元素`（多维按行展开）。
nonisolated final class YURIS变量 {
    // 这些属性读写极频繁，关掉运行时的独占检查（虚拟机只在一个线程上跑）
    @exclusivity(unchecked) var 类型: Int
    @exclusivity(unchecked) var 维度: [Int]
    @exclusivity(unchecked) var 标量: YURIS值
    @exclusivity(unchecked) var 元素: [YURIS值]
    /// 局部变量声明时的调用深度，全局和静态变量是 -1
    var 帧深度: Int

    init(类型: Int, 维度: [Int] = [], 初值: YURIS值? = nil, 帧深度: Int = -1) {
        self.类型 = 类型
        self.维度 = 维度
        self.帧深度 = 帧深度
        let value = 初值 ?? YURIS虚拟机.默认值(类型)
        标量 = value
        if 维度.isEmpty {
            元素 = []
        } else {
            元素 = [YURIS值](repeating: value, count: max(0, 维度.reduce(1, *)))
        }
    }

    @inline(__always)
    func 展开(_ indices: ArraySlice<YURIS值>) -> Int {
        // 一维最常见
        if 维度.count == 1, indices.count == 1 {
            return indices[indices.startIndex].转Int
        }
        guard 维度.count == indices.count else {
            // 维度对不上时按一维处理，脚本偶尔会把一维数组当二维读
            var flat = 0
            for value in indices { flat = flat * 1 + value.转Int }
            return flat
        }
        var flat = 0
        var position = 0
        for value in indices {
            flat = flat * 维度[position] + value.转Int
            position += 1
        }
        return flat
    }
}

nonisolated struct YURIS循环项 {
    let 开始: Int
    let 结束: Int
    let 总数: Int64
    var 计数: Int64
}

nonisolated final class YURIS帧 {
    @exclusivity(unchecked) var 脚本: YURIS脚本文件
    @exclusivity(unchecked) var pc: Int
    @exclusivity(unchecked) var 循环: [YURIS循环项] = []
    /// 下标 1...16。GOSUB 传入的参数
    @exclusivity(unchecked) var 参数: [YURIS值?] = []
    /// RETURN 传回的值，留在调用方这一帧
    @exclusivity(unchecked) var 返回值: [YURIS值?] = []
    /// 被这一帧遮住的同号局部变量，RETURN 时还原
    @exclusivity(unchecked) var 遮蔽: [(Int, YURIS变量?)] = []
    let 深度: Int

    init(脚本: YURIS脚本文件, pc: Int, 深度: Int) {
        self.脚本 = 脚本
        self.pc = pc
        self.深度 = 深度
    }
}

nonisolated final class YURIS任务 {
    var 名称: [UInt8]
    var 优先度: Int64
    var 启用 = true
    @exclusivity(unchecked) var 帧栈: [YURIS帧] = []
    @exclusivity(unchecked) var 局部: [YURIS变量?]
    /// 还要等几帧
    var 等待帧 = 0
    /// 等到这个时间（毫秒）
    var 等待到: Double = 0
    var 已结束 = false
    var 任务参数: [Int64] = [Int64](repeating: 0, count: 17)
    var 文字行: Int = 0
    var 下句语音: Int = 0
    /// OUTPUTMODE=1：等引擎显示完这段文字
    var 等待自动文字 = false

    init(名称: [UInt8], 优先度: Int64, 变量数: Int) {
        self.名称 = 名称
        self.优先度 = 优先度
        局部 = [YURIS变量?](repeating: nil, count: 变量数)
    }
}

/// 变量引用（赋值用）
nonisolated enum YURIS引用 {
    case 标量(YURIS变量)
    case 元素(YURIS变量, Int)
    case 整个数组(YURIS变量)
    case 无
}

/// YU-RIS 虚拟机。所有方法只在运行线程上调用，界面线程只通过 `输入` 和 `最新画面` 交流。
nonisolated final class YURIS虚拟机: @unchecked Sendable {
    static func 默认值(_ type: Int) -> YURIS值 {
        switch type {
        case 2: return .小数(0)
        case 3: return .文字([])
        default: return .整数(0)
        }
    }

    let 程序: YURIS程序
    let 存档目录: URL
    @exclusivity(unchecked) var 全局: [YURIS变量?]
    var 任务表: [YURIS任务] = []
    private var 新任务: [YURIS任务] = []
    @exclusivity(unchecked) var 当前任务: YURIS任务!
    var 帧数: Int = 0
    let 开始时间 = Date()
    var 已结束 = false
    var 请求重启 = false
    @exclusivity(unchecked) var 变量容量: Int
    @exclusivity(unchecked) var 栈: [YURIS值] = []
    @exclusivity(unchecked) private var 下标基址: [(Int, Int)] = []
    private var 引擎命令: [((YURIS虚拟机, YURIS指令) -> Void)?] = []
    private var 已跑静态 = Set<Int>()
    private var 标签小写: [[UInt8]: YURIS标签]?
    /// 未实现的命令只提示一次
    var 已提示: Set<String> = []
    var 日志: (String) -> Void = { _ in }
    var 跟踪引擎命令 = false
    var 跟踪MATH3D = false

    // 文字
    var 文字输出模式 = 1
    // 图形、声音、文字等状态
    let 画面: YURIS画面
    let 声音: YURIS声音
    var 字体 = YURIS字体状态()
    var 输入状态 = YURIS输入状态()
    /// 待写入的存档（SAVE 预约）
    var 预约存档: [Int: YURIS存档项] = [:]
    var 存档缓存: [String: [Int: YURIS存档项]] = [:]
    let 影片 = YURIS影片状态()
    let 自动文字 = YURIS自动文字()
    var 图层影片: [(图层: YURIS图层, 播放器: 视觉小说影片)] = []
    var Flash状态 = YURISFlash状态()
    var Flash接口: (any YURISFlash接口)?
    var MIDI文件 = ""
    var MIDI接口: (any YURISMIDI接口)?
    var 对话框: ((YURIS对话框请求) -> Int)?

    enum 启动错误: Error { case 没有入口 }

    init(程序: YURIS程序, 存档目录: URL, 声音: YURIS声音) throws {
        self.程序 = 程序
        self.存档目录 = 存档目录
        self.声音 = 声音
        var capacity = 6000
        for item in 程序.变量定义 { capacity = max(capacity, item.编号 + 1) }
        变量容量 = capacity
        全局 = [YURIS变量?](repeating: nil, count: capacity)
        画面 = YURIS画面(资源: 程序.资源, 宽: 程序.窗口宽, 高: 程序.窗口高)
        for item in 程序.变量定义 where item.类型 != 0 {
            let initial: YURIS值
            switch item.类型 {
            case 1: initial = .整数(item.整数初值)
            case 2: initial = .小数(item.小数初值)
            default:
                // 文字初值存的是表达式字节码（带引号）
                let code = item.文字初值
                if case .常量(let value) = YURIS表达式.编译(code, 0, code.count) {
                    initial = .文字(value.转文字)
                } else {
                    initial = .文字(code)
                }
            }
            全局[item.编号] = YURIS变量(类型: item.类型, 维度: item.维度, 初值: initial)
        }
        建立引擎命令表()
        初始化系统变量()
        guard let entry = 程序.标签[Array("SYSTEM_START".utf8)], let script = 程序.脚本(entry.脚本) else {
            // 没有 SYSTEM_START 时从脚本 0 开头运行
            guard let first = 程序.脚本(0) else { throw 启动错误.没有入口 }
            let task = YURIS任务(名称: Array("SYSTEM".utf8), 优先度: 100, 变量数: capacity)
            task.帧栈.append(YURIS帧(脚本: first, pc: 0, 深度: 0))
            任务表.append(task)
            当前任务 = task
            运行静态声明(first)
            return
        }
        let task = YURIS任务(名称: Array("SYSTEM".utf8), 优先度: 100, 变量数: capacity)
        task.帧栈.append(YURIS帧(脚本: script, pc: entry.位置, 深度: 0))
        任务表.append(task)
        当前任务 = task
        运行静态声明(script)
    }

    // MARK: - 帧

    /// 跑一帧：更新输入和时间，按优先度依次运行任务
    func 运行一帧() {
        guard !已结束 else { return }
        帧数 += 1
        更新系统变量()
        声音.更新(帧数: 帧数)
        更新影片()
        更新图层影片()
        更新自动文字()
        // 优先度高的先跑；相同优先度保持创建顺序
        let order = 任务表.enumerated().sorted {
            $0.element.优先度 != $1.element.优先度 ? $0.element.优先度 > $1.element.优先度 : $0.offset < $1.offset
        }.map(\.element)
        for task in order {
            运行(task)
            if 已结束 { return }
        }
        // 这一帧里新生成的任务马上开始
        var guardCount = 0
        while !新任务.isEmpty, guardCount < 64 {
            let pending = 新任务
            新任务 = []
            for task in pending { 运行(task) }
            guardCount += 1
        }
        任务表.removeAll { $0.已结束 }
    }

    private func 运行(_ task: YURIS任务) {
        guard task.启用, !task.已结束 else { return }
        if task.等待自动文字 {
            guard 自动文字.队列.isEmpty, !自动文字.等待点按 else { return }
            task.等待自动文字 = false
        }
        if task.等待帧 > 0 {
            task.等待帧 -= 1
            if task.等待帧 > 0 { return }
        }
        if task.等待到 > 0 {
            if 当前毫秒 < task.等待到 { return }
            task.等待到 = 0
        }
        当前任务 = task
        执行(task)
    }

    /// 命令行测试时按帧数走时钟，不用真的等
    var 虚拟时钟 = false
    var 当前毫秒: Double {
        虚拟时钟 ? Double(帧数) * 1000 / 60 : Date().timeIntervalSince(开始时间) * 1000
    }

    /// 持续执行到等待或结束
    private func 执行(_ task: YURIS任务) {
        var budget = 3_000_000
        while budget > 0 {
            budget -= 1
            guard let frame = task.帧栈.last else {
                task.已结束 = true
                if 是系统任务(task) { 已结束 = true }
                return
            }
            let script = frame.脚本
            guard frame.pc < script.指令.count else {
                // 走到文件尾：相当于 RETURN，系统任务结束就结束游戏
                退帧(task, 返回值: nil)
                continue
            }
            let index = frame.pc
            let ins = script.指令[index]
            frame.pc = index + 1
            switch ins.种类 {
            case .无, .静态声明, .判断结束:
                break
            case .判断:
                if !条件(ins) {
                    frame.pc = ins.目标 > 0 ? ins.目标 : (ins.结束 >= 0 ? ins.结束 : index + 1)
                }
            case .否则:
                if !ins.参数.isEmpty, !条件(ins) {
                    frame.pc = ins.目标 > 0 ? ins.目标 : (ins.结束 >= 0 ? ins.结束 : index + 1)
                }
            case .分支结束:
                if ins.结束 >= 0 { frame.pc = ins.结束 }
            case .判断跳出:
                if ins.结束 >= 0 { frame.pc = ins.结束 }
            case .判断重来:
                if ins.目标 >= 0 { frame.pc = ins.目标 }
            case .循环:
                let count: Int64 = ins.参数.isEmpty ? -1 : 求值(ins.参数[0].表达式).转整数
                if count == 0 {
                    frame.pc = ins.目标 + 1
                } else {
                    frame.循环.append(YURIS循环项(开始: index, 结束: ins.目标, 总数: count, 计数: 1))
                }
            case .循环结束:
                // 带标签跳出循环后可能留下陈旧的项
                while let top = frame.循环.last, top.结束 != index { frame.循环.removeLast() }
                if var top = frame.循环.popLast() {
                    top.计数 += 1
                    if top.总数 < 0 || top.计数 <= top.总数 {
                        frame.循环.append(top)
                        frame.pc = top.开始 + 1
                    }
                }
            case .循环跳出:
                var level = 1
                if let first = ins.参数.first { level = max(1, 求值(first.表达式).转Int) }
                var target = -1
                for _ in 0..<level {
                    if let top = frame.循环.popLast() { target = top.结束 }
                }
                if target >= 0 { frame.pc = target + 1 }
            case .循环重来:
                var level = 1
                if let first = ins.参数.first { level = max(1, 求值(first.表达式).转Int) }
                for _ in 1..<max(1, level) { _ = frame.循环.popLast() }
                if let top = frame.循环.last { frame.pc = top.结束 }
            case .跳转:
                if let first = ins.参数.first { 跳到(task, 标签: 求值(first.表达式).转文字) }
            case .调用:
                调用(task, ins)
            case .返回:
                var values: [YURIS值?]?
                if !ins.参数.isEmpty {
                    var list = [YURIS值?](repeating: nil, count: 17)
                    for argument in ins.参数 where argument.槽 > 0 && argument.槽 <= 16 {
                        list[argument.槽] = 求值(argument.表达式)
                    }
                    values = list
                }
                退帧(task, 返回值: values)
            case .结束:
                var restart = false
                if let first = ins.参数.first { restart = 求值(first.表达式).为真 }
                请求重启 = restart
                已结束 = true
                return
            case .赋值:
                guard ins.参数.count >= 2 else { break }
                let target = ins.参数[0]
                let value = 求值(ins.参数[1].表达式)
                写入(求引用(target.表达式), value, 运算: target.赋值)
            case .整数变量: 声明(task, ins, 类型: 1)
            case .小数变量: 声明(task, ins, 类型: 2)
            case .文字变量: 声明(task, ins, 类型: 3)
            case .任意变量: 声明(task, ins, 类型: 0)
            case .文字:
                if let text = ins.参数.first?.文字 {
                    if 文字输出模式 == 1 {
                        自动文字追加(text)
                        return
                    }
                    追加文字(text)
                }
            case .表达式文字:
                if let first = ins.参数.first {
                    let text = 求值(first.表达式).转文字
                    if 文字输出模式 == 1 {
                        自动文字追加(text)
                        return
                    }
                    追加文字(text)
                }
            case .行结束:
                if let first = ins.参数.first {
                    task.文字行 = first.编号
                    task.下句语音 = first.原始大小
                }
                if 文字输出模式 == 1 {
                    自动文字行尾()
                    return
                }
                // 行尾标记：文字任务看到 E 才处理点按等待和换页
                if let flags = 全局[101] { flags.标量 = .文字(flags.标量.转文字 + [0x45]) }
                // 显示文字要让出这一帧，其他任务才有机会接手
                task.等待帧 = 1
                return
            case .等待:
                var frames = 0, time = 0.0
                for argument in ins.参数 {
                    switch argument.关键字 {
                    case "FRAME": frames = 求值(argument.表达式).转Int
                    case "TIME": time = 求值(argument.表达式).转小数
                    default: break
                    }
                }
                if time > 0 {
                    task.等待到 = 当前毫秒 + time
                    task.等待帧 = 1
                } else {
                    task.等待帧 = max(1, frames)
                }
                return
            case .引擎:
                if ins.命令 < 引擎命令.count, let handler = 引擎命令[ins.命令] {
                    if 跟踪引擎命令 { 跟踪(ins, script, index) }
                    handler(self, ins)
                    if 已结束 { return }
                    if task.已结束 || task.帧栈.isEmpty { return }
                    // TASK[SCRIPTPOS] 或 E=0 作用于自己时要立刻停
                    if !task.启用 { return }
                } else {
                    提示未实现(程序.命令表[ins.命令].名称)
                }
            }
        }
        // 防止脚本死循环把整个 App 拖住
        task.等待帧 = 1
    }

    private func 跟踪(_ ins: YURIS指令, _ script: YURIS脚本文件, _ index: Int) {
        var parts: [String] = []
        for argument in ins.参数 {
            parts.append("\(argument.关键字)=\(描述(argument.表达式))")
        }
        日志("[\(帧数)] s\(script.序号):\(index) \(程序.命令表[ins.命令].名称)[\(parts.joined(separator: " "))]")
    }

    private func 描述(_ expression: YURIS表达式) -> String {
        switch expression {
        case .整个数组(let number): return "()\(number)"
        case .空: return ""
        default: return 求值(expression).显示文字
        }
    }

    func 提示未实现(_ name: String) {
        guard !已提示.contains(name) else { return }
        已提示.insert(name)
        日志("未实现：\(name)")
    }

    func 是系统任务(_ task: YURIS任务) -> Bool {
        task.名称 == Array("SYSTEM".utf8)
    }

    func 添加任务(_ task: YURIS任务) {
        任务表.append(task)
        新任务.append(task)
    }

    func 查找任务(_ name: [UInt8]) -> YURIS任务? {
        任务表.first { $0.名称 == name && !$0.已结束 }
    }

    // MARK: - 控制流

    @inline(__always)
    private func 条件(_ ins: YURIS指令) -> Bool {
        guard let first = ins.参数.first else { return true }
        return 求值(first.表达式).为真
    }

    func 查标签(_ name: [UInt8]) -> YURIS标签? {
        if let label = 程序.标签[name] { return label }
        if 标签小写 == nil {
            var map: [[UInt8]: YURIS标签] = [:]
            for (key, value) in 程序.标签 { map[YURIS虚拟机.小写(key)] = value }
            标签小写 = map
        }
        return 标签小写?[YURIS虚拟机.小写(name)]
    }

    static func 小写(_ bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        var i = 0
        while i < result.count {
            let c = result[i]
            if YURIS文本.是首字节(c) { i += YURIS文本.字符长度(result, i); continue }
            if c >= 0x41, c <= 0x5A { result[i] = c + 0x20 }
            i += 1
        }
        return result
    }

    func 取脚本(_ index: Int) -> YURIS脚本文件? {
        guard let script = 程序.脚本(index) else { return nil }
        运行静态声明(script)
        return script
    }

    private func 运行静态声明(_ script: YURIS脚本文件) {
        guard 已跑静态.insert(script.序号).inserted else { return }
        for ins in script.指令 where ins.种类 == .静态声明 {
            let name = 程序.命令表[ins.命令].名称
            let type: Int
            switch name {
            case "S_INT", "G_INT": type = 1
            case "S_FLT", "G_FLT": type = 2
            case "S_STR", "G_STR": type = 3
            default: type = 0
            }
            声明全局(ins, 类型: type)
        }
    }

    private func 声明全局(_ ins: YURIS指令, 类型 type: Int) {
        guard let first = ins.参数.first else { return }
        let (number, dims) = 声明目标(first.表达式)
        guard number >= 0 else { return }
        let initial: YURIS值? = ins.参数.count > 1 ? 转换(求值(ins.参数[1].表达式), 类型: type) : nil
        确保容量(number)
        全局[number] = YURIS变量(类型: type, 维度: dims, 初值: initial)
    }

    private func 确保容量(_ number: Int) {
        guard number >= 变量容量 else { return }
        let grow = number + 1024 - 变量容量
        全局.append(contentsOf: [YURIS变量?](repeating: nil, count: grow))
        for task in 任务表 { task.局部.append(contentsOf: [YURIS变量?](repeating: nil, count: grow)) }
        变量容量 += grow
    }

    private func 声明目标(_ expression: YURIS表达式) -> (Int, [Int]) {
        switch expression {
        case .变量(let number): return (number, [])
        case .下标常量(let number, let dim): return (number, [dim])
        case .整个数组(let number): return (number, [])
        case .通用(let ops):
            guard case .下标开始(let number) = ops.first else { return (-1, []) }
            let base = 栈.count
            运行(ops[1..<(ops.count - 1)])
            let dims = 栈[base...].map(\.转Int)
            栈.removeSubrange(base...)
            return (number, dims)
        default: return (-1, [])
        }
    }

    private func 声明(_ task: YURIS任务, _ ins: YURIS指令, 类型 type: Int) {
        guard let first = ins.参数.first else { return }
        let (number, dims) = 声明目标(first.表达式)
        guard number >= 0 else { return }
        确保容量(number)
        let initial: YURIS值? = ins.参数.count > 1 ? 转换(求值(ins.参数[1].表达式), 类型: type) : nil
        guard let frame = task.帧栈.last else { return }
        if let existing = task.局部[number], existing.帧深度 == frame.深度 {
            existing.类型 = type
            existing.维度 = dims
            let value = initial ?? Self.默认值(type)
            existing.标量 = value
            if dims.isEmpty {
                if !existing.元素.isEmpty { existing.元素 = [] }
            } else {
                existing.元素 = [YURIS值](repeating: value, count: max(0, dims.reduce(1, *)))
            }
            return
        }
        frame.遮蔽.append((number, task.局部[number]))
        task.局部[number] = YURIS变量(类型: type, 维度: dims, 初值: initial, 帧深度: frame.深度)
    }

    func 跳到(_ task: YURIS任务, 标签 name: [UInt8]) {
        guard let label = 查标签(name), let frame = task.帧栈.last else {
            日志("找不到标签：\(YURIS文本.解码(name))")
            return
        }
        guard let script = 取脚本(label.脚本) else { return }
        frame.脚本 = script
        frame.pc = label.位置
        if frame.循环.count > label.loop层数 {
            frame.循环.removeLast(frame.循环.count - label.loop层数)
        }
    }

    private func 调用(_ task: YURIS任务, _ ins: YURIS指令) {
        guard let first = ins.参数.first, let caller = task.帧栈.last else { return }
        let resolved: YURIS标签
        if let fixed = ins.静态标签 {
            resolved = fixed
        } else {
            let name = 求值(first.表达式).转文字
            guard let label = 查标签(name) else {
                日志("找不到标签：\(YURIS文本.解码(name))")
                return
            }
            resolved = label
        }
        let label = resolved
        var parameters: [YURIS值?] = []
        if ins.参数.count > 1 {
            // 结束字段在 GOSUB 上存最大的参数槽
            parameters = [YURIS值?](repeating: nil, count: ins.结束 + 1)
            for argument in ins.参数.dropFirst() where argument.槽 > 0 {
                parameters[argument.槽] = 求值(argument.表达式)
            }
        }
        guard let script = 取脚本(label.脚本) else { return }
        let frame = YURIS帧(脚本: script, pc: label.位置, 深度: caller.深度 + 1)
        frame.参数 = parameters
        task.帧栈.append(frame)
    }

    private func 退帧(_ task: YURIS任务, 返回值 values: [YURIS值?]?) {
        guard let frame = task.帧栈.popLast() else { return }
        if !frame.遮蔽.isEmpty {
            for (number, previous) in frame.遮蔽.reversed() { task.局部[number] = previous }
        }
        if let caller = task.帧栈.last {
            caller.返回值 = values ?? []
        } else {
            task.已结束 = true
            if 是系统任务(task) { 已结束 = true }
        }
    }

    // MARK: - 求值

    func 求值(_ expression: YURIS表达式) -> YURIS值 {
        switch expression {
        case .常量(let value): return value
        case .变量(let number): return 读变量(number)
        case .下标常量(let number, let index): return 读元素(number, 下标: index)
        case .通用(let ops):
            let base = 栈.count
            运行(ops[...])
            let result = 栈.count > base ? 栈[栈.count - 1] : .整数(0)
            栈.removeLast(栈.count - base)
            return result
        case .整个数组(let number): return 读变量(number)
        case .空: return .整数(0)
        }
    }

    private func 运行(_ ops: ArraySlice<YURIS操作>) {
        for op in ops {
            switch op {
            case .常量(let value): 栈.append(value)
            case .变量(let number): 栈.append(读变量(number))
            case .整个数组(let number): 栈.append(读变量(number))
            case .下标开始(let number): 下标基址.append((number, 栈.count))
            case .下标结束:
                guard let (number, base) = 下标基址.popLast() else { break }
                let value: YURIS值
                if 栈.count - base == 1 {
                    value = 读元素(number, 下标: 栈[base].转Int)
                } else {
                    value = 读元素(number, 下标组: 栈[base...])
                }
                栈.removeLast(栈.count - base)
                栈.append(value)
            case .运算(let kind):
                运算(kind)
            }
        }
    }

    private func 运算(_ kind: YURIS运算) {
        switch kind {
        case .转整数:
            guard let top = 栈.popLast() else { return }
            if case .小数 = top { 栈.append(top) } else { 栈.append(.整数(top.转整数)) }
        case .转文字:
            guard let top = 栈.popLast() else { return }
            栈.append(.文字(top.转文字))
        case .取负:
            guard let top = 栈.popLast() else { return }
            if case .小数(let value) = top { 栈.append(.小数(-value)) } else { 栈.append(.整数(0 &- top.转整数)) }
        default:
            guard 栈.count >= 2 else { return }
            let right = 栈.removeLast()
            let left = 栈.removeLast()
            栈.append(二元(kind, left, right))
        }
    }

    private func 二元(_ kind: YURIS运算, _ left: YURIS值, _ right: YURIS值) -> YURIS值 {
        // 文字
        if left.是文字 || right.是文字 {
            let a = left.转文字, b = right.转文字
            switch kind {
            case .加: return .文字(a + b)
            case .等于: return .整数(a == b ? 1 : 0)
            case .不等于: return .整数(a != b ? 1 : 0)
            case .小于: return .整数(a.lexicographicallyPrecedes(b) ? 1 : 0)
            case .大于: return .整数(b.lexicographicallyPrecedes(a) ? 1 : 0)
            case .小于等于: return .整数(b.lexicographicallyPrecedes(a) ? 0 : 1)
            case .大于等于: return .整数(a.lexicographicallyPrecedes(b) ? 0 : 1)
            case .逻辑与: return .整数(left.为真 && right.为真 ? 1 : 0)
            case .逻辑或: return .整数(left.为真 || right.为真 ? 1 : 0)
            default: return .整数(0)
            }
        }
        // 小数
        var isReal = false
        if case .小数 = left { isReal = true }
        if case .小数 = right { isReal = true }
        if isReal {
            let a = left.转小数, b = right.转小数
            switch kind {
            case .加: return .小数(a + b)
            case .减: return .小数(a - b)
            case .乘: return .小数(a * b)
            case .除: return .小数(b == 0 ? 0 : a / b)
            case .余: return .小数(b == 0 ? 0 : fmod(a, b))
            case .小于: return .整数(a < b ? 1 : 0)
            case .小于等于: return .整数(a <= b ? 1 : 0)
            case .大于: return .整数(a > b ? 1 : 0)
            case .大于等于: return .整数(a >= b ? 1 : 0)
            case .等于: return .整数(a == b ? 1 : 0)
            case .不等于: return .整数(a != b ? 1 : 0)
            case .逻辑与: return .整数(a != 0 && b != 0 ? 1 : 0)
            case .逻辑或: return .整数(a != 0 || b != 0 ? 1 : 0)
            case .按位与: return .整数(left.转整数 & right.转整数)
            case .按位或: return .整数(left.转整数 | right.转整数)
            case .按位异或: return .整数(left.转整数 ^ right.转整数)
            default: return .整数(0)
            }
        }
        let a = left.转整数, b = right.转整数
        switch kind {
        case .加: return .整数(a &+ b)
        case .减: return .整数(a &- b)
        case .乘: return .整数(a &* b)
        case .除: return .整数(b == 0 ? 0 : a / b)
        case .余: return .整数(b == 0 ? 0 : a % b)
        case .小于: return .整数(a < b ? 1 : 0)
        case .小于等于: return .整数(a <= b ? 1 : 0)
        case .大于: return .整数(a > b ? 1 : 0)
        case .大于等于: return .整数(a >= b ? 1 : 0)
        case .等于: return .整数(a == b ? 1 : 0)
        case .不等于: return .整数(a != b ? 1 : 0)
        case .按位与: return .整数(a & b)
        case .按位或: return .整数(a | b)
        case .按位异或: return .整数(a ^ b)
        case .逻辑与: return .整数(a != 0 && b != 0 ? 1 : 0)
        case .逻辑或: return .整数(a != 0 || b != 0 ? 1 : 0)
        default: return .整数(0)
        }
    }

    // MARK: - 变量读写

    @inline(__always)
    func 变量(_ number: Int) -> YURIS变量? {
        guard number < 变量容量 else { return nil }
        if let local = 当前任务.局部[number] { return local }
        return 全局[number]
    }

    func 读变量(_ number: Int) -> YURIS值 {
        if number == 48 { return .整数(当前循环计数) }
        if let variable = 变量(number) { return variable.标量 }
        return .整数(0)
    }

    private var 当前循环计数: Int64 {
        for frame in 当前任务.帧栈.reversed() {
            if let top = frame.循环.last { return top.计数 }
        }
        return 0
    }

    func 读元素(_ number: Int, 下标 index: Int) -> YURIS值 {
        if number >= 50, number <= 58 {
            return 读调用值(number, index)
        }
        guard let variable = 变量(number) else { return .整数(0) }
        if index >= 0, index < variable.元素.count { return variable.元素[index] }
        return Self.默认值(variable.类型)
    }

    func 读元素(_ number: Int, 下标组 indices: ArraySlice<YURIS值>) -> YURIS值 {
        guard let variable = 变量(number) else { return .整数(0) }
        let index = variable.展开(indices)
        if index >= 0, index < variable.元素.count { return variable.元素[index] }
        return Self.默认值(variable.类型)
    }

    private func 读调用值(_ number: Int, _ index: Int) -> YURIS值 {
        guard let frame = 当前任务.帧栈.last, index >= 0 else { return .整数(0) }
        switch number {
        case 50, 51, 52, 53:
            let value: YURIS值? = index < frame.参数.count ? frame.参数[index] : nil
            return 读槽(value, number - 50)
        case 54, 55, 56, 57:
            let value: YURIS值? = index < frame.返回值.count ? frame.返回值[index] : nil
            return 读槽(value, number - 54)
        case 58:
            return .整数(index < 当前任务.任务参数.count ? 当前任务.任务参数[index] : 0)
        default:
            return .整数(0)
        }
    }

    @inline(__always)
    private func 读槽(_ value: YURIS值?, _ kind: Int) -> YURIS值 {
        switch kind {
        case 0: return .整数(value?.转整数 ?? 0)
        case 1: return .小数(value?.转小数 ?? 0)
        case 2: return .文字(value?.转文字 ?? [])
        default: return .整数(value == nil ? 0 : 1)
        }
    }

    func 求引用(_ expression: YURIS表达式) -> YURIS引用 {
        switch expression {
        case .变量(let number):
            return 变量或新建(number).map { .标量($0) } ?? .无
        case .整个数组(let number):
            return 变量或新建(number).map { .整个数组($0) } ?? .无
        case .下标常量(let number, let index):
            return 变量或新建(number).map { .元素($0, index) } ?? .无
        case .通用(let ops):
            guard case .下标开始(let number)? = ops.first, case .下标结束? = ops.last else { return .无 }
            let base = 栈.count
            运行(ops[1..<(ops.count - 1)])
            defer { 栈.removeLast(栈.count - base) }
            guard let variable = 变量或新建(number) else { return .无 }
            return .元素(variable, variable.展开(栈[base...]))
        default:
            return .无
        }
    }

    private func 变量或新建(_ number: Int) -> YURIS变量? {
        确保容量(number)
        if let variable = 变量(number) { return variable }
        let variable = YURIS变量(类型: 0)
        全局[number] = variable
        return variable
    }

    func 转换(_ value: YURIS值, 类型 type: Int) -> YURIS值 {
        switch type {
        case 1: return .整数(value.转整数)
        case 2: return .小数(value.转小数)
        case 3: return .文字(value.转文字)
        default: return value
        }
    }

    func 写入(_ reference: YURIS引用, _ value: YURIS值, 运算 op: Int = 0) {
        switch reference {
        case .标量(let variable):
            variable.标量 = 合并(variable.标量, value, op, variable.类型)
        case .元素(let variable, let index):
            guard index >= 0, index < variable.元素.count else { return }
            variable.元素[index] = 合并(variable.元素[index], value, op, variable.类型)
        case .整个数组(let variable):
            for i in variable.元素.indices { variable.元素[i] = 合并(variable.元素[i], value, op, variable.类型) }
        case .无:
            break
        }
    }

    private func 合并(_ old: YURIS值, _ value: YURIS值, _ op: Int, _ type: Int) -> YURIS值 {
        if op == 0 { return 转换(value, 类型: type) }
        let kind: YURIS运算
        switch op {
        case 1: kind = .加
        case 2: kind = .减
        case 3: kind = .乘
        case 4: kind = .除
        case 5: kind = .余
        case 6: kind = .按位与
        case 7: kind = .按位或
        case 8: kind = .按位异或
        default: return 转换(value, 类型: type)
        }
        return 转换(二元(kind, old, value), 类型: type)
    }

    func 读引用(_ reference: YURIS引用) -> YURIS值 {
        switch reference {
        case .标量(let variable): return variable.标量
        case .元素(let variable, let index):
            return index >= 0 && index < variable.元素.count ? variable.元素[index] : Self.默认值(variable.类型)
        case .整个数组(let variable): return variable.标量
        case .无: return .整数(0)
        }
    }

    // MARK: - 文字

    private func 追加文字(_ text: [UInt8]) {
        guard let buffer = 全局[100], let flags = 全局[101] else { return }
        buffer.标量 = .文字(buffer.标量.转文字 + text)
        flags.标量 = .文字(flags.标量.转文字 + YURIS文本.字符标记(text))
    }

    // MARK: - 引擎命令表

    private func 建立引擎命令表() {
        引擎命令 = 程序.命令表.map { YURIS命令表.处理(名称: $0.名称) }
    }

    // MARK: - 系统变量

    private func 设(_ number: Int, _ value: YURIS值) {
        guard let variable = 全局[number] else { return }
        variable.标量 = value
    }

    private func 初始化系统变量() {
        设(2, .整数(100)) // OS 版本：Windows 10
        设(3, .整数(9))
        设(4, .整数(1)) // 有声音
        设(5, .整数(4 << 30))
        设(6, .整数(2 << 30))
        设(7, .整数(0))
        设(8, .整数(490))
        设(9, .整数(0)) // 不是只读媒体
        设(10, .小数(Double.pi))
        设(11, .整数(0)) // 非调试
        设(82, .文字(Array("./".utf8)))
        设(83, .文字(Array("save/".utf8)))
        设(84, .文字(Array("save/".utf8)))
        设(85, .文字(Array("save/".utf8)))
        设(90, .整数(0))
        设(91, .整数(0)) // 走软件绘制，不用纹理
        设(92, .整数(32))
        设(93, .整数(Int64(程序.窗口宽)))
        设(94, .整数(Int64(程序.窗口高)))
        // $_CHR(n)
        if let table = 全局[105] {
            for i in 1..<min(256, table.元素.count) { table.元素[i] = .文字([UInt8(i)]) }
        }
        // 按键码：@_CODE_MOUSE_L = 393 起
        for number in 393...520 {
            设(number, .整数(Int64(number - 393 + 1)))
        }
    }

    private func 更新系统变量() {
        let now = Date()
        if let time = 全局[0], time.元素.count >= 16 {
            let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .weekday, .hour, .minute, .second, .nanosecond], from: now)
            let values = [c.year ?? 0, c.month ?? 0, c.day ?? 0, (c.weekday ?? 1) - 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0, (c.nanosecond ?? 0) / 1_000_000]
            for (i, value) in values.enumerated() { time.元素[i] = .整数(Int64(value)) }
        }
        if let elapsed = 全局[1], elapsed.元素.count >= 2 {
            let ms = Int64(当前毫秒)
            elapsed.元素[0] = .整数(ms)
            elapsed.元素[1] = .整数(ms)
        }
        输入状态.应用(到: self)
    }
}
