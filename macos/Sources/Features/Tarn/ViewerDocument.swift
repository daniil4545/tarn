import Foundation

/// Size and modification time: the cheap test for "the file changed on disk".
struct FileStamp: Equatable {
    var modified: Date
    var size: Int

    static func of(_ path: String) -> FileStamp? {
        // The watcher follows symlinks, so the stamp does too.
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved) else { return nil }
        return FileStamp(
            modified: attributes[.modificationDate] as? Date ?? .distantPast,
            size: (attributes[.size] as? NSNumber)?.intValue ?? 0)
    }
}

/// What reading a file from disk gives. Over 5 MB and non UTF-8 files get a notice instead of text.
enum FileRead: Equatable {
    case text(String, FileStamp)
    case notice(String, FileStamp)
    case missing

    static let maxBytes = 5 * 1024 * 1024

    static func read(_ path: String) -> FileRead {
        guard let stamp = FileStamp.of(path) else { return .missing }
        if stamp.size > maxBytes { return .notice("This file is larger than 5 MB.", stamp) }
        guard let data = FileManager.default.contents(atPath: path) else { return .missing }
        guard let text = String(data: data, encoding: .utf8) else {
            return .notice("This file is not UTF-8 text.", stamp)
        }
        return .text(text, stamp)
    }
}

/// One open file: the text on screen, the text on disk and what to do when the disk changes.
/// `docs/spec.md` 2.5: a rewrite re-renders; with unsaved edits the user chooses.
struct ViewerDocument: Equatable {
    enum Content: Equatable {
        case markdown
        case code
        case notice(String)
    }

    enum DiskChange: Equatable {
        case none
        case reloaded
        case conflict
        case deleted
    }

    let path: String
    private(set) var content: Content
    private(set) var text: String
    private(set) var savedText: String
    private(set) var stamp: FileStamp?
    /// The disk text held back while the user decides on a conflict.
    private var diskText: String?
    /// Grows when the text changes under the user (open, reload, take), never on their own edits.
    private(set) var revision = 1
    private(set) var conflict = false
    /// The file is gone from disk; the tab keeps its text and Save writes it again.
    private(set) var isMissing = false

    var isDirty: Bool { text != savedText }

    init?(path: String) {
        self.path = path
        switch FileRead.read(path) {
        case .missing:
            return nil
        case let .text(text, stamp):
            content = ViewerPaths.isMarkdown(path) ? .markdown : .code
            self.text = text
            savedText = text
            self.stamp = stamp
        case let .notice(message, stamp):
            content = .notice(message)
            text = ""
            savedText = ""
            self.stamp = stamp
        }
    }

    mutating func edit(_ newText: String) {
        guard case .markdown = content else { return }
        text = newText
    }

    /// Applies the file as read from disk after a watcher event.
    mutating func diskChanged(_ read: FileRead) -> DiskChange {
        switch read {
        case .missing:
            guard !isMissing else { return .none }
            isMissing = true
            return .deleted
        case let .notice(message, stamp):
            // A dirty document never turns into a notice under the user's hands.
            guard stamp != self.stamp || isMissing, !isDirty else { return .none }
            self.stamp = stamp
            isMissing = false
            content = .notice(message)
            text = ""
            savedText = ""
            conflict = false
            revision += 1
            return .reloaded
        case let .text(disk, stamp):
            guard stamp != self.stamp || isMissing else { return .none }
            self.stamp = stamp
            isMissing = false
            let wanted: Content = ViewerPaths.isMarkdown(path) ? .markdown : .code
            if disk == savedText && content == wanted { return .none }
            if !isDirty {
                content = wanted
                text = disk
                savedText = disk
                revision += 1
                return .reloaded
            }
            if conflict && diskText == disk { return .none }
            diskText = disk
            conflict = true
            return .conflict
        }
    }

    mutating func takeDisk() {
        guard conflict, let diskText else { return }
        text = diskText
        savedText = diskText
        self.diskText = nil
        conflict = false
        revision += 1
    }

    /// Keeps the user's text; it now differs from the disk text, so it stays dirty.
    mutating func keepMine() {
        guard conflict else { return }
        savedText = diskText ?? savedText
        diskText = nil
        conflict = false
    }

    mutating func saved(stamp: FileStamp?) {
        savedText = text
        self.stamp = stamp
        diskText = nil
        conflict = false
        isMissing = false
    }

    /// Sets the task marker on a source line and returns the new text, or nil when the line has none.
    mutating func setTask(line: Int, checked: Bool) -> Bool {
        guard let updated = TaskList.set(text, line: line, checked: checked) else { return false }
        text = updated
        revision += 1
        return true
    }
}

/// Task-list write-back: `- [ ] item` and `- [x] item` lines, also inside quotes.
enum TaskList {
    private static let marker = #"^([\s>]*(?:[-*+]|\d+[.)])\s+\[)([ xX])(\])"#

    static func set(_ text: String, line: Int, checked: Bool) -> String? {
        var lines = text.components(separatedBy: "\n")
        guard lines.indices.contains(line),
              let range = lines[line].range(of: marker, options: .regularExpression)
        else { return nil }
        let head = lines[line][range]
        let box = head.index(before: head.index(before: head.endIndex))
        lines[line].replaceSubrange(box...box, with: checked ? "x" : " ")
        return lines.joined(separator: "\n")
    }
}
