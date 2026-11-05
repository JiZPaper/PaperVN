// PaperVN：吉里吉里Z 的 OGLDrawDevice（wamsoft/krkrz，修改 BSD）在 krkr2 上的实现。
// krkr2 的窗口只能显示 iTVPTexture2D，所以 Canvas 画到离屏 FBO，每帧读回后交给窗口。
// 没有 Canvas 时和 BasicDrawDevice 一样直接显示图层合成的结果。
#include "tjsCommHead.h"
#include "tjsArray.h"
#include "DrawDevice.h"
#include "LayerIntf.h"
#include "LayerManager.h"
#include "MsgIntf.h"
#include "WindowIntf.h"
#include "WindowImpl.h"
#include "EventIntf.h"
#include "DebugIntf.h"
#include "RenderManager.h"
#include "TVPWindow.h"
#include "OpenGLHeader.h"
#include "OpenGLContext.h"
#include "GLFrameBufferObject.h"
#include "GLTexture.h"
#include "TextureUpdateRect.h"
#include "TextureIntf.h"
#include "Matrix32Intf.h"
#include "Matrix44Intf.h"
#include "CanvasIntf.h"
#include "OffscreenIntf.h"
#include "ShaderProgramIntf.h"
#include "VertexBufferIntf.h"
#include "VertexBinderIntf.h"
#include "GLCompositorIntf.h"
#include "TextureLayerTreeOwner.h"
#include <dlfcn.h>
#include <vector>

// ---- 吉里吉里Z 的 OpenGLError.cpp、EglContext.cpp 在这边的对应物
int TVPOpenGLESVersion = 300;
int TVPGetOpenGLESVersion() { return TVPOpenGLESVersion; }
void InitGLES() {}
void *TVPGLGetProcAddress(const char *name) { return dlsym(RTLD_DEFAULT, name); }

bool _CheckGLErrorAndLog(const char *file, int lineno, const char *funcname) {
    GLenum error = glGetError();
    if (error == GL_NO_ERROR) return true;
    TVPAddLog(ttstr(TJS_W("OpenGL error: ")) + TJSInt32ToHex((tjs_uint32)error));
    return false;
}

namespace {
struct PaperVNGLContextProxy : iTVPGLContext {
    int Release() override { return 0; }
    void *NativeWindow() override { return nullptr; }
    void GetSurfaceSize(int *width, int *height) override { *width = *height = 0; }
    void MakeCurrent() override {}
    void Swap() override {}
    void SetWaitVSync(bool) override {}
};
}
iTVPGLContext *iTVPGLContext::GetContext(void *, bool) {
    static PaperVNGLContextProxy proxy;
    return &proxy;
}

// ---- 绘制设备
class tTVPOGLDrawDevice : public tTVPDrawDevice, public tTVPContinuousEventCallbackIntf {
    typedef tTVPDrawDevice inherited;

    iTJSDispatch2 *Self;
    iTJSDispatch2 *Owner = nullptr;
    tTJSVariant WindowObject;
    tTJSNI_Window *NIWindow = nullptr;

    tTJSNativeClass *TextureClass;
    tTJSVariant TextureObject;
    tTJSNI_Texture *TextureInstance = nullptr;
    TextureUpdateRect mTextureUpdateRect;
    tTJSVariant MatrixObject;
    tTJSNI_Matrix32 *MatrixInstance = nullptr;
    tTJSVariant CanvasObject;
    tTJSNI_Canvas *CanvasInstance = nullptr;

    bool ContextReady = false;
    bool DoCreateCanvas = false;
    bool LayerDirty = true;
    bool HookAdded = false;
    bool OnDrawDisabled = false;
    int FailedDraws = 0;

    GLFrameBufferObject *ScreenFBO = nullptr;
    iTVPTexture2D *Output = nullptr;
    std::vector<tjs_uint8> ReadBuffer;

    ~tTVPOGLDrawDevice() override {}

