import AppKit
import ApplicationServices
@testable import PromptPolishCore
@testable import PromptPolishUI

@MainActor
final class FloatingHoverTests {
    let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
    func testExpansionKeepsOriginalHitAreaAndAvoidsInputAtEdges() {
        for field in [CGRect(x: 500, y: 100, width: 630, height: 150), CGRect(x: 0, y: 100, width: 1190, height: 150), CGRect(x: 100, y: 620, width: 700, height: 150)] {
            let layout = FloatingHoverLayout.make(field: field, screens: [screen], sceneCount: 5)!
            expectTrue(layout.expanded.contains(layout.collapsed))
            expectFalse(field.intersects(layout.expanded))
            expectTrue(screen.contains(layout.expanded))
            if let menu = layout.menu {
                expectFalse(menu.intersects(field))
                expectFalse(menu.intersects(layout.expanded))
                expectTrue(screen.contains(menu))
            }
        }
    }
    func testEmptyScenesHaveNoChooserAndNoRoomIsSafe() {
        let field = CGRect(x: 100, y: 100, width: 500, height: 150)
        expectNil(FloatingHoverLayout.make(field: field, screens: [screen], sceneCount: 0)?.menu)
        expectNil(FloatingHoverLayout.make(field: screen, screens: [screen], sceneCount: 5))
        let second = CGRect(x: -1200, y: 0, width: 1200, height: 900)
        let layout = FloatingHoverLayout.make(field: CGRect(x: -1100, y: 100, width: 600, height: 150), screens: [screen, second], sceneCount: 5)!
        expectTrue(second.contains(layout.expanded))
        expectTrue(layout.menu.map(second.contains) ?? false)
    }
    func testHoverImmediatelyShowsConfiguredMenuAndCrossingKeepsItOpen() async {
        _ = NSApplication.shared
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        fixture.model.draftSceneConfiguration.scenes = [OptimizationScene(name: "评审", systemPrompt: "评审规则")]
        expectTrue(fixture.model.saveScenes())
        fixture.model.poll()
        let controller = FloatingButtonController(model: fixture.model, screens: { [self.screen] }, ownFrontmost: { false }, reduceMotion: { true })
        defer { controller.hide() }
        controller.update()
        controller.hoverChanged(.button, entered: true)
        expectTrue(controller.isExpanded)
        expectTrue(controller.scenePanel.isVisible)
        expectNil(fixture.model.optimizationTask)
        expectFalse(controller.scenePanel.canBecomeKey)
        controller.hoverChanged(.button, entered: false)
        controller.hoverChanged(.menu, entered: true)
        try? await Task.sleep(nanoseconds: 230_000_000)
        expectTrue(controller.isExpanded)
        controller.hoverChanged(.menu, entered: false)
        try? await Task.sleep(nanoseconds: 230_000_000)
        expectFalse(controller.isExpanded)
        expectFalse(controller.scenePanel.isVisible)
    }
    func testNoConfiguredScenesDoesNotShowPopup() {
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        fixture.model.poll()
        let controller = FloatingButtonController(model: fixture.model, screens: { [self.screen] }, ownFrontmost: { false }, reduceMotion: { true })
        defer { controller.hide() }
        controller.update()
        controller.hoverChanged(.button, entered: true)
        expectTrue(controller.isExpanded)
        expectFalse(controller.scenePanel.isVisible)
        expectNil(fixture.model.optimizationTask)
    }

    func testNativeTrackingDeliversEntrySynchronouslyForInactiveWindows() {
        let view = FloatingActionView()
        view.frame = CGRect(x: 0, y: 0, width: 40, height: 32)
        view.updateTrackingAreas()
        var entered = false
        view.onHover = { entered = $0 }
        let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
        view.mouseEntered(with: event)
        expectTrue(entered, "Native event must call hover handler without a timer")
        expectTrue(view.trackingAreas.contains { $0.options.contains(.activeAlways) })
    }

    func testReenterDuringCollapseAndPeriodicUpdateKeepMenuExpanded() async {
        _ = NSApplication.shared
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        fixture.model.draftSceneConfiguration.scenes = [OptimizationScene(name: "评审", systemPrompt: "规则")]
        _ = fixture.model.saveScenes(); fixture.model.poll()
        let controller = FloatingButtonController(model: fixture.model, screens: { [self.screen] }, ownFrontmost: { false }, reduceMotion: { false })
        defer { controller.hide() }
        controller.update(); controller.hoverChanged(.button, entered: true)
        controller.hoverChanged(.button, entered: false)
        try? await Task.sleep(nanoseconds: 195_000_000)
        controller.hoverChanged(.button, entered: true)
        controller.update()
        try? await Task.sleep(nanoseconds: 230_000_000)
        expectTrue(controller.isExpanded)
        expectTrue(controller.scenePanel.isVisible)
        expectNil(fixture.model.optimizationTask)
    }

    func testSameGeometryDifferentInputClosesOldChooser() {
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        fixture.model.draftSceneConfiguration.scenes = [OptimizationScene(name: "评审", systemPrompt: "规则")]
        _ = fixture.model.saveScenes(); fixture.model.poll()
        let controller = FloatingButtonController(model: fixture.model, screens: { [self.screen] }, ownFrontmost: { false }, reduceMotion: { true })
        defer { controller.hide() }
        controller.update(); controller.hoverChanged(.button, entered: true)
        expectTrue(controller.scenePanel.isVisible)
        let old = fixture.accessibility.current!
        fixture.accessibility.current = AXTarget(application: old.application, element: AXUIElementCreateApplication(930_001), window: old.window, canWrite: true, rect: old.rect)
        fixture.model.poll(); controller.update()
        expectFalse(controller.isExpanded)
        expectFalse(controller.scenePanel.isVisible)
    }
}
