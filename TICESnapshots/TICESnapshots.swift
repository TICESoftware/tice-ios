//
//  Copyright © 2019 TICE Software UG (haftungsbeschränkt). All rights reserved.
//  

import XCTest
import TICEAPIModels
import ConvAPI
import PromiseKit

enum TICESnapshotsError: Error {
    case failure
}

func Localized(_ key: String) -> String {
    return LocalizedString(key, bundle: Bundle(for: TICESnapshots.self))
}

class TICESnapshots: XCTestCase {
    
    var cncAPI: CnCAPI!
    var app: XCUIApplication!

    lazy var infoPlist: NSDictionary = {
        let url = Bundle(for: TICESnapshots.self).url(forResource: "Info", withExtension: "plist")!
        return NSDictionary(contentsOf: url)!
    }()

    lazy var cncBaseURL: URL = {
        let address = infoPlist["CNC_SERVER_ADDRESS"] as! String
        return URL(string: address)!
    }()

    lazy var buildNumber: Int = {
        let bundleVersion = infoPlist["CFBundleVersion"] as! String
        return Int(bundleVersion)!
    }()

    override func setUp() {
        
        URLSession.shared.delegateQueue.maxConcurrentOperationCount = -1
        let convAPI = ConvAPI(requester: URLSession.shared)
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .custom({ date, encoder in
            let dateFormatter = ISO8601DateFormatter()
            dateFormatter.formatOptions.insert(.withFractionalSeconds)
            let dateString = dateFormatter.string(from: date)

            var container = encoder.singleValueContainer()
            try container.encode(dateString)
        })
        convAPI.encoder = jsonEncoder
        
        let backend = Backend(api: convAPI, baseURL: cncBaseURL)
        cncAPI = CnC(backend: backend)

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        let serverAddress = infoPlist["SERVER_ADDRESS"] as! String
        let wsServerAddress = infoPlist["WS_SERVER_ADDRESS"] as! String
        
        self.app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["SNAPSHOT", "UITESTING"])
        app.launchArguments.append(contentsOf: ["-SERVER_ADDRESS", serverAddress])
        app.launchArguments.append(contentsOf: ["-WS_SERVER_ADDRESS", wsServerAddress])
        setupSnapshot(app, waitForAnimations: false)
        
