#!/usr/bin/env python3
"""提取 Apple 自己的界面字符串并存档，按 PaperVN 支持的七种语言对齐，用来核对术语表。

来源有两个：
  ios  Xcode 装的最新 iOS 模拟器运行时：所有系统 App 与框架，和 iPhone 上的本地化文件相同
  mac  本机 macOS 的“系统设置”
提取一次存进数据目录（默认是仓库外的 /Volumes/项目/PaperVN/Apple系统字符串/），之后的统计、查找、对照都直接读存档，
不用重新读系统文件。系统或 Xcode 运行时更新后再运行“提取”。读到的字符串只用来核对，不提交到仓库。
docs/Apple用语术语表.md 里的统计和多语言对照表就是用它生成的。

用法：
  python3 Tools/提取Apple系统用语.py 提取 [--来源 ios|mac] [--runtime "<…>/iOS 27.1.simruntime"]
    重新读取系统文件并存档（默认两个来源都提取；iOS 默认用版本最高的运行时）
  python3 Tools/提取Apple系统用语.py 统计 <输出目录>
    每个来源输出 <输出目录>/常用词对照-<来源>.md
  python3 Tools/提取Apple系统用语.py 查找 <正则> [<正则> …] [--语言 zh-Hans] [--例子 5]
    每个来源中匹配的不重复字符串数和例子，用来比较两种写法哪个更常用
  python3 Tools/提取Apple系统用语.py 对照 PaperVN/Localizable.xcstrings
    PaperVN 中与 Apple 相同的简中字符串、但其他语言译文和 Apple 不一样的地方
所有命令都可以加 --数据 <目录> 换数据目录。
"""

import argparse
import collections
import datetime
import gzip
import json
import pathlib
import platform
import plistlib
import re
import sys

数据目录 = pathlib.Path(__file__).resolve().parents[2] / "Apple系统字符串"
来源 = ["ios", "mac"]
MAC_ROOTS = [
    "/System/Applications/System Settings.app",
    "/System/Library/ExtensionKit",
    "/System/Library/PreferencePanes",
]
# 系统里的语言目录名 → PaperVN 的语言代码
LANGUAGES = {
    "zh_CN": "zh-Hans", "zh-Hans": "zh-Hans", "zh_TW": "zh-Hant", "zh-Hant": "zh-Hant",
    "en": "en", "English": "en", "ja": "ja", "Japanese": "ja", "ko": "ko",
    "de": "de", "German": "de", "pl": "pl",
}
OTHERS = ["zh-Hant", "en", "ja", "ko", "de", "pl"]


def latest_ios_runtime():
    """/Library/Developer/CoreSimulator 里版本最高的 iOS 运行时。"""
    runtimes = pathlib.Path("/Library/Developer/CoreSimulator/Volumes").glob(
        "*/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS *.simruntime")

    def version(path):
        return tuple(int(part) for part in re.findall(r"\d+", path.stem))
    return max(runtimes, key=version, default=None)


def extract(roots, base):
    """{"文件|键": {语言: 译文}}，只保留有简体中文的字符串。文件写成相对 `base` 的路径。"""
    rows = {}

    def add(file, language, table):
        name = str(pathlib.Path(file).relative_to(base))
        for key, value in table.items():
            if isinstance(value, str):
                rows.setdefault(f"{name}|{key}", {})[language] = value

    for root in roots:
        for path in pathlib.Path(root).rglob("*.loctable"):
            try:
                table = plistlib.loads(path.read_bytes())
            except Exception:
                continue
            for folder, language in LANGUAGES.items():
                if isinstance(table.get(folder), dict):
                    add(path, language, table[folder])
        for path in pathlib.Path(root).rglob("*.lproj/*.strings"):
            language = LANGUAGES.get(path.parent.name[:-len(".lproj")])
            if not language:
                continue
            try:
                table = plistlib.loads(path.read_bytes())
            except Exception:
                continue
            add(path.parent.parent / path.name, language, table)
    return {key: value for key, value in rows.items() if "zh-Hans" in value}


def 存档(data, name, rows, info):
    data.mkdir(parents=True, exist_ok=True)
    with gzip.open(data / f"{name}.json.gz", "wt", encoding="utf-8") as file:
        json.dump(rows, file, ensure_ascii=False)
    sources = data / "来源.json"
    infos = json.loads(sources.read_text(encoding="utf-8")) if sources.exists() else {}
    infos[name] = info
    sources.write_text(json.dumps(infos, ensure_ascii=False, indent=2), encoding="utf-8")


def 读取(data):
    """{来源: rows}，只含已经存档的来源。"""
    result = {}
    for name in 来源:
        path = data / f"{name}.json.gz"
        if path.exists():
            with gzip.open(path, "rt", encoding="utf-8") as file:
                result[name] = json.load(file)
    if not result:
        sys.exit(f"{data} 里还没有存档，先运行“提取”。")
    return result


