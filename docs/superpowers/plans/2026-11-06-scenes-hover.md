# Scenario Selection and Immediate Hover Plan

**Goal:** Hover immediately expands the optimization button and shows configured scene choices; click one to optimize with that scene's independent system prompt. At most five configurable scenes; zero scenes means no chooser. Default click/shortcut keeps global prompt. Regeneration keeps the selected scene snapshot.

**Execution:** Native sequential implementation on `codex/scenario-hover`, red/green behavior checks, fresh read-only final review. User's explicit requirements and independent-prompt answer authorize implementation. Do not operate DingTalk or Codex, do not reintroduce inline attachments, and do not publish a new release without a separate request.

**Architecture:** Separate persisted SceneConfiguration draft/save state, AppModel session-scene snapshot, anchored button/menu geometry, and native tracking/animation. Passive AX geometry reads move to a coalescing serial worker; fresh explicit captures and strict replacement checks remain unchanged. Hover never reads prompt text or calls API.

## Tasks

- [x] Scene model/config/settings: names + independent prompts; validate at most five, nonblank fields and unique identities; no default scenes, preserve old configuration. Add/edit/delete/save/cancel in a dedicated settings page. Scene click directly invokes optimization; regenerated and latest-source retries preserve chosen scene, new default optimization clears it. Tests cover persistence, limits, invalid/removed scene identities, per-request config and unchanged global config.
- [x] Geometry and native Hover: reserve stable expansion side before presenting collapsed button, keep collapsed area within expansion, place chooser outside input on same display. Active-always NSTrackingArea, immediate expansion (~180 ms easing), cancellable short exit grace for crossing into chooser, no API on hover, nonactivating panels retain source focus. Respect Reduce Motion. Tests cover edges, no-space/menu-hidden case, pointer transition and cancelled collapse.
- [x] Passive probe worker: no cross-process AX reads in main-thread periodic refresh. Capture fresh on explicit optimize, coalesce polling, reject stale app results, maintain current pinned target while our popup is focused. Tests prove pending/coalescing/cancel behavior with fake worker only; current replacement safety tests remain.
- [x] Full checks, local native fixture validation, independent review, update docs and package 1.1.0/build 8. Actual third-party hover latency/Spaces acceptance remains manual. If PromptPolish is running, ask user to quit before replacing app.

## Review Focus

- Chooser must not steal focus or collapse during button-to-menu movement; no invisible large hit area over the input.
- Reversing hover mid-animation must interrupt smoothly, not queue frames or relocate the hot area.
- Deleted or invalid scene cannot silently fall back to a different prompt; no key/prompt in logs.
- A delayed passive probe cannot overwrite a newer foreground target/capture or backlog the UI.
- Main-thread UI responsiveness requires no passive AX work there; exact comparison/readback/undo safeguards remain intact.
