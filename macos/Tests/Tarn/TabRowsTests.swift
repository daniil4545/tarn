import Foundation
import Testing
@testable import Ghostty

/// The second line of a wide sidebar row (`docs/modules/sidebar.md`).
@Suite
struct TabRowsTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test(arguments: [
        ("~/code/tarn", 30.0, "~/code/tarn · now"),
        ("~/code/tarn", 150.0, "~/code/tarn · 2m"),
        ("~/code/tarn", 3_900.0, "~/code/tarn · 1h 5m"),
        ("", 150.0, "2m"),
    ])
    func secondLineIsFolderAndMinutesInState(folder: String, seconds: Double, expected: String) {
        #expect(TabRows.secondLine(folder: folder, since: Self.start, now: Self.start + seconds) == expected)
    }
}
