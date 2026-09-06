import AppKit
import ChorusInstallerUI
import ChorusProviderKit
import Foundation
import SwiftUI

@main
struct ChorusInstallerPreview {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else { throw PreviewError.usage }

        NSApplication.shared.setActivationPolicy(.prohibited)
        let descriptor = try ProviderDescriptor.load(from: URL(fileURLWithPath: arguments[1]))
        // Register both marks under the names the view looks up, so the dark
        // render is not silently missing its logo.
        let lightMark = URL(fileURLWithPath: arguments[2])
        let darkMark = lightMark
            .deletingLastPathComponent()
            .appendingPathComponent(lightMark.deletingPathExtension().lastPathComponent + "Dark")
            .appendingPathExtension(lightMark.pathExtension)
        for (url, name) in [(lightMark, "ChorusSoundwave"), (darkMark, "ChorusSoundwaveDark")] {
            if let mark = NSImage(contentsOf: url) {
                mark.setName(NSImage.Name(name))
            }
        }
        let outputDirectory = URL(fileURLWithPath: arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let previewStore = ArtifactStore(
            rootDirectory: FileManager.default.temporaryDirectory,
            artifacts: descriptor.artifacts
        )
        // Both appearances, because a light-only render cannot show whether the
        // dark palette actually resolves.
        let states: [(name: String, status: InstallerController.InstallationStatus)] = [
            ("installer", .notInstalled),
            ("maintenance", .installed)
        ]
        let appearances: [(name: String, appearance: NSAppearance.Name)] = [
            ("light", .aqua),
            ("dark", .darkAqua)
        ]

        for state in states {
            for variant in appearances {
                try capture(
                    InstallerView(controller: InstallerController(
                        descriptor: descriptor,
                        initialStatus: state.status,
                        store: previewStore
                    )),
                    appearance: variant.appearance,
                    at: outputDirectory.appendingPathComponent("\(state.name)-\(variant.name).png")
                )
            }
        }
    }

    @MainActor
    private static func capture<Content: View>(
        _ content: Content,
        appearance name: NSAppearance.Name,
        at url: URL
    ) throws {
        let size = NSSize(width: 560, height: 440)
        let view = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let appearance = NSAppearance(named: name)
        window.appearance = appearance
        view.appearance = appearance
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        window.setFrame(NSRect(origin: .zero, size: size), display: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        view.layoutSubtreeIfNeeded()

        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw PreviewError.noSurface
        }
        // Dynamic colors resolve against the *drawing* appearance, which is not
        // set by assigning one to the view, so make it current for the capture.
        appearance?.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw PreviewError.noImage
        }
        try png.write(to: url)
    }

    private enum PreviewError: LocalizedError {
        case usage
        case noSurface
        case noImage

        var errorDescription: String? {
            switch self {
            case .usage:
                return "Usage: chorus-installer-preview <Provider.json> <brand-mark.png> <output-directory>"
            case .noSurface:
                return "The installer preview did not create a render surface."
            case .noImage:
                return "The installer preview could not encode a PNG."
            }
        }
    }
}
