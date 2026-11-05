// PaperVN 嵌入 krkr2（cocos2d-x 3.17 + KiriKiri2 引擎）的接口。
// cocos2d-x 在 iOS 上跑在主线程，用 CCDirectorCaller 的 CADisplayLink 驱动；PaperVN 只提供 CCEAGLView 和游戏路径，
// 跳过 krkr2 自带的文件选择界面直接运行。

#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/glext.h>

#include <cocos2d.h>
#include <cstdint>
#include "platform/ios/CCEAGLView-ios.h"
#include "platform/ios/CCGLViewImpl-ios.h"
#include "platform/ios/CCDirectorCaller-ios.h"

#include "environ/cocos2d/AppDelegate.h"
#include "environ/cocos2d/MainScene.h"
#include "tjsCommHead.h"
#include "MenuItemIntf.h"
#include "environ/ui/MainFileSelectorForm.h"
#include "PaperVNKiriKiriHost.h"
#include "papervn_kirikiri.h"
#include <vorbis/vorbisfile.h>

#include <spdlog/spdlog.h>
#include <spdlog/sinks/stdout_color_sinks.h>

namespace {
    std::string gDataPath;
    papervn_kirikiri_exit_callback gExitCallback = nullptr;
    papervn_kirikiri_dialog_callback gDialogCallback = nullptr;
    void *gUserData = nullptr;
    bool gStarted = false;
    bool gStopped = false;
    uint64_t gSessionGeneration = 0;
    // 引擎的调用栈上有等回答的对话框时，不能在嵌套的 run loop 里卸载引擎
    int gDialogDepth = 0;
    bool gTeardownPending = false;
    std::unique_ptr<TVPAppDelegate> gDelegate;
    // cocos2d-x 的 GLView 一直引用这个视图，引擎停下后也不能释放
    CCEAGLView *gView = nil;

    // 对话框的回答（-2 表示还在等）
    int gDialogResult = -2;
    std::string gDialogText;

    void SetAnimating(bool animating) {
        auto director = cocos2d::Director::getInstance();
        if(animating) director->startAnimation(); else director->stopAnimation();
    }

    /// 在主线程上弹出 PaperVN 的对话框，暂停画面循环，转嵌套 run loop 等回答。
    int WaitForDialog(int kind, const std::string &title, const std::string &message, std::string *text,
                      const std::vector<std::string> &buttons) {
        if(!gDialogCallback || gStopped) return -1;
        __block int result = -1;
        auto run = ^{
            std::vector<const char *> labels;
            for(const auto &button : buttons) labels.push_back(button.c_str());
            gDialogResult = -2;
            SetAnimating(false);
            ++gDialogDepth;
            gDialogCallback(gUserData, kind, title.c_str(), message.c_str(), text ? text->c_str() : nullptr,
                            labels.data(), (int32_t)labels.size());
            while(gDialogResult == -2 && !gStopped) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
            }
            --gDialogDepth;
            if(text) *text = gDialogText;
            result = gDialogResult;
            if(!gStopped) SetAnimating(true);
        };
        if([NSThread isMainThread]) run(); else dispatch_sync(dispatch_get_main_queue(), run);
        return result;
    }
}

/// 卸载当前游戏。同一进程里可以再运行下一部：cocos2d-x 的 Director、场景和画面都留着。
static void FinishTeardown(uint64_t generation) {
    if(generation != gSessionGeneration) return;
    if(!gTeardownPending) return;
    gTeardownPending = false;
    if(auto scene = TVPMainScene::GetInstance()) scene->paperVNShutdownGame();
}

static void ScheduleTeardown(uint64_t generation) {
    if(generation != gSessionGeneration) return;
    gTeardownPending = true;
    dispatch_async(dispatch_get_main_queue(), ^{
        if(generation != gSessionGeneration) return;
        if(gDialogDepth > 0) {
            // 等对话框从引擎的调用栈上退出
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 50), dispatch_get_main_queue(), ^{
                ScheduleTeardown(generation);
            });
            return;
        }
        FinishTeardown(generation);
    });
}

