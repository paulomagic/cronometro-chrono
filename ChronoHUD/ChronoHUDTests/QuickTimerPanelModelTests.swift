import XCTest
@testable import ChronoHUD

@MainActor
final class QuickTimerPanelModelTests: XCTestCase {
    func testValidationPreservesInputAndClearsWhenTextChanges() throws {
        let model = QuickTimerPanelModel()
        model.input = "bad"
        var feedbackCount = 0
        XCTAssertFalse(try model.submit(optionPressed: false, sessionIsActive: false, validationFeedback: { feedbackCount += 1 }) { _, _ in .started })
        XCTAssertEqual(model.input, "bad")
        XCTAssertEqual(model.phase, .entry(error: .invalidFormat))
        XCTAssertEqual(feedbackCount, 1)
        model.input = "5m"
        XCTAssertEqual(model.phase, .entry(error: nil))
    }

    func testReturnConfirmationRaceAndSecondReturn() throws {
        let model = QuickTimerPanelModel()
        model.input = "5m"
        XCTAssertFalse(try model.submit(optionPressed: false, sessionIsActive: true) { _, _ in XCTFail(); return .started })
        XCTAssertEqual(model.phase, .confirmation(duration: 300, origin: .sessionKnownAtSubmit))
        var policy: QuickTimerSubmissionPolicy?
        XCTAssertTrue(try model.submit(optionPressed: false, sessionIsActive: true) { _, value in policy = value; return .started })
        XCTAssertEqual(policy, .replaceIfActive)

        let racing = QuickTimerPanelModel()
        racing.input = "2m"
        XCTAssertFalse(try racing.submit(optionPressed: false, sessionIsActive: false) { _, value in
            XCTAssertEqual(value, .requireIdle)
            return .confirmationRequired(.sessionBecameActive)
        })
        XCTAssertEqual(racing.phase, .confirmation(duration: 120, origin: .sessionBecameActive))
    }

    func testOptionReturnReplacesImmediatelyOrStartsWhenIdle() throws {
        for active in [false, true] {
            let model = QuickTimerPanelModel()
            model.input = "30s"
            var policy: QuickTimerSubmissionPolicy?
            XCTAssertTrue(try model.submit(optionPressed: true, sessionIsActive: active) { _, value in policy = value; return .started })
            XCTAssertEqual(policy, .replaceIfActive)
        }
    }

    func testEscapeAndAutomaticSessionEndPreserveText() throws {
        let model = QuickTimerPanelModel()
        model.input = "10m"
        _ = try model.submit(optionPressed: false, sessionIsActive: true) { _, _ in .started }
        XCTAssertFalse(model.escape())
        XCTAssertEqual(model.phase, .entry(error: nil))
        XCTAssertEqual(model.input, "10m")

        _ = try model.submit(optionPressed: false, sessionIsActive: true) { _, _ in .started }
        model.sessionActivityChanged(isActive: false)
        XCTAssertEqual(model.phase, .entry(error: nil))
        XCTAssertTrue(model.escape())
    }

    func testKeyEventMapsReturnKeypadOptionAndIgnoresRepeats() {
        XCTAssertEqual(QuickTimerKeyEvent.action(keyCode: 36, modifiers: [], isRepeat: false), .submit(optionPressed: false))
        XCTAssertEqual(QuickTimerKeyEvent.action(keyCode: 76, modifiers: .option, isRepeat: false), .submit(optionPressed: true))
        XCTAssertEqual(QuickTimerKeyEvent.action(keyCode: 53, modifiers: [], isRepeat: false), .escape)
        XCTAssertNil(QuickTimerKeyEvent.action(keyCode: 36, modifiers: [], isRepeat: true))
        XCTAssertNil(QuickTimerKeyEvent.action(keyCode: 49, modifiers: [], isRepeat: false))
    }
}
