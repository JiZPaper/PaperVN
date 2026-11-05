import Foundation
import KiriKiri

/// MPEG-1 以外的影片（AVI、WMV 等）：解码器是 KiriKiri 库里的 FFmpeg
nonisolated final class FFmpeg影片后端: 影片解码后端 {
    private let 数据: NSData
    private let 解码器: OpaquePointer
    let 宽: Int
    let 高: Int
    let 帧长: Double
    let 采样率: Double
    let 音频偏移: Double

    /// 在第一次打开影片之前调用
    static func 启用() {
        视觉小说影片.其他格式后端 = { FFmpeg影片后端(数据: $0, 声音: $1) }
    }

    init?(数据 storage: NSData, 声音: Bool) {
        guard let handle = papervn_video_open(storage.bytes, storage.length, 声音 ? 1 : 0) else { return nil }
        数据 = storage
        解码器 = handle
        宽 = Int(papervn_video_width(handle))
        高 = Int(papervn_video_height(handle))
        帧长 = papervn_video_frame_duration(handle)
        采样率 = Double(papervn_video_samplerate(handle))
        音频偏移 = papervn_video_audio_offset(handle)
    }

    deinit { papervn_video_close(解码器) }

    func 下一帧时间() -> Double { papervn_video_next_time(解码器) }
    func 读包() -> Bool { papervn_video_pump(解码器) != 0 }

    func 解码视频(跳过: Bool, 帧: inout 影片帧数据) -> Int {
        var frame = papervn_video_frame()
        let result = Int(papervn_video_decode(解码器, 跳过 ? 1 : 0, &frame))
        if result == 1 {
            帧 = 影片帧数据(时间: frame.time, y: frame.y, cb: frame.cb, cr: frame.cr,
                         y行宽: Int(frame.y_stride), c行宽: Int(frame.c_stride))
        }
        return result
    }

    func 解码音频(_ output: (UnsafePointer<Float>, Int) -> Void) -> Bool {
        var frames: Int32 = 0
        guard let samples = papervn_video_decode_audio(解码器, &frames), frames > 0 else { return false }
        output(samples, Int(frames))
        return true
    }
}
