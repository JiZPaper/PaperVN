#!/usr/bin/env python3
"""列出 KiriKiri 静态库里 vcpkg 编出的依赖及其许可证，供许可页面（deploy/vps/legal）使用。

用法：Tools/列出KiriKiri依赖.py [vcpkg 安装目录]（由 Tools/构建KiriKiri.sh 调用）
"""
import glob
import json
import os
import sys
from pathlib import Path

app = Path(__file__).resolve().parent.parent
installed = Path(sys.argv[1] if len(sys.argv) > 1 else app.parent / "第三方源码/krkr2-ios/ios-arm64")
output = app.parent / "deploy/vps/legal/license/kirikiri-dependencies.json"

# vcpkg 没写或写得不准的许可证，照各项目自己的说明（有多种许可时写 PaperVN 采用的那种）
更正 = {
    "box2d": "MIT",
    "cocos2dx": "MIT",
    "ffmpeg": "LGPL-2.1-or-later",  # 没有 --enable-gpl / --enable-nonfree
    "freetype": "FTL",
    "libarchive": "BSD-2-Clause",
    "libiconv": "LGPL-2.1-or-later",
    "liblzma": "0BSD",
    "oniguruma": "BSD-2-Clause",
    "uchardet": "MPL-1.1",
    "unrar": "UnRAR",
    "zstd": "BSD-3-Clause",
}
# 只在编译时用的工具
不进App = {"pkgconf"}

rows = {}
for spdx in glob.glob(str(installed / "*/share/*/vcpkg.spdx.json")):
    data = json.load(open(spdx, encoding="utf-8"))
    port = next((p for p in data["packages"] if p.get("SPDXID") == "SPDXRef-port"), data["packages"][0])
    name = port["name"]
    if name.startswith("vcpkg-") or name in 不进App:
        continue  # 编译工具，不进 App
    license_name = port.get("licenseConcluded") or ""
    rows[name] = {
        "name": name,
        "version": port.get("versionInfo", "").split("#")[0],
        "license": 更正.get(name, "" if license_name in ("NOASSERTION", "LicenseRef-vcpkg-null") else license_name),
        "repository": port.get("homepage") or port.get("downloadLocation") or "",
    }
# Boost 的几十个子库合成一行
boost = [r for r in rows.values() if r["name"].startswith("boost")]
for r in boost:
    del rows[r["name"]]
if boost:
    rows["boost"] = {"name": "boost", "version": boost[0]["version"], "license": "BSL-1.0", "repository": "https://www.boost.org"}
# 不经 vcpkg 编进来的
for extra in [
    {"name": "krkr2", "version": "", "license": "MIT", "repository": "https://github.com/2468785842/krkr2"},
    {"name": "krkrlive2d", "version": "", "license": "MIT", "repository": "https://github.com/wamsoft/krkrlive2d"},
    {"name": "wtnbgo/live2d", "version": "", "license": "Live2D Open Software License", "repository": "https://github.com/wtnbgo/live2d"},
    {"name": "Live2D Cubism Framework", "version": "5-r.5", "license": "Live2D Open Software License", "repository": "https://github.com/Live2D/CubismNativeFramework"},
    {"name": "Live2D Cubism Core", "version": "06.00.0001", "license": "Live2D Proprietary Software License", "repository": "https://www.live2d.com/sdk/download/native/"},
    {"name": "minizip-ng", "version": "4.1.0", "license": "Zlib", "repository": "https://github.com/zlib-ng/minizip-ng"},
    {"name": "KIRIKIRI-Z", "version": "", "license": "BSD-3-Clause", "repository": "https://github.com/wamsoft/krkrz"},
    {"name": "krkrgles", "version": "", "license": "BSD-3-Clause", "repository": "https://github.com/wamsoft/krkrgles"},
    {"name": "KTX-Software", "version": "", "license": "Apache-2.0", "repository": "https://github.com/KhronosGroup/KTX-Software"},
    {"name": "Basis Universal", "version": "", "license": "Apache-2.0", "repository": "https://github.com/BinomialLLC/basis_universal"},
    {"name": "pl_mpeg", "version": "2025-12-30", "license": "MIT", "repository": "https://github.com/phoboslab/pl_mpeg"},
    {"name": "NtDec", "version": "", "license": "MIT", "repository": "https://github.com/UlyssesWu/NtDec"},
    {"name": "GeneralUser GS", "version": "2.0.3", "license": "GeneralUser GS License v2.0", "repository": "https://github.com/mrbumpy409/GeneralUser-GS"},
    {"name": "Ruffle", "version": "0.7.1", "license": "MIT OR Apache-2.0", "repository": "https://github.com/ruffle-rs/ruffle"},
    {"name": "Ren'Py", "version": "8.5.3", "license": "MIT, LGPL-2.1-or-later (SDL2, FFmpeg)", "repository": "https://www.renpy.org"},
]:
    rows.setdefault(extra["name"], extra)
result = sorted(rows.values(), key=lambda r: r["name"].lower())
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{output}：{len(result)} 个包")
