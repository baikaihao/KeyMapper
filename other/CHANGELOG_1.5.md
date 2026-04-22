# KeyMapper v1.5 Release Notes

<br />

***

## 中文版本\[English version below]

### 🎡 新功能：轮转转盘选择器

当一个按键组合有多个映射时，现在会弹出一个精美的轮转转盘供快速选择！

**使用方法：**

1. 为同一按键创建多个映射（如 `Ctrl+C` → `Command+C` 和 `Ctrl+C` → `Option+C`）
2. 按住该按键组合
3. 轮转转盘会在鼠标位置弹出
4. 移动鼠标选择想要的映射
5. 松手执行

**特性：**

- **液态玻璃效果**：macOS 26+ (Tahoe) 上呈现精美的半透明玻璃效果，旧系统使用磨砂玻璃
- **即时响应**：快速的弹性动画，选择流畅
- **ESC 取消**：按 ESC 键可取消本次操作，不执行任何映射
- **智能检测**：自动检测同一按键是否有多个映射

### 🐛 问题修复

- **修复**：应用窗口内的按键不再触发映射
- **修复**：录制模式下不再触发已有映射
- **修复**：录制时不再发出系统"嘟"提示音
- **修复**：开机自启动功能现在可以正常工作（需将应用放在「应用程序」文件夹）

### 💅 改进优化

- 录制状态会正确禁用按键映射引擎
- 开机自启动功能添加了更好的错误处理
- 改进代码签名配置，更好地与 macOS 集成

<br />

## English Version\[中文版在上面]

### 🎡 New Feature: Radial Wheel Selector

When a key combination has multiple mappings, a beautiful radial wheel now appears for quick selection!

**How it works:**

1. Create multiple mappings for the same key (e.g., `Ctrl+C` → `Command+C` and `Ctrl+C` → `Option+C`)
2. Press and hold the key combination
3. A radial wheel appears at your mouse cursor position
4. Move your mouse to select the desired mapping
5. Release to execute

**Features:**

- **Liquid Glass Effect**: Beautiful translucent glass effect on macOS 26+ (Tahoe), with frosted glass fallback on older systems
- **Instant Response**: Fast spring animation for quick selection
- **ESC to Cancel**: Press ESC to dismiss the wheel without executing any mapping
- **Smart Detection**: Automatically detects when you have multiple mappings for the same key

### 🐛 Bug Fixes

- **Fixed**: Key mappings no longer trigger inside the app's own window
- **Fixed**: Recording mode now works correctly without triggering existing mappings
- **Fixed**: System "beep" sound no longer plays when recording keys
- **Fixed**: Launch at Login now works correctly when app is in Applications folder

### 💅 Improvements

- Recording state now properly disables the key mapping engine
- Better error handling for Launch at Login feature
- Improved code signing configuration for better macOS integration

***

## Technical Notes / 技术说明

- Minimum macOS version: 13.5
- Built with SwiftUI + AppKit
- Uses `CGEventTap` for global key interception
- Liquid Glass effect requires macOS 26+

***

Thank you for using KeyMapper! / 感谢使用 KeyMapper！
