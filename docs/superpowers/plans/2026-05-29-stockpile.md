# Stockpile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu-bar app that offloads folders to an external SSD via symlinks ("integrate") and restores them ("disintegrate"), without ever losing data.

**Architecture:** A UI-free, fully-tested Swift package (`StockpileCore`) holds all file/manifest/drive logic. A thin SwiftUI `MenuBarExtra` executable (`StockpileApp`) calls the core. The risky copy uses Apple's `ditto`; identity is tracked by volume UUID; every operation is copy → verify → swap so the original is never deleted before a verified copy exists.

**Tech Stack:** Swift 6, Swift Package Manager, swift-testing (`import Testing`), Foundation, AppKit (NSWorkspace for mount events), SwiftUI (MenuBarExtra), `/usr/bin/ditto`.

**Spec:** `docs/superpowers/specs/2026-05-29-stockpile-design.md`

**Prerequisites:** macOS 14+ and a Swift 6 toolchain (`swift --version` should report 6.x). Verify before Task 1.

---

## File structure

```
stockpile/
├── Package.swift
├── Sources/
│   ├── StockpileCore/
│   │   ├── Errors.swift          # StockpileError
│   │   ├── JSONCoders.swift      # shared encoder/decoder config
│   │   ├── Models.swift          # DriveRef, Entry, Manifest, Status
│   │   ├── ManifestStore.swift   # atomic load/save
│   │   ├── DirStats.swift        # recursive file count + byte size
│   │   ├── Copier.swift          # ditto wrapper + verify
│   │   ├── SpaceChecking.swift   # protocol + FileSystem impl
│   │   ├── DriveLocating.swift   # protocol + FileManager impl
│   │   ├── DriveWatcher.swift    # NSWorkspace mount/unmount events
│   │   └── Engine.swift          # integrate / disintegrate / repair / status
│   └── StockpileApp/
│       ├── StockpileApp.swift    # @main, MenuBarExtra
│       ├── ViewModel.swift       # ObservableObject bridge to core
│       └── MenuView.swift        # status + folder list + buttons
├── Tests/StockpileCoreTests/
│   ├── TestSupport.swift         # temp-dir + tree-builder helpers
│   ├── ManifestStoreTests.swift
│   ├── CopierTests.swift
│   ├── EngineIntegrateTests.swift
│   ├── EngineDisintegrateTests.swift
│   ├── EngineRepairTests.swift
│   └── DriveLocatingTests.swift
└── scripts/
    └── bundle.sh                 # assemble Stockpile.app (LSUIElement)
```

---

## Task 1: SPM scaffold + smoke test

**Files:**
- Create: `Package.swift`
- Create: `Sources/StockpileCore/Version.swift`
- Create: `Tests/StockpileCoreTests/SmokeTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stockpile",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StockpileCore"),
        .testTarget(
            name: "StockpileCoreTests",
            dependencies: ["StockpileCore"]
        ),
        .executableTarget(
            name: "StockpileApp",
            dependencies: ["StockpileCore"]
        ),
    ]
)
```

- [ ] **Step 2: Add a trivial source so the target compiles**

`Sources/StockpileCore/Version.swift`:
```swift
public enum Stockpile {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Write the smoke test**

`Tests/StockpileCoreTests/SmokeTests.swift`:
```swift
import Testing
@testable import StockpileCore

@Test func versionIsSet() {
    #expect(Stockpile.version == "0.1.0")
}
```

- [ ] **Step 4: Create an empty app entry point so the executable target builds**

`Sources/StockpileApp/StockpileApp.swift`:
```swift
// Placeholder replaced in Task 14. Keeps the executable target compiling.
@main
struct StockpileApp {
    static func main() {
        print("Stockpile \(StockpileCoreVersionShim.version)")
    }
}

import StockpileCore
enum StockpileCoreVersionShim {
    static var version: String { Stockpile.version }
}
```

- [ ] **Step 5: Build and test**

Run: `swift test`
Expected: builds, `versionIsSet` PASSES.

- [ ] **Step 6: Add `.gitignore` and commit**

`.gitignore`:
```
.build/
.swiftpm/
*.xcodeproj
Stockpile.app/
.DS_Store
```

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "chore: scaffold SPM package with core, app, and test targets"
```

---

## Task 2: Errors + JSON coders

**Files:**
- Create: `Sources/StockpileCore/Errors.swift`
- Create: `Sources/StockpileCore/JSONCoders.swift`

- [ ] **Step 1: Write `StockpileError`**

`Sources/StockpileCore/Errors.swift`:
```swift
import Foundation

public enum StockpileError: Error, Equatable {
    case doesNotExist(URL)
    case notADirectory(URL)
    case sourceIsSymlink(URL)
    case alreadyIntegrated(URL)
    case notIntegrated(URL)
    case driveNotMounted
    case insufficientSpace(needed: Int64, available: Int64)
    case destinationExists(URL)
    case verificationFailed(URL)
    case copyFailed(String)
}
```

- [ ] **Step 2: Write shared JSON coders**

`Sources/StockpileCore/JSONCoders.swift`:
```swift
import Foundation

extension JSONEncoder {
    static var stockpile: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var stockpile: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: compiles, no warnings.

- [ ] **Step 4: Commit**

```bash
git add Sources/StockpileCore/Errors.swift Sources/StockpileCore/JSONCoders.swift
git commit -m "feat: add StockpileError and shared JSON coders"
```

---

## Task 3: Models (DriveRef, Entry, Manifest, Status)

**Files:**
- Create: `Sources/StockpileCore/Models.swift`
- Test: `Tests/StockpileCoreTests/ManifestStoreTests.swift` (Codable round-trip lives here, store added next task)

- [ ] **Step 1: Write the models**

`Sources/StockpileCore/Models.swift`:
```swift
import Foundation

public struct DriveRef: Codable, Equatable {
    public var uuid: String
    public var name: String
    public var stockpileSubdir: String

    public init(uuid: String, name: String, stockpileSubdir: String = "Stockpile") {
        self.uuid = uuid
        self.name = name
        self.stockpileSubdir = stockpileSubdir
    }
}

