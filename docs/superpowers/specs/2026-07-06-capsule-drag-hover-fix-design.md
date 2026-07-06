# 胶囊长按拖拽 + 悬停展开 — 设计文档

**日期**: 2026-07-06
**状态**: 已确认

---

## 问题

当前 `DragGesture(minimumDistance: 3)` 在胶囊上全局生效，与悬停展开和其他交互产生冲突：
- 点击粘贴 / 列表滚动可能与拖拽手势竞争
- 悬停展开和拖拽没有明确的优先级区分

## 方案

用**长按（0.5s）**区分"想拖窗口"和"想用胶囊"：快速点击和悬停不触发拖拽，按住 0.5 秒后才进入拖拽模式。

---

## 交互时序

```
光标进入胶囊区域
  ├── 悬停 0.3s → 展开窗口（现有逻辑保留）
  │     └── 光标离开 1s → 收起窗口
  │
  └── 按下鼠标 + 保持不动 0.5s → 进入拖拽模式
        ├── 视觉反馈：毛玻璃变亮 + 边框光晕
        └── 开始拖拽 → 窗口跟手移动 → 松手保存位置
```

- 悬停展开（0.3s）不需要按下鼠标，长按拖拽（0.5s）需要按下鼠标，两者不冲突
- 快速按下 + 拖动（< 0.5s）不触发拖拽，防止与列表交互竞争
- 快速点击（< 0.5s 且无明显位移）不触发拖拽，列表项的 onTapGesture 正常响应
- 展开状态下同样可以长按 0.5s 拖拽整个面板
- 收起态下先悬停 0.3s 展开，继续按住 0.2s 后进入拖拽模式

---

## 视觉反馈

进入拖拽准备态（`isDragPrimed = true`）后：

- **背景**：毛玻璃材质上叠加微弱白色 overlay（opacity ~0.1），使窗口看起来更亮/更实
- **边框**：胶囊/面板边缘出现 subtle 光晕：
  - 收起态（Capsule 形）：`shadow(color: .white.opacity(0.3), radius: 6)`
  - 展开态（RoundedRectangle 18pt）：overlay `RoundedRectangle` + `stroke(LinearGradient, lineWidth: 1.5)`
- **两态统一**：收起和展开使用相同的视觉语言，仅适配各自形状

---

## 实现

### CapsuleView.swift — 核心改动

- 新增 `@State isDragPrimed: Bool` — 按住 0.5s 后变为 true
- 新增 `@State isDragging: Bool` — 正在拖拽中
- 新增 `@State dragWorkItem: DispatchWorkItem?` — 延迟任务引用
- 重写 `windowDragGesture`：
  - `minimumDistance: 0`
  - 首次 `onChanged`：启动 0.5s 延迟任务，到时间设 `isDragPrimed = true`
  - `isDragPrimed` 为 true 后才执行窗口 frame 移动
  - `onEnded`：重置 `isDragPrimed`、`isDragging`、`dragStartFrame`，保存位置
  - 鼠标抬起 < 0.5s：取消延迟任务，不触发拖拽
- 将 `isDragPrimed` 传给 `CapsuleCollapsedView` 和 `CapsuleExpandedView`

### CapsuleCollapsedView.swift

- 新增 `isDragPrimed: Bool` 参数
- `isDragPrimed` 为 true 时：
  - 叠加 `Color.white.opacity(0.1)` 在毛玻璃之上
  - shadow 从 `color: .black.opacity(0.15), radius: 8` 变为 `color: .white.opacity(0.3), radius: 6`

### CapsuleExpandedView.swift

- 新增 `isDragPrimed: Bool` 参数
- `isDragPrimed` 为 true 时：
  - 叠加 `Color.white.opacity(0.1)` 在毛玻璃之上
  - overlay `RoundedRectangle(cornerRadius: 18).stroke(LinearGradient(...), lineWidth: 1.5)`

### 不改动

- `CapsuleWindowController.swift`
- `ClipItemRow.swift`
- 所有服务层
