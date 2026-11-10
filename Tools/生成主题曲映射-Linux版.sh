#!/usr/bin/env bash
set -Eeuo pipefail

# 交叉编译主题曲映射生成器的 Linux 版（x86_64，静态链接），给美国 VPS 的每日任务用。
# 需要 swift.org 的工具链和 Static Linux SDK，默认在外置盘 /Volumes/项目/.swift-linux-toolchain（只解压、不做系统安装）。
# 用法：Tools/生成主题曲映射-Linux版.sh <输出路径>

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLCHAIN="${SWIFT_LINUX_TOOLCHAIN:-/Volumes/项目/.swift-linux-toolchain}"
SWIFT="$TOOLCHAIN/expanded/swift-6.4.2-RELEASE-osx-package.pkg/Payload/usr/bin/swift"
OUTPUT="${1:?用法：$0 <输出路径>}"
BUILD="$TOOLCHAIN/build"
SOURCES="$BUILD/Sources/themesongs"

rm -rf "$SOURCES"
mkdir -p "$SOURCES"
cp "$ROOT/PaperVN/非用户界面/资料库/动画主题曲.swift" "$SOURCES/ThemeSong.swift"
cp "$ROOT/Tools/主题曲映射/目录匹配.swift" "$SOURCES/Catalog.swift"
cp "$ROOT/Tools/主题曲映射/Linux读音.swift" "$SOURCES/Reading.swift"
cp "$ROOT/Tools/主题曲映射/main.swift" "$SOURCES/main.swift"
cat > "$BUILD/Package.swift" <<'SWIFT'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "themesongs", targets: [
    .executableTarget(name: "themesongs", path: "Sources/themesongs",
                      swiftSettings: [.swiftLanguageMode(.v5), .defaultIsolation(MainActor.self)])
])
SWIFT
cd "$BUILD"
FLAGS=(-c release --swift-sdks-path "$TOOLCHAIN/sdks" --swift-sdk x86_64-swift-linux-musl -Xlinker -s)
"$SWIFT" build "${FLAGS[@]}"
cp "$("$SWIFT" build "${FLAGS[@]}" --show-bin-path)/themesongs" "$OUTPUT"
ls -lh "$OUTPUT"