public struct Entry: Codable, Equatable {
    public var original: String       // absolute path of the original folder
    public var destRelative: String   // path relative to the stockpile root
    public var bytes: Int64
    public var integratedAt: Date

    public init(original: String, destRelative: String, bytes: Int64, integratedAt: Date) {
        self.original = original
        self.destRelative = destRelative
        self.bytes = bytes
        self.integratedAt = integratedAt
    }
}

public struct Manifest: Codable, Equatable {
    public var version: Int
    public var drive: DriveRef?
    public var entries: [Entry]

    public init(version: Int = 1, drive: DriveRef? = nil, entries: [Entry] = []) {
        self.version = version
        self.drive = drive
        self.entries = entries
    }
}

public struct Status: Equatable {
    public var driveMounted: Bool
    public var stashedCount: Int
    public var freedBytes: Int64

    public init(driveMounted: Bool, stashedCount: Int, freedBytes: Int64) {
        self.driveMounted = driveMounted
        self.stashedCount = stashedCount
        self.freedBytes = freedBytes
    }
}
```

- [ ] **Step 2: Write a Codable round-trip test**

`Tests/StockpileCoreTests/ManifestStoreTests.swift`:
```swift
import Testing
import Foundation
@testable import StockpileCore

@Test func manifestRoundTripsThroughJSON() throws {
    let m = Manifest(
        version: 1,
        drive: DriveRef(uuid: "ABC-123", name: "T7"),
        entries: [
            Entry(original: "/Users/me/Movies",
                  destRelative: "Movies",
                  bytes: 268_435_456,
                  integratedAt: Date(timeIntervalSince1970: 1_700_000_000))
        ]
    )
    let data = try JSONEncoder.stockpile.encode(m)
    let back = try JSONDecoder.stockpile.decode(Manifest.self, from: data)
    #expect(back == m)
}
```

- [ ] **Step 3: Run the test**

Run: `swift test --filter manifestRoundTripsThroughJSON`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/StockpileCore/Models.swift Tests/StockpileCoreTests/ManifestStoreTests.swift
git commit -m "feat: add core models with Codable round-trip test"
```

---

## Task 4: ManifestStore (atomic load/save) + test helpers

**Files:**
- Create: `Sources/StockpileCore/ManifestStore.swift`
- Create: `Tests/StockpileCoreTests/TestSupport.swift`
- Modify: `Tests/StockpileCoreTests/ManifestStoreTests.swift`

- [ ] **Step 1: Write shared test helpers**

`Tests/StockpileCoreTests/TestSupport.swift`:
```swift
import Foundation

/// A throwaway temp directory, removed when the value is dropped.
final class TempDir {
    let url: URL
    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("stockpile-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }

    func sub(_ name: String) -> URL { url.appendingPathComponent(name) }
}

/// Build a folder with `files` (relative path -> contents) under `root`.
@discardableResult
func makeTree(at root: URL, files: [String: String]) throws -> URL {
    let fm = FileManager.default
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    for (rel, contents) in files {
        let f = root.appendingPathComponent(rel)
        try fm.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: f)
    }
    return root
}

func isSymlink(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
}

func symlinkTarget(_ url: URL) -> URL? {
    let p = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    return p.map { URL(fileURLWithPath: $0) }
}
```

- [ ] **Step 2: Write the failing ManifestStore test**

Append to `Tests/StockpileCoreTests/ManifestStoreTests.swift`:
```swift
@Test func loadReturnsEmptyManifestWhenFileMissing() throws {
    let dir = try TempDir()
    let store = ManifestStore(url: dir.sub("manifest.json"))
    let m = try store.load()
    #expect(m.entries.isEmpty)
    #expect(m.version == 1)
}

@Test func saveThenLoadPreservesManifest() throws {
    let dir = try TempDir()
    let store = ManifestStore(url: dir.sub("nested/manifest.json"))
    var m = Manifest(drive: DriveRef(uuid: "U", name: "T7"))
    m.entries.append(Entry(original: "/x", destRelative: "x", bytes: 10,
                           integratedAt: Date(timeIntervalSince1970: 1)))
    try store.save(m)
    let back = try store.load()
    #expect(back == m)
}

@Test func saveOverwritesExistingFileAtomically() throws {
    let dir = try TempDir()
    let store = ManifestStore(url: dir.sub("manifest.json"))
    try store.save(Manifest())
    var m2 = Manifest()
    m2.entries.append(Entry(original: "/y", destRelative: "y", bytes: 1,
                            integratedAt: Date(timeIntervalSince1970: 2)))
    try store.save(m2)
    #expect(try store.load().entries.count == 1)
}
```

- [ ] **Step 3: Run to verify failure**

Run: `swift test --filter ManifestStore`
Expected: FAIL — `ManifestStore` is not defined.

- [ ] **Step 4: Implement `ManifestStore`**

`Sources/StockpileCore/ManifestStore.swift`:
```swift
import Foundation

public struct ManifestStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> Manifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Manifest()
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.stockpile.decode(Manifest.self, from: data)
    }

    public func save(_ manifest: Manifest) throws {
        let data = try JSONEncoder.stockpile.encode(manifest)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        // .atomic writes to a temp file and renames into place — crash-safe.
        try data.write(to: url, options: .atomic)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter ManifestStore`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/StockpileCore/ManifestStore.swift Tests/StockpileCoreTests/TestSupport.swift Tests/StockpileCoreTests/ManifestStoreTests.swift
git commit -m "feat: add atomic ManifestStore with tests and test helpers"
```

---

## Task 5: DirStats + Copier (ditto) + verify

**Files:**
- Create: `Sources/StockpileCore/DirStats.swift`
- Create: `Sources/StockpileCore/Copier.swift`
- Create: `Tests/StockpileCoreTests/CopierTests.swift`

- [ ] **Step 1: Write failing Copier tests**

`Tests/StockpileCoreTests/CopierTests.swift`:
```swift
import Testing
import Foundation
@testable import StockpileCore

