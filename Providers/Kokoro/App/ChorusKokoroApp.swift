import AppKit
import ChorusInstallerUI
import ChorusProviderKit
import Foundation

@main
struct ChorusKokoroApp {
    @MainActor
    static func main() {
        do {
            InstallerApplication.run(descriptor: try ProviderDescriptor.load())
        } catch {
            reportUnrecoverable(error)
        }
    }

    /// A malformed or missing manifest is a packaging fault the user cannot act on,
    /// but trapping on it shows them a crash report rather than an explanation.
    /// The descriptor errors already carry user-facing copy, so surface that.
    @MainActor
    private static func reportUnrecoverable(_ error: Error) -> Never {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Chorus Kokoro can’t start."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        exit(EXIT_FAILURE)
    }
}
