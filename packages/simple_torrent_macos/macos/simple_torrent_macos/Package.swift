// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "simple_torrent_macos",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "simple-torrent-macos", targets: ["simple_torrent_macos"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .binaryTarget(
            name: "SimpleTorrentNative",
            path: "Frameworks/SimpleTorrentNative.xcframework"
        ),
        .target(
            name: "simple_torrent_macos",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "SimpleTorrentNative",
            ],
            resources: [.process("PrivacyInfo.xcprivacy")],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
    ]
)
