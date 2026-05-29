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
