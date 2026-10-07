"""纯名称模糊匹配模型：作品、角色、会社、制作人员的名字、别名和梗，输错、输几个字都能找到。

不做语义（剧情描述）检索，也就没有查询编码器：App 只需要名称索引和一个小排序器，文件只有几十 MB。

文档：
- 作品、角色来自 `prepare` 阶段的 corpus.jsonl，再并入 `aliases` 阶段的中文名、别名和梗；
- 会社、制作人员直接读 VNDB 数据库导出，热度按其作品的投票数估计；
- 每部作品带一个系列编号（续作、前传、FD、外传、同系列等关系连成的组），每个角色带所属作品，
  App 用它们把同系列作品叠在一起、把角色挂在作品下面。

排序器只用名称匹配特征和热度。训练查询按“用户真的会这么搜”的方式从名字生成：完整名字、开头几个字、
中间几个字、输错的名字、别名和梗；同样能匹配的条目都是正例，正例概率按热度分配。
"""

from __future__ import annotations

import bisect
import collections
import hashlib
import json
import math
import random
import struct
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

from . import 别名, 名称

格式版本 = 2
文件名 = "PaperVNSmartSearch.pvss"
类型顺序 = ["v", "c", "p", "s"]

名称候选数 = 80
覆盖候选数 = 40

特征名 = [
    "f", "p", "r", "exact", "prefix", "contains", "f_gap", "prior", "prior_gap",
    "is_char", "is_producer", "is_staff", "len_ratio", "query_len", "query_cjk",
]
空特征名 = ["f_max", "exact_any", "prefix_any", "query_len", "query_cjk"]

_系列关系 = {"seq", "preq", "fan", "orig", "par", "side", "alt", "ser"}


def _读表(目录: Path, 表名: str):
    with open(目录 / 表名, encoding="utf-8") as 文件:
        for 行 in 文件:
            yield [None if 值 == "\\N" else 值 for 值 in 行.rstrip("\n").split("\t")]


# MARK: - 文档

