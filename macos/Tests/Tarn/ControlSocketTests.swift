import Foundation
import Testing
@testable import Ghostty

@Suite
@MainActor
struct ControlSocketReadTests {
    @MainActor
    private final class Lines {
        var received: [Data] = []
    }

    /// A client that connects and sends nothing holds only itself: the next hook's line still
    /// reaches the app at once, not after the silent client's receive timeout. The timeout is
    /// raised so a stall shows through the noise of a parallel test run.
    @Test func aSilentClientDoesNotDelayTheNextLine() async throws {
        let path = "/tmp/ts-\(UUID().uuidString.prefix(8)).sock"
        defer { unlink(path) }
        let lines = Lines()
        let socket = ControlSocket(readTimeout: 8) { line, _ in lines.received.append(line) }
        socket.start(path: path)
        try #require(socket.isBound)

        let silent = connect(path)
        defer { close(silent) }
        let talker = connect(path)
        defer { close(talker) }
        let line = Array("{\"version\":1}\n".utf8)
        let start = ContinuousClock.now
        _ = write(talker, line, line.count)
        for _ in 0..<1000 where lines.received.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(lines.received == [Data(line)])
        #expect(ContinuousClock.now - start < .seconds(4))
    }

    private func connect(_ path: String) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: path.utf8) }
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return fd
    }
}
