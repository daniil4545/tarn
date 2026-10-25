import AppKit
import Foundation
import Testing
@testable import Ghostty

/// The layout of a tab: the terminal block is one leaf and viewers sit around it
/// (`docs/modules/layout.md`).
@MainActor
@Suite
struct AreaTreeTests {
    private func rootSplit(_ tree: AreaTree) -> (direction: AreaTree.Direction, ratio: Double)? {
        guard case let .split(split)? = tree.root else { return nil }
        return (split.direction, split.ratio)
    }

    @Test func aTabStartsWithOneBlockLeaf() {
        let tree = AreaTree.block(AreaLeaf(kind: .block))
        #expect(tree.count == 1)
        #expect(tree.block?.kind == .block)
        #expect(tree.viewers.isEmpty)
        #expect(!tree.isSplit)
    }

    @Test func aViewerOpensBesideTheBlockAndTheBlockKeepsItsShare() {
        let block = AreaLeaf(kind: .block)
        let viewer = AreaLeaf(kind: .viewer)
        let tree = AreaTree.block(block).opening(viewer, beside: block, direction: .right, share: 0.6)
        #expect(tree.map(\.id) == [block.id, viewer.id])
        #expect(rootSplit(tree)?.direction == .horizontal)
        #expect(rootSplit(tree)?.ratio == 0.6)
    }

    @Test func aViewerOnTheFirstSideGetsTheRemainder() {
        let block = AreaLeaf(kind: .block)
        let viewer = AreaLeaf(kind: .viewer)
        let tree = AreaTree.block(block).opening(viewer, beside: block, direction: .up, share: 0.6)
        #expect(tree.map(\.id) == [viewer.id, block.id])
        #expect(rootSplit(tree)?.direction == .vertical)
        #expect(rootSplit(tree)?.ratio == 0.4)
    }

    @Test func removingTheLastViewerLeavesTheBlockAlone() {
        let block = AreaLeaf(kind: .block)
        let viewer = AreaLeaf(kind: .viewer)
        let tree = AreaTree.block(block).opening(viewer, beside: block, direction: .right).removing(viewer)
        #expect(tree.map(\.id) == [block.id])
        #expect(!tree.isSplit)
    }

    @Test func removingAViewerKeepsTheOthers() {
        let block = AreaLeaf(kind: .block)
        let first = AreaLeaf(kind: .viewer)
        let second = AreaLeaf(kind: .viewer)
        var tree = AreaTree.block(block).opening(first, beside: block, direction: .right)
        tree = tree.opening(second, beside: first, direction: .down)
        #expect(tree.count == 3)
        #expect(tree.removing(first).map(\.id) == [block.id, second.id])
    }

    @Test func aSnapshotRoundTripsStructureAndIds() throws {
        let block = AreaLeaf(kind: .block)
        let first = AreaLeaf(kind: .viewer)
        let second = AreaLeaf(kind: .viewer)
        var tree = AreaTree.block(block).opening(first, beside: block, direction: .right, share: 0.7)
        tree = tree.opening(second, beside: first, direction: .down)
        let decoded = try JSONDecoder().decode(AreaTree.self, from: JSONEncoder().encode(tree))
        #expect(decoded.map(\.id) == tree.map(\.id))
        #expect(decoded.map(\.kind) == [.block, .viewer, .viewer])
        #expect(rootSplit(decoded)?.ratio == 0.7)
    }

    @Test func theNeighbourIsFoundByDirection() {
        let block = AreaLeaf(kind: .block)
        let viewer = AreaLeaf(kind: .viewer)
        let tree = AreaTree.block(block).opening(viewer, beside: block, direction: .right)
        #expect(tree.neighbor(of: block, .spatial(.right)) === viewer)
        #expect(tree.neighbor(of: viewer, .spatial(.left)) === block)
        #expect(tree.neighbor(of: block, .spatial(.left)) == nil)
        #expect(tree.neighbor(of: block, .spatial(.up)) == nil)
        #expect(tree.neighbor(of: block, .next) === viewer)
        #expect(tree.neighbor(of: viewer, .next) === block)
    }

    @Test func aClosedViewerRemembersItsPlace() throws {
        let block = AreaLeaf(kind: .block)
        let viewer = AreaLeaf(kind: .viewer)
        let tree = AreaTree.block(block).opening(viewer, beside: block, direction: .down)
        let slot = try #require(tree.slot(of: viewer))
        #expect(slot.anchor === block)
        #expect(slot.direction == .down)
        #expect(tree.slot(of: block)?.direction == .up)
        #expect(AreaTree.block(block).slot(of: block) == nil)
    }
}