def 构建文档(导出目录: Path, 数据目录: Path) -> list[dict]:
    """返回按 作品、角色、会社、制作人员 排好的文档：key、kind、names、prior、display、series、parent。"""
    db = 导出目录 / "db"
    语料 = 别名.合并别名([json.loads(行) for 行 in open(数据目录 / "corpus.jsonl", encoding="utf-8")], 数据目录)
    作品 = [d for d in 语料 if d["kind"] == "v"]
    角色 = [d for d in 语料 if d["kind"] == "c"]
    作品键 = {d["key"] for d in 作品}
    角色键 = {d["key"] for d in 角色}

    票数 = {}
    for 行 in _读表(db, "vn"):
        票数[行[0]] = int(行[4] or 0)
    最高票 = max(票数.values())

    def 热度(总票数: float, 系数: float) -> float:
        return min(1.0, 系数 * math.log1p(总票数) / math.log1p(最高票))

    # 系列：并查集
    父: dict[str, str] = {}

    def 找(x: str) -> str:
        while 父.get(x, x) != x:
            父[x] = 父.get(父[x], 父[x])
            x = 父[x]
        return x

    for 行 in _读表(db, "vn_relations"):
        a, b, 关系 = 行[0], 行[1], 行[2]
        if 关系 in _系列关系 and a in 作品键 and b in 作品键:
            父.setdefault(a, a)
            父.setdefault(b, b)
            ra, rb = 找(a), 找(b)
            if ra != rb:
                父[ra] = rb
    根编号: dict[str, int] = {}
    for d in 作品:
        if d["key"] in 父:
            根 = 找(d["key"])
            # 系列编号取组里编号最小的作品，稳定且可读
            根编号.setdefault(根, 0)
    组成员 = collections.defaultdict(list)
    for d in 作品:
        if d["key"] in 父:
            组成员[找(d["key"])].append(int(d["key"][1:]))
    系列 = {}
    for 根, 成员 in 组成员.items():
        if len(成员) >= 2:
            代表 = min(成员)
            for 编号 in 成员:
                系列[f"v{编号}"] = 代表

    # 角色所属作品：主要角色优先，再按作品票数
    角色作品 = collections.defaultdict(list)
    权重 = {"main": 3, "primary": 2, "side": 1, "appears": 0}
    for 行 in _读表(db, "chars_vns"):
        c, v, 定位 = 行[0], 行[1], 行[3]
        if c in 角色键 and v in 作品键:
            角色作品[c].append((权重.get(定位, 0), 票数.get(v, 0), v))
    for d in 角色:
        候选 = sorted(角色作品.get(d["key"], []), reverse=True)
        d["parent"] = int(候选[0][2][1:]) if 候选 else 0

    for d in 作品:
        d["series"] = 系列.get(d["key"], 0)

    # 会社：按开发的作品的票数
    发行作品 = collections.defaultdict(set)
    for 行 in _读表(db, "releases_vn"):
        发行作品[行[0]].add(行[1])
    会社票数 = collections.Counter()
    for 行 in _读表(db, "releases_producers"):
        r, p, 开发 = 行[0], 行[1], 行[2]
        for v in 发行作品.get(r, ()):
            if v in 作品键:
                会社票数[(p, v)] = max(会社票数[(p, v)], 票数.get(v, 0) * (1.0 if 开发 == "t" else 0.5))
    会社总票 = collections.Counter()
    for (p, _), n in 会社票数.items():
        会社总票[p] += n
    会社 = []
    for 行 in _读表(db, "producers"):
        p, 名, 拉丁, 别名列表 = 行[0], 行[3], 行[4], 行[5]
        if 会社总票[p] <= 0:
            continue
        名称列表 = [n for n in [名, 拉丁] + (别名列表 or "").split("\n") if n]
        会社.append({
            "key": p, "kind": "p", "names": 名称列表, "prior": round(热度(会社总票[p], 0.9), 5),
            "display": 拉丁 or 名,
        })

    # 制作人员：按参与作品的票数
    别名到人 = {}
    人员名 = collections.defaultdict(list)
    for 行 in _读表(db, "staff_alias"):
        s, aid, 名, 拉丁 = 行[0], 行[1], 行[2], 行[3]
        别名到人[aid] = s
        人员名[s].extend(n for n in [名, 拉丁] if n)
    主名 = {}
    for 行 in _读表(db, "staff"):
        主名[行[0]] = 行[3]
    人员作品 = collections.defaultdict(set)
    for 行 in _读表(db, "vn_staff"):
        v, aid = 行[0], 行[1]
        if v in 作品键 and aid in 别名到人:
            人员作品[别名到人[aid]].add(v)
    for 行 in _读表(db, "vn_seiyuu"):
        v, aid = 行[0], 行[2]
        if v in 作品键 and aid in 别名到人:
            人员作品[别名到人[aid]].add(v)
    主名显示 = {}
    for 行 in _读表(db, "staff_alias"):
        s, aid, 名, 拉丁 = 行[0], 行[1], 行[2], 行[3]
        if 主名.get(s) == aid:
            主名显示[s] = 拉丁 or 名
    人员 = []
    for s, 作品集 in 人员作品.items():
        总票 = sum(票数.get(v, 0) for v in 作品集)
        人员.append({
            "key": s, "kind": "s", "names": list(dict.fromkeys(人员名[s])),
            "prior": round(热度(总票, 0.8), 5), "display": 主名显示.get(s, 人员名[s][0]),
        })
    会社.sort(key=lambda d: int(d["key"][1:]))
    人员.sort(key=lambda d: int(d["key"][1:]))

    # 会社和制作人员的中文叫法（“柚子社”“奈须蘑菇”）只在手工维护的社区别名里
    社区 = json.loads((Path(__file__).with_name("社区别名.json")).read_text(encoding="utf-8"))
    for d in 会社 + 人员:
        d["names"] = list(dict.fromkeys(d["names"] + 社区.get(d["key"], [])))

    文档 = 作品 + 角色 + 会社 + 人员
    print(f"作品 {len(作品)}（{len(set(系列.values()))} 个系列），角色 {len(角色)}，会社 {len(会社)}，制作人员 {len(人员)}")
    return 文档


# MARK: - 查询

class 名称查找:
    """训练时判断哪些文档满足“完全一致 / 以此开头 / 包含”。"""

    def __init__(self, 文档: list[dict]):
        self.精确 = collections.defaultdict(set)
        条目 = []
        for i, d in enumerate(文档):
            for n in d["names"]:
                k = 名称.规范化(n)
                if k:
                    self.精确[k].add(i)
                    条目.append((k, i))
        条目.sort()
        self.键 = [k for k, _ in 条目]
        self.值 = [v for _, v in 条目]

    def 前缀(self, k: str, 上限: int = 2000) -> set[int] | None:
        左 = bisect.bisect_left(self.键, k)
        右 = bisect.bisect_left(self.键, k + "\U0010ffff")
        if 右 - 左 > 上限:
            return None
        return set(self.值[左:右])


