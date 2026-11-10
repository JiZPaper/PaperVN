#!/usr/bin/env bash
set -Eeuo pipefail

# 生成 PaperVN/Resources/PaperVNThemeSongMap.json（主题曲 → Apple Music 歌曲的对应表）。
# 和 App 用同一份匹配代码编译，按作品映射里的热度顺序处理，进度存在 Tools/主题曲映射/进度/，可以随时中断再接着运行。
# 在 Config/PaperVN.private.xcconfig 配置了 Apple Music API 密钥（APPLE_MUSIC_KEY_ID、APPLE_MUSIC_KEY_PATH）时用它，
# 每 0.5 秒一次请求；没有时退回 iTunes 接口，每分钟只能约 12 次，慢得多。之后再运行只重查过期的作品。
#
# 用法：
#   Tools/生成主题曲映射.sh                      处理热度前 1500 部（--top 改数量，--top all 处理作品映射里的全部动画）
#   Tools/生成主题曲映射.sh --season 2026/fall  另外加上某一季的作品（可以写多次）
#   Tools/生成主题曲映射.sh --ids 9253,52991    只处理这几部
#   Tools/生成主题曲映射.sh --minutes 60        最多运行 60 分钟
#   Tools/生成主题曲映射.sh --write-only        不检索，只按进度和人工校正重新写出映射文件
# 其他参数：--recheck-days（默认 60 天后重查）、--miss-recheck-days（有没找到的歌曲时默认 14 天后重查）、
# --force（配合 --ids，不管进度重新匹配这几部，只改了个别规则时用）、
# --misses-only（只重查上次没找到的歌曲，找到的保留；规则只是放宽时用）
# 生成后用 deploy/vps/deploy-themesongs.sh 发布，App 会静默下载。

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

swiftc -O -default-isolation MainActor \
  "$ROOT/PaperVN/非用户界面/资料库/动画主题曲.swift" \
  "$ROOT/Tools/主题曲映射/目录匹配.swift" \
  "$ROOT/Tools/主题曲映射/Linux读音.swift" \
  "$ROOT/Tools/主题曲映射/main.swift" \
  -o "$BUILD/生成主题曲映射"

cd "$ROOT"
PAPERVN_APP_ROOT="$ROOT" "$BUILD/生成主题曲映射" "$@"
