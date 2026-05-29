import Foundation

public struct Copier {
    public init() {}

    public func copy(from src: URL, to dest: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [src.path, dest.path]
        let errPipe = Pipe()
        p.standardError = errPipe
        do {
            try p.run()
        } catch {
            throw StockpileError.copyFailed("could not launch ditto: \(error)")
        }
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let msg = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8) ?? "ditto exit \(p.terminationStatus)"
            throw StockpileError.copyFailed(msg)
        }
    }

    /// True when src and dest contain the same number of regular files and bytes.
    public func verify(src: URL, dest: URL) throws -> Bool {
        try DirStats.measure(src) == DirStats.measure(dest)
    }
}
