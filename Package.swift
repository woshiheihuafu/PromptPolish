// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PromptPolish",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "PromptPolish", targets: ["PromptPolish"])],
    targets: [
        .target(name: "PromptPolishCore"),
        .executableTarget(name: "PromptPolish", dependencies: ["PromptPolishCore"]),
        .executableTarget(name: "PromptPolishChecks", dependencies: ["PromptPolishCore"], path: "Tests/PromptPolishCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
