# DMG 打包与 App Store 合规实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Mini Capsule 构建 macOS 双通道分发基础设施：DMG 直接分发（Developer ID 签名 + 公证）和 Mac App Store 上架（App Sandbox + Apple Distribution 签名）。

**Architecture:** 三套 entitlement 文件按 configuration 分离；两个构建脚本；用户填写证书凭据后一键出包。

**Tech Stack:** Bash shell scripts, Xcode xcodebuild, hdiutil, codesign, notarytool, stapler, altool, plutil

## Global Constraints

- 平台：macOS
- 证书和 Team ID 由用户后续自行填写，计划中仅放置占位符
- 现有开发调试流程不受影响（Debug 配置保持不变）
- aps-environment: DMG 和 AppStore 用 production，Development 保持 development
- App Store 版本强制启用 App Sandbox
- DMG 版本用 Hardened Runtime（公证必需）
- 脚本语法验证通过（不需要实际证书即可运行语法检查）

---

### Task 1: 创建目录结构和迁移现有 entitlements

**Files:**
- Create: `Configs/` 目录
- Move: `Mini Capsule/Mini_Capsule.entitlements` → `Configs/Development.entitlements`
- Modify: `Mini Capsule.xcodeproj/project.pbxproj`（更新 CODE_SIGN_ENTITLEMENTS 路径）

**Interfaces:**
- Produces: `Configs/` directory with `Development.entitlements` ready for Tasks 2-3

- [ ] **Step 1: 创建 Configs 目录，移动 entitlements 文件**

```bash
mkdir -p "Mini Capsule/Configs"
mv "Mini Capsule/Mini Capsule.entitlements" "Mini Capsule/Configs/Development.entitlements"
```

- [ ] **Step 2: 更新 Xcode project.pbxproj 中的路径引用**

查找 project.pbxproj 中所有引用 `Mini_Capsule.entitlements` 的行，更新路径为 `Configs/Development.entitlements`。

```bash
grep -n "Mini_Capsule.entitlements" "Mini Capsule.xcodeproj/project.pbxproj"
```

逐行替换：
```
Mini_Capsule.entitlements → Configs/Development.entitlements
```

- [ ] **Step 3: 验证构建**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Configs/" "Mini Capsule/Mini_Capsule.entitlements" "Mini Capsule.xcodeproj/"
git commit -m "refactor: move entitlements to Configs/ directory, rename to Development.entitlements

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 创建 DMG.entitlements

**Files:**
- Create: `Mini Capsule/Configs/DMG.entitlements`

**Interfaces:**
- Produces: DMG entitlement plist for Developer ID signing with Hardened Runtime

- [ ] **Step 1: 创建 DMG.entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Hardened Runtime (required for notarization) -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>
    <!-- Network access (push notifications) -->
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- Push notifications (production) -->
    <key>aps-environment</key>
    <string>production</string>
    <!-- CloudKit -->
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.$(CFBundleIdentifier)</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: 验证 plist 格式**

```bash
plutil -lint "Mini Capsule/Configs/DMG.entitlements"
```

Expected: `Mini Capsule/Configs/DMG.entitlements: OK`

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Configs/DMG.entitlements"
git commit -m "feat: add DMG.entitlements for Developer ID distribution with Hardened Runtime

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 创建 AppStore.entitlements

**Files:**
- Create: `Mini Capsule/Configs/AppStore.entitlements`

**Interfaces:**
- Produces: App Store entitlement plist with App Sandbox enabled

- [ ] **Step 1: 创建 AppStore.entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- App Sandbox (required for Mac App Store) -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <!-- User-selected file access (save/open clipboard items) -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <!-- Network access (push notifications) -->
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- Push notifications (production) -->
    <key>aps-environment</key>
    <string>production</string>
    <!-- CloudKit -->
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.$(CFBundleIdentifier)</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: 验证 plist 格式**

```bash
plutil -lint "Mini Capsule/Configs/AppStore.entitlements"
```

Expected: `Mini Capsule/Configs/AppStore.entitlements: OK`

- [ ] **Step 3: Commit**

