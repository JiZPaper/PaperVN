// PaperVN：krkrgles、Live2D、OGLDrawDevice 共用的 OpenGL ES 3 上下文。
// krkr2 的 cocos2d-x 用自己的 ES2 上下文画界面，还缓存了 GL 状态，这边的绘制不能碰它。
// 吉里吉里Z 的做法是让 EGL 上下文一直是当前上下文；这里改成每次进入原生调用时切过去，离开时切回，
// 所以 TJS 里的 makeCurrent() 不需要做事，脚本运行期间 cocos 的上下文也不会被换掉。
#pragma once

#ifdef __cplusplus
extern "C" {
#endif
/// 进入。返回 0 表示这台设备拿不到 ES3 上下文
int papervn_gl_enter(void);
void papervn_gl_leave(void);
/// 上下文的函数地址查询（GLESAdaptor.GLGetProcAddress 用）
void *papervn_gl_get_proc_address(const char *name);
#ifdef __cplusplus
}

struct PaperVNGLScope {
    bool ok;
    PaperVNGLScope() : ok(papervn_gl_enter() != 0) {}
    ~PaperVNGLScope() { papervn_gl_leave(); }
    PaperVNGLScope(const PaperVNGLScope &) = delete;
    PaperVNGLScope &operator=(const PaperVNGLScope &) = delete;
};
#endif