void PaperVNKiriKiriHostRequestExit(int code) {
    if(gStopped) return;
    gStopped = true;
    SetAnimating(false);
    [[CCDirectorCaller sharedDirectorCaller] stopMainLoop];
    ScheduleTeardown(gSessionGeneration);
    if(gExitCallback) {
        auto callback = gExitCallback;
        void *user = gUserData;
        dispatch_async(dispatch_get_main_queue(), ^{ callback(user, code); });
    }
}

std::string PaperVNKiriKiriHostDataPath() { return gDataPath; }

int PaperVNKiriKiriHostMessageBox(const std::string &title, const std::string &message,
                                  const std::vector<std::string> &buttons) {
    return WaitForDialog(0, title, message, nullptr, buttons);
}

int PaperVNKiriKiriHostInputBox(const std::string &title, const std::string &prompt, std::string &text,
                                const std::vector<std::string> &buttons) {
    return WaitForDialog(1, title, prompt, &text, buttons);
}

extern "C" void *papervn_kirikiri_create_view(double width, double height, double scale) {
    // 上一部游戏的画面接着用：cocos2d-x 的 GLView 一直绑在它上面
    if(gView) return (__bridge_retained void *)gView;
    CCEAGLView *view = [CCEAGLView viewWithFrame:CGRectMake(0, 0, width, height)
                                     pixelFormat:kEAGLColorFormatRGBA8
                                     depthFormat:GL_DEPTH24_STENCIL8_OES
                              preserveBackbuffer:NO
                                      sharegroup:nil
                                   multiSampling:NO
                                 numberOfSamples:0];
    view.contentScaleFactor = scale;
    view.multipleTouchEnabled = YES;
    gView = view;
    // AppDelegate 发现 Director 已经有 GLView 就不再自己建（自己建的不在界面上）
    auto glview = cocos2d::GLViewImpl::createWithEAGLView((__bridge void *)view);
    cocos2d::Director::getInstance()->setOpenGLView(glview);
    return (__bridge_retained void *)view;
}

extern "C" int32_t papervn_kirikiri_start(const char *game_dir, const char *data_dir, const char *resource_dir,
                                          papervn_kirikiri_exit_callback exit_callback,
                                          papervn_kirikiri_dialog_callback dialog_callback, void *user_data) {
    if(!game_dir || !data_dir || !resource_dir) return 2;
    if(gStarted && !gStopped) return 1;
    const bool restarting = gStarted;
    if(restarting) {
        if(gDialogDepth > 0) return 1;
        FinishTeardown(gSessionGeneration);
    }
    ++gSessionGeneration;
    gStarted = true;
    gStopped = false;
    gDialogResult = -2;
    gDataPath = data_dir;
    gExitCallback = exit_callback;
    gDialogCallback = dialog_callback;
    gUserData = user_data;

    static auto core = spdlog::stdout_color_mt("core");
    static auto tjs2 = spdlog::stdout_color_mt("tjs2");
    static auto plugin = spdlog::stdout_color_mt("plugin");
    spdlog::set_default_logger(core);
    spdlog::set_level(spdlog::level::info);

    // 文件选择界面看到路径就直接运行：含 startup.tjs 的文件夹，或 data.xp3 这类封包文件
    std::string path = game_dir;
    BOOL isDirectory = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:@(game_dir) isDirectory:&isDirectory];
    if(isDirectory && (path.empty() || path.back() != '/')) path += '/';
    TVPMainFileSelectorForm::filePath = path;

    if(restarting) {
        [[CCDirectorCaller sharedDirectorCaller] startMainLoop];
        SetAnimating(true);
        if(!TVPMainScene::GetInstance()->startupFrom(path)) {
            gStopped = true;
            SetAnimating(false);
            [[CCDirectorCaller sharedDirectorCaller] stopMainLoop];
            return 2;
        }
        return 0;
    }

    // AppDelegate 把搜索路径设成 "res"，相对资源根目录；PaperVN 的 res 在 Swift 包的 bundle 里，
    // 启动前就要设好（applicationDidFinishLaunching 里马上会读语言文件）
    std::string resources = resource_dir;
    while(!resources.empty() && resources.back() == '/') resources.pop_back();
    auto slash = resources.find_last_of('/');
    cocos2d::FileUtils::getInstance()->setDefaultResourceRootPath(resources.substr(0, slash + 1));

    gDelegate = std::make_unique<TVPAppDelegate>();
    // iOS 版 Application::run 调用 applicationDidFinishLaunching 后启动 CCDirectorCaller
    cocos2d::Application::getInstance()->run();
    return 0;
}

