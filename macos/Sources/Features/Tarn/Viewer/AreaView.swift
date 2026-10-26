import SwiftUI

/// Lays out the viewers and the terminal block of a tab as the `AreaTree` says. With no viewer it
/// is the terminal view alone. Each split is Ghostty's `SplitView`, as in
/// `Features/Splits/TerminalSplitTreeView.swift`.
struct ViewerLayout<Content: View>: View {
    @ObservedObject var host: ViewerHost
    @ObservedObject var ghostty: Ghostty.App
    let content: Content

    init(host: ViewerHost, ghostty: Ghostty.App, @ViewBuilder content: () -> Content) {
        self.host = host
        self.ghostty = ghostty
        self.content = content()
    }

    var body: some View {
        if let root = host.tree.root, host.tree.isSplit, !host.hidden {
            AreaSubtree(host: host, ghostty: ghostty, node: root, block: content)
                .overlay(AreaDropOverlay(host: host))
                // Ghostty's grab handle publishes which terminal is dragged.
                .onPreferenceChange(Ghostty.DraggingSurfaceKey.self) { host.terminalDragged($0) }
        } else {
            content
        }
    }
}

private struct AreaSubtree<Block: View>: View {
    @ObservedObject var host: ViewerHost
    let ghostty: Ghostty.App
    let node: AreaTree.Node
    let block: Block

    var body: some View {
        switch node {
        case let .leaf(leaf):
            if leaf.kind == .block {
                block
            } else if let pane = host.pane(for: leaf.id) {
                ViewerPaneRepresentable(pane: pane, dark: isDark, dragHandle: ghostty.config.dragHandle)
            }
        case let .split(split):
            AreaSplit(
                direction: split.direction == .horizontal ? .horizontal : .vertical,
                ratio: CGFloat(split.ratio),
                dividerColor: ghostty.config.splitDividerColor,
                onResize: { host.resize(node, to: Double($0)) },
                onEqualize: { host.equalize() },
                left: { AreaSubtree(host: host, ghostty: ghostty, node: split.left, block: block) },
                right: { AreaSubtree(host: host, ghostty: ghostty, node: split.right, block: block) })
        }
    }

    private var isDark: Bool {
        !NSColor(ghostty.config.backgroundColor).isLightColor
    }
}

private struct ViewerPaneRepresentable: NSViewRepresentable {
    let pane: ViewerHost.Pane
    let dark: Bool
    let dragHandle: Ghostty.Config.DragHandle

    func makeNSView(context: Context) -> ViewerPaneView { pane.web.container }

    func updateNSView(_ nsView: ViewerPaneView, context: Context) {
        pane.model.dark = dark
        nsView.grip.dark = dark
        nsView.dragHandle = dragHandle
    }
}
