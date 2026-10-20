"""动画、漫画与轻小说的搜索条目。

和视觉小说条目进同一个名称索引，搜索时不分类别，由排序器按名称匹配和热度判断用户要找的是哪一部。
作品的划分和 App 的资料库一致：动画以 Annict 为准、漫画与轻小说以 MAL 为准（读取预装的作品映射
`PaperVNWorkMap.json`），条目编号是 MAL ID，App 用它打开详情页。

数据（`--works-data` 目录，和 `Tools/构建作品映射.py` 用的是同一份）：
  anilist-anime.jsonl、anilist-manga.jsonl  AniList 全部动画、漫画（标题、别名、格式、MAL ID）
  aod.json                                    anime-offline-database（AniList 上没有的 MAL 动画）
  annict-titles.jsonl                         Annict 作品的日文标题（可选）
  bgm/subject.jsonlines                       Bangumi 数据库导出（中文名、别名、收藏人数）
  anilist-popularity.json                     AniList 热度前 5000 部动画、漫画（可选）
"""

from __future__ import annotations

import collections
import json
import math
import re
from pathlib import Path

from . import 别名 as 别名工具, 名称 as 名称工具

# Bangumi 上动画、书籍的标签比游戏多得多、描述性的也多（“家庭喜剧”“老动画”），当别名的门槛比视觉小说高
标签最少人数 = 20
标签最低占比 = 0.08

# 漫画、轻小说的收藏人数（Bangumi）或热度（AniList）低于这个数的不进索引（数量太多，冷门的靠在线搜索）；动画全部收录
漫画最少热度 = 5
# AniList 的热度（列表人数）大约是 Bangumi 收藏人数的这么多倍，换算到同一个尺度
AniList热度换算 = 6.0

# 动画、书籍上常见、不能当名字的标签（视觉小说的通用标签见 别名._通用标签）
_书籍动画通用标签 = {
    "tv", "ova", "oad", "web", "剧场版", "漫画", "小说", "轻小说", "原创", "漫改", "轻改", "游戏改", "小说改",
    "日常", "搞笑", "治愈", "热血", "后宫", "百合", "战斗", "奇幻", "科幻", "校园", "恋爱", "催泪", "致郁",
    "京都动画", "a-1pictures", "j.c.staff", "sunrise", "madhouse", "shaft", "p.a.works", "kinemacitrus",
}

_其他文字 = re.compile(r"[\u0370-\u03ff\u0400-\u052f\u0590-\u06ff\u0750-\u077f\u0900-\u0dff\u0e00-\u0eff\u10a0-\u10ff]")
_单卷 = re.compile(r"[（(]\s*\d+\s*[)）]\s*$|第\s*\d+\s*[巻卷]|\s\d+$")
_日期 = re.compile(r"\d{4}|\d+[年月季]")
_句子 = re.compile(r"[，。！？,.!?：:]|\s\S+\s")
# “乐队题材”“轻改”“京都系”这类说的是类别
_类别后缀 = ("题材", "改", "改编", "系", "向", "风", "类", "番", "社", "期", "结尾")

_别名行 = re.compile(r"\|别名\s*=\s*\{(.*?)\}", re.S)
_别名项 = re.compile(r"\[([^\[\]]+)\]")


def _读jsonl(路径: Path):
    with open(路径, encoding="utf-8") as 文件:
        for 行 in 文件:
            if 行.strip():
                yield json.loads(行)


def _bangumi别名(信息框: str) -> list[str]:
    别名 = []
    for 块 in _别名行.findall(信息框 or ""):
        for 项 in _别名项.findall(块):
            # “[日文名|xxx]”这类带标签的写法取后半
            别名.append(项.split("|", 1)[-1].strip())
    return [n for n in 别名 if n]


