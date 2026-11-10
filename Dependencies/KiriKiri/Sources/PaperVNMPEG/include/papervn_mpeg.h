// MPEG-1 影片（MPEG-PS）的解码接口。视频和 MP2 音频由 pl_mpeg 解码；
// MP3 音频 pl_mpeg 解不了，这里只把数据拆出来，由 AudioToolbox 解码。
#ifndef PAPERVN_MPEG_H
#define PAPERVN_MPEG_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct papervn_mpeg papervn_mpeg;

typedef struct {
    double time;
    unsigned int width;
    unsigned int height;
    const uint8_t *y;
    const uint8_t *cb;
    const uint8_t *cr;
    unsigned int y_stride;
    unsigned int c_stride;
} papervn_mpeg_frame;

/// 数据要在 close 之前一直有效。不是 MPEG-1 的 PS 流（比如 MPEG-2）时返回 NULL。
papervn_mpeg *papervn_mpeg_open(const void *data, size_t size, int with_audio);
void papervn_mpeg_close(papervn_mpeg *mpeg);

int papervn_mpeg_width(papervn_mpeg *mpeg);
int papervn_mpeg_height(papervn_mpeg *mpeg);
double papervn_mpeg_framerate(papervn_mpeg *mpeg);
/// 下一帧的时间（秒，从 0 开始）
double papervn_mpeg_next_time(papervn_mpeg *mpeg);

/// 解码下一帧。skip_b 非 0 时直接跳过 B 帧（来不及解码时用）。
/// 返回 1：out 有效，到下次调用为止；0：这次没有产生画面；-1：视频已结束。
int papervn_mpeg_decode_video(papervn_mpeg *mpeg, int skip_b, papervn_mpeg_frame *out);

/// 再读一个数据包。文件已读完时返回 0。
int papervn_mpeg_pump(papervn_mpeg *mpeg);

/// 音频的层：2 是 MP2，3 是 MP3，0 是没有音频或不支持
int papervn_mpeg_audio_layer(papervn_mpeg *mpeg);
/// 音频开头相对视频开头的时间差（秒）
double papervn_mpeg_audio_offset(papervn_mpeg *mpeg);

/// MP2：解码一帧，返回 PAPERVN_MPEG_MP2_FRAMES 帧交错的立体声；数据不够时返回 NULL
#define PAPERVN_MPEG_MP2_FRAMES 1152
const float *papervn_mpeg_decode_mp2(papervn_mpeg *mpeg);
int papervn_mpeg_mp2_samplerate(papervn_mpeg *mpeg);

/// MP3：还没用掉的原始数据
const uint8_t *papervn_mpeg_audio_bytes(papervn_mpeg *mpeg, size_t *length);
void papervn_mpeg_audio_consume(papervn_mpeg *mpeg, size_t count);

#ifdef __cplusplus
}
#endif

#endif
