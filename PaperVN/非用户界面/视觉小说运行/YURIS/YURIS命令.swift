import Accelerate
import CoreGraphics
import Foundation
import ImageIO

nonisolated enum YURIS命令表 {
    typealias 处理函数 = (YURIS虚拟机, YURIS指令) -> Void

    static func 处理(名称 name: String) -> 处理函数? {
        switch name {
        case "CG": return { $0.执行CG($1) }
        case "CGACT": return { $0.执行CGACT($1) }
        case "CGEND": return { $0.执行CGEND($1) }
        case "CGINFO": return { $0.执行CGINFO($1) }
        case "FONT": return { $0.执行FONT($1) }
        case "FONTINFO": return { $0.执行FONTINFO($1) }
        case "TEXT": return { $0.执行TEXT($1) }
        case "TEXTINFO": return { $0.执行TEXTINFO($1) }
        case "TASK": return { $0.执行TASK($1) }
        case "TASKEND": return { $0.执行TASKEND($1) }
        case "TASKINFO": return { $0.执行TASKINFO($1) }
        case "VARACT": return { $0.执行VARACT($1) }
        case "VARINFO": return { $0.执行VARINFO($1) }
        case "MATH": return { $0.执行MATH($1) }
        case "SAVE": return { $0.执行SAVE($1) }
        case "SAVEEND": return { vm, _ in vm.预约存档 = [:] }
        case "SAVEINFO": return { $0.执行空信息($1) }
        case "LOAD": return { $0.执行LOAD($1) }
        case "FILEACT": return { $0.执行FILEACT($1) }
        case "FILEINFO": return { $0.执行FILEINFO($1) }
        case "SOUND": return { $0.执行SOUND($1) }
        case "SOUNDEND": return { $0.执行SOUNDEND($1) }
        case "SOUNDINFO": return { $0.执行SOUNDINFO($1) }
        case "MOVIE": return { $0.执行MOVIE($1) }
        case "MOVIEINFO": return { $0.执行MOVIEINFO($1) }
        case "MIDI": return { $0.执行MIDI($1) }
        case "MIDIEND": return { $0.执行MIDIEND($1) }
        case "FLASH": return { $0.执行FLASH($1) }
        case "FLASHEND": return { $0.执行FLASHEND($1) }
        case "FLASHINFO": return { $0.执行FLASHINFO($1) }
        case "MOVIEEND": return { vm, _ in vm.结束影片() }
        case "YMVINFO", "MIDIINFO", "MENUINFO", "CLIPINFO", "REGINFO", "ERRORINFO", "CSVINFO":
            return { $0.执行空信息($1) }
        case "WINDOW": return { $0.执行WINDOW($1) }
        case "WINDOWINFO": return { $0.执行WINDOWINFO($1) }
        case "SYSTEM": return { $0.执行SYSTEM($1) }
        case "SYSTEMINFO": return { $0.执行SYSTEMINFO($1) }
        case "LABELINFO": return { $0.执行LABELINFO($1) }
        case "DIALOG": return { $0.执行DIALOG($1) }
        case "PRODUCT": return { $0.执行空信息($1) }
        // 这些命令在这个平台上没有对应的东西
        case "MENU", "MENUACT", "MENUEND", "MOUSE", "INPUT", "FPS", "TRAY",
             "WINDOWEND", "ERROR", "CLIPACT", "CDDA", "PLUG", "DEBUGLIST", "YMV", "YMVEND",
             "CSV":
            return { _, _ in }
        case "MATH3D": return { $0.执行MATH3D($1) }
        default:
            return nil
        }
    }
}

/// 引擎自动显示文字（OUTPUTMODE=1）的状态
nonisolated final class YURIS自动文字 {
    enum 项 {
        case 字符([UInt8])
        case 换行
        case 换页
        case 点按
    }
    var 队列: [项] = []
    var 图层ID: [UInt8] = []
    var 每字毫秒 = 0.0
    var 下一字时间 = 0.0
    var 光标x = 0
    var 光标y = 0
    var 等待点按 = false
    var 自动换行 = true
    var 自动换页 = true
    var 自动点按 = true
    /// 按键码。手册：默认是鼠标左键和回车，跳过是 Ctrl
    var 点按键: [Int] = [1, 98, 0, 0]
    var 跳过键: [Int] = [101, 0, 0, 0]
}

nonisolated struct YURISFlash状态 {
    var 文件 = ""
    var x = 0
    var y = 0
    var 宽: Int?
    var 高: Int?
    var 结束帧: Int?
}

/// Flash 画在界面层（命令行测试工具没有）
nonisolated protocol YURISFlash接口: AnyObject {
    func 打开(地址: URL, x: Int, y: Int, 宽: Int, 高: Int, 画面宽: Int, 画面高: Int, 结束帧: Int?)
    func 关闭()
    func 暂停(_ paused: Bool)
    var 状态: (播放中: Bool, 当前帧: Int, 总帧数: Int) { get }
}

/// MIDI 在界面层播放（命令行测试工具没有）
nonisolated protocol YURISMIDI接口: AnyObject {
    func 播放(_ data: Data)
    func 停止()
}

nonisolated final class YURIS影片状态 {
    var 文件 = ""
    var x = 0
    var y = 0
    var 宽: Int?
    var 高: Int?
    var 音量 = 256
    var 播放器: 视觉小说影片?
}

nonisolated enum YURIS存档项 {
    case 值(维度: [Int], 元素: [YURIS值])
    case 图片(Data)
}

nonisolated struct YURIS对话框请求: Sendable {
    let 标题: String
    let 内容: String
    /// 0 确定，1 是/否，2 确定/取消，3 是/否/取消
    let 类型: Int
}

/// 界面线程写入，虚拟机每帧读取
nonisolated final class YURIS输入状态: @unchecked Sendable {
    /// 按键状态变量的编号：@125 鼠标左键，@129 右键，@133 中键，@137 滚轮上，@141 滚轮下，@145 起是键盘
    static let 左键 = 125, 右键 = 129, 中键 = 133, 滚轮上 = 137, 滚轮下 = 141
    static let 回车 = 222, 空格 = 223, 控制键 = 225, 退出键 = 236

    private let lock = NSLock()
    private var 待处理: [(键: Int, 按下: Bool)] = []
    private var 鼠标X = 0, 鼠标Y = 0
    private var 按下的键 = Set<Int>()
    var 脚本要求退出 = false

    func 移动鼠标(x: Int, y: Int) {
        lock.lock(); defer { lock.unlock() }
        鼠标X = x
        鼠标Y = y
    }

    func 按键(_ key: Int, 按下: Bool) {
        lock.lock(); defer { lock.unlock() }
        待处理.append((key, 按下))
    }

    /// 按一下（下一帧按下，再下一帧放开）
    func 点按(_ key: Int) {
        按键(key, 按下: true)
        按键(key, 按下: false)
    }

    func 应用(到 vm: YURIS虚拟机) {
        lock.lock()
        // 一帧只处理一次按键变化，太快的点按也能被脚本看到
        var changed = Set<Int>()
        var remaining: [(键: Int, 按下: Bool)] = []
        for event in 待处理 {
            if changed.contains(event.键) {
                remaining.append(event)
            } else {
                changed.insert(event.键)
                if event.按下 { 按下的键.insert(event.键) } else { 按下的键.remove(event.键) }
            }
        }
        待处理 = remaining
        let pressed = 按下的键
        let x = 鼠标X, y = 鼠标Y
        lock.unlock()

        let globals = vm.全局
        globals[111]?.标量 = .整数(Int64(x))
        globals[116]?.标量 = .整数(Int64(y))
        for number in 125...252 {
            guard let variable = globals[number] else { continue }
            let value = variable.标量.转整数
            if pressed.contains(number) {
                variable.标量 = .整数(value > 0 ? value + 1 : 1)
                if value <= 0, let count = globals[number + 134] {
                    count.标量 = .整数(count.标量.转整数 + 1)
                }
            } else {
                variable.标量 = .整数(value < 0 ? value - 1 : -1)
            }
        }
        // 任意键
        if let any = globals[253] {
            let value = any.标量.转整数
            any.标量 = .整数(pressed.isEmpty ? (value < 0 ? value - 1 : -1) : (value > 0 ? value + 1 : 1))
        }
        // @_INP(按键码)，按键码 = 变量号 - 124
        if let table = globals[122] {
            for number in 125...252 {
                let code = number - 124
                if code < table.元素.count, let variable = globals[number] { table.元素[code] = variable.标量 }
            }
        }
    }
}