def _切片(名: str, 随机: random.Random, 开头: bool) -> str | None:
    """取名字的开头或中间几个字：汉字和假名 2～4 个字，拉丁字母取一个或几个词或 3～8 个字母。"""
    if 名称.含中日文(名):
        字 = [c for c in 名 if not c.isspace()]
        if len(字) < 3:
            return None
        长度 = 随机.randint(2, min(4, len(字) - 1))
        起点 = 0 if 开头 else 随机.randint(1, len(字) - 长度)
        return "".join(字[起点:起点 + 长度])
    词 = 名.split()
    if 开头:
        if len(词) >= 2 and 随机.random() < 0.5:
            return " ".join(词[: 随机.randint(1, len(词) - 1)])
        字 = 名.replace(" ", "")
        if len(字) < 5:
            return None
        return 名[: 随机.randint(3, min(8, len(名) - 1))]
    if len(词) >= 2:
        return 随机.choice(词[1:])
    return None


def 生成查询(文档: list[dict], 数据目录: Path, 种子: int, 每文档基数: float = 0.03) -> tuple[list[dict], list[dict]]:
    随机 = random.Random(种子)
    别名表 = json.loads((数据目录 / "aliases.json").read_text(encoding="utf-8")) if (数据目录 / "aliases.json").exists() else {}
    别名规范 = {k: {名称.规范化(n) for n in v} for k, v in 别名表.items()}

    def 评估文档(键: str) -> bool:
        return int(hashlib.md5(键.encode()).hexdigest()[:8], 16) % 100 < 3

    训练, 评估 = [], []
    for i, d in enumerate(文档):
        次数期望 = 每文档基数 * 4 + 6 * d["prior"] ** 1.5
        次数 = int(次数期望) + (随机.random() < 次数期望 - int(次数期望))
        if not d["names"]:
            continue
        for _ in range(次数):
            名列表 = d["names"]
            别名们 = [n for n in 名列表 if 名称.规范化(n) in 别名规范.get(d["key"], set())]
            if 别名们 and 随机.random() < 0.25:
                名 = 随机.choice(别名们)
                来源 = "alias"
            else:
                # 中文玩家多用中文名或原名，短名字更常被搜
                中文 = [n for n in 名列表 if 名称.含汉字(n) and not 名称.含假名(n)]
                if 中文 and 随机.random() < 0.4:
                    名 = 随机.choice(中文)
                else:
                    名 = 随机.choice(名列表)
                来源 = "name"
            选择 = 随机.random()
            if 选择 < 0.3:
                q = {"q": 名, "rel": "exact", "type": 来源}
            elif 选择 < 0.55:
                片 = _切片(名, 随机, True)
                if not 片:
                    continue
                q = {"q": 片, "rel": "prefix", "type": 来源 + "-prefix"}
            elif 选择 < 0.68:
                片 = _切片(名, 随机, False)
                if not 片:
                    continue
                q = {"q": 片, "rel": "contains", "type": 来源 + "-infix"}
            else:
                错 = 别名._扰动(名, 随机)
                if 名称.规范化(错) == 名称.规范化(名):
                    continue
                q = {"q": 错, "rel": "noisy", "type": 来源 + "-typo"}
            q["src"] = i
            q["kind"] = d["kind"]
            (评估 if 评估文档(d["key"]) else 训练).append(q)

    # 乱输入和只输入一个标签词：没有哪个条目是“它要找的”，排序器要学会这时把握不大。
    常用字 = "的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经"
    for _ in range(4000):
        if 随机.random() < 0.5:
            文本 = "".join(随机.choice("asdfghjklqwertyuiopzxcvbnm") for _ in range(随机.randint(3, 9)))
        else:
            文本 = "".join(随机.choice(常用字) for _ in range(随机.randint(2, 5)))
        (评估 if 随机.random() < 0.15 else 训练).append({"q": 文本, "rel": "none", "type": "neg", "src": -1, "kind": ""})
    标签词 = set()
    for d in 文档:
        for 行 in (d.get("text") or "").split("\n"):
            if 行.startswith("标签：") or 行.startswith("特征："):
                标签词.update(w.strip() for w in 行[3:].split("、") if len(w.strip()) >= 2)
    for 词 in 随机.sample(sorted(标签词), min(2500, len(标签词))):
        (评估 if 随机.random() < 0.1 else 训练).append({"q": 词, "rel": "none", "type": "tag", "src": -1, "kind": ""})

    随机.shuffle(训练)
    计数 = collections.Counter(q["type"] for q in 训练)
    print(f"训练查询 {len(训练)}，评估查询 {len(评估)}，类型 {dict(计数)}")
    return 训练, 评估


