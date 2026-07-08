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
