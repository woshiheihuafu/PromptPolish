import Foundation
import CoreGraphics
@testable import PromptPolishCore

final class FloatingPlacementTests {
    let size = CGSize(width: 40, height: 32)
    let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    func testPrefersRightOutsideField() {
        let field = CGRect(x: 100, y: 100, width: 500, height: 100)
        expectEqual(FloatingPlacement.origin(field: field, visibleFrames: [screen], size: size), CGPoint(x: 612, y: 168))
    }
    func testRightEdgeUsesLeftAndDoesNotOverlap() {
        let field = CGRect(x: 500, y: 100, width: 490, height: 100)
        let origin = FloatingPlacement.origin(field: field, visibleFrames: [screen], size: size)!
        expectEqual(origin.x, 448)
        expectFalse(CGRect(origin: origin, size: size).intersects(field))
    }
    func testSpansScreenWidthUsesAbove() {
        let field = CGRect(x: 0, y: 100, width: 1_000, height: 100)
        expectEqual(FloatingPlacement.origin(field: field, visibleFrames: [screen], size: size), CGPoint(x: 0, y: 212))
    }
    func testNoRoomOrOffscreenHidesButton() {
        expectNil(FloatingPlacement.origin(field: screen, visibleFrames: [screen], size: size))
        expectNil(FloatingPlacement.origin(field: CGRect(x: 2_000, y: 0, width: 100, height: 100), visibleFrames: [screen], size: size))
    }
    func testNegativeOriginSecondaryDisplay() {
        let second = CGRect(x: -1_200, y: 0, width: 1_200, height: 800)
        expectEqual(FloatingPlacement.origin(field: CGRect(x: -1_100, y: 200, width: 500, height: 100), visibleFrames: [screen, second], size: size), CGPoint(x: -588, y: 268))
    }
}
