#!/usr/bin/env python3
"""把运行视觉小说用的资源打成运行时下载的资源包，并生成 App 里的清单。

资源不进 App：Dependencies/KiriKiri/下载资源/ → ../第三方源码/视觉小说资源包/<名称>-<校验值前 16 位>.zip
文件名带校验值，内容变了就是新文件，旧版 App 仍能下载它自己的版本。

用法：
  Tools/打包视觉小说资源.py          # 打包并更新 PaperVN/非用户界面/视觉小说运行/视觉小说运行资源清单.swift
  Tools/打包视觉小说资源.py 上传     # 另外上传到 R2 的 Resources/VisualNovelRuntime/（需要 R2_* 环境变量）
"""
import hashlib
import subprocess
import sys
import zipfile
from pathlib import Path

app = Path(__file__).resolve().parent.parent
source = app / "Dependencies/KiriKiri/下载资源"
output = app.parent / "第三方源码/视觉小说资源包"
manifest = app / "PaperVN/非用户界面/视觉小说运行/视觉小说运行资源清单.swift"
FONT = "NotoSansCJK-Regular.ttc"

# case 名、文件名前缀、来源文件夹、筛选、包内前缀
# krkr2 的搜索路径固定是资源根目录下的 res，所以 KiriKiri 的包里要带这一层
PACKS = [
    ("kirikiri", "KiriKiri", "res", lambda p: p.name != FONT, "res/"),
    ("字体", "Font", "res", lambda p: p.name == FONT, ""),
    ("midi音色", "MIDISounds", "soundfont", lambda p: True, ""),
    ("flash", "Ruffle", "ruffle", lambda p: True, ""),
    ("renpy", "RenPy", "renpyweb", lambda p: True, ""),
]
IGNORED = {".DS_Store"}


def build(prefix, folder, keep, inner):
    base = source / folder
    files = sorted(p for p in base.rglob("*") if p.is_file() and p.name not in IGNORED and keep(p))
    assert files, folder
    temporary = output / f"{prefix}.tmp"
    extracted = 0
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in files:
            # 固定时间戳，内容不变时包也不变
            info = zipfile.ZipInfo(inner + path.relative_to(base).as_posix(), (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            data = path.read_bytes()
            extracted += len(data)
            archive.writestr(info, data, compresslevel=9)
    digest = hashlib.sha256(temporary.read_bytes()).hexdigest()
    target = output / f"{prefix}-{digest[:16]}.zip"
    for old in output.glob(f"{prefix}-*.zip"):
        if old != target:
            old.unlink()
    temporary.replace(target)
    return target, digest, extracted


def main():
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for case, prefix, folder, keep, inner in PACKS:
        target, digest, extracted = build(prefix, folder, keep, inner)
        size = target.stat().st_size
        print(f"{target.name}  下载 {size / 1048576:.1f} MB  解压后 {extracted / 1048576:.1f} MB")
        rows.append((case, target, digest, size, extracted))

    body = "\n".join(
        f'        case .{case}: 视觉小说资源包信息(文件名: "{target.name}", 下载大小: {size}, 解压大小: {extracted}, '
        f'校验值: "{digest}")'
        for case, target, digest, size, extracted in rows
    )
    manifest.write_text(
        "// 由 Tools/打包视觉小说资源.py 生成，不要手改。\n\n"
        "extension 视觉小说运行资源包 {\n"
        "    nonisolated var 信息: 视觉小说资源包信息 {\n"
        "        switch self {\n"
        f"{body}\n"
        "        }\n"
        "    }\n"
        "}\n",
        encoding="utf-8",
    )

    if sys.argv[1:] == ["上传"]:
        python = app / ".build/smart-search-venv/bin/python"
        python = str(python) if python.exists() else "python3"
        for _, target, *_ in rows:
            subprocess.run([python, str(app / "Tools/上传到R2.py"), str(target),
                            f"Resources/VisualNovelRuntime/{target.name}"], check=True)


main()
