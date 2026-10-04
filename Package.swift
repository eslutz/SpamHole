// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpamHoleCore",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "SpamHoleCore", targets: ["SpamHoleCore"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "SpamHoleCore", dependencies: ["CSQLite"]),
        .testTarget(name: "SpamHoleCoreTests", dependencies: ["SpamHoleCore"], resources: [.copy("Fixtures")])
    ]
)
