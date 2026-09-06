import AppKit
import Foundation

/// Finds the separately installed provider; model storage and repair belong to that app.
@MainActor
final class CompanionApp: ObservableObject {
    static let bundleIdentifier = "in.onpy.Chorus.Kokoro"
    static let fileName = "Chorus Kokoro.app"
    @Published private(set) var installedURL: URL?
    @Published private(set) var busy = false
    @Published private(set) var message: String?

    init() { refresh() }

    func refresh() {
        let manager = FileManager.default
        let candidates = [
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/\(Self.fileName)"),
            URL(fileURLWithPath: "/Applications/\(Self.fileName)")
        ] + [NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier)].compactMap { $0 }
        installedURL = candidates.first {
            !$0.pathComponents.contains(".Trash") && Bundle(url: $0)?.bundleIdentifier == Self.bundleIdentifier
                && manager.fileExists(atPath: $0.appendingPathComponent("Contents/PlugIns/KokoroSynthesizer.appex").path)
        }
    }

    func open() async {
        guard !busy else { return }
        refresh()
        guard let installedURL else { return }
        busy = true
        message = nil
        defer { busy = false }
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: installedURL, configuration: configuration)
        } catch { message = error.localizedDescription }
    }
}