    void CreateTexture();
    void DestroyTexture();
    void InitMatrix();
    void CreateCanvas();
    void SetCanvasObject(const tTJSVariant &val);
    void InitContext();
    void DoneContext();
    void UploadLayerTexture();

public:
    explicit tTVPOGLDrawDevice(iTJSDispatch2 *self);

    void RequestCreateCanvas();
    void ResumeOnDraw() { OnDrawDisabled = false; FailedDraws = 0; }
    const tTJSVariant &GetCanvasObject() const { return CanvasObject; }
    const tTJSVariant &GetWindowObject() const { return WindowObject; }
    const tTJSVariant &GetTextureObject() const { return TextureObject; }
    const tTJSVariant &GetMatrixObject() const { return MatrixObject; }

    void Destruct() override;
    void SetWindowInterface(iTVPWindow *window) override;
    void AddLayerManager(iTVPLayerManager *manager) override;
    void NotifyLayerResize(iTVPLayerManager *manager) override;
    void Show() override;
    void StartBitmapCompletion(iTVPLayerManager *manager) override {}
    void NotifyBitmapCompleted(iTVPLayerManager *manager, tjs_int x, tjs_int y, tTVPBaseTexture *bmp,
                               const tTVPRect &cliprect, tTVPLayerType type, tjs_int opacity) override { LayerDirty = true; }
    void EndBitmapCompletion(iTVPLayerManager *manager) override {}
    void SetShowUpdateRect(bool) override {}
    void OnContinuousCallback(tjs_uint64) override {
        if (Window && CanvasInstance) Window->RequestUpdate();
    }
};

tTVPOGLDrawDevice::tTVPOGLDrawDevice(iTJSDispatch2 *self) : Self(self) {
    if (Self) Self->AddRef();
    TextureClass = TVPCreateNativeClass_Texture();
    tTJSNativeClass *matrixClass = TVPCreateNativeClass_Matrix32();
    iTJSDispatch2 *newobj = nullptr;
    if (TJS_FAILED(matrixClass->CreateNew(0, nullptr, nullptr, &newobj, 0, nullptr, matrixClass))) {
        matrixClass->Release();
        TVPThrowExceptionMessage(TVPInternalError, TJS_W("tTJSNI_Matrix32::Construct"));
    }
    MatrixObject = tTJSVariant(newobj, newobj);
    newobj->Release();
    MatrixObject.AsObjectClosureNoAddRef().Object->NativeInstanceSupport(
        TJS_NIS_GETINSTANCE, tTJSNC_Matrix32::ClassID, (iTJSNativeInstance **)&MatrixInstance);
    matrixClass->Release();
}

void tTVPOGLDrawDevice::SetCanvasObject(const tTJSVariant &val) {
    if (CanvasObject.Type() == tvtObject)
        CanvasObject.AsObjectClosureNoAddRef().Invalidate(0, nullptr, nullptr, CanvasObject.AsObjectNoAddRef());
    CanvasObject = val;
    CanvasInstance = nullptr;
    if (CanvasObject.Type() == tvtObject) {
        tTJSVariantClosure clo = CanvasObject.AsObjectClosureNoAddRef();
        if (clo.Object && TJS_FAILED(clo.Object->NativeInstanceSupport(TJS_NIS_GETINSTANCE, tTJSNC_Canvas::ClassID,
                                                                       (iTJSNativeInstance **)&CanvasInstance))) {
            CanvasInstance = nullptr;
            TVPThrowExceptionMessage(TVPCannotRetriveInstance, TJS_W("canvas"));
        }
    }
}

void tTVPOGLDrawDevice::CreateCanvas() {
    iTJSDispatch2 *cls = new tTJSNC_Canvas();
    iTJSDispatch2 *newobj = nullptr;
    tTJSVariant param(Owner, Owner);
    tTJSVariant *pparam[1] = {&param};
    tjs_error hr = cls->CreateNew(0, nullptr, nullptr, &newobj, 1, pparam, cls);
    cls->Release();
    if (TJS_FAILED(hr)) TVPThrowExceptionMessage(TVPInternalError, TJS_W("tTJSNI_Canvas::Construct"));
    SetCanvasObject(tTJSVariant(newobj, newobj));
    newobj->Release();
    if (!HookAdded) {
        TVPAddContinuousEventHook(this);
        HookAdded = true;
    }
    Window->RequestUpdate();
}

