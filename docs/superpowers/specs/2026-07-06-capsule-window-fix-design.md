# 胶囊窗口修复 — 设计文档

**日期**: 2026-07-06
**状态**: 已确认

---

## 问题

1. app 启动时显示一个空的 SwiftUI 主窗口（由 `WindowGroup { EmptyView() }` 产生）
2. 胶囊窗口初始尺寸可能不正确（`loadFrame()` 恢复了大尺寸 frame）

## 修复方案

### Mini_CapsuleApp.swift — 隐藏空窗口 + 转为后台应用

在 `CapsuleAppDelegate.applicationDidFinishLaunching` 中：
- `NSApp.setActivationPolicy(.accessory)` — 隐藏 Dock 图标，防止 SwiftUI 自动创建窗口
- 关闭自动生成的空窗口

### CapsuleWindowController.swift — 恢复位置只取坐标

`loadFrame()` 始终使用 `collapsedSize`（200×36）作为初始尺寸，只恢复 x/y 位置。
