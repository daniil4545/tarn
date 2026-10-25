import Foundation
import Testing
@testable import Ghostty

/// S7: where a dragged tab lands among the other tabs of its window.
@Suite
struct MoveTabTests {
    private let t = (0..<5).map { _ in TabKey() }

    @Test func aTabBeforeANeighbourTakesItsPlace() {
        let place = WorkspaceRegistry.destination(of: t[0], in: t, before: t[3], isMember: { _ in false })
        #expect(place == 2)
    }

    @Test func aTabGoesAfterTheLastMemberOfTheWorkspace() {
        let members: Set = [t[1], t[2]]
        let place = WorkspaceRegistry.destination(of: t[4], in: t, before: nil, isMember: members.contains)
        #expect(place == 3)
    }

    // A lone tab dropped on its own header or row moved its whole workspace to the end.
    @Test func theOnlyTabOfAWorkspaceStaysWhereItIs() {
        let place = WorkspaceRegistry.destination(of: t[1], in: t, before: nil, isMember: { _ in false })
        #expect(place == 1)
    }
}