extern "C" uint64_t papervn_kirikiri_session_id(void) {
    return gSessionGeneration;
}

extern "C" void papervn_kirikiri_answer_dialog(int32_t button, const char *text) {
    gDialogText = text ? text : "";
    gDialogResult = button;
}

extern "C" void papervn_kirikiri_set_paused(int32_t paused) {
    if(!gStarted || gStopped) return;
    auto app = cocos2d::Application::getInstance();
    if(paused) app->applicationDidEnterBackground(); else app->applicationWillEnterForeground();
}

extern "C" void papervn_kirikiri_set_fast_forward(int32_t enabled) {
    if(!gStarted || gStopped) return;
    if(auto scene = TVPMainScene::GetInstance())
        scene->paperVNSetKey(cocos2d::EventKeyboard::KeyCode::KEY_LEFT_CTRL, enabled != 0);
}

extern "C" void papervn_kirikiri_secondary_click(void) {
    if(!gStarted || gStopped) return;
    if(auto scene = TVPMainScene::GetInstance()) scene->paperVNSecondaryClick();
}

static NSArray *PaperVNMenuItems(tTJSNI_MenuItem *menu, NSString *prefix) {
    NSMutableArray *result = [NSMutableArray array];
    const auto &children = menu->GetChildren();
    for(size_t index = 0; index < children.size(); ++index) {
        auto *item = static_cast<tTJSNI_MenuItem *>(children.at(index));
        if(!item || !item->GetVisible()) continue;
        ttstr caption;
        item->GetCaption(caption);
        const std::string title = caption.AsStdString();
        if(title.empty() || title == "+") continue;
        NSString *path = prefix ? [NSString stringWithFormat:@"%@/%zu", prefix, index]
                                : [NSString stringWithFormat:@"%zu", index];
        [result addObject:@{
            @"path" : path,
            @"title" : [NSString stringWithUTF8String:title.c_str()] ?: @"",
            @"enabled" : @(item->GetEnabled()),
            @"checked" : @(item->GetChecked()),
            @"children" : PaperVNMenuItems(item, path),
        }];
    }
    return result;
}

extern "C" char *papervn_kirikiri_copy_game_menu(void) {
    if(!gStarted || gStopped) return nullptr;
    auto scene = TVPMainScene::GetInstance();
    tTJSNI_MenuItem *menu = scene ? scene->paperVNGameMenu() : nullptr;
    if(!menu) return nullptr;
    NSArray *items = PaperVNMenuItems(menu, nil);
    if(items.count == 0) return nullptr;
    NSData *data = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
    if(!data) return nullptr;
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return strdup(json.UTF8String);
}

extern "C" void papervn_kirikiri_click_game_menu(const char *path) {
    if(!gStarted || gStopped || !path) return;
    auto scene = TVPMainScene::GetInstance();
    tTJSNI_MenuItem *item = scene ? scene->paperVNGameMenu() : nullptr;
    for(NSString *part in [[NSString stringWithUTF8String:path] componentsSeparatedByString:@"/"]) {
        if(!item) return;
        const size_t index = (size_t)part.integerValue;
        const auto &children = item->GetChildren();
        if(index >= children.size()) return;
        item = static_cast<tTJSNI_MenuItem *>(children.at(index));
    }
    if(item) item->OnClick();
}

