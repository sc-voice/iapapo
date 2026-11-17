// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "VACore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "VACore",
            targets: ["VACore"]
        ),
        .library(
            name: "VACoreSpeech",
            targets: ["VACoreSpeech"]
        ),
        .executable(
            name: "transcribe",
            targets: ["transcribe"]
        ),
        .executable(
            name: "eval_take",
            targets: ["eval_take"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "VACore",
            resources: [.copy("Resources/wakenet.mlmodelc")]
        ),
        // On-device speech transcription. Kept apart from VACore so VACore has no Speech dependency.
        .target(
            name: "VACoreSpeech",
            dependencies: ["VACore"]
        ),
        // Command-line transcription. The Info.plist is embedded so macOS can show the speech permission prompt.
        .executableTarget(
            name: "transcribe",
            dependencies: ["VACoreSpeech"],
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/transcribe/Info.plist",
                ])
            ]
        ),
        // Scores one take with a run's model and writes its eval record, as scripts/python/eval_take.py does.
        .executableTarget(
            name: "eval_take",
            dependencies: ["VACore"]
        ),
        .testTarget(
            name: "VACoreSpeechTests",
            dependencies: ["VACoreSpeech", "VACore"]
        ),
        .testTarget(
            name: "VACoreTests",
            dependencies: ["VACore"]
        ),
        // Checks the Swift front end and resampler against Python references in lab/. Run by make test-wakeword.
        .testTarget(
            name: "VAValidationTests",
            dependencies: ["VACore"]
        ),
    ]
)
