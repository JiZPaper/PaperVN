# PaperVN 离线推荐模型构建器

以下命令均在仓库根目录执行。

## Paparu视觉小说图像数据集

`收集Paparu视觉小说图像数据集.py`使用项目内的
`PaperVN/Resources/vndb_id_connector.json`作为唯一的 VNDB、Steam 与 Bangumi ID 映射来源。
脚本按 VNDB ID 去重，因此同一部作品的多个发行版本不会变成多个识别类别。

默认选择映射文件中的前200部有 Steam 或 Bangumi ID 的作品，并且可以断点续跑：

```sh
python3 "Tools/收集Paparu视觉小说图像数据集.py"
```

输出默认写入 `.build/paparu-vision-dataset/`，包括：

- `dataset.sqlite3`：可断点续跑的状态、作品、角色、来源响应和图片清单；
- `images/`：下载的 VNDB、Steam、Bangumi 图片；
- `titles.jsonl`、`characters.jsonl`、`assets.jsonl`：供后续训练或索引使用的导出清单；
- `selected_titles.json`：本次固定选择的200部作品。

VNDB提供作品截图、封面和角色图片；Steam主要提供商店截图；Bangumi主要补充封面和作品元数据。
Bangumi或Steam某个ID不存在时会记录错误并继续处理其他来源。

手动补图时，将图片放进：

```text
.build/paparu-vision-dataset/manual/v123/
```

其中目录名必须是 VNDB ID。重新运行脚本后，图片会被复制到 `images/v123/manual/` 并写入同一份清单。

常用选项：

```sh
python3 "Tools/收集Paparu视觉小说图像数据集.py" --dry-run --limit 200
python3 "Tools/收集Paparu视觉小说图像数据集.py" --limit 200 --retry-failed
python3 "Tools/收集Paparu视觉小说图像数据集.py" --skip-bangumi
```

`构建VNDB离线推荐模型.py`在Mac上构建由服务器分发的推荐语料和低秩作品向量。

它会：

- 从 `POST /vn` 获取全部可推荐视觉小说，并从 `POST /character` 获取候选作品中承担主要角色或核心角色的角色证据；
- 用 SQLite 保存已经完成的页面和去重记录，中断后从下一个页面继续；
- 下载 VNDB 每日公开评分文件，把每位用户的评分按其中位数和尺度转成信号，用每轮重新打乱顺序的逐条 SGD 训练“作品偏置 + 低秩向量”；
- 作品偏置按“相当于 50 票的贝叶斯平均”收缩，避免只有少数粉丝评分的作品被推给所有人；
- 留出 3,000 位公开用户的部分评分，按 App 折入资料库的方式评估模型，达不到质量门槛就不写出模型；
- 只把作品、标签、角色特征、作品向量和作品偏置写入 `VNDBRecommendationModel.json.gz`，不写入公开用户 ID；
- 把这些留出用户的评分（只有作品编号和分数，没有用户 ID）写入 `evaluation-users.json.gz`，供离线评估使用；
- 通过 `--refresh-content` 或 `--refresh-votes` 显式重新获取对应数据。

## 构建

只需要 Python 3.10 及以上，不依赖第三方库。先运行不联网的自检：

```sh
python3 Tools/构建VNDB离线推荐模型.py --self-test
```

自检在合成评分里植入已知的口味结构，要求训练结果能学回这个结构（相关性至少 0.8），并确认质量门槛会接受训练好的模型、拒绝随机向量。

完整构建（首次抓取作品与角色需要数小时；训练和评估约 10 分钟）：

```sh
caffeinate -dimsu python3 Tools/构建VNDB离线推荐模型.py
```

只想用最新评分重训协同部分、沿用已发布模型的作品和角色内容时，可以跳过抓取：

```sh
python3 Tools/构建VNDB离线推荐模型.py --base-model 已发布的/VNDBRecommendationModel.json.gz --refresh-votes
```

再次运行会复用`.build/vndb-recommendation-model/`中的断点和去重数据；公开评分文件中断后会保留`.partial`并尝试续传。继续现有构建时不要添加`--refresh-content`。生成的模型默认放在`.build/vndb-recommendation-model/VNDBRecommendationModel.json.gz`，不会进入App资源。

