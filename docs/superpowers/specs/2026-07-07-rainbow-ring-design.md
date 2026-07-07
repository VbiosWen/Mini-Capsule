# Rainbow Ring: Replace Dot with Adjustable Rainbow Ring

Date: 2026-07-07

## Overview

Replace the current solid-color "dot" collapsed style with a static rainbow gradient ring. The ring size is freely adjustable via a slider in Appearance settings (20–200px diameter, default 60px). The old dot color settings (`dotColorMode`, `dotCustomColor`) are removed since the ring is always rainbow.

## 1. View Layer — Rainbow Ring in CapsuleCollapsedView

**Current state:** `dotView` renders a 12×12 filled `Circle()` with a solid color determined by content type (auto) or a custom hex color (custom).

**Change:** Replace `dotView` with `ringView` — a stroked `Circle()` with a rainbow `AngularGradient`:

```swift
private var ringView: some View {
    Circle()
        .stroke(
            AngularGradient(
                colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                center: .center
            ),
            lineWidth: max(2, settings.ringDiameter * 0.05)
        )
        .frame(width: settings.ringDiameter, height: settings.ringDiameter)
        .scaleEffect(isCapturing ? 1.3 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
}
```

- The ring center is transparent — whatever is behind the window shows through
- Line width scales proportionally (~5% of diameter, minimum 2px)
- Capture animation (scale up on new item) and shadow are preserved from the old dot

### Remove

- `dotColor` computed property (no longer needed)
- Any reference to `dotColorMode` or `dotCustomColor` in this file

## 2. Settings Layer — AppearanceSettingsView

**Remove:**
- "圆点颜色模式" picker (auto/custom)
- "自定义颜色" color picker (shown when mode is "custom")
- The entire "圆点" (Dot) section

**Add:**
- New "圆环" (Ring) section with a slider:

```
圆环大小: [======o====] 60px
```

```swift
Section {
    LabeledContent("圆环大小") {
        HStack(spacing: 8) {
            Slider(value: Bindable(settings).ringDiameter, in: 20...200, step: 1)
                .frame(width: 150)
            Text("\(Int(settings.ringDiameter))px")
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
} header: {
    Text("圆环")
} footer: {
    Text("圆环模式下的彩虹圆环直径，范围 20–200px。")
        .font(.system(size: 11))
        .foregroundColor(.secondary)
}
```

## 3. Data Layer — SettingsKey + SettingsStore

### SettingsKey

- **Remove:** `dotColorMode`, `dotCustomColor`
- **Add:** `ringDiameter`

### SettingsStore

- **Remove:** `dotColorMode` property (get/set UserDefaults), `dotCustomColor` property
- **Add:** `ringDiameter` property:
  ```swift
  var ringDiameter: Double {
      get {
          access(keyPath: \.ringDiameter)
          return UserDefaults.standard.object(forKey: SettingsKey.ringDiameter.rawValue) as? Double ?? 60
      }
      set {
          withMutation(keyPath: \.ringDiameter) {
              UserDefaults.standard.set(newValue, forKey: SettingsKey.ringDiameter.rawValue)
          }
      }
  }
  ```
- **`resetAll()`:** Remove `dotColorMode` and `dotCustomColor` resets; add `ringDiameter = 60`

### SettingsProtocol

Update the protocol to remove `dotColorMode`/`dotCustomColor` and add `ringDiameter`.

## 4. Impact Summary

| File | Change |
|------|--------|
| `CapsuleCollapsedView.swift` | `dotView` → `ringView` with `AngularGradient`; remove `dotColor` |
| `AppearanceSettingsView.swift` | Remove dot color section; add ring diameter slider section |
| `SettingsKey.swift` | `-dotColorMode -dotCustomColor +ringDiameter` |
| `SettingsStore.swift` | Same + `resetAll()` update + protocol conformance |
| `SettingsProtocol.swift` | `-dotColorMode -dotCustomColor +ringDiameter` |
| `Mini_CapsuleTests.swift` | Replace `dotColorMode`/`dotCustomColor` assertions with `ringDiameter` tests |
| `SettingsKeyTests.swift` | Update expected keys list |

## 5. Edge Cases

- **Ring at 20px:** At minimum size, line width floors to 2px so the ring is still visible (20 × 0.05 = 1px would be too thin)
- **Ring at 200px:** At maximum size, line width is 10px — looks bold but still clearly a ring
- **Window shape:** The `capsuleWindowFrame` corner radius for dot mode (`layer.cornerRadius = 6`) needs to scale with the ring size so the window mask matches. Use `ringDiameter / 2` as the corner radius.
- **Existing collapsed style setting:** The setting `collapsedStyle` still uses the value `"dot"` — no migration needed, the key stays the same; only the rendering changes
