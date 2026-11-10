import Accelerate
import AVFoundation
import Foundation
import PaperVNMPEG
import os

/// 一帧解码好的 YUV420P（有限范围的 BT.601），指针到下一次解码为止有效
nonisolated struct 影片帧数据 {
    var 时间 = 0.0
    var y: UnsafePointer<UInt8>?
    var cb: UnsafePointer<UInt8>?
    var cr: UnsafePointer<UInt8>?
    var y行宽 = 0
    var c行宽 = 0
}

/// 播放器和具体解码器之间的接口：MPEG-1 用 pl_mpeg，其他格式用 FFmpeg
nonisolated protocol 影片解码后端: AnyObject {
    var 宽: Int { get }
    var 高: Int { get }
    var 帧长: Double { get }
    /// 没有声音时是 0
    var 采样率: Double { get }
    var 音频偏移: Double { get }
    func 下一帧时间() -> Double
    /// 1：帧有效；0：这次没有画面；-1：结束
    func 解码视频(跳过: Bool, 帧: inout 影片帧数据) -> Int
    /// 再读一个数据包。文件读完时返回 false。
    func 读包() -> Bool
    /// 解码一段声音（交错的立体声）。没有完整的一段时返回 false。
    func 解码音频(_ output: (UnsafePointer<Float>, Int) -> Void) -> Bool
}

