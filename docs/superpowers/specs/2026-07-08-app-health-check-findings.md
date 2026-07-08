# Mini Capsule 健康检查 · 发现报告

**日期**: 2026-07-08
**关联设计**: [2026-07-08-app-health-check-design.md](2026-07-08-app-health-check-design.md)
**方式**: 热点深读（我）+ 4 个并行子代理（广度）+ 关键项实测验证

## 汇总

| 严重度 | 数量 | 说明 |
|---|---|---|
| Critical | 1 | 可轻易触发的崩溃 |
| High | 6 | 核心功能失效 / 数据丢失 |
| Medium | ~14 | 正确性 / 性能 / 一致性 |
| Low / Info | ~25 | 清理 / 风格 / 健壮性 |
| 死代码 | 3 处文件 | grep 确认未被引用 |
| 测试缺口 | 多个关键路径 | 见末节 |

**验证标记**：`✅实测` = 已用可运行代码验证；`✅读证` = 已用源码/grep 确认；`⚠️待验` = 高置信推断，修复阶段用测试确认。

---

## Critical

### C1 · enforceCap `suffix(from:)` 越界崩溃 ✅实测
`Services/ClipboardMonitor.swift:242`
```swift
let toDelete = sorted.filter { !$0.isPinned }.suffix(from: maxCount)
```
`suffix(from:)` 接收的是**起始索引**，不是数量。过滤掉置顶项后，非置顶数组长度可能 < `maxCount`；此时 `suffix(from: maxCount)` 触发 `Fatal error: Range requires lowerBound <= upperBound`。
**触发条件极易达成**：默认 `historyMaxCount = 200`，当历史攒到 200 条且**只要有 ≥1 条置顶**，非置顶=199 < 200 → 下一次复制即崩溃，且会反复崩溃。
实测复现：对 3 元素数组 `suffix(from: 200)` → 崩溃。
**修复**：改用「保留前 N、删除其余」的正确语义，例如 `sorted.filter{!$0.isPinned}.dropFirst(maxCount)`，并对空/越界安全。同时修正下方 M1 的容量语义。

---

## High

### H1 · 全局快捷键对后台应用无效 ✅读证
`Mini_CapsuleApp.swift:85`（`registerShortcuts`）
显示/隐藏、快速粘贴、切换置顶都靠 `NSEvent.addLocalMonitorForEvents` 注册。**本地监听只在本 App 为前台活跃应用时才收到按键**；而本应用是 `.accessory` 后台应用（`Mini_CapsuleApp.swift:31`），几乎从不前台。grep 确认全项目**没有任何** `addGlobalMonitorForEvents`。
后果：在别的 App 里按全局热键唤出胶囊——主用途——**完全不工作**。
**修复**：全局热键改用 `addGlobalMonitorForEvents`（只读，不能吞事件）+ 本地监听组合，或 Carbon `RegisterEventHotKey` / `CGEventTap`。需辅助功能/输入监控权限，UI 要提示授权。

### H2 · 默认快捷键字符串永不匹配 ✅读证
`Settings/SettingsData.swift:15-16` vs `Mini_CapsuleApp.swift:117`、`ShortcutsSettingsView.swift:48`
默认值存的是大写 `"cmd+shift+V"` / `"cmd+shift+C"`，但匹配器与录制器都用 `charactersIgnoringModifiers?.lowercased()` 生成 `"cmd+shift+v"`。字符串比较永不相等 → **出厂默认快捷键从不触发**（即便修好 H1 也一样）。
**修复**：默认值改小写 `"cmd+shift+v"` / `"cmd+shift+c"`；并把「事件→字符串」抽成 H2/H1 共用的单一函数（见 M-dup）。

### H3 · 升级即丢设置（迁移缺陷）✅实测
`Settings/SettingsData.swift` + `Settings/SettingsPersistence.swift:16-23`
`SettingsData` 用编译器合成的 `Decodable`。实测确认：**合成解码器忽略属性默认值**，JSON 缺任一 key 就抛 `keyNotFound`。`load()` 用 `try?` 兜底 → 返回**全默认**。
后果：未来任何版本给 `SettingsData` 加一个字段，老用户磁盘上的 `settings.json` 缺新 key → 启动时**全部设置被重置**。
**修复**：实现自定义 `init(from:)` 用 `decodeIfPresent(...) ?? 默认值` 做逐字段容错合并（前后向兼容），并加分区版本/迁移测试。

