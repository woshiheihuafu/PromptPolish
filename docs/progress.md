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

## 2026-11-05 — Preview-focus false target-change report

- User reports the generic target/window changed banner specifically after clicking Replace in Codex.
- Root cause reproduced at the adapter boundary: old validation required both source AXFocusedUIElement and AXFocusedWindow even while our preview was foreground. Apple documents application-level focused-window metadata as recommended; pinned AXWindow membership provides the containing-window identity.
- Extracted the OS-only AXRuntime boundary and added adapter+transaction checks (no user prompts, credentials or external AX access in tests). Stable focused-field baseline passed; background blur and missing focused-window regressions failed with targetChanged before the fix.
- Fix: while our preview is foreground, allow absent source focus metadata only for the exact live captured field belonging to the exact captured source window. Reject an explicitly different focused field/window, wrong window membership, foreign foreground app and invalid/secure handles. No fuzzy rebind or clipboard path; exact UTF-8 transaction comparisons unchanged.
- Validation: 39 checks, 0 failures; Release product build passes. A focused independent reviewer reported no important findings.
- Actual Codex acceptance remains pending; CUA restriction against operating Codex remains respected. No assertion of a successful real Codex replacement is made from mocked boundary tests.

- Packaged hotfix as 1.0.1 (bundle build 2); final 39 checks and signature verification pass. Restarted app; its initial Keychain read awaits OS confirmation after the ad-hoc identity changed. SecurityAgent automation was explicitly denied; user handoff requested for Keychain/Accessibility refresh and an actual Codex test, without collecting any API key or attempting another path into SecurityAgent/Codex.

- Hotfix startup follow-up: native settings UI visibly shows version 1.0.1 and connection-test success with the existing configuration. No credential value was inspected or changed. Actual user-driven Codex replacement result is still pending.

## 2026-11-05 — Adjacent comparison popup (1.0.2, build 3)

- User confirmed 1.0.1 replacement succeeds in Codex. Repeated Keychain prompts were resolved by the user choosing Always Allow; no credential caching or security-grant change was introduced.
- Current scope: default comparison, immediate adjacent popup, close prompt/settings UI after successful replacement. User explicitly clarified that optimization rules must remain unchanged; exact existing system prompt documented in `docs/optimization-prompt.md`.
- Replaced the centered preview window and separate loading bubble with one resizable native NSPanel. Normal requests show original/loading immediately without taking input focus; explicit menu review activates the panel. Successful write/readback hides both popup and settings while preserving undo. Blocked writes retain results; closing loading popup rejects late responses.
- Geometry prefers available space outside the composer, clamps to its display, and retains the last matching anchor when source focus changes. Independent read-only review found the stale capture-location fallback after cross-display movement; regression reproduced 1 failure in 50 checks, then passed after retaining the matching position.
- Final behavior verification: 50 checks, 0 failures. Includes actual NSPanel visibility and model lifecycle with controlled input/API boundaries; no user credentials or third-party input were read by tests. Offscreen NSHostingView bitmap exports were incomplete and are not used as visual acceptance evidence.
- Real Codex 1.0.2 placement/fullscreen/Spaces and provider-backed replacement remain user acceptance items. Existing Codex/SecurityAgent automation restrictions remain respected.
- Final package: `bash scripts/build-app.sh` completed Release build, Info.plist validation and strict codesign verification for `dist/PromptPolish.app` (1.0.2/build 3). Old app was quit through its own menu before packaging; new app is ready to reopen. No new OS grant was changed or requested by automation.

## 2026-11-05 — Write confirmation and custom prompt (1.0.3/build 4)

- User reports unconfirmed write plus popup staying open, and explicitly confirms Codex input actually contains the complete optimized text. Added request: user-editable optimizer system prompt.
- Investigation: TextTransaction called the setter then one immediate read, conflating setter failure, unreadable value and mismatch. AppModel correctly closed only on confirmed success, so the popup symptom follows the failed confirmation branch. Source behavior does not prove actual partial write.
- Primary reference: Chromium accessibility overview documents browser-side cache possibly lagging renderer by a fraction of a second; Apple AXUIElementSetAttributeValue lists communication/unsupported/invalid-element failures. Source: https://chromium.googlesource.com/chromium/src/+/main/docs/accessibility/overview.md and https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue . User's exact Codex readback cause remains an inference until live diagnostic evidence; invisible formatting differences/invalid handle/read errors remain alternatives.
- TDD evidence: controlled complete write returning stale text reproduced writeUnconfirmed, visible popup and missing undo (52 checks, 3 assertions failing). After asynchronous read-only confirmation, 52 checks pass. Setter error-code regression then failed before AXValueFailure mapping. Final expanded suite: 61 checks, 0 failures.
- Ruling: keep one setter; retry only reads with up to twelve 100 ms suspensions, stop on a divergent nonoriginal value, compare exact UTF-8 and retain uncertain snapshots. Both replace and undo use the same confirmation. isWriting blocks interleaving; dismissal generation prevents late failure reopening. No normalization/fuzzy rebind/clipboard/automatic rollback.
- Ruling: custom prompt lives in existing APIConfiguration and AI settings draft/save/cancel flow; missing field decodes to exact unchanged legacy default. Empty rules rejected. Request snapshots use saved configuration for both APIs and regeneration. This fulfills the new customization request without altering the default instructions or silently adding numbering rules.
- No user credentials/defaults or third-party input were read in tests; no attempt to automate Codex or OS permission/Keychain prompts. Fresh independent read-only review reported no concrete actionable correctness findings; noted unproven coverage gaps around recovering read errors and delayed undo/dismissal, not observed failures.
- Final evidence: 61 checks, 0 failures; `git diff --check` clean; `bash scripts/build-app.sh` Release build, plist and strict signature verification pass. Packaged at `dist/PromptPolish.app` as 1.0.3/build 4 after quitting the old app through its own menu. Default prompt checked byte-for-byte against 567a069. New package is ready to reopen; current Codex behavior remains a manual acceptance boundary.