@Test func copyDuplicatesAFolderTree() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("src"),
                           files: ["a.txt": "hello", "sub/b.txt": "world"])
    let dest = dir.sub("dest")
    let copier = Copier()
    try copier.copy(from: src, to: dest)
    #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.txt").path))
    #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("sub/b.txt").path))
}

@Test func verifyReturnsTrueForIdenticalTrees() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("src"), files: ["a.txt": "hello", "b.txt": "xyz"])
    let dest = dir.sub("dest")
    let copier = Copier()
    try copier.copy(from: src, to: dest)
    #expect(try copier.verify(src: src, dest: dest))
}

@Test func verifyReturnsFalseWhenDestIncomplete() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("src"), files: ["a.txt": "hello", "b.txt": "xyz"])
    let dest = try makeTree(at: dir.sub("dest"), files: ["a.txt": "hello"])
    let copier = Copier()
    #expect(try copier.verify(src: src, dest: dest) == false)
}

@Test func copyThrowsCopyFailedForMissingSource() throws {
    let dir = try TempDir()
    let copier = Copier()
    #expect(throws: StockpileError.self) {
        try copier.copy(from: dir.sub("nope"), to: dir.sub("dest"))
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter Copier`
Expected: FAIL — `Copier` / `DirStats` not defined.

- [ ] **Step 3: Implement `DirStats`**

`Sources/StockpileCore/DirStats.swift`:
```swift
import Foundation

struct DirStats: Equatable {
    var fileCount: Int
    var totalBytes: Int64

    static func measure(_ url: URL) throws -> DirStats {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw StockpileError.doesNotExist(url)
        }
        if !isDir.boolValue {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return DirStats(fileCount: 1, totalBytes: Int64(size))
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            throw StockpileError.doesNotExist(url)
        }
        var count = 0
        var bytes: Int64 = 0
        for case let f as URL in en {
            let rv = try f.resourceValues(forKeys: keys)
            if rv.isRegularFile == true {
                count += 1
                bytes += Int64(rv.fileSize ?? 0)
            }
        }
        return DirStats(fileCount: count, totalBytes: bytes)
    }
}
```

- [ ] **Step 4: Implement `Copier`**

`Sources/StockpileCore/Copier.swift`:
```swift
import Foundation

public struct Copier {
    public init() {}

    public func copy(from src: URL, to dest: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [src.path, dest.path]
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
        } catch {
            throw StockpileError.copyFailed("could not launch ditto: \(error)")
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? "ditto exit \(p.terminationStatus)"
            throw StockpileError.copyFailed(msg)
        }
    }

    /// True when src and dest contain the same number of regular files and bytes.
    public func verify(src: URL, dest: URL) throws -> Bool {
        try DirStats.measure(src) == DirStats.measure(dest)
    }
}
```

- [ ] **Step 5: Run to verify pass**

Run: `swift test --filter Copier`
Expected: all PASS. (Requires `/usr/bin/ditto`, present on every macOS.)

- [ ] **Step 6: Commit**

```bash
git add Sources/StockpileCore/DirStats.swift Sources/StockpileCore/Copier.swift Tests/StockpileCoreTests/CopierTests.swift
git commit -m "feat: add ditto-based Copier with file-count+byte verification"
```

---

## Task 6: SpaceChecking protocol + filesystem impl

**Files:**
- Create: `Sources/StockpileCore/SpaceChecking.swift`

- [ ] **Step 1: Write the protocol and real implementation**

`Sources/StockpileCore/SpaceChecking.swift`:
```swift
import Foundation

public protocol SpaceChecking {
    /// Free bytes available on the volume containing `url`.
    func freeBytes(at url: URL) throws -> Int64
    /// Total bytes of regular files under `url`.
    func size(of url: URL) throws -> Int64
}

public struct FileSystemSpaceChecker: SpaceChecking {
    public init() {}

    public func freeBytes(at url: URL) throws -> Int64 {
        let vals = try url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(vals.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    public func size(of url: URL) throws -> Int64 {
        try DirStats.measure(url).totalBytes
    }
}
```

- [ ] **Step 2: Add a controllable stub for tests**

`Tests/StockpileCoreTests/TestSupport.swift` — append:
```swift
@testable import StockpileCore

/// Space checker whose answers the test controls.
struct StubSpaceChecker: SpaceChecking {
    var free: Int64
    var measured: ((URL) throws -> Int64)?
    func freeBytes(at url: URL) throws -> Int64 { free }
    func size(of url: URL) throws -> Int64 {
        if let measured { return try measured(url) }
        return try DirStats.measure(url).totalBytes
    }
}
```

- [ ] **Step 3: Build (no behavior test yet — exercised by Engine tests)**

Run: `swift build`
Expected: compiles.

- [ ] **Step 4: Commit**

```bash
git add Sources/StockpileCore/SpaceChecking.swift Tests/StockpileCoreTests/TestSupport.swift
git commit -m "feat: add SpaceChecking protocol, filesystem impl, and test stub"
```

---

## Task 7: Engine.integrate — happy path

**Files:**
- Create: `Sources/StockpileCore/Engine.swift`
- Create: `Tests/StockpileCoreTests/EngineIntegrateTests.swift`

- [ ] **Step 1: Write the failing happy-path test**

`Tests/StockpileCoreTests/EngineIntegrateTests.swift`:
```swift
import Testing
import Foundation
@testable import StockpileCore

private func makeEngine(_ dir: TempDir, free: Int64 = 1_000_000_000) -> Engine {
    Engine(store: ManifestStore(url: dir.sub("manifest.json")),
           copier: Copier(),
           space: StubSpaceChecker(free: free))
}

@Test func integrateCopiesReplacesWithSymlinkAndRecords() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("Movies"),
                           files: ["a.mp4": "aaaa", "x/b.mp4": "bbbb"])
    let driveRoot = dir.sub("drive/Stockpile")
    let engine = makeEngine(dir)

    let entry = try engine.integrate(src, driveRoot: driveRoot)

