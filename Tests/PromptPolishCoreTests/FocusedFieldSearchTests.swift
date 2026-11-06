import AppKit
import ApplicationServices
@testable import PromptPolishUI

final class FocusedFieldSearchTests {
    final class Tree: PassiveAXReading {
        let pid: pid_t = 954_000
        let app = AXUIElementCreateApplication(954_000)
        let window = AXUIElementCreateApplication(950_000)
        let field = AXUIElementCreateApplication(950_001)
        let other = AXUIElementCreateApplication(950_002)
        var attributes: [AXKey: [String: CFTypeRef]] = [:]
        var failures = Set<AXKey>()
        var requestedKeys = Set<String>()
        var owners: [AXKey: pid_t] = [:]
        var timedNodes: [AXUIElement] = []
        init() {
            put(kAXFocusedWindowAttribute, window, on: app)
            owners[AXKey(window)] = pid
            owners[AXKey(field)] = 954_001 // Hosted content may use another process.
            put(kAXRoleAttribute, kAXWindowRole as CFString, on: window)
            for node in [field, other] {
                put(kAXRoleAttribute, kAXTextAreaRole as CFString, on: node)
                put(kAXWindowAttribute, window, on: node)
                var point = CGPoint(x: 100, y: 200), size = CGSize(width: 600, height: 80)
                put(kAXPositionAttribute, AXValueCreate(.cgPoint, &point), on: node)
                put(kAXSizeAttribute, AXValueCreate(.cgSize, &size), on: node)
            }
            put(kAXFocusedAttribute, kCFBooleanTrue, on: field)
            put(kAXChildrenAttribute, [other, field] as CFArray, on: window)
        }
        func put(_ key: String, _ value: CFTypeRef?, on node: AXUIElement) { attributes[AXKey(node), default: [:]][key] = value }
        func read(_ key: String, _ node: AXUIElement) throws -> CFTypeRef? {
            requestedKeys.insert(key)
            if failures.contains(AXKey(node)) { throw AXValueFailure.read(AXError.cannotComplete.rawValue) }
            return attributes[AXKey(node)]?[key]
        }
        func attribute(_ key: String, _ node: AXUIElement) throws -> CFTypeRef? { try read(key, node) }
        func processID(_ node: AXUIElement) -> pid_t? { owners[AXKey(node)] }
        func isValueSettable(_ node: AXUIElement) -> Bool { true }
        func setTimeout(_ seconds: Float, _ node: AXUIElement) { timedNodes.append(node) }
    }

    func testFindsFocusedTextInsideDeepHostedWindowWithoutReadingText() {
        let tree = Tree()
        var previous = tree.window
        for index in 0..<32 {
            let group = AXUIElementCreateApplication(pid_t(951_000 + index))
            tree.put(kAXRoleAttribute, kAXGroupRole as CFString, on: group)
            tree.put(kAXChildrenAttribute, [group] as CFArray, on: previous)
            previous = group
        }
        tree.put(kAXChildrenAttribute, [tree.other, tree.field] as CFArray, on: previous)
        let result = AXFocusedFieldSearch.find(in: tree.window, read: tree.read)
        expectTrue(result.map { CFEqual($0, tree.field) } ?? false)
        expectFalse(tree.requestedKeys.contains(kAXValueAttribute))
        expectFalse(tree.requestedKeys.contains(kAXSelectedTextAttribute))
    }

    func testRejectsUnfocusedAndAmbiguousFields() {
        let tree = Tree()
        tree.put(kAXFocusedAttribute, kCFBooleanFalse, on: tree.field)
        expectNil(AXFocusedFieldSearch.find(in: tree.window, read: tree.read))
        tree.put(kAXFocusedAttribute, kCFBooleanTrue, on: tree.field)
        tree.put(kAXFocusedAttribute, kCFBooleanTrue, on: tree.other)
        expectNil(AXFocusedFieldSearch.find(in: tree.window, read: tree.read))
    }

