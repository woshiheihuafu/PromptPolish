import AppKit
import Combine
import PromptPolishCore

@MainActor
final class AppModel: ObservableObject {
    enum SettingsPage: String, CaseIterable { case general = "通用", api = "AI 服务", access = "权限与兼容性", shortcuts = "快捷键" }
    let accessibility: any AccessibilityProviding
    private let client: any PromptOptimizing
    private let keychain: any CredentialStoring
    private let defaults: UserDefaults
    @Published private(set) var configuration: APIConfiguration
    @Published var draftConfiguration: APIConfiguration
    @Published var draftKey = ""
    @Published var selectedSettings: SettingsPage = .api
    @Published var settingsMessage: String?
    @Published var capabilityMessage: String?
    @Published private(set) var hasKey = false
    @Published private(set) var isTrusted = false
    @Published private(set) var isBusy = false
    @Published private(set) var isWriting = false
    @Published private(set) var isTesting = false
    @Published private(set) var detectedTarget: AXTarget?
    @Published private(set) var sessionTarget: AXTarget?
    @Published private(set) var original = ""
    @Published var result = ""
    @Published private(set) var hasReceivedResult = false
    @Published private(set) var quickModeNotice: String?
    @Published private(set) var previousResult: String?
    @Published private(set) var message: String?
    @Published private(set) var successMessage: String?
    @Published private(set) var lastActionLabel = "尚无最近操作"
    @Published var showComparison = true
    @Published private(set) var previewSessionID: UUID?
    @Published private(set) var previewAnchorRect: CGRect?
    @Published var shortcutAvailable = true
    @Published var floatingPaused: Bool { didSet { defaults.set(floatingPaused, forKey: "floatingPaused") } }
    @Published var optimizationEnabled: Bool {
        didSet {
            defaults.set(optimizationEnabled, forKey: "optimizationEnabled")
            if !optimizationEnabled { cancelRequest() }
            statusChanged()
        }
    }
    @Published var quickReplacement: Bool { didSet { defaults.set(quickReplacement, forKey: "quickReplacement") } }
    @Published var replacementNoticeSeconds: Int { didSet { defaults.set(replacementNoticeSeconds, forKey: "replacementNoticeSeconds") } }
    var showPreview: () -> Void = {}
    var focusPreview: () -> Void = {}
    var closePreview: () -> Void = {}
    var replacementSucceeded: () -> Void = {}
    var showSettings: () -> Void = {}
    var closeSettings: () -> Void = {}
    var statusChanged: () -> Void = {}
    var notify: (String, Bool) -> Void = { _, _ in }
    private(set) var optimizationTask: Task<Void, Never>?
    private var testTask: Task<Void, Never>?
    private var requestID: UUID?
    private var testID: UUID?
    private var transaction: TextTransaction?
    private var access: (any FocusableTextAccess)?
    private var undoTransaction: TextTransaction?
    private var undoAccess: (any FocusableTextAccess)?
    private var undoTarget: AXTarget?
    private var replacementBlocked = false
    private var verifiedApplications = Set<pid_t>()
    private var previewDismissalID = UUID()

    init(client: any PromptOptimizing = OptimizationClient(), keychain: any CredentialStoring = KeychainStore(), accessibility: (any AccessibilityProviding)? = nil, defaults: UserDefaults = .standard) {
        self.client = client
        self.keychain = keychain
        self.accessibility = accessibility ?? AccessibilityService()
        self.defaults = defaults
        let saved = defaults.data(forKey: "apiConfiguration").flatMap { try? JSONDecoder().decode(APIConfiguration.self, from: $0) } ?? APIConfiguration()
        configuration = saved
        draftConfiguration = saved
        floatingPaused = defaults.bool(forKey: "floatingPaused")
        optimizationEnabled = defaults.object(forKey: "optimizationEnabled") == nil ? true : defaults.bool(forKey: "optimizationEnabled")
        quickReplacement = defaults.bool(forKey: "quickReplacement")
        replacementNoticeSeconds = defaults.object(forKey: "replacementNoticeSeconds") == nil ? 2 : min(30, max(1, defaults.integer(forKey: "replacementNoticeSeconds")))
        isTrusted = self.accessibility.isTrusted
        do { hasKey = !(try keychain.load()).isEmpty } catch { settingsMessage = error.localizedDescription }
    }

