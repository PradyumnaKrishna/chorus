import AppKit
import AVFoundation
import SwiftUI

/// Render our own AppKit hosting hierarchy, including scroll views and text editors.
@main
struct RenderApp {
    @MainActor static func capture<Content: View>(_ content: Content, name: String, size: NSSize, scheme: ColorScheme = .light) throws {
        let view = NSHostingView(rootView: content.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.setFrame(NSRect(origin: .zero, size: size), display: false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No render surface") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
        try png.write(to: URL(fileURLWithPath: "build/Chorus/chorus-\(name).png"))
        print("Rendered \(name)")
    }

    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try capture(Image(nsImage: BrandIcon.menuImage), name: "menu-icon", size: NSSize(width: 44, height: 28))
        let suite = "in.onpy.Chorus.RenderTests"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "setupComplete")
        defer { defaults.removePersistentDomain(forName: suite) }
        for page in Page.allCases {
            let name = page == .reader ? "reader" : page == .models ? "models" : page == .settings ? "settings" : "integrations"
            let root = ChorusView(player: SpeechPlayer(), companion: CompanionApp(), inbox: CompletionInbox(), overlay: PlaybackOverlay(defaults: defaults), selectionReader: SelectionReader(defaults: defaults), initialPage: page)
                .defaultAppStorage(defaults).environment(\.colorScheme, .light)
            try capture(root, name: name, size: NSSize(width: 740, height: 540))
        }
        for page in [Page.reader, .settings] {
            let root = ChorusView(player: SpeechPlayer(), companion: CompanionApp(), inbox: CompletionInbox(),
                                  overlay: PlaybackOverlay(defaults: defaults), selectionReader: SelectionReader(defaults: defaults), initialPage: page).defaultAppStorage(defaults)
            try capture(root, name: page == .reader ? "reader-small-dark" : "settings-small-dark",
                        size: NSSize(width: 700, height: 500), scheme: .dark)
        }
        for step in 0..<3 {
            try capture(OnboardingView(initialStep: step), name: step == 0 ? "onboarding" : "onboarding-\(step + 1)", size: NSSize(width: 490, height: 380))
        }
        try capture(IntegrationSetupView(source: .claude, error: nil), name: "configuration", size: NSSize(width: 550, height: 520))
        let overlays = VStack(spacing: 20) {
            PlaybackOverlayView(player: SpeechPlayer(), inbox: CompletionInbox(), selectionReader: SelectionReader(defaults: defaults), dismiss: {})
            PlaybackOverlayView(player: SpeechPlayer(), inbox: CompletionInbox(), selectionReader: SelectionReader(defaults: defaults), captions: true, dismiss: {})
            HighlightedExcerpt(text: "Chorus keeps the spoken word in view while you work.", range: NSRange(location: 17, length: 6))
                .padding().frame(width: 360).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }.padding(24).environment(\.colorScheme, .dark)
        try capture(overlays, name: "overlay", size: NSSize(width: 410, height: 300))
    }
}
