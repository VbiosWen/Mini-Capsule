# macOS 14+ 支持 — 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `MACOSX_DEPLOYMENT_TARGET` 从 26.5 降至 14.0，使 macOS 14 (Sonoma) 及以上用户可安装运行。

**Architecture:** 纯项目配置变更 — 修改 `project.pbxproj` 中 6 处 `MACOSX_DEPLOYMENT_TARGET` 值，零代码改动。

**Tech Stack:** Xcode project (pbxproj), xcodebuild

## Global Constraints

- `MACOSX_DEPLOYMENT_TARGET` = `14.0`（从 `26.5` 改为 `14.0`）
- `IPHONEOS_DEPLOYMENT_TARGET` 保持 `26.5` 不变
- `SWIFT_VERSION` 保持 `5.0` 不变
- 所有 entitlements 文件不变
- `Info.plist` 不变
- 构建脚本（`Scripts/*.sh`）不变
- 零 Swift 代码改动

---

### Task 1: 修改 macOS 部署目标

**Files:**
- Modify: `Mini Capsule.xcodeproj/project.pbxproj:320,366,506,531,555,579`

**Interfaces:**
- Consumes: 无（首个任务）
- Produces: `MACOSX_DEPLOYMENT_TARGET = 14.0`（全部 6 处 build configuration）

- [ ] **Step 1: 修改 project.pbxproj 中的部署目标**

`Mini Capsule.xcodeproj/project.pbxproj` 中有 6 处 `MACOSX_DEPLOYMENT_TARGET = 26.5;`，全部替换为 `14.0`。使用 `sed` 精确替换：

```bash
cd '/Users/vbiso/xcode_projects/Mini Capsule'
sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 26\.5;/MACOSX_DEPLOYMENT_TARGET = 14.0;/g' \
    'Mini Capsule.xcodeproj/project.pbxproj'
```

- [ ] **Step 2: 确认修改结果**

```bash
grep -n 'MACOSX_DEPLOYMENT_TARGET' 'Mini Capsule.xcodeproj/project.pbxproj'
```

预期输出：6 行全部显示 `MACOSX_DEPLOYMENT_TARGET = 14.0;`，`IPHONEOS_DEPLOYMENT_TARGET` 行保持 `26.5` 不变。

- [ ] **Step 3: 确认 IPHONEOS_DEPLOYMENT_TARGET 未被误改**

```bash
grep -n 'IPHONEOS_DEPLOYMENT_TARGET' 'Mini Capsule.xcodeproj/project.pbxproj'
```

预期输出：全部显示 `IPHONEOS_DEPLOYMENT_TARGET = 26.5;`。

- [ ] **Step 4: 提交**

```bash
cd '/Users/vbiso/xcode_projects/Mini Capsule'
git add 'Mini Capsule.xcodeproj/project.pbxproj'
git commit -m "build: lower macOS deployment target from 26.5 to 14.0

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 编译验证

**Files:**
- 无文件变更（验证任务）

**Interfaces:**
- Consumes: Task 1 的 `MACOSX_DEPLOYMENT_TARGET = 14.0`

- [ ] **Step 1: 清理构建缓存**

```bash
cd '/Users/vbiso/xcode_projects/Mini Capsule'
rm -rf DerivedData/Build
```

- [ ] **Step 2: 执行 macOS 编译**

```bash
cd '/Users/vbiso/xcode_projects/Mini Capsule'
xcodebuild -project "Mini Capsule.xcodeproj" \
    -scheme "Mini Capsule" \
    -destination 'platform=macOS' \
    build 2>&1 | tail -20
```

预期：`** BUILD SUCCEEDED **`，无 API 可用性警告。

- [ ] **Step 3: 检查编译输出中无版本相关警告**

```bash
cd '/Users/vbiso/xcode_projects/Mini Capsule'
xcodebuild -project "Mini Capsule.xcodeproj" \
    -scheme "Mini Capsule" \
    -destination 'platform=macOS' \
    build 2>&1 | grep -i 'deprecated\|unavailable\|availability\|version'
```

预期：空输出（无相关警告）。

---

### Task 3: 运行单元测试

**Files:**
- 无文件变更（验证任务）

**Interfaces:**
- Consumes: Task 1 的 `MACOSX_DEPLOYMENT_TARGET = 14.0`

- [ ] **Step 1: 运行全部单元测试**

```bash
cd '/Users/vbiso/xcode_projects/Mini Capsule'
xcodebuild -project "Mini Capsule.xcodeproj" \
    -scheme "Mini Capsule" \
    -destination 'platform=macOS' \
    test 2>&1 | tail -30
```

预期：`** TEST SUCCEEDED **`，全部现有测试通过。

- [ ] **Step 2: （可选）运行单个核心测试确认 SwiftData + 剪贴板正常**

```bash
cd '/Users/vbiso/xcode_projects/Mini Capsule'
xcodebuild -project "Mini Capsule.xcodeproj" \
    -scheme "Mini Capsule" \
    -destination 'platform=macOS' \
    -only-testing:Mini_CapsuleTests/ClipboardMonitorTests \
    test 2>&1 | tail -15
```

预期：`** TEST SUCCEEDED **`
