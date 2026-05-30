import Foundation

public struct DriveRef: Codable, Equatable {
    public var uuid: String
    public var name: String
    public var stockpileSubdir: String

    public init(uuid: String, name: String, stockpileSubdir: String = "Stockpile") {
        self.uuid = uuid
        self.name = name
        self.stockpileSubdir = stockpileSubdir
    }
}

public struct Entry: Codable, Equatable {
    public var original: String       // absolute path of the original folder
    public var destRelative: String   // path relative to the stockpile root
    public var bytes: Int64
    public var integratedAt: Date

    public init(original: String, destRelative: String, bytes: Int64, integratedAt: Date) {
        self.original = original
        self.destRelative = destRelative
        self.bytes = bytes
        self.integratedAt = integratedAt
    }
}

public struct Manifest: Codable, Equatable {
    public var version: Int
    public var drive: DriveRef?
    public var entries: [Entry]

    public init(version: Int = 1, drive: DriveRef? = nil, entries: [Entry] = []) {
        self.version = version
        self.drive = drive
        self.entries = entries
    }
}

public struct Status: Equatable {
    public var driveMounted: Bool
    public var stashedCount: Int
    public var freedBytes: Int64

    public init(driveMounted: Bool, stashedCount: Int, freedBytes: Int64) {
        self.driveMounted = driveMounted
        self.stashedCount = stashedCount
        self.freedBytes = freedBytes
    }
}
