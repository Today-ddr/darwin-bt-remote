@testable import BTRemote
import XCTest

@MainActor
final class InputReleaseCoordinatorTests: XCTestCase {
    func testRegisteredReleasesRunInRegistrationOrderBeforeTheClearingReports() {
        let recorder = Recorder()
        let coordinator = InputReleaseCoordinator()
        coordinator.register { recorder.events.append("keyboard") }
        coordinator.register { recorder.events.append("trackpad") }

        coordinator.releaseAll(using: makeHID(recorder))

        XCTAssertEqual(recorder.events, ["keyboard", "trackpad", "keyboard-zero", "mouse-zero"])
    }

    func testUnregisteredReleaseNoLongerRuns() {
        let recorder = Recorder()
        let coordinator = InputReleaseCoordinator()
        let token = coordinator.register { recorder.events.append("released") }
        coordinator.unregister(token)

        coordinator.releaseAll(using: makeHID(recorder))

        XCTAssertEqual(recorder.events, ["keyboard-zero", "mouse-zero"])
    }

    func testAViewThatRegistersAgainAfterLeavingIsReleasedAgain() {
        let recorder = Recorder()
        let coordinator = InputReleaseCoordinator()
        let first = coordinator.register { recorder.events.append("first") }
        coordinator.unregister(first)
        coordinator.register { recorder.events.append("second") }

        coordinator.releaseAll(using: makeHID(recorder))

        XCTAssertEqual(recorder.events, ["second", "keyboard-zero", "mouse-zero"])
    }

    func testRepeatedReleaseDoesNotProduceASecondButtonTransition() {
        let recorder = Recorder()
        let coordinator = InputReleaseCoordinator()
        coordinator.register {
            if !recorder.buttons.isEmpty {
                recorder.buttons = []
                recorder.transitions += 1
            }
        }

        coordinator.releaseAll(using: makeHID(recorder))
        coordinator.releaseAll(using: makeHID(recorder))

        XCTAssertEqual(recorder.transitions, 1)
        XCTAssertTrue(recorder.buttons.isEmpty)
    }

    func testTheKeyboardZeroIsSentAfterEveryRegisteredRelease() {
        let recorder = Recorder()
        let coordinator = InputReleaseCoordinator()
        coordinator.register { recorder.hasKeyboardState = false }

        coordinator.releaseAll(using: makeHID(recorder))

        XCTAssertTrue(recorder.keyboardZeroSawClearedState)
    }

    private func makeHID(_ recorder: Recorder) -> HIDInput {
        HIDInput(
            sendMouse: { report in
                if report == .zero {
                    recorder.events.append("mouse-zero")
                }
            },
            sendKeyboard: { report in
                if report == .zero {
                    recorder.keyboardZeroSawClearedState = !recorder.hasKeyboardState
                    recorder.events.append("keyboard-zero")
                }
            },
            updateBattery: { _ in },
            isActive: true,
            isConnected: true,
            activeError: nil,
            batteryLevel: 100,
            isCapsLockOn: false
        )
    }

    private final class Recorder {
        var events: [String] = []
        var buttons: MouseButtons = [.left]
        var transitions = 0
        var hasKeyboardState = true
        var keyboardZeroSawClearedState = false
    }
}