### H4 · 复制/粘贴历史项产生重复条目（isSelfPaste 失效）⚠️待验
`Services/PasteService.swift:52-53` 与 `:115-116`
```swift
isSelfPaste = true
defer { isSelfPaste = false }   // 同步、微秒级即复位
```
`isSelfPaste` 用于让轮询跳过「自己写入剪贴板」的变更。但它在函数返回时**同步复位**，而 `ClipboardMonitor` 只在**异步轮询**（最长 0.5s 后）才读它（`ClipboardMonitor.swift:80`）。轮询时 flag 早已 false → 自己写入的内容被当作新内容重新捕获。
具体表现：`paste()` 不更新 `timestamp`，粘贴一个非最新的旧项后，下次轮询把它当新内容**插入重复条目**（dedup 开关都挡不住，因为文本 dedup 只比对「最新项」）。关闭 dedup 时复制也会重复。
**修复**：让抑制窗口覆盖到下一次轮询——例如记录「自写入的 changeCount」并在轮询里对比跳过，或用时间窗口而非同步 flag。

### H5 · 每次启动把历史悄悄裁到 50 条 ✅读证
`Services/FrequencyCleanupService.swift:11-14` + `Mini_CapsuleApp.swift:47-51`
清理保留数 `count >= 50 ? min(50, count) : 50` **恒等于 50**（`min(50, ≥50)` 永远是 50）；且启动处又硬编码 `keepCount: 50`。
后果：用户把「历史上限」设到 1000、复制了 200 条，**重启后非置顶项被裁到只剩 50 条**（按 pasteCount 取高）。`historyMaxCount` 设置形同虚设 → 数据丢失。
**修复**：保留数应跟随 `historyMaxCount`；去掉恒为 50 的表达式与硬编码。

### H6 · “启动时清理”开关被忽略 ✅读证
`Mini_CapsuleApp.swift:45-51`（`finishSetup`）
`finishSetup` **无条件**调用 `FrequencyCleanupService.performCleanup`，从不检查 `settingsStore.cleanupOnStartup`（默认 true）。用户关掉该开关也照样清理（并叠加 H5 的裁到 50）。
**修复**：`guard settingsStore.cleanupOnStartup else { ... }` 后再清理。

---

## Medium

- **M1 · 容量语义不一致 + off-by-one** `ClipboardMonitor.swift:233-246`：`enforceCap` 在插入前判 `>= maxCount` 再删到 maxCount，最终停在 maxCount+1；且与 `FrequencyCleanupService` 各写一套裁剪逻辑、语义不同（maxHistoryCount vs 50），会互相打架。建议统一为单一容量服务。
- **M2 · 设置写入乱序竞态** `SettingsStore.swift:34-39`：每个 setter 都 `Task { await persistence.save(snapshot) }`。拖动滑块时多个 Task 各带自己的快照并发落盘，actor 串行化但**执行顺序不保证**，可能后写的是旧快照 → 丢更新。建议串行化/去抖（单一写入队列或合并写）。
- **M3 · 列表每帧重复 fetch** `ClipboardListViewModel.swift:50-83` + `CapsuleExpandedView.swift:42,156,159,209`：`filteredItems` 是每次访问都 `fetch+sort` 的计算属性，且在 body 内被多次读取 → 每帧多次数据库查询。建议每次更新缓存一次（`@State`/单一 `let`）。
- **M4 · 悬浮 popover 卡死** `ClipItemRow.swift:16,63-107`：单个 `hoverTask` 被 hover-in / hover-out / popover-dismiss 复用，重叠切换互相取消，`showPopover` 可能在鼠标离开后卡在 true。建议 show/dismiss 分离句柄或小状态机；并在 `.onDisappear` 取消。
- **M5 · 大图主线程整图解码** `ClipItemRow.swift:237,165-167`：36×36 缩略图与预览都在 body 内 `NSImage(data:)` 解全分辨率位图、逐行执行，无降采样 → 大图卡顿。建议离屏预计算并缓存缩略图。
- **M6 · 快捷键冲突检测用陈旧值** `ShortcutsSettingsView.swift:68,73,78`：`otherShortcuts` 在 init 时按值捕获，录新键不刷新兄弟行 → 漏报/误报冲突。建议在检测时从实时 `settings` 读。
- **M7 · 危险操作弹窗靠标题字符串分派** `AdvancedSettingsView.swift:67-78`：同一 `alertTitle` 状态既做「清空历史/重置设置」的动作判定，又复用于错误弹窗，字符串分派脆弱、破坏性按钮样式会串到普通错误弹窗。建议用 `enum AlertKind`。
- **M8 · capImageSize 单次缩放常超标 + 逻辑重复** `ClipboardMonitor.swift:212-231` 与 `AppearanceSettingsView.swift:117-120`：按 `sqrt(maxBytes/count)` 假设「文件大小∝像素面积」，JPEG 并不成比例，单次常仍超 `maxBytes` 且逻辑在两处重复。建议抽公共工具并循环/二分压到目标内。
- **M9 · 关 dedup 仍写 MD5，切回开态不一致** `ClipboardMonitor.swift:115-131` + `ClipItem`：dedup 关闭时插入的图片仍带 MD5，重开 dedup 后历史里已有的重复项处理不一致；且 dedup-on 分支重复算了两次 MD5。建议在分支前只算一次并统一策略。
- **M10 · 文本 dedup 只比最新项** `ClipboardMonitor.swift:136-149`：复制 A、B、A → 第二个 A 不去重（只比最新）。与图片 dedup（全表 MD5）语义不一致。确认预期后统一。
- **M11 · resetAll 不发通知，重置只半生效** `SettingsStore.swift:215-218`：`resetAll` 改了 collapsedStyle/ringDiameter/pollingInterval 却没 post `.capsuleStyleDidChange` / `.pollingIntervalDidChange` → 胶囊样式/尺寸、轮询间隔要重启才更新。建议重置后补发相关通知。
- **M12 · ClipItem.id 非唯一** `Models/ClipItem.swift:7`：UI 选择/查找都基于存储的 `var id: UUID`，但没有 `@Attribute(.unique)`；导入等场景一旦 id 重复，`firstIndex(where:{$0.id==})` 选择逻辑会错乱。建议标 `@Attribute(.unique)`。
- **M13 · toHex 颜色空间/截断错误** `Utilities/ColorHex.swift:18-24`（注：整文件为死代码，见下）：未转 sRGB 就读 `cgColor.components`，非 RGB 色彩空间静默回退 `#007AFF`，P3 出错，且 `Int(x*255)` 截断非四舍五入。若将来启用需修；否则随死代码删除。
- **M14 · 导入不设容量上限** `SettingsStore.swift:241-265`：`importData` 直接插入，不做 `historyMaxCount` 约束，可超上限。建议导入后统一走容量服务。