nonisolated extension YURIS虚拟机 {
    // MARK: - 参数帮助

    @inline(__always)
    private func 整数(_ argument: YURIS参数) -> Int { 求值(argument.表达式).转Int }
    @inline(__always)
    private func 长整数(_ argument: YURIS参数) -> Int64 { 求值(argument.表达式).转整数 }
    @inline(__always)
    private func 文字(_ argument: YURIS参数) -> [UInt8] { 求值(argument.表达式).转文字 }

    private func 改(_ current: Int, _ argument: YURIS参数) -> Int {
        let value = 整数(argument)
        switch argument.赋值 {
        case 1: return current + value
        case 2: return current - value
        case 3: return current * value
        case 4: return value == 0 ? 0 : current / value
        case 5: return value == 0 ? 0 : current % value
        default: return value
        }
    }

    private func 查参数(_ ins: YURIS指令, _ keyword: String) -> YURIS参数? {
        ins.参数.first { $0.关键字 == keyword }
    }

    // MARK: - 图层

    func 执行CG(_ ins: YURIS指令) {
        guard let idArg = 查参数(ins, "ID") else { return }
        let id = 文字(idArg)
        guard !id.isEmpty else { return }
        let fileArg = 查参数(ins, "FILE")
        let needsCreate = fileArg != nil || id.last == 0x2F
        guard let layer = needsCreate ? 画面.查找或新建(id) : 画面.查找(id) else { return }
        var sizeX: Int?, sizeY: Int?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "E": layer.启用 = 整数(argument) != 0
            case "A": layer.透明度 = 改(layer.透明度, argument)
            case "X": layer.x = 改(layer.x, argument)
            case "Y": layer.y = 改(layer.y, argument)
            case "Z": layer.z = 长整数(argument)
            case "SX": sizeX = 整数(argument)
            case "SY": sizeY = 整数(argument)
            case "MODE": layer.模式 = 整数(argument)
            case "T": layer.过渡进度 = 改(layer.过渡进度, argument)
            case "TID": layer.过渡图层 = 文字(argument)
            case "TA": layer.过渡精度 = 整数(argument)
            case "MID": layer.蒙版图层 = 文字(argument)
            case "LINT": layer.整数属性[0] = 长整数(argument)
            case "LINT2": layer.整数属性[1] = 长整数(argument)
            default: break
            }
        }
        if let fileArg {
            let file = 文字(fileArg)
            if file.isEmpty {
                // FILE="" 生成黑色位图，SX、SY 指定大小
                let image = YURIS图像(宽: sizeX ?? 1, 高: sizeY ?? 1)
                image.填充(a: 255, r: 0, g: 0, b: 0)
                layer.图像 = image
            } else if 打开图层影片(YURIS文本.解码(file), layer) {
                // 图像由 更新图层影片 填
            } else if let image = 画面.读图片(YURIS文本.解码(file)) {
                layer.图像 = image
            } else {
                // 找不到文件时引擎给 1×1 的灰色占位，脚本靠这个判断素材是否存在
                日志("找不到图片：\(YURIS文本.解码(file))")
                let image = YURIS图像(宽: 1, 高: 1)
                image.填充(a: 255, r: 0x80, g: 0x80, b: 0x80)
                layer.图像 = image
            }
        } else if layer.是集合 {
            if let sizeX { layer.集合宽 = sizeX }
            if let sizeY { layer.集合高 = sizeY }
        }
        画面.脏 = true
    }

    func 执行CGEND(_ ins: YURIS指令) {
        if let argument = 查参数(ins, "ID") {
            if let layer = 画面.查找(文字(argument)) {
                图层影片.removeAll { item in
                    guard item.图层 === layer else { return false }
                    item.播放器.停止()
                    return true
                }
            }
            画面.删除(文字(argument))
        }
    }

    /// 源图层的位图。集合要先合成。
    private func 源图像(_ layer: YURIS图层) -> YURIS图像? {
        layer.是集合 ? 画面.渲染集合(layer) : layer.图像
    }

    /// 要改写的位图：图片缓存里的位图是共享的，不能原地改。为简单起见每次都复制。
    private func 可写图像(_ layer: YURIS图层) -> YURIS图像? {
        guard let image = layer.图像 else { return nil }
        if !isKnownUniquelyReferenced(&layer.图像) { return image.复制() }
        // 文件缓存也持有时引用计数大于 1，上面已经处理
        return image
    }

    func 执行CGACT(_ ins: YURIS指令) {
        var id: [UInt8] = [], id2: [UInt8]?, id3: [UInt8]?
        var set: Int64 = 0, set2: Int64 = 0
        var setString: [UInt8] = []
        var x: Int?, y: Int?, x2: Int?, y2: Int?, sx: Int?, sy: Int?
        var fx: Double?, fy: Double?, fx2: Double?, fy2: Double?, fsx: Double?, fsy: Double?
        var operation = ""
        var bno = 0
        for argument in ins.参数 {
            switch argument.关键字 {
            case "ID": id = 文字(argument)
            case "ID2": id2 = 文字(argument)
            case "ID3": id3 = 文字(argument)
            case "SET": set = 长整数(argument)
            case "SET2": set2 = 长整数(argument)
            case "SETSTR": setString = 文字(argument)
            case "X": x = 整数(argument)
            case "Y": y = 整数(argument)
            case "X2": x2 = 整数(argument)
            case "Y2": y2 = 整数(argument)
            case "SX": sx = 整数(argument)
            case "SY": sy = 整数(argument)
            case "FX": fx = 求值(argument.表达式).转小数 / 100
            case "FY": fy = 求值(argument.表达式).转小数 / 100
            case "FX2": fx2 = 求值(argument.表达式).转小数 / 100
            case "FY2": fy2 = 求值(argument.表达式).转小数 / 100
            case "FSX": fsx = 求值(argument.表达式).转小数 / 100
            case "FSY": fsy = 求值(argument.表达式).转小数 / 100
            case "BNO": bno = 整数(argument)
            default:
                if !argument.关键字.isEmpty, 求值(argument.表达式).为真 { operation = argument.关键字 }
            }
        }
        _ = set2
        guard let source = 画面.查找(id) else { return }
        画面.脏 = true
        switch operation {
        case "COPY", "COPY2":
            guard let image = 源图像(source) else { return }
            let cropped: YURIS图像
            if x != nil || y != nil || x2 != nil || y2 != nil {
                // 按钮图是横向排的多帧，只给 X、X2 也常见，没给的边取整张图
                let left = x ?? 0, top = y ?? 0
                cropped = image.裁剪(x: left, y: top, 宽: (x2 ?? image.宽 - 1) - left + 1, 高: (y2 ?? image.高 - 1) - top + 1)
            } else {
                // 共享不可变的位图，改写时才复制
                cropped = image
            }
            let target = id2.map { 画面.查找或新建($0) } ?? source
            target.图像 = cropped
            if operation == "COPY", target !== source {
                target.启用 = source.启用
                target.透明度 = source.透明度
                target.x = source.x
                target.y = source.y
                target.z = source.z
                target.模式 = source.模式
                target.过渡进度 = source.过渡进度
                target.过渡图层 = source.过渡图层
                target.过渡精度 = source.过渡精度
            }
        case "SWAP", "SWAP2":
            guard let id2, let target = 画面.查找(id2) else { return }
            画面.交换(source, target, 含属性: operation == "SWAP")
        case "SIZE", "SIZE2", "SIZE3", "SIZE4", "SIZE5":
            guard let image = 源图像(source) else { return }
            let target = id2.map { 画面.查找或新建($0) } ?? source
            if let fx, let fy, let fx2, let fy2, let fsx, let fsy {
                target.图像 = image.小数缩放(x: fx, y: fy, x2: fx2 + 1, y2: fy2 + 1, 宽: fsx, 高: fsy)
            } else {
                let width = sx ?? image.宽, height = sy ?? image.高
                guard width > 0, height > 0 else {
                    target.图像 = YURIS图像(宽: 1, 高: 1)
                    return
                }
                var from = image
                if x != nil || y != nil || x2 != nil || y2 != nil {
                    let left = x ?? 0, top = y ?? 0
                    from = image.裁剪(x: left, y: top, 宽: (x2 ?? image.宽 - 1) - left + 1, 高: (y2 ?? image.高 - 1) - top + 1)
                }
                target.图像 = operation == "SIZE" ? from.最近邻缩放(宽: width, 高: height) : from.缩放(宽: width, 高: height)
            }
        case "RESIZE":
            guard let image = source.图像 else { return }
            let left = x ?? 0, top = y ?? 0, right = x2 ?? 0, bottom = y2 ?? 0
            let width = max(1, image.宽 + left + right), height = max(1, image.高 + top + bottom)
            let result = YURIS图像(宽: width, 高: height)
            // 负数方向相当于裁剪，正数方向留透明
            let cropped = image.裁剪(x: -left, y: -top, 宽: width, 高: height)
            memcpy(result.像素, cropped.像素, result.字节数)
            source.图像 = result
        case "RECTPAINT", "RECTPAINT2", "RECTPAINT3":
            guard let image = 可写图像(source) else { return }
            填充矩形(image, 操作: operation, 颜色: set, x: x, y: y, x2: x2, y2: y2)
            source.图像 = image
        case "MERGE", "MERGE2":
            guard let top = 源图像(source), let id2, let target = 画面.查找(id2), let bottom = 可写图像(target) else { return }
            let dx = x ?? 0, dy = y ?? 0
            let range = (max(0, dx), max(0, dy), min(bottom.宽, dx + top.宽), min(bottom.高, dy + top.高))
            YURIS画面.混合(top, 到: bottom, dx: dx, dy: dy, 范围: range, 透明度: source.透明度, 模式: 0)
            target.图像 = bottom
        case "TEXT":
            guard let image = 可写图像(source) else { return }
            var state = 字体
            if bno == 1 {
                state.颜色 = 字体.备用颜色
                state.颜色2 = 字体.备用颜色2
            }
            画面.绘制文字(setString, 字体: state, 到: image, x: x ?? 0, y: y ?? 0, 描边: Int(set))
            source.图像 = image
        case "SAIDO":
            改色(source, id2, x, y, x2, y2) { p in
                // 128 不变，0 灰度，256 两倍
                let gray = (Int(p[1]) * 77 + Int(p[2]) * 151 + Int(p[3]) * 28) >> 8
                for c in 1...3 {
                    let value = gray + (Int(p[c]) - gray) * Int(set) / 128
                    p[c] = UInt8(max(0, min(Int(p[0]), value)))
                }
            }
        case "MEIDO":
            // RGB 各 8 位，0x80 不变（两倍是 0xFF 附近）
            let red = Int((set >> 16) & 0xFF), green = Int((set >> 8) & 0xFF), blue = Int(set & 0xFF)
            改色(source, id2, x, y, x2, y2) { p in
                p[1] = UInt8(min(Int(p[0]), Int(p[1]) * red / 128))
                p[2] = UInt8(min(Int(p[0]), Int(p[2]) * green / 128))
                p[3] = UInt8(min(Int(p[0]), Int(p[3]) * blue / 128))
            }
        case "AKARUSA":
            // 128 不变，0 全黑，256 全白
            let amount = Int(set) - 128
            改色(source, id2, x, y, x2, y2) { p in
                let a = Int(p[0])
                for c in 1...3 {
                    let value = amount >= 0 ? Int(p[c]) + (a - Int(p[c])) * amount / 128 : Int(p[c]) * (128 + amount) / 128
                    p[c] = UInt8(max(0, min(a, value)))
                }
            }
        case "REVERSE":
            改色(source, id2, x, y, x2, y2) { p in
                let a = p[0]
                p[1] = a &- p[1]
                p[2] = a &- p[2]
                p[3] = a &- p[3]
            }
        case "MONO":
            let threshold = Int(set)
            改色(source, id2, x, y, x2, y2) { p in
                let a = Int(p[0])
                guard a > 0 else { return }
                let gray = (Int(p[1]) * 77 + Int(p[2]) * 151 + Int(p[3]) * 28) >> 8
                let value = gray * 255 / a >= threshold ? UInt8(a) : 0
                p[1] = value
                p[2] = value
                p[3] = value
            }
        case "VERTICAL", "HORIZONTAL":
            guard let image = 源图像(source) else { return }
            let result = YURIS图像(宽: image.宽, 高: image.高)
            var from = image.缓冲区(), to = result.缓冲区()
            if operation == "VERTICAL" {
                vImageVerticalReflect_ARGB8888(&from, &to, vImage_Flags(kvImageNoFlags))
            } else {
                vImageHorizontalReflect_ARGB8888(&from, &to, vImage_Flags(kvImageNoFlags))
            }
            (id2.map { 画面.查找或新建($0) } ?? source).图像 = result
        case "BLUR", "BLUR2", "BLUR3", "BLUR4":
            guard let image = 源图像(source) else { return }
            let result = YURIS图像(宽: image.宽, 高: image.高)
            var from = image.缓冲区(), to = result.缓冲区()
            let size = UInt32(max(1, Int(set)) | 1)
            vImageBoxConvolve_ARGB8888(&from, &to, nil, 0, 0, size, size, nil, vImage_Flags(kvImageEdgeExtend))
            (id2.map { 画面.查找或新建($0) } ?? source).图像 = result
        case "MOSAIC":
            guard let image = 源图像(source) else { return }
            let block = max(1, Int(set))
            let small = image.缩放(宽: max(1, image.宽 / block), 高: max(1, image.高 / block))
            (id2.map { 画面.查找或新建($0) } ?? source).图像 = small.最近邻缩放(宽: image.宽, 高: image.高)
        case "ROTATION":
            guard let image = 源图像(source) else { return }
            // SET 是度 × 1000000 或者度，大于 1000 的按前者
            let degrees = abs(set) > 3600 ? Double(set) / 1_000_000 : Double(set)
            let radians = degrees * .pi / 180
            let width = Int((abs(cos(radians)) * Double(image.宽) + abs(sin(radians)) * Double(image.高)).rounded(.up))
            let height = Int((abs(sin(radians)) * Double(image.宽) + abs(cos(radians)) * Double(image.高)).rounded(.up))
            let result = YURIS图像(宽: width, 高: height)
            if let context = result.上下文(), let cg = image.转CGImage() {
                context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
                context.rotate(by: CGFloat(-radians))
                context.interpolationQuality = .medium
                context.draw(cg, in: CGRect(x: -CGFloat(image.宽) / 2, y: -CGFloat(image.高) / 2, width: CGFloat(image.宽), height: CGFloat(image.高)))
            }
            (id2.map { 画面.查找或新建($0) } ?? source).图像 = result
        case "TRANSITION", "TRANSITION2":
            // ID 到 ID2 的中间画面写进 ID3
            guard let a = 源图像(source), let id2, let targetSource = 画面.查找(id2), let b = 源图像(targetSource) else { return }
            let result = a.复制()
            YURIS画面.混合(b, 到: result, dx: 0, dy: 0, 范围: (0, 0, min(a.宽, b.宽), min(a.高, b.高)), 透明度: Int(set), 模式: 0)
            (id3.map { 画面.查找或新建($0) } ?? targetSource).图像 = result
        case "TRIM":
            guard let image = source.图像 else { return }
            var left = 0, top = 0, right = image.宽 - 1, bottom = image.高 - 1
            func emptyRow(_ row: Int) -> Bool { (0..<image.宽).allSatisfy { image.取像素($0, row).a == 0 } }
            func emptyColumn(_ column: Int) -> Bool { (0..<image.高).allSatisfy { image.取像素(column, $0).a == 0 } }
            if set & 8 != 0 { while top < bottom, emptyRow(top) { top += 1 } }
            if set & 4 != 0 { while bottom > top, emptyRow(bottom) { bottom -= 1 } }
            if set & 2 != 0 { while left < right, emptyColumn(left) { left += 1 } }
            if set & 1 != 0 { while right > left, emptyColumn(right) { right -= 1 } }
            source.图像 = image.裁剪(x: left, y: top, 宽: right - left + 1, 高: bottom - top + 1)
            source.x += left
            source.y += top
        case "":
            break
        default:
            提示未实现("CGACT \(operation)")
        }
    }

    private func 填充矩形(_ image: YURIS图像, 操作: String, 颜色: Int64, x: Int?, y: Int?, x2: Int?, y2: Int?) {
        let left = max(0, x ?? 0), top = max(0, y ?? 0)
        let right = min(image.宽 - 1, x2 ?? image.宽 - 1), bottom = min(image.高 - 1, y2 ?? image.高 - 1)
        guard right >= left, bottom >= top else { return }
        let a: Int, r: Int, g: Int, b: Int
        switch 操作 {
        case "RECTPAINT":
            a = -1
            r = Int((颜色 >> 16) & 0xFF); g = Int((颜色 >> 8) & 0xFF); b = Int(颜色 & 0xFF)
        case "RECTPAINT2":
            a = Int(颜色 & 0xFF)
            r = -1; g = -1; b = -1
        default:
            a = Int((颜色 >> 24) & 0xFF)
            r = Int((颜色 >> 16) & 0xFF); g = Int((颜色 >> 8) & 0xFF); b = Int(颜色 & 0xFF)
        }
        for row in top...bottom {
            var p = image.像素 + (row * image.宽 + left) * 4
            for _ in left...right {
                if 操作 == "RECTPAINT" {
                    let alpha = Int(p[0])
                    p[1] = UInt8(r * alpha / 255)
                    p[2] = UInt8(g * alpha / 255)
                    p[3] = UInt8(b * alpha / 255)
                } else if 操作 == "RECTPAINT2" {
                    // 只改透明度，颜色按新透明度重新预乘
                    let old = max(1, Int(p[0]))
                    p[1] = UInt8(min(a, Int(p[1]) * a / old))
                    p[2] = UInt8(min(a, Int(p[2]) * a / old))
                    p[3] = UInt8(min(a, Int(p[3]) * a / old))
                    p[0] = UInt8(a)
                } else {
                    p[0] = UInt8(a)
                    p[1] = UInt8(r * a / 255)
                    p[2] = UInt8(g * a / 255)
                    p[3] = UInt8(b * a / 255)
                }
                p += 4
            }
        }
    }

    private func 改色(_ source: YURIS图层, _ id2: [UInt8]?, _ x: Int?, _ y: Int?, _ x2: Int?, _ y2: Int?, _ body: (UnsafeMutablePointer<UInt8>) -> Void) {
        guard let image = 源图像(source) else { return }
        let target = id2.map { 画面.查找或新建($0) } ?? source
        let result: YURIS图像
        if target === source, !source.是集合, let writable = 可写图像(source) {
            result = writable
        } else {
            result = image.复制()
        }
        let left = max(0, x ?? 0), top = max(0, y ?? 0)
        let right = min(result.宽 - 1, x2 ?? result.宽 - 1), bottom = min(result.高 - 1, y2 ?? result.高 - 1)
        if right >= left, bottom >= top {
            for row in top...bottom {
                var p = result.像素 + (row * result.宽 + left) * 4
                for _ in left...right {
                    if p[0] != 0 { body(p) }
                    p += 4
                }
            }
        }
        target.图像 = result
    }

    func 执行CGINFO(_ ins: YURIS指令) {
        var id: [UInt8] = []
        var target: YURIS引用 = .无
        var query = ""
        var setX: Int?, setY: Int?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "ID": id = 文字(argument)
            case "LET": target = 求引用(argument.表达式)
            case "SET": setX = 整数(argument)
            case "SET2": setY = 整数(argument)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        let layer = 画面.查找(id)
        let result: YURIS值
        switch query {
        case "EXIST": result = .整数(layer == nil ? 0 : 1)
        case "E": result = .整数(layer?.启用 == true ? 1 : 0)
        case "A": result = .整数(Int64(layer?.透明度 ?? 0))
        case "X": result = .整数(Int64(layer?.x ?? 0))
        case "Y": result = .整数(Int64(layer?.y ?? 0))
        case "Z": result = .整数(layer?.z ?? 0)
        case "SX": result = .整数(Int64(layer?.宽 ?? 0))
        case "SY": result = .整数(Int64(layer?.高 ?? 0))
        case "MODE": result = .整数(Int64(layer?.模式 ?? 0))
        case "T": result = .整数(Int64(layer?.过渡进度 ?? 0))
        case "TA": result = .整数(Int64(layer?.过渡精度 ?? 0))
        case "TID": result = .文字(layer?.过渡图层 ?? [])
        case "LINT": result = .整数(layer?.整数属性[0] ?? 0)
        case "LINT2": result = .整数(layer?.整数属性[1] ?? 0)
        case "COLOR":
            let pixel = layer?.图像?.取像素(setX ?? 0, setY ?? 0) ?? (0, 0, 0, 0)
            result = .整数(Self.还原颜色(pixel))
        case "ONMOUSE", "ONMOUSE2", "ONMOUSE3":
            // 默认用鼠标位置
            let mouseX = setX ?? 全局[111]?.标量.转Int ?? 0
            let mouseY = setY ?? 全局[116]?.标量.转Int ?? 0
            guard let layer, let image = layer.图像 else { result = .整数(-1); break }
            let origin = layer.绝对位置
            let px = mouseX - origin.x, py = mouseY - origin.y
            guard px >= 0, py >= 0, px < image.宽, py < image.高 else { result = .整数(-1); break }
            let pixel = image.取像素(px, py)
            switch query {
            case "ONMOUSE": result = .整数(Self.还原颜色(pixel))
            case "ONMOUSE2": result = .整数(Int64(pixel.a))
            default: result = .整数(Int64(pixel.a) << 24 | Self.还原颜色(pixel))
            }
        default:
            result = .整数(0)
        }
        写入(target, result)
    }

    private static func 还原颜色(_ pixel: (a: UInt8, r: UInt8, g: UInt8, b: UInt8)) -> Int64 {
        let a = Int64(pixel.a)
        guard a > 0 else { return 0 }
        func channel(_ value: UInt8) -> Int64 { a == 255 ? Int64(value) : min(255, (Int64(value) * 255 + a / 2) / a) }
        return channel(pixel.r) << 16 | channel(pixel.g) << 8 | channel(pixel.b)
    }

    // MARK: - 字体和文字

    func 执行FONT(_ ins: YURIS指令) {
        let isBank = 查参数(ins, "BNO").map { 整数($0) != 0 } ?? false
        for argument in ins.参数 {
            switch argument.关键字 {
            case "NAME": 字体.名称 = 求值(argument.表达式).显示文字
            case "COLOR":
                let value = 长整数(argument)
                if isBank { 字体.备用颜色 = value } else { 字体.颜色 = value; if 字体.颜色2 < 0 { 字体.颜色2 = value } }
            case "COLOR2":
                let value = 长整数(argument)
                if isBank { 字体.备用颜色2 = value } else { 字体.颜色2 = value < 0 ? 字体.颜色 : value }
            case "SX": 字体.宽 = 整数(argument)
            case "SY": 字体.高 = 整数(argument)
            case "BOLD": 字体.粗体 = 整数(argument) != 0
            case "ANTIALIASING": 字体.抗锯齿 = 整数(argument) != 0
            case "DRAWMODE": 字体.绘制模式 = 整数(argument)
            case "GRADATION": 字体.渐变 = 整数(argument)
            case "ROTATION": 字体.旋转 = 整数(argument)
            default: break
            }
        }
    }

    private static let 字体列表 = ["ＭＳ ゴシック", "ＭＳ Ｐゴシック", "ＭＳ 明朝", "ＭＳ Ｐ明朝", "メイリオ"]

    func 执行FONTINFO(_ ins: YURIS指令) {
        var target: YURIS引用 = .无
        var query = ""
        var number: Int?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "LET": target = 求引用(argument.表达式)
            case "NO": number = 整数(argument)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        let result: YURIS值
        switch query {
        case "COLOR": result = .整数(字体.颜色)
        case "COLOR2": result = .整数(字体.颜色2)
        case "SX": result = .整数(Int64(字体.宽))
        case "SY": result = .整数(Int64(字体.高))
        case "BOLD": result = .整数(字体.粗体 ? 1 : 0)
        case "ANTIALIASING": result = .整数(字体.抗锯齿 ? 1 : 0)
        case "DRAWMODE": result = .整数(Int64(字体.绘制模式))
        case "NUM": result = .整数(Int64(Self.字体列表.count))
        case "NAME":
            if let number, number >= 1, number <= Self.字体列表.count {
                result = .文字(YURIS文本.编码(Self.字体列表[number - 1]))
            } else {
                result = .文字(YURIS文本.编码(字体.名称))
            }
        case "LANG": result = .整数(128) // Shift-JIS 字符集
        default: result = .整数(0)
        }
        写入(target, result)
    }

    func 执行TEXT(_ ins: YURIS指令) {
        var enqueue: [YURIS自动文字.项] = []
        for argument in ins.参数 {
            switch argument.关键字 {
            case "OUTPUTMODE": 文字输出模式 = 整数(argument)
            case "ID": 自动文字.图层ID = 文字(argument)
            case "WAIT": 自动文字.每字毫秒 = Double(max(0, 整数(argument)))
            case "AUTORETURN": 自动文字.自动换行 = 整数(argument) != 0
            case "AUTOPAGE": 自动文字.自动换页 = 整数(argument) != 0
            case "AUTOCLICK": 自动文字.自动点按 = 整数(argument) != 0
            case "RETURN": if 整数(argument) != 0 { enqueue.append(.换行) }
            case "PAGE": if 整数(argument) != 0 { enqueue.append(.换页) }
            case "CLICK": if 整数(argument) != 0 { enqueue.append(.点按) }
            case "CLICKRETURN": if 整数(argument) != 0 { enqueue += [.点按, .换行] }
            case "CLICKPAGE": if 整数(argument) != 0 { enqueue += [.点按, .换页] }
            case "CLICKBUTTON", "CLICKBUTTON2", "CLICKBUTTON3", "CLICKBUTTON4":
                let slot = argument.关键字 == "CLICKBUTTON" ? 0 : Int(argument.关键字.last!.wholeNumberValue! - 1)
                自动文字.点按键[slot] = 整数(argument)
            case "SKIPBUTTON", "SKIPBUTTON2", "SKIPBUTTON3", "SKIPBUTTON4":
                let slot = argument.关键字 == "SKIPBUTTON" ? 0 : Int(argument.关键字.last!.wholeNumberValue! - 1)
                自动文字.跳过键[slot] = 整数(argument)
            case "CLEAR":
                if 整数(argument) != 0 {
                    全局[100]?.标量 = .文字([])
                    全局[101]?.标量 = .文字([])
                    自动文字.队列.removeAll()
                    自动文字.等待点按 = false
                }
            default: break
            }
        }
        if !enqueue.isEmpty {
            自动文字.队列 += enqueue
            当前任务.等待自动文字 = true
        }
    }

    func 执行TEXTINFO(_ ins: YURIS指令) {
        var target: YURIS引用 = .无
        var query = ""
        for argument in ins.参数 {
            if argument.关键字 == "LET" {
                target = 求引用(argument.表达式)
            } else if argument.关键字 != "ID", argument.关键字 != "SET", 求值(argument.表达式).为真 {
                query = argument.关键字
            }
        }
        let value: Int
        switch query {
        case "OUTPUTMODE": value = 文字输出模式
        case "CX": value = 自动文字.光标x
        case "CY": value = 自动文字.光标y
        case "CLICK": value = 自动文字.等待点按 ? 1 : 0
        case "AUTORETURN": value = 自动文字.自动换行 ? 1 : 0
        case "AUTOPAGE": value = 自动文字.自动换页 ? 1 : 0
        case "AUTOCLICK": value = 自动文字.自动点按 ? 1 : 0
        default: value = 0
        }
        写入(target, .整数(Int64(value)))
    }

    // MARK: - 引擎自动显示文字（OUTPUTMODE=1）

    /// 正文进队列，由 更新自动文字 按 TEXT[WAIT] 一个字一个字画到图层上。任务等到队列空了才继续。
    func 自动文字追加(_ text: [UInt8]) {
        var i = 0
        while i < text.count {
            let c = text[i]
            // \r \p \c 编译成 $_CHR(239) 加一个控制字节
            if c == 0xEF, i + 1 < text.count, text[i + 1] >= 0xF0, text[i + 1] <= 0xF3 {
                switch text[i + 1] {
                case 0xF0: 自动文字.队列.append(.换行)
                case 0xF2: 自动文字.队列.append(.换页)
                case 0xF3: 自动文字.队列.append(.点按)
                default: break
                }
                i += 2
                continue
            }
            // 手册写法 \[r] \[p] \[c]。也可能原样留在文本里
            if c == 0x5C, i + 3 < text.count, text[i + 1] == 0x5B, text[i + 3] == 0x5D {
                var known = true
                switch text[i + 2] {
                case 0x72, 0x52: 自动文字.队列.append(.换行)
                case 0x70, 0x50: 自动文字.队列.append(.换页)
                case 0x63, 0x43: 自动文字.队列.append(.点按)
                default: known = false
                }
                if known {
                    i += 4
                    continue
                }
            }
            let end = min(text.count, i + YURIS文本.字符长度(text, i))
            自动文字.队列.append(.字符(Array(text[i..<end])))
            i = end
        }
        当前任务.等待自动文字 = true
    }

    /// RETURNCODE：行尾的自动处理
    func 自动文字行尾() {
        if 自动文字.自动点按 { 自动文字.队列.append(.点按) }
        if 自动文字.自动换页 { 自动文字.队列.append(.换页) } else if 自动文字.自动换行 { 自动文字.队列.append(.换行) }
        当前任务.等待自动文字 = true
    }

    private func 按键按下(_ code: Int) -> Bool {
        guard code > 0, let variable = 全局[code + 124] else { return false }
        return variable.标量.转Int == 1
    }

    private func 按键按住(_ code: Int) -> Bool {
        guard code > 0, let variable = 全局[code + 124] else { return false }
        return variable.标量.转Int > 0
    }

    private func 自动文字图层() -> YURIS图层 {
        let id = 自动文字.图层ID.isEmpty ? Array("__PAPERVN_TEXT".utf8) : 自动文字.图层ID
        let layer = 画面.查找或新建(id)
        if 自动文字.图层ID.isEmpty { layer.z = 1_000_000 }
        if layer.图像 == nil || (layer.图像?.宽 ?? 0) <= 1 {
            layer.图像 = YURIS图像(宽: 画面.宽, 高: 画面.高)
        }
        return layer
    }

    func 更新自动文字() {
        guard !自动文字.队列.isEmpty || 自动文字.等待点按 else { return }
        let skipping = 自动文字.跳过键.contains { 按键按住($0) }
        if 自动文字.等待点按 {
            guard skipping || 自动文字.点按键.contains(where: { 按键按下($0) }) else { return }
            自动文字.等待点按 = false
        }
        let layer = 自动文字图层()
        let line = max(1, 字体.高)
        while !自动文字.队列.isEmpty {
            if !skipping, 自动文字.每字毫秒 > 0, 当前毫秒 < 自动文字.下一字时间 { return }
            switch 自动文字.队列.removeFirst() {
            case .字符(let bytes):
                guard let image = 可写图像(layer) else { continue }
                let wide = bytes.count > 1
                let advance = wide ? 字体.宽 : 字体.宽 / 2
                if 自动文字.光标x + advance > image.宽 {
                    自动文字.光标x = 0
                    自动文字.光标y += line
                }
                画面.绘制文字(bytes, 字体: 字体, 到: image, x: 自动文字.光标x, y: 自动文字.光标y, 描边: 0)
                layer.图像 = image
                自动文字.光标x += advance
                if let buffer = 全局[100], let flags = 全局[101] {
                    buffer.标量 = .文字(buffer.标量.转文字 + bytes)
                    flags.标量 = .文字(flags.标量.转文字 + [wide ? 0x32 : 0x31])
                }
                画面.脏 = true
                if !skipping, 自动文字.每字毫秒 > 0 { 自动文字.下一字时间 = 当前毫秒 + 自动文字.每字毫秒 }
            case .换行:
                自动文字.光标x = 0
                自动文字.光标y += line
            case .换页:
                if let image = 可写图像(layer) {
                    image.填充(a: 0, r: 0, g: 0, b: 0)
                    layer.图像 = image
                }
                自动文字.光标x = 0
                自动文字.光标y = 0
                全局[100]?.标量 = .文字([])
                全局[101]?.标量 = .文字([])
                画面.脏 = true
            case .点按:
                if !skipping {
                    自动文字.等待点按 = true
                    return
                }
            }
        }
    }

    // MARK: - 图层上的影片（CG[FILE="x.avi"]）

    /// 图层里放影片：每帧把画面换成当前帧。放不了时返回 false，按找不到图片处理。
    private func 打开图层影片(_ file: String, _ layer: YURIS图层) -> Bool {
        图层影片.removeAll { item in
            guard item.图层 === layer else { return false }
            item.播放器.停止()
            return true
        }
        let ext = (file as NSString).pathExtension.lowercased()
        guard ["avi", "wmv", "asf", "mpg", "mpeg"].contains(ext), let data = 程序.资源.读取(file) else { return false }
        guard let player = 视觉小说影片.打开(数据: data, 顺序: .argb, 声音: !虚拟时钟, 外部时钟: 影片时钟()) else { return false }
        layer.图像 = YURIS图像(宽: player.宽, 高: player.高)
        player.开始()
        图层影片.append((layer, player))
        return true
    }

    private func 影片时钟() -> (() -> Double)? {
        guard 虚拟时钟 else { return nil }
        let start = 当前毫秒
        return { [unowned self] in (当前毫秒 - start) / 1000 }
    }

    func 更新图层影片() {
        guard !图层影片.isEmpty else { return }
        图层影片.removeAll { item in
            if let frame = item.播放器.取帧(), let image = item.图层.图像, image.宽 == frame.宽, image.高 == frame.高 {
                memcpy(image.像素, frame.像素, image.字节数)
                画面.脏 = true
            }
            guard item.播放器.已结束 else { return false }
            item.播放器.停止()
            return true
        }
    }

    func 停止图层影片() {
        for item in 图层影片 { item.播放器.停止() }
        图层影片 = []
    }

    // MARK: - MIDI

    func 执行MIDI(_ ins: YURIS指令) {
        var file: String?
        var play: Bool?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": file = 求值(argument.表达式).显示文字
            case "PLAY": play = 整数(argument) != 0
            default: break
            }
        }
        if let file { MIDI文件 = file }
        if play == true {
            guard let data = 程序.资源.读取(MIDI文件) else {
                日志("找不到 MIDI：\(MIDI文件)")
                return
            }
            MIDI接口?.播放(data)
        } else if play == false {
            MIDI接口?.停止()
        }
    }

    func 执行MIDIEND(_ ins: YURIS指令) {
        MIDI接口?.停止()
    }

    // MARK: - Flash

    func 执行FLASH(_ ins: YURIS指令) {
        var play: Bool?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": Flash状态.文件 = 求值(argument.表达式).显示文字
            case "X": Flash状态.x = 整数(argument)
            case "Y": Flash状态.y = 整数(argument)
            case "SX": Flash状态.宽 = 整数(argument)
            case "SY": Flash状态.高 = 整数(argument)
            case "ENDFRAME": Flash状态.结束帧 = 整数(argument)
            case "PLAY": play = 整数(argument) != 0
            default: break
            }
        }
        if play == true {
            // 手册：swf 不能放进封包
            guard let url = 程序.资源.散放文件地址(Flash状态.文件) else {
                日志("找不到 Flash：\(Flash状态.文件)")
                return
            }
            Flash接口?.打开(地址: url, x: Flash状态.x, y: Flash状态.y, 宽: Flash状态.宽 ?? 画面.宽, 高: Flash状态.高 ?? 画面.高,
                         画面宽: 画面.宽, 画面高: 画面.高, 结束帧: Flash状态.结束帧)
        } else if play == false {
            Flash接口?.关闭()
        }
    }

    func 执行FLASHEND(_ ins: YURIS指令) {
        Flash接口?.关闭()
    }

    func 执行FLASHINFO(_ ins: YURIS指令) {
        var target: YURIS引用 = .无
        var query = ""
        for argument in ins.参数 {
            if argument.关键字 == "LET" {
                target = 求引用(argument.表达式)
            } else if 求值(argument.表达式).为真 {
                query = argument.关键字
            }
        }
        let status = Flash接口?.状态 ?? (播放中: false, 当前帧: 0, 总帧数: 0)
        let value: Int
        switch query {
        case "PLAY": value = status.播放中 ? 1 : 0
        case "FRAME": value = status.当前帧
        case "TOTALFRAME": value = status.总帧数
        case "ENDFRAME": value = Flash状态.结束帧 ?? status.总帧数
        case "X": value = Flash状态.x
        case "Y": value = Flash状态.y
        case "SX": value = Flash状态.宽 ?? 画面.宽
        case "SY": value = Flash状态.高 ?? 画面.高
        default: value = 0
        }
        写入(target, .整数(Int64(value)))
    }

    // MARK: - 任务

    func 执行TASK(_ ins: YURIS指令) {
        var id: [UInt8]?
        var enabled: Int?
        var z: Int64?
        var label: [UInt8]?
        var position: [UInt8]?
        var restart = false
        var parameters: [(Int, Int64)] = []
        for argument in ins.参数 {
            switch argument.关键字 {
            case "ID": id = 文字(argument)
            case "E": enabled = 整数(argument)
            case "Z": z = 长整数(argument)
            case "#": label = 文字(argument)
            case "SCRIPTPOS": position = 文字(argument)
            case "RESTART": restart = 整数(argument) != 0
            default:
                if argument.槽 > 0 { parameters.append((argument.槽, 长整数(argument))) }
            }
        }
        if let label {
            guard let resolved = 查标签(label), let script = 取脚本(resolved.脚本) else {
                日志("TASK 找不到标签：\(YURIS文本.解码(label))")
                return
            }
            let name = id ?? []
            if let old = 查找任务(name) { old.已结束 = true }
            let task = YURIS任务(名称: name, 优先度: z ?? 1, 变量数: 变量容量)
            task.帧栈.append(YURIS帧(脚本: script, pc: resolved.位置, 深度: 0))
            for (slot, value) in parameters where slot < task.任务参数.count { task.任务参数[slot] = value }
            添加任务(task)
            return
        }
        let task: YURIS任务? = id.map { 查找任务($0) } ?? 当前任务
        guard let task else { return }
        if let enabled { task.启用 = enabled != 0 }
        if let z { task.优先度 = z }
        if let position { 恢复位置(task, position) }
        if restart {
            // 文字任务显示完一句后调用：下一句从空缓冲开始（WORD 只负责追加）
            全局[100]?.标量 = .文字([])
            全局[101]?.标量 = .文字([])
        }
        for (slot, value) in parameters where slot < task.任务参数.count { task.任务参数[slot] = value }
    }

    func 执行TASKEND(_ ins: YURIS指令) {
        let id = 查参数(ins, "ID").map { 文字($0) }
        let task: YURIS任务? = id.map { 查找任务($0) } ?? 当前任务
        task?.已结束 = true
    }

    func 执行TASKINFO(_ ins: YURIS指令) {
        var id: [UInt8]?
        var target: YURIS引用 = .无
        var query = ""
        for argument in ins.参数 {
            switch argument.关键字 {
            case "ID": id = 文字(argument)
            case "LET": target = 求引用(argument.表达式)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        let task: YURIS任务? = id.map { 查找任务($0) } ?? 当前任务
        let top = task?.帧栈.last, bottom = task?.帧栈.first
        func scriptName(_ frame: YURIS帧?) -> [UInt8] {
            guard let frame else { return [] }
            return Array(String(format: "yst%05d.yst", frame.脚本.序号).utf8)
        }
        func line(_ frame: YURIS帧?) -> Int64 {
            guard let frame else { return 0 }
            let index = max(0, frame.pc - 1)
            return index < frame.脚本.指令.count ? Int64(frame.脚本.指令[index].行) : 0
        }
        let result: YURIS值
        switch query {
        case "EXIST": result = .整数(task == nil ? 0 : 1)
        case "E": result = .整数(task?.启用 == true ? 1 : 0)
        case "Z": result = .整数(task?.优先度 ?? 0)
        case "FILE": result = .文字(scriptName(top))
        case "FILE0": result = .文字(scriptName(bottom))
        case "FILENO": result = .整数(Int64(top?.脚本.序号 ?? 0))
        case "FILENO0": result = .整数(Int64(bottom?.脚本.序号 ?? 0))
        case "LINE": result = .整数(line(top))
        case "LINE0": result = .整数(line(bottom))
        case "GOSUBNEST": result = .整数(Int64((task?.帧栈.count ?? 1) - 1))
        case "LOOPNEST": result = .整数(Int64(top?.循环.count ?? 0))
        case "TEXTLINE": result = .整数(Int64(task?.文字行 ?? 0))
        case "NEXTVOICE": result = .整数(Int64(task?.下句语音 ?? 0))
        case "SCRIPTPOS": result = .文字(task.map { 序列化位置($0) } ?? [])
        default: result = .整数(0)
        }
        写入(target, result)
    }

    /// 脚本位置：调用栈和循环状态的文本表示。存档时脚本把它当字符串存。
    private func 序列化位置(_ task: YURIS任务) -> [UInt8] {
        var parts: [String] = []
        for frame in task.帧栈 {
            var text = "\(frame.脚本.序号):\(frame.pc)"
            for loop in frame.循环 {
                text += ":\(loop.开始),\(loop.结束),\(loop.总数),\(loop.计数)"
            }
            parts.append(text)
        }
        parts.append("L\(task.文字行),\(task.下句语音)")
        return Array(parts.joined(separator: ";").utf8)
    }

    private func 恢复位置(_ task: YURIS任务, _ position: [UInt8]) {
        let text = String(decoding: position, as: UTF8.self)
        var frames: [YURIS帧] = []
        for part in text.split(separator: ";") {
            if part.hasPrefix("L") {
                let values = part.dropFirst().split(separator: ",").compactMap { Int($0) }
                if values.count == 2 {
                    task.文字行 = values[0]
                    task.下句语音 = values[1]
                }
                continue
            }
            let fields = part.split(separator: ":")
            guard fields.count >= 2, let script = Int(fields[0]), let pc = Int(fields[1]), let file = 取脚本(script) else { continue }
            let frame = YURIS帧(脚本: file, pc: pc, 深度: frames.count)
            for field in fields.dropFirst(2) {
                let values = field.split(separator: ",").compactMap { Int64($0) }
                if values.count == 4 {
                    frame.循环.append(YURIS循环项(开始: Int(values[0]), 结束: Int(values[1]), 总数: values[2], 计数: values[3]))
                }
            }
            frames.append(frame)
        }
        guard !frames.isEmpty else { return }
        task.帧栈 = frames
        task.局部 = [YURIS变量?](repeating: nil, count: 变量容量)
        task.等待帧 = 0
        task.等待到 = 0
    }

    // MARK: - 变量

    func 执行VARACT(_ ins: YURIS指令) {
        var source: YURIS引用 = .无
        var sourceArgument: YURIS参数?
        var target: YURIS引用?
        var position = 1, length = 0
        var operation = ""
        var dimension: YURIS参数?
        var push: Int?, pop: Int?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "SET":
                sourceArgument = argument
                source = 求引用(argument.表达式)
            case "LET": target = 求引用(argument.表达式)
            case "POS": position = 整数(argument)
            case "LENGTH": length = 整数(argument)
            case "DIMSIZE": dimension = argument
            case "PUSH": push = 整数(argument)
            case "POP": pop = 整数(argument)
            default:
                if 求值(argument.表达式).为真 { operation = argument.关键字 }
            }
        }
        if let dimension, case .整个数组(let variable) = source {
            let current = variable.维度.first ?? variable.元素.count
            let size = max(0, 改(current, dimension))
            let fill = Self.默认值(variable.类型)
            if size > variable.元素.count {
                variable.元素.append(contentsOf: [YURIS值](repeating: fill, count: size - variable.元素.count))
            } else if size < variable.元素.count {
                variable.元素.removeLast(variable.元素.count - size)
            }
            variable.维度 = [size]
            return
        }
        if let push, case .整个数组(let variable) = source, push >= 0, push < variable.元素.count {
            variable.元素.insert(Self.默认值(variable.类型), at: push)
            variable.元素.removeLast()
            return
        }
        if let pop, case .整个数组(let variable) = source, pop >= 0, pop < variable.元素.count {
            variable.元素.remove(at: pop)
            variable.元素.append(Self.默认值(variable.类型))
            return
        }
        // 表达式也能当源（SET=$_PSTR(1)）
        let value: YURIS值
        if case .无 = source, let sourceArgument {
            value = 求值(sourceArgument.表达式)
        } else if let sourceArgument, case .下标常量 = sourceArgument.表达式 {
            value = 求值(sourceArgument.表达式)
        } else if let sourceArgument, case .通用 = sourceArgument.表达式 {
            value = 求值(sourceArgument.表达式)
        } else {
            value = 读引用(source)
        }
        let bytes = value.转文字
        switch operation {
        case "TYPE":
            if value.是文字 {
                写入(target ?? source, .整数(YURIS值.解析整数(bytes)))
            } else {
                写入(target ?? source, .文字(bytes))
            }
        case "COPY":
            写入(target ?? source, .文字(YURIS文本.子串(bytes, 位置: position, 长度: length)))
        case "CUT":
            // 从源里切掉一段；有 LET 时把切掉后的结果放进 LET
            let before = YURIS文本.子串(bytes, 位置: 1, 长度: position - 1)
            let after = YURIS文本.子串(bytes, 位置: position + length, 长度: Int.max / 2)
            写入(target ?? source, .文字(before + after))
        case "UPPER", "UPPER2", "LOWER", "LOWER2":
            var result = bytes
            let upper = operation.hasPrefix("UPPER")
            var i = 0
            while i < result.count {
                let c = result[i]
                if YURIS文本.是首字节(c) { i += YURIS文本.字符长度(result, i); continue }
                if upper, c >= 0x61, c <= 0x7A { result[i] = c - 0x20 }
                if !upper, c >= 0x41, c <= 0x5A { result[i] = c + 0x20 }
                i += 1
            }
            写入(target ?? source, .文字(result))
        case "HANTOZEN", "ZENTOHAN":
            let text = YURIS文本.解码(bytes) as NSString
            let converted = text.applyingTransform(.fullwidthToHalfwidth, reverse: operation == "HANTOZEN") ?? (text as String)
            写入(target ?? source, .文字(YURIS文本.编码(converted)))
        default:
            break
        }
    }

    func 执行VARINFO(_ ins: YURIS指令) {
        var sourceArgument: YURIS参数?
        var target: YURIS引用 = .无
        var query = ""
        var searchValue: YURIS值?
        var start = 0
        for argument in ins.参数 {
            switch argument.关键字 {
            case "SET": sourceArgument = argument
            case "LET": target = 求引用(argument.表达式)
            case "INT", "FLT", "STR": searchValue = 求值(argument.表达式)
            case "NO": start = 整数(argument)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        guard let sourceArgument else { return }
        let reference = 求引用(sourceArgument.表达式)
        var array: YURIS变量?
        if case .整个数组(let variable) = reference { array = variable }
        let result: YURIS值
        switch query {
        case "LENGTH":
            result = .整数(Int64(YURIS文本.字符数(求值(sourceArgument.表达式).转文字)))
        case "STRTYPE":
            // 单个字符的类型：1 半角，2 全角
            let bytes = 求值(sourceArgument.表达式).转文字
            result = .整数(bytes.first.map { YURIS文本.是首字节($0) ? 2 : 1 } ?? 0)
        case "TYPE":
            switch 求值(sourceArgument.表达式) {
            case .整数: result = .整数(1)
            case .小数: result = .整数(2)
            case .文字: result = .整数(3)
            }
        case "DIMNUM":
            result = .整数(Int64(array?.维度.count ?? 0))
        case "DIMSIZE", "DIMSIZE2", "DIMSIZE3", "DIMSIZE4", "DIMSIZE5", "DIMSIZE6", "DIMSIZE7", "DIMSIZE8":
            let level = query == "DIMSIZE" ? 0 : (Int(query.dropFirst(7)) ?? 1) - 1
            if let dims = array?.维度, level < dims.count {
                result = .整数(Int64(dims[level]))
            } else {
                result = .整数(0)
            }
        case "SEARCH":
            var found: Int64 = -1
            if let array, let searchValue {
                let elements = array.元素
                var i = max(0, start)
                while i < elements.count {
                    let same: Bool
                    switch (elements[i], searchValue) {
                    case (.文字(let a), .文字(let b)): same = a == b
                    case (.文字, _), (_, .文字): same = false
                    default: same = elements[i].转小数 == searchValue.转小数
                    }
                    if same { found = Int64(i); break }
                    i += 1
                }
            }
            result = .整数(found)
        default:
            result = .整数(0)
        }
        写入(target, result)
    }

    func 执行MATH(_ ins: YURIS指令) {
        var target: YURIS引用 = .无
        var a = 0.0, b = 0.0
        var query = ""
        for argument in ins.参数 {
            switch argument.关键字 {
            case "LET": target = 求引用(argument.表达式)
            case "SET": a = 求值(argument.表达式).转小数
            case "SET2": b = 求值(argument.表达式).转小数
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        let result: Double
        switch query {
        case "SIN": result = sin(a)
        case "ASIN": result = asin(a)
        case "SINH": result = sinh(a)
        case "COS": result = cos(a)
        case "ACOS": result = acos(a)
        case "COSH": result = cosh(a)
        case "TAN": result = tan(a)
        case "ATAN": result = atan(a)
        case "ATAN2": result = atan2(a, b)
        case "TANH": result = tanh(a)
        case "SQRT": result = a.squareRoot()
        case "ABS": result = abs(a)
        case "EXP": result = exp(a)
        case "LOG": result = log(a)
        case "LOG10": result = log10(a)
        case "POW": result = pow(a, b)
        case "RND":
            let low = Int64(a), high = Int64(b)
            写入(target, .整数(low <= high ? Int64.random(in: low...high) : low))
            return
        default: result = 0
        }
        写入(target, .小数(result))
    }

    func 执行MATH3D(_ ins: YURIS指令) {
        var ints: YURIS变量?, reals: YURIS变量?
        for argument in ins.参数 {
            switch (argument.关键字, 求引用(argument.表达式)) {
            case ("INT", .整个数组(let variable)): ints = variable
            case ("FLT", .整个数组(let variable)): reals = variable
            default: break
            }
        }
        guard let ints, let reals, ints.元素.count >= 8, reals.元素.count >= 35 else { return }
        if 跟踪MATH3D {
            日志("MATH3D I=\(ints.元素.map(\.转Int)) F=\(reals.元素.map { (($0.转小数 * 100).rounded()) / 100 })")
        }
        // E-ris 精灵库的透视投影。输入约定（从脚本 es.SP.XYZCALC 读出来的）：
        // I[1] 精灵，I[4] 父精灵，I[5]、I[6] 屏幕大小
        // F[3...5] 视点，F[13...15] 精灵位置，F[16...17]、F[20...21] 缩放百分比，F[18...19] 精灵中心
        // F[22...24] 父精灵位置，F[27] 基准距离（200，距离等于它时不缩放），F[28...30] 相机偏移
        // 输出 F[31]、F[32] 精灵左上角的屏幕坐标，F[33]、F[34] 缩放百分比
        let f = reals.元素.map(\.转小数)
        let width = Double(ints.元素[5].转Int), height = Double(ints.元素[6].转Int)
        var x = f[13], y = f[14], z = f[15]
        if ints.元素[4].转Int != 0 {
            x += f[22]
            y += f[23]
            z += f[24] - f[27]
        }
        let eyeX = f[3] + f[28], eyeY = f[4] + f[29], eyeZ = f[5] + f[30]
        let distance = max(1, z - eyeZ)
        let perspective = f[27] / distance
        let scaleX = f[16] * f[20] / 100 * perspective
        let scaleY = f[17] * f[21] / 100 * perspective
        reals.元素[31] = .小数(width / 2 + (x - eyeX) * perspective - f[18] * scaleX / 100)
        reals.元素[32] = .小数(height / 2 + (y - eyeY) * perspective - f[19] * scaleY / 100)
        reals.元素[33] = .小数(scaleX)
        reals.元素[34] = .小数(scaleY)
    }

    // MARK: - 存档

    /// `save/abc`、`save\abc.sd` → 存档目录/abc.sd
    private func 存档路径(_ file: String) -> URL {
        var name = file.replacingOccurrences(of: "\\", with: "/")
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if !name.lowercased().hasSuffix(".sd"), !name.contains(".") { name += ".sd" }
        return 存档目录.appending(path: name)
    }

    private func 是存档路径(_ file: String) -> Bool {
        let name = file.replacingOccurrences(of: "\\", with: "/").lowercased()
        return name.hasPrefix("save/") || name.hasSuffix(".sd") || name.contains("/save/")
    }

    private func 读存档文件(_ url: URL) -> [Int: YURIS存档项] {
        if let cached = 存档缓存[url.lastPathComponent] { return cached }
        guard let data = try? Data(contentsOf: url), let entries = YURIS存档编码.解码(data) else { return [:] }
        存档缓存[url.lastPathComponent] = entries
        return entries
    }

    func 执行SAVE(_ ins: YURIS指令) {
        var file: String?
        var number: Int?
        var valueArgument: YURIS参数?
        var layerID: [UInt8]?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": file = 求值(argument.表达式).显示文字
            case "DNO": number = 整数(argument)
            case "SET": valueArgument = argument
            case "ID": layerID = 文字(argument)
            default: break
            }
        }
        if let number {
            if let valueArgument {
                let reference = 求引用(valueArgument.表达式)
                switch reference {
                case .整个数组(let variable):
                    预约存档[number] = .值(维度: variable.维度, 元素: variable.元素)
                default:
                    预约存档[number] = .值(维度: [], 元素: [求值(valueArgument.表达式)])
                }
            } else if let layerID, let layer = 画面.查找(layerID), let image = 源图像Public(layer), let png = YURIS存档编码.编码图片(image) {
                预约存档[number] = .图片(png)
            }
        }
        if let file {
            let url = 存档路径(file)
            var entries = 读存档文件(url)
            for (key, value) in 预约存档 { entries[key] = value }
            预约存档 = [:]
            存档缓存[url.lastPathComponent] = entries
            try? FileManager.default.createDirectory(at: 存档目录, withIntermediateDirectories: true)
            try? YURIS存档编码.编码(entries).write(to: url, options: .atomic)
        }
    }

    private func 源图像Public(_ layer: YURIS图层) -> YURIS图像? { 源图像(layer) }

    func 执行LOAD(_ ins: YURIS指令) {
        var file = ""
        var number = 0
        var targetArgument: YURIS参数?
        var layerID: [UInt8]?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": file = 求值(argument.表达式).显示文字
            case "DNO": number = 整数(argument)
            case "LET": targetArgument = argument
            case "ID": layerID = 文字(argument)
            default: break
            }
        }
        let entries = 读存档文件(存档路径(file))
        guard let entry = entries[number] else { return }
        switch entry {
        case .值(let dims, let elements):
            guard let targetArgument else { return }
            let reference = 求引用(targetArgument.表达式)
            switch reference {
            case .整个数组(let variable):
                // 存档比当前数组大或小都按存档的来，DIMSIZE 增长过的数组也能还原
                variable.维度 = dims
                variable.元素 = elements.map { 转换($0, 类型: variable.类型) }
            default:
                if let first = elements.first { 写入(reference, first) }
            }
        case .图片(let data):
            guard let layerID else { return }
            let layer = 画面.查找或新建(layerID)
            layer.图像 = YURIS图像.解码(data)
            画面.脏 = true
        }
    }

    func 执行FILEACT(_ ins: YURIS指令) {
        var file: String?, file2: String?
        var operation = ""
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": file = 求值(argument.表达式).显示文字
            case "FILE2": file2 = 求值(argument.表达式).显示文字
            case "COPY", "DELETE", "CREATE", "EXEC":
                if 求值(argument.表达式).为真 { operation = argument.关键字 }
            default: break
            }
        }
        switch operation {
        case "DELETE":
            guard let file, 是存档路径(file) else { return }
            let url = 存档路径(file)
            存档缓存[url.lastPathComponent] = nil
            try? FileManager.default.removeItem(at: url)
        case "COPY":
            guard let file, let file2, 是存档路径(file), 是存档路径(file2) else { return }
            let from = 存档路径(file), to = 存档路径(file2)
            存档缓存[to.lastPathComponent] = nil
            try? FileManager.default.removeItem(at: to)
            try? FileManager.default.copyItem(at: from, to: to)
        default:
            break
        }
    }

    func 执行FILEINFO(_ ins: YURIS指令) {
        var file: String?
        var target: YURIS引用 = .无
        var query = ""
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": file = 求值(argument.表达式).显示文字
            case "FOLDER": file = 求值(argument.表达式).显示文字
            case "LET": target = 求引用(argument.表达式)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        guard let file else { return }
        let result: YURIS值
        switch query {
        case "EXIST":
            if 是存档路径(file) {
                result = .整数(FileManager.default.fileExists(atPath: 存档路径(file).path) ? 1 : 0)
            } else {
                result = .整数(程序.资源.存在(file) ? 1 : 0)
            }
        case "SIZE":
            let size = (try? 存档路径(file).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            result = .整数(Int64(size))
        default:
            result = .文字([])
        }
        写入(target, result)
    }

    // MARK: - 声音

    func 执行SOUND(_ ins: YURIS指令) {
        guard let idArgument = 查参数(ins, "ID") else { return }
        let id = 文字(idArgument)
        var request = YURIS声音请求()
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": request.文件 = 求值(argument.表达式).显示文字
            case "E": request.启用 = 整数(argument) != 0
            case "PLAY": request.播放 = 整数(argument) != 0
            case "LOOP": request.循环 = 整数(argument)
            case "FADE": request.淡变 = 整数(argument)
            case "PAUSE": request.暂停 = 整数(argument) != 0
            case "START": request.开始 = 整数(argument)
            case "RESTART": request.重开 = 整数(argument)
            case "END": request.结束 = 整数(argument)
            case "VOLUME": request.音量 = 整数(argument)
            case "PAN": request.声像 = 整数(argument)
            case "PITCH": request.音高 = 整数(argument)
            default: break
            }
        }
        声音.执行(id: id, 请求: request, 资源: 程序.资源)
    }

    func 执行SOUNDEND(_ ins: YURIS指令) {
        if let argument = 查参数(ins, "ID") { 声音.删除(文字(argument)) }
    }

    func 执行SOUNDINFO(_ ins: YURIS指令) {
        var id: [UInt8] = []
        var target: YURIS引用 = .无
        var query = ""
        for argument in ins.参数 {
            switch argument.关键字 {
            case "ID": id = 文字(argument)
            case "LET": target = 求引用(argument.表达式)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        写入(target, 声音.查询(id: id, 项: query))
    }

    // MARK: - 影片和窗口

    /// 影片盖在所有图层上面，直到 MOVIEEND 才能再看到其他图层
    func 执行MOVIE(_ ins: YURIS指令) {
        var play: Bool?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "FILE": 影片.文件 = 求值(argument.表达式).显示文字
            case "X": 影片.x = 整数(argument)
            case "Y": 影片.y = 整数(argument)
            case "SX": 影片.宽 = 整数(argument)
            case "SY": 影片.高 = 整数(argument)
            case "VOLUME":
                影片.音量 = max(0, min(256, 整数(argument)))
                影片.播放器?.设音量(Float(影片.音量) / 256)
            case "PLAY": play = 整数(argument) != 0
            default: break
            }
        }
        画面.影片区域 = (影片.x, 影片.y, 影片.宽, 影片.高)
        if play == true {
            开始影片()
        } else if play == false {
            影片.播放器?.停止()
            影片.播放器 = nil
        }
    }

    private func 开始影片() {
        影片.播放器?.停止()
        影片.播放器 = nil
        // 打不开的格式（AVI、WMV 等）当作立即结束，脚本会接着往下走
        guard let data = 程序.资源.读取(影片.文件) else {
            日志("找不到影片：\(影片.文件)")
            return
        }
        guard let player = 视觉小说影片.打开(数据: data, 顺序: .argb, 声音: !虚拟时钟, 外部时钟: 影片时钟()) else {
            日志("放不了的影片：\(影片.文件)")
            return
        }
        日志("播放影片：\(影片.文件) \(player.宽)×\(player.高)")
        player.开始()
        player.设音量(Float(影片.音量) / 256)
        影片.播放器 = player
        画面.影片模式 = true
        画面.脏 = true
    }

    func 更新影片() {
        guard let frame = 影片.播放器?.取帧() else { return }
        画面.影片帧 = frame
        画面.脏 = true
    }

    func 结束影片() {
        停止图层影片()
        Flash接口?.关闭()
        MIDI接口?.停止()
        影片.播放器?.停止()
        影片.播放器 = nil
        画面.影片模式 = false
        画面.影片帧 = nil
        画面.脏 = true
    }

    func 暂停影片(_ paused: Bool) {
        影片.播放器?.暂停(paused)
        for item in 图层影片 { item.播放器.暂停(paused) }
        Flash接口?.暂停(paused)
    }

    func 执行MOVIEINFO(_ ins: YURIS指令) {
        var target: YURIS引用 = .无
        var query = ""
        for argument in ins.参数 {
            if argument.关键字 == "LET" {
                target = 求引用(argument.表达式)
            } else if 求值(argument.表达式).为真 {
                query = argument.关键字
            }
        }
        let value: Int
        switch query {
        case "PLAY": value = (影片.播放器.map { !$0.已结束 } ?? false) ? 1 : 0
        case "X": value = 影片.x
        case "Y": value = 影片.y
        case "SX": value = 影片.宽 ?? 画面.宽
        case "SY": value = 影片.高 ?? 画面.高
        case "VOLUME": value = 影片.音量
        default: value = 0
        }
        写入(target, .整数(Int64(value)))
    }

    func 执行WINDOW(_ ins: YURIS指令) {
        var number = 0
        for argument in ins.参数 where argument.关键字 == "NO" { number = 整数(argument) }
        guard number == 0 else { return }
        // WSX、WSY 是窗口尺寸，这里全屏显示，不用管
    }

    func 执行WINDOWINFO(_ ins: YURIS指令) {
        var number = 0
        var target: YURIS引用 = .无
        var query = ""
        for argument in ins.参数 {
            switch argument.关键字 {
            case "NO": number = 整数(argument)
            case "LET": target = 求引用(argument.表达式)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        let result: YURIS值
        switch query {
        case "EXIST", "E", "ACTIVE": result = .整数(number == 0 ? 1 : 0)
        case "SX", "WSX": result = .整数(Int64(画面.宽))
        case "SY", "WSY": result = .整数(Int64(画面.高))
        case "FULLSCREEN", "FULLSCREEN2": result = .整数(1)
        case "CAPTION": result = .文字(YURIS文本.编码(程序.窗口标题))
        default: result = .整数(0)
        }
        写入(target, result)
    }

    func 执行SYSTEM(_ ins: YURIS指令) {
        var width: Int?, height: Int?
        for argument in ins.参数 {
            switch argument.关键字 {
            case "SX": width = 整数(argument)
            case "SY": height = 整数(argument)
            default: break
            }
        }
        if let width, width > 0 { 画面.宽 = width }
        if let height, height > 0 { 画面.高 = height }
    }

    func 执行SYSTEMINFO(_ ins: YURIS指令) {
        var target: YURIS引用 = .无
        var query = ""
        var number = 0
        for argument in ins.参数 {
            switch argument.关键字 {
            case "LET": target = 求引用(argument.表达式)
            case "NO": number = 整数(argument)
            default:
                if 求值(argument.表达式).为真 { query = argument.关键字 }
            }
        }
        let result: YURIS值
        switch query {
        case "SCRIPTNUM": result = .整数(Int64(程序.资源.全部名称.filter { $0.hasPrefix("ysbin/yst") && $0.count == 18 }.count))
        case "SCRIPTFILE": result = .文字(Array(String(format: "yst%05d.yst", number).utf8))
        case "TEXTNUM":
            // 脚本里的文字行数
            let script = 程序.脚本(number)
            let count = script?.指令.reduce(0) { $0 + ($1.种类 == .行结束 ? 1 : 0) } ?? 0
            result = .整数(Int64(count))
        default:
            result = .整数(0)
        }
        写入(target, result)
    }

    func 执行LABELINFO(_ ins: YURIS指令) {
        var name: [UInt8] = []
        var target: YURIS引用 = .无
        for argument in ins.参数 {
            switch argument.关键字 {
            case "#": name = 文字(argument)
            case "LET": target = 求引用(argument.表达式)
            default: break
            }
        }
        写入(target, .整数(查标签(name) == nil ? 0 : 1))
    }

    func 执行DIALOG(_ ins: YURIS指令) {
        var title = "", message = ""
        var kind = 0
        var target: YURIS引用 = .无
        for argument in ins.参数 {
            switch argument.关键字 {
            case "CAPTION": title = 求值(argument.表达式).显示文字
            case "STR": message = 求值(argument.表达式).显示文字
            case "YESNO": if 求值(argument.表达式).为真 { kind = 1 }
            case "OKCANCEL": if 求值(argument.表达式).为真 { kind = 2 }
            case "YESNOCANCEL": if 求值(argument.表达式).为真 { kind = 3 }
            case "LET": target = 求引用(argument.表达式)
            default: break
            }
        }
        let answer = 对话框?(YURIS对话框请求(标题: title, 内容: message, 类型: kind)) ?? 1
        写入(target, .整数(Int64(answer)))
    }

    /// 只把 LET 清零（平台上没有的信息）
    func 执行空信息(_ ins: YURIS指令) {
        for argument in ins.参数 where argument.关键字 == "LET" {
            let reference = 求引用(argument.表达式)
            switch reference {
            case .标量(let variable):
                写入(reference, Self.默认值(variable.类型))
            case .元素(let variable, _):
                写入(reference, Self.默认值(variable.类型))
            default:
                break
            }
        }
    }
}

/// 存档文件：自己的简单二进制格式（不需要跟 Windows 版互通）
nonisolated enum YURIS存档编码 {
    private static let 魔数: [UInt8] = Array("PVYS".utf8)

    static func 编码(_ entries: [Int: YURIS存档项]) -> Data {
        var out = Data(魔数)
        func u32(_ value: Int) {
            var v = UInt32(truncatingIfNeeded: value).littleEndian
            withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        }
        func u64(_ value: UInt64) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { out.append(contentsOf: $0) }
        }
        u32(entries.count)
        for (number, entry) in entries {
            u32(number)
            switch entry {
            case .值(let dims, let elements):
                out.append(0)
                u32(dims.count)
                for dim in dims { u32(dim) }
                u32(elements.count)
                for element in elements {
                    switch element {
                    case .整数(let value):
                        out.append(1)
                        u64(UInt64(bitPattern: value))
                    case .小数(let value):
                        out.append(2)
                        u64(value.bitPattern)
                    case .文字(let bytes):
                        out.append(3)
                        u32(bytes.count)
                        out.append(contentsOf: bytes)
                    }
                }
            case .图片(let data):
                out.append(1)
                u32(data.count)
                out.append(data)
            }
        }
        return out
    }

    static func 解码(_ data: Data) -> [Int: YURIS存档项]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<4]) == 魔数 else { return nil }
        var p = 4
        func u32() -> Int? {
            guard p + 4 <= bytes.count else { return nil }
            defer { p += 4 }
            return Int(bytes[p]) | Int(bytes[p + 1]) << 8 | Int(bytes[p + 2]) << 16 | Int(bytes[p + 3]) << 24
        }
        func u64() -> UInt64? {
            guard p + 8 <= bytes.count else { return nil }
            var value: UInt64 = 0
            for i in 0..<8 { value |= UInt64(bytes[p + i]) << UInt64(8 * i) }
            p += 8
            return value
        }
        guard let count = u32() else { return nil }
        var entries: [Int: YURIS存档项] = [:]
        for _ in 0..<count {
            guard let number = u32(), p < bytes.count else { return entries }
            let kind = bytes[p]; p += 1
            if kind == 0 {
                guard let dimCount = u32() else { return entries }
                var dims: [Int] = []
                for _ in 0..<dimCount { guard let dim = u32() else { return entries }; dims.append(dim) }
                guard let elementCount = u32() else { return entries }
                var elements: [YURIS值] = []
                elements.reserveCapacity(elementCount)
                for _ in 0..<elementCount {
                    guard p < bytes.count else { return entries }
                    let type = bytes[p]; p += 1
                    switch type {
                    case 1:
                        guard let value = u64() else { return entries }
                        elements.append(.整数(Int64(bitPattern: value)))
                    case 2:
                        guard let value = u64() else { return entries }
                        elements.append(.小数(Double(bitPattern: value)))
                    default:
                        guard let length = u32(), p + length <= bytes.count else { return entries }
                        elements.append(.文字(Array(bytes[p..<(p + length)])))
                        p += length
                    }
                }
                entries[number] = .值(维度: dims, 元素: elements)
            } else {
                guard let length = u32(), p + length <= bytes.count else { return entries }
                entries[number] = .图片(Data(bytes[p..<(p + length)]))
                p += length
            }
        }
        return entries
    }

    static func 编码图片(_ image: YURIS图像) -> Data? {
        guard let cg = image.转CGImage() else { return nil }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}
