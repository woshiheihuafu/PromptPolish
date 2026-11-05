import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var floating: FloatingButtonController!
    private var shortcut: HotKey?
    private var timer: Timer?
    private var settingsWindow: NSWindow?
    private var previewWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let mainMenu = NSMenu()
        let appMenu = NSMenuItem()
        let commands = NSMenu()
        let quit = commands.addItem(withTitle: "退出 PromptPolish", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.submenu = commands
        mainMenu.addItem(appMenu)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        edit.submenu = editMenu; mainMenu.addItem(edit)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        statusItem.menu = menu
        floating = FloatingButtonController(model: model)
        model.showPreview = { [weak self] in self?.openPreview() }
        model.closePreview = { [weak self] in self?.previewWindow?.orderOut(nil) }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.closeSettings = { [weak self] in self?.settingsWindow?.performClose(nil) }
        model.statusChanged = { [weak self] in self?.updateStatus() }
        model.notify = { [weak self] message, undo in self?.floating.showNotice(message, canUndo: undo) }
        shortcut = HotKey { [weak self] in
            Task { @MainActor in self?.model.optimizeFocused() }
        }
        model.shortcutAvailable = shortcut?.register() ?? false
        timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.model.poll(); self?.floating.update() }
        }
        model.poll(); updateStatus()
        if !model.isTrusted || !model.hasKey || model.configuration.model.isEmpty {
            model.selectedSettings = model.isTrusted ? .api : .access
            openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); model.cancelRequest(); model.cancelTest() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openSettings() }
        return true
    }

    private func updateStatus() {
        guard let statusItem else { return }
        let symbol = model.isBusy ? "ellipsis.circle" : (!model.isTrusted ? "sparkles.square.filled.on.square" : "sparkles")
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PromptPolish：\(model.statusText)") ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "PromptPolish")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = "PromptPolish · \(model.statusText) · ⌘ ⇧ E"
        floating?.update()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.poll()
        menu.removeAllItems()
        item(menu, "PromptPolish", nil, enabled: false)
        item(menu, model.statusText, nil, enabled: false)
        menu.addItem(.separator())
        let optimize = item(menu, model.isBusy ? "取消正在进行的优化" : "优化当前输入", #selector(optimizeOrCancel), enabled: model.isBusy || (model.optimizationEnabled && model.detectedTarget != nil && model.isTrusted))
        optimize.keyEquivalent = "e"; optimize.keyEquivalentModifierMask = [.command, .shift]
        item(menu, "目标：\(model.detectedTarget?.name ?? "请先点击输入框")", nil, enabled: false)
        item(menu, model.floatingPaused ? "恢复悬浮按钮" : "暂停悬浮按钮", #selector(toggleFloating))
        item(menu, model.optimizationEnabled ? "暂停全部优化" : "启用优化", #selector(toggleEnabled))
        menu.addItem(.separator())
        item(menu, "最近一次操作", nil, enabled: false)
        item(menu, "查看优化结果…", #selector(showRecent), enabled: model.hasPreview)
        item(menu, "撤销上次替换", #selector(undo), enabled: model.canUndo)
        item(menu, model.canUndo ? "原文临时保留 · 剩余 \(model.undoMinutes) 分钟" : model.lastActionLabel, nil, enabled: false)
        menu.addItem(.separator())
        let settings = item(menu, "设置…", #selector(settings)); settings.keyEquivalent = ","
        item(menu, "权限与应用兼容性…", #selector(accessSettings))
        menu.addItem(.separator())
        let quit = item(menu, "退出 PromptPolish", #selector(quit)); quit.keyEquivalent = "q"
    }

    @discardableResult
    private func item(_ menu: NSMenu, _ title: String, _ action: Selector?, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = enabled; menu.addItem(item)
        return item
    }

    @objc private func optimizeOrCancel() { if model.isBusy { model.cancelRequest() } else { model.optimizeFocused() } }
    @objc private func toggleFloating() { model.floatingPaused.toggle(); floating.update() }
    @objc private func toggleEnabled() { model.optimizationEnabled.toggle(); if !model.optimizationEnabled { model.cancelRequest() }; updateStatus() }
    @objc private func showRecent() { model.showRecent() }
    @objc private func undo() { model.undo() }
    @objc private func settings() { openSettings() }
    @objc private func accessSettings() { model.selectedSettings = .access; openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func openSettings() {
        if settingsWindow == nil {
            let window = window(title: "设置 — PromptPolish", size: NSSize(width: 870, height: 670), minimum: NSSize(width: 800, height: 600))
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func openPreview() {
        if previewWindow == nil {
            let window = window(title: "优化 Prompt — PromptPolish", size: NSSize(width: 920, height: 680), minimum: NSSize(width: 720, height: 540))
            window.contentView = NSHostingView(rootView: PreviewView(model: model))
            previewWindow = window
        }
        previewWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func window(title: String, size: NSSize, minimum: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.minSize = minimum; window.isReleasedWhenClosed = false
        window.delegate = self; window.center()
        window.setFrameAutosaveName(title)
        return window
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === settingsWindow, model.settingsDirty {
            let alert = NSAlert()
            alert.messageText = "保存 AI 服务配置的修改？"
            alert.informativeText = "未保存的配置只会保留在本次窗口中。"
            alert.addButton(withTitle: "保存")
            alert.addButton(withTitle: "放弃修改")
            alert.addButton(withTitle: "取消")
            switch alert.runModal() {
            case .alertFirstButtonReturn: return model.saveConfiguration()
            case .alertSecondButtonReturn: model.discardDraft(); return true
            default: return false
            }
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === previewWindow { model.dismissPreview() }
        if window === settingsWindow { model.discardDraft() }
    }
}
