#!/bin/sh
# 每月更新“为你推荐”模型：自检 → 抓取内容与最新公开评分 → 训练并通过质量门槛 → 离线评估。
#
# 用法：Tools/更新推荐模型.sh               完整更新，重新抓取全部作品与角色（需要数小时）
#      Tools/更新推荐模型.sh --votes-only  只用最新评分重训协同部分，沿用上次模型的内容（约 15 分钟）
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/.build/vndb-recommendation-model"
MODEL="$WORK/VNDBRecommendationModel.json.gz"
cd "$ROOT"

python3 Tools/构建VNDB离线推荐模型.py --self-test

if [ "${1:-}" = "--votes-only" ]; then
  if [ ! -f "$MODEL" ]; then
    echo "没有可以沿用内容的模型：$MODEL" >&2
    exit 2
  fi
  cp "$MODEL" "$WORK/previous-model.json.gz"
  caffeinate -dimsu python3 Tools/构建VNDB离线推荐模型.py \
    --base-model "$WORK/previous-model.json.gz" \
    --refresh-votes
else
  caffeinate -dimsu python3 Tools/构建VNDB离线推荐模型.py \
    --refresh-content \
    --refresh-votes
fi

gzip -t "$MODEL"
Tools/运行推荐离线评估.sh --count 300 --output "$WORK/evaluation-report.json"

echo
echo "确认评估结果后，把下面的文件上传到"
echo "https://r2-papervn.jizpaper.com/Resources/VNDBRecommendationModel.json.gz："
echo "$MODEL"
echo "已安装的 App 会提示用户更新。"
