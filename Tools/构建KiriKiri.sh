#!/usr/bin/env bash
# 从 krkr2（https://github.com/2468785842/krkr2，MIT）编译 KiriKiriCore.xcframework，
# 放到 Dependencies/KiriKiri/ 供 PaperVN 运行 KiriKiri（吉里吉里）的视觉小说。
#
# 用法：Tools/构建KiriKiri.sh [krkr2 源码目录]
# 默认源码在仓库外的 ../第三方源码/krkr2，vcpkg 在 ../第三方源码/vcpkg（或 $VCPKG_ROOT）。
# 依赖用 Dependencies/KiriKiri/vcpkg 里的清单编译（关掉了 iOS 不能用的即时编译和 OpenMP），
# 对 krkr2 的修改在 Dependencies/KiriKiri/patches/krkr2-ios.patch。
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
krkr2="$(cd "${1:-$project_root/../第三方源码/krkr2}" && pwd)"
export VCPKG_ROOT="${VCPKG_ROOT:-$(cd "$project_root/../第三方源码/vcpkg" && pwd)}"
package_dir="$project_root/Dependencies/KiriKiri"
work="${KIRIKIRI_BUILD_DIR:-$project_root/../第三方源码/krkr2-ios}"
xcframework="$package_dir/KiriKiriCore.xcframework"
mkdir -p "$work"
# TJS2 的语法分析器要 bison 3.8 以上（brew install bison）
bison="$(brew --prefix bison 2>/dev/null)/bin/bison"
[ -x "$bison" ] || bison="$(command -v bison)"

# 1. 打补丁（已打过就跳过）
if git -C "$krkr2" apply --check "$package_dir/patches/krkr2-ios.patch" 2>/dev/null; then
    git -C "$krkr2" apply "$package_dir/patches/krkr2-ios.patch"
elif ! git -C "$krkr2" apply --reverse --check "$package_dir/patches/krkr2-ios.patch" 2>/dev/null; then
    echo "error: krkr2-ios.patch 打不上，krkr2 版本可能变了" >&2
    exit 1
fi

# Live2D（可选，缺了就不编）：放在 ../第三方源码 下
#   krkr-plugins/krkrlive2d（wamsoft，打 patches/krkrlive2d-ios.patch）、live2d-driver（wtnbgo/live2d，含子模块 CubismNativeFramework）、
#   minizip-ng（4.1.0）、cubism-sdk/CubismSdkForNative-5-r.5（官方下载，只用 Core；商用许可见 LICENSE.md）
third_party="$project_root/../第三方源码"
if [ -d "$third_party/krkr-plugins/krkrlive2d/.git" ] && git -C "$third_party/krkr-plugins/krkrlive2d" apply --check "$package_dir/patches/krkrlive2d-ios.patch" 2>/dev/null; then
    git -C "$third_party/krkr-plugins/krkrlive2d" apply "$package_dir/patches/krkrlive2d-ios.patch"
fi

# krkrgles 和 OGLDrawDevice（可选，缺了就不编）：放在 ../第三方源码 下
#   krkrgles（wamsoft/krkrgles，提交记在 patches/krkrgles.commit）、krkrz-wam（wamsoft/krkrz，提交记在 patches/krkrz.commit）
# KTX 用 live2d-driver/external/KTX-Software 的读取部分；工作区里如果没有 utils/unused.h 要先恢复
for pair in "krkrgles:krkrgles-ios.patch" "krkrz-wam:krkrz-gl-ios.patch" "live2d-driver:live2d-driver-ios.patch"; do
    dir="$third_party/${pair%%:*}"
    patch="$package_dir/patches/${pair##*:}"
    if [ -d "$dir/.git" ] && git -C "$dir" apply --check "$patch" 2>/dev/null; then
        git -C "$dir" apply "$patch"
    fi
done
ktx="$third_party/live2d-driver/external/KTX-Software"
if [ -d "$ktx" ] && [ ! -f "$ktx/utils/unused.h" ]; then
    git -C "$ktx" restore --source=HEAD --worktree utils/unused.h
fi

