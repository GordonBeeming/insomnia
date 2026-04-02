// ScheduleRuleTests.swift — InsomniaCoreTests
//
// Tests for ScheduleRule including isActive evaluation for various
// dates, times, weekdays, midnight-crossing windows, and display summary.
// Also tests the Weekday enum's properties and ordering.

import XCTest
@testable import InsomniaCore

/// Tests for ScheduleRule and Weekday types.
final class ScheduleRuleTests: XCTestCase {

    // MARK: - Weekday Tests

    /// Verifies Weekday raw values match Calendar's weekday numbering.
    func testWeekdayRawValues() {
        // Calendar convention: Sunday=1, Saturday=7
        XCTAssertEqual(Weekday.sunday.rawValue, 1)
        XCTAssertEqual(Weekday.monday.rawValue, 2)
        XCTAssertEqual(Weekday.tuesday.rawValue, 3)
        XCTAssertEqual(Weekday.wednesday.rawValue, 4)
        XCTAssertEqual(Weekday.thursday.rawValue, 5)
        XCTAssertEqual(Weekday.friday.rawValue, 6)
        XCTAssertEqual(Weekday.saturday.rawValue, 7)
    }

    /// Verifies Weekday short names are correct.
    func testWeekdayShortNames() {
        // Each day should have a 3-letter abbreviation
        XCTAssertEqual(Weekday.monday.shortName, "Mon")
        XCTAssertEqual(Weekday.friday.shortName, "Fri")
        XCTAssertEqual(Weekday.sunday.shortName, "Sun")
    }

    /// Verifies CaseIterable contains all 7 days.
    func testWeekdayCaseIterable() {
        // Should contain all 7 days of the week
        XCTAssertEqual(Weekday.allCases.count, 7)
    }

    /// Verifies Comparable ordering follows raw values.
    func testWeekdayComparable() {
        // Sunday (1) should be less than Monday (2)
        XCTAssertTrue(Weekday.sunday < Weekday.monday)
        // Saturday (7) should be greater than Friday (6)
        XCTAssertTrue(Weekday.saturday > Weekday.friday)
    }

    // MARK: - Schedule Rule: Basic isActive

    /// Tests that a rule is active during its configured window.
    func testIsActiveDuringWindow() {
        // Create a rule for weekdays 09:00-17:00
        let rule = makeRule(
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            startHour: 9, startMinute: 0,
            endHour: 17, endMinute: 0
        )
        // Create a date on a Monday at 12:00 (noon)
        let mondayNoon = makeDate(weekday: 2, hour: 12, minute: 0)
        // Should be active during business hours on a weekday
        XCTAssertTrue(rule.isActive(at: mondayNoon))
    }

    /// Tests that a rule is inactive outside its configured window.
    func testIsInactiveOutsideWindow() {
        // Create a rule for weekdays 09:00-17:00
        let rule = makeRule(
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            startHour: 9, startMinute: 0,
            endHour: 17, endMinute: 0
        )
        // Create a date on a Monday at 20:00 (after hours)
        let mondayEvening = makeDate(weekday: 2, hour: 20, minute: 0)
        // Should not be active outside business hours
        XCTAssertFalse(rule.isActive(at: mondayEvening))
    }

    /// Tests that a rule is inactive on non-matching weekdays.
    func testIsInactiveOnWrongWeekday() {
        // Create a rule for weekdays only (Mon-Fri)
        let rule = makeRule(
            weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            startHour: 9, startMinute: 0,
            endHour: 17, endMinute: 0
        )
        // Create a date on a Saturday at noon
        let saturdayNoon = makeDate(weekday: 7, hour: 12, minute: 0)
        // Should not be active on weekends
        XCTAssertFalse(rule.isActive(at: saturdayNoon))
    }

    // MARK: - Disabled Rules

    /// Tests that a disabled rule is never active.
    func testDisabledRuleIsNeverActive() {
        // Create a disabled rule
        var rule = makeRule(
            weekdays: Set(Weekday.allCases),
            startHour: 0, startMinute: 0,
            endHour: 23, endMinute: 59
        )
        rule.isEnabled = false
        // Should be inactive even when all conditions match
        let mondayNoon = makeDate(weekday: 2, hour: 12, minute: 0)
        XCTAssertFalse(rule.isActive(at: mondayNoon))
    }

    // MARK: - Edge Cases

    /// Tests that the rule is active at exactly the start time.
    func testActiveAtExactStartTime() {
        // Rule starts at 09:00
        let rule = makeRule(
            weekdays: [.monday],
            startHour: 9, startMinute: 0,
            endHour: 17, endMinute: 0
        )
        // Check at exactly 09:00 on Monday
        let mondayNineAM = makeDate(weekday: 2, hour: 9, minute: 0)
        // Start time is inclusive
        XCTAssertTrue(rule.isActive(at: mondayNineAM))
    }

    /// Tests that the rule is inactive at exactly the end time.
    func testInactiveAtExactEndTime() {
        // Rule ends at 17:00
        let rule = makeRule(
            weekdays: [.monday],
            startHour: 9, startMinute: 0,
            endHour: 17, endMinute: 0
        )
        // Check at exactly 17:00 on Monday
        let mondayFivePM = makeDate(weekday: 2, hour: 17, minute: 0)
        // End time is exclusive
        XCTAssertFalse(rule.isActive(at: mondayFivePM))
    }