/// YU-RIS 和 NScripter 共用的影片播放器。解码在自己的线程上，界面每帧调用“取帧”拿到该显示的画面。
/// 有声音时以声音为时钟，解码跟不上就先跳过不被参考的帧，声音不会被拖慢。
nonisolated final class 视觉小说影片: @unchecked Sendable {
    final class 帧: @unchecked Sendable {
        let 宽: Int
        let 高: Int
        let 像素: UnsafeMutablePointer<UInt8>
        fileprivate(set) var 时间 = 0.0

        fileprivate init(宽: Int, 高: Int) {
            self.宽 = 宽
            self.高 = 高
            像素 = .allocate(capacity: 宽 * 高 * 4)
        }

        deinit { 像素.deallocate() }
    }

    /// 内存里的通道顺序
    enum 像素顺序 {
        case argb
        case bgra

        fileprivate var 映射: [UInt8] {
            switch self {
            case .argb: [0, 1, 2, 3]
            case .bgra: [3, 2, 1, 0]
            }
        }
    }

    /// MPEG-1 以外的格式。App 里设成 FFmpeg（命令行测试工具没有）
    nonisolated(unsafe) static var 其他格式后端: ((NSData, Bool) -> (any 影片解码后端)?)?

    let 宽: Int
    let 高: Int
    private let 帧长: Double
    private let 后端: any 影片解码后端
    private let 外部时钟: (() -> Double)?
    private let 通道映射: [UInt8]
    private var 转换信息 = vImage_YpCbCrToARGB()

    private let lock = NSLock()
    private var 队列: [帧] = []
    private var 空闲帧: [帧] = []
    private var 上次取出: 帧?
    private var 已停止 = false
    private var 已暂停 = false
    private var 视频已结束 = false
    private var 全部结束 = false
    private var 线程已启动 = false
    private static let 队列长度 = 3

    // 声音
    private let 采样率: Double
    private let 音频偏移: Double
    private let 环: MPEG1音频环?
    private var 音频已读完 = false
    private var 引擎: AVAudioEngine?
    private var 观察: [NSObjectProtocol] = []

    // 没有声音、或者声音放完了之后，用墙上时钟
    private var 墙钟累计 = 0.0
    private var 墙钟起点: Date?

    /// 先试 MPEG-1，再试其他格式。都打不开时返回 nil。
    static func 打开(数据 data: Data, 顺序: 像素顺序, 声音: Bool = true, 外部时钟: (() -> Double)? = nil) -> 视觉小说影片? {
        let storage = data as NSData
        guard let backend = MPEG1后端(数据: storage, 声音: 声音) ?? 其他格式后端?(storage, 声音) else { return nil }
        return 视觉小说影片(后端: backend, 顺序: 顺序, 外部时钟: 外部时钟)
    }

    /// 外部时钟用于测试：取帧会等到对应的画面解出来，不丢帧
    private init?(后端 backend: any 影片解码后端, 顺序: 像素顺序, 外部时钟: (() -> Double)?) {
        后端 = backend
        // 4:2:0 的画面宽高要是偶数
        宽 = backend.宽 & ~1
        高 = backend.高 & ~1
        帧长 = backend.帧长
        self.外部时钟 = 外部时钟
        通道映射 = 顺序.映射
        采样率 = backend.采样率
        音频偏移 = backend.音频偏移
        环 = backend.采样率 > 0 ? MPEG1音频环(帧数: Int(backend.采样率)) : nil

        var range = vImage_YpCbCrPixelRange(Yp_bias: 16, CbCr_bias: 128, YpRangeMax: 235, CbCrRangeMax: 240,
                                            YpMax: 255, YpMin: 0, CbCrMax: 255, CbCrMin: 0)
        var matrix = vImage_YpCbCrToARGBMatrix(Yp: 1, Cr_R: 1.402, Cr_G: -0.714136, Cb_G: -0.344136, Cb_B: 1.772)
        guard 宽 > 0, 高 > 0,
              vImageConvert_YpCbCrToARGB_GenerateConversion(&matrix, &range, &转换信息,
                                                            kvImage420Yp8_Cb8_Cr8, kvImageARGB8888,
                                                            vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
            return nil
        }
    }

    // MARK: - 控制

    func 开始() {
        lock.lock()
        let started = 线程已启动
        线程已启动 = true
        lock.unlock()
        guard !started else { return }
        启动声音()
        lock.lock()
        墙钟起点 = Date()
        lock.unlock()
        let thread = Thread { [self] in 解码循环() }
        thread.name = "MPEG-1"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// 播放结束或不再需要时一定要调用，否则解码线程不会退出
    func 停止() {
        lock.lock()
        已停止 = true
        lock.unlock()
        观察.forEach(NotificationCenter.default.removeObserver)
        观察 = []
        lock.lock()
        let engine = 引擎
        引擎 = nil
        lock.unlock()
        engine?.stop()
    }

    func 暂停(_ paused: Bool) {
        lock.lock()
        let changed = 已暂停 != paused
        已暂停 = paused
        if changed {
            if paused {
                if let start = 墙钟起点 { 墙钟累计 += Date().timeIntervalSince(start) }
                墙钟起点 = nil
            } else {
                墙钟起点 = Date()
            }
        }
        lock.unlock()
        guard changed else { return }
        lock.lock()
        let engine = 引擎
        lock.unlock()
        if paused { engine?.pause() } else { try? engine?.start() }
    }

    /// 0～1
    func 设音量(_ value: Float) {
        lock.lock()
        let engine = 引擎
        lock.unlock()
        engine?.mainMixerNode.outputVolume = value
    }

    var 已结束: Bool {
        lock.lock()
        defer { lock.unlock() }
        return 全部结束
    }

    /// 现在该显示的帧；和上次一样时返回 nil。上一次取到的帧在这次调用之后就不能再用了。
    func 取帧() -> 帧? {
        let time = 时钟()
        lock.lock()
        defer { lock.unlock() }
        if 外部时钟 != nil {
            // 测试：等解码线程赶上
            while (队列.last?.时间 ?? -1) < time, !视频已结束, !已停止 {
                lock.unlock()
                Thread.sleep(forTimeInterval: 0.001)
                lock.lock()
            }
        }
        var result: 帧?
        while let first = 队列.first, first.时间 <= time + 帧长 / 2 {
            队列.removeFirst()
            if let skipped = result { 空闲帧.append(skipped) }
            result = first
        }
        guard let result else { return nil }
        if let previous = 上次取出 { 空闲帧.append(previous) }
        上次取出 = result
        return result
    }

    // MARK: - 时钟

    private func 时钟() -> Double {
        if let 外部时钟 { return 外部时钟() }
        lock.lock()
        defer { lock.unlock() }
        let wall = 墙钟累计 + (墙钟起点.map { Date().timeIntervalSince($0) } ?? 0)
        guard let 环, 引擎 != nil else { return wall }
        let (played, remaining) = 环.状态()
        let audio = Double(played) / 采样率 + 音频偏移 - (引擎?.outputNode.presentationLatency ?? 0)
        // 声音放完了视频还有：接着走墙上时钟
        if 音频已读完, remaining == 0 {
            if 声音结束时 == nil { 声音结束时 = (audio, wall) }
            return 声音结束时!.0 + wall - 声音结束时!.1
        }
        return max(0, audio)
    }

    private var 声音结束时: (Double, Double)?

    // MARK: - 声音

    private func 启动声音() {
        guard let 环, 外部时钟 == nil,
              let format = AVAudioFormat(standardFormatWithSampleRate: 采样率, channels: 2) else { return }
        let engine = AVAudioEngine()
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, list -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            环.读取(left, right, 帧数: Int(frameCount))
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        引擎 = engine
        // 耳机拔出、来电等情况系统会停掉引擎，不恢复的话时钟也跟着停
        let center = NotificationCenter.default
        观察.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.恢复引擎()
        })
        #if os(iOS)
        观察.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.恢复引擎()
        })
        #endif
    }

    private func 恢复引擎() {
        lock.lock()
        let paused = 已暂停 || 已停止
        let engine = 引擎
        lock.unlock()
        guard !paused, let engine, !engine.isRunning else { return }
        try? engine.start()
    }

    private func 补充音频() {
        guard let 环, !音频已读完 else { return }
        let target = Int(采样率 / 2)
        while 环.可写帧数() >= 2304 {
            if 后端.解码音频({ 环.写入($0, 帧数: $1) }) { continue }
            if 环.状态().剩余 >= target { break }
            if !后端.读包() {
                // 文件读完，最后再解一次
                while 环.可写帧数() >= 2304, 后端.解码音频({ 环.写入($0, 帧数: $1) }) {}
                lock.lock()
                音频已读完 = true
                lock.unlock()
                break
            }
        }
    }

    /// 测试用：不播放，把声音全部解码。返回交错的立体声。
    func 解码全部声音() -> (采样: [Float], 采样率: Double) {
        var result: [Float] = []
        while true {
            if 后端.解码音频({ result.append(contentsOf: UnsafeBufferPointer(start: $0, count: $1 * 2)) }) { continue }
            if !后端.读包() { break }
        }
        return (result, 采样率)
    }

    // MARK: - 解码线程

    private func 解码循环() {
        var lastShown = -Double.infinity
        let exact = 外部时钟 != nil
        while true {
            lock.lock()
            let stopped = 已停止, paused = 已暂停, videoEnded = 视频已结束
            let hasRoom = 队列.count < Self.队列长度
            let queueEmpty = 队列.isEmpty
            let audioDone = 环 == nil || 音频已读完
            lock.unlock()
            if stopped {
                打印统计()
                return
            }
            if paused {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }
            补充音频()
            if videoEnded {
                if queueEmpty, audioDone, (环?.状态().剩余 ?? 0) == 0 {
                    lock.lock()
                    全部结束 = true
                    lock.unlock()
                    打印统计()
                    return
                }
                Thread.sleep(forTimeInterval: 0.005)
                continue
            }
            guard hasRoom else {
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            let now = exact ? 0 : 时钟()
            let late = exact ? 0 : now - 后端.下一帧时间()
            var frame = 影片帧数据()
            #if DEBUG
            let decodeStart = Date()
            #endif
            let result = 后端.解码视频(跳过: late > 帧长 * 2, 帧: &frame)
            #if DEBUG
            统计解码秒数 += Date().timeIntervalSince(decodeStart)
            if result == 0 { 统计跳过B帧 += 1 }
            #endif
            switch result {
            case 1:
                // 晚了就不转换颜色，但至少每 0.1 秒更新一次画面
                if !exact, now - frame.时间 > 帧长 * 1.5, now - lastShown < 0.1 {
                    #if DEBUG
                    统计丢帧 += 1
                    #endif
                    break
                }
                lastShown = now
                #if DEBUG
                统计显示 += 1
                #endif
                提交(frame)
            case -1:
                lock.lock()
                视频已结束 = true
                lock.unlock()
            default:
                break
            }
        }
    }

    #if DEBUG
    private var 统计显示 = 0
    private var 统计丢帧 = 0
    private var 统计跳过B帧 = 0
    private var 统计解码秒数 = 0.0
    #endif

    private func 打印统计() {
        #if DEBUG
        let frames = 统计显示 + 统计丢帧
        print("[影片] \(宽)×\(高) \(1 / 帧长) 帧/秒，显示 \(统计显示)，丢 \(统计丢帧)，跳过 B 帧 \(统计跳过B帧)，"
              + "每帧解码 \(统计解码秒数 / Double(max(frames, 1)) * 1000) ms，时钟 \(时钟()) 秒，已放声音 \(Double(环?.状态().已放 ?? 0) / max(采样率, 1)) 秒")
        #endif
    }

    private func 提交(_ frame: 影片帧数据) {
        lock.lock()
        let target = 空闲帧.popLast() ?? 帧(宽: 宽, 高: 高)
        lock.unlock()
        var y = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: frame.y), height: vImagePixelCount(高),
                              width: vImagePixelCount(宽), rowBytes: frame.y行宽)
        var cb = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: frame.cb), height: vImagePixelCount(高 / 2),
                               width: vImagePixelCount(宽 / 2), rowBytes: frame.c行宽)
        var cr = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: frame.cr), height: vImagePixelCount(高 / 2),
                               width: vImagePixelCount(宽 / 2), rowBytes: frame.c行宽)
        var output = vImage_Buffer(data: target.像素, height: vImagePixelCount(高),
                                   width: vImagePixelCount(宽), rowBytes: 宽 * 4)
        vImageConvert_420Yp8_Cb8_Cr8ToARGB8888(&y, &cb, &cr, &output, &转换信息, 通道映射, 255, vImage_Flags(kvImageDoNotTile))
        target.时间 = frame.时间
        lock.lock()
        队列.append(target)
        lock.unlock()
    }
}

