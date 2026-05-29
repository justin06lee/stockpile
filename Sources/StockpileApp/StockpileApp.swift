// Placeholder replaced in Task 14. Keeps the executable target compiling.
@main
struct StockpileApp {
    static func main() {
        print("Stockpile \(StockpileCoreVersionShim.version)")
    }
}

import StockpileCore
enum StockpileCoreVersionShim {
    static var version: String { Stockpile.version }
}
