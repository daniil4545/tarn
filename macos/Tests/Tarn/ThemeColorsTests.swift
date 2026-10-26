import Foundation
import Testing
@testable import Ghostty

/// The window colors derived from a terminal theme (`docs/modules/settings.md`).
@MainActor
@Suite
struct ThemeColorsTests {
    private static let dracula = """
    palette = 0=#21222c
    palette = 1=#ff5555
    palette = 2=#50fa7b
    palette = 3=#f1fa8c
    palette = 4=#bd93f9
    palette = 5=#ff79c6
    palette = 6=#8be9fd
    background = #282a36
    foreground = #f8f8f2
    cursor-color = #f8f8f2
    """

    private static let latte = """
    palette = 1=#d20f39
    palette = 4=#1e66f5
    palette = 5=#ea76cb
    palette = 6=#179299
    palette = 12=#456eff
    background = #eff1f5
    foreground = #4c4f69
    """

    private func color(_ hex: String) -> ThemeColor { ThemeColor(hex: hex)! }

    // MARK: - Color math

    @Test func hexRoundTripsWithAndWithoutHash() {
        #expect(ThemeColor(hex: "#282a36")?.hex == "#282a36")
        #expect(ThemeColor(hex: "282A36")?.hex == "#282a36")
        #expect(ThemeColor(hex: "#28") == nil)
        #expect(ThemeColor(hex: "#gggggg") == nil)
    }

    @Test func contrastOfBlackAndWhiteIsTwentyOne() {
        #expect(abs(color("#ffffff").contrast(with: .black) - 21) < 0.001)
        #expect(abs(color("#777777").contrast(with: color("#777777")) - 1) < 0.001)
    }

    @Test func mixMovesEachChannelByTheAmount() {
        #expect(color("#000000").mixed(with: color("#ffffff"), by: 0.5).hex == "#808080")
        #expect(color("#282a36").mixed(with: color("#f8f8f2"), by: 0).hex == "#282a36")
        #expect(color("#282a36").mixed(with: color("#f8f8f2"), by: 1).hex == "#f8f8f2")
    }

    // MARK: - Reading a theme file

    @Test func aThemeFileGivesBackgroundTextAndPalette() throws {
        let palette = try #require(ThemePalette(themeFile: Self.dracula))
        #expect(palette.background.hex == "#282a36")
        #expect(palette.foreground.hex == "#f8f8f2")
        #expect(palette.ansi[ThemePalette.Slot.blue]?.hex == "#bd93f9")
        #expect(palette.ansi.count == 7)
    }

    @Test func commentsBlankLinesAndOtherKeysAreSkipped() throws {
        let palette = try #require(ThemePalette(themeFile: "# note\n\nbackground = 101010\nselection-background = #ffffff\n"))
        #expect(palette.background.hex == "#101010")
        #expect(palette.foreground == ThemePalette.defaultForeground)
    }

    @Test func aBadPaletteLineIsSkipped() throws {
        let text = "palette = 99=#ffffff\npalette = x=#ffffff\npalette = 4=zzz\npalette = 4=#112233\nbackground = #000000"
        let palette = try #require(ThemePalette(themeFile: text))
        #expect(palette.ansi == [4: color("#112233")])
    }

    @Test func aFileWithNoColorIsNotATheme() {
        #expect(ThemePalette(themeFile: "") == nil)
        #expect(ThemePalette(themeFile: "font-size = 12\n") == nil)
    }

    @Test func aConfigGivesTheEffectiveColors() throws {
        let config = try TemporaryConfig("background = #101010\nforeground = #eeeeee\npalette = 4=#5599ff\npalette = 12=#77bbff")
        let palette = try #require(ThemePalette(config: config))
        #expect(palette.background.hex == "#101010")
        #expect(palette.foreground.hex == "#eeeeee")
        #expect(palette.ansi[4]?.hex == "#5599ff")
        #expect(palette.ansi[12]?.hex == "#77bbff")
        #expect(palette.ansi.count == 16)
    }

    // MARK: - The window colors

