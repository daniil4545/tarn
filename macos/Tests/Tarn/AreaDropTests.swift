import AppKit
import Foundation
import Testing
@testable import Ghostty

/// The drop zones of `docs/specs/windows-workspaces.md` section 3a, one case per row, and what a
/// drop does to the layout.
@MainActor
@Suite
struct AreaDropTests {
    private let size = CGSize(width: 1000, height: 600)
    private let block = AreaLeaf(kind: .block)
    private let first = AreaLeaf(kind: .viewer)
    private let second = AreaLeaf(kind: .viewer)

    /// Block on the left (60 percent), the viewers on the right.
    private var oneViewer: AreaTree {
        AreaTree.block(block).opening(first, beside: block, direction: .right, share: 0.6)
    }

    private var twoViewers: AreaTree {
        oneViewer.opening(second, beside: first, direction: .right, share: 0.5)
    }

    private func target(
        _ x: CGFloat, _ y: CGFloat, tree: AreaTree, _ payload: AreaPayload
    ) -> AreaDropTarget? {
        AreaDrop.target(at: CGPoint(x: x, y: y), in: size, tree: tree, payload: payload)
    }

    private func frame(of leaf: AreaLeaf, in tree: AreaTree) -> CGRect {
        AreaDrop.frames(of: tree.root!, in: CGRect(origin: .zero, size: size)).first { $0.0 === leaf }!.1
    }

    // MARK: Zones

    @Test func aCornerOfAnUnsplitAreaGivesTheNearestHalf() {
        // The viewer moves; what is left is the block alone.
        let result = target(10, 30, tree: oneViewer, .viewer(first.id))
        #expect(result?.plan == .half(.left))
        #expect(result?.frame == CGRect(x: 0, y: 0, width: 500, height: 600))
    }

    @Test func aCornerOfASplitAreaGivesAQuarter() {
        // Block and first viewer stay (60/40); the second viewer is dragged to the top left corner.
        let result = target(10, 10, tree: twoViewers, .viewer(second.id))
        #expect(result?.plan == .quarter(first: true, edge: .top))
        #expect(result?.frame == CGRect(x: 0, y: 0, width: 600, height: 300))
        let bottomRight = target(990, 590, tree: twoViewers, .viewer(second.id))
        #expect(bottomRight?.plan == .quarter(first: false, edge: .bottom))
        #expect(bottomRight?.frame == CGRect(x: 600, y: 300, width: 400, height: 300))
    }

    @Test func aStripGivesHalfOfTheWholeArea() {
        let tree = twoViewers
        #expect(target(10, 300, tree: tree, .viewer(second.id))?.plan == .half(.left))
        #expect(target(990, 300, tree: tree, .viewer(first.id))?.plan == .half(.right))
        #expect(target(500, 10, tree: tree, .viewer(second.id))?.plan == .half(.top))
        let bottom = target(500, 590, tree: tree, .viewer(second.id))
        #expect(bottom?.plan == .half(.bottom))
        #expect(bottom?.frame == CGRect(x: 0, y: 300, width: 1000, height: 300))
    }

    /// The top strip of the area wins over the tab bar: a viewer at the top edge keeps 24 to 32 px of bar.
    @Test func theTabBarAndTheMiddleOfAViewerMeanIntoThatViewer() {
        let rect = frame(of: first, in: twoViewers)
        let bar = target(rect.midX, rect.minY + 28, tree: twoViewers, .viewer(second.id))
        #expect(bar?.plan == .into(first.id))
        #expect(bar?.frame == rect)
        let middle = target(rect.midX, rect.midY, tree: twoViewers, .viewer(second.id))
        #expect(middle?.plan == .into(first.id))
    }

    @Test func elsewhereInAPaneGivesTheHalfOnTheNearestEdge() {
        let rect = frame(of: first, in: twoViewers)
        let result = target(rect.minX + 20, rect.midY + 120, tree: twoViewers, .viewer(second.id))
        #expect(result?.plan == .beside(first.id, .left))
        #expect(result?.frame == AreaDrop.half(.left, of: rect))
        let overBlock = target(300, 400, tree: twoViewers, .viewer(second.id))
        #expect(overBlock?.plan == .beside(block.id, .bottom))
    }

    @Test func overTheDraggedPaneItselfIsRefusedInRed() {
        let rect = frame(of: second, in: twoViewers)
        let result = target(rect.midX, rect.midY + 100, tree: twoViewers, .viewer(second.id))
        #expect(result?.plan == nil)
        #expect(result?.refusal == AreaDrop.selfRefusal)
        #expect(result?.frame == rect)
    }