def 构建文档(数据目录: Path, 映射路径: Path) -> list[dict]:
    映射 = json.loads(映射路径.read_text(encoding="utf-8"))

    # Bangumi 的用户标签：和视觉小说一样，只出现在极少数条目上、又有足够多人打的标签往往是简称或梗（“SP”“孤独摇滚”），
    # 当作别名。标签出现在几部作品上按书籍、动画、游戏一起数
    原始 = {}
    标签出现: collections.Counter[str] = collections.Counter()
    for 条目 in _读jsonl(数据目录 / "bgm" / "subject.jsonlines"):
        if 条目["type"] not in (1, 2, 4):
            continue
        for 标签 in 条目.get("tags") or []:
            if 标签["count"] >= 3:
                标签出现[名称工具.规范化(标签["name"])] += 1
        if 条目["type"] in (1, 2):
            原始[条目["id"]] = 条目
    # 人名（声优、制作人员、原作者）在动画、书籍上很常被打成标签，不能当作品的叫法
    人名 = set()
    for 人 in _读jsonl(数据目录 / "bgm" / "person.jsonlines"):
        人名.add(名称工具.规范化(人["name"]))
        人名.update(名称工具.规范化(n) for n in 别名工具._infobox值(人.get("infobox") or "", "简体中文名"))

    def 像叫法(标签: str, 信息框: str) -> bool:
        键 = 名称工具.规范化(标签)
        if 键 in 人名 or 标签 in 信息框:  # 制作公司、杂志、出版社等写在 infobox 里
            return False
        if _日期.search(标签) or _句子.search(标签) or 标签.endswith(_类别后缀):
            return False
        # 太长的通常是评价
        return len(键) <= (12 if 名称工具.含中日文(标签) else 24)

    bangumi = {}
    for 编号, 条目 in 原始.items():
        收藏 = sum((条目.get("favorite") or {}).values())
        名字 = {名称工具.规范化(n) for n in [条目["name"], 条目.get("name_cn") or ""] if n}
        标签别名 = []
        最高 = max([t["count"] for t in 条目.get("tags") or []] or [1])
        for 标签 in 条目.get("tags") or []:
            键 = 名称工具.规范化(标签["name"])
            if (标签["count"] >= 标签最少人数 and 标签["count"] >= 标签最低占比 * 最高
                    and 标签出现[键] <= 别名工具.标签最多作品数 and 别名工具._可作别名的标签(标签["name"])
                    and 键 not in 名字 and 标签["name"].strip().lower() not in _书籍动画通用标签
                    and 像叫法(标签["name"], 条目.get("infobox") or "")):
                标签别名.append(标签["name"])
        信息别名 = _bangumi别名(条目.get("infobox")) + 别名工具._infobox值(条目.get("infobox") or "", "中文名")
        bangumi[编号] = (条目["name"], 条目.get("name_cn") or "", 信息别名, 标签别名, 收藏, 条目.get("platform"))

    # AniList ID → 热度（热度前 5000 部动画、漫画）
    热度表 = {int(ani): v[1] for ani, v in json.loads((数据目录 / "anilist-popularity.json").read_text()).items()}

    # 更多叫法：Wikidata 各语言的名称与别名（wikidata-names-P4086/P4087.json，SPARQL 结果），
    # 以及 anime-offline-database 汇总的各站别名（动画）
    其他名称 = {"ANIME": collections.defaultdict(list), "MANGA": collections.defaultdict(list)}
    for 类别, 属性 in (("ANIME", "P4086"), ("MANGA", "P4087")):
        路径 = 数据目录 / f"wikidata-names-{属性}.json"
        if 路径.exists():
            for 行 in json.loads(路径.read_text(encoding="utf-8"))["results"]["bindings"]:
                if 行["mal"]["value"].isdigit():
                    其他名称[类别][int(行["mal"]["value"])].append(行["l"]["value"])
    for 项 in json.loads((数据目录 / "aod.json").read_text(encoding="utf-8"))["data"]:
        for 地址 in 项["sources"]:
            if (m := re.match(r"https://myanimelist\.net/anime/(\d+)$", 地址)):
                其他名称["ANIME"][int(m.group(1))].extend([项["title"]] + (项.get("synonyms") or []))

    annict标题 = {}
    if (数据目录 / "annict-titles.jsonl").exists():
        for 项 in _读jsonl(数据目录 / "annict-titles.jsonl"):
            if 项.get("title"):
                annict标题[int(项["annict"])] = 项["title"]

    文档 = []
    for 类别, 文件名 in (("ANIME", "anilist-anime.jsonl"), ("MANGA", "anilist-manga.jsonl")):
        分组 = 映射["anime" if 类别 == "ANIME" else "manga"]
        anilist = {项["id"]: 项 for 项 in _读jsonl(数据目录 / 文件名)}
        aod标题 = {}
        if 类别 == "ANIME":
            for 项 in json.loads((数据目录 / "aod.json").read_text(encoding="utf-8"))["data"]:
                for 地址 in 项["sources"]:
                    if (m := re.match(r"https://myanimelist\.net/anime/(\d+)$", 地址)):
                        aod标题[int(m.group(1))] = 项["title"]
        # 映射里的每部作品（附属条目不单独成为作品）；漫画只写入了有 Bangumi 条目的，
        # AniList 热度前 5000 部里没有 Bangumi 条目的另外补上
        行们 = [(行[1], 行[2], 行[3], 行[4]) for 行 in 分组["works"]]
        if 类别 == "MANGA":
            已有 = {行[2] for 行 in 分组["works"] if 行[2]}
            for ani, (mal, _热度, _格式, 种) in ((int(k), v) for k, v in json.loads((数据目录 / "anilist-popularity.json").read_text()).items()):
                if 种 == "MANGA" and ani not in 已有 and ani in anilist:
                    行们.append((mal or anilist[ani].get("idMal"), ani, None, None))
        # 只在 Bangumi 上的作品（国产动画、映射没对上的条目等）：有一定收藏人数的也收录
        已对应 = {行[4] for 行 in 分组["works"] if 行[4]} | set(分组["attached"].get("bangumi", [])[0::2])
        for 编号, 条目 in bangumi.items():
            是动画 = 原始[编号]["type"] == 2
            # 书籍的单卷（“(2)”“第3巻”）属于某个系列，不单独收录
            if not 是动画 and _单卷.search(条目[0]):
                continue
            if 是动画 == (类别 == "ANIME") and 编号 not in 已对应 and 条目[4] >= (5 if 是动画 else 20):
                行们.append((None, None, None, 编号))
        for mal, ani, annict, bgm in 行们:
            项 = anilist.get(ani) if ani else None
            条目 = bangumi.get(bgm) if bgm else None
            if 类别 == "ANIME":
                种类 = "a"
            elif 项:
                种类 = "n" if 项.get("format") == "NOVEL" else "m"
            else:
                种类 = "n" if 条目 and 条目[5] == 1002 else "m"
            名称 = []
            显示 = None
            if 项:
                标题 = 项.get("title") or {}
                名称 += [标题.get("native"), 标题.get("romaji"), 标题.get("english")] + (项.get("synonyms") or [])
                显示 = 标题.get("romaji") or 标题.get("native")
            if mal and mal in aod标题:
                名称.append(aod标题[mal])
                显示 = 显示 or aod标题[mal]
            别名 = []
            热度 = (热度表.get(ani, 0) if ani else 0) / AniList热度换算
            if 条目:
                原名, 中文名, 信息别名, 标签别名, 收藏, _平台 = 条目
                名称 += [原名, 中文名] + 信息别名
                别名 = 标签别名
                显示 = 显示 or 原名
                热度 = max(热度, 收藏)
            if annict and annict in annict标题:
                名称.append(annict标题[annict])
                显示 = 显示 or annict标题[annict]
            if mal:
                名称 += [n for n in 其他名称[类别].get(mal, []) if len(n) <= 120]
            # 动画全部收录；漫画、轻小说收录有人收藏或比较热门的（其余靠各平台的在线搜索）
            if 类别 == "MANGA" and 热度 < 漫画最少热度:
                continue
            # 只留 App 支持的语言会输入的文字（拉丁字母、中日韩），其他文字的译名只会让模型变大
            名称 = list(dict.fromkeys(n.strip() for n in 名称 if n and n.strip() and not _其他文字.search(n)))
            if not 名称:
                continue
            # 编号：MAL ID；没有 MAL ID 时用最高位标出 AniList、Bangumi、Annict 的 ID（App 按同样的规则解码）
            if mal:
                编号 = mal
            elif ani:
                编号 = 0x8000_0000 | ani
            elif bgm:
                编号 = 0x4000_0000 | bgm
            elif annict:
                编号 = 0x2000_0000 | annict
            else:
                continue
            文档.append({"key": f"{种类}{编号}", "kind": 种类, "names": 名称, "aliases": 别名,
                         "热度": 热度, "display": 显示 or 名称[0]})

    for d in 文档:
        d["names"] = list(dict.fromkeys(d["names"] + d["aliases"]))
    最高 = max(d["热度"] for d in 文档)
    for d in 文档:
        d["prior"] = round(math.log1p(d.pop("热度")) / math.log1p(最高), 5)
    文档.sort(key=lambda d: ("amn".index(d["kind"]), int(d["key"][1:])))
    数量 = collections.Counter(d["kind"] for d in 文档)
    print(f"动画 {数量['a']}，漫画 {数量['m']}，轻小说 {数量['n']}")
    return 文档
