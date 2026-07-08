# DMG 打包与 App Store 合规设计

**日期**: 2026-07-08
**状态**: 已批准

## 目标

为 Mini Capsule 构建 macOS 双通道分发基础设施：
1. **DMG 直接分发**（Developer ID 签名 + 公证）
2. **Mac App Store 上架**（App Sandbox + Apple Distribution 签名）

用户自行填写 Team ID 和证书，构建脚本一键出包。

## 架构

```
Mini Capsule.xcodeproj
├── Configs/
│   ├── DMG.entitlements          ← Developer ID + Hardened Runtime + production aps
│   ├── AppStore.entitlements     ← App Sandbox + Apple Distribution + production aps
│   └── Development.entitlements  ← 现有开发用（保留，aps: development）
├── Scripts/
│   ├── build-dmg.sh              ← 构建 DMG + 公证流程
│   ├── build-appstore.sh         ← 构建 + 打包 pkg 用于提交
│   └── common.sh                 ← 共享变量和工具函数
├── Resources/
│   └── dmg-background.png        ← DMG 安装背景图（可选）
└── BUILD.md                      ← 证书/Team ID 填写指南
```

## 两套 Entitlements

### DMG.entitlements（Developer ID，不强制 App Sandbox）

| 权限 | 用途 |
|---|---|
| Hardened Runtime (allow-jit: false, allow-unsigned-executable-memory: false) | 公证必需 |
| com.apple.security.network.client | 推送通知 |
| com.apple.developer.icloud-container-identifiers | CloudKit |
| com.apple.developer.icloud-services (CloudKit) | iCloud 同步 |
| aps-environment: production | 生产推送 |

### AppStore.entitlements（强制 App Sandbox）

DMG 内容 + 额外：

| 权限 | 用途 |
|---|---|
| com.apple.security.app-sandbox: true | App Store 强制要求 |
| com.apple.security.files.user-selected.read-write | 用户主动保存/打开文件 |

### Development.entitlements

现有文件保留，aps-environment 保持 development。新增的两个 production entitlement 文件分开使用。

## 构建脚本

### 共享变量（`Scripts/common.sh`）

```bash
DEVELOPMENT_TEAM="YOUR_TEAM_ID"
BUNDLE_ID="com.yourcompany.Mini-Capsule"
APP_NAME="Mini Capsule"
VERSION="1.0"
DMG_NAME="${APP_NAME}-${VERSION}"
PROJECT="../Mini Capsule.xcodeproj"
SCHEME="Mini Capsule"
```

### DMG 构建流程（`Scripts/build-dmg.sh`）

1. `xcodebuild archive` — Release 配置，使用 Developer ID 签名和 DMG.entitlements
2. 生成 `.app` bundle
3. `hdiutil` 创建 DMG，含 `/Applications` 快捷方式
4. `codesign --deep --verify` 验证签名
5. `xcrun notarytool submit` 提交 Apple 公证
6. `xcrun stapler staple` 钉上公证票据
7. 输出 `Mini Capsule-1.0.dmg`

### App Store 构建流程（`Scripts/build-appstore.sh`）

1. `xcodebuild archive` — Release 配置，Apple Distribution 签名，AppStore.entitlements
2. 生成 `.xcarchive`
3. `xcodebuild -exportArchive` 导出 `.pkg`（App Store Connect 格式）
4. `xcrun altool --upload-app` 上传到 App Store Connect

### 用户填写清单

脚本顶部标注 `## REPLACE ME` 注释，用户填入：
- `DEVELOPMENT_TEAM` — Apple Developer Team ID
- `BUNDLE_ID` — App 的 Bundle Identifier
- App Store Connect 凭证（邮箱 + 密码/API Key）

## 证书类型对照

| 用途 | 证书 | Xcode 配置 |
|---|---|---|
| 开发调试 | Apple Development | Debug |
| DMG 分发 | Developer ID Application | Release → DMG profile |
| App Store 分发 | Apple Distribution | Release → AppStore profile |

## Info.plist 补充

需要在 `Info.plist` 中补充的字段：

```xml
<key>LSApplicationCategoryType</key>
<string>public.app-category.utilities</string>
<key>LSUIElement</key>
<true/>  <!-- 后台辅助应用，Dock 不显示 -->
```

## App Store 合规检查清单

除 Sandbox 外，App Store 审核还需关注：

| 项目 | 状态 |
|---|---|
| App Sandbox 开启 | 通过 AppStore.entitlements 保证 |
| 隐私说明 | 需在 Info.plist 中添加 `NSPrivacyAccessedAPICategoryDiskSpace` 等 |
| Hardened Runtime | App Store 版本自动处理 |
| 截图/描述/隐私政策 URL | App Store Connect 中填写 |
| 无私有 API | 当前代码使用标准 SwiftUI/AppKit API |
| LSUIElement = true | 菜单栏/浮动面板型 app，不需要 Dock 图标 |

## 文件变更清单

| 文件 | 操作 |
|---|---|
| `Configs/DMG.entitlements` | 新增 |
| `Configs/AppStore.entitlements` | 新增 |
| `Configs/Development.entitlements` | 移动（从 Mini Capsule/） |
| `Mini Capsule/Mini_Capsule.entitlements` | 删除（迁移到 Configs/） |
| `Mini Capsule/Info.plist` | 修改（补充 LSUIElement, LSApplicationCategoryType） |
| `Scripts/common.sh` | 新增 |
| `Scripts/build-dmg.sh` | 新增 |
| `Scripts/build-appstore.sh` | 新增 |
| `Resources/dmg-background.png` | 新增（占位） |
| `BUILD.md` | 新增 |
| `Mini Capsule.xcodeproj/project.pbxproj` | 修改（多 entitlement 配置，Release/Debug scheme） |

## Xcode 项目配置变更

需要在 Xcode 中为 Release 配置关联对应的 entitlement 文件：
- Debug → Development.entitlements
- Release (DMG profile) → DMG.entitlements  
- Release (AppStore profile) → AppStore.entitlements

实际操作中可通过 Build Settings 的 `CODE_SIGN_ENTITLEMENTS` 按 configuration 分别设置，或通过 xcconfig 文件管理。

## 测试策略

- 构建脚本在 CI 可运行性测试（不需要实际证书即可验证脚本语法和流程）
- Entitlement 文件格式验证（plutil -lint）
- Info.plist 格式验证
