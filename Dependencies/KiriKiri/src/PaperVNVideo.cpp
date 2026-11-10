// 用 krkr2 带的 FFmpeg 解码视频文件（AVI、WMV、MP4 等），NScripter 和 YU-RIS 共用。
// 播放节奏和声音输出在 Swift 的 视觉小说影片 里，这里只负责解复用和解码。
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
}
#include <cmath>
#include <cstring>
#include <deque>
#include <mutex>
#include <vector>
#include "papervn_kirikiri.h"

struct papervn_video {
    const uint8_t *data = nullptr;
    size_t size = 0;
    int64_t position = 0;
    AVIOContext *io = nullptr;
    AVFormatContext *format = nullptr;
    AVCodecContext *video = nullptr;
    AVCodecContext *audio = nullptr;
    int videoStream = -1;
    int audioStream = -1;
    std::deque<AVPacket *> videoPackets;
    std::deque<AVPacket *> audioPackets;
    bool fileEnded = false;
    bool videoFlushed = false;
    bool audioFlushed = false;
    AVFrame *frame = nullptr;
    AVFrame *audioFrame = nullptr;
    SwsContext *scaler = nullptr;
    std::vector<uint8_t> converted;
    SwrContext *resampler = nullptr;
    std::vector<float> samples;
    double startTime = 0;
    double duration = 1.0 / 30;
    double nextTime = 0;
    int width = 0;
    int height = 0;
    int rate = 0;
};

static int PaperVNVideoRead(void *opaque, uint8_t *buffer, int size) {
    auto *self = static_cast<papervn_video *>(opaque);
    int64_t left = (int64_t)self->size - self->position;
    if (left <= 0) return AVERROR_EOF;
    int count = (int)std::min<int64_t>(left, size);
    memcpy(buffer, self->data + self->position, count);
    self->position += count;
    return count;
}

static int64_t PaperVNVideoSeek(void *opaque, int64_t offset, int whence) {
    auto *self = static_cast<papervn_video *>(opaque);
    if (whence == AVSEEK_SIZE) return (int64_t)self->size;
    switch (whence & ~AVSEEK_FORCE) {
        case SEEK_SET: self->position = offset; break;
        case SEEK_CUR: self->position += offset; break;
        case SEEK_END: self->position = (int64_t)self->size + offset; break;
        default: return -1;
    }
    return self->position;
}

static AVCodecContext *PaperVNOpenDecoder(AVStream *stream) {
    AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) return nullptr;
    AVCodecContext *context = avcodec_alloc_context3(codec);
    if (!context) return nullptr;
    if (avcodec_parameters_to_context(context, stream->codecpar) < 0 || avcodec_open2(context, codec, nullptr) < 0) {
        avcodec_free_context(&context);
        return nullptr;
    }
    return context;
}