    // original is now a symlink pointing into the drive
    #expect(isSymlink(src))
    #expect(symlinkTarget(src)?.path == driveRoot.appendingPathComponent("Movies").path)
    // data is on the "drive"
    #expect(FileManager.default.fileExists(
        atPath: driveRoot.appendingPathComponent("Movies/a.mp4").path))
    // no leftover backup
    #expect(!FileManager.default.fileExists(atPath: src.path + ".stockpile-bak"))
    // manifest recorded it
    let m = try ManifestStore(url: dir.sub("manifest.json")).load()
    #expect(m.entries.count == 1)
    #expect(entry.destRelative == "Movies")
    #expect(m.entries[0].original == src.standardizedFileURL.path)
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter EngineIntegrate`
Expected: FAIL — `Engine` not defined.

- [ ] **Step 3: Implement `Engine` with integrate + helpers**

`Sources/StockpileCore/Engine.swift`:
```swift
import Foundation

public struct Engine {
    let store: ManifestStore
    let copier: Copier
    let space: SpaceChecking
    private let fm = FileManager.default

    public init(store: ManifestStore,
                copier: Copier = Copier(),
                space: SpaceChecking = FileSystemSpaceChecker()) {
        self.store = store
        self.copier = copier
        self.space = space
    }

    @discardableResult
    public func integrate(_ folder: URL, driveRoot: URL) throws -> Entry {
        let src = folder.standardizedFileURL

        // --- preflight ---
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else {
            throw StockpileError.doesNotExist(src)
        }
        if isSymlinkPath(src) { throw StockpileError.sourceIsSymlink(src) }
        guard isDir.boolValue else { throw StockpileError.notADirectory(src) }

        var manifest = try store.load()
        if manifest.entries.contains(where: { $0.original == src.path }) {
            throw StockpileError.alreadyIntegrated(src)
        }

        let needed = try space.size(of: src)
        let available = try space.freeBytes(at: driveRoot.deletingLastPathComponent())
        if available < needed {
            throw StockpileError.insufficientSpace(needed: needed, available: available)
        }

        // --- choose destination (dedup) ---
        try fm.createDirectory(at: driveRoot, withIntermediateDirectories: true)
        let relName = dedupName(base: src.lastPathComponent, in: driveRoot)
        let dest = driveRoot.appendingPathComponent(relName)
        if fm.fileExists(atPath: dest.path) {
            throw StockpileError.destinationExists(dest)
        }

        // --- copy + verify (original still intact) ---
        try copier.copy(from: src, to: dest)
        guard try copier.verify(src: src, dest: dest) else {
            try? fm.removeItem(at: dest)
            throw StockpileError.verificationFailed(src)
        }

        // --- swap: rename original aside, symlink, then delete backup ---
        let bak = backupURL(for: src)
        try fm.moveItem(at: src, to: bak)
        do {
            try fm.createSymbolicLink(at: src, withDestinationURL: dest)
        } catch {
            try? fm.moveItem(at: bak, to: src)   // roll back
            try? fm.removeItem(at: dest)
            throw error
        }
        try? fm.removeItem(at: bak)

        // --- record ---
        let entry = Entry(original: src.path,
                          destRelative: relName,
                          bytes: needed,
                          integratedAt: Date())
        manifest.entries.append(entry)
        try store.save(manifest)
        return entry
    }

    // MARK: - Helpers

    func isSymlinkPath(_ url: URL) -> Bool {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    func backupURL(for src: URL) -> URL {
        URL(fileURLWithPath: src.path + ".stockpile-bak")
    }

    func dedupName(base: String, in root: URL) -> String {
        if !fm.fileExists(atPath: root.appendingPathComponent(base).path) { return base }
        let ns = base as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)"
            if !fm.fileExists(atPath: root.appendingPathComponent(candidate).path) {
                return candidate
            }
            i += 1
        }
    }
}
```

> Note: preflight uses `attributesOfItem` (which does NOT follow symlinks) to detect a symlink, because `fileExists` follows links. `space.freeBytes` is checked against `driveRoot`'s parent so the check works even before the `Stockpile` subdir exists.

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter EngineIntegrate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StockpileCore/Engine.swift Tests/StockpileCoreTests/EngineIntegrateTests.swift
git commit -m "feat: add Engine.integrate happy path (copy-verify-swap)"
```

---

## Task 8: Engine.integrate — edge cases

**Files:**
- Modify: `Tests/StockpileCoreTests/EngineIntegrateTests.swift`

- [ ] **Step 1: Add failing edge-case tests**

Append to `Tests/StockpileCoreTests/EngineIntegrateTests.swift`:
```swift
@Test func integrateRejectsASymlinkSource() throws {
    let dir = try TempDir()
    let real = try makeTree(at: dir.sub("real"), files: ["a": "1"])
    let link = dir.sub("link")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
    let engine = makeEngine(dir)
    #expect(throws: StockpileError.sourceIsSymlink(link.standardizedFileURL)) {
        try engine.integrate(link, driveRoot: dir.sub("drive/Stockpile"))
    }
}

@Test func integrateRejectsADoubleIntegrate() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("Docs"), files: ["a": "1"])
    let engine = makeEngine(dir)
    try engine.integrate(src, driveRoot: dir.sub("drive/Stockpile"))
    #expect(throws: StockpileError.self) {
        // src is now a symlink, so this throws sourceIsSymlink
        try engine.integrate(src, driveRoot: dir.sub("drive/Stockpile"))
    }
}

@Test func integrateDedupsDestinationNameOnCollision() throws {
    let dir = try TempDir()
    let driveRoot = dir.sub("drive/Stockpile")
    // pre-create a colliding folder on the drive
    try makeTree(at: driveRoot.appendingPathComponent("Movies"), files: ["old": "x"])
    let src = try makeTree(at: dir.sub("Movies"), files: ["a": "1"])
    let engine = makeEngine(dir)
    let entry = try engine.integrate(src, driveRoot: driveRoot)
    #expect(entry.destRelative == "Movies 2")
    #expect(symlinkTarget(src)?.lastPathComponent == "Movies 2")
}

@Test func integrateFailsWhenDriveIsTooFull() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("Big"), files: ["a": "12345"])
    let engine = Engine(store: ManifestStore(url: dir.sub("manifest.json")),
                        copier: Copier(),
                        space: StubSpaceChecker(free: 1))   // 1 byte free
    #expect(throws: StockpileError.self) {
        try engine.integrate(src, driveRoot: dir.sub("drive/Stockpile"))
    }
    // original untouched, no symlink
    #expect(!isSymlink(src))
    #expect(FileManager.default.fileExists(atPath: src.appendingPathComponent("a").path))
}
```

