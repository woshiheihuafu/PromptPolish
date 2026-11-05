# Inline Attachment Preservation Plan

**Approved scope:** Optimize only text in mixed text/image editors; keep original attachment nodes and order. Codex independent attachments need no special transformation. User explicitly prohibits further DingTalk UI operations: development and isolated local tests only; real DingTalk acceptance is manual.

**Design:** Read AX attributed text and AXAttachment references on explicit capture. Produce human-readable protected attachment labels. Use those labels in the text-only model request, validate exact marker count/order, then replace attachment-free selected text ranges from end to start. Round-trip selected range and selected text, recheck complete text/attachment identity before each mutation, and verify every intermediate state asynchronously. Never write whole AXValue for an attachment-bearing session. Missing metadata or range capability permits preview only. Rich mode always previews even if quick mode is enabled.

**Files / tasks (sequential):**

- [x] Core AttachmentDocument: UTF-16 ranges, disjoint attachment spans, stable collision-free labels, exact marker validation, text segments and positions. Tests: Unicode, newline-valued attachment spans, multiple images, labels missing/duplicated/reordered, literal `image` remains ordinary text.
- [x] AX runtime / attachment adapter: attributed text, attribute capability/set boundary; pinned identities, selection verification, reverse edits, asynchronous intermediate confirmation and safe undo. Tests with controlled AX boundary: preserved identities, no whole-value setter, changed attachment/text/selection rejected, partial mutation stops without replay, unsupported metadata/capability preview only.
- [x] Capture/model/preview: allow rich text capture, guarded preview fallback, contract appended only for marker-bearing requests, output validation, rich quick mode disabled, notices and no-API capability description. Existing default optimizer rules untouched. Tests cover API text-only request and invalid marker output.
- [ ] Full checks, fresh read-only review, release build/package 1.1.0/build 7, docs and local commit. Do not interact with DingTalk or Codex. If installed app is running, user quits it before packaging.

**Acceptance boundary:** In-memory real Foundation/AppKit and controlled AX tests verify implementation behavior, not a claim that DingTalk exposes all required attributes. No clipboard reconstruction, image upload, simulated send or destructive fallback. User performs live DingTalk test.
