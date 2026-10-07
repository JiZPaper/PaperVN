"""名称模糊匹配。App 里的 `智能搜索名称索引.swift` 与这里逐条对应。

规范化：NFKC → 小写 → 去掉拉丁字母变音（映射表随模型下发）→ 片假名转平假名、去掉长音符
→ 只保留字母和数字 → 折叠罗马字长音（oh、ou、oo、uu、aa、ii、ee）。

相似度：规范化后的双字片段集合，按 IDF 加权：
- 查询覆盖率 P = 重合权重 / 查询权重；
- 名称覆盖率 R = 重合权重 / 名称权重；
- F = 2 × 重合权重 / (查询权重 + 名称权重)。
查询里有、索引里没有的片段按最大 IDF 计入查询权重。
"""

from __future__ import annotations

import math
import re
import unicodedata

import numpy as np


def _生成变音映射() -> dict[str, str]:
    # ς：Python 的 lower() 会按词尾规则生成，Swift 的 lowercased() 不会，统一折叠成 σ。
    映射 = {"ß": "ss", "æ": "ae", "ø": "o", "đ": "d", "ł": "l", "œ": "oe", "þ": "th", "ı": "i", "ς": "σ"}
    for 码 in range(0xC0, 0x250):
        字 = chr(码).lower()
        if len(字) != 1 or 字 in 映射:
            continue
        分解 = unicodedata.normalize("NFD", 字)
        if len(分解) > 1 and "a" <= 分解[0] <= "z" and all(unicodedata.category(c) == "Mn" for c in 分解[1:]):
            映射[字] = 分解[0]
    return 映射


变音映射 = _生成变音映射()
_变音转换 = str.maketrans(变音映射)
_长音替换 = [("ou", "o"), ("oo", "o"), ("uu", "u"), ("aa", "a"), ("ii", "i"), ("ee", "e")]
_oh = re.compile(r"oh(?![aeiou])")
未知片段 = (1 << 21) - 1


def 规范化(文本: str) -> str:
    文本 = unicodedata.normalize("NFKC", 文本).lower().translate(_变音转换)
    结果 = []
    for 字 in 文本:
        码 = ord(字)
        if 0x30A1 <= 码 <= 0x30F6:
            字 = chr(码 - 0x60)
        elif 字 == "ー":
            continue
        if unicodedata.category(字)[0] in ("L", "N"):
            结果.append(字)
    文本 = _oh.sub("o", "".join(结果))
    for 旧, 新 in _长音替换:
        文本 = 文本.replace(旧, 新)
    return 文本


def 含汉字(文本: str) -> bool:
    return any(0x3400 <= ord(c) <= 0x9FFF for c in 文本)


def 含假名(文本: str) -> bool:
    return any(0x3040 <= ord(c) <= 0x30FF for c in 文本)


def 含中日文(文本: str) -> bool:
    """含汉字、假名或韩文。"""
    return any(
        0x3040 <= ord(c) <= 0x30FF or 0x3400 <= ord(c) <= 0x9FFF or 0xAC00 <= ord(c) <= 0xD7A3
        for c in 文本
    )


def _是汉字(字: str) -> bool:
    return 0x3400 <= ord(字) <= 0x9FFF


查询单字最多汉字数 = 8


def 片段键(文本: str, 含单字: bool = True) -> list[int]:
    """去重后的双字片段；只有一个字时用单字片段。

    汉字另外加上单字片段：中文名通常只有三四个字，错一个字或调换两个字就会丢掉大半双字片段
    （“命运之石门”和“命运石之门”只共享“命运”），单字片段让这类输错仍能匹配上。
    名称一律带单字片段；查询只在汉字不多时带（见 `查询含单字`），长句描述带上单字片段
    只会和大量名字零散地对上几个字，让名称匹配的信号变成噪声。
    """
    if not 文本:
        return []
    if len(文本) == 1:
        return [(ord(文本) << 21) | 未知片段]
    键 = [(ord(文本[i]) << 21) | ord(文本[i + 1]) for i in range(len(文本) - 1)]
    if 含单字:
        键 += [(ord(字) << 21) | 未知片段 for 字 in 文本 if _是汉字(字)]
    return list(dict.fromkeys(键))