- [ ] **Step 2: Run the tests**

Run: `swift test --filter EngineIntegrate`
Expected: PASS (the Task 7 implementation already covers these paths).
If `integrateFailsWhenDriveIsTooFull` fails because `size(of:)` returns 0 for the stub, confirm `StubSpaceChecker.measured` is nil so it measures the real tree (5 bytes > 1 free).

- [ ] **Step 3: Commit**

```bash
git add Tests/StockpileCoreTests/EngineIntegrateTests.swift
git commit -m "test: cover integrate edge cases (symlink, dedup, full drive)"
```

---

## Task 9: Engine.disintegrate

**Files:**
- Modify: `Sources/StockpileCore/Engine.swift`
- Create: `Tests/StockpileCoreTests/EngineDisintegrateTests.swift`

- [ ] **Step 1: Write failing disintegrate tests**

`Tests/StockpileCoreTests/EngineDisintegrateTests.swift`:
```swift
import Testing
import Foundation
@testable import StockpileCore

private func engine(_ dir: TempDir, free: Int64 = 1_000_000_000) -> Engine {
    Engine(store: ManifestStore(url: dir.sub("manifest.json")),
           copier: Copier(),
           space: StubSpaceChecker(free: free))
}

@Test func disintegrateRestoresFolderAndClearsState() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("Movies"), files: ["a.mp4": "aaaa", "x/b": "bb"])
    let driveRoot = dir.sub("drive/Stockpile")
    let e = engine(dir)
    try e.integrate(src, driveRoot: driveRoot)
    #expect(isSymlink(src))

    try e.disintegrate(src, driveRoot: driveRoot)

    // back to a real directory with content
    #expect(!isSymlink(src))
    #expect(FileManager.default.fileExists(atPath: src.appendingPathComponent("a.mp4").path))
    // drive copy removed
    #expect(!FileManager.default.fileExists(
        atPath: driveRoot.appendingPathComponent("Movies").path))
    // manifest empty
    #expect(try ManifestStore(url: dir.sub("manifest.json")).load().entries.isEmpty)
}

@Test func disintegrateThrowsWhenNotIntegrated() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("Movies"), files: ["a": "1"])
    let e = engine(dir)
    #expect(throws: StockpileError.notIntegrated(src.standardizedFileURL)) {
        try e.disintegrate(src, driveRoot: dir.sub("drive/Stockpile"))
    }
}

@Test func disintegrateThrowsWhenDriveDataMissing() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("Movies"), files: ["a": "1"])
    let driveRoot = dir.sub("drive/Stockpile")
    let e = engine(dir)
    try e.integrate(src, driveRoot: driveRoot)
    // simulate unplugged drive: remove the data
    try FileManager.default.removeItem(at: driveRoot.appendingPathComponent("Movies"))
    #expect(throws: StockpileError.driveNotMounted) {
        try e.disintegrate(src, driveRoot: driveRoot)
    }
}

@Test func disintegrateFailsWhenInternalTooFull() throws {
    let dir = try TempDir()
    let src = try makeTree(at: dir.sub("Movies"), files: ["a": "12345"])
    let driveRoot = dir.sub("drive/Stockpile")
    try engine(dir).integrate(src, driveRoot: driveRoot)
    // new engine reporting only 1 free byte for the restore target
    let tight = Engine(store: ManifestStore(url: dir.sub("manifest.json")),
                       copier: Copier(),
                       space: StubSpaceChecker(free: 1))
    #expect(throws: StockpileError.self) {
        try tight.disintegrate(src, driveRoot: driveRoot)
    }
    // symlink still present, drive data intact (no data lost)
    #expect(isSymlink(src))
    #expect(FileManager.default.fileExists(
        atPath: driveRoot.appendingPathComponent("Movies/a").path))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter EngineDisintegrate`
Expected: FAIL — `disintegrate` not defined.

- [ ] **Step 3: Implement `disintegrate`**

Add to `Sources/StockpileCore/Engine.swift` inside `public struct Engine`, after `integrate`:
```swift
    public func disintegrate(_ folder: URL, driveRoot: URL) throws {
        let orig = folder.standardizedFileURL
        var manifest = try store.load()
        guard let idx = manifest.entries.firstIndex(where: { $0.original == orig.path }) else {
            throw StockpileError.notIntegrated(orig)
        }
        let entry = manifest.entries[idx]
        let dest = driveRoot.appendingPathComponent(entry.destRelative)

        // drive data must be present
        guard fm.fileExists(atPath: dest.path) else {
            throw StockpileError.driveNotMounted
        }

        // internal must have room
        let needed = try space.size(of: dest)
        let available = try space.freeBytes(at: orig.deletingLastPathComponent())
        if available < needed {
            throw StockpileError.insufficientSpace(needed: needed, available: available)
        }

        // remove only the symlink (never its target)
        if isSymlinkPath(orig) {
            try fm.removeItem(at: orig)
        }

        // copy back + verify
        try copier.copy(from: dest, to: orig)
        guard try copier.verify(src: dest, dest: orig) else {
            try? fm.removeItem(at: orig)
            try? fm.createSymbolicLink(at: orig, withDestinationURL: dest)
            throw StockpileError.verificationFailed(orig)
        }

        // success: drop drive copy + manifest entry
        try fm.removeItem(at: dest)
        manifest.entries.remove(at: idx)
        try store.save(manifest)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter EngineDisintegrate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/StockpileCore/Engine.swift Tests/StockpileCoreTests/EngineDisintegrateTests.swift
git commit -m "feat: add Engine.disintegrate with preflight + no-data-loss guarantees"
```

---

## Task 10: Engine.repair (interrupted-swap recovery) + status

