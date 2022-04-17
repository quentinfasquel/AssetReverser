// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "AssetReverser",
    platforms: [.iOS(.v10)],
    products: [
        .library(name: "AssetReverser", targets: ["AssetReverser"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AssetReverser",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "AssetReverserTests",
            exclude: ["Info.plist"]
        )
    ]
)
