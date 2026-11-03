import Testing
@testable import Ghostty

/// Settings > Modules > Permission card off: no card opens, an open one closes.
@MainActor
@Suite
struct SidebarCardTests {
    private final class Marker {}

    @Test func moduleOffOpensNoCard() {
        let model = SidebarModel()
        model.cardIsOn = { false }
        model.cardTab = ObjectIdentifier(Marker())
        #expect(model.cardTab == nil)
    }

    @Test func switchingTheModuleOffClosesTheOpenCard() {
        let model = SidebarModel()
        var isOn = true
        model.cardIsOn = { isOn }
        let id = ObjectIdentifier(Marker())
        model.cardTab = id
        #expect(model.cardTab == id)
        isOn = false
        model.refresh()
        #expect(model.cardTab == nil)
    }
}
