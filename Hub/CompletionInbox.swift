import Foundation
import ChorusIntegrationKit

@MainActor
final class CompletionInbox: ObservableObject {
    @Published private(set) var pending: [CompletionEvent] = []
    @Published private(set) var latest: CompletionEvent?
    @Published var status = "Waiting for a completed response"
    @Published var claudeEnabled = UserDefaults.standard.bool(forKey: "claudeEnabled") {
        didSet { UserDefaults.standard.set(claudeEnabled, forKey: "claudeEnabled"); discardDisabled() }
    }
    @Published var codexEnabled = UserDefaults.standard.bool(forKey: "codexEnabled") {
        didSet { UserDefaults.standard.set(codexEnabled, forKey: "codexEnabled"); discardDisabled() }
    }
    private var timer: Timer?

    func start(player: SpeechPlayer) {
        guard timer == nil else { return }
        poll(player: player)
        // Owned by the app's inbox, so closing the reader window does not stop delivery.
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak player] _ in
            Task { @MainActor in
                guard let self, let player else { return }
                self.poll(player: player)
            }
        }
    }

    private var seen = UserDefaults.standard.stringArray(forKey: "completionIDs") ?? []

    func enabled(_ source: Harness) -> Bool { source == .claude ? claudeEnabled : codexEnabled }
    private func discardDisabled() { pending.removeAll { !enabled($0.source) } }
    func clear() { pending.removeAll(); status = "Queue cleared" }

    func poll(player: SpeechPlayer) {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: CompletionEvent.inbox, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let files = try manager.contentsOfDirectory(at: CompletionEvent.inbox,
                                                        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
            var received: [CompletionEvent] = []
            for file in files where file.pathExtension == "json" {
                // Files are transient deliveries, removed even when disabled, stale, or invalid.
                defer { try? manager.removeItem(at: file) }
                let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 400_000,
                      let event = try? JSONDecoder().decode(CompletionEvent.self, from: Data(contentsOf: file)),
                      event.id.count == 64, !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      event.text.utf8.count <= CompletionEvent.maximumBytes,
                      abs(event.createdAt.timeIntervalSinceNow) < 300,
                      !seen.contains(event.id) else { continue }
                seen.append(event.id)
                if enabled(event.source) { received.append(event) }
            }
            seen = Array(seen.suffix(200))
            UserDefaults.standard.set(seen, forKey: "completionIDs")
            pending.append(contentsOf: received.sorted { $0.createdAt < $1.createdAt })
            if pending.count > 20 { pending.removeFirst(pending.count - 20); status = "Kept the 20 most recent responses" }
            guard player.state == .idle, !pending.isEmpty else { return }
            guard !player.voices.isEmpty else { status = "Refresh voices to read queued responses"; return }
            let event = pending[0]
            if player.speak(event.text) {
                pending.removeFirst()
                latest = event
                status = "Reading a response from \(event.source.title)"
            }
        } catch { status = "Could not read completions: \(error.localizedDescription)" }
    }

    static func configuration(for source: Harness) -> String {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/chorus-hook").path
        switch source {
        case .codex:
            // JSON basic strings are also valid TOML basic strings for filesystem paths.
            let quoted = String(data: try! JSONEncoder().encode(executable), encoding: .utf8)!
            return "notify = [\(quoted), \"codex\"]"
        case .claude:
            let command = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "' claude"
            let value: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": command, "async": true]]]]]]
            return String(data: try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), encoding: .utf8)!
        }
    }
}
