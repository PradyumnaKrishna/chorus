import AppKit
import Carbon
import Combine
import SwiftUI

/// A nonactivating panel keeps playback controls available without taking focus from the user's work.
@MainActor
final class PlaybackOverlay: ObservableObject {
    enum Style: String, CaseIterable, Identifiable {
        case compact = "Compact", full = "Full", disabled = "Disabled"
        var id: Self { self }
    }

    @Published var style: Style {
        didSet {
            defaults.set(style.rawValue, forKey: "playerStyle")
            if style == .disabled { hide() } else { resize() }
            configureShortcut()
        }
    }
    @Published var autoHide: Bool {
        didSet {
            defaults.set(autoHide, forKey: "playerAutoHide")
            if autoHide && player?.state == .idle && selectionReader?.enabled != true { hide() }
        }
    }
    @Published var shortcutEnabled: Bool {
        didSet {
            defaults.set(shortcutEnabled, forKey: "playerShortcutEnabled")
            configureShortcut()
        }
    }
    @Published private(set) var shortcutUnavailable = false
    @Published private(set) var isVisible = false
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var subscription: AnyCancellable?
    private var voiceSubscription: AnyCancellable?
    private weak var player: SpeechPlayer?
    private var selectionReader: SelectionReader?
    private var playbackState = SpeechPlayer.State.idle
    private var escapeMonitor: Any?
    private var shortcut: PlayerShortcut?
    private var stopShortcut: PlayerShortcut?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: "playerStyle"), let style = Style(rawValue: stored) {
            self.style = style
        } else {
            self.style = defaults.object(forKey: "automaticOverlay") as? Bool == false ? .disabled
                : defaults.bool(forKey: "overlayCaptions") ? .full : .compact
        }
        shortcutEnabled = defaults.object(forKey: "playerShortcutEnabled") as? Bool ?? true
        autoHide = defaults.object(forKey: "playerAutoHide") as? Bool ?? true
    }

    func connect(player: SpeechPlayer, inbox: CompletionInbox, selectionReader: SelectionReader) {
        guard subscription == nil else { return }
        self.player = player
        self.selectionReader = selectionReader
        voiceSubscription = player.$selection.receive(on: RunLoop.main).sink { [weak self] _ in self?.resize() }
        shortcut = PlayerShortcut(keyCode: UInt32(kVK_ANSI_P),
                                  modifiers: UInt32(cmdKey | optionKey | controlKey), id: 1) { [weak self, weak player, weak inbox] in
            guard let self, let player, let inbox else { return }
            self.toggle(player: player, inbox: inbox)
        }
        stopShortcut = PlayerShortcut(keyCode: UInt32(kVK_ANSI_Period), modifiers: UInt32(cmdKey), id: 2) { [weak player, weak inbox] in
            inbox?.clear()
            player?.stop()
        }
        configureShortcut()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.isVisible == true { self?.hide(); return nil }
            return event
        }
        subscription = player.$state.removeDuplicates().sink { [weak self, weak player, weak inbox] state in
            guard let self, let player, let inbox else { return }
            let began = self.playbackState == .idle && state != .idle
            // @Published emits before player.state changes; retain the incoming state.
            self.playbackState = state
            self.configureShortcut()
            if state == .idle {
                if self.autoHide && self.selectionReader?.enabled != true { self.hide() }
            } else if began {
                self.show(player: player, inbox: inbox)
            }
        }
    }

    private func configureShortcut() {
        guard let shortcut, let stopShortcut else { return }
        shortcutUnavailable = false
        if shortcutEnabled {
            let playerRegistered = style == .disabled || shortcut.register()
            if style == .disabled { shortcut.unregister() }
            let stopRegistered: Bool
            if playbackState == .idle {
                stopShortcut.unregister()
                stopRegistered = true
            } else {
                stopRegistered = stopShortcut.register()
            }
            shortcutUnavailable = !playerRegistered || !stopRegistered
        } else {
            shortcut.unregister()
            stopShortcut.unregister()
        }
    }

    isolated deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    /// Dismissing never stops speech, and pause/resume must not reopen a dismissed player.
    func hide() {
        selectionReader?.enabled = false
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle(player: SpeechPlayer, inbox: CompletionInbox) {
        if isVisible { hide() } else { show(player: player, inbox: inbox) }
    }

    private var updateContent: (() -> Void)?

    var effectiveStyle: Style {
        guard style != .disabled, let player else { return style }
        let capabilities = player.state == .idle ? player.selectedCapabilities : player.playbackCapabilities
        return capabilities.fullPlayer ? style : .compact
    }

    private func resize() {
        guard let panel else { return }
        let size = effectiveStyle == .full ? NSSize(width: 340, height: 100) : NSSize(width: 176, height: 44)
        let center = panel.frame.midX
        panel.setFrame(NSRect(x: center - size.width / 2, y: panel.frame.minY,
                              width: size.width, height: size.height), display: true)
        updateContent?()
    }

    func show(player: SpeechPlayer, inbox: CompletionInbox) {
        guard style != .disabled else { return }
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isMovableByWindowBackground = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            self.panel = panel
        }
        guard let panel else { return }
        updateContent = { [weak self, weak player, weak inbox] in
            guard let self, let player, let inbox, let selectionReader = self.selectionReader else { return }
            self.panel?.contentView = NSHostingView(rootView: PlaybackOverlayView(player: player, inbox: inbox, selectionReader: selectionReader, captions: self.effectiveStyle == .full) { [weak self] in
                self?.hide()
            })
        }
        resize()
        if !panel.isVisible {
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
            if let bounds = screen?.visibleFrame {
                panel.setFrameOrigin(NSPoint(x: bounds.midX - panel.frame.width / 2, y: bounds.minY + 28))
            }
        }
        panel.orderFrontRegardless()
        isVisible = true
    }
}

