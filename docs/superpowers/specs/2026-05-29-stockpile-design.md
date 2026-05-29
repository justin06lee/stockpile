# Stockpile — Design Spec

**Date:** 2026-05-29
**Status:** Approved (design phase)

## Summary

Stockpile is a macOS menu-bar app that transparently offloads folders from
internal storage to a designated external SSD and back. "Integrate" a folder
and it moves to the SSD with a symlink left in its original location, so apps
keep finding it at the same path while internal space is freed.
"Disintegrate" reverses it. The app tracks state, identifies the drive by
volume UUID, and reacts to plug/unplug events.

### Goals

- Free internal disk space by moving folders to an external SSD without
  breaking the paths apps expect.
- One-click integrate / disintegrate from the menu bar.
- Never lose data: copy-verify-swap, never a bare `mv`.
- Clear status at a glance, including when the SSD is unplugged.

### Non-goals (v1 — YAGNI)

- Multiple external drives (one designated drive only).
- Scheduling / automation of integrate/disintegrate.
- Encryption or compression of stashed data.
- A command-line interface (the core is CLI-ready, but no CLI ships in v1).
- Auto-disintegrate on unplug.

## Architecture

Two units with a clean boundary: a UI-free engine and a thin SwiftUI shell.

```
stockpile/
├── Package.swift                  # SPM: core library + test target
├── Sources/
│   ├── StockpileCore/             # Engine — no UI, fully testable
│   │   ├── Manifest.swift         # load/save JSON state (atomic writes)
│   │   ├── Drive.swift            # locate drive by volume UUID, mount check
│   │   ├── DriveWatcher.swift     # DiskArbitration plug/unplug callbacks
│   │   ├── Engine.swift           # integrate() / disintegrate() / status()
│   │   ├── Copier.swift           # ditto wrapper with progress
│   │   └── Errors.swift           # typed StockpileError
│   └── StockpileApp/              # GUI — thin SwiftUI MenuBarExtra
│       ├── StockpileApp.swift     # @main, MenuBarExtra
│       ├── MenuView.swift         # status + folder list + buttons
│       └── ViewModel.swift        # bridges UI <-> Core
└── Tests/StockpileCoreTests/      # unit tests on the engine (no UI, no real SSD)
```

**Boundary rule:** `StockpileApp` only calls public functions on
`StockpileCore`. It never performs file operations directly. All dangerous
logic lives in the engine and is unit-tested without launching a GUI.

**Stack rationale (hybrid):**

- `ditto` (via subprocess in `Copier`) for the bulk copy — Apple's
  battle-tested tool that correctly preserves resource forks, ACLs, and
  extended attributes, and reports progress. `/usr/bin/ditto` is always
  present on macOS.
- Foundation for symlink create/remove and manifest JSON.
- DiskArbitration for plug/unplug events and volume UUID resolution.

**Sandboxing:** the app must be **non-sandboxed**. It accesses arbitrary user
folders and external volumes, which the App Sandbox would block. This affects
code signing and packaging.

## Core operations

**Invariant: original data is never deleted until a verified copy exists
elsewhere.** Every operation is copy → verify → swap. Never a bare `mv`.

### `integrate(folder)` — internal → SSD

1. **Preflight** (fail fast, no changes if any check fails):
   - drive mounted
   - folder exists and is a real directory (reject if already a symlink)
   - drive free space ≥ folder size
   - destination slot free
2. **Copy:** `ditto <src> <dest>`, where `dest` is the resolved drive mount
   point (from UUID) joined with `Stockpile/<basename>` (dedup the basename on
   collision; the chosen relative path is what gets recorded). Source is left
   untouched.
3. **Verify:** ditto exits 0 **and** destination file-count + total bytes
   match the source. On mismatch: delete the partial destination, leave the
   source intact, raise `verificationFailed`.
