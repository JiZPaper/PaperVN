#ifndef PAPERVN_KIRIKIRI_H
#define PAPERVN_KIRIKIRI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 游戏调用 System.terminate 等结束时。code 是退出码。 */
typedef void (*papervn_kirikiri_exit_callback)(void *user_data, int32_t code);
/* 游戏弹出提示框（kind 0）或输入框（kind 1）。回答用 papervn_kirikiri_answer_dialog。 */
typedef void (*papervn_kirikiri_dialog_callback)(void *user_data, int32_t kind, const char *title,
                                                 const char *message, const char *text,
                                                 const char *const *buttons, int32_t button_count);

/* 创建画面（UIView，CAEAGLLayer）。一个进程里只有一个，下一部游戏接着用。返回的视图由调用方持有（+1）。 */
void *papervn_kirikiri_create_view(double width, double height, double scale);
/* 在主线程上启动游戏。game_dir 是含 startup.tjs 的文件夹，或 data.xp3 这类封包文件。
 * data_dir 放引擎自己的设置；resource_dir 是 krkr2 界面资源（KiriKiri资源.路径）。
 * 0：已启动；1：上一部游戏还没结束；2：参数无效。 */
int32_t papervn_kirikiri_start(const char *game_dir, const char *data_dir, const char *resource_dir,
                               papervn_kirikiri_exit_callback exit_callback,
                               papervn_kirikiri_dialog_callback dialog_callback, void *user_data);
/* button：按钮序号；text：输入框的内容（提示框传 NULL）。 */
void papervn_kirikiri_answer_dialog(int32_t button, const char *text);
/* 进入后台、弹出 PaperVN 的界面时暂停。 */
void papervn_kirikiri_set_paused(int32_t paused);
/* 快进：按住或松开 Ctrl。 */
void papervn_kirikiri_set_fast_forward(int32_t enabled);
/* 游戏窗口菜单的 JSON（[{path,title,enabled,checked,children}]）。没有时返回 NULL；用 free 释放。 */
char *papervn_kirikiri_copy_game_menu(void);
/* 点按菜单项。path 来自 papervn_kirikiri_copy_game_menu。 */
void papervn_kirikiri_click_game_menu(const char *path);
/* 发送一次辅助点按（鼠标右键）。 */
void papervn_kirikiri_secondary_click(void);
/* 离开运行页面：卸载当前游戏，之后可以再调用 papervn_kirikiri_start。 */
void papervn_kirikiri_stop(void);
/* 当前运行代次，用来阻止旧页面的延迟卸载影响下一部游戏。 */
uint64_t papervn_kirikiri_session_id(void);
void papervn_kirikiri_stop_session(uint64_t session_id);

/* Ogg Vorbis 解码（用 krkr2 带的 libvorbisfile，其他引擎也能用）。data 在 close 之前都要有效。 */
typedef struct papervn_ogg papervn_ogg;
papervn_ogg *papervn_ogg_open(const void *data, size_t size);
int32_t papervn_ogg_channels(papervn_ogg *ogg);
double papervn_ogg_sample_rate(papervn_ogg *ogg);
int64_t papervn_ogg_total_frames(papervn_ogg *ogg);
/* 读交错的 Float32。返回实际帧数，0 表示读完。 */
int64_t papervn_ogg_read(papervn_ogg *ogg, float *interleaved, int64_t frames);
void papervn_ogg_seek(papervn_ogg *ogg, int64_t frame);
void papervn_ogg_close(papervn_ogg *ogg);

/* 视频文件解码（krkr2 带的 FFmpeg）。data 在 close 之前都要有效。 */
typedef struct papervn_video papervn_video;
typedef struct {
    double time;
    const uint8_t *y;
    const uint8_t *cb;
    const uint8_t *cr;
    int y_stride;
    int c_stride;
} papervn_video_frame;
papervn_video *papervn_video_open(const void *data, size_t size, int with_audio);
void papervn_video_close(papervn_video *video);
int papervn_video_width(papervn_video *video);
int papervn_video_height(papervn_video *video);
double papervn_video_frame_duration(papervn_video *video);
double papervn_video_next_time(papervn_video *video);
/* 没有声音（或解不了）时返回 0 */
int papervn_video_samplerate(papervn_video *video);
double papervn_video_audio_offset(papervn_video *video);
/* 再读一个数据包。文件读完时返回 0。 */
int papervn_video_pump(papervn_video *video);
/* 1：out 有效，到下次调用为止；0：这次没有画面；-1：结束。skip_nonref 非 0 时跳过不被参考的帧。 */
int papervn_video_decode(papervn_video *video, int skip_nonref, papervn_video_frame *out);
/* 交错的立体声 Float32，到下次调用为止有效；数据不够时返回 NULL。 */
const float *papervn_video_decode_audio(papervn_video *video, int *frames);

#ifdef __cplusplus
}
#endif

#endif
