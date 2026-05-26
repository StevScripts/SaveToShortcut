# SaveToShortcut

A lightweight macOS menu bar app that lets you choose where to save downloads — on demand.

## The Problem

Every download goes to `~/Downloads`. When you need a file in a specific project folder, you have to download it first, then manually move it. Every. Single. Time.

## How It Works

1. **Press a global hotkey** (default: `⌘⇧D`) to arm the app
2. **Download your file** from any browser
3. **A Finder save dialog appears** — pick the destination
4. **The file moves automatically**

If you don't press the hotkey, downloads stay in your Downloads folder as usual. Works with Safari, Chrome, Firefox — any browser.

## Features

- **Global hotkey** to arm/disarm (customizable)
- **Menu bar icon** shows armed/disarmed state
- **Auto-disarm timer** — forgets after a configurable timeout so it won't surprise you later
- **Recent destinations** — remembers your last folders for quick re-selection
- **Launch at login** — optional startup on boot
- **Notification control** — banner, sound, or silent after each move
- **Full SwiftUI settings window** with tabbed configuration

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permissions (for global hotkey)

## Building

```bash
swift build
swift run
```

Or open in Xcode:

```bash
open Package.swift
```

## Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Global Shortcut | Key combo to arm/disarm | ⌘⇧D |
| Watch Folder | Folder to monitor for new files | ~/Downloads |
| Auto-disarm | Time before auto-disarm | 30 seconds |
| Launch at Login | Start on boot | Off |
| Recent Destinations | Number of folders to remember | 5 |
| Notifications | Alert style after moving | Banner |

## License

MIT
