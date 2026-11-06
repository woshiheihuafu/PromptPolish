import AppKit
import ApplicationServices
import PromptPolishCore

@MainActor
protocol FocusableTextAccess: TextAccess {
    func restoreFocus()
}

@MainActor
protocol AccessibilityProviding {
    var isTrusted: Bool { get }
    var current: AXTarget? { get }
    func requestPermission()
    func openPermissionSettings()
    func refresh() -> AXTarget?
    func capture() throws -> (AXTarget, String, any FocusableTextAccess)
}

enum TargetChangeReason: Equatable {
    case otherApplication, otherWindow, otherField, windowMembership, focusUnavailable
}

enum AccessError: LocalizedError, Equatable {
    case permission, noField, secure, unreadable, readOnly, unavailable, richText
    case targetChanged(TargetChangeReason)
    var errorDescription: String? {
        switch self {
        case .permission: return "辅助功能权限未开启。请在系统设置中允许 PromptPolish，再重新检测。"
        case .noField: return "没有找到可编辑输入框。请点击原应用的输入框，再按 ⌘ ⇧ E。"
        case .secure: return "安全输入框不支持读取或优化。"
        case .unreadable: return "暂时无法读取这个输入框，当前控件没有提供可用文本。"
        case .readOnly: return "这个输入框暂不支持可靠写回。结果已保留，可继续预览。"
        case .targetChanged(.otherApplication): return "当前已切换到其他应用。请回到原应用输入框后重试。"
        case .targetChanged(.otherWindow): return "原应用已切换到另一个窗口。请回到触发优化的窗口。"
        case .targetChanged(.otherField): return "原应用当前聚焦了另一个输入框。请回到触发优化的输入框。"
        case .targetChanged(.windowMembership): return "原输入框所属的窗口已变化，请重新获取输入内容。"
        case .targetChanged(.focusUnavailable): return "暂时无法确认原输入框的焦点。请点击原输入框后重试。"
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
final class AccessibilityService: AccessibilityProviding {
    private(set) var current: AXTarget?
    var isTrusted: Bool { AXIsProcessTrusted() }
    private let passive = PassiveTargetTracker()

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
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication else { passive.cancel(); current = nil; return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { passive.cancel(); return current }
        if current?.application.processIdentifier != app.processIdentifier { current = nil }
        passive.request(pid: app.processIdentifier) { [weak self] result in
            guard let self, self.isTrusted,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            self.current = result.flatMap { self.target(from: $0, application: app) }
        }
        return current
    }

    func capture() throws -> (AXTarget, String, any FocusableTextAccess) {
        guard isTrusted else { throw AccessError.permission }
        passive.cancel()
        guard let app = NSWorkspace.shared.frontmostApplication else { throw AccessError.noField }
        let captured: AXTarget?
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { captured = current }
        else { captured = SystemPassiveAXProbe.read(app.processIdentifier).flatMap { target(from: $0, application: app) } }
        guard let target = captured else { throw AccessError.noField }
        // Passive handles use short read timeouts. Explicit capture/read/write must
        // retain the normal default instead of inheriting the probe's 150 ms budget.
        AXUIElementSetMessagingTimeout(target.element, 0)
        AXUIElementSetMessagingTimeout(target.window, 0)
        current = target
        let access = AXTextAccess(target: target)
        let value = try access.read()
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizationError.emptyPrompt }
        guard value.utf8.count <= 200_000 else { throw OptimizationError.tooLarge }
        guard !value.contains("\u{FFFC}") else { throw AccessError.richText }
        return (target, value, access)
    }

    private func target(from result: PassiveAXTarget, application: NSRunningApplication) -> AXTarget? {
        guard result.pid == application.processIdentifier, !application.isTerminated, let primary = NSScreen.screens.first else { return nil }
        let rect = CGRect(x: result.rawFrame.minX, y: primary.frame.maxY - result.rawFrame.maxY, width: result.rawFrame.width, height: result.rawFrame.height)
        return AXTarget(application: application, element: result.element, window: result.window, canWrite: result.canWrite, rect: rect)
    }
}

@MainActor
final class AXTextAccess: FocusableTextAccess {
    let target: AXTarget
    private let runtime: any AXRuntime
    init(target: AXTarget, runtime: (any AXRuntime)? = nil) {
        self.target = target
        self.runtime = runtime ?? SystemAXRuntime()
    }

    func validate() throws {
        guard runtime.isTrusted else { throw AccessError.permission }
        guard runtime.isRunning(target.application) else { throw AccessError.unavailable }
        guard let front = runtime.frontmostPID else { throw AccessError.targetChanged(.focusUnavailable) }
        let sourcePID = target.application.processIdentifier
        guard front == runtime.ownPID || front == sourcePID else { throw AccessError.targetChanged(.otherApplication) }

        // Pin the original field and its containing window; never search by text or geometry.
        // A hosted field may be implemented in another process, but its containing window must
        // still be the captured source window and belong to the captured application.
        guard runtime.processID(of: target.element) != nil,
              runtime.processID(of: target.window) == sourcePID,
              runtime.string(kAXRoleAttribute, of: target.window) == kAXWindowRole,
              let role = runtime.string(kAXRoleAttribute, of: target.element),
              [kAXTextAreaRole, kAXTextFieldRole, kAXComboBoxRole].contains(role) else { throw AccessError.unavailable }
        guard runtime.string(kAXSubroleAttribute, of: target.element) != kAXSecureTextFieldSubrole else { throw AccessError.secure }
        guard let containingWindow = runtime.element(kAXWindowAttribute, of: target.element),
              CFEqual(containingWindow, target.window) else { throw AccessError.targetChanged(.windowMembership) }

        let app = AXUIElementCreateApplication(target.application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.4)
        if let focusedWindow = runtime.element(kAXFocusedWindowAttribute, of: app), !CFEqual(focusedWindow, target.window) {
            throw AccessError.targetChanged(.otherWindow)
        }
        if let focused = runtime.element(kAXFocusedUIElementAttribute, of: app), let field = runtime.textField(containing: focused) {
            guard CFEqual(field, target.element) else { throw AccessError.targetChanged(.otherField) }
        } else if front != runtime.ownPID {
            throw AccessError.targetChanged(.focusUnavailable)
        }
        // Clicking our preview legitimately removes the source application's keyboard focus.
        // In that case the live, pinned field/window above provide identity; TextTransaction
        // still compares its exact current text before a write and verifies the readback.
    }

    func read() throws -> String {
        try validate()
        return try runtime.readValue(of: target.element)
    }

    func write(_ text: String) throws {
        try validate()
        guard runtime.isValueSettable(on: target.element) else { throw AccessError.readOnly }
        guard !text.contains("\u{FFFC}") else { throw AccessError.richText }
        let error = runtime.setValue(text, on: target.element)
        guard error == .success else { throw AXValueFailure.write(error.rawValue) }
    }

    func restoreFocus() {
        guard !target.application.isTerminated else { return }
        target.application.activate()
    }
}

