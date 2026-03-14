# KeyMapper for macOS 【中文描述在下面】
an easy small MacOS app for Windows users who prefer to use ctrl+c instead of command+c
all supported by Gemini
including README 😆

<p align = center>
<img src="https://github.com/baikaihao/KeyMapper/blob/main/app图标.png?raw=true" width="100" height="100">
</p>

---

## English Version

Hi there! I built this little tool just three days after getting my first MacBook. After a decade of "Ctrl+C" muscle memory, I honestly couldn't handle the finger gymnastics required for "Command+C"—it was pure torture! I’m not sure if someone else has built a similar tool, but given how powerful AI is nowadays, I decided to just "vibe-code" it into existence. (Shoutout to Gemini and Qwen for helping me grind this out in 12 hours! 🚀)

Now, you might ask: "Doesn't macOS let you swap Command and Control natively?"
Sure it does. But if you swap them globally, every other shortcut gets messed up. The vision for this app is simple: map Windows-style "Ctrl+C/V" to "Cmd+C/V" without breaking your existing Command-key shortcuts.


### ✨ Features

* **Global Interception**: Uses low-level `CGEventTap` for system-wide key remapping.
* **Visual Recording**: No need to look up keycodes. Simply click "Record" and press your desired key.
* **Modifier Support**: Full support for `⌘ (Command)`, `⌥ (Option)`, `⇧ (Shift)`, and `⌃ (Control)`.
* **Stealth Mode**: Options to hide the Dock icon and enable "Launch at Login" for a seamless experience.
* **Privacy First**: 100% open-source, no analytics, no network access.

### 🚀 Getting Started

1. **Download**: Grab the latest `.zip` from the [Releases] page.
2. **Install**: Unzip and move `KeyMapper.app` to your `Applications` folder.
3. **Permissions (Required)**:
* Go to **System Settings > Privacy & Security > Accessibility**.
* Toggle **KeyMapper** to **ON**. This is required for the engine to intercept keystrokes.


4. **First Run**: If macOS warns you about an "unverified developer," **Right-click** the app and select **Open**.

### 🛠 Technical Notes

* **Sandboxing**: This app is distributed **without Sandbox** because global event interception is restricted by Apple's Sandbox environment.
* **Storage**: User configurations are serialized via `JSONEncoder` and persisted in `UserDefaults`.

---

<div>
<img src="https://github.com/baikaihao/KeyMapper/blob/main/screenshot.jpg?raw=true" height="250px">
</div>


## 中文版

嗨！这个小软件是我拿到MacBook后的第三天有这个想法去做的，主要是我摁了十几年的ctrl+c，实在是搞不来那个手型去摁command+c，太折磨了。俺也不知道有没有别的大神做过类似的软件了，想着现在ai这么厉害直接vibe coding一个出来算了【12小时靠Gemini和千问给我vibe出来了齁哦哦哦哦哦哦哦哦哦】

这个时候就有人问了：macOS不是自带command改成control功能吗？
确实，但是改了的话那其他需要command的快捷键不是也变了吗。所以这个软件的初衷就是，既可以实现Windows的ctrl+C转为command+c的映射，又不会影响其他需要command的快捷键的使用

下面的就是gemini老师生成的readme了

---

一个基于 SwiftUI 开发的轻量级 macOS 全局按键映射工具。

### ✨ 功能特性

* **全局拦截**：利用底层 `CGEventTap` 技术，实现系统级按键重映射。
* **可视化录制**：无需记忆键位码，点击录制按钮后直接敲击键盘即可自动识别。
* **组合键支持**：完美支持 `⌘ (Command)`, `⌥ (Option)`, `⇧ (Shift)`, `⌃ (Control)` 的任意组合。
* **静默运行**：支持隐藏 Dock 图标、开机自启动，满足无感化后台运行需求。
* **完全开源**：不包含任何统计或网络模块，纯净安全，保护输入隐私。

### 🚀 快速开始

1. **下载**：在 [Releases] 页面下载最新版的 `.zip` 压缩包。
2. **安装**：解压并拖入 `Applications` (应用程序) 文件夹。
3. **授权 (必须)**：
* 打开 **系统设置 > 隐私与安全性 > 辅助功能**。
* 在列表中找到 `KeyMapper` 并打开开关。如果不打开，引擎将无法捕获及修改按键信号。


4. **运行**：由于未经过 Apple 公证，首次运行请**右键点击**图标并选择“打开”。

### 🛠 技术细节

* **权限管理**：应用必须运行在 **非沙盒 (Non-Sandboxed)** 模式下才能调用 `CoreGraphics` 的 `CGEventTap` 接口。
* **持久化**：使用 `UserDefaults` 结合 `JSONEncoder` 实现配置的本地存储。

---

