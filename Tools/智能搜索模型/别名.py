"""从 Bangumi 数据库导出补充中文名、别名和玩家常用的梗，加进名称模糊匹配索引。

VNDB 几乎没有简体中文名和中文圈的叫法（“白学”“WA2”“幼刀”这类），Bangumi 有：
- 条目的中文名、infobox 里的“别名”；
- 用户标签：只出现在极少数条目上、又有足够多人打的标签，往往就是这部作品的简称或梗；
- 角色的“简体中文名”和“别名”。

这些名称进 `名称.名称索引`，再用它们生成合成查询训练排序器（见 `模糊.py`）。

输出 `data/aliases.json`：{"文档键": ["补充名称", ...]}，以及 `data/alias-rank.jsonl`、`data/alias-eval.jsonl`。
"""

from __future__ import annotations

import collections
import json
import random
import re
from pathlib import Path

from . import 名称

# 条目的标签要当作别名，最多只能出现在这么多部作品上；越多越像通用标签（“催泪”“柚子社”）。
标签最多作品数 = 3
标签最少人数 = 8
# 标签人数至少要达到该条目最高标签人数的这个比例。
标签最低占比 = 0.03

_通用标签 = {
    "galgame", "gal", "pc", "adv", "avg", "游戏", "game", "视觉小说", "恋爱", "18禁", "r18", "全年龄",
    "汉化", "中文", "日本", "日语", "未通关", "想玩", "补完", "神作", "粪作", "废萌", "拔作", "黄油",
    "steam", "switch", "ns", "ps4", "ps5", "psv", "psp", "ps2", "ps3", "xbox360", "android", "ios",
    "同人", "同人游戏", "独立游戏", "国产", "国产gal", "移植", "重制", "合集", "fd", "续作", "前作",
}
_年份 = re.compile(r"^(19|20)\d\d$")
_别名项 = re.compile(r"\[(?:[^|\]]*\|)?([^\]]*)\]")


def _infobox值(infobox: str, 字段: str, 斜杠分隔: bool = False) -> list[str]:
    """读取 Bangumi infobox 里某个字段的值：单值 `|字段= 值` 或多值 `|字段={ [值] [标签|值] }`。"""
    结果 = []
    # 值为空时 `[ \t]*` 不能越过换行，否则会把下一行的 `|别名={` 当成值。
    匹配 = re.search(r"\|" + re.escape(字段) + r"[ \t]*=[ \t]*(\{.*?\}|[^\r\n]*)", infobox, re.S)
    if not 匹配:
        return 结果
    值 = 匹配.group(1).strip()
    if 值.startswith("{"):
        结果 = [v.strip() for v in _别名项.findall(值)]
    else:
        结果 = [值]
    拆分后 = []
    for v in 结果:
        拆分后.extend(_拆分别名(v, 斜杠分隔))
    return 拆分后


_括号 = re.compile(r"[（(]([^）)]*)[）)]")
_分隔 = re.compile(r"[，、;；|]")
_分隔含斜杠 = re.compile(r"[，,、;；|/／]")


def _拆分别名(值: str, 斜杠分隔: bool) -> list[str]:
    """一个别名字段里常塞着多个名字：“天才少女，克里斯蒂娜，助手”“凤凰院凶真(鳳凰院 凶真,ほうおういん きょうま)”。

    作品名里的斜杠、顿号可能是标题本身的一部分（Fate/stay night、恋爱、初邂逅），所以作品名
    （`斜杠分隔` 为假）总是保留整串，只有拆出的每一段都至少 4 个字时才另外加上各段。
    """
    if not 值 or 值.startswith("{") or 值.startswith("|"):
        return []
    括号内 = _括号.findall(值)
    主体 = _括号.sub(" ", 值).strip()
    结果 = []

    def 清理(v: str) -> str:
        return v.strip(" 　“”\"'「」『』《》")

    for 片段 in [主体] + 括号内:
        if 斜杠分隔:
            段 = [清理(v) for v in _分隔含斜杠.split(片段)]
            结果.extend(v for v in 段 if v and len(v) <= 40)
            continue
        整串 = 清理(片段)
        if 整串 and len(整串) <= 60:
            结果.append(整串)
        段 = [清理(v) for v in _分隔.split(片段)]
        if len(段) > 1 and all(len(名称.规范化(v)) >= 4 for v in 段):
            结果.extend(v for v in 段 if len(v) <= 40)
    return 结果


