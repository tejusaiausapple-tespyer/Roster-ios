import XCTest
@testable import Rosterra

final class TFNTests: XCTestCase {
    func testNormalizeAndFormat() {
        XCTAssertEqual(TFN.normalize("648 188 527"), "648188527")
        XCTAssertEqual(TFN.format("648188527"), "648 188 527")
    }

    func testValidChecksum() {
        XCTAssertTrue(TFN.isValid("648188527"))
        XCTAssertFalse(TFN.isValid("123456789"))
        XCTAssertFalse(TFN.isValid("111111111"))
    }

    func testMaskAndLast4() {
        XCTAssertEqual(TFN.mask("648188527"), "*** *** 527")
        XCTAssertEqual(TFN.last4("648188527"), "8527")
    }

    func testValidationAllowsEmpty() {
        XCTAssertNil(TFN.validationError(""))
        XCTAssertEqual(TFN.validationError("123"), "TFN must be 9 digits")
    }
}
