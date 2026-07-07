# JSON 设置持久化设计

**日期**: 2026-07-08
**状态**: 已批准

## 目标

将 Mini Capsule 的设置存储从 `UserDefaults` 完全替换为 JSON 文件持久化。设置文件存放于 `~/.minicapule/settings.json`，启动时加载，运行时修改即时写回。

## 架构

三层分离：

```
┌─────────────────────────────────┐
│  Views (SwiftUI)                │  ← 通过 @Environment 读取设置
├─────────────────────────────────┤
│  SettingsStore (@Observable)    │  ← 内存中的设置，SwiftUI 绑定源
│  持有 SettingsData 实例          │
│  getter → 读内存，setter → 写内存 + 触发持久化 │
├─────────────────────────────────┤
│  SettingsPersistence (actor)    │  ← 文件 I/O：加载/保存 JSON
│  路径: ~/.minicapule/settings.json │
├─────────────────────────────────┤
│  SettingsData (Codable struct)  │  ← 纯数据模型，所有设置值 + 默认值
│  编译时类型安全，自动 Codable 编解码 │
└─────────────────────────────────┘
```

### 各层职责

| 层 | 职责 | 状态 |
|---|---|---|
| `SettingsData` | Codable struct，定义所有设置字段及其默认值 | 新增 |
| `SettingsPersistence` | actor 隔离文件读写，创建目录，处理损坏/缺失 | 新增 |
| `SettingsStore` | 持有内存中的 SettingsData，对外暴露计算属性 | 重构 |
| `SettingsProtocol` | 保持现有协议不变 | 不变 |
| `SettingsKey` | 不再需要 rawValue 映射 UserDefaults key | 删除 |

## 数据模型

### SettingsData

```swift
struct SettingsData: Codable, Equatable {
    // Clipboard
    var historyMaxCount: Int = 200
    var imageMaxSizeMB: Int = 2
    var pollingInterval: Double = 0.5
    var cleanupOnStartup: Bool = true
    var dedupEnabled: Bool = true

    // Shortcuts
    var showHideShortcut: String = "cmd+shift+V"
    var quickPasteShortcut: String = "cmd+shift+C"
    var togglePinShortcut: String = ""

    // Advanced
    var iCloudSyncEnabled: Bool = false

    // General
    var launchAtLogin: Bool = false
    var showInMenuBar: Bool = true
    var showFloatingPanel: Bool = true
    var collapsedStyle: String = "capsule"
    var hoverExpandDelay: Double = 0.3
    var hoverCollapseDelay: Double = 1.0

    // Appearance
    var panelOpacityUnfocused: Double = 0.6
    var backgroundImageData: Data = Data()
    var ringDiameter: Double = 30
    var capsuleWindowFrame: Data = Data()
}
```

所有属性有默认值，`SettingsData()` 即默认配置。所有类型均为 Codable 原生类型，编解码由编译器自动生成。

## 持久化层

### SettingsPersistence

```swift
actor SettingsPersistence {
    private let fileURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".minicapule")
        self.fileURL = dir.appendingPathComponent("settings.json")
    }

    func load() -> SettingsData {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(SettingsData.self, from: data)
        else { return SettingsData() }
        return settings
    }

    func save(_ data: SettingsData) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: fileURL, options: .atomic)
    }
}
```

### 行为规范

- `load()` 不抛异常：文件缺失或 JSON 损坏 → 静默返回默认值
- `save()` 抛异常：由调用方处理（记录日志或重试）
- `options: .atomic`：先写临时文件再 rename，防止写一半崩溃导致文件损坏
- 首次启动自动创建 `~/.minicapule/` 目录

## SettingsStore 重构

```swift
@MainActor
@Observable
final class SettingsStore: SettingsProtocol {
    private var data: SettingsData
    private let persistence = SettingsPersistence()

    init(data: SettingsData) {
        self.data = data
    }

    var historyMaxCount: Int {
        get { data.historyMaxCount }
        set {
            data.historyMaxCount = newValue
            persist()
        }
    }

    // 其余属性模式相同

    private func persist() {
        let snapshot = data
        Task { [snapshot] in
            try? await persistence.save(snapshot)
        }
    }

    func resetAll() {
        data = SettingsData()
        persist()
    }
}
```

### 关键设计决策

- `persist()` 捕获当前 `data` 的快照，异步写文件不阻塞 UI
- 设置修改频率低，不需要防抖合并
- `resetAll()` 创建新的 `SettingsData()` 赋值后写回文件

## 启动流程

在 `CapsuleAppDelegate.applicationDidFinishLaunching` 中：

```swift
let persistence = SettingsPersistence()
let settingsData = await persistence.load()
let store = SettingsStore(data: settingsData)
self.settingsStore = store
// 首次启动时文件不存在，写入默认配置确保文件就位
try? await persistence.save(settingsData)
```

## 错误处理

| 场景 | 行为 |
|---|---|
| 目录不存在 | 首次 save/load 时自动创建 |
| 文件不存在 | load() 返回默认值，下次 save 时创建文件 |
| JSON 解析失败 | load() 返回默认值，下次 save 时覆盖损坏文件 |
| 写入失败（磁盘满/权限） | save() 抛异常，SettingsStore 静默忽略（try?），不影响 UI |

## 文件变更清单

| 文件 | 操作 |
|---|---|
| `Settings/SettingsData.swift` | 新增 |
| `Settings/SettingsPersistence.swift` | 新增 |
| `Settings/SettingsStore.swift` | 重构 |
| `Settings/SettingsKey.swift` | 删除 |
| `Settings/SettingsProtocol.swift` | 不变 |
| `Mini_CapsuleApp.swift` | 修改启动逻辑 |
| `Settings/SettingsStoreTests.swift` | 新增（JSON 编解码往返测试）|
| `Settings/SettingsPersistenceTests.swift` | 新增（文件读写测试）|

## 测试策略

- `SettingsData` 编解码往返测试：编码 → 解码 → 断言值一致
- `SettingsPersistence` 用临时目录注入测试：
  - 空目录 → load 返回默认值
  - 写入后 load → 返回写入的值
  - 损坏 JSON → load 返回默认值
- `SettingsStore` 测试：注入已知 SettingsData，验证属性读写和 persist 触发
