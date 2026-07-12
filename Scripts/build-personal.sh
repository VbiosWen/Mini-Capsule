#!/bin/bash
# Mini Capsule — 个人构建脚本（无需 Apple Developer 账号）
# 用法: ./build-personal.sh [输出目录，默认 /Applications]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# === 检测 Xcode 路径 ===
# 如果当前 developer directory 是 CommandLineTools，自动切换到 Xcode
CURRENT_DEVELOPER_DIR=$(xcode-select -p 2>/dev/null || true)
if [[ "$CURRENT_DEVELOPER_DIR" == *"CommandLineTools"* ]] || [[ -z "$CURRENT_DEVELOPER_DIR" ]]; then
    XCODE_APP="/Applications/Xcode.app/Contents/Developer"
    if [ -d "$XCODE_APP" ]; then
        export DEVELOPER_DIR="$XCODE_APP"
        echo "==> 检测到 CommandLineTools，已自动切换为 Xcode"
    else
        echo "错误: 未安装 Xcode.app，请从 App Store 安装 Xcode"
        exit 1
    fi
fi

# === 配置 ===
SCHEME="Mini Capsule"
APP_NAME="Mini Capsule"
CONFIG="Release"
OUT_DIR="${1:-/Applications}"
ENTITLEMENTS="${PROJECT_DIR}/Mini Capsule/Configs/Personal.entitlements"

echo "==> 构建 ${APP_NAME} (${CONFIG}, 无签名)..."

# Step 1: Build
xcodebuild \
    -project "${PROJECT_DIR}/Mini Capsule.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="${ENTITLEMENTS}" \
    build

# Step 2: 找到构建产物
DERIVED_DATA=$(xcodebuild \
    -project "${PROJECT_DIR}/Mini Capsule.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIG}" \
    -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | cut -d= -f2 | xargs)

APP_PATH="${DERIVED_DATA}/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "错误: 找不到 ${APP_PATH}"
    exit 1
fi

# Step 3: 移除旧版本并拷贝
if [ -d "${OUT_DIR}/${APP_NAME}.app" ]; then
    echo "==> 移除旧版本..."
    rm -rf "${OUT_DIR}/${APP_NAME}.app"
fi

echo "==> 拷贝到 ${OUT_DIR}..."
cp -R "$APP_PATH" "$OUT_DIR/"

echo "==> 完成! ${OUT_DIR}/${APP_NAME}.app"
echo ""
echo "提示: 首次打开时，如果 macOS 提示「无法验证开发者」:"
echo "  右键点击 App → 打开 → 确认打开即可"
