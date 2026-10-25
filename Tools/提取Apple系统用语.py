#!/usr/bin/env python3
"""从本机 macOS“系统设置”读取 Apple 自己的界面字符串，按 PaperVN 支持的七种语言对齐，用来核对术语表。

docs/Apple用语术语表.md 里的统计和多语言对照表就是用它生成的。系统更新后可以重新运行，看 Apple 的用词有没有变。
读到的字符串只用来核对，不提交到仓库。

用法：
  python3 Tools/提取Apple系统用语.py <输出目录>
    输出 <输出目录>/apple-strings.json（每条字符串的各语言译文）和 <输出目录>/常用词对照.md
  python3 Tools/提取Apple系统用语.py <输出目录> --compare PaperVN/Localizable.xcstrings
    另外列出 PaperVN 中与系统设置相同的简中字符串、但其他语言译文和 Apple 不一样的地方
"""

import collections
import json
import pathlib
import plistlib
import re
import sys

ROOTS = [
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


def extract():
    """{"文件|键": {语言: 译文}}，只保留有简体中文的字符串。"""
    rows = {}

    def add(file, language, table):
        for key, value in table.items():
            if isinstance(value, str):
                rows.setdefault(f"{file}|{key}", {})[language] = value

    for root in ROOTS:
        for path in pathlib.Path(root).rglob("*.loctable"):
            try:
                table = plistlib.loads(path.read_bytes())
            except Exception:
                continue
            for folder, language in LANGUAGES.items():
                if isinstance(table.get(folder), dict):
                    add(str(path), language, table[folder])
        for path in pathlib.Path(root).rglob("*.lproj/*.strings"):
            language = LANGUAGES.get(path.parent.name[:-len(".lproj")])
            if not language:
                continue
            try:
                table = plistlib.loads(path.read_bytes())
            except Exception:
                continue
            add(str(path.parent.parent / path.name), language, table)
    return {key: value for key, value in rows.items() if "zh-Hans" in value}


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
    """PaperVN 与系统设置相同的简中字符串里，其他语言译文不一样的。"""
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


def main():
    if len(sys.argv) not in (2, 4) or (len(sys.argv) == 4 and sys.argv[2] != "--compare"):
        print(__doc__)
        sys.exit(64)
    output = pathlib.Path(sys.argv[1])
    output.mkdir(parents=True, exist_ok=True)
    rows = extract()
    (output / "apple-strings.json").write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
    coverage = collections.Counter(language for value in rows.values() for language in value)
    print(f"{len(rows)} 条字符串：" + "，".join(f"{language} {count}" for language, count in coverage.items()))
    lines = ["| 简体中文 | 繁体中文 | English | 日本語 | 한국어 | Deutsch | Polski | 次数 |",
             "|---|---|---|---|---|---|---|---|"]
    for text, count, translated in common_terms(rows):
        cells = " | ".join(translated.get(language, "").replace("|", "\\|") for language in OTHERS)
        lines.append(f"| {text} | {cells} | {count} |")
    (output / "常用词对照.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    if len(sys.argv) == 4:
        compare(rows, sys.argv[3])


if __name__ == "__main__":
    main()
