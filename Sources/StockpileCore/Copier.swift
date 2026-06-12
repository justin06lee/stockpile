import Foundation

public struct Copier: Sendable {
    public init() {}

    public func copy(from src: URL, to dest: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = [src.path, dest.path]
        let result: (status: Int32, stderr: Data)
        do {
            result = try Copier.runCapturingStderr(p)
        } catch {
            throw StockpileError.copyFailed("could not launch ditto: \(error)")
        }
        if result.status != 0 {
            let msg = String(data: result.stderr, encoding: .utf8)
                ?? "ditto exit \(result.status)"
            throw StockpileError.copyFailed(msg)
        }
    }

    /// Run `process`, draining its stderr on a background queue so a chatty child
    /// (ditto prints a warning per unreadable file/xattr) can't fill the ~64 KB
    /// pipe buffer and block on write while we block in `waitUntilExit()` — the
    /// deadlock that froze stashing on "working…". Reading concurrently lets the
    /// child keep writing; we collect everything once it hits EOF.
    static func runCapturingStderr(_ process: Process) throws -> (status: Int32, stderr: Data) {
        let errPipe = Pipe()
        process.standardError = errPipe
        let handle = errPipe.fileHandleForReading

        final class Box: @unchecked Sendable { var data = Data() }
        let box = Box()
        let drained = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = handle.readDataToEndOfFile()   // returns at EOF (child's stderr closes)
            drained.signal()
        }

        try process.run()
        process.waitUntilExit()
        drained.wait()                                // ensure all stderr is collected
        return (process.terminationStatus, box.data)
    }

    /// True when src and dest contain the same number of regular files and bytes.
    public func verify(src: URL, dest: URL) throws -> Bool {
        try DirStats.measure(src) == DirStats.measure(dest)
    }
}
