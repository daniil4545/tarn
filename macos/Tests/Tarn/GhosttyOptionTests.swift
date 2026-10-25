import Foundation
import Testing
@testable import Ghostty

extension GhosttyOption {
    static func option(_ key: String) -> GhosttyOption? {
        all.first { $0.key == key }
    }
}

/// The option catalog against Ghostty itself (`docs/plans/s4-settings.md` sections 3 and 4).
@Suite
struct GhosttyOptionTests {
    @Test func keysAreUniqueAndEachSectionHasOptions() {
        let keys = GhosttyOption.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        for section in GhosttyOption.Section.allCases {
            #expect(!GhosttyOption.options(in: section).isEmpty)
        }
    }

    @Test func aChoiceListHoldsItsDefault() {
        for option in GhosttyOption.all {
            if case let .choice(values) = option.control {
                #expect(values.contains(option.defaultValue), "\(option.key)")
            }
        }
    }

    @Test(arguments: GhosttyOption.all)
    func defaultsMatchZig(option: GhosttyOption) throws {
        let config = try TemporaryConfig("")
        let read = GhosttyOptionReader.value(of: option, in: config)
        if option.reading == .unreadable || option.defaultValue.isEmpty {
            #expect(read == nil, "\(option.key) reads \(String(describing: read))")
        } else {
            #expect(read == option.defaultValue, "\(option.key)")
        }
    }

    /// Every value a control can write is one Ghostty accepts and reports back unchanged.
    @Test(arguments: GhosttyOption.all)
    func offeredValuesAreAcceptedByGhostty(option: GhosttyOption) throws {
        var values: [String] = []
        switch option.control {
        case .toggle: values = ["true", "false"]
        case let .choice(list): values = list.filter { !$0.isEmpty }
        case let .number(range), let .slider(range, _):
            values = [range.lowerBound, range.upperBound].map { String(format: "%g", $0) }
        case .theme, .text: return
        }
        for value in values {
            let config = try TemporaryConfig("\(option.key) = \(value)")
            #expect(config.errors.isEmpty, "\(option.key) = \(value): \(config.errors)")
            guard option.reading != .unreadable else { continue }
            #expect(GhosttyOptionReader.value(of: option, in: config) == value, "\(option.key) = \(value)")
        }
    }

    @Test func aRepeatableOptionClearsItsListFirst() {
        #expect(GhosttyOption.option("font-family")?.fileValues(for: "Menlo") == ["", "Menlo"])
        #expect(GhosttyOption.option("font-size")?.fileValues(for: "14") == ["14"])
    }

    @Test func nonLiveOptionsSayWhenTheyApply() {
        #expect(GhosttyOption.option("background-opacity")?.applies == .restart)
        #expect(GhosttyOption.option("macos-titlebar-style")?.applies == .newWindows)
        #expect(GhosttyOption.option("font-size")?.applies == .live)
        #expect(GhosttyOption.option("window-padding-x")?.applies == .newWindows)
    }

    /// Ghostty parses `window-padding-x` as an integer, so the catalog marks it whole.
    @Test func aWholeNumberOptionIsOneGhosttyRejectsWithAFraction() throws {
        let option = try #require(GhosttyOption.option("window-padding-x"))
        #expect(option.wholeNumber)
        #expect(try !TemporaryConfig("window-padding-x = 5.5").errors.isEmpty)
        #expect(try TemporaryConfig("window-padding-x = 6").errors.isEmpty)
    }
}
