import Foundation
import Testing
@testable import Ghostty

/// The settings store against a temp file (`docs/plans/s4-settings.md` section 4).
@MainActor
@Suite
struct GhosttyOptionStoreTests {
    private func makeStore(
        _ text: String? = nil,
        config: Ghostty.Config? = nil,
        reload: @escaping () -> Void = {}
    ) throws -> (GhosttyOptionStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("ghostty.conf")
        if let text { try text.write(to: url, atomically: true, encoding: .utf8) }
        return (GhosttyOptionStore(url: url, config: config, reload: reload), url)
    }

    private func option(_ key: String) -> GhosttyOption {
        GhosttyOption.option(key)!
    }

    private func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") }
    }

    @Test func setWritesTheLineAndReloads() throws {
        var reloads = 0
        let (store, url) = try makeStore { reloads += 1 }
        store.set(option("font-size"), to: "16")
        #expect(try lines(url) == ["font-size = 16"])
        #expect(store.isSet(option("font-size")))
        #expect(reloads == 1)
    }

    @Test func aValueEqualToTheDefaultStillWritesItsLine() throws {
        let (store, url) = try makeStore()
        store.set(option("font-size"), to: "13")
        #expect(try lines(url) == ["font-size = 13"])
    }

    @Test func resetRemovesOnlyThatLine() throws {
        let (store, url) = try makeStore("# mine\nfont-size = 16\ndrag-handle = never\n")
        store.reset(option("drag-handle"))
        #expect(try lines(url) == ["font-size = 16"])
        #expect(try String(contentsOf: url, encoding: .utf8).contains("# mine"))
        #expect(!store.isSet(option("drag-handle")))
    }

    /// The user's own config says `false`; picking "default (auto)" must not bring it back.
    @Test func theDefaultEntryOfAnOptionalOptionWritesAnEmptyValue() throws {
        let user = try TemporaryConfig("cursor-style-blink = false")
        let (store, url) = try makeStore(config: user)
        store.set(option("cursor-style-blink"), to: "")
        #expect(try lines(url) == ["cursor-style-blink = \"\""])
        #expect(store.isSet(option("cursor-style-blink")))
        #expect(store.display(option("cursor-style-blink")) == .value(""))
        // Ghostty reads the empty value as the default, over the user's line.
        let effective = try TemporaryConfig("cursor-style-blink = false\n\(String(contentsOf: url, encoding: .utf8))")
        #expect(GhosttyOptionReader.value(of: option("cursor-style-blink"), in: effective) == nil)
        store.reset(option("cursor-style-blink"))
        #expect(try lines(url).isEmpty)
    }

    @Test func aNumberTheTypeDoesNotTakeIsReportedAndNotWritten() throws {
        let (store, url) = try makeStore()
        store.set(option("window-padding-x"), to: "5.5")
        #expect(store.errors["window-padding-x"]?.contains("whole number") == true)
        store.set(option("font-size"), to: "99")
        store.set(option("font-size"), to: "abc")
        #expect(store.errors["font-size"] != nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        store.set(option("font-size"), to: "13.5")
        #expect(try lines(url) == ["font-size = 13.5"])
        store.set(option("window-padding-x"), to: "6")
        #expect(store.errors["window-padding-x"] == nil)
    }

    @Test func aFractionInTheFileForAWholeNumberShowsRaw() throws {
        let (store, _) = try makeStore("window-padding-x = 5.5\n")
        #expect(store.display(option("window-padding-x")) == .raw("5.5"))
    }

    @Test func clearingFontFamilyWritesOneClearLine() throws {
        let (store, url) = try makeStore()
        store.set(option("font-family"), to: "")
        #expect(try lines(url) == ["font-family = \"\""])
    }

    @Test func linesFollowCatalogOrder() throws {
        let (store, url) = try makeStore()
        store.set(option("drag-handle"), to: "never")
        store.set(option("font-size"), to: "16")
        store.set(option("copy-on-select"), to: "clipboard")
        #expect(try lines(url) == ["font-size = 16", "copy-on-select = clipboard", "drag-handle = never"])
    }

    @Test func fontFamilyClearsTheListFirstAndKeepsOrder() throws {
        let (store, url) = try makeStore()
        store.set(option("font-size"), to: "16")
        store.set(option("font-family"), to: "Menlo")
        #expect(try lines(url) == ["font-family = \"\"", "font-family = Menlo", "font-size = 16"])
    }

    @Test func aHandEditBetweenTwoWritesIsKept() throws {
        let (store, url) = try makeStore()
        store.set(option("font-size"), to: "16")
        try "font-size = 16\nlink-url = false\n".write(to: url, atomically: true, encoding: .utf8)
        store.set(option("drag-handle"), to: "never")
        #expect(try lines(url) == ["link-url = false", "font-size = 16", "drag-handle = never"].sorted { a, b in
            let order = GhosttyOption.all.map(\.key)
            return order.firstIndex(of: String(a.split(separator: " ")[0]))! < order.firstIndex(of: String(b.split(separator: " ")[0]))!
        })
    }

    @Test func aFailedWriteReportsInTheRowAndDoesNotReload() throws {
        var reloads = 0
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The parent of the file is a regular file, so the directory cannot be created.
        let blocker = dir.appendingPathComponent("blocker")
        try "x".write(to: blocker, atomically: true, encoding: .utf8)
        let store = GhosttyOptionStore(url: blocker.appendingPathComponent("ghostty.conf"), config: nil) { reloads += 1 }
        store.set(option("font-size"), to: "16")
        #expect(store.errors["font-size"] != nil)
        #expect(!store.isSet(option("font-size")))
        #expect(reloads == 0)
        #expect(try String(contentsOf: blocker, encoding: .utf8) == "x")
    }

    @Test func aValueWithALineBreakIsRejected() throws {
        let (store, url) = try makeStore()
        store.set(option("font-family"), to: "A\nB")
        #expect(store.errors["font-family"] != nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func aSuccessClearsTheOldError() throws {
        let (store, _) = try makeStore()
        store.set(option("font-size"), to: "abc")
        #expect(store.errors["font-size"] != nil)
        store.set(option("font-size"), to: "16")
        #expect(store.errors["font-size"] == nil)
    }

    @Test func aValueTheControlCannotShowIsRaw() throws {
        let (store, _) = try makeStore("undo-timeout = 7s\nbackground-blur = 20\n")
        #expect(store.display(option("undo-timeout")) == .raw("7s"))
        #expect(store.display(option("background-blur")) == .raw("20"))
        store.reset(option("undo-timeout"))
        #expect(store.display(option("undo-timeout")) == .value("5s"))
    }

    @Test func unreadableOptionsSayFromGhosttyConfigUnlessSet() throws {
        let config = try TemporaryConfig("")
        let (store, _) = try makeStore(config: config)
        #expect(store.display(option("theme")) == .fromGhosttyConfig)
        #expect(store.display(option("font-size")) == .value("13"))
        store.set(option("theme"), to: "Nord")
        #expect(store.display(option("theme")) == .value("Nord"))
    }

    @Test func theNotificationConfigIsTakenOnlyForTheApp() throws {
        let (store, _) = try makeStore(config: try TemporaryConfig(""))
        let new = try TemporaryConfig("font-size = 20")
        let key = Notification.Name.GhosttyConfigChangeKey
        store.configDidChange(Notification(name: .ghosttyConfigDidChange, object: NSObject(), userInfo: [key: new]))
        #expect(store.display(option("font-size")) == .value("13"))
        store.configDidChange(Notification(name: .ghosttyConfigDidChange, object: nil, userInfo: [key: new]))
        #expect(store.display(option("font-size")) == .value("20"))
    }
}