4. **Swap:**
   1. rename `src` → `src.stockpile-bak`
   2. create symlink `src` → `dest`
   3. only after the symlink is confirmed, delete `src.stockpile-bak`
   If step 2 fails, rename the backup back and abort.
5. **Record:** add a manifest entry
   `{ original, destRelative, bytes, integratedAt }`.

### `disintegrate(folder)` — SSD → internal

1. **Preflight** (fail fast):
   - drive mounted (the data lives there)
   - manifest entry exists
   - symlink present at the original path
   - **internal** free space ≥ folder size
2. Remove the symlink (the link only, not its target).
3. `ditto <dest> <original>`, then verify (same count + bytes check).
4. On success: delete `dest`, drop the manifest entry.
   On failure: recreate the symlink, keep `dest`, raise an error.

### Crash / unplug mid-operation

- **Mid-copy:** the original is always intact (copy happens first). A partial
  destination is an orphan, cleaned up on the next run.
- **Mid-swap:** a leftover `.stockpile-bak` is recoverable. On launch the app
  detects it and offers a repair.

## Drive identity and watcher

- **Identity:** match the drive by **volume UUID**
  (`DADiskCopyDescription` → `DAVolumeUUID`), not by name or mount path, so a
  rename or a remount at a different `/Volumes/...` path does not break the
  link. On first run the user picks the drive from a list; the app stores its
  UUID, a friendly name, and the stockpile root path.
- **Watcher:** `DiskArbitration` callbacks
  (`DARegisterDiskAppearedCallback` / disk-disappeared), with
  `NSWorkspace.didMountNotification` / `didUnmountNotification` as a fallback.
  - On appear: re-verify symlinks, set status green.
  - On disappear: set status red, post a notification
    "Drive missing — N folders offline."

## Manifest

JSON at `~/Library/Application Support/Stockpile/manifest.json`:

```json
{
  "version": 1,
  "drive": {
    "uuid": "…",
    "name": "T7",
    "stockpileSubdir": "Stockpile"
  },
  "entries": [
    {
      "original": "/Users/huiyunlee/Movies",
      "destRelative": "Movies",
      "bytes": 268435456,
      "integratedAt": "2026-05-29T12:00:00Z"
    }
  ]
}
```

**Path resolution:** the absolute destination is never stored, because the
volume can remount at a different `/Volumes/...` path. Instead it is resolved
at runtime: find the volume's current mount point by its UUID, then join
`stockpileSubdir` + `entry.destRelative`. Identity is the UUID; everything
else is derived. (`drive.name` is a display label only.)

Written atomically (write to a temp file, then rename) so a crash never
corrupts the manifest.

## GUI — MenuBarExtra

- **Icon** reflects state: green (drive present, all linked) / red (drive
  absent) / amber (repair needed, e.g. leftover `.stockpile-bak`).
- **Body:**
  - status line, e.g. "T7 ✓ · 4 stashed · 38 GB freed"
  - folder list with a per-row Integrate / Disintegrate control
  - "+ Stash a folder…" opening a folder picker
  - progress bar during a copy
- **Confirm dialog** before any move, showing the folder, its size, and the
  direction.

## Error handling

Typed `StockpileError` cases: `driveNotMounted`, `insufficientSpace`,
`alreadyIntegrated`, `notIntegrated`, `verificationFailed`,
`permissionDenied`, `destinationExists`, `repairNeeded`. The GUI maps each to
a plain-English alert. The core never half-completes silently — every failure
path leaves the system in a known, recoverable state.

## Testing

`StockpileCoreTests` runs against temporary directories and a fake "drive"
directory, so no real SSD is required:

- integrate → assert symlink created, data at destination, manifest updated
- disintegrate → assert data restored to original, destination removed,
  manifest entry dropped
- collision → assert destination name dedup
- insufficient space → assert clean abort, no changes
- interrupted swap → assert `.stockpile-bak` recovery
- manifest write → assert atomicity (no corruption on simulated failure)

The GUI is kept thin enough that heavy UI testing is unnecessary for v1.
