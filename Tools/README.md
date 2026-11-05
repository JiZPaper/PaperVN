# PaperVN 工具

以下命令均在仓库根目录执行。

## Paparu视觉小说图像数据集

`收集Paparu视觉小说图像数据集.py`使用项目内的
`PaperVN/Resources/vndb_id_connector.json`作为唯一的 VNDB、Steam 与 Bangumi ID 映射来源。
脚本按 VNDB ID 去重，因此同一部作品的多个发行版本不会变成多个识别类别。

默认选择映射文件中的前200部有 Steam 或 Bangumi ID 的作品，并且可以断点续跑：

```sh
python3 "Tools/收集Paparu视觉小说图像数据集.py"
```

输出默认写入 `../训练数据/Paparu图像数据集/`，包括：

- `dataset.sqlite3`：可断点续跑的状态、作品、角色、来源响应和图片清单；
- `images/`：下载的 VNDB、Steam、Bangumi 图片；
- `titles.jsonl`、`characters.jsonl`、`assets.jsonl`：供后续训练或索引使用的导出清单；
- `selected_titles.json`：本次固定选择的200部作品。

VNDB提供作品截图、封面和角色图片；Steam主要提供商店截图；Bangumi主要补充封面和作品元数据。
Bangumi或Steam某个ID不存在时会记录错误并继续处理其他来源。

手动补图时，将图片放进：

```text
../训练数据/Paparu图像数据集/manual/v123/
```

其中目录名必须是 VNDB ID。重新运行脚本后，图片会被复制到 `images/v123/manual/` 并写入同一份清单。

常用选项：

```sh
python3 "Tools/收集Paparu视觉小说图像数据集.py" --dry-run --limit 200
python3 "Tools/收集Paparu视觉小说图像数据集.py" --limit 200 --retry-failed
python3 "Tools/收集Paparu视觉小说图像数据集.py" --skip-bangumi
```

# 智能搜索模型

搜索页的智能搜索模型（Paper智能）是一个在设备上运行的名称模糊匹配模型（`PaperVNSmartSearch.pvss`），App 安装包里预装了一份，更新放在 `https://r2-papervn.jizpaper.com/Resources/PaperVNSmartSearch-v4.pvss`（格式 4；旧版 App 只认得格式 3，仍从 `Resources/PaperVNSmartSearch.pvss` 下载，那个文件不要覆盖）。模型文件超过 GitHub 的 100 MB 限制，不进仓库：克隆后先运行 `Tools/R2模型.sh 下载`（`archive.sh` 会自动运行），它按 `Tools/R2模型清单.txt` 从 R2 的 `Build/` 目录下载并核对校验值；换了新模型要运行 `Tools/R2模型.sh 发布 PaperVN/Resources/PaperVNSmartSearch.pvss` 上传并更新清单，再提交清单。`Build/` 只给开发用，App 不读取，上传不会触发更新提示。仓库里有 App 端的读取、搜索代码（`PaperVN/智能搜索/`，公开的 `Packages/HiroIntelligence` 和服务器的 `deploy/vps/hiro-search.mjs` 是同一套逻辑，要一起改），训练方式与数据不公开。

发布新模型时，`PaperVN/Resources/PaperVNSmartSearch.pvss` 必须和 R2 上的文件一致，否则装好 App 的用户会马上收到一次没有必要的更新提示：

```sh
R2_ACCOUNT_ID=… R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… R2_BUCKET=papervn \
  python3 Tools/上传到R2.py PaperVN/Resources/PaperVNSmartSearch.pvss Resources/PaperVNSmartSearch-v4.pvss
```

# “为你推荐”模型

“为你推荐”里的动画、漫画、轻小说与视觉小说都来自同一个模型 `PaperVN/Resources/PaperVNWorkRecommendation.pvwr`（App 端代码在 `PaperVN/非用户界面/推荐/`）。和 Hiro智能一样，仓库里只有模型文件，训练方式与数据不公开。

设备上每次打开 Today 时按资料库重新计算，只要几毫秒，不需要登录 VNDB，也没有后台分析。App 安装包里预装了一份，更新放在 `https://r2-papervn.jizpaper.com/Resources/PaperVNWorkRecommendation.pvwr`；服务器上的模型比正在用的新（标识开头的构建日期更晚）时，App 会弹出“更新“为你推荐”模型”提示。发布新模型时同样要让 App 资源和 R2 上的文件一致：

```sh
R2_ACCOUNT_ID=… R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… R2_BUCKET=papervn \
  python3 Tools/上传到R2.py PaperVN/Resources/PaperVNWorkRecommendation.pvwr Resources/PaperVNWorkRecommendation.pvwr
```

文件格式：`PVWR`、UInt32 标识长度、标识、UInt32 原文长度、raw DEFLATE 压缩的 JSON；作品编号与智能搜索模型相同（`作品搜索结果.编号`）。

# 视觉小说引擎库

运行视觉小说用到的两个引擎库体积很大，不进仓库，第一次编译或归档前要在本机编好（`Tools/archive.sh` 缺库时会中止）：

```sh
Tools/构建Siglus.sh     # siglus_rs（MPL-2.0）→ Dependencies/Siglus/SiglusCore.xcframework，约 15 分钟
Tools/构建KiriKiri.sh   # krkr2（MIT）→ Dependencies/KiriKiri/KiriKiriCore.xcframework 和界面资源，第一次约 1 小时
```

源码放在仓库外的 `../第三方源码/`：`siglus_rs`、`krkr2`、`vcpkg`（`git clone` 对应仓库即可，提交号记在 `Dependencies/Siglus/SIGLUS_RS_COMMIT` 和 `Dependencies/KiriKiri/KRKR2_COMMIT`）。需要 rustup（`aarch64-apple-ios`、`aarch64-apple-ios-sim`）以及 Homebrew 的 `nasm`、`yasm`、`bison`。PaperVN 对 krkr2 的修改在 `Dependencies/KiriKiri/patches/krkr2-ios.patch`，脚本会自动打上；两个脚本都会顺便更新许可页面用的依赖列表（`deploy/vps/legal/license/`）。

# 归档与上传

App Store 版本只支持 iOS 26 及以上，TestFlight 构建开放到 iOS 18。项目 Release 配置的部署目标是 26.0（在 Xcode 里直接 Archive 得到的就是上架构建），Debug 配置是 18.0（日常编译即可发现未加 `#available` 守卫的新 API）。

```sh
Tools/archive.sh testflight            # 最低 iOS 18，归档后在 Organizer 中打开
Tools/archive.sh testflight --upload   # 最低 iOS 18，直接上传到 App Store Connect
Tools/archive.sh appstore              # 最低 iOS 26
Tools/archive.sh appstore --upload
```

脚本会检查主程序与扩展的 `MinimumOSVersion`，不符合预期时中止。上传使用 `ExportOptions-AppStoreConnect.plist`，build 号由 App Store Connect 自动递增，需要本机 Xcode 已登录开发者账户。

同一版本号下会有两个构建：iOS 18 构建只分发给 TestFlight 测试组，提交审核时必须选择最低 iOS 26 的构建。
