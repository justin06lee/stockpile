import Foundation
import AppKit

/// Observes external volume mount/unmount and reports the affected mount point.
public final class DriveWatcher {
    public var onMount: ((URL) -> Void)?
    public var onUnmount: ((URL) -> Void)?

    private var tokens: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil, queue: .main) { [weak self] note in
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self?.onMount?(url)
                }
        })
        tokens.append(center.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil, queue: .main) { [weak self] note in
                if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
                    self?.onUnmount?(url)
                }
        })
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        tokens.forEach { center.removeObserver($0) }
        tokens.removeAll()
    }

    deinit { stop() }
}
