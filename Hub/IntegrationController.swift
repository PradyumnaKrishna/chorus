import Foundation
import ChorusIntegrationKit

@MainActor
final class IntegrationController: ObservableObject {
    struct ManualSetup: Identifiable {
        let source: Harness
        let error: String?
        var id: Harness { source }
    }

    @Published private(set) var configured: Set<Harness> = []
    @Published var setupRequest: Harness?
    @Published var manualSetup: ManualSetup?

    static var hookExecutable: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/chorus-hook")
    }

    private let inbox: CompletionInbox

    init(inbox: CompletionInbox) {
        self.inbox = inbox
    }

    func isListening(to source: Harness) -> Bool {
        inbox.enabled(source)
    }

    func request(_ enabled: Bool, for source: Harness) {
        if enabled, !configured.contains(source) {
            setupRequest = source
        } else if enabled {
            setListening(true, for: source)
        } else {
            setListening(false, for: source)
            inbox.status = "\(source.title) reading paused"
        }
    }

    func confirmSetup(for source: Harness) {
        setupRequest = nil
        do {
            try configuration(for: source).install()
            configured.insert(source)
            setListening(true, for: source)
            if source == .codex {
                inbox.status = "Codex configured. Restart it, then approve the new Chorus hook in /hooks."
            } else {
                inbox.status = "Claude Code configured. Restart it, then approve the new Chorus hook when prompted."
            }
        } catch {
            setListening(false, for: source)
            manualSetup = ManualSetup(source: source, error: error.localizedDescription)
        }
    }

    func showManualSetup(for source: Harness) {
        manualSetup = ManualSetup(source: source, error: nil)
    }

    func refresh() {
        configured = Set(Harness.allCases.filter { source in
            (try? configuration(for: source).isInstalled()) == true
        })
    }

    private func configuration(for source: Harness) -> IntegrationConfiguration {
        IntegrationConfiguration(source: source, executable: Self.hookExecutable)
    }

    private func setListening(_ enabled: Bool, for source: Harness) {
        if source == .claude { inbox.claudeEnabled = enabled } else { inbox.codexEnabled = enabled }
    }
}
