#!/usr/bin/env python3
"""列出 Siglus 静态库在 iOS 上用到的第三方 Rust 包及其许可证，供许可页面（deploy/vps/legal）使用。

用法：Tools/列出Siglus依赖.py（由 Tools/构建Siglus.sh 调用）
"""
import json
import subprocess
from pathlib import Path

app = Path(__file__).resolve().parent.parent
crate = app / "Dependencies/Siglus/PaperVNSiglus"
output = app.parent / "deploy/vps/legal/license/siglus-dependencies.json"

meta = json.loads(subprocess.run(
    ["cargo", "metadata", "--format-version", "1", "--filter-platform", "aarch64-apple-ios"],
    cwd=crate, check=True, capture_output=True, text=True,
).stdout)
nodes = {n["id"]: n for n in meta["resolve"]["nodes"]}
packages = {p["id"]: p for p in meta["packages"]}
seen, stack = set(), [meta["resolve"]["root"]]
while stack:
    current = stack.pop()
    if current in seen:
        continue
    seen.add(current)
    for dep in nodes[current]["deps"]:
        if any(kind["kind"] is None for kind in dep["dep_kinds"]):
            stack.append(dep["pkg"])

rows = []
for package_id in seen:
    package = packages[package_id]
    if package["source"] is None:
        continue  # siglus_rs 自己的包和 papervn_siglus，许可页面单独说明
    rows.append({
        "name": package["name"],
        "version": package["version"],
        "license": package.get("license") or "",
        "repository": package.get("repository") or f"https://crates.io/crates/{package['name']}",
    })
rows.sort(key=lambda row: (row["name"].lower(), row["version"]))
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(rows, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{output}：{len(rows)} 个包")
