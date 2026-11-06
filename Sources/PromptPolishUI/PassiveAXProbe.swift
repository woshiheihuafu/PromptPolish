import AppKit
import ApplicationServices

/// Immutable handles/geometry may cross the serial probe queue; no prompt text is read.
struct PassiveAXTarget: @unchecked Sendable {
    let pid: pid_t
    let element: AXUIElement
    let window: AXUIElement
    let canWrite: Bool
    let rawFrame: CGRect
}

@MainActor
final class PassiveTargetTracker {
    typealias Probe = @Sendable (pid_t, PassiveAXTarget?) -> PassiveAXTarget?
    private let queue = DispatchQueue(label: "com.kker.PromptPolish.passiveAX", qos: .userInitiated)
    private let probe: Probe
    private var desiredPID: pid_t?
    private var cached: PassiveAXTarget?
    private var generation = 0
    private var running = false
    private var deliver: ((PassiveAXTarget?) -> Void)?
    init(probe: @escaping Probe = { SystemPassiveAXProbe.read($0, preferred: $1) }) { self.probe = probe }

    func request(pid: pid_t, deliver: @escaping (PassiveAXTarget?) -> Void) {
        if desiredPID != pid { generation += 1; desiredPID = pid; cached = nil }
        self.deliver = deliver
        if !running { launch(pid: pid, generation: generation) }
    }
    func cancel() { generation += 1; desiredPID = nil; deliver = nil; cached = nil }
    private func launch(pid: pid_t, generation ticket: Int) {
        running = true
        let operation = probe
        let preferred = cached
        queue.async { [weak self] in
            let result = operation(pid, preferred)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.running = false
                if self.generation == ticket, self.desiredPID == pid { self.cached = result; self.deliver?(result) }
                else if let latest = self.desiredPID { self.launch(pid: latest, generation: self.generation) }
            }
        }
    }
}

protocol PassiveAXReading {
    func attribute(_ key: String, _ node: AXUIElement) throws -> CFTypeRef?
    func processID(_ node: AXUIElement) -> pid_t?
    func isValueSettable(_ node: AXUIElement) -> Bool
    func setTimeout(_ seconds: Float, _ node: AXUIElement)
}

struct SystemPassiveAXReader: PassiveAXReading {
    func attribute(_ key: String, _ node: AXUIElement) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(node, key as CFString, &value)
        switch error {
        case .success: return value
        case .attributeUnsupported, .noValue: return nil
        default: throw AXValueFailure.read(error.rawValue)
        }
    }
    func processID(_ node: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(node, &pid) == .success ? pid : nil
    }
    func isValueSettable(_ node: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(node, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
    }
    func setTimeout(_ seconds: Float, _ node: AXUIElement) { AXUIElementSetMessagingTimeout(node, seconds) }
}

enum SystemPassiveAXProbe {
    static func read(_ pid: pid_t, preferred: PassiveAXTarget? = nil, reader: any PassiveAXReading = SystemPassiveAXReader()) -> PassiveAXTarget? {
        let app = AXUIElementCreateApplication(pid)
        let system = AXUIElementCreateSystemWide()
        // Never set a timeout on the system-wide object: that changes the global default.
        reader.setTimeout(0.15, app)
        let focused = element(kAXFocusedUIElementAttribute, app, reader) ?? element(kAXFocusedUIElementAttribute, system, reader)
        // The normal focus route remains authoritative, including non-text focus.
        let resolved: AXUIElement?
        var reused = false
        if let focused {
            resolved = textField(focused, reader)
        } else if let window = element(kAXFocusedWindowAttribute, app, reader),
                  reader.processID(window) == pid, string(kAXRoleAttribute, window, reader) == kAXWindowRole {
            if let preferred, preferred.pid == pid, CFEqual(preferred.window, window),
               (try? reader.attribute(kAXFocusedAttribute, preferred.element)) as? Bool == true,
               let containingWindow = element(kAXWindowAttribute, preferred.element, reader), CFEqual(containingWindow, window),
               [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(string(kAXRoleAttribute, preferred.element, reader) ?? "") {
                resolved = preferred.element
                reused = true
            } else {
                resolved = AXFocusedFieldSearch.find(in: window) { key, node in
                    reader.setTimeout(0.04, node)
                    return try reader.attribute(key, node)
                }
            }
        } else { resolved = nil }
        guard let field = resolved,
              string(kAXSubroleAttribute, field, reader) != kAXSecureTextFieldSubrole,
              let window = element(kAXWindowAttribute, field, reader),
              reader.processID(window) == pid else { return nil }
        // A cached handle may have been explicitly captured/reset to the default
        // timeout. Do not change that shared handle's timeout on later passive reads.
        if !reused { reader.setTimeout(0.15, field) }
        guard let position = try? reader.attribute(kAXPositionAttribute, field),
              let size = try? reader.attribute(kAXSizeAttribute, field),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width >= 30, dimensions.height >= 18 else { return nil }
        return PassiveAXTarget(pid: pid, element: field, window: window, canWrite: reader.isValueSettable(field), rawFrame: CGRect(origin: point, size: dimensions))
    }
    private static func string(_ key: String, _ node: AXUIElement, _ reader: any PassiveAXReading) -> String? {
        (try? reader.attribute(key, node)) as? String
    }
    private static func element(_ key: String, _ node: AXUIElement, _ reader: any PassiveAXReading) -> AXUIElement? {
        guard let value = try? reader.attribute(key, node), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func textField(_ focused: AXUIElement, _ reader: any PassiveAXReading) -> AXUIElement? {
        var current: AXUIElement? = focused
        for _ in 0..<4 {
            guard let node = current else { return nil }
            reader.setTimeout(0.15, node)
            if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(string(kAXRoleAttribute, node, reader) ?? "") { return node }
            current = element(kAXParentAttribute, node, reader)
        }
        return nil
    }
}
