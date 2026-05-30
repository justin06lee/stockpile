import Foundation

struct DirStats: Equatable {
    var fileCount: Int
    var totalBytes: Int64

    static func measure(_ url: URL) throws -> DirStats {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
            throw StockpileError.doesNotExist(url)
        }
        if !isDir.boolValue {
            let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return DirStats(fileCount: 1, totalBytes: Int64(size))
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            throw StockpileError.doesNotExist(url)
        }
        var count = 0
        var bytes: Int64 = 0
        for case let f as URL in en {
            let rv = try f.resourceValues(forKeys: keys)
            if rv.isRegularFile == true {
                count += 1
                bytes += Int64(rv.fileSize ?? 0)
            }
        }
        return DirStats(fileCount: count, totalBytes: bytes)
    }
}
