<p align="center">
  <img src="stockpile_readme.png" alt="Stockpile" width="360">
</p>

<h1 align="center">Stockpile</h1>

<p align="center">
  macOS menu-bar app that transparently offloads folders to an external SSD.<br>
  Free internal disk space without breaking paths — apps never know the difference.
</p>

---

## Overview

Stockpile is a safety-first macOS utility that **stashes** folders from your internal drive onto an external SSD, replacing them with symlinks. Everything that uses those paths — your apps, terminal, system services — keeps working as if nothing changed. When you need the folder back, **restore** it with one click.

Think of it as a "stash" system: offload bulky media, project files, or archives to an external drive, and bring them back on demand.

**Version:** 0.1.0 — macOS 14+ (Sonoma or later)

---

## Features

| Capability | Description |
|------------|-------------|
| **Stash (Integrate)** | Move a folder to the external SSD, leaving a symlink at the original path |
| **Restore (Disintegrate)** | Move a folder back from the SSD to its original location, restoring the real directory |
| **Menu-bar UI** | Compact SwiftUI popover showing stashed folders, status, and one-click actions |
| **Drive selection** | First-run picker chooses an external drive (identified by volume UUID, not mount path) |
| **Auto-refresh** | Watches for drive plug/unplug events and updates the UI instantly |
| **Status indicator** | Green checkmark when the drive is ready, red X-mark when it's missing |
| **Space tracking** | Shows how many folders are stashed and how much space has been freed |
| **Multi-folder stash** | Select multiple folders at once via Cmd-click / Shift-click in the picker |
| **Per-folder restore** | Each stashed folder has its own "Disintegrate" button |
| **Confirmation dialogs** | Native macOS alerts before any stash or restore operation |
| **Error reporting** | In-menu error display with clear descriptions |

---

## Safety

Stockpile is built around a strict **copy-verify-swap** protocol — your original data is never deleted until a verified copy exists on the destination:

1. **Copy** — `/usr/bin/ditto` copies the folder (preserving resource forks, ACLs, extended attributes)
2. **Verify** — file count + total bytes are checked against the source
3. **Swap** — the original is renamed to a backup, a symlink is created, then the backup is deleted

Additional safeguards:

- **Crash recovery** — detects and repairs interrupted swaps on launch (leftover `.stockpile-bak` folders)
- **Space pre-checking** — verifies free space on the destination before any copy
- **Atomic manifest writes** — the JSON manifest is written atomically to prevent corruption
- **Symlink / duplicate detection** — prevents stashing an already-stashed or symlinked folder
- **Force-remove for locked trees** — can remove write-protected files when needed

---

## How It Works

### Architecture

```
┌─────────────────────────────────────────────┐
│              StockpileApp                    │
│  (SwiftUI MenuBarExtra — no Dock icon)       │
│                                              │
│  ┌──────────────────────────────────────┐   │
│  │          ViewModel                   │   │
│  │  (ObservableObject — state bridge)   │   │
│  └──────────┬───────────────────────────┘   │
└─────────────┼───────────────────────────────┘
              │  (all calls go through Engine)
┌─────────────┼───────────────────────────────┐
│  ┌──────────┴───────────────────────────┐   │
│  │         StockpileCore (Engine)        │   │
│  │                                       │   │
│  │  integrate / disintegrate / repair    │   │
│  │  ManifestStore  Copier  DirStats      │   │
│  │  DriveLocating  DriveWatcher          │   │
│  └───────────────────────────────────────┘   │
│               StockpileCore                   │
└───────────────────────────────────────────────┘
```

The **engine** (`StockpileCore`) contains all file operations and is fully unit-tested without a GUI. The **app** (`StockpileApp`) is a thin SwiftUI shell that never performs file operations directly.

### Drive Identity

The external drive is identified by its **volume UUID**, not its mount path or volume name. This means:
- Renaming the volume doesn't break the link
- Remounting at a different `/Volumes/...` path doesn't break the link
- On launch, the current mount point is resolved from the UUID

### Manifest

Stored at `~/Library/Application Support/Stockpile/manifest.json`:

```json
{
  "version": 1,
  "drive": { "uuid": "...", "name": "T7", "stockpileSubdir": "Stockpile" },
  "entries": [
    {
      "original": "/Users/me/Movies",
      "destRelative": "Movies",
      "bytes": 268435456,
      "integratedAt": "2026-05-29T12:00:00Z"
    }
  ]
}
```

Absolute destination paths are never stored — they are resolved at runtime from the UUID, configured subdirectory, and the relative entry path.

---

## Installation

### Requirements

- macOS 14.0 (Sonoma) or later
- Swift 6 toolchain (for building from source)

### Build from source

```bash
git clone <repo-url>
cd stockpile
./scripts/bundle.sh
open Stockpile.app
```

The first time you run it, macOS will prompt you to grant **Full Disk Access** — this is required because the app needs to read and write folders outside its sandbox (by design, no sandbox is configured).

### Usage

1. Launch Stockpile — it appears in the menu bar
2. Click the icon and select a drive (first run) or connect your designated SSD
3. Click **Integrate** and pick folders to stash
4. To restore, click **Disintegrate** next to any stashed folder

---

## Project Structure

```
stockpile/
├── Package.swift              # Swift Package Manager (Swift 6)
├── Sources/
│   ├── StockpileCore/         # Engine library (11 files)
│   │   ├── Version.swift      # 0.1.0
│   │   ├── Errors.swift       # Typed error enum
│   │   ├── Models.swift       # Domain types
│   │   ├── ManifestStore.swift # JSON persistence
│   │   ├── Engine.swift       # integrate / disintegrate / repair
│   │   ├── Copier.swift       # ditto wrapper
│   │   ├── DirStats.swift     # Recursive size enumeration
│   │   ├── SpaceChecking.swift
│   │   ├── DriveLocating.swift # Volume UUID resolution
│   │   └── DriveWatcher.swift # Mount/unmount events
│   └── StockpileApp/          # GUI executable (3 files)
│       ├── StockpileApp.swift  # @main entry point
│       ├── ViewModel.swift     # State bridge
│       └── MenuView.swift      # Menu bar popover
├── Tests/StockpileCoreTests/  # 8 test files
├── Resources/                 # App resources (icons, plist)
│   ├── Info.plist
│   ├── stockpile.icns
│   └── stockpile_taskbar.png
└── scripts/
    └── bundle.sh              # Release build + codesign
```

---

## Development

### Running tests

```bash
swift test
```

### Building for release

```bash
./scripts/bundle.sh
```

The output is a standalone `Stockpile.app` bundle in the project root.

### Code conventions

- `StockpileApp` never performs file operations directly — all dangerous logic is in `StockpileCore`
- All errors conform to `LocalizedError` with user-friendly descriptions using `ByteCountFormatter`
- Maximum 3 lines of inline error display in the menu
- All core operations are async off the main thread via `Task.detached`

---

## License

MIT