## 质量门槛

训练结束后，脚本会打印以下指标，并写进模型清单的 `collaborative.evaluation`：

- 留出评分的 RMSE，必须低于“只用作品偏置”的基线；
- 留出评分的成对排序准确率，必须比基线至少高 0.005；
- 只用个性化项 p·q 排序时的准确率，必须至少 0.55（0.5 相当于随机）；
- 官方续作、前作、FD 之间的向量余弦，必须比随机作品对至少高 0.15；
- 留出用户喜欢的作品在前 100 名中的召回率，必须高于“所有人都按作品偏置排序”。

任何一项不达标，构建直接失败。另外会打印“最常见作品出现在多少位留出用户的前 20 名里”，用来观察推荐是否过度集中；它不参与门槛判断。2026-08-01 发布的模型由旧版 MLX 路径训练，关联作品的余弦只有 +0.006，与随机向量没有区别；那条训练路径已删除。

模型清单里的 `collaborative.userRegularization`、`biasWeight` 和 `scoreScale` 由同一次评估选出，App 折入资料库时直接使用：协同分 = 个性化项 p·q + `biasWeight` × 作品偏置，`biasWeight` 在 0、0.0625、0.125 中取留出召回率最高的值，`scoreScale` 让典型用户前 0.1% 的作品得到 0.72。`biasWeight` 不再放大：在留出用户上，0.25 会让同一部作品进入 76% 的前 20 名。缺少 `collaborative` 的旧模型，App 不会使用其中的低秩向量。

构建完成后，在上传前确认文件存在并检查gzip文件：

```sh
test -f .build/vndb-recommendation-model/VNDBRecommendationModel.json.gz
gzip -t .build/vndb-recommendation-model/VNDBRecommendationModel.json.gz
```

将该文件上传到`https://r2-papervn.jizpaper.com/Resources/VNDBRecommendationModel.json.gz`。App不再打包模型；用户开启“为你推荐”后会按需下载。之后服务器上的模型一有变化，App 就会弹出“更新偏好分析模型”提示，并显示服务器上的文件大小：先比较 ETag，必要时只读取文件开头的模型清单，确认确实是新模型才提示。用户选择“忽略”只跳过这一版，模型再次变化时会重新提示；旧版构建器生成的模型也可以在设置里点“重新下载模型”。

## 离线评估

```sh
Tools/运行推荐离线评估.sh --count 300 --output report.json
```

脚本把 App 的推荐源码（`VNDB探索数据模型.swift`、`推荐/VNDB本地推荐算法.swift`、`推荐/VNDB离线推荐模型.swift`、`推荐/推荐展示排序.swift`）和 `Tools/推荐离线评估/main.swift` 一起编译，对 `evaluation-users.json.gz` 里的留出用户逐个运行与 App 完全相同的推荐流程。这些用户被隐藏的评分没有参与训练，所以不会有数据泄漏。报告包括：

- NDCG@12、前 12 名至少命中一部的比例、Recall@48，以用户被隐藏的高分作品为准；
- 前 12 名覆盖的不同作品数、最常出现的作品、推荐作品与资料库的评分人数中位数；
- 前 12 名中“相似用户”理由和探索项的占比；
- 两周展示模拟：在用户从不点开的最坏情况下，新的展示排序与改动前“固定前 8 名 + 轮换”各自展示过多少部作品、相邻两天的重合度。

推荐源码只能依赖 Foundation；如果评估脚本编译失败，通常是有人在这些文件里引用了界面层的类型。

## 每月更新

```sh
Tools/更新推荐模型.sh               # 完整更新：重新抓取作品与角色，需要数小时
Tools/更新推荐模型.sh --votes-only  # 只用最新评分重训协同部分，约 15 分钟
```

脚本依次运行自检、构建（含质量门槛）和离线评估，最后提示需要上传的文件。

用户自己资料库中的全部角色与角色特征不依赖下载的低秩模型：App首次分析时按资料库作品获取并永久保存，后续只为新增作品补充数据。

# Hiro智能模型