    var settingsDirty: Bool { configuration != draftConfiguration || !draftKey.isEmpty }
    var hasPreview: Bool { transaction != nil }
    var canReplace: Bool {
        optimizationEnabled && !isBusy && !isWriting && !replacementBlocked && transaction?.state == .ready && sessionTarget?.canWrite == true &&
        !(result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && (transaction?.expiresAt ?? .distantPast) > Date()
    }
    var canUndo: Bool { !isWriting && !isBusy && undoTransaction?.state == .replaced && (undoTransaction?.expiresAt ?? .distantPast) > Date() }
    var undoMinutes: Int { max(0, Int((undoTransaction?.expiresAt.timeIntervalSinceNow ?? 0) / 60)) }
    var statusText: String {
        if isWriting { return "正在确认写回…" }
        if !optimizationEnabled { return "优化已暂停" }
        if isBusy { return "正在优化…" }
        if !isTrusted { return "需要辅助功能权限" }
        if !hasKey || configuration.model.isEmpty { return "请配置 AI 服务" }
        return quickReplacement ? "已就绪 · 快速替换" : "已就绪 · 预览后替换"
    }

    func poll() {
        let trusted = accessibility.isTrusted
        if trusted != isTrusted { isTrusted = trusted; statusChanged() }
        detectedTarget = accessibility.refresh()
        if let sessionTarget, let detectedTarget, detectedTarget.sameField(as: sessionTarget) {
            previewAnchorRect = detectedTarget.rect
        }
        if !isWriting, let transaction, transaction.expiresAt <= Date() {
            cancelRequest()
            self.transaction = nil; access = nil; sessionTarget = nil
            previewSessionID = nil
            previewAnchorRect = nil
            original = ""; result = ""; previousResult = nil; hasReceivedResult = false
            message = TransactionError.expired.localizedDescription
        }
        if let undoTransaction, undoTransaction.expiresAt <= Date() {
            self.undoTransaction = nil; undoAccess = nil; undoTarget = nil
            lastActionLabel = "上次操作已过期"
            statusChanged()
        }
    }

    func optimizeFocused() {
        guard !isWriting else { notify("正在确认上次写回，请稍候。", false); return }
        guard optimizationEnabled else { notify("优化已暂停，请从菜单栏或通用设置中开启。", false); return }
        guard !isBusy else { notify("优化仍在进行，可从预览或菜单栏取消。", false); return }
        do {
            let (target, text, access) = try accessibility.capture()
            // Check configuration before discarding an existing preview.
            _ = try configuration.validatedURL()
            let key = try keychain.load()
            guard !key.isEmpty else { throw ConfigurationError.missingKey }
            transaction = TextTransaction(access: access, original: text)
            previewSessionID = UUID()
            self.access = access; sessionTarget = target
            previewAnchorRect = target.rect
            original = text; result = ""; previousResult = nil; hasReceivedResult = false
            replacementBlocked = false; message = nil; successMessage = nil; quickModeNotice = nil
            showComparison = true
            startRequest(key: key, instruction: nil, permitsQuickReplace: true)
        } catch {
            notify(error.localizedDescription, false)
            if error is ConfigurationError { selectedSettings = .api; showSettings() }
            else if case AccessError.permission = error { selectedSettings = .access; showSettings() }
        }
    }

    func regenerate(instruction: String) {
        guard optimizationEnabled, transaction?.state == .ready, !isBusy, !isWriting, !replacementBlocked else { return }
        do { startRequest(key: try keychain.load(), instruction: instruction, permitsQuickReplace: false) }
        catch { message = error.localizedDescription }
    }

    private func startRequest(key: String, instruction: String?, permitsQuickReplace: Bool) {
        cancelRequest()
        let id = UUID(), prompt = original, config = configuration
        requestID = id; isBusy = true; message = nil; successMessage = nil
        let oldResult = result
        let fastPath = permitsQuickReplace && quickReplacement && sessionTarget.map { verifiedApplications.contains($0.application.processIdentifier) } == true
        let presentedBeforeResponse = !fastPath
        statusChanged()
        if presentedBeforeResponse { showPreview() }
        optimizationTask = Task { [weak self, client] in
            do {
                let output = try await client.optimize(prompt: prompt, configuration: config, apiKey: key, instruction: instruction)
                guard let self, !Task.isCancelled, self.requestID == id, self.optimizationEnabled else { return }
                self.requestID = nil; self.isBusy = false; self.optimizationTask = nil
                if !oldResult.isEmpty { self.previousResult = oldResult }
                self.result = output
                self.hasReceivedResult = true
                // The original may have changed while the request was in flight.
                do {
                    guard let current = try self.access?.read(), current.utf8.elementsEqual(self.original.utf8) else { throw TransactionError.contentChanged }
                } catch {
                    self.replacementBlocked = true
                    self.message = error.localizedDescription
                }
                if self.quickReplacement && permitsQuickReplace && self.canReplace,
                   let pid = self.sessionTarget?.application.processIdentifier,
                   self.verifiedApplications.contains(pid) {
                    await self.replace()
                } else {
                    if self.quickReplacement && permitsQuickReplace && self.canReplace {
                        self.quickModeNotice = "本次先预览：该应用完成一次成功的确认替换后，本次会话才会启用快速模式。"
                    }
                    if !presentedBeforeResponse { self.showPreview() }
                }
                self.statusChanged()
            } catch {
                guard let self, !Task.isCancelled, self.requestID == id else { return }
                self.requestID = nil; self.optimizationTask = nil; self.isBusy = false
                self.message = self.friendly(error)
                if !presentedBeforeResponse { self.showPreview() }
                self.statusChanged()
            }
        }
    }

    func cancelRequest() {
        requestID = nil
        optimizationTask?.cancel(); optimizationTask = nil; isBusy = false
        statusChanged()
    }

    func dismissPreview() {
        previewDismissalID = UUID()
        cancelRequest()
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { access?.restoreFocus() }
    }

    func optimizeLatest() { cancelRequest(); optimizeFocused() }

    func restorePreviousResult() {
        guard !isWriting else { return }
        guard let previousResult else { return }
        self.previousResult = result
        result = previousResult
    }

    func replace() async {
        guard canReplace, let transaction else { return }
        isWriting = true
        let dismissalID = previewDismissalID
        statusChanged()
        defer { isWriting = false; statusChanged() }
        do {
            try await transaction.replace(with: result)
            if let pid = sessionTarget?.application.processIdentifier { verifiedApplications.insert(pid) }
            undoTransaction = transaction; undoAccess = access; undoTarget = sessionTarget
            lastActionLabel = "已替换，未发送"
            successMessage = "已替换，未发送"
            closePreview()
            replacementSucceeded()
            access?.restoreFocus()
            notify("已替换，未发送 · 原文最多临时保留 30 分钟", true)
        } catch {
            message = transaction.confirmationIssue?.localizedDescription ?? error.localizedDescription
            replacementBlocked = true
            if dismissalID == previewDismissalID { showPreview() }
        }
        statusChanged()
    }

    func undo() async {
        guard canUndo, let undoTransaction else { return }
        isWriting = true
        let dismissalID = previewDismissalID
        statusChanged()
        defer { isWriting = false; statusChanged() }
        do {
            try await undoTransaction.undo()
            lastActionLabel = "已恢复原文"
            successMessage = "已恢复原文"
            undoAccess?.restoreFocus()
            notify("已恢复原文", false)
        } catch {
            // Show both snapshots without overwriting any newer edit.
            cancelRequest()
            transaction = undoTransaction; access = undoAccess; sessionTarget = undoTarget
            previewSessionID = UUID()
            previewAnchorRect = undoTarget?.rect
            original = undoTransaction.original; result = undoTransaction.replacement ?? ""
            hasReceivedResult = undoTransaction.replacement != nil
            showComparison = true; replacementBlocked = true
            message = "撤销已暂停：\(undoTransaction.confirmationIssue?.localizedDescription ?? error.localizedDescription)"
            if dismissalID == previewDismissalID { showPreview() }
        }
        statusChanged()
    }

    func showRecent() { if hasPreview { focusPreview() } }

    func probeTarget() {
        do {
            let (target, _, _) = try accessibility.capture()
            capabilityMessage = "\(target.name)：读取成功 · \(target.canWrite ? "控件声明支持直接写回，写入后仍需核对" : "仅可预览，替换不可用")"
        } catch { capabilityMessage = error.localizedDescription }
    }

    @discardableResult
    func saveConfiguration() -> Bool {
        do {
            _ = try draftConfiguration.validatedURL()
            let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { try keychain.save(key) }
            hasKey = !(try keychain.load()).isEmpty
            guard hasKey else { throw ConfigurationError.missingKey }
            let data = try JSONEncoder().encode(draftConfiguration)
            defaults.set(data, forKey: "apiConfiguration")
            configuration = draftConfiguration; draftKey = ""
            settingsMessage = "配置已保存"
            statusChanged()
            return true
        } catch { settingsMessage = error.localizedDescription; return false }
    }

    func discardDraft() { cancelTest(); draftConfiguration = configuration; draftKey = ""; settingsMessage = nil }

    func testConnection() {
        guard !isTesting else { return }
        do {
            _ = try draftConfiguration.validatedURL()
            let key = try draftKey.isEmpty ? keychain.load() : draftKey
            guard !key.isEmpty else { throw ConfigurationError.missingKey }
            let id = UUID(), config = draftConfiguration
            testID = id; isTesting = true; settingsMessage = "正在测试连接…"
            testTask = Task { [weak self, client] in
                do {
                    _ = try await client.optimize(prompt: "Connectivity test. Please say OK.", configuration: config, apiKey: key, instruction: nil)
                    guard let self, !Task.isCancelled, self.testID == id else { return }
                    self.settingsMessage = "连接成功 · 模型返回了可用文本"
                    self.finishTest()
                } catch {
                    guard let self, !Task.isCancelled, self.testID == id else { return }
                    self.settingsMessage = self.friendly(error)
                    self.finishTest()
                }
            }
        } catch { settingsMessage = error.localizedDescription }
    }

    func cancelTest() { testTask?.cancel(); finishTest() }
    private func finishTest() { testID = nil; testTask = nil; isTesting = false }
    private func friendly(_ error: Error) -> String {
        if let error = error as? URLError {
            return error.code == .timedOut ? "服务响应超时，请稍后重试。" : "无法连接 AI 服务，请检查网络、Base URL 或本机服务。"
        }
        return error.localizedDescription
    }
}
