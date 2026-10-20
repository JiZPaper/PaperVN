#!/usr/bin/env python3
"""审计预装的作品映射 PaperVNWorkMap.json：每次重新生成映射后运行，检查所有平台之间的对应。

检查内容：
  1. 数据源本身：arm 与 AniList、Wikidata 是否一致；AniList 重复的 MAL ID；bangumi-data 的可疑对应；
     视觉小说对应文件里被多部作品共用的 Bangumi 条目。
  2. 映射结果：同一个平台条目是否被对到多部作品；每一对 Bangumi 对应的标题、年份、类型是否合理（逐对检查，不抽样）。
  3. 覆盖率：每个平台按作品类型能对上的比例。
  4. 准确率：以 bangumi-data 的人工对应为答案的自测；对照 Wikidata（Bangumi、MAL、TMDB、VNDB）；
     对照 AniList 自己记的 MAL ID。

用法：python3 Tools/审计作品映射.py <数据目录>（与 构建作品映射.py 相同的数据目录，需要先 download）
可疑的对应会写进 <数据目录>/audit/，逐条核对后把结论写回生成规则或人工校准表。
"""

import collections
import difflib
import importlib.util
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAP = ROOT / "PaperVN" / "Resources" / "PaperVNWorkMap.json"
VN_CONNECTOR = ROOT / "PaperVN" / "Resources" / "vndb_id_connector.json"

