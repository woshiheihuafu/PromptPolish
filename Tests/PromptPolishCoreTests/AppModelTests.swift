import AppKit
import SwiftUI
import ApplicationServices
@testable import PromptPolishCore
@testable import PromptPolishUI

actor ControlledOptimizer: PromptOptimizing {
    private var count = 0
    private var pending: [Int: CheckedContinuation<String, Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    func optimize(prompt: String, configuration: APIConfiguration, apiKey: String, instruction: String?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            count += 1
            pending[count] = continuation
            let ready = waiters.filter { $0.0 <= count }
            waiters.removeAll { $0.0 <= count }
            for waiter in ready { waiter.1.resume() }
        }
    }
    func waitForRequests(_ expected: Int) async {
        if count >= expected { return }
        await withCheckedContinuation { waiters.append((expected, $0)) }
    }
    // Deliberately ignores cancellation to simulate a late, uncooperative provider.
    func complete(_ index: Int, with text: String) { pending.removeValue(forKey: index)?.resume(returning: text) }
}

@MainActor
final class AppModelTests {
    final class Field: FocusableTextAccess {
        var text = "原始 Prompt 🧑‍💻"
        var writes = [String]()
        func read() throws -> String { text }
        func write(_ text: String) throws { writes.append(text); self.text = text }
        func restoreFocus() {}
    }
    final class Accessibility: AccessibilityProviding {
        let field = Field()
        var isTrusted = true
        var current: AXTarget?
        init() {
            let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
            current = AXTarget(application: .current, element: element, window: element, canWrite: true, rect: CGRect(x: 10, y: 10, width: 300, height: 100))
        }
        func requestPermission() {}
        func openPermissionSettings() {}
        func refresh() -> AXTarget? { current }
        func capture() throws -> (AXTarget, String, any FocusableTextAccess) { (current!, try field.read(), field) }
    }
    final class Credentials: CredentialStoring {
        var value = "only-a-test-key"
        func load() throws -> String { value }
        func save(_ value: String) throws { self.value = value }
    }
    @MainActor final class Fixture {
        let client = ControlledOptimizer()
        let accessibility = Accessibility()
        let suite = "PromptPolish.Checks.\(UUID().uuidString)"
        let defaults: UserDefaults
        let model: AppModel
        var previews = 0
        init() {
            defaults = UserDefaults(suiteName: suite)!
            defaults.set(try! JSONEncoder().encode(APIConfiguration(baseURL: "https://example.com/v1", model: "test-model")), forKey: "apiConfiguration")
            model = AppModel(client: client, keychain: Credentials(), accessibility: accessibility, defaults: defaults)
            model.showPreview = { [weak self] in self?.previews += 1 }
        }
        func clean() { defaults.removePersistentDomain(forName: suite) }
    }

    func testSettingsPauseCancelsAndRejectsLateQuickReplacement() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.model.quickReplacement = true
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        fixture.model.optimizationEnabled = false
        expectFalse(fixture.model.isBusy)
        await fixture.client.complete(1, with: "late optimized result")
        await request?.value
        expectTrue(fixture.accessibility.field.writes.isEmpty)
        expectEqual(fixture.previews, 0)
        expectEqual(fixture.model.result, "")
    }

    func testDismissedRequestCannotReopenPreview() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        fixture.model.dismissPreview()
        await fixture.client.complete(1, with: "late result")
        await request?.value
        expectEqual(fixture.previews, 0)
        expectEqual(fixture.model.result, "")
        expectTrue(fixture.accessibility.field.writes.isEmpty)
    }

    func testOlderRequestCannotReplaceNewerResult() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.model.optimizeFocused()
        let oldRequest = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        fixture.model.cancelRequest()
        fixture.accessibility.field.text = "new prompt"
        fixture.model.optimizeFocused()
        let currentRequest = fixture.model.optimizationTask
        await fixture.client.waitForRequests(2)
        await fixture.client.complete(2, with: "current result")
        await currentRequest?.value
        await fixture.client.complete(1, with: "obsolete result")
        await oldRequest?.value
        expectEqual(fixture.model.result, "current result")
        expectEqual(fixture.model.original, "new prompt")
        expectEqual(fixture.previews, 1)
    }

    func testInFlightEditPreventsQuickReplacement() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.model.quickReplacement = true
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        fixture.accessibility.field.text = "my newer input"
        await fixture.client.complete(1, with: "AI text")
        await request?.value
        expectFalse(fixture.model.canReplace)
        expectTrue(fixture.accessibility.field.writes.isEmpty)
        expectEqual(fixture.model.result, "AI text")
        expectEqual(fixture.previews, 1)
    }

    func testPreviewReplaceAndUndoThroughNativeModel() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        let original = fixture.accessibility.field.text
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        await fixture.client.complete(1, with: "optimized")
        await request?.value
        expectTrue(fixture.model.canReplace)
        expectTrue(fixture.accessibility.field.writes.isEmpty)
        fixture.model.result = "edited result"
        fixture.model.replace()
        expectEqual(fixture.accessibility.field.text, "edited result")
        expectTrue(fixture.model.canUndo)
        fixture.model.undo()
        expectEqual(fixture.accessibility.field.text, original)
        expectFalse(fixture.model.canUndo)
    }

    func testDeletingResultKeepsNativeTextEditorMounted() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        await fixture.client.complete(1, with: "editable result")
        await request?.value
        _ = NSApplication.shared
        let host = NSHostingView(rootView: PreviewView(model: fixture.model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        expectTrue(hasEditor(host), "Editor should exist after receiving a result")
        fixture.model.result = ""
        host.rootView = PreviewView(model: fixture.model)
        host.layoutSubtreeIfNeeded()
        expectTrue(hasEditor(host), "Deleting all text must keep an editor for typing and undo")
        expectFalse(fixture.model.canReplace)
        window.contentView = nil
    }

    func testQuickModeRequiresSuccessfulManualReplacementFirst() async {
        let fixture = Fixture()
        defer { fixture.clean() }
        fixture.model.quickReplacement = true
        fixture.model.optimizeFocused()
        let first = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        await fixture.client.complete(1, with: "first optimized result")
        await first?.value
        expectTrue(fixture.accessibility.field.writes.isEmpty, "An unverified app must preview before its first write")
        expectEqual(fixture.previews, 1)
        fixture.model.replace()
        expectEqual(fixture.accessibility.field.text, "first optimized result")
        fixture.model.optimizeFocused()
        let second = fixture.model.optimizationTask
        await fixture.client.waitForRequests(2)
        await fixture.client.complete(2, with: "second optimized result")
        await second?.value
        expectEqual(fixture.accessibility.field.text, "second optimized result")
        expectEqual(fixture.previews, 1)
    }

    private func hasEditor(_ view: NSView) -> Bool {
        if let editor = view as? NSTextView, editor.isEditable { return true }
        return view.subviews.contains { hasEditor($0) }
    }
}
