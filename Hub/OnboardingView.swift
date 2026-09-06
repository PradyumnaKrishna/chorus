import SwiftUI

extension Notification.Name {
    static let chorusShowOnboarding = Notification.Name("in.onpy.Chorus.showOnboarding")
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    private let titles = ["Make room to listen", "Keep your place", "Hear when it's done"]
    private let symbols = ["waveform", "pip", "terminal"]
    private let descriptions = [
        "Paste text and choose a voice. Use the voices already on your Mac, or add Chorus Kokoro from Voice apps.",
        "The floating player keeps controls close. Choose Compact, Full, or Disabled in Settings, and hide it without stopping your reading.",
        "Connect Claude Code or Codex to hear completed answers. Manual setup is available in Integrations whenever you're ready."
    ]

    init(initialStep: Int = 0) {
        _step = State(initialValue: min(2, max(0, initialStep)))
    }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button("Skip") { dismiss() }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if step == 0 { BrandIcon().frame(width: 80, height: 80) }
            else {
                Image(systemName: symbols[step]).font(.system(size: 46, weight: .light)).foregroundStyle(.orange)
                    .frame(height: 80)
            }
            VStack(spacing: 12) {
                Text(titles[step]).font(.system(size: 25, weight: .semibold, design: .rounded))
                Text(descriptions[step]).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 370)
            }
            Spacer(minLength: 0)
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Button(step == 2 ? "Start reading" : "Continue") {
                    if step == 2 { dismiss() } else { step += 1 }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.overlay {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in Circle().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25)).frame(width: 6, height: 6) }
                }.accessibilityLabel("Step \(step + 1) of 3").allowsHitTesting(false)
            }
        }.padding(28).frame(width: 490, height: 380)
    }
}
