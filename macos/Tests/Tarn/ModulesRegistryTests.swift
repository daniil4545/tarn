import Foundation
import Testing
@testable import Ghostty

/// Permission card and Notifications switched off, on the registry without a window.
@MainActor
@Suite
struct ModulesRegistryTests {
    private final class Banners { var list: [String] = [] }
    private final class SocketBox {
        var list: [ControlSocket] = []
        var paths: [String] = []
        var clients: [Int32] = []
        deinit {
            clients.forEach { close($0) }
            paths.forEach { unlink($0) }
        }
    }

    private let id = UUID()
    private let registry = SessionRegistry()
    private let banners = Banners()
    private let sockets = SocketBox()

    init() {
        let banners = banners
        registry.deliver = { _, _, body in banners.list.append(body) }
    }

    private func surface(focused: Bool = false) -> SurfaceContext {
        SurfaceContext(id: id, focused: focused, pwd: "/nonexistent/proj")
    }

    private func hook(_ name: String, reply: ControlSocket.Reply? = nil, extra: [String: Any] = [:]) {
        let event = ["hook_event_name": name].merging(extra) { $1 }
        registry.process(name, event, message: reply == nil ? [:] : ["reply": true], reply: reply, surface: surface())
    }

    // MARK: Notifications

    @Test func notificationsOffRaiseNoBannerButKeepTheState() {
        registry.isOn = { $0 != .notifications }
        hook("Stop")
        #expect(banners.list.isEmpty)
        #expect(registry.sessions[id]?.state == .waiting)
    }

    @Test func notificationsOffRefuseTarnNotify() {
        registry.isOn = { $0 != .notifications }
        #expect(registry.notify("done", surface: surface()) == "notifications are off in Settings")
        #expect(registry.sessions[id] == nil)
    }

    @Test func notificationsOffGiveTheAgentItsTerminalNotificationsBack() {
        hook("UserPromptSubmit", extra: ["session_id": "s1"])
        #expect(registry.suppresses(id))
        registry.isOn = { $0 != .notifications }
        #expect(!registry.suppresses(id))
    }

    @Test func theEventsCheckSeesTheFirstHook() {
        #expect(!registry.eventsSeen)
        hook("UserPromptSubmit")
        #expect(registry.eventsSeen)
    }

    // MARK: Permission card

    private func connection() async throws -> (reply: ControlSocket.Reply, client: Int32) {
        final class Box: @unchecked Sendable { var reply: ControlSocket.Reply? }
        let box = Box()
        let path = "/tmp/t-\(UUID().uuidString.prefix(8)).sock"  // short: sun_path holds 104 bytes; removed in SocketBox.deinit
        sockets.paths.append(path)
        let socket = ControlSocket { _, reply in box.reply = reply }
        socket.start(path: path)
        sockets.list.append(socket)
        let client = connectClient(path)
        sockets.clients.append(client)
        let line = Array("{\"x\":1}\n".utf8)
        _ = write(client, line, line.count)
        for _ in 0..<100 where box.reply == nil { try await Task.sleep(for: .milliseconds(20)) }
        return (try #require(box.reply), client)
    }

    private func connectClient(_ path: String) -> Int32 {
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

    /// True when the other end closed the connection (a read gives end of file).
    private func isClosed(_ fd: Int32) async throws -> Bool {
        var byte: UInt8 = 0
        for _ in 0..<50 {
            let n = recv(fd, &byte, 1, MSG_DONTWAIT)
            if n == 0 { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private let permission: [String: Any] = ["tool_name": "Bash", "tool_input": ["command": "make"]]

    @Test func permissionCardOnHoldsTheHook() async throws {
        let (reply, client) = try await connection()
        hook("PermissionRequest", reply: reply, extra: permission)
        #expect(registry.sessions[id]?.answerable == true)
        #expect(try await isClosed(client) == false)
    }

    @Test func permissionCardOffAnswersAtOnceWithAnEmptyReply() async throws {
        registry.isOn = { $0 != .permissionCard }
        let (reply, client) = try await connection()
        hook("PermissionRequest", reply: reply, extra: permission)
        #expect(try await isClosed(client))
        #expect(registry.sessions[id]?.answerable == false)
        #expect(registry.sessions[id]?.state == .permission)
    }

    @Test func switchingTheCardOffReleasesAWaitingHook() async throws {
        let (reply, client) = try await connection()
        hook("PermissionRequest", reply: reply, extra: permission)
        #expect(try await isClosed(client) == false)
        registry.isOn = { $0 != .permissionCard }
        registry.permissionCardChanged()
        #expect(try await isClosed(client))
        #expect(registry.sessions[id]?.answerable == false)
    }
}
