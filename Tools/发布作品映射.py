#!/usr/bin/env python3
"""把 PaperVN/Resources/PaperVNWorkMap.json 打包成 App 内静默更新用的文件。

输出到指定目录：
  PaperVNWorkMap-<版本>.json.deflate   原始 DEFLATE 压缩（App 用 Foundation 的 zlib 解压）
  manifest.json                         {format, version, file, bytes, jsonBytes, sha256}

format 是映射文件的结构版本：结构改到旧版 App 读不了时加一，旧版 App 只接受自己认识的 format。
sha256 是解压后 JSON 的摘要，App 下载解压后核对，再确认能完整读取才替换。

用法：
  python3 Tools/发布作品映射.py <输出目录>
部署到 VPS 用 deploy/vps/deploy-workmap.sh（它会调用这个脚本）。
"""

import hashlib
import json
import pathlib
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "PaperVN" / "Resources" / "PaperVNWorkMap.json"
FORMAT = 1


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(64)
    output = pathlib.Path(sys.argv[1]).resolve()
    output.mkdir(parents=True, exist_ok=True)
    data = SOURCE.read_bytes()
    version = json.loads(data)["version"]
    # wbits=-15：不带 zlib 头的原始 DEFLATE，和 NSData.decompressed(using: .zlib) 一致
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    compressed = compressor.compress(data) + compressor.flush()
    name = f"PaperVNWorkMap-{version}.json.deflate"
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