    // MARK: Terminals

    @Test func aLoneTerminalMovesTheBlockToAViewerEdge() {
        let rect = frame(of: first, in: oneViewer)
        let result = target(rect.maxX - 40, rect.midY, tree: oneViewer, .terminal(UUID()))
        #expect(result?.plan == .beside(first.id, .right))
        #expect(result?.refusal == nil)
    }

    @Test func aTerminalInsideTheBlockAndWithoutViewersIsGhosttys() {
        #expect(target(300, 300, tree: oneViewer, .terminal(UUID())) == nil)
        #expect(target(10, 300, tree: AreaTree.block(block), .terminal(UUID())) == nil)
    }

    // MARK: Placing

    @Test func aHalfPlacesThePaneBesideEverything() {
        let result = twoViewers.placing(second, .half(.left))
        #expect(result.map(\.id) == [second.id, block.id, first.id])
        guard case let .split(split)? = result.root else {
            Issue.record("not split")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(split.ratio == 0.5)
    }

    @Test func aQuarterHalvesThePartUnderTheCorner() {
        let result = twoViewers.placing(second, .quarter(first: true, edge: .top))
        #expect(result.map(\.id) == [second.id, block.id, first.id])
        guard case let .split(split)? = result.root, case let .split(inner) = split.left else {
            Issue.record("not a quarter")
            return
        }
        #expect(split.direction == .horizontal)
        #expect(split.ratio == 0.6)
        #expect(inner.direction == .vertical)
    }

    @Test func aBesidePlacesTheBlockOfALoneTerminal() {
        let result = oneViewer.placing(block, .beside(first.id, .right))
        #expect(result.map(\.id) == [first.id, block.id])
    }

    @Test func intoOnlyTakesTheViewerOut() {
        let result = twoViewers.placing(second, .into(first.id))
        #expect(result.map(\.id) == [block.id, first.id])
    }

    // MARK: Grip

    @Test func theDotsAreBrighterThanGhosttys() {
        #expect(ViewerGripView.opacity(near: false, hovering: false) == 0)
        #expect(ViewerGripView.opacity(near: true, hovering: false) == 0.6)
        #expect(ViewerGripView.opacity(near: true, hovering: true) == 1.0)
    }

    // MARK: Files from a viewer page

    private func file(from viewer: AreaLeaf, moves: Bool = true, sole: Bool = false) -> AreaPayload {
        .file(FileDrag(path: "/tmp/a.md", viewer: viewer.id, moves: moves, sole: sole))
    }

    @Test func aFileTabOnTheTabBarOfAnotherViewerJoinsIt() {
        let result = target(900, 28, tree: twoViewers, file(from: first))
        #expect(result?.plan == .into(second.id))
    }

    @Test func aFileDroppedOnItsOwnViewerChangesNothingUnlessATabSplitsOffAnEdge() {
        // The middle of the own viewer, and the only tab on any part of it: refused in red.
        #expect(target(700, 300, tree: twoViewers, file(from: first))?.plan == nil)
        #expect(target(700, 300, tree: twoViewers, file(from: first))?.refusal == AreaDrop.selfRefusal)
        #expect(target(620, 300, tree: twoViewers, file(from: first, sole: true))?.plan == nil)
        // Not the only tab: the left edge of the own viewer splits a new viewer off.
        #expect(target(620, 300, tree: twoViewers, file(from: first))?.plan == .beside(first.id, .left))
    }

    @Test func aTreeRowOnTheMiddleOfItsOwnViewerIsRefused() {
        #expect(target(700, 300, tree: twoViewers, file(from: first, moves: false))?.plan == nil)
        #expect(target(620, 300, tree: twoViewers, file(from: first, moves: false, sole: true))?.plan == .beside(first.id, .left))
    }

    @Test func aFileOnTheTerminalBlockOpensAViewerBesideIt() {
        #expect(target(100, 300, tree: twoViewers, file(from: first))?.plan == .beside(block.id, .left))
    }

    @Test func aFileOnAnAreaStripTakesThatHalfOfTheWholeArea() {
        #expect(target(10, 300, tree: twoViewers, file(from: first))?.plan == .half(.left))
    }

    @Test func aNewViewerLeafCanBePlacedByAPlan() {
        let new = AreaLeaf(kind: .viewer)
        let placed = oneViewer.placing(new, .beside(first.id, .left))
        #expect(placed.count == 3)
        #expect(placed.leaf(id: new.id) != nil)
        #expect(oneViewer.placing(new, .half(.top)).count == 3)
    }

    // MARK: Thresholds: corner 48, strip 24, on both sides

    @Test func theStripEndsAt24() {
        #expect(target(23, 300, tree: twoViewers, file(from: first))?.plan == .half(.left))
        #expect(target(25, 300, tree: twoViewers, file(from: first))?.plan == .beside(block.id, .left))
        #expect(target(300, 23, tree: twoViewers, file(from: first))?.plan == .half(.top))
        #expect(target(300, 25, tree: twoViewers, file(from: first))?.plan == .beside(block.id, .top))
        #expect(target(977, 300, tree: twoViewers, file(from: first))?.plan == .half(.right))
        #expect(target(975, 300, tree: twoViewers, file(from: first))?.plan == .beside(second.id, .right))
        #expect(target(300, 577, tree: twoViewers, file(from: first))?.plan == .half(.bottom))
        #expect(target(300, 575, tree: twoViewers, file(from: first))?.plan == .beside(block.id, .bottom))
    }

    @Test func theCornerEndsAt48() {
        let inside = target(47, 47, tree: twoViewers, .viewer(second.id))
        #expect(inside?.plan == .quarter(first: true, edge: .top))
        // One point further along either axis it is no corner any more: a pane zone of the block.
        for point in [CGPoint(x: 49, y: 47), CGPoint(x: 47, y: 49)] {
            let outside = target(point.x, point.y, tree: twoViewers, .viewer(second.id))
            if case .quarter? = outside?.plan { Issue.record("still a corner at \(point)") }
            #expect(outside?.plan != nil)
        }
        // The far corner starts at width minus 48.
        let far = target(953, 553, tree: twoViewers, .viewer(first.id))
        #expect(far?.plan == .quarter(first: false, edge: .bottom))
        for point in [CGPoint(x: 951, y: 553), CGPoint(x: 953, y: 551)] {
            let outside = target(point.x, point.y, tree: twoViewers, .viewer(first.id))
            if case .quarter? = outside?.plan { Issue.record("still a corner at \(point)") }
        }
    }

    // MARK: The line

    /// The line lies on the border of the new pane: the inner edge of the frame it will take.
    @Test func theLineIsCenteredOnTheInnerEdgeOfTheFrame() throws {
        let width = AreaDrop.lineWidth
        // A strip, a corner, the half of a viewer and of the block.
        let cases: [(CGPoint, AreaPayload)] = [
            (CGPoint(x: 10, y: 300), .viewer(second.id)),
            (CGPoint(x: 990, y: 300), .viewer(first.id)),
            (CGPoint(x: 300, y: 10), .viewer(first.id)),
            (CGPoint(x: 300, y: 590), .viewer(first.id)),
            (CGPoint(x: 47, y: 47), .viewer(second.id)),
            (CGPoint(x: 300, y: 300), .viewer(first.id)),
            (CGPoint(x: 900, y: 150), file(from: first)),
        ]
        for (point, payload) in cases {
            let result = try #require(target(point.x, point.y, tree: twoViewers, payload), "\(point)")
            let plan = try #require(result.plan, "\(point)")
            let line = try #require(AreaDrop.line(for: plan, frame: result.frame), "\(point)")
            switch plan {
            case .half(let edge), .quarter(_, let edge), .beside(_, let edge):
                switch edge {
                case .left: #expect(line.midX == result.frame.maxX && line.width == width && line.height == result.frame.height)
                case .right: #expect(line.midX == result.frame.minX && line.width == width && line.height == result.frame.height)
                case .top: #expect(line.midY == result.frame.maxY && line.height == width && line.width == result.frame.width)
                case .bottom: #expect(line.midY == result.frame.minY && line.height == width && line.width == result.frame.width)
                }
            case .into:
                Issue.record("unexpected into at \(point)")
            }
        }
    }

    @Test func theLineOfALeftStripSitsAtTheMiddleOfTheArea() throws {
        let result = try #require(target(10, 300, tree: twoViewers, .viewer(second.id)))
        let line = AreaDrop.line(for: try #require(result.plan), frame: result.frame)
        #expect(line == CGRect(x: 498.5, y: 0, width: 3, height: 600))
    }

    @Test func aDropIntoAViewerShowsTheLineUnderItsTabBar() throws {
        let rect = frame(of: second, in: twoViewers)
        let result = try #require(target(rect.midX, rect.minY + 28, tree: twoViewers, .viewer(first.id)))
        #expect(result.plan == .into(second.id))
        let line = try #require(AreaDrop.line(for: .into(second.id), frame: result.frame))
        #expect(line == CGRect(x: rect.minX, y: rect.minY + AreaDrop.tabBar - 1.5, width: rect.width, height: 3))
    }
}
