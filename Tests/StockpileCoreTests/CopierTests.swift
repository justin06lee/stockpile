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

/// Regression: a child that floods stderr (ditto warns per unreadable file)
/// must not deadlock. The old code read the pipe only after waitUntilExit(),
/// so once stderr filled the ~64 KB pipe buffer the child blocked on write and
/// the parent blocked forever — the "working…" hang. The watchdog turns any
/// re-introduced deadlock into a test failure instead of an infinite hang.
@Test func runCapturingStderrDoesNotDeadlockOnLargeStderr() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "i=0; while [ $i -lt 20000 ]; do "
                 + "echo 'warn: noisy stderr line' 1>&2; i=$((i+1)); done; exit 3"]

    final class Out: @unchecked Sendable { var status: Int32 = -1; var bytes = 0 }
    let out = Out()
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        if let r = try? Copier.runCapturingStderr(p) {
            out.status = r.status
            out.bytes = r.stderr.count
        }
        done.signal()
    }
    #expect(done.wait(timeout: .now() + 30) == .success)   // deadlock → timeout → fail
    #expect(out.status == 3)
    #expect(out.bytes > 65_536)                            // proves we read past the buffer
}
