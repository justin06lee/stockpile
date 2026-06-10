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
    case sourceInsideStockpile(URL)
}

extension StockpileError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .doesNotExist(let url):
            return "“\(url.lastPathComponent)” doesn't exist."
        case .notADirectory(let url):
            return "“\(url.lastPathComponent)” isn't a folder."
        case .sourceIsSymlink(let url):
            return "“\(url.lastPathComponent)” is already a link, not a real folder."
        case .alreadyIntegrated(let url):
            return "“\(url.lastPathComponent)” is already stashed."
        case .notIntegrated(let url):
            return "“\(url.lastPathComponent)” isn't stashed."
        case .driveNotMounted:
            return "The stockpile drive isn't connected."
        case .insufficientSpace(let needed, let available):
            return "Not enough free space: need "
                 + ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
                 + ", only "
                 + ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                 + " available."
        case .destinationExists(let url):
            return "“\(url.lastPathComponent)” is in the way. Move it aside and try again."
        case .verificationFailed(let url):
            return "Copy verification failed for “\(url.lastPathComponent)”. Nothing was lost."
        case .copyFailed(let message):
            return "Copy failed: \(message)"
        case .sourceInsideStockpile(let url):
            return "“\(url.lastPathComponent)” is already on the stockpile drive."
        }
    }
}
