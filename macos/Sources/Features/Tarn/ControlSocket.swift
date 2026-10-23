import Foundation
import OSLog

/// The unix socket of the running app. Agent hooks send one JSON line per connection;
/// each line and its connection are handed to the main actor. See `docs/spec.md` section 2.2.
final class ControlSocket {
    static let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/tarn/tarn.sock").path

    private static let logger = Logger(subsystem: "tarn", category: "socket")

    /// Lines longer than this are dropped: a hook event with a huge tool output is not
    /// worth the memory, and the state machine never needs those fields.
    private static let maxLine = 4 * 1024 * 1024

    private let onLine: @MainActor (Data, Reply) -> Void
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "tarn.socket")

    init(onLine: @escaping @MainActor (Data, Reply) -> Void) {
        self.onLine = onLine
    }

    /// Binds the socket, replacing a stale file. Failure is logged; the app runs without it.
    func start() {
        let path = Self.path
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        unlink(path)

        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return fail("socket") }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxPath = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard path.utf8.count <= maxPath else { return fail("path too long") }
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            buf.copyBytes(from: path.utf8)
        }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { return fail("bind") }
        chmod(path, 0o600)
        guard listen(fd, 16) == 0 else { return fail("listen") }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        self.source = source
    }

    private func accept() {
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { return }

        // A hook writes its line first; reading on our queue never blocks the agent for
        // longer than its own write.
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        while true {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
            if data.count > Self.maxLine { break }
            if buffer[n - 1] == UInt8(ascii: "\n") { break }
        }

        guard !data.isEmpty, data.count <= Self.maxLine else {
            if data.count > Self.maxLine { Self.logger.info("dropped an oversized line") }
            close(client)
            return
        }
        let line = data
        let reply = Reply(fd: client, queue: queue)
        DispatchQueue.main.async { [onLine] in
            MainActor.assumeIsolated { onLine(line, reply) }
        }
    }

    private func fail(_ step: String) {
        Self.logger.error("control socket \(step, privacy: .public) failed: errno \(errno)")
        if fd >= 0 { close(fd) }
        fd = -1
    }
}

extension ControlSocket {
    /// The connection of one hook. Dropping it closes the connection; the permission hook
    /// keeps it open and waits for an answer line (`docs/spec.md` section 2.3).
    final class Reply: @unchecked Sendable {
        private let fd: Int32
        private let queue: DispatchQueue
        private var isClosed = false

        fileprivate init(fd: Int32, queue: DispatchQueue) {
            self.fd = fd
            self.queue = queue
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        }

        deinit {
            if !isClosed { close(fd) }
        }

        /// Writes `line` and closes the connection; an empty line only closes it. A hook
        /// that is gone makes the write fail, which is fine: nobody waits for it.
        func send(_ line: Data) {
            queue.async { [self] in
                guard !isClosed else { return }
                isClosed = true
                line.withUnsafeBytes { buf in
                    var offset = 0
                    while offset < buf.count, let base = buf.baseAddress {
                        let n = write(fd, base + offset, buf.count - offset)
                        if n <= 0 { break }
                        offset += n
                    }
                }
                close(fd)
            }
        }
    }
}
