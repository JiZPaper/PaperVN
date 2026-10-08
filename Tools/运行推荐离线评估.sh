#!/bin/sh
# 用构建器导出的留出用户离线评估“为你推荐”，与 App 使用同一套推荐源码。
# 先运行 Tools/构建VNDB离线推荐模型.py 生成模型和 evaluation-users.json.gz。
#
# 用法：Tools/运行推荐离线评估.sh [--count 300] [--output report.json]
#      [--model 模型.json.gz] [--users evaluation-users.json.gz]
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/.build/vndb-recommendation-model"
BIN="$ROOT/.build/recommendation-evaluation/evaluate"
SOURCES="$ROOT/PaperVN/非用户界面"

mkdir -p "$(dirname "$BIN")"
swiftc -O -o "$BIN" \
  "$SOURCES/VNDB探索数据模型.swift" \
  "$SOURCES/推荐/VNDB本地推荐算法.swift" \
  "$SOURCES/推荐/VNDB离线推荐模型.swift" \
  "$SOURCES/推荐/推荐展示排序.swift" \
  "$ROOT/Tools/推荐离线评估/main.swift"

exec "$BIN" \
  --model "$WORK/VNDBRecommendationModel.json.gz" \
  --users "$WORK/evaluation-users.json.gz" \
  "$@"
