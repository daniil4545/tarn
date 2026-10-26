import AppKit
import Foundation
import Testing
@testable import Ghostty

/// The split keys of Ghostty's menu while a viewer holds the keyboard: move the divider, equalize
/// (`docs/modules/layout.md`).
@MainActor
@Suite
struct ViewerLayoutKeysTests {
    /// Block on the left, one viewer on the right.
    private func host() throws -> (ViewerHost, String) {
        let dir = NSTemporaryDirectory() + "tarn-layout-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "one".write(toFile: dir + "/a.md", atomically: true, encoding: .utf8)
        let host = ViewerHost()
        host.open(OpenTarget(path: dir + "/a.md"), root: dir, focus: false)
        return (host, dir)
    }

    private func ratio(_ host: ViewerHost) -> Double? {
        guard case let .split(split)? = host.tree.root else { return nil }
        return split.ratio
    }

    /// Ghostty moves a divider by 10 points of the whole area; the viewer's size gives the area's.
    @Test func cmdCtrlLeftMovesTheViewersBorderLeftByTenPoints() throws {
        let (host, dir) = try host()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let before = try #require(ratio(host))
        let pane = CGSize(width: 400, height: 600)
        host.activeModel?.onLayout?(.resize(.left, pane: pane))
        let after = try #require(ratio(host))
        let area = pane.width / (1 - before)
        #expect(abs((before - after) - 10 / area) < 0.0001)
        host.activeModel?.onLayout?(.resize(.right, pane: pane))
        #expect(abs(try #require(ratio(host)) - before) < 0.001)
    }

    @Test func cmdCtrlUpWithNoSplitAcrossLeavesTheLayout() throws {
        let (host, dir) = try host()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let before = ratio(host)
        host.activeModel?.onLayout?(.resize(.up, pane: CGSize(width: 400, height: 600)))
        #expect(ratio(host) == before)
    }

    @Test func equalizeGivesTheViewerAndTheBlockEqualShares() throws {
        let (host, dir) = try host()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        host.activeModel?.onLayout?(.resize(.left, pane: CGSize(width: 400, height: 600)))
        #expect(ratio(host) != 0.5)
        host.activeModel?.onLayout?(.equalize)
        #expect(ratio(host) == 0.5)
    }
}
