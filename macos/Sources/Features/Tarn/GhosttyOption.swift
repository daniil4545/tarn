import Foundation

/// One Ghostty option the settings window edits: the mockup's `GHOSTTY` table as data
/// (`docs/plans/s4-settings.md` sections 1.4 and 2). Names, values and defaults follow
/// `src/config/Config.zig`; `GhosttyOptionTests` checks the defaults against a loaded config.
struct GhosttyOption: Identifiable, Equatable {
    enum Section: CaseIterable {
        case appearance, terminal, windows
    }

    /// The control the row draws, and so the values a file line may hold.
    enum Control: Equatable {
        case toggle
        /// An empty string in the list is the default entry ("default (auto)" for optional options).
        case choice([String])
        /// A list of installed themes, filled by the pane: names are not a fixed set.
        case theme
        case number(ClosedRange<Double>)
        case slider(ClosedRange<Double>, step: Double)
        case text
    }

    /// When a changed value shows up.
    enum Applies: Equatable {
        case live
        case newWindows
        case restart
    }

    /// How `ghostty_config_get` returns the effective value. `unreadable`: a struct without `cval`.
    enum Reading: Equatable {
        case bool, float32, float64, tag, blur, duration, unreadable
    }

    let key: String
    let section: Section
    let control: Control
    /// The Ghostty default in file syntax; empty for an unset optional option.
    let defaultValue: String
    let reading: Reading
    var applies: Applies = .live
    /// A repeatable option: the file clears the list first, else the tarn value is only a fallback.
    var repeatable = false
    let help: String

    var id: String { key }

    /// The file lines for a value: `font-family` becomes an empty clear line plus the value.
    func fileValues(for value: String) -> [String] {
        repeatable ? ["", value] : [value]
    }

    static func option(_ key: String) -> GhosttyOption? {
        all.first { $0.key == key }
    }

    static func options(in section: Section) -> [GhosttyOption] {
        all.filter { $0.section == section }
    }

    /// Catalog order is the order of rows in the window and of lines in the file.
    static let all: [GhosttyOption] = [
        GhosttyOption(key: "theme", section: .appearance, control: .theme, defaultValue: "", reading: .unreadable,
                      help: "Color theme. The app lists the installed themes."),
        GhosttyOption(key: "window-theme", section: .appearance,
                      control: .choice(["auto", "system", "light", "dark", "ghostty"]), defaultValue: "auto", reading: .tag,
                      help: "Window chrome: follow the system or the terminal colors."),
        GhosttyOption(key: "font-family", section: .appearance, control: .text, defaultValue: "", reading: .unreadable,
                      repeatable: true,
                      help: "Empty uses the built-in JetBrains Mono. The file starts the list over, so this font replaces the one in your Ghostty config."),
        GhosttyOption(key: "font-size", section: .appearance, control: .number(6...32), defaultValue: "13", reading: .float32,
                      help: "Points. A terminal where you pressed cmd+= or cmd+- keeps its own size."),
        GhosttyOption(key: "background-opacity", section: .appearance, control: .slider(0.3...1, step: 0.05),
                      defaultValue: "1", reading: .float64, applies: .restart,
                      help: "Below 1 the desktop shows through."),
        GhosttyOption(key: "background-blur", section: .appearance, control: .toggle, defaultValue: "false", reading: .blur,
                      help: "Blurs what shows through a transparent background. A radius or glass value in the file shows as text."),
        GhosttyOption(key: "window-padding-x", section: .appearance, control: .number(0...40), defaultValue: "2",
                      reading: .unreadable,
                      help: "Space between the window edge and the text, in points."),
        GhosttyOption(key: "unfocused-split-opacity", section: .appearance, control: .slider(0.15...1, step: 0.05),
                      defaultValue: "0.7", reading: .float64,
                      help: "How much an unfocused split is dimmed."),
        GhosttyOption(key: "cursor-style", section: .appearance, control: .choice(["block", "bar", "underline"]),
                      defaultValue: "block", reading: .tag,
                      help: "Shell integration shows a bar at the prompt."),
        GhosttyOption(key: "cursor-style-blink", section: .appearance, control: .choice(["", "true", "false"]),
                      defaultValue: "", reading: .bool,
                      help: "Default follows the program (DEC mode 12); true or false forces it."),
        GhosttyOption(key: "macos-titlebar-style", section: .appearance,
                      control: .choice(["transparent", "native", "hidden"]), defaultValue: "transparent", reading: .tag,
                      applies: .newWindows,
                      help: "How the title bar looks."),

        GhosttyOption(key: "copy-on-select", section: .terminal, control: .choice(["none", "clipboard"]),
                      defaultValue: "none", reading: .tag,
                      help: "Copy selected text without cmd+C."),
        GhosttyOption(key: "mouse-hide-while-typing", section: .terminal, control: .toggle, defaultValue: "false",
                      reading: .bool,
                      help: "Hide the pointer while typing."),
        GhosttyOption(key: "clipboard-paste-protection", section: .terminal, control: .toggle, defaultValue: "true",
                      reading: .bool,
                      help: "Ask before pasting text that may run commands."),
        GhosttyOption(key: "macos-option-as-alt", section: .terminal,
                      control: .choice(["", "false", "true", "left", "right"]), defaultValue: "", reading: .tag,
                      help: "Option sends Alt instead of special characters. Default: on for US layouts, off for others."),
        GhosttyOption(key: "link-url", section: .terminal, control: .toggle, defaultValue: "true", reading: .bool,
                      help: "Cmd+click opens URLs."),
        GhosttyOption(key: "notify-on-command-finish", section: .terminal,
                      control: .choice(["never", "unfocused", "always"]), defaultValue: "never", reading: .tag,
                      help: "Rings the bell when a command that ran over 5 seconds finishes while the window is not focused."),

        GhosttyOption(key: "window-save-state", section: .windows, control: .choice(["default", "never", "always"]),
                      defaultValue: "default", reading: .tag,
                      help: "Restore windows, tabs and splits on launch; default follows macOS."),
        GhosttyOption(key: "confirm-close-surface", section: .windows, control: .choice(["true", "false", "always"]),
                      defaultValue: "true", reading: .tag,
                      help: "Ask before closing a terminal with a running program."),
        GhosttyOption(key: "window-inherit-working-directory", section: .windows, control: .toggle, defaultValue: "true",
                      reading: .bool,
                      help: "A new tab or split starts in the focused tab's folder."),
        GhosttyOption(key: "undo-timeout", section: .windows, control: .choice(["0s", "5s", "10s", "30s"]),
                      defaultValue: "5s", reading: .duration,
                      help: "How long cmd+Z can bring back a closed pane or tab."),
        GhosttyOption(key: "drag-handle", section: .windows, control: .choice(["auto", "always", "never"]),
                      defaultValue: "auto", reading: .tag,
                      help: "The three dots that drag a pane: on hover, always or never."),
    ]
}
