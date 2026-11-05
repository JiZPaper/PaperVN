#include "papervn_mpeg.h"

// pl_mpeg.h 本身不引入 size_t
#define PL_MPEG_IMPLEMENTATION
#define PLM_NO_STDIO
#include "pl_mpeg.h"

#include <math.h>

struct papervn_mpeg {
    plm_demux_t *demux;
    plm_buffer_t *video_buffer;
    plm_video_t *video;
    plm_buffer_t *audio_buffer;
    plm_audio_t *audio;
    int with_audio;
    int layer;
    int layer_known;
    double video_pts;
    double audio_pts;
    uint8_t *bytes;
    size_t bytes_length;
    size_t bytes_capacity;
    size_t bytes_read;
};

static void append_bytes(papervn_mpeg *self, const uint8_t *data, size_t length) {
    // 用掉的部分超过一半才整理，避免每个包都搬一次
    if (self->bytes_read > 0 && self->bytes_read >= self->bytes_length / 2) {
        memmove(self->bytes, self->bytes + self->bytes_read, self->bytes_length - self->bytes_read);
        self->bytes_length -= self->bytes_read;
        self->bytes_read = 0;
    }
    if (self->bytes_length + length > self->bytes_capacity) {
        size_t capacity = self->bytes_capacity ? self->bytes_capacity : 64 * 1024;
        while (capacity < self->bytes_length + length) capacity *= 2;
        uint8_t *grown = realloc(self->bytes, capacity);
        if (!grown) return;
        self->bytes = grown;
        self->bytes_capacity = capacity;
    }
    memcpy(self->bytes + self->bytes_length, data, length);
    self->bytes_length += length;
}

/// 第一个同步字决定音频是 MP2 还是 MP3
static void detect_layer(papervn_mpeg *self, const uint8_t *data, size_t length) {
    for (size_t i = 0; i + 1 < length; i++) {
        if (data[i] != 0xFF || (data[i + 1] & 0xE0) != 0xE0) continue;
        int bits = (data[i + 1] >> 1) & 3;
        if (bits == 0) continue;
        self->layer = bits == 2 ? 2 : bits == 1 ? 3 : 0;
        self->layer_known = 1;
        if (self->layer == 2) {
            self->audio_buffer = plm_buffer_create_with_capacity(PLM_BUFFER_DEFAULT_SIZE);
            self->audio = plm_audio_create_with_buffer(self->audio_buffer, 1);
        }
        return;
    }
}

static void handle_packet(papervn_mpeg *self, plm_packet_t *packet) {
    if (packet->type == PLM_DEMUX_PACKET_VIDEO_1) {
        if (self->video_pts == PLM_PACKET_INVALID_TS) self->video_pts = packet->pts;
        plm_buffer_write(self->video_buffer, packet->data, packet->length);
    } else if (packet->type == PLM_DEMUX_PACKET_AUDIO_1 && self->with_audio) {
        if (self->audio_pts == PLM_PACKET_INVALID_TS) self->audio_pts = packet->pts;
        if (!self->layer_known) detect_layer(self, packet->data, packet->length);
        if (self->layer == 2) {
            plm_buffer_write(self->audio_buffer, packet->data, packet->length);
        } else if (self->layer == 3) {
            append_bytes(self, packet->data, packet->length);
        }
    }
}

static int read_packet(papervn_mpeg *self, int requested_type) {
    plm_packet_t *packet;
    while ((packet = plm_demux_decode(self->demux))) {
        handle_packet(self, packet);
        if (requested_type == 0 || packet->type == requested_type) return 1;
    }
    if (plm_demux_has_ended(self->demux)) {
        plm_buffer_signal_end(self->video_buffer);
        if (self->audio_buffer) plm_buffer_signal_end(self->audio_buffer);
    }
    return 0;
}

static void load_video(plm_buffer_t *buffer, void *user) {
    PLM_UNUSED(buffer);
    read_packet((papervn_mpeg *)user, PLM_DEMUX_PACKET_VIDEO_1);
}

/// 有的文件序列头写的帧率和时间戳不一致（euphoria 写 59.94，实际是 29.97），只按序列头算会比声音快一倍。
/// 这里用开头几秒的时间戳量出实际帧率。B 帧的显示顺序和解码顺序不同，所以只看长距离的平均值。
static double measure_framerate(const void *data, size_t size, double declared) {
    const size_t limit = 8 * 1024 * 1024;
    plm_buffer_t *source = plm_buffer_create_with_memory((uint8_t *)data, size < limit ? size : limit, 0);
    plm_demux_t *demux = plm_demux_create(source, 1);
    double first_pts = PLM_PACKET_INVALID_TS, last_pts = PLM_PACKET_INVALID_TS;
    long pictures = 0, first_count = 0, last_count = 0;
    uint32_t window = 0xFFFFFFFF;
    plm_packet_t *packet;
    while ((packet = plm_demux_decode(demux))) {
        if (packet->type != PLM_DEMUX_PACKET_VIDEO_1) continue;
        if (packet->pts != PLM_PACKET_INVALID_TS) {
            if (first_pts == PLM_PACKET_INVALID_TS) {
                first_pts = packet->pts;
                first_count = pictures;
            }
            last_pts = packet->pts;
            last_count = pictures;
        }
        for (size_t i = 0; i < packet->length; i++) {
            window = (window << 8) | packet->data[i];
            if (window == 0x00000100) pictures++;
        }
    }
    plm_demux_destroy(demux);

    long counted = last_count - first_count;
    double span = last_pts - first_pts;
    if (counted < 30 || span <= 0) return declared;
    double measured = (double)counted / span;
    if (fabs(measured - declared) < declared * 0.05) return declared;
    if (fabs(measured - declared / 2) < declared * 0.025) return declared / 2;
    return measured >= 1 && measured <= 120 ? measured : declared;
}

