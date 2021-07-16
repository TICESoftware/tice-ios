//
//  Copyright © 2018 TICE Software UG (haftungsbeschränkt). All rights reserved.
//

import XCTest
import ConvAPI
import PromiseKit
import TICEAPIModels

class TICEUIAccountTests: TICEUITestCase {
    
    func testDeleteAccount() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        app.textFields["register_name_placeholder"].waitAndTypeText("Dirk")
        
        app.buttons["register_register"].waitAndTap()
        
        let notificationsAlert = springboard.alerts.firstMatch
        if notificationsAlert.waitForExistence(timeout: 3.0) {
            notificationsAlert.buttons["Allow"].tap()
        }
        
        app.buttons["teams_settings"].waitAndTap()
        
        app.cells["settings_account_delete"].waitAndTap()
        
        let alert = app.alerts.firstMatch
        alert.buttons.element(boundBy: 1).waitAndTap()
        
        app.staticTexts["register_welcome"].assertExistence(timeout: 1.0)
    }
}