---

## Low / Info / Cleanup（分组）

**并发/生命周期健壮性**
- `ClipboardMonitor.swift:55-63` 设置观察者未在 `stop()` 移除；`start()` 可重复调用叠加观察者。
- `MenuBarService.swift:41-47` 监听 `UserDefaults.didChangeNotification` 的**空回调**（设置早已迁到 JSON），纯无用且未移除。
- `CapsuleViewModel.swift:120-127` `postExpandedNotification` 在 asyncAfter 闭包里强引用 `self`（0.05s）。
- 面板回调里 `@State` 变更 + 同步大文件读/SwiftData 保存跑在主线程：`AppearanceSettingsView.swift:101-114`、`AdvancedSettingsView.swift:97-142`。
- `CopyFeedbackView.swift:33-37`、`ClipItemRow.swift:64-71` 的 Task 未在 `.onDisappear` 取消。

**正确性小问题**
- `CapsuleCollapsedView.swift:105` 文本为空串/纯换行时胶囊空白（`?? ""` 只挡 nil）。
- `PopoverEditorView.swift:15,38-41` 编辑器 `@State` 复用致旧文本；空串可覆盖原文本、无 trim/空判。
- `ClipItemRow.swift:200-217` 图片零尺寸 → 0 框不可见 popover；`:165-183` 无可渲染内容仍弹空 popover。
- `CopyFeedbackView.swift:24-27` 连续复制同一项 `lastCopiedItemID` 不变 → 「已复制」提示不再弹。
- `CapsuleView.swift:58` 顶部项被重复复制（id 不变、时间戳变）时捕获动画不触发。
- `ClipboardSettingsView.swift:15` Stepper 限 50…1000 但 store/monitor 只兜下界，导入的越界值被采纳。
- `ShortcutsSettingsView.swift:50-51` 修饰键-only 守卫集合 `["","\u{7F}"]` 冗余/不准。
- `GeneralSettingsView.swift:24-27` `showInMenuBar` 关闭走「写后纠正」，有瞬时 false。

