import Foundation

public struct VolumeInfo: Equatable {
    public var name: String
    public var uuid: String
    public var url: URL
}

public protocol DriveLocating {
    func mountedVolumes() -> [VolumeInfo]
    func mountPoint(forUUID uuid: String) -> URL?
    func uuid(forMountPoint url: URL) -> String?
}

public struct FileManagerDriveLocator: DriveLocating {
    public init() {}

    public func mountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeUUIDStringKey]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let rv = try? url.resourceValues(forKeys: Set(keys)),
                  let uuid = rv.volumeUUIDString else { return nil }
            return VolumeInfo(name: rv.volumeName ?? url.lastPathComponent,
                              uuid: uuid, url: url)
        }
    }

    public func mountPoint(forUUID uuid: String) -> URL? {
        mountedVolumes().first { $0.uuid == uuid }?.url
    }

    public func uuid(forMountPoint url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }
}
