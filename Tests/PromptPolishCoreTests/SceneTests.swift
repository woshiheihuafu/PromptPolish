import Foundation
@testable import PromptPolishCore
@testable import PromptPolishUI

@MainActor
final class SceneTests {
    func testSceneLimitAndRequiredFields() throws {
        let five = (1...5).map { OptimizationScene(name: "场景 \($0)", systemPrompt: "规则 \($0)") }
        expectEqual(try SceneConfiguration(scenes: five).validated().scenes.count, 5)
        expectThrows(try SceneConfiguration(scenes: five + [OptimizationScene(name: "第六个", systemPrompt: "规则")]).validated())
        expectThrows(try SceneConfiguration(scenes: [OptimizationScene(name: " \n", systemPrompt: "规则")]).validated())
        expectThrows(try SceneConfiguration(scenes: [OptimizationScene(name: "名称", systemPrompt: " \n")]).validated())
        expectThrows(try SceneConfiguration(scenes: [five[0], five[0]]).validated())
        expectTrue(try SceneConfiguration().validated().scenes.isEmpty)
    }

    func testSceneSettingsPersistAndCancelWithoutAPIChanges() {
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        expectTrue(fixture.model.sceneConfiguration.scenes.isEmpty)
        let global = fixture.model.configuration
        fixture.model.draftSceneConfiguration.scenes = [OptimizationScene(name: "  代码评审  ", systemPrompt: "只改写评审要求。")]
        expectTrue(fixture.model.settingsDirty)
        expectTrue(fixture.model.saveScenes())
        let restored = AppModel(client: fixture.client, keychain: AppModelTests.Credentials(), accessibility: fixture.accessibility, defaults: fixture.defaults)
        expectEqual(restored.sceneConfiguration.scenes.first?.name, "代码评审")
        expectEqual(restored.configuration, global)
        restored.draftSceneConfiguration.scenes.removeAll()
        restored.discardDraft()
        expectEqual(restored.draftSceneConfiguration, restored.sceneConfiguration)
        restored.draftSceneConfiguration.scenes[0].systemPrompt = ""
        expectFalse(restored.saveScenes())
        expectEqual(restored.sceneConfiguration.scenes.first?.systemPrompt, "只改写评审要求。")
    }

    func testSceneRequestRegenerationAndDefaultKeepCorrectPrompt() async {
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        let global = fixture.model.configuration.systemPrompt
        let scene = OptimizationScene(name: "技术说明", systemPrompt: "将需求改写为清晰的技术说明。")
        fixture.model.draftSceneConfiguration.scenes = [scene]
        expectTrue(fixture.model.saveScenes())
        fixture.model.optimizeScene(id: scene.id)
        let first = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        let config = await fixture.client.lastConfiguration
        expectEqual(config?.systemPrompt, "将需求改写为清晰的技术说明。")
        expectEqual(fixture.model.sessionScene?.name, "技术说明")
        await fixture.client.complete(1, with: "first")
        await first?.value
        fixture.model.draftSceneConfiguration.scenes.removeAll()
        expectTrue(fixture.model.saveScenes())
        fixture.model.regenerate(instruction: "更短")
        let second = fixture.model.optimizationTask
        await fixture.client.waitForRequests(2)
        expectEqual(await fixture.client.lastConfiguration?.systemPrompt, "将需求改写为清晰的技术说明。")
        await fixture.client.complete(2, with: "second")
        await second?.value
        fixture.model.optimizeFocused()
        let third = fixture.model.optimizationTask
        await fixture.client.waitForRequests(3)
        expectEqual(await fixture.client.lastConfiguration?.systemPrompt, global)
        expectNil(fixture.model.sessionScene)
        await fixture.client.complete(3, with: "default")
        await third?.value
        expectEqual(fixture.model.configuration.systemPrompt, global)
    }

    func testDeletedSceneDoesNotCaptureOrStartRequest() {
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        fixture.model.optimizeScene(id: UUID())
        expectNil(fixture.model.optimizationTask)
        expectFalse(fixture.model.hasPreview)
        expectTrue(fixture.accessibility.field.writes.isEmpty)
    }

    func testLatestSourceUsesSessionSceneAndAddStopsAtFive() async {
        let fixture = AppModelTests.Fixture()
        defer { fixture.clean() }
        for index in 0..<5 {
            expectTrue(fixture.model.addScene() != nil)
            fixture.model.draftSceneConfiguration.scenes[index].name = "场景\(index)"
        }
        expectNil(fixture.model.addScene())
        expectEqual(fixture.model.draftSceneConfiguration.scenes.count, 5)
        fixture.model.draftSceneConfiguration.scenes[0].systemPrompt = "本次场景规则"
        _ = fixture.model.saveScenes()
        fixture.model.optimizeScene(id: fixture.model.sceneConfiguration.scenes[0].id)
        let first = fixture.model.optimizationTask
        await fixture.client.waitForRequests(1)
        await fixture.client.complete(1, with: "old")
        await first?.value
        fixture.accessibility.field.text = "新的原输入"
        fixture.model.optimizeLatest()
        let next = fixture.model.optimizationTask
        await fixture.client.waitForRequests(2)
        expectEqual(await fixture.client.lastConfiguration?.systemPrompt, "本次场景规则")
        expectEqual(fixture.model.original, "新的原输入")
        await fixture.client.complete(2, with: "new")
        await next?.value
    }
}