        print(app.launchArguments)
        app.launch()
    }
    
    struct Invitation {
        let groupId: GroupId
        let groupKey: String
    }
    
    @discardableResult
    func createGroupFromGroupsScreen(name: String) throws -> Invitation {
        app.buttons["groups_add"].waitAndTap()
        
        let groupNameTextField = app.textFields["createGroup_basic_name"]
        groupNameTextField.waitAndTap()
        groupNameTextField.waitAndTypeText(name)
        
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
                throw TICESnapshotsError.failure
        }

        app.buttons["invite_done"].tap()
        
        let notificationsAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if notificationsAlert.waitForExistence(timeout: 3.0) {
            notificationsAlert.buttons.firstMatch.tap()
        }
        
        app.navigationBars.buttons.element(boundBy: 0).waitAndTap()
        
        return Invitation(groupId: groupId, groupKey: String(encodedGroupKey))
    }
    
    func createUser(name: String?, joining invitation: Invitation) -> Promise<UserId> {
        return firstly {
            cncAPI.createUser()
        }.then { createUserResponse in
            firstly {
                self.cncAPI.changeUserName(userId: createUserResponse.userId, name: name)
            }.then {
                self.cncAPI.joinGroup(userId: createUserResponse.userId, groupId: invitation.groupId, groupKey: invitation.groupKey)
            }.map {
                createUserResponse.userId
            }
        }
    }
    
    func createUsers(names: [String?], joining invitation: Invitation) -> Promise<Void> {
        var promise = Promise<Void>()
        for name in names {
            promise = promise.then {
                self.createUser(name: name, joining: invitation)
            }.asVoid()
        }
        return promise
    }
    
    func joinGroups(userId: UserId, groupInvitations invitations: [Invitation]) -> Promise<Void> {
        let promises = invitations.map { invitation in
            return cncAPI.joinGroup(userId: userId, groupId: invitation.groupId, groupKey: invitation.groupKey)
        }
        
        return when(fulfilled: promises)
    }
    
    enum UIMode {
        case light
        case dark
    }
    
    func activateUIMode(_ app: XCUIApplication, mode: UIMode) {
        let navigationBar = app.navigationBars.firstMatch
        switch mode {
        case .light:
            navigationBar.waitAndTap()
        default:
            navigationBar.waitAndDoubleTap()
        }
    }

    func testSnapshots() throws {
        
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        app.textFields["register_name_placeholder"].waitAndTypeText(Localized("snapshot.user.self"))
        
        snapshot("06Register")

        app.buttons["register_register"].waitAndTap()

        let notificationsAlert = springboard.alerts.firstMatch
        if notificationsAlert.waitForExistence(timeout: 3.0) {
            notificationsAlert.buttons.element(boundBy: 1).tap()
        }

        app.buttons["teams_settings"].waitAndTap()

        activateUIMode(app, mode: .light)

        snapshot("07Settings")

        app.navigationBars.buttons.element(boundBy: 0).waitAndTap()

        app.cells.element(boundBy: 0).waitAndSwipeLeft()
        app.cells.element(boundBy: 0).buttons.element(boundBy: 0).waitAndTap()
        
        let date = [Localized("snapshot.user.4")]
        let business = [Localized("snapshot.user.5"), Localized("snapshot.user.6"), Localized("snapshot.user.7")]
        let sports = [Localized("snapshot.user.8"), Localized("snapshot.user.9"), Localized("snapshot.user.10"), Localized("snapshot.user.11"), Localized("snapshot.user.12")]

        var familyInvitation: Invitation!
        var familyMeetup: GroupId!
        var user1: UserId!
        var user2: UserId!
        var user3: UserId!

        let cncUsersExpectation = self.expectation(description: "Created users and joined groups")
        firstly { () -> Promise<UserId> in
            familyInvitation = try self.createGroupFromGroupsScreen(name: Localized("snapshot.group.1"))
            return self.createUser(name: Localized("snapshot.user.1"), joining: familyInvitation).get { user1 = $0 }
        }.then(on: .main) { userId -> Promise<UserId> in
            return self.createUser(name: Localized("snapshot.user.2"), joining: familyInvitation).get { user2 = $0 }
        }.then(on: .main) { userId -> Promise<UserId> in
            return self.createUser(name: Localized("snapshot.user.3"), joining: familyInvitation).get { user3 = $0 }
        }.then(on: .main) { _ -> Promise<Void> in
            let dateInvitation = try self.createGroupFromGroupsScreen(name: Localized("snapshot.group.2"))
            return self.createUsers(names: date, joining: dateInvitation)
        }.then(on: .main) { () -> Promise<Void> in
            let businessInvitation = try self.createGroupFromGroupsScreen(name: Localized("snapshot.group.3"))
            return self.createUsers(names: business, joining: businessInvitation)
        }.then(on: .main) { () -> Promise<Void> in
            let sportsInvitation = try self.createGroupFromGroupsScreen(name: Localized("snapshot.group.4"))
            return self.createUsers(names: sports, joining: sportsInvitation)
        }.catch {
            XCTFail("\($0)")
        }.finally {
            cncUsersExpectation.fulfill()
        }
        wait(for: [cncUsersExpectation], timeout: 120.0)

        let teamExpectation = self.expectation(description: "Created users and joined groups")
        firstly { () -> Promise<CnCCreateGroupResponse> in
            self.cncAPI.createGroup(userId: user1, type: .meetup, joinMode: .open, permissionMode: .everyone, parent: familyInvitation.groupId, settings: GroupSettings(owner: user1, name: nil)).get { familyMeetup = $0.groupId }
        }.then { createGroupResponse -> Promise<CnCCreateGroupResponse> in
            self.cncAPI.joinGroup(userId: user2, groupId: createGroupResponse.groupId, groupKey: createGroupResponse.groupKey).map { createGroupResponse }
        }.then { createGroupResponse -> Promise<CnCCreateGroupResponse> in
            self.cncAPI.joinGroup(userId: user3, groupId: createGroupResponse.groupId, groupKey: createGroupResponse.groupKey).map { createGroupResponse }
        }.then(on: .main) { createGroupResponse -> Promise<Void> in
            self.app.tables.cells.staticTexts[Localized("snapshot.group.1")].waitAndTap()
            self.app.buttons["group_meetup"].waitAndTap()
            self.app.buttons["meetupSettings_participation_join_join"].waitAndTap()

            let notificationsAlert = springboard.alerts.firstMatch
            if notificationsAlert.waitForExistence(timeout: 3.0) {
                notificationsAlert.buttons.element(boundBy: 0).waitAndTap()
            }

            self.app.navigationBars.buttons.element(boundBy: 0).waitAndTap()
            
            let chatMessage = ChatMessage(groupId: familyInvitation.groupId, text: Localized("snapshot.chat.message.1"), imageData: nil)
            let container = PayloadContainer(payloadType: .chatMessageV1, payload: chatMessage)
            return self.cncAPI.sendMessage(userId: user1, groupId: familyInvitation.groupId, payloadContainer: container)
        }.then { _ -> Promise<Void> in
            return self.cncAPI.updateMeetingPoint(userId: user1, meetupId: familyInvitation.groupId, latitude: 52.515272, longitude: 13.390860)
        }.then { _ -> Promise<Void> in
            let chatMessage = ChatMessage(groupId: familyInvitation.groupId, text: Localized("snapshot.chat.message.2"), imageData: nil)
            let container = PayloadContainer(payloadType: .chatMessageV1, payload: chatMessage)
            return self.cncAPI.sendMessage(userId: user2, groupId: familyInvitation.groupId, payloadContainer: container)
        }.then { _ -> Promise<Void> in
            let location = Location(latitude: 52.517597, longitude: 13.393480, altitude: 0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
            return self.cncAPI.sendLocationUpdate(userId: user1, groupId: familyInvitation.groupId, location: location)
        }.then { _ -> Promise<Void> in
            let location = Location(latitude: 52.513731, longitude: 13.387533, altitude: 0, horizontalAccuracy: 20.0, verticalAccuracy: 5.0, timestamp: Date())
            return self.cncAPI.sendLocationUpdate(userId: user2, groupId: familyInvitation.groupId, location: location)
        }.then { _ -> Promise<Void> in
            let location = Location(latitude: 52.517609, longitude: 13.385662, altitude: 0, horizontalAccuracy: 10.0, verticalAccuracy: 5.0, timestamp: Date())
            return self.cncAPI.sendLocationUpdate(userId: user3, groupId: familyInvitation.groupId, location: location)
        }.asVoid().catch {
            XCTFail("\($0)")
        }.finally {
            teamExpectation.fulfill()
        }
        wait(for: [teamExpectation], timeout: 120.0)

        sleep(1)

        snapshot("02GroupsScreen")

        app.tables.cells.staticTexts[Localized("snapshot.group.1")].waitAndTap()
        
        sleep(1)
        
        snapshot("05TeamScreen")
        
        app.buttons["group_chat"].waitAndTap()
        
        app.waitAndTypeText(Localized("snapshot.chat.message.own") + "\n")
        
        snapshot("03Chat")
        
        app.buttons["close"].waitAndTap()

        app.otherElements[Localized("snapshot.user.2")].firstMatch.waitAndTap()
        
        let meetingPointExpectation = self.expectation(description: "Create meeting point")
        firstly {
            self.cncAPI.updateMeetingPoint(userId: user1, meetupId: familyMeetup, latitude: 52.516541, longitude: 13.388846)
        }.asVoid().catch {
            XCTFail("\($0)")
        }.finally {
            meetingPointExpectation.fulfill()
        }
        wait(for: [meetingPointExpectation], timeout: 10.0)

        snapshot("01TeamScreenWithAnnotation")

        app.buttons["team_info"].waitAndTap()

        snapshot("04TeamInfoScreen")
    }
}