**Files:**
- Modify: `Sources/StockpileCore/Engine.swift`
- Create: `Tests/StockpileCoreTests/EngineRepairTests.swift`

- [ ] **Step 1: Write failing repair + status tests**

`Tests/StockpileCoreTests/EngineRepairTests.swift`:
```swift
import Testing
import Foundation
@testable import StockpileCore

private func engine(_ dir: TempDir) -> Engine {
    Engine(store: ManifestStore(url: dir.sub("manifest.json")),
           copier: Copier(),
           space: StubSpaceChecker(free: 1_000_000_000))
}

@Test func repairFinishesSwapWhenCopySucceededButLinkMissing() throws {
    let dir = try TempDir()
    let orig = dir.sub("Movies")
    let driveRoot = dir.sub("drive/Stockpile")
    // simulate crash AFTER copy + rename-to-bak, BEFORE symlink
    try makeTree(at: driveRoot.appendingPathComponent("Movies"), files: ["a": "1"])
    try makeTree(at: dir.sub("Movies.stockpile-bak"), files: ["a": "1"])
    var m = Manifest()
    m.entries.append(Entry(original: orig.standardizedFileURL.path,
                           destRelative: "Movies", bytes: 1,
                           integratedAt: Date(timeIntervalSince1970: 1)))
    try ManifestStore(url: dir.sub("manifest.json")).save(m)

    try engine(dir).repair(driveRoot: driveRoot)

    #expect(isSymlink(orig))
    #expect(!FileManager.default.fileExists(atPath: orig.path + ".stockpile-bak"))
}

@Test func repairRollsBackWhenCopyMissing() throws {
    let dir = try TempDir()
    let orig = dir.sub("Movies")
    let driveRoot = dir.sub("drive/Stockpile")
    // simulate crash after rename-to-bak, copy never landed
    try makeTree(at: dir.sub("Movies.stockpile-bak"), files: ["a": "1"])
    var m = Manifest()
    m.entries.append(Entry(original: orig.standardizedFileURL.path,
                           destRelative: "Movies", bytes: 1,
                           integratedAt: Date(timeIntervalSince1970: 1)))
    try ManifestStore(url: dir.sub("manifest.json")).save(m)

    try engine(dir).repair(driveRoot: driveRoot)

    #expect(!isSymlink(orig))
    #expect(FileManager.default.fileExists(atPath: orig.appendingPathComponent("a").path))
    #expect(!FileManager.default.fileExists(atPath: orig.path + ".stockpile-bak"))
}

@Test func statusSummarizesManifest() throws {
    let dir = try TempDir()
    var m = Manifest()
    m.entries.append(Entry(original: "/a", destRelative: "a", bytes: 100,
                           integratedAt: Date(timeIntervalSince1970: 1)))
    m.entries.append(Entry(original: "/b", destRelative: "b", bytes: 50,
                           integratedAt: Date(timeIntervalSince1970: 2)))
    try ManifestStore(url: dir.sub("manifest.json")).save(m)
    let s = try engine(dir).status(driveMounted: true)
    #expect(s == Status(driveMounted: true, stashedCount: 2, freedBytes: 150))
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter EngineRepair`
Expected: FAIL — `repair` / `status` not defined.

- [ ] **Step 3: Implement `repair` and `status`**

Add to `Sources/StockpileCore/Engine.swift` inside `public struct Engine`:
```swift
    /// Recover from a crash during the integrate swap window.
    public func repair(driveRoot: URL) throws {
        let manifest = try store.load()
        for entry in manifest.entries {
            let orig = URL(fileURLWithPath: entry.original)
            let bak = backupURL(for: orig)
            let dest = driveRoot.appendingPathComponent(entry.destRelative)

            let bakExists = fm.fileExists(atPath: bak.path)
            // path exists as a non-symlink? (fileExists follows links, so check type)
            let origIsRealItem = fm.fileExists(atPath: orig.path) && !isSymlinkPath(orig)

            guard bakExists, !origIsRealItem, !isSymlinkPath(orig) else { continue }

            if fm.fileExists(atPath: dest.path) {
                // copy had landed: finish the swap
                try fm.createSymbolicLink(at: orig, withDestinationURL: dest)
                try fm.removeItem(at: bak)
            } else {
                // copy never landed: roll the original back
                try fm.moveItem(at: bak, to: orig)
            }
        }
    }

    public func status(driveMounted: Bool) throws -> Status {
        let m = try store.load()
        let freed = m.entries.reduce(Int64(0)) { $0 + $1.bytes }
        return Status(driveMounted: driveMounted,
                      stashedCount: m.entries.count,
                      freedBytes: freed)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter EngineRepair`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: every test PASSES.

- [ ] **Step 6: Commit**

```bash
git add Sources/StockpileCore/Engine.swift Tests/StockpileCoreTests/EngineRepairTests.swift
git commit -m "feat: add Engine.repair (crash recovery) and status summary"
```

---

## Task 11: DriveLocating (UUID <-> mount point)

**Files:**
- Create: `Sources/StockpileCore/DriveLocating.swift`
- Create: `Tests/StockpileCoreTests/DriveLocatingTests.swift`

- [ ] **Step 1: Write the protocol + FileManager implementation**

`Sources/StockpileCore/DriveLocating.swift`:
```swift
import Foundation

public struct VolumeInfo: Equatable {
    public var name: String
    public var uuid: String
    public var url: URL
}

public protocol DriveLocating {
    func mountedVolumes() -> [VolumeInfo]
    func mountPoint(forUUID uuid: String) -> URL?
    func uuid(forMountPoint url: URL) -> String?
}

public struct FileManagerDriveLocator: DriveLocating {
    public init() {}

    public func mountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeUUIDStringKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let rv = try? url.resourceValues(forKeys: Set(keys)),
                  let uuid = rv.volumeUUIDString else { return nil }
            return VolumeInfo(name: rv.volumeName ?? url.lastPathComponent,
                              uuid: uuid, url: url)
        }
    }

    public func mountPoint(forUUID uuid: String) -> URL? {
        mountedVolumes().first { $0.uuid == uuid }?.url
    }

    public func uuid(forMountPoint url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }
}
```

