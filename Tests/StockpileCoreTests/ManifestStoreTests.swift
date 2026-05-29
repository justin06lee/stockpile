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
