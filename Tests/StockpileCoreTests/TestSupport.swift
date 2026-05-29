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