# MARK: - 特征（App 的 `智能搜索引擎.swift` 按同样的方式计算）

class 特征计算:
    def __init__(self, 文档: list[dict]):
        self.文档 = 文档
        self.索引 = 名称.名称索引([d["names"] for d in 文档])
        self.先验 = np.array([d["prior"] for d in 文档], dtype=np.float32)
        self.类型 = np.array([类型顺序.index(d["kind"]) for d in 文档], dtype=np.int8)
        self.名称长度 = np.array([len(n) for n in self.索引.名称], dtype=np.int32)

    def 候选(self, 规范: str, 重合: np.ndarray, 查询权重: float) -> list[int]:
        索引 = self.索引
        命中 = np.nonzero(重合)[0]
        if len(命中) == 0:
            return []
        # 一：按名称 F 值
        f = 2 * 重合[命中] / (查询权重 + 索引.名称权重[命中])
        顺序 = np.argsort(-f, kind="stable")
        结果, 已有 = [], set()
        for k in 顺序:
            d = int(索引.所属[命中[k]])
            if d not in 已有:
                已有.add(d)
                结果.append(d)
                if len(结果) >= 名称候选数:
                    break
        # 二：查询的所有片段都出现在名字里（输入的是名字的一部分）时，按热度补上最热门的条目，
        # 否则只输开头几个字时，长标题的热门作品会被一堆短名字挤出候选。
        全覆盖 = 命中[重合[命中] >= 查询权重 - 1e-4]
        if len(全覆盖):
            文档们 = np.unique(索引.所属[全覆盖])
            热门 = 文档们[np.argsort(-self.先验[文档们], kind="stable")]
            加入 = 0
            for d in 热门:
                d = int(d)
                if d not in 已有:
                    已有.add(d)
                    结果.append(d)
                    加入 += 1
                    if 加入 >= 覆盖候选数:
                        break
        return 结果

    def 计算(self, 查询: str):
        规范 = 名称.规范化(查询)
        片段, 查询权重 = self.索引.查询片段(规范)
        if not 片段:
            return 规范, [], None, None
        重合 = self.索引.重合(片段)
        候选 = self.候选(规范, 重合, 查询权重)
        if not 候选:
            return 规范, [], None, None
        名称特征 = np.array([self.索引.文档特征(规范, 重合, 查询权重, d) for d in 候选], dtype=np.float32)
        长度比 = np.array([self._长度比(规范, 重合, 查询权重, d) for d in 候选], dtype=np.float32)
        先验 = self.先验[候选]
        类型 = self.类型[候选]
        查询长度 = min(len(规范), 32) / 32
        中日韩 = float(名称.含中日文(查询))
        特征 = np.zeros((len(候选), len(特征名)), dtype=np.float32)
        特征[:, 0:6] = 名称特征
        特征[:, 6] = 名称特征[:, 0] - 名称特征[:, 0].max()
        特征[:, 7] = 先验
        特征[:, 8] = 先验 - 先验.max()
        特征[:, 9] = 类型 == 1
        特征[:, 10] = 类型 == 2
        特征[:, 11] = 类型 == 3
        特征[:, 12] = 长度比
        特征[:, 13] = 查询长度
        特征[:, 14] = 中日韩
        空特征 = np.array([
            名称特征[:, 0].max(), 名称特征[:, 3].max(), 名称特征[:, 4].max(), 查询长度, 中日韩,
        ], dtype=np.float32)
        return 规范, 候选, 特征, 空特征

    def _长度比(self, 规范: str, 重合: np.ndarray, 查询权重: float, d: int) -> float:
        """查询长度占该文档 F 值最高的名字长度的比例：只输了长标题的开头两个字时这个值很小。"""
        索引 = self.索引
        起, 止 = 索引.文档名称起点[d], 索引.文档名称起点[d + 1]
        if 止 <= 起:
            return 0.0
        f = 2 * 重合[起:止] / (查询权重 + 索引.名称权重[起:止])
        i = int(np.argmax(f))
        return min(1.0, len(规范) / max(int(self.名称长度[起 + i]), 1))

    def 正例(self, q: dict, 规范: str, 候选: list[int], 查找: 名称查找) -> set[int]:
        关系 = q["rel"]
        if 关系 == "none":
            return set()
        if 关系 == "exact":
            结果 = set(查找.精确.get(规范, set()))
        elif 关系 == "prefix":
            结果 = 查找.前缀(规范) or set()
        elif 关系 == "contains":
            结果 = {d for d in 候选 if any(规范 in 名称.规范化(n) for n in self.文档[d]["names"])}
        else:  # noisy
            结果 = set(查找.精确.get(规范, set()))
        if q["src"] >= 0:
            结果.add(q["src"])
        return 结果