struct PlaybackOverlayView: View {
    @ObservedObject var player: SpeechPlayer
    @ObservedObject var inbox: CompletionInbox
    @ObservedObject var selectionReader: SelectionReader
    var captions = false
    var dismiss: () -> Void

    private var canReplay: Bool {
        !player.voices.isEmpty && !(player.spokenText.isEmpty ? UserDefaults.standard.string(forKey: "readerText") ?? "" : player.spokenText)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if captions {
                    Image(systemName: "waveform").foregroundStyle(.orange)
                    Text(player.state == .speaking ? "Reading" : player.state == .paused ? "Paused" : "Chorus")
                        .font(.caption.weight(.semibold))
                    Spacer()
                }
                Button {
                    if player.state == .idle {
                        player.speak(player.spokenText.isEmpty ? UserDefaults.standard.string(forKey: "readerText") ?? "" : player.spokenText)
                    } else { player.togglePause() }
                } label: {
                    Image(systemName: player.state == .speaking ? "pause.fill" : "play.fill").frame(width: 28, height: 28)
                }
                .help(player.state == .speaking ? "Pause" : player.state == .paused ? "Resume" : "Read again")
                .accessibilityLabel(player.state == .speaking ? "Pause" : "Play")
                .disabled(player.state == .idle && !canReplay)
                Button { inbox.clear(); player.stop() } label: { Image(systemName: "stop.fill").frame(width: 28, height: 28) }
                    .help("Stop and clear queue").accessibilityLabel("Stop")
                    .disabled(player.state == .idle && inbox.pending.isEmpty)
                Toggle(isOn: $selectionReader.enabled) {
                    Image(systemName: "character.cursor.ibeam").frame(width: 28, height: 28)
                }
                .toggleStyle(.button).buttonStyle(.borderless)
                .foregroundStyle(selectionReader.enabled ? Color.accentColor : Color.primary)
                .background(selectionReader.enabled ? Color.accentColor.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .help(selectionReader.enabled ? "Turn off selection reading" : "Read selected text in other apps")
                .accessibilityLabel("Read selected text")
                Divider().frame(height: 16)
                Button(action: dismiss) { Image(systemName: "xmark").frame(width: 24, height: 28) }
                    .help("Hide player · reading continues").accessibilityLabel("Hide player")
            }.buttonStyle(.borderless)
            if captions {
                HighlightedExcerpt(text: player.spokenText, range: player.wordRange)
                    .font(.system(size: 14)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(captions ? 12 : 6)
        .frame(width: captions ? 340 : 176, height: captions ? 100 : 44)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: captions ? 18 : 24))
        .overlay(RoundedRectangle(cornerRadius: captions ? 18 : 24).stroke(.white.opacity(0.15)))
        .contextMenu { Button("Hide mini player", action: dismiss) }
    }
}

struct HighlightedExcerpt: View {
    let text: String
    let range: NSRange?

    var body: some View {
        if let word = SpeechHighlight.range(range, in: text) {
            let window = SpeechHighlight.excerpt(around: word, in: text)
            let before = String(text[window.lowerBound..<word.lowerBound])
            let after = String(text[word.upperBound..<window.upperBound].prefix(140))
            Text("\(Text(before).foregroundColor(.secondary))\(Text(String(text[word])).bold().foregroundColor(.orange))\(Text(after).foregroundColor(.secondary))")
        } else {
            Text(text.isEmpty ? "Start reading in Chorus. Text appears here." : String(text.prefix(110)))
                .foregroundStyle(.secondary)
        }
    }
}