- [ ] **Step 2: Write a smoke test against the boot volume**

`Tests/StockpileCoreTests/DriveLocatingTests.swift`:
```swift
import Testing
import Foundation
@testable import StockpileCore

@Test func bootVolumeHasAUUIDAndRoundTrips() throws {
    let locator = FileManagerDriveLocator()
    let root = URL(fileURLWithPath: "/")
    guard let uuid = locator.uuid(forMountPoint: root) else {
        // Some CI volumes lack a UUID; skip rather than fail.
        return
    }
    #expect(!uuid.isEmpty)
    // The boot volume should appear among mounted volumes.
    #expect(locator.mountedVolumes().contains { $0.uuid == uuid }
            || locator.mountPoint(forUUID: uuid) != nil)
}
```

- [ ] **Step 3: Run**

Run: `swift test --filter DriveLocating`
Expected: PASS (or no-op skip if `/` lacks a UUID).

- [ ] **Step 4: Commit**

```bash
git add Sources/StockpileCore/DriveLocating.swift Tests/StockpileCoreTests/DriveLocatingTests.swift
git commit -m "feat: add DriveLocating with FileManager-based UUID resolution"
```

---

## Task 12: DriveWatcher (mount/unmount events)

**Files:**
- Create: `Sources/StockpileCore/DriveWatcher.swift`

No unit test — this wraps system notifications and is exercised manually in Task 15. Keep it a thin, side-effect-only shim.

- [ ] **Step 1: Implement the watcher**

`Sources/StockpileCore/DriveWatcher.swift`:
```swift
import Foundation
import AppKit

/// Observes external volume mount/unmount and reports the affected mount point.
public final class DriveWatcher {
    public var onMount: ((URL) -> Void)?
    public var onUnmount: ((URL) -> Void)?

    private var tokens: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil, queue: .main) { [weak self] note in
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self?.onMount?(url)
                }
        })
        tokens.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil, queue: .main) { [weak self] note in
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self?.onUnmount?(url)
                }
        })
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
    }

    deinit { stop() }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles (AppKit links on macOS).

- [ ] **Step 3: Commit**

```bash
git add Sources/StockpileCore/DriveWatcher.swift
git commit -m "feat: add DriveWatcher for mount/unmount events"
```

---

## Task 13: App ViewModel

**Files:**
- Create: `Sources/StockpileApp/ViewModel.swift`

This bridges the core to SwiftUI. It owns the manifest path, the chosen drive, and the observable state the menu renders. File operations run off the main thread; published state updates on the main thread.

- [ ] **Step 1: Implement the view model**

`Sources/StockpileApp/ViewModel.swift`:
```swift
import Foundation
import SwiftUI
import StockpileCore

@MainActor
final class ViewModel: ObservableObject {
    @Published var status = Status(driveMounted: false, stashedCount: 0, freedBytes: 0)
    @Published var entries: [Entry] = []
    @Published var busy = false
    @Published var lastError: String?

