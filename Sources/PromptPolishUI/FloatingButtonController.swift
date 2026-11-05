import AppKit
import SwiftUI
import PromptPolishCore

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingButtonController {
    private let model: AppModel
    private let buttonPanel: NSPanel
    private let noticePanel: NSPanel
    private var expanded = false
    private var lastRect: CGRect?
    private var noticeDismiss: DispatchWorkItem?

    init(model: AppModel) {
        self.model = model
        buttonPanel = Self.panel()
        noticePanel = Self.panel()
        buttonPanel.contentView = NSHostingView(rootView: FloatingButtonView(action: { [weak model] in model?.optimizeFocused() }, hover: { [weak self] value in self?.setHover(value) ?? false }))
    }

    func update() {
        let ownFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        guard model.optimizationEnabled, model.isTrusted, !model.floatingPaused, !ownFront,
              let target = model.detectedTarget else { buttonPanel.orderOut(nil); return }
        lastRect = target.rect
        positionButton()
    }

    private func setHover(_ value: Bool) -> Bool {
        guard let rect = lastRect else { return false }
        expanded = value && FloatingPlacement.origin(field: rect, visibleFrames: NSScreen.screens.map(\.visibleFrame), size: CGSize(width: 118, height: 32)) != nil
        positionButton()
        return expanded
    }

    private func positionButton() {
        guard let rect = lastRect else { buttonPanel.orderOut(nil); return }
        let size = CGSize(width: expanded ? 118 : 40, height: 32)
        guard let origin = FloatingPlacement.origin(field: rect, visibleFrames: NSScreen.screens.map(\.visibleFrame), size: size) else { buttonPanel.orderOut(nil); return }
        buttonPanel.setFrame(CGRect(origin: origin, size: size), display: true)
        if !model.isBusy { buttonPanel.orderFrontRegardless() } else { buttonPanel.orderOut(nil) }
    }

    func showNotice(_ message: String, canUndo: Bool) {
        noticeDismiss?.cancel()
        noticePanel.contentView = NSHostingView(rootView: NoticeView(message: message, canUndo: canUndo, undo: { [weak self] in
            self?.noticePanel.orderOut(nil); self?.model.undo()
        }, review: { [weak self] in
            guard let self else { return }
            self.noticePanel.orderOut(nil)
            if self.model.hasPreview { self.model.showRecent() }
            else { self.model.showSettings() }
        }, dismiss: { [weak self] in self?.noticePanel.orderOut(nil) }))
        let size = CGSize(width: 440, height: 140)
        let field = model.sessionTarget?.rect ?? model.detectedTarget?.rect
        var origin = field.flatMap { outsideOrigin(field: $0, size: size) }
        if origin == nil, let screen = NSScreen.main {
            let candidate = CGRect(x: screen.visibleFrame.maxX - size.width - 18, y: screen.visibleFrame.maxY - size.height - 18, width: size.width, height: size.height)
            if screen.visibleFrame.contains(candidate), field.map({ !$0.intersects(candidate) }) ?? true { origin = candidate.origin }
        }
        guard let origin else { return }
        noticePanel.setFrame(CGRect(origin: origin, size: size), display: true)
        noticePanel.orderFrontRegardless()
        let dismiss = DispatchWorkItem { [weak self] in self?.noticePanel.orderOut(nil) }
        noticeDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: dismiss)
    }

    private func outsideOrigin(field: CGRect, size: CGSize) -> CGPoint? {
        FloatingPlacement.origin(field: field, visibleFrames: NSScreen.screens.map(\.visibleFrame), size: size)
    }

    private static func panel() -> NSPanel {
        let panel = PassivePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}

private struct FloatingButtonView: View {
    let action: () -> Void
    let hover: (Bool) -> Bool
    @State private var expanded = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                if expanded { Text("优化").font(.system(size: 13, weight: .medium)) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(FloatingStyle(hovered: expanded))
        .onHover { expanded = hover($0) }
        .help("优化 Prompt · ⌘ ⇧ E")
        .accessibilityLabel("优化当前输入框的 Prompt")
    }
}

private struct FloatingStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let hovered: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .background(configuration.isPressed ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(hovered ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.18)))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct NoticeView: View {
    let message: String
    let canUndo: Bool
    let undo: () -> Void
    let review: () -> Void
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: canUndo ? "checkmark.circle" : "info.circle").foregroundStyle(canUndo ? .green : .secondary)
                Text(message).font(.callout).lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭提示")
            }
            HStack {
                Text(canUndo ? "未发送消息" : "可从菜单栏打开设置或结果").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if canUndo { Button("撤销", action: undo).buttonStyle(.borderedProminent) }
                else { Button("查看", action: review) }
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }
}