/// MPEG-1 后端：pl_mpeg 解视频和 MP2，MP3 交给系统解码器
private nonisolated final class MPEG1后端: 影片解码后端 {
    private let 数据: NSData
    private let 解码器: OpaquePointer
    private var mp3解码器: MPEG1MP3解码器?
    private let 音频层: Int32
    let 宽: Int
    let 高: Int
    let 帧长: Double
    let 采样率: Double
    let 音频偏移: Double

    init?(数据 storage: NSData, 声音: Bool) {
        guard let handle = papervn_mpeg_open(storage.bytes, storage.length, 声音 ? 1 : 0) else { return nil }
        数据 = storage
        解码器 = handle
        宽 = Int(papervn_mpeg_width(handle))
        高 = Int(papervn_mpeg_height(handle))
        let framerate = papervn_mpeg_framerate(handle)
        帧长 = framerate > 0 ? 1 / framerate : 1.0 / 30

        var layer = papervn_mpeg_audio_layer(handle)
        var rate = 0.0
        if layer == 2 {
            rate = Double(papervn_mpeg_mp2_samplerate(handle))
            if rate <= 0 {
                // 第一帧的头还没进来
                for _ in 0..<256 where rate <= 0 {
                    guard papervn_mpeg_pump(handle) != 0 else { break }
                    if papervn_mpeg_decode_mp2(handle) != nil {
                        rate = Double(papervn_mpeg_mp2_samplerate(handle))
                    }
                }
            }
        } else if layer == 3 {
            for _ in 0..<256 {
                var length = 0
                let bytes = papervn_mpeg_audio_bytes(handle, &length)
                if let header = bytes.flatMap({ MPEG1MP3帧.查找(UnsafeBufferPointer(start: $0, count: length)) }) {
                    mp3解码器 = MPEG1MP3解码器(采样率: header.帧.采样率, 声道数: header.帧.声道数)
                    rate = Double(header.帧.采样率)
                    break
                }
                guard papervn_mpeg_pump(handle) != 0 else { break }
            }
        }
        if rate <= 0 || (layer == 3 && mp3解码器 == nil) { layer = 0 }
        音频层 = layer
        采样率 = layer != 0 ? rate : 0
        音频偏移 = papervn_mpeg_audio_offset(handle)
    }

    deinit { papervn_mpeg_close(解码器) }

    func 下一帧时间() -> Double { papervn_mpeg_next_time(解码器) }
    func 读包() -> Bool { papervn_mpeg_pump(解码器) != 0 }

    func 解码视频(跳过: Bool, 帧: inout 影片帧数据) -> Int {
        var frame = papervn_mpeg_frame()
        let result = Int(papervn_mpeg_decode_video(解码器, 跳过 ? 1 : 0, &frame))
        if result == 1 {
            帧 = 影片帧数据(时间: frame.time, y: frame.y, cb: frame.cb, cr: frame.cr,
                         y行宽: Int(frame.y_stride), c行宽: Int(frame.c_stride))
        }
        return result
    }

    func 解码音频(_ output: (UnsafePointer<Float>, Int) -> Void) -> Bool {
        if 音频层 == 2 {
            guard let samples = papervn_mpeg_decode_mp2(解码器) else { return false }
            output(samples, Int(PAPERVN_MPEG_MP2_FRAMES))
            return true
        }
        guard let mp3解码器 else { return false }
        var length = 0
        guard let bytes = papervn_mpeg_audio_bytes(解码器, &length), length > 0 else { return false }
        let buffer = UnsafeBufferPointer(start: bytes, count: length)
        guard let found = MPEG1MP3帧.查找(buffer) else {
            // 没有完整的帧；同步字之前的垃圾可以丢掉
            if length > 8192 { papervn_mpeg_audio_consume(解码器, length - 4096) }
            return false
        }
        mp3解码器.解码(UnsafeBufferPointer(rebasing: buffer[found.位置..<(found.位置 + found.帧.字节数)]), output)
        papervn_mpeg_audio_consume(解码器, found.位置 + found.帧.字节数)
        return true
    }
}

