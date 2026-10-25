import Foundation
import Testing
@testable import Ghostty
import GhosttyKit

/// The tarn options file: writer, load order and atomic save (`docs/plans/s4-settings.md` section 4).
/// Every test passes its own temp folder as `tarnFile`; the real `~/.config/tarn` is never read.
@Suite
struct TarnConfigFileTests {
    /// A temp folder with the user's config and the tarn file; removed on deinit.
    final class Sandbox {
        let dir: URL
        var user: URL { dir.appendingPathComponent("user.conf") }
        var tarn: URL { dir.appendingPathComponent("tarn/ghostty.conf") }

        init() throws {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        deinit {
            let fm = FileManager.default
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.appendingPathComponent("tarn").path)
            try? fm.removeItem(at: dir)
        }

        func write(_ name: String, _ text: String) throws {
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        /// The config as the app builds it: user file, includes, then the tarn file, then finalize.
        func config(_ tarnFile: URL? = nil) -> Ghostty.Config {
            Ghostty.Config(config: Ghostty.Config.loadConfig(at: user.path, finalize: true, tarnFile: tarnFile ?? tarn))
        }
    }

    private func fontSize(_ config: Ghostty.Config) -> Float {
        var v: Float = 0
        let key = "font-size"
        _ = ghostty_config_get(config.config, &v, key, UInt(key.utf8.count))
        return v
    }

    private func text(_ config: Ghostty.Config, _ key: String) -> String? {
        var v: UnsafePointer<Int8>?
        guard ghostty_config_get(config.config, &v, key, UInt(key.utf8.count)), let v else { return nil }
        return String(cString: v)
    }

    // MARK: - Writer

    @Test func serializeThenParseIsIdentical() throws {
        var file = TarnConfigFile()
        try file.set("font-size", to: "16")
        try file.set("window-title-font-family", to: "  spaced  ")
        try file.set("title", to: "a \"quoted\" # hash \\ slash")
        try file.set("working-directory", to: "")
        try file.set("command", to: "\"wrapped\"")
        let again = TarnConfigFile(parsing: file.text)
        #expect(again == file)
        #expect(again.value(for: "window-title-font-family") == "  spaced  ")
        #expect(again.value(for: "title") == "a \"quoted\" # hash \\ slash")
        #expect(again.value(for: "working-directory") == "")
        #expect(again.value(for: "command") == "\"wrapped\"")
    }

    @Test func commentsAndUnknownLinesSurviveAnEdit() throws {
        let source = "# mine\nnot a config line\n\nfont-size = 14\n# tail\n"
        var file = TarnConfigFile(parsing: source)
        #expect(file.text == source)
        try file.set("font-size", to: "15")
        #expect(file.text == "# mine\nnot a config line\n\nfont-size = 15\n# tail\n")
    }

    @Test func aNewFileStartsWithTheHeaderAndAnEmptyFileHasNoText() {
        #expect(TarnConfigFile().text.hasPrefix("# Written by the tarn settings window."))
        #expect(TarnConfigFile(parsing: "").text.isEmpty)
    }

    @Test func aRepeatableKeyKeepsItsPlaceAndAllItsValues() throws {
        var file = TarnConfigFile(parsing: "a = 1\nfont-family = \"\"\nfont-family = X\nb = 2\n")
        try file.set("font-family", to: ["", "Y"])
        #expect(file.text == "a = 1\nfont-family = \"\"\nfont-family = Y\nb = 2\n")
    }

    @Test func aValueWithALineBreakIsRejected() {
        var file = TarnConfigFile()
        #expect(throws: TarnConfigFile.Error.invalidText) { try file.set("font-size", to: "1\n2") }
        #expect(throws: TarnConfigFile.Error.invalidText) { try file.set("font-size", to: "1\r2") }
        #expect(throws: TarnConfigFile.Error.invalidText) { try file.set("a=b", to: "1") }
        #expect(file == TarnConfigFile())
    }

    @Test func defaultPathFollowsXdg() {
        #expect(TarnConfigFile.defaultURL(environment: ["HOME": "/h"]).path == "/h/.config/tarn/ghostty.conf")
        #expect(TarnConfigFile.defaultURL(environment: ["HOME": "/h", "XDG_CONFIG_HOME": "/x"]).path == "/x/tarn/ghostty.conf")
        #expect(TarnConfigFile.activeURL(arguments: ["tarn", "-e", "ls"]) == nil)
    }

    // MARK: - Ghostty reads it

    @Test func ghosttyReadsWhatTheWriterWrote() throws {
        let box = try Sandbox()
        var file = TarnConfigFile()
        try file.set("font-size", to: "16")
        try file.set("window-title-font-family", to: "  spaced  ")
        try file.set("title", to: "a \"q\" # h \\ s")
        try file.save(to: box.tarn)
        let config = box.config()
        #expect(config.errors.isEmpty)
        #expect(fontSize(config) == 16)
        #expect(text(config, "window-title-font-family") == "  spaced  ")
        #expect(text(config, "title") == "a \"q\" # h \\ s")
    }

