# PromptPolish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Build a runnable native macOS menu bar utility that optimizes a focused third-party prompt and safely previews, replaces, and undoes the change.

**Architecture:** A Foundation core owns API validation, requests, and compare-before-write transactions. A main-actor AppKit adapter owns Accessibility elements, a nonactivating floating button, global hotkey, and window lifecycle. SwiftUI provides the approved preview and settings views.

**Tech Stack:** Swift 6 compiler in Swift 5 language mode, macOS 14+, SwiftUI, AppKit, ApplicationServices, Carbon, Security, Foundation, standalone Swift behavior checks. No third-party dependencies. SwiftPM + shell packaging because full Xcode is unavailable.

**Spec:** `/Users/kker/.codex/visualizations/2026/11/05/01a1aa6f-7161-78e3-9e60-61b995615e01/PromptPolish-macOS-UIUX.pen`, approved for implementation by “进行开发吧”.

## Global Constraints

- Independent repository `/Users/kker/jqh/PromptPolish`; leave the Android workspace untouched.
- Default preview before replacing; never send messages or synthesize Return/clipboard paste.
- Keep original snapshots in memory only, expire after 30 minutes or app exit.
- Before replace/undo, require the same live target and exact text match; verify readback; uncertain writes stop automatic retries.
- API Key in Keychain only; no prompt/key logging, no background API requests, no user prompt in connection tests.
- Unsupported and secure fields fail closed. Never claim all Codex/Cursor versions work without live validation.
- Floating UI stays outside the field and screen visible area; shortcut is Command + Shift + E.

## Review Focus

- Target text changes or target disappears during a network request: replacement must refuse to overwrite.
- A target setter errors after partially mutating text: preserve snapshots and block blind retry/undo.
- Async cancellation or out-of-order completion: cancelled work must not reopen UI or auto-replace.
- Expired undo, edited result, Unicode/empty output: protect text and preserve exact whitespace of the original.
- API endpoint mistakes, redirects and malformed/error responses: no credential forwarding, no empty replacement.

### Task 1: Testable core and transactions

Files: `Sources/PromptPolishCore/{Configuration,OptimizationClient,TextTransaction}.swift`; `Tests/PromptPolishCoreTests/*`.

Interfaces: `APIConfiguration.validatedURL()`, `PromptOptimizing.optimize(prompt:configuration:apiKey:instruction:) async throws -> String`; main-actor `TextAccess.read()/write(_:)`; `TextTransaction.replace(with:now:)` and `undo(now:)`.

- [x] Write behavior tests first: configuration parsing, real request construction/response parsing through URLProtocol, original-change guard, partial-write refusal, undo conflict/expiry.
- [x] Run `swift run PromptPolishChecks`; first see missing behavior, then implement the smallest core that passes each case.
- [x] Run full `swift run PromptPolishChecks`, record evidence in progress ledger.

### Task 2: Accessibility and native app integration

Files: `Sources/PromptPolishUI/{AccessibilityService,FloatingButtonController,HotKey,AppModel,AppDelegate,main}.swift`.

Consumes: Task 1 contracts. Produces: detected target capability/rect without passive text capture; explicit capture; transaction access; one cancellable optimization task; menu/status/settings/preview lifecycle.

- [x] Write placement tests for field edges, secondary displays, no available room; verify RED, implement, verify GREEN.
- [x] Implement AXValue read/write only on focused text fields; reject secure, unsupported, attachment-marked, stale/window-switched targets. Require readback for success.
- [x] Register Carbon hotkey, poll target geometry/capability, show nonactivating floating panel with hover/press. Preserve external target across own menu/preview focus.
- [x] Integrate cancellable requests with generation IDs, safe fast replacement and explicit errors; compile using `swift build`.

### Task 3: Approved SwiftUI screens and configuration storage

Files: `Sources/PromptPolishUI/{PreviewView,SettingsView,KeychainStore}.swift`.

Consumes: AppModel and transactions. Produces: editable result/original tabs, regeneration with optional instructions, cancel, replace, undo/conflict recovery; native grouped settings, API test, permission/capability guidance, explicit quick mode opt-in.

- [x] Implement Keychain-backed key storage and explicit save; configuration errors stay in UI; no raw service error response displayed.
- [x] Implement dynamic system appearance, keyboard focus, Command+Return explicit replacement and Escape close; normal Return only edits text.
- [x] Compile app and run core tests; visually check settings/menu and preview where system authorization permits.

### Task 4: Package, verify and review

Files: `Resources/Info.plist`, `scripts/build-app.sh`, `README.md`.

- [x] Build release executable, package `dist/PromptPolish.app`, ad-hoc sign, verify signature and plist. Do not change system privacy grants or publish.
- [x] Launch app; inspect actual native UI via CUA. Perform live AX/API validation only with user-granted permissions/configuration; otherwise state the boundary.
- [x] Run complete test suite and a fresh independent code review of the finished source. Fix important findings with regression tests.
- [x] Deliver runnable `.app`, source, commands and concrete remaining validation needs.

## Acceptance boundary

Build, packaging, native settings and 29 behavior checks are verified. Live Codex/Cursor and real user-provider API acceptance remain explicitly pending; CUA refuses access to the Codex app itself. After refreshing the old authorization entry, the user granted the exact final bundle. Live TextEdit capture succeeds. The agent did not enable any grant or change API credentials; actual external replacement and provider API acceptance remain pending.
