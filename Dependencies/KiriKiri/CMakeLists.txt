# PaperVN 在 iOS 上运行 KiriKiri（吉里吉里）视觉小说用的静态库：
# krkr2（https://github.com/2468785842/krkr2，MIT）的 core 和 plugins，加上 PaperVN 的 iOS 平台层与接口。
# 由 Tools/构建KiriKiri.sh 调用，krkr2 源码在仓库外，对它的修改都在 patches/krkr2-ios.patch。
cmake_minimum_required(VERSION 3.28)

project(PaperVNKiriKiri LANGUAGES C CXX OBJC OBJCXX)

if(NOT KRKR2_ROOT)
    message(FATAL_ERROR "需要 -DKRKR2_ROOT=<krkr2 源码目录>")
endif()

# 以下照 krkr2 顶层 CMakeLists.txt
add_compile_definitions(
    $<$<CONFIG:Debug>:DEBUG>
    $<$<CONFIG:Debug>:_DEBUG>
    $<$<NOT:$<CONFIG:Debug>>:NDEBUG>
)
set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_compile_options(-Wno-inconsistent-missing-override)

set(KRKR2CORE_PATH ${KRKR2_ROOT}/cpp/core)
set(KRKR2PLUGIN_PATH ${KRKR2_ROOT}/cpp/plugins)

add_subdirectory(${KRKR2_ROOT}/cpp/external external)
add_subdirectory(${KRKR2CORE_PATH} core)
add_subdirectory(${KRKR2PLUGIN_PATH} plugins)

add_library(papervn_kirikiri STATIC
    src/PaperVNKiriKiri.mm
    src/platform_ios.mm
    src/PaperVNVideo.cpp
)
target_include_directories(papervn_kirikiri PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${KRKR2CORE_PATH}/environ/cocos2d
)
target_compile_options(papervn_kirikiri PRIVATE -fobjc-arc)
target_link_libraries(papervn_kirikiri PUBLIC krkr2plugin krkr2core)

find_package(spdlog CONFIG REQUIRED)
target_link_libraries(papervn_kirikiri PRIVATE spdlog::spdlog)