_常见称呼 = {
    "天才", "变态", "哥哥", "姐姐", "妹妹", "弟弟", "主人公", "主角", "男主", "女主", "男主角", "女主角",
    "魔女", "少女", "少年", "大小姐", "学姐", "学长", "学妹", "前辈", "后辈", "老师", "班长", "会长",
    "笨蛋", "公主", "王子", "天使", "恶魔", "女仆", "管家", "妈妈", "爸爸", "母亲", "父亲", "奶奶",
    "师傅", "师父", "大人", "小姐", "先生", "老大", "boss", "master", "sensei", "onisan", "oneesan",
    # 别名括号里的注释词
    "网名", "爱称", "昵称", "本名", "全名", "旧名", "原名", "英文名", "日文名", "中文名", "假名", "外号", "绰号",
}


def _停用词(语料: list[dict]) -> set[str]:
    """标签、特征的中文名和常见称呼：这些词描述的是一类人或作品，不能当某一个条目的名字。"""
    词 = {名称.规范化(w) for w in _常见称呼}
    for d in 语料:
        for 行 in d["text"].split("\n"):
            if 行.startswith("标签：") or 行.startswith("特征："):
                词.update(名称.规范化(w) for w in 行[3:].split("、"))
    return {w for w in 词 if w}


def _读取jsonl(路径: Path):
    with open(路径, encoding="utf-8") as 文件:
        for 行 in 文件:
            if 行.strip():
                yield json.loads(行)


def _可作别名的标签(标签: str) -> bool:
    键 = 名称.规范化(标签)
    if len(键) < 2 or _年份.match(键) or 键.isdigit():
        return False
    if 标签.strip().lower() in _通用标签 or 键 in _通用标签:
        return False
    # 纯拉丁字母的标签至少 2 个字母且不能太长（太长的通常是整句评价）。
    return len(键) <= 24


