import AudioToolbox
import AVFoundation
import KiriKiri

/// 播放 MIDI。iOS 没有内置 GM 音色，AVMIDIPlayer 也不能调音量，所以用系统的 MIDISynth 加自带的音色库。
@MainActor
final class MIDI播放器 {
    private let 引擎 = AVAudioEngine()
    private let 合成器: AVAudioUnitMIDIInstrument
    private let 序列器: AVAudioSequencer
    private var 淡出任务: Task<Void, Never>?

    /// 0～1
    var 音量: Float = 1 { didSet { 引擎.mainMixerNode.outputVolume = 音量 } }

    init?(数据 data: Data, 循环: Bool) {
        guard data.prefix(4) == Data("MThd".utf8),
              视觉小说运行资源.已安装(.midi音色) else { return nil }
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice, componentSubType: kAudioUnitSubType_MIDISynth,
            componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        合成器 = AVAudioUnitMIDIInstrument(audioComponentDescription: description)
        引擎.attach(合成器)
        引擎.connect(合成器, to: 引擎.mainMixerNode, format: nil)
        // 这个音色库在多声部时峰值会超过 1，留些余量免得削波
        合成器.volume = 0.5
        var bank = 视觉小说运行资源.MIDI音色库 as CFURL
        let unit = 合成器.audioUnit
        let status = withUnsafeMutablePointer(to: &bank) {
            AudioUnitSetProperty(unit, kMusicDeviceProperty_SoundBankURL, kAudioUnitScope_Global, 0,
                                 $0, UInt32(MemoryLayout<CFURL>.size))
        }
        guard status == noErr else { return nil }
        序列器 = AVAudioSequencer(audioEngine: 引擎)
        do {
            try 序列器.load(from: data, options: [])
        } catch {
            return nil
        }
        引擎.prepare()
        guard (try? 引擎.start()) != nil else { return nil }
        预载音色(data)
        var longest: AVMusicTimeStamp = 0
        for track in 序列器.tracks { longest = max(longest, track.lengthInBeats) }
        for track in 序列器.tracks {
            track.destinationAudioUnit = 合成器
            if 循环, longest > 0 {
                track.loopRange = AVBeatRange(start: 0, length: longest)
                track.isLoopingEnabled = true
                track.numberOfLoops = AVMusicTrackLoopCount.forever.rawValue
            }
        }
        序列器.prepareToPlay()
    }

    /// 播放中才加载音色会卡一下、前几个音发不出来，所以先把用到的音色都加载好
    private func 预载音色(_ data: Data) {
        var enable: UInt32 = 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioUnitSetProperty(合成器.audioUnit, AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
                                   kAudioUnitScope_Global, 0, &enable, size) == noErr else { return }
        for item in Self.用到的音色(data) {
            合成器.sendProgramChange(item.program, onChannel: item.channel)
        }
        enable = 0
        AudioUnitSetProperty(合成器.audioUnit, AudioUnitPropertyID(kAUMIDISynthProperty_EnablePreload),
                             kAudioUnitScope_Global, 0, &enable, size)
    }

    /// 从标准 MIDI 文件里找出 Program Change
    private static func 用到的音色(_ data: Data) -> Set<音色> {
        let bytes = [UInt8](data)
        var result: Set<音色> = []
        var p = 14
        func u32(_ at: Int) -> Int { Int(bytes[at]) << 24 | Int(bytes[at + 1]) << 16 | Int(bytes[at + 2]) << 8 | Int(bytes[at + 3]) }
        while p + 8 <= bytes.count {
            let isTrack = bytes[p] == 0x4D && bytes[p + 1] == 0x54 && bytes[p + 2] == 0x72 && bytes[p + 3] == 0x6B
            let length = u32(p + 4)
            p += 8
            let end = min(bytes.count, p + length)
            if isTrack {
                var i = p
                var status: UInt8 = 0
                func varlen() -> Int {
                    var value = 0
                    while i < end {
                        let byte = bytes[i]; i += 1
                        value = value << 7 | Int(byte & 0x7F)
                        if byte & 0x80 == 0 { break }
                    }
                    return value
                }
                while i < end {
                    _ = varlen()
                    guard i < end else { break }
                    if bytes[i] & 0x80 != 0 { status = bytes[i]; i += 1 }
                    switch status & 0xF0 {
                    case 0xC0:
                        if i < end { result.insert(音色(channel: status & 0x0F, program: bytes[i])) }
                        i += 1
                    case 0xD0: i += 1
                    case 0x80, 0x90, 0xA0, 0xB0, 0xE0: i += 2
                    default:
                        if status == 0xFF {
                            i += 1
                            i += varlen()
                        } else if status == 0xF0 || status == 0xF7 {
                            i += varlen()
                        } else {
                            i = end
                        }
                    }
                }
            }
            p = end
        }
        return result
    }

    private struct 音色: Hashable, Sendable {
        let channel: UInt8
        let program: UInt8
    }

    func 播放() {
        if !引擎.isRunning { try? 引擎.start() }
        try? 序列器.start()
    }

    func 暂停() {
        序列器.stop()
        引擎.pause()
    }

    func 停止() {
        淡出任务?.cancel()
        序列器.stop()
        引擎.stop()
    }

    func 淡出(毫秒 milliseconds: Int, 完成: @escaping @MainActor () -> Void) {
        淡出任务?.cancel()
        let start = 音量
        淡出任务 = Task { [weak self] in
            let steps = max(1, milliseconds / 50)
            for step in 1...steps {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                self?.音量 = start * (1 - Float(step) / Float(steps))
            }
            完成()
        }
    }

    #if DEBUG
    /// 测试用：装一个监听，打印混音器的电平
    func 打印电平() {
        Self.监听电平(引擎.mainMixerNode)
    }

    /// 回调在音频线程上，不能带主线程隔离
    nonisolated private static func 监听电平(_ node: AVAudioNode) {
        nonisolated(unsafe) var peak: Float = 0
        nonisolated(unsafe) var count = 0
        node.installTap(onBus: 0, bufferSize: 4096, format: nil) { @Sendable buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[i])) }
            count += 1
            if count % 20 == 0 {
                print("[MIDI] 峰值电平 \(peak)")
                peak = 0
            }
        }
    }
    #endif
}
