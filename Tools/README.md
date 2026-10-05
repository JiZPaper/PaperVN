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
- 留出 3,000 位公开用户的部分评分，按 App 折入资料库的方式评估模型，达不到质量门槛就不写出模型；
- 只把作品、标签、角色特征、作品向量和作品偏置写入 `VNDBRecommendationModel.json.gz`，不写入公开用户 ID；
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

任何一项不达标，构建直接失败。2026-08-01 发布的模型由旧版 MLX 路径训练，关联作品的余弦只有 +0.006，与随机向量没有区别；那条训练路径已删除。

模型清单里的 `collaborative.userRegularization`、`biasWeight` 和 `scoreScale` 由同一次评估选出，App 折入资料库时直接使用：协同分 = 个性化项 p·q + `biasWeight` × 作品偏置，`biasWeight` 取留出召回率最高的值，`scoreScale` 让典型用户前 0.1% 的作品得到 0.72。缺少 `collaborative` 的旧模型，App 不会使用其中的低秩向量。

构建完成后，在上传前确认文件存在并检查gzip文件：

```sh
test -f .build/vndb-recommendation-model/VNDBRecommendationModel.json.gz
gzip -t .build/vndb-recommendation-model/VNDBRecommendationModel.json.gz
```

将该文件上传到`https://r2-papervn.jizpaper.com/Resources/VNDBRecommendationModel.json.gz`。App不再打包模型；用户开启“为你推荐”后会按需下载。已经下载过旧模型的 App 会在非昂贵网络下自动更新（服务器文件与上次下载相同时不会重复下载），用户也可以在设置里点“重新下载模型”。

用户自己资料库中的全部角色与角色特征不依赖下载的低秩模型：App首次分析时按资料库作品获取并永久保存，后续只为新增作品补充数据。

# 归档与上传

App Store 版本只支持 iOS 26 及以上，TestFlight 构建开放到 iOS 17。项目 Release 配置的部署目标是 26.0（在 Xcode 里直接 Archive 得到的就是上架构建），Debug 配置是 17.0（日常编译即可发现未加 `#available` 守卫的新 API）。

```sh
Tools/archive.sh testflight            # 最低 iOS 17，归档后在 Organizer 中打开
Tools/archive.sh testflight --upload   # 最低 iOS 17，直接上传到 App Store Connect
Tools/archive.sh appstore              # 最低 iOS 26
Tools/archive.sh appstore --upload
```

脚本会检查主程序与扩展的 `MinimumOSVersion`，不符合预期时中止。上传使用 `ExportOptions-AppStoreConnect.plist`，build 号由 App Store Connect 自动递增，需要本机 Xcode 已登录开发者账户。

同一版本号下会有两个构建：iOS 17 构建只分发给 TestFlight 测试组，提交审核时必须选择最低 iOS 26 的构建。