void tTVPOGLDrawDevice::RequestCreateCanvas() {
    if (!ContextReady) {
        DoCreateCanvas = true;
        return;
    }
    if (!CanvasInstance) {
        PaperVNGLScope scope;
        CreateCanvas();
    }
}

void tTVPOGLDrawDevice::DestroyTexture() {
    if (TextureObject.Type() == tvtObject)
        TextureObject.AsObjectClosureNoAddRef().Invalidate(0, nullptr, nullptr, TextureObject.AsObjectNoAddRef());
    TextureObject.Clear();
    TextureInstance = nullptr;
}

void tTVPOGLDrawDevice::CreateTexture() {
    if (TextureInstance || !TextureClass) return;
    tjs_int w = 0, h = 0;
    GetSrcSize(w, h);
    if (w <= 0 || h <= 0) return;
    iTJSDispatch2 *newobj = nullptr;
    tTJSVariant pw = w, ph = h;
    tTJSVariant *pparam[2] = {&pw, &ph};
    if (TJS_FAILED(TextureClass->CreateNew(0, nullptr, nullptr, &newobj, 2, pparam, TextureClass)))
        TVPThrowExceptionMessage(TVPInternalError, TJS_W("tTJSNI_Texture::Construct"));
    TextureObject = tTJSVariant(newobj, newobj);
    newobj->Release();
    tTJSVariantClosure clo = TextureObject.AsObjectClosureNoAddRef();
    if (clo.Object && TJS_FAILED(clo.Object->NativeInstanceSupport(TJS_NIS_GETINSTANCE, tTJSNC_Texture::ClassID,
                                                                   (iTJSNativeInstance **)&TextureInstance))) {
        TextureInstance = nullptr;
        TVPThrowExceptionMessage(TVPCannotRetriveInstance, TJS_W("texture"));
    }
    mTextureUpdateRect.Resize(w, h);
    LayerDirty = true;
    InitMatrix();
}

void tTVPOGLDrawDevice::InitMatrix() {
    if (!MatrixInstance || !TextureInstance || !NIWindow) return;
    tjs_int w = NIWindow->GetInnerWidth(), h = NIWindow->GetInnerHeight();
    if (w <= 0 || h <= 0) GetSrcSize(w, h);
    MatrixInstance->SetIdentity();
    MatrixInstance->SetScale((tjs_real)w / TextureInstance->GetWidth(), (tjs_real)h / TextureInstance->GetHeight());
}

void tTVPOGLDrawDevice::InitContext() {
    PaperVNGLScope scope;
    if (!scope.ok) TVPThrowExceptionMessage(TJS_W("Failed to create the OpenGL ES 3 context."));
    ContextReady = true;
    if (DoCreateCanvas) {
        DoCreateCanvas = false;
        CreateCanvas();
    }
    CreateTexture();
    if (Self) {
        static ttstr eventname(TJS_W("onInit"));
        TVPPostEvent(Self, Self, eventname, 0, TVP_EPT_IMMEDIATE, 0, nullptr);
    }
}

void tTVPOGLDrawDevice::DoneContext() {
    if (!ContextReady) return;
    PaperVNGLScope scope;
    if (Self) {
        static ttstr eventname(TJS_W("onDone"));
        TVPPostEvent(Self, Self, eventname, 0, TVP_EPT_IMMEDIATE, 0, nullptr);
    }
    if (HookAdded) {
        TVPRemoveContinuousEventHook(this);
        HookAdded = false;
    }
    DestroyTexture();
    SetCanvasObject(tTJSVariant());
    delete ScreenFBO;
    ScreenFBO = nullptr;
    if (Output) {
        Output->Release();
        Output = nullptr;
    }
    ContextReady = false;
}

