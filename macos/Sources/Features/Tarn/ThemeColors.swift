import GhosttyKit
import SwiftUI

/// One color of a terminal theme, 8 bits per channel. Window colors derive from it by the demo's
/// rule (`demo/js/chrome-theme.js`).
struct ThemeColor: Equatable, Hashable {
    let r: Int
    let g: Int
    let b: Int

    init(r: Int, g: Int, b: Int) {
        self.r = min(255, max(0, r))
        self.g = min(255, max(0, g))
        self.b = min(255, max(0, b))
    }

    /// `#rrggbb` or `rrggbb`; theme files hold both.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(r: value >> 16 & 0xFF, g: value >> 8 & 0xFF, b: value & 0xFF)
    }

    init(_ color: ghostty_config_color_s) {
        self.init(r: Int(color.r), g: Int(color.g), b: Int(color.b))
    }

    var hex: String { String(format: "#%02x%02x%02x", r, g, b) }

    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }

    /// This color with `amount` (0 to 1) of `other` mixed in.
    func mixed(with other: ThemeColor, by amount: Double) -> ThemeColor {
        func channel(_ from: Int, _ to: Int) -> Int { Int((Double(from) + Double(to - from) * amount).rounded()) }
        return ThemeColor(r: channel(r, other.r), g: channel(g, other.g), b: channel(b, other.b))
    }

    /// WCAG relative luminance: 0 black, 1 white.
    var luminance: Double {
        func linear(_ value: Int) -> Double {
            let s = Double(value) / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    var isLight: Bool { luminance > 0.4 }

    /// WCAG contrast ratio, 1 to 21.
    func contrast(with other: ThemeColor) -> Double {
        let (high, low) = (max(luminance, other.luminance), min(luminance, other.luminance))
        return (high + 0.05) / (low + 0.05)
    }

    static let black = ThemeColor(r: 0, g: 0, b: 0)
}

/// The colors a theme sets: background, foreground and the 16 palette colors it names.
struct ThemePalette: Equatable {
    /// Palette indexes the window colors use (ANSI order).
    enum Slot {
        static let red = 1, green = 2, yellow = 3, blue = 4, magenta = 5, cyan = 6, brightBlue = 12
    }

    /// Ghostty's own defaults (`src/config/Config.zig`): a theme file may leave these out.
    static let defaultBackground = ThemeColor(r: 0x28, g: 0x2C, b: 0x34)
    static let defaultForeground = ThemeColor(r: 0xFF, g: 0xFF, b: 0xFF)

    var background = defaultBackground
    var foreground = defaultForeground
    /// Palette index 0...15 to color; a theme may name only some.
    var ansi: [Int: ThemeColor] = [:]

    /// Reads a Ghostty theme file: `background = #rrggbb`, `foreground = ...`, `palette = N=#rrggbb`.
    /// Other lines and comments are skipped. `nil` when the text names no color at all.
    init?(themeFile text: String) {
        var named = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            switch key {
            case "background":
                if let color = ThemeColor(hex: value) { background = color; named = true }
            case "foreground":
                if let color = ThemeColor(hex: value) { foreground = color; named = true }
            case "palette":
                let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2, let index = Int(parts[0]), (0..<16).contains(index),
                   let color = ThemeColor(hex: parts[1]) {
                    ansi[index] = color
                    named = true
                }
            default:
                break
            }
        }
        if !named { return nil }
    }

    init(background: ThemeColor, foreground: ThemeColor, ansi: [Int: ThemeColor] = [:]) {
        self.background = background
        self.foreground = foreground
        self.ansi = ansi
    }

    /// The effective colors of a loaded config, whatever sets them: the theme or the user's own lines.
    init?(config: Ghostty.Config) {
        guard let cfg = config.config else { return nil }
        func color(_ key: String) -> ThemeColor? {
            var value = ghostty_config_color_s()
            return ghostty_config_get(cfg, &value, key, UInt(key.utf8.count)) ? ThemeColor(value) : nil
        }
        var palette = ghostty_config_palette_s()
        let key = "palette"
        guard let background = color("background"), let foreground = color("foreground"),
              ghostty_config_get(cfg, &palette, key, UInt(key.utf8.count))
        else { return nil }
        var ansi: [Int: ThemeColor] = [:]
        withUnsafeBytes(of: &palette.colors) { bytes in
            let colors = bytes.bindMemory(to: ghostty_config_color_s.self)
            for index in 0..<16 { ansi[index] = ThemeColor(colors[index]) }
        }
        self.init(background: background, foreground: foreground, ansi: ansi)
    }

    /// The accent: the first of blue, bright blue, cyan, magenta with contrast 3:1 against the
    /// background, else the text color.
    var accent: ThemeColor {
        [Slot.blue, Slot.brightBlue, Slot.cyan, Slot.magenta]
            .compactMap { ansi[$0] }
            .first { $0.contrast(with: background) >= 3 } ?? foreground
    }
}

