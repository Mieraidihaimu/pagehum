// swift-tools-version: 6.2
import PackageDescription

// The only module that depends on Kokoro and MLX; the app and CLI reach them through its API.
let package = Package(
    name: "SpeechCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SpeechCore", targets: ["SpeechCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mlalma/kokoro-ios", from: "1.0.10"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", from: "0.0.6"),
    ],
    targets: [
        .target(
            name: "SpeechCore",
            dependencies: [
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
