# Appearance & General Settings — Design Spec

**Date**: 2026-07-06
**Status**: Draft
**App**: Mini Capsule (macOS clipboard manager)

---

## Overview

Add General and Appearance tabs to the settings window. Extend the capsule UI with: menu bar mode, configurable collapse style (capsule / dot), unfocused opacity, and expand-panel background image. These features complement the existing Clipboard, Shortcuts, and Advanced tabs.

## Architecture

```
Mini Capsule/
├── Settings/
│   ├── SettingsStore.swift              (modify) add new @AppStorage keys
│   ├── GeneralSettingsView.swift        (new) General tab
│   └── AppearanceSettingsView.swift     (new) Appearance tab
├── Services/
│   └── MenuBarService.swift             (new) NSStatusItem + NSMenu
├── UI/
│   ├── CapsuleView.swift                (modify) opacity + dot style + configurable delays
│   ├── CapsuleCollapsedView.swift       (modify) dot variant
│   └── CapsuleExpandedView.swift        (modify) background image support
├── Mini_CapsuleApp.swift                (modify) add menu bar init, new Settings tabs
```

### New @AppStorage Keys

| Key | Type | Default | Scope |
|-----|------|---------|-------|
| `launchAtLogin` | Bool | false | General |
| `showInMenuBar` | Bool | true | General |
| `showFloatingPanel` | Bool | true | General |
| `collapsedStyle` | String | "capsule" | General |
| `hoverExpandDelay` | Double | 0.3 | General |
| `hoverCollapseDelay` | Double | 1.0 | General |
| `panelOpacityUnfocused` | Double | 0.6 | Appearance |
| `backgroundImageData` | Data? | nil | Appearance |
| `dotColorMode` | String | "auto" | Appearance |
| `dotCustomColor` | String | "#007AFF" | Appearance |

## General Tab

| Setting | Control | Default | Notes |
|---------|---------|---------|-------|
| Launch at login | Toggle | Off | `SMAppService.mainApp.register()` / `unregister()` |
| Show in menu bar | Toggle | On | NSStatusItem always visible |
| Show floating panel | Toggle | On | Controls CapsuleWindow visibility |
| Collapsed style | Picker | Capsule | Capsule / Dot (disabled when floating panel is off) |
| Hover expand delay | Picker | 0.3s | 0.1s / 0.3s / 0.5s / 1.0s (disabled when floating panel is off) |
| Hover collapse delay | Picker | 1.0s | 0.5s / 1.0s / 2.0s / 3.0s (disabled when floating panel is off) |

Layout: `Form` with `.formStyle(.grouped)`, `.frame(width: 450, height: 320)`.

### Menu Bar Behavior (MenuBarService)

NSStatusItem with a text/icon label. On click, shows an NSMenu with:
- 5 most recent clip items (text preview, click to copy)
- Separator
- "打开悬浮窗" / "隐藏悬浮窗" (toggle, only if floating panel exists)
- "设置..." (opens Settings window)
- Separator
- "退出 Mini Capsule"

Updates menu items dynamically when clipboard changes.

## Appearance Tab

| Setting | Control | Default | Notes |
|---------|---------|---------|-------|
| Unfocused opacity | Slider | 0.6 | Range 0.3–1.0, step 0.05. Real-time preview on the capsule window |
| Background image | Button + preview | None | NSOpenPanel for image types. Shows 80×50 thumbnail. Compressed to max 2MB before save |
| Clear background | Button | — | Only visible when background is set. Restores ultraThinMaterial |
| Dot color mode | Picker | Auto | Auto (type-based) / Custom |
| Custom color | ColorPicker | Blue | Only visible when dot color mode is "custom" |

Layout: `Form` with `.formStyle(.grouped)`, `.frame(width: 450, height: 320)`.

### Background Image Behavior

- Image stored as compressed JPEG Data in UserDefaults (`backgroundImageData`)
- Max size 2MB; if larger, scale down before saving
- Applied only to CapsuleExpandedView, behind the ultraThinMaterial
- If the image fails to decode, silently fall back to no background
- Clearing the background removes the Data key

### Opacity Real-Time Preview

When `panelOpacityUnfocused` changes in settings, the capsule window's opacity is updated immediately via a shared mechanism:

Option: `CapsuleView` observes `UserDefaults.didChangeNotification` for the opacity key, or AppDelegate posts a notification on change.

Actual opacity logic in CapsuleView:
- Window is key/focused → opacity 1.0
- Mouse is inside the window → opacity 1.0 (smooth transition)
- Neither → `panelOpacityUnfocused`
- Transition animation: 0.3s ease

## Capsule Collapsed View — Dot Variant

When `collapsedStyle == "dot"`:

- Size: 12×12 circle (vs 200×36 capsule)
- Color: green (latest item is text), blue (image), orange (file), gray (empty)
- In custom color mode: always the chosen color
- No text, no drag handle visible (drag still works on the dot)
- Expands on hover same as capsule style
- Window resizes to dot size (12×12)

CapsuleWindowController updates:
- `collapsedSize` becomes dynamic: reads `collapsedStyle` from UserDefaults
- Dot size: 12×12
- Capsule size: 200×36

## CapsuleView Changes

- Read `hoverExpandDelay` and `hoverCollapseDelay` from UserDefaults instead of hardcoded 0.3/1.0
- Apply opacity based on focus/hover state
- Pass `collapsedStyle` to CapsuleCollapsedView

## Edge Cases

1. **Both toggles off** — If `showInMenuBar` and `showFloatingPanel` are both off, warn user: "⚠️ 至少需要开启一种展示方式" and auto-enable menu bar
2. **Background image decode failure** — Silently fall back to no background
3. **Dot dragged** — Dot is draggable (drag gesture works on the small hit area or slightly expanded hit area)
4. **First launch** — All new keys use defaults; floating panel shows as capsule
5. **Opacity + background image** — Image respects the panel opacity setting

## Out of Scope

- Per-appearance themes (dark/light mode toggle — macOS inherits system)
- Multiple background images (slideshow)
- Menu bar icon customization (use default text/icon)
