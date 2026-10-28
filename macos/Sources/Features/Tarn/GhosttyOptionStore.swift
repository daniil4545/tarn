import AppKit
import Combine
import Foundation
import OSLog

/// The model behind the Ghostty option panes: reads and writes tarn's options file and keeps the
/// last effective config (`docs/modules/settings.md`).
///
/// A control change always writes its line, even when the value equals the Ghostty default; only
/// `reset` removes it. Each write re-reads the file first and changes one key, so a hand edit
/// between two clicks is kept.
@MainActor
final class GhosttyOptionStore: ObservableObject {
    /// What a row shows for an option.
    enum Display: Equatable {
        /// A value the control can show.
        case value(String)
        /// Ghostty cannot tell and tarn does not set it (`theme`, `font-family`, `window-padding-x`).
        case fromGhosttyConfig
        /// A value in the file the control cannot show (`undo-timeout = 7s`); read-only with Reset.
        case raw(String)
    }

    static let fromGhosttyConfigText = "from Ghostty config"

    private static let logger = Logger(subsystem: "tarn", category: "settings")

    /// The window's store: the real file, the app's config, a full reload after each write.
    static let shared = GhosttyOptionStore(
        url: TarnConfigFile.defaultURL(),
        config: (NSApp.delegate as? AppDelegate)?.ghostty.config
    ) {
        (NSApp.delegate as? AppDelegate)?.ghostty.reloadConfig()
    }

    /// The file as last read or saved.
    @Published private(set) var file: TarnConfigFile
    /// Failure text per option key, shown in the row until the next successful change.
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var config: Ghostty.Config?

    private let url: URL
    private let reload: () -> Void
    private var observer: AnyCancellable?

    init(url: URL, config: Ghostty.Config?, reload: @escaping () -> Void) {
        self.url = url
        self.config = config
        self.reload = reload
        file = (try? TarnConfigFile.read(from: url)) ?? TarnConfigFile()
        observer = NotificationCenter.default.publisher(for: .ghosttyConfigDidChange)
            .sink { [weak self] note in
                MainActor.assumeIsolated { self?.configDidChange(note) }
            }
    }

    // MARK: - Reading

    func isSet(_ option: GhosttyOption) -> Bool {
        file.contains(option.key)
    }

    func display(_ option: GhosttyOption) -> Display {
        if let value = file.value(for: option.key) {
            return canShow(value, for: option) ? .value(value) : .raw(value)
        }
        if let config, let value = GhosttyOptionReader.value(of: option, in: config) {
            return .value(value)
        }
        return option.reading == .unreadable ? .fromGhosttyConfig : .value(option.defaultValue)
    }

    private func canShow(_ value: String, for option: GhosttyOption) -> Bool {
        switch option.control {
        case .toggle: ["true", "false"].contains(value)
        case let .choice(values): values.contains(value)
        case .theme, .text: true
        case let .number(range), let .slider(range, _): Double(value).flatMap { Self.numberText($0, option: option, range: range) } != nil
        }
    }

    // MARK: - Writing

    /// Writes the line. The default entry of an optional option is the empty value `key = ""`,
    /// which Ghostty reads as "back to the default" (`src/cli/args.zig:325`): it hides the value
    /// of the user's own config, which only Reset gives back. A number the type does not take is
    /// reported in the row and not written.
    func set(_ option: GhosttyOption, to value: String) {
        var value = value
        switch option.control {
        case let .number(range), let .slider(range, _):
            guard let number = Double(value), let text = Self.numberText(number, option: option, range: range) else {
                errors[option.key] = Self.numberProblem(option: option, range: range)
                return
            }
            value = text
        default:
            break
        }
        write(option) { try $0.set(option.key, to: option.fileValues(for: value)) }
    }

    /// The text of a number the option takes, or nil: out of range, or a fraction for a whole number.
    static func numberText(_ number: Double, option: GhosttyOption, range: ClosedRange<Double>) -> String? {
        guard range.contains(number), !option.wholeNumber || number == number.rounded() else { return nil }
        return number.optionText
    }

    private static func numberProblem(option: GhosttyOption, range: ClosedRange<Double>) -> String {
        let kind = option.wholeNumber ? "whole number" : "number"
        return "Enter a \(kind) from \(range.lowerBound.optionText) to \(range.upperBound.optionText)."
    }

    func reset(_ option: GhosttyOption) {
        write(option) { $0.remove(option.key) }
    }

    /// Re-reads the file, so a change made outside the window shows up.
    func refreshFile() {
        if let fresh = try? TarnConfigFile.read(from: url), fresh != file { file = fresh }
    }

    /// Reads, changes one key, puts the options in catalog order, saves, then reloads Ghostty.
    /// A failed step leaves the file and the reload alone and reports in the row.
    private func write(_ option: GhosttyOption, _ change: (inout TarnConfigFile) throws -> Void) {
        do {
            var next = try TarnConfigFile.read(from: url)
            try change(&next)
            try Self.sortedByCatalog(&next)
            try next.save(to: url)
            file = next
            errors[option.key] = nil
            reload()
        } catch {
            Self.logger.error("write \(option.key, privacy: .public) to \(self.url.path, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            errors[option.key] = "Could not save: \(error.localizedDescription)"
        }
    }

    /// Moves the catalog options to the end in catalog order, after the header and any lines the
    /// user added by hand. The file then reads like the window.
    static func sortedByCatalog(_ file: inout TarnConfigFile) throws {
        let present = GhosttyOption.all.compactMap { option -> (String, [String])? in
            let values = file.entries.filter { $0.key == option.key }.map(\.value)
            return values.isEmpty ? nil : (option.key, values)
        }
        for (key, _) in present { file.remove(key) }
        for (key, values) in present { try file.set(key, to: values) }
    }

    // MARK: - Notification

    /// Takes the config of the app, not the one of a single terminal (`object == nil`).
    func configDidChange(_ notification: Notification) {
        guard notification.object == nil,
              let new = notification.userInfo?[Notification.Name.GhosttyConfigChangeKey] as? Ghostty.Config
        else { return }
        config = new
    }
}
