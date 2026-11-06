import AppKit
import SwiftUI
import QuartzCore
import PromptPolishCore

private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingButtonController {
    enum Surface: Hashable { case button, menu }
    private let model: AppModel
    private let buttonPanel: NSPanel
    let scenePanel: NSPanel
    private let noticePanel: NSPanel
    private let buttonView: FloatingActionView
    private let sceneView: FloatingSceneView
    private let screens: () -> [CGRect]
    private let ownFrontmost: () -> Bool
    private let reduceMotion: () -> Bool
    private(set) var isExpanded = false
    private var hovered = Set<Surface>()
    private var collapseTask: Task<Void, Never>?
    private var layout: FloatingHoverLayout?
    private var lastScenes: [OptimizationScene] = []
    private var lastTarget: AXTarget?
    private var noticeDismiss: DispatchWorkItem?

    init(model: AppModel, screens: @escaping () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) }, ownFrontmost: @escaping () -> Bool = { NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier }, reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.model = model
        self.screens = screens; self.ownFrontmost = ownFrontmost; self.reduceMotion = reduceMotion
        buttonPanel = Self.panel()
        scenePanel = Self.panel()
        noticePanel = Self.panel()
        buttonView = FloatingActionView(); sceneView = FloatingSceneView()
        buttonPanel.contentView = buttonView; scenePanel.contentView = sceneView
        buttonView.action = { [weak self] in self?.hide(); model.optimizeFocused() }
        buttonView.onHover = { [weak self] entered in self?.hoverChanged(.button, entered: entered) }
        sceneView.onHover = { [weak self] entered in self?.hoverChanged(.menu, entered: entered) }
        sceneView.choose = { [weak self] id in self?.hide(); model.optimizeScene(id: id) }
    }

    func update() {
        guard model.optimizationEnabled, model.isTrusted, !model.floatingPaused, !ownFrontmost(), !model.isBusy, !model.isWriting,
              let target = model.detectedTarget,
              let next = FloatingHoverLayout.make(field: target.rect, screens: screens(), sceneCount: model.sceneConfiguration.scenes.count) else { hide(); return }
        let targetChanged = lastTarget.map { !target.sameField(as: $0) } ?? true
        if targetChanged || layout != next || lastScenes != model.sceneConfiguration.scenes {
            collapseTask?.cancel(); hovered.removeAll(); isExpanded = false
            scenePanel.orderOut(nil)
            lastScenes = model.sceneConfiguration.scenes
            sceneView.setScenes(lastScenes)
            layout = next; buttonView.growsLeft = next.growsLeft
            if let menu = next.menu { scenePanel.setFrame(menu, display: false); sceneView.layoutSubtreeIfNeeded() }
            buttonView.setExpanded(false, animated: false)
            buttonPanel.setFrame(next.collapsed, display: true)
        }
        lastTarget = target
        if !buttonPanel.isVisible { buttonPanel.orderFrontRegardless() }
    }

    func hoverChanged(_ surface: Surface, entered: Bool) {
        guard buttonPanel.isVisible, layout != nil else { return }
        if entered {
            hovered.insert(surface); collapseTask?.cancel(); collapseTask = nil
            // Start immediately from the tracking event; no delayed hover/AX work here.
            setExpanded(true)
        } else {
            hovered.remove(surface)
            guard hovered.isEmpty else { return }
            collapseTask?.cancel()
            collapseTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 170_000_000) } catch { return }
                guard let self, self.hovered.isEmpty else { return }
                self.setExpanded(false)
            }
        }
    }

    private func setExpanded(_ value: Bool) {
        guard let layout, isExpanded != value else { return }
        isExpanded = value
        let animated = !reduceMotion()
        buttonView.setExpanded(value, animated: animated)
        let destination = value ? layout.expanded : layout.collapsed
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                buttonPanel.animator().setFrame(destination, display: true)
            }
        } else { buttonPanel.setFrame(destination, display: true) }
        if value, let menu = layout.menu, !lastScenes.isEmpty {
            scenePanel.setFrame(menu, display: true)
            scenePanel.alphaValue = animated ? 0 : 1
            scenePanel.orderFrontRegardless()
            if animated {
                NSAnimationContext.runAnimationGroup { context in context.duration = 0.12; scenePanel.animator().alphaValue = 1 }
            }
        } else { scenePanel.orderOut(nil) }
    }

    func hide() {
        collapseTask?.cancel(); collapseTask = nil; hovered.removeAll()
        isExpanded = false; layout = nil; lastTarget = nil
        buttonView.setExpanded(false, animated: false)
        buttonPanel.orderOut(nil); scenePanel.orderOut(nil)
    }

    func showNotice(_ message: String, canUndo: Bool) {
        noticeDismiss?.cancel()
        noticeDismiss = nil
        let seconds = canUndo ? min(30, max(0, model.replacementNoticeSeconds)) : 10
        guard seconds > 0 else { noticePanel.orderOut(nil); return }
        noticePanel.contentView = NSHostingView(rootView: NoticeView(message: message, canUndo: canUndo, undo: { [weak self] in
            self?.noticePanel.orderOut(nil)
            Task { await self?.model.undo() }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: dismiss)
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
