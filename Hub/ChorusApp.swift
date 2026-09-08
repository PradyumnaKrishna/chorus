import SwiftUI
import ChorusIntegrationKit

#if !CHORUS_SNAPSHOT
@main
struct ChorusApp: App {
    @NSApplicationDelegateAdaptor(ChorusAppDelegate.self) private var appDelegate
    @StateObject private var player = SpeechPlayer()
    @StateObject private var companion = CompanionApp()
    @StateObject private var inbox = CompletionInbox()
    @StateObject private var overlay = PlaybackOverlay()
    @StateObject private var selectionReader = SelectionReader()

    var body: some Scene {
        Window("Chorus", id: "main") {
            ChorusView(player: player, companion: companion, inbox: inbox, overlay: overlay, selectionReader: selectionReader)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear { inbox.start(player: player); overlay.connect(player: player, inbox: inbox, selectionReader: selectionReader); selectionReader.connect(player: player, inbox: inbox) }

        }
        .defaultSize(width: 740, height: 540)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { NotificationCenter.default.post(name: .chorusShowSettings, object: nil) }
                    .keyboardShortcut(",")
            }
            CommandGroup(after: .appInfo) {
                Button("Show onboarding…") { NotificationCenter.default.post(name: .chorusShowOnboarding, object: nil) }
            }
        }
        MenuBarExtra {
            MenuControls(player: player, inbox: inbox, overlay: overlay)
        } label: {
            Image(nsImage: BrandIcon.menuImage)
                .accessibilityLabel("Chorus")
        }
    }
}

#endif

private final class ChorusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep playback and the menu-bar controls running without a Dock icon.
        sender.setActivationPolicy(.accessory)
        return false
    }
}

private struct MenuControls: View {
    @ObservedObject var player: SpeechPlayer
    @ObservedObject var inbox: CompletionInbox
    @ObservedObject var overlay: PlaybackOverlay
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Open Chorus") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }.keyboardShortcut("0")
        Button(overlay.isVisible ? "Hide player" : "Show player") { overlay.toggle(player: player, inbox: inbox) }
            .disabled(overlay.style == .disabled)
            .keyboardShortcut("p", modifiers: [.control, .option, .command])
        Menu("Player style") {
            ForEach(PlaybackOverlay.Style.allCases) { style in
                Toggle(style.rawValue, isOn: Binding(get: { overlay.style == style }, set: { selected in
                    if selected { overlay.style = style }
                }))
                .keyboardShortcut(style == .compact ? "1" : style == .full ? "2" : "0", modifiers: [.command, .option])
            }
            Divider()
            Toggle("Auto hide", isOn: $overlay.autoHide).disabled(overlay.style == .disabled)
                .keyboardShortcut("h", modifiers: [.command, .shift])
        }
        Button("Settings…") {
            NSApp.setActivationPolicy(.regular)
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .chorusShowSettings, object: nil)
        }.keyboardShortcut(",")
        Divider()
        Button(player.state == .paused ? "Resume" : "Pause", action: player.togglePause)
            .disabled(player.state == .idle).keyboardShortcut(.space, modifiers: [.command, .shift])
        Button("Stop and clear queue") { inbox.clear(); player.stop() }.keyboardShortcut(".")
        Divider()
        Button("Quit Chorus") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

enum Page: String, CaseIterable, Identifiable {
    case reader = "Text to speech", models = "Voice apps", integrations = "Integrations", settings = "Settings"
    var id: Self { self }
    var icon: String {
        switch self { case .reader: return "text.alignleft"; case .models: return "waveform"; case .integrations: return "terminal"; case .settings: return "gearshape" }
    }
}

struct ChorusView: View {
    @ObservedObject var player: SpeechPlayer
    @ObservedObject var companion: CompanionApp
    @ObservedObject var inbox: CompletionInbox
    @ObservedObject var overlay: PlaybackOverlay
    @ObservedObject var selectionReader: SelectionReader
    @StateObject private var integrationController: IntegrationController
    @State private var page: Page = .reader
    @AppStorage("setupComplete") private var setupComplete = false
    @State private var showOnboarding = false
    @AppStorage("readerText") private var text = "Welcome to Chorus. Give your words a voice.\n\nPaste something you want to listen to, choose a voice, and press play. Everything is spoken right here on your Mac."

