import AppKit
import ApplicationServices
import PromptPolishCore

@MainActor
private struct AttachmentSnapshot {
    let document: AttachmentDocument
    let elements: [AXUIElement]
    init(_ value: NSAttributedString, markers: [String]? = nil) throws {
        var ranges = [NSRange](), nodes = [AXUIElement](), invalid = false
        value.enumerateAttribute(NSAttributedString.Key(kAXAttachmentTextAttribute.takeUnretainedValue() as String), in: NSRange(location: 0, length: value.length)) { object, range, _ in
            guard let object else { return }
            let ref = object as CFTypeRef
            guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { invalid = true; return }
            ranges.append(range); nodes.append(ref as! AXUIElement)
        }
        guard !invalid else { throw AttachmentError.unknownStructure }
        document = try AttachmentDocument(text: value.string, attachments: ranges, markers: markers)
        elements = nodes
    }
    func hasSameAttachments(as other: Self) -> Bool {
        elements.count == other.elements.count && zip(elements, other.elements).allSatisfy { CFEqual($0, $1) }
    }
    func exactlyMatches(_ other: Self) -> Bool {
        hasSameAttachments(as: other) && document.attachmentRanges == other.document.attachmentRanges && document.rawText.utf8.elementsEqual(other.document.rawText.utf8)
    }
}

/// A rich editor is changed exclusively through attachment-free selected text ranges.
@MainActor
final class AXAttachmentTextAccess: FocusableTextAccess {
    private let plain: AXTextAccess
    private let runtime: any AXRuntime
    private let baseline: AttachmentSnapshot
    var protectedMarkers: [String] { baseline.document.markers }
    var canWrite: Bool {
        runtime.isAttributeSettable(kAXSelectedTextRangeAttribute, on: plain.target.element) && runtime.isAttributeSettable(kAXSelectedTextAttribute, on: plain.target.element)
    }
    var contentNotice: String? { canWrite ? "图文模式：只改文字，原附件留在输入框。请保留所有附件标记。" : "已识别内嵌附件，但此输入框不支持可靠的局部写回；可优化预览。" }

    init(target: AXTarget, runtime: any AXRuntime) throws {
        self.runtime = runtime
        plain = AXTextAccess(target: target, runtime: runtime)
        try plain.validate()
        guard let value = runtime.attributedText(of: target.element) else { throw AttachmentError.unknownStructure }
        baseline = try AttachmentSnapshot(value)
        guard !baseline.elements.isEmpty else { throw AttachmentError.unknownStructure }
    }

    private func current() throws -> AttachmentSnapshot {
        try plain.validate()
        guard let value = runtime.attributedText(of: plain.target.element) else { throw AttachmentError.unknownStructure }
        let snapshot = try AttachmentSnapshot(value, markers: protectedMarkers)
        guard snapshot.hasSameAttachments(as: baseline) else { throw AttachmentError.attachmentsChanged }
        return snapshot
    }

    func read() throws -> String { try current().document.text }
    func validateReplacement(_ text: String) throws { _ = try baseline.document.segments(in: text) }
    func restoreFocus() { plain.restoreFocus() }

