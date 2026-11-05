import AppKit
import ApplicationServices
@testable import PromptPolishCore
@testable import PromptPolishUI

struct AXKey: Hashable {
    let element: AXUIElement
    init(_ element: AXUIElement) { self.element = element }
    static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
    func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
}

@MainActor
final class AXTextAccessTests {
    /// Fake only the cross-process AX/Workspace calls; exercise the real adapter and transaction.
    final class Runtime: AXRuntime {
        var isTrusted = true
        var ownPID: pid_t = 900_000
        var frontmostPID: pid_t? = 900_000
        var attributes: [AXKey: [String: CFTypeRef]] = [:]
        var owners: [AXKey: pid_t] = [:]
        var settable = true
        var writes = 0
        func isRunning(_ application: NSRunningApplication) -> Bool { true }
        func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? { attributes[AXKey(element)]?[name] }
        func processID(of element: AXUIElement) -> pid_t? { owners[AXKey(element)] }
        func isValueSettable(on element: AXUIElement) -> Bool { settable }
        func setValue(_ value: String, on element: AXUIElement) -> AXError {
            writes += 1
            put(kAXValueAttribute, value as CFString, on: element)
            return .success
        }
        func put(_ attribute: String, _ value: CFTypeRef?, on element: AXUIElement) {
            attributes[AXKey(element), default: [:]][attribute] = value
        }
    }

    @MainActor
    final class Fixture {
        let runtime = Runtime()
        let app: AXUIElement
        let field = AXUIElementCreateApplication(900_001)
        let window = AXUIElementCreateApplication(900_002)
        let otherField = AXUIElementCreateApplication(900_003)
        let otherWindow = AXUIElementCreateApplication(900_004)
        let access: AXTextAccess
        init() {
            let targetPID = NSRunningApplication.current.processIdentifier
            app = AXUIElementCreateApplication(targetPID)
            for element in [app, field, window, otherField, otherWindow] { runtime.owners[AXKey(element)] = targetPID }
            runtime.put(kAXRoleAttribute, kAXTextAreaRole as CFString, on: field)
            runtime.put(kAXRoleAttribute, kAXTextAreaRole as CFString, on: otherField)
            runtime.put(kAXRoleAttribute, kAXWindowRole as CFString, on: window)
            runtime.put(kAXRoleAttribute, kAXWindowRole as CFString, on: otherWindow)
            runtime.put(kAXWindowAttribute, window, on: field)
            runtime.put(kAXValueAttribute, "原始 Prompt 🧑‍💻" as CFString, on: field)
            runtime.put(kAXFocusedUIElementAttribute, field, on: app)
            runtime.put(kAXFocusedWindowAttribute, window, on: app)
            let target = AXTarget(application: .current, element: field, window: window, canWrite: true, rect: CGRect(x: 10, y: 10, width: 400, height: 100))
            access = AXTextAccess(target: target, runtime: runtime)
        }
        func blurSourceApplication() {
            runtime.put(kAXFocusedUIElementAttribute, nil, on: app)
            runtime.put(kAXFocusedWindowAttribute, nil, on: app)
        }
    }

    func testOriginalFocusedTargetCanBeRead() throws {
        let fixture = Fixture()
        expectEqual(try fixture.access.read(), "原始 Prompt 🧑‍💻")
    }

    func testPreviewFocusDoesNotInvalidatePinnedField() throws {
        let fixture = Fixture()
        let transaction = TextTransaction(access: fixture.access, original: "原始 Prompt 🧑‍💻")
        fixture.blurSourceApplication()
        try transaction.replace(with: "优化后的 Prompt")
        expectEqual(try fixture.access.read(), "优化后的 Prompt")
        try transaction.undo()
        expectEqual(try fixture.access.read(), "原始 Prompt 🧑‍💻")
    }

    func testOptionalFocusedWindowIsNotRequiredWhenExactFieldIsKnown() throws {
        let fixture = Fixture()
        fixture.runtime.frontmostPID = fixture.access.target.application.processIdentifier
        fixture.runtime.put(kAXFocusedWindowAttribute, nil, on: fixture.app)
        expectEqual(try fixture.access.read(), "原始 Prompt 🧑‍💻")
    }

    func testChangedTextStillBlocksWriteAfterPreviewFocus() {
        let fixture = Fixture()
        let transaction = TextTransaction(access: fixture.access, original: "原始 Prompt 🧑‍💻")
        fixture.blurSourceApplication()
        fixture.runtime.put(kAXValueAttribute, "用户新增的内容" as CFString, on: fixture.field)
        expectThrows(try transaction.replace(with: "AI text")) { expectEqual($0 as? TransactionError, .contentChanged) }
        expectEqual(fixture.runtime.writes, 0)
    }

    func testOtherFocusedFieldIsNeverSubstituted() {
        let fixture = Fixture()
        fixture.runtime.put(kAXFocusedUIElementAttribute, fixture.otherField, on: fixture.app)
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
    }

    func testOtherWindowIsNeverAccepted() {
        let fixture = Fixture()
        fixture.runtime.put(kAXFocusedWindowAttribute, fixture.otherWindow, on: fixture.app)
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
    }

    func testPinnedFieldMovedToOtherWindowIsRejected() {
        let fixture = Fixture()
        fixture.runtime.put(kAXWindowAttribute, fixture.otherWindow, on: fixture.field)
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
    }

    func testForegroundSourceStillRequiresItsOriginalFocus() {
        let fixture = Fixture()
        fixture.runtime.frontmostPID = fixture.access.target.application.processIdentifier
        fixture.blurSourceApplication()
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
    }

    func testUnrelatedForegroundApplicationBlocksWrite() {
        let fixture = Fixture()
        fixture.runtime.frontmostPID = 900_099
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
    }

    func testInvalidOrSecurePinnedTargetsAreRejected() {
        let fixture = Fixture()
        fixture.runtime.owners[AXKey(fixture.field)] = nil
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
        fixture.runtime.owners[AXKey(fixture.field)] = fixture.access.target.application.processIdentifier
        fixture.runtime.put(kAXSubroleAttribute, kAXSecureTextFieldSubrole as CFString, on: fixture.field)
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
    }
}
