# Execution ledger — 2026-11-05 PromptPolish

- User approved development after reviewing the editable design.
- Independent new repository, branch `codex/promptpolish-native`; no Android files modified.
- Native execution: shared safety contracts and UI lifecycle are tightly coupled; implement sequentially and use one independent final review.
- Environment: macOS 26.5.1 arm64, Swift 6.3.2, Command Line Tools; no Xcode. Build via SwiftPM and package an app bundle.
- Pre-flight: Task 2 consumes Task 1 API/TextAccess contracts; Task 3 consumes Task 2 AppModel. No conflicting interfaces.
- Design decisions: direct Accessibility value writes only; controls not declaring AXValue settable remain read-only. No clipboard or synthesized keyboard fallback. Real app compatibility remains a live acceptance item.
- Ruling: `swift test` cannot run because the installed CLT SDK has no XCTest/Testing runtime. Keep the behavior checks in a standalone Swift executable, run via `swift run PromptPolishChecks`; no dependencies or full-Xcode installation required. Cost: a small local check runner rather than Xcode test discovery.

- Task 1 complete: core requests, configuration, strict compare-before-write, partial-write handling, expiry and undo; initial 20 checks passed after missing features were implemented.
- Task 2 complete: native AX adapter, nonactivating button and notifications, Cmd+Shift+E, cancellable request lifecycle. Main-thread native UI compiled and launched.
- Task 3 complete: native settings/preview, editable comparison, regeneration, Keychain integration, explicit quick-mode opt-in. Input labels visually corrected after native screenshot inspection.
- Review: independent gpt-6-astra reviewer audited root commit 57b3c38 read-only; no Critical, 2 Important and 1 editor usability finding initially Minor.
- Review grading: the disappearing editor blocks a normal editing action, so treat it as Important and fix it in the same review pass.
- Final fixed: settings pause leaving in-flight quick replacement active — native AppModel regression failed before fix and passed after shared cancellation and completion gating.
- Final fixed: explicit partial/failed provider responses were accepted — Chat length/content_filter and Responses incomplete/failed/cancelled/in_progress fixtures failed before fix and passed after validation.
- Final fixed: clearing text destroyed the result editor — actual NSHostingView/NSTextView test failed before fix and passed after keeping received-result state separate.
- Additional regressions: strict Unicode code-unit change protection and first manual confirmation before per-process quick replacement each failed before implementation and passed after it.
- Ruling: extract native code into PromptPolishUI, inject accessibility/client/credential/defaults contracts to test real AppModel lifecycle without reading user credentials or changing privacy grants — cost: one local library target, no runtime dependencies.
- Ruling: asynchronous result windows are shown without stealing input focus; explicit menu review activates them — preserves ongoing typing, user clicks the preview to edit.
- Ruling: AX-declared writable controls permit protected manual writes; quick mode additionally requires one successful manual write/readback for that app process in the current session — stricter first-use confirmation, not a claim of universal compatibility.
- No review findings deferred. Remote composition visibility, rich text/attachments, native undo and third-party version compatibility remain documented acceptance boundaries.
- Final automated evidence: swift run PromptPolishChecks — 29 checks, 0 failures. Release package built at dist/PromptPolish.app; plist valid; codesign --verify --deep --strict succeeds.
- Native UI evidence: app launches, API/permission settings render; user granted initial binary Accessibility. Final ad-hoc rebuild changed signature and requires renewed OS authorization, requested from user; agent did not grant it.
- Codex live UI check blocked: CUA explicitly refuses com.openai.codex for safety. Did not attempt another automation path into that app.
- Task 4 implementation/package/review complete; real-provider API and Codex/Cursor live acceptance remain pending, not counted as verified.
- Token accounting for independent review: unavailable (collaboration tool does not expose exact usage). Root usage also unavailable; no estimates made.

- System authorization follow-up: System Settings showed the old PromptPolish grant on while final process remained untrusted. Removed only that stale entry; user completed OS password verification, then user clicked Open for the exact final app path and enabled its grant. Final native UI now reports 已授权. No grant was enabled by the agent.

- Final live evidence: after user completed the current app grant, native UI reports 已授权. User physically focused the isolated plain-text TextEdit document and ran the no-API probe; app displayed 文本编辑：读取成功 · 控件声明支持直接写回，写入后仍需核对. User confirmed 显示读取成功. This verifies real AX capture only, not an actual provider request or external replace/undo.
- Temporary TextEdit test document contains only generated generic Chinese/Emoji text; the pre-existing user document was not modified.
- Final repository kept locally on codex/promptpolish-native; no remote, merge or publication requested.
