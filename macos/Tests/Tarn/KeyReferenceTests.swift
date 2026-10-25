import Testing
@testable import Ghostty

/// Help against Ghostty itself (`docs/plans/s4-settings.md` sections 1.3 and 3, slice D).
@Suite
struct KeyReferenceTests {
    private static let ghosttyRows = KeyReference.groups.flatMap(\.rows).filter { $0.action != nil }

    @Test func rowIDsAreUnique() {
        let ids = KeyReference.groups.flatMap(\.rows).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test(arguments: ghosttyRows)
    @MainActor
    func everyActionHasADefaultTrigger(row: KeyReference.Row) throws {
        let config = try TemporaryConfig("")
        let keys = KeyReference.keys(for: row, in: config)
        #expect(keys != KeyReference.notBound, "\(row.action ?? "")")
        if row.defaultKeys == nil {
            #expect(config.keyboardShortcut(for: row.action ?? "") != nil, "\(row.action ?? "")")
        }
    }

    @Test @MainActor func anUnboundActionIsShownAsSuch() throws {
        let config = try TemporaryConfig("keybind = super+t=unbind")
        let row = try #require(Self.ghosttyRows.first { $0.action == "new_tab" })
        #expect(KeyReference.keys(for: row, in: config) == KeyReference.notBound)
    }

    @Test @MainActor func aKeybindLineChangesTheKeys() throws {
        let config = try TemporaryConfig("keybind = cmd+shift+w=close_tab")
        let row = try #require(Self.ghosttyRows.first { $0.action == "close_tab" })
        #expect(KeyReference.keys(for: row, in: config).contains("W"))
        #expect(KeyReference.keys(for: row, in: nil) == KeyReference.notBound)
    }

    @Test func performableActionsCarryTheirDefaultKeys() {
        let keys = Dictionary(uniqueKeysWithValues: Self.ghosttyRows.compactMap { row in row.defaultKeys.map { (row.action ?? "", $0) } })
        #expect(keys["undo"] == "⌘Z")
        #expect(keys["redo"] == "⇧⌘Z")
        #expect(keys["clear_screen"] == "⌘K")
        #expect(keys["start_search"] == "⌘F")
        #expect(keys["navigate_search:next"] == "⌘G")
        #expect(keys["navigate_search:previous"] == "⇧⌘G")
    }

    @Test @MainActor func viewerKeysAreFixedAndComeFromTheTable() {
        let viewer = KeyReference.groups.first { $0.title == "Viewer" }
        #expect(viewer?.rows.map(\.source) == Array(repeating: "tarn", count: 4))
        #expect(viewer?.rows.compactMap(\.fixedKeys).contains("⌘S") == true)
    }
}
