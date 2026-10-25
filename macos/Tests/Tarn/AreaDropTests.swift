import AppKit
import Foundation
import Testing
@testable import Ghostty

/// The drop zones of `docs/plans/windows-workspaces.md` section 3a, one case per row, and what a
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
        _ x: CGFloat, _ y: CGFloat, tree: AreaTree, _ payload: AreaPayload, lone: Bool = true
    ) -> AreaDropTarget? {
        AreaDrop.target(at: CGPoint(x: x, y: y), in: size, tree: tree, payload: payload, loneTerminal: lone)
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

    @Test func splitTerminalsAreRefusedWithAHint() {
        let rect = frame(of: first, in: oneViewer)
        let result = target(rect.maxX - 40, rect.midY, tree: oneViewer, .terminal(UUID()), lone: false)
        #expect(result?.plan == nil)
        #expect(result?.refusal == AreaDrop.splitRefusal)
        let strip = target(990, 300, tree: oneViewer, .terminal(UUID()), lone: false)
        #expect(strip?.refusal == AreaDrop.splitRefusal)
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
}