`构建智能搜索模型.py` 在 Mac 上训练搜索页的 Hiro智能：一个名称模糊匹配模型。用户输入作品名、角色名、会社、制作人员的几个字、错拼、别名或玩家常用的梗（如“白学”“助手”“吾王”），App 在设备上找出对应条目并排序。搜索页按相关程度排序时完全按这个顺序排列，第一个结果把握足够大时加彩虹辉光。查询文本不离开设备，只有结果的 VNDB 编号会用来请求详情。

不做剧情、外观描述的语义检索，所以没有查询编码器。模型打包成一个约 32 MB 的文件 `PaperVNSmartSearch.pvss`（格式版本 2），App 直接内存映射：

- **条目**：约 3.9 万部作品（至少 1 票）、6.2 万个角色（得票至少 10 的作品里的主要角色）、1.8 万个会社、4.9 万名制作人员，各带一个热度先验。作品带系列编号（按 VNDB 作品关联的续作、前作、外传、同系列等关系合并，搜索页据此把同系列作品叠在一起），角色带主要出场作品（搜索页把角色挂在这部作品下面）。
- **名称索引**：标题、别名、角色名、Bangumi 中文名和梗的双字片段索引（NFKC、小写、去变音、片假名转平假名、折叠罗马字长音）；不超过 8 个汉字的查询还加上单字片段，输入两三个字也能召回。候选包括名称最相近的 80 个，以及包含全部查询片段的名称里最热门的 40 个。
- **排序器**：综合名称匹配（覆盖率、完全一致、前缀、包含）、热度和条目类型等 15 项特征的小型网络，还有一个“输入不像任何名字”选项。用软标签训练：一条查询匹配多个条目时正例概率按热度分配，让同样匹配时热门条目排在前面。

数据来源：VNDB 数据库导出；Bangumi 数据库导出（中文名、别名，以及只出现在极少数条目上、又有足够多人打的标签，往往就是这部作品的简称或梗）；`智能搜索模型/社区别名.json` 手工维护两边都没有的叫法（作品、角色、会社、制作人员都可以加）。合成查询包括完整名称、开头几个字、中间片段、错拼和别名，另有 `智能搜索模型/评估查询-名称.json` 中的人工评估查询。

## 环境

```sh
python3 -m venv .build/smart-search-venv
.build/smart-search-venv/bin/pip install torch numpy boto3
```

## 构建

```sh
caffeinate -dimsu .build/smart-search-venv/bin/python -u Tools/构建智能搜索模型.py
```

依次执行 `prepare`（下载并解析 VNDB 数据库导出）、`aliases`（下载 Bangumi 数据库导出，补充中文名、别名和梗）、`fuzzy`（构建名称索引，训练排序器，打印合成评估、人工评估和示例查询，然后打包）。也可以只运行某几个阶段，例如改了 `社区别名.json` 后运行 `Tools/构建智能搜索模型.py aliases fuzzy`。`fuzzy` 在 M4 上约 20 分钟。

App 的名称规范化、片段索引和特征计算是 Swift 重写的（`PaperVN/智能搜索/`），必须与 `名称.py`、`模糊.py` 逐项一致，修改任一侧后都要重新比对。

产物在 `.build/smart-search-model/PaperVNSmartSearch.pvss`，上传到 `https://r2-papervn.jizpaper.com/Resources/PaperVNSmartSearch.pvss`：

```sh
R2_ACCOUNT_ID=… R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… R2_BUCKET=papervn \
  .build/smart-search-venv/bin/python Tools/上传到R2.py .build/smart-search-model/PaperVNSmartSearch.pvss Resources/PaperVNSmartSearch.pvss
```

App 安装包里预装了一份模型（`PaperVN/Resources/PaperVNSmartSearch.pvss`），装好就能用。上传新模型后，App 会像偏好分析模型一样先比较 ETag、必要时只读取文件头，确认服务器上的模型和正在用的不同才提示“更新Hiro智能模型”，下载的更新放在 Application Support 里。模型标识开头是构建日期：App 更新后内置的模型和下载的一样新或更新时，改用内置的并删除下载的文件。

发布带新模型的 App 版本前，把同一个文件复制到 `PaperVN/Resources/PaperVNSmartSearch.pvss`，并且和 R2 上的保持一致，否则装好 App 的用户会马上收到一次没有必要的更新提示。

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
