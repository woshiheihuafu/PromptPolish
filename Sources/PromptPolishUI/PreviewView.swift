import SwiftUI

struct PreviewView: View {
    @ObservedObject var model: AppModel
    @State private var showRegenerate = false
    @State private var instruction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(.tint)
                Text("优化 Prompt").font(.title2.weight(.semibold))
                Spacer()
                if model.isBusy || model.isWriting { ProgressView().controlSize(.small) }
            }
            Text("目标：\(model.sessionTarget?.name ?? "原应用") · 触发时的输入框")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Picker("显示方式", selection: $model.showComparison) {
                    Text("优化结果").tag(false)
                    Text("原文对比").tag(true)
                }.pickerStyle(.segmented).frame(width: 235)
                Spacer()
                if !model.isBusy && !model.result.isEmpty {
                    Label(model.sessionTarget?.canWrite == true ? "结果可编辑" : "仅可预览", systemImage: model.sessionTarget?.canWrite == true ? "checkmark.circle" : "eye")
                        .font(.caption).foregroundStyle(model.sessionTarget?.canWrite == true ? Color.secondary : Color.orange)
                }
            }
            if let notice = model.contentNotice {
                Label(notice, systemImage: "photo.on.rectangle").font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.message ?? model.resultValidationMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle").font(.callout)
                    HStack {
                        Button(model.retryUsesOriginal ? "重新优化" : "优化最新内容") { model.retryPreview() }
                            .disabled(model.isBusy || model.isWriting)
                        Text("当前输入不会被自动覆盖").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            }
            if let notice = model.quickModeNotice {
                Label(notice, systemImage: "checkmark.shield").font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                if model.showComparison {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("原文").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                        ScrollView {
                            Text(model.original).font(.system(size: 14))
                                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                    }.frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.isBusy ? "正在优化…" : "优化后").font(.callout.weight(.medium)).foregroundStyle(.secondary)
                    if !model.hasReceivedResult {
                        VStack(spacing: 12) {
                            if model.isBusy { ProgressView() } else { Image(systemName: "text.alignleft").font(.largeTitle).foregroundStyle(.tertiary) }
                            Text(model.isBusy ? "正在调用你配置的 AI 服务" : "尚未收到可用结果").foregroundStyle(.secondary)
                            if model.isBusy { Text("可取消请求，原文保持可编辑").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        TextEditor(text: $model.result).font(.system(size: 14))
                            .scrollContentBackground(.hidden).padding(8)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                            .disabled(model.isBusy || model.isWriting)
                            .accessibilityLabel("优化后的 Prompt")
                    }
                }.frame(maxWidth: .infinity)
            }.frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                Button("重新优化") { showRegenerate = true }
                    .disabled(!model.optimizationEnabled || model.isBusy || model.isWriting || model.original.isEmpty || !model.hasPreview)
                    .popover(isPresented: $showRegenerate) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("重新优化").font(.headline)
                            Text("基于原文生成新版本，上一版本临时保留。")
                                .font(.caption).foregroundStyle(.secondary)
                            TextField("补充要求（可选），例如：更简短", text: $instruction, axis: .vertical)
                                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                            HStack {
                                Spacer()
                                Button("取消") { showRegenerate = false }
                                Button("开始优化") { model.regenerate(instruction: instruction); showRegenerate = false }
                                    .buttonStyle(.borderedProminent)
                            }
                        }.padding(18).frame(width: 350)
                    }
                if model.previousResult != nil { Button("上一版本") { model.restorePreviousResult() }.disabled(model.isBusy || model.isWriting) }
                Spacer()
                Button("取消") { model.dismissPreview(); model.closePreview() }.keyboardShortcut(.cancelAction)
                Button(model.isWriting ? "正在确认写回…" : "替换原文") { Task { await model.replace() } }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent).disabled(!model.canReplace)
            }.controlSize(.large)
            Text("只替换输入内容，不发送消息。原文快照最多保留 30 分钟；撤销前会核对是否有新编辑。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(minWidth: 560, minHeight: 400)
    }
}