papervn_video *papervn_video_open(const void *data, size_t size, int with_audio) {
    static std::once_flag once;
    std::call_once(once, [] { av_register_all(); });
    auto *self = new papervn_video();
    self->data = static_cast<const uint8_t *>(data);
    self->size = size;
    const int bufferSize = 64 * 1024;
    auto *buffer = static_cast<uint8_t *>(av_malloc(bufferSize));
    self->io = avio_alloc_context(buffer, bufferSize, 0, self, PaperVNVideoRead, nullptr, PaperVNVideoSeek);
    self->format = avformat_alloc_context();
    self->format->pb = self->io;
    self->format->flags |= AVFMT_FLAG_CUSTOM_IO;
    if (avformat_open_input(&self->format, nullptr, nullptr, nullptr) < 0 ||
        avformat_find_stream_info(self->format, nullptr) < 0) {
        papervn_video_close(self);
        return nullptr;
    }
    self->videoStream = av_find_best_stream(self->format, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
    if (self->videoStream < 0) {
        papervn_video_close(self);
        return nullptr;
    }
    AVStream *vs = self->format->streams[self->videoStream];
    self->video = PaperVNOpenDecoder(vs);
    if (!self->video || self->video->width <= 0 || self->video->height <= 0) {
        papervn_video_close(self);
        return nullptr;
    }
    self->width = self->video->width;
    self->height = self->video->height;
    AVRational rate = av_guess_frame_rate(self->format, vs, nullptr);
    if (rate.num > 0 && rate.den > 0) self->duration = av_q2d(av_inv_q(rate));
    if (vs->start_time != AV_NOPTS_VALUE) self->startTime = vs->start_time * av_q2d(vs->time_base);

    if (with_audio) {
        self->audioStream = av_find_best_stream(self->format, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
        if (self->audioStream >= 0) {
            self->audio = PaperVNOpenDecoder(self->format->streams[self->audioStream]);
            if (self->audio && self->audio->sample_rate > 0) {
                self->rate = self->audio->sample_rate;
                int64_t layout = self->audio->channel_layout ? self->audio->channel_layout
                                                             : av_get_default_channel_layout(self->audio->channels);
                self->resampler = swr_alloc_set_opts(nullptr, AV_CH_LAYOUT_STEREO, AV_SAMPLE_FMT_FLT, self->rate,
                                                     layout, self->audio->sample_fmt, self->rate, 0, nullptr);
                if (!self->resampler || swr_init(self->resampler) < 0) {
                    swr_free(&self->resampler);
                    avcodec_free_context(&self->audio);
                    self->rate = 0;
                }
            } else {
                avcodec_free_context(&self->audio);
            }
        }
    }
    self->frame = av_frame_alloc();
    self->audioFrame = av_frame_alloc();
    return self;
}

void papervn_video_close(papervn_video *self) {
    if (!self) return;
    for (AVPacket *packet : self->videoPackets) av_packet_free(&packet);
    for (AVPacket *packet : self->audioPackets) av_packet_free(&packet);
    if (self->frame) av_frame_free(&self->frame);
    if (self->audioFrame) av_frame_free(&self->audioFrame);
    if (self->scaler) sws_freeContext(self->scaler);
    if (self->resampler) swr_free(&self->resampler);
    if (self->video) avcodec_free_context(&self->video);
    if (self->audio) avcodec_free_context(&self->audio);
    if (self->format) avformat_close_input(&self->format);
    if (self->io) {
        av_freep(&self->io->buffer);
        av_freep(&self->io);
    }
    delete self;
}

int papervn_video_width(papervn_video *self) { return self->width; }
int papervn_video_height(papervn_video *self) { return self->height; }
double papervn_video_frame_duration(papervn_video *self) { return self->duration; }
double papervn_video_next_time(papervn_video *self) { return self->nextTime; }
int papervn_video_samplerate(papervn_video *self) { return self->rate; }

double papervn_video_audio_offset(papervn_video *self) {
    if (self->audioStream < 0 || !self->audio) return 0;
    AVStream *as = self->format->streams[self->audioStream];
    if (as->start_time == AV_NOPTS_VALUE) return 0;
    return as->start_time * av_q2d(as->time_base) - self->startTime;
}

int papervn_video_pump(papervn_video *self) {
    if (self->fileEnded) return 0;
    AVPacket *packet = av_packet_alloc();
    if (av_read_frame(self->format, packet) < 0) {
        av_packet_free(&packet);
        self->fileEnded = true;
        return 0;
    }
    if (packet->stream_index == self->videoStream) {
        self->videoPackets.push_back(packet);
    } else if (packet->stream_index == self->audioStream && self->audio) {
        self->audioPackets.push_back(packet);
    } else {
        av_packet_free(&packet);
    }
    return 1;
}

int papervn_video_decode(papervn_video *self, int skip_nonref, papervn_video_frame *out) {
    self->video->skip_frame = skip_nonref ? AVDISCARD_NONREF : AVDISCARD_DEFAULT;
    while (true) {
        int status = avcodec_receive_frame(self->video, self->frame);
        if (status == 0) break;
        if (status == AVERROR_EOF) return -1;
        if (status != AVERROR(EAGAIN)) return -1;
        if (self->videoPackets.empty() && papervn_video_pump(self)) continue;
        if (self->videoPackets.empty()) {
            if (!self->fileEnded) continue;
            if (self->videoFlushed) return -1;
            self->videoFlushed = true;
            avcodec_send_packet(self->video, nullptr);
            continue;
        }
        AVPacket *packet = self->videoPackets.front();
        self->videoPackets.pop_front();
        avcodec_send_packet(self->video, packet);
        av_packet_free(&packet);
    }
    AVStream *vs = self->format->streams[self->videoStream];
    int64_t stamp = av_frame_get_best_effort_timestamp(self->frame);
    double time = stamp != AV_NOPTS_VALUE ? stamp * av_q2d(vs->time_base) - self->startTime : self->nextTime;
    if (time < 0) time = 0;
    self->nextTime = time + self->duration;
    out->time = time;

    const bool direct = self->frame->format == AV_PIX_FMT_YUV420P && self->frame->color_range != AVCOL_RANGE_JPEG;
    if (direct) {
        out->y = self->frame->data[0];
        out->cb = self->frame->data[1];
        out->cr = self->frame->data[2];
        out->y_stride = self->frame->linesize[0];
        out->c_stride = self->frame->linesize[1];
        return 1;
    }
    // 其他像素格式（Cinepak、MSVC、RGB 等）统一转成 YUV420P
    const int w = self->width & ~1, h = self->height & ~1;
    self->scaler = sws_getCachedContext(self->scaler, self->frame->width, self->frame->height,
                                        (AVPixelFormat)self->frame->format, w, h, AV_PIX_FMT_YUV420P,
                                        SWS_BILINEAR, nullptr, nullptr, nullptr);
    if (!self->scaler) return 0;
    const int cw = w / 2, ch = h / 2;
    self->converted.resize((size_t)w * h + (size_t)cw * ch * 2);
    uint8_t *planes[4] = {self->converted.data(), self->converted.data() + (size_t)w * h,
                          self->converted.data() + (size_t)w * h + (size_t)cw * ch, nullptr};
    int strides[4] = {w, cw, cw, 0};
    sws_scale(self->scaler, self->frame->data, self->frame->linesize, 0, self->frame->height, planes, strides);
    out->y = planes[0];
    out->cb = planes[1];
    out->cr = planes[2];
    out->y_stride = w;
    out->c_stride = cw;
    return 1;
}

const float *papervn_video_decode_audio(papervn_video *self, int *frames) {
    *frames = 0;
    if (!self->audio) return nullptr;
    while (true) {
        int status = avcodec_receive_frame(self->audio, self->audioFrame);
        if (status == 0) break;
        if (status != AVERROR(EAGAIN)) return nullptr;
        if (self->audioPackets.empty()) {
            if (!self->fileEnded || self->audioFlushed) return nullptr;
            self->audioFlushed = true;
            avcodec_send_packet(self->audio, nullptr);
            continue;
        }
        AVPacket *packet = self->audioPackets.front();
        self->audioPackets.pop_front();
        avcodec_send_packet(self->audio, packet);
        av_packet_free(&packet);
    }
    const int capacity = self->audioFrame->nb_samples + 256;
    self->samples.resize((size_t)capacity * 2);
    uint8_t *output = reinterpret_cast<uint8_t *>(self->samples.data());
    int count = swr_convert(self->resampler, &output, capacity, (const uint8_t **)self->audioFrame->extended_data,
                            self->audioFrame->nb_samples);
    if (count <= 0) return nullptr;
    *frames = count;
    return self->samples.data();
}
