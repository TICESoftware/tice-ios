//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest

extension XCTestCase {
    func XCTAssertThrowsSpecificError<E: Error & Equatable>(_ expression: @autoclosure () throws -> Void, _ expectedError: E, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try expression(), message(), file: file, line: line) { error in
            guard error as? E == expectedError else {
                XCTFail("Unexpected error: \(error). Expected: \(expectedError)")
                return
            }
        }
    }
}