/// 解码线程写、音频线程读。锁只保护几次拷贝，不会卡住音频线程。
private nonisolated final class MPEG1音频环: @unchecked Sendable {
    private let 容量: Int
    private let 采样: UnsafeMutablePointer<Float>
    private let 锁: UnsafeMutablePointer<os_unfair_lock>
    private var 读位置 = 0
    private var 数量 = 0
    private var 已读 = 0

    init(帧数: Int) {
        容量 = max(帧数, 4096)
        采样 = .allocate(capacity: 容量 * 2)
        锁 = .allocate(capacity: 1)
        锁.initialize(to: os_unfair_lock())
    }

    deinit {
        采样.deallocate()
        锁.deallocate()
    }

    func 状态() -> (已放: Int, 剩余: Int) {
        os_unfair_lock_lock(锁)
        defer { os_unfair_lock_unlock(锁) }
        return (已读, 数量)
    }

    func 可写帧数() -> Int {
        os_unfair_lock_lock(锁)
        defer { os_unfair_lock_unlock(锁) }
        return 容量 - 数量
    }

    func 写入(_ source: UnsafePointer<Float>, 帧数: Int) {
        os_unfair_lock_lock(锁)
        defer { os_unfair_lock_unlock(锁) }
        let count = min(帧数, 容量 - 数量)
        var position = (读位置 + 数量) % 容量
        for i in 0..<count {
            采样[position * 2] = source[i * 2]
            采样[position * 2 + 1] = source[i * 2 + 1]
            position = position + 1 == 容量 ? 0 : position + 1
        }
        数量 += count
    }

    func 读取(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, 帧数: Int) {
        os_unfair_lock_lock(锁)
        defer { os_unfair_lock_unlock(锁) }
        let count = min(帧数, 数量)
        for i in 0..<count {
            left[i] = 采样[读位置 * 2]
            right[i] = 采样[读位置 * 2 + 1]
            读位置 = 读位置 + 1 == 容量 ? 0 : 读位置 + 1
        }
        数量 -= count
        已读 += count
        // 供不上时补静音，时钟也不走，画面会等声音
        for i in count..<max(count, 帧数) {
            left[i] = 0
            right[i] = 0
        }
    }
}