def 构建(导出目录: Path, bangumi目录: Path, 映射文件: Path, 数据目录: Path, 种子: int = 20261007):
    语料 = [json.loads(行) for 行 in open(数据目录 / "corpus.jsonl", encoding="utf-8")]
    文档下标 = {d["key"]: i for i, d in enumerate(语料)}
    原有名称 = {d["key"]: {名称.规范化(n) for n in d["names"]} for d in 语料}

    # MARK: Bangumi 条目 → VNDB 作品
    条目: dict[int, dict] = {}
    链接映射: dict[int, set[str]] = collections.defaultdict(set)
    标签出现: collections.Counter[str] = collections.Counter()
    for d in _读取jsonl(bangumi目录 / "subject.jsonlines"):
        if d.get("type") != 4:
            continue
        条目[d["id"]] = d
        for v in re.findall(r"vndb\.org/(v\d+)", d.get("infobox") or ""):
            if v in 文档下标:
                链接映射[d["id"]].add(v)
        for 标签 in d.get("tags") or []:
            if 标签["count"] >= 3:
                标签出现[名称.规范化(标签["name"])] += 1

    有链接的作品 = {v for vs in 链接映射.values() for v in vs}
    映射数据 = json.loads(映射文件.read_text(encoding="utf-8"))["entries"]
    for 项 in 映射数据:
        v, b = 项.get("vndb"), 项.get("bangumi")
        if not v or not b or v not in 文档下标 or v in 有链接的作品:
            continue
        for 编号 in re.findall(r"\d+", b):
            d = 条目.get(int(编号))
            if not d:
                continue
            # 映射表有按名字猜的错配（如命运石之门指向 RE:BOOT），要求 Bangumi 的名字和 VNDB 的某个名字一致。
            候选 = {名称.规范化(d["name"]), 名称.规范化(d.get("name_cn") or "")} - {""}
            if 候选 & 原有名称[v]:
                链接映射[int(编号)].add(v)

    作品条目: dict[str, list[int]] = collections.defaultdict(list)
    for 编号, vs in 链接映射.items():
        if len(vs) == 1:
            作品条目[next(iter(vs))].append(编号)

    别名: dict[str, dict[str, tuple[str, str]]] = collections.defaultdict(dict)  # 键 → {规范化名: (原文, 来源)}
    停用 = _停用词(语料)

    def 添加(键: str, 名: str, 来源: str):
        名 = 名.strip()
        规范 = 名称.规范化(名)
        if len(规范) < 2 or 规范 in 原有名称[键] or 规范 in 别名[键]:
            return
        # 描述性的词（“变态”“天才”“傲娇”）当成名字会让搜这些词时以为找到了某个角色。
        if 来源 != "community" and 规范 in 停用:
            return
        别名[键][规范] = (名, 来源)

    # 已经是某个条目名字的标签（如 Fate 作品上的“Saber”、白色相簿2 上的女主角名）不当作品别名，
    # 否则搜角色名时会先给出作品。
    全部名字 = set().union(*原有名称.values())

    for v, 编号列表 in 作品条目.items():
        标签人数: collections.Counter[str] = collections.Counter()
        标签原文: dict[str, str] = {}
        最高 = 1
        for 编号 in 编号列表:
            d = 条目[编号]
            for 名 in [d.get("name_cn") or ""] + _infobox值(d.get("infobox") or "", "中文名") + _infobox值(d.get("infobox") or "", "别名"):
                if 名:
                    添加(v, 名, "name")
            for 标签 in d.get("tags") or []:
                键 = 名称.规范化(标签["name"])
                标签人数[键] += 标签["count"]
                标签原文.setdefault(键, 标签["name"])
                最高 = max(最高, 标签["count"])
        for 键, 人数 in 标签人数.items():
            if (人数 >= 标签最少人数 and 人数 >= 标签最低占比 * 最高
                    and 标签出现[键] <= 标签最多作品数 and _可作别名的标签(标签原文[键])
                    and 键 not in 全部名字):
                添加(v, 标签原文[键], "tag")

    # MARK: 社区别名（手工维护）
    社区 = json.loads((Path(__file__).with_name("社区别名.json")).read_text(encoding="utf-8"))
    for 键, 名列表 in 社区.items():
        if 键.startswith("_"):
            continue
        if 键 not in 文档下标:
            if 键[0] in "vc":
                print(f"社区别名里的 {键} 不在语料中，已跳过")
            continue  # 会社和制作人员在 `模糊.构建文档` 里并入
        for 名 in 名列表:
            添加(键, 名, "community")

    # MARK: 角色
    vndb角色作品: dict[str, set[str]] = collections.defaultdict(set)
    with open(导出目录 / "db" / "chars_vns", encoding="utf-8") as 文件:
        for 行 in 文件:
            c, vn = 行.split("\t")[:2]
            if c in 文档下标 and vn in 文档下标:
                vndb角色作品[vn].add(c)
    作品角色名: dict[str, dict[str, str]] = {}
    for vn, cs in vndb角色作品.items():
        表 = {}
        for c in cs:
            for n in 语料[文档下标[c]]["names"]:
                表.setdefault(名称.规范化(n), c)
        作品角色名[vn] = 表

    条目到作品 = {编号: v for v, 编号列表 in 作品条目.items() for 编号 in 编号列表}
    条目角色: dict[int, set[int]] = collections.defaultdict(set)
    需要的角色: set[int] = set()
    for d in _读取jsonl(bangumi目录 / "subject-characters.jsonlines"):
        if d["subject_id"] in 条目到作品:
            条目角色[d["subject_id"]].add(d["character_id"])
            需要的角色.add(d["character_id"])
    角色数据 = {}
    for d in _读取jsonl(bangumi目录 / "character.jsonlines"):
        if d["id"] in 需要的角色:
            角色数据[d["id"]] = d
    角色匹配 = 0
    for 编号, 角色集合 in 条目角色.items():
        表 = 作品角色名.get(条目到作品[编号], {})
        for 角色 in 角色集合:
            d = 角色数据.get(角色)
            if not d:
                continue
            infobox = d.get("infobox") or ""
            日文 = [d["name"]] + _infobox值(infobox, "日文名") + _infobox值(infobox, "纯假名")
            c = next((表[名称.规范化(n)] for n in 日文 if 名称.规范化(n) in 表), None)
            if not c:
                continue
            角色匹配 += 1
            for 名 in _infobox值(infobox, "简体中文名", True):
                添加(c, 名, "char")
            for 名 in _infobox值(infobox, "别名", True):
                添加(c, 名, "char-alias")

    # 同一个角色别名出现在 3 个以上的条目上，多半是“哥哥”“主人公”这类称呼，不能用来认人。
    角色别名条目数 = collections.Counter(
        规范 for 表 in 别名.values() for 规范, (_, 来源) in 表.items() if 来源 == "char-alias"
    )
    for 表 in 别名.values():
        for 规范 in [k for k, (_, 来源) in 表.items() if 来源 == "char-alias" and 角色别名条目数[k] >= 3]:
            del 表[规范]
        for 规范, (原文, 来源) in list(表.items()):
            if 来源 == "char-alias":
                表[规范] = (原文, "char")

    输出 = {键: [原文 for 原文, _ in 表.values()] for 键, 表 in 别名.items() if 表}
    (数据目录 / "aliases.json").write_text(json.dumps(输出, ensure_ascii=False), encoding="utf-8")
    来源计数 = collections.Counter(来源 for 表 in 别名.values() for _, 来源 in 表.values())
    print(f"映射作品 {len(作品条目)}，匹配角色 {角色匹配}，补充名称 {sum(len(v) for v in 输出.values())}（{dict(来源计数)}）")

    生成查询(语料, 文档下标, 别名, 数据目录, 种子)
    return 输出


