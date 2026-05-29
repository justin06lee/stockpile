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
