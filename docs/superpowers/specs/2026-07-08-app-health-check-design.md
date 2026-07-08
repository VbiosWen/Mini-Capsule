# 全应用健康检查与重构设计

**日期**: 2026-07-08
**状态**: 待批准

## 目标

对 Mini Capsule（macOS 菜单栏剪贴板管理器，约 3600 行源码 / 29 个 Swift 文件）做一次**主动健康检查**：系统性审查全部代码，挖出潜在 bug，并在**中等力度**下做有针对性的重构。核心约束：

- **审查优先**：先产出一份分级的发现报告供用户过目，再分批修复/重构。
- **中等重构**：允许重划模块边界、抽取服务/协议、统一状态管理；但**用户可见行为保持不变**。
- **修 bug 可改行为**（这是修复的本意）；**重构必须保持行为**。两者分批进行，互不混淆。

## 非目标（YAGNI）

- 不做大规模架构重写（不重组窗口/状态分层、不引入新交互模式）。
- 不改动用户可见的 UX / 视觉（除非是修复明确的 bug）。
- 不做与健康检查无关的重构或"顺手美化"。
- 不新增功能。

## 当前基线

在读正式代码前，建立可验证基线时已发现：

| # | 严重度 | 类别 | 现象 |
|---|---|---|---|
| #0 | Low | 文档 | CLAUDE.md 记录的 `xcodebuild` 命令在本机直接跑失败，需 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（活跃目录是 CommandLineTools） |
| #1 | Medium | 项目配置 | `.xcodeproj` 的 Compile Sources 阶段重复引用了 `UI/ClipboardListViewModel.swift`（构建告警 "Skipping duplicate build file"） |
| #2 | Info | 发布 | 带 entitlements 的签名构建需开发证书；CLI 纯 `build` 失败，验证时用 `CODE_SIGNING_ALLOWED=NO` 绕过 |

**编译基线**：`DEVELOPER_DIR=... xcodebuild ... CODE_SIGNING_ALLOWED=NO build` → `BUILD SUCCEEDED`。
**测试基线**：以同样参数运行 `test` → **71 个测试 / 13 个套件全部通过**（约 6.7s）。安全网就绪。

## 审查方式：混合（C）

3600 行分成清晰的子系统（Services / UI / Settings / Models / Utilities）。采用混合策略：

**热点（我自己深读，需跨文件整体上下文）** —— 并发、AppKit 生命周期、事件监听、剪贴板/粘贴这类高发 bug 区：

- `Services/ClipboardMonitor.swift`（轮询 / changeCount / 线程）
- `Services/PasteService.swift`（辅助功能权限 / 事件注入）
- `Services/MenuBarService.swift`、`Services/FrequencyCleanupService.swift`
- `UI/CapsuleWindowController.swift`（NSWindow 生命周期 / 拖拽）
- `UI/KeyboardEventHandler.swift`（全局 / 本地事件监听）
- `UI/CapsuleViewModel.swift`、`UI/ClipboardListViewModel.swift`（状态管理）
- `Mini_CapsuleApp.swift`（App 生命周期 / 装配）
- `Settings/SettingsStore.swift`、`Settings/SettingsPersistence.swift`（actor / 并发 / 持久化）

**广度（派并行子代理审查，相对独立、低风险）**：

- 子代理 A：`Settings/` 下五个设置视图（Appearance/General/Clipboard/Advanced/Shortcuts）+ `SettingsData`/`SettingsProtocol`/`NotificationNames`
- 子代理 B：`UI/` 展示层（CapsuleView/CapsuleCollapsedView/CapsuleExpandedView/ClipItemRow/CopyFeedbackView/PopoverEditorView）
- 子代理 C：`Models/ClipItem.swift`、`Item.swift`、`Utilities/ColorHex.swift`、`ContentView.swift`（疑似 iOS 模板残留）
- 子代理 D：测试套件覆盖缺口审查（对照发现的 bug 看哪些没被测到）

子代理只做只读审查，按统一格式回报发现；跨文件关联与最终定级由我汇总。

## 审查重点类别

1. **并发 / 线程** —— 轮询定时器、actor 隔离、`@MainActor` 正确性、跨线程访问 UI
2. **内存 / 生命周期** —— 循环引用、`NotificationCenter` / 事件监听 / KVO 未移除、`Timer` 未 invalidate、窗口控制器释放
3. **AppKit ↔ SwiftUI 桥接** —— 窗口管理、全局/本地事件监听、`NSPasteboard.changeCount` 语义
4. **数据正确性** —— `ClipItem` 去重 / MD5、剪贴板变更检测、设置 JSON 读写往返 / 迁移 / 损坏处理
5. **边界条件** —— 空 / 超大剪贴板、图片、频率清理逻辑、并发写
6. **错误处理** —— paste 失败、辅助功能权限缺失、文件 I/O 异常
7. **状态管理一致性** —— 多处状态源是否可统一（中等重构机会）
8. **死代码 / 陈旧** —— `Item.swift` / `ContentView.swift` 模板残留、过时的 CLAUDE.md、未用符号
9. **测试覆盖缺口** —— 关键路径与已发现 bug 的测试缺失

## 发现报告格式

审查产出存入 `docs/superpowers/specs/2026-07-08-app-health-check-findings.md`，每条：

```
ID · 严重度(Critical/High/Medium/Low/Info) · 类别(Bug/重构/清理/文档) · 位置(file:line) · 现象与原因 · 建议修复 · 风险与影响
```

按严重度排序，附一页汇总表。用户过目后决定修哪些。

## 验证与安全网

- 所有构建 / 测试统一用 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` + `CODE_SIGNING_ALLOWED=NO`。
- 每批修改后重跑 `build` + `test`，必须保持绿色。
- 自动化测试覆盖不到的 AppKit 行为（窗口拖拽、粘贴注入、全局热键、菜单栏），在报告中**标注为需用户手动验证**，修复后请用户实机确认。

## 报告通过后的分阶段修复

| 阶段 | 内容 | 行为 |
|---|---|---|
| 0 | 绿色基线（build + test） | —— |
| 1 | 修 Critical / High bug，逐个隔离 + 验证 | 允许改行为（修复本意） |
| 2 | 中等重构：重划边界、去重、拆大文件、统一状态 | 保持行为不变 |
| 3 | 清理：死代码、陈旧文档、补测试缺口 | 保持行为不变 |

每个阶段前用 `writing-plans` 把用户批准的条目排成实施计划，再按 TDD / systematic-debugging 执行。

## 成功标准

- 一份完整、分级、可执行的发现报告，用户认可其覆盖面。
- 用户批准的 bug 全部修复，且有测试或手动验证证据。
- 批准的重构完成后，构建 + 测试仍绿，行为无回退。
- 死代码 / 陈旧文档清理完毕，CLAUDE.md 反映真实结构。
