import Foundation

public protocol SpaceChecking {
    /// Free bytes available on the volume containing `url`.
    func freeBytes(at url: URL) throws -> Int64
    /// Total bytes of regular files under `url`.
    func size(of url: URL) throws -> Int64
}

public struct FileSystemSpaceChecker: SpaceChecking {
    public init() {}

    public func freeBytes(at url: URL) throws -> Int64 {
        let vals = try url.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(vals.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    public func size(of url: URL) throws -> Int64 {
        try DirStats.measure(url).totalBytes
    }
}