    private let store: ManifestStore
    private let locator: DriveLocating
    private let watcher = DriveWatcher()
    private var engine: Engine { Engine(store: store) }

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stockpile", isDirectory: true)
        self.store = ManifestStore(url: appSupport.appendingPathComponent("manifest.json"))
        self.locator = FileManagerDriveLocator()
        watcher.onMount = { [weak self] _ in Task { await self?.refresh() } }
        watcher.onUnmount = { [weak self] _ in Task { await self?.refresh() } }
        watcher.start()
    }

    /// Absolute stockpile root for the configured drive, or nil if unplugged.
    private func driveRoot() throws -> URL? {
        let manifest = try store.load()
        guard let drive = manifest.drive,
              let mount = locator.mountPoint(forUUID: drive.uuid) else { return nil }
        return mount.appendingPathComponent(drive.stockpileSubdir, isDirectory: true)
    }

    func refresh() async {
        do {
            let manifest = try store.load()
            let mounted = (try driveRoot()) != nil
            await MainActor.run {
                self.entries = manifest.entries
                self.status = Status(driveMounted: mounted,
                                     stashedCount: manifest.entries.count,
                                     freedBytes: manifest.entries.reduce(0) { $0 + $1.bytes })
            }
        } catch {
            await report(error)
        }
    }

    /// First-run drive selection. `volume` comes from a picker in the menu.
    func chooseDrive(_ volume: VolumeInfo) async {
        do {
            var manifest = try store.load()
            manifest.drive = DriveRef(uuid: volume.uuid, name: volume.name)
            try store.save(manifest)
            await refresh()
        } catch { await report(error) }
    }

    func availableVolumes() -> [VolumeInfo] {
        locator.mountedVolumes().filter { $0.url.path != "/" }
    }

    func integrate(_ folder: URL) async { await run { engine, root in
        try engine.integrate(folder, driveRoot: root)
    } }

    func disintegrate(_ original: URL) async { await run { engine, root in
        try engine.disintegrate(original, driveRoot: root)
    } }

    private func run(_ op: @escaping (Engine, URL) throws -> Void) async {
        await MainActor.run { self.busy = true; self.lastError = nil }
        do {
            guard let root = try driveRoot() else { throw StockpileError.driveNotMounted }
            let engine = self.engine
            try await Task.detached { try op(engine, root) }.value
            await refresh()
        } catch { await report(error) }
        await MainActor.run { self.busy = false }
    }

    private func report(_ error: Error) async {
        await MainActor.run { self.lastError = String(describing: error) }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: compiles.

- [ ] **Step 3: Commit**

```bash
git add Sources/StockpileApp/ViewModel.swift
git commit -m "feat: add app ViewModel bridging core engine to SwiftUI"
```

---

## Task 14: MenuBarExtra UI

**Files:**
- Modify: `Sources/StockpileApp/StockpileApp.swift` (replace Task 1 placeholder)
- Create: `Sources/StockpileApp/MenuView.swift`

- [ ] **Step 1: Replace the placeholder app entry point**

`Sources/StockpileApp/StockpileApp.swift`:
```swift
import SwiftUI

@main
struct StockpileApp: App {
    @StateObject private var vm = ViewModel()

    var body: some Scene {
        MenuBarExtra("Stockpile", systemImage: vm.status.driveMounted
                     ? "externaldrive.fill.badge.checkmark"
                     : "externaldrive.badge.xmark") {
            MenuView(vm: vm)
        }
        .menuBarExtraStyle(.window)
    }
}
```

- [ ] **Step 2: Write the menu view**

`Sources/StockpileApp/MenuView.swift`:
```swift
import SwiftUI
import AppKit
import StockpileCore

struct MenuView: View {
    @ObservedObject var vm: ViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            if vm.entries.isEmpty {
                Text("No folders stashed.").foregroundStyle(.secondary)
            } else {
                ForEach(vm.entries, id: \.original) { entry in
                    row(entry)
                }
            }
            Divider()
            drivePicker
            Button("Stash a folder…") { stashFolder() }
                .disabled(vm.busy || !vm.status.driveMounted)
            if vm.busy {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Working…") }
                    .foregroundStyle(.secondary)
            }
            if let err = vm.lastError {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 320)
        .task { await vm.refresh() }
    }

    /// First-run / change-of-drive selection.
    private var drivePicker: some View {
        Menu("Use drive…") {
            ForEach(vm.availableVolumes(), id: \.uuid) { vol in
                Button("\(vol.name) (\(vol.url.lastPathComponent))") {
                    Task { await vm.chooseDrive(vol) }
                }
            }
        }
        .disabled(vm.busy)
    }

    private var header: some View {
        let freedGB = Double(vm.status.freedBytes) / 1_000_000_000
        return Text(vm.status.driveMounted
            ? String(format: "Drive ✓ · %d stashed · %.1f GB freed",
                     vm.status.stashedCount, freedGB)
            : "Drive missing · \(vm.status.stashedCount) folders offline")
            .font(.headline)
            .foregroundStyle(vm.status.driveMounted ? .primary : .red)
    }

    private func row(_ entry: Entry) -> some View {
        HStack {
            Text((entry.original as NSString).lastPathComponent)
            Spacer()
            Button("Disintegrate") {
                Task { await vm.disintegrate(URL(fileURLWithPath: entry.original)) }
            }
            .disabled(vm.busy || !vm.status.driveMounted)
        }
    }

    private func stashFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await vm.integrate(url) }
        }
    }
}
```

- [ ] **Step 3: Build and launch manually**

Run: `swift build && swift run StockpileApp`
Expected: a menu-bar icon appears. Clicking it shows the panel. (Drive selection UI is wired via `vm.availableVolumes()` / `vm.chooseDrive` — if no drive is configured yet, see Task 15's manual check to set it.)

- [ ] **Step 4: Commit**

```bash
git add Sources/StockpileApp/StockpileApp.swift Sources/StockpileApp/MenuView.swift
git commit -m "feat: add MenuBarExtra UI with stash/disintegrate actions"
```

---

## Task 15: Packaging into a menu-bar .app

**Files:**
- Create: `scripts/bundle.sh`
- Create: `Resources/Info.plist`

The SPM executable is a bare binary; a menu-bar app needs a bundle with `LSUIElement` set (no Dock icon) and an `Info.plist`. The app is **non-sandboxed** by default (no entitlements file), which it requires for arbitrary-folder + external-volume access.

- [ ] **Step 1: Write the Info.plist**

`Resources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Stockpile</string>
    <key>CFBundleIdentifier</key><string>sh.tenet.stockpile</string>
    <key>CFBundleVersion</key><string>0.1.0</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>StockpileApp</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```

- [ ] **Step 2: Write the bundling script**

`scripts/bundle.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP="Stockpile.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/StockpileApp "$APP/Contents/MacOS/StockpileApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc sign for local use (no sandbox entitlements = full disk access prompts).
codesign --force --deep --sign - "$APP"

echo "Built $APP"
echo "Run: open $APP   (grant access if macOS prompts)"
```

- [ ] **Step 3: Make it executable and build the app**

Run:
```bash
chmod +x scripts/bundle.sh
./scripts/bundle.sh
open Stockpile.app
```
Expected: `Stockpile.app` builds; launching shows a menu-bar icon and **no Dock icon**.

- [ ] **Step 4: Manual end-to-end verification (real SSD)**

Do this with the actual T7 plugged in, using a small throwaway folder first:
1. Create a test folder: `mkdir -p ~/StockpileTest && echo hi > ~/StockpileTest/a.txt`
2. First run: open the menu → "Use drive…" → select the T7 (from `availableVolumes()`).
3. "Stash a folder…" → pick `~/StockpileTest`. Confirm `~/StockpileTest` is now a
   symlink → `/Volumes/T7/Stockpile/StockpileTest`, and `a.txt` is readable through it.
   Verify with: `ls -la ~/StockpileTest` (shows symlink) and `cat ~/StockpileTest/a.txt`.
4. Unplug T7 → menu turns red, "folders offline".
5. Replug → menu turns green again.
6. "Disintegrate" → folder restored locally, drive copy removed.
7. Clean up: `rm -rf ~/StockpileTest`.

Record the result of each step. Do not claim success for a step you did not run.

- [ ] **Step 5: Commit**

```bash
git add scripts/bundle.sh Resources/Info.plist
git commit -m "build: add app bundle packaging with LSUIElement menu-bar config"
```

---

## Notes for the implementer

- **Confirmation dialogs:** the spec calls for a confirm dialog before each move. The current UI triggers moves directly. Add a SwiftUI `.confirmationDialog` around `integrate`/`disintegrate` (showing folder name, size, and direction) before shipping; it does not affect core correctness, so it is left as a polish step rather than a core task.
- **ditto progress:** the UI shows an indeterminate "Working…" spinner during a copy. A determinate bar would require parsing `ditto -V` stderr line-by-line; out of scope for v1.
- **Always test with a throwaway folder first.** The core guarantees copy-verify-swap, but verify the real flow on disposable data before stashing anything that matters.
```
