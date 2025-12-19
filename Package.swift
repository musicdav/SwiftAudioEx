// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "SwiftAudioEx",
    platforms: [.iOS(.v11)],
    products: [
        .library(
            name: "SwiftAudioEx",
            targets: ["SwiftAudioEx"]),
    ],
    dependencies: [
        .package(url: "https://github.com/musicdav/CachingPlayerItem.git", branch: "master"),
    ],
    targets: [
        .target(
            name: "SwiftAudioEx",
            dependencies: [
                "CachingPlayerItem"
            ]),
        .testTarget(
            name: "SwiftAudioExTests",
            dependencies: ["SwiftAudioEx"],
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
