import Foundation

public struct Engine {
    let store: ManifestStore
    let copier: Copier
    let space: SpaceChecking
    private let fm = FileManager.default

    public init(store: ManifestStore,
                copier: Copier = Copier(),
                space: SpaceChecking = FileSystemSpaceChecker()) {
        self.store = store
        self.copier = copier
        self.space = space
    }

    @discardableResult
    public func integrate(_ folder: URL, driveRoot: URL) throws -> Entry {
        let src = folder.standardizedFileURL

        // --- preflight ---
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else {
            throw StockpileError.doesNotExist(src)
        }
        if isSymlinkPath(src) { throw StockpileError.sourceIsSymlink(src) }
        guard isDir.boolValue else { throw StockpileError.notADirectory(src) }

        var manifest = try store.load()
        if manifest.entries.contains(where: { $0.original == src.path }) {
            throw StockpileError.alreadyIntegrated(src)
        }

        let needed = try space.size(of: src)
        let available = try space.freeBytes(at: driveRoot.deletingLastPathComponent())
        if available < needed {
            throw StockpileError.insufficientSpace(needed: needed, available: available)
        }

        // --- choose destination (dedup) ---
        try fm.createDirectory(at: driveRoot, withIntermediateDirectories: true)
        let relName = dedupName(base: src.lastPathComponent, in: driveRoot)
        let dest = driveRoot.appendingPathComponent(relName)
        if fm.fileExists(atPath: dest.path) {
            throw StockpileError.destinationExists(dest)
        }

        // --- copy + verify (original still intact) ---
        try copier.copy(from: src, to: dest)
        guard try copier.verify(src: src, dest: dest) else {
            try? fm.removeItem(at: dest)
            throw StockpileError.verificationFailed(src)
        }

        // --- swap: rename original aside, symlink, then delete backup ---
        let bak = backupURL(for: src)
        try fm.moveItem(at: src, to: bak)
        do {
            try fm.createSymbolicLink(at: src, withDestinationURL: dest)
        } catch {
            try? fm.moveItem(at: bak, to: src)   // roll back
            try? fm.removeItem(at: dest)
            throw error
        }
        try? fm.removeItem(at: bak)

        // --- record ---
        let entry = Entry(original: src.path,
                          destRelative: relName,
                          bytes: needed,
                          integratedAt: Date())
        manifest.entries.append(entry)
        try store.save(manifest)
        return entry
    }

    public func disintegrate(_ folder: URL, driveRoot: URL) throws {
        let orig = folder.standardizedFileURL
        var manifest = try store.load()
        guard let idx = manifest.entries.firstIndex(where: { $0.original == orig.path }) else {
            throw StockpileError.notIntegrated(orig)
        }
        let entry = manifest.entries[idx]
        let dest = driveRoot.appendingPathComponent(entry.destRelative)

        // drive data must be present
        guard fm.fileExists(atPath: dest.path) else {
            throw StockpileError.driveNotMounted
        }

        // internal must have room
        let needed = try space.size(of: dest)
        let available = try space.freeBytes(at: orig.deletingLastPathComponent())
        if available < needed {
            throw StockpileError.insufficientSpace(needed: needed, available: available)
        }

        // remove only the symlink (never its target)
        if isSymlinkPath(orig) {
            try fm.removeItem(at: orig)
        }

        // copy back + verify
        try copier.copy(from: dest, to: orig)
        guard try copier.verify(src: dest, dest: orig) else {
            try? fm.removeItem(at: orig)
            try? fm.createSymbolicLink(at: orig, withDestinationURL: dest)
            throw StockpileError.verificationFailed(orig)
        }

        // success: drop drive copy + manifest entry
        try fm.removeItem(at: dest)
        manifest.entries.remove(at: idx)
        try store.save(manifest)
    }

    /// Recover from a crash during the integrate swap window.
    public func repair(driveRoot: URL) throws {
        let manifest = try store.load()
        for entry in manifest.entries {
            let orig = URL(fileURLWithPath: entry.original)
            let bak = backupURL(for: orig)
            let dest = driveRoot.appendingPathComponent(entry.destRelative)

            let bakExists = fm.fileExists(atPath: bak.path)
            // path exists as a non-symlink? (fileExists follows links, so check type)
            let origIsRealItem = fm.fileExists(atPath: orig.path) && !isSymlinkPath(orig)

            guard bakExists, !origIsRealItem, !isSymlinkPath(orig) else { continue }

            if fm.fileExists(atPath: dest.path) {
                // copy had landed: finish the swap
                try fm.createSymbolicLink(at: orig, withDestinationURL: dest)
                try fm.removeItem(at: bak)
            } else {
                // copy never landed: roll the original back
                try fm.moveItem(at: bak, to: orig)
            }
        }
    }

    public func status(driveMounted: Bool) throws -> Status {
        let m = try store.load()
        let freed = m.entries.reduce(Int64(0)) { $0 + $1.bytes }
        return Status(driveMounted: driveMounted,
                      stashedCount: m.entries.count,
                      freedBytes: freed)
    }

    // MARK: - Helpers

    func isSymlinkPath(_ url: URL) -> Bool {
        let attrs = try? fm.attributesOfItem(atPath: url.path)
        return (attrs?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    func backupURL(for src: URL) -> URL {
        URL(fileURLWithPath: src.path + ".stockpile-bak")
    }

    func dedupName(base: String, in root: URL) -> String {
        if !fm.fileExists(atPath: root.appendingPathComponent(base).path) { return base }
        let ns = base as NSString
        let ext = ns.pathExtension
        let stem = ns.deletingPathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(i)" : "\(stem) \(i).\(ext)"
            if !fm.fileExists(atPath: root.appendingPathComponent(candidate).path) {
                return candidate
            }
            i += 1
        }
    }
}