```bash
git add "Mini Capsule/Configs/AppStore.entitlements"
git commit -m "feat: add AppStore.entitlements with App Sandbox for Mac App Store distribution

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 更新 Info.plist

**Files:**
- Modify: `Mini Capsule/Info.plist`

**Interfaces:**
- Produces: Updated Info.plist with App Store required keys

- [ ] **Step 1: 添加 LSUIElement 和 LSApplicationCategoryType**

Read the current Info.plist at `Mini Capsule/Info.plist`. Add the following keys inside `<dict>`:

```xml
<key>LSUIElement</key>
<true/>
<key>LSApplicationCategoryType</key>
<string>public.app-category.utilities</string>
```

- [ ] **Step 2: 验证 plist 格式**

```bash
plutil -lint "Mini Capsule/Info.plist"
```

Expected: `Mini Capsule/Info.plist: OK`

- [ ] **Step 3: 验证构建**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add "Mini Capsule/Info.plist"
git commit -m "feat: add LSUIElement and LSApplicationCategoryType to Info.plist for App Store compliance

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 创建共享构建变量脚本

**Files:**
- Create: `Scripts/common.sh`

**Interfaces:**
- Produces: Shared shell variables for both build scripts
- shellcheck 通过

- [ ] **Step 1: 创建 common.sh**

```bash
#!/bin/bash
# Mini Capsule — shared build variables
# Replace the placeholders below with your own values.

set -euo pipefail

# === REPLACE ME: Your Apple Developer Team ID ===
export DEVELOPMENT_TEAM="YOUR_TEAM_ID"

# === REPLACE ME: Your app's Bundle Identifier ===
export BUNDLE_ID="com.yourcompany.Mini-Capsule"

# === REPLACE ME: App Store Connect credentials (for App Store upload) ===
export ASC_EMAIL="you@example.com"
# Use @keychain:AC_PASSWORD to store securely, or set APP_SPECIFIC_PASSWORD
export ASC_PASSWORD="@keychain:AC_PASSWORD"

# === Project settings (usually no need to change) ===
export APP_NAME="Mini Capsule"
export VERSION="1.0"
export PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export SCHEME="Mini Capsule"
export ARCHIVE_DIR="${PROJECT_DIR}/build"
export DMG_NAME="${APP_NAME}-${VERSION}"
```

- [ ] **Step 2: 验证脚本语法**

```bash
bash -n Scripts/common.sh
```

Expected: no output (no syntax errors)

- [ ] **Step 3: Commit**

```bash
git add Scripts/common.sh
git commit -m "feat: add shared build variables script for DMG and App Store builds

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 创建 DMG 构建脚本

**Files:**
- Create: `Scripts/build-dmg.sh`

**Interfaces:**
- Consumes: `common.sh` from Task 5, `DMG.entitlements` from Task 2
- Produces: `Mini Capsule-1.0.dmg` (when run with valid certificates)

- [ ] **Step 1: 创建 build-dmg.sh**

```bash
#!/bin/bash
# Mini Capsule — DMG build script
# Builds a signed and notarized DMG for direct distribution.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "==> Building ${APP_NAME} ${VERSION} for DMG distribution..."

# Step 1: Build and archive
echo "==> Archiving..."
xcodebuild archive \
    -project "${PROJECT_DIR}/Mini Capsule.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_DIR}/${APP_NAME}.xcarchive" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
    CODE_SIGN_ENTITLEMENTS="${PROJECT_DIR}/Mini Capsule/Configs/DMG.entitlements" \
    CODE_SIGN_IDENTITY="Developer ID Application"

# Step 2: Export the .app from the archive
echo "==> Exporting .app..."
APP_PATH="${ARCHIVE_DIR}/${APP_NAME}.xcarchive/Products/Applications/${APP_NAME}.app"

# Step 3: Create DMG
echo "==> Creating DMG..."
DMG_PATH="${ARCHIVE_DIR}/${DMG_NAME}.dmg"
TMP_DMG="${ARCHIVE_DIR}/tmp.dmg"

hdiutil create -size 100m -fs HFS+ -volname "${APP_NAME}" "${TMP_DMG}"
hdiutil attach "${TMP_DMG}" -mountpoint "/Volumes/${APP_NAME}"

# Copy .app and Applications shortcut
cp -R "${APP_PATH}" "/Volumes/${APP_NAME}/"
ln -s /Applications "/Volumes/${APP_NAME}/Applications"

# Optional: set DMG background
if [ -f "${PROJECT_DIR}/Resources/dmg-background.png" ]; then
    mkdir -p "/Volumes/${APP_NAME}/.background"
    cp "${PROJECT_DIR}/Resources/dmg-background.png" "/Volumes/${APP_NAME}/.background/"
fi

hdiutil detach "/Volumes/${APP_NAME}"
hdiutil convert "${TMP_DMG}" -format UDZO -o "${DMG_PATH}"
rm -f "${TMP_DMG}"

# Step 4: Verify code signature
echo "==> Verifying code signature..."
codesign --deep --strict --verify --verbose=1 "${APP_PATH}"

# Step 5: Notarize
echo "==> Submitting for notarization..."
xcrun notarytool submit "${DMG_PATH}" \
    --team-id "${DEVELOPMENT_TEAM}" \
    --apple-id "${ASC_EMAIL}" \
    --password "${ASC_PASSWORD}" \
    --wait

# Step 6: Staple notarization ticket
echo "==> Stapling notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "==> Done! DMG created at: ${DMG_PATH}"
```

