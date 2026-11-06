// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalDictation",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DictationCore", targets: ["DictationCore"]),
        .executable(name: "asr-bench", targets: ["ASRBench"]),
        .executable(name: "LocalDictation", targets: ["DictationApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.2"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1"),
    ],
    targets: [
        .target(name: "DictationCore", dependencies: [
            .product(name: "FluidAudio", package: "FluidAudio"),
        ]),
        .target(name: "WhisperEngine", dependencies: ["DictationCore",
            .product(name: "WhisperKit", package: "argmax-oss-swift"),
        ]),
        .executableTarget(name: "ASRBench", dependencies: ["DictationCore", "WhisperEngine"]),
        .target(name: "DictationSystem"),
        .target(name: "DictationModels", resources: [.copy("Resources/parakeet-ultra.json")]),
        .executableTarget(name: "DictationApp", dependencies: ["DictationCore", "DictationSystem", "DictationModels"]),
        .testTarget(name: "DictationCoreTests", dependencies: ["DictationCore"]),
        .testTarget(name: "DictationSystemTests", dependencies: ["DictationSystem"]),
        .testTarget(name: "DictationModelsTests", dependencies: ["DictationModels"]),
    ]
)
