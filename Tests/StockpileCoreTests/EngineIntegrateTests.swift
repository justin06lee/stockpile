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
