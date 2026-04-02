// DurationOptionTests.swift — InsomniaCoreTests
//
// Tests for DurationOption including parsing all supported formats,
// invalid input handling, timeInterval values, and displayLabel output.

import XCTest
@testable import InsomniaCore

/// Tests for the DurationOption enum and its parse method.
final class DurationOptionTests: XCTestCase {

    // MARK: - Time Interval Values

    /// Verifies that preset durations return the correct time intervals.
    func testPresetTimeIntervals() {
        // 15 minutes = 900 seconds
        XCTAssertEqual(DurationOption.fifteenMinutes.timeInterval, 900)
        // 30 minutes = 1800 seconds
        XCTAssertEqual(DurationOption.thirtyMinutes.timeInterval, 1_800)
        // 1 hour = 3600 seconds
        XCTAssertEqual(DurationOption.oneHour.timeInterval, 3_600)
        // 2 hours = 7200 seconds
        XCTAssertEqual(DurationOption.twoHours.timeInterval, 7_200)
    }

    /// Verifies custom duration returns the specified interval.
    func testCustomTimeInterval() {
        // Custom 45 minutes = 2700 seconds
        let custom = DurationOption.custom(2_700)
        XCTAssertEqual(custom.timeInterval, 2_700)
    }

    // MARK: - Display Labels

    /// Verifies preset durations produce the correct display labels.
    func testPresetDisplayLabels() {
        // Check each preset label is human-readable
        XCTAssertEqual(DurationOption.fifteenMinutes.displayLabel, "15 minutes")
        XCTAssertEqual(DurationOption.thirtyMinutes.displayLabel, "30 minutes")
        XCTAssertEqual(DurationOption.oneHour.displayLabel, "1 hour")
        XCTAssertEqual(DurationOption.twoHours.displayLabel, "2 hours")
    }

    /// Verifies custom durations produce formatted display labels.
    func testCustomDisplayLabel() {
        // 90 minutes should display as "1 hour 30 minutes"
        let ninetyMinutes = DurationOption.custom(5_400)
        XCTAssertEqual(ninetyMinutes.displayLabel, "1 hour 30 minutes")
        // 45 seconds should display as "45 seconds"
        let fortyFiveSeconds = DurationOption.custom(45)
        XCTAssertEqual(fortyFiveSeconds.displayLabel, "45 seconds")
    }

    // MARK: - Presets

    /// Verifies the presets array contains all four standard options.
    func testPresetsArray() {
        // Should contain exactly 4 preset durations
        XCTAssertEqual(DurationOption.presets.count, 4)
        XCTAssertEqual(DurationOption.presets[0], .fifteenMinutes)
        XCTAssertEqual(DurationOption.presets[1], .thirtyMinutes)
        XCTAssertEqual(DurationOption.presets[2], .oneHour)
        XCTAssertEqual(DurationOption.presets[3], .twoHours)
    }

    // MARK: - Parsing: Minutes

    /// Tests parsing minute-based duration strings.
    func testParseMinutes() throws {
        // "15m" should map to the fifteenMinutes preset
        let fifteen = try DurationOption.parse("15m")
        XCTAssertEqual(fifteen, .fifteenMinutes)
        // "30m" should map to thirtyMinutes preset
        let thirty = try DurationOption.parse("30m")
        XCTAssertEqual(thirty, .thirtyMinutes)
        // "45m" should be custom(2700)
        let fortyFive = try DurationOption.parse("45m")
        XCTAssertEqual(fortyFive, .custom(2_700))
    }

    // MARK: - Parsing: Hours

    /// Tests parsing hour-based duration strings.
    func testParseHours() throws {
        // "1h" should map to the oneHour preset
        let one = try DurationOption.parse("1h")
        XCTAssertEqual(one, .oneHour)
        // "2h" should map to twoHours preset
        let two = try DurationOption.parse("2h")
        XCTAssertEqual(two, .twoHours)
        // "3h" should be custom
        let three = try DurationOption.parse("3h")
        XCTAssertEqual(three, .custom(10_800))
    }

