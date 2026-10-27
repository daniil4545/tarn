import AppKit

/// `tarn new [--right] [--cwd D] -- <cmd...>`: a split below the caller's pane, or to its right, that
/// runs the command; focus stays where it was (`docs/specs/agent-cli.md` 4.2-4.4). Placement follows
/// WezTerm `cli split-pane` (default bottom) and kitty `launch --keep-focus`.
enum NewPane {
    static let notOneLine = AgentRefusal(text: "command must be one line")

    @MainActor
    static func run(_ message: [String: Any], _ scope: AgentScope) -> Result<[String: Any], AgentRefusal> {
        guard let argv = message["argv"] as? [String], !argv.isEmpty else { return .failure(AgentRefusal(text: "no command")) }
        guard let command = ShellQuote.join(argv) else { return .failure(notOneLine) }
        guard let caller = SessionRegistry.surfaceView(scope.caller.pane),
              let controller = BaseTerminalController.controller(owning: caller)
        else { return .failure(.notInTab) }

        var config = Ghostty.SurfaceConfiguration()
        config.command = command
        config.workingDirectory = (message["cwd"] as? String) ?? caller.workingDirectory
        let direction: SplitTree<Ghostty.SurfaceView>.NewDirection = message["right"] as? Bool == true ? .right : .down
        guard let pane = split(controller, at: caller, direction: direction, config: config) else {
            return .failure(AgentRefusal(text: "split failed"))
        }
        PaneWaits.shared.marks[pane.id] = RunMark(kind: .new, command: command)
        return .success(["pane": pane.id.uuidString])
    }

    /// Inserts a new surface next to `at` and assigns the tree directly: `newSplit` would move the
    /// focus to it and register an undo (`BaseTerminalController.swift:282-316`, `540-582`).
    @MainActor
    static func split(
        _ controller: BaseTerminalController,
        at: Ghostty.SurfaceView,
        direction: SplitTree<Ghostty.SurfaceView>.NewDirection,
        config: Ghostty.SurfaceConfiguration
    ) -> Ghostty.SurfaceView? {
        guard let app = controller.ghostty.app else { return nil }
        let view = Ghostty.SurfaceView(app, baseConfig: config)
        guard let tree = try? controller.surfaceTree.inserting(view: view, at: at, direction: direction) else { return nil }
        let window = controller.window
        let responder = window?.firstResponder
        controller.surfaceTree = tree
        keep(responder, in: window)
        return view
    }

    /// A tree change drops the first responder once SwiftUI rebuilds the split view
    /// (`SurfaceView.swift:1067-1070`); it is given back to whoever had it: a surface as Ghostty does
    /// after a split, any other view (viewer, sidebar field) twice, as `ViewerHost.keepFocus` does.
    @MainActor
    private static func keep(_ responder: NSResponder?, in window: NSWindow?) {
        guard let window, let responder else { return }
        if let surface = responder as? Ghostty.SurfaceView {
            Ghostty.moveFocus(to: surface)
            return
        }
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak window] in
                guard let window, window.firstResponder !== responder else { return }
                window.makeFirstResponder(responder)
            }
        }
    }
}

/// POSIX quoting by the rules of Python `shlex.join`: an argument is quoted only when it has a
/// character outside the safe set. Ghostty takes the command as one shell string.
enum ShellQuote {
    private static let safe = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-")

    /// Nil when an argument has a newline or a carriage return: it would press Enter (B2).
    static func join(_ argv: [String]) -> String? {
        guard !argv.contains(where: { $0.unicodeScalars.contains { $0 == "\n" || $0 == "\r" } }) else { return nil }
        return argv.map(quote).joined(separator: " ")
    }

    static func quote(_ argument: String) -> String {
        if argument.isEmpty { return "''" }
        if argument.allSatisfy(safe.contains) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