void tTVPOGLDrawDevice::Destruct() {
    DoneContext();
    WindowObject.Clear();
    if (Owner) Owner->Release();
    Owner = nullptr;
    if (Self) Self->Release();
    Self = nullptr;
    if (TextureClass) TextureClass->Release();
    TextureClass = nullptr;
    inherited::Destruct();
}

void tTVPOGLDrawDevice::SetWindowInterface(iTVPWindow *window) {
    inherited::SetWindowInterface(window);
    if (Owner) Owner->Release();
    Owner = Window->GetWindowDispatch();
    WindowObject = tTJSVariant(Owner, Owner);
    NIWindow = nullptr;
    if (TJS_FAILED(Owner->NativeInstanceSupport(TJS_NIS_GETINSTANCE, tTJSNC_Window::ClassID, (iTJSNativeInstance **)&NIWindow)))
        TVPThrowExceptionMessage(TVPSpecifyWindow);
    if (!ContextReady) InitContext();
}

void tTVPOGLDrawDevice::AddLayerManager(iTVPLayerManager *manager) {
    if (!Managers.empty()) TVPThrowExceptionMessage(TVPBasicDrawDeviceDoesNotSupporteLayerManagerMoreThanOne);
    inherited::AddLayerManager(manager);
    manager->SetDesiredLayerType(ltOpaque);
    LayerDirty = true;
}

void tTVPOGLDrawDevice::NotifyLayerResize(iTVPLayerManager *manager) {
    inherited::NotifyLayerResize(manager);
    if (!ContextReady) return;
    PaperVNGLScope scope;
    DestroyTexture();
    CreateTexture();
}

void tTVPOGLDrawDevice::UploadLayerTexture() {
    if (!TextureInstance || !LayerDirty || Managers.empty()) return;
    iTVPBaseBitmap *buf = Managers.back()->GetDrawBuffer();
    if (!buf) return;
    tjs_int w = std::min<tjs_int>(buf->GetWidth(), TextureInstance->GetWidth());
    tjs_int h = std::min<tjs_int>(buf->GetHeight(), TextureInstance->GetHeight());
    if (w <= 0 || h <= 0) return;
    mTextureUpdateRect.Clear();
    mTextureUpdateRect.Update(TextureInstance, 0, 0, w, h, (const tjs_uint8 *)buf->GetScanLine(0), buf->GetPitchBytes(), 0, 0);
    mTextureUpdateRect.RenderToTexture(TextureInstance);
    LayerDirty = false;
}