papervn_mpeg *papervn_mpeg_open(const void *data, size_t size, int with_audio) {
    plm_buffer_t *source = plm_buffer_create_with_memory((uint8_t *)data, size, 0);
    papervn_mpeg *self = calloc(1, sizeof(papervn_mpeg));
    self->demux = plm_demux_create(source, 1);
    self->video_pts = PLM_PACKET_INVALID_TS;
    self->audio_pts = PLM_PACKET_INVALID_TS;
    self->with_audio = with_audio;

    if (!plm_demux_has_headers(self->demux) || plm_demux_get_num_video_streams(self->demux) < 1) {
        plm_demux_destroy(self->demux);
        free(self);
        return NULL;
    }

    self->video_buffer = plm_buffer_create_with_capacity(PLM_BUFFER_DEFAULT_SIZE);
    plm_buffer_set_load_callback(self->video_buffer, load_video, self);
    self->video = plm_video_create_with_buffer(self->video_buffer, 1);
    if (!plm_video_has_header(self->video)) {
        papervn_mpeg_close(self);
        return NULL;
    }

    self->video->framerate = measure_framerate(data, size, self->video->framerate);

    // 要在开始播放前知道音频格式。系统头可能写错，所以看实际的数据包
    if (with_audio && plm_demux_get_num_audio_streams(self->demux) > 0) {
        for (int i = 0; i < 4096 && !self->layer_known; i++) {
            if (!read_packet(self, 0)) break;
        }
    }
    return self;
}

void papervn_mpeg_close(papervn_mpeg *self) {
    if (!self) return;
    if (self->audio) plm_audio_destroy(self->audio);
    if (self->video) plm_video_destroy(self->video);
    plm_demux_destroy(self->demux);
    free(self->bytes);
    free(self);
}

int papervn_mpeg_width(papervn_mpeg *self) { return plm_video_get_width(self->video); }
int papervn_mpeg_height(papervn_mpeg *self) { return plm_video_get_height(self->video); }
double papervn_mpeg_framerate(papervn_mpeg *self) { return plm_video_get_framerate(self->video); }
double papervn_mpeg_next_time(papervn_mpeg *self) { return plm_video_get_time(self->video); }

/// 下一张是 B 帧就跳过。B 帧不被其他帧参考，跳过不影响后面的画面。
static int skip_b_picture(plm_video_t *video) {
    if (!video->has_reference_frame) return 0;
    if (video->start_code != PLM_START_PICTURE) {
        video->start_code = plm_buffer_find_start_code(video->buffer, PLM_START_PICTURE);
        if (video->start_code == -1) return 0;
    }
    if (plm_buffer_has_start_code(video->buffer, PLM_START_PICTURE) == -1 && !plm_buffer_has_ended(video->buffer)) {
        return 0;
    }
    if (!plm_buffer_has(video->buffer, 13)) return 0;
    size_t position = video->buffer->bit_index;
    plm_buffer_skip(video->buffer, 10);
    int type = plm_buffer_read(video->buffer, 3);
    video->buffer->bit_index = position;
    if (type != PLM_VIDEO_PICTURE_TYPE_B) return 0;

    video->start_code = -1;
    video->frames_decoded++;
    video->time = (double)video->frames_decoded / video->framerate;
    return 1;
}

int papervn_mpeg_decode_video(papervn_mpeg *self, int skip_b, papervn_mpeg_frame *out) {
    if (skip_b && skip_b_picture(self->video)) return 0;
    plm_frame_t *frame = plm_video_decode(self->video);
    if (!frame) {
        return plm_buffer_has_ended(self->video_buffer) ? -1 : 0;
    }
    out->time = frame->time;
    out->width = frame->width;
    out->height = frame->height;
    out->y = frame->y.data;
    out->cb = frame->cb.data;
    out->cr = frame->cr.data;
    out->y_stride = frame->y.width;
    out->c_stride = frame->cb.width;
    return 1;
}

int papervn_mpeg_pump(papervn_mpeg *self) { return read_packet(self, 0); }

int papervn_mpeg_audio_layer(papervn_mpeg *self) { return self->layer; }

double papervn_mpeg_audio_offset(papervn_mpeg *self) {
    if (self->audio_pts == PLM_PACKET_INVALID_TS || self->video_pts == PLM_PACKET_INVALID_TS) return 0;
    return self->audio_pts - self->video_pts;
}

const float *papervn_mpeg_decode_mp2(papervn_mpeg *self) {
    if (!self->audio) return NULL;
    plm_samples_t *samples = plm_audio_decode(self->audio);
    return samples ? samples->interleaved : NULL;
}

int papervn_mpeg_mp2_samplerate(papervn_mpeg *self) {
    return self->audio ? plm_audio_get_samplerate(self->audio) : 0;
}

const uint8_t *papervn_mpeg_audio_bytes(papervn_mpeg *self, size_t *length) {
    *length = self->bytes_length - self->bytes_read;
    return self->bytes + self->bytes_read;
}

void papervn_mpeg_audio_consume(papervn_mpeg *self, size_t count) {
    self->bytes_read += count;
    if (self->bytes_read > self->bytes_length) self->bytes_read = self->bytes_length;
}