    @Test func aDarkThemeGivesDarkWindowColors() throws {
        let chrome = ThemeChrome(try #require(ThemePalette(themeFile: Self.dracula)))
        #expect(!chrome.isLight)
        #expect(chrome.surface.hex == "#343641")
        #expect(chrome.accent.hex == "#bd93f9")
        // The divider is darker than the background.
        #expect(chrome.divider.luminance < chrome.background.luminance)
        #expect(chrome.muted.luminance < chrome.foreground.luminance)
    }

    @Test func aLightThemeGivesLightWindowColors() throws {
        let chrome = ThemeChrome(try #require(ThemePalette(themeFile: Self.latte)))
        #expect(chrome.isLight)
        #expect(chrome.surface.luminance < chrome.background.luminance)
        #expect(chrome.divider.luminance < chrome.surface.luminance)
        #expect(chrome.accent.hex == "#1e66f5")
        // Text on the sidebar stays readable; muted text is weaker than text but still apart from the surface.
        // The demo rule gives Latte muted text 2.66:1 (report W-G); the rule is kept as the user approved it.
        #expect(chrome.foreground.contrast(with: chrome.surface) >= 4.5)
        #expect(chrome.muted.contrast(with: chrome.surface) > 2.5)
        #expect(chrome.muted.contrast(with: chrome.surface) < chrome.foreground.contrast(with: chrome.surface))
    }

    @Test func theAccentSkipsAColorBelowThreeToOne() {
        // Blue and bright blue are close to the background; cyan is the first that reads.
        let palette = ThemePalette(
            background: color("#000000"), foreground: color("#ffffff"),
            ansi: [4: color("#0a0a2a"), 12: color("#111133"), 6: color("#00cccc"), 5: color("#ff00ff")])
        #expect(palette.accent.hex == "#00cccc")
    }

    @Test func theAccentIsTheTextColorWhenNoPaletteColorReads() {
        let palette = ThemePalette(
            background: color("#000000"), foreground: color("#eeeeee"),
            ansi: [4: color("#0a0a2a"), 12: color("#111133")])
        #expect(palette.accent.hex == "#eeeeee")
        #expect(ThemePalette(background: .black, foreground: color("#eeeeee")).accent.hex == "#eeeeee")
    }

    /// The rule holds for every installed theme: the accent reads at 3:1 or is the text color, and
    /// the light or dark class follows the background.
    @Test func everyInstalledThemeGivesReadableColors() throws {
        let catalog = ThemeCatalog(folders: ThemeCatalogTests.installedFolders())
        let names = catalog.names
        try #require(!names.isEmpty, "no installed themes found")
        for name in names {
            guard let palette = catalog.palette(of: name) else { continue }
            let chrome = ThemeChrome(palette)
            #expect(chrome.accent == chrome.foreground || chrome.accent.contrast(with: chrome.background) >= 3, "\(name)")
            #expect(chrome.isLight == palette.background.isLight, "\(name)")
        }
    }

    // MARK: - From the config

    @Test func theTerminalColorsRuleWhenWindowThemeIsAuto() throws {
        let config = try TemporaryConfig("background = #101010\nforeground = #eeeeee")
        #expect(ThemeChrome.current(for: config)?.background.hex == "#101010")
        let ghostty = try TemporaryConfig("window-theme = ghostty\nbackground = #101010")
        #expect(ThemeChrome.current(for: ghostty) != nil)
    }

    @Test(arguments: ["system", "light", "dark"])
    func theBuiltInPalettesRuleWhenWindowThemeSaysSo(value: String) throws {
        let config = try TemporaryConfig("window-theme = \(value)\nbackground = #101010")
        #expect(ThemeChrome.current(for: config) == nil)
    }

    // MARK: - The viewer page

    @Test func theViewerGetsTheSevenVariables() throws {
        let chrome = ThemeChrome(try #require(ThemePalette(themeFile: Self.dracula)))
        let variables = chrome.viewerVariables
        #expect(Set(variables.keys) == Set(ThemeChrome.viewerVariableNames))
        #expect(variables["--p-bg"] == "#282a36")
        #expect(variables["--p-accent"] == "#bd93f9")
        let script = ViewerColors.script(for: chrome)
        #expect(script.contains("\"--p-bg\":\"#282a36\""))
    }

    @Test func noThemeClearsTheViewerVariables() {
        let script = ViewerColors.script(for: nil)
        for name in ThemeChrome.viewerVariableNames {
            #expect(script.contains("\"\(name)\":null"), "\(name)")
        }
    }
}

/// The theme folders and the base list.
@Suite
struct ThemeCatalogTests {
    /// The themes of the app bundle, or of the build output next to the sources.
    static func installedFolders() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return [
            Bundle.main.resourceURL?.appendingPathComponent("ghostty/themes"),
            root.appendingPathComponent("zig-out/share/ghostty/themes"),
        ].compactMap { $0 }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func makeFolder(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, text) in files { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        return dir
    }

    @Test func theBaseListHoldsSevenThemesAndNoPair() {
        #expect(ThemeCatalog.baseNames == [
            "Catppuccin Latte", "Catppuccin Mocha", "Atom One Light", "Atom One Dark",
            "Gruvbox Light", "Gruvbox Dark", "Dracula",
        ])
        #expect(Set(ThemeCatalog.baseNames).count == 7)
    }

    @Test func everyBaseThemeIsAnInstalledTheme() throws {
        let catalog = ThemeCatalog(folders: Self.installedFolders())
        let names = catalog.names
        try #require(!names.isEmpty, "no installed themes found")
        #expect(catalog.base(among: names) == ThemeCatalog.baseNames)
        for name in ThemeCatalog.baseNames {
            #expect(catalog.palette(of: name) != nil, "\(name)")
        }
    }

    @Test func theRestIsEveryThemeBelowTheBaseList() throws {
        let catalog = ThemeCatalog(folders: Self.installedFolders())
        let names = catalog.names
        let rest = catalog.rest(among: names)
        #expect(rest.count == names.count - ThemeCatalog.baseNames.count)
        #expect(Set(rest).isDisjoint(with: ThemeCatalog.baseNames))
    }

    @Test func aMissingBaseThemeLeavesTheListShorter() {
        #expect(ThemeCatalog(folders: []).base(among: ["Dracula", "Other"]) == ["Dracula"])
    }

    @Test func namesFromBothFoldersShowOnceAndSorted() throws {
        let user = try makeFolder(["zebra": "background = #000000", "Dracula": "background = #111111", ".hidden": ""])
        let app = try makeFolder(["Dracula": "background = #222222", "alpha": "background = #333333"])
        let catalog = ThemeCatalog(folders: [user, app])
        #expect(catalog.names == ["alpha", "Dracula", "zebra"])
        // The user's folder wins, as in Ghostty.
        #expect(catalog.palette(of: "Dracula")?.background.hex == "#111111")
    }

    @Test func aNameWithAPathIsNotATheme() throws {
        let folder = try makeFolder(["inside": "background = #000000"])
        let catalog = ThemeCatalog(folders: [folder])
        #expect(catalog.palette(of: "../inside") == nil)
        #expect(catalog.palette(of: "") == nil)
        #expect(catalog.palette(of: "missing") == nil)
    }

    @Test func theUserFolderFollowsXdgConfigHome() {
        let folders = ThemeCatalog.defaultFolders(environment: ["XDG_CONFIG_HOME": "/x/cfg"], resources: URL(fileURLWithPath: "/app/Res"))
        #expect(folders.map(\.path) == ["/x/cfg/ghostty/themes", "/app/Res/ghostty/themes"])
        let relative = ThemeCatalog.defaultFolders(environment: ["XDG_CONFIG_HOME": "cfg"], resources: nil)
        #expect(relative.count == 1)
        #expect(relative[0].path.hasSuffix("/.config/ghostty/themes"))
    }
}

/// Cmd+W and Close Window reach the settings window through `close:` and `closeWindow:`.
@MainActor
@Suite
struct SettingsWindowCloseTests {
    @Test func theSettingsControllerAnswersTheCloseMenuActions() {
        let controller = TarnSettingsController.shared
        #expect(controller.responds(to: NSSelectorFromString("close:")))
        #expect(controller.responds(to: NSSelectorFromString("closeWindow:")))
    }
}
