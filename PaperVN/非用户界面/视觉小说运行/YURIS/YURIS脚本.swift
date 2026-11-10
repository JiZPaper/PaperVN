import Foundation

/// 脚本里的值。文字保持原始字节（Shift-JIS 或 GBK），只有显示时才解码：
/// 脚本会把单字节拼成双字节字符（`$_CHR(239)+$_CHR(240)`），也按字符取子串。
nonisolated enum YURIS值: Sendable {
    case 整数(Int64)
    case 小数(Double)
    case 文字([UInt8])

    var 是文字: Bool { if case .文字 = self { return true }; return false }

    var 转整数: Int64 {
        switch self {
        case .整数(let value): return value
        case .小数(let value):
            guard value.isFinite else { return 0 }
            return Int64(max(min(value, 9.2e18), -9.2e18))
        case .文字(let bytes): return YURIS值.解析整数(bytes)
        }
    }

    var 转小数: Double {
        switch self {
        case .整数(let value): return Double(value)
        case .小数(let value): return value
        case .文字(let bytes): return Double(String(decoding: bytes, as: UTF8.self)) ?? Double(YURIS值.解析整数(bytes))
        }
    }

    var 转文字: [UInt8] {
        switch self {
        case .文字(let bytes): return bytes
        case .整数(let value): return Array(String(value).utf8)
        case .小数(let value):
            if value == value.rounded(), abs(value) < 1e15 { return Array(String(Int64(value)).utf8) }
            return Array(String(value).utf8)
        }
    }

    var 为真: Bool {
        switch self {
        case .整数(let value): return value != 0
        case .小数(let value): return value != 0
        case .文字(let bytes): return !bytes.isEmpty
        }
    }

    var 显示文字: String { YURIS文本.解码(转文字) }
    var 转Int: Int { Int(转整数) }

    static func 解析整数(_ bytes: [UInt8]) -> Int64 {
        var value: Int64 = 0
        var i = 0
        var negative = false
        if i < bytes.count, bytes[i] == 0x2D { negative = true; i += 1 }
        if i + 1 < bytes.count, bytes[i] == 0x30, bytes[i + 1] == 0x78 || bytes[i + 1] == 0x58 {
            i += 2
            while i < bytes.count {
                let c = bytes[i]
                let digit: Int64
                switch c {
                case 0x30...0x39: digit = Int64(c) - 0x30
                case 0x41...0x46: digit = Int64(c) - 0x41 + 10
                case 0x61...0x66: digit = Int64(c) - 0x61 + 10
                default: return negative ? 0 &- value : value
                }
                value = value &* 16 &+ digit
                i += 1
            }
        } else {
            while i < bytes.count, bytes[i] >= 0x30, bytes[i] <= 0x39 {
                value = value &* 10 &+ Int64(bytes[i] - 0x30)
                i += 1
            }
        }
        return negative ? 0 &- value : value
    }
}

nonisolated enum YURIS运算: UInt8, Sendable {
    case 转整数, 转文字, 取负
    case 乘, 除, 余, 加, 减
    case 小于, 小于等于, 大于, 大于等于, 等于, 不等于
    case 按位与, 按位或, 按位异或, 逻辑与, 逻辑或
}

nonisolated enum YURIS操作: Sendable {
    case 常量(YURIS值)
    case 变量(Int)
    case 整个数组(Int)
    case 下标开始(Int)
    case 下标结束
    case 运算(YURIS运算)
}

