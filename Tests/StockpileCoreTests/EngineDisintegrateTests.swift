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
