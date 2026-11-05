import AppKit
import ApplicationServices
@testable import PromptPolishCore
@testable import PromptPolishUI

@MainActor
final class AXAttachmentAccessTests {
    final class Runtime: AXRuntime {
        let fixture = AXTextAccessTests.Fixture()
        let imageA = AXUIElementCreateApplication(910_001)
        let imageB = AXUIElementCreateApplication(910_002)
        var document: NSMutableAttributedString
        var selectedRange = NSRange(location: 0, length: 0)
        var rangeSupported = true
        var exposeMetadata = true
        var incorrectSelection = false
        var wholeWrites = 0
        var rangeWrites = 0
        var afterWrite: (() -> Void)?
        var staleReadsAfterWrite = 0
        var afterSnapshot: (() -> Void)?
        var selectionSets = 0
        private var staleReads = 0
        private var previousDocument: NSAttributedString?
        init() {
            document = NSMutableAttributedString(string: "前🧑‍💻\u{FFFC}中\u{FFFC}后")
            document.addAttribute(NSAttributedString.Key(kAXAttachmentTextAttribute.takeUnretainedValue() as String), value: imageA, range: NSRange(location: 6, length: 1))
            document.addAttribute(NSAttributedString.Key(kAXAttachmentTextAttribute.takeUnretainedValue() as String), value: imageB, range: NSRange(location: 8, length: 1))
        }
        var isTrusted: Bool { true }
        var ownPID: pid_t { fixture.runtime.ownPID }
        var frontmostPID: pid_t? { fixture.runtime.frontmostPID }
        func isRunning(_ application: NSRunningApplication) -> Bool { true }
        func processID(of element: AXUIElement) -> pid_t? { fixture.runtime.processID(of: element) }
        func isValueSettable(on element: AXUIElement) -> Bool { true }
        func readValue(of element: AXUIElement) throws -> String { document.string }
        func setValue(_ value: String, on element: AXUIElement) -> AXError { wholeWrites += 1; return .failure }
        func attributedText(of element: AXUIElement) -> NSAttributedString? {
            guard exposeMetadata else { return nil }
            afterSnapshot?()
            if staleReads > 0 { staleReads -= 1; return previousDocument }
            return document.copy() as? NSAttributedString
        }
        func isAttributeSettable(_ name: String, on element: AXUIElement) -> Bool { rangeSupported && [kAXSelectedTextRangeAttribute, kAXSelectedTextAttribute].contains(name) }
        func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
            if CFEqual(element, fixture.field) {
                switch name {
                case kAXValueAttribute: return document.string as CFString
                case kAXSelectedTextAttribute: return (document.string as NSString).substring(with: selectedRange) as CFString
                case kAXSelectedTextRangeAttribute:
                    var range = CFRange(location: selectedRange.location, length: selectedRange.length)
                    return AXValueCreate(.cfRange, &range)
                default: break
                }
            }
            return fixture.runtime.attribute(name, of: element)
        }
        func setAttribute(_ name: String, value: CFTypeRef, on element: AXUIElement) -> AXError {
            if name == kAXSelectedTextRangeAttribute {
                selectionSets += 1
                var range = CFRange()
                guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetValue(value as! AXValue, .cfRange, &range) else { return .illegalArgument }
                selectedRange = NSRange(location: range.location + (incorrectSelection ? 1 : 0), length: range.length)
                return .success
            }
            guard name == kAXSelectedTextAttribute, let text = value as? String else { return .attributeUnsupported }
            previousDocument = document.copy() as? NSAttributedString
            staleReads = staleReadsAfterWrite
            rangeWrites += 1
            document.replaceCharacters(in: selectedRange, with: NSAttributedString(string: text))
            selectedRange = NSRange(location: selectedRange.location + (text as NSString).length, length: 0)
            afterWrite?()
            return .success
        }
    }

    func testOnlyTextRangesAreReplacedAndUndoPreservesAttachmentIdentity() async throws {
        let runtime = Runtime()
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let original = try access.read(), markers = access.protectedMarkers
        let transaction = TextTransaction(access: access, original: original)
        try await transaction.replace(with: "改写前\(markers[0])改写中\(markers[1])改写后")
        expectEqual(try access.read(), "改写前\(markers[0])改写中\(markers[1])改写后")
        expectEqual(runtime.document.string, "改写前\u{FFFC}改写中\u{FFFC}改写后")
        expectEqual(runtime.wholeWrites, 0)
        expectEqual(runtime.rangeWrites, 3)
        try await transaction.undo()
        expectEqual(try access.read(), original)
        expectEqual(runtime.document.string, "前🧑‍💻\u{FFFC}中\u{FFFC}后")
        expectEqual(runtime.wholeWrites, 0)
        expectEqual(runtime.rangeWrites, 6)
    }

    func testWrongSelectionNeverMutatesTextOrImages() async throws {
        let runtime = Runtime()
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let original = try access.read()
        runtime.incorrectSelection = true
        let transaction = TextTransaction(access: access, original: original)
        await expectAsyncThrows(try await transaction.replace(with: original + "改写"))
        expectEqual(runtime.rangeWrites, 0)
        expectEqual(runtime.wholeWrites, 0)
    }

    func testChangedAttachmentIdentityBlocksBeforeWriting() async throws {
        let runtime = Runtime()
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let original = try access.read()
        let transaction = TextTransaction(access: access, original: original)
        runtime.document.addAttribute(NSAttributedString.Key(kAXAttachmentTextAttribute.takeUnretainedValue() as String), value: runtime.imageB, range: NSRange(location: 6, length: 1))
        await expectAsyncThrows(try await transaction.replace(with: original + "改写")) { expectEqual($0 as? AttachmentError, .attachmentsChanged) }
        expectEqual(runtime.rangeWrites, 0)
        expectEqual(runtime.wholeWrites, 0)
    }

    func testMovedNewlineAttachmentStopsRemainingEdits() async throws {
        let runtime = Runtime()
        runtime.document = NSMutableAttributedString(string: "\n\n后")
        let key = NSAttributedString.Key(kAXAttachmentTextAttribute.takeUnretainedValue() as String)
        runtime.document.addAttribute(key, value: runtime.imageA, range: NSRange(location: 0, length: 1))
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let transaction = TextTransaction(access: access, original: try access.read())
        runtime.afterWrite = {
            runtime.document.removeAttribute(key, range: NSRange(location: 0, length: runtime.document.length))
            runtime.document.addAttribute(key, value: runtime.imageA, range: NSRange(location: 1, length: 1))
            runtime.afterWrite = nil
        }
        await expectAsyncThrows(try await transaction.replace(with: access.protectedMarkers[0] + "\n新"))
        expectEqual(transaction.state, .uncertain)
        expectEqual(runtime.rangeWrites, 1, "Do not continue editing when attachment position changes independently")
        expectEqual(runtime.document.string, "\n\n新")
    }

    func testInvalidOutputMarkersAreRejectedBeforeMutation() async throws {
        let runtime = Runtime()
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let transaction = TextTransaction(access: access, original: try access.read())
        await expectAsyncThrows(try await transaction.replace(with: "missing attachments")) { expectEqual($0 as? AttachmentError, .markersChanged) }
        expectEqual(transaction.state, .ready)
        expectEqual(runtime.rangeWrites, 0)
        expectEqual(runtime.wholeWrites, 0)
    }

    func testDelayedRichReadbackDoesNotRepeatRangeWrite() async throws {
        let runtime = Runtime()
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let original = try access.read()
        runtime.staleReadsAfterWrite = 2
        let transaction = TextTransaction(access: access, original: original)
        try await transaction.replace(with: original + "新")
        expectEqual(transaction.state, .replaced)
        expectEqual(runtime.rangeWrites, 1)
        expectEqual(runtime.wholeWrites, 0)
    }

    func testMidWriteNewEditStopsWithoutRetryOrRollback() async throws {
        let runtime = Runtime()
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let transaction = TextTransaction(access: access, original: try access.read())
        runtime.afterWrite = { runtime.document.append(NSAttributedString(string: "用户新编辑")) }
        let value = "前文\(access.protectedMarkers[0])中段\(access.protectedMarkers[1])后文"
        await expectAsyncThrows(try await transaction.replace(with: value))
        expectEqual(transaction.state, .uncertain)
        await expectAsyncThrows(try await transaction.replace(with: value))
        await expectAsyncThrows(try await transaction.undo())
        expectEqual(runtime.rangeWrites, 1)
        expectEqual(runtime.wholeWrites, 0)
        expectTrue(runtime.document.string.hasSuffix("用户新编辑"))
        runtime.afterWrite = nil
    }

    func testPlainWriterRejectsNewInlineAttachmentEvenWhenTextUsesNewline() {
        let runtime = Runtime()
        runtime.document = NSMutableAttributedString(string: "\n文字")
        runtime.document.addAttribute(NSAttributedString.Key(kAXAttachmentTextAttribute.takeUnretainedValue() as String), value: runtime.imageA, range: NSRange(location: 0, length: 1))
        let plain = AXTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        expectThrows(try plain.write("new text"))
        expectEqual(runtime.wholeWrites, 0)
        expectEqual(runtime.document.string, "\n文字")
    }

    func testLiteralImageAndBlankLinesRemainPlainText() throws {
        let runtime = Runtime()
        runtime.document = NSMutableAttributedString(string: "image\n\n哈哈哈哈")
        let captured = try AXTextCapture.capture(target: runtime.fixture.access.target, runtime: runtime)
        expectTrue(captured.0.canWrite)
        expectTrue(captured.2.protectedMarkers.isEmpty)
        expectEqual(captured.1, "image\n\n哈哈哈哈")
    }

    func testStructuredOnlyEditorNeverTreatsHiddenImagesAsPlainValue() async throws {
        let runtime = Runtime()
        runtime.exposeMetadata = false
        runtime.document = NSMutableAttributedString(string: "\n文字")
        let captured = try AXTextCapture.capture(target: runtime.fixture.access.target, runtime: runtime, requiresStructuredContent: true)
        expectFalse(captured.0.canWrite)
        let transaction = TextTransaction(access: captured.2, original: captured.1)
        await expectAsyncThrows(try await transaction.replace(with: "优化文字"))
        expectEqual(runtime.wholeWrites, 0)
        expectEqual(runtime.rangeWrites, 0)
    }

    func testTruncatedAttachmentScanIsPreviewOnly() throws {
        for wide in [false, true] {
            let runtime = Runtime()
            runtime.exposeMetadata = false
            runtime.document = NSMutableAttributedString(string: "\n文字")
            let nodes = (0..<(wide ? 130 : 5)).map { AXUIElementCreateApplication(pid_t(920_000 + $0)) }
            if wide {
                runtime.fixture.runtime.put(kAXChildrenAttribute, nodes as CFArray, on: runtime.fixture.field)
            } else {
                var parent = runtime.fixture.field
                for node in nodes {
                    runtime.fixture.runtime.put(kAXChildrenAttribute, [node] as CFArray, on: parent)
                    parent = node
                }
            }
            runtime.fixture.runtime.put(kAXRoleAttribute, kAXImageRole as CFString, on: nodes.last!)
            let captured = try AXTextCapture.capture(target: runtime.fixture.access.target, runtime: runtime)
            expectFalse(captured.0.canWrite)
            let plain = AXTextAccess(target: runtime.fixture.access.target, runtime: runtime)
            expectThrows(try plain.write("new"))
            expectEqual(runtime.wholeWrites, 0)
        }
    }

    func testSelectionChangeDuringSnapshotIsRejectedBeforeSetter() async throws {
        let runtime = Runtime()
        let access = try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime)
        let original = try access.read()
        runtime.afterSnapshot = {
            if runtime.selectionSets > 0 {
                runtime.selectedRange = NSRange(location: 6, length: 1)
                runtime.afterSnapshot = nil
            }
        }
        let transaction = TextTransaction(access: access, original: original)
        await expectAsyncThrows(try await transaction.replace(with: original + "新"))
        expectEqual(runtime.rangeWrites, 0)
        expectEqual(runtime.document.string, "前🧑‍💻\u{FFFC}中\u{FFFC}后")
    }

    func testUnsupportedRangeAndMissingMetadataNeverFallBackToWholeValue() async throws {
        let runtime = Runtime()
        runtime.rangeSupported = false
        let captured = try AXTextCapture.capture(target: runtime.fixture.access.target, runtime: runtime)
        expectFalse(captured.0.canWrite)
        let transaction = TextTransaction(access: captured.2, original: captured.1)
        await expectAsyncThrows(try await transaction.replace(with: captured.1 + "edit"))
        runtime.rangeSupported = true; runtime.exposeMetadata = false
        expectThrows(try AXAttachmentTextAccess(target: runtime.fixture.access.target, runtime: runtime))
        let unknown = try AXTextCapture.capture(target: runtime.fixture.access.target, runtime: runtime)
        expectFalse(unknown.0.canWrite)
        expectEqual(runtime.rangeWrites, 0)
        expectEqual(runtime.wholeWrites, 0)
    }
}
