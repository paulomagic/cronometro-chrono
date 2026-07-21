import XCTest
@testable import ChronoHUD

final class QuickTimerParserTests: XCTestCase {
    func testAcceptedInputs() throws {
        let cases: [(String, TimeInterval)] = [
            ("25", 1_500), ("25m", 1_500), ("90s", 90), ("1h", 3_600),
            ("1h30", 5_400), ("1h30m", 5_400), ("1h 30m", 5_400),
            ("1h    30m", 5_400), ("  \n1H 30M\n", 5_400), ("00025", 1_500),
            ("1h0", 3_600), ("1h00m", 3_600), ("1h 00m", 3_600),
            ("24h", 86_400), ("24h0m", 86_400), ("1440m", 86_400), ("86400s", 86_400)
        ]
        for (input, expected) in cases {
            XCTAssertEqual(try QuickTimerParser.parse(input), expected, input)
        }
    }

    func testInvalidFormats() {
        let values = [
            "25 m", "1 h", "1h 30", "0h30m", "0h 30m", "1h60m", "+25", "-1m",
            "1.5h", "12:30", "tomorrow", "1hm", "1h30mm", "1h\t30m", "２５m", "١h"
        ]
        for value in values { assertError(.invalidFormat, value) }
    }

    func testEmptyAndOutOfRangeInputs() {
        for value in ["", "  \n\t"] { assertError(.empty, value) }
        for value in ["0", "0m", "0s", "24h1m", "1441m", "86401s", String(repeating: "9", count: 40)] {
            assertError(.outOfRange, value)
        }
    }

    private func assertError(_ expected: QuickTimerParseError, _ input: String) {
        XCTAssertThrowsError(try QuickTimerParser.parse(input), input) { error in
            XCTAssertEqual(error as? QuickTimerParseError, expected, input)
        }
    }
}
