import AVFoundation
import KiriKiri
import OSLog

/// NScripter 的声音：背景音乐一路、效果音（wave）一路、dwave 按声道编号多路。
/// AVAudioPlayer 能播放 WAV、MP3、AAC；Ogg Vorbis 先解码成 WAV（解码器在 KiriKiri 的库里）；MIDI 走 MIDI播放器。
@MainActor
final class NScripter音频 {
    private static let logger = Logger(subsystem: "com.jizpaper.PaperVN", category: "NScripter")

    private let 资源: NScripter资源
    private var 背景音乐: AVAudioPlayer?
    private var 背景MIDI: MIDI播放器?
    private var 效果音: AVAudioPlayer?
    private var 声道: [Int: AVAudioPlayer] = [:]
    private var 已提示的格式: Set<String> = []
    private var 原来的类别: AVAudioSession.Category?

    private(set) var 背景音乐文件: String?
    private(set) var 背景音乐循环 = false
    var 音乐音量: Float = 1 {
        didSet {
            背景音乐?.volume = 音乐音量
            背景MIDI?.音量 = 音乐音量
        }
    }
    var 效果音量: Float = 1
    var 语音音量: Float = 1

    init(资源: NScripter资源) {
        self.资源 = 资源
    }

    func 激活() {
        let session = AVAudioSession.sharedInstance()
        原来的类别 = session.category
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    func 停用() {
        全部停止()
        if let 原来的类别 { try? AVAudioSession.sharedInstance().setCategory(原来的类别) }
    }

    func 暂停(_ paused: Bool) {
        for player in [背景音乐, 效果音].compactMap({ $0 }) + Array(声道.values) {
            if paused { player.pause() } else if player.currentTime > 0 { player.play() }
        }
        if paused { 背景MIDI?.暂停() } else { 背景MIDI?.播放() }
    }

    private func 播放器(_ file: String) -> AVAudioPlayer? {
        guard let data = 资源.读取(file) else {
            Self.logger.debug("Missing sound \(file, privacy: .public)")
            return nil
        }
        do {
            if data.prefix(4) == Data("OggS".utf8), let wave = NScripterOgg.解码成WAV(data) {
                return try AVAudioPlayer(data: wave)
            }
            return try AVAudioPlayer(data: data)
        } catch {
            let ext = (file as NSString).pathExtension.lowercased()
            if 已提示的格式.insert(ext).inserted {
                Self.logger.info("Unsupported sound format \(ext, privacy: .public)")
            }
            return nil
        }
    }

    func 播放音乐(_ file: String, 循环 loop: Bool) {
        背景音乐?.stop()
        背景MIDI?.停止()
        背景MIDI = nil
        背景音乐文件 = file
        背景音乐循环 = loop
        // MIDI 走系统的 MIDISynth 加自带音色库
        if let data = 资源.读取(file), data.prefix(4) == Data("MThd".utf8) {
            背景音乐 = nil
            背景MIDI = MIDI播放器(数据: data, 循环: loop)
            背景MIDI?.音量 = 音乐音量
            背景MIDI?.播放()
            #if DEBUG
            背景MIDI?.打印电平()
            #endif
            return
        }
        背景音乐 = 播放器(file)
        背景音乐?.numberOfLoops = loop ? -1 : 0
        背景音乐?.volume = 音乐音量
        背景音乐?.play()
    }

    func 停止音乐() {
        背景音乐?.stop()
        背景音乐 = nil
        背景MIDI?.停止()
        背景MIDI = nil
        背景音乐文件 = nil
    }

    func 淡出音乐(_ milliseconds: Int) {
        if let midi = 背景MIDI {
            背景音乐文件 = nil
            midi.淡出(毫秒: milliseconds) { [weak self] in
                if self?.背景MIDI === midi { self?.停止音乐() }
            }
            return
        }
        guard let player = 背景音乐 else { return }
        player.setVolume(0, fadeDuration: Double(milliseconds) / 1000)
        背景音乐文件 = nil
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            if self?.背景音乐 === player { self?.停止音乐() }
        }
    }

    func 播放效果音(_ file: String, 循环 loop: Bool) {
        效果音?.stop()
        效果音 = 播放器(file)
        效果音?.numberOfLoops = loop ? -1 : 0
        效果音?.volume = 效果音量
        效果音?.play()
    }

    func 停止效果音() {
        效果音?.stop()
        效果音 = nil
    }

    /// dwave：0 号声道通常是语音。
    func 播放声道(_ channel: Int, _ file: String, 循环 loop: Bool) {
        声道[channel]?.stop()
        let player = 播放器(file)
        player?.numberOfLoops = loop ? -1 : 0
        player?.volume = channel == 0 ? 语音音量 : 效果音量
        player?.play()
        声道[channel] = player
    }

    func 停止声道(_ channel: Int) {
        声道[channel]?.stop()
        声道[channel] = nil
    }

    func 全部停止() {
        停止音乐()
        停止效果音()
        for player in 声道.values { player.stop() }
        声道.removeAll()
    }
}

nonisolated enum NScripterOgg {
    /// Ogg Vorbis → 16 位 PCM 的 WAV
    static func 解码成WAV(_ data: Data) -> Data? {
        let copy = UnsafeMutableRawPointer.allocate(byteCount: data.count, alignment: 1)
        defer { copy.deallocate() }
        data.copyBytes(to: copy.assumingMemoryBound(to: UInt8.self), count: data.count)
        guard let handle = papervn_ogg_open(copy, data.count) else { return nil }
        defer { papervn_ogg_close(handle) }
        let channels = Int(papervn_ogg_channels(handle))
        let rate = Int(papervn_ogg_sample_rate(handle))
        let total = Int(papervn_ogg_total_frames(handle))
        guard channels > 0, rate > 0 else { return nil }
        var wave = Data()
        wave.reserveCapacity(44 + max(0, total) * channels * 2)
        func u32(_ value: Int) { var v = UInt32(value).littleEndian; withUnsafeBytes(of: &v) { wave.append(contentsOf: $0) } }
        func u16(_ value: Int) { var v = UInt16(value).littleEndian; withUnsafeBytes(of: &v) { wave.append(contentsOf: $0) } }
        wave.append(contentsOf: Array("RIFF".utf8)); u32(0)
        wave.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(channels)
        u32(rate); u32(rate * channels * 2); u16(channels * 2); u16(16)
        wave.append(contentsOf: Array("data".utf8)); u32(0)
        let frames = 8192
        let floats = UnsafeMutablePointer<Float>.allocate(capacity: frames * channels)
        let samples = UnsafeMutablePointer<Int16>.allocate(capacity: frames * channels)
        defer { floats.deallocate(); samples.deallocate() }
        var written = 0
        while true {
            let count = Int(papervn_ogg_read(handle, floats, Int64(frames)))
            guard count > 0 else { break }
            for i in 0..<(count * channels) {
                samples[i] = Int16(max(-1, min(1, floats[i])) * 32767).littleEndian
            }
            wave.append(UnsafeBufferPointer(start: samples, count: count * channels))
            written += count * channels * 2
        }
        guard written > 0 else { return nil }
        func patch(_ at: Int, _ value: Int) {
            let v = UInt32(value)
            for i in 0..<4 { wave[at + i] = UInt8((v >> UInt32(8 * i)) & 0xFF) }
        }
        patch(4, wave.count - 8)
        patch(40, written)
        return wave
    }
}
