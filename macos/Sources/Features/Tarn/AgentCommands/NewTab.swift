import AppKit

/// U5: Ghostty's controller and native attachment, without its foreground new-tab factory or creation undo.
enum NewTab {
    static func refusal(group: UUID?, frozen: Bool) -> AgentRefusal? {
        frozen || group == nil ? AgentRefusal(text: "put this tab in a group first") : nil
    }

    @MainActor
    static func open(
        _ caller: BaseTerminalController,
        config: Ghostty.SurfaceConfiguration,
        title: String?
    ) -> Result<Ghostty.SurfaceView, AgentRefusal> {
        let unavailable = AgentRefusal(text: "window not available")
        guard let parent = caller.window else { return .failure(unavailable) }
        let selected = parent.tabGroup?.selectedWindow ?? parent
        // An unselected caller can belong to a minimized or non-native fullscreen selected window.
        for window in [parent, selected] {
            guard !window.isMiniaturized, window.tabbingMode != .disallowed else { return .failure(unavailable) }
            if let style = (window.windowController as? TerminalController)?.fullscreenStyle,
               style.isFullscreen && !style.supportsTabs { return .failure(unavailable) }
        }

        let child = TerminalController(caller.ghostty, withBaseConfig: config)
        child.isBackgroundOpaque = caller.isBackgroundOpaque
        child.titleOverride = title.flatMap { $0.isEmpty ? nil : $0 }
        var attached = false
        defer {
            if !attached {
                // Emptying Ghostty's tree disposes the surfaces and closes the window without undo.
                child.surfaceTree = .init()
            }
        }
        guard let window = child.window, window.tabbingMode != .disallowed,
              let surface = child.surfaceTree.first else { return .failure(unavailable) }
        let added = parent.addTabbedWindowSafely(window, ordered: .above)
        if let group = parent.tabGroup, group.selectedWindow !== selected { group.selectedWindow = selected }
        guard added, parent.tabGroup?.windows.contains(window) == true else {
            return .failure(AgentRefusal(text: "tab failed"))
        }
        WorkspaceRegistry.shared.opened(child, from: parent)
        child.relabelTabs()
        attached = true
        return .success(surface)
    }
}
