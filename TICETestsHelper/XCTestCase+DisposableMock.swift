//
//  Copyright © 2020 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import Foundation
import XCTest
import Cuckoo

extension XCTestCase {
    func mock<T: Mock>(_ initializer: () -> T) -> T {
        let mock = initializer()
        addTeardownBlock { clearInvocations(mock) }
        return mock
    }
}