- [ ] **Step 2: 验证脚本语法**

```bash
bash -n Scripts/build-dmg.sh
```

Expected: no output (no syntax errors)

- [ ] **Step 3: Commit**

```bash
chmod +x Scripts/build-dmg.sh
git add Scripts/build-dmg.sh
git commit -m "feat: add DMG build script with signing, notarization, and stapling

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: 创建 App Store 构建脚本

**Files:**
- Create: `Scripts/build-appstore.sh`

**Interfaces:**
- Consumes: `common.sh` from Task 5, `AppStore.entitlements` from Task 3
- Produces: `.pkg` for App Store Connect upload (when run with valid certificates)

- [ ] **Step 1: 创建 build-appstore.sh**

```bash
#!/bin/bash
# Mini Capsule — App Store build script
# Builds and exports a .pkg for Mac App Store submission.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "==> Building ${APP_NAME} ${VERSION} for App Store distribution..."

# Step 1: Build and archive with App Store entitlements
echo "==> Archiving..."
xcodebuild archive \
    -project "${PROJECT_DIR}/Mini Capsule.xcodeproj" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_DIR}/${APP_NAME}-AppStore.xcarchive" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
    PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
    CODE_SIGN_ENTITLEMENTS="${PROJECT_DIR}/Mini Capsule/Configs/AppStore.entitlements" \
    CODE_SIGN_IDENTITY="Apple Distribution" \
    OTHER_CODE_SIGN_FLAGS="--options=runtime"

# Step 2: Export .pkg for App Store Connect
echo "==> Exporting .pkg..."
EXPORT_PLIST="${ARCHIVE_DIR}/exportOptions.plist"

cat > "${EXPORT_PLIST}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_DIR}/${APP_NAME}-AppStore.xcarchive" \
    -exportPath "${ARCHIVE_DIR}/${APP_NAME}-AppStore" \
    -exportOptionsPlist "${EXPORT_PLIST}"

PKG_PATH="${ARCHIVE_DIR}/${APP_NAME}-AppStore/${APP_NAME}.pkg"

# Step 3: Validate the package
echo "==> Validating .pkg..."
xcrun altool --validate-app \
    -f "${PKG_PATH}" \
    -t macOS \
    -u "${ASC_EMAIL}" \
    -p "${ASC_PASSWORD}"

# Step 4: Upload to App Store Connect
echo "==> Uploading to App Store Connect..."
xcrun altool --upload-app \
    -f "${PKG_PATH}" \
    -t macOS \
    -u "${ASC_EMAIL}" \
    -p "${ASC_PASSWORD}"

echo "==> Done! .pkg uploaded to App Store Connect."
```

- [ ] **Step 2: 验证脚本语法**

```bash
bash -n Scripts/build-appstore.sh
```

Expected: no output (no syntax errors)

- [ ] **Step 3: Commit**

```bash
chmod +x Scripts/build-appstore.sh
git add Scripts/build-appstore.sh
git commit -m "feat: add App Store build script with archive, export, validate, and upload

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: 创建 BUILD.md 填写指南 + DMG 背景占位

**Files:**
- Create: `BUILD.md`
- Create: `Resources/dmg-background.png`（占位说明）

- [ ] **Step 1: 创建 BUILD.md**