def 准备样本(查询: list[dict], 计算: 特征计算, 查找: 名称查找, 进度: str = ""):
    样本 = []
    开始 = time.time()
    for n, q in enumerate(查询):
        规范, 候选, 特征, 空特征 = 计算.计算(q["q"])
        if not 候选:
            continue
        正例 = 计算.正例(q, 规范, 候选, 查找)
        if len(正例) > 300:
            continue
        标签 = np.array([d in 正例 for d in 候选] + [not 正例], dtype=bool)
        if not 标签.any():
            continue
        样本.append((q, 候选, 特征, 空特征, 标签))
        if 进度 and n % 20000 == 0 and n:
            print(f"{进度} {n}/{len(查询)}，{(time.time() - 开始) / n * 1000:.1f} ms/条", flush=True)
    return 样本


# MARK: - 排序器

class 排序器(nn.Module):
    def __init__(self, 隐藏: int = 48):
        super().__init__()
        self.网络 = nn.Sequential(
            nn.Linear(len(特征名), 隐藏), nn.ReLU(),
            nn.Linear(隐藏, 隐藏), nn.ReLU(),
            nn.Linear(隐藏, 1),
        )
        self.空 = nn.Linear(len(空特征名), 1)

    def 导出(self) -> dict:
        层 = [m for m in self.网络 if isinstance(m, nn.Linear)]
        return {
            "features": 特征名,
            "nullFeatures": 空特征名,
            "layers": [{"weight": l.weight.detach().tolist(), "bias": l.bias.detach().tolist()} for l in 层],
            "null": {"weight": self.空.weight.detach()[0].tolist(), "bias": float(self.空.bias.detach()[0])},
        }


def _张量(样本: list):
    最多 = max(len(c) for _, c, *_ in 样本)
    n = len(样本)
    特征 = torch.zeros(n, 最多, len(特征名))
    空特征 = torch.zeros(n, len(空特征名))
    有效 = torch.zeros(n, 最多 + 1, dtype=torch.bool)
    标签 = torch.zeros(n, 最多 + 1, dtype=torch.bool)
    for i, (_, c, f, e, l) in enumerate(样本):
        k = len(c)
        特征[i, :k] = torch.from_numpy(f)
        空特征[i] = torch.from_numpy(e)
        有效[i, :k] = True
        有效[i, 最多] = True
        标签[i, :k] = torch.from_numpy(l[:-1])
        标签[i, 最多] = bool(l[-1])
    return 特征, 空特征, 有效, 标签


def 打分(模型: 排序器, 特征: torch.Tensor, 空特征: torch.Tensor, 有效: torch.Tensor) -> torch.Tensor:
    分 = torch.cat([模型.网络(特征).squeeze(-1), 模型.空(空特征)], 1)
    return 分.masked_fill(~有效, -1e4)


