import SwiftUI
import ChorusIntegrationKit

struct IntegrationSetupView: View {
    let source: Harness
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Connect \(source.title)").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("1. Keep Chorus in its permanent location.\n2. Merge the configuration below into your settings.\n3. Restart your harness and enable listening in Chorus.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(source == .claude ? "~/.claude/settings.json" : "~/.codex/config.toml")
                .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            ScrollView([.vertical, .horizontal]) {
                Text(CompletionInbox.configuration(for: source))
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(14)
            }.frame(height: 215).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            Text(source == .claude ? "Preserve existing hooks. This adds an asynchronous Stop hook that sends only the final answer." : "Place notify at the top level. If you already have a notify command, call Chorus from your existing wrapper instead of replacing it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("CLI sessions only").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy configuration") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CompletionInbox.configuration(for: source), forType: .string)
                    copied = true
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 550)
    }
}
