"""从 VNDB 数据库导出构建智能搜索的文档与合成查询。

只依赖标准库。输出：
- corpus.jsonl：每行一个文档（作品或角色），顺序即索引顺序；
- train.jsonl / eval.jsonl：合成查询，`pos` 是所有满足查询条件的文档下标。

合成查询模拟用户在搜索框里输入的模糊描述：标签和特征组合、简介片段、台词、标题和名字。
标签和特征组合查询的正例是所有同时具有这些标签或特征的条目，而不只是采样来源，
这样训练时不会把同样符合描述的其他作品当成负例。
"""

from __future__ import annotations

import bisect
import collections
import json
import math
import random
import re
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

语言 = ["zh-Hans", "zh-Hant", "ja", "en", "ko"]
语言权重 = [0.40, 0.10, 0.20, 0.20, 0.10]

作品最少票数 = 1
角色作品最少票数 = 10
配角作品最少票数 = 300
正例上限 = 300

_转义 = {"\\": "\\", "n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v"}
_转义模式 = re.compile(r"\\([\\ntrbfv])")


def 解码字段(值: str) -> str | None:
    if 值 == "\\N":
        return None
    if "\\" not in 值:
        return 值
    return _转义模式.sub(lambda m: _转义[m.group(1)], 值)


def 读取表(目录: Path, 表名: str, 列: list[str]):
    """逐行读取 PostgreSQL COPY 格式的表，只返回需要的列。"""
    表头 = (目录 / f"{表名}.header").read_text(encoding="utf-8").strip().split("\t")
    下标 = [表头.index(名) for 名 in 列]
    with open(目录 / 表名, encoding="utf-8") as 文件:
        for 行 in 文件:
            字段 = 行.rstrip("\n").split("\t")
            yield tuple(解码字段(字段[i]) for i in 下标)


def 编号(值: str) -> int:
    return int(值[1:])


# MARK: - 文本清理

_剧透 = re.compile(r"\[spoiler\].*?\[/spoiler\]", re.S | re.I)
_链接 = re.compile(r"\[url=[^\]]*\](.*?)\[/url\]", re.S | re.I)
_格式 = re.compile(r"\[/?(?:b|i|u|s|quote|code|raw|url)\]", re.I)
_来源 = re.compile(r"\[(?:from|source|translated from|edited from)\b[^\]]*\]", re.I)
_空白 = re.compile(r"[ \t　]+")


def 清理简介(文本: str | None) -> str:
    if not 文本:
        return ""
    文本 = _剧透.sub(" ", 文本)
    文本 = _链接.sub(r"\1", 文本)
    文本 = _格式.sub("", 文本)
    文本 = _来源.sub(" ", 文本)
    文本 = _空白.sub(" ", 文本)
    文本 = re.sub(r"\s*\n\s*", "\n", 文本)
    return 文本.strip()


def 规范化名称(文本: str) -> str:
    """比较标题和名字时使用：忽略大小写、空白和标点。"""
    文本 = unicodedata.normalize("NFKC", 文本).casefold()
    return "".join(
        字 for 字 in 文本
        if unicodedata.category(字)[0] in ("L", "N")
    )


def 含假名(文本: str) -> bool:
    return any("぀" <= 字 <= "ヿ" for 字 in 文本)


def 含汉字(文本: str) -> bool:
    return any("一" <= 字 <= "鿿" for 字 in 文本)


_英文句子 = re.compile(r"(?<=[.!?])\s+(?=[A-Z\"'(])")
_中日句子 = re.compile(r"(?<=[。！？!?])")


def 分句(文本: str) -> list[str]:
    结果 = []
    for 段 in 文本.split("\n"):
        段 = 段.strip()
        if not 段:
            continue
        if 含假名(段) or 含汉字(段):
            部分 = _中日句子.split(段)
        else:
            部分 = _英文句子.split(段)
        结果.extend(句.strip() for 句 in 部分 if len(句.strip()) >= 6)
    return 结果


# MARK: - 译名

def 读取译名表(路径: Path, 前缀: str = "") -> dict[str, dict[str, str]]:
    数据 = json.loads(路径.read_text(encoding="utf-8"))["strings"]
    结果: dict[str, dict[str, str]] = {}
    for 键, 值 in 数据.items():
        名称 = 键[len(前缀):] if 前缀 and 键.startswith(前缀) else 键
        本地化 = 值.get("localizations", {})
        译名 = {"en": 名称}
        for 语种 in 语言:
            单元 = 本地化.get(语种, {}).get("stringUnit")
            if 单元 and 单元.get("value", "").strip():
                译名[语种] = 单元["value"].strip()
        结果[名称] = 译名
    return 结果


