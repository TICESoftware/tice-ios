//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import PromiseKit
import TICEAPIModels

class TICEUIDemoTests: TICEUITestCase {
    
    func testDemo() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        app.textFields["register_name_placeholder"].waitAndTypeText("Dirk")
        app.buttons["register_register"].waitAndTap()
        
        let notificationsAlert = springboard.alerts.firstMatch
        if notificationsAlert.waitForExistence(timeout: 3.0) {
            notificationsAlert.buttons["Allow"].tap()
        }
        
        app.staticTexts[L10n.Demo.Team.name].waitAndTap()
        
        app.longStaticText(containing: L10n.Demo.Message.opened).assertExistence()
        
        app.buttons["group_chat"].waitAndTap()
        
        app.buttons["close"].waitAndTap()
        
        app.longStaticText(containing: L10n.Demo.Message.chatClosed).assertExistence()
        
        app.buttons["group_meetup"].waitAndTap()
        
        app.alerts.firstMatch.buttons.element(boundBy: 1).waitAndTap()
        
        app.longStaticText(containing: L10n.Demo.Message.locationSharingStarted).assertExistence()
        
        app.maps.element.press(forDuration: 1.0)
        
        app.longStaticText(containing: L10n.Demo.Message.locationMarked).assertExistence()
        
        app.buttons[L10n.LocationAnnotationDetail.createMeetingPoint].waitAndTap()
        
        app.longStaticText(containing: L10n.Demo.Message.meetingPointCreated).assertExistence()
        
        app.otherElements[L10n.Demo.Team.Member.One.name].waitAndTap()
        
        app.longStaticText(containing: L10n.Demo.Message.userSelected).assertExistence()
        
        app.buttons["group_meetup"].waitAndTap()
        
        app.longStaticText(containing: L10n.Demo.Message.locationSharingEnded).assertExistence()
        
        app.buttons["team_info"].waitAndTap()
        
        app.staticTexts[L10n.Demo.Manage.endDemo].waitAndTap()
        
        app.buttons["groups_add"].assertExistence()
    }
}
