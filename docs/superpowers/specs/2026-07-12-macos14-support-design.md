# macOS 14+ 支持 — 设计文档

**日期:** 2026-07-12  
**状态:** 已批准  
**目标:** 将 Mini Capsule 最低 macOS 部署目标从 26.5 降低至 14.0，让 macOS 14 (Sonoma) 及更高版本的用户可以安装运行。

## 背景

当前项目 `MACOSX_DEPLOYMENT_TARGET` 设置为 26.5，导致 macOS 14/15 用户安装时收到"需要升级系统"的提示，无法使用。代码层面已经有三处 `if #available(macOS 14.0, *)` 兼容性检查，且所有依赖 API 的最低要求均不高于 macOS 14.0。因此只需修改项目配置即可解决。

## 方案选择

选择方案 B（部署目标修改 + 完整审计验证），不选方案 A（缺少验证可能遗漏问题）和方案 C（双构建配置对单项目过度）。

## 设计

### 1. 项目配置变更

**文件:** `Mini Capsule.xcodeproj/project.pbxproj`

将所有 build configuration 中的 `MACOSX_DEPLOYMENT_TARGET` 从 `26.5` 改为 `14.0`。

- iOS / visionOS 的 `IPHONEOS_DEPLOYMENT_TARGET` 保持 `26.5` 不变（占位 target，非本次范围）
- `SWIFT_VERSION` 保持 `5.0`
- 所有 entitlements 文件不变
- `Info.plist` 不变
- 构建脚本（`Scripts/*.sh`）不变

### 2. API 兼容性（零代码改动）

全部 API 均兼容 macOS 14.0 或更早：

| API | 最低 macOS | 状态 |
|-----|-----------|------|
| SwiftData 全套 | 14.0 | ✅ |
| `@Observable` 宏 | 14.0 | ✅ |
| `SettingsLink` | 14.0 | ✅ 已有 `#available` 检查 |
| `showSettingsWindow:` | 14.0 | ✅ 已有 `#available` 检查 |
| `.scrollContentBackground(.hidden)` | 13.0 | ✅ |
| `.focused` / `.popover` / `.contextMenu` | 12.0 / 10.15 | ✅ |
| Carbon 热键 / NSPasteboard / NSPanel | 10.0 | ✅ |

项目未使用任何 macOS 15+ 或 26+ 专用 API。

### 3. 验证计划

| 验证项 | 方法 | 观察点 |
|--------|------|--------|
| 编译通过 | `xcodebuild build` | 无错误、无 API 可用性警告 |
| 单元测试 | `xcodebuild test` | 全部现有测试通过 |
| 悬浮窗交互 | 手动 | hover 展开/折叠、拖拽、键盘导航 |
| 剪贴板捕获 | 手动 | 文本/图片/文件条目正常出现 |
| 粘贴功能 | 手动 | 条目粘贴、Cmd+V 模拟正常 |
| 全局热键 | 手动 | 快捷键响应 |
| 设置面板 | 手动 | 设置持久化、热键录制 |
| DMG 安装 | macOS 14 实机 | 无"需要升级系统"提示 |

## 影响范围

- **代码改动:** 零
- **配置改动:** `project.pbxproj` 中 `MACOSX_DEPLOYMENT_TARGET` 值
- **测试改动:** 无需新增测试
- **构建流程:** 不变
- **分发:** DMG 和 App Store 构建均自动继承新部署目标

## 风险

- **风险低。** SwiftData 和 `@Observable` 都是 macOS 14.0 引入的，14.0 是自然下限。不存在使用旧版 API 导致的运行时崩溃风险。
- 现有 `#available(macOS 14.0, *)` 分支降级后始终走新 API 路径，行为无变化。
