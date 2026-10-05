#!/bin/sh
set -eu

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

if [ -n "${PAPERVN_PRIVATE_XCCONFIG_B64:-}" ]; then
    printf '%s' "$PAPERVN_PRIVATE_XCCONFIG_B64" | base64 --decode > "$ROOT/Config/PaperVN.private.xcconfig"
fi

if [ -n "${PAPERVN_PRIVATE_SWIFT_B64:-}" ]; then
    mkdir -p "$ROOT/PaperVN/Private"
    printf '%s' "$PAPERVN_PRIVATE_SWIFT_B64" | base64 --decode > "$ROOT/PaperVN/Private/内容安全私有配置.swift"
fi

if [ ! -f "$ROOT/Config/PaperVN.private.xcconfig" ] || [ ! -f "$ROOT/PaperVN/Private/内容安全私有配置.swift" ]; then
    echo "error: PaperVN private configuration is missing" >&2
    exit 1
fi