void tTVPOGLDrawDevice::Show() {
    if (!Window) return;
    iWindowLayer *form = Window->getForm();
    if (!form) return;
    if (!CanvasInstance) {
        // Canvas 还没建：和 BasicDrawDevice 相同
        if (!Managers.empty()) {
            iTVPBaseBitmap *buf = Managers.back()->GetDrawBuffer();
            if (buf) form->UpdateDrawBuffer(buf->GetTexture());
        }
        return;
    }
    tjs_int w = NIWindow ? NIWindow->GetInnerWidth() : 0, h = NIWindow ? NIWindow->GetInnerHeight() : 0;
    if (w <= 0 || h <= 0) GetSrcSize(w, h);
    if (w <= 0 || h <= 0) return;
    {
        PaperVNGLScope scope;
        if (!scope.ok) return;
        UploadLayerTexture();
        if (!ScreenFBO || (tjs_int)ScreenFBO->width() != w || (tjs_int)ScreenFBO->height() != h) {
            delete ScreenFBO;
            ScreenFBO = new GLFrameBufferObject();
            if (!ScreenFBO->create(w, h, false)) {
                delete ScreenFBO;
                ScreenFBO = nullptr;
                return;
            }
        }
        ScreenFBO->bindFramebuffer();
        CanvasInstance->SetSurfaceSize(w, h);
        CanvasInstance->BeginDrawing();
        try {
            if (Self && !OnDrawDisabled) {
                static ttstr eventname(TJS_W("onDraw"));
                TVPPostEvent(Self, Self, eventname, 0, TVP_EPT_IMMEDIATE, 0, nullptr);
            }
        } catch (...) {
            CanvasInstance->EndDrawing();
            if (++FailedDraws >= 10) {
                OnDrawDisabled = true;
                TVPAddImportantLog(TJS_W("OGLDrawDevice: onDraw suspended after repeated exceptions. Call drawDevice.resumeOnDraw() to retry."));
            }
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            throw;
        }
        FailedDraws = 0;
        CanvasInstance->EndDrawing();
        ScreenFBO->bindFramebuffer();
        ReadBuffer.resize((size_t)w * h * 4);
        glPixelStorei(GL_PACK_ALIGNMENT, 4);
        glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, ReadBuffer.data());
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }
    // GL 的第 0 行在画面底部
    tjs_int pitch = w * 4;
    std::vector<tjs_uint8> line(pitch);
    for (tjs_int y = 0; y < h / 2; y++) {
        tjs_uint8 *a = ReadBuffer.data() + (size_t)y * pitch, *b = ReadBuffer.data() + (size_t)(h - 1 - y) * pitch;
        memcpy(line.data(), a, pitch);
        memcpy(a, b, pitch);
        memcpy(b, line.data(), pitch);
    }
    if (Output && ((tjs_int)Output->GetWidth() != w || (tjs_int)Output->GetHeight() != h)) {
        Output->Release();
        Output = nullptr;
    }
    if (!Output) {
        Output = TVPGetRenderManager()->CreateTexture2D(ReadBuffer.data(), pitch, w, h, TVPTextureFormat::RGBA, RENDER_CREATE_TEXTURE_FLAG_NO_COMPRESS);
    } else {
        tTVPRect rect(0, 0, w, h);
        Output->Update(ReadBuffer.data(), TVPTextureFormat::RGBA, pitch, rect);
    }
    if (Output) form->UpdateDrawBuffer(Output);
}

// ---- TJS 类
class tTJSNI_OGLDrawDevice : public tTJSNativeInstance {
    tTVPOGLDrawDevice *Device = nullptr;
public:
    tjs_error Construct(tjs_int, tTJSVariant **, iTJSDispatch2 *tjs_obj) override {
        Device = new tTVPOGLDrawDevice(tjs_obj);
        return TJS_S_OK;
    }
    void Invalidate() override {
        if (Device) Device->Destruct(), Device = nullptr;
    }
    tTVPOGLDrawDevice *GetDevice() const { return Device; }
};

class tTJSNC_OGLDrawDevice : public tTJSNativeClass {
public:
    tTJSNC_OGLDrawDevice();
    static tjs_uint32 ClassID;
private:
    iTJSNativeInstance *CreateNativeInstance() override { return new tTJSNI_OGLDrawDevice(); }
};
tjs_uint32 tTJSNC_OGLDrawDevice::ClassID = (tjs_uint32)-1;

