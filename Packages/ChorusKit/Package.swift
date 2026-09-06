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
        .executable(name: "chorus-installer-preview", targets: ["ChorusInstallerPreview"])
    ],
    targets: [
        .target(name: "ChorusProviderKit"),
        .target(name: "ChorusInstallerUI", dependencies: ["ChorusProviderKit"]),
        .executableTarget(name: "ChorusInstallerPreview", dependencies: ["ChorusInstallerUI"]),
        .testTarget(name: "ChorusProviderKitTests", dependencies: ["ChorusProviderKit"])
    ]
)
