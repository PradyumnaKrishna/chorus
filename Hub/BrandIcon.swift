import SwiftUI

struct BrandIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    private static let light = load("ChorusSoundwave")
    private static let dark = load("ChorusSoundwaveDark")

    private static func load(_ name: String) -> NSImage {
        #if CHORUS_SNAPSHOT
        return NSImage(contentsOfFile: "BuildSupport/Brand/\(name).png") ?? NSImage()
        #else
        return NSImage(named: name) ?? NSImage()
        #endif
    }

    var body: some View {
        Image(nsImage: colorScheme == .dark ? Self.dark : Self.light)
            .resizable().scaledToFit().accessibilityHidden(true)
    }

    static let menuImage: NSImage = {
        let image = (light.copy() as? NSImage) ?? NSImage()
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }()
}
