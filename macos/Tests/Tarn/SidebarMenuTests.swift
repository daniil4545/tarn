import AppKit
import Foundation
import Testing
@testable import Ghostty

/// The right-click menus of the sidebar: the items must send a message their target handles.
/// A selector `#selector(MenuAction.perform(_:))` once resolved to `NSObject.perform(_:)`, so
/// no item of any menu did anything.
@MainActor
@Suite
struct SidebarMenuTests {
    private func makeModel() -> (SidebarModel, NSWindow) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.orderFront(nil)
        let model = SidebarModel()
        model.window = window
        return (model, window)
    }

    private func tab() -> SidebarModel.Tab {
        SidebarModel.Tab(
            id: ObjectIdentifier(NSObject()), key: TabKey(), index: 1, title: "one", agentProcess: nil,
            keyEquivalent: nil, color: .none, isSelected: false, agent: nil, workspace: "", folder: nil
        )
    }

    private func itemsWithActions(_ menu: NSMenu) -> [NSMenuItem] {
        menu.items.filter { $0.action != nil && !$0.hasSubmenu }
    }

    private func expectHandled(_ items: [NSMenuItem]) {
        #expect(!items.isEmpty)
        for item in items {
            #expect(item.action != #selector(NSObject.perform(_:)), "\(item.title) sends performSelector:")
            #expect(item.target?.responds(to: item.action) == true, "\(item.title): target does not handle its action")
        }
    }

    @Test func workspaceMenuItemsSendAMessageTheirTargetHandles() {
        let (model, _) = makeModel()
        let menu = model.contextMenu(for: Workspace(name: "Alpha"))
        #expect(itemsWithActions(menu).map(\.title) == ["New Tab", "Collapse", "Rename Workspace...", "Delete Workspace..."])
        expectHandled(itemsWithActions(menu))
    }

    @Test func tabMenuItemsSendAMessageTheirTargetHandles() {
        let (model, _) = makeModel()
        let items = itemsWithActions(model.contextMenu(for: tab()))
        #expect(items.map(\.title).contains("Close Tab"))
        expectHandled(items)
    }

    @Test func renameWorkspaceItemOpensTheNameSheet() throws {
        let (model, window) = makeModel()
        let menu = model.contextMenu(for: Workspace(name: "Alpha"))
        let rename = try #require(menu.items.first { $0.title == "Rename Workspace..." })

        _ = NSApp.sendAction(try #require(rename.action), to: rename.target, from: rename)

        let sheet = try #require(window.attachedSheet, "the item did not run its action")
        window.endSheet(sheet)
    }
}
