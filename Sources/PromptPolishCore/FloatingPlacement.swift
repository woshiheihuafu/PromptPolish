import Foundation
import CoreGraphics

public enum FloatingPlacement {
    public static func origin(field: CGRect, visibleFrames: [CGRect], size: CGSize, gap: CGFloat = 12) -> CGPoint? {
        guard field.width > 0, field.height > 0, size.width > 0, size.height > 0,
              let screen = visibleFrames.max(by: { $0.intersection(field).area < $1.intersection(field).area }),
              screen.intersects(field) else { return nil }
        let candidates = [
            CGPoint(x: field.maxX + gap, y: field.maxY - size.height),
            CGPoint(x: field.minX - gap - size.width, y: field.maxY - size.height),
            CGPoint(x: max(screen.minX, field.minX), y: field.maxY + gap),
            CGPoint(x: max(screen.minX, field.minX), y: field.minY - gap - size.height)
        ]
        return candidates.first {
            let bounds = CGRect(origin: $0, size: size)
            return screen.contains(bounds) && !field.intersects(bounds)
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isInfinite ? 0 : width * height }
}
