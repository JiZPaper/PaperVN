// PaperVN：吉里吉里Z 的 GL 绘图接口编进 krkr2 时补上名字差异
#pragma once
#ifndef TJS_INTF_METHOD
#define TJS_INTF_METHOD
#endif
#ifdef __cplusplus
#include "tjsCommHead.h"
#include "tjsNative.h"
#include "tjsObject.h"
#include "ComplexRect.h"
#include "PaperVNGLContext.h"
#include <algorithm>
#include <cstring>
#include <string>

// krkr2 没有这些消息。文字照吉里吉里Z 的英文版
#define TVPNotFoundInShader TJS_W("%1 is not found in the shader.")
#define TVPInsufficientNumberOfArrays TJS_W("Insufficient number of arrays.")
#define TVPCannotRetriveInstance TJS_W("Cannot retrieve instance from %1.")
#define TVPCaptureAreaOver TJS_W("Capture area is out of range.")
#define TVPParameterRequireClassInstance TJS_W("Parameter %1 requires a class instance.")
#define TVPArrayIsZero TJS_W("The array is empty.")
#define TVPVertexBinderIsEmpty TJS_W("VertexBinder is empty.")
#define TVPUnknownDataType TJS_W("Unknown data type.")
#define TVPThisVertexBufferIsConstant TJS_W("This vertex buffer is constant.")
#define TVPThisMethodRequireVBO TJS_W("This method requires a vertex buffer object.")
#define TVPShaderCompileError TJS_W("Shader compile error.")
#define TVPNotHavePrimaryLayer TJS_W("There is no primary layer.")
#define TVPIndexTypeIsInvalid TJS_W("Index type is invalid.")
#define TVPIncompatibleTexture TJS_W("Incompatible texture.")
#define TVPFBOCreateError TJS_W("Failed to create frame buffer object.")
#define TVPCanvasBeginStencilClipNoCanvasSizeCallWhileDrawing TJS_W("beginStencilClip requires a canvas size while drawing.")
#define TVPCanvasBeginEffectNoCanvasSizeCallWhileDrawing TJS_W("beginEffect requires a canvas size while drawing.")
#define TVPCannotExchangeTexture TJS_W("Cannot exchange the texture.")

#ifndef GL_FRAMEBUFFER_SRGB_EXT
#define GL_FRAMEBUFFER_SRGB_EXT 0x8DB9
#endif

// 吉里吉里Z 的 tjsNative.h 里有，krkr2 的没有
inline iTJSNativeInstance *TJSGetNativeInstance(tjs_int32 classid, tTJSVariant *param) {
    if (param && param->Type() == tvtObject) {
        tTJSVariantClosure clo = param->AsObjectClosureNoAddRef();
        if (clo.Object) {
            iTJSNativeInstance *ret = nullptr;
            if (TJS_SUCCEEDED(clo.Object->NativeInstanceSupport(TJS_NIS_GETINSTANCE, classid, &ret))) return ret;
        }
    }
    return nullptr;
}
inline const iTJSNativeInstance *TJSGetNativeInstance(tjs_int32 classid, const tTJSVariant *param) {
    return TJSGetNativeInstance(classid, const_cast<tTJSVariant *>(param));
}

// krkr2 的图层内存就是 RGBA，和 GL 相同：吉里吉里Z 的“红蓝交换”在这里只是复制
inline void TVPRedBlueSwapCopy(tjs_uint32 *dest, const tjs_uint32 *src, tjs_int len) {
    memcpy(dest, src, (size_t)len * 4);
}
#define TVPRenderStatsAddTexUpload(...) ((void)0)
#define TVPRenderStatsBumpUploadFrame(...) ((void)0)

inline bool TVPUtf16ToUtf8(std::string &out, const std::u16string &in) {
    out.clear();
    for (size_t i = 0; i < in.size(); i++) {
        uint32_t c = in[i];
        if (c >= 0xD800 && c < 0xDC00 && i + 1 < in.size()) {
            c = 0x10000 + ((c - 0xD800) << 10) + (in[++i] - 0xDC00);
        }
        if (c < 0x80) out += (char)c;
        else if (c < 0x800) { out += (char)(0xC0 | c >> 6); out += (char)(0x80 | (c & 63)); }
        else if (c < 0x10000) { out += (char)(0xE0 | c >> 12); out += (char)(0x80 | (c >> 6 & 63)); out += (char)(0x80 | (c & 63)); }
        else { out += (char)(0xF0 | c >> 18); out += (char)(0x80 | (c >> 12 & 63)); out += (char)(0x80 | (c >> 6 & 63)); out += (char)(0x80 | (c & 63)); }
    }
    return true;
}


#define TVPGLCompositor1stArgumentMustBeAWindow TJS_W("The first argument of GLCompositor must be a Window.")
#define TVPGLCompositorFailedToGetGLContext TJS_W("GLCompositor failed to get the GL context.")
// iOS 的 ES3 没有 glCopyImageSubData。TVPOpenGLESVersion 固定为 300、也没有扩展，走不到这两个调用
#define glCopyImageSubData(...) ((void)0)
#define glCopyImageSubDataEXT(...) ((void)0)

