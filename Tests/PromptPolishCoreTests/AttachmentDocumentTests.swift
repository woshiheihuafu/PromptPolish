import Foundation
@testable import PromptPolishCore

final class AttachmentDocumentTests {
    func testUnicodeAndNewlineAttachmentsProduceSafeSegments() throws {
        let document = try AttachmentDocument(text: "🧑‍💻前\n后 image", attachments: [NSRange(location: 6, length: 1)])
        expectEqual(document.segments, ["🧑‍💻前", "后 image"])
        expectEqual(document.segmentRanges, [NSRange(location: 0, length: 6), NSRange(location: 7, length: 7)])
        let marker = document.markers[0]
        expectEqual(document.text, "🧑‍💻前\(marker)后 image")
        expectEqual(try document.segments(in: "改写前\(marker)改写后"), ["改写前", "改写后"])
    }

    func testMissingDuplicatedOrReorderedMarkersAreRejected() throws {
        let document = try AttachmentDocument(text: "A\u{FFFC}B\u{FFFC}C", attachments: [NSRange(location: 1, length: 1), NSRange(location: 3, length: 1)])
        let a = document.markers[0], b = document.markers[1]
        for invalid in ["ABC", "\(a)\(a)\(b)", "\(b)\(a)", "\(a)\u{FFFC}\(b)"] {
            expectThrows(try document.segments(in: invalid))
        }
        expectEqual(try document.segments(in: "X\(a)Y\(b)Z"), ["X", "Y", "Z"])
    }

    func testLiteralImageTextIsNotAnAttachmentAndLabelsAvoidCollisions() throws {
        let plain = try AttachmentDocument(text: "image\n\n哈哈哈哈", attachments: [])
        expectTrue(plain.markers.isEmpty)
        expectEqual(plain.text, "image\n\n哈哈哈哈")
        let document = try AttachmentDocument(text: "⟦保留附件 1⟧\u{FFFC}", attachments: [NSRange(location: 8, length: 1)])
        expectFalse(document.markers.contains("⟦保留附件 1⟧"))
    }

    func testUnmappedOrOverlappingAttachmentRangesAreRejected() {
        expectThrows(try AttachmentDocument(text: "a\u{FFFC}", attachments: []))
        expectThrows(try AttachmentDocument(text: "abcd", attachments: [NSRange(location: 1, length: 2), NSRange(location: 2, length: 1)]))
        expectThrows(try AttachmentDocument(text: "a", attachments: [NSRange(location: 1, length: 1)]))
    }
}
