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
