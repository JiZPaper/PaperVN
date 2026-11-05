#pragma once
#undef TJS_GET_NATIVE_INSTANCE
#define TJS_GET_NATIVE_INSTANCE(varname, typename)                             \
    if(!objthis)                                                               \
        return TJS_E_NATIVECLASSCRASH;                                         \
    PaperVNGLScope paperVNGLScope;                                             \
    typename *varname;                                                         \
    {                                                                          \
        tjs_error hr;                                                          \
        hr = objthis->NativeInstanceSupport(TJS_NIS_GETINSTANCE,               \
                                            TJS_NATIVE_CLASSID_NAME,           \
                                            (iTJSNativeInstance **)&varname);  \
        if(TJS_FAILED(hr))                                                     \
            return TJS_E_NATIVECLASSCRASH;                                     \
    }
