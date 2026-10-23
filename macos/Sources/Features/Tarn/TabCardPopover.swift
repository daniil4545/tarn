import AppKit
import SwiftUI

/// The one card popover of a sidebar. Moving to another row keeps the popover open: it
/// slides to the new row and swaps its content, instead of closing and opening again.
@MainActor
final class TabCardPopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let host = NSHostingController(rootView: AnyView(EmptyView()))

    /// The pointer is over the card, so the row under it may close without closing the card.
    private(set) var isHovering = false
    var onHoverChange: () -> Void = {}
    var onClose: () -> Void = {}

    override init() {
        super.init()
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
    }

    /// Shows `tab`'s card beside `anchor`. While shown, it moves to the new row instead of
    /// closing and opening again.
    func show(_ tab: SidebarModel.Tab, anchor: NSView, onAnswer: @escaping () -> Void) {
        host.rootView = AnyView(
            TabCard(tab: tab, onAnswer: onAnswer)
                .padding(12)
                .frame(width: 280, alignment: .leading)
                .onHover { [weak self] in
                    self?.isHovering = $0
                    self?.onHoverChange()
                })
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    func close() {
        isHovering = false
        if popover.isShown { popover.performClose(nil) }
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            isHovering = false
            onClose()
        }
    }
}