    func testRejectsSecureFieldsAndForeignWindowMembership() {
        let tree = Tree()
        tree.put(kAXSubroleAttribute, kAXSecureTextFieldSubrole as CFString, on: tree.field)
        expectNil(AXFocusedFieldSearch.find(in: tree.window, read: tree.read))
        tree.put(kAXSubroleAttribute, nil, on: tree.field)
        tree.put(kAXWindowAttribute, AXUIElementCreateApplication(952_000), on: tree.field)
        expectNil(AXFocusedFieldSearch.find(in: tree.window, read: tree.read))
    }

    func testIncompleteSearchNeverReturnsEarlyCandidate() {
        let tree = Tree()
        tree.put(kAXChildrenAttribute, [tree.field, tree.other] as CFArray, on: tree.window)
        expectNil(AXFocusedFieldSearch.find(in: tree.window, maxNodes: 2, read: tree.read))
        expectNil(AXFocusedFieldSearch.find(in: tree.window, maxDepth: 0, read: tree.read))
        tree.failures.insert(AXKey(tree.other))
        expectNil(AXFocusedFieldSearch.find(in: tree.window, read: tree.read))
    }

    func testCycleDoesNotHideUniqueFocusedField() {
        let tree = Tree()
        tree.put(kAXChildrenAttribute, [tree.window, tree.field] as CFArray, on: tree.window)
        let result = AXFocusedFieldSearch.find(in: tree.window, read: tree.read)
        expectTrue(result.map { CFEqual($0, tree.field) } ?? false)
    }

    func testProbeFindsHostedFieldWhenApplicationAndSystemFocusAreMissing() {
        let tree = Tree()
        let target = SystemPassiveAXProbe.read(tree.pid, reader: tree)
        expectTrue(target.map { CFEqual($0.element, tree.field) && CFEqual($0.window, tree.window) } ?? false)
        expectEqual(target?.rawFrame, CGRect(x: 100, y: 200, width: 600, height: 80))
        expectTrue(target?.canWrite ?? false)
        expectFalse(tree.requestedKeys.contains(kAXValueAttribute))
        let system = AXUIElementCreateSystemWide()
        expectFalse(tree.timedNodes.contains { CFEqual($0, system) })
    }

    func testProbeRevalidatesCachedFocusWhenUserChangesInputs() {
        let tree = Tree()
        let first = SystemPassiveAXProbe.read(tree.pid, reader: tree)
        tree.failures.insert(AXKey(tree.other))
        let cached = SystemPassiveAXProbe.read(tree.pid, preferred: first, reader: tree)
        expectTrue(cached.map { CFEqual($0.element, tree.field) } ?? false)
        tree.failures.removeAll()
        tree.put(kAXFocusedAttribute, kCFBooleanFalse, on: tree.field)
        tree.put(kAXFocusedAttribute, kCFBooleanTrue, on: tree.other)
        let second = SystemPassiveAXProbe.read(tree.pid, preferred: first, reader: tree)
        expectTrue(second.map { CFEqual($0.element, tree.other) } ?? false)
    }

    func testProbeRespectsExplicitNonTextFocusEvenWithCachedTextField() {
        let tree = Tree()
        let first = SystemPassiveAXProbe.read(tree.pid, reader: tree)
        let button = AXUIElementCreateApplication(954_010)
        tree.put(kAXRoleAttribute, kAXButtonRole as CFString, on: button)
        tree.put(kAXFocusedUIElementAttribute, button, on: tree.app)
        expectNil(SystemPassiveAXProbe.read(tree.pid, preferred: first, reader: tree))
    }

    func testProbeRejectsForeignFocusedWindow() {
        let tree = Tree()
        tree.owners[AXKey(tree.window)] = 954_099
        expectNil(SystemPassiveAXProbe.read(tree.pid, reader: tree))
    }
}
