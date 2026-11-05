import AppKit
import ApplicationServices

enum AXValueFailure: LocalizedError, Equatable {
    case read(Int32), write(Int32)
    var errorDescription: String? {
        switch self {
        case .read(let code): return "AXValue 读取失败（系统错误码 \(code)）。"
        case .write(let code): return "AXValue 写入失败（系统错误码 \(code)）。"
        }
    }
}

/// The operating-system boundary used by a pinned accessibility text target.
@MainActor
protocol AXRuntime {
    var isTrusted: Bool { get }
    var ownPID: pid_t { get }
    var frontmostPID: pid_t? { get }
    func isRunning(_ application: NSRunningApplication) -> Bool
    func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef?
    func processID(of element: AXUIElement) -> pid_t?
    func isValueSettable(on element: AXUIElement) -> Bool
    func setValue(_ value: String, on element: AXUIElement) -> AXError
    func readValue(of element: AXUIElement) throws -> String
    func attributedText(of element: AXUIElement) -> NSAttributedString?
    func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool
    func setAttribute(_ name: String, value: CFTypeRef, on element: AXUIElement) -> AXError
}

@MainActor
struct SystemAXRuntime: AXRuntime {
    var isTrusted: Bool { AXIsProcessTrusted() }
    var ownPID: pid_t { ProcessInfo.processInfo.processIdentifier }
    var frontmostPID: pid_t? { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    func isRunning(_ application: NSRunningApplication) -> Bool { !application.isTerminated }
    func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    func processID(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(element, &pid) == .success ? pid : nil
    }
    func isValueSettable(on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
    }
    func setValue(_ value: String, on element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString)
    }
    func readValue(of element: AXUIElement) throws -> String {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
        guard error == .success else { throw AXValueFailure.read(error.rawValue) }
        guard let text = value as? String else { throw AccessError.unreadable }
        return text
    }
    func attributedText(of element: AXUIElement) -> NSAttributedString? {
        let count = (attribute(kAXNumberOfCharactersAttribute, of: element) as? NSNumber)?.intValue
            ?? (try? readValue(of: element).utf16.count)
        guard let count, count > 0, count <= 500_000 else { return nil }
        var range = CFRange(location: 0, length: count)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXAttributedStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success else { return nil }
        return value as? NSAttributedString
    }
    func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }
    func setAttribute(_ name: String, value: CFTypeRef, on element: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(element, name as CFString, value)
    }
}

extension AXRuntime {
    func attributedText(of element: AXUIElement) -> NSAttributedString? { nil }
    func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool { false }
    func setAttribute(_ name: String, value: CFTypeRef, on element: AXUIElement) -> AXError { .attributeUnsupported }
    func hasInlineObjects(in element: AXUIElement) -> Bool {
        if let text = attributedText(of: element) {
            var found = false
            text.enumerateAttribute(NSAttributedString.Key(kAXAttachmentTextAttribute.takeUnretainedValue() as String), in: NSRange(location: 0, length: text.length)) { value, _, stop in
                if value != nil { found = true; stop.pointee = true }
            }
            if found || text.string.contains("\u{FFFC}") { return true }
        }
        // Independent sibling attachments are deliberately outside this scan.
        var pending: [(AXUIElement, Int)] = [(element, 0)], visited = [AXUIElement]()
        for _ in 0..<128 {
            guard let (node, depth) = pending.popLast() else { return false }
            guard !visited.contains(where: { CFEqual($0, node) }) else { continue }
            visited.append(node)
            if depth > 0, string(kAXRoleAttribute, of: node) == kAXImageRole { return true }
            if let children = attribute(kAXChildrenAttribute, of: node) as? [AXUIElement], !children.isEmpty {
                // An incomplete scan is unknown, never proof that a whole-value write is safe.
                guard depth < 4, children.count <= 128 else { return true }
                pending.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }
        return !pending.isEmpty
    }
    func string(_ attribute: String, of element: AXUIElement) -> String? {
        self.attribute(attribute, of: element) as? String
    }
    func element(_ attribute: String, of element: AXUIElement) -> AXUIElement? {
        guard let value = self.attribute(attribute, of: element), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func textField(containing focused: AXUIElement) -> AXUIElement? {
        var candidate: AXUIElement? = focused
        for _ in 0..<4 {
            guard let node = candidate else { return nil }
            let role = string(kAXRoleAttribute, of: node)
            if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role ?? "") { return node }
            candidate = element(kAXParentAttribute, of: node)
        }
        return nil
    }
}