# 发色、瞳色和发长在查询里通常连着部位一起说（“银发”“红瞳”），单独的颜色译名不够自然。
_发色 = {
    "Black": ("黑发", "黑髮", "黒髪", "black hair", "흑발"),
    "Blond": ("金发", "金髮", "金髪", "blonde hair", "금발"),
    "Brown": ("棕发|茶发", "棕髮|茶髮", "茶髪", "brown hair", "갈색 머리"),
    "Blue": ("蓝发", "藍髮", "青い髪", "blue hair", "파란 머리"),
    "Pink": ("粉发", "粉髮", "ピンク髪", "pink hair", "분홍 머리"),
    "Violet": ("紫发", "紫髮", "紫髪", "purple hair", "보라색 머리"),
    "Red": ("红发", "紅髮", "赤髪", "red hair", "빨간 머리"),
    "White": ("白发", "白髮", "白い髪", "white hair", "백발"),
    "Green": ("绿发", "綠髮", "緑髪", "green hair", "초록 머리"),
    "Multicolored": ("挑染|渐变发色", "挑染|漸層髮色", "メッシュ", "multicolored hair", "투톤 머리"),
    "Cyan": ("水蓝色头发|青发", "水藍色頭髮", "水色の髪", "cyan hair", "하늘색 머리"),
    "Teal": ("青绿色头发", "青綠色頭髮", "ティール色の髪", "teal hair", "청록색 머리"),
    "Grey": ("银发|灰发", "銀髮|灰髮", "銀髪", "silver hair|grey hair", "은발"),
    "Dyed": ("染发", "染髮", "染めた髪", "dyed hair", "염색 머리"),
    "Orange": ("橙发", "橙髮", "オレンジ髪", "orange hair", "주황색 머리"),
}
_瞳色 = {
    "Brown": ("棕色眼睛|棕瞳", "棕色眼睛", "茶色の瞳", "brown eyes", "갈색 눈"),
    "Amber": ("金瞳|金色眼睛", "金瞳|金色眼睛", "金色の瞳", "golden eyes|amber eyes", "금안"),
    "Black": ("黑瞳|黑色眼睛", "黑瞳", "黒い瞳", "black eyes", "검은 눈"),
    "Blue": ("蓝瞳|蓝色眼睛|碧眼", "藍瞳|碧眼", "青い瞳|碧眼", "blue eyes", "파란 눈"),
    "Grey": ("灰瞳|银瞳", "灰瞳|銀瞳", "銀色の瞳", "grey eyes|silver eyes", "회색 눈"),
    "Green": ("绿瞳|绿色眼睛", "綠瞳", "緑の瞳", "green eyes", "녹색 눈"),
    "Hazel": ("淡褐色眼睛", "淡褐色眼睛", "ヘーゼルの瞳", "hazel eyes", "담갈색 눈"),
    "Violet": ("紫瞳|紫色眼睛", "紫瞳", "紫の瞳", "purple eyes", "보라색 눈"),
    "Red": ("红瞳|红色眼睛", "紅瞳", "赤い瞳|赤目", "red eyes", "붉은 눈"),
    "White": ("白瞳", "白瞳", "白い瞳", "white eyes", "흰 눈"),
    "Pink": ("粉瞳|粉色眼睛", "粉瞳", "ピンクの瞳", "pink eyes", "분홍색 눈"),
    "Heterochromia": ("异色瞳", "異色瞳", "オッドアイ", "heterochromia", "오드아이"),
}
_发长 = {
    "Long": ("长发", "長髮", "ロングヘア", "long hair", "장발"),
    "Short": ("短发", "短髮", "ショートヘア", "short hair", "단발"),
    "Shoulder-length": ("及肩发|中长发", "及肩髮", "セミロング", "shoulder-length hair", "어깨 길이 머리"),
    "Waist Length+": ("及腰长发", "及腰長髮", "腰までの長い髪", "waist-length hair", "허리까지 오는 머리"),
    "Bald": ("光头", "光頭", "スキンヘッド", "bald", "대머리"),
}
_部位表 = {"Hair Color": _发色, "Eye Color": _瞳色, "Length": _发长, "Long": _发长}

_性别词 = {
    "f": {
        "zh-Hans": ["女孩", "少女", "女生", "女角色", "妹子"],
        "zh-Hant": ["女孩", "少女", "女生", "女角色"],
        "ja": ["女の子", "少女", "女性キャラ"],
        "en": ["girl", "female character", "heroine"],
        "ko": ["여자아이", "소녀", "여캐"],
    },
    "m": {
        "zh-Hans": ["男生", "少年", "男角色"],
        "zh-Hant": ["男生", "少年", "男角色"],
        "ja": ["男の子", "少年", "男性キャラ"],
        "en": ["boy", "guy", "male character"],
        "ko": ["남자아이", "소년", "남캐"],
    },
    "": {
        "zh-Hans": ["角色"],
        "zh-Hant": ["角色"],
        "ja": ["キャラ"],
        "en": ["character"],
        "ko": ["캐릭터"],
    },
}

_标签模板 = {
    "zh-Hans": ["{T}的游戏", "{T}的galgame", "{T}的视觉小说", "想找一部{T}的作品", "{T}",
               "有{T}的gal", "{T}题材的游戏", "一个{T}的故事", "{T}，求推荐"],
    "zh-Hant": ["{T}的遊戲", "{T}的galgame", "{T}的視覺小說", "想找一部{T}的作品", "{T}"],
    "ja": ["{T}なゲーム", "{T}のノベルゲーム", "{T}系のギャルゲー", "{T}", "{T}の作品"],
    "en": ["{T} visual novel", "vn with {T}", "{T}", "a {T} game", "{T} vn"],
    "ko": ["{T} 게임", "{T} 비주얼노벨", "{T} 미연시", "{T}"],
}
_标签连接 = {
    "zh-Hans": ["、", "，", " ", "+"],
    "zh-Hant": ["、", "，", " "],
    "ja": ["、", "・", " "],
    "en": [", ", " ", " and "],
    "ko": [", ", " "],
}
_会社模板 = {
    "zh-Hans": ["{D}的{T}游戏", "{D} {T}", "{D}出的{T}作品"],
    "zh-Hant": ["{D}的{T}遊戲", "{D} {T}"],
    "ja": ["{D}の{T}ゲーム", "{D} {T}"],
    "en": ["{D} {T} game", "{T} vn by {D}"],
    "ko": ["{D}의 {T} 게임", "{D} {T}"],
}
_角色模板 = {
    "zh-Hans": ["{T}的{G}", "一个{T}的{G}", "{T}{G}", "找一个{T}的角色", "{T}"],
    "zh-Hant": ["{T}的{G}", "一個{T}的{G}", "{T}{G}", "{T}"],
    "ja": ["{T}の{G}", "{T}な{G}", "{T}"],
    "en": ["{G} with {T}", "{T} {G}", "{T}"],
    "ko": ["{T} {G}", "{T}"],
}
_角色作品模板 = {
    "zh-Hans": ["{V}里{T}的{G}", "{V}的{T}{G}", "{V} {T}", "{V}里那个{T}的角色"],
    "zh-Hant": ["{V}裡{T}的{G}", "{V}的{T}{G}", "{V} {T}"],
    "ja": ["{V}に出てくる{T}の{G}", "{V}の{T}キャラ", "{V} {T}"],
    "en": ["{T} {G} from {V}", "{V} {G} with {T}", "{V} {T}"],
    "ko": ["{V}에 나오는 {T} {G}", "{V} {T} 캐릭터", "{V} {T}"],
}
_特征连接 = {
    "zh-Hans": ["、", "，", "", " "],
    "zh-Hant": ["、", "，", ""],
    "ja": ["、", " "],
    "en": [", ", " "],
    "ko": [", ", " "],
}
_简介前缀 = {
    "zh-Hans": ["", "", "", "好像是", "记得是", "有一个游戏，", "剧情大概是", "我记得剧情是"],
    "en": ["", "", "", "game where ", "vn where ", "i remember a vn where "],
    "ja": ["", "", "たしか", "あらすじは"],
}
_角色名模板 = {
    "zh-Hans": ["{V}的{N}", "{V}里的{N}", "{N} {V}"],
    "ja": ["{V}の{N}", "{N} {V}"],
    "en": ["{N} from {V}", "{N} {V}"],
}

