import AppKit
import AVFoundation
import ChorusProviderKit
import SwiftUI

public enum InstallerApplication {
    /// Runs the shared single-window installer for one provider product.
    @MainActor
    public static func run(descriptor: ProviderDescriptor) {
        let application = NSApplication.shared
        let delegate = InstallerApplicationDelegate(descriptor: descriptor)
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class InstallerApplicationDelegate: NSObject, NSApplicationDelegate {
    private let descriptor: ProviderDescriptor
    private let controller: InstallerController
    private var window: NSWindow?

    init(descriptor: ProviderDescriptor) {
        self.descriptor = descriptor
        controller = InstallerController(descriptor: descriptor)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.onInstallationChanged = {
            AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        }
        installApplicationMenu()

        let palette = InstallerPalette(descriptor: descriptor)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Chorus \(descriptor.displayName)"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = palette.backgroundColor
        window.contentView = NSHostingView(rootView: InstallerView(controller: controller))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.window = window

        AVSpeechSynthesisProviderVoice.updateSpeechVoices()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func installApplicationMenu() {
        let applicationName = "Chorus \(descriptor.displayName)"
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu(title: applicationName)

        let aboutItem = NSMenuItem(
            title: "About \(applicationName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        applicationMenu.addItem(aboutItem)
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit \(applicationName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = NSApp
        applicationMenu.addItem(quitItem)

        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)
        NSApp.mainMenu = mainMenu
    }
}

public struct InstallerView: View {
    @ObservedObject private var controller: InstallerController
    @Environment(\.colorScheme) private var colorScheme

    public init(controller: InstallerController) {
        self.controller = controller
    }

    public var body: some View {
        let palette = InstallerPalette(descriptor: controller.descriptor)
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                brandMark(palette: palette)
                    .padding(.bottom, 16)

                Text(title)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.ink)

                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 410)
                    .padding(.top, 8)

                phaseContent(palette: palette)
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 36)
            .padding(.bottom, 12)
        }
        .frame(width: 560, height: 440)
        .background(palette.background)
    }

    private var title: String {
        let name = controller.descriptor.displayName
        switch controller.phase {
        case .ready(.notInstalled): return "Install \(name)"
        case .ready(.outdated): return "Upgrade \(name)"
        case .ready(.installed): return "\(name) is installed"
        case .downloading(.repair, _), .verifying(.repair): return "Repairing \(name)"
        case .downloading(.upgrade, _), .verifying(.upgrade): return "Upgrading \(name)"
        case .downloading(_, _), .verifying(_): return "Installing \(name)"
        case .removing: return "Uninstalling \(name)"
        case .completed(.uninstall): return "\(name) uninstalled"
        case .completed: return "\(name) is ready"
        case .failed: return "Something went wrong"
        }
    }

    private var detail: String {
        switch controller.phase {
        case .ready(.notInstalled):
            return controller.descriptor.summary
        case .ready(.outdated):
            return "A newer model is available. Upgrading replaces the installed files and lets Chorus follow the spoken word while these voices read."
        case .ready(.installed):
            return "Repair the installed files with fresh verified copies, or remove this provider’s downloaded files from your Mac."
        case .downloading:
            return "The required files are downloading directly to this Mac. Nothing is sent from your computer."
        case .verifying:
            return "Checking every download before making it available to the provider."
        case .removing:
            return "Removing the downloaded files and refreshing the system voice list."
        case .completed(.uninstall):
            return "The downloaded files have been removed. You can reinstall them whenever you need them."
        case .completed:
            return "The verified files are installed and the provider is available to macOS."
        case .failed(_, let message):
            return message
        }
    }