    // MARK: - Parsing: Seconds

    /// Tests parsing second-based duration strings.
    func testParseSeconds() throws {
        // "90s" should be custom(90)
        let ninety = try DurationOption.parse("90s")
        XCTAssertEqual(ninety, .custom(90))
        // "3600s" maps to 1 hour = preset
        let hourInSeconds = try DurationOption.parse("3600s")
        XCTAssertEqual(hourInSeconds, .oneHour)
    }

    // MARK: - Parsing: Combined

    /// Tests parsing combined duration strings like "1h30m".
    func testParseCombined() throws {
        // "1h30m" = 5400 seconds (custom)
        let combined = try DurationOption.parse("1h30m")
        XCTAssertEqual(combined, .custom(5_400))
        // "1h30m45s" = 5445 seconds
        let full = try DurationOption.parse("1h30m45s")
        XCTAssertEqual(full, .custom(5_445))
        // "2h0m" should equal the 2h preset (7200)
        let twoHoursZero = try DurationOption.parse("2h0m")
        XCTAssertEqual(twoHoursZero, .twoHours)
    }

    // MARK: - Parsing: Case Insensitivity

    /// Tests that parsing handles uppercase input.
    func testParseCaseInsensitive() throws {
        // Uppercase should work — parser lowercases input
        let result = try DurationOption.parse("1H30M")
        XCTAssertEqual(result, .custom(5_400))
    }

    // MARK: - Parsing: Whitespace

    /// Tests that parsing handles leading/trailing whitespace.
    func testParseWithWhitespace() throws {
        // Whitespace should be trimmed
        let result = try DurationOption.parse("  15m  ")
        XCTAssertEqual(result, .fifteenMinutes)
    }

    // MARK: - Parsing: Invalid Input

    /// Tests that empty input throws emptyInput error.
    func testParseEmptyInput() {
        // Empty string should throw
        XCTAssertThrowsError(try DurationOption.parse("")) { error in
            guard let parseError = error as? DurationOption.ParseError else {
                XCTFail("Expected ParseError")
                return
            }
            XCTAssertEqual(parseError, .emptyInput)
        }
    }

    /// Tests that whitespace-only input throws emptyInput error.
    func testParseWhitespaceOnly() {
        // Whitespace-only should throw emptyInput after trimming
        XCTAssertThrowsError(try DurationOption.parse("   ")) { error in
            guard let parseError = error as? DurationOption.ParseError else {
                XCTFail("Expected ParseError")
                return
            }
            XCTAssertEqual(parseError, .emptyInput)
        }
    }

    /// Tests that garbage input throws invalidFormat error.
    func testParseInvalidFormat() {
        // Non-duration strings should throw
        XCTAssertThrowsError(try DurationOption.parse("hello")) { error in
            guard let parseError = error as? DurationOption.ParseError else {
                XCTFail("Expected ParseError")
                return
            }
            if case .invalidFormat = parseError {
                // Expected
            } else {
                XCTFail("Expected invalidFormat error, got \(parseError)")
            }
        }
    }

    /// Tests that zero duration throws nonPositiveDuration error.
    func testParseZeroDuration() {
        // "0m" should throw nonPositiveDuration
        XCTAssertThrowsError(try DurationOption.parse("0m")) { error in
            guard let parseError = error as? DurationOption.ParseError else {
                XCTFail("Expected ParseError")
                return
            }
            XCTAssertEqual(parseError, .nonPositiveDuration)
        }
    }

    // MARK: - Equatable

    /// Tests equatable conformance for preset and custom durations.
    func testEquatable() {
        // Same presets should be equal
        XCTAssertEqual(DurationOption.fifteenMinutes, .fifteenMinutes)
        // Different presets should not be equal
        XCTAssertNotEqual(DurationOption.fifteenMinutes, .thirtyMinutes)
        // Custom with same value should be equal
        XCTAssertEqual(DurationOption.custom(100), .custom(100))
        // Custom with different values should not be equal
        XCTAssertNotEqual(DurationOption.custom(100), .custom(200))
    }
}
