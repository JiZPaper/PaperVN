#!/usr/bin/env python3
"""按 docs/Apple用语术语表.md 检查 PaperVN 所有界面字符串（Localizable.xcstrings），七种语言都查。

规则来自术语表；术语表的依据是 Tools/提取Apple系统用语.py 存档的 iOS 与 macOS 系统字符串，以 iOS 为准。
每条规则写明“用这个”和“不用这个”，命中的都列出来，由人判断要不要改：
同一个字在别的意思里可能是对的（例如“存储空间”的“存储”），第三方网站的菜单路径也照原网站写。

用法：
  python3 Tools/检查Apple用语.py [PaperVN/Localizable.xcstrings] [--输出 报告.md] [--含过时]
    默认跳过已经不用的（stale）字符串；报告默认打印到终端
"""

import argparse
import collections
import json
import pathlib
import re

CJK = r"[一-鿿]"
JA = r"[ぁ-んァ-ヶ一-鿿]"
# 西文与数字，也包括格式占位符（%@、%1$@、%lld）
LATIN = r"(?:[A-Za-z0-9]|%(?:\d+\$)?(?:@|l{0,2}d))"

# (语言, 正则, 用这个, 说明)。正则命中的就是“不用这个”的写法。
RULES = [
    # 简体中文：用词
    ("zh-Hans", r"全部(?=[一-鿿])(?!使用|免费)", "所有（+名词）", "“全部”只单独作筛选项或作副词"),
    ("zh-Hans", r"点击|单击|点按", "轻点", ""),
    ("zh-Hans", r"长按", "按住", ""),
    ("zh-Hans", r"复制", "拷贝", ""),
    ("zh-Hans", r"存储(?!空间|设备|容量|位置|卡)", "保存", "iOS 里 Save 译作“保存”（579 条），“存储”只表示 storage"),
    ("zh-Hans", r"分享", "共享", ""),
    ("zh-Hans", r"开启|关掉", "打开／关闭", ""),
    ("zh-Hans", r"禁用", "停用", ""),
    ("zh-Hans", r"账号|帐户|帐号", "账户", ""),
    ("zh-Hans", r"登陆|登出|注销", "登录／退出／删除账户", ""),
    ("zh-Hans", r"载入", "加载", "iOS 用“加载”（355 条，“载入”1 条）"),
    ("zh-Hans", r"图片", "图像", ""),
    ("zh-Hans", r"(?<![应活])该(?=[一-鿿])|本(?=App|作品|条款|条目|应用)", "此", ""),
    ("zh-Hans", r"您", "你", ""),
    ("zh-Hans", r"是否.*？|确定要.*吗？", "要……吗？", "“确定要”是 Are you sure 的直译"),
    # “请求失败”“下载失败”“验证失败”和规定性质的“不能……”iOS 里都常见，不查
    ("zh-Hans", r"失败了|请再试一次|请重试一下", "无法……／请重试／请稍后再试", "iOS“请重试”187 处，“请再试一次”0 处（繁中相反：“請再試一次”157 处）"),
    ("zh-Hans", r"不可撤销|不能撤销", "此操作无法撤销。", ""),
    ("zh-Hans", r"标签栏|标签页栏", "Tab栏", ""),
    ("zh-Hans", r"播出表", "放送表", ""),
    ("zh-Hans", r"^(打开|关闭|启用|停用)(此功能)?后", "直接写效果", "说明文字不写“打开后……”"),
    # 简体中文：标点与格式
    ("zh-Hans", rf"{CJK} {LATIN}|{LATIN} {CJK}", "中文与西文、数字之间不加空格", ""),
    ("zh-Hans", r"\.\.\.", "…", ""),
    ("zh-Hans", r"”\s*(→|＞)\s*“|”\s+>\s*“|”\s*>\s+“", "“设置”>“搜索”", "iOS 简中路径用半角“>”、前后不加空格（1,633 处，“→”为 0）"),
    ("zh-Hans", rf"{CJK}[?!,:;]|[?!,:;]{CJK}", "全角标点", ""),
    ("zh-Hans", r"\"", "“”", ""),
    ("zh-Hans", r"(?<!^谢谢)！", "不用感叹号", "Today 里刻意的俏皮话除外；“谢谢！”iOS 里也有"),
    # 繁体中文
    ("zh-Hant", r"[“”]", "「」", ""),
    ("zh-Hant", r"…|\.\.\.", "⋯", ""),
    ("zh-Hant", r"加載|加载", "載入", ""),
    ("zh-Hant", r"保存", "儲存", ""),
    ("zh-Hant", r"帳戶|账户", "帳號", ""),
    ("zh-Hant", r"您", "你", ""),
    ("zh-Hant", rf"{CJK} {LATIN}|{LATIN} {CJK}", "中文与西文之间不加空格", ""),
    ("zh-Hant", r"」\s*(→|＞)\s*「|」\s+>\s*「|」\s*>\s+「", "「設定」>「搜尋」", "iOS 繁中路径用半角“>”、不加空格（1,576 处）"),
    ("zh-Hant", rf"{CJK}[?!,:;]", "全角标点", ""),
    # 日本語
    ("ja", r"[「」]", "“ ”", ""),
    ("ja", r"？", "半角?", ""),
    ("ja", r"ログイン|ログアウト", "サインイン／サインアウト", ""),
    ("ja", rf"{JA} {LATIN}|{LATIN} {JA}", "日文与西文之间不加空格", ""),
    ("ja", r"”\s*(→|>)\s*“", "“設定”＞“一般”", "iOS 日语路径用全角“＞”、不加空格（2,669 处）"),
    ("ja", r"\.\.\.", "…", ""),
    # 한국어
    ("ko", r"[“”]", "‘ ’", ""),
    ("ko", r"\.\.\.", "…", ""),
    # Deutsch
    ("de", r"„[^“”]*”|[“”][^„]*?[“”]", "„…“", ""),
    ("de", r"[^\s (]…", "前面加不换行空格：Optionen …", ""),
    ("de", r"\.\.\.", "…", ""),
    ("de", r"\"", "„…“", ""),
    # Polski
    ("pl", r"„[^“”]*“", "„…”", ""),
    ("pl", r"\s…", "省略号前不加空格", ""),
    ("pl", r"\.\.\.", "…", ""),
    ("pl", r"\"", "„…”", ""),
    # English
    ("en", r"\"", "“ ”", ""),
    ("en", r"\b(Log In|Log Out|Login|Logout)\b", "Sign In／Sign Out", ""),
    ("en", r"\.\.\.", "…", ""),
    ("en", r"”(→|>| → )“", "“Settings” > “Search”", "iOS 英文路径前后有空格"),
]

