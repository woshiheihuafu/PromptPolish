import AppKit
@testable import PromptPolishUI

@MainActor
final class PreviewPanelTests {
    func testDelayedSuccessfulWriteClosesPopupAndRetainsUndo() async {
        _ = NSApplication.shared
        let fixture = AppModelTests.Fixture()
        let presenter = PreviewPanelController(model: fixture.model)
        defer { presenter.hide(); fixture.clean() }
        fixture.model.showPreview = { [weak presenter] in presenter?.show(activate: false) }
        fixture.model.closePreview = { [weak presenter] in presenter?.hide() }
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        await fixture.client.complete(1, with: "complete optimized result")
        await request?.value
        fixture.accessibility.field.staleReadsAfterWrite = 2
        await fixture.model.replace()
        expectEqual(fixture.accessibility.field.text, "complete optimized result")
        expectTrue(presenter.panel?.isVisible == false, "A complete write with delayed readback must close the popup")
        expectTrue(fixture.model.canUndo)
        expectEqual(fixture.accessibility.field.writes, ["complete optimized result"])
    }

    func testSuccessfulReplaceHidesPopupAndSettingsButKeepsUndo() async {
        _ = NSApplication.shared
        let fixture = AppModelTests.Fixture()
        let presenter = PreviewPanelController(model: fixture.model)
        let settings = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        defer { presenter.hide(); settings.orderOut(nil); fixture.clean() }
        fixture.model.showPreview = { [weak presenter] in presenter?.show(activate: false) }
        fixture.model.closePreview = { [weak presenter] in presenter?.hide() }
        fixture.model.replacementSucceeded = { [weak presenter, weak settings] in presenter?.hideAfterReplacement(companion: settings) }
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        expectTrue(presenter.panel?.isVisible == true, "Comparison popup must appear while loading")
        await fixture.client.waitForRequests(1)
        await fixture.client.complete(1, with: "optimized")
        await request?.value
        settings.orderFront(nil)
        expectTrue(settings.isVisible)
        await fixture.model.replace()
        expectFalse(presenter.panel?.isVisible == true)
        expectFalse(settings.isVisible)
        expectTrue(fixture.model.canUndo)
        expectEqual(fixture.accessibility.field.text, "optimized")
    }

    func testBlockedReplaceKeepsResultPopupOpen() async {
        _ = NSApplication.shared
        let fixture = AppModelTests.Fixture()
        let presenter = PreviewPanelController(model: fixture.model)
        defer { presenter.hide(); fixture.clean() }
        fixture.model.showPreview = { [weak presenter] in presenter?.show(activate: false) }
        fixture.model.closePreview = { [weak presenter] in presenter?.hide() }
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        await fixture.client.complete(1, with: "optimized")
        await request?.value
        fixture.accessibility.field.text = "new edit"
        await fixture.model.replace()
        expectTrue(presenter.panel?.isVisible == true)
        expectEqual(fixture.accessibility.field.text, "new edit")
        expectEqual(fixture.model.result, "optimized")
    }

    func testClosingLoadingPopupCancelsLateResult() async {
        _ = NSApplication.shared
        let fixture = AppModelTests.Fixture()
        let presenter = PreviewPanelController(model: fixture.model)
        defer { presenter.hide(); fixture.clean() }
        fixture.model.showPreview = { [weak presenter] in presenter?.show(activate: false) }
        fixture.model.optimizeFocused()
        let request = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        presenter.panel?.performClose(nil)
        await fixture.client.complete(1, with: "late result")
        await request?.value
        expectFalse(fixture.model.isBusy)
        expectFalse(presenter.panel?.isVisible == true)
        expectEqual(fixture.model.result, "")
    }

}
