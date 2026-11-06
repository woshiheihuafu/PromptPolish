import AppKit
import SwiftUI
import PromptPolishCore

@MainActor
class HoverTrackingSurface: NSVisualEffectView {
    var onHover: (Bool) -> Void = { _ in }
    private var area: NSTrackingArea?
    init() {
        super.init(frame: .zero)
        material = .popover; blendingMode = .behindWindow; state = .active
        wantsLayer = true
        layer?.cornerRadius = 10; layer?.masksToBounds = true
        layer?.borderWidth = 0.7; layer?.borderColor = NSColor.separatorColor.cgColor
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateTrackingAreas() {
        if area == nil {
            // inVisibleRect follows the animated bounds without replacing the active
            // tracking region during every animation frame.
            let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(next); area = next
        }
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class FloatingActionView: HoverTrackingSurface {
    var action: () -> Void = {}
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "优化")
    private let button = FirstMouseButton(title: "", target: nil, action: nil)
    var growsLeft = false { didSet { needsLayout = true } }
    override init() {
        super.init()
        icon.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        icon.contentTintColor = .controlAccentColor
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.alignment = .center; titleLabel.alphaValue = 0
        button.isBordered = false; button.setButtonType(.momentaryChange)
        button.target = self; button.action = #selector(pressed)
        button.setAccessibilityLabel("优化当前输入框的 Prompt")
        addSubview(icon); addSubview(titleLabel); addSubview(button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        icon.frame = CGRect(x: growsLeft ? bounds.width - 28 : 12, y: 8, width: 16, height: 16)
        titleLabel.frame = CGRect(x: growsLeft ? 8 : 36, y: 6, width: max(0, bounds.width - 44), height: 20)
        button.frame = bounds
    }
    func setExpanded(_ expanded: Bool, animated: Bool) {
        layer?.borderColor = (expanded ? NSColor.controlAccentColor.withAlphaComponent(0.65) : NSColor.separatorColor).cgColor
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                titleLabel.animator().alphaValue = expanded ? 1 : 0
            }
        } else { titleLabel.alphaValue = expanded ? 1 : 0 }
    }
    @objc private func pressed() { action() }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class FloatingSceneView: HoverTrackingSurface {
    private let host: FirstMouseHostingView<SceneChooserView>
    var choose: (UUID) -> Void = { _ in }
    override init() {
        host = FirstMouseHostingView(rootView: SceneChooserView(scenes: [], choose: { _ in }))
        super.init()
        addSubview(host)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() { super.layout(); host.frame = bounds }
    func setScenes(_ scenes: [OptimizationScene]) {
        host.rootView = SceneChooserView(scenes: scenes, choose: { [weak self] id in self?.choose(id) })
    }
}

private struct SceneChooserView: View {
    let scenes: [OptimizationScene]
    let choose: (UUID) -> Void
    var body: some View {
        VStack(spacing: 2) {
            ForEach(scenes) { scene in SceneRow(scene: scene, choose: choose) }
        }.padding(6)
    }
}

private struct SceneRow: View {
    let scene: OptimizationScene
    let choose: (UUID) -> Void
    @State private var hovered = false
    var body: some View {
        Button { choose(scene.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2").foregroundStyle(.secondary)
                Text(scene.name).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 34)
                .background(hovered ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.accessibilityLabel("使用\(scene.name)场景优化")
    }
}
