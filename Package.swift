// swift-tools-version: 6.2

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
            name: "Netcall",
            swiftSettings: [
                .enableExperimentalFeature("ApproachableConcurrency"),
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "NetcallTests",
            dependencies: ["Netcall"],
            swiftSettings: [
                .enableExperimentalFeature("ApproachableConcurrency"),
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ]
        ),
    ]
)
