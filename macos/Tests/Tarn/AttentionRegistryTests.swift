import Combine
import Foundation
import Testing
@testable import Ghostty

/// The registry's attention paths without a window: a stub surface context and a recorded banner list.
@MainActor
@Suite
struct AttentionRegistryTests {
    private final class Banners {
        var list: [(surface: UUID, title: String, body: String)] = []
    }

    private let id = UUID()
    private let registry = SessionRegistry()
    private let banners = Banners()

    init() {
        let banners = banners
        registry.deliver = { banners.list.append(($0, $1, $2)) }
    }

    private func surface(focused: Bool = false, pwd: String? = "/nonexistent/proj") -> SurfaceContext {
        SurfaceContext(id: id, focused: focused, pwd: pwd)
    }

    private func hook(_ name: String, focused: Bool = false, extra: [String: Any] = [:]) {
        let event = ["hook_event_name": name].merging(extra) { $1 }
        registry.process(name, event, message: [:], reply: nil, surface: surface(focused: focused))
    }

    // MARK: Hook events reach the gate

    private func response(to message: [String: Any]) throws -> Data {
        var fds: [Int32] = [-1, -1]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer { close(fds[1]) }
        let queue = DispatchQueue(label: "test.version")
        let reply = ControlSocket.Reply(fd: fds[0], queue: queue)
        registry.handle(message, reply: reply)
        queue.sync {}
        var bytes = [UInt8](repeating: 0, count: 1024)
        let count = recv(fds[1], &bytes, bytes.count, MSG_DONTWAIT)
        return count > 0 ? Data(bytes.prefix(count)) : Data()
    }

    @Test func unsupportedVersionsAreRefusedBeforeDispatch() throws {
        for command in ["ls", "new", "run", "read", "close", "modules", "wait", "open", "notify", "bogus"] {
            for version: Any? in [nil, 2, "1"] {
                var message: [String: Any] = ["cmd": command]
                message["version"] = version
                let data = try response(to: message)
                let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(fields["error"] as? String == "unsupported version")
                #expect(fields["ok"] as? Bool == false)
                #expect(fields["version"] as? Int == 1)
                let agentCommand = !["open", "notify", "bogus"].contains(command)
                #expect(fields["code"] as? Int == (agentCommand ? 1 : nil))
            }
        }
        let valid = try response(to: ["version": 1, "cmd": "bogus"])
        #expect(String(data: valid, encoding: .utf8)?.contains("unknown command: bogus") == true)
    }

    @Test func unsupportedHookVersionsStaySilent() throws {
        for version: Any? in [nil, 2, "1"] {
            var message: [String: Any] = ["reply": true, "surface": id.uuidString,
                                          "event": ["hook_event_name": "PermissionRequest"]]
            message["version"] = version
            #expect(try response(to: message).isEmpty)
            #expect(!registry.eventsSeen)
            #expect(registry.sessions.isEmpty)
            #expect(banners.list.isEmpty)
        }
    }

    @Test func aStateChangeRaisesOnceWithTheProjectAsTitle() {
        hook("Stop")
        hook("Stop")
        #expect(banners.list.count == 1)
        #expect(banners.list.first?.title == "proj")
        #expect(banners.list.first?.body == "Waiting for you")
        hook("PermissionRequest", extra: ["tool_name": "Bash", "tool_input": ["command": "make"]])
        #expect(banners.list.last?.body == "Needs your permission")
        #expect(banners.list.count == 2)
    }

    @Test func aNewPermissionRequestAfterASeenOneRaises() {
        hook("PermissionRequest", focused: true, extra: ["tool_name": "Bash", "tool_input": ["command": "make"]])
        #expect(banners.list.isEmpty)
        hook("PermissionRequest", extra: ["tool_name": "Bash", "tool_input": ["command": "make test"]])
        #expect(banners.list.map(\.body) == ["Needs your permission"])
    }

    @Test func aFocusedSurfaceRaisesNothing() {
        hook("Stop", focused: true)
        #expect(banners.list.isEmpty)
        #expect(registry.sessions[id]?.seen == true)
    }

