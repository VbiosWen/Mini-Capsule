# 图片预览 — 设计文档

**日期**: 2026-07-06
**状态**: 已确认

---

## 问题

复制到剪贴板的图片内容在列表中只显示文字标签（"图片"），用户无法快速确认是哪张图。

## 方案

点击图片条目时在条目右侧弹出 200×200 的预览浮层，点击其他区域关闭。

---

## 交互

- **触发**：点击 `contentTypeRaw == "image"` 的条目 → 条目右侧弹出 200×200 预览浮层
- **关闭**：点击展开面板内其他区域（其他条目、搜索栏、空白处）→ 预览消失
- **图片非图片区分**：图片条目的点击弹出预览，不执行粘贴；文本/文件条目点击仍执行粘贴
- **图片缩放**：`aspectRatio(contentMode: .fit)` 等比缩放，不裁剪

## 视觉

- 预览浮层：`.ultraThinMaterial` 背景，`RoundedRectangle(cornerRadius: 12)`
- 固定尺寸：200×200
- 位置：条目行右侧偏移 8pt

---

## 实现

### ClipItemRow.swift

- 新增 `@State private var showImagePreview: Bool`
- 图片条目点击时 `showImagePreview.toggle()`
- 通过 `.overlay` 在条目右侧展示预览：
  ```
  HStack { Spacer().frame(width: rowWidth + 8); Image(nsImage: ...) }
  ```
- 新增 `var onPreviewStateChanged: ((Bool) -> Void)?` 回调通知父视图

### CapsuleExpandedView.swift

- 监听 `onPreviewStateChanged` 记录当前展开预览的条目
- 点击其他条目时关闭预览
- 搜索栏文本变化时关闭预览

### 不改动

- `CapsuleView.swift`
- `CapsuleCollapsedView.swift`
- `CapsuleWindowController.swift`
- 服务层