inline bool TVPUtf16ToUtf8(std::string &out, const std::string &in) {
    // krkr2 的 ttstr::AsStdString 已经是 UTF-8
    out = in;
    return true;
}

// 吉里吉里Z 放在 LayerTreeOwner.h 里
class tTJSQuickPropertyObject : tTJSDispatch {
    tTJSVariant val;
public:
    tTJSQuickPropertyObject() : tTJSDispatch() {}
    ~tTJSQuickPropertyObject() {}
    tjs_error PropGet(tjs_uint32 flag, const tjs_char *membername, tjs_uint32 *hint, tTJSVariant *result, iTJSDispatch2 *objthis) override {
        if (membername) return TJS_E_MEMBERNOTFOUND;
        if (result) *result = val;
        return TJS_S_OK;
    }
    tjs_error PropSet(tjs_uint32 flag, const tjs_char *membername, tjs_uint32 *hint, const tTJSVariant *param, iTJSDispatch2 *objthis) override {
        if (membername) return TJS_E_MEMBERNOTFOUND;
        if (param) val = *param;
        return TJS_S_OK;
    }
    static void Wrap(tTJSVariant &v) {
        tTJSQuickPropertyObject *self = new tTJSQuickPropertyObject();
        self->val = v;
        v = tTJSVariant(self, self);
        self->Release();
    }
    static void Unwrap(tTJSVariant &v) {
        if (v.Type() == tvtObject) {
            tTJSVariant out;
            iTJSDispatch2 *obj = v.AsObjectNoAddRef();
            if (obj && TJS_SUCCEEDED(obj->PropGet(0, nullptr, nullptr, &out, obj))) v = out;
        }
    }
};

// 9-patch 信息：外面一圈 1 像素的标记（吉里吉里Z 的 tTVPBaseBitmap::Read9PatchInfo）
template <class B>
inline void PaperVNRead9PatchInfo(const B *bitmap, tTVPRect &scale, tTVPRect &margin) {
    const tjs_int w = bitmap->GetWidth(), h = bitmap->GetHeight();
    const tjs_uint32 *src = (const tjs_uint32 *)bitmap->GetScanLine(0);
    const tjs_int pitch = bitmap->GetPitchBytes() / (tjs_int)sizeof(tjs_uint32);
    const tjs_uint32 *bottom = (const tjs_uint32 *)bitmap->GetScanLine(h - 1);
    scale = tTVPRect(-1, -1, -1, -1);
    margin = tTVPRect(-1, -1, -1, -1);
    for (tjs_int x = 1; x < w - 1; x++) {
        if (scale.left == -1 && (src[x] & 0xff000000) == 0xff000000) scale.left = x;
        else if (scale.left != -1 && scale.right == -1 && (src[x] & 0xff000000) == 0) scale.right = x;
        if (margin.left == -1 && (bottom[x] & 0xff000000) == 0xff000000) margin.left = x - 1;
        else if (margin.left != -1 && margin.right == -1 && (bottom[x] & 0xff000000) == 0) margin.right = w - x - 1;
        if (scale.right != -1 && margin.right != -1) break;
    }
    if (scale.left != -1 && scale.right == -1) scale.right = w - 1;
    if (margin.left != -1 && margin.right == -1) margin.right = 0;
    for (tjs_int y = 1; y < h - 1; y++) {
        tjs_uint32 lp = src[y * pitch], rp = src[y * pitch + w - 1];
        if (scale.top == -1 && (lp & 0xff000000) == 0xff000000) scale.top = y;
        else if (scale.top != -1 && scale.bottom == -1 && (lp & 0xff000000) == 0) scale.bottom = y;
        if (margin.top == -1 && (rp & 0xff000000) == 0xff000000) margin.top = y - 1;
        else if (margin.top != -1 && margin.bottom == -1 && (rp & 0xff000000) == 0) margin.bottom = h - y - 1;
        if (scale.bottom != -1 && margin.bottom != -1) break;
    }
    if (scale.top != -1 && scale.bottom == -1) scale.bottom = h - 1;
    if (margin.top != -1 && margin.bottom == -1) margin.bottom = 0;
}

// 32 位和 8 位之间转换（调用前已经 DoGrayScale 过）
template <class B>
inline void PaperVNCopyBitWidth(B *dest, const B *src) {
    const tjs_int w = std::min<tjs_int>(dest->GetWidth(), src->GetWidth());
    const tjs_int h = std::min<tjs_int>(dest->GetHeight(), src->GetHeight());
    for (tjs_int y = 0; y < h; y++) {
        tjs_uint8 *d = (tjs_uint8 *)dest->GetScanLineForWrite(y);
        const tjs_uint8 *s = (const tjs_uint8 *)src->GetScanLine(y);
        if (dest->Is8BPP()) {
            for (tjs_int x = 0; x < w; x++) d[x] = s[x * 4];
        } else {
            for (tjs_int x = 0; x < w; x++) {
                d[x * 4] = d[x * 4 + 1] = d[x * 4 + 2] = s[x];
                d[x * 4 + 3] = 255;
            }
        }
    }
}

// 每个 TJS 原生方法都在这个宏之后开始用 GL，所以在这里切换上下文
#include "PaperVNOGLScopeMacros.h"
#endif