build_slice() {
    local triplet="$1" sysroot="$2" name="$3" platform="$4"
    local installed="$work/$name"
    # 2. 依赖（GitHub 下载偶尔断开，重试几次）
    for attempt in 1 2 3; do
        if (cd "$package_dir/vcpkg" && "$VCPKG_ROOT/vcpkg" install --allow-unsupported \
                --triplet "$triplet" --host-triplet arm64-osx --x-install-root="$installed"); then
            break
        fi
        [ "$attempt" = 3 ] && exit 1
    done
    # 3. 引擎
    cmake -S "$package_dir" -B "$work/build-$name" -G Ninja \
        -DKRKR2_ROOT="$krkr2" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
        -DVCPKG_TARGET_TRIPLET="$triplet" \
        -DVCPKG_INSTALLED_DIR="$installed" \
        -DVCPKG_MANIFEST_MODE=OFF \
        -DVCPKG_OVERLAY_TRIPLETS="$package_dir/vcpkg/triplets" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$sysroot" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
        -DBISON_EXECUTABLE="$bison"
    cmake --build "$work/build-$name" --target papervn_kirikiri
    # 4. 合成一个静态库。krkr2 的插件（addFont 等）靠全局对象的构造函数注册，没人直接引用，
    #    放在静态库里会被链接器整个丢掉；先把引擎各模块预链接成一个目标文件，用到接口时就全部带进来。
    #    vcpkg 编出的依赖仍是普通的静态库成员，按需链接
    local engine=()
    while IFS= read -r lib; do engine+=("$lib"); done < <(find "$work/build-$name" -name '*.a' -type f)
    local libs=()
    while IFS= read -r lib; do libs+=("$lib"); done < <(find "$installed/$triplet/lib" -maxdepth 1 -name '*.a' -type f)
    # Live2D Cubism Core：官方只提供预编译库（下载 CubismSdkForNative 解压到 ../第三方源码/cubism-sdk）
    local core="$project_root/../第三方源码/cubism-sdk/CubismSdkForNative-5-r.5/Core/lib/ios"
    case "$name" in
        ios-arm64-simulator) core="$core/Release-iphonesimulator-arm64/libLive2DCubismCore.a" ;;
        *) core="$core/Release-iphoneos/libLive2DCubismCore.a" ;;
    esac
    mkdir -p "$work/out/$name"
    # 官方库标的最低系统版本（iOS 26.2）比 App 高，链接时每个成员都报警告；拷贝一份改标记，原文件不动
    if [ -f "$core" ]; then
        cp -f "$core" "$work/out/$name/libLive2DCubismCore.a"
        python3 "$project_root/Tools/修正静态库最低系统版本.py" "$work/out/$name/libLive2DCubismCore.a" 18.0
        libs+=("$work/out/$name/libLive2DCubismCore.a")
    fi
    rm -rf "$work/out/$name/objects"
    python3 "$project_root/Tools/去重KiriKiri目标文件.py" "$work/out/$name/objects" "${engine[@]}" >/dev/null
    xcrun ld -r -arch arm64 -platform_version "$platform" 18.0 "$(xcrun --sdk "$sysroot" --show-sdk-version)" \
        "$work/out/$name/objects"/*.o -o "$work/out/$name/krkr2.o"
    libtool -static -no_warning_for_no_symbols -o "$work/out/$name/libKiriKiriCore.a" "$work/out/$name/krkr2.o" "${libs[@]}" 2>/dev/null
    xcrun strip -S -x "$work/out/$name/libKiriKiriCore.a" 2>/dev/null || true
}

build_slice arm64-ios-simulator-papervn iphonesimulator ios-arm64-simulator ios-simulator
build_slice arm64-ios-papervn iphoneos ios-arm64 ios

headers="$work/out/Headers"
# 头文件放在 Headers/KiriKiriCore/，免得和其他 xcframework 的 module.modulemap 撞在同一个 include 里
rm -rf "$headers"
mkdir -p "$headers/KiriKiriCore"
cp "$package_dir/include/papervn_kirikiri.h" "$headers/KiriKiriCore/"
cat > "$headers/KiriKiriCore/module.modulemap" <<'EOF'
module KiriKiriCore {
    header "papervn_kirikiri.h"
    export *
}
EOF
rm -rf "$xcframework"
xcodebuild -create-xcframework \
    -library "$work/out/ios-arm64/libKiriKiriCore.a" -headers "$headers" \
    -library "$work/out/ios-arm64-simulator/libKiriKiriCore.a" -headers "$headers" \
    -output "$xcframework"

# 5. krkr2 自带界面（菜单、提示）用到的资源和默认字体
# 界面资源不进 App，由 Tools/打包视觉小说资源.py 打成运行时下载的资源包
rm -rf "$package_dir/下载资源/res"
mkdir -p "$package_dir/下载资源"
cp -R "$krkr2/ui/cocos-studio" "$package_dir/下载资源/res"

git -C "$krkr2" rev-parse HEAD > "$package_dir/KRKR2_COMMIT"
cp "$krkr2/LICENSE" "$package_dir/LICENSE-krkr2"
du -sh "$xcframework"
echo "✓ $xcframework（krkr2 $(cat "$package_dir/KRKR2_COMMIT")）"

# 许可页面（papervn.jizpaper.com/license）列出的依赖
python3 "$project_root/Tools/列出KiriKiri依赖.py" "$work/ios-arm64"