**风格/一致性/可维护性**
- 死代码：见下节（`Item.swift`、`ContentView.swift`、`ColorHex.swift`）。
- Stringly-typed：`contentTypeRaw` 与 `collapsedStyle` 全用 `"text"/"image"/"file"`、`"dot"/"icon"/"capsule"` 魔法串散落多处（`ClipboardMonitor`、`ClipItemRow`、`CapsuleWindowController`…），拼错静默失效 → 建议各抽 enum。
- `copyToClipboard` 文档注释写「Updates usage stats」但实现并不更新（`PasteService.swift:50`）。
- `NotificationNames.swift` raw value 命名不统一（`Settings*` vs 裸 camelCase）。
- 设置视图大量重复：`LabeledContent+Slider/Stepper/Picker+尾值` 与 `.frame(width:450)`、`.formStyle(.grouped)` 到处复制 → 抽 `SettingSlider/Stepper/Picker` + 容器修饰符。
- `CapsuleExpandedView.swift:56-71` 三段近似 `onReceive` 解 `userInfo["itemID"]` → 抽 helper。
- `iCloudSyncEnabled` 字段被持久化但 UI 恒 `.constant(false)`（`AdvancedSettingsView.swift:27`）→ 死配置。

**项目/文档（基线阶段已发现）**
- `#0` CLAUDE.md 的 `xcodebuild` 命令在本机需 `DEVELOPER_DIR` 指向 Xcode；且 CLAUDE.md 架构描述完全过时（仍写 iOS `Item` 模板）。
- `#1` `.xcodeproj` Compile Sources 阶段重复引用 `UI/ClipboardListViewModel.swift`（构建告警）。
- `#2` 带 entitlements 的签名构建需开发证书（发布相关）。

---

## 死代码（grep 确认未引用）

- **`Mini Capsule/Item.swift`** — 仅出现在两处 `Schema([Item.self, ClipItem.self])`（`Mini_CapsuleApp.swift:11,162`）与死掉的 `ContentView`。运行路径无任何创建/查询。删除并从两个 Schema 数组移除。
- **`Mini Capsule/ContentView.swift`** — 只在 `#else`（非 macOS）`WindowGroup` 用；macOS 走 `CapsuleAppDelegate` + `Settings` 场景，`ContentView` 在 macOS 被编译掉、永不显示。若不发 iOS/visionOS，整文件删除。
- **`Mini Capsule/Utilities/ColorHex.swift`** — `Color(hex:)`/`toHex()` 全项目零引用。删除，或接入本要用它的强调色设置（届时先修 M13 与 hex 解析）。

> 注：`Item` + `ContentView` + iOS `WindowGroup`/`sharedModelContainer` 是一整团 iOS 模板残留；macOS 上唯一存活模型是 `ClipItem`。三者可一并清理。

---

## 测试缺口（重点）

现有 71 个测试偏重设置/ViewModel 的取值断言，**核心业务路径几乎无覆盖**：
- **ClipboardMonitor**：捕获管线、text/image dedup、`md5Hash`、`enforceCap`（正是 C1 崩溃处）、`capImageSize`、类型优先级、self-paste 跳过——全无测试。
- **PasteService**：`copyToClipboard` 内容路由、`isSelfPaste` 复位（正是 H4）、`paste` 统计——无测试。
- **FrequencyCleanupService**：整服务无测试（正是 H5/H6）。
- **SettingsStore**：`importData`/`exportData` 往返、`clearAllHistory`、`replaceData` 不持久化契约——无测试。
- **SettingsPersistence**：部分/前向兼容 JSON（正是 H3）、并发写——无测试；且测试直接读写真实 `~/.minicapule`（应注入临时目录）。
- **KeyboardEventHandler / CapsuleWindowController.loadFrame 越界钳制 / MenuBarService.previewText**：可测但未测。
- 若干**弱测试**（`>=`/非空断言掩盖回归）：`PasteServiceTests`、`ClipboardListViewModelTests:171-191,272-287`、`ColorHexTests`。

可测性重构机会：给 `ClipboardMonitor` 注入 pasteboard/frontmost-app 抽象；把 `KeyboardEventHandler` 路由与 `shortcutString(from:)` 抽成纯函数。

---

## 建议修复分阶段（供你挑选）

- **阶段 1 — Critical/High（改行为，逐个隔离+测试）**：C1、H1、H2、H3、H4、H5、H6。
- **阶段 2 — 行为保持的中等重构**：统一容量服务（M1/M8/M14）、设置写入去抖（M2）、列表 fetch 缓存（M3）、hover/popover 状态机（M4/M5）、stringly-typed→enum、抽共用 `shortcutString` 与设置控件。
- **阶段 3 — 清理**：删死代码（3 文件 + Schema）、修 `.xcodeproj` 重复引用、刷新 CLAUDE.md、补关键路径测试、注入临时目录的持久化测试。

每阶段前用 `writing-plans` 排计划，按 TDD / systematic-debugging 执行；每批后 build+test 保持绿；窗口/粘贴/热键类改动标注需实机验证。
