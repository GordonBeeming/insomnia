// AppVersionTests.swift — InsomniaCoreTests
//
// Tests for AppVersion parsing and comparison, covering GitHub release
// tag formats, bundle version formats, edge cases, and ordering.

import XCTest
@testable import InsomniaCore

/// Tests for the AppVersion model.
final class AppVersionTests: XCTestCase {

    // MARK: - Parsing

    /// Tests parsing a GitHub release tag with "v" prefix.
    func testParseTagWithPrefix() {
        let version = AppVersion(string: "v0.6")
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 0)
        XCTAssertEqual(version?.minor, 6)
    }

    /// Tests parsing a version string without "v" prefix.
    func testParseWithoutPrefix() {
        let version = AppVersion(string: "0.5")
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 0)
        XCTAssertEqual(version?.minor, 5)
    }

    /// Tests parsing a bundle version with build number (third component ignored).
    func testParseBundleVersion() {
        let version = AppVersion(string: "0.5.42")
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 0)
        XCTAssertEqual(version?.minor, 5)
    }

    /// Tests parsing a tagged bundle version with "v" prefix and build number.
    func testParseTaggedBundleVersion() {
        let version = AppVersion(string: "v1.2.100")
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 1)
        XCTAssertEqual(version?.minor, 2)
    }

    /// Tests parsing a higher major version.
    func testParseHigherMajor() {
        let version = AppVersion(string: "v2.0")
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 2)
        XCTAssertEqual(version?.minor, 0)
    }

    // MARK: - Invalid Input

    /// Tests that empty string returns nil.
    func testParseEmptyString() {
        XCTAssertNil(AppVersion(string: ""))
    }

    /// Tests that a single number returns nil (needs at least major.minor).
    func testParseSingleNumber() {
        XCTAssertNil(AppVersion(string: "5"))
    }

    /// Tests that garbage input returns nil.
    func testParseGarbage() {
        XCTAssertNil(AppVersion(string: "not-a-version"))
    }

    /// Tests that "v" alone returns nil.
    func testParsePrefixOnly() {
        XCTAssertNil(AppVersion(string: "v"))
    }

    /// Tests that non-numeric components return nil.
    func testParseNonNumeric() {
        XCTAssertNil(AppVersion(string: "v1.abc"))
    }

    // MARK: - Comparison

    /// Tests that a higher minor version is greater.
    func testHigherMinorIsGreater() {
        let v05 = AppVersion(string: "0.5")!
        let v06 = AppVersion(string: "0.6")!
        XCTAssertTrue(v06 > v05)
        XCTAssertFalse(v05 > v06)
    }

    /// Tests that a higher major version is greater regardless of minor.
    func testHigherMajorIsGreater() {
        let v099 = AppVersion(string: "0.99")!
        let v10 = AppVersion(string: "1.0")!
        XCTAssertTrue(v10 > v099)
    }

    /// Tests that equal versions are equal.
    func testEqualVersions() {
        let a = AppVersion(string: "0.5")!
        let b = AppVersion(string: "v0.5")!
        XCTAssertEqual(a, b)
        XCTAssertFalse(a < b)
        XCTAssertFalse(a > b)
    }

    /// Tests that bundle version and tag version with same major.minor are equal.
    func testBundleVersionEqualsTag() {
        let bundle = AppVersion(string: "0.5.42")!
        let tag = AppVersion(string: "v0.5")!
        XCTAssertEqual(bundle, tag)
    }

    // MARK: - Description

    /// Tests the string description format.
    func testDescription() {
        let version = AppVersion(string: "v0.6")!
        XCTAssertEqual(version.description, "0.6")
    }

    /// Tests description for higher versions.
    func testDescriptionHigherVersion() {
        let version = AppVersion(string: "12.34.56")!
        XCTAssertEqual(version.description, "12.34")
    }
}
