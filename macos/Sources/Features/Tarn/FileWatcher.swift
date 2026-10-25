// Follows macdown3000 MPFileWatcher.m (MIT) and cmux FileWatcher.swift (structure only): a
// vnode source on the file and on its folder, a 300 ms throttle, re-armed after each event.

import Foundation

/// Calls `onChange` on the main queue when a file is written, replaced or deleted. The folder
/// watch catches the atomic save (`mv tmp file`), where the old inode dies.
final class FileWatcher {
    static let throttle: TimeInterval = 0.3

    private let path: String
    private let onChange: () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending = false

    init(path: String, onChange: @escaping () -> Void) {
        self.path = path
        self.onChange = onChange
        arm()
    }

    deinit {
        disarm()
    }

    private func arm() {
        disarm()
        let folder = (path as NSString).deletingLastPathComponent
        for (target, mask) in [(path, DispatchSource.FileSystemEvent([.write, .delete, .rename, .extend])),
                               (folder, DispatchSource.FileSystemEvent([.write, .rename, .delete]))] {
            let fd = open(target, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
            source.setEventHandler { [weak self] in self?.fire() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    private func disarm() {
        sources.forEach { $0.cancel() }
        sources = []
    }

    private func fire() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.throttle) { [weak self] in
            guard let self else { return }
            pending = false
            arm()
            onChange()
        }
    }
}