    @Test func aFailureAfterWaitingResetsSeen() {
        hook("Stop")
        #expect(registry.sessions[id]?.seen == false)
        hook("StopFailure", focused: true)
        #expect(registry.sessions[id]?.need == .failed)
        #expect(registry.sessions[id]?.seen == true)
    }

    @Test func failureAfterWaitingRaisesTheFailureBanner() {
        hook("Stop")
        hook("StopFailure")
        #expect(banners.list.map(\.body) == ["Waiting for you", "Failed, see the session"])
    }

    // MARK: Suppression

    @Test func aLiveAgentSessionSuppressesTerminalNotifications() {
        #expect(!registry.suppresses(id))
        hook("UserPromptSubmit", extra: ["session_id": "abc"])
        #expect(registry.suppresses(id))
        hook("SessionEnd", extra: ["reason": "logout"])
        #expect(!registry.suppresses(id))
    }

    // MARK: notify

    @Test func notifyCreatesARecordAndBannersWithTheText() {
        #expect(registry.notify("  tests failed \n", surface: surface()) == nil)
        #expect(registry.sessions[id]?.note == "tests failed")
        #expect(registry.sessions[id]?.state == .idle)
        #expect(banners.list.map(\.body) == ["tests failed"])
        #expect(banners.list.first?.title == "proj")
    }

    @Test func theSameTextAgainRaisesNothing() {
        _ = registry.notify("done", surface: surface())
        _ = registry.notify("done", surface: surface())
        #expect(banners.list.count == 1)
    }

    @Test func anUnseenNoteIsReplacedWithoutANewBanner() {
        _ = registry.notify("step 1", surface: surface())
        let since = registry.sessions[id]?.noteSince
        _ = registry.notify("step 2", surface: surface())
        _ = registry.notify("step 1", surface: surface())
        #expect(banners.list.map(\.body) == ["step 1"])
        #expect(registry.sessions[id]?.note == "step 1")
        #expect(registry.sessions[id]?.noteSince == since)
    }

    @Test func afterTheUserFocusesTheNextNoteBannersAgain() {
        _ = registry.notify("one", surface: surface())
        registry.markFocused(id)
        #expect(registry.sessions[id]?.note.isEmpty == true)
        _ = registry.notify("two", surface: surface())
        #expect(banners.list.map(\.body) == ["one", "two"])
    }

    @Test func aFocusedSurfaceStoresNothing() {
        #expect(registry.notify("done", surface: surface(focused: true)) == nil)
        #expect(registry.sessions[id] == nil)
        #expect(banners.list.isEmpty)
    }

    @Test func emptyTextIsAnError() {
        #expect(registry.notify(" \n", surface: surface()) == "empty text")
        #expect(registry.sessions[id] == nil)
    }

    // MARK: Focus events

    @Test func aFocusBeforeSubscribingIsNotAFocusEvent() async throws {
        let instant = CurrentValueSubject<ContinuousClock.Instant?, Never>(.now)
        var events = 0
        let subscription = SessionRegistry.focusEvents(instant).sink { events += 1 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(events == 0)
        instant.send(.now)
        try await Task.sleep(for: .milliseconds(50))
        #expect(events == 1)
        subscription.cancel()
    }

    // MARK: Screen order

    @Test func windowsOutsideTabGroupsComeLast() {
        let order = SessionRegistry.screenOrder(
            terminals: ["a", "c"], all: ["quick", "a", "b", "c"]
        ) { $0 == "a" ? ["a", "b"] : [$0] }
        #expect(order == ["a", "b", "c", "quick"])
    }
}

@Suite
struct MalformedLineTests {
    @Test func junkAndInvalidUTF8GetAnErrorReply() {
        #expect(AttentionCommands.isMalformed(Data("not json\n".utf8)))
        #expect(AttentionCommands.isMalformed(Data([0xFF, 0xFE, 0x0A])))
        #expect(AttentionCommands.isMalformed(Data("[1,2]\n".utf8)))
    }

    @Test func objectsAndPermissionHookLinesAreNotMalformed() {
        #expect(!AttentionCommands.isMalformed(Data("{\"event\":{}}\n".utf8)))
        #expect(!AttentionCommands.isMalformed(Data("{\"reply\":true,\"event\":garbage}\n".utf8)))
    }
}