/// MP3 的帧头
private nonisolated struct MPEG1MP3帧 {
    let 字节数: Int
    let 采样率: Int
    let 声道数: Int

    private static let 码率1: [Int] = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
    private static let 码率2: [Int] = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0]
    private static let 采样率表: [Int] = [44100, 48000, 32000, 0]

    init?(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        guard a == 0xFF, b & 0xE0 == 0xE0, (b >> 1) & 3 == 1 else { return nil }
        let version = (b >> 3) & 3
        guard version != 1 else { return nil }
        let mpeg1 = version == 3
        let bitrate = (mpeg1 ? Self.码率1 : Self.码率2)[Int(c >> 4)]
        var rate = Self.采样率表[Int((c >> 2) & 3)]
        guard bitrate > 0, rate > 0 else { return nil }
        if version == 2 { rate /= 2 }
        if version == 0 { rate /= 4 }
        let padding = Int((c >> 1) & 1)
        字节数 = (mpeg1 ? 144 : 72) * bitrate * 1000 / rate + padding
        采样率 = rate
        声道数 = (d >> 6) == 3 ? 1 : 2
    }

    /// 第一个完整的帧
    static func 查找(_ bytes: UnsafeBufferPointer<UInt8>) -> (位置: Int, 帧: MPEG1MP3帧)? {
        var i = 0
        while i + 4 <= bytes.count {
            if let frame = MPEG1MP3帧(bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]) {
                return i + frame.字节数 <= bytes.count ? (i, frame) : nil
            }
            i += 1
        }
        return nil
    }
}

