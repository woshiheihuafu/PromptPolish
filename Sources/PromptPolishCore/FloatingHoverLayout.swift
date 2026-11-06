import Foundation
import CoreGraphics

public struct FloatingHoverLayout: Equatable {
    public let collapsed: CGRect
    public let expanded: CGRect
    public let menu: CGRect?
    public let growsLeft: Bool

    public static func make(field: CGRect, screens: [CGRect], sceneCount: Int) -> Self? {
        let compact = CGSize(width: 40, height: 32), full = CGSize(width: 118, height: 32)
        let origin = FloatingPlacement.origin(field: field, visibleFrames: screens, size: full)
        guard let point = origin ?? FloatingPlacement.origin(field: field, visibleFrames: screens, size: compact),
              let screen = screens.first(where: { $0.contains(CGRect(origin: point, size: origin == nil ? compact : full)) }) else { return nil }
        let expanded = CGRect(origin: point, size: origin == nil ? compact : full)
        let growsLeft = expanded.maxX <= field.minX
        let collapsed = CGRect(x: growsLeft ? expanded.maxX - compact.width : expanded.minX, y: expanded.minY, width: compact.width, height: compact.height)
        var menu: CGRect?
        if sceneCount > 0 {
            let size = CGSize(width: min(224, screen.width), height: CGFloat(min(sceneCount, 5)) * 36 + 12)
            let x = min(max(growsLeft ? expanded.maxX - size.width : expanded.minX, screen.minX), screen.maxX - size.width)
            let candidates = [
                CGRect(x: x, y: expanded.minY - 6 - size.height, width: size.width, height: size.height),
                CGRect(x: x, y: expanded.maxY + 6, width: size.width, height: size.height),
                CGRect(x: expanded.maxX + 6, y: expanded.maxY - size.height, width: size.width, height: size.height),
                CGRect(x: expanded.minX - 6 - size.width, y: expanded.maxY - size.height, width: size.width, height: size.height)
            ]
            menu = candidates.first { screen.contains($0) && !$0.intersects(field) && !$0.intersects(expanded) }
        }
        return Self(collapsed: collapsed, expanded: expanded, menu: menu, growsLeft: growsLeft)
    }
}