```markdown
# Mini Capsule — 构建与分发指南

## 前置条件

1. **Apple Developer Program** 付费账号
2. 在 Xcode → Settings → Accounts 中添加 Apple ID
3. 创建以下证书（通过 Xcode 自动管理或手动在 developer.apple.com 创建）：
   - **Developer ID Application**（用于 DMG 签名）
   - **Apple Distribution**（用于 App Store 提交）

## 填写配置

### 1. 编辑 `Scripts/common.sh`

替换以下占位符：

```bash
export DEVELOPMENT_TEAM="ABCDEF1234"           # 你的 Team ID
export BUNDLE_ID="com.yourcompany.Mini-Capsule" # 你的 Bundle ID
export ASC_EMAIL="you@example.com"             # Apple ID 邮箱
export ASC_PASSWORD="@keychain:AC_PASSWORD"    # App 专用密码
```

`ASC_PASSWORD` 建议用 Keychain 存储：
```bash
xcrun altool --store-password-in-keychain-item "AC_PASSWORD" \
    -u "you@example.com" -p "xxxx-xxxx-xxxx-xxxx"
```

### 2. DMG 背景图（可选）

将 DMG 背景图保存为 `Resources/dmg-background.png`（推荐 658×498 像素）。

## 构建

### DMG 直接分发

```bash
cd Scripts
./build-dmg.sh
```

输出：`build/Mini Capsule-1.0.dmg`（已签名 + 公证）

### App Store 提交

```bash
cd Scripts
./build-appstore.sh
```

输出：自动上传到 App Store Connect，在 App Store Connect 中完成后续审核流程。

## 证书对照

| 分发方式 | 证书 | Entitlements |
|---|---|---|
| 开发调试 | Apple Development | `Configs/Development.entitlements` |
| DMG 分发 | Developer ID Application | `Configs/DMG.entitlements` |
| App Store | Apple Distribution | `Configs/AppStore.entitlements` |

## App Store Connect 后续步骤

1. 上传后登录 [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. 填写 App 信息（描述、截图、隐私政策 URL 等）
3. 提交审核
4. 审核通过后 App 上架
```

- [ ] **Step 2: 创建 DMG 背景占位目录和说明**

```bash
mkdir -p Resources
echo "Replace this file with your DMG background image (658x498 px recommended)." > Resources/dmg-background.png
# 实际项目可以放一张真实的占位 PNG
```

替换为：

```bash
mkdir -p Resources
touch Resources/.gitkeep
# dmg-background.png 由用户自行放入此目录
```

在 `Resources/README.md` 中说明：

```markdown
# Resources

## dmg-background.png

DMG 安装窗口背景图。推荐规格：
- 尺寸：658 × 498 像素
- 格式：PNG
- 颜色：深色背景（与 macOS 安装窗口风格一致）

创建后脚本会自动使用。不放入此文件则使用默认白色背景。
```

- [ ] **Step 3: Commit**

```bash
mkdir -p Resources
echo "Put your dmg-background.png (658x498 px) here." > Resources/README.md
git add BUILD.md Resources/
git commit -m "docs: add BUILD.md distribution guide and Resources directory

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: 最终验证

- [ ] **Step 1: 验证所有 plist 文件格式**

```bash
plutil -lint "Mini Capsule/Configs/Development.entitlements"
plutil -lint "Mini Capsule/Configs/DMG.entitlements"
plutil -lint "Mini Capsule/Configs/AppStore.entitlements"
plutil -lint "Mini Capsule/Info.plist"
```

Expected: All return `OK`

- [ ] **Step 2: 验证所有脚本语法**

```bash
bash -n Scripts/common.sh && echo "common.sh: OK"
bash -n Scripts/build-dmg.sh && echo "build-dmg.sh: OK"
bash -n Scripts/build-appstore.sh && echo "build-appstore.sh: OK"
```

Expected: All return `OK`

- [ ] **Step 3: 验证项目构建不受影响**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: 验证测试仍然通过**

```bash
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test 2>&1 | tail -10
```

Expected: All tests pass

- [ ] **Step 5: 检查文件结构**

```bash
echo "=== Expected file structure ===" && ls -la Configs/ && ls -la Scripts/ && ls -la Resources/ && ls -la BUILD.md
```

Expected:
```
Configs/
  Development.entitlements
  DMG.entitlements
  AppStore.entitlements
Scripts/
  common.sh
  build-dmg.sh
  build-appstore.sh
Resources/
  README.md
BUILD.md
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: final verification — plists valid, scripts syntax OK, build passes

Co-Authored-By: Claude <noreply@anthropic.com>"
```
