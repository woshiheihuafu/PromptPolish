import SwiftUI
import PromptPolishCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var showKey = false
    @State private var confirmQuick = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("PromptPolish").font(.headline).padding(.bottom, 20).padding(.leading, 8)
                ForEach(AppModel.SettingsPage.allCases, id: \.self) { page in
                    Button { model.selectedSettings = page } label: {
                        Label(page.rawValue, systemImage: icon(page))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 9)
                            .background(model.selectedSettings == page ? Color.accentColor.opacity(0.20) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("版本 1.0.0 · 本地构建").font(.caption2).foregroundStyle(.secondary).padding(.leading, 8)
            }.padding(16).frame(width: 175).background(.ultraThinMaterial)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(model.selectedSettings.rawValue).font(.title2.weight(.semibold)).padding(.horizontal, 28).padding(.top, 24)
                switch model.selectedSettings {
                case .general: general
                case .api: api
                case .access: access
                case .shortcuts: shortcuts
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.frame(minWidth: 800, minHeight: 600)
    }

    private var api: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text("连接你自己的 AI 服务，仅在主动优化时发送当前 Prompt。")
                        .font(.callout).foregroundStyle(.secondary)
                    LabeledContent("服务类型", value: "OpenAI 兼容 API")
                }
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("API Key").font(.callout.weight(.medium))
                        HStack {
                            Group {
                                if showKey { TextField(keyPlaceholder, text: $model.draftKey) }
                                else { SecureField(keyPlaceholder, text: $model.draftKey) }
                            }.textFieldStyle(.roundedBorder).labelsHidden()
                            Button { showKey.toggle() } label: { Image(systemName: showKey ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless).help(showKey ? "隐藏密钥" : "显示本次输入的密钥")
                        }
                        Text("保存后存入 macOS 钥匙串；不写入普通配置和日志。").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Base URL").font(.callout.weight(.medium))
                        TextField("https://api.example.com/v1", text: $model.draftConfiguration.baseURL).textFieldStyle(.roundedBorder).labelsHidden()
                        Text("填写 API 根路径，不包含 chat/completions 或 responses。").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("模型 ID").font(.callout.weight(.medium))
                        TextField("输入服务商提供的完整模型 ID", text: $model.draftConfiguration.model).textFieldStyle(.roundedBorder).labelsHidden()
                    }.padding(.vertical, 3)
                    Picker("API 协议", selection: $model.draftConfiguration.apiProtocol) {
                        ForEach(PromptPolishCore.APIProtocol.allCases, id: \.self) { item in Text(item.title).tag(item) }
                    }
                }
                Section {
                    HStack {
                        if model.isTesting { ProgressView().controlSize(.small) }
                        Text(model.settingsMessage ?? "尚未测试连接").font(.callout).textSelection(.enabled)
                    }
                    Text("连接测试只发送固定短文本，不读取当前输入框，也不会保存尚未提交的配置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).scrollBounceBehavior(.basedOnSize)
            Divider()
            HStack {
                Button(model.isTesting ? "取消测试" : "测试连接") {
                    if model.isTesting { model.cancelTest() } else { model.testConnection() }
                }
                Spacer()
                Button("取消") { model.discardDraft(); model.closeSettings() }
                Button("保存") { _ = model.saveConfiguration() }
                    .keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent).disabled(model.isTesting)
            }.controlSize(.large).padding(20)
        }
    }

    private var general: some View {
        Form {
            Section("优化入口") {
                Toggle("启用 Prompt 优化", isOn: $model.optimizationEnabled)
                Toggle("显示输入框外侧的悬浮按钮", isOn: Binding(get: { !model.floatingPaused }, set: { model.floatingPaused = !$0 }))
                Text("按钮不会遮挡输入和发送操作；没有可用空间时仅保留快捷键。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("替换方式") {
                Toggle("优化完成后快速替换", isOn: Binding(get: { model.quickReplacement }, set: { value in
                    if value { confirmQuick = true } else { model.quickReplacement = false }
                }))
                Text("默认先预览后替换。每个应用在本次会话完成一次成功的确认替换后，快速模式才会跳过预览；始终不发送消息，原文或目标变化时暂停替换。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("隐私与撤销") {
                LabeledContent("原文保留", value: "内存中最多 30 分钟，退出即清除")
                Text("不默认保存 Prompt 历史；不使用剪贴板兜底，不模拟全选或发送按键。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
            .confirmationDialog("开启快速替换？", isPresented: $confirmQuick, titleVisibility: .visible) {
                Button("开启快速替换") { model.quickReplacement = true }
                Button("取消", role: .cancel) {}
            } message: { Text("优化完成即写回原输入框。仅对声明支持直接写回的控件生效；写入后核对，支持撤销。") }
    }

    private var access: some View {
        Form {
            Section("辅助功能") {
                Label(model.isTrusted ? "已授权" : "需要辅助功能权限", systemImage: model.isTrusted ? "checkmark.shield" : "lock.shield")
                Text("用于读取你主动触发的输入框并写回结果。安全输入框不读取；不申请屏幕录制权限。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("请求辅助功能权限") { model.accessibility.requestPermission() }
                    Button("打开系统设置") { model.accessibility.openPermissionSettings() }
                    Button("重新检测") { model.poll() }
                }
            }
            Section("当前输入框") {
                LabeledContent("应用", value: model.detectedTarget?.name ?? "请先点击原应用输入框")
                if let target = model.detectedTarget {
                    LabeledContent("直接写回能力", value: target.canWrite ? "控件声明可写 · 执行后核对" : "不可用 · 仅预览")
                }
                Button("检测当前输入框（不发送 API）") { model.probeTarget() }.disabled(!model.isTrusted)
                if let message = model.capabilityMessage { Text(message).font(.callout).textSelection(.enabled) }
            }
            Section("兼容性边界") {
                Text("Codex Desktop、Cursor 等应用的不同版本可能提供不同的辅助功能能力。无法读取时停止优化；无法可靠写回时只允许预览。")
                Text("请先提交中文输入法的候选文字，再触发优化。第三方应用未必公开组合输入状态。含附件标记的文本不替换；原生 ⌘Z 需逐应用验证，请优先使用本工具的「撤销上次替换」。")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("全局快捷键") {
                LabeledContent("优化当前输入", value: "⌘ ⇧ E")
                Label(model.shortcutAvailable ? "快捷键已注册" : "快捷键被其他应用占用，可使用悬浮按钮", systemImage: model.shortcutAvailable ? "checkmark.circle" : "exclamationmark.triangle")
            }
            Section("结果预览窗口") {
                LabeledContent("替换原文", value: "⌘ Return")
                LabeledContent("关闭预览 / 取消请求", value: "Esc")
                LabeledContent("普通 Return", value: "只编辑结果，不执行替换")
            }
        }.formStyle(.grouped)
    }

    private var keyPlaceholder: String { model.hasKey ? "密钥已保存；留空保持不变" : "输入 API Key" }
    private func icon(_ page: AppModel.SettingsPage) -> String {
        switch page { case .general: return "slider.horizontal.3"; case .api: return "sparkles"; case .access: return "checkmark.shield"; case .shortcuts: return "keyboard" }
    }
}

