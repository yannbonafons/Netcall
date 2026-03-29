// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Netcall",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "Netcall",
            targets: ["Netcall"]
        ),
    ],
    targets: [
        .target(
            name: "Netcall"
        ),
        .testTarget(
            name: "NetcallTests",
            dependencies: ["Netcall"]
        ),
    ]
)