## 2026-11-05 — Configurable replacement notice (1.0.4/build 5)

- User requests adjustable replacement-success toast duration. Replaced fixed ten-second success timer with a persisted General setting, 1–30 seconds, default two seconds. Existing unrelated notices retain their timer. Setting applies to subsequent notices; menu undo remains available after dismissal.
- Small reversible preference/UI change; no new tests added. Existing 61 behavior checks pass, Release packaging/plist/strict signature checks pass, and `git diff --check` is clean. Old app quit through its own menu before final packaging. Native duration/setting interaction remains available for user verification on reopening.

## 2026-11-05 — Disable success notice with zero seconds (1.0.5/build 6)

- User clarifies that zero seconds should disable the replacement-success notice. General setting now accepts 0–30 seconds; saved zero remains zero after restart. Zero bypasses notice construction/presentation and hides any previous notice, so there is no flash; menu undo is retained. Default remains two seconds; unrelated notices keep their existing behavior.
- Existing 61 checks pass; Release build, final app packaging/plist and strict signature checks pass. User manually quit old app after CUA reported app state changes; inventory confirmed it was no longer running before packaging. No OS grants or credentials were changed. Native zero-setting interaction remains a user acceptance boundary.

## 2026-11-05 — Inline attachment preservation (1.1.0/build 7)

- User approved scoped development: keep Codex independent attachments unchanged; support rich inline attachments without sending images to AI. User then explicitly prohibited DingTalk UI operations. Before that instruction, assistant opened DingTalk and clicked the displayed test-draft conversation to inspect structure; no input/replacement/send action was performed. Stopped immediately on correction; all subsequent development uses only local source and isolated tests. No further DingTalk/Codex UI operations permitted for this task.
- Architecture: explicit capture reads AX attributed string + AXAttachment object references/ranges. Text-only document uses stable collision-free labels; output requires each label exactly once in order. Rich adapter uses selected text/range APIs only, reverse edits with strict selection/text readback and complete snapshot validation before each mutation, async intermediate verification of text and attachment identities/positions. It never invokes whole-value setter. Unsupported/incomplete metadata/capability permits preview only.
- Plain writer additionally blocks newly added inline objects, including newline-valued images. Bounded descendant scan treats truncation as unknown, not absence. Literal image/blank lines are not attachment heuristics. Images outside the captured input remain outside the scan.
- Default optimizer prompt unchanged; only rich requests append a marker-preservation transport contract. Rich mode always previews, including already verified quick-mode applications. Invalid model/user markers disable replacement while permitting regeneration; changed source recaptures latest text.
- TDD: missing document/adapter initially failed; 65 then 69 checks passed. Adversarial newline-attachment movement and missing rich model contract/quick guard failed (72 checks / 7 assertions), then passed. Four final regressions for scan truncation, selection changes during snapshot, dismissal cancellation and latest-source recovery failed (80 checks / 8 assertions) before fixes; all 80 pass after them.
- Fresh independent read-only reviewer identified truncation P1 and retry recovery P2, and flagged the selection check timing boundary. Fixed with red/green regressions; also added cancellation of remaining multi-range writes when closing/pausing and cancellation checks before mutation. Follow-up review found no additional important regressions.
- Final defensive policy: DingTalk bundle identifiers require structured content; if attachments are invisible in both the plain text and generic child tree, capture still remains preview-only instead of permitting whole-value writes. Additional regression failed for the missing policy, then passed. Full current suite: 81 checks, 0 failures. Default saved optimizer prompt confirmed unchanged against 01c8483. User asked to quit PromptPolish before packaging; current old process still running, so installed app has not been overwritten.
- Local tests use Foundation rich strings and a controlled cross-process AX boundary, not a verified DingTalk implementation. Live metadata availability, preserved attachment appearance/content and undo remain user-only acceptance. No clipboard reconstruction, image upload, real-provider calls or privacy-grant changes in tests. Release package pending.
