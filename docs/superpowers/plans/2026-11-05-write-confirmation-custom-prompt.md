# Write Confirmation and Custom Prompt Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for sequential implementation and red/green checks.

**Goal:** Confirm delayed accessibility writes without repeating them, and allow a saved custom optimizer system prompt.

**Architecture:** Make TextTransaction confirmation asynchronous and read-only, with bounded stale-value polling and explicit failure details. Keep AppModel actions serialized while verifying. Add a backward-compatible prompt field to the existing configuration and edit it in AI settings.

**Tech Stack:** Existing SwiftPM, SwiftUI, AppKit, public Accessibility APIs; macOS 14+.

**Spec:** User reports complete replacement followed by an unconfirmed-write banner and open popup; additionally requests custom optimization instructions. Existing default instructions must remain unchanged.

## Global Constraints

- One write attempt; exact UTF-8 comparison before write, after write and before undo. No normalization, clipboard fallback, repeated setter, rollback or new privacy grants.
- Confirmation polls only the pinned original field; give the main run loop time to process changes. Divergent non-original content stops confirmation; stale original or temporary read failure may be read again for about one second.
- Success closes popup/settings and retains undo; uncertain outcome retains snapshots and a specific safe diagnostic. Closing while checking must not reopen the popup later.
- Settings draft/save/cancel semantics apply to system prompt; older saved API settings migrate without losing URL/model/protocol/key.

## Review Focus

- Source changes or text edits while awaiting confirmation must never be written over (Task 1).
- Undo also needs delayed confirmation, and duplicate click/optimization must not interleave (Task 1).
- User closes popup or API completes while a write is being checked; no stale popup or automatic second write (Task 1).
- Existing saved configurations lack new key, or a custom prompt is whitespace-only (Task 2).
- Both API protocols must send saved system prompt, preserving raw user input and regeneration preference (Task 2).

### Task 1: Delayed readback and accurate outcome

**Files:** TextTransaction.swift; AppModel.swift; AXRuntime.swift; AccessibilityService.swift; PreviewView.swift; AppDelegate.swift; FloatingButtonController.swift; transaction/model/AX/panel tests and runner.

- [x] Reproduce immediate-read false failure using a field whose write is committed but whose read briefly returns the old value; expect successful replace/undo with a single setter each. Add permanent mismatch/read failure and no interleaving/late reopen cases.
- [x] Run `swift run PromptPolishChecks` and observe the intended red regression.
- [x] Use async transaction replace/undo; after successful setter poll stale old value with 100 ms suspension, bounded to about 1.2 seconds; stop on divergent content and keep uncertain state. Separate setter/read/stale/mismatch diagnostic without exposing prompt text.
- [x] Await writes throughout UI/model; publish checking state, block duplicate actions/new capture and show checking status; preserve cancellation and undo.
- [x] Run complete checks; inspect all asynchronous call sites and safety guards.

### Task 2: Configurable optimizer system prompt

**Files:** OptimizationPrompt.swift; Configuration.swift; OptimizationClient.swift; SettingsView.swift; configuration/API/model tests and runner.

- [x] Add red cases for old-config migration, custom-prompt persistence and cancel, empty validation, and custom system messages in both protocols plus regeneration.
- [x] Keep exact old prompt as default; add `APIConfiguration.systemPrompt` and decode fallback. UI editor and restore button modify draft; Save commits, Cancel discards. Reject blank prompt instead of silently overriding.
- [x] Run complete checks and verify default prompt byte-for-byte against prior source.

### Task 3: Review and package

- [x] Review asynchronous lifecycle and diagnostics; document confirmed code defects versus actual Codex evidence and remaining acceptance boundary.
- [x] Run all checks, Release package, plist/signature checks; bump to 1.0.3/build 4. Quit own old app through CUA before packaging; no automated permission changes or Codex operations.
- [x] Commit local changes and deliver app plus concise cause/solution and custom-prompt location.
