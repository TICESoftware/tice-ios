//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import ConvAPI
import PromiseKit
import TICEAPIModels

class TICEUIAppTests: TICEUITestCase {

    func testLaunchPerformance() throws {
        measure(metrics: [XCTOSSignpostMetric.applicationLaunch]) {
            XCUIApplication().launch()
        }
    }

}
