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
    typealias Probe = @Sendable (pid_t) -> PassiveAXTarget?
    private let queue = DispatchQueue(label: "com.kker.PromptPolish.passiveAX", qos: .userInitiated)
    private let probe: Probe
    private var desiredPID: pid_t?
    private var generation = 0
    private var running = false
    private var deliver: ((PassiveAXTarget?) -> Void)?
    init(probe: @escaping Probe = { SystemPassiveAXProbe.read($0) }) { self.probe = probe }

    func request(pid: pid_t, deliver: @escaping (PassiveAXTarget?) -> Void) {
        if desiredPID != pid { generation += 1; desiredPID = pid }
        self.deliver = deliver
        if !running { launch(pid: pid, generation: generation) }
    }
    func cancel() { generation += 1; desiredPID = nil; deliver = nil }
    private func launch(pid: pid_t, generation ticket: Int) {
        running = true
        let operation = probe
        queue.async { [weak self] in
            let result = operation(pid)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.running = false
                if self.generation == ticket, self.desiredPID == pid { self.deliver?(result) }
                else if let latest = self.desiredPID { self.launch(pid: latest, generation: self.generation) }
            }
        }
    }
}

enum SystemPassiveAXProbe {
    static func read(_ pid: pid_t) -> PassiveAXTarget? {
        let app = AXUIElementCreateApplication(pid)
        let system = AXUIElementCreateSystemWide()
        // Setting a timeout on the system-wide object would change the process-global
        // default, including writes. Only bound these private passive query handles.
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let focused = element(kAXFocusedUIElementAttribute, app) ?? element(kAXFocusedUIElementAttribute, system),
              let field = textField(focused),
              string(kAXSubroleAttribute, field) != kAXSecureTextFieldSubrole,
              let window = element(kAXWindowAttribute, field) else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(window, &owner) == .success, owner == pid else { return nil }
        AXUIElementSetMessagingTimeout(field, 0.15)
        guard let position = attribute(kAXPositionAttribute, field), let size = attribute(kAXSizeAttribute, field),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width >= 30, dimensions.height >= 18 else { return nil }
        var settable = DarwinBoolean(false)
        let writable = AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        return PassiveAXTarget(pid: pid, element: field, window: window, canWrite: writable, rawFrame: CGRect(origin: point, size: dimensions))
    }
    private static func attribute(_ key: String, _ node: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success ? value : nil
    }
    private static func string(_ key: String, _ node: AXUIElement) -> String? { attribute(key, node) as? String }
    private static func element(_ key: String, _ node: AXUIElement) -> AXUIElement? {
        guard let value = attribute(key, node), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func textField(_ focused: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = focused
        for _ in 0..<4 {
            guard let node = current else { return nil }
            AXUIElementSetMessagingTimeout(node, 0.15)
            if [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(string(kAXRoleAttribute, node) ?? "") { return node }
            current = element(kAXParentAttribute, node)
        }
        return nil
    }
}
