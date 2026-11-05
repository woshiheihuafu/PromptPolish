import AppKit
import ApplicationServices
import PromptPolishCore

enum AccessError: LocalizedError {
    case permission, noField, secure, unreadable, readOnly, targetChanged, unavailable, richText
    var errorDescription: String? {
        switch self {
        case .permission: return "辅助功能权限未开启。请在系统设置中允许 PromptPolish，再重新检测。"
        case .noField: return "没有找到可编辑输入框。请点击原应用的输入框，再按 ⌘ ⇧ E。"
        case .secure: return "安全输入框不支持读取或优化。"
        case .unreadable: return "暂时无法读取这个输入框，当前控件没有提供可用文本。"
        case .readOnly: return "这个输入框暂不支持可靠写回。结果已保留，可继续预览。"
        case .targetChanged: return "目标输入框或窗口已变化。请回到原输入框再试，当前输入未被替换。"
        case .unavailable: return "目标窗口已关闭或暂时无法访问。结果与原文快照仍保留。"
        case .richText: return "输入内容含附件或嵌入对象，暂不替换，以免丢失原有内容。"
        }
    }
}

@MainActor
struct AXTarget {
    let application: NSRunningApplication
    let element: AXUIElement
    let window: AXUIElement
    let canWrite: Bool
    let rect: CGRect
    var name: String { application.localizedName ?? "当前应用" }
    var bundleID: String { application.bundleIdentifier ?? "未知应用" }
    func sameField(as other: AXTarget) -> Bool {
        application.processIdentifier == other.application.processIdentifier && CFEqual(element, other.element) && CFEqual(window, other.window)
    }
}

@MainActor
final class AccessibilityService {
    private(set) var current: AXTarget?
    var isTrusted: Bool { AXIsProcessTrusted() }
    private let system = AXUIElementCreateSystemWide()

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Passive tracking reads only role, geometry and capability, never the prompt value.
    @discardableResult
    func refresh() -> AXTarget? {
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication else { current = nil; return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return current }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        guard let focused = axElement(appElement, kAXFocusedUIElementAttribute) ?? axElement(system, kAXFocusedUIElementAttribute),
              let field = textField(focused),
              let window = axElement(field, kAXWindowAttribute),
              let rect = frame(field), rect.width >= 30, rect.height >= 18,
              axString(field, kAXSubroleAttribute) != (kAXSecureTextFieldSubrole as String) else {
            current = nil
            return nil
        }
        var settable = DarwinBoolean(false)
        let canWrite = AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        current = AXTarget(application: app, element: field, window: window, canWrite: canWrite, rect: rect)
        return current
    }

    func capture() throws -> (AXTarget, String, AXTextAccess) {
        guard isTrusted else { throw AccessError.permission }
        guard let target = refresh() else { throw AccessError.noField }
        let access = AXTextAccess(target: target)
        let value = try access.read()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizationError.emptyPrompt }
        guard value.utf8.count <= 200_000 else { throw OptimizationError.tooLarge }
        guard !value.contains("\u{FFFC}") else { throw AccessError.richText }
        return (target, value, access)
    }

    private func textField(_ focused: AXUIElement) -> AXUIElement? {
        var candidate: AXUIElement? = focused
        for _ in 0..<4 {
            guard let node = candidate else { return nil }
            let role = axString(node, kAXRoleAttribute)
            if role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) || role == (kAXComboBoxRole as String) { return node }
            candidate = axElement(node, kAXParentAttribute)
        }
        return nil
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = axValue(element, kAXPositionAttribute), let size = axValue(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              let primary = NSScreen.screens.first else { return nil }
        let rect = CGRect(x: point.x, y: primary.frame.maxY - point.y - dimensions.height, width: dimensions.width, height: dimensions.height)
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { return nil }
        return rect
    }
}

@MainActor
final class AXTextAccess: TextAccess {
    let target: AXTarget
    init(target: AXTarget) { self.target = target }

    func validate() throws {
        guard AXIsProcessTrusted() else { throw AccessError.permission }
        guard !target.application.isTerminated else { throw AccessError.unavailable }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ownPID && front.processIdentifier != target.application.processIdentifier {
            throw AccessError.targetChanged
        }
        let app = AXUIElementCreateApplication(target.application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.4)
        guard let focused = axElement(app, kAXFocusedUIElementAttribute), CFEqual(focused, target.element),
              let window = axElement(app, kAXFocusedWindowAttribute), CFEqual(window, target.window),
              axString(target.element, kAXSubroleAttribute) != (kAXSecureTextFieldSubrole as String) else { throw AccessError.targetChanged }
    }

    func read() throws -> String {
        try validate()
        guard let value = axString(target.element, kAXValueAttribute) else { throw AccessError.unreadable }
        return value
    }

    func write(_ text: String) throws {
        try validate()
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(target.element, kAXValueAttribute as CFString, &settable) == .success, settable.boolValue else { throw AccessError.readOnly }
        guard !text.contains("\u{FFFC}") else { throw AccessError.richText }
        guard AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString, text as CFString) == .success else { throw AccessError.unavailable }
    }

    func restoreFocus() {
        guard !target.application.isTerminated else { return }
        target.application.activate()
    }
}

@MainActor
private func axValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
    return value
}

@MainActor
private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    axValue(element, attribute) as? String
}

@MainActor
private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = axValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
