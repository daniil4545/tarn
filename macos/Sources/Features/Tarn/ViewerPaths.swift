import Foundation

extension Ghostty.SurfaceView {
    /// The reported working directory (OSC 7), or the foreground process's when the shell reports none.
    var workingDirectory: String? {
        pwd ?? surfaceModel?.foregroundPID.flatMap { ViewerPaths.cwd(ofPid: pid_t($0)) }
    }
}

/// A file a path click or `tarn open` asks for.
struct OpenTarget: Equatable {
    var path: String
    var line: Int?
}

/// What a path points at, and so who opens it.
enum ViewerFileKind: Equatable {
    case text
    case system
    case directory
    /// A pipe, device or socket: never read.
    case special
    case missing
}

/// Turns the text of a path click into a file: `~/`, absolute and relative paths with an optional
/// `:line[:column]` suffix. See `docs/spec.md` 2.5 and section 3, row "Path click".
enum ViewerPaths {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    /// A scheme with `//` or `mailto:` is a URL, `file://` excepted; `spec.md:12` is a path whose
    /// suffix looks like a scheme.
    static func isURL(_ raw: String) -> Bool {
        if raw.hasPrefix("file://") { return false }
        return raw.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil || raw.hasPrefix("mailto:")
    }

    /// Resolves `raw` against the clicked terminal's `cwd`. A real file whose name contains a colon
    /// wins over the `:line` split.
    static func resolve(
        _ raw: String,
        cwd: String?,
        home: String = NSHomeDirectory(),
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> OpenTarget? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("file://") {
            guard let path = URL(string: text)?.path else { return nil }
            text = path
        }
        guard !text.isEmpty else { return nil }

        var candidates = [(text, Int?.none)]
        if let match = text.range(of: #":(\d+)(:\d+)?$"#, options: .regularExpression) {
            let suffix = text[match].split(separator: ":")
            candidates.append((String(text[..<match.lowerBound]), suffix.first.flatMap { Int($0) }))
        }

        var fallback: OpenTarget?
        for (candidate, line) in candidates {
            guard let absolute = absolutePath(candidate, cwd: cwd, home: home) else { continue }
            let target = OpenTarget(path: absolute, line: line)
            if exists(absolute) { return target }
            fallback = target
        }

        // Ghostty's link regex drops a trailing `.` or `,` from URLs but not from paths, so a path
        // that ends a sentence arrives with it. A real name that ends with one is found above.
        var bare = Substring(text)
        while bare.last == "." || bare.last == "," { bare.removeLast() }
        if bare.count < text.count,
           let shorter = resolve(String(bare), cwd: cwd, home: home, exists: exists),
           exists(shorter.path) {
            return shorter
        }
        return fallback
    }

    private static func absolutePath(_ path: String, cwd: String?, home: String) -> String? {
        guard !path.isEmpty else { return nil }
        let full: String
        if path == "~" || path.hasPrefix("~/") {
            full = home + path.dropFirst()
        } else if path.hasPrefix("/") {
            full = path
        } else if let cwd {
            full = cwd + "/" + path
        } else {
            return nil
        }
        return URL(fileURLWithPath: full).standardizedFileURL.path
    }

    /// Files of these types open in their own app; every other regular file is read as text
    /// (a non-UTF-8 file gets a notice). An allowlist, because `UTType` calls `.ts` video.
    static let systemExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp", "ico", "icns", "psd",
        "pdf", "mp3", "m4a", "wav", "aac", "flac", "aif", "aiff", "mp4", "mov", "m4v", "mkv", "avi", "webm",
        "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "tar", "dmg", "pkg", "iso",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers", "rtf", "app",
    ]

    static func classify(_ path: String) -> ViewerFileKind {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return .missing }
        if isDirectory.boolValue { return .directory }
        let values = try? URL(fileURLWithPath: path).resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true else { return .special }
        return systemExtensions.contains((path as NSString).pathExtension.lowercased()) ? .system : .text
    }

    /// The working directory of a process, for a terminal that reports none (no shell integration).
    static func cwd(ofPid pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }

    /// Binary by content, as git decides: a NUL byte or invalid UTF-8 in the first 8 KB. A multibyte
    /// character cut by the 8 KB edge is not invalid.
    static func isBinary(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        defer { try? handle.close() }
        let limit = 8192
        guard let head = try? handle.read(upToCount: limit) else { return false }
        if head.contains(0) { return true }
        let cut = head.count == limit
        for trim in 0...(cut ? 3 : 0) where String(data: head.dropLast(trim), encoding: .utf8) != nil {
            return false
        }
        return true
    }

    static func isMarkdown(_ path: String) -> Bool {
        markdownExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// The highlight.js language hint: the extension, or the lowercase name of `Makefile` and the like.
    static func language(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? name : ext
    }
}
