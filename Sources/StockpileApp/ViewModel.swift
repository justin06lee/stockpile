import Foundation
import SwiftUI
import StockpileCore

@MainActor
final class ViewModel: ObservableObject {
    @Published var status = Status(driveMounted: false, stashedCount: 0, freedBytes: 0)
    @Published var entries: [Entry] = []
    @Published var busy = false
    @Published var lastError: String?

    private let store: ManifestStore
    private let locator: DriveLocating
    private let watcher = DriveWatcher()
    private var engine: Engine { Engine(store: store) }

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stockpile", isDirectory: true)
        self.store = ManifestStore(url: appSupport.appendingPathComponent("manifest.json"))
        self.locator = FileManagerDriveLocator()
        watcher.onMount = { [weak self] _ in Task { await self?.refresh() } }
        watcher.onUnmount = { [weak self] _ in Task { await self?.refresh() } }
        watcher.start()
    }

    /// Absolute stockpile root for the configured drive, or nil if unplugged.
    private func driveRoot() throws -> URL? {
        let manifest = try store.load()
        guard let drive = manifest.drive,
              let mount = locator.mountPoint(forUUID: drive.uuid) else { return nil }
        return mount.appendingPathComponent(drive.stockpileSubdir, isDirectory: true)
    }

    func refresh() async {
        do {
            let manifest = try store.load()
            let mounted = (try driveRoot()) != nil
            self.entries = manifest.entries
            self.status = Status(driveMounted: mounted,
                                 stashedCount: manifest.entries.count,
                                 freedBytes: manifest.entries.reduce(0) { $0 + $1.bytes })
        } catch {
            report(error)
        }
    }

    /// First-run drive selection. `volume` comes from a picker in the menu.
    func chooseDrive(_ volume: VolumeInfo) async {
        do {
            var manifest = try store.load()
            manifest.drive = DriveRef(uuid: volume.uuid, name: volume.name)
            try store.save(manifest)
            await refresh()
        } catch { report(error) }
    }

    func availableVolumes() -> [VolumeInfo] {
        locator.mountedVolumes().filter { $0.url.path != "/" }
    }

    func integrate(_ folder: URL) async { await run { engine, root in
        try engine.integrate(folder, driveRoot: root)
    } }

    func disintegrate(_ original: URL) async { await run { engine, root in
        try engine.disintegrate(original, driveRoot: root)
    } }

    private func run(_ op: @escaping @Sendable (Engine, URL) throws -> Void) async {
        self.busy = true
        self.lastError = nil
        do {
            guard let root = try driveRoot() else { throw StockpileError.driveNotMounted }
            let engine = self.engine
            try await Task.detached { try op(engine, root) }.value
            await refresh()
        } catch { report(error) }
        self.busy = false
    }

    private func report(_ error: Error) {
        self.lastError = String(describing: error)
    }
}
