# Image Pasteboard Capture — 通用图片剪贴板捕获

**Date:** 2026-07-08
**Status:** approved

## Problem

ClipboardMonitor 只通过 `public.png` 和 `public.tiff` 两个 UTI 检测图片。微信公众
号等 app 使用自定义 pasteboard 类型，导致右键"复制图片"无法被胶囊捕获。此外
JPEG、HEIC、GIF 等常见格式也未覆盖。

## Design

### 分层读取策略（`readPasteboard` 方法）

| 优先级 | 方法 | 覆盖场景 | 格式保留 |
|--------|------|---------|---------|
| 1 | 遍历已知图片 UTI，读原始 Data | PNG / JPEG / TIFF / GIF / HEIC / BMP | ✅ 原始格式（GIF 动画不丢） |
| 2 | `readObjects(forClasses: [NSImage.self])` 兜底 | 微信等自定义类型 | ❌ 转 PNG |
| 3 | `.fileURL` | 文件引用 | — |
| 4 | `.string` | 纯文本 | — |

### 已知图片 UTI 列表

- `public.png` (`.png`)
- `public.tiff` (`.tiff`)
- `public.jpeg` (`.jpeg`)
- `com.compuserve.gif` (GIF)
- `public.heic` (HEIC)
- `public.heif` (HEIF)
- `com.microsoft.bmp` (BMP)

### 新增 helper

`nsImageToPNGData(_ nsImage: NSImage) -> Data` — NSImage → TIFF → NSBitmapImageRep → PNG，仅用于兜底路径。

### 改动文件

仅一个文件：`Mini Capsule/Services/ClipboardMonitor.swift`

- `readPasteboard()`: 重写图片检测，分层读取
- 新增 `nsImageToPNGData()`: NSImage 转 PNG Data

`checkPasteboard()` 中的去重、上限、插入逻辑不变。`capImageSize()`、
`extractFileName()` 不变。

### 边界情况

| 场景 | 行为 |
|------|------|
| GIF 动图 | 优先路径读到原始 GIF Data，动画完整保留 |
| 微信复制图片 | NSImage 兜底，转 PNG 存储 |
| HEIC 照片 | 优先路径读原始 HEIC Data |
| Finder 复制图片文件 | fileURL 上有图片 UTI，优先路径识别为图片 |
| 超大图片 | `capImageSize()` 压缩逻辑不变 |

## Implementation Plan

1. 在 `readPasteboard()` 中定义已知图片 UTI 列表
2. 遍历列表，`pb.data(forType:)` 读取原始数据
3. 已知类型都未命中时，用 `pb.readObjects(forClasses: [NSImage.self])` 兜底
4. 新增 `nsImageToPNGData()` helper
5. 更新 `ClipboardMonitorTests` 测试新路径
