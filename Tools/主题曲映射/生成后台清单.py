#!/usr/bin/env python3
"""生成管理后台“主题曲”页的完整清单（theme-song-catalog.json）：映射里的每一首歌和还没匹配的歌都列出来。

来源：生成工具写的待人工处理清单（信息最全，含自动匹配候选）、MAL 主题曲缓存解析结果（片头曲、片尾曲的歌名歌手）、
进度里的插入曲和作品名。只放歌曲信息；匹配结果在服务器的映射里，后台读取时再合并。

用法：python3 -I 生成后台清单.py <待人工处理清单> <MAL解析.jsonl> <映射.json> <输出>
"""
import json, pathlib, sys

APP = pathlib.Path(__file__).resolve().parent.parent.parent
misses_path, mal_path, map_path, output = sys.argv[1:5]
progress = json.load(open(APP / 'Tools/主题曲映射/进度/进度.json'))['作品']
mapping = json.load(open(map_path))
work_map = json.load(open(APP / 'PaperVN/Resources/PaperVNWorkMap.json'))
ranks = {}
for index, row in enumerate(work_map['anime']['works']):
    if len(row) > 1 and isinstance(row[1], int) and row[1] not in ranks:
        ranks[row[1]] = index + 1

FIELDS = ['key', 'malID', 'anime', 'rank', 'kind', 'number', 'title', 'originalTitle', 'artist', 'originalArtist', 'artistJapanese', 'episodes', 'text', 'autoMatch']
items = {}
works = {}
def anime_name(mal_id):
    return (progress.get(str(mal_id)) or {}).get('作品名')

# MAL 片头曲、片尾曲
for line in open(mal_path):
    row = json.loads(line)
    row['rank'] = ranks.get(row['malID'])
    row['anime'] = anime_name(row['malID']) or row.get('anime')
    items[row['key']] = row
# 进度里的插入曲（AnisongDB，罗马字）
for mal_id, work in progress.items():
    for entry in work.get('插入曲') or []:
        key = str(-entry['编号'])
        items.setdefault(key, {'key': key, 'malID': int(mal_id), 'anime': work.get('作品名'), 'rank': ranks.get(int(mal_id)), 'kind': 'in', 'title': entry['歌名'], 'artist': entry['歌手']})
    if work.get('Bangumi音乐'):
        works[mal_id] = [{'relation': x['关系'], 'name': x['名称']} for x in work['Bangumi音乐']]
# 待人工处理清单信息最全，覆盖上面的
for item in json.load(open(misses_path))['items']:
    merged = dict(items.get(item['key'], {}))
    merged.update({k: v for k, v in item.items() if k in FIELDS and v is not None})
    items[item['key']] = merged
    if item.get('bangumiMusic') and str(item['malID']) not in works:
        works[str(item['malID'])] = item['bangumiMusic']

# 映射里有、但上面都没有信息的歌（很少）：用 Apple Music 的写法，作品从插入曲列表找
insert_work = {str(i): int(w) for w, ids in mapping['inserts'].items() for i in ids}
missing = 0
for key, value in mapping['songs'].items():
    if key in items:
        continue
    missing += 1
    mal_id = insert_work.get(key)
    items[key] = {'key': key, 'malID': mal_id, 'anime': anime_name(mal_id) if mal_id else None, 'rank': ranks.get(mal_id),
                  'kind': 'in' if int(key) < 0 else 'op', 'title': value[2] if isinstance(value, list) else key,
                  'artist': value[3] if isinstance(value, list) else ''}

# 不在映射里的歌：只列待人工处理清单里有的（还没匹配的）
pending = {item['key'] for item in json.load(open(misses_path))['items']}
listed = [{k: v for k, v in item.items() if k in FIELDS and v is not None} for key, item in items.items() if key in mapping['songs'] or key in pending]
listed.sort(key=lambda x: (x.get('rank') or 10**9, int(x['key'])))
json.dump({'version': mapping['version'], 'items': listed, 'works': works}, open(output, 'w'), ensure_ascii=False, separators=(',', ':'))
print(f"{len(listed)} 首（映射 {len(mapping['songs'])} 首，其中没有信息的 {missing} 首），{len(works)} 部作品有Bangumi音乐")
