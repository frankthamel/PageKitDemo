// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NewsClient",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "NewsClient", targets: ["NewsClient"]),
        .library(name: "NewsClientLive", targets: ["NewsClientLive"]),
    ],
    targets: [
        .target(name: "NewsClient"),
        .target(name: "NewsClientLive", dependencies: ["NewsClient"]),
        .testTarget(name: "NewsClientTests", dependencies: ["NewsClient"]),
    ]
)
