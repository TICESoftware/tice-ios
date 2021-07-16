//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest

@testable import TICE

class LocalizationTests: XCTestCase {

    func testListLocalization() throws {
        XCTAssertEqual(LocalizedList([]), "")
        XCTAssertEqual(LocalizedList(["Anna"]), "Anna")
        XCTAssertEqual(LocalizedList(["Anna", "Bert"]), "Anna and Bert")
        XCTAssertEqual(LocalizedList(["Anna", "Bert", "Charlie"]), "Anna, Bert, and Charlie")
        XCTAssertEqual(LocalizedList(["Anna", "Bert", "Charlie", "David"]), "Anna, Bert, Charlie, and David")
    }

}
