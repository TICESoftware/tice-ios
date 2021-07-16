//
//  Copyright © 2021 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import PromiseKit
import TICEAPIModels

class TICEUIChatTests: TICEUITestCase {

    func testReceiveChatMessage() throws {
        
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
        
        let chatMessage = "Hello World! Lorem ipsum dolor set amet pro era secura in vitae cerunium. This is a very long text in order to show text truncating works. This should only be visible in the chat window. Let's see!"
        let chatMessageTruncated = String(chatMessage.prefix(20))
        
        let expectation = self.expectation(description: "Completion")
        firstly { () -> Promise<CreateUserResponse> in
            cncAPI.createUser()
        }.then { createUserResponse -> Promise<Void> in
            firstly {
                self.cncAPI.changeUserName(userId: createUserResponse.userId, name: otherName)
            }.then {
                self.cncAPI.joinGroup(userId: createUserResponse.userId, groupId: groupId, groupKey: String(encodedGroupKey))
            }.then { () -> Promise<Void> in
                let payloadContainer = PayloadContainer(payloadType: .chatMessageV1, payload: ChatMessage(groupId: groupId, text: chatMessage, imageData: nil))
                return self.cncAPI.sendMessage(userId: createUserResponse.userId, groupId: groupId, payloadContainer: payloadContainer)
            }
        }.done {
            app.longStaticText(containing: chatMessageTruncated).assertExistence()
            app.longStaticText(containing: chatMessage).assertInexistence()
        }.catch {
            XCTFail(String(describing: $0))
        }.finally {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 60.0)
        
        app.buttons["group_chat"].tap()
        XCTAssertEqual(app.otherElements.matching(identifier: "app.tice.chat.textMessage.bubble").count, 1, "Should have exactly one chat bubble")
        XCTExpectFailure("Chatto chat bubbles can't be queried for text. Would be great to have this:") {
            app.longStaticText(containing: chatMessage).assertExistence()
        }
    }

}