_键盘邻键 = {
    "q": "wa", "w": "qes", "e": "wrd", "r": "etf", "t": "ryg", "y": "tuh", "u": "yij", "i": "uok",
    "o": "ipl", "p": "o", "a": "qsz", "s": "adwx", "d": "sfec", "f": "dgrv", "g": "fhtb", "h": "gjyn",
    "j": "hkum", "k": "jli", "l": "ko", "z": "xa", "x": "zcs", "c": "xvd", "v": "cbf", "b": "vng",
    "n": "bmh", "m": "nj",
}
_常用汉字 = (
    "的一是不了人我在有他这中大来上国个到说们为子和你地出道也时年得就那要下以生会自着去之过家学对可"
    "她里后小么心多天而能好都然没日于起还发成事只作当想看文无开手十用主行方又如前所本见经头面公同三"
    "已老从动两长知民样现分将外但身些与高意进把法此实回二理美点月明其种声全工己话儿者向情部正名定女"
    "问力机给等几很业最间新什打便位因重被走电四第门相次东政海口使教西再平真听世气信北少关并内加化由"
)
_泛化查询 = [
    "你好", "今天天气怎么样", "推荐", "游戏", "好玩的游戏", "随便看看", "最新", "排行榜", "免费", "下载",
    "怎么用", "帮助", "设置", "登录", "测试", "哈哈哈", "谢谢", "晚安", "明天", "附近的餐厅",
    "test", "hello", "what is this", "help", "download", "free", "new", "top", "asdf", "qwerty",
    "こんにちは", "おすすめ", "テスト", "ありがとう", "안녕하세요", "추천", "테스트", "감사합니다", "123", "0000",
]

# 特征分组在查询中出现的概率，越靠前越像用户会记住的外观特征。
_特征组权重 = {
    "Hair Color": 0.9, "Eye Color": 0.6, "Length": 0.35, "Long": 0.35,
    "Hairstyle": 0.5, "Personality": 0.5, "Role": 0.35, "Relationships": 0.35,
    "Careers": 0.3, "Clothes": 0.3, "Body": 0.25, "Items": 0.2,
    "Engages in": 0.25, "Subject of": 0.2, "Eyes": 0.3, "Hair": 0.3,
}


def _选(随机: random.Random, 值: str) -> str:
    return 随机.choice(值.split("|"))


def _随机语言(随机: random.Random) -> str:
    return 随机.choices(语言, weights=语言权重)[0]


# MARK: - 数据结构

@dataclass
class 标签:
    名称: str
    类别: str
    父级: list[str] = field(default_factory=list)


@dataclass
class 特征:
    名称: str
    父名: str
    根名: str
    性: bool


@dataclass
class 文档:
    键: str
    类型: str
    文本: str
    先验: float
    显示名: str
    名称变体: list[str]


# MARK: - 构建

