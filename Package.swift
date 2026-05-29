// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Stockpile",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StockpileCore"),
        .testTarget(
            name: "StockpileCoreTests",
            dependencies: ["StockpileCore"]
        ),
        .executableTarget(
            name: "StockpileApp",
            dependencies: ["StockpileCore"]
        ),
    ]
)
