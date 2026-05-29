import Foundation

public enum StockpileError: Error, Equatable {
    case doesNotExist(URL)
    case notADirectory(URL)
    case sourceIsSymlink(URL)
    case alreadyIntegrated(URL)
    case notIntegrated(URL)
    case driveNotMounted
    case insufficientSpace(needed: Int64, available: Int64)
    case destinationExists(URL)
    case verificationFailed(URL)
    case copyFailed(String)
}
