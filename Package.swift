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
    dependencies: [
        .package(url: "https://github.com/realm/SwiftLint", from: "0.57.0"),
    ],
    targets: [
        .target(
            name: "Netcall",
            swiftSettings: [
                .enableExperimentalFeature("ApproachableConcurrency"),
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
            ]
        ),
        .testTarget(
            name: "NetcallTests",
            dependencies: ["Netcall"],
            swiftSettings: [
                .enableExperimentalFeature("ApproachableConcurrency"),
                .defaultIsolation(MainActor.self),
                .swiftLanguageMode(.v6)
            ],
            plugins: [
                .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLint")
            ]
        ),
    ]
)