    func write(_ text: String) async throws {
        guard canWrite else { throw AttachmentError.rangeUnavailable }
        let desired = try baseline.document.segments(in: text)
        var snapshot = try current()
        // Reverse order keeps the not-yet-edited prefix and all original image nodes intact.
        for index in desired.indices.reversed() {
            try Task.checkCancellation()
            guard !snapshot.document.segments[index].utf8.elementsEqual(desired[index].utf8) else { continue }
            let live = try current()
            guard live.exactlyMatches(snapshot) else { throw TransactionError.contentChanged }
            let range = snapshot.document.segmentRanges[index]
            var selection = CFRange(location: range.location, length: range.length)
            guard let encoded = AXValueCreate(.cfRange, &selection),
                  runtime.setAttribute(kAXSelectedTextRangeAttribute, value: encoded, on: plain.target.element) == .success else { throw AttachmentError.selectionMismatch }
            guard try current().exactlyMatches(snapshot) else { throw TransactionError.contentChanged }
            guard let selected = runtime.attribute(kAXSelectedTextRangeAttribute, of: plain.target.element), CFGetTypeID(selected) == AXValueGetTypeID() else { throw AttachmentError.selectionMismatch }
            var roundTrip = CFRange()
            guard AXValueGetValue(selected as! AXValue, .cfRange, &roundTrip), roundTrip.location == selection.location, roundTrip.length == selection.length,
                  let selectedText = runtime.string(kAXSelectedTextAttribute, of: plain.target.element), selectedText.utf8.elementsEqual(snapshot.document.segments[index].utf8) else { throw AttachmentError.selectionMismatch }
            var expectedSegments = snapshot.document.segments
            expectedSegments[index] = desired[index]
            let expectedText = snapshot.document.rawText(with: expectedSegments)
            let delta = (desired[index] as NSString).length - range.length
            let expectedRanges = snapshot.document.attachmentRanges.enumerated().map { offset, span in
                NSRange(location: span.location + (offset >= index ? delta : 0), length: span.length)
            }
            let error = runtime.setAttribute(kAXSelectedTextAttribute, value: desired[index] as CFString, on: plain.target.element)
            guard error == .success else { throw AXValueFailure.write(error.rawValue) }
            var confirmed: AttachmentSnapshot?
            for attempt in 0...12 {
                let observed = try current()
                if observed.document.rawText.utf8.elementsEqual(expectedText.utf8) {
                    guard observed.document.attachmentRanges == expectedRanges else { throw AttachmentError.attachmentsChanged }
                    confirmed = observed; break
                }
                guard observed.exactlyMatches(snapshot) else { throw TransactionError.writeUnconfirmed }
                if attempt < 12 { try await Task.sleep(nanoseconds: 100_000_000) }
            }
            guard let confirmed else { throw TransactionError.writeUnconfirmed }
            snapshot = confirmed
        }
    }
}

@MainActor
final class AXPreviewOnlyTextAccess: FocusableTextAccess {
    private let plain: AXTextAccess
    init(_ plain: AXTextAccess) { self.plain = plain }
    var contentNotice: String? { "无法确认此输入框的附件边界；本次仅优化预览，不写回。" }
    func read() throws -> String { try plain.read().replacingOccurrences(of: "\u{FFFC}", with: "⟦未解析附件⟧") }
    func write(_ text: String) throws { throw AttachmentError.unknownStructure }
    func restoreFocus() { plain.restoreFocus() }
}

@MainActor
enum AXTextCapture {
    static func capture(target: AXTarget, runtime: any AXRuntime, requiresStructuredContent: Bool? = nil) throws -> (AXTarget, String, any FocusableTextAccess) {
        // DingTalk can omit inline images from its plain string entirely. Without
        // structured attachment metadata, absence of a placeholder proves nothing.
        let requiresStructure = requiresStructuredContent ?? target.bundleID.lowercased().contains("dingtalk")
        let plain = AXTextAccess(target: target, runtime: runtime)
        try plain.validate()
        let access: any FocusableTextAccess
        let writable: Bool
        if let rich = try? AXAttachmentTextAccess(target: target, runtime: runtime) {
            access = rich; writable = rich.canWrite
        } else if try requiresStructure || runtime.hasInlineObjects(in: target.element) || plain.read().contains("\u{FFFC}") {
            access = AXPreviewOnlyTextAccess(plain); writable = false
        } else { access = plain; writable = target.canWrite }
        let text = try access.read()
        let onlyText = access is AXPreviewOnlyTextAccess ? try plain.read().replacingOccurrences(of: "\u{FFFC}", with: "") : access.protectedMarkers.reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
        guard !onlyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OptimizationError.emptyPrompt }
        guard text.utf8.count <= 200_000 else { throw OptimizationError.tooLarge }
        let captured = AXTarget(application: target.application, element: target.element, window: target.window, canWrite: writable, rect: target.rect)
        return (captured, text, access)
    }
}
