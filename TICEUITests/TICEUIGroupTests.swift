//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import PromiseKit
import TICEAPIModels

class TICEUIGroupTests: TICEUITestCase {
    
    func testOtherUserJoinsGroup() throws {
        
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        let ourName = "Dirk"
        let otherName = "Bot"
        
        app.textFields["register_name_placeholder"].waitAndTypeText(ourName)
        
        app.buttons["register_register"].waitAndTap()
        
        let notificationsAlert = springboard.alerts.firstMatch
        if notificationsAlert.waitForExistence(timeout: 3.0) {
            notificationsAlert.buttons["Allow"].tap()
        }
        
        app.buttons["groups_add"].waitAndTap()
        
        app.switches["createGroup_startLocationSharing"].waitAndTap()
        
        app.buttons["createGroup_done"].waitAndTap()
        
        app.otherElements["ActivityListView"].buttons.element(boundBy: 0).waitAndTap()
        let inviteLabel = app.staticTexts["invite_body"].wait()
        
        let invitationText = inviteLabel.label
        guard let groupURL = invitationText.split(separator: " ").last,
              let groupIdString = groupURL.split(separator: "#").first?.split(separator: "/").last,
              let groupId = GroupId(uuidString: String(groupIdString)),
              let encodedGroupKey = groupURL.split(separator: "#").last else {
            XCTFail("Could not get group key")
            return
        }
        
        app.buttons["invite_done"].tap()
        
        let locationAlert = springboard.alerts.firstMatch
        if locationAlert.waitForExistence(timeout: 3.0) {
            locationAlert.buttons["Allow Once"].tap()
        }
        
        app.buttons["team_info"].waitAndTap()
        
        let expectation = self.expectation(description: "Completion")
        firstly { () -> Promise<CreateUserResponse> in
            cncAPI.createUser()
        }.then { createUserResponse -> Promise<Void> in
            firstly {
                self.cncAPI.changeUserName(userId: createUserResponse.userId, name: otherName)
            }.then {
                self.cncAPI.joinGroup(userId: createUserResponse.userId, groupId: groupId, groupKey: String(encodedGroupKey))
            }.then {
                self.cncAPI.sendLocationUpdate(userId: createUserResponse.userId, groupId: groupId, location: Location(latitude: 52.0, longitude: 13.0))
            }
        }.done {
            app.tables.staticTexts[ourName].assertExistence(timeout: 10)
            app.tables.staticTexts[otherName].assertExistence(timeout: 10)
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 60.0)
    }
    
    func testUserDeletesGroup() throws {
        
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        app.textFields["register_name_placeholder"].waitAndTypeText("Dirk")
        
        app.buttons["register_register"].waitAndTap()
        
        let notificationsAlert = springboard.alerts.firstMatch
        if notificationsAlert.waitForExistence(timeout: 3.0) {
            notificationsAlert.buttons["Allow"].tap()
        }
        
        app.buttons["groups_add"].waitAndTap()
        
        let groupNameTextField = app.textFields["createGroup_basic_name"]
        groupNameTextField.waitAndTap()
        groupNameTextField.waitAndTypeText("Test Group")
        
        app.switches["createGroup_startLocationSharing"].waitAndTap()
        
        app.buttons["createGroup_done"].waitAndTap()
        
        app.otherElements["ActivityListView"].buttons.element(boundBy: 0).waitAndTap()
        
        app.buttons["invite_done"].tap()
        
        let locationAlert = springboard.alerts.firstMatch
        if locationAlert.waitForExistence(timeout: 3.0) {
            locationAlert.buttons["Allow Once"].tap()
        }
        
        app.buttons["team_info"].waitAndTap()
        
        app.staticTexts[Localized("groupSettings_participation_delete")].waitAndTap()
        
        app.buttons[Localized("groupSettings_participation_confirmDeletion_delete")].waitAndTap()
        
        app.staticTexts["Test Group"].assertInexistence()
    }
    
    func testJoiningGroup() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        let ourName = "Dirk"
        let otherName = "Bot"
        
        app.textFields["register_name_placeholder"].waitAndTypeText(ourName)
        
        app.buttons["register_register"].waitAndTap()
        
        let notificationsAlert = springboard.alerts.firstMatch
        if notificationsAlert.waitForExistence(timeout: 3.0) {
            notificationsAlert.buttons["Allow"].tap()
        }
        
        let expectation = self.expectation(description: "Completion")
        firstly { () -> Promise<CreateUserResponse> in
            cncAPI.createUser()
        }.then { createUserResponse -> Promise<Void> in
            return firstly { () -> Promise<Void> in
                self.cncAPI.changeUserName(userId: createUserResponse.userId, name: otherName)
            }.then { _ -> Promise<CnCCreateGroupResponse> in
                self.cncAPI.createGroup(userId: createUserResponse.userId, type: .team, joinMode: .open, permissionMode: .everyone, parent: nil, settings: GroupSettings(owner: createUserResponse.userId, name: "Test Group"))
            }.done { response in
                openURLViaSpotlight("https://develop.tice.app/group/\(response.groupId.uuidString)#\(response.groupKey)", returnToApp: app)
            }
        }.done {
            app.staticTexts["Test Group"].assertExistence()
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 60.0)
        
        app.staticTexts[Localized("joinGroup_participation_join")].waitAndTap()
        
        app.staticTexts["Test Group"].waitAndTap()
        
        app.buttons["team_info"].waitAndTap()
        
        app.staticTexts[Localized("groupSettings_participation_leave")].waitAndTap()
        
        app.buttons[Localized("groupSettings_participation_confirmLeave_leave")].waitAndTap()
        
        app.staticTexts["Test Group"].assertInexistence()
    }
}