tTJSNC_OGLDrawDevice::tTJSNC_OGLDrawDevice() : tTJSNativeClass(TJS_W("OGLDrawDevice")) {
    TJS_BEGIN_NATIVE_MEMBERS(OGLDrawDevice)
    TJS_DECL_EMPTY_FINALIZE_METHOD
    TJS_BEGIN_NATIVE_CONSTRUCTOR_DECL(_this, tTJSNI_OGLDrawDevice, OGLDrawDevice) { return TJS_S_OK; }
    TJS_END_NATIVE_CONSTRUCTOR_DECL(OGLDrawDevice)
    TJS_BEGIN_NATIVE_METHOD_DECL(recreate) { return TJS_S_OK; }
    TJS_END_NATIVE_METHOD_DECL(recreate)
    TJS_BEGIN_NATIVE_METHOD_DECL(createCanvas) {
        TJS_GET_NATIVE_INSTANCE(_this, tTJSNI_OGLDrawDevice);
        _this->GetDevice()->RequestCreateCanvas();
        return TJS_S_OK;
    }
    TJS_END_NATIVE_METHOD_DECL(createCanvas)
    TJS_BEGIN_NATIVE_METHOD_DECL(resumeOnDraw) {
        TJS_GET_NATIVE_INSTANCE(_this, tTJSNI_OGLDrawDevice);
        _this->GetDevice()->ResumeOnDraw();
        return TJS_S_OK;
    }
    TJS_END_NATIVE_METHOD_DECL(resumeOnDraw)
#define PAPERVN_DEVICE_PROP(name, getter)                                      \
    TJS_BEGIN_NATIVE_PROP_DECL(name) {                                         \
        TJS_BEGIN_NATIVE_PROP_GETTER {                                         \
            TJS_GET_NATIVE_INSTANCE(_this, tTJSNI_OGLDrawDevice);              \
            if (result) *result = _this->GetDevice()->getter();                \
            return TJS_S_OK;                                                   \
        }                                                                      \
        TJS_END_NATIVE_PROP_GETTER                                             \
        TJS_DENY_NATIVE_PROP_SETTER                                            \
    }                                                                          \
    TJS_END_NATIVE_PROP_DECL(name)
    TJS_BEGIN_NATIVE_PROP_DECL(interface) {
        TJS_BEGIN_NATIVE_PROP_GETTER {
            TJS_GET_NATIVE_INSTANCE(_this, tTJSNI_OGLDrawDevice);
            // 要转成基类指针：Window 按 iTVPDrawDevice* 取
            if (result) *result = reinterpret_cast<tjs_int64>(static_cast<iTVPDrawDevice *>(_this->GetDevice()));
            return TJS_S_OK;
        }
        TJS_END_NATIVE_PROP_GETTER
        TJS_DENY_NATIVE_PROP_SETTER
    }
    TJS_END_NATIVE_PROP_DECL(interface)
    PAPERVN_DEVICE_PROP(window, GetWindowObject)
    PAPERVN_DEVICE_PROP(canvas, GetCanvasObject)
    PAPERVN_DEVICE_PROP(texture, GetTextureObject)
    PAPERVN_DEVICE_PROP(matrix, GetMatrixObject)
    TJS_END_NATIVE_MEMBERS
}

// ScriptMgnIntf.cpp 启动时调用
void TVPPaperVNRegisterOGLClasses(iTJSDispatch2 *global, iTJSDispatch2 *windowclass) {
    auto reg = [global](const tjs_char *name, iTJSDispatch2 *object) {
        // 不带 objthis：带了的话 super.Canvas() 这样的调用 objthis 会变成类本身
        tTJSVariant val(object);
        object->Release();
        global->PropSet(TJS_MEMBERENSURE, name, nullptr, &val, global);
    };
    reg(TJS_W("Canvas"), TVPCreateNativeClass_Canvas());
    reg(TJS_W("GLCompositor"), TVPCreateNativeClass_GLCompositor());
    reg(TJS_W("Texture"), TVPCreateNativeClass_Texture());
    reg(TJS_W("TextureLayerTreeOwner"), TVPCreateNativeClass_TextureLayerTreeOwner());
    reg(TJS_W("Offscreen"), TVPCreateNativeClass_Offscreen());
    reg(TJS_W("Matrix44"), TVPCreateNativeClass_Matrix44());
    reg(TJS_W("Matrix32"), TVPCreateNativeClass_Matrix32());
    reg(TJS_W("ShaderProgram"), TVPCreateNativeClass_ShaderProgram());
    reg(TJS_W("VertexBuffer"), TVPCreateNativeClass_VertexBuffer());
    reg(TJS_W("VertexBinder"), TVPCreateNativeClass_VertexBinder());
    iTJSDispatch2 *device = new tTJSNC_OGLDrawDevice();
    tTJSVariant val(device);
    device->Release();
    global->PropSet(TJS_MEMBERENSURE, TJS_W("OGLDrawDevice"), nullptr, &val, global);
    windowclass->PropSet(TJS_MEMBERENSURE | TJS_IGNOREPROP | TJS_STATICMEMBER, TJS_W("OGLDrawDevice"), nullptr, &val, windowclass);
}