/// 系统的 MP3 解码器
private nonisolated final class MPEG1MP3解码器 {
    private let 转换器: AVAudioConverter
    private let 输入: AVAudioCompressedBuffer
    private let 输出: AVAudioPCMBuffer
    private let 声道数: Int
    private var 交错: [Float]

    init?(采样率: Int, 声道数: Int) {
        var description = AudioStreamBasicDescription(
            mSampleRate: Double(采样率), mFormatID: kAudioFormatMPEGLayer3, mFormatFlags: 0, mBytesPerPacket: 0,
            mFramesPerPacket: 采样率 >= 32000 ? 1152 : 576, mBytesPerFrame: 0, mChannelsPerFrame: UInt32(声道数),
            mBitsPerChannel: 0, mReserved: 0)
        guard let input = AVAudioFormat(streamDescription: &description),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(采样率),
                                         channels: AVAudioChannelCount(声道数), interleaved: false),
              let converter = AVAudioConverter(from: input, to: output),
              let pcm = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 4096) else { return nil }
        转换器 = converter
        输入 = AVAudioCompressedBuffer(format: input, packetCapacity: 1, maximumPacketSize: 4096)
        输出 = pcm
        self.声道数 = 声道数
        交错 = [Float](repeating: 0, count: 8192)
    }

    func 解码(_ packet: UnsafeBufferPointer<UInt8>, _ sink: (UnsafePointer<Float>, Int) -> Void) {
        guard let source = packet.baseAddress, packet.count <= Int(输入.maximumPacketSize) else { return }
        memcpy(输入.data, source, packet.count)
        输入.byteLength = UInt32(packet.count)
        输入.packetCount = 1
        输入.packetDescriptions?.pointee = AudioStreamPacketDescription(
            mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: UInt32(packet.count))
        var given = false
        var error: NSError?
        let input = 输入
        输出.frameLength = 0
        _ = 转换器.convert(to: 输出, error: &error) { _, status in
            if given {
                status.pointee = .noDataNow
                return nil
            }
            given = true
            status.pointee = .haveData
            return input
        }
        let count = Int(输出.frameLength)
        guard count > 0, let channels = 输出.floatChannelData else { return }
        let left = channels[0], right = channels[声道数 > 1 ? 1 : 0]
        for i in 0..<count {
            交错[i * 2] = left[i]
            交错[i * 2 + 1] = right[i]
        }
        交错.withUnsafeBufferPointer { sink($0.baseAddress!, count) }
    }
}
