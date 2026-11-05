import AppKit
import SwiftUI
import PromptPolishCore

private final class ComparisonPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PreviewPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private(set) var panel: NSPanel?
    private var lastSession: UUID?
    private var lastAnchor: CGRect?

    init(model: AppModel) { self.model = model }

    func show(activate: Bool) {
        if panel == nil {
            let window = ComparisonPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            window.title = "优化 Prompt"
            window.titlebarAppearsTransparent = true
            window.isFloatingPanel = true
            window.hidesOnDeactivate = false
            window.level = .floating
            window.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: PreviewView(model: model))
            window.delegate = self
            panel = window
        }
        guard let panel else { return }
        let newSession = lastSession != model.previewSessionID
        if newSession || !panel.isVisible {
            position(preferredSize: newSession ? CGSize(width: 720, height: 520) : panel.frame.size)
            lastSession = model.previewSessionID
        }
        if activate {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            // Show beside the composer without taking keystrokes away from the source editor.
            // Clicking this normally activating panel can then focus its editable result.
            panel.orderFrontRegardless()
        }
    }

    func updateAnchor() {
        guard let panel, panel.isVisible, lastAnchor != model.previewAnchorRect else { return }
        position(preferredSize: panel.frame.size)
    }

    func hide() { panel?.orderOut(nil) }

    func hideAfterReplacement(companion: NSWindow?) {
        hide()
        companion?.orderOut(nil)
    }

    private func position(preferredSize: CGSize) {
        guard let panel else { return }
        let anchor = model.previewAnchorRect
        guard let frame = PreviewPlacement.frame(near: anchor, visibleFrames: NSScreen.screens.map(\.visibleFrame), preferredSize: preferredSize) else { return }
        panel.minSize = CGSize(width: min(640, frame.width), height: min(440, frame.height))
        panel.setFrame(frame, display: true)
        lastAnchor = anchor
    }

    func windowWillClose(_ notification: Notification) { model.dismissPreview() }
}
