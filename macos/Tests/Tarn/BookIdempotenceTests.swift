import Foundation
import Testing
@testable import Ghostty

/// `WorkspaceRegistry.sync` publishes whenever a pass reports a change, and every redraw calls
/// `sync` again. A pass that keeps reporting changes on the same groups loops without end, so
/// the second pass over the same groups must report nothing.
@Suite
struct BookIdempotenceTests {
    /// A small deterministic generator, so a failure replays.
    private struct Lcg: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    @Test func aSecondPassOnTheSameGroupChangesNothing() {
        run()
    }

    private func run() {
        for seed in 1...300 {
            var rng = Lcg(state: UInt64(seed))
            var book = WorkspaceBook()
            var order = [TabKey()]
            _ = book.pass([order])
            var log: [String] = []
            for _ in 0..<12 {
                let op = Int.random(in: 0..<5, using: &rng)
                switch op {
                case 0, 1:
                    // A new tab, after a random tab (Ghostty puts it after the selected one).
                    let source = order.randomElement(using: &rng)
                    let fresh = TabKey()
                    order.insert(fresh, at: Int.random(in: 1...order.count, using: &rng))
                    if op == 1, let source {
                        // Announced by the insertion point, as a second workspace's tab.
                        _ = book.edit(source) { $0.join(source, to: $0.create(name: "W\(order.count)")!) }
                        _ = book.pass([order])
                        _ = book.opened(fresh, from: source)
                    }
                    log.append("new")
                case 2:
                    guard order.count > 1, let tab = order.randomElement(using: &rng) else { continue }
                    _ = book.closing(tab)
                    order.removeAll { $0 == tab }
                    log.append("close")
                case 3:
                    guard order.count > 1 else { continue }
                    let from = Int.random(in: 0..<order.count, using: &rng)
                    let to = Int.random(in: 0..<order.count, using: &rng)
                    order.insert(order.remove(at: from), at: to)
                    log.append("move \(from)->\(to)")
                default:
                    guard order.count > 1 else { continue }
                    // Closed behind the book's back: the window left the group before any note.
                    order.remove(at: Int.random(in: 0..<order.count, using: &rng))
                    log.append("vanish")
                }
                _ = book.pass([order])
                let last = book.pass([order])
                #expect(last.changed.isEmpty, "seed \(seed) after \(log): changed \(last.changed.count)")
                if !last.changed.isEmpty { break }
            }
        }
    }
}