LANGUAGES = ["zh-Hans", "zh-Hant", "en", "ja", "ko", "de", "pl"]


def strings(catalog, include_stale):
    """[(键, 语言, 文字)]。简中没有单独译文时用键本身。"""
    result = []
    for key, entry in catalog["strings"].items():
        if entry.get("extractionState") == "stale" and not include_stale:
            continue
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations", {})
        for language in LANGUAGES:
            unit = localizations.get(language, {}).get("stringUnit")
            if unit:
                result.append((key, language, unit["value"]))
            elif language == "zh-Hans" and key.strip():
                result.append((key, language, key))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("catalog", nargs="?", default=str(pathlib.Path(__file__).resolve().parents[1] / "PaperVN/Localizable.xcstrings"))
    parser.add_argument("--输出")
    parser.add_argument("--含过时", action="store_true")
    arguments = parser.parse_args()
    catalog = json.loads(pathlib.Path(arguments.catalog).read_text(encoding="utf-8"))
    texts = strings(catalog, arguments.含过时)

    hits = collections.defaultdict(list)
    for language, pattern, use, note in RULES:
        regex = re.compile(pattern)
        for key, text_language, text in texts:
            if text_language == language and (match := regex.search(text)):
                hits[(language, pattern, use, note)].append((key, text, match.group(0)))

    lines = [f"# Apple用语检查", "", f"检查了 {len({k for k, _, _ in texts})} 个字符串（{len(texts)} 条译文）。"
             f"命中的是“不用这个”的写法，要不要改逐条判断。", ""]
    summary = collections.Counter()
    for language in LANGUAGES:
        rules = [(rule, items) for rule, items in hits.items() if rule[0] == language]
        if not rules:
            continue
        lines += [f"## {language}", ""]
        for (_, pattern, use, note), items in rules:
            summary[language] += len(items)
            lines.append(f"### 用“{use}”，命中 `{pattern}`：{len(items)} 条" + (f"（{note}）" if note else ""))
            lines.append("")
            for key, text, found in items:
                shown = text.replace("\n", " ").replace("|", "\\|")
                label = f"“{found}”"
                lines.append(f"- {label} {shown}" + ("" if language == "zh-Hans" or key == text else f"　〔键：{key.replace(chr(10), ' ')[:60]}〕"))
            lines.append("")
    lines.insert(3, "命中数：" + "，".join(f"{language} {summary[language]}" for language in LANGUAGES if summary[language]))
    report = "\n".join(lines) + "\n"
    if arguments.输出:
        pathlib.Path(arguments.输出).write_text(report, encoding="utf-8")
        print(lines[3])
    else:
        print(report)


if __name__ == "__main__":
    main()
