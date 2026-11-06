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
        var setterResult: AXError = .success
        var readErrorAfterWrite: AXError?
        func isRunning(_ application: NSRunningApplication) -> Bool { true }
        func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? { attributes[AXKey(element)]?[name] }
        func processID(of element: AXUIElement) -> pid_t? { owners[AXKey(element)] }
        func isValueSettable(on element: AXUIElement) -> Bool { settable }
        func readValue(of element: AXUIElement) throws -> String {
            if writes > 0, let error = readErrorAfterWrite { throw AXValueFailure.read(error.rawValue) }
            guard let text = attribute(kAXValueAttribute, of: element) as? String else { throw AccessError.unreadable }
            return text
        }
        func setValue(_ value: String, on element: AXUIElement) -> AXError {
            writes += 1
            guard setterResult == .success else { return setterResult }
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

    func testSetterErrorCodeIsPreservedInConfirmationDiagnostic() async {
        let fixture = Fixture()
        fixture.runtime.setterResult = .cannotComplete
        let transaction = TextTransaction(access: fixture.access, original: "原始 Prompt 🧑‍💻")
        await expectAsyncThrows(try await transaction.replace(with: "result"))
        if case .setterFailed(let reason) = transaction.confirmationIssue {
            expectTrue(reason.contains("-25204"), "Keep the AX setter code so messaging failure is distinguishable")
        } else { fail("Expected setter diagnostic") }
        expectEqual(transaction.state, .uncertain)
        expectEqual(fixture.runtime.writes, 1)
    }

    func testReadErrorCodeIsPreservedAfterSuccessfulSetter() async {
        let fixture = Fixture()
        fixture.runtime.readErrorAfterWrite = .cannotComplete
        let transaction = TextTransaction(access: fixture.access, original: "原始 Prompt 🧑‍💻")
        await expectAsyncThrows(try await transaction.replace(with: "result"))
        if case .readFailed(let reason) = transaction.confirmationIssue {
            expectTrue(reason.contains("-25204"))
        } else { fail("Expected readback diagnostic") }
        expectEqual(transaction.state, .uncertain)
        expectEqual(fixture.runtime.writes, 1)
    }

    func testPreviewFocusDoesNotInvalidatePinnedField() async throws {
        let fixture = Fixture()
        let transaction = TextTransaction(access: fixture.access, original: "原始 Prompt 🧑‍💻")
        fixture.blurSourceApplication()
        try await transaction.replace(with: "优化后的 Prompt")
        expectEqual(try fixture.access.read(), "优化后的 Prompt")
        try await transaction.undo()
        expectEqual(try fixture.access.read(), "原始 Prompt 🧑‍💻")
    }

    func testOptionalFocusedWindowIsNotRequiredWhenExactFieldIsKnown() throws {
        let fixture = Fixture()
        fixture.runtime.frontmostPID = fixture.access.target.application.processIdentifier
        fixture.runtime.put(kAXFocusedWindowAttribute, nil, on: fixture.app)
        expectEqual(try fixture.access.read(), "原始 Prompt 🧑‍💻")
    }

    func testChangedTextStillBlocksWriteAfterPreviewFocus() async {
        let fixture = Fixture()
        let transaction = TextTransaction(access: fixture.access, original: "原始 Prompt 🧑‍💻")
        fixture.blurSourceApplication()
        fixture.runtime.put(kAXValueAttribute, "用户新增的内容" as CFString, on: fixture.field)
        await expectAsyncThrows(try await transaction.replace(with: "AI text")) { expectEqual($0 as? TransactionError, .contentChanged) }
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

    func testHostedFocusedFieldCanReplaceAndUndoWithoutApplicationFocusAttribute() async throws {
        let fixture = Fixture()
        fixture.runtime.frontmostPID = fixture.access.target.application.processIdentifier
        fixture.runtime.put(kAXFocusedUIElementAttribute, nil, on: fixture.app)
        fixture.runtime.put(kAXFocusedAttribute, kCFBooleanTrue, on: fixture.field)
        let transaction = TextTransaction(access: fixture.access, original: "原始 Prompt 🧑‍💻")
        try await transaction.replace(with: "优化结果")
        expectEqual(try fixture.access.read(), "优化结果")
        try await transaction.undo()
        expectEqual(try fixture.access.read(), "原始 Prompt 🧑‍💻")
    }

    func testHostedFocusFallbackRequiresSameFocusedWindowAndPositiveFieldFocus() {
        let fixture = Fixture()
        fixture.runtime.frontmostPID = fixture.access.target.application.processIdentifier
        fixture.runtime.put(kAXFocusedUIElementAttribute, nil, on: fixture.app)
        fixture.runtime.put(kAXFocusedAttribute, kCFBooleanFalse, on: fixture.field)
        expectThrows(try fixture.access.write("must not write"))
        fixture.runtime.put(kAXFocusedAttribute, kCFBooleanTrue, on: fixture.field)
        fixture.runtime.put(kAXFocusedWindowAttribute, nil, on: fixture.app)
        expectThrows(try fixture.access.write("must not write"))
        expectEqual(fixture.runtime.writes, 0)
    }

    func testExplicitNonTextFocusCannotUsePinnedFallback() {
        let fixture = Fixture()
        fixture.runtime.frontmostPID = fixture.access.target.application.processIdentifier
        fixture.runtime.put(kAXFocusedUIElementAttribute, fixture.otherField, on: fixture.app)
        fixture.runtime.put(kAXRoleAttribute, kAXButtonRole as CFString, on: fixture.otherField)
        fixture.runtime.put(kAXFocusedAttribute, kCFBooleanTrue, on: fixture.field)
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