    @ViewBuilder
    private func phaseContent(palette: InstallerPalette) -> some View {
        switch controller.phase {
        case .ready(.notInstalled):
            VStack(spacing: 30) {
                operationButton(
                    "Install",
                    systemImage: "arrow.down.circle",
                    color: .blue
                ) {
                    controller.perform(.install)
                }
                Label(downloadSize, systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(palette.ink.opacity(0.62))
            }

        case .ready(.outdated):
            HStack(spacing: 36) {
                operationButton(
                    "Upgrade",
                    systemImage: "arrow.up.circle",
                    color: palette.brandAccent,
                    iconSize: 29
                ) {
                    controller.perform(.upgrade)
                }
                operationButton(
                    "Uninstall",
                    systemImage: "trash",
                    color: .red.opacity(0.86),
                    iconSize: 29
                ) {
                    controller.perform(.uninstall)
                }
            }

        case .ready(.installed):
            HStack(spacing: 36) {
                operationButton(
                    "Repair",
                    systemImage: "arrow.clockwise",
                    color: palette.ink,
                    iconSize: 29
                ) {
                    controller.perform(.repair)
                }
                operationButton(
                    "Uninstall",
                    systemImage: "trash",
                    color: .red.opacity(0.86),
                    iconSize: 29
                ) {
                    controller.perform(.uninstall)
                }
            }

        case .downloading(_, let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.blue)
                    .frame(width: 340)
                Text("Downloading… \(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(palette.ink.opacity(0.58))
                Button("Cancel", action: controller.cancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }

        case .verifying:
            workingIndicator("Verifying and installing…", palette: palette)
        case .removing:
            workingIndicator("Removing files…", palette: palette)
        case .completed:
            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(.blue)
                Button("Done") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
            }
        case .failed(let operation, _):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.red.opacity(0.82))
                Button("Try Again") { controller.perform(operation) }
                    .buttonStyle(.plain)
                    .foregroundStyle(operation == .uninstall ? .red : .blue)
            }
        }
    }

    private var downloadSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: controller.descriptor.expectedByteCount)) · Runs on device"
    }

    private func workingIndicator(_ label: String, palette: InstallerPalette) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(label).font(.callout)
        }
        .foregroundStyle(palette.ink.opacity(0.68))
    }

    private func operationButton(
        _ title: String,
        systemImage: String,
        color: Color,
        iconSize: CGFloat = 34,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 48, height: 48)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .foregroundStyle(color)
            .frame(width: 96)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func brandMark(palette: InstallerPalette) -> some View {
        // Two committed assets rather than a runtime recolor: the mark is a fixed
        // bitmap whose ink bars vanish on a dark ground.
        let markName = colorScheme == .dark ? "ChorusSoundwaveDark" : "ChorusSoundwave"
        if let image = NSImage(named: markName) {
            HStack(spacing: 10) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 66, height: 58)
                Text("CHORUS")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(3.2)
                    .foregroundStyle(palette.ink)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Chorus")
        } else {
            Image(systemName: "waveform")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(palette.brandAccent)
                .frame(width: 106, height: 106)
        }
    }
}

/// Chorus brand tokens, mirroring `BuildSupport/Brand/build-icon.sh`.
private enum Brand {
    /// Ink #272F38: primary text on light, and the basis of the dark ground.
    static let ink = NSColor(srgbRed: 39 / 255, green: 47 / 255, blue: 56 / 255, alpha: 1)
    /// A step below ink, so a window edge still reads against the content.
    static let groundDark = NSColor(srgbRed: 23 / 255, green: 27 / 255, blue: 33 / 255, alpha: 1)
    /// Paper, warmed slightly, as text on the dark ground.
    static let paper = NSColor(srgbRed: 244 / 255, green: 241 / 255, blue: 235 / 255, alpha: 1)
}

/// Brand colors, resolved per appearance.
///
/// A provider declares one background and one accent, describing its light
/// appearance. The dark counterparts are derived rather than declared, so
/// providers stay a two-color contract. Chorus's ink token is already close to a
/// dark ground, so the palette turns over instead of inverting: the ground
/// becomes ink and the text becomes paper, and the provider keeps its identity in
/// both appearances.
private struct InstallerPalette {
    let backgroundColor: NSColor
    let background: Color
    let brandAccent: Color
    let ink: Color

    init(descriptor: ProviderDescriptor) {
        let declaredBackground = NSColor(hex: descriptor.backgroundColor) ?? .windowBackgroundColor
        let declaredAccent = NSColor(hex: descriptor.accentColor) ?? .controlAccentColor

        backgroundColor = .resolving(light: declaredBackground, dark: Brand.groundDark)
        background = Color(nsColor: backgroundColor)
        ink = Color(nsColor: .resolving(light: Brand.ink, dark: Brand.paper))
        // Saturated amber goes muddy on a near-black ground; lift it to hold contrast.
        brandAccent = Color(nsColor: .resolving(
            light: declaredAccent,
            dark: declaredAccent.lifted(by: 0.18)
        ))
    }
}

private extension NSColor {
    /// A color that resolves against whatever appearance is drawing it. Applying
    /// this to `NSWindow.backgroundColor` is what makes the window chrome follow
    /// the system without observing appearance changes by hand.
    static func resolving(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    /// Brighter and a little less saturated, for use on a dark ground.
    func lifted(by amount: CGFloat) -> NSColor {
        guard let srgb = usingColorSpace(.sRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(
            hue: hue,
            saturation: max(0, saturation - amount * 0.3),
            brightness: min(1, brightness + amount),
            alpha: alpha
        )
    }

    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = Int(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }
}
