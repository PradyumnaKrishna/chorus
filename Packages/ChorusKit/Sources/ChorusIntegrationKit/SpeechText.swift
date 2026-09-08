import Foundation
import Markdown

/// Renders assistant-authored GitHub-flavored Markdown as stable plain text for speech.
///
/// The result is intended for a plain-string speech API. It must never be interpreted
/// as HTML or SSML. Link destinations and executable code are deliberately omitted.
public enum SpeechText {
    public static func render(_ input: String) -> String {
        let source = removeUnsafeControls(from: input)
        var renderer = SpeechMarkupRenderer()
        let rendered = renderer.visit(Document(parsing: removingControlDirectives(from: source)))
        return normalizeSpacing(in: rendered)
    }

    private static func removingControlDirectives(from text: String) -> String {
        text.components(separatedBy: .newlines)
            .filter { !isControlDirective($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: "\n")
    }

    private static func isControlDirective(_ line: String) -> Bool {
        guard line.hasPrefix("::"), line.hasSuffix("}"),
              let openingBrace = line.firstIndex(of: "{") else { return false }
        let name = line[line.index(line.startIndex, offsetBy: 2)..<openingBrace]
        guard let first = name.first, first.isASCII && first.isLetter else { return false }
        return name.dropFirst().allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber
                                   || character == "-" || character == "_")
        }
    }

    private static func removeUnsafeControls(from text: String) -> String {
        let omitted: Set<UInt32> = [0x200B, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
                                    0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF]
        let scalars = text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t"
                || (scalar.value >= 0x20 && scalar.value != 0x7F && !omitted.contains(scalar.value))
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func normalizeSpacing(in text: String) -> String {
        var lines: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .joined(separator: " ")
            if line.isEmpty {
                if !lines.isEmpty, lines.last != "" { lines.append("") }
            } else {
                lines.append(line)
            }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n")
    }
}

private struct SpeechMarkupRenderer: MarkupVisitor {
    typealias Result = String

    private var announcedCodeBlock = false

    mutating func defaultVisit(_ markup: Markup) -> String {
        renderChildren(of: markup)
    }

    mutating func visitDocument(_ document: Document) -> String {
        renderChildren(of: document, separatedBy: "\n\n")
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> String {
        renderChildren(of: blockQuote, separatedBy: "\n")
    }

    mutating func visitHeading(_ heading: Heading) -> String {
        renderChildren(of: heading)
    }

    mutating func visitParagraph(_ paragraph: Paragraph) -> String {
        renderChildren(of: paragraph)
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) -> String {
        renderChildren(of: orderedList, separatedBy: "\n")
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> String {
        renderChildren(of: unorderedList, separatedBy: "\n")
    }

    mutating func visitListItem(_ listItem: ListItem) -> String {
        renderChildren(of: listItem, separatedBy: "\n")
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> String {
        guard !announcedCodeBlock else { return "" }
        announcedCodeBlock = true
        return "Code block omitted."
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) -> String {
        inlineCode.code
    }

    mutating func visitText(_ text: Text) -> String {
        text.string
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) -> String { " " }
    mutating func visitLineBreak(_ lineBreak: LineBreak) -> String { "\n" }
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> String { "" }
    mutating func visitHTMLBlock(_ html: HTMLBlock) -> String { "" }
    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> String { "" }
    mutating func visitBlockDirective(_ blockDirective: BlockDirective) -> String { "" }
    mutating func visitCustomBlock(_ customBlock: CustomBlock) -> String { "" }
    mutating func visitCustomInline(_ customInline: CustomInline) -> String { "" }
    mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> String { "" }

    mutating func visitImage(_ image: Image) -> String {
        renderChildren(of: image)
    }

    mutating func visitLink(_ link: Link) -> String {
        renderChildren(of: link)
    }

    mutating func visitTable(_ table: Table) -> String {
        renderChildren(of: table, separatedBy: "\n")
    }

    mutating func visitTableHead(_ tableHead: Table.Head) -> String {
        renderChildren(of: tableHead, separatedBy: ", ")
    }

    mutating func visitTableBody(_ tableBody: Table.Body) -> String {
        renderChildren(of: tableBody, separatedBy: "\n")
    }

    mutating func visitTableRow(_ tableRow: Table.Row) -> String {
        renderChildren(of: tableRow, separatedBy: ", ")
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) -> String {
        renderChildren(of: tableCell)
    }

    private mutating func renderChildren(of markup: Markup, separatedBy separator: String = "") -> String {
        markup.children.map { visit($0) }.filter { !$0.isEmpty }.joined(separator: separator)
    }
}
