#!/usr/bin/env python3
"""生成预装在 App 内的作品 ID 映射 PaperVN/Resources/PaperVNWorkMap.json。

PaperVN Sync 同步时不再按标题现场匹配，各平台的条目都先查这份映射。规则：

动画以 Annict 的作品划分为准
  - 一部 Annict 作品就是一部作品（arm 提供 Annict、MAL、AniList 的一对一对应）。
  - 没有 Annict 作品的按 MAL 划分。MAL 的 Special 如果在 AniList 上只有一个“PARENT”（正篇），
    而正篇有 Annict 作品，说明 Annict 把它并在正篇的话里：它仍是单独的作品（用户会在 MAL 上单独记录），
    只是不写入 Annict（annictFolded）。
  - Bangumi 条目先用 bangumi-data 的 MAL 对应；没有的按原名、年份与类型离线对应（唯一才采用）；
    仍然没有、而它是某部已对应作品的“番外篇”“总集篇”的，作为那部作品的附属条目。
  - 多个 Bangumi 条目对应同一部作品时，与 MAL 同一年开播、编号最小的是主条目，其余为附属。
漫画与轻小说以 MAL 为准
  - AniList 的 idMal 对应 MAL。
  - Bangumi 的系列条目按原名、年份与类型（漫画 / 小说）离线对应；单行本是系列的附属条目。
TMDB（只有动画）
  - bangumi-data 给出的 TMDB 条目（类型必须相符：TV 对剧集、剧场版对电影），再用 Wikidata 补充一对一的对应；
    TMDB 把一部剧的各季算作一个条目，第二季以后在 App 里不写入 TMDB。
视觉小说以 VNDB 为准
  - vndb_id_connector.json 已经列出每部 VNDB 作品对应的 Bangumi 条目；这里只选出主条目
    （被其他条目标为“主版本”的，否则最早发售的），推送到 Bangumi 时只写主条目。

用法：
  python3 Tools/构建作品映射.py download <数据目录>   下载 arm、bangumi-data、anime-offline-database、
                                                     Bangumi Archive 和 AniList 的数据（AniList 约 1 小时，可断点续传）
  python3 Tools/构建作品映射.py build <数据目录>      生成映射文件
"""

import base64
import collections
import datetime
import json
import pathlib
import re
import sys
import time
import unicodedata
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "PaperVN" / "Resources" / "PaperVNWorkMap.json"
VN_CONNECTOR = ROOT / "PaperVN" / "Resources" / "vndb_id_connector.json"
# 人工核对过的校正（审计时逐条确认），优先于所有自动规则：Bangumi 条目 → MAL ID，null 表示这个条目不对应任何 MAL 作品
CORRECTIONS = ROOT / "Tools" / "作品映射人工校正.json"

# Bangumi 关联类型（bangumi/common subject_relations.yml）
BGM_ANIME_SUMMARY, BGM_ANIME_SIDE_STORY, BGM_ANIME_MAIN_STORY = 4, 6, 12
BGM_BOOK_SERIES, BGM_BOOK_VOLUME = 1002, 1003
BGM_GAME_MAIN_VERSION = 4017
# Bangumi 动画平台：1 TV、2 OVA、3 剧场版、5 WEB；书籍平台：1001 漫画、1002 小说
# 各平台对短篇、网络动画、特别篇的分类并不一致（Bangumi 的 WEB 在 AniList 上常是 SPECIAL），所以放宽到相近的几类；
# 标题和年份仍然必须对上，并且只有一个候选。
BGM_ANIME_FORMATS = {
    # Bangumi 的电视特别节目也记为 TV，但允许 TV 对 SPECIAL 时，审计发现 TV 动画会被配到同名的特别篇，所以不允许
    1: {"TV", "TV_SHORT", "ONA"},
    2: {"OVA", "SPECIAL", "ONA"},
    3: {"MOVIE", "SPECIAL"},
    5: {"ONA", "SPECIAL", "TV_SHORT", "OVA"},
}
BGM_BOOK_FORMATS = {1001: {"MANGA", "ONE_SHOT"}, 1002: {"NOVEL"}}
# 各 Bangumi 动画平台最典型的格式，用来判断 bangumi-data 的对应是否明显配错了类型
BGM_PRIMARY_FORMATS = {1: {"TV", "TV_SHORT"}, 2: {"OVA"}, 3: {"MOVIE"}, 5: {"ONA"}}


# MARK: 下载

def fetch(url, path, timeout=600):
    for attempt in range(5):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "PaperVN-Tools"})
            with urllib.request.urlopen(request, timeout=timeout) as response, open(path, "wb") as file:
                while chunk := response.read(1 << 20):
                    file.write(chunk)
            return
        except Exception as error:  # 网络不稳定时重试
            print(f"  {url}: {error}，重试", flush=True)
            time.sleep(5 * (attempt + 1))
    raise SystemExit(f"无法下载 {url}")


ANILIST_QUERY = """query ($ids: [Int], $page: Int) { Page(page: $page, perPage: 50) { pageInfo { hasNextPage }
 media(id_in: $ids, sort: ID) { id idMal type format episodes countryOfOrigin startDate { year month day }
  title { native romaji english } synonyms relations { edges { relationType node { id idMal type format } } } } } }"""


def anilist_post(variables):
    """用 curl 请求：经本机代理时 Python 的 TLS 连接经常被中断，curl 稳定得多。"""
    import subprocess
    while True:
        body = json.dumps({"query": ANILIST_QUERY, "variables": variables})
        result = subprocess.run(
            ["curl", "-s", "-m", "90", "-D", "-", "https://graphql.anilist.co",
             "-H", "Content-Type: application/json", "-H", "Accept: application/json",
             "-H", "User-Agent: PaperVN-Tools", "--data-binary", "@-"],
            input=body.encode(), capture_output=True,
        )
        head, _, payload = result.stdout.decode("utf-8", "replace").partition("\r\n\r\n")
        status = head.split(" ")[1] if head.startswith("HTTP") else "000"
        if status == "200":
            try:
                return json.loads(payload)
            except ValueError:
                pass
        wait = 30
        for line in head.split("\r\n"):
            if line.lower().startswith("retry-after:"):
                wait = int(line.split(":")[1].strip() or 30)
        time.sleep(wait + 1)


