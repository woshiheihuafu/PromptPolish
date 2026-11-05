// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptPolish",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PromptPolish", targets: ["PromptPolish"])],
    targets: [
        .target(name: "PromptPolishCore"),
        .target(name: "PromptPolishUI", dependencies: ["PromptPolishCore"]),
        .executableTarget(name: "PromptPolish", dependencies: ["PromptPolishUI"]),
        .executableTarget(name: "PromptPolishChecks", dependencies: ["PromptPolishCore", "PromptPolishUI"], path: "Tests/PromptPolishCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