    // MARK: - Midnight Crossing

    /// Tests a rule window that crosses midnight (e.g., 22:00-06:00).
    func testMidnightCrossingActiveBeforeMidnight() {
        // Rule active from 22:00 to 06:00 on Fridays
        let rule = makeRule(
            weekdays: [.friday],
            startHour: 22, startMinute: 0,
            endHour: 6, endMinute: 0
        )
        // Friday at 23:00 — should be active (after start, before midnight)
        let fridayLateNight = makeDate(weekday: 6, hour: 23, minute: 0)
        XCTAssertTrue(rule.isActive(at: fridayLateNight))
    }

    /// Tests that a midnight-crossing rule is active after midnight on the next day.
    func testMidnightCrossingActiveAfterMidnight() {
        // Rule active from 22:00 to 06:00 on Fridays
        let rule = makeRule(
            weekdays: [.friday],
            startHour: 22, startMinute: 0,
            endHour: 6, endMinute: 0
        )
        // Saturday at 03:00 — should be active (the "next day" part of Friday's rule)
        let saturdayEarlyMorning = makeDate(weekday: 7, hour: 3, minute: 0)
        // For this to work, the rule checks if "yesterday" (Friday) is in the weekdays set
        XCTAssertTrue(rule.isActive(at: saturdayEarlyMorning))
    }

    /// Tests that a midnight-crossing rule is inactive outside both portions.
    func testMidnightCrossingInactiveDuringDay() {
        // Rule active from 22:00 to 06:00 on Fridays
        let rule = makeRule(
            weekdays: [.friday],
            startHour: 22, startMinute: 0,
            endHour: 6, endMinute: 0
        )
        // Friday at noon — should be inactive (outside both portions)
        let fridayNoon = makeDate(weekday: 6, hour: 12, minute: 0)
        XCTAssertFalse(rule.isActive(at: fridayNoon))
    }

    // MARK: - Display Summary

    /// Tests the displaySummary format.
    func testDisplaySummary() {
        // Create a rule for Mon, Wed, Fri 09:00-17:00
        let rule = makeRule(
            weekdays: [.monday, .wednesday, .friday],
            startHour: 9, startMinute: 0,
            endHour: 17, endMinute: 0
        )
        let summary = rule.displaySummary
        // Should contain the day names
        XCTAssertTrue(summary.contains("Mon"))
        XCTAssertTrue(summary.contains("Wed"))
        XCTAssertTrue(summary.contains("Fri"))
        // Should contain the time range
        XCTAssertTrue(summary.contains("09:00"))
        XCTAssertTrue(summary.contains("17:00"))
    }

    // MARK: - Codable

    /// Tests that ScheduleRule round-trips through JSON encoding/decoding.
    func testCodableRoundTrip() throws {
        // Create a rule with all fields populated
        let rule = makeRule(
            weekdays: [.monday, .friday],
            startHour: 8, startMinute: 30,
            endHour: 16, endMinute: 45
        )
        // Encode to JSON
        let encoder = JSONEncoder()
        let data = try encoder.encode(rule)
        // Decode from JSON
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ScheduleRule.self, from: data)
        // Verify all fields match
        XCTAssertEqual(decoded.id, rule.id)
        XCTAssertEqual(decoded.weekdays, rule.weekdays)
        XCTAssertEqual(decoded.startTime.hour, rule.startTime.hour)
        XCTAssertEqual(decoded.startTime.minute, rule.startTime.minute)
        XCTAssertEqual(decoded.endTime.hour, rule.endTime.hour)
        XCTAssertEqual(decoded.endTime.minute, rule.endTime.minute)
        XCTAssertEqual(decoded.isEnabled, rule.isEnabled)
        XCTAssertEqual(decoded.assertionType, rule.assertionType)
    }

    // MARK: - Helpers

    /// Creates a ScheduleRule with the given parameters for testing.
    ///
    /// - Parameters:
    ///   - weekdays: The set of active weekdays.
    ///   - startHour: The start hour (0-23).
    ///   - startMinute: The start minute (0-59).
    ///   - endHour: The end hour (0-23).
    ///   - endMinute: The end minute (0-59).
    /// - Returns: A configured ScheduleRule for testing.
    private func makeRule(
        weekdays: Set<Weekday>,
        startHour: Int, startMinute: Int,
        endHour: Int, endMinute: Int
    ) -> ScheduleRule {
        // Build DateComponents for start and end times
        var start = DateComponents()
        start.hour = startHour
        start.minute = startMinute
        var end = DateComponents()
        end.hour = endHour
        end.minute = endMinute
        // Return a rule with the configured times
        return ScheduleRule(
            weekdays: weekdays,
            startTime: start,
            endTime: end
        )
    }

    /// Creates a Date for a specific weekday and time in the current week.
    ///
    /// Uses Calendar to find the next occurrence of the specified weekday
    /// and sets the time to the given hour and minute.
    ///
    /// - Parameters:
    ///   - weekday: The Calendar weekday number (1=Sunday, 7=Saturday).
    ///   - hour: The hour (0-23).
    ///   - minute: The minute (0-59).
    /// - Returns: A Date representing the specified weekday and time.
    private func makeDate(weekday: Int, hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        // Start from a known date and find the next occurrence of the target weekday
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        components.second = 0
        // Create the date from the components
        return calendar.date(from: components) ?? Date()
    }
}