def fetch_anilist(directory):
    """读取 AniList 的全部动画和漫画。AniList 的页数分页最多只能读到 5000 条，所以按 ID 区间（id_in）逐段读取；
    动画和漫画共用一套 ID，一次读完再分到两个文件。中断后从上次的区间继续。"""
    max_id = subprocess_max_id() or 300000
    state = directory / "anilist-window.state"
    start = int(state.read_text()) if state.exists() else 1
    files = {kind: (directory / f"anilist-{kind.lower()}.jsonl").open("a") for kind in ("ANIME", "MANGA")}
    while start <= max_id:
        ids = list(range(start, min(start + 2000, max_id + 1)))
        page = 1
        while True:
            result = anilist_post({"ids": ids, "page": page})["data"]["Page"]
            for media in result["media"]:
                files[media["type"]].write(json.dumps(media, ensure_ascii=False) + "\n")
            for file in files.values():
                file.flush()
            time.sleep(1.2)
            if not result["pageInfo"]["hasNextPage"]:
                break
            page += 1
        start += 2000
        state.write_text(str(start))
        print(f"  AniList 已读到 ID {start - 1}", flush=True)


def subprocess_max_id():
    """AniList 目前最大的作品 ID。"""
    import subprocess
    query = json.dumps({"query": "{ Page(perPage: 1) { media(sort: ID_DESC) { id } } }"})
    result = subprocess.run(["curl", "-s", "-m", "60", "https://graphql.anilist.co", "-H", "Content-Type: application/json",
                             "--data-binary", "@-"], input=query.encode(), capture_output=True)
    try:
        return json.loads(result.stdout)["data"]["Page"]["media"][0]["id"]
    except (ValueError, KeyError, IndexError):
        return None


def download(directory):
    directory.mkdir(parents=True, exist_ok=True)
    print("arm（Annict、MAL、AniList 对应）")
    fetch("https://raw.githubusercontent.com/kawaiioverflow/arm/master/arm.json", directory / "arm.json")
    print("bangumi-data")
    with urllib.request.urlopen("https://registry.npmjs.org/bangumi-data/latest", timeout=60) as response:
        version = json.load(response)["version"]
    fetch(f"https://cdn.jsdelivr.net/npm/bangumi-data@{version}/dist/data.json", directory / "bangumi-data.json")
    print("anime-offline-database")
    fetch("https://github.com/manami-project/anime-offline-database/releases/latest/download/anime-offline-database-minified.json",
          directory / "aod.json", timeout=1800)
    print("Bangumi Archive")
    with urllib.request.urlopen("https://raw.githubusercontent.com/bangumi/Archive/master/aux/latest.json", timeout=60) as response:
        latest = json.load(response)
    fetch(latest["browser_download_url"], directory / "bangumi-dump.zip", timeout=3600)
    with zipfile.ZipFile(directory / "bangumi-dump.zip") as archive:
        for name in ("subject.jsonlines", "subject-relations.jsonlines"):
            archive.extract(name, directory / "bgm")
    print("Wikidata（MAL 与 TMDB 的对应）")
    import subprocess
    for name, prop in (("wikidata-tmdb-tv.json", "P4983"), ("wikidata-tmdb-movie.json", "P4947")):
        query = f"SELECT ?mal ?x WHERE {{ ?item wdt:P4086 ?mal . ?item wdt:{prop} ?x . }}"
        subprocess.run(["curl", "-s", "-m", "300", "-G", "-A", "PaperVN-Tools", "--data-urlencode", "format=json",
                        "--data-urlencode", f"query={query}", "https://query.wikidata.org/sparql",
                        "-o", str(directory / name)], check=True)
    print("AniList（约 1 小时）")
    fetch_anilist(directory)


# MARK: 读取

