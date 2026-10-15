# Xournal++ CopyPageToClipboard Plugin

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Xournal++](https://img.shields.io/badge/Xournal%2B%2B-1.3.8%2B-brightgreen.svg)](https://github.com/xournalpp/xournalpp)
[![Lua](https://img.shields.io/badge/Lua-5.3%2B-blue.svg)](https://www.lua.org)

> Developed by **Antigravity**, directed by **[@m-sarabi](https://github.com/m-sarabi)**.

A production-ready Xournal++ Lua plugin that enables copying the currently active page directly to your system clipboard as a PNG image with a single shortcut (`<Control><Alt>c`) or menu action, completely bypassing the manual file export workflow.

---

## Features

- ⚡ **Instant Non-Blocking Copy**: Press `<Control><Alt>c` to capture the currently viewed page directly into your clipboard. Clipboard encoding and cleanup run asynchronously in the background so Xournal++ never freezes or lags regardless of image size.
- 🖼️ **Dual Quality Modes & Custom Values**:
  - **DPI Mode** (Default: 300 DPI, supports any custom resolution from 50 to 2400 DPI)
  - **Fixed Width Mode** (Default: 1920 px, supports any custom width from 100 to 10000 px)
- 🎛️ **Clean Unified Dialog**: Replaces cluttered preset menu items with a single intuitive dialog for selecting mode and custom resolution.
- 💾 **Settings Persistence**: Remembers your preferred mode and quality settings across Xournal++ restarts in `config.ini`.
- 🌐 **Cross-Platform Clipboard Integration**:
  - **Windows**: Native background PowerShell & .NET Clipboard API (`System.Windows.Forms.Clipboard`).
  - **Linux**: Wayland (`wl-copy`) and X11 (`xclip` / `xsel`) background subshell.
  - **macOS**: Native background `osascript` (`«class PNGf»`).
- 🧹 **Zero Disk Clutter**: Temporary export images are safely and cleanly removed by the background process immediately after being transferred to clipboard memory.
- 🔔 **Visual Feedback**: Displays brief status notifications on successful copy or configuration changes.

---

## Exact Installation Paths

### Windows

Install into your user plugins directory:

```powershell
# Default Windows User Plugins Directory:
%LOCALAPPDATA%\xournalpp\plugins\CopyPageToClipboard\
# (Typically: C:\Users\<Username>\AppData\Local\xournalpp\plugins\CopyPageToClipboard\)
```

#### Quick Install via PowerShell:
```powershell
$target = "$env:LOCALAPPDATA\xournalpp\plugins\CopyPageToClipboard"
New-Item -ItemType Directory -Force -Path $target
git clone https://github.com/m-sarabi/xournal-to-clipboard.git $target
```

Or manually copy `plugin.ini` and `main.lua` into `C:\Users\<YourUsername>\AppData\Local\xournalpp\plugins\CopyPageToClipboard\`.

---

### Linux

Install into your user plugins directory:

```bash
# Default Linux User Plugins Directory:
~/.config/xournalpp/plugins/CopyPageToClipboard/
```

#### Quick Install via Terminal:
```bash
mkdir -p ~/.config/xournalpp/plugins/CopyPageToClipboard
git clone https://github.com/m-sarabi/xournal-to-clipboard.git ~/.config/xournalpp/plugins/CopyPageToClipboard
```

*Note for Linux users: Ensure a clipboard utility is installed:*
- **Wayland**: `wl-clipboard` (provides `wl-copy`)
  - Ubuntu/Debian: `sudo apt install wl-clipboard`
  - Fedora: `sudo dnf install wl-clipboard`
  - Arch: `sudo pacman -S wl-clipboard`
- **X11**: `xclip` or `xsel`
  - Ubuntu/Debian: `sudo apt install xclip`
  - Fedora: `sudo dnf install xclip`
  - Arch: `sudo pacman -S xclip`

---

### macOS

Install into your user configuration directory:

```bash
mkdir -p ~/Library/Application\ Support/xournalpp/plugins/CopyPageToClipboard
git clone https://github.com/m-sarabi/xournal-to-clipboard.git ~/Library/Application\ Support/xournalpp/plugins/CopyPageToClipboard
```

---

## Step-by-Step Instructions: Enable and Test in Xournal++ 1.3.8

### 1. Enable the Plugin
1. Open **Xournal++ 1.3.8**.
2. In the top menu, navigate to **Plugin > Plugin Manager**.
3. In the list of installed plugins, locate **CopyPageToClipboard**.
4. Check the box to enable it (if not already enabled by default).
5. Restart Xournal++ or click **Reload plugins** to ensure hooks are loaded.

### 2. Test Page Copying
1. Open or create any notebook file in Xournal++.
2. Draw or write some strokes on the current page.
3. Press **`<Control><Alt>c`** (or click **Plugin > Copy Current Page to Clipboard** from the menu).
4. A notification will appear confirming: `Page 1 copied to clipboard (300 DPI)!`. The clipboard transfer executes smoothly in the background without causing the interface to hang or stutter.
5. Open any application that supports image pasting (such as Slack, Discord, Microsoft Word, Obsidian, WhatsApp, or an image editor like GIMP / Paint) and press **`Ctrl+V`** (`Cmd+V` on macOS).
6. Verify the high-resolution PNG image is pasted into the target application.

### 3. Configure Image Quality Settings
Under the **Plugin** menu, you can configure quality at any time:
- Click **Plugin > Quality Settings...** to open the unified configuration dialog.
- Select your preferred mode: **DPI** or **Fixed Width (pixels)**.
- Enter any custom value (e.g. `450` for 450 DPI, or `2560` for 2560 px width).
- Click **OK** to apply.

All preferences are automatically persisted in `config.ini` in the plugin directory across sessions.

---

## Configuration Reference (`config.ini`)

You can also customize settings by editing `config.ini` directly:

```ini
[settings]
mode=dpi      # Quality mode: "dpi" or "width"
dpi=300       # Resolution in DPI (default: 300, valid: 50 - 2400)
width=1920    # Pixel width for fixed width mode (default: 1920, valid: 100 - 10000)
```

---

## Automated Validation & Testing

The repository includes both Lua and Python automated test suites:

### Run Lua Test Suite
```bash
# Runs with any Lua 5.3+ interpreter (e.g., texlua, lua5.3, lua5.4)
texlua --luaonly tests/test_plugin.lua
```

### Run Python Test Suite
```bash
python -m unittest tests/test_plugin.py
```

Tests verify:
- `plugin.ini` syntax and metadata according to Xournal++ specs
- Lua 5.3+ compilation and runtime initialization
- Configuration persistence (read, write, edge cases)
- Host OS detection and command generation (Windows, Linux Wayland/X11, macOS)
- Temporary path resolution and page-indexed file discovery
- Live clipboard transfer and temporary file cleanup

---

## Credits

Developed by **Antigravity**, directed by **[@m-sarabi](https://github.com/m-sarabi)**.