def 训练排序器(样本: list, 轮数: int = 25, 热度系数: float = 10.0, 热度权重: float = 1.0, 种子: int = 0) -> 排序器:
    """软标签：正例概率按 exp(热度系数 × 先验) 分配，样本按目标期望热度加权（热门的被搜得多）。"""
    torch.manual_seed(种子)
    模型 = 排序器()
    优化器 = torch.optim.AdamW(模型.parameters(), lr=3e-3, weight_decay=1e-4)
    特征, 空特征, 有效, 标签 = _张量(样本)
    先验 = 特征[:, :, 特征名.index("prior")]
    目标 = torch.softmax(torch.cat([
        torch.where(标签[:, :-1], 热度系数 * 先验, torch.full_like(先验, -1e4)),
        torch.where(标签[:, -1:], 0.0, -1e4),
    ], 1), 1)
    权重 = torch.exp(热度权重 * (目标[:, :-1] * 先验).sum(1))
    权重 = 权重 / 权重.mean()
    n = len(样本)
    调度 = torch.optim.lr_scheduler.CosineAnnealingLR(优化器, 轮数 * math.ceil(n / 128))
    生成器 = torch.Generator().manual_seed(种子)
    for 轮 in range(轮数):
        总 = 0.0
        for 批 in torch.randperm(n, generator=生成器).split(128):
            对数概率 = torch.log_softmax(打分(模型, 特征[批], 空特征[批], 有效[批]), 1)
            交叉熵 = -(目标[批] * 对数概率.masked_fill(目标[批] == 0, 0)).sum(1)
            损失 = (交叉熵 * 权重[批]).mean()
            优化器.zero_grad()
            损失.backward()
            优化器.step()
            调度.step()
            总 += float(损失) * len(批)
        if 轮 % 5 == 4 or 轮 == 轮数 - 1:
            print(f"排序器第 {轮 + 1} 轮，损失 {总 / n:.4f}", flush=True)
    return 模型


def 评估(模型: 排序器, 样本: list, 文档: list[dict], 名字: str, 打印: bool = False) -> None:
    if not 样本:
        return
    特征, 空特征, 有效, 标签 = _张量(样本)
    with torch.no_grad():
        概率 = torch.softmax(打分(模型, 特征, 空特征, 有效), 1)
    分类 = collections.defaultdict(lambda: [0, 0, 0, 0.0])
    for i, (q, c, *_ ) in enumerate(样本):
        p = 概率[i, : len(c)]
        顺序 = torch.argsort(p, descending=True).tolist()
        正例 = 标签[i, : len(c)]
        类型 = q["type"]
        统计 = 分类[类型]
        统计[0] += 1
        if not 正例.any():
            统计[1] += float(p.max()) < 0.3
            continue
        位置 = next((j for j, k in enumerate(顺序) if 正例[k]), None)
        if 位置 is not None:
            统计[1] += 位置 == 0
            统计[2] += 位置 < 5
            统计[3] += 1 / (位置 + 1)
        if 打印:
            标记 = "✓" if 位置 == 0 else ("·" if 位置 is not None and 位置 < 5 else "✗")
            print(f"{标记} {q['q'][:28]:<28} → " + " / ".join(文档[c[k]]["display"][:22] for k in 顺序[:3]))
    行 = []
    for 类型, (n, 第一, 前五, 倒数) in sorted(分类.items()):
        if 类型 in ("neg", "tag"):
            行.append(f"{类型} 低把握 {第一 / n:.2f}")
        else:
            行.append(f"{类型} R@1 {第一 / n:.2f} R@5 {前五 / n:.2f}")
    print(f"{名字}（{len(样本)}）：" + "，".join(行), flush=True)


# MARK: - 导出

def _对齐(n: int) -> int:
    return (n + 15) // 16 * 16


