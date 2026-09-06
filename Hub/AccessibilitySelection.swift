import ApplicationServices
import Foundation

/// Read selection-only attributes, including browser text markers and terminal text ranges.
enum AccessibilitySelection {
    static func read(pid: pid_t, prepare: Bool) -> SelectionGate.Snapshot? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        // Chromium lazily exposes its document tree when an accessibility client requests it.
        if prepare { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(value, to: AXUIElement.self)
        }
        func parameterized(_ node: AXUIElement, _ name: String, _ range: CFTypeRef) -> String? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            var value: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(node, name as CFString, range, &value) == .success else { return nil }
            return value as? String
        }
        func selectedText(_ node: AXUIElement) -> String? {
            if let text = attribute(node, kAXSelectedTextAttribute) as? String, !text.isEmpty { return text }
            if let range = attribute(node, "AXSelectedTextMarkerRange"),
               let text = parameterized(node, "AXStringForTextMarkerRange", range), !text.isEmpty { return text }
            if let value = attribute(node, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
                let rangeValue = unsafeBitCast(value, to: AXValue.self)
                var range = CFRange()
                if AXValueGetType(rangeValue) == .cfRange, AXValueGetValue(rangeValue, .cfRange, &range),
                   range.location >= 0, range.length > 0, range.length <= 65_536 {
                    return parameterized(node, kAXStringForRangeParameterizedAttribute, value)
                }
            }
            return nil
        }

        let focused = element(attribute(app, kAXFocusedUIElementAttribute))
        // A secure focused field must suppress the whole search, not just that node.
        if let focused, attribute(focused, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole { return nil }
        var nodes: [AXUIElement] = []
        var ancestor = focused
        for _ in 0..<5 {
            guard let node = ancestor else { break }
            nodes.append(node)
            ancestor = element(attribute(node, kAXParentAttribute))
            if let ancestor, CFEqual(ancestor, app) { break }
        }
        if let window = element(attribute(app, kAXFocusedWindowAttribute)) { nodes.append(window) }
        var seen = Set<AXUIElement>()
        var index = 0
        // Focused controls can be a web area or terminal container, with selection on a child.
        // Bound traversal and IPC time so a large/unresponsive page cannot monopolize polling.
        while index < nodes.count, seen.count < 160, ProcessInfo.processInfo.systemUptime < deadline {
            let node = nodes[index]; index += 1
            guard seen.insert(node).inserted else { continue }
            guard attribute(node, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { continue }
            if let text = selectedText(node), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               text.utf8.count <= 65_536 {
                return .init(source: "\(pid):\(CFHash(node))", text: text)
            }
            if let children = (attribute(node, kAXVisibleChildrenAttribute) ?? attribute(node, kAXChildrenAttribute)) as? [AXUIElement] {
                nodes.append(contentsOf: children.prefix(max(0, 320 - nodes.count)))
            }
        }
        return nil
    }
}
