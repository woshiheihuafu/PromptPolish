import AppKit
import ApplicationServices

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
}

extension AXRuntime {
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
