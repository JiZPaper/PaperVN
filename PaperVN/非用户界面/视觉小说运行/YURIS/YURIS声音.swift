import AVFoundation
import Foundation

nonisolated struct YURIS声音请求 {
    var 文件: String?
    var 启用: Bool?
    var 播放: Bool?
    var 循环: Int?
    var 淡变: Int?
    var 暂停: Bool?
    var 开始: Int?
    var 重开: Int?
    var 结束: Int?
    var 音量: Int?
    var 声像: Int?
    var 音高: Int?
}

/// 解码好的音频流（交错 Float32）
nonisolated protocol YURIS音频流: AnyObject {
    var 采样率: Double { get }
    var 声道数: Int { get }
    var 总帧数: Int64 { get }
    func 读取(_ buffer: UnsafeMutablePointer<Float>, 帧数: Int) -> Int
    func 定位(_ frame: Int64)
}

/// WAVE（PCM 8/16 位）
nonisolated final class YURISWave流: YURIS音频流 {
    let 采样率: Double
    let 声道数: Int
    let 总帧数: Int64
    private let data: Data
    private let 数据开始: Int
    private let 字节每样本: Int
    private var 位置: Int64 = 0

    init?(data: Data) {
        guard data.count > 44, data.prefix(4) == Data("RIFF".utf8) else { return nil }
        var p = 12
        var channels = 0, rate = 0, bits = 0, start = 0, size = 0
        while p + 8 <= data.count {
            let id = data.subdata(in: (data.startIndex + p)..<(data.startIndex + p + 4))
            let length = Int(data.读UInt32(p + 4))
            if id == Data("fmt ".utf8), p + 24 <= data.count {
                guard data.读UInt16(p + 8) == 1 else { return nil }
                channels = Int(data.读UInt16(p + 10))
                rate = Int(data.读UInt32(p + 12))
                bits = Int(data.读UInt16(p + 22))
            } else if id == Data("data".utf8) {
                start = p + 8
                size = min(length, data.count - start)
                break
            }
            p += 8 + length + (length & 1)
        }
        guard channels > 0, rate > 0, bits == 8 || bits == 16, start > 0 else { return nil }
        self.data = data
        采样率 = Double(rate)
        声道数 = channels
        数据开始 = start
        字节每样本 = bits / 8
        总帧数 = Int64(size / (channels * bits / 8))
    }

    func 读取(_ buffer: UnsafeMutablePointer<Float>, 帧数: Int) -> Int {
        let count = min(Int64(帧数), 总帧数 - 位置)
        guard count > 0 else { return 0 }
        let samples = Int(count) * 声道数
        var offset = data.startIndex + 数据开始 + Int(位置) * 声道数 * 字节每样本
        for i in 0..<samples {
            if 字节每样本 == 1 {
                buffer[i] = (Float(data[offset]) - 128) / 128
                offset += 1
            } else {
                let value = Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
                buffer[i] = Float(value) / 32768
                offset += 2
            }
        }
        位置 += count
        return Int(count)
    }

    func 定位(_ frame: Int64) {
        位置 = max(0, min(总帧数, frame))
    }
}

nonisolated final class YURIS声音层 {
    let 路径: [[UInt8]]
    var 是集合: Bool
    var 文件 = ""
    var 启用 = true
    var 循环 = 1
    var 开始 = 0
    var 重开 = 0
    var 结束 = 0
    var 音量 = 256
    var 声像 = 256
    var 音高 = 256

    var 流: (any YURIS音频流)?
    var 播放中 = false
    var 暂停中 = false
    var 已循环 = 0
    var 下一帧: Int64 = 0
    var 已排帧: Int64 = 0
    var 循环内已排帧: Int64 = 0
    var 播放器: AVAudioPlayerNode?
    var 变速: AVAudioUnitVarispeed?
    var 已连接格式: AVAudioFormat?
    /// 没有音频引擎时（命令行测试）靠时钟估算进度
    var 开始时间: Date?
    var 暂停时累计: Double = 0

    // 淡入淡出
    var 淡变开始 = Date.distantPast
    var 淡变时长 = 0.0
    var 淡变起点 = 1.0
    var 淡变终点 = 1.0
    var 淡变后停止 = false

    init(路径: [[UInt8]], 是集合: Bool) {
        self.路径 = 路径
        self.是集合 = 是集合
    }
}

