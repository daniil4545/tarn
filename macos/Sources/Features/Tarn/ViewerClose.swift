import AppKit

/// Asks about unsaved viewer edits when a window, a tab or the app closes. It hooks the same
/// entry points as Ghostty's close confirmation (`TerminalController.closeTab`, `closeWindow`,
/// `AppDelegate.applicationShouldTerminate`) and shows one sheet for all dirty files.
enum ViewerClose {
    enum Choice: Equatable {
        case save, discard, cancel
    }

    /// Maps the sheet button to a choice: Save, Don't Save, Cancel (or Escape).
    static func choice(for response: NSApplication.ModalResponse) -> Choice {
        switch response {
        case .alertFirstButtonReturn: .save
        case .alertSecondButtonReturn: .discard
        default: .cancel
        }
    }

    /// Whether the close goes on after the user's choice. Save needs every file written.
    static func proceeds(_ choice: Choice, saved: () -> Bool) -> Bool {
        switch choice {
        case .save: saved()
        case .discard: true
        case .cancel: false
        }
    }

    /// Dirty paths of the given panes, in order, without repeats.
    @MainActor
    static func dirtyPaths(in models: [ViewerModel]) -> [String] {
        var seen = Set<String>()
        return models.flatMap(\.dirtyPaths).filter { seen.insert($0).inserted }
    }

    static func message(for paths: [String]) -> (title: String, detail: String) {
        let names = paths.prefix(8).map { "  \(($0 as NSString).lastPathComponent)" }
        let more = paths.count > 8 ? ["  and \(paths.count - 8) more"] : []
        let title = paths.count == 1
            ? "Save changes to \((paths[0] as NSString).lastPathComponent)?"
            : "Save changes to \(paths.count) files?"
        return (title, (["Your changes are lost if you do not save them."] + names + more).joined(separator: "\n"))
    }

    /// Runs `proceed` after the user settles unsaved edits of `controllers`. Returns false at once
    /// when nothing is dirty (the caller carries on); true when it took over: `proceed` runs later,
    /// or never on Cancel. Don't Save drops the edits first, so the repeated close finds nothing dirty.
    @MainActor
    static func intercept(_ controllers: [TerminalController], window: NSWindow?, proceed: @escaping () -> Void) -> Bool {
        let models = controllers.compactMap(\.viewerHost.model)
        let paths = dirtyPaths(in: models)
        guard !paths.isEmpty else { return false }
        ask(paths, window: window) { choice in
            guard proceeds(choice, saved: { models.allSatisfy { $0.saveAll() } }) else { return }
            if choice == .discard { models.forEach { $0.discardEdits() } }
            proceed()
        }
        return true
    }

    /// The quit case: `proceed(true)` to carry on with the quit, `proceed(false)` to cancel it.
    /// Returns false when nothing is dirty.
    @MainActor
    static func interceptQuit(proceed: @escaping (Bool) -> Void) -> Bool {
        let models = TerminalController.all.compactMap(\.viewerHost.model)
        let paths = dirtyPaths(in: models)
        guard !paths.isEmpty else { return false }
        ask(paths, window: NSApp.keyWindow ?? TerminalController.all.first?.window) { choice in
            proceed(proceeds(choice, saved: { models.allSatisfy { $0.saveAll() } }))
        }
        return true
    }

    @MainActor
    private static func ask(_ paths: [String], window: NSWindow?, completion: @escaping (Choice) -> Void) {
        let text = message(for: paths)
        let alert = NSAlert()
        alert.messageText = text.title
        alert.informativeText = text.detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        guard let window else { return completion(choice(for: alert.runModal())) }
        alert.beginSheetModal(for: window) { response in
            // Same as Ghostty's confirmation: keep focus with Stage Manager.
            alert.window.orderOut(nil)
            completion(choice(for: response))
        }
    }
}
