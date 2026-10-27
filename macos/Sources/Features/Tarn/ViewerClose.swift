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

    /// The panes that still need a question. A pane the user just answered Don't Save for is
    /// skipped once: that answer is consumed by the repeated close.
    @MainActor
    static func unsettled(_ models: [ViewerModel]) -> [ViewerModel] {
        models.filter { model in
            if model.discardOnce {
                model.discardOnce = false
                return false
            }
            return !model.dirtyPaths.isEmpty
        }
    }

    /// Runs the repeated close with Don't Save in force: its `intercept` call passes once. The mark is
    /// cleared afterwards, so a path that never asks again cannot leave it behind.
    @MainActor
    static func discardThen(_ models: [ViewerModel], _ proceed: () -> Void) {
        models.forEach { $0.discardOnce = true }
        proceed()
        models.forEach { $0.discardOnce = false }
    }

    /// The windows a close of `window` reaches: its whole tab group, or the window alone.
    @MainActor
    static func members(of window: NSWindow?) -> [NSWindow] {
        window?.tabGroup?.windows ?? window.map { [$0] } ?? []
    }

    /// Runs `proceed` after the user settles unsaved edits of `controllers`. Returns false at once
    /// when nothing is dirty (the caller carries on); true when it took over: `proceed` runs later,
    /// or never on Cancel. Don't Save keeps the edits and lets the repeated close pass once, so a
    /// Cancel in Ghostty's own dialog afterwards loses nothing.
    @MainActor
    static func intercept(_ controllers: [TerminalController], window: NSWindow?, proceed: @escaping () -> Void) -> Bool {
        let models = unsettled(controllers.flatMap(\.viewerHost.models))
        let paths = dirtyPaths(in: models)
        guard !paths.isEmpty else { return false }
        ask(paths, window: window) { choice in
            guard proceeds(choice, saved: { saveAll(models, window: window) }) else { return }
            if choice == .discard { discardThen(models, proceed) } else { proceed() }
        }
        return true
    }

    /// The quit case: `proceed(true)` to carry on with the quit, `proceed(false)` to cancel it.
    /// Returns false when nothing is dirty.
    @MainActor
    static func interceptQuit(proceed: @escaping (Bool) -> Void) -> Bool {
        let models = TerminalController.all.flatMap(\.viewerHost.models).filter { !$0.dirtyPaths.isEmpty }
        let paths = dirtyPaths(in: models)
        guard !paths.isEmpty else { return false }
        let window = NSApp.keyWindow ?? TerminalController.all.first?.window
        ask(paths, window: window) { choice in
            proceed(proceeds(choice, saved: { saveAll(models, window: window) }))
        }
        return true
    }

    /// Saves every dirty file. A file that stays dirty (disk conflict, write error) stops the close
    /// and is named in an alert: the pane may not be visible, so its own notice is not enough.
    @MainActor
    private static func saveAll(_ models: [ViewerModel], window: NSWindow?) -> Bool {
        models.forEach { _ = $0.saveAll() }
        let failed = dirtyPaths(in: models)
        guard !failed.isEmpty else { return true }
        let alert = NSAlert()
        alert.messageText = failed.count == 1
            ? "Cannot save \((failed[0] as NSString).lastPathComponent)"
            : "Cannot save \(failed.count) files"
        alert.informativeText = "The file changed on disk or cannot be written. Nothing was closed. "
            + (FileViewerSetting.isOn
                ? "Open the file in the viewer to take the disk version, keep yours or fix the error.\n"
                : "Switch File viewer on in Settings > Modules to take the disk version, keep yours or fix the error.\n")
            + failed.prefix(8).map { "  \(($0 as NSString).lastPathComponent)" }.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window) { _ in alert.window.orderOut(nil) }
        } else {
            alert.runModal()
        }
        return false
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