class 语料构建器:
    def __init__(self, 导出目录: Path, 译文目录: Path | None, 应用目录: Path, 种子: int = 20261006):
        self.db = 导出目录 / "db"
        self.译文目录 = 译文目录
        self.标签译名 = 读取译名表(应用目录 / "VNDBTags.xcstrings")
        self.特征译名 = 读取译名表(应用目录 / "VNDBTraits.xcstrings", 前缀="trait.")
        self.种子 = 种子

    # MARK: 读取

    def 读取全部(self):
        self._读取作品()
        self._读取会社()
        self._读取标签()
        self._读取角色()
        self._读取台词()
        self._读取中文简介()

    def _读取作品(self):
        self.作品 = {}
        for 编, 原语言, 票数, 别名, 简介, 状态 in 读取表(
            self.db, "vn", ["id", "olang", "c_votecount", "alias", "description", "devstatus"]
        ):
            self.作品[编号(编)] = {
                "原语言": 原语言,
                "票数": int(票数 or 0),
                "别名": [a.strip() for a in (别名 or "").split("\n") if a.strip()],
                "简介": 清理简介(简介),
                "状态": int(状态 or 0),
                "标题": [],
            }
        for 编, 语种, 官方, 标题, 拉丁 in 读取表(
            self.db, "vn_titles", ["id", "lang", "official", "title", "latin"]
        ):
            项 = self.作品.get(编号(编))
            if 项 is not None:
                项["标题"].append((语种, 官方 == "t", 标题, 拉丁))

    def _读取会社(self):
        会社名 = {}
        for 编, 名, 拉丁 in 读取表(self.db, "producers", ["id", "name", "latin"]):
            会社名[编] = (名, 拉丁)
        发行年 = {}
        for 编, 日期, 官方 in 读取表(self.db, "releases", ["id", "released", "official"]):
            日期 = int(日期 or 0)
            if 官方 == "t" and 19000101 <= 日期 < 21000000:
                发行年[编] = 日期 // 10000
        发行作品 = collections.defaultdict(list)
        for 发行, 作品 in 读取表(self.db, "releases_vn", ["id", "vid"]):
            发行作品[发行].append(编号(作品))
        开发 = collections.defaultdict(collections.Counter)
        for 发行, 会社, 是开发 in 读取表(self.db, "releases_producers", ["id", "pid", "developer"]):
            if 是开发 != "t" or 会社 not in 会社名:
                continue
            for 作品 in 发行作品.get(发行, []):
                开发[作品][会社] += 1
        for 发行, 年 in 发行年.items():
            for 作品 in 发行作品.get(发行, []):
                项 = self.作品.get(作品)
                if 项 is not None:
                    项["年份"] = min(项.get("年份", 9999), 年)
        for 作品, 计数 in 开发.items():
            项 = self.作品.get(作品)
            if 项 is None:
                continue
            名称 = []
            for 会社, _ in 计数.most_common(3):
                名, 拉丁 = 会社名[会社]
                名称.append((名, 拉丁))
            项["开发"] = 名称

    def _读取标签(self):
        self.标签 = {}
        for 编, 类别, 名称 in 读取表(self.db, "tags", ["id", "cat", "name"]):
            self.标签[编] = 标签(名称=名称, 类别=类别)
        for 编, 父 in 读取表(self.db, "tags_parents", ["id", "parent"]):
            if 编 in self.标签:
                self.标签[编].父级.append(父)
        汇总 = collections.defaultdict(lambda: [0.0, 0, 0.0, 0])
        for 标, 作品, 票, 剧透, 忽略, 谎言 in 读取表(
            self.db, "tags_vn", ["tag", "vid", "vote", "spoiler", "ignore", "lie"]
        ):
            if 忽略 == "t" or 谎言 == "t":
                continue
            项 = 汇总[(编号(作品), 标)]
            项[0] += int(票)
            项[1] += 1
            if 剧透 is not None:
                项[2] += int(剧透)
                项[3] += 1
        self.作品标签 = collections.defaultdict(dict)
        for (作品, 标), (总分, 票数, 剧透和, 剧透数) in 汇总.items():
            分 = 总分 / 票数
            剧透 = 剧透和 / 剧透数 if 剧透数 else 0
            if 分 > 0 and 剧透 < 0.7 and 标 in self.标签:
                self.作品标签[作品][标] = 分

    def _读取角色(self):
        self.特征 = {}
        名称表 = {}
        for 编, 名称, 性 in 读取表(self.db, "traits", ["id", "name", "sexual"]):
            名称表[编] = 名称
            self.特征[编] = 特征(名称=名称, 父名="", 根名="", 性=性 == "t")
        父级 = {}
        for 编, 父 in 读取表(self.db, "traits_parents", ["id", "parent"]):
            父级.setdefault(编, 父)
        for 编, 项 in self.特征.items():
            父 = 父级.get(编)
            项.父名 = 名称表.get(父, "") if 父 else ""
            根 = 编
            while 根 in 父级:
                根 = 父级[根]
            项.根名 = 名称表.get(根, "")
            if 项.根名 in ("Engages in (Sexual)", "Subject of (Sexual)"):
                项.性 = True

        self.角色 = {}
        for 编, 图片, 性别, 简介 in 读取表(self.db, "chars", ["id", "image", "sex", "description"]):
            self.角色[编号(编)] = {
                "图片": 图片 is not None,
                "性别": 性别 or "",
                "简介": 清理简介(简介),
                "名称": [],
                "别名": [],
                "特征": [],
                "作品": [],
            }
        for 编, 语种, 名, 拉丁 in 读取表(self.db, "chars_names", ["id", "lang", "name", "latin"]):
            项 = self.角色.get(编号(编))
            if 项 is not None:
                项["名称"].append((语种, 名, 拉丁))
        for 编, 剧透, 名, 拉丁 in 读取表(self.db, "chars_alias", ["id", "spoil", "name", "latin"]):
            项 = self.角色.get(编号(编))
            if 项 is not None and int(剧透 or 0) == 0:
                项["别名"].append((名, 拉丁))
        for 编, 特, 剧透, 谎言 in 读取表(self.db, "chars_traits", ["id", "tid", "spoil", "lie"]):
            项 = self.角色.get(编号(编))
            if 项 is None or int(剧透 or 0) > 0 or 谎言 == "t":
                continue
            特项 = self.特征.get(特)
            if 特项 is not None and not 特项.性:
                项["特征"].append(特)
        for 编, 作品, 角色定位, 剧透 in 读取表(self.db, "chars_vns", ["id", "vid", "role", "spoil"]):
            项 = self.角色.get(编号(编))
            if 项 is not None and int(剧透 or 0) < 2:
                项["作品"].append((编号(作品), 角色定位))

    def _读取台词(self):
        self.台词 = []
        for 作品, 角色, 内容 in 读取表(self.db, "quotes", ["vid", "cid", "quote"]):
            if 内容 and len(内容.strip()) >= 8:
                self.台词.append((编号(作品), 编号(角色) if 角色 else None, 内容.strip()))

    def _读取中文简介(self):
        self.中文简介 = {}
        if not self.译文目录:
            return
        for 路径 in (self.译文目录 / "zh-Hans" / "visual-novels").glob("*/v*.json"):
            try:
                数据 = json.loads(路径.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            译文 = 清理简介(数据.get("translation"))
            if 译文:
                self.中文简介[编号(数据["id"])] = 译文

    # MARK: 文档

    def 标签名(self, 标: str, 语种: str) -> str:
        名称 = self.标签[标].名称
        return self.标签译名.get(名称, {}).get(语种, 名称)

    def 特征名(self, 特: str, 语种: str, 随机: random.Random | None = None) -> str:
        项 = self.特征[特]
        表 = _部位表.get(项.父名)
        if 表 and 项.名称 in 表:
            值 = 表[项.名称][语言.index(语种)]
            return _选(随机, 值) if 随机 else 值.split("|")[0]
        return self.特征译名.get(项.名称, {}).get(语种, 项.名称)

    def 作品标题(self, 作品: int) -> tuple[str, str | None, list[str]]:
        """返回（显示标题，原文标题，全部标题变体）。"""
        项 = self.作品[作品]
        主 = None
        for 语种, 官方, 标题, 拉丁 in 项["标题"]:
            if 语种 == 项["原语言"] and (主 is None or 官方):
                主 = (标题, 拉丁)
        if 主 is None and 项["标题"]:
            主 = (项["标题"][0][2], 项["标题"][0][3])
        显示 = (主[1] or 主[0]) if 主 else f"v{作品}"
        原文 = 主[0] if 主 else None
        变体 = []
        for _, _, 标题, 拉丁 in 项["标题"]:
            变体.append(标题)
            if 拉丁:
                变体.append(拉丁)
        变体.extend(项["别名"])
        return 显示, 原文, list(dict.fromkeys(v for v in 变体 if v))

    def 查询用作品名(self, 作品: int, 语种: str, 随机: random.Random) -> str:
        """按查询语言挑用户最可能记得的作品名：中文用户多记中文或原文标题，英语用户多记罗马字。"""
        项 = self.作品[作品]
        显示, 原文, 变体 = self.作品标题(作品)
        候选: list[str] = []
        if 语种 in ("zh-Hans", "zh-Hant"):
            候选 = [标题 for 语, _, 标题, _ in 项["标题"] if 语.startswith("zh")]
            if 原文 and 随机.random() < 0.5:
                候选.append(原文)
        elif 语种 in ("ja", "ko"):
            候选 = [标题 for 语, _, 标题, _ in 项["标题"] if 语 == 语种]
            if 原文:
                候选.append(原文)
        else:
            候选 = [拉丁 or 标题 for 语, _, 标题, 拉丁 in 项["标题"] if 语 == "en" or 拉丁]
        候选 += [别名 for 别名 in 项["别名"] if len(别名) <= 16]
        if not 候选 or 随机.random() < 0.15:
            候选 = [显示] + ([原文] if 原文 else [])
        return 随机.choice(候选)

    def 角色名称(self, 角色: int) -> tuple[str, str | None, list[str]]:
        项 = self.角色[角色]
        主 = None
        for 语种, 名, 拉丁 in 项["名称"]:
            if 主 is None or 语种 == "ja":
                主 = (名, 拉丁)
                if 语种 == "ja":
                    break
        显示 = (主[1] or 主[0]) if 主 else f"c{角色}"
        原文 = 主[0] if 主 else None
        变体 = []
        for _, 名, 拉丁 in 项["名称"]:
            变体.append(名)
            if 拉丁:
                变体.append(拉丁)
        for 名, 拉丁 in 项["别名"]:
            变体.append(名)
            if 拉丁:
                变体.append(拉丁)
        return 显示, 原文, list(dict.fromkeys(v for v in 变体 if v))

    def 选择条目(self):
        self.选中作品 = sorted(
            编 for 编, 项 in self.作品.items()
            if 项["票数"] >= 作品最少票数 and 项["状态"] != 2
        )
        选中集合 = set(self.选中作品)
        最高票 = max(项["票数"] for 项 in self.作品.values())
        self.作品先验 = {
            编: math.log1p(self.作品[编]["票数"]) / math.log1p(最高票)
            for 编 in self.选中作品
        }
        角色权重 = {"main": 1.0, "primary": 0.9, "side": 0.6, "appears": 0.4}
        self.选中角色 = []
        self.角色先验 = {}
        self.作品主要角色 = collections.defaultdict(list)
        for 编, 项 in sorted(self.角色.items()):
            链接 = [(作品, 定位) for 作品, 定位 in 项["作品"] if 作品 in 选中集合]
            if not 链接:
                continue
            入选 = any(
                (定位 in ("main", "primary") and self.作品[作品]["票数"] >= 角色作品最少票数)
                or (定位 == "side" and self.作品[作品]["票数"] >= 配角作品最少票数)
                for 作品, 定位 in 链接
            )
            if not 入选 or not (项["图片"] or len(项["特征"]) >= 3 or 项["简介"]):
                continue
            项["作品"] = sorted(链接, key=lambda x: -self.作品[x[0]]["票数"])
            self.选中角色.append(编)
            for 作品, 定位 in 链接:
                if 定位 in ("main", "primary"):
                    self.作品主要角色[作品].append(编)
            self.角色先验[编] = max(
                self.作品先验[作品] * 角色权重.get(定位, 0.4) for 作品, 定位 in 链接
            )

    def 构建文档(self) -> list[文档]:
        文档列表 = []
        for 编 in self.选中作品:
            文档列表.append(self._作品文档(编))
        for 编 in self.选中角色:
            文档列表.append(self._角色文档(编))
        self.文档下标 = {d.键: i for i, d in enumerate(文档列表)}
        return 文档列表

    def _作品文档(self, 编: int) -> 文档:
        项 = self.作品[编]
        显示, 原文, 变体 = self.作品标题(编)
        行 = [" / ".join(dict.fromkeys([显示] + ([原文] if 原文 else []) + 变体[:10]))]
        信息 = []
        if 项.get("开发"):
            信息.append("、".join(拉丁 or 名 for 名, 拉丁 in 项["开发"]))
        if 项.get("年份"):
            信息.append(str(项["年份"]))
        if 信息:
            行.append(" · ".join(信息))
        标签列表 = sorted(
            ((标, 分) for 标, 分 in self.作品标签.get(编, {}).items() if 分 >= 1.0),
            key=lambda x: -x[1],
        )[:20]
        if 标签列表:
            行.append("标签：" + "、".join(self.标签名(标, "zh-Hans") for 标, _ in 标签列表))
            行.append("Tags: " + ", ".join(self.标签名(标, "en") for 标, _ in 标签列表))
        角色名 = []
        for 角色 in self.作品主要角色.get(编, [])[:8]:
            显示名, 原名, _ = self.角色名称(角色)
            角色名.append(原名 or 显示名)
        if 角色名:
            行.append("角色：" + "、".join(角色名))
        if 编 in self.中文简介:
            行.append(self.中文简介[编][:1200])
        if 项["简介"]:
            行.append(项["简介"][:2000])
        return 文档(
            键=f"v{编}",
            类型="v",
            文本="\n".join(行),
            先验=self.作品先验[编],
            显示名=显示,
            名称变体=变体,
        )

    def _角色文档(self, 编: int) -> 文档:
        项 = self.角色[编]
        显示, 原文, 变体 = self.角色名称(编)
        行 = [" / ".join(dict.fromkeys([显示] + ([原文] if 原文 else []) + 变体[:8]))]
        作品名 = []
        for 作品, _ in 项["作品"][:3]:
            作品显示, 作品原文, _ = self.作品标题(作品)
            作品名.append(作品显示 if not 作品原文 or 作品原文 == 作品显示 else f"{作品显示}（{作品原文}）")
        行.append("出自：" + " / ".join(作品名))
        性别 = {"f": "女性 female", "m": "男性 male"}.get(项["性别"])
        if 性别:
            行.append(性别)
        特征列表 = sorted(
            项["特征"], key=lambda 特: -_特征组权重.get(self.特征[特].父名, _特征组权重.get(self.特征[特].根名, 0.1))
        )[:24]
        if 特征列表:
            行.append("特征：" + "、".join(self.特征名(特, "zh-Hans") for 特 in 特征列表))
            行.append("Traits: " + ", ".join(self.特征名(特, "en") for 特 in 特征列表))
        if 项["简介"]:
            行.append(项["简介"][:1500])
        return 文档(
            键=f"c{编}",
            类型="c",
            文本="\n".join(行),
            先验=self.角色先验[编],
            显示名=显示,
            名称变体=变体,
        )

    # MARK: 正例索引

    def 构建正例索引(self, 文档列表: list[文档]):
        self.名称精确 = collections.defaultdict(set)
        前缀条目 = []
        for i, 文 in enumerate(文档列表):
            for 名 in 文.名称变体:
                键 = 规范化名称(名)
                if len(键) >= 2:
                    self.名称精确[键].add(i)
                    前缀条目.append((键, i))
        前缀条目.sort()
        self.名称单词 = collections.defaultdict(set)
        for i, 文 in enumerate(文档列表):
            for 名 in 文.名称变体:
                for 词 in 名.split():
                    键 = 规范化名称(词)
                    if len(键) >= 3:
                        self.名称单词[键].add(i)
        self.前缀键 = [k for k, _ in 前缀条目]
        self.前缀值 = [v for _, v in 前缀条目]

        self.标签成员 = collections.defaultdict(set)
        祖先缓存: dict[str, set[str]] = {}

        def 祖先(标: str) -> set[str]:
            if 标 not in 祖先缓存:
                结果 = set()
                for 父 in self.标签.get(标, 标签("", "")).父级:
                    结果.add(父)
                    结果 |= 祖先(父)
                祖先缓存[标] = 结果
            return 祖先缓存[标]

        for 编 in self.选中作品:
            下标 = self.文档下标[f"v{编}"]
            for 标, 分 in self.作品标签.get(编, {}).items():
                if 分 >= 1.0:
                    self.标签成员[标].add(下标)
                    for 父 in 祖先(标):
                        self.标签成员[父].add(下标)

        self.特征成员 = collections.defaultdict(set)
        self.性别成员 = collections.defaultdict(set)
        self.作品角色 = collections.defaultdict(set)
        for 编 in self.选中角色:
            下标 = self.文档下标[f"c{编}"]
            项 = self.角色[编]
            for 特 in 项["特征"]:
                self.特征成员[特].add(下标)
            self.性别成员[项["性别"]].add(下标)
            for 作品, _ in 项["作品"]:
                self.作品角色[作品].add(下标)

        self.会社成员 = collections.defaultdict(set)
        for 编 in self.选中作品:
            for 名, 拉丁 in self.作品[编].get("开发", []):
                self.会社成员[(拉丁 or 名)].add(self.文档下标[f"v{编}"])

    def 前缀正例(self, 键: str) -> set[int] | None:
        左 = bisect.bisect_left(self.前缀键, 键)
        右 = bisect.bisect_left(self.前缀键, 键 + "\U0010ffff")
        if 右 - 左 > 正例上限 * 4:
            return None
        结果 = set(self.前缀值[左:右])
        return 结果 if len(结果) <= 60 else None

    # MARK: 合成查询

    def 生成查询(self, 文档列表: list[文档]) -> list[dict]:
        随机 = random.Random(self.种子)
        查询 = []
        for 编 in self.选中作品:
            查询.extend(self._作品查询(编, 随机))
        for 编 in self.选中角色:
            查询.extend(self._角色查询(编, 随机))
        for 作品, 角色, 内容 in self.台词:
            正例 = set()
            if f"v{作品}" in self.文档下标:
                正例.add(self.文档下标[f"v{作品}"])
            if 角色 is not None and f"c{角色}" in self.文档下标:
                正例.add(self.文档下标[f"c{角色}"])
            if 正例:
                来源 = f"v{作品}" if f"v{作品}" in self.文档下标 else f"c{角色}"
                查询.append(self._查询(内容, 正例, "quote", "en", 来源))
        查询.extend(self._单标签查询(文档列表, 随机))
        return [q for q in 查询 if q is not None]

    def _单标签查询(self, 文档列表: list[文档], 随机: random.Random) -> list[dict]:
        """只输入一个标签（如“猫娘”）时，最热门的同类作品都是合理答案。"""
        结果 = []
        for 标, 成员 in self.标签成员.items():
            if len(成员) < 10 or self.标签[标].类别 != "cont":
                continue
            热门 = sorted(成员, key=lambda i: -文档列表[i].先验)[:500]
            for _ in range(2):
                语种 = _随机语言(随机)
                文本 = 随机.choice(_标签模板[语种]).format(T=self.标签名(标, 语种))
                结果.append(self._查询(文本, set(热门), "tag1", 语种, 文档列表[热门[0]].键, 上限=500))
        return 结果

    def 生成负例(self, 数量: int) -> list[dict]:
        随机 = random.Random(self.种子 + 7)
        结果 = [{"q": q, "pos": [], "type": "neg", "lang": "", "src": ""} for q in _泛化查询]
        while len(结果) < 数量:
            选择 = 随机.random()
            if 选择 < 0.4:
                文本 = "".join(随机.choice("asdfghjklqwertyuiopzxcvbnm") for _ in range(随机.randint(3, 10)))
            elif 选择 < 0.8:
                文本 = "".join(随机.choice(_常用汉字) for _ in range(随机.randint(2, 6)))
            else:
                文本 = "".join(随机.choice("0123456789") for _ in range(随机.randint(2, 8)))
            结果.append({"q": 文本, "pos": [], "type": "neg", "lang": "", "src": ""})
        return 结果

    def _查询(self, 文本: str, 正例: set[int], 类型: str, 语种: str, 来源: str, 上限: int = 正例上限) -> dict | None:
        文本 = re.sub(r"\s+", " ", 文本).strip()
        if len(文本) < 2 or not 正例 or len(正例) > 上限:
            return None
        return {"q": 文本, "pos": sorted(正例), "type": 类型, "lang": 语种, "src": 来源}

    def _扰动(self, 名: str, 随机: random.Random) -> str:
        """模拟用户输错或记不全的名字：错字、漏字、调换、假名写法、罗马字长音写法等。"""
        if 含汉字(名) or 含假名(名) or not 名.isascii():
            字 = [c for c in 名 if c not in " ・　"]
            选择 = 随机.random()
            if 选择 < 0.3 and len(字) >= 4:
                del 字[随机.randrange(len(字))]
            elif 选择 < 0.5 and len(字) >= 3:
                i = 随机.randrange(len(字) - 1)
                字[i], 字[i + 1] = 字[i + 1], 字[i]
            elif 选择 < 0.75:
                字 = [chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in 字]
            return "".join(字)
        字 = list(名.lower() if 随机.random() < 0.6 else 名)
        if 随机.random() < 0.5:
            字 = [c for c in 字 if c.isalnum() or c == " "]
        选择 = 随机.random()
        字母位置 = [i for i, c in enumerate(字) if c.isalpha()]
        if not 字母位置:
            return "".join(字)
        文本 = "".join(字)
        if 选择 < 0.2:
            return 文本.replace(" ", "")
        if 选择 < 0.4:
            for 旧, 新 in 随机.sample([("ou", "o"), ("o", "ou"), ("oo", "ou"), ("ou", "oh"), ("uu", "u"), ("u", "uu")], 6):
                if 旧 in 文本:
                    i = 随机.choice([m.start() for m in re.finditer(re.escape(旧), 文本)])
                    return 文本[:i] + 新 + 文本[i + len(旧):]
            return 文本
        i = 随机.choice(字母位置)
        if 选择 < 0.55 and len(字母位置) >= 5:
            del 字[i]
        elif 选择 < 0.7 and i + 1 < len(字) and 字[i + 1].isalpha():
            字[i], 字[i + 1] = 字[i + 1], 字[i]
        elif 选择 < 0.85 and 字[i].lower() in _键盘邻键:
            字[i] = 随机.choice(_键盘邻键[字[i].lower()])
        else:
            字.insert(i, 字[i])
        return "".join(字)

    def _名称查询(self, 名: str, 来源下标: int, 随机: random.Random, 类型: str, 来源: str):
        键 = 规范化名称(名)
        if len(键) < 2:
            return None
        if 随机.random() < 0.3:
            扰动后 = self._扰动(名, 随机)
            if len(规范化名称(扰动后)) >= 2:
                正例 = self.名称精确.get(规范化名称(扰动后), set()) | {来源下标}
                return self._查询(扰动后, 正例, 类型 + "-noisy", "", 来源)
        词 = 名.split()
        if len(词) >= 2 and 随机.random() < 0.2:
            单词 = 随机.choice(词)
            正例 = self.名称单词.get(规范化名称(单词), set())
            if len(规范化名称(单词)) >= 3 and 来源下标 in 正例:
                return self._查询(单词, 正例, 类型 + "-word", "", 来源)
        if 随机.random() < 0.25 and len(键) >= 4:
            if 含汉字(名) or 含假名(名):
                长度 = 随机.randint(2, max(2, len(名) - 1))
                片段 = 名[:长度]
            else:
                词 = 名.split()
                if len(词) < 2:
                    return None
                片段 = " ".join(词[: 随机.randint(1, len(词) - 1)])
            正例 = self.前缀正例(规范化名称(片段))
            if not 正例 or 来源下标 not in 正例:
                return None
            return self._查询(片段, 正例, 类型 + "-prefix", "", 来源)
        正例 = self.名称精确.get(键, set()) | {来源下标}
        return self._查询(名, 正例, 类型, "", 来源)

    def _标签组合(self, 编: int, 随机: random.Random, 数量: int) -> list[str] | None:
        候选 = [
            (标, 分) for 标, 分 in self.作品标签.get(编, {}).items()
            if 分 >= 1.5 and self.标签[标].类别 != "ero"
        ]
        if len(候选) < 数量:
            return None
        # 偏向更具体（成员更少）的标签，泛泛的“恋爱”“男主角”无法区分作品。
        权重 = [
            分 / math.log(2 + len(self.标签成员.get(标, ())))
            * (0.25 if self.标签[标].类别 == "tech" else 1.0)
            for 标, 分 in 候选
        ]
        选中 = []
        for _ in range(数量):
            标 = 随机.choices([c[0] for c in 候选], weights=权重)[0]
            i = [c[0] for c in 候选].index(标)
            候选.pop(i)
            权重.pop(i)
            选中.append(标)
        return 选中

    def _作品查询(self, 编: int, 随机: random.Random) -> list[dict]:
        项 = self.作品[编]
        下标 = self.文档下标[f"v{编}"]
        来源 = f"v{编}"
        票数 = 项["票数"]
        结果 = []
        _, _, 变体 = self.作品标题(编)

        if 变体:
            结果.append(self._名称查询(随机.choice(变体), 下标, 随机, "title", 来源))

        for _ in range(1 + (票数 >= 50) + (票数 >= 500)):
            标签组 = self._标签组合(编, 随机, 随机.choice([2, 2, 3, 3, 4]))
            if not 标签组:
                break
            正例 = set.intersection(*(self.标签成员[标] for 标 in 标签组))
            语种 = _随机语言(随机)
            连接 = 随机.choice(_标签连接[语种])
            名称 = 连接.join(self.标签名(标, 语种) for 标 in 标签组)
            if 项.get("开发") and 随机.random() < 0.2:
                名, 拉丁 = 项["开发"][0]
                会社 = 名 if 语种 in ("ja", "zh-Hans", "zh-Hant") and 随机.random() < 0.5 else (拉丁 or 名)
                正例 &= self.会社成员[(拉丁 or 名)]
                文本 = 随机.choice(_会社模板[语种]).format(D=会社, T=名称)
            else:
                文本 = 随机.choice(_标签模板[语种]).format(T=名称)
            结果.append(self._查询(文本, 正例 | {下标}, "tags", 语种, 来源))

        句子 = []
        if 编 in self.中文简介:
            句子.extend(("zh-Hans", s) for s in 分句(self.中文简介[编]))
        if 项["简介"]:
            语种 = "ja" if 含假名(项["简介"]) else "en"
            句子.extend((语种, s) for s in 分句(项["简介"]))
        次数 = min(len(句子), 1 + (票数 >= 20) + (票数 >= 200))
        中文优先 = [s for s in 句子 if s[0] == "zh-Hans"]
        for _ in range(次数):
            池 = 中文优先 if 中文优先 and 随机.random() < 0.7 else 句子
            语种, 句 = 随机.choice(池)
            片段 = self._截取片段(句, 语种, 随机)
            前缀 = 随机.choice(_简介前缀.get(语种, [""]))
            if 前缀 and 语种 == "en":
                片段 = 片段[:1].lower() + 片段[1:]
            结果.append(self._查询(前缀 + 片段, {下标}, "desc", 语种, 来源))
        return 结果

    def _截取片段(self, 句: str, 语种: str, 随机: random.Random) -> str:
        if 语种 == "en":
            词 = 句.split()
            if len(词) > 22:
                长度 = 随机.randint(8, 20)
                起点 = 随机.randint(0, len(词) - 长度)
                词 = 词[起点: 起点 + 长度]
            if len(词) > 6 and 随机.random() < 0.3:
                词 = [w for w in 词 if 随机.random() > 0.12]
            return " ".join(词)
        if len(句) > 60:
            长度 = 随机.randint(14, 50)
            起点 = 随机.randint(0, len(句) - 长度)
            句 = 句[起点: 起点 + 长度]
        if 随机.random() < 0.3:
            句 = re.sub(r"[，。、！？「」『』“”]", 随机.choice(["", " "]), 句)
        return 句

    def _采样特征(self, 项: dict, 随机: random.Random) -> list[str]:
        候选 = list(dict.fromkeys(项["特征"]))
        随机.shuffle(候选)
        选中 = []
        已有分组 = set()
        for 特 in 候选:
            特项 = self.特征[特]
            分组 = 特项.父名 or 特项.根名
            if 分组 in 已有分组 and 分组 in ("Hair Color", "Eye Color", "Length", "Long"):
                continue
            权重 = _特征组权重.get(特项.父名, _特征组权重.get(特项.根名, 0.1))
            if 随机.random() < 权重:
                选中.append(特)
                已有分组.add(分组)
            if len(选中) >= 随机.choice([2, 3, 3, 4]):
                break
        return 选中

    def _角色查询(self, 编: int, 随机: random.Random) -> list[dict]:
        项 = self.角色[编]
        下标 = self.文档下标[f"c{编}"]
        来源 = f"c{编}"
        结果 = []
        作品票数 = self.作品[项["作品"][0][0]]["票数"]
        显示, 原文, 变体 = self.角色名称(编)

        if 变体 and 随机.random() < 0.6:
            结果.append(self._名称查询(随机.choice(变体), 下标, 随机, "name", 来源))
        if 随机.random() < 0.35:
            作品, _ = 随机.choice(项["作品"][:2])
            语种 = 随机.choice(list(_角色名模板))
            名 = 原文 if 语种 != "en" and 原文 else 显示
            作品名 = self.查询用作品名(作品, 语种, 随机)
            文本 = 随机.choice(_角色名模板[语种]).format(V=作品名, N=名)
            结果.append(self._查询(文本, {下标}, "name-vn", 语种, 来源))

        for 次 in range(1 + (作品票数 >= 100) + (作品票数 >= 1000)):
            特征组 = self._采样特征(项, 随机)
            if len(特征组) < 2:
                break
            语种 = _随机语言(随机)
            连接 = 随机.choice(_特征连接[语种])
            名称 = 连接.join(self.特征名(特, 语种, 随机) for 特 in 特征组)
            性别 = 项["性别"] if 项["性别"] in ("f", "m") else ""
            性别词 = 随机.choice(_性别词[性别][语种])
            正例 = set.intersection(*(self.特征成员[特] for 特 in 特征组))
            if 性别:
                正例 &= self.性别成员[性别]
            if 次 > 0 or 随机.random() < 0.4:
                作品, _ = 随机.choice(项["作品"][:2])
                作品名 = self.查询用作品名(作品, 语种, 随机)
                正例 &= self.作品角色[作品]
                文本 = 随机.choice(_角色作品模板[语种]).format(V=作品名, T=名称, G=性别词)
            else:
                文本 = 随机.choice(_角色模板[语种]).format(T=名称, G=性别词)
            结果.append(self._查询(文本, 正例 | {下标}, "traits", 语种, 来源))

        if 项["简介"] and 随机.random() < 0.7:
            句子 = 分句(项["简介"])
            if 句子:
                句 = 随机.choice(句子)
                语种 = "ja" if 含假名(句) else "en"
                结果.append(self._查询(self._截取片段(句, 语种, 随机), {下标}, "desc", 语种, 来源))
        return 结果


def 划分(查询: list[dict], 负例: list[dict], 文档列表: list[文档], 种子: int):
    """按来源文档划分成三份：语义模型训练、排序模型训练、评估。

    排序模型和评估用的查询来自语义模型没见过的条目，这样它们看到的是真实使用时的相似度分布。
    """
    随机 = random.Random(种子 + 1)
    候选 = list(range(len(文档列表)))
    权重 = [math.sqrt(0.05 + 文档列表[i].先验) for i in 候选]
    已选: set[int] = set()

    def 抽取(比例: float) -> set[str]:
        目标 = len(已选) + int(len(候选) * 比例)
        while len(已选) < 目标:
            已选.update(随机.choices(候选, weights=权重, k=目标 - len(已选)))
        return {文档列表[i].键 for i in 已选}

    评估键 = 抽取(0.02)
    排序键 = 抽取(0.03) - 评估键
    训练, 排序, 评估 = [], [], []
    for q in 查询:
        if q["src"] in 评估键:
            评估.append(q)
        elif q["src"] in 排序键:
            排序.append(q)
        else:
            训练.append(q)
    保留文本 = {q["q"] for q in 评估} | {q["q"] for q in 排序}
    训练 = [q for q in 训练 if q["q"] not in 保留文本]
    随机.shuffle(负例)
    一半 = len(负例) // 2
    排序 += 负例[:一半]
    评估 += 负例[一半:]
    随机.shuffle(排序)
    随机.shuffle(评估)
    return 训练, 排序, 评估


def 准备(导出目录: Path, 译文目录: Path | None, 应用目录: Path, 输出目录: Path, 种子: int = 20261006):
    构建器 = 语料构建器(导出目录, 译文目录, 应用目录, 种子)
    构建器.读取全部()
    构建器.选择条目()
    文档列表 = 构建器.构建文档()
    构建器.构建正例索引(文档列表)
    查询 = 构建器.生成查询(文档列表)
    训练, 排序, 评估 = 划分(查询, 构建器.生成负例(3000), 文档列表, 种子)

    输出目录.mkdir(parents=True, exist_ok=True)
    with open(输出目录 / "corpus.jsonl", "w", encoding="utf-8") as 文件:
        for 文 in 文档列表:
            文件.write(json.dumps({
                "key": 文.键, "kind": 文.类型, "text": 文.文本,
                "prior": round(文.先验, 5), "display": 文.显示名, "names": 文.名称变体,
            }, ensure_ascii=False) + "\n")
    for 名称, 数据 in (("train.jsonl", 训练), ("rank.jsonl", 排序), ("eval.jsonl", 评估)):
        with open(输出目录 / 名称, "w", encoding="utf-8") as 文件:
            for q in 数据:
                文件.write(json.dumps(q, ensure_ascii=False) + "\n")

    类型计数 = collections.Counter(q["type"] for q in 训练)
    语言计数 = collections.Counter(q["lang"] for q in 训练)
    print(f"作品 {len(构建器.选中作品)}，角色 {len(构建器.选中角色)}，中文简介 {len(构建器.中文简介)}")
    print(f"语义训练查询 {len(训练)}，排序训练查询 {len(排序)}，评估查询 {len(评估)}")
    print(f"类型 {dict(类型计数)}")
    print(f"语言 {dict(语言计数)}")
    return 文档列表
