// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AppleSpeechSpike",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "AppleSpeechSpike",
            dependencies: [.product(name: "SottoCore", package: "sotto")]
        )
    ]
)
