# Mini Capsule

一个轻量级的 macOS 剪贴板管理器，提供浮动胶囊 UI 快速访问剪贴板历史。

## 功能

- **剪贴板监听** — 自动捕获文本、图片、文件类型的剪贴板内容
- **浮动胶囊 UI** — 可拖拽的悬浮窗口，鼠标悬停展开/收起
- **图片支持** — 多层读取策略（7 种 UTI + NSImage 回退），保留 GIF 动画
- **全局快捷键** — Carbon 热键，随时随地快速粘贴
- **菜单栏** — NSStatusItem 常驻状态栏，显示最近剪贴内容
- **搜索过滤** — 关键词搜索，键盘上下导航，回车粘贴
- **图钉置顶** — 固定常用内容，支持拖拽排序
- **粘贴历史** — SwiftData 持久化存储，自动清理低频内容
- **多种样式** — 胶囊/圆点/图标三种悬浮窗样式

## 系统要求

- macOS 26.5+
- Apple Silicon / Intel

## 安装

### 下载 DMG

从 [Releases](https://github.com/VbiosWen/Mini-Capsule/releases) 下载最新 DMG，双击打开后将 `Mini Capsule.app` 拖入 `Applications` 文件夹。

首次打开时若提示「无法验证开发者」，请右键点击 App → 打开，或在终端执行：

```bash
xattr -cr /Applications/Mini\ Capsule.app
```

### 所需权限

- **辅助功能** — 用于模拟 Cmd+V 粘贴操作（系统设置 → 隐私与安全性 → 辅助功能）
- **屏幕录制**（可选）— 部分应用的图片剪贴板读取可能需要

## 开发

### 构建

```bash
# macOS（推荐）
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' build

# 个人构建（无需 Apple Developer 账号）
./Scripts/build-personal.sh

# 运行测试
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" -destination 'platform=macOS' test
```

### 打包 DMG

```bash
# 构建 Release 版本
xcodebuild -project "Mini Capsule.xcodeproj" -scheme "Mini Capsule" \
  -configuration Release -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="Mini Capsule/Configs/Personal.entitlements" build

# Ad-hoc 签名
codesign --force --deep --sign - "./DerivedData/Build/Products/Release/Mini Capsule.app"

# 制作 DMG
hdiutil create -volname "Mini Capsule" -srcfolder ./dmg_staging \
  -ov -format UDZO "Mini Capsule.dmg"
```

## 技术架构

| 层 | 技术栈 |
|---|--------|
| UI | SwiftUI + AppKit（NSPanel 悬浮窗） |
| 架构 | MVVM + Services |
| 持久化 | SwiftData（ClipItem） |
| 热键 | Carbon `RegisterEventHotKey` |
| 剪贴板 | NSPasteboard 轮询 + changeCount 差异检测 |
| 粘贴 | CGEvent Cmd+V 模拟 |
| 设置 | Protocol + Store + Actor JSON 持久化 |
| 测试 | Swift Testing |

## 项目结构

```
Mini Capsule/
├── Models/              # 数据模型
│   └── ClipItem.swift   # 核心剪贴项
├── Services/            # 服务层
│   ├── ClipboardMonitor.swift    # 剪贴板轮询
│   ├── PasteService.swift        # 粘贴操作
│   ├── HotKeyCenter.swift        # 全局热键
│   ├── MenuBarService.swift      # 菜单栏
│   └── FrequencyCleanupService.swift  # 清理
├── UI/                  # 视图层
│   ├── CapsuleView.swift         # 根视图
│   ├── CapsuleCollapsedView.swift # 收起状态
│   ├── CapsuleExpandedView.swift  # 展开状态
│   ├── CapsuleViewModel.swift    # 状态管理
│   ├── CapsuleWindowController.swift  # 窗口控制
│   ├── ClipItemRow.swift         # 列表行
│   └── ...
├── Settings/            # 设置模块
│   ├── SettingsStore.swift
│   ├── SettingsPersistence.swift
│   ├── SettingsProtocol.swift
│   └── ...
├── Configs/             # 配置文件
├── Scripts/             # 构建脚本
└── Mini_CapsuleApp.swift # 入口
```

## 许可证

MIT License
