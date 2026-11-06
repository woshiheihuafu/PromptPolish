import SwiftUI
import PromptPolishCore

struct SceneSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedID: UUID?
    private var ids: [UUID] { model.draftSceneConfiguration.scenes.map(\.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("最多配置 5 个场景。悬停优化按钮可选择场景，点击后立即优化。没有场景时不显示选择框。")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(selection: $selectedID) {
                        ForEach(model.draftSceneConfiguration.scenes) { scene in
                            Text(scene.name.isEmpty ? "未命名场景" : scene.name).lineLimit(1).tag(scene.id)
                        }
                    }.listStyle(.sidebar)
                    Divider()
                    HStack {
                        Button { selectedID = model.addScene() } label: { Image(systemName: "plus") }
                            .disabled(ids.count >= SceneConfiguration.maximumCount).accessibilityLabel("添加优化场景")
                        Button {
                            guard let selectedID else { return }
                            model.draftSceneConfiguration.scenes.removeAll { $0.id == selectedID }
                        } label: { Image(systemName: "minus") }
                            .disabled(selectedID == nil).accessibilityLabel("删除所选场景")
                        Spacer()
                        Text("\(ids.count)/5").font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.borderless).padding(10)
                }.frame(width: 170)
                Divider()
                if let selectedID, ids.contains(selectedID) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("场景名称").font(.callout.weight(.medium))
                        TextField("例如：代码评审", text: binding(selectedID, \.name)).textFieldStyle(.roundedBorder)
                        Text("场景提示词").font(.callout.weight(.medium)).padding(.top, 6)
                        TextEditor(text: binding(selectedID, \.systemPrompt)).font(.system(size: 13))
                            .padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.quaternary))
                            .accessibilityLabel("场景独立优化提示词")
                        Text("此提示词会替换全局优化规则。直接点击优化按钮或使用快捷键，仍使用全局规则。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(16).frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2").font(.largeTitle).foregroundStyle(.secondary)
                        Text("添加一个优化场景").font(.headline)
                        Text("可以为开发需求、代码评审等场景设置独立提示词。")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
                }
            }.frame(maxHeight: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.quaternary))
            if let message = model.sceneSettingsMessage { Text(message).font(.callout).textSelection(.enabled) }
            HStack {
                Text("保存后生效").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消") { model.discardSceneDraft(); model.closeSettings() }
                Button("保存") { _ = model.saveScenes() }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
            }.controlSize(.large)
        }.padding(24)
            .onAppear { if selectedID == nil { selectedID = ids.first } }
            .onChange(of: ids) { _, values in if selectedID.map({ !values.contains($0) }) ?? true { selectedID = values.first } }
    }
    private func binding(_ id: UUID, _ path: WritableKeyPath<OptimizationScene, String>) -> Binding<String> {
        Binding(get: { model.draftSceneConfiguration.scenes.first(where: { $0.id == id })?[keyPath: path] ?? "" }, set: { value in
            guard let index = model.draftSceneConfiguration.scenes.firstIndex(where: { $0.id == id }) else { return }
            model.draftSceneConfiguration.scenes[index][keyPath: path] = value
        })
    }
}