static void StopCurrentGame(uint64_t session_id, bool requireMatchingSession) {
    if(requireMatchingSession && session_id != gSessionGeneration) return;
    if(!gStarted || gStopped) return;
    gStopped = true;
    gDialogResult = -1;
    // stopAnimation 之后 CCDirectorCaller 的 CADisplayLink 仍会每帧访问视图，彻底停掉
    [[CCDirectorCaller sharedDirectorCaller] stopMainLoop];
    ScheduleTeardown(gSessionGeneration);
}

extern "C" void papervn_kirikiri_stop(void) {
    StopCurrentGame(0, false);
}

extern "C" void papervn_kirikiri_stop_session(uint64_t session_id) {
    StopCurrentGame(session_id, true);
}

// MARK: - Ogg Vorbis

struct papervn_ogg {
    OggVorbis_File file;
    const uint8_t *data;
    size_t size;
    size_t position;
    int channels;
    double rate;
};

static size_t PaperVNOggRead(void *ptr, size_t size, size_t count, void *source) {
    auto *ogg = static_cast<papervn_ogg *>(source);
    size_t bytes = size * count;
    size_t available = ogg->size - ogg->position;
    if (bytes > available) bytes = available;
    if (bytes > 0) memcpy(ptr, ogg->data + ogg->position, bytes);
    ogg->position += bytes;
    return size > 0 ? bytes / size : 0;
}

static int PaperVNOggSeek(void *source, ogg_int64_t offset, int whence) {
    auto *ogg = static_cast<papervn_ogg *>(source);
    int64_t base = whence == SEEK_SET ? 0 : (whence == SEEK_CUR ? (int64_t)ogg->position : (int64_t)ogg->size);
    int64_t target = base + offset;
    if (target < 0 || target > (int64_t)ogg->size) return -1;
    ogg->position = (size_t)target;
    return 0;
}

static long PaperVNOggTell(void *source) {
    return (long)static_cast<papervn_ogg *>(source)->position;
}

papervn_ogg *papervn_ogg_open(const void *data, size_t size) {
    if (!data || size == 0) return nullptr;
    auto *ogg = new papervn_ogg();
    ogg->data = static_cast<const uint8_t *>(data);
    ogg->size = size;
    ogg->position = 0;
    ov_callbacks callbacks = {PaperVNOggRead, PaperVNOggSeek, nullptr, PaperVNOggTell};
    if (ov_open_callbacks(ogg, &ogg->file, nullptr, 0, callbacks) != 0) {
        delete ogg;
        return nullptr;
    }
    vorbis_info *info = ov_info(&ogg->file, -1);
    if (!info) {
        ov_clear(&ogg->file);
        delete ogg;
        return nullptr;
    }
    ogg->channels = info->channels;
    ogg->rate = (double)info->rate;
    return ogg;
}

int32_t papervn_ogg_channels(papervn_ogg *ogg) { return ogg ? ogg->channels : 0; }
double papervn_ogg_sample_rate(papervn_ogg *ogg) { return ogg ? ogg->rate : 0; }
int64_t papervn_ogg_total_frames(papervn_ogg *ogg) { return ogg ? (int64_t)ov_pcm_total(&ogg->file, -1) : 0; }

int64_t papervn_ogg_read(papervn_ogg *ogg, float *interleaved, int64_t frames) {
    if (!ogg || !interleaved) return 0;
    int64_t done = 0;
    int section = 0;
    while (done < frames) {
        float **channels = nullptr;
        long got = ov_read_float(&ogg->file, &channels, (int)(frames - done), &section);
        if (got == OV_HOLE) continue;
        if (got <= 0) break;
        for (long i = 0; i < got; i++) {
            for (int c = 0; c < ogg->channels; c++) {
                interleaved[(done + i) * ogg->channels + c] = channels[c][i];
            }
        }
        done += got;
    }
    return done;
}

void papervn_ogg_seek(papervn_ogg *ogg, int64_t frame) {
    if (ogg) ov_pcm_seek(&ogg->file, frame);
}

void papervn_ogg_close(papervn_ogg *ogg) {
    if (!ogg) return;
    ov_clear(&ogg->file);
    delete ogg;
}
