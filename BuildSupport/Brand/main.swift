import AppKit
import Foundation

enum IconBuildError: LocalizedError {
    case usage
    case invalidColor(String)
    case unreadableMark(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .usage:
            return "Usage: main.swift <mark.png> <output.png> <background-hex> <ink-hex> <subtitle>"
        case .invalidColor(let value):
            return "Invalid six-digit color: \(value)"
        case .unreadableMark(let path):
            return "Could not read the soundwave mark at \(path)"
        case .encodingFailed:
            return "Could not encode the finished icon as PNG"
        }
    }
}

extension NSColor {
    convenience init(hex: String) throws {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let rgb = Int(value, radix: 16) else {
            throw IconBuildError.invalidColor(hex)
        }
        self.init(
            red: CGFloat((rgb >> 16) & 0xff) / 255,
            green: CGFloat((rgb >> 8) & 0xff) / 255,
            blue: CGFloat(rgb & 0xff) / 255,
            alpha: 1
        )
    }
}

let arguments = CommandLine.arguments
guard arguments.count == 6 else { throw IconBuildError.usage }
guard let mark = NSImage(contentsOfFile: arguments[1]) else {
    throw IconBuildError.unreadableMark(arguments[1])
}

let size = NSSize(width: 1_024, height: 1_024)
let image = NSImage(size: size)
image.lockFocus()
NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let tile = NSBezierPath(
    roundedRect: NSRect(x: 54, y: 54, width: 916, height: 916),
    xRadius: 210,
    yRadius: 210
)
try NSColor(hex: arguments[3]).setFill()
tile.fill()

NSGraphicsContext.current?.imageInterpolation = .high
mark.draw(
    in: NSRect(x: 145, y: 190, width: 734, height: 690),
    from: .zero,
    operation: .sourceOver,
    fraction: 1
)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 72, weight: .bold),
    .foregroundColor: try NSColor(hex: arguments[4]),
    .kern: 9,
    .paragraphStyle: paragraph
]
NSString(string: arguments[5].uppercased()).draw(
    in: NSRect(x: 110, y: 106, width: 804, height: 92),
    withAttributes: attributes
)
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    throw IconBuildError.encodingFailed
}
try png.write(to: URL(fileURLWithPath: arguments[2]))
