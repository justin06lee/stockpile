import Testing
import Foundation
@testable import StockpileCore

@Test func bootVolumeHasAUUIDAndRoundTrips() throws {
    let locator = FileManagerDriveLocator()
    let root = URL(fileURLWithPath: "/")
    guard let uuid = locator.uuid(forMountPoint: root) else {
        // Some CI volumes lack a UUID; skip rather than fail.
        return
    }
    #expect(!uuid.isEmpty)
    // The boot volume should appear among mounted volumes.
    #expect(locator.mountedVolumes().contains { $0.uuid == uuid }
            || locator.mountPoint(forUUID: uuid) != nil)
}