spec = importlib.util.spec_from_file_location("builder", ROOT / "Tools" / "构建作品映射.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def percent(a, b):
    return f"{a / b:.2%}" if b else "—"


def load_wikidata(path, a, b, convert=int):
    pairs = collections.defaultdict(set)
    if not path.exists():
        return pairs
    for binding in json.load(open(path))["results"]["bindings"]:
        try:
            pairs[convert(binding[a]["value"])].add(convert(binding[b]["value"]))
        except (KeyError, ValueError):
            continue
    return pairs


class Map:
    """把映射文件读成便于查询的结构（与 App 的 作品映射.swift 相同的规则）。"""

    def __init__(self, document, kind):
        group = document[kind]
        self.rows = []
        for row in group["works"]:
            mal, ani = row[1], row[2]
            key = row[0] or (f"mal-{kind}:{mal}" if mal else f"aniList-{kind}:{ani}")
            self.rows.append([key] + row[1:] + [None] * (6 - len(row)))
        self.main = collections.defaultdict(list)       # (平台, ID) → [行号]
        for index, row in enumerate(self.rows):
            for platform, value in (("myAnimeList", row[1]), ("aniList", row[2]), ("annict", row[3]), ("bangumi", row[4])):
                if value is not None:
                    self.main[(platform, value)].append(index)
        self.attached = collections.defaultdict(list)   # (平台, ID) → [行号]
        for platform, values in group["attached"].items():
            for offset in range(0, len(values), 2):
                self.attached[(platform, values[offset])].append(values[offset + 1])
        self.annict_folded = set(group.get("annictFolded") or [])
        self.tmdb_no_write = set(group.get("tmdbNoWrite") or [])

    def bangumi(self, bangumi):
        """Bangumi 条目对应的行号与是否为附属。"""
        if ("bangumi", bangumi) in self.main:
            return self.main[("bangumi", bangumi)][0], False
        if ("bangumi", bangumi) in self.attached:
            return self.attached[("bangumi", bangumi)][0], True
        return None, None


def main(directory):
    directory = pathlib.Path(directory).resolve()
    out = directory / "audit"
    out.mkdir(exist_ok=True)
    document = json.load(open(MAP))
    anime, manga = Map(document, "anime"), Map(document, "manga")
    report = []

    def section(title):
        report.append(f"\n## {title}")

    def line(text):
        report.append(text)

    def dump(name, rows):
        with open(out / f"{name}.json", "w") as file:
            json.dump(rows, file, ensure_ascii=False, indent=1)
        return len(rows)

    # MARK: 读取数据
    arm = json.load(open(directory / "arm.json"))
    anilist_anime = {m["id"]: m for m in builder.read_jsonl(directory / "anilist-anime.jsonl")}
    anilist_manga = {m["id"]: m for m in builder.read_jsonl(directory / "anilist-manga.jsonl")}
    mal_to_anilist = collections.defaultdict(set)
    for media in anilist_anime.values():
        if media.get("idMal"):
            mal_to_anilist[media["idMal"]].add(media["id"])
    manga_mal_to_anilist = collections.defaultdict(set)
    for media in anilist_manga.values():
        if media.get("idMal"):
            manga_mal_to_anilist[media["idMal"]].add(media["id"])
    mal_info = {}
    for entry in json.load(open(directory / "aod.json"))["data"]:
        for url in entry["sources"]:
            match = re.match(r"https://myanimelist\.net/anime/(\d+)$", url)
            if match:
                mal_info[int(match.group(1))] = (entry["type"], (entry.get("animeSeason") or {}).get("year"),
                                                 [entry["title"]] + (entry.get("synonyms") or []))
    subjects = {}
    for subject in builder.read_jsonl(directory / "bgm" / "subject.jsonlines"):
        if subject["type"] in (1, 2, 4):
            subjects[subject["id"]] = subject
    bangumi_data = json.load(open(directory / "bangumi-data.json"))["items"]

    def titles_of(kind, row):
        """一行作品的所有标题、年份、格式（AniList 优先，没有时用 anime-offline-database）。"""
        source = anilist_anime if kind == "anime" else anilist_manga
        media = source.get(row[2]) if row[2] else None
        if media:
            titles = [media["title"].get("native"), media["title"].get("romaji"), media["title"].get("english")] + (media.get("synonyms") or [])
            return [t for t in titles if t], builder.year_of(media.get("startDate")), media.get("format")
        if kind == "anime" and row[1] in mal_info:
            fmt, year, titles = mal_info[row[1]]
            return titles, year, fmt
        return [], None, None

    def similarity(name, titles):
        key = builder.title_key(name)
        if not key or not titles:
            return 0.0
        return max(difflib.SequenceMatcher(None, key, builder.title_key(t)).ratio() for t in titles)

    # MARK: 1. 数据源
    section("1. 数据源")
    annict_dupes = collections.Counter(r["annict_id"] for r in arm if r.get("annict_id"))
    mal_dupes = collections.Counter(r["mal_id"] for r in arm if r.get("annict_id") and r.get("mal_id"))
    line(f"- arm：Annict 作品 {len(annict_dupes)} 部；一部 Annict 对多部 MAL {sum(v > 1 for v in annict_dupes.values())}，"
         f"一部 MAL 对多部 Annict {sum(v > 1 for v in mal_dupes.values())}")
    agree = disagree = 0
    for row in arm:
        if row.get("annict_id") and row.get("mal_id") and row.get("anilist_id") and row["mal_id"] in mal_to_anilist:
            if row["anilist_id"] in mal_to_anilist[row["mal_id"]]:
                agree += 1
            else:
                disagree += 1
    line(f"- arm 的 MAL↔AniList 与 AniList 自己的 idMal：一致 {agree}，不一致 {disagree}（{percent(agree, agree + disagree)}）")
    syobocal = load_wikidata(directory / "wikidata-mal-syobocal.json", "mal", "x")
    agree, bad = 0, []
    for row in arm:
        if row.get("annict_id") and row.get("mal_id") and row.get("syobocal_tid") and row["mal_id"] in syobocal:
            if row["syobocal_tid"] in syobocal[row["mal_id"]]:
                agree += 1
            else:
                bad.append({"mal": row["mal_id"], "annict": row["annict_id"], "arm_syobocal": row["syobocal_tid"],
                            "wikidata_syobocal": sorted(syobocal[row["mal_id"]]), "mal_titles": (mal_info.get(row["mal_id"]) or (None, None, []))[2][:3]})
    line(f"- arm 的 MAL↔しょぼいカレンダー 与 Wikidata：一致 {agree}，不一致 {len(bad)}（{percent(agree, agree + len(bad))}）"
         f" → audit/arm_syobocal.json（{dump('arm_syobocal', bad)} 条）")
    duplicates = {mal: sorted(ids) for mal, ids in mal_to_anilist.items() if len(ids) > 1}
    line(f"- AniList 上同一个 MAL ID 被多个条目使用：动画 {len(duplicates)}，漫画 {sum(len(v) > 1 for v in manga_mal_to_anilist.values())}")

    # bangumi-data：逐条检查标题、年份、类型
    suspicious = []
    for item in bangumi_data:
        sites = {s["site"]: s.get("id") for s in item.get("sites", [])}
        try:
            bangumi, mal = int(sites.get("bangumi") or 0), int(sites.get("mal") or 0)
        except ValueError:
            continue
        if not bangumi or not mal or bangumi not in subjects:
            continue
        index = anime.main.get(("myAnimeList", mal), [None])[0]
        if index is None:
            continue
        titles, year, fmt = titles_of("anime", anime.rows[index])
        subject = subjects[bangumi]
        bangumi_year = builder.year_of(subject.get("date"))
        score = similarity(subject["name"], titles + [item.get("title") or ""])
        if score < 0.5 or (year and bangumi_year and abs(year - bangumi_year) > 1):
            suspicious.append({"bangumi": bangumi, "name": subject["name"], "date": subject.get("date"), "platform": subject.get("platform"),
                               "mal": mal, "mal_titles": titles[:3], "mal_year": year, "mal_format": fmt, "similarity": round(score, 2)})
    line(f"- bangumi-data 中标题相差很大或年份相差超过一年的对应：{dump('bangumi_data_suspicious', suspicious)} 条 → audit/bangumi_data_suspicious.json")

    # 视觉小说对应文件
    connector = json.load(open(VN_CONNECTOR))["entries"]
    owners = collections.defaultdict(set)
    for entry in connector:
        if entry.get("vndb") and str(entry.get("bangumi", "")).isdigit():
            owners[int(entry["bangumi"])].add(entry["vndb"].lower())
    shared = {b: sorted(v) for b, v in owners.items() if len(v) > 1}
    line(f"- 视觉小说对应文件：Bangumi 条目 {len(owners)} 个，被多部 VNDB 作品共用的 {dump('vn_shared_bangumi', [{'bangumi': b, 'vndb': v, 'name': (subjects.get(b) or {}).get('name')} for b, v in shared.items()])} 个 → audit/vn_shared_bangumi.json")
    wikidata_vn = load_wikidata(directory / "wikidata-vndb-bangumi.json", "a", "b", convert=str)
    agree = disagree = missing = 0
    vn_bad = []
    by_vndb = collections.defaultdict(set)
    for b, vs in owners.items():
        for v in vs:
            by_vndb[v].add(b)
    for vndb, bangumis in wikidata_vn.items():
        ours = by_vndb.get(vndb.lower())
        if not ours:
            missing += 1
            continue
        if {int(b) for b in bangumis} & ours:
            agree += 1
        else:
            disagree += 1
            vn_bad.append({"vndb": vndb, "wikidata_bangumi": sorted(bangumis), "ours": sorted(ours)})
    line(f"- 视觉小说 VNDB↔Bangumi 对照 Wikidata：一致 {agree}，不一致 {disagree}（{percent(agree, agree + disagree)}），"
         f"文件里没有 {missing} → audit/vn_wikidata_disagree.json（{dump('vn_wikidata_disagree', vn_bad)} 条）")

    # MARK: 2. 映射结果
    section("2. 映射结果的一致性（逐条检查）")
    for name, table in (("动画", anime), ("漫画与轻小说", manga)):
        multi = {f"{p}:{v}": rows for (p, v), rows in table.main.items() if len(rows) > 1}
        both = [f"{p}:{v}" for (p, v) in table.attached if (p, v) in table.main]
        multi_attached = {f"{p}:{v}": rows for (p, v), rows in table.attached.items() if len(rows) > 1}
        line(f"- {name}：同一平台条目是多部作品的主条目 {len(multi)}；既是主条目又是附属 {len(both)}；附属于多部作品 {len(multi_attached)}")
    tmdb_bases = collections.defaultdict(list)
    for index, row in enumerate(anime.rows):
        if row[5] and index not in anime.tmdb_no_write:
            parts = row[5].split("/")
            if len(parts) == 2 or parts[3] == "1":
                tmdb_bases["/".join(parts[:2])].append(index)
    line(f"- 动画：共用一个 TMDB 条目、不写入 TMDB 的作品 {len(anime.tmdb_no_write)}")
    line(f"- 动画：同一个 TMDB 条目被多部作品当作第一季（会互相覆盖） {sum(len(v) > 1 for v in tmdb_bases.values())} → audit/tmdb_shared.json"
         f"（{dump('tmdb_shared', [{'tmdb': k, 'works': [anime.rows[i][0] for i in v]} for k, v in tmdb_bases.items() if len(v) > 1])} 条）")

    for kind, table in (("anime", anime), ("manga", manga)):
        flagged = []
        checked = 0
        for (platform, bangumi), rows in list(table.main.items()) + list(table.attached.items()):
            if platform != "bangumi" or bangumi not in subjects:
                continue
            subject = subjects[bangumi]
            if kind == "manga" and (platform, bangumi) in table.attached:
                continue  # 单行本的标题带卷号，单独检查
            row = table.rows[rows[0]]
            titles, year, fmt = titles_of(kind, row)
            if not titles:
                continue
            checked += 1
            score = similarity(subject["name"], titles)
            bangumi_year = builder.year_of(subject.get("date"))
            late = 3 if kind == "manga" else 1
            year_bad = year and bangumi_year and not (-1 <= bangumi_year - year <= late)
            if score < 0.6 or year_bad:
                flagged.append({"bangumi": bangumi, "name": subject["name"], "date": subject.get("date"), "platform": subject.get("platform"),
                                "work": row[0], "titles": titles[:3], "year": year, "format": fmt, "similarity": round(score, 2),
                                "attached": (platform, bangumi) in table.attached})
        line(f"- {('动画' if kind == 'anime' else '漫画与轻小说')}：逐条检查 Bangumi 对应 {checked} 对，标题相差很大或年份不合的 "
             f"{dump(f'{kind}_flagged', flagged)} 对 → audit/{kind}_flagged.json")

    # 单行本：系列没对上的、属于多个系列的
    volume_series = collections.defaultdict(set)
    for relation in builder.read_jsonl(directory / "bgm" / "subject-relations.jsonlines"):
        if relation["relation_type"] == builder.BGM_BOOK_VOLUME and relation["subject_id"] in subjects:
            volume_series[relation["related_subject_id"]].add(relation["subject_id"])
    unmapped_volumes = sum(1 for v in volume_series if ("bangumi", v) not in manga.attached and ("bangumi", v) not in manga.main)
    line(f"- 单行本：{len(volume_series)} 本，属于多个系列的 {sum(len(s) > 1 for s in volume_series.values())}，所属系列没对上的 {unmapped_volumes}")

    # MARK: 3. 覆盖率
    section("3. 覆盖率")
    by_mal = {row[1]: row for row in anime.rows if row[1]}
    line("| MAL 类型 | 作品数 | AniList | Annict | Bangumi | TMDB |")
    line("|---|---|---|---|---|---|")
    for fmt in ("TV", "MOVIE", "OVA", "ONA", "SPECIAL", None):
        mals = [m for m, info in mal_info.items() if fmt is None or info[0] == fmt]

        def cov(i):
            return percent(sum(1 for m in mals if m in by_mal and by_mal[m][i]), len(mals))
        line(f"| {fmt or '全部'} | {len(mals)} | {cov(2)} | {cov(3)} | {cov(4)} | {cov(5)} |")
    names = {0: "其他", 1: "TV", 2: "OVA", 3: "剧场版", 5: "WEB", 2006: "动态漫画", 1001: "漫画", 1002: "小说"}
    line("")
    line("| Bangumi 条目 | 已对应 / 总数 |")
    line("|---|---|")
    counts = collections.Counter()
    for bangumi, subject in subjects.items():
        if subject["type"] == 2:
            group, table = names.get(subject.get("platform"), "其他"), anime
        elif subject["type"] == 1 and subject.get("platform") in (1001, 1002):
            group = names[subject["platform"]] + ("单行本" if bangumi in volume_series else "")
            table = manga
        else:
            continue
        counts[(group, "total")] += 1
        if table.bangumi(bangumi)[0] is not None:
            counts[(group, "mapped")] += 1
    for group in ("TV", "OVA", "剧场版", "WEB", "其他", "动态漫画", "漫画", "漫画单行本", "小说", "小说单行本"):
        line(f"| {group} | {counts[(group, 'mapped')]} / {counts[(group, 'total')]}（{percent(counts[(group, 'mapped')], counts[(group, 'total')])}） |")

    # MARK: 4. 准确率
    section("4. 准确率")
    # 自测：只用按原名对应，答案是 bangumi-data
    entries = []
    for index, row in enumerate(anime.rows):
        titles, year, fmt = titles_of("anime", row)
        if titles:
            entries.append((index, titles, year, fmt))
    index_by_title = builder.title_index(entries)
    agree = disagree = missed = 0
    for item in bangumi_data:
        sites = {s["site"]: s.get("id") for s in item.get("sites", [])}
        try:
            bangumi, mal = int(sites.get("bangumi") or 0), int(sites.get("mal") or 0)
        except ValueError:
            continue
        if not bangumi or not mal or bangumi not in subjects or ("myAnimeList", mal) not in anime.main:
            continue
        subject = subjects[bangumi]
        got = builder.match_title(index_by_title, [subject["name"]], builder.year_of(subject.get("date")),
                                  builder.BGM_ANIME_FORMATS.get(subject.get("platform")))
        if got is None:
            missed += 1
        elif anime.rows[got][1] == mal:
            agree += 1
        else:
            disagree += 1
    line(f"- 按原名对应（以 bangumi-data 为答案）：对上 {percent(agree + disagree, agree + disagree + missed)}，"
         f"与答案一致 {agree}/{agree + disagree}（{percent(agree, agree + disagree)}）")

    for kind, table, path in (("anime", anime, "wikidata-bangumi-mal-anime.json"), ("manga", manga, "wikidata-bangumi-mal-manga.json")):
        allowed = load_wikidata(directory / path, "b", "m")
        stats = collections.Counter()
        bad = []
        bangumi_data_ids = set()
        if kind == "anime":
            for item in bangumi_data:
                sites = {s["site"]: s.get("id") for s in item.get("sites", [])}
                if str(sites.get("bangumi") or "").isdigit():
                    bangumi_data_ids.add(int(sites["bangumi"]))
        for bangumi, mals in allowed.items():
            if bangumi not in subjects:
                continue
            index, attached = table.bangumi(bangumi)
            source = "附属" if attached else ("bangumi-data" if bangumi in bangumi_data_ids else "按原名对应")
            if index is None:
                stats[("按原名对应" if bangumi not in bangumi_data_ids else "bangumi-data", "missing")] += 1
                continue
            if table.rows[index][1] in mals:
                stats[(source, "agree")] += 1
            else:
                stats[(source, "disagree")] += 1
                titles, year, fmt = titles_of(kind, table.rows[index])
                bad.append({"source": source, "bangumi": bangumi, "name": subjects[bangumi]["name"], "date": subjects[bangumi].get("date"),
                            "platform": subjects[bangumi].get("platform"), "wikidata_mal": sorted(mals), "ours": table.rows[index][1],
                            "ours_titles": titles[:2], "ours_year": year, "ours_format": fmt})
        for source in ("bangumi-data", "按原名对应", "附属"):
            a, d, m = stats[(source, "agree")], stats[(source, "disagree")], stats[(source, "missing")]
            if a + d + m:
                line(f"- {('动画' if kind == 'anime' else '漫画与轻小说')} Bangumi↔MAL（{source}）对照 Wikidata：一致 {a}/{a + d}（{percent(a, a + d)}），未对上 {m}")
        dump(f"{kind}_wikidata_disagree", bad)

    wikidata_tmdb = collections.defaultdict(set)
    for name, kind in (("wikidata-tmdb-tv.json", "tv"), ("wikidata-tmdb-movie.json", "movie")):
        for mal, ids in load_wikidata(directory / name, "mal", "x").items():
            wikidata_tmdb[mal].update(f"{kind}/{i}" for i in ids)
    a = d = 0
    for mal, ids in wikidata_tmdb.items():
        row = by_mal.get(mal)
        if row and row[5]:
            if "/".join(row[5].split("/")[:2]) in ids:
                a += 1
            else:
                d += 1
    line(f"- MAL↔TMDB 对照 Wikidata（含 Wikidata 补充的部分，偏高）：{a}/{a + d}（{percent(a, a + d)}）")
    a = d = 0
    for mal, row in by_mal.items():
        if row[2] and mal in mal_to_anilist:
            if row[2] in mal_to_anilist[mal]:
                a += 1
            else:
                d += 1
    line(f"- MAL↔AniList 对照 AniList 的 idMal（同一 MAL 有多个 AniList 条目时任一即可）：{a}/{a + d}（{percent(a, a + d)}）")

    text = "# 作品映射审计\n" + "\n".join(report) + "\n"
    (out / "report.md").write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(64)
    main(sys.argv[1])
