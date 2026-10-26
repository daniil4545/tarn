import Foundation
import Testing
@testable import Ghostty

/// Where a window dropped outside every window lands, with the screens of a real desk: a second
/// screen to the left (negative x), above (y beyond the main screen) and below (negative y).
@Suite
struct WindowPlacementTests {
    private typealias Screen = WindowPlacement.Screen

    private let main = Screen(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 80, width: 1440, height: 795))
    private let left = Screen(
        frame: CGRect(x: -1920, y: -100, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: -100, width: 1920, height: 1055))
    private let above = Screen(
        frame: CGRect(x: 100, y: 900, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 100, y: 900, width: 1920, height: 1055))
    private let below = Screen(
        frame: CGRect(x: -200, y: -1180, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -200, y: -1180, width: 1920, height: 1055))
    private let size = CGSize(width: 800, height: 600)

    private func frame(_ x: CGFloat, _ y: CGFloat, _ screens: [Screen]) -> CGRect {
        WindowPlacement.frame(topLeft: CGPoint(x: x, y: y), size: size, screens: screens)
    }

    @Test func aDropOnTheMainScreenKeepsTheCornerAtThePointer() {
        #expect(frame(300, 700, [main, left]) == CGRect(x: 300, y: 100, width: 800, height: 600))
    }

    @Test func aDropOnAScreenToTheLeftStaysThere() {
        let result = frame(-1000, 800, [main, left])
        #expect(result == CGRect(x: -1000, y: 200, width: 800, height: 600))
        #expect(!main.frame.intersects(result))
    }

    @Test func aDropOnAScreenAboveStaysThere() {
        let result = frame(500, 1700, [main, above])
        #expect(result == CGRect(x: 500, y: 1100, width: 800, height: 600))
        #expect(!main.frame.intersects(result))
    }

    @Test func aDropOnAScreenBelowKeepsNegativeCoordinates() {
        let result = frame(0, -300, [main, below])
        #expect(result == CGRect(x: 0, y: -900, width: 800, height: 600))
    }

    @Test func aWindowPushedPastTheRightEdgeOfTheLeftScreenDoesNotCrossToTheMainOne() {
        // The pointer is 100 pt inside the left screen; 800 pt of window would reach the main one.
        let result = frame(-100, 500, [main, left])
        #expect(result.maxX == 0)
        #expect(result.minX == -800)
    }

    @Test func aWindowPushedBelowTheBottomEdgeMovesUp() {
        let result = frame(-1000, -50, [main, left])
        #expect(result.minY == -100)
        #expect(result.maxY == 500)
    }

    @Test func aPointInTheMenuBarGivesAWindowBelowTheBar() {
        // The top 25 pt of the left screen are the menu bar: visibleFrame ends at y 955.
        let result = frame(-1000, 975, [main, left])
        #expect(result.maxY == 955)
    }

    @Test func aPointInTheDockStripMovesTheWindowAboveTheDock() {
        let result = frame(300, 20, [main, left])
        #expect(result.minY >= 80)
    }

    @Test func aPointInAGapBetweenScreensTakesTheNearestScreen() {
        let result = frame(-1990, 400, [main, left])
        #expect(result.minX == -1920)
        #expect(left.frame.contains(result.origin))
    }

    @Test func aWindowLargerThanTheScreenIsShrunkToIt() {
        let result = WindowPlacement.frame(
            topLeft: CGPoint(x: -1500, y: 500), size: CGSize(width: 3000, height: 2000), screens: [main, left])
        #expect(result == left.visibleFrame)
    }

    @Test func noScreensKeepsTheCornerAtThePointer() {
        #expect(frame(10, 700, []) == CGRect(x: 10, y: 100, width: 800, height: 600))
    }

    @Test func theResultAlwaysLiesInsideTheVisibleAreaOfTheScreenUnderThePoint() {
        let screens = [main, left, above, below]
        for x in stride(from: -2200 as CGFloat, through: 2300, by: 137) {
            for y in stride(from: -1200 as CGFloat, through: 2100, by: 131) {
                let point = CGPoint(x: x, y: y)
                let result = WindowPlacement.frame(topLeft: point, size: size, screens: screens)
                let screen = WindowPlacement.screen(at: point, in: screens)
                #expect(screen?.visibleFrame.contains(result) == true, "point \(point)")
            }
        }
    }
}
