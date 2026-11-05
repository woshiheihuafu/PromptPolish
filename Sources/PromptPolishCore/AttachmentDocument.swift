import Foundation

public enum AttachmentError: LocalizedError, Equatable {
    case unknownStructure, markersChanged, attachmentsChanged, selectionMismatch, rangeUnavailable
    public var errorDescription: String? {
        switch self {
        case .unknownStructure: return "无法确定附件与文字的边界，此内容仅支持优化预览。"
        case .markersChanged: return "附件保留标记被删除、重复或调整了顺序。请保留标记后再替换，或重新优化。"
        case .attachmentsChanged: return "原输入框的附件或图文结构已变化，已暂停写回。"
        case .selectionMismatch: return "输入框返回的文字选区与预期不一致，已停止写入。"
        case .rangeUnavailable: return "此输入框不支持可验证的局部文字替换，仅支持预览。"
        }
    }
}

/// Text-only projection of a rich editor. Attachment spans remain owned by the source app.
public struct AttachmentDocument {
    public let rawText: String
    public let attachmentRanges: [NSRange]
    public let markers: [String]
    public let segments: [String]
    public let segmentRanges: [NSRange]
    public var text: String { interleave(segments, with: markers) }
    public var hasText: Bool { segments.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    public init(text: String, attachments: [NSRange], markers: [String]? = nil) throws {
        let source = text as NSString
        var cursor = 0, ranges = [NSRange](), pieces = [String]()
        for range in attachments {
            guard range.location >= cursor, range.length > 0, range.location <= source.length,
                  range.length <= source.length - range.location, Range(range, in: text) != nil else { throw AttachmentError.unknownStructure }
            let gap = NSRange(location: cursor, length: range.location - cursor)
            ranges.append(gap); pieces.append(source.substring(with: gap))
            cursor = NSMaxRange(range)
        }
        let tail = NSRange(location: cursor, length: source.length - cursor)
        ranges.append(tail); pieces.append(source.substring(with: tail))
        guard !pieces.contains(where: { $0.contains("\u{FFFC}") }) else { throw AttachmentError.unknownStructure }
        let labels: [String]
        if let markers {
            guard markers.count == attachments.count, Set(markers).count == markers.count,
                  markers.allSatisfy({ !$0.isEmpty }) else { throw AttachmentError.unknownStructure }
            labels = markers
        } else {
            var generated = [String](), index = 1
            while generated.count < attachments.count {
                let candidate = "⟦保留附件 \(index)⟧"
                if !text.contains(candidate) { generated.append(candidate) }
                index += 1
            }
            labels = generated
        }
        rawText = text; attachmentRanges = attachments
        self.markers = labels; segments = pieces; segmentRanges = ranges
        _ = try self.segments(in: self.text)
    }

    public func segments(in replacement: String) throws -> [String] {
        guard !replacement.contains("\u{FFFC}") else { throw AttachmentError.markersChanged }
        var remainder = replacement[...], pieces = [String]()
        for marker in markers {
            guard replacement.components(separatedBy: marker).count == 2,
                  let range = remainder.range(of: marker) else { throw AttachmentError.markersChanged }
            pieces.append(String(remainder[..<range.lowerBound]))
            remainder = remainder[range.upperBound...]
        }
        pieces.append(String(remainder))
        // No marker may appear as literal text in another slot.
        guard pieces.allSatisfy({ part in !markers.contains(where: part.contains) }) else { throw AttachmentError.markersChanged }
        return pieces
    }

    public func rawText(with segments: [String]) -> String {
        let source = rawText as NSString
        return interleave(segments, with: attachmentRanges.map { source.substring(with: $0) })
    }

    private func interleave(_ pieces: [String], with separators: [String]) -> String {
        var result = pieces.first ?? ""
        for (index, separator) in separators.enumerated() {
            result += separator + pieces[index + 1]
        }
        return result
    }
}