/// SOUND 系列命令。图层 ID 跟 CG 一样是路径（`:/S0/`、`SSE/SSSE11`），集合的音量会乘到子层。
nonisolated final class YURIS声音: @unchecked Sendable {
    typealias 解码器 = (Data) -> (any YURIS音频流)?

    private var 层: [[[UInt8]]: YURIS声音层] = [:]
    private var 引擎: AVAudioEngine?
    private let ogg解码: 解码器?
    private let 使用引擎: Bool
    private static let 块帧数: Int64 = 22050
    private static let 预排秒数 = 1.0

    init(ogg解码: 解码器?, 使用引擎: Bool) {
        self.ogg解码 = ogg解码
        self.使用引擎 = 使用引擎
    }

    private func 规范路径(_ id: [UInt8]) -> (parts: [[UInt8]], isSet: Bool) {
        var bytes = id[...]
        if bytes.first == 0x3A {
            bytes = bytes.dropFirst()
            if bytes.first == 0x2F { bytes = bytes.dropFirst() }
        }
        let isSet = bytes.last == 0x2F
        var parts: [[UInt8]] = []
        var current: [UInt8] = []
        for c in bytes {
            if c == 0x2F || c == 0x5C {
                if !current.isEmpty { parts.append(current); current = [] }
            } else {
                current.append(c >= 0x61 && c <= 0x7A ? c - 0x20 : c)
            }
        }
        if !current.isEmpty { parts.append(current) }
        // 相对路径都在 S0 下
        if parts.first != Array("S0".utf8) { parts.insert(Array("S0".utf8), at: 0) }
        return (parts, isSet)
    }

    private func 启动引擎() -> AVAudioEngine? {
        guard 使用引擎 else { return nil }
        if let 引擎 {
            if !引擎.isRunning { try? 引擎.start() }
            return 引擎
        }
        let engine = AVAudioEngine()
        _ = engine.mainMixerNode
        engine.prepare()
        do {
            try engine.start()
        } catch {
            return nil
        }
        引擎 = engine
        return engine
    }

    func 执行(id: [UInt8], 请求 request: YURIS声音请求, 资源: YURIS资源库) {
        let (parts, isSet) = 规范路径(id)
        let layer: YURIS声音层
        if let existing = 层[parts] {
            layer = existing
        } else {
            layer = YURIS声音层(路径: parts, 是集合: isSet)
            层[parts] = layer
        }
        if let file = request.文件 { 载入(layer, file, 资源: 资源) }
        if let value = request.启用 { layer.启用 = value }
        if let value = request.循环 { layer.循环 = value }
        if let value = request.开始 { layer.开始 = value }
        if let value = request.重开 { layer.重开 = value }
        if let value = request.结束 { layer.结束 = value }
        if let value = request.声像 { layer.声像 = value }
        if let value = request.音高 { layer.音高 = value }
        let fade = request.淡变 ?? 0
        if let value = request.音量 {
            if fade > 0, layer.播放中 || request.播放 == true {
                开始淡变(layer, 到: Double(value) / 256, 时长: fade, 结束后停止: false)
                layer.音量 = value
            } else {
                layer.音量 = value
                layer.淡变时长 = 0
                layer.淡变终点 = 1
                layer.淡变起点 = 1
            }
        }
        if let pause = request.暂停 { 设暂停(layer, pause) }
        if let play = request.播放 {
            if play {
                if layer.播放中, fade > 0, request.文件 == nil {
                    // 播放中再次 PLAY=1 + FADE 只是改音量
                } else {
                    开始播放(layer, 淡入: fade)
                }
            } else if fade > 0, layer.播放中 {
                开始淡变(layer, 到: 0, 时长: fade, 结束后停止: true)
            } else {
                停止(layer)
            }
        }
        应用音量()
    }

    private func 载入(_ layer: YURIS声音层, _ file: String, 资源: YURIS资源库) {
        停止(layer)
        layer.文件 = file
        layer.流 = nil
        let name = file.replacingOccurrences(of: "\\", with: "/")
        var candidates: [String] = []
        // 路径可能省略大类目录（SE/SYS001 实际在 se/）
        candidates.append(name)
        candidates.append("\(name).ogg")
        candidates.append("\(name).wav")
        for candidate in candidates where 资源.存在(candidate) {
            guard let data = 资源.读取(candidate), data.count > 4 else { continue }
            if data.prefix(4) == Data("RIFF".utf8) {
                layer.流 = YURISWave流(data: data)
            } else if data.prefix(4) == Data("OggS".utf8) {
                layer.流 = ogg解码?(data) ?? YURISOgg信息流(data: data)
            }
            return
        }
    }

    private func 开始淡变(_ layer: YURIS声音层, 到 target: Double, 时长 ms: Int, 结束后停止 stop: Bool) {
        layer.淡变起点 = 当前淡变值(layer)
        layer.淡变终点 = target
        layer.淡变开始 = Date()
        layer.淡变时长 = Double(ms) / 1000
        layer.淡变后停止 = stop
    }

    private func 当前淡变值(_ layer: YURIS声音层) -> Double {
        guard layer.淡变时长 > 0 else { return layer.淡变终点 }
        let t = Date().timeIntervalSince(layer.淡变开始) / layer.淡变时长
        return t >= 1 ? layer.淡变终点 : layer.淡变起点 + (layer.淡变终点 - layer.淡变起点) * t
    }

    private func 开始播放(_ layer: YURIS声音层, 淡入 fade: Int) {
        停止(layer)
        guard let stream = layer.流 else { return }
        layer.播放中 = true
        layer.暂停中 = false
        layer.已循环 = 0
        layer.已排帧 = 0
        layer.循环内已排帧 = 0
        layer.下一帧 = Int64(Double(max(0, layer.开始)) / 1000 * stream.采样率)
        stream.定位(layer.下一帧)
        layer.开始时间 = Date()
        layer.暂停时累计 = 0
        if fade > 0 {
            layer.淡变起点 = 0
            layer.淡变终点 = 1
            layer.淡变开始 = Date()
            layer.淡变时长 = Double(fade) / 1000
            layer.淡变后停止 = false
        } else {
            layer.淡变时长 = 0
            layer.淡变终点 = 1
            layer.淡变起点 = 1
        }
        #if DEBUG
        print("[YU-RIS] 播放 \(layer.文件) \(type(of: stream)) \(stream.采样率)Hz \(stream.声道数)声道 \(stream.总帧数)帧")
        #endif
        if let engine = 启动引擎() {
            let format = AVAudioFormat(standardFormatWithSampleRate: stream.采样率, channels: AVAudioChannelCount(stream.声道数))
            let player = AVAudioPlayerNode()
            engine.attach(player)
            if layer.音高 != 256 {
                let varispeed = AVAudioUnitVarispeed()
                engine.attach(varispeed)
                varispeed.rate = Float(0.5 + Double(layer.音高) / 512)
                engine.connect(player, to: varispeed, format: format)
                engine.connect(varispeed, to: engine.mainMixerNode, format: format)
                layer.变速 = varispeed
            } else {
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
            layer.播放器 = player
            layer.已连接格式 = format
            补充缓冲(layer)
            player.play()
        }
    }

    private func 补充缓冲(_ layer: YURIS声音层) {
        guard let player = layer.播放器, let format = layer.已连接格式, let stream = layer.流 else { return }
        let rendered = 已播放帧数(layer)
        let channels = stream.声道数
        let target = Int64(Self.预排秒数 * stream.采样率)
        var attempts = 0
        while layer.已排帧 - rendered < target, attempts < 8 {
            attempts += 1
            var frames = Int(Self.块帧数)
            // END 是循环点
            if layer.结束 > 0 {
                let endFrame = Int64(Double(layer.结束) / 1000 * stream.采样率)
                frames = min(frames, Int(endFrame - layer.下一帧))
            }
            if frames > 0 {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                      let outputs = buffer.floatChannelData else { return }
                let interleaved = UnsafeMutablePointer<Float>.allocate(capacity: frames * channels)
                defer { interleaved.deallocate() }
                let read = stream.读取(interleaved, 帧数: frames)
                if read > 0 {
                    for c in 0..<channels {
                        let output = outputs[c]
                        for i in 0..<read { output[i] = interleaved[i * channels + c] }
                    }
                    buffer.frameLength = AVAudioFrameCount(read)
                    player.scheduleBuffer(buffer)
                    layer.已排帧 += Int64(read)
                    layer.下一帧 += Int64(read)
                    if read == frames { continue }
                }
            }
            // 到尾了：循环或结束
            layer.已循环 += 1
            if layer.循环 != 0, layer.已循环 >= layer.循环 { return }
            let restartFrame = Int64(Double(max(0, layer.重开 != 0 ? layer.重开 : layer.开始)) / 1000 * stream.采样率)
            stream.定位(restartFrame)
            layer.下一帧 = restartFrame
        }
    }

    private func 已播放帧数(_ layer: YURIS声音层) -> Int64 {
        guard let player = layer.播放器, let node = player.lastRenderTime, node.isSampleTimeValid,
              let time = player.playerTime(forNodeTime: node), time.isSampleTimeValid else { return 0 }
        return max(0, time.sampleTime)
    }

    private func 设暂停(_ layer: YURIS声音层, _ pause: Bool) {
        guard layer.播放中, layer.暂停中 != pause else { return }
        layer.暂停中 = pause
        if pause {
            layer.播放器?.pause()
            if let start = layer.开始时间 {
                layer.暂停时累计 += Date().timeIntervalSince(start)
                layer.开始时间 = nil
            }
        } else {
            layer.播放器?.play()
            layer.开始时间 = Date()
        }
    }

    private func 停止(_ layer: YURIS声音层) {
        layer.播放中 = false
        layer.暂停中 = false
        layer.开始时间 = nil
        layer.暂停时累计 = 0
        if let player = layer.播放器 {
            player.stop()
            if let engine = 引擎 {
                engine.detach(player)
                if let varispeed = layer.变速 { engine.detach(varispeed) }
            }
        }
        layer.播放器 = nil
        layer.变速 = nil
        layer.已连接格式 = nil
    }

    private func 已用秒数(_ layer: YURIS声音层) -> Double {
        layer.暂停时累计 + (layer.开始时间.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// 每帧调用：补缓冲、淡变、检测播放结束
    func 更新(帧数: Int) {
        var volumeChanged = false
        for layer in 层.values where layer.播放中 {
            if layer.淡变时长 > 0 {
                volumeChanged = true
                if Date().timeIntervalSince(layer.淡变开始) >= layer.淡变时长 {
                    layer.淡变起点 = layer.淡变终点
                    let stop = layer.淡变后停止
                    layer.淡变时长 = 0
                    layer.淡变后停止 = false
                    if stop {
                        停止(layer)
                        layer.淡变终点 = 1
                        continue
                    }
                }
            }
            guard !layer.暂停中, let stream = layer.流 else { continue }
            if layer.播放器 != nil {
                补充缓冲(layer)
                let finished = layer.循环 != 0 && layer.已循环 >= layer.循环
                if finished, 已播放帧数(layer) >= layer.已排帧, layer.已排帧 > 0 {
                    停止(layer)
                }
            } else if layer.循环 != 0 {
                // 没有引擎：按时钟结束
                let duration = Double(stream.总帧数) / stream.采样率
                let start = Double(max(0, layer.开始)) / 1000
                if 已用秒数(layer) >= (duration - start) * Double(layer.循环) { 停止(layer) }
            }
        }
        if volumeChanged { 应用音量() }
    }

    private func 总音量(_ layer: YURIS声音层) -> Double {
        var value = Double(layer.音量) / 256 * 当前淡变值(layer)
        if !layer.启用 { return 0 }
        var parts = layer.路径
        while parts.count > 1 {
            parts.removeLast()
            if let parent = 层[parts] {
                if !parent.启用 { return 0 }
                value *= Double(parent.音量) / 256
            }
        }
        return value
    }

    private func 应用音量() {
        for layer in 层.values {
            guard let player = layer.播放器 else { continue }
            player.volume = Float(总音量(layer))
            player.pan = Float((Double(layer.声像) - 256) / 256)
        }
    }

    func 删除(_ id: [UInt8]) {
        let (parts, _) = 规范路径(id)
        for (key, layer) in 层 where key.starts(with: parts) {
            停止(layer)
            层[key] = nil
        }
    }

    func 查询(id: [UInt8], 项 query: String) -> YURIS值 {
        let (parts, _) = 规范路径(id)
        let layer = 层[parts]
        switch query {
        case "EXIST": return .整数(layer == nil ? 0 : 1)
        case "E": return .整数(layer?.启用 == true ? 1 : 0)
        case "PLAY": return .整数(layer?.播放中 == true ? 1 : 0)
        case "PAUSE": return .整数(layer?.暂停中 == true ? 1 : 0)
        case "LOOP": return .整数(Int64(layer?.循环 ?? 0))
        case "LOOPCOUNT": return .整数(Int64(layer?.已循环 ?? 0))
        case "START": return .整数(Int64(layer?.开始 ?? 0))
        case "RESTART": return .整数(Int64(layer?.重开 ?? 0))
        case "END": return .整数(Int64(layer?.结束 ?? 0))
        case "VOLUME": return .整数(Int64(layer?.音量 ?? 0))
        case "PAN": return .整数(Int64(layer?.声像 ?? 0))
        case "PITCH": return .整数(Int64(layer?.音高 ?? 0))
        case "FILE": return .文字(YURIS文本.编码(layer?.文件 ?? ""))
        case "TIME":
            guard let layer, let stream = layer.流, layer.播放中 else { return .整数(0) }
            if layer.播放器 != nil {
                let start = Double(max(0, layer.开始))
                return .整数(Int64(start + Double(已播放帧数(layer)) / stream.采样率 * 1000))
            }
            return .整数(Int64(已用秒数(layer) * 1000))
        case "TOTALTIME":
            guard let stream = layer?.流 else { return .整数(0) }
            return .整数(Int64(Double(stream.总帧数) / stream.采样率 * 1000))
        case "CHANNEL": return .整数(Int64(layer?.流?.声道数 ?? 0))
        case "SAMPLE": return .整数(Int64(layer?.流?.采样率 ?? 0))
        case "BIT": return .整数(16)
        default: return .整数(0)
        }
    }

    func 全部停止() {
        for layer in 层.values { 停止(layer) }
        层 = [:]
        引擎?.stop()
        引擎 = nil
    }

    func 暂停引擎(_ pause: Bool) {
        if pause { 引擎?.pause() } else { try? 引擎?.start() }
    }
}

/// 没有 Ogg 解码器时的替身：只从文件头尾读出时长，让脚本里的进度逻辑能走（命令行测试用）
nonisolated final class YURISOgg信息流: YURIS音频流 {
    let 采样率: Double
    let 声道数: Int
    let 总帧数: Int64

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count > 58, bytes[28] == 1, bytes[29] == 0x76 else { return nil }
        声道数 = Int(bytes[39])
        采样率 = Double(UInt32(bytes[40]) | UInt32(bytes[41]) << 8 | UInt32(bytes[42]) << 16 | UInt32(bytes[43]) << 24)
        var position: Int64 = 0
        var p = bytes.count - 27
        while p > 0 {
            if bytes[p] == 0x4F, bytes[p + 1] == 0x67, bytes[p + 2] == 0x67, bytes[p + 3] == 0x53 {
                for i in 0..<8 { position |= Int64(bytes[p + 6 + i]) << Int64(8 * i) }
                break
            }
            p -= 1
        }
        总帧数 = position
    }

    func 读取(_ buffer: UnsafeMutablePointer<Float>, 帧数: Int) -> Int { 0 }
    func 定位(_ frame: Int64) {}
}