/// 编译后的表达式。绝大多数参数只是常量或单个变量，单独走快速路径。
nonisolated enum YURIS表达式: Sendable {
    case 空
    case 常量(YURIS值)
    case 变量(Int)
    case 下标常量(Int, Int)
    case 整个数组(Int)
    case 通用([YURIS操作])

    /// 文件里的系统变量编号 → 虚拟机的编号。读 ysv 时确定，nil 表示不用换算
    nonisolated(unsafe) static var 系统变量映射: [Int]?

    @inline(__always)
    private static func 变量号(_ bytes: [UInt8], _ p: Int) -> Int {
        let number = Int(bytes[p + 1]) | Int(bytes[p + 2]) << 8
        if let map = 系统变量映射, number < 1000, number < map.count { return map[number] }
        return number
    }

    static func 编译(_ bytes: [UInt8], _ start: Int, _ size: Int) -> YURIS表达式 {
        guard size > 0, start >= 0, start + size <= bytes.count else { return .空 }
        var ops: [YURIS操作] = []
        ops.reserveCapacity(4)
        var p = start
        let end = start + size
        while p + 3 <= end {
            let op = bytes[p]
            let length = Int(bytes[p + 1]) | Int(bytes[p + 2]) << 8
            p += 3
            guard p + length <= end else { break }
            switch op {
            case 0x42: ops.append(.常量(.整数(Int64(Int8(bitPattern: bytes[p])))))
            case 0x57: ops.append(.常量(.整数(Int64(Int16(bitPattern: UInt16(bytes[p]) | UInt16(bytes[p + 1]) << 8)))))
            case 0x49:
                let raw = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
                ops.append(.常量(.整数(Int64(Int32(bitPattern: raw)))))
            case 0x4C, 0x46:
                var raw: UInt64 = 0
                for i in 0..<8 { raw |= UInt64(bytes[p + i]) << UInt64(8 * i) }
                ops.append(.常量(op == 0x4C ? .整数(Int64(bitPattern: raw)) : .小数(Double(bitPattern: raw))))
            case 0x4D:
                // 字符串字面量带引号
                let text = length >= 2 ? Array(bytes[(p + 1)..<(p + length - 1)]) : []
                ops.append(.常量(.文字(text)))
            case 0x48: ops.append(.变量(变量号(bytes, p)))
            case 0x76: ops.append(.整个数组(变量号(bytes, p)))
            case 0x56: ops.append(.下标开始(变量号(bytes, p)))
            case 0x29: ops.append(.下标结束)
            case 0x2C: break
            case 0x69: ops.append(.运算(.转整数))
            case 0x73: ops.append(.运算(.转文字))
            case 0x52: ops.append(.运算(.取负))
            case 0x2A: ops.append(.运算(.乘))
            case 0x2F: ops.append(.运算(.除))
            case 0x25: ops.append(.运算(.余))
            case 0x2B: ops.append(.运算(.加))
            case 0x2D: ops.append(.运算(.减))
            case 0x3C: ops.append(.运算(.小于))
            case 0x53: ops.append(.运算(.小于等于))
            case 0x3E: ops.append(.运算(.大于))
            case 0x5A: ops.append(.运算(.大于等于))
            case 0x3D: ops.append(.运算(.等于))
            case 0x21: ops.append(.运算(.不等于))
            case 0x41: ops.append(.运算(.按位与))
            case 0x4F: ops.append(.运算(.按位或))
            case 0x5E: ops.append(.运算(.按位异或))
            case 0x26: ops.append(.运算(.逻辑与))
            case 0x7C: ops.append(.运算(.逻辑或))
            default: break
            }
            p += length
        }
        // 把常见形式折叠成快速路径
        if ops.count == 1 {
            switch ops[0] {
            case .常量(let value): return .常量(value)
            case .变量(let number): return .变量(number)
            case .整个数组(let number): return .整个数组(number)
            default: break
            }
        }
        if ops.count == 3, case .下标开始(let number) = ops[0], case .常量(.整数(let index)) = ops[1], case .下标结束 = ops[2] {
            return .下标常量(number, Int(index))
        }
        // 负数字面量
        if ops.count == 2, case .常量(.整数(let value)) = ops[0], case .运算(.取负) = ops[1] {
            return .常量(.整数(0 &- value))
        }
        if ops.count == 2, case .常量(.小数(let value)) = ops[0], case .运算(.取负) = ops[1] {
            return .常量(.小数(-value))
        }
        return .通用(ops)
    }
}

nonisolated struct YURIS参数: Sendable {
    let 编号: Int
    let 类型: Int
    let 赋值: Int
    /// IF、ELSE、LOOP 的控制参数把目标指令序号存在这里
    let 原始大小: Int
    let 表达式: YURIS表达式
    /// GOSUB、RETURN、TASK 的参数槽（PINT3 就是 3）；其他命令是 0
    let 槽: Int
    let 关键字: String
    /// WORD 的文字
    var 文字: [UInt8] = []
}

