// PaperVN：吉里吉里Z 的 GL 代码用 glad 加载 GLES；iOS 直接链接系统的 OpenGLES
#pragma once
#include <OpenGLES/ES3/gl.h>
#include <OpenGLES/ES3/glext.h>
#ifndef GL_BGRA_EXT
#define GL_BGRA_EXT 0x80E1
#endif
#ifndef GL_BGRA8_EXT
#define GL_BGRA8_EXT 0x93A1
#endif
typedef void (*GLADapiproc)(void);
