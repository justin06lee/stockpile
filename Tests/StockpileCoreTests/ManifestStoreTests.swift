import Testing
import Foundation
@testable import StockpileCore

@Test func manifestRoundTripsThroughJSON() throws {
    let m = Manifest(
        version: 1,
        drive: DriveRef(uuid: "ABC-123", name: "T7"),
        entries: [
            Entry(original: "/Users/me/Movies",
                  destRelative: "Movies",
                  bytes: 268_435_456,
                  integratedAt: Date(timeIntervalSince1970: 1_700_000_000))
        ]
    )
    let data = try JSONEncoder.stockpile.encode(m)
    let back = try JSONDecoder.stockpile.decode(Manifest.self, from: data)
    #expect(back == m)
}