def 查询含单字(规范查询: str) -> bool:
    return sum(_是汉字(字) for 字 in 规范查询) <= 查询单字最多汉字数


class 名称索引:
    def __init__(self, 文档名称: list[list[str]]):
        名称, 所属 = [], []
        self.文档名称起点 = [0]
        for 文档, 变体 in enumerate(文档名称):
            for 名 in dict.fromkeys(规范化(v) for v in 变体):
                if 名:
                    名称.append(名)
                    所属.append(文档)
            self.文档名称起点.append(len(名称))
        self.名称 = 名称
        self.所属 = np.array(所属, dtype=np.int32)
        self.文档名称起点 = np.array(self.文档名称起点, dtype=np.int64)

        条目 = []
        for i, 名 in enumerate(名称):
            for 键 in 片段键(名):
                条目.append((键, i))
        条目.sort()
        键数组 = np.array([k for k, _ in 条目], dtype=np.uint64)
        self.倒排 = np.array([v for _, v in 条目], dtype=np.uint32)
        self.键, 起点 = np.unique(键数组, return_index=True)
        self.起点 = np.append(起点, len(键数组)).astype(np.int64)
        数量 = np.diff(self.起点)
        self.名称总数 = len(名称)
        self.idf = np.log1p(self.名称总数 / 数量).astype(np.float32)
        self.最大idf = float(math.log1p(self.名称总数))
        self.名称权重 = np.zeros(len(名称), dtype=np.float32)
        for k in range(len(self.键)):
            self.名称权重[self.倒排[self.起点[k]: self.起点[k + 1]]] += self.idf[k]

    def 查询片段(self, 规范查询: str) -> tuple[list[tuple[int, float]], float]:
        片段 = []
        查询权重 = 0.0
        for 键 in 片段键(规范查询, 查询含单字(规范查询)):
            位置 = int(np.searchsorted(self.键, np.uint64(键)))
            if 位置 < len(self.键) and int(self.键[位置]) == 键:
                片段.append((位置, float(self.idf[位置])))
                查询权重 += float(self.idf[位置])
            else:
                查询权重 += self.最大idf
        return 片段, 查询权重

    def 重合(self, 片段: list[tuple[int, float]]) -> np.ndarray:
        重合 = np.zeros(self.名称总数, dtype=np.float32)
        for 位置, 权重 in 片段:
            重合[self.倒排[self.起点[位置]: self.起点[位置 + 1]]] += 权重
        return 重合

    def 文档特征(self, 规范查询: str, 重合: np.ndarray, 查询权重: float, 文档: int) -> tuple[float, float, float, float, float, float]:
        """返回（F，P，R，完全一致，前缀，包含），取该文档 F 最高的名称。"""
        起, 止 = self.文档名称起点[文档], self.文档名称起点[文档 + 1]
        if 止 <= 起 or 查询权重 <= 0:
            return (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        o = 重合[起:止]
        f = 2 * o / (查询权重 + self.名称权重[起:止])
        i = int(np.argmax(f))
        名 = self.名称[起 + i]
        完全 = float(any(self.名称[j] == 规范查询 for j in range(起, 止)))
        前缀 = float(len(规范查询) >= 2 and any(self.名称[j].startswith(规范查询) for j in range(起, 止)))
        包含 = float(any(
            (len(规范查询) >= 2 and 规范查询 in self.名称[j]) or (len(self.名称[j]) >= 3 and self.名称[j] in 规范查询)
            for j in range(起, 止)
        ))
        return (
            float(f[i]),
            float(o[i] / 查询权重),
            float(o[i] / max(self.名称权重[起 + i], 1e-6)),
            完全, 前缀, 包含,
        )

    def 候选文档(self, 重合: np.ndarray, 查询权重: float, 数量: int) -> list[int]:
        命中 = np.nonzero(重合)[0]
        if len(命中) == 0:
            return []
        f = 2 * 重合[命中] / (查询权重 + self.名称权重[命中])
        顺序 = np.argsort(-f, kind="stable")
        结果, 已有 = [], set()
        for k in 顺序:
            文档 = int(self.所属[命中[k]])
            if 文档 not in 已有:
                已有.add(文档)
                结果.append(文档)
                if len(结果) >= 数量:
                    break
        return 结果
