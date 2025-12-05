// swift-tools-version:5.3
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
        .package(url: "https://github.com/sukov/CachingPlayerItem.git", from: "2.2.0")
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
