#pragma once
#include "gles2.h"
#include "PaperVNGLContext.h"
inline GLADapiproc eglGetProcAddress(const char *name) { return (GLADapiproc)papervn_gl_get_proc_address(name); }
