#!/bin/bash
# 归档 PaperVN，区分 TestFlight（最低 iOS 18）与 App Store（最低 iOS 26）构建。
#
# 用法：
#   Tools/archive.sh testflight [--upload]
#   Tools/archive.sh appstore   [--upload]
#
# 不带 --upload 时只归档并在 Xcode Organizer 中打开；带 --upload 时直接上传到 App Store Connect。
set -euo pipefail

usage() {
    echo "用法：$0 <testflight|appstore> [--upload]" >&2
    exit 64
}

[[ $# -ge 1 ]] || usage
mode="$1"
upload=false
if [[ $# -ge 2 ]]; then
    [[ "$2" == "--upload" ]] || usage
    upload=true
fi

case "$mode" in
    testflight)
        expected_minimum_os="18.0"
        deployment_override=(IPHONEOS_DEPLOYMENT_TARGET=18.0)
        ;;
    appstore)
        # 使用项目 Release 配置中的 26.0，不做覆盖。
        expected_minimum_os="26.0"
        deployment_override=()
        ;;
    *)
        usage
        ;;
esac

project_root="$(cd "$(dirname "$0")/.." && pwd)"
timestamp="$(date +%Y%m%d-%H%M%S)"
archive_path="$project_root/.build/archives/PaperVN-$mode-$timestamp.xcarchive"
export_path="$project_root/.build/exports/PaperVN-$mode-$timestamp"

echo "▶︎ 归档 $mode 构建（最低 iOS $expected_minimum_os）"
xcodebuild archive \
    -project "$project_root/PaperVN.xcodeproj" \
    -scheme PaperVN \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$archive_path" \
    -allowProvisioningUpdates \
    ${deployment_override[@]+"${deployment_override[@]}"}

# 确认主程序与所有扩展的最低系统版本都符合预期，防止把 iOS 18 构建送审。
app_path="$archive_path/Products/Applications/PaperVN.app"
bundles=("$app_path")
while IFS= read -r -d '' appex; do
    bundles+=("$appex")
done < <(find "$app_path/PlugIns" -maxdepth 1 -name "*.appex" -print0 2>/dev/null)

for bundle in "${bundles[@]}"; do
    minimum_os="$(/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$bundle/Info.plist")"
    if [[ "$minimum_os" != "$expected_minimum_os" ]]; then
        echo "✗ $(basename "$bundle") 的最低系统版本是 $minimum_os，预期 $expected_minimum_os。已中止。" >&2
        exit 1
    fi
    echo "✓ $(basename "$bundle")：最低 iOS $minimum_os"
done

echo "✓ 归档完成：$archive_path"

if [[ "$upload" == true ]]; then
    echo "▶︎ 上传到 App Store Connect"
    xcodebuild -exportArchive \
        -archivePath "$archive_path" \
        -exportPath "$export_path" \
        -exportOptionsPlist "$project_root/Tools/ExportOptions-AppStoreConnect.plist" \
        -allowProvisioningUpdates
    echo "✓ 已上传 $mode 构建（最低 iOS $expected_minimum_os）"
    if [[ "$mode" == testflight ]]; then
        echo "提示：此构建只分发给 TestFlight 测试组，不要选它提交审核。"
    fi
else
    open "$archive_path"
fi
