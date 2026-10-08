#!/usr/bin/env python3
"""构建 PaperVN 智能搜索模型（Hiro智能）。

在 Mac 上用 VNDB 和 Bangumi 数据库导出训练一个名称模糊匹配模型，并打包成 App 下载的单个文件：
作品、角色、会社、制作人员的名称片段索引，以及综合名称匹配和热度的排序器。

阶段（默认依次执行全部阶段）：
  prepare   解析 VNDB 数据库导出，生成文档
  aliases   从 Bangumi 数据库导出补充中文名、别名和梗，生成别名查询
  fuzzy     构建名称索引、训练排序器、评估并打包

依赖见 Tools/README.md。
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import urllib.request
from pathlib import Path

仓库 = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(仓库 / "Tools"))

from 智能搜索模型 import 别名, 数据, 模糊  # noqa: E402

导出地址 = "https://dl.vndb.org/dump/vndb-db-latest.tar.zst"


def 下载导出(工作目录: Path) -> Path:
    目录 = 工作目录 / "dump"
    if (目录 / "db" / "vn").exists():
        return 目录
    压缩包 = 工作目录 / "vndb-db.tar.zst"
    if not 压缩包.exists():
        print(f"下载 {导出地址}")
        urllib.request.urlretrieve(导出地址, 压缩包)
    目录.mkdir(parents=True, exist_ok=True)
    subprocess.run(["tar", "--zstd", "-xf", str(压缩包), "-C", str(目录)], check=True)
    return 目录


def 阶段准备(参数, 工作目录: Path):
    导出 = Path(参数.dump) if 参数.dump else 下载导出(工作目录)
    译文 = Path(参数.translations) if 参数.translations else 仓库.parent / "VNDB-Description-Translations"
    数据.准备(导出, 译文 if 译文.exists() else None, 仓库 / "PaperVN", 工作目录 / "data")


def 下载bangumi导出(工作目录: Path) -> Path:
    目录 = 工作目录 / "bangumi"
    if (目录 / "subject.jsonlines").exists():
        return 目录
    目录.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen("https://api.github.com/repos/bangumi/Archive/releases/latest") as 响应:
        资源 = [a for a in json.load(响应)["assets"] if a["name"].endswith(".zip")]
    最新 = max(资源, key=lambda a: a["name"])
    压缩包 = 目录 / "dump.zip"
    print(f"下载 {最新['browser_download_url']}（{最新['size'] / 1e6:.0f} MB）")
    urllib.request.urlretrieve(最新["browser_download_url"], 压缩包)
    subprocess.run(["unzip", "-o", "-q", str(压缩包), "-d", str(目录)], check=True)
    return 目录


def 阶段别名(参数, 工作目录: Path):
    导出 = Path(参数.dump) if 参数.dump else 下载导出(工作目录)
    别名.构建(导出, 下载bangumi导出(工作目录), 仓库 / "PaperVN/Resources/vndb_id_connector.json", 工作目录 / "data")


def 阶段模糊(参数, 工作目录: Path):
    导出 = Path(参数.dump) if 参数.dump else 下载导出(工作目录)
    模糊.构建(导出, 工作目录 / "data", 工作目录, 仓库 / "Tools/智能搜索模型/评估查询-名称.json")


def main():
    解析器 = argparse.ArgumentParser(description="构建 PaperVN 智能搜索模型")
    解析器.add_argument("stages", nargs="*", default=["prepare", "aliases", "fuzzy"])
    解析器.add_argument("--work-dir", default=str(仓库 / ".build/smart-search-model"))
    解析器.add_argument("--dump", help="已解压的 VNDB 数据库导出目录（包含 db/）")
    解析器.add_argument("--translations", help="VNDB-Description-Translations 仓库目录")
    参数 = 解析器.parse_args()
    工作目录 = Path(参数.work_dir)
    工作目录.mkdir(parents=True, exist_ok=True)
    阶段表 = {"prepare": 阶段准备, "aliases": 阶段别名, "fuzzy": 阶段模糊}
    for 阶段 in 参数.stages:
        print(f"== {阶段}", flush=True)
        阶段表[阶段](参数, 工作目录)


if __name__ == "__main__":
    main()