def common_terms(rows, minimum=4):
    """整条字符串就是一个词语的（按钮、标签、状态），按简体中文分组，取各语言最常见的译法。"""
    counts = collections.Counter()
    translations = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    for value in rows.values():
        text = value["zh-Hans"].strip()
        if not text or len(text) > 8 or "%" in text or not re.search(r"[一-鿿]", text):
            continue
        counts[text] += 1
        for language in OTHERS:
            if language in value:
                translations[text][language][value[language].strip()] += 1
    return [
        (text, count, {language: translations[text][language].most_common(1)[0][0]
                       for language in OTHERS if translations[text][language]})
        for text, count in counts.most_common() if count >= minimum
    ]


def compare(rows, catalog_path):
    """PaperVN 与 Apple 相同的简中字符串里，其他语言译文不一样的。"""
    apple = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
    for value in rows.values():
        for language in OTHERS:
            if language in value:
                apple[value["zh-Hans"].strip()][language][value[language].strip()] += 1
    catalog = json.loads(pathlib.Path(catalog_path).read_text(encoding="utf-8"))["strings"]
    for key, entry in sorted(catalog.items()):
        if key not in apple:
            continue
        differences = []
        for language in OTHERS:
            ours = entry.get("localizations", {}).get(language, {}).get("stringUnit", {}).get("value")
            theirs = apple[key][language].most_common(1)[0][0] if apple[key][language] else None
            if ours and theirs and ours != theirs:
                differences.append(f"{language} PaperVN“{ours}” Apple“{theirs}”")
        if differences:
            print(f"{key}：" + "；".join(differences))


def 提取(arguments):
    names = [arguments.来源] if arguments.来源 else 来源
    for name in names:
        if name == "ios":
            runtime = pathlib.Path(arguments.runtime) if arguments.runtime else latest_ios_runtime()
            if not runtime:
                print("找不到 iOS 模拟器运行时，先在 Xcode→“设置”→“组件”中下载。跳过 iOS。")
                continue
            base = runtime / "Contents/Resources/RuntimeRoot"
            rows = extract([base / "Applications", base / "System/Library"], base)
            info = {"系统": runtime.stem}
        else:
            rows = extract(MAC_ROOTS, "/")
            info = {"系统": f"macOS {platform.mac_ver()[0]}"}
        info |= {"提取时间": datetime.datetime.now().isoformat(timespec="seconds"), "字符串数": len(rows)}
        存档(arguments.数据, name, rows, info)
        coverage = collections.Counter(language for value in rows.values() for language in value)
        print(f"{name}（{info['系统']}）{len(rows)} 条：" + "，".join(f"{k} {v}" for k, v in coverage.items()))


def 统计(arguments):
    output = pathlib.Path(arguments.输出目录)
    output.mkdir(parents=True, exist_ok=True)
    for name, rows in 读取(arguments.数据).items():
        lines = ["| 简体中文 | 繁体中文 | English | 日本語 | 한국어 | Deutsch | Polski | 次数 |",
                 "|---|---|---|---|---|---|---|---|"]
        for text, count, translated in common_terms(rows):
            cells = " | ".join(translated.get(language, "").replace("|", "\\|") for language in OTHERS)
            lines.append(f"| {text} | {cells} | {count} |")
        (output / f"常用词对照-{name}.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"{output / f'常用词对照-{name}.md'}：{len(lines) - 2} 个词语")


def 查找(arguments):
    datasets = 读取(arguments.数据)
    for pattern in arguments.正则:
        regex = re.compile(pattern)
        for name, rows in datasets.items():
            texts = sorted({value[arguments.语言] for value in rows.values()
                            if arguments.语言 in value and regex.search(value[arguments.语言])}, key=len)
            print(f"{pattern}  {name} {len(texts)}")
            for text in texts[:arguments.例子]:
                print("    " + text.replace("\n", " ")[:100])


def 对照(arguments):
    for name, rows in 读取(arguments.数据).items():
        print(f"# {name}")
        compare(rows, arguments.catalog)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--数据", type=pathlib.Path, default=数据目录)
    commands = parser.add_subparsers(dest="命令", required=True)
    command = commands.add_parser("提取")
    command.add_argument("--来源", choices=来源)
    command.add_argument("--runtime")
    command.set_defaults(run=提取)
    command = commands.add_parser("统计")
    command.add_argument("输出目录")
    command.set_defaults(run=统计)
    command = commands.add_parser("查找")
    command.add_argument("正则", nargs="+")
    command.add_argument("--语言", default="zh-Hans")
    command.add_argument("--例子", type=int, default=3)
    command.set_defaults(run=查找)
    command = commands.add_parser("对照")
    command.add_argument("catalog")
    command.set_defaults(run=对照)
    arguments = parser.parse_args()
    arguments.run(arguments)


if __name__ == "__main__":
    main()
