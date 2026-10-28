import Foundation
import Testing
@testable import Ghostty

/// `WorkspaceRegistry.sync` publishes whenever a pass reports a change, and every redraw calls
/// `sync` again. A pass that keeps reporting changes on the same groups loops without end, so
/// once the native moves are made, the next pass over the same groups must report nothing.
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

    /// Passes over `order` until the native moves are made; returns the last outcome.
    private func settle(_ book: inout WorkspaceBook, _ order: inout [TabKey], moves: Bool = true) -> WorkspaceBook.Outcome {
        var outcome = book.pass([order])
        for reorder in outcome.reorders where moves {
            guard let index = order.firstIndex(of: reorder.tab) else { continue }
            let tab = order.remove(at: index)
            order.insert(tab, at: min(max(index + reorder.delta, 0), order.count))
        }
        if !outcome.reorders.isEmpty { outcome = book.pass([order]) }
        return book.pass([order])
    }

    @Test func aSecondPassOnTheSameGroupChangesNothing() {
        run(moves: true)
    }

    /// The native move may not take effect (AppKit refuses it): the book still settles.
    @Test func aRefusedNativeMoveDoesNotKeepTheBookChanging() {
        run(moves: false)
    }

    private func run(moves: Bool) {
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
                    if op == 1, let tab = order.randomElement(using: &rng) {
                        book.setPendingTarget(book.newWorkspace("W\(order.count)", in: tab), for: tab)
                    }
                    let fresh = TabKey()
                    order.insert(fresh, at: Int.random(in: 1...order.count, using: &rng))
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
                let last = settle(&book, &order, moves: moves)
                // A refused move leaves the ungrouped run out of place (I2): the book asks again
                // but its membership stays.
                let quiet = last.changed.isEmpty && (!moves || last.reorders.isEmpty)
                #expect(quiet, "seed \(seed) after \(log): changed \(last.changed.count) reorders \(last.reorders.count)")
                if !quiet { break }
            }
        }
    }
}
