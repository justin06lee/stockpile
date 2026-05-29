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
