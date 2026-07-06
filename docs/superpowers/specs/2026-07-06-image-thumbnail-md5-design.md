# 图片条目优化 + MD5 去重 — 设计文档

**日期**: 2026-07-06
**状态**: 已确认

---

## A1：图片名称显示

- 有文件名 → 显示文件名（如 `screenshot.png`）
- 无文件名 → 显示 `来源APP-短ID`（如 `Safari-a3f2`，短 ID 为 UUID 前 4 位）
- ClipItem 新增 `imageFileName: String?`

### 文件名来源

`ClipboardMonitor.readPasteboard` 中，检测图片时同时尝试读取粘贴板的文件名。某些 app（Finder、Preview）会在粘贴板中同时放入文件 URL，可以从中提取文件名。

---

## A2：左侧缩略图

- 图片条目（`contentTypeRaw == "image"`）：左侧 36×36 缩略图
- 图片等比填充（`aspectRatio(contentMode: .fill)`），裁剪为 `RoundedRectangle(cornerRadius: 6)`
- 文本/文件条目保持原有 SF Symbol 图标不变
- 实现：ClipItemRow 的 typeIcon 根据类型分流

---

## A3：悬停预览

- 仅图片条目悬停时弹出 popover（通过 `Binding(get: { isHovering && item.contentTypeRaw == "image" })` 控制）
- 预览尺寸最大 200×300，小图不放大

---

## D：图片 MD5 去重

### 数据模型

ClipItem 新增 `imageMD5: String?`

### 去重流程

1. `ClipboardMonitor` 捕获图片时对 `imageData` 计算 MD5
2. 查询 SwiftData 中是否有 `imageMD5` 相同且 `contentTypeRaw == "image"` 的记录
3. 有 → 更新该记录的 `timestamp`（置顶），不新增
4. 无 → 正常插入新记录

### MD5 计算

使用 `CommonCrypto` 或 `CryptoKit` 的 `MD5Digest`

---

## 改动范围

| 文件 | 改动 |
|------|------|
| `ClipItem.swift` | 新增 `imageFileName: String?`、`imageMD5: String?` |
| `ClipboardMonitor.swift` | 提取图片文件名 + 计算 MD5 + MD5 去重查询 |
| `ClipItemRow.swift` | 图片名称 + 左侧缩略图 + 仅图片弹 popover（已修复） |

### 不改动

- CapsuleView、CapsuleCollapsedView、CapsuleExpandedView、CapsuleWindowController
- PasteService、FrequencyCleanupService
