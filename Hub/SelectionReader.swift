import AppKit
import ApplicationServices

/// Opt-in selected-text reading. Never copies the clipboard or requests full document contents.
@MainActor
final class SelectionReader: ObservableObject {
    @Published var enabled: Bool {
        didSet {
            generation += 1
            gate = SelectionGate()
            configure()
            if enabled && player != nil && !permissionGranted { requestPermission() }
        }
    }
    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    private weak var player: SpeechPlayer?
    private weak var inbox: CompletionInbox?
    private var timer: Timer?
    private var querying = false
    private var generation = 0
    private var gate = SelectionGate()
    private var preparedPID: pid_t?

    init(defaults: UserDefaults = .standard) {
        // Selection mode belongs to the visible player and never resumes invisibly at launch.
        enabled = false
        defaults.removeObject(forKey: "readSelection")
    }

    func connect(player: SpeechPlayer, inbox: CompletionInbox) {
        self.player = player
        self.inbox = inbox
        configure()
    }

    func requestPermission() {
        // The SDK exports this immutable key as a mutable C global, which cannot cross actor boundaries.
        permissionGranted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private func configure() {
        timer?.invalidate()
        timer = nil
        preparedPID = nil
        guard enabled, player != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    private func poll() async {
        guard enabled, !querying else { return }
        let trusted = AXIsProcessTrusted()
        if permissionGranted != trusted { permissionGranted = trusted }
        guard permissionGranted, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            gate = SelectionGate(); return
        }
        querying = true
        defer { querying = false }
        let requestGeneration = generation
        let snapshot: SelectionGate.Snapshot?
        if pid == ProcessInfo.processInfo.processIdentifier {
            // Playback highlighting uses background attributes, so real selections remain distinct.
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
               editor.selectedRange().length > 0,
               let range = Range(editor.selectedRange(), in: editor.string) {
                snapshot = .init(source: "local-selection", text: String(editor.string[range]))
            } else { snapshot = nil }
        } else {
            let prepare = preparedPID != pid
            preparedPID = pid
            snapshot = await Task.detached(priority: .utility) {
                AccessibilitySelection.read(pid: pid, prepare: prepare)
            }.value
        }
        guard enabled, AXIsProcessTrusted(), generation == requestGeneration,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { gate = SelectionGate(); return }
        let interacting = NSEvent.pressedMouseButtons != 0 || NSEvent.modifierFlags.contains(.shift)
        if let text = gate.observe(snapshot, at: ProcessInfo.processInfo.systemUptime, interacting: interacting) {
            if player?.speak(text) == true { inbox?.clear() }
        }
    }

    isolated deinit { timer?.invalidate() }
}