nonisolated enum YURIS命令种类: UInt8, Sendable {
    case 无, 判断, 否则, 判断结束, 分支结束, 判断跳出, 判断重来
    case 循环, 循环结束, 循环跳出, 循环重来
    case 跳转, 调用, 返回, 结束
    case 赋值, 整数变量, 小数变量, 文字变量, 任意变量, 静态声明
    case 文字, 表达式文字, 行结束
    case 等待
    case 引擎
}

nonisolated struct YURIS指令: Sendable {
    let 命令: Int
    let 种类: YURIS命令种类
    let 参数: [YURIS参数]
    /// IF/ELSE 条件不成立时跳到的指令；LOOP 的结束；IFBLEND 和 ELSE 所属的 IFEND
    var 目标: Int = -1
    /// IF 的 IFEND
    var 结束: Int = -1
    /// 源文件行号（调试）
    var 行: Int = 0
    /// GOSUB、GO 的标签是常量时，加载时就解析好
    var 静态标签: YURIS标签?
}

nonisolated final class YURIS脚本文件: @unchecked Sendable {
    let 序号: Int
    let 指令: [YURIS指令]
    init(序号: Int, 指令: [YURIS指令]) { self.序号 = 序号; self.指令 = 指令 }
}

nonisolated struct YURIS命令定义: Sendable {
    let 名称: String
    let 参数名: [String]
}

nonisolated struct YURIS标签: Sendable {
    let 位置: Int
    let 脚本: Int
    let if层数: Int
    let loop层数: Int
}

nonisolated struct YURIS变量定义: Sendable {
    /// 1 全局，2 静态（属于某脚本）
    let 作用域: Int
    let 脚本: Int
    let 编号: Int
    let 类型: Int
    let 维度: [Int]
    let 整数初值: Int64
    let 小数初值: Double
    let 文字初值: [UInt8]
}

