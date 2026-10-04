import XCTest
@testable import SpamHoleCore

final class NormalizationTests: XCTestCase {
    func testNormalizesExactNANPNumbers() throws {
        XCTAssertEqual(try PhoneNormalizer.callNumber("(202) 555-0100"), "+12025550100")
        XCTAssertEqual(try PhoneNormalizer.callNumber("1 416 555 0100", defaultRegion: .canada), "+14165550100")
        XCTAssertEqual(try PhoneNormalizer.callDirectoryNumber("+1 (202) 555-0100"), 12025550100)
        XCTAssertEqual(try PhoneNormalizer.callNumber("+44 20 7946 0018"), "+442079460018")
    }
    func testRejectsEmergencyPrefixesRangesExtensionsAndUnsupportedMetadata() {
        for value in ["911", "112", "+1202", "2025550100*", "2025550100/99", "2025550100-2025550199", "2025550100 x2", "1115550100", "2021110100", "++12025550100", "20255501000000", "２０２５５５０１００"] {
            XCTAssertThrowsError(try PhoneNormalizer.callNumber(value), value)
        }
        XCTAssertThrowsError(try PhoneNormalizer.callNumber("+999123456789"))
        XCTAssertThrowsError(try PhoneNormalizer.callNumber("+44 020 7946 0018"))
    }
    func testCallNumbersRejectTextOnlyIdentifiers() {
        for value in ["12345", "123456", "BANKALERT", "bank@example.com"] {
            XCTAssertThrowsError(try PhoneNormalizer.callNumber(value), value)
            XCTAssertThrowsError(try PhoneNormalizer.callDirectoryNumber(value), value)
        }
    }
}