    init(player: SpeechPlayer, companion: CompanionApp, inbox: CompletionInbox,
         overlay: PlaybackOverlay, selectionReader: SelectionReader, initialPage: Page = .reader) {
        self.player = player
        self.companion = companion
        self.inbox = inbox
        self.overlay = overlay
        self.selectionReader = selectionReader
        _integrationController = StateObject(wrappedValue: IntegrationController(inbox: inbox))
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Page.allCases.filter { $0 != .settings }) { item in
                            Button { page = item } label: {
                                Label(item.rawValue, systemImage: item.icon)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .background(page == item ? Color.accentColor.opacity(0.12) : .clear,
                                                in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 10).padding(.top, 12)
                    Spacer()
                    Button { page = .settings } label: {
                        Label("Settings", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                            .background(page == .settings ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                        .frame(height: 40).padding(.horizontal, 10).padding(.vertical, 4)
                    Divider()
                    HStack(spacing: 7) {
                        BrandIcon().frame(width: 24, height: 24)
                        Text("Chorus").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 18).frame(height: 40).padding(.vertical, 4)
                }
                    .frame(width: 158).frame(maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                Divider()
            VStack(alignment: .leading, spacing: 16) {
                switch page {
                case .reader: reader
                case .models:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) { models }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                case .integrations: integrations
                case .settings: PreferencesView(overlay: overlay)
                }
            }
            .padding(page == .models || page == .settings ? 0 : 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor))
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { setupComplete = true }) {
            OnboardingView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chorusShowSettings)) { _ in page = .settings }
        .onReceive(NotificationCenter.default.publisher(for: .chorusShowOnboarding)) { _ in showOnboarding = true }
        .sheet(item: $integrationController.manualSetup) { setup in
            IntegrationSetupView(source: setup.source, error: setup.error)
        }
        .alert("Setup required", isPresented: Binding(
            get: { integrationController.setupRequest != nil },
            set: { if !$0 { integrationController.setupRequest = nil } }
        ), presenting: integrationController.setupRequest) { source in
            Button("Set Up") { integrationController.confirmSetup(for: source) }
            Button("Cancel", role: .cancel) {}
        } message: { source in
            Text("Chorus needs to add its response hook to \(source.title). Existing settings and hooks will be preserved.")
        }
        .tint(.accentColor)
        .onAppear {
            player.refresh()
            integrationController.refresh()
            if !setupComplete { showOnboarding = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            player.refresh(); companion.refresh(); integrationController.refresh()
        }
    }

    private func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 22, weight: .semibold))
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private var reader: some View {
        Group {
            HStack {
                Text("Reader").font(.system(size: 22, weight: .semibold))
                Spacer()
                Button { overlay.toggle(player: player, inbox: inbox) } label: {
                    Image(systemName: "pip")
                }.buttonStyle(.borderless).help(overlay.isVisible ? "Hide player" : "Show player")
                    .accessibilityLabel("Toggle floating player").disabled(overlay.style == .disabled)
            }
            if player.voices.isEmpty {
                HStack {
                    Label("Refresh voices to start listening", systemImage: "arrow.down.circle")
                    Spacer()
                    Button("Set up Chorus voices") { page = .models }
                }.padding().background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 10) {
                Text("Voice").foregroundStyle(.secondary)
                Picker("Voice", selection: $player.selection) {
                    if player.voices.isEmpty { Text("No voices installed").tag("") }
                    ForEach(player.voices, id: \.identifier) { voice in
                        Text(player.voiceLabel(voice)).tag(voice.identifier)
                    }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).disabled(player.state != .idle)
                Button { player.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh voices")
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(player.state == .idle ? "YOUR TEXT" : "NOW READING").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if player.state == .idle {
                        Button("Paste", systemImage: "doc.on.clipboard") {
                            if let pasted = NSPasteboard.general.string(forType: .string) { text = pasted }
                        }.buttonStyle(.borderless)
                    }
                }.padding(.horizontal, 14).padding(.vertical, 10)
                Divider()
                if player.state == .idle || selectionReader.enabled {
                    TextEditor(text: $text).font(.system(size: 16)).scrollContentBackground(.hidden).padding(12)
                        .frame(minHeight: 80, idealHeight: 140, maxHeight: .infinity)
                } else {
                    SpokenTextView(text: player.spokenText, range: player.wordRange)
                }
                Divider()
                HStack {
                    Text("\((player.state == .idle ? text : player.spokenText).split(whereSeparator: \.isWhitespace).count) words")
                    Spacer()
                    Text(player.state == .paused ? "Paused" : player.state == .speaking ? (player.wordRange != nil ? "Following words" : "Reading") : "Ready")
                }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.vertical, 9)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
            HStack(spacing: 14) {
                Button {
                    if player.state == .idle { player.speak(text) } else { player.togglePause() }
                } label: {
                    Label(player.state == .speaking ? "Pause" : player.state == .paused ? "Resume" : "Read aloud",
                          systemImage: player.state == .speaking ? "pause.fill" : "play.fill").frame(minWidth: 88)
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command)
                    .disabled(player.voices.isEmpty || (player.state == .idle && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                Button { inbox.clear(); player.stop() } label: { Image(systemName: "stop.fill") }
                    .controlSize(.regular).help("Stop and clear queued responses").disabled(player.state == .idle && inbox.pending.isEmpty)
                Spacer()
                Text("Speed").foregroundStyle(.secondary)
                Slider(value: $player.rate, in: 0.35...0.65).frame(width: 76).accessibilityLabel("Speech rate").disabled(player.state != .idle).help("Set the speed before starting a reading")
                Text(String(format: "%.1f×", player.rate / 0.5)).monospacedDigit().frame(width: 40)
            }
            if let error = player.error { Text(error).foregroundStyle(.red).font(.callout) }
            if !inbox.pending.isEmpty { Text("\(inbox.pending.count) responses queued").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var models: some View {
        Group {
            heading("Choose how Chorus sounds", "Use macOS voices or add a companion voice app.")
            HStack {
                Label("macOS voices", systemImage: "speaker.wave.2")
                Spacer()
                Text(player.refreshing ? "Finding voices…" : "\(player.appleVoiceCount) available").foregroundStyle(.secondary)
            }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    BrandIcon().frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chorus Kokoro").font(.headline)
                        Text("41 voices · 7 languages").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Divider()
                if let url = companion.installedURL {
                    HStack {
                        if player.kokoroVoiceCount > 0 {
                            Label("\(player.kokoroVoiceCount) voices available", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Setup required", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                        }
                        Spacer()
                        Button("Open Chorus Kokoro") {
                            Task { await companion.open() }
                        }.disabled(companion.busy).help(url.path)
                    }.font(.callout)
                } else {
                    Text("To add voices, place Chorus Kokoro.app in ~/Applications and open it to complete setup.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("Refresh voices", systemImage: "arrow.clockwise") { player.refresh(); companion.refresh() }
                Spacer()
                if !player.voices.isEmpty { Button("Start listening →") { page = .reader }.buttonStyle(.borderedProminent) }
            }
            if let message = companion.message { Text(message).font(.callout).foregroundStyle(.red) }
        }
    }

    private var integrations: some View {
        Group {
            heading("Integrations", "Read completed answers from your coding assistants.")
            ForEach(Harness.allCases) { source in
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(source.title, systemImage: "terminal").font(.headline)
                        Spacer()
                        Toggle("Read responses", isOn: integrationBinding(for: source))
                            .labelsHidden().toggleStyle(.switch).accessibilityLabel("Read \(source.title) responses")
                    }
                    HStack {
                        Label(integrationController.configured.contains(source) ? "Configured" : "Setup required",
                              systemImage: integrationController.configured.contains(source) ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(integrationController.configured.contains(source) ? .green : .secondary)
                        Spacer()
                        if !integrationController.configured.contains(source) {
                            Button("Manual setup…") { integrationController.showManualSetup(for: source) }
                                .buttonStyle(.link)
                        }
                    }
                }.padding(18).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Setup happens once. Turning an integration off pauses reading without changing its configuration.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Text(inbox.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Clear queue", action: inbox.clear)
            }
        }
    }

    private func integrationBinding(for source: Harness) -> Binding<Bool> {
        Binding(get: { integrationController.isListening(to: source) }) { enabled in
            integrationController.request(enabled, for: source)
        }
    }

}

/// Apply trusted UTF-16 ranges; a nil range displays the passage without guessed timing.
private struct SpokenTextView: NSViewRepresentable {
    let text: String
    let range: NSRange?
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let view = scroll.documentView as! NSTextView
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 18, height: 18)
        return scroll
    }
    final class Coordinator {
        var text: String?
        var highlighted: NSRange?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? NSTextView, let storage = view.textStorage else { return }
        let changedText = context.coordinator.text != text
        if changedText {
            storage.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.labelColor
            ]))
            context.coordinator.text = text
            context.coordinator.highlighted = nil
        }
        let spoken = SpeechHighlight.range(range, in: text)
        let validRange = spoken.map { NSRange($0, in: text) }
        guard changedText || context.coordinator.highlighted != validRange else { return }
        if let previous = context.coordinator.highlighted {
            storage.removeAttribute(.backgroundColor, range: previous)
        }
        if let spoken, let validRange {
            storage.addAttribute(.backgroundColor, value: NSColor.systemOrange.withAlphaComponent(0.3), range: validRange)
            // Show the whole paragraph where it fits, then the word itself, which is
            // what still has to be on screen when the paragraph is taller than the view.
            view.scrollRangeToVisible(NSRange(SpeechHighlight.paragraph(around: spoken, in: text), in: text))
            view.scrollRangeToVisible(validRange)
        }
        context.coordinator.highlighted = validRange
    }
}
