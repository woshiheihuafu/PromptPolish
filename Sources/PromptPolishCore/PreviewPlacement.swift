import Foundation
import CoreGraphics

public enum PreviewPlacement {
    public static func frame(near field: CGRect?, visibleFrames: [CGRect], preferredSize: CGSize = CGSize(width: 720, height: 520), minimumSize: CGSize = CGSize(width: 640, height: 440), gap: CGFloat = 12) -> CGRect? {
        let screens = visibleFrames.filter { !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0 }
        guard let first = screens.first else { return nil }
        let source = field.flatMap { $0.isNull || $0.isInfinite || $0.width <= 0 || $0.height <= 0 ? nil : $0 }
        let screen = source.flatMap { field in
            screens.filter { $0.intersects(field) }.max { area($0.intersection(field)) < area($1.intersection(field)) }
        } ?? first
        let bounds = screen.width > 24 && screen.height > 24 ? screen.insetBy(dx: 12, dy: 12) : screen
        let preferred = CGSize(width: min(max(1, preferredSize.width), bounds.width), height: min(max(1, preferredSize.height), bounds.height))
        let minimum = CGSize(width: min(minimumSize.width, preferred.width), height: min(minimumSize.height, preferred.height))
        guard let field = source, field.intersects(screen) else {
            return CGRect(x: bounds.midX - preferred.width / 2, y: bounds.midY - preferred.height / 2, width: preferred.width, height: preferred.height)
        }
        let zones = [
            CGSize(width: bounds.width, height: bounds.maxY - field.maxY - gap),
            CGSize(width: bounds.width, height: field.minY - gap - bounds.minY),
            CGSize(width: bounds.maxX - field.maxX - gap, height: bounds.height),
            CGSize(width: field.minX - gap - bounds.minX, height: bounds.height)
        ]
        for (side, available) in zones.enumerated() where available.width >= minimum.width && available.height >= minimum.height {
            let size = CGSize(width: min(preferred.width, available.width), height: min(preferred.height, available.height))
            let candidate = adjacent(field: field, side: side, size: size, gap: gap, bounds: bounds)
            if bounds.contains(candidate) && !candidate.intersects(field) { return candidate }
        }
        // With no room outside the composer, keep a smaller popup on the same display.
        let candidates = (0..<4).map { adjacent(field: field, side: $0, size: minimum, gap: gap, bounds: bounds) }
        return candidates.min { area($0.intersection(field)) < area($1.intersection(field)) }
    }

    private static func adjacent(field: CGRect, side: Int, size: CGSize, gap: CGFloat, bounds: CGRect) -> CGRect {
        var origin = CGPoint(x: field.maxX - size.width, y: field.maxY + gap)
        if side == 1 { origin.y = field.minY - gap - size.height }
        if side == 2 { origin = CGPoint(x: field.maxX + gap, y: field.maxY - size.height) }
        if side == 3 { origin = CGPoint(x: field.minX - gap - size.width, y: field.maxY - size.height) }
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return CGRect(origin: origin, size: size)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull || rect.isInfinite ? 0 : rect.width * rect.height }
}
