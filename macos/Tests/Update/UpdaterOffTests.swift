import Testing
import Foundation
import Sparkle
@testable import Ghostty

/// tarn ships without an updater: Sparkle must never find a Ghostty build.
struct UpdaterOffTests {
    @Test func theFeedIsEmpty() {
        let controller = UpdateController()
        let driver = UpdateDriver(viewModel: .init(), hostBundle: .main)
        #expect(driver.feedURLString(for: controller.updater) == nil)
    }

    @Test func checkingForUpdatesLeavesTheStateIdle() {
        let controller = UpdateController()
        controller.checkForUpdates()
        #expect(controller.viewModel.state == .idle)
        #expect(controller.updater.sessionInProgress == false)
    }
}