    // MARK: - Precedence

    @Test func tarnBeatsTheUserFile() throws {
        let box = try Sandbox()
        try box.write("user.conf", "font-size = 12\n")
        #expect(fontSize(box.config()) == 12, "no tarn file: the user value")
        var file = TarnConfigFile()
        try file.set("font-size", to: "16")
        try file.save(to: box.tarn)
        #expect(fontSize(box.config()) == 16)
    }

    @Test func tarnBeatsAConfigFileInclude() throws {
        let box = try Sandbox()
        try box.write("inc.conf", "font-size = 10\n")
        try box.write("user.conf", "font-size = 12\nconfig-file = inc.conf\n")
        #expect(fontSize(box.config()) == 10, "the include wins over the user file")
        var file = TarnConfigFile()
        try file.set("font-size", to: "16")
        try file.save(to: box.tarn)
        #expect(fontSize(box.config()) == 16)
    }

    @Test func tarnBeatsATheme() throws {
        let box = try Sandbox()
        try box.write("theme.conf", "font-size = 9\nbackground = 112233\n")
        try box.write("user.conf", "theme = \(box.dir.appendingPathComponent("theme.conf").path)\n")
        var file = TarnConfigFile()
        try file.set("font-size", to: "16")
        try file.save(to: box.tarn)
        let config = box.config()
        #expect(config.errors.isEmpty)
        #expect(fontSize(config) == 16)
    }

    @Test func fontFamilyClearLineLoadsWithoutErrors() throws {
        let box = try Sandbox()
        try box.write("user.conf", "font-family = A\n")
        var file = TarnConfigFile()
        try file.set("font-family", to: ["", "B"])
        try file.save(to: box.tarn)
        // font-family is not readable through ghostty_config_get; the C slice checks the effective list.
        #expect(box.config().errors.isEmpty)
        #expect(TarnConfigFile(parsing: file.text).entries.map(\.value) == ["", "B"])
    }

    // MARK: - Reset and set-to-default

    @Test func resetRemovesOnlyThatLineAndTheUserValueReturns() throws {
        let box = try Sandbox()
        try box.write("user.conf", "font-size = 12\n")
        var file = TarnConfigFile()
        try file.set("font-size", to: "16")
        try file.set("drag-handle", to: "never")
        file.remove("font-size")
        #expect(!file.contains("font-size"))
        #expect(file.value(for: "drag-handle") == "never")
        try file.save(to: box.tarn)
        #expect(fontSize(box.config()) == 12)
    }

    @Test func anEmptyFileLoads() throws {
        let box = try Sandbox()
        try box.write("user.conf", "font-size = 12\n")
        try TarnConfigFile(parsing: "").save(to: box.tarn)
        let config = box.config()
        #expect(config.errors.isEmpty)
        #expect(fontSize(config) == 12)
    }

    @Test func aValueEqualToTheGhosttyDefaultStillWritesItsLine() throws {
        let box = try Sandbox()
        try box.write("user.conf", "font-size = 12\n")
        var file = TarnConfigFile()
        try file.set("font-size", to: "13")
        try file.save(to: box.tarn)
        #expect(file.text.contains("font-size = 13\n"))
        #expect(fontSize(box.config()) == 13)
    }

    // MARK: - Disk

    @Test func aMissingFileReadsAsNewAndLoadsNothing() throws {
        let box = try Sandbox()
        try box.write("user.conf", "font-size = 12\n")
        #expect(try TarnConfigFile.read(from: box.tarn) == TarnConfigFile())
        #expect(fontSize(box.config()) == 12)
    }

    @Test func aFailedWriteLeavesTheOldFileAndThrows() throws {
        let box = try Sandbox()
        var file = TarnConfigFile()
        try file.set("font-size", to: "16")
        try file.save(to: box.tarn)
        let before = try String(contentsOf: box.tarn, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: box.tarn.deletingLastPathComponent().path)
        try file.set("font-size", to: "20")
        #expect(throws: (any Error).self) { try file.save(to: box.tarn) }
        #expect(try String(contentsOf: box.tarn, encoding: .utf8) == before)
    }

    @Test func aSymlinkedFileStaysASymlink() throws {
        let box = try Sandbox()
        let real = box.dir.appendingPathComponent("dotfiles/ghostty.conf")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "font-size = 14\n".write(to: real, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: box.tarn.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: box.tarn, withDestinationURL: real)
        var file = try TarnConfigFile.read(from: box.tarn)
        try file.set("font-size", to: "18")
        try file.save(to: box.tarn)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: box.tarn.path) == real.path)
        #expect(try String(contentsOf: real, encoding: .utf8) == "font-size = 18\n")
    }
}
