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
