//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest

let defaultExpectationTimeout: TimeInterval = 3.0

extension XCTestCase {
    func wait(for expectations: [XCTestExpectation]) {
        wait(for: expectations, timeout: defaultExpectationTimeout)
    }
}