# Live2D：krkrlive2d 插件 + wtnbgo/live2d 驱动 + Cubism Framework（Live2D Open Software License）。
# Cubism Core 是官方预编译库，由 Tools/构建KiriKiri.sh 合进静态库。这些源码都在仓库外，缺了就不编，游戏调用时报插件不存在。
get_filename_component(PAPERVN_THIRD_PARTY ${KRKR2_ROOT}/.. ABSOLUTE)
set(L2D_PLUGIN ${PAPERVN_THIRD_PARTY}/krkr-plugins/krkrlive2d/src)
set(L2D_DRIVER ${PAPERVN_THIRD_PARTY}/live2d-driver/src)
set(L2D_FRAMEWORK ${PAPERVN_THIRD_PARTY}/live2d-driver/external/CubismNativeFramework/src)
set(L2D_MINIZIP ${PAPERVN_THIRD_PARTY}/minizip-ng)
set(L2D_CORE ${PAPERVN_THIRD_PARTY}/cubism-sdk/CubismSdkForNative-5-r.5/Core)
if(EXISTS ${L2D_PLUGIN}/Live2D.cpp AND EXISTS ${L2D_FRAMEWORK}/CubismFramework.cpp AND EXISTS ${L2D_CORE}/include/Live2DCubismCore.h)
    file(GLOB_RECURSE L2D_FRAMEWORK_SOURCES ${L2D_FRAMEWORK}/*.cpp)
    list(FILTER L2D_FRAMEWORK_SOURCES EXCLUDE REGEX "/Rendering/(D3D9|D3D11|Metal|Vulkan)/")
    add_library(papervn_live2d STATIC
        ${L2D_FRAMEWORK_SOURCES}
        ${L2D_DRIVER}/MyCubismPose.cpp
        ${L2D_DRIVER}/MyCubismModel.cpp
        ${L2D_DRIVER}/LAppModel.cpp
        ${L2D_DRIVER}/plive2d.cpp
        ${L2D_DRIVER}/zipinfo.cpp
        ${L2D_DRIVER}/LAppAllocator.cpp
        ${L2D_DRIVER}/ogl/LAppModelOGL.cpp
        ${L2D_MINIZIP}/mz_crypt.c
        ${L2D_MINIZIP}/mz_os.c
        ${L2D_MINIZIP}/mz_os_posix.c
        ${L2D_MINIZIP}/mz_strm.c
        ${L2D_MINIZIP}/mz_strm_buf.c
        ${L2D_MINIZIP}/mz_strm_mem.c
        ${L2D_MINIZIP}/mz_strm_os_posix.c
        ${L2D_MINIZIP}/mz_strm_split.c
        ${L2D_MINIZIP}/mz_strm_zlib.c
        ${L2D_MINIZIP}/mz_zip.c
        ${L2D_MINIZIP}/mz_zip_rw.c
        ${L2D_PLUGIN}/Live2D.cpp
        ${L2D_PLUGIN}/utils.cpp
        ${L2D_PLUGIN}/MemoryAllocator.cpp
        src/live2d/LicensesStub.cpp
    )
    target_compile_definitions(papervn_live2d PRIVATE
        CSM_TARGET_IPHONE_ES2 __IOS__ GLES_SILENCE_DEPRECATION HAVE_ZLIB ZLIB_COMPAT MZ_ZIP_NO_ENCRYPTION MZ_ZIP_NO_CRYPTO HAVE_STDINT_H HAVE_INTTYPES_H)
    target_include_directories(papervn_live2d PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src/live2d
        ${L2D_FRAMEWORK} ${L2D_DRIVER} ${L2D_DRIVER}/ogl ${L2D_MINIZIP} ${L2D_CORE}/include ${L2D_PLUGIN}
        ${KRKR2PLUGIN_PATH})
    set_source_files_properties(${L2D_PLUGIN}/Live2D.cpp ${L2D_PLUGIN}/utils.cpp PROPERTIES COMPILE_OPTIONS
        "-include;${KRKR2PLUGIN_PATH}/PaperVNPluginCompat.h;-include;${CMAKE_CURRENT_SOURCE_DIR}/src/live2d/PaperVNLive2DCompat.h")
    target_link_libraries(papervn_live2d PUBLIC krkr2plugin)
    # KTX 纹理：KTX-Software（Apache-2.0）的只读部分。只要读取、BasisU 转码和 GL 上传，不要编码器，
    # 所以不用它的 CMake（会连带编译编码器，还要它的工具目录）
    set(L2D_KTX ${PAPERVN_THIRD_PARTY}/live2d-driver/external/KTX-Software)
    add_library(papervn_ktx STATIC
        ${L2D_KTX}/lib/src/basis_transcode.cpp
        ${L2D_KTX}/lib/src/miniz_wrapper.cpp
        ${L2D_KTX}/lib/src/checkheader.c
        ${L2D_KTX}/lib/src/filestream.c
        ${L2D_KTX}/lib/src/gl_funcs.c
        ${L2D_KTX}/lib/src/glloader.c
        ${L2D_KTX}/lib/src/glformat_str.c
        ${L2D_KTX}/lib/src/hashlist.c
        ${L2D_KTX}/lib/src/info.c
        ${L2D_KTX}/lib/src/memstream.c
        ${L2D_KTX}/lib/src/strings.c
        ${L2D_KTX}/lib/src/swap.c
        ${L2D_KTX}/lib/src/texture.c
        ${L2D_KTX}/lib/src/texture1.c
        ${L2D_KTX}/lib/src/texture2.c
        ${L2D_KTX}/lib/src/vkformat_check.c
        ${L2D_KTX}/lib/src/vkformat_check_variant.c
        ${L2D_KTX}/lib/src/vkformat_str.c
        ${L2D_KTX}/lib/src/vkformat_typesize.c
        ${L2D_KTX}/external/dfdutils/createdfd.c
        ${L2D_KTX}/external/dfdutils/colourspaces.c
        ${L2D_KTX}/external/dfdutils/interpretdfd.c
        ${L2D_KTX}/external/dfdutils/printdfd.c
        ${L2D_KTX}/external/dfdutils/queries.c
        ${L2D_KTX}/external/dfdutils/vk2dfd.c
        ${L2D_KTX}/external/basis_universal/transcoder/basisu_transcoder.cpp
        ${L2D_KTX}/external/basis_universal/zstd/zstddeclib.c
        src/live2d/PaperVNKTXStubs.cpp
    )
    target_compile_definitions(papervn_ktx PRIVATE
        LIBKTX KHRONOS_STATIC SUPPORT_SOFTWARE_ETC_UNPACK=0 BASISD_SUPPORT_FXT1=0 BASISD_SUPPORT_KTX2=1 BASISD_SUPPORT_KTX2_ZSTD=1
        BASISU_NO_ITERATOR_DEBUG_LEVEL GLES_SILENCE_DEPRECATION)
    target_compile_definitions(papervn_ktx PUBLIC KHRONOS_STATIC)
    target_compile_options(papervn_ktx PRIVATE -Wno-everything)
    target_include_directories(papervn_ktx PUBLIC ${L2D_KTX}/lib/include)
    target_include_directories(papervn_ktx PRIVATE
        ${L2D_KTX}/lib/src ${L2D_KTX}/utils ${L2D_KTX}/external ${L2D_KTX}/external/basis_universal ${L2D_KTX}/external/basis_universal/zstd ${L2D_KTX}/external/basis_universal/transcoder)
    target_include_directories(papervn_ktx SYSTEM PRIVATE ${L2D_KTX}/other_include)
    target_link_libraries(papervn_live2d PUBLIC papervn_ktx)
    target_link_libraries(papervn_kirikiri PUBLIC papervn_live2d)
endif()

# GL 系插件共用的上下文，以及 krkrgles（wamsoft，许可随吉里吉里Z，改动在 patches/krkrgles-ios.patch）
add_library(papervn_gl STATIC src/gl/PaperVNGLContext.mm)
target_compile_options(papervn_gl PRIVATE -fobjc-arc)
target_include_directories(papervn_gl PUBLIC src/gl)
target_link_libraries(papervn_kirikiri PUBLIC papervn_gl)
if(TARGET papervn_live2d)
    target_link_libraries(papervn_live2d PUBLIC papervn_gl)
endif()
set(GLES_PLUGIN ${PAPERVN_THIRD_PARTY}/krkrgles/src)
if(EXISTS ${GLES_PLUGIN}/GLES.cpp)
    add_library(papervn_gles STATIC
        ${GLES_PLUGIN}/GLES.cpp
        ${GLES_PLUGIN}/GLClip.cpp
        ${GLES_PLUGIN}/GLEffect.cpp
        ${GLES_PLUGIN}/GLFrameBufferObject.cpp
        ${GLES_PLUGIN}/GLShaderUtil.cpp
        ${GLES_PLUGIN}/GLTexture.cpp
        ${GLES_PLUGIN}/OpenGLError.cpp
    )
    target_compile_definitions(papervn_gles PRIVATE GLES_SILENCE_DEPRECATION)
    target_include_directories(papervn_gles PRIVATE src/gl/shim src/gl ${KRKR2PLUGIN_PATH})
    target_compile_options(papervn_gles PRIVATE -Wno-everything
        "SHELL:-include \"${KRKR2PLUGIN_PATH}/PaperVNPluginCompat.h\""
        "SHELL:-include \"${KRKR2PLUGIN_PATH}/PaperVNKrkrzCompat.h\""
        "SHELL:-include \"${CMAKE_CURRENT_SOURCE_DIR}/src/gl/PaperVNGLESModule.h\"")
    # 不直接链接 krkr2plugin：它的 PUBLIC 源文件会被再编译一遍，还带上这里强制包含的头文件
    target_include_directories(papervn_gles PRIVATE $<TARGET_PROPERTY:krkr2plugin,INTERFACE_INCLUDE_DIRECTORIES>)
    target_compile_definitions(papervn_gles PRIVATE $<TARGET_PROPERTY:krkr2plugin,INTERFACE_COMPILE_DEFINITIONS>)
    add_dependencies(papervn_gles krkr2plugin)
    target_link_libraries(papervn_gles PUBLIC papervn_gl)
    target_link_libraries(papervn_kirikiri PUBLIC papervn_gles)
endif()

# OGLDrawDevice：吉里吉里Z（wamsoft/krkrz，修改 BSD）的 GPU 绘图接口，改动在 patches/krkrz-gl-ios.patch
set(KRKRZ_GL ${PAPERVN_THIRD_PARTY}/krkrz-wam/common/visual/opengl)
if(EXISTS ${KRKRZ_GL}/CanvasIntf.cpp)
    add_library(papervn_ogl STATIC
        ${KRKRZ_GL}/CanvasIntf.cpp
        ${KRKRZ_GL}/TextureIntf.cpp
        ${KRKRZ_GL}/OffscreenIntf.cpp
        ${KRKRZ_GL}/ShaderProgramIntf.cpp
        ${KRKRZ_GL}/VertexBufferIntf.cpp
        ${KRKRZ_GL}/VertexBinderIntf.cpp
        ${KRKRZ_GL}/Matrix32Intf.cpp
        ${KRKRZ_GL}/Matrix44Intf.cpp
        ${KRKRZ_GL}/GLTexture.cpp
        ${KRKRZ_GL}/GLFrameBufferObject.cpp
        ${KRKRZ_GL}/GLShaderUtil.cpp
        ${KRKRZ_GL}/GLEffect.cpp
        ${KRKRZ_GL}/GLClip.cpp
        ${KRKRZ_GL}/EffectCommand.cpp
        ${KRKRZ_GL}/GLCompositorIntf.cpp
        ${KRKRZ_GL}/TextureLayerTreeOwner.cpp
        src/gl/PaperVNOGLDrawDevice.cpp
    )
    target_compile_definitions(papervn_ogl PRIVATE GLES_SILENCE_DEPRECATION PAPERVN_KRKR2 $<TARGET_PROPERTY:krkr2core,INTERFACE_COMPILE_DEFINITIONS>)
    target_include_directories(papervn_ogl PRIVATE src/gl/ogl-shim src/gl/shim src/gl ${KRKRZ_GL}
        $<TARGET_PROPERTY:krkr2core,INTERFACE_INCLUDE_DIRECTORIES>)
    target_compile_options(papervn_ogl PRIVATE -Wno-everything -ferror-limit=0
        "SHELL:-include \"${CMAKE_CURRENT_SOURCE_DIR}/src/gl/ogl-shim/PaperVNOGLCompat.h\"")
    add_dependencies(papervn_ogl krkr2core)
    target_link_libraries(papervn_ogl PUBLIC papervn_gl)
    target_link_libraries(papervn_kirikiri PUBLIC papervn_ogl)
endif()
