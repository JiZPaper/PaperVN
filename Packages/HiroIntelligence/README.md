# HiroIntelligence

PaperVN 搜索页 Hiro智能 的设备端名称模糊匹配，抽成独立的 Swift Package。读取 `.pvss` 模型文件，按名称搜索视觉小说、角色、会社、制作人员、动画、漫画和轻小说；查询文本不会离开设备。

App 里的原版代码仍在 `PaperVN/智能搜索/`，这里是同一套搜索逻辑去掉了 App 专用的部分（模型下载、存储位置、本地化文案）。修改搜索逻辑时两边要一起改。

## 模型文件

本 Package 不附带模型。最新的模型在：

```
https://r2-papervn.jizpaper.com/Resources/PaperVNSmartSearch.pvss
```

App 安装包里预装的一份在 `PaperVN/Resources/PaperVNSmartSearch.pvss`。模型约 90 MB，搜索时按内存映射读取，不会整个复制进内存。

## 使用

```swift
import HiroIntelligence

let 引擎 = 智能搜索引擎(模型URL: 模型文件URL)
let 结果 = try await 引擎.搜索("Ever17")
for 命中 in 结果.命中 {
    print(命中.类型, 命中.编号, 命中.概率)
}
```

- `编号`：视觉小说、角色、会社、制作人员是 VNDB 编号（如 `v17`、`c6487`、`p98`、`s216`）；动画、漫画、轻小说是 `a`、`m`、`n` 加 MAL ID。
- `空概率`：输入不像任何一个名字的概率。
- `系列`：同系列的视觉小说这个值相同；`所属作品`：角色的主要出场作品。
- `智能搜索模型文件.读取标识(url)` 只读文件开头就能取得模型标识，开头的日期可以用来比较新旧。
- 替换模型文件后调用 `卸载()`，下次搜索时重新加载。

## 文件格式

`"PVSS"` | 格式版本 UInt32 | 头长度 UInt32 | 头 JSON | 各段数据（16 字节对齐，小端序）。头 JSON 的 `sections` 记录各段的偏移和长度。目前支持格式版本 2–3。

## 测试

```sh
swift test
```

默认使用 App 里预装的模型，也可以用环境变量 `HIRO_INTELLIGENCE_MODEL` 指定模型文件；找不到模型时跳过测试。

## 许可

CC BY-SA 4.0（见 `LICENSE`）。模型里的中文标题、别名和标签来自 [Bangumi](https://bgm.tv/) wiki 数据存档（[bangumi/Archive](https://github.com/bangumi/Archive)），这部分仍受 Bangumi 的条款约束。模型的训练方式与数据不公开。
