#define GLES_SILENCE_DEPRECATION 1
#import <OpenGLES/EAGL.h>
#include <dlfcn.h>
#include "PaperVNGLContext.h"

// 都在主线程上调用（TJS 和 cocos2d-x 都跑在主线程）
static EAGLContext *gContext = nil;
static EAGLContext *gSaved = nil;
static int gDepth = 0;

int papervn_gl_enter(void) {
    if (gDepth++ > 0) return gContext != nil;
    if (!gContext) gContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!gContext) return 0;
    gSaved = [EAGLContext currentContext];
    if (gSaved != gContext) [EAGLContext setCurrentContext:gContext];
    return 1;
}

void papervn_gl_leave(void) {
    if (--gDepth > 0 || !gContext) return;
    if (gSaved != gContext) [EAGLContext setCurrentContext:gSaved];
    gSaved = nil;
}

void *papervn_gl_get_proc_address(const char *name) {
    return dlsym(RTLD_DEFAULT, name);
}