def 打包(路径: Path, 文档: list[dict], 计算: 特征计算, 排序器数据: dict) -> str:
    索引 = 计算.索引
    数量 = collections.Counter(d["kind"] for d in 文档)
    编号 = np.array([int(d["key"][1:]) for d in 文档], dtype="<u4")
    先验 = np.array([d["prior"] for d in 文档], dtype="<f4")
    系列 = np.array([d.get("series", 0) for d in 文档 if d["kind"] == "v"], dtype="<u4")
    所属作品 = np.array([d.get("parent", 0) for d in 文档 if d["kind"] == "c"], dtype="<u4")
    名称字节 = [n.encode("utf-8") for n in 索引.名称]
    名称偏移 = np.zeros(len(名称字节) + 1, dtype="<u4")
    名称偏移[1:] = np.cumsum([len(b) for b in 名称字节])

    段 = [
        ("ranker", json.dumps(排序器数据).encode()),
        ("latinFold", json.dumps(名称.变音映射, ensure_ascii=False).encode()),
        ("docs/ids", 编号.tobytes()),
        ("docs/priors", 先验.tobytes()),
        ("docs/series", 系列.tobytes()),
        ("docs/parents", 所属作品.tobytes()),
        ("names/strings", b"".join(名称字节)),
        ("names/offsets", 名称偏移.tobytes()),
        ("names/docs", 索引.所属.astype("<u4").tobytes()),
        ("names/weights", 索引.名称权重.astype("<f4").tobytes()),
        ("names/docStarts", 索引.文档名称起点.astype("<u4").tobytes()),
        ("grams/keys", 索引.键.astype("<u8").tobytes()),
        ("grams/starts", 索引.起点.astype("<u4").tobytes()),
        ("grams/postings", 索引.倒排.astype("<u4").tobytes()),
        ("grams/idf", 索引.idf.astype("<f4").tobytes()),
    ]
    摘要 = hashlib.sha256()
    for 名, 数据 in 段:
        摘要.update(名.encode())
        摘要.update(数据)
    头 = {
        "formatVersion": 格式版本,
        "createdAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "modelIdentifier": f"{time.strftime('%Y%m%d')}-{摘要.hexdigest()[:12]}",
        "visualNovelCount": 数量["v"],
        "characterCount": 数量["c"],
        "producerCount": 数量["p"],
        "staffCount": 数量["s"],
        "nameCount": len(索引.名称),
        "gramCount": int(len(索引.键)),
        "maxIDF": 索引.最大idf,
        "nameCandidateCount": 名称候选数,
        "coverageCandidateCount": 覆盖候选数,
        "queryUnigramMaxHan": 名称.查询单字最多汉字数,
    }

    def 排布(头长度: int) -> dict:
        位置 = _对齐(12 + 头长度)
        表 = {}
        for 名, 数据 in 段:
            表[名] = {"offset": 位置, "length": len(数据)}
            位置 = _对齐(位置 + len(数据))
        return 表

    头长度 = 0
    while True:
        头["sections"] = 排布(头长度)
        编码头 = json.dumps(头, ensure_ascii=False, separators=(",", ":")).encode()
        if len(编码头) <= 头长度:
            编码头 = 编码头.ljust(头长度, b" ")
            break
        头长度 = _对齐(len(编码头) + 64)
    assert 12 + 头长度 <= 65536
    with open(路径, "wb") as 文件:
        文件.write(b"PVSS" + struct.pack("<II", 格式版本, 头长度) + 编码头)
        for 名, 数据 in 段:
            文件.write(b"\0" * (头["sections"][名]["offset"] - 文件.tell()))
            文件.write(数据)
    print(f"已写入 {路径}（{路径.stat().st_size / 1e6:.1f} MB），标识 {头['modelIdentifier']}")
    return 头["modelIdentifier"]


# MARK: - 入口

def 构建(导出目录: Path, 数据目录: Path, 工作目录: Path, 人工评估路径: Path, 种子: int = 20261008):
    文档 = 构建文档(导出目录, 数据目录)
    计算 = 特征计算(文档)
    查找 = 名称查找(文档)
    print(f"名称 {len(计算.索引.名称)}，片段 {len(计算.索引.键)}", flush=True)

    训练查询, 评估查询 = 生成查询(文档, 数据目录, 种子)
    训练样本 = 准备样本(训练查询, 计算, 查找, "训练样本")
    评估样本 = 准备样本(评估查询, 计算, 查找)
    文档下标 = {d["key"]: i for i, d in enumerate(文档)}
    人工 = []
    for 项 in json.loads(人工评估路径.read_text(encoding="utf-8")):
        目标 = {文档下标[k] for k in 项["targets"] if k in 文档下标}
        if 目标:
            人工.append({"q": 项["query"], "rel": "manual", "type": "人工-" + 项["type"], "src": -1, "kind": "", "pos": 目标})
    人工样本 = []
    for q in 人工:
        规范, 候选, 特征, 空特征 = 计算.计算(q["q"])
        if not 候选:
            人工样本.append((q, [0], np.zeros((1, len(特征名)), np.float32), np.zeros(len(空特征名), np.float32), np.array([False, False])))
            continue
        标签 = np.array([d in q["pos"] for d in 候选] + [False], dtype=bool)
        人工样本.append((q, 候选, 特征, 空特征, 标签))

    模型 = 训练排序器(训练样本)
    评估(模型, 评估样本, 文档, "合成评估")
    评估(模型, 人工样本, 文档, "人工评估", 打印=True)
    数据 = 模型.导出()
    (工作目录 / "fuzzy-ranker.json").write_text(json.dumps(数据), encoding="utf-8")
    return 打包(工作目录 / 文件名, 文档, 计算, 数据)
