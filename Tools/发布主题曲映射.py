#!/usr/bin/env python3
"""把 PaperVN/Resources/PaperVNThemeSongMap.json 打包成 App 内静默更新用的文件。

输出到指定目录：
  PaperVNThemeSongMap-<版本>.json.deflate   原始 DEFLATE 压缩（App 用 Foundation 的 zlib 解压）
  manifest.json                              {format, version, file, bytes, jsonBytes, sha256}

格式和作品映射相同（见 Tools/发布作品映射.py）。format 是映射文件的结构版本，旧版 App 只接受自己认识的 format。

用法：
  python3 Tools/发布主题曲映射.py <输出目录>
部署到 VPS 用 deploy/vps/deploy-themesongs.sh（它会调用这个脚本）。
"""

import hashlib
import json
import pathlib
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PaperVN" / "Resources" / "PaperVNThemeSongMap.json"
FORMAT = 1


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(64)
    output = pathlib.Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    data = SOURCE.read_bytes()
    parsed = json.loads(data)
    if parsed.get("format") != FORMAT or not parsed.get("songs"):
        sys.exit("映射文件的 format 不对或没有主题曲")
    version = parsed["version"]
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    compressed = compressor.compress(data) + compressor.flush()
    name = f"PaperVNThemeSongMap-{version}.json.deflate"
    (output / name).write_bytes(compressed)
    manifest = {
        "format": FORMAT,
        "version": version,
        "file": name,
        "bytes": len(compressed),
        "jsonBytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"{name}：{len(data) // 1024} KB → {len(compressed) // 1024} KB")


if __name__ == "__main__":
    main()
