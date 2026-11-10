#!/usr/bin/env bash
# 从 siglus_rs（https://github.com/xmoezzz/siglus_rs，MPL-2.0）编译 Siglus.xcframework，
# 放到 Dependencies/Siglus/ 供 PaperVN 运行 SiglusEngine 的视觉小说。
#
# 用法：Tools/构建Siglus.sh [siglus_rs 源码目录]
# 默认源码目录是仓库外的 ../第三方源码/siglus_rs；需要 rustup（aarch64-apple-ios、aarch64-apple-ios-sim）。
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="${1:-$project_root/../第三方源码/siglus_rs}"
source_dir="$(cd "$source_dir" && pwd)"
output_dir="$project_root/Dependencies/Siglus"
xcframework="$output_dir/SiglusCore.xcframework"

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
command -v cargo >/dev/null || { echo "error: 没有 cargo，先安装 rustup" >&2; exit 1; }
rustup target add aarch64-apple-ios aarch64-apple-ios-sim >/dev/null

# iOS 18 起支持
export IPHONEOS_DEPLOYMENT_TARGET=18.0

# Dependencies/Siglus/PaperVNSiglus 依赖 siglus_rs 的 game_launcher，并加上 PaperVN 的 papervn_siglus_* 接口；
# Cargo.toml 里用相对路径指向 ../第三方源码/siglus_rs，源码放在别处时先建好这个路径
export CARGO_TARGET_DIR="$source_dir/target"
cd "$output_dir/PaperVNSiglus"
for target in aarch64-apple-ios aarch64-apple-ios-sim; do
    cargo build --release --target "$target"
done
cd "$source_dir"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# 头文件放在 Headers/SiglusCore/，免得和其他 xcframework 的 module.modulemap 撞在同一个 include 里
mkdir -p "$work/Headers/SiglusCore" "$work/ios-arm64" "$work/ios-arm64-simulator"
cp "$source_dir/platform/ios/SiglusLauncher/Headers/siglus.h" "$work/Headers/SiglusCore/"
cp "$output_dir/PaperVNSiglus/papervn_siglus.h" "$work/Headers/SiglusCore/"
cat > "$work/Headers/SiglusCore/module.modulemap" <<'EOF'
module SiglusCore {
    header "siglus.h"
    header "papervn_siglus.h"
    export *
}
EOF
# 静态库里的调试符号去掉，体积小很多
for pair in "aarch64-apple-ios:ios-arm64" "aarch64-apple-ios-sim:ios-arm64-simulator"; do
    target="${pair%%:*}"
    slice="${pair##*:}"
    cp "target/$target/release/libpapervn_siglus.a" "$work/$slice/libSiglusCore.a"
    xcrun strip -S -x "$work/$slice/libSiglusCore.a" 2>/dev/null || true
done

rm -rf "$xcframework"
mkdir -p "$output_dir"
xcodebuild -create-xcframework \
    -library "$work/ios-arm64/libSiglusCore.a" -headers "$work/Headers" \
    -library "$work/ios-arm64-simulator/libSiglusCore.a" -headers "$work/Headers" \
    -output "$xcframework"

commit="$(git -C "$source_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
echo "$commit" > "$output_dir/SIGLUS_RS_COMMIT"
cp "$source_dir/LICENSE-MPL-2.0" "$output_dir/LICENSE-MPL-2.0"
du -sh "$xcframework"
echo "✓ $xcframework（siglus_rs $commit）"

# 许可页面（papervn.jizpaper.com/license）列出的依赖
python3 "$project_root/Tools/列出Siglus依赖.py"
