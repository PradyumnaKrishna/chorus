import SwiftUI
import ChorusIntegrationKit

struct IntegrationSetupView: View {
    let source: Harness
    let error: String?
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var configuration: IntegrationConfiguration {
        IntegrationConfiguration(source: source, executable: IntegrationController.hookExecutable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Manual setup for \(source.title)").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
            }
            Text("Merge this configuration into your existing settings, then restart your coding assistant and approve the new hook if prompted.")
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text((configuration.file.path as NSString).abbreviatingWithTildeInPath)
                .font(.system(.callout, design: .monospaced)).textSelection(.enabled)
            ScrollView([.vertical, .horizontal]) {
                Text(configuration.snippet)
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(14)
            }.frame(height: 215).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            Text(source == .codex
                 ? "Preserve existing hooks when merging. In Codex, open /hooks and approve the new Chorus hook before using it."
                 : "Preserve existing hooks when merging. In Claude Code, approve the new Chorus hook when prompted before using it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("CLI sessions only").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy configuration") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(configuration.snippet, forType: .string)
                    copied = true
                }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 550)
    }
}