/// Every color the sidebar and the viewer need, derived from a theme with one rule for all themes.
struct ThemeChrome: Equatable {
    /// How far the text color is mixed into the background for each surface.
    enum Mix {
        static let surface = 0.06, line = 0.16, code = 0.05
        static let muted = 0.38, key = 0.55
        static let dividerLight = 0.22, dividerDark = 0.45
        /// `muted` mixes less where `Mix.muted` falls below this contrast (light themes).
        static let mutedContrast = 4.5
    }

    /// The text color faded toward the background by `amount`, or less if that drops below `floor`.
    static func fade(_ fg: ThemeColor, toward bg: ThemeColor, by amount: Double, floor: Double) -> ThemeColor {
        var amount = amount
        while amount > 0, fg.mixed(with: bg, by: amount).contrast(with: bg) < floor {
            amount = max(0, amount - 0.02)
        }
        return fg.mixed(with: bg, by: amount)
    }

    let isLight: Bool
    let background: ThemeColor
    let foreground: ThemeColor
    /// Sidebar and title bar.
    let surface: ThemeColor
    let line: ThemeColor
    /// The line between the sidebar and the terminal.
    let divider: ThemeColor
    let muted: ThemeColor
    /// Fainter than `muted`: key hints, counts.
    let key: ThemeColor
    let code: ThemeColor
    let accent: ThemeColor

    init(_ palette: ThemePalette) {
        let bg = palette.background, fg = palette.foreground
        isLight = bg.isLight
        background = bg
        foreground = fg
        surface = bg.mixed(with: fg, by: Mix.surface)
        line = bg.mixed(with: fg, by: Mix.line)
        divider = bg.mixed(with: .black, by: bg.isLight ? Mix.dividerLight : Mix.dividerDark)
        muted = Self.fade(fg, toward: bg, by: Mix.muted, floor: Mix.mutedContrast)
        key = fg.mixed(with: bg, by: Mix.key)
        code = bg.mixed(with: fg, by: Mix.code)
        accent = palette.accent
    }

    static let viewerVariableNames = ["--p-bg", "--p-bar", "--p-fg", "--p-muted", "--p-line", "--p-code", "--p-accent"]

    /// The `--p-*` custom properties of the viewer page (`viewer-web/src/viewer.css`).
    var viewerVariables: [String: String] {
        [
            "--p-bg": background.hex, "--p-bar": surface.hex, "--p-fg": foreground.hex,
            "--p-muted": muted.hex, "--p-line": line.hex, "--p-code": code.hex, "--p-accent": accent.hex,
        ]
    }

    /// The window colors of a loaded config, or `nil` when the window keeps the built-in palettes:
    /// `window-theme` is `system`, `light` or `dark` (`auto` and `ghostty` follow the terminal colors).
    @MainActor static func current(for config: Ghostty.Config) -> ThemeChrome? {
        if let windowTheme = config.windowTheme, ["system", "light", "dark"].contains(windowTheme) { return nil }
        return cached(config) { ThemePalette(config: $0).map(ThemeChrome.init) }
    }

    /// One entry: the sidebar asks on each layout, and a config changes rarely.
    /// The config is held weakly: an identity of a freed config could come back for a new one.
    private struct CacheEntry {
        weak var config: Ghostty.Config?
        let chrome: ThemeChrome?
    }

    @MainActor private static var cache: CacheEntry?

    @MainActor private static func cached(_ config: Ghostty.Config, _ make: (Ghostty.Config) -> ThemeChrome?) -> ThemeChrome? {
        if let cache, cache.config === config { return cache.chrome }
        let chrome = make(config)
        cache = CacheEntry(config: config, chrome: chrome)
        return chrome
    }
}

/// What the sidebar draws with: the theme colors, or the system ones when there is no theme.
struct ChromeInk {
    var theme: ThemeChrome?

    /// Text at an opacity; the fills of hover and selection use the same color.
    func text(_ opacity: Double = 1) -> Color {
        theme.map { $0.foreground.color.opacity(opacity) } ?? Color.primary.opacity(opacity)
    }

    var muted: Color { theme?.muted.color ?? Color.secondary }
    var faint: Color { theme?.key.color ?? Color(nsColor: .tertiaryLabelColor) }
    var accent: Color { theme?.accent.color ?? Color.accentColor }
    var groupBackground: Color { theme.map { $0.surface.mixed(with: $0.foreground, by: 0.04).color } ?? text(0.04) }
    var divider: Color { theme?.divider.color ?? Color.primary.opacity(0.12) }
}

private struct ChromeInkKey: EnvironmentKey {
    static let defaultValue = ChromeInk(theme: nil)
}

extension EnvironmentValues {
    var chromeInk: ChromeInk {
        get { self[ChromeInkKey.self] }
        set { self[ChromeInkKey.self] = newValue }
    }
}
