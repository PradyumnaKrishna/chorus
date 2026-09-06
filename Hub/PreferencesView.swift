import SwiftUI

extension Notification.Name {
    static let chorusShowSettings = Notification.Name("chorusShowSettings")
}

struct PreferencesView: View {
    @ObservedObject var overlay: PlaybackOverlay

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Text("Settings").font(.system(size: 22, weight: .semibold))
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Player style").font(.callout.weight(.medium))
                    Spacer(minLength: 12)
                    Picker("Player style", selection: $overlay.style) {
                        ForEach(PlaybackOverlay.Style.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 244)
                }
                Text(overlay.style == .compact ? "Pause, stop, and hide. No captions." : overlay.style == .full ? "Text preview for macOS voices. Chorus neural voices always use Compact." : "Read aloud without a floating window.")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                HStack {
                    Text("Auto hide")
                    Spacer()
                    Toggle("Auto hide", isOn: $overlay.autoHide).labelsHidden()
                        .toggleStyle(.switch).controlSize(.small).disabled(overlay.style == .disabled)
                }
                Text("Hide when reading ends, except while selection reading is on. Hiding the player turns selection reading off and keeps audio playing.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Text("Global player shortcut")
                    Spacer()
                    Toggle("Global player shortcut", isOn: $overlay.shortcutEnabled).labelsHidden()
                        .toggleStyle(.switch).controlSize(.small).disabled(overlay.style == .disabled)
                }
                Text(overlay.shortcutUnavailable ? "Shortcut unavailable. Another app may be using it. Use the Chorus menu to show the player." : "⌃⌥⌘P shows or hides the player from any app.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(16).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 8) {
                Text("Word highlighting").font(.callout.weight(.medium))
                Text("macOS voices follow the spoken word. Chorus neural voices play continuously using the Compact player until reliable timing is available.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
            Spacer(minLength: 0)
            Button("Show onboarding…") { NotificationCenter.default.post(name: .chorusShowOnboarding, object: nil) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18) }
        .scrollBounceBehavior(.basedOnSize)
    }
}