TITLE_PREFIXES = ("映画", "劇場版", "剧场版", "电影", "電影", "tvアニメ", "the movie")
CHINESE_NUMERALS = {"一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10}
PART_PATTERNS = (
    re.compile(r"part\s*\.?\s*([0-9]+)"),
    re.compile(r"第?\s*([0-9]+)\s*クール"),
    re.compile(r"([0-9]+)\s*(?:st|nd|rd|th)?\s*cour"),
)
SEASON_PATTERNS = (
    re.compile(r"第\s*([0-9]+|[一二三四五六七八九十])\s*(期|季|シーズン|部)"),
    re.compile(r"([0-9]+)\s*(st|nd|rd|th)?\s*season"),
    re.compile(r"season\s*([0-9]+)"),
    re.compile(r"([0-9]+)\s*期"),
    # “…同好会 2”这样标题末尾单独的数字也是季数
    re.compile(r"\s([0-9]{1,2})$"),
)


def title_key(title):
    """与 App 里 `同步合并.标题匹配键` 相同：统一全半角和大小写，去掉“映画”“劇場版”等前缀，
    把“第2期”“2期”“2nd Season”“Season 2”“第二季”统一成同一种写法，再去掉空白和符号。"""
    if not title:
        return ""
    text = unicodedata.normalize("NFKC", title).lower()
    for prefix in TITLE_PREFIXES:
        if text.startswith(prefix):
            text = text[len(prefix):]
            break

    def season(match):
        value = match.group(1)
        number = int(value) if value.isdigit() else CHINESE_NUMERALS.get(value)
        return f" s{number} " if number else match.group(0)

    text = text.strip()
    # 分割放送的写法：“Part 2”“Part.2”“第2クール”“2nd Cour”统一成同一个记号，免得末尾的数字被当成季数
    for pattern in PART_PATTERNS:
        text = pattern.sub(lambda match: f" pt{int(match.group(1))} ", text)
    for pattern in SEASON_PATTERNS:
        text = pattern.sub(season, text)
    # “+”“@”“!”“?”常常就是区分作品的部分（GJ部 与 GJ部@、ロボットガールズZ 与 ロボットガールズZ+、
    # デュエル・マスターズ 与 デュエル・マスターズ!），保留；其余符号和空白去掉
    return "".join(ch for ch in text if ch.isalnum() or ch in "+@!?")


def year_of(value):
    if isinstance(value, dict):
        return value.get("year")
    if isinstance(value, str) and re.match(r"^\d{4}", value):
        return int(value[:4])
    return None


def read_jsonl(path):
    with open(path, encoding="utf-8") as file:
        for line in file:
            if line.strip():
                yield json.loads(line)


def annict_node(annict_id):
    return base64.b64encode(f"Work-{annict_id}".encode()).decode()


class Works:
    """一类作品（动画或漫画）的映射：作品列表、各平台主条目和附属条目。"""

    def __init__(self, kind):
        self.kind = kind
        self.rows = []          # [key, mal, anilist, annict, bangumi, tmdb]
        self.index = {}         # key → 下标
        self.owner = {}         # (平台, ID) → 下标
        self.attached = []      # (平台, ID, 下标)
        self.annict_folded = set()  # Annict 并在正篇里的作品下标
        self.tmdb_no_write = set()  # 和别的作品共用一个 TMDB 条目、不写入 TMDB 的作品下标
        self.series = {}  # 下标 → 所属系列（取系列里下标最小的作品）

    def add(self, key, mal=None, anilist=None, annict=None):
        if key in self.index:
            return self.index[key]
        index = len(self.rows)
        self.rows.append([key, mal, anilist, annict, None, None])
        self.index[key] = index
        for platform, value in (("myAnimeList", mal), ("aniList", anilist), ("annict", annict)):
            if value is not None:
                self.owner[(platform, str(value))] = index
        return index

    def find(self, platform, value):
        return self.owner.get((platform, str(value)))

    def set_bangumi(self, index, bangumi):
        """作品还没有 Bangumi 主条目时设为主条目，否则作为附属条目。"""
        if ("bangumi", str(bangumi)) in self.owner:
            return
        if self.rows[index][4] is None:
            self.rows[index][4] = bangumi
        else:
            self.attached.append(("bangumi", bangumi, index))
        self.owner[("bangumi", str(bangumi))] = index

    def attach(self, platform, value, index):
        if (platform, str(value)) in self.owner:
            return False
        self.attached.append((platform, value, index))
        self.owner[(platform, str(value))] = index
        return True

    def json(self, keep=lambda row: True):
        """keep 为假的作品不写入（附属条目指向的作品始终保留）。下标随之重新编号。"""
        needed = {index for _, _, index in self.attached}
        kept = [index for index, row in enumerate(self.rows) if index in needed or keep(row)]
        renumber = {old: new for new, old in enumerate(kept)}
        # 附属条目按平台写成扁平的数字数组 [ID, 作品下标, ID, 作品下标, …]，Bangumi 单行本有十几万条，这样体积小得多
        attached = collections.defaultdict(list)
        for platform, value, index in self.attached:
            attached[platform] += [int(value), renumber[index]]
        # 编号能从 MAL ID 或 AniList ID 推出来时写 null（“mal-anime:5114”“aniList-manga:30013”），App 读取时再补上
        rows = []
        for index in kept:
            key, mal, ani, annict, bangumi, tmdb = self.rows[index]
            derived = f"mal-{self.kind}:{mal}" if mal else (f"aniList-{self.kind}:{ani}" if ani else None)
            row = [None if key == derived else key, mal, ani, annict, bangumi]
            if tmdb:
                row.append(tmdb)
            rows.append(row)
        document = {"works": rows, "attached": dict(attached)}
        if self.annict_folded:
            document["annictFolded"] = sorted(renumber[index] for index in self.annict_folded if index in renumber)
        if self.tmdb_no_write:
            document["tmdbNoWrite"] = sorted(renumber[index] for index in self.tmdb_no_write if index in renumber)
        if self.series:
            # [作品下标, 系列下标, …]：系列下标是同一系列里下标最小的作品
            document["series"] = [value for index, root in sorted(self.series.items())
                                  if index in renumber and root in renumber
                                  for value in (renumber[index], renumber[root])]
        return document


def read_bangumi(directory, types):
    subjects = {}
    for subject in read_jsonl(directory / "bgm" / "subject.jsonlines"):
        if subject["type"] in types:
            subjects[subject["id"]] = subject
    relations = collections.defaultdict(list)
    for relation in read_jsonl(directory / "bgm" / "subject-relations.jsonlines"):
        if relation["subject_id"] in subjects:
            relations[relation["subject_id"]].append((relation["relation_type"], relation["related_subject_id"]))
    return subjects, relations


def title_index(entries):
    """标题 → 候选（下标, 年份, 格式）。entries: (下标, [标题], 年份, 格式)。"""
    index = collections.defaultdict(set)
    for work, titles, year, kind in entries:
        for title in titles:
            key = title_key(title)
            if len(key) >= 2:
                index[key].add((work, year, kind))
    return index


def title_similarity(name, keys):
    """Bangumi 原名与一部作品各标题的最大相似度（0–1）。"""
    import difflib
    key = title_key(name)
    if not key or not keys:
        return 0.0
    return max(difflib.SequenceMatcher(None, key, other).ratio() for other in keys)


def exact_year_match(index, name, year, formats):
    """只接受同一年的唯一候选（覆盖人工数据时用，比 match_title 严格）。"""
    found = {work for work, other_year, kind in index.get(title_key(name), ())
             if year and other_year == year and (not formats or not kind or kind in formats)}
    return found.pop() if len(found) == 1 else None


def match_title(index, titles, year, formats, later=1):
    """原名、年份、类型都对得上且只有一个候选时才采用。
    同一年的候选优先：只有一个同年的就用它；没有同年的，才接受年份相近的唯一候选。
    动画各平台的开播日期常差几天跨年，允许相差一年；书籍 Bangumi 记的是第一卷的发售日，
    比 AniList 的连载开始晚一到三年，later=3。"""
    exact, near = set(), set()
    keys = []
    for title in titles:
        key = title_key(title)
        keys.append(key)
        # “第1期”在另一个平台上常常没有写季数
        if key.endswith("s1"):
            keys.append(key[:-2])
    for key in keys:
        for work, other_year, kind in index.get(key, ()):
            if formats and kind and kind not in formats:
                continue
            if year and other_year:
                if year == other_year:
                    exact.add(work)
                elif -1 <= year - other_year <= later:
                    near.add(work)
            else:
                near.add(work)
    if exact:
        return exact.pop() if len(exact) == 1 else None
    return near.pop() if len(near) == 1 else None


def resolve_duplicate_mal(anilist, mal_titles, stats, name):
    """AniList 上偶尔有几个不同的作品记着同一个 MAL ID（例如同名的两部漫画）。
    有 MAL 自己的标题与年份（mal_titles: MAL ID → (年份, [标题])）时，只保留标题和年份都对得上的那一个；
    对不上或没有 MAL 数据时，这几个条目都不算对应到 MAL，免得把一部作品的 MAL ID 安到另一部上。"""
    groups = collections.defaultdict(list)
    for media in anilist.values():
        if media.get("idMal"):
            groups[media["idMal"]].append(media)
    cleared = 0
    for mal, medias in groups.items():
        if len(medias) < 2:
            continue
        keep = None
        if mal in mal_titles:
            year, titles = mal_titles[mal]
            keys = {title_key(t) for t in titles}
            fits = [m for m in medias
                    if {title_key(t) for t in (m["title"].get("native"), m["title"].get("romaji"), m["title"].get("english")) if t} & keys
                    and (not year or year_of(m.get("startDate")) in (None, year))]
            keep = fits[0] if len(fits) == 1 else None
        for media in medias:
            if media is not keep:
                media["idMal"] = None
                cleared += 1
    stats[f"{name}：AniList 上重复的 MAL ID 已去掉"] = cleared


# MARK: 动画

# 只按续作、前作连起来（第 1、2、3 季，续篇剧场版）。外传、衍生、另一版本不算：
# 例如 Love Live! 的各企划（μ's、Sunshine!!、虹咲、Superstar!!）是不同的作品，不能叠在一起
SERIES_RELATIONS = {"SEQUEL", "PREQUEL"}
# AniList 也会把不同企划标成续作（Love Live! 剧场版 → Sunshine!!，高达 → 高达 0083）。两部都有 Bangumi 条目时，
# 还要 Bangumi 也记着前传、续集、总集篇、全集或番外篇才算同一系列（Bangumi 动画条目关系的编号）
BANGUMI_SERIES_RELATIONS = {2, 3, 4, 5, 6}


def fill_missing_mal(anilist, found, stats, name):
    """AniList 没记 MAL ID 的作品补上 MAL ID（found：AniList ID → MAL ID）。这个 MAL ID 已经属于另一个 AniList 条目时不补。"""
    used = {media["idMal"] for media in anilist.values() if media.get("idMal")}
    filled = 0
    for ani, mal in found.items():
        media = anilist.get(int(ani))
        if mal and media and not media.get("idMal") and mal not in used:
            media["idMal"] = mal
            used.add(mal)
            filled += 1
    stats[f"{name}：AniList 没记的 MAL ID 已补上"] = filled


def build_anime(directory, stats):
    works = Works("anime")
    arm = json.load(open(directory / "arm.json"))
    anilist = {media["id"]: media for media in read_jsonl(directory / "anilist-anime.jsonl")}  # 续传时可能有重复的行
    mal_titles = {}
    for entry in json.load(open(directory / "aod.json"))["data"]:
        for url in entry["sources"]:
            if (match := re.match(r"https://myanimelist\.net/anime/(\d+)$", url)):
                mal_titles[int(match.group(1))] = ((entry.get("animeSeason") or {}).get("year"), [entry["title"]] + (entry.get("synonyms") or []))
    resolve_duplicate_mal(anilist, mal_titles, stats, "动画")
    # anime-offline-database 同一条目里同时有 AniList 和 MAL 的链接
    from_aod = {}
    for entry in json.load(open(directory / "aod.json"))["data"]:
        ids = {site: int(m.group(1)) for url in entry["sources"]
               for site, pattern in (("ani", r"https://anilist\.co/anime/(\d+)$"), ("mal", r"https://myanimelist\.net/anime/(\d+)$"))
               if (m := re.match(pattern, url))}
        if "ani" in ids and "mal" in ids:
            from_aod[ids["ani"]] = ids["mal"]
    fill_missing_mal(anilist, from_aod, stats, "动画")
    anilist_by_mal = {media["idMal"]: media for media in anilist.values() if media.get("idMal")}

    # 1. Annict 作品（arm 中 Annict 与 MAL 一一对应）。Annict 自己记错 MAL ID 的，按人工校正改正（null 表示 MAL 上没有对应的作品）
    annict_corrections = json.load(open(CORRECTIONS)).get("annict", {}) if CORRECTIONS.exists() else {}
    corrected = 0
    for row in arm:
        annict, mal = row.get("annict_id"), row.get("mal_id")
        if not annict:
            continue
        fixed = str(annict) in annict_corrections
        if fixed:
            mal = annict_corrections[str(annict)]
            corrected += 1
        media = anilist_by_mal.get(mal) if mal else None
        # AniList 的 ID 以 AniList 自己记的 idMal 为准（arm 偶尔记的是 AniList 上重复的条目）
        # 校正过 MAL ID 的行，arm 记的 AniList ID 属于原来那部作品，不能用
        ani = (media["id"] if media else None) or (None if fixed else row.get("anilist_id"))
        key = f"mal-anime:{mal}" if mal else f"annict-anime:{annict_node(annict)}"
        if key in works.index:
            # 同一部 MAL 作品已经有 Annict 作品（例如校正后指向的作品），这个 Annict 作品作为附属条目
            index = works.index[key]
            if works.rows[index][3] is None:
                works.rows[index][3] = annict
                works.owner[("annict", str(annict))] = index
            else:
                works.attach("annict", annict, index)
            continue
        works.add(key, mal=mal, anilist=ani, annict=annict)
    stats["动画：Annict作品"] = len(works.rows)
    stats["动画：Annict的MAL ID已校正"] = corrected

    # 2. 没有 Annict 作品的 MAL / AniList 作品：Special 并入正篇，其余单独成为作品
    folded = 0
    pending_specials = []
    for media in anilist.values():
        mal = media.get("idMal")
        if (mal and works.find("myAnimeList", mal) is not None) or works.find("aniList", media["id"]) is not None:
            continue
        if media.get("format") == "SPECIAL":
            parents = [edge["node"] for edge in (media.get("relations") or {}).get("edges", [])
                       if edge["relationType"] == "PARENT" and edge["node"]["type"] == "ANIME"]
            if len(parents) == 1:
                pending_specials.append((media, parents[0]))
                continue
        key = f"mal-anime:{mal}" if mal else f"aniList-anime:{media['id']}"
        works.add(key, mal=mal, anilist=media["id"])
    # 动画按 Annict 划分作品：Annict 把这些 Special 并在正篇的话里，所以 MAL、AniList 上单独的 Special 条目
    # 是正篇的附属条目（导入时并入正篇，不单独成为作品，也不写入）。正篇没有 Annict 作品时仍单独成为作品
    for media, parent in pending_specials:
        index = works.find("aniList", parent["id"])
        mal = media.get("idMal")
        if index is not None and works.rows[index][3] is not None and (not mal or works.find("myAnimeList", mal) is None):
            if mal:
                works.attach("myAnimeList", mal, index)
            works.attach("aniList", media["id"], index)
            folded += 1
            continue
        works.add(f"mal-anime:{mal}" if mal else f"aniList-anime:{media['id']}", mal=mal, anilist=media["id"])
    stats["动画：按Annict并入正篇的特别篇（MAL、AniList附属条目）"] = folded

    # 2b. AniList 上没有的 MAL 动画（例如一些总集篇、网络短片）：从 anime-offline-database 补上，标题用于离线对应
    aod_format = {"TV": "TV", "MOVIE": "MOVIE", "OVA": "OVA", "ONA": "ONA", "SPECIAL": "SPECIAL"}
    mal_info = {}
    for entry in json.load(open(directory / "aod.json"))["data"]:
        mal = next((int(m.group(1)) for url in entry["sources"]
                    if (m := re.match(r"https://myanimelist\.net/anime/(\d+)$", url))), None)
        if not mal:
            continue
        mal_info[mal] = (aod_format.get(entry.get("type")), (entry.get("animeSeason") or {}).get("year"),
                         [entry["title"]] + (entry.get("synonyms") or []))
        if works.find("myAnimeList", mal) is None:
            works.add(f"mal-anime:{mal}", mal=mal)
    stats["动画：只在MAL上的作品"] = sum(1 for row in works.rows if row[1] and row[2] is None and row[3] is None)

    # 各作品的标题（AniList 的各语言标题与别名；AniList 上没有的用 anime-offline-database 的），用于离线对应
    entries = []
    for index, row in enumerate(works.rows):
        media = anilist.get(row[2]) if row[2] else None
        if media:
            titles = [media["title"].get("native"), media["title"].get("romaji"), media["title"].get("english")] + (media.get("synonyms") or [])
            entries.append((index, [t for t in titles if t], year_of(media.get("startDate")), media.get("format")))
        elif row[1] in mal_info:
            mal_format, mal_year, titles = mal_info[row[1]]
            entries.append((index, titles, mal_year, mal_format))
    index_by_title = title_index(entries)
    titles_of = collections.defaultdict(set)
    work_year, work_format = {}, {}
    for work, titles, year, kind in entries:
        titles_of[work].update(title_key(title) for title in titles)
        work_year[work], work_format[work] = year, kind
    overrides = []

    # 3. Bangumi：bangumi-data 的 MAL 对应
    subjects, relations = read_bangumi(directory, {2})
    corrections = json.load(open(CORRECTIONS))["anime"] if CORRECTIONS.exists() else {}
    data = json.load(open(directory / "bangumi-data.json"))
    by_work = collections.defaultdict(list)
    moved_bangumi = {}  # 改用按原名对应的 Bangumi 条目 → 改到的作品（这条 bangumi-data 的 TMDB 也跟着改）
    rejected = 0
    for item in data["items"]:
        sites = {site["site"]: site.get("id") for site in item.get("sites", [])}
        try:
            bangumi, mal = int(sites.get("bangumi") or 0), int(sites.get("mal") or 0)
        except ValueError:
            continue
        if str(bangumi) in corrections:
            continue  # 人工校正的条目稍后单独处理
        if not (bangumi and mal) or (index := works.find("myAnimeList", mal)) is None:
            continue
        # bangumi-data 是人工整理的，各平台对特别篇、剧场版、OVA 的分类又不一致，所以不按类型筛选；
        # 只有 Bangumi 的原名明确是另一部作品（唯一对上别的作品、却和这部的任何标题都不一样）时才改用按原名对应
        # （例如“虹ヶ咲 2期”被配到了 MAL 的“1期总集篇”）
        subject = subjects.get(bangumi) or {}
        by_title = match_title(index_by_title, [subject.get("name")], year_of(subject.get("date")),
                               BGM_ANIME_FORMATS.get(subject.get("platform")))
        # 用 bangumi-data 的人工对应作答案检验过：按原名对应约 99.7% 准确，但它和 bangumi-data 不一致时只有一半是 bangumi-data 错了。
        # 所以只在三个条件同时成立时改用：改用的作品有 MAL ID（AniList 把剧场版前后篇分开而 MAL 合在一起时不换）、
        # 开播年份与 Bangumi 完全相同、它的格式符合 Bangumi 的分类而 bangumi-data 配的那部不符合
        # 或者：bangumi-data 配的那部标题和原名差得很远（相似度不到 0.5），而同一年有标题完全相同的唯一作品
        primary = BGM_PRIMARY_FORMATS.get(subject.get("platform"), set())
        format_wrong = work_format.get(by_title) in primary and work_format.get(index) not in primary
        title_wrong = title_similarity(subject.get("name"), titles_of[index]) < 0.5
        if (by_title is not None and by_title != index and works.rows[by_title][1]
                and title_key(subject.get("name")) not in titles_of[index]
                and work_year.get(by_title) == year_of(subject.get("date"))
                and (format_wrong or title_wrong)):
            overrides.append((subject.get("name"), works.rows[index][1], works.rows[by_title][1]))
            index = by_title
            moved_bangumi[bangumi] = index
            rejected += 1
        by_work[index].append(bangumi)
    # TMDB：bangumi-data 也给出了 TMDB 的条目（“tv/123”“tv/123/season/2”“movie/123”）。
    # bangumi-data 的 MAL ID 偶尔记错，会把剧场版的 TMDB 带到 TV 版上：TV、TV_SHORT、ONA 只接受 TMDB 的剧集，
    # MOVIE 只接受 TMDB 的电影，OVA 与特别篇两种都可能
    def tmdb_kind_ok(row, tmdb):
        media = anilist.get(row[2]) if row[2] else None
        mal_format = media.get("format") if media else mal_info.get(row[1], (None,))[0]
        kind = tmdb.split("/")[0]
        if mal_format in ("TV", "TV_SHORT", "ONA"):
            return kind == "tv"
        if mal_format == "MOVIE":
            return kind == "movie"
        return True

    tmdb_count = tmdb_rejected = 0
    for item in data["items"]:
        sites = {site["site"]: site.get("id") for site in item.get("sites", [])}
        tmdb, mal = sites.get("tmdb"), sites.get("mal")
        if not tmdb or not mal or not re.match(r"^(tv/\d+(/season/\d+)?|movie/\d+)$", tmdb):
            continue
        try:
            index = works.find("myAnimeList", int(mal))
            # 上面因为 MAL ID 记错而改了对应的 Bangumi 条目，TMDB 也是这一部的（例如“虹ヶ咲 2期”的 TMDB 第 2 季
            # 不能留在 MAL 的“1期总集篇”上）
            index = moved_bangumi.get(int(sites.get("bangumi") or 0), index)
        except ValueError:
            continue
        if index is not None and works.rows[index][5] is None:
            if not tmdb_kind_ok(works.rows[index], tmdb):
                tmdb_rejected += 1
                continue
            works.rows[index][5] = tmdb
            tmdb_count += 1
    # Wikidata（CC0）上的 MAL 与 TMDB 对应：只用一个 TMDB 条目只对应一部 MAL 作品的（整个系列一个条目时不知道是哪一季）
    wikidata_count = 0
    wikidata_pairs = collections.defaultdict(set)
    for name, kind in (("wikidata-tmdb-tv.json", "tv"), ("wikidata-tmdb-movie.json", "movie")):
        path = directory / name
        if not path.exists():
            continue
        for binding in json.load(open(path))["results"]["bindings"]:
            try:
                wikidata_pairs[f"{kind}/{int(binding['x']['value'])}"].add(int(binding["mal"]["value"]))
            except (KeyError, ValueError):
                continue
    for tmdb, mals in wikidata_pairs.items():
        if len(mals) != 1:
            continue
        index = works.find("myAnimeList", next(iter(mals)))
        if index is not None and works.rows[index][5] is None and tmdb_kind_ok(works.rows[index], tmdb):
            works.rows[index][5] = tmdb
            wikidata_count += 1
    # bangumi-data 常把整个系列的 TMDB 条目配到几部 MAL 作品上（ななみちゃん 六个系列、涼宮ハルヒ 2006 与 2009、
    # 正篇和它的特别篇）。几部作品都写同一个 TMDB 条目会互相覆盖：只留一部写入（TV 优先、其次最早的），
    # 其余记为“在 TMDB 上没有单独的条目”，和第二季以后一样不写入、也不算找不到
    format_rank = {"TV": 0, "MOVIE": 0, "TV_SHORT": 1, "ONA": 2, "OVA": 3, "SPECIAL": 4}
    shared = collections.defaultdict(list)
    for index, row in enumerate(works.rows):
        if row[5]:
            parts = row[5].split("/")
            if len(parts) == 2 or parts[3] == "1":
                shared["/".join(parts[:2])].append(index)
    for tmdb, indexes in shared.items():
        if len(indexes) < 2:
            continue
        def rank(index):
            row = works.rows[index]
            media = anilist.get(row[2]) if row[2] else None
            fmt = media.get("format") if media else mal_info.get(row[1], (None,))[0]
            year = year_of(media.get("startDate")) if media else mal_info.get(row[1], (None, None))[1]
            return (format_rank.get(fmt, 5), year or 9999, row[1] or 10 ** 9)
        for index in sorted(indexes, key=rank)[1:]:
            works.tmdb_no_write.add(index)
    stats["动画：TMDB对应（bangumi-data）"] = tmdb_count
    stats["动画：共用TMDB条目、不写入TMDB的作品"] = len(works.tmdb_no_write)
    stats["动画：TMDB类型不符未采用"] = tmdb_rejected
    stats["动画：TMDB对应（Wikidata补充）"] = wikidata_count
    reassigned = 0
    for index, bangumis in by_work.items():
        mal_year = year_of((anilist_by_mal.get(works.rows[index][1]) or {}).get("startDate"))
        bangumis.sort(key=lambda b: (year_of((subjects.get(b) or {}).get("date")) != mal_year, b))
        for position, bangumi in enumerate(bangumis):
            # bangumi-data 把几个 Bangumi 条目配到同一部 MAL 作品时，第一个以外的先找同一年、标题完全相同的另一部 MAL 作品
            # （例如“進撃の巨人 The Final Season Part.2”在 MAL 上有单独的条目），找不到才作为附属条目
            if position > 0:
                subject = subjects.get(bangumi) or {}
                other = exact_year_match(index_by_title, subject.get("name"), year_of(subject.get("date")),
                                         BGM_ANIME_FORMATS.get(subject.get("platform")))
                if other is not None and other != index and works.rows[other][1] and works.rows[other][4] is None:
                    works.set_bangumi(other, bangumi)
                    reassigned += 1
                    continue
            works.set_bangumi(index, bangumi)
    stats["动画：bangumi-data多对一改到单独的MAL条目"] = reassigned
    # 人工校正
    for bangumi, mal in corrections.items():
        if mal is None:
            works.owner[("bangumi", str(bangumi))] = None  # 占位：不对应任何作品，也不再按原名对应
            continue
        index = works.find("myAnimeList", mal)
        if index is not None:
            works.set_bangumi(index, int(bangumi))
    stats["动画：人工校正"] = len(corrections)
    stats["动画：bangumi-data对应"] = sum(len(v) for v in by_work.values())
    stats["动画：bangumi-data改用原名对应"] = rejected
    for name, before, after in overrides:
        print(f"  改用：{name}（bangumi-data MAL {before} → MAL {after}）")

    # 4. 其余 Bangumi 条目按原名、年份、类型离线对应
    index_by_title = title_index(entries)
    matched = 0
    for bangumi, subject in subjects.items():
        if ("bangumi", str(bangumi)) in works.owner:
            continue
        index = match_title(index_by_title, [subject["name"]], year_of(subject.get("date")), BGM_ANIME_FORMATS.get(subject.get("platform")))
        if index is not None:
            works.set_bangumi(index, bangumi)
            matched += 1
    stats["动画：Bangumi按原名对应"] = matched

    # 不再把对不上的 Bangumi OVA 并入正篇：用 Wikidata 检验，这样并入的有一半其实在 MAL 上有单独的条目（例如 OAD），
    # 并入会把它的记录算到正篇上。对不上的留给手动匹配和后台校准
    stats["动画：Bangumi动画条目总数"] = len(subjects)
    stats["动画：Bangumi已对应"] = sum(1 for b in subjects if ("bangumi", str(b)) in works.owner)
    # 系列：AniList 的续作、前作关系连起来的动画（各季、续篇剧场版），搜索页把它们叠在一起
    parent = {}

    def find(x):
        while parent.get(x, x) != x:
            parent[x] = parent.get(parent[x], parent[x])
            x = parent[x]
        return x

    for media in anilist.values():
        a = works.find("aniList", media["id"])
        if a is None or media.get("format") == "MUSIC":
            continue
        for edge in (media.get("relations") or {}).get("edges", []):
            node = edge["node"]
            # 只按续作、前作合并（见 SERIES_RELATIONS）
            if edge["relationType"] not in SERIES_RELATIONS or node.get("type") != "ANIME" or node.get("format") == "MUSIC":
                continue
            b = works.find("aniList", node["id"])
            if b is None and node.get("idMal"):
                b = works.find("myAnimeList", node["idMal"])
            if b is None or b == a:
                continue
            ba, bb = works.rows[a][4], works.rows[b][4]
            if ba in subjects and bb in subjects and not any(
                kind in BANGUMI_SERIES_RELATIONS and other == y
                for x, y in ((ba, bb), (bb, ba)) for kind, other in relations.get(x, [])
            ):
                continue
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[max(ra, rb)] = min(ra, rb)
    members = collections.defaultdict(list)
    for index in set(parent) | set(parent.values()):
        members[find(index)].append(index)
    for root, group in members.items():
        if len(group) >= 2:
            for index in group:
                works.series[index] = min(group)
    stats["动画：系列"] = sum(1 for group in members.values() if len(group) >= 2)

    return works


# MARK: 漫画与轻小说

def build_manga(directory, stats):
    works = Works("manga")
    by_id = {media["id"]: media for media in read_jsonl(directory / "anilist-manga.jsonl")}
    resolve_duplicate_mal(by_id, {}, stats, "漫画")  # 没有 MAL 漫画的标题数据：重复的都不算对应到 MAL
    # AniList 没记 MAL ID 的漫画、轻小说：在 MAL 上按原名、年份、类型严格对上的结果（`anilist-mal-fill.json`，可选）
    if (directory / "anilist-mal-fill.json").exists():
        fill_missing_mal(by_id, json.load(open(directory / "anilist-mal-fill.json")), stats, "漫画")
    anilist = list(by_id.values())
    for media in anilist:
        mal = media.get("idMal")
        works.add(f"mal-manga:{mal}" if mal else f"aniList-manga:{media['id']}", mal=mal, anilist=media["id"])
    stats["漫画：作品"] = len(works.rows)

    subjects, relations = read_bangumi(directory, {1})
    series_of = collections.defaultdict(set)
    for subject_id, items in relations.items():
        for relation_type, related in items:
            if relation_type == BGM_BOOK_VOLUME:
                series_of[related].add(subject_id)
    # 一本单行本属于好几个系列（合订本、新装版等）时不知道该并入哪个，不并入
    volume_of = {volume: next(iter(series)) for volume, series in series_of.items() if len(series) == 1}
    stats["漫画：属于多个系列、未并入的单行本"] = sum(len(series) > 1 for series in series_of.values())

    entries = []
    for media in anilist:
        index = works.index[f"mal-manga:{media['idMal']}" if media.get("idMal") else f"aniList-manga:{media['id']}"]
        titles = [media["title"].get("native"), media["title"].get("romaji"), media["title"].get("english")] + (media.get("synonyms") or [])
        entries.append((index, [t for t in titles if t], year_of(media.get("startDate")), media.get("format")))
    index_by_title = title_index(entries)

    matched = 0
    for bangumi, subject in subjects.items():
        if bangumi in volume_of or subject.get("platform") not in BGM_BOOK_FORMATS:
            continue
        index = match_title(index_by_title, [subject["name"]], year_of(subject.get("date")), BGM_BOOK_FORMATS[subject["platform"]], later=3)
        if index is not None:
            works.set_bangumi(index, bangumi)
            matched += 1
    stats["漫画：Bangumi系列按原名对应"] = matched

    # 单行本：Bangumi 把有些续篇算作系列的一卷（攻殻機動隊2、失踪日記2），MAL 上却是单独的作品。
    # 先找标题完全相同、年份相符、还没有 Bangumi 主条目的另一部作品；找不到才并入系列
    volumes = separate = 0
    for volume, series in volume_of.items():
        index = works.owner.get(("bangumi", str(series)))
        if index is None or ("bangumi", str(volume)) in works.owner:
            continue
        subject = subjects.get(volume) or {}
        other = match_title(index_by_title, [subject.get("name")], year_of(subject.get("date")),
                            BGM_BOOK_FORMATS.get(subject.get("platform")), later=3)
        if (other is not None and other != index and works.rows[other][1] and works.rows[other][4] is None
                and title_key(subject.get("name")) != title_key((subjects.get(series) or {}).get("name"))):
            works.set_bangumi(other, volume)
            separate += 1
        elif works.attach("bangumi", volume, index):
            volumes += 1
    stats["漫画：并入系列的Bangumi单行本"] = volumes
    stats["漫画：在MAL上是单独作品的Bangumi单行本"] = separate
    return works


# MARK: 视觉小说

def build_visual_novels(directory, stats):
    """视觉小说以 VNDB 为准。返回 (主条目, 共用条目的归属, 补充的对应)：
    - 主条目：一部 VNDB 作品在 Bangumi 上有多个条目（不同发行版本）时，推送用哪一个；
    - 共用条目的归属：VNDB 把原版和重制版等分成两部、Bangumi 只有一个条目时，只有一部作品写入这个条目
      （VNDB 编号小的，通常是原版），否则两部作品会互相覆盖；
    - 补充的对应：对应文件里没有 Bangumi 条目、Wikidata 记着唯一一个条目且没有被别的作品用到的。"""
    connector = json.load(open(VN_CONNECTOR))
    groups = collections.defaultdict(list)
    for entry in connector["entries"]:
        if entry.get("vndb") and str(entry.get("bangumi", "")).isdigit():
            bangumi = int(entry["bangumi"])
            if bangumi not in groups[entry["vndb"].lower()]:
                groups[entry["vndb"].lower()].append(bangumi)
    subjects, relations = read_bangumi(directory, {4})

    owners = collections.defaultdict(set)
    for vndb, bangumis in groups.items():
        for bangumi in bangumis:
            owners[bangumi].add(vndb)
    shared = {bangumi: min(vndbs, key=lambda v: int(v[1:]) if v[1:].isdigit() else 10 ** 9)
              for bangumi, vndbs in owners.items() if len(vndbs) > 1}

    extra = {}
    path = directory / "wikidata-vndb-bangumi.json"
    if path.exists():
        candidates = collections.defaultdict(set)
        for binding in json.load(open(path))["results"]["bindings"]:
            try:
                candidates[binding["a"]["value"].lower()].add(int(binding["b"]["value"]))
            except (KeyError, ValueError):
                continue
        used = collections.Counter(b for values in candidates.values() for b in values)
        for vndb, bangumis in candidates.items():
            if vndb in groups or len(bangumis) != 1:
                continue
            bangumi = next(iter(bangumis))
            if bangumi in owners or used[bangumi] > 1 or bangumi not in subjects:
                continue
            extra[vndb] = bangumi

    main = {}
    for vndb, bangumis in groups.items():
        # 别的作品拥有的共用条目不能当主条目
        own = [b for b in bangumis if shared.get(b, vndb) == vndb]
        if len(bangumis) < 2 and own == bangumis:
            continue
        if not own:
            main[vndb] = 0  # 0：这部作品在 Bangumi 上没有自己的条目，不推送
            continue
        members = set(own)
        # 被组内其他条目标为“主版本”的
        marked = {related for b in own for t, related in relations.get(b, ()) if t == BGM_GAME_MAIN_VERSION and related in members}
        candidates = sorted(marked or members, key=lambda b: ((subjects.get(b) or {}).get("date") or "9999", b))
        main[vndb] = candidates[0]
    stats["视觉小说：有多个Bangumi条目的作品"] = sum(1 for v in main.values() if v)
    stats["视觉小说：被多部作品共用的Bangumi条目"] = len(shared)
    stats["视觉小说：从Wikidata补充的对应"] = len(extra)
    return main, shared, extra


COUNTRY_LANGUAGE = {"KR": "ko", "CN": "zh-Hans", "TW": "zh-Hant", "HK": "zh-Hant"}


def original_languages(path):
    """语言 → MAL ID 列表，只列出原名不是日文的作品。"""
    languages = collections.defaultdict(set)
    for media in read_jsonl(path):
        language = COUNTRY_LANGUAGE.get(media.get("countryOfOrigin"))
        if language and media.get("idMal"):
            languages[language].add(media["idMal"])
    return {language: sorted(ids) for language, ids in sorted(languages.items())}


def build(directory):
    stats = {}
    anime = build_anime(directory, stats)
    manga = build_manga(directory, stats)
    visual_novels, visual_novel_shared, visual_novel_extra = build_visual_novels(directory, stats)
    document = {
        "version": datetime.date.today().isoformat(),
        "anime": anime.json(),
        # 漫画只写入有 Bangumi 条目的作品：MAL 与 AniList 之间 App 会按 MAL ID 向 AniList 精确查询，不必预装 14 万条
        "manga": manga.json(keep=lambda row: row[4] is not None),
        # 原名不是日文的作品（AniList 的出品国家）：MAL 的 ja 字段放的是原名，中国、韩国作品其实是中文、韩文，App 按这里改正语言
        "originalLanguage": {"anime": original_languages(directory / "anilist-anime.jsonl"),
                             "manga": original_languages(directory / "anilist-manga.jsonl")},
        "visualNovels": visual_novels,
        "visualNovelSharedBangumi": {str(k): v for k, v in visual_novel_shared.items()},
        "visualNovelExtraBangumi": visual_novel_extra,
    }
    OUTPUT.write_text(json.dumps(document, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    for name, value in stats.items():
        print(f"{name}：{value}")
    print(f"写入 {OUTPUT.relative_to(ROOT)}（{OUTPUT.stat().st_size // 1024} KB）")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("download", "build"):
        print(__doc__)
        sys.exit(64)
    target = pathlib.Path(sys.argv[2]).resolve()
    download(target) if sys.argv[1] == "download" else build(target)