# MARK: 合成查询

def _扰动(名: str, 随机: random.Random) -> str:
    """输错或记不全：删字、换位、重复、拉丁字母邻键。"""
    字 = list(名)
    位置 = [i for i, c in enumerate(字) if not c.isspace()]
    if len(位置) < 3:
        return 名
    选择 = 随机.random()
    i = 随机.choice(位置)
    if 选择 < 0.35:
        del 字[i]
    elif 选择 < 0.6 and i + 1 < len(字):
        字[i], 字[i + 1] = 字[i + 1], 字[i]
    elif 选择 < 0.8:
        字.insert(i, 字[i])
    else:
        字[i] = 随机.choice("aeiounrstlkmh") if 字[i].isascii() else 字[i]
    return "".join(字)


def 生成查询(语料: list[dict], 文档下标: dict[str, int], 别名: dict, 数据目录: Path, 种子: int):
    """用补充名称生成排序器训练与评估查询。来源文档在原评估集里的放进评估，其余用于训练排序器。

    名称精确对应的全部文档都是正例；软标签训练会按热度在它们之间分配。
    """
    随机 = random.Random(种子)
    评估来源 = {json.loads(行)["src"] for 行 in open(数据目录 / "eval.jsonl", encoding="utf-8")}
    精确: dict[str, set[int]] = collections.defaultdict(set)
    for i, d in enumerate(语料):
        for n in d["names"]:
            精确[名称.规范化(n)].add(i)
    for 键, 表 in 别名.items():
        for 规范 in 表:
            精确[规范].add(文档下标[键])

    训练, 评估 = [], []
    for 键, 表 in 别名.items():
        下标 = 文档下标[键]
        # 热门条目的别名更常被搜索；冷门条目按先验抽样，避免查询集被冷门同人作品占满。
        保留概率 = 0.15 + 0.85 * 语料[下标]["prior"] ** 2
        for 规范, (原文, 来源) in 表.items():
            # 角色别名数量远多于其他来源，全部放进来会让排序器过分相信“别名完全一致”而忽略热度。
            if 来源 == "char" and 随机.random() > 0.4:
                continue
            if 来源 != "community" and 随机.random() > 保留概率:
                continue
            正例 = 精确[规范]
            if len(正例) > 50:
                continue
            类型 = {"name": "alias", "tag": "alias-tag", "char": "alias-char", "community": "alias-community"}[来源]
            查询 = [{"q": 原文, "pos": sorted(正例), "type": 类型, "lang": "zh-Hans", "src": 键}]
            if len(规范) >= 3 and 随机.random() < 0.6:
                扰动后 = _扰动(原文, 随机)
                if 名称.规范化(扰动后) != 规范:
                    正例2 = 精确.get(名称.规范化(扰动后), set()) | {下标}
                    查询.append({"q": 扰动后, "pos": sorted(正例2), "type": 类型 + "-noisy", "lang": "zh-Hans", "src": 键})
            (评估 if 键 in 评估来源 else 训练).extend(查询)

    # 原有标题和名字的输错版本：现有排序器训练数据里这类查询太少，导致输错时把握不足。
    for i, d in enumerate(语料):
        if 随机.random() > 0.02 + 0.3 * d["prior"] ** 2:
            continue
        名 = 随机.choice(d["names"]) if d["names"] else d["display"]
        规范 = 名称.规范化(名)
        if len(规范) < 4:
            continue
        扰动后 = _扰动(名, 随机)
        if 名称.规范化(扰动后) == 规范:
            continue
        正例 = 精确.get(名称.规范化(扰动后), set()) | {i}
        q = {"q": 扰动后, "pos": sorted(正例), "type": "typo", "lang": "", "src": d["key"]}
        (评估 if d["key"] in 评估来源 else 训练).append(q)

    # 只输入一个标签或特征词（“恋爱”“猫娘”）时，用户要的是这一类里的热门作品或角色，
    # 而不是恰好叫这个名字的冷门条目；正例是带这个标签的热门条目，让排序器学会此时把握不大。
    成员: dict[str, list[int]] = collections.defaultdict(list)
    for i, d in enumerate(语料):
        for 行 in d["text"].split("\n"):
            if 行.startswith("标签：") or 行.startswith("特征："):
                for 词 in 行[3:].split("、"):
                    成员[词.strip()].append(i)
    for 词, 下标列表 in 成员.items():
        if len(下标列表) < 10 or len(名称.规范化(词)) < 2:
            continue
        热门 = sorted(下标列表, key=lambda i: -语料[i]["prior"])[:200]
        q = {"q": 词, "pos": sorted(热门), "type": "tag-bare", "lang": "zh-Hans", "src": 语料[热门[0]]["key"]}
        (评估 if 随机.random() < 0.1 else 训练).append(q)

    随机.shuffle(训练)
    for 文件名, 数据 in (("alias-rank.jsonl", 训练), ("alias-eval.jsonl", 评估)):
        with open(数据目录 / 文件名, "w", encoding="utf-8") as 文件:
            for q in 数据:
                文件.write(json.dumps(q, ensure_ascii=False) + "\n")
    print(f"别名查询：排序训练 {len(训练)}，评估 {len(评估)}，类型 {dict(collections.Counter(q['type'] for q in 训练))}")


def 合并别名(语料: list[dict], 数据目录: Path) -> list[dict]:
    """把 aliases.json 里的补充名称并进语料的 names（只影响名称索引，不影响文档向量）。"""
    路径 = 数据目录 / "aliases.json"
    if not 路径.exists():
        return 语料
    别名 = json.loads(路径.read_text(encoding="utf-8"))
    for d in 语料:
        if d["key"] in 别名:
            d["names"] = d["names"] + 别名[d["key"]]
    return 语料
