// swift-tools-version: 6.0
import PackageDescription

// ChorusProviderKit is Foundation-only so a speech extension can link it. That
// is the whole point of the split: the AppKit and SwiftUI installer lives in a
// separate library, and providers no longer restate the artifact layout that
// ChorusProviderKit already describes.
let package = Package(
    name: "ChorusKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChorusProviderKit", targets: ["ChorusProviderKit"]),
        .library(name: "ChorusInstallerUI", targets: ["ChorusInstallerUI"]),
        .library(name: "ChorusIntegrationKit", targets: ["ChorusIntegrationKit"]),
        .executable(name: "chorus-installer-preview", targets: ["ChorusInstallerPreview"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.8.0")
    ],
    targets: [
        .target(name: "ChorusProviderKit"),
        .target(name: "ChorusInstallerUI", dependencies: ["ChorusProviderKit"]),
        .target(
            name: "ChorusIntegrationKit",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")]
        ),
        .executableTarget(name: "ChorusInstallerPreview", dependencies: ["ChorusInstallerUI"]),
        .testTarget(name: "ChorusProviderKitTests", dependencies: ["ChorusProviderKit"]),
        .testTarget(name: "ChorusIntegrationKitTests", dependencies: ["ChorusIntegrationKit"])
    ]
)
