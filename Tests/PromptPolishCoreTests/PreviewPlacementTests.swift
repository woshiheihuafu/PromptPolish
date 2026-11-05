import Foundation
import CoreGraphics
@testable import PromptPolishCore

final class PreviewPlacementTests {
    func testBottomComposerGetsAdjacentPreviewAbove() {
        let frame = PreviewPlacement.frame(near: CGRect(x: 300, y: 100, width: 900, height: 120), visibleFrames: [CGRect(x: 0, y: 0, width: 1_600, height: 1_000)])
        expectEqual(frame, CGRect(x: 480, y: 232, width: 720, height: 520))
    }
    func testTopComposerGetsAdjacentPreviewBelow() {
        let frame = PreviewPlacement.frame(near: CGRect(x: 300, y: 800, width: 900, height: 100), visibleFrames: [CGRect(x: 0, y: 0, width: 1_600, height: 1_000)])
        expectEqual(frame, CGRect(x: 480, y: 268, width: 720, height: 520))
    }
    func testShrinksToAvailableSpaceBeforeOverlappingComposer() {
        let field = CGRect(x: 100, y: 200, width: 700, height: 120)
        let frame = PreviewPlacement.frame(near: field, visibleFrames: [CGRect(x: 0, y: 0, width: 1_000, height: 800)])!
        expectEqual(frame, CGRect(x: 80, y: 332, width: 720, height: 456))
        expectFalse(frame.intersects(field))
    }
    func testUsesSideWhenNeitherAboveNorBelowFits() {
        let field = CGRect(x: 20, y: 350, width: 200, height: 300)
        let frame = PreviewPlacement.frame(near: field, visibleFrames: [CGRect(x: 0, y: 0, width: 1_800, height: 1_000)])!
        expectEqual(frame, CGRect(x: 232, y: 130, width: 720, height: 520))
        expectFalse(frame.intersects(field))
    }
    func testUsesTheComposerDisplayWithNegativeOrigin() {
        let screen = CGRect(x: -1_600, y: 0, width: 1_600, height: 1_000)
        let frame = PreviewPlacement.frame(near: CGRect(x: -1_500, y: 100, width: 1_200, height: 120), visibleFrames: [CGRect(x: 0, y: 0, width: 1_600, height: 1_000), screen])!
        expectTrue(screen.contains(frame))
        expectEqual(frame.minY, 232)
        expectEqual(frame.width, 720)
    }
    func testNoRoomStillKeepsCompactPopupOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 900, height: 700)
        let frame = PreviewPlacement.frame(near: screen, visibleFrames: [screen])!
        expectTrue(screen.contains(frame))
        expectEqual(frame.size, CGSize(width: 640, height: 440))
        expectNil(PreviewPlacement.frame(near: nil, visibleFrames: []))
    }
}