/// ysbin 下的 ysc（命令表）、ysl（标签）、ysv（变量）、yscfg（配置）和 ystNNNNN（脚本）
nonisolated final class YURIS程序: @unchecked Sendable {
    private(set) var 命令表: [YURIS命令定义] = []
    private(set) var 命令号: [String: Int] = [:]
    private(set) var 标签: [[UInt8]: YURIS标签] = [:]
    private(set) var 变量定义: [YURIS变量定义] = []
    private(set) var 缓存: [Int: YURIS脚本文件] = [:]
    private(set) var 窗口宽 = 800
    private(set) var 窗口高 = 600
    private(set) var 窗口标题 = ""
    private var 种类表: [YURIS命令种类] = []
    let 资源: YURIS资源库
    private var 密钥: [UInt8]?
    private var 旧版偏移: [Int: [Int: Int]] = [:]

    enum 错误: Error { case 缺少文件(String) }

    init(资源: YURIS资源库) throws {
        self.资源 = 资源
        guard let ysc = 资源.读取("ysbin/ysc.ybn") else { throw 错误.缺少文件("ysc.ybn") }
        读命令表(ysc)
        guard let ysl = 资源.读取("ysbin/ysl.ybn") else { throw 错误.缺少文件("ysl.ybn") }
        读标签(ysl)
        guard let ysv = 资源.读取("ysbin/ysv.ybn") else { throw 错误.缺少文件("ysv.ybn") }
        读变量(ysv)
        if let cfg = 资源.读取("ysbin/yscfg.ybn") { 读配置(cfg) }
        判断文字编码()
        换算旧版标签()
    }

    /// 0.300 以前标签记的是命令区的字节偏移，要先读一遍脚本才能换算成指令序号
    private func 换算旧版标签() {
        let scripts = Set(标签.values.map(\.脚本))
        guard let first = scripts.min(), let probe = 资源.读取(String(format: "ysbin/yst%05d.ybn", first)),
              probe.count >= 8, Int(probe.读UInt32(4)) < 300 else { return }
        for index in scripts { _ = 脚本(index) }
        for (name, label) in 标签 {
            if let map = 旧版偏移[label.脚本], let position = map[label.位置] {
                标签[name] = YURIS标签(位置: position, 脚本: label.脚本, if层数: label.if层数, loop层数: label.loop层数)
            }
        }
        // 调用指令缓存了标签，重新读一遍
        缓存 = [:]
    }

    /// 看 WORD 里的文字判断编码：商业版有 UTF-8，汉化版有 GBK
    private func 判断文字编码() {
        YURIS文本.文字编码 = .日文
        var sample: [UInt8] = []
        for index in Set(标签.values.map(\.脚本)).sorted() {
            guard sample.count < 200_000, let script = 脚本(index) else { continue }
            for ins in script.指令 where ins.种类 == .文字 {
                if let text = ins.参数.first?.文字 { sample += text }
            }
        }
        let detected = YURIS文本.判断编码(sample)
        guard detected != .日文 else { return }
        YURIS文本.文字编码 = detected
        资源.添加别名()
        // 指令里已经按日文切分过的内容要重新读
        缓存 = [:]
    }

    /// 命令和关键字都是 ASCII。用原生字符串（解码出来的是桥接的 NSString，比较很慢）
    private func c字符串(_ bytes: [UInt8], _ p: inout Int) -> String {
        var end = p
        while end < bytes.count, bytes[end] != 0 { end += 1 }
        defer { p = end + 1 }
        return String(decoding: bytes[p..<end], as: UTF8.self)
    }

    private func 读命令表(_ data: Data) {
        let bytes = [UInt8](data)
        let count = Int(data.读UInt32(8))
        var p = 16
        for index in 0..<count {
            let name = c字符串(bytes, &p)
            let argc = Int(bytes[p]); p += 1
            var args: [String] = []
            for _ in 0..<argc {
                args.append(c字符串(bytes, &p))
                p += 2
            }
            命令表.append(.init(名称: name, 参数名: args))
            命令号[name] = index
            种类表.append(Self.种类(name))
        }
    }

    private static func 种类(_ name: String) -> YURIS命令种类 {
        switch name {
        case "IF": return .判断
        case "ELSE": return .否则
        case "IFEND": return .判断结束
        case "IFBLEND": return .分支结束
        case "IFBREAK": return .判断跳出
        case "IFCONTINUE": return .判断重来
        case "LOOP": return .循环
        case "LOOPEND": return .循环结束
        case "LOOPBREAK": return .循环跳出
        case "LOOPCONTINUE": return .循环重来
        case "GO": return .跳转
        case "GOSUB": return .调用
        case "RETURN": return .返回
        case "END": return .结束
        case "LET": return .赋值
        case "INT": return .整数变量
        case "FLT": return .小数变量
        case "STR": return .文字变量
        case "VAR": return .任意变量
        case "S_INT", "S_FLT", "S_STR", "S_VAR", "G_INT", "G_FLT", "G_STR", "G_VAR", "F_INT", "F_FLT", "F_STR", "F_VAR",
             "G_INT2", "G_FLT2", "G_STR2", "G_INT3", "G_FLT3", "G_STR3", "G_INT4", "G_FLT4", "G_STR4": return .静态声明
        case "WORD": return .文字
        case "_": return .表达式文字
        case "RETURNCODE": return .行结束
        case "WAIT": return .等待
        case "MACRO", "LABEL", "_IFDEF", "_IFNDEF", "_IFEND", "PREP", "SYSTEMMODE", "COMPILEMODE", "RELEASEMODE", "PROJECTFOLDER": return .无
        default: return .引擎
        }
    }

    private func 读标签(_ data: Data) {
        let bytes = [UInt8](data)
        let count = Int(data.读UInt32(8))
        var p = 12 + 1024
        for _ in 0..<count {
            let length = Int(bytes[p]); p += 1
            let name = Array(bytes[p..<(p + length)]); p += length
            let position = Int(data.读UInt32(p + 4))
            let script = Int(data.读UInt16(p + 8))
            标签[name] = YURIS标签(位置: position, 脚本: script, if层数: Int(bytes[p + 10]), loop层数: Int(bytes[p + 11]))
            p += 12
        }
    }

    /// 0.481 起每项多一个字节。商业版的版本号不一定可信，所以两种都试，能正好读完的才对。
    private func 读变量(_ data: Data) {
        let version = Int(data.读UInt32(4))
        let preferred = version >= 481
        guard let raw = 解析变量(data, 带扩展: preferred) ?? 解析变量(data, 带扩展: !preferred) else { return }
        let count = (raw.filter { $0.编号 < 1000 }.map(\.编号).max() ?? -1) + 1
        let map = YURIS系统变量表.映射(系统变量数: count)
        YURIS表达式.系统变量映射 = map
        变量定义 = raw.map { item in
            guard let map, item.编号 < 1000, item.编号 < map.count else { return item }
            return YURIS变量定义(作用域: item.作用域, 脚本: item.脚本, 编号: map[item.编号], 类型: item.类型, 维度: item.维度,
                             整数初值: item.整数初值, 小数初值: item.小数初值, 文字初值: item.文字初值)
        }
    }

    private func 解析变量(_ data: Data, 带扩展 extended: Bool) -> [YURIS变量定义]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 10 else { return nil }
        let count = Int(data.读UInt16(8))
        var p = 10
        var result: [YURIS变量定义] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            guard p + (extended ? 7 : 6) <= bytes.count else { return nil }
            let scope = Int(bytes[p]); p += 1
            if extended { p += 1 }
            let script = Int(data.读UInt16(p)); p += 2
            let number = Int(data.读UInt16(p)); p += 2
            let type = Int(bytes[p]); p += 1
            let dimensions = Int(bytes[p]); p += 1
            guard type <= 3, dimensions <= 16, p + dimensions * 4 <= bytes.count else { return nil }
            var dims: [Int] = []
            for _ in 0..<dimensions { dims.append(Int(data.读UInt32(p))); p += 4 }
            var integer: Int64 = 0, real = 0.0, text: [UInt8] = []
            switch type {
            case 1:
                guard p + 8 <= bytes.count else { return nil }
                integer = Int64(bitPattern: data.读UInt64(p)); p += 8
            case 2:
                guard p + 8 <= bytes.count else { return nil }
                real = Double(bitPattern: data.读UInt64(p)); p += 8
            case 3:
                guard p + 2 <= bytes.count else { return nil }
                let length = Int(data.读UInt16(p)); p += 2
                guard p + length <= bytes.count else { return nil }
                text = Array(bytes[p..<(p + length)]); p += length
            default: break
            }
            result.append(.init(作用域: scope, 脚本: script, 编号: number, 类型: type, 维度: dims,
                                整数初值: integer, 小数初值: real, 文字初值: text))
        }
        return p == bytes.count ? result : nil
    }

    /// YSCF：头 4+4，之后第 16 字节起是窗口尺寸，再往后有长度前缀的标题
    private func 读配置(_ data: Data) {
        guard data.count >= 24 else { return }
        let bytes = [UInt8](data)
        let width = Int(data.读UInt32(16)), height = Int(data.读UInt32(20))
        if width > 0, width <= 8192, height > 0, height <= 8192 { 窗口宽 = width; 窗口高 = height }
        // 标题前是 2 字节长度，后面紧跟可打印内容，版本之间位置不同，这里只取第一个说得通的
        var p = 24
        while p + 2 < bytes.count {
            let length = Int(bytes[p]) | Int(bytes[p + 1]) << 8
            if length > 0, length < 256, p + 2 + length <= bytes.count, bytes[p + 2] >= 0x20 {
                窗口标题 = YURIS文本.解码(Array(bytes[(p + 2)..<(p + 2 + length)]))
                break
            }
            p += 1
        }
    }

    func 脚本(_ index: Int) -> YURIS脚本文件? {
        if let cached = 缓存[index] { return cached }
        let name = String(format: "ysbin/yst%05d.ybn", index)
        guard let data = 资源.读取(name), let file = 解析脚本(index, data) else { return nil }
        缓存[index] = file
        return file
    }

    /// 从结构求 XOR 密钥（官方默认是 0xD36FAC96，商业版会改）：
    /// 每条指令第 3、4 字节几乎都是 0；所有参数个数之和等于参数表项数；参数表第 1 字节多为 0
    private func 求密钥(_ bytes: [UInt8], codeSize: Int, argumentSize: Int) -> [UInt8] {
        func 众数(_ start: Int, _ end: Int, step: Int) -> UInt8 {
            var counts = [Int](repeating: 0, count: 256)
            var i = start
            while i < end { counts[Int(bytes[i])] += 1; i += step }
            return UInt8(counts.indices.max { counts[$0] < counts[$1] } ?? 0)
        }
        let code = 32, args = 32 + codeSize
        let k2 = 众数(code + 2, args, step: 4)
        let k3 = 众数(code + 3, args, step: 4)
        var k1: UInt8 = 0
        for candidate in 0...255 {
            var sum = 0, i = code + 1
            while i < args { sum += Int(bytes[i] ^ UInt8(candidate)); i += 4 }
            if sum == argumentSize / 12 { k1 = UInt8(candidate); break }
        }
        let k0 = 众数(args, args + argumentSize, step: 12)
        return [k0, k1, k2, k3]
    }

    private func 解析脚本(_ index: Int, _ data: Data) -> YURIS脚本文件? {
        guard data.count >= 32, data.prefix(4) == Data([0x59, 0x53, 0x54, 0x42]) else { return nil }
        if Int(data.读UInt32(4)) < 300 { return 解析旧版脚本(index, data) }
        var bytes = [UInt8](data)
        let count = Int(data.读UInt32(8))
        let codeSize = Int(data.读UInt32(12)), argumentSize = Int(data.读UInt32(16))
        let resourceSize = Int(data.读UInt32(20)), lineSize = Int(data.读UInt32(24))
        // 指令足够多才能可靠地求出密钥，脚本 0 通常就够
        if 密钥 == nil {
            guard count > 8 else {
                if let probe = 资源.读取("ysbin/yst00000.ybn"), probe.count >= 32, index != 0 {
                    _ = 解析脚本(0, probe)
                }
                guard 密钥 != nil else { return nil }
                return 解析脚本(index, data)
            }
            密钥 = 求密钥(bytes, codeSize: codeSize, argumentSize: argumentSize)
        }
        guard let key = 密钥 else { return nil }
        var position = 32
        for size in [codeSize, argumentSize, resourceSize, lineSize] {
            guard position + size <= bytes.count else { return nil }
            for i in 0..<size { bytes[position + i] ^= key[i & 3] }
            position += size
        }
        let argumentBase = 32 + codeSize, resourceBase = argumentBase + argumentSize
        let lineBase = resourceBase + resourceSize
        var instructions: [YURIS指令] = []
        instructions.reserveCapacity(count)
        var a = argumentBase
        @inline(__always) func u32(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        for i in 0..<count {
            let at = 32 + i * 4
            let command = Int(bytes[at]), argc = Int(bytes[at + 1])
            var args: [YURIS参数] = []
            args.reserveCapacity(argc)
            for j in 0..<argc {
                args.append(组装参数(bytes, 命令: command, 序号: j, 位置: a, 资源基址: resourceBase))
                a += 12
            }
            var line = 0
            if lineSize >= (i + 1) * 4 { line = u32(lineBase + i * 4) }
            instructions.append(组装指令(命令: command, 参数: args, 行: line))
        }
        配对(&instructions)
        return YURIS脚本文件(序号: index, 指令: instructions)
    }

    private func 组装参数(_ bytes: [UInt8], 命令 command: Int, 序号 j: Int, 位置 a: Int, 资源基址 resourceBase: Int) -> YURIS参数 {
        let kind = command < 种类表.count ? 种类表[command] : .无
        let keywords = command < 命令表.count ? 命令表[command].参数名 : []
        let number = Int(bytes[a]) | Int(bytes[a + 1]) << 8
        let type = Int(bytes[a + 2]), assign = Int(bytes[a + 3])
        let size = Int(bytes[a + 4]) | Int(bytes[a + 5]) << 8 | Int(bytes[a + 6]) << 16 | Int(bytes[a + 7]) << 24
        let offset = Int(bytes[a + 8]) | Int(bytes[a + 9]) << 8 | Int(bytes[a + 10]) << 16 | Int(bytes[a + 11]) << 24
        let start = resourceBase + offset
        switch kind {
        case .文字:
            var argument = YURIS参数(编号: number, 类型: type, 赋值: assign, 原始大小: size, 表达式: .空, 槽: 0, 关键字: "")
            if size > 0, start + size <= bytes.count { argument.文字 = Array(bytes[start..<(start + size)]) }
            return argument
        case .行结束:
            return YURIS参数(编号: number, 类型: type, 赋值: assign, 原始大小: size, 表达式: .空, 槽: 0, 关键字: "")
        case .判断, .否则, .循环:
            // 第一个参数是条件，其余是目标序号
            let expression: YURIS表达式 = j == 0 ? .编译(bytes, start, size) : .空
            return YURIS参数(编号: number, 类型: type, 赋值: assign, 原始大小: size, 表达式: expression, 槽: 0, 关键字: "")
        default:
            let keyword = number < keywords.count ? keywords[number] : ""
            return YURIS参数(编号: number, 类型: type, 赋值: assign, 原始大小: size,
                           表达式: .编译(bytes, start, size), 槽: Self.参数槽(keyword), 关键字: keyword)
        }
    }

    private func 组装指令(命令 command: Int, 参数 args: [YURIS参数], 行 line: Int) -> YURIS指令 {
        let kind = command < 种类表.count ? 种类表[command] : .无
        var instruction = YURIS指令(命令: command, 种类: kind, 参数: args, 行: line)
        if kind == .调用 {
            if let first = args.first, case .常量(.文字(let name)) = first.表达式 { instruction.静态标签 = 标签[name] }
            instruction.结束 = args.reduce(0) { max($0, $1.槽) }
        }
        return instruction
    }

    /// 0.300 以前的布局：头后面是命令区（每条命令 6 字节，参数紧跟在命令后面）和数据区，没有单独的行号区。
    /// 密钥是固定的两个（0.290 以前和以后），商业版改过的话靠结构判断。
    private func 解析旧版脚本(_ index: Int, _ data: Data) -> YURIS脚本文件? {
        let version = Int(data.读UInt32(4))
        let codeSize = Int(data.读UInt32(8)), resourceSize = Int(data.读UInt32(12))
        guard 32 + codeSize + resourceSize <= data.count else { return nil }
        let defaults: [[UInt8]] = version >= 290 ? [[0xD3, 0x6F, 0xAC, 0x96], [0x07, 0xB4, 0x02, 0x4A]] : [[0x07, 0xB4, 0x02, 0x4A], [0xD3, 0x6F, 0xAC, 0x96]]
        for key in (密钥.map { [$0] } ?? []) + defaults {
            var bytes = [UInt8](data)
            for i in 0..<codeSize { bytes[32 + i] ^= key[i & 3] }
            for i in 0..<resourceSize { bytes[32 + codeSize + i] ^= key[i & 3] }
            guard let result = 读旧版指令(index, bytes, 版本: version, 命令区大小: codeSize) else { continue }
            密钥 = key
            return result
        }
        return nil
    }

    private func 读旧版指令(_ index: Int, _ bytes: [UInt8], 版本 version: Int, 命令区大小 codeSize: Int) -> YURIS脚本文件? {
        let resourceBase = 32 + codeSize
        var instructions: [YURIS指令] = []
        var offsets: [Int: Int] = [:]
        var p = 32
        while p < resourceBase {
            guard p + 6 <= resourceBase else { return nil }
            let command = Int(bytes[p]), argc = Int(bytes[p + 1])
            guard command < 种类表.count else { return nil }
            let line = Int(bytes[p + 2]) | Int(bytes[p + 3]) << 8 | Int(bytes[p + 4]) << 16 | Int(bytes[p + 5]) << 24
            offsets[p - 32] = instructions.count
            p += 6
            var args: [YURIS参数] = []
            if 种类表[command] == .行结束 {
                // 短参数：编号、类型、赋值，0.290 才有大小
                guard argc == 1, p + 4 <= resourceBase else { return nil }
                let number = Int(bytes[p]) | Int(bytes[p + 1]) << 8
                let type = Int(bytes[p + 2]), assign = Int(bytes[p + 3])
                p += 4
                var size = 0
                if version == 290 {
                    guard p + 4 <= resourceBase else { return nil }
                    size = Int(bytes[p]) | Int(bytes[p + 1]) << 8 | Int(bytes[p + 2]) << 16 | Int(bytes[p + 3]) << 24
                    p += 4
                }
                args.append(YURIS参数(编号: number, 类型: type, 赋值: assign, 原始大小: size, 表达式: .空, 槽: 0, 关键字: ""))
            } else {
                guard p + argc * 12 <= resourceBase else { return nil }
                for j in 0..<argc {
                    args.append(组装参数(bytes, 命令: command, 序号: j, 位置: p, 资源基址: resourceBase))
                    p += 12
                }
            }
            instructions.append(组装指令(命令: command, 参数: args, 行: line))
        }
        旧版偏移[index] = offsets
        配对(&instructions)
        return YURIS脚本文件(序号: index, 指令: instructions)
    }

    /// PINT3 → 3，PINT → 1；不是参数槽的关键字是 0
    private static func 参数槽(_ keyword: String) -> Int {
        let bytes = Array(keyword.utf8)
        guard bytes.count >= 4 else { return 0 }
        let head = String(decoding: bytes[0..<4], as: UTF8.self)
        guard ["PINT", "PFLT", "PSTR", "RINT", "RFLT", "RSTR", "TINT", "TFLT", "TSTR"].contains(head) else { return 0 }
        if bytes.count == 4 { return 1 }
        return min(16, Int(String(decoding: bytes[4...], as: UTF8.self)) ?? 0)
    }

    /// IF、ELSE、LOOP 的跳转目标已经编译进参数。这里补上 ELSE 和 IFBLEND 到 IFEND 的目标，以及 IFBREAK 的目标。
    private func 配对(_ code: inout [YURIS指令]) {
        var ifs: [Int] = []
        var pendingBranches: [[Int]] = []
        var breaks: [(index: Int, level: Int, depth: Int)] = []
        for i in code.indices {
            switch code[i].种类 {
            case .判断:
                let elseTarget = code[i].参数.count > 1 ? code[i].参数[1].原始大小 : 0
                let endTarget = code[i].参数.count > 2 ? code[i].参数[2].原始大小 : 0
                code[i].目标 = elseTarget
                code[i].结束 = endTarget
                ifs.append(i)
                pendingBranches.append([])
            case .否则:
                code[i].目标 = code[i].参数.count > 1 ? code[i].参数[1].原始大小 : 0
                if !pendingBranches.isEmpty { pendingBranches[pendingBranches.count - 1].append(i) }
            case .分支结束:
                if !pendingBranches.isEmpty { pendingBranches[pendingBranches.count - 1].append(i) }
            case .判断跳出, .判断重来:
                var level = 1
                if let first = code[i].参数.first, case .常量(let value) = first.表达式 { level = max(1, value.转Int) }
                breaks.append((i, level, ifs.count))
            case .判断结束:
                if let start = ifs.popLast() {
                    code[start].结束 = i
                    for branch in pendingBranches.removeLast() { code[branch].结束 = i }
                    // 解析嵌套里的 IFBREAK：LV=n 跳到第 n 层的 IFEND
                    var remaining: [(index: Int, level: Int, depth: Int)] = []
                    for item in breaks {
                        // item.depth 是它所在的层数；当前结束的是第 ifs.count+1 层
                        if item.depth - item.level + 1 == ifs.count + 1 {
                            code[item.index].结束 = i
                            code[item.index].目标 = start
                        } else {
                            remaining.append(item)
                        }
                    }
                    breaks = remaining
                }
            case .循环:
                code[i].目标 = code[i].参数.count > 1 ? code[i].参数[1].原始大小 : -1
            default:
                break
            }
        }
    }
}
