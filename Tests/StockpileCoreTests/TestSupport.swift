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
    // Use FileManager (live filesystem read) rather than URL.resourceValues,
    // which caches per-URL-instance and can report a stale value when the same
    // URL is queried before and after the on-disk type changes.
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.standardizedFileURL.path)
    return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
}

func symlinkTarget(_ url: URL) -> URL? {
    let p = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)
    return p.map { URL(fileURLWithPath: $0) }
}

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
