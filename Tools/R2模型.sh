#!/bin/bash
# 大模型文件不进 Git 仓库，放在 R2 的 Build/ 目录下（App 从不读取这个目录，上传不会触发用户的更新提示）。
# 仓库里只记录清单 Tools/R2模型清单.txt，每行：<仓库内路径> <R2对象键> <sha256>
#
# 用法：
#   Tools/R2模型.sh 下载               # 缺失或校验值不符的模型从 R2 下载（archive.sh 会自动运行）
#   Tools/R2模型.sh 发布 <仓库内路径>  # 把本地模型上传到 R2 的 Build/ 并更新清单（需要 R2_* 环境变量，见 Tools/上传到R2.py）
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
manifest="$project_root/Tools/R2模型清单.txt"
base_url="https://r2-papervn.jizpaper.com"

sha256_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

下载() {
    local path key sha file tmp
    while read -r path key sha; do
        [[ -z "$path" || "$path" == \#* ]] && continue
        file="$project_root/$path"
        if [[ -f "$file" && "$(sha256_of "$file")" == "$sha" ]]; then
            continue
        fi
        echo "下载 $path"
        mkdir -p "$(dirname "$file")"
        tmp="$file.download"
        curl -fL --retry 3 --progress-bar -o "$tmp" "$base_url/$key"
        if [[ "$(sha256_of "$tmp")" != "$sha" ]]; then
            rm -f "$tmp"
            echo "错误：$path 校验值不符" >&2
            exit 1
        fi
        mv "$tmp" "$file"
    done < "$manifest"
}

发布() {
    local path="${1:?用法：$0 发布 <仓库内路径>}"
    local file="$project_root/$path"
    [[ -f "$file" ]] || { echo "找不到 $path" >&2; exit 1; }
    local sha name stem ext key python
    sha="$(sha256_of "$file")"
    name="$(basename "$path")"
    stem="${name%.*}"
    ext="${name##*.}"
    key="Build/$stem-${sha:0:16}.$ext"
    python="$project_root/.build/smart-search-venv/bin/python"
    [[ -x "$python" ]] || python=python3
    "$python" "$project_root/Tools/上传到R2.py" "$file" "$key"
    touch "$manifest"
    grep -v -F "$path " "$manifest" > "$manifest.tmp" || true
    echo "$path $key $sha" >> "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
    echo "已更新清单：$path → $key"
}

case "${1:-}" in
    下载) 下载 ;;
    发布) shift; 发布 "$@" ;;
    *) echo "用法：$0 <下载|发布 路径>" >&2; exit 64 ;;
esac
